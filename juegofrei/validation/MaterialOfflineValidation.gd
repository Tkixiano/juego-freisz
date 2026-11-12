extends RefCounted
var tree: SceneTree
var lab: Node
var replay: Node
var adapter: Node
var manager: Node
var p: CharacterBody2D
var input_driver: Node
var rows: Array = []
var scenarios: Array = []
var duplicate_samples: int = 0
var identity_errors: int = 0
var supported_samples: Dictionary = {}

func frames(n: int) -> void:
	for i: int in range(n): await tree.physics_frame
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
	if not ok: push_error("MATERIAL_OFFLINE "+name+" "+str(detail))
func place(pos: Vector2,vel: Vector2=Vector2.ZERO) -> void:
	p.position = pos;p.velocity = vel;p.force_update_transform();p.reset_physics_interpolation()
	p.combat.reset_after_respawn();p.combat.respawn_left = 0;p.combat.invulnerability_left = 0
	p.coyote_left = 0;p.buffer_left = 0
func park() -> void:
	for player: Node in lab.players:
		player.collision_mask = 0;player.set_physics_process(false);player.position = Vector2(1100,-400)
	input_driver.events.clear()
	for name: StringName in InputMap.get_actions():
		if String(name).begins_with("p1_"): Input.action_release(name)
