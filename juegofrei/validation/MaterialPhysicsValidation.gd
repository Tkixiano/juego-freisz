extends RefCounted
const Fixture = preload("res://scripts/material_physics/MaterialPhysicsFixtures.gd")
var tree: SceneTree
var lab: Node
var p: CharacterBody2D
var q: CharacterBody2D
var manager: Node
var adapter: Node
var contact: Node
var input_driver: Node
var rows: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var incoherent_commits: int = 0
func observe_commit(_sequence: int,status: String,_reason: String) -> void:
	if status!="APPLIED": return
	var expected: Array = []
	for c: Dictionary in adapter.logical_active.values():
		for region: Dictionary in c.material_regions:
			expected.append(StringName(region.region_id))
			var body: Node = manager.get_body(StringName(region.region_id))
			if body==null or body.material_kind!=region.material: incoherent_commits += 1
	var actual: Array = manager.object_ids()
	expected.sort();actual.sort()
	if expected!=actual: incoherent_commits += 1

func frames(n: int) -> void:
	for i: int in range(n): await tree.physics_frame
func check(name: String,passed: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":passed,"detail":detail})
	if not passed: push_error("MATERIAL_PHYSICS "+name+" "+str(detail))
func action(name: String,pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new();event.action = name;event.pressed = pressed
	input_driver.events.append(event)
func release() -> void:
	input_driver.events.clear()
	for a: StringName in InputMap.get_actions():
		if String(a).begins_with("p1_") or String(a).begins_with("p2_"): Input.action_release(a)
func place(player: CharacterBody2D,pos: Vector2,velocity: Vector2=Vector2.ZERO) -> void:
	player.position = pos;player.velocity = velocity;player.reset_physics_interpolation();player.force_update_transform()
	player.combat.reset_after_respawn();player.combat.respawn_left = 0;player.combat.invulnerability_left = 0
	player.drop_left = 0;player.buffer_left = 0;player.coyote_left = 0
func reset(structures: Array) -> void:
	release();lab.moving = false
	place(p,Vector2(60,-400));place(q,Vector2(1100,-400));q.collision_mask = 0;q.set_physics_process(false)
	for fighter: Node in [p,q]:
		for body: PhysicsBody2D in fighter.get_collision_exceptions(): fighter.remove_collision_exception_with(body)
		fighter.get_node("MaterialContact").ignored.clear();fighter.get_node("MaterialContact").latches.clear()
	contact.bounce_impulse = 760;contact.min_impulse = 120;contact.max_impulse = 1000;contact.max_total_speed = 1100
	adapter.request_reset();await frames(3);lab.sequence = 0
	var result: Dictionary = lab.submit(structures)
	check("fixture_queued",result.status=="QUEUED",result)
	await frames(4)
	check("fixture_applied",adapter.applied_sequence==1,manager.last_conflict)
func land(kind: String="GREEN_SOLID",angle: float=0.0) -> void:
	await reset([Fixture.single(kind,Vector2(640,400),angle)])
	place(p,Vector2(640,320),Vector2(0,100));await frames(40)
func contact_since(value: int,limit: int=90) -> bool:
	for i: int in range(limit):
		await frames(1)
		if contact.metrics.bounces>value:return true
	return false
func shape(kind: String,ring: Array) -> Dictionary:
	var region: Dictionary = Fixture.region("test_r",kind,ring)
	var points: PackedVector2Array = []
	for point: Array in ring: points.append(Vector2(float(point[0]),float(point[1])))
	region.convex_parts = []
	for part: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(points):
		var raw: Array = []
		for point: Vector2 in part: raw.append([point.x,point.y])
		region.convex_parts.append(raw)
	return Fixture.structure("test",Vector2(640,400),[region])

func run(scene_tree: SceneTree,label: String="headless") -> Dictionary:
	tree = scene_tree;lab = tree.current_scene;manager = lab.manager;adapter = lab.adapter
	p = lab.players[0];q = lab.players[1];contact = p.get_node("MaterialContact")
	input_driver = load("res://validation/MaterialPhysicsTestInput.gd").new()
	lab.add_child(input_driver)
	adapter.batch_result.connect(observe_commit)
	await frames(8)
	await land()
	check("solid_horizontal",p.is_on_floor() and absf(p.position.y-380)<1,p.position)
	await land("GREEN_SOLID",0.25)
	check("solid_inclined",p.is_on_floor() and p.get_floor_normal().dot(Vector2.UP.rotated(0.25))>0.98,p.get_floor_normal())
	await reset([shape("GREEN_SOLID",[[-140,0],[-70,0],[-70,70],[140,70],[140,110],[-140,110]])])
	place(p,Vector2(535,320));await frames(50)
	check("solid_concave",p.is_on_floor() and p.position.y<390,p.position)
	var ring: Dictionary = Fixture.region("test_r","GREEN_SOLID",Fixture.rect(-140,0,280,140))
	ring.regions[0].holes = [[[-80,25],[-80,100],[80,100],[80,25]]]
	ring.convex_parts = [Fixture.rect(-140,0,280,25),Fixture.rect(-140,100,280,40),Fixture.rect(-140,25,60,75),Fixture.rect(80,25,60,75)]
	await reset([Fixture.structure("test",Vector2(640,400),[ring])])
	place(p,Vector2(640,455));await frames(25)
	check("solid_hole_is_empty_and_bottom_collides",p.is_on_floor() and p.position.y>470 and p.position.y<485,p.position)
	for name: String in ["above","below","left","right","diagonal","inclined","dash"]:
		var angle: float = 0.35 if name=="inclined" else 0
		await reset([Fixture.single("BLUE_BOUNCE",Vector2(640,400),angle)])
		var before: int = contact.metrics.bounces
		var normal: Vector2 = Vector2.UP
		match name:
			"above": place(p,Vector2(640,340),Vector2(0,300))
			"below": place(p,Vector2(640,490),Vector2(0,-500));normal = Vector2.DOWN
			"left","dash":
				place(p,Vector2(475,416));action("p1_right",true);normal = Vector2.LEFT
				if name=="dash": action("p1_dodge",true)
			"right": place(p,Vector2(805,416));action("p1_left",true);normal = Vector2.RIGHT
			"diagonal": place(p,Vector2(560,340),Vector2(300,300));action("p1_right",true)
			"inclined": place(p,Vector2(640,310),Vector2(0,350));normal = Vector2.UP.rotated(angle)
		var bounced: bool = await contact_since(before)
		check("bounce_"+name,bounced,{"position":p.position,"velocity":p.velocity})
		if bounced:
			var event: Dictionary = contact.bounce_events[-1]
			check("normal_"+name,event.normal.dot(normal)>0.97,event)
			check("bounded_"+name,event.velocity.length()<=1100.01,event.velocity)
			if name=="dash": check("dash_cancelled_but_invulnerability_preserved",p.combat.dodge_left==0 and p.combat.invulnerability_left>0)
			if name=="diagonal": check("diagonal_retains_tangent",event.velocity.x>30 and event.velocity.y< -500,event.velocity)
		check("bounce_has_no_contact_damage_"+name,p.combat.damage_model.percent==0)
		release()
	await reset([Fixture.single("BLUE_BOUNCE")])
	contact.min_impulse = 0;contact.bounce_impulse = 0
	var before: int = contact.metrics.bounces
	var duplicates: int = contact.metrics.duplicate_bounces_avoided
	place(p,Vector2(640,350),Vector2(0,150));await frames(60)
	check("continuous_contact_bounces_once",contact.metrics.bounces-before==1,contact.metrics.bounces-before)
	check("continuous_duplicates_suppressed",contact.metrics.duplicate_bounces_avoided>duplicates)
	await reset([Fixture.single("BLUE_BOUNCE")])
	contact.bounce_impulse = 10000;contact.max_impulse = 850;contact.max_total_speed = 900
	before = contact.metrics.bounces;place(p,Vector2(640,340),Vector2(0,500))
	await contact_since(before)
	check("impulse_configured_cap",p.velocity.length()<=900.01,p.velocity)
	await reset([Fixture.single("BLUE_BOUNCE")])
	contact.bounce_impulse = 900;contact.min_impulse = 600;contact.max_total_speed = 400
	before = contact.metrics.bounces;place(p,Vector2(640,340),Vector2(0,500));await contact_since(before)
	check("total_cap_wins_over_minimum_impulse",contact.bounce_events[-1].velocity.length()<=400.01,contact.bounce_events[-1])
	await reset([Fixture.single("ORANGE_ONE_WAY")])
	place(p,Vector2(640,480),Vector2(0,-650));await frames(20)
	check("one_way_passes_from_below",p.position.y<350,p.position)
	await frames(65)
	check("one_way_landing",p.is_on_floor() and absf(p.position.y-380)<2,p.position)
	var drops: int = contact.metrics.drops
	action("p1_down",true);await frames(2);action("p1_down",false)
	check("voluntary_drop",contact.metrics.drops==drops+1 and not contact.ignored.is_empty(),{"drops":contact.metrics.drops-drops,"floor":p.is_on_floor(),"velocity":p.velocity,"down":Input.is_action_pressed("p1_down"),"input_trace":input_driver.trace.duplicate(true)})
	await frames(45)
	check("drop_exits_and_restores",p.position.y>460 and contact.ignored.is_empty() and p.get_collision_exceptions().is_empty(),p.position)
	place(p,Vector2(640,470),Vector2(0,-650));await frames(90)
	check("one_way_collision_returns_after_drop",p.is_on_floor() and absf(p.position.y-380)<2,p.position)
	await land("ORANGE_ONE_WAY")
	drops = contact.metrics.drops
	action("p1_down",true);action("p1_dodge",true);await frames(2);release()
	check("defense_has_priority_over_drop",contact.metrics.drops==drops and p.combat.dodge_left>0,{"drops":contact.metrics.drops-drops,"dodge":p.combat.dodge_left,"input_trace":input_driver.trace.duplicate(true)})
	await frames(25)
	action("p1_down",true);action("p1_light",true);await frames(2);release()
	check("attack_has_priority_over_drop",contact.metrics.drops==drops and p.combat.attack_frame>=0)
	await reset([Fixture.single("ORANGE_ONE_WAY")])
	place(p,Vector2(490,420),Vector2(0,-150));action("p1_right",true);await frames(24);release()
	check("one_way_passes_side",p.position.x>560 and not p.is_on_wall(),p.position)
	await land("ORANGE_ONE_WAY",0.2)
	check("one_way_incline",p.is_on_floor() and p.get_floor_normal().dot(Vector2.UP.rotated(0.2))>0.98,p.get_floor_normal())
	await reset([shape("ORANGE_ONE_WAY",[[-140,0],[-70,0],[-70,70],[140,70],[140,110],[-140,110]])])
	place(p,Vector2(700,410),Vector2(0,100));await frames(35)
	check("one_way_concave_upper_ledge",p.is_on_floor() and absf(p.position.y-450)<2,p.position)
	ring.material = "ORANGE_ONE_WAY"
	await reset([Fixture.structure("test",Vector2(640,400),[ring])])
	place(p,Vector2(640,455));await frames(30)
	check("one_way_hole_empty_and_inner_upper_edge",p.is_on_floor() and absf(p.position.y-480)<2,p.position)
	await land("ORANGE_ONE_WAY")
	var ow_body: Node = manager.get_body(&"test_r")
	var ow_builds: int = ow_body.shape_builds
	var ow_player_start: Vector2 = p.position
	lab.submit([Fixture.single("ORANGE_ONE_WAY",Vector2(670,390))]);await frames(45)
	check("moving_one_way_carries_without_rebuild",p.is_on_floor() and ow_body.shape_builds==ow_builds and (p.position-ow_player_start-Vector2(30,-10)).length()<3,{"position":p.position,"conflict":manager.last_conflict})
	await reset([Fixture.single("ORANGE_ONE_WAY")])
	ow_body = manager.get_body(&"test_r");ow_builds = ow_body.shape_builds
	lab.submit([Fixture.single("ORANGE_ONE_WAY",Vector2(640,400),0.2)]);await frames(40)
	check("one_way_rotation_does_not_rebuild",absf(ow_body.rotation-0.2)<0.01 and ow_body.shape_builds==ow_builds)
	var enabled_edges: int = 0
	for collider: CollisionShape2D in ow_body.colliders:
		if not collider.disabled: enabled_edges += 1
	check("one_way_only_upper_edges_enabled",enabled_edges==1,enabled_edges)
	await land("GREEN_SOLID")
	drops = contact.metrics.drops;action("p1_down",true);await frames(20);release()
	check("down_on_solid_does_not_drop",p.is_on_floor() and absf(p.position.y-380)<1 and contact.metrics.drops==drops,p.position)
	for kind: String in ["ORANGE_ONE_WAY","BLUE_BOUNCE"]:
		var joined: Dictionary = Fixture.structure("joined",Vector2(640,400),[Fixture.region("joined_g","GREEN_SOLID",Fixture.rect(-160,0,160,40)),Fixture.region("joined_m",kind,Fixture.rect(0,0,160,40))])
		await reset([joined]);place(p,Vector2(560,320));await frames(40)
		check("mixed_solid_support_"+kind,p.is_on_floor())
		check("one_logical_two_regions_"+kind,adapter.logical_active.size()==1 and manager.object_ids().size()==2)
		q.set_physics_process(true);q.collision_mask = 3;place(q,Vector2(720,320))
		var qb: int = q.get_node("MaterialContact").metrics.bounces
		await frames(40)
		check("two_players_"+kind,p.is_on_floor() and (q.is_on_floor() if kind=="ORANGE_ONE_WAY" else q.get_node("MaterialContact").metrics.bounces>qb))
	await land()
	var body: Node = manager.get_body(&"test_r")
	var builds: int = body.shape_builds
	var start: Vector2 = p.position
	var initial_body: Vector2 = body.position
	var moved: Dictionary = Fixture.single("GREEN_SOLID",Vector2(670,380))
	lab.submit([moved]);var floors: int = 0;var max_step: float = 0;var previous: Vector2 = p.position
	for i: int in range(50):
		await frames(1)
		if p.is_on_floor(): floors += 1
		max_step = maxf(max_step,p.position.distance_to(previous));previous = p.position
	measurements.append({"name":"carrier","floor_ticks":floors,"max_step_px":max_step,"carry_error":((p.position-start)-(body.position-initial_body)).length(),"manager_conflicts":manager.motion_conflicts})
	check("pose_no_rebuild",body.shape_builds==builds)
	check("moving_supported_character",floors>=45 and body.position.distance_to(Vector2(670,380))<1 and ((p.position-start)-(body.position-initial_body)).length()<3,measurements[-1])
	check("no_large_carrier_jump",max_step<4,measurements[-1])
	await land()
	var ceiling: StaticBody2D = StaticBody2D.new()
	var ceiling_shape: CollisionShape2D = CollisionShape2D.new()
	var ceiling_rect: RectangleShape2D = RectangleShape2D.new();ceiling_rect.size = Vector2(300,10)
	ceiling_shape.shape = ceiling_rect;ceiling.add_child(ceiling_shape);ceiling.position = Vector2(640,340);lab.add_child(ceiling)
	await frames(2)
	var external_blocks: int = manager.conflict_counts.get("carrier_blocked_by_external_solid",0)
	lab.submit([Fixture.single("GREEN_SOLID",Vector2(640,350))]);await frames(55)
	check("carrier_stops_before_external_ceiling",int(manager.conflict_counts.get("carrier_blocked_by_external_solid",0))>external_blocks and p.position.y>364 and manager.get_body(&"test_r").position.y>380,{"position":p.position,"conflict":manager.last_conflict,"counts":manager.conflict_counts.duplicate()})
	var clearance: RectangleShape2D = RectangleShape2D.new();clearance.size = Vector2(38,38)
	check("carrier_does_not_crush_rider",not ceiling_rect.collide(ceiling.global_transform,clearance,p.get_node("CollisionShape2D").global_transform))
	ceiling.queue_free();await frames(3)
	await land()
	body = manager.get_body(&"test_r");builds = body.shape_builds
	var changed: Dictionary = Fixture.single("GREEN_SOLID")
	changed.geometry_version = 2;changed.material_regions[0].geometry_version = 2
	changed.regions[0].exterior = Fixture.rect(-120,-20,240,55)
	changed.convex_parts = [changed.regions[0].exterior.duplicate(true)]
	changed.material_regions[0].regions = changed.regions.duplicate(true);changed.material_regions[0].convex_parts = changed.convex_parts.duplicate(true)
	lab.submit([changed]);await frames(8)
	check("occupied_geometry_deferred_atomically",not adapter.pending_frame.is_empty() and body.shape_builds==builds and manager.last_conflict=="character_penetration",manager.last_conflict)
	action("p1_right",true);await frames(70);release()
	check("geometry_applies_after_character_leaves",adapter.pending_frame.is_empty() and body.shape_builds==builds+1,manager.last_conflict)
	await land("ORANGE_ONE_WAY")
	action("p1_down",true);await frames(2);action("p1_down",false)
	var material_change: Dictionary = Fixture.single("GREEN_SOLID")
	material_change.geometry_version = 2;material_change.material_regions[0].geometry_version = 2
	lab.submit([material_change]);await frames(1)
	body = manager.get_body(&"test_r")
	check("material_change_during_traversal_deferred",body.material_kind=="ORANGE_ONE_WAY" and not adapter.pending_frame.is_empty(),{"position":p.position,"drops":contact.metrics.drops,"phase":p.combat.phase(),"trace":input_driver.trace.duplicate(true)})
	await frames(40)
	check("material_change_commits_when_clear",body.material_kind=="GREEN_SOLID" and adapter.pending_frame.is_empty() and contact.ignored.is_empty())
	await land("GREEN_SOLID")
	before = contact.metrics.bounces
	material_change = Fixture.single("BLUE_BOUNCE");material_change.geometry_version = 2;material_change.material_regions[0].geometry_version = 2
	lab.submit([material_change]);await frames(15)
	check("solid_to_bounce_at_contact",contact.metrics.bounces>before and manager.object_ids().size()==1)
	await reset([Fixture.single("BLUE_BOUNCE")])
	place(p,Vector2(640,340),Vector2(0,300))
	p.combat.receive_hit(p.combat.ground_light,Vector2.DOWN);p.combat.hitstun_left = 0.5
	var percent: float = p.combat.damage_model.percent
	before = contact.metrics.bounces;await contact_since(before)
	check("bounce_preserves_hitstun_and_damage",contact.metrics.bounces==before+1 and p.combat.hitstun_left>0 and p.combat.damage_model.percent==percent,{"percent":p.combat.damage_model.percent,"hitstun":p.combat.hitstun_left})
	# Geometry/material transactions without actors: reject one bad member, all stay.
	await reset([Fixture.single("GREEN_SOLID")]);place(p,Vector2(60,-400));p.set_physics_process(false)
	var base_nodes: int = lab.get_tree().get_node_count()
	for i: int in range(80):
		var c: Dictionary = Fixture.single(["GREEN_SOLID","ORANGE_ONE_WAY","BLUE_BOUNCE"][i%3])
		c.geometry_version = i+2;c.material_regions[0].geometry_version = i+2
		var width: float = 200 if i%2==0 else 240
		c.regions[0].exterior = Fixture.rect(-width/2,0,width,35)
		c.convex_parts = [c.regions[0].exterior.duplicate(true)]
		c.material_regions[0].regions = c.regions.duplicate(true);c.material_regions[0].convex_parts = c.convex_parts.duplicate(true)
		c.orientation_radians = sin(i*.1)*.2
		lab.submit([c]);await frames(2)
	check("stress_transactions_finish",adapter.pending_frame.is_empty() and adapter.metrics.applied>=80)
	check("stress_no_node_growth",lab.get_tree().get_node_count()<=base_nodes+4,{"before":base_nodes,"after":lab.get_tree().get_node_count()})
	var invalid: Dictionary = Fixture.single("GREEN_SOLID");invalid.geometry_version = 100;invalid.material_regions[0].material = "UNKNOWN"
	var applied: int = adapter.applied_sequence
	check("invalid_batch_rejected",lab.submit([invalid]).status=="REJECTED")
	await frames(2);check("invalid_batch_keeps_last",adapter.applied_sequence==applied and manager.object_ids().size()==1)
	var good: Dictionary = Fixture.structure("new_good",Vector2(300,300),[Fixture.region("new_good_r","GREEN_SOLID",Fixture.rect(-60,0,120,30))])
	check("invalid_member_rejects_entire_batch",lab.submit([good,invalid]).status=="REJECTED")
	await frames(2)
	check("no_partial_valid_member_created",manager.get_body(&"new_good_r")==null and adapter.applied_sequence==applied)
	p.set_physics_process(true);q.set_physics_process(true);q.collision_mask = 3
	check("no_deep_solid_penetrations",lab.physical_metrics.solid_penetration_frames_over_1px==0,lab.penetration_events)
	check("commit_signal_has_coherent_logical_and_physical_state",incoherent_commits==0,incoherent_commits)
	adapter.batch_result.disconnect(observe_commit)
	release();input_driver.queue_free()
	var failures: Array = rows.filter(func(r: Dictionary) -> bool:return not r.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"measurements":measurements,"contact_metrics":contact.metrics.duplicate(),"adapter":adapter.get_status(),"update_us":manager.update_us.duplicate(),"physical_metrics":lab.physical_metrics.duplicate(),"penetration_events":lab.penetration_events.duplicate(true),"logical_metrics":adapter.logical_metrics.duplicate(true),"conflict_counts":manager.conflict_counts.duplicate(),"human_tested":false}
	var file: FileAccess = FileAccess.open("res://validation/material_physics_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	lab.set_meta("material_physics_results",result)
	print("MATERIAL_PHYSICS ",result.passed,"/",result.total," ",failures)
	return result
