extends RefCounted
const Lab = preload("res://scripts/geometry/PolygonLab.gd")
const Validator = preload("res://scripts/geometry/PolygonValidator.gd")
var tree: SceneTree
var scene: Node
var manager: Node
var player: CharacterBody2D
var rows: Array[Dictionary] = []
var measurements: Dictionary = {}

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(label: String,passed: bool,detail: Variant = "") -> void:
	rows.append({"test":label,"passed":passed,"detail":str(detail)})

func point_hits(id: StringName,local_point: Vector2) -> bool:
	var body: StaticBody2D = manager.get_body(id)
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = body.to_global(local_point)
	query.collision_mask = 1
	query.collide_with_areas = false
	for hit: Dictionary in player.get_world_2d().direct_space_state.intersect_point(query,16):
		if hit.collider==body:
			return true
	return false

func overlap_area(body: Node2D) -> float:
	var rectangle: PackedVector2Array = PackedVector2Array([Vector2(-20,-20),Vector2(20,-20),Vector2(20,20),Vector2(-20,20)])
	rectangle = player.global_transform*rectangle
	var silhouette: PackedVector2Array = body.global_transform*body.polygon
	var total: float = 0
	for part: PackedVector2Array in Geometry2D.intersect_polygons(rectangle,silhouette):
		total += absf(Validator.signed_area(part))
	return total

func place_player(point: Vector2) -> void:
	player.position = point
	# Fixture teleports must also be visible to direct-space queries this tick.
	player.force_update_transform()
	player.velocity = Vector2.ZERO
	player.combat.reset_after_respawn()
	player.combat.respawn_left = 0
	player.combat.invulnerability_left = 0
	player.reset_physics_interpolation()