func action(name: String,pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new();event.action = name;event.pressed = pressed
	input_driver.events.append(event)
func activate(pos: Vector2,vel: Vector2=Vector2.ZERO) -> void:
	p.collision_mask = 3;p.set_physics_process(true);place(pos,vel)
func load_case(name: String) -> void:
	replay.pause();adapter.request_reset();await frames(3)
	check(name+"_load",replay.load_replay("res://validation/material_replays/"+name+".json"),replay.errors)
	await frames(3);replay.set_speed(2.0)
func coherent(_seq: int,status: String,_reason: String) -> void:
	if status!="APPLIED": return
	var ids: Array = []
	for c: Dictionary in adapter.logical_active.values():
		for r: Dictionary in c.material_regions:
			ids.append(StringName(r.region_id))
			var body: Node = manager.get_body(StringName(r.region_id))
			if body==null or body.material_kind!=r.material or body.structure_id!=c.id: identity_errors += 1
	var actual: Array = manager.object_ids();ids.sort();actual.sort()
	if ids!=actual: identity_errors += 1
func overlaps() -> bool:
	var ids: Array = manager.object_ids()
	for i: int in range(ids.size()):
		for j: int in range(i+1,ids.size()):
			var a: Node = manager.get_body(ids[i]);var b: Node = manager.get_body(ids[j])
			for pa: PackedVector2Array in a.convex_parts:
				for pb: PackedVector2Array in b.convex_parts:
					if manager.CompoundValidator.intersection_area(a.global_transform*pa,b.global_transform*pb)>0.001:return true
	return false
func finish(limit: int=10000,measure_support: bool=false) -> Dictionary:
	var ticks: int = 0;var landed: bool = false;var losses: int = 0;var floors: int = 0;var max_step: float = 0
	var previous: Vector2 = p.position
	var previous_floor: bool = false;var max_supported_step: float = 0
	while (replay.cursor<replay.frames.size() or not adapter.pending_frame.is_empty()) and ticks<limit:
		await frames(1);ticks += 1
		if overlaps(): duplicate_samples += 1
		if measure_support:
			if previous_floor and p.is_on_floor():max_supported_step = maxf(max_supported_step,p.position.distance_to(previous))
			if p.is_on_floor(): landed = true;floors += 1
			elif landed: losses += 1
			previous_floor = p.is_on_floor()
			max_step = maxf(max_step,p.position.distance_to(previous));previous = p.position
	replay.pause()
	return {"ticks":ticks,"cursor":replay.cursor,"pending":not adapter.pending_frame.is_empty(),"landed":landed,"floor_ticks":floors,"losses":losses,"max_step_px":max_step,"max_supported_step_px":max_supported_step}
func submit_frame(frame: Dictionary) -> Dictionary:
	frame.sequence = adapter.high_sequence+1;frame.logical_time = maxf(0,adapter.high_time)+1
	return adapter.submit(frame)

func run(scene_tree: SceneTree,label: String="headless") -> Dictionary:
	tree = scene_tree;lab = tree.current_scene;replay = lab.get_node("Replay");adapter = lab.adapter;manager = lab.manager;p = lab.players[0]
	input_driver = load("res://validation/MaterialPhysicsTestInput.gd").new();lab.add_child(input_driver)
	adapter.batch_result.connect(coherent)
	await frames(10);park()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/material_replays/manifest.json"))
	for entry: Dictionary in manifest.scenarios:
		park();await load_case(entry.scenario)
		if replay.frames.is_empty(): continue
		lab.set_meta("offline_progress",entry.scenario)
		var before: Dictionary = adapter.metrics.duplicate(true)
		var before_rebuilds: int = manager.total_rebuilds
		var lm: Dictionary = adapter.logical_metrics.duplicate(true)
		replay.play();var observation: Dictionary = await finish(entry.frames*3+120)
		var rejected: int = adapter.metrics.rejected-before.rejected
		var last: Dictionary = replay.frames[-1]
		var expected_regions: int = 0
		for c: Dictionary in last.structures: expected_regions += c.material_regions.size()
		var s: Dictionary = {"scenario":entry.scenario,"frames":entry.frames,"rejected":rejected,"applied":adapter.metrics.applied-before.applied,"merges":adapter.logical_metrics.merges-lm.merges,"splits":adapter.logical_metrics.splits-lm.splits,"observed":observation}
		scenarios.append(s)
		s.rebuilds = manager.total_rebuilds-before_rebuilds
		if entry.scenario in ["13_movement","14_rotation","21_mobile_one_way","22_mobile_bounce"]:check(entry.scenario+"_no_rebuild_for_pose",s.rebuilds==1,s)
		check(entry.scenario+"_completed",replay.cursor==replay.frames.size() and not observation.pending,s)
		check(entry.scenario+"_rejections",rejected==entry.expected_rejections,s)
		check(entry.scenario+"_recovery",manager.object_ids().size()==expected_regions and adapter.logical_active.size()==last.structures.size(),s)
		check(entry.scenario+"_events",s.merges==entry.merges and s.splits==entry.splits,s)
	# Real physics while topology changes, using the same exported states.
	for name: String in ["19_supported_merge","20_supported_split","21_mobile_one_way","27_orange_merge_split"]:
		park();await load_case(name);activate(Vector2(330,240) if name=="27_orange_merge_split" else Vector2(210,240));replay.play()
		var observation: Dictionary = await finish(500,true)
		supported_samples[name] = observation
		check(name+"_keeps_support",observation.landed and observation.losses==0 and not observation.pending,observation)
		check(name+"_no_teleport",observation.max_step_px<8,observation)
		check(name+"_bounded_supported_step",observation.max_supported_step_px<2.1,observation)
	# No hidden solid parent may block the orange part after MERGE/SPLIT.
	place(Vector2(330,390),Vector2(0,-650));await frames(20)
	check("orange_after_split_passes_from_below",p.position.y<280,p.position)
	await frames(65);check("orange_after_split_lands",p.is_on_floor() and p.position.y<285,p.position)
	var orange_contact: Node = p.get_node("MaterialContact")
	var orange_drops: int = orange_contact.metrics.drops
	action("p1_down",true);await frames(2);action("p1_down",false);await frames(40)
	check("orange_after_split_drop",orange_contact.metrics.drops==orange_drops+1 and orange_contact.ignored.is_empty(),p.position)
	for name: String in ["08_merge","09_split"]:
		park();await load_case(name);replay.play();await finish(200)
		var blue_region: Node
		for id: StringName in manager.object_ids():
			if manager.get_body(id).material_kind=="BLUE_BOUNCE":blue_region = manager.get_body(id)
		var center: Vector2 = Vector2.ZERO
		for point: Vector2 in blue_region.convex_parts[0]:center += point/blue_region.convex_parts[0].size()
		center = blue_region.to_global(center)
		var bounce_count: int = orange_contact.metrics.bounces
		activate(center-Vector2(0,70),Vector2(0,250))
		for i: int in range(35):
			await frames(1)
			if orange_contact.metrics.bounces>bounce_count:break
		check(name+"_blue_still_bounces",orange_contact.metrics.bounces==bounce_count+1)
	# A bounce on an actually moving region.
	park();await load_case("22_mobile_bounce");replay.play()
	while replay.cursor<18: await frames(1)
	var contact: Node = p.get_node("MaterialContact")
	var before_bounce: int = contact.metrics.bounces
	var blue: Node = manager.get_body(manager.object_ids()[0])
	activate(Vector2(blue.position.x,blue.position.y-70),Vector2(0,250))
	var moving_bounce: bool = false
	for i: int in range(35):
		await frames(1)
		if contact.metrics.bounces>before_bounce: moving_bounce = blue.constant_linear_velocity.length()>1;break
	check("bounce_on_moving_blue",moving_bounce,contact.bounce_events)
	replay.pause()
	# Dropping and restoring the collision of an exported orange region.
	park();await load_case("03_one_way");replay.play();await finish(100)
	activate(Vector2(210,240));await frames(35)
	check("exported_one_way_landing",p.is_on_floor(),p.position)
	var drops: int = contact.metrics.drops
	action("p1_down",true);await frames(2);action("p1_down",false);await frames(40)
	check("exported_one_way_drop",contact.metrics.drops==drops+1 and contact.ignored.is_empty() and p.position.y>350,p.position)
	# Occupied geometry: keep the complete last state and apply only after leaving.
	park();await load_case("01_solid");replay.play();await finish(100)
	activate(Vector2(210,240));await frames(35)
	var frame: Dictionary = replay.frames[-1].duplicate(true)
	var c: Dictionary = frame.structures[0]
	c.geometry_version += 1;c.material_regions[0].geometry_version += 1
	for ring: Dictionary in c.regions:
		for point: Array in ring.exterior:
			if point[1]<0:point[1] -= 20
	c.convex_parts = [c.regions[0].exterior.duplicate(true)]
	c.material_regions[0].regions = c.regions.duplicate(true);c.material_regions[0].convex_parts = c.convex_parts.duplicate(true)
	var rebuilds: int = manager.total_rebuilds
	check("occupied_update_queued",submit_frame(frame).status=="QUEUED");await frames(5)
	check("occupied_update_deferred",not adapter.pending_frame.is_empty() and manager.total_rebuilds==rebuilds,manager.last_conflict)
	action("p1_right",true);await frames(50);action("p1_right",false);await frames(2)
	check("occupied_update_applies_after_exit",adapter.pending_frame.is_empty() and manager.total_rebuilds==rebuilds+1)
	# Direct version/epoch/session failures; no partial apply.
	park();await load_case("01_solid");replay.play();await finish(100)
	var original: Dictionary = replay.frames[-1].duplicate(true)
	for kind: String in ["session","root_epoch","region_epoch","geometry_version"]:
		frame = original.duplicate(true)
		match kind:
			"session":frame.session_id = "other-session"
			"root_epoch":frame.identity_epochs[frame.structures[0].id] += 1
			"region_epoch":frame.region_identity_epochs[frame.structures[0].material_regions[0].region_id] += 1
			"geometry_version":frame.structures[0].geometry_version = 0
		check("reject_"+kind,submit_frame(frame).status=="REJECTED")
	check("identity_failures_preserve_state",manager.object_ids().size()==1 and adapter.logical_active.size()==1)
	# Reusing a retired regional identity requires a new explicit epoch.
	frame = original.duplicate(true);frame.structures = [];frame.identity_epochs = {};frame.region_identity_epochs = {}
	check("retire_all_queued",submit_frame(frame).status=="QUEUED");await frames(3)
	frame = original.duplicate(true);frame.identity_epochs[frame.structures[0].id] += 1
	check("retired_region_epoch_rejected",submit_frame(frame).status=="REJECTED")
	frame.region_identity_epochs[frame.structures[0].material_regions[0].region_id] += 1
	check("retired_identity_new_epoch_queued",submit_frame(frame).status=="QUEUED");await frames(3)
	check("retired_identity_restored",manager.object_ids().size()==1 and adapter.pending_frame.is_empty())
	# A file header cannot change a session silently, nor erase the current state.
	var bad_header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/material_replays/01_solid.json"))
	bad_header.session_id = "mismatched-header"
	var bad_file: FileAccess = FileAccess.open("res://validation/material_replays/header_bad.json",FileAccess.WRITE)
	bad_file.store_string(JSON.stringify(bad_header));bad_file.close()
	check("mismatched_file_session_rejected",not replay.load_replay("res://validation/material_replays/header_bad.json") and manager.object_ids().size()==1)
	# The legacy adapter must reject v2 explicitly, not silently flatten materials.
	var legacy_adapter: Node = load("res://scripts/geometry/OfflineGeometryAdapter.gd").new();legacy_adapter.manager = manager
	var legacy_player: Node = load("res://scripts/geometry/OfflineReplayPlayer.gd").new();legacy_player.adapter = legacy_adapter
	check("legacy_backend_rejects_v2",not legacy_player.load_replay("res://validation/material_replays/01_solid.json"))
	legacy_player.free();legacy_adapter.free()
	adapter.request_reset();await frames(3)
	frame = original.duplicate(true);frame.session_id = "new-test-session";frame.sequence = 1;frame.logical_time = 0
	check("new_session_requires_explicit_reset",adapter.submit(frame).status=="QUEUED");await frames(3)
	check("new_session_applied",adapter.session_id=="new-test-session" and adapter.applied_sequence==1)
	# Explicit migration of an actual old replay.
	adapter.request_reset();await frames(3)
	check("legacy_v1_load",replay.load_replay("res://validation/replays/01_creation.json"))
	await frames(3);replay.play();await finish(200)
	check("legacy_v1_migrated_to_solid",manager.object_ids().size()==1 and manager.get_body(manager.object_ids()[0]).material_kind=="GREEN_SOLID")
	# Playback UI (signals execute the same handlers as clicks).
	lab.get_node("UI/Panel/Restart").pressed.emit();await frames(3)
	check("ui_restart",replay.cursor==0 and manager.object_ids().is_empty())
	lab.get_node("UI/Panel/Step").pressed.emit();await frames(3)
	check("ui_step",replay.cursor==1 and not replay.playing)
	lab.get_node("UI/Panel/Speed").item_selected.emit(1);check("ui_speed",replay.speed==0.5)
	lab.get_node("UI/Panel/Play").pressed.emit();await frames(8)
	lab.get_node("UI/Panel/Pause").pressed.emit();var cursor: int = replay.cursor;await frames(6)
	check("ui_pause",replay.cursor==cursor and not replay.playing)
	lab.get_node("UI/Panel/Files").item_selected.emit(4);await frames(6)
	check("ui_file_selection",replay.loaded_path.ends_with("05_green_blue.json") and replay.cursor==0)
	check("ui_file_selection_resets_session",manager.object_ids().is_empty() and adapter.session_id.is_empty())
	check("no_duplicate_collision_volumes",duplicate_samples==0,duplicate_samples)
	check("coherent_material_and_owner_identities",identity_errors==0,identity_errors)
	check("no_solid_penetrations_over_one_pixel",lab.physical_metrics.solid_penetration_frames_over_1px==0,lab.penetration_events)
	adapter.batch_result.disconnect(coherent);input_driver.queue_free()
	var failures: Array = rows.filter(func(row: Dictionary) -> bool:return not row.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"scenarios":scenarios,"support":supported_samples,"adapter":adapter.get_status(),"physical":lab.physical_metrics.duplicate(true),"contacts":contact.metrics.duplicate(true),"identity_errors":identity_errors,"duplicate_collision_samples":duplicate_samples,"update_us":manager.update_us.duplicate(),"human_tested":false}
	var file: FileAccess = FileAccess.open("res://validation/material_offline_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
	lab.set_meta("material_offline_results",result);print("MATERIAL_OFFLINE ",result.passed,"/",result.total," ",failures)
	return result