func run(scene_tree: SceneTree,label: String = "first") -> void:
	tree = scene_tree
	scene = tree.current_scene
	manager = scene.get_node("DynamicGeometry")
	player = scene.get_node("Player")
	scene.sequence_running = false
	scene.set_meta("polygon_validation_progress","api")
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("p1_"):
			Input.action_release(action)
	await frames(6)
	place_player(Vector2(75,590))
	check("three_independent_example_ids",manager.object_ids().size()==3)
	check("two_green_objects_share_color_not_identity",manager.get_state("green_A").color==manager.get_state("green_C").color and manager.get_body("green_A")!=manager.get_body("green_C"))
	check("scene_reuses_original_player_controller",player.get_script().resource_path=="res://scripts/PlayerController.gd" and player.movement.resource_path=="res://resources/PlayerMovement.tres")
	check("new_bodies_are_static_not_animatable",manager.get_body("green_A") is StaticBody2D and not manager.get_body("green_A") is AnimatableBody2D)
	check("queue_create_convex",manager.create_object(&"api_convex",Lab.CONVEX,Vector2(220,170),0,Color.GREEN))
	check("create_commits_only_on_physics_tick",manager.get_body("api_convex")==null and not manager.get_state("api_convex").committed)
	check("queue_create_concave",manager.create_object(&"api_concave",Lab.CONCAVE,Vector2(650,170),0,Color.GREEN))
	check("duplicate_id_rejected",not manager.create_object(&"api_convex",Lab.TRIANGLE,Vector2(900,170)))
	await frames(3)
	check("convex_creates_one_polygon_shape",manager.get_state("api_convex").parts==1 and manager.get_body("api_convex").colliders[0].shape is ConvexPolygonShape2D)
	check("concave_decomposed_into_multiple_convex_shapes",manager.get_state("api_concave").parts>1,manager.get_state("api_concave").parts)
	check("concave_notch_remains_empty",not point_hits("api_concave",Vector2(0,-12)))
	check("concave_lower_surface_is_solid",point_hits("api_concave",Vector2(0,30)))
	var convex: Node2D = manager.get_body("api_convex")
	var builds: int = convex.shape_builds
	var shape_id: RID = convex.colliders[0].shape.get_rid()
	var initial_pose: Transform2D = convex.transform
	check("queue_position_and_rotation",manager.update_transform(&"api_convex",Vector2(250,170),0.2))
	check("pose_not_mutated_by_api_call",convex.transform==initial_pose)
	await frames(65)
	check("position_target_reached",convex.position.distance_to(Vector2(250,170))<0.01,convex.position)
	check("rotation_target_reached",absf(convex.rotation-.2)<.001,convex.rotation)
	check("pose_only_preserves_shape_instances",convex.shape_builds==builds and convex.colliders[0].shape.get_rid()==shape_id)
	var other_before: Transform2D = manager.get_body("green_A").transform
	manager.update_transform(&"green_C",Vector2(1040,360),.1)
	await frames(45)
	check("same_color_motion_does_not_modify_other_object",manager.get_body("green_A").transform==other_before)
	check("queue_valid_geometry_change",manager.assign_polygon(&"api_convex",Lab.TRIANGLE))
	check("geometry_not_mutated_before_tick",convex.geometry_revision==1)
	var bowtie: PackedVector2Array = PackedVector2Array([Vector2(-60,-30),Vector2(60,30),Vector2(-60,30),Vector2(60,-30)])
	check("invalid_after_valid_pending_does_not_cancel_valid_request",not manager.assign_polygon(&"api_convex",bowtie))
	await frames(3)
	check("valid_geometry_swapped_once_without_replacing_body",manager.get_body("api_convex")==convex and convex.geometry_revision==2 and convex.polygon.size()==3)
	var stable_geometry: PackedVector2Array = convex.polygon.duplicate()
	var invalids: Dictionary = {
		"fewer_than_three":PackedVector2Array([Vector2.ZERO,Vector2(10,0)]),
		"zero_edge":PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2(30,40)]),
		"zero_area":PackedVector2Array([Vector2.ZERO,Vector2(20,0),Vector2(40,0)]),
		"tiny_area":PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2(0,1)]),
		"self_intersection":bowtie,
		"adjacent_overlap":PackedVector2Array([Vector2.ZERO,Vector2(50,0),Vector2(20,0),Vector2(40,50),Vector2(0,50)]),
		"repeated_nonadjacent":PackedVector2Array([Vector2.ZERO,Vector2(40,0),Vector2(40,40),Vector2.ZERO,Vector2(0,40)]),
		"closing_duplicate":PackedVector2Array([Vector2.ZERO,Vector2(40,0),Vector2(0,40),Vector2.ZERO]),
		"touching_nonadjacent_edge":PackedVector2Array([Vector2(0,0),Vector2(60,0),Vector2(60,60),Vector2(30,0),Vector2(0,60)]),
		"nan":PackedVector2Array([Vector2(NAN,0),Vector2(40,0),Vector2(0,40)]),
		"infinite":PackedVector2Array([Vector2(INF,0),Vector2(40,0),Vector2(0,40)]),
		"coordinate_limit":PackedVector2Array([Vector2(5000,0),Vector2(5100,0),Vector2(5000,40)])}
	var too_many: PackedVector2Array = []
	for i: int in range(manager.max_vertices+1):
		too_many.append(Vector2.from_angle(TAU*i/(manager.max_vertices+1))*80)
	invalids["vertex_limit"] = too_many
	for name: String in invalids:
		check("reject_"+name,not manager.assign_polygon(&"api_convex",invalids[name]))
		check("preserve_last_valid_after_"+name,manager.get_state("api_convex").polygon==stable_geometry and convex.geometry_revision==2)
	await frames(3)
	check("invalid_geometry_never_rebuilt_shapes",convex.geometry_revision==2 and convex.polygon==stable_geometry)
	check("invalid_pose_rejected",not manager.update_transform(&"api_convex",Vector2(NAN,0),0) and not manager.update_transform(&"api_convex",Vector2.ZERO,INF))
	check("unknown_id_rejected_without_creation",not manager.assign_polygon(&"absent",Lab.CONVEX) and not manager.update_transform(&"absent",Vector2.ZERO,0) and not manager.has_object(&"absent"))
	builds = convex.shape_builds
	manager.assign_polygon(&"api_convex",Lab.TRIANGLE)
	await frames(3)
	check("identical_geometry_does_not_rebuild",convex.shape_builds==builds)
	var reversed: PackedVector2Array = Lab.CONVEX.duplicate()
	reversed.reverse()
	check("both_windings_are_valid",Validator.validate(reversed).ok)
	check("collinear_forward_edge_valid",Validator.validate(PackedVector2Array([Vector2(0,0),Vector2(40,0),Vector2(80,0),Vector2(80,40),Vector2(0,40)])).ok)
	manager.set_collision_enabled(&"api_convex",false)
	await frames(3)
	check("disabled_removes_physical_collision",not point_hits("api_convex",Vector2(0,15)) and convex.collision_layer==0 and convex.shape_builds==builds)
	manager.set_collision_enabled(&"api_convex",true)
	await frames(3)
	check("reenable_reuses_shapes",point_hits("api_convex",Vector2(0,15)) and convex.shape_builds==builds)
	manager.remove_object(&"api_convex")
	await frames(3)
	check("deletion_removes_body_and_id",not manager.has_object(&"api_convex") and manager.get_body("api_convex")==null and manager.get_state("api_convex").is_empty())
	await callback_test()
	scene.set_meta("polygon_validation_progress","physics")
	await physics_tests()
	var failures: Array = rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var report: Dictionary = {"label":label,"engine":Engine.get_version_info()["string"],"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"measurements":measurements,"rows":rows,"hardware_used":false}
	var file: FileAccess = FileAccess.open("res://validation/polygon_lab_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	scene.set_meta("polygon_validation_results",report)
	scene.set_meta("polygon_validation_progress","complete")
	print("POLYGON_LAB_QA ",JSON.stringify({"label":label,"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"measurements":measurements}))

func callback_test() -> void:
	var area: Area2D = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.position = Vector2(230,130)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(90,90)
	shape.shape = rectangle
	area.add_child(shape)
	var flag: Dictionary = {"called":false,"accepted":false}
	area.body_entered.connect(func(body: Node2D) -> void:
		if body==manager.get_body("callback"):
			flag.called = true
			flag.accepted = manager.assign_polygon(&"callback",Lab.TRIANGLE) and manager.update_transform(&"callback",Vector2(260,130),.05) and manager.set_collision_enabled(&"callback",false) and manager.create_object(&"callback_aux",Lab.TRIANGLE,Vector2(80,140)) and manager.remove_object(&"callback_victim")
	)
	scene.add_child(area)
	manager.create_object(&"callback_victim",Lab.CONVEX,Vector2(950,140))
	manager.create_object(&"callback",Lab.CONVEX,Vector2(230,130))
	await frames(10)
	check("requests_inside_body_entered_callback_are_deferred",flag.called and flag.accepted)
	check("callback_changes_committed_without_flush_mutation",manager.get_state("callback").geometry_revision==2 and not manager.get_state("callback").collision_enabled and manager.has_object("callback_aux") and not manager.has_object("callback_victim"))
	area.queue_free()
	await frames(2)
	var baseline: int = manager.get_child_count()
	for i: int in range(12):
		manager.create_object(&"cycle",Lab.CONVEX,Vector2(1100,150))
		await frames(1)
		manager.remove_object(&"cycle")
		await frames(1)
	check("repeated_creation_deletion_does_not_leak_nodes",manager.get_child_count()==baseline)

func physics_tests() -> void:
	for id: StringName in manager.object_ids():
		manager.remove_object(id)
	await frames(3)
	manager.create_object(&"carrier",Lab.CONVEX,Vector2(350,410),0,Color.GREEN)
	manager.create_object(&"notch",Lab.CONCAVE,Vector2(780,390),0,Color.BLUE)
	manager.create_object(&"slope",Lab.TRIANGLE,Vector2(1060,400),0,Color.GREEN)
	await frames(3)
	place_player(Vector2(780,240))
	await frames(90)
	check("character_lands_inside_concave_notch_not_bounding_rectangle",player.is_on_floor() and absf(player.position.y-380)<.6 and absf(player.position.x-780)<1,player.position)
	check("concave_contact_has_no_deep_overlap",overlap_area(manager.get_body("notch"))<2)
	place_player(Vector2(1020,250))
	await frames(90)
	check("character_contacts_real_sloped_surface",player.is_on_floor() and absf(player.get_floor_normal().x)>.2 and player.position.y>345,player.get_floor_normal())
	check("sloped_contact_has_no_deep_overlap",overlap_area(manager.get_body("slope"))<2)
	place_player(Vector2(350,240))
	await frames(90)
	check("character_lands_on_irregular_convex_top",player.is_on_floor() and absf(player.position.y-362)<.6,player.position)
	await measure_motion("horizontal",Vector2(450,410),0,100)
	await measure_motion("rising",Vector2(450,360),0,90)
	await measure_motion("descending",Vector2(450,410),0,90)
	await measure_motion("rotation",Vector2(450,410),.22,100)
	await stress_motion()
	manager.update_transform(&"carrier",Vector2(350,410),0)
	await frames(150)
	place_player(Vector2(350,240))
	await frames(90)
	var carrier: Node2D = manager.get_body("carrier")
	var revision: int = carrier.geometry_revision
	var expanded: PackedVector2Array = Lab.CONVEX.duplicate()
	for i: int in range(expanded.size()):
		expanded[i].y -= 16
	manager.assign_polygon(&"carrier",expanded)
	await frames(4)
	check("occupied_geometry_update_keeps_last_collision",manager.get_state("carrier").blocked_by_character and carrier.geometry_revision==revision and overlap_area(carrier)<2)
	place_player(Vector2(75,590))
	await frames(4)
	check("pending_geometry_commits_when_character_clears",not manager.get_state("carrier").blocked_by_character and carrier.geometry_revision==revision+1)
	manager.assign_polygon(&"carrier",Lab.CONVEX)
	await frames(4)
	place_player(Vector2(350,240))
	await frames(90)
	manager.create_object(&"occupied_spawn",Lab.CONVEX,player.position)
	await frames(4)
	check("spawn_intersecting_character_is_pending_not_engulfing",manager.has_object("occupied_spawn") and manager.get_body("occupied_spawn")==null and manager.get_state("occupied_spawn").blocked_by_character)
	place_player(Vector2(75,590))
	await frames(4)
	check("pending_spawn_commits_after_character_clears",manager.get_body("occupied_spawn")!=null and not manager.get_state("occupied_spawn").blocked_by_character)
	manager.remove_object(&"occupied_spawn")
	await frames(3)
	place_player(Vector2(350,240))
	await frames(90)
	manager.set_collision_enabled(&"carrier",false)
	await frames(100)
	check("disable_support_character_falls_to_safety_floor",player.is_on_floor() and absf(player.position.y-610)<.6,player.position)
	place_player(Vector2(350,410))
	manager.set_collision_enabled(&"carrier",true)
	await frames(4)
	check("reactivation_does_not_engulf_character",not carrier.collision_enabled and manager.get_state("carrier").blocked_by_character,{"state":manager.get_state("carrier"),"player_position":player.position,"native_player":PhysicsServer2D.body_get_state(player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM),"player_layer":player.collision_layer})
	place_player(Vector2(75,590))
	await frames(4)
	check("reactivation_commits_after_character_clears",carrier.collision_enabled and not manager.get_state("carrier").blocked_by_character)
	place_player(Vector2(350,240))
	await frames(90)
	manager.remove_object(&"carrier")
	await frames(100)
	check("remove_support_character_falls_to_safety_floor",player.is_on_floor() and absf(player.position.y-610)<.6,player.position)

func measure_motion(label: String,target: Vector2,angle: float,count: int) -> void:
	var body: Node2D = manager.get_body("carrier")
	var start_body: Vector2 = body.position
	var start_player: Vector2 = player.position
	var builds: int = body.shape_builds
	var recoveries: int = player.get_node("UnstuckGuard").recoveries
	var previous: Vector2 = player.position
	var maximum_step: float = 0
	var maximum_overlap: float = 0
	var floor_frames: int = 0
	manager.update_transform(&"carrier",target,angle)
	for i: int in range(count):
		await frames(1)
		maximum_step = maxf(maximum_step,player.position.distance_to(previous))
		maximum_overlap = maxf(maximum_overlap,overlap_area(body))
		previous = player.position
		if player.is_on_floor():
			floor_frames += 1
	var offset_error: Vector2 = (player.position-start_player)-(body.position-start_body)
	var result: Dictionary = {"max_player_step_px":maximum_step,"max_overlap_area_px2":maximum_overlap,"floor_frames":floor_frames,"frames":count,"carry_error_px":offset_error,"recovery_events":player.get_node("UnstuckGuard").recoveries-recoveries,"player_position":player.position,"body_position":body.position}
	measurements[label] = result
	check(label+"_no_rebuild_or_recovery",body.shape_builds==builds and result.recovery_events==0,result)
	check(label+"_no_unexpected_jump_or_penetration",maximum_step<8 and maximum_overlap<2,result)
	check(label+"_keeps_floor_contact",floor_frames>=count*.9,result)
	if label!="rotation":
		check(label+"_carries_character",offset_error.length()<2.5,result)

func stress_motion() -> void:
	var body: Node2D = manager.get_body("carrier")
	var builds: int = body.shape_builds
	var recoveries: int = player.get_node("UnstuckGuard").recoveries
	var previous: Vector2 = player.position
	var maximum_overlap: float = 0
	var maximum_step: float = 0
	var maximum_sweep: float = 0
	var floor_frames: int = 0
	for i: int in range(360):
		var t: float = i/60.0
		var pose: Transform2D = body.transform
		# Several producers in a tick: only the latest desired pose is committed.
		manager.update_transform(&"carrier",Vector2(450+sin(t*2)*20,410+sin(t)*8),sin(t)*.15)
		await frames(1)
		maximum_overlap = maxf(maximum_overlap,overlap_area(body))
		maximum_step = maxf(maximum_step,player.position.distance_to(previous))
		maximum_sweep = maxf(maximum_sweep,body.position.distance_to(pose.origin)+absf(angle_difference(pose.get_rotation(),body.rotation))*body.surface_radius)
		previous = player.position
		if player.is_on_floor():
			floor_frames += 1
	var result: Dictionary = {"frames":360,"floor_frames":floor_frames,"max_overlap_area_px2":maximum_overlap,"max_player_step_px":maximum_step,"max_surface_sweep_px":maximum_sweep,"recovery_events":player.get_node("UnstuckGuard").recoveries-recoveries}
	measurements["stress"] = result
	check("repeated_updates_preserve_shapes_and_no_recovery",builds==body.shape_builds and result.recovery_events==0,result)
	check("repeated_updates_no_jump_or_penetration",maximum_overlap<2 and maximum_step<8,result)
	check("repeated_updates_respect_sweep_budget",maximum_sweep<=manager.max_surface_step+.001,result)
	check("repeated_updates_keep_floor_contact",floor_frames>=324,result)
