extends RefCounted
var rows: Array = []
var tree: SceneTree
var game: Node
var gateway: Node
var adapter: Node
var manager: Node
var max_vertex_error_px: float = 0
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
	if not ok:push_error("CALIBRATION_PREP "+name+" "+str(detail))
func frames(n: int=4) -> void:
	for i: int in range(n):await tree.physics_frame
func fresh() -> void:
	for p: Node in game.players:p.collision_mask = 0;p.set_physics_process(false);p.position = Vector2(100,-100)
	game.get_node("Sources").select_mode("OFFLINE")
	game.get_node("Replay").pause();adapter.request_reset();gateway.request_reset();await frames(5)
func send(input: Dictionary) -> Dictionary:
	var last: Dictionary = {}
	for i: int in range(4):
		var f: Dictionary = input.duplicate(true);f.sequence = i+1;f.logical_time = i*.05
		last = gateway.submit(f);await frames(4)
	return last
func run(scene_tree: SceneTree,label: String="headless") -> Dictionary:
	tree = scene_tree;game = tree.current_scene;gateway = game.get_node("SceneSource");adapter = game.get_node("Adapter");manager = game.get_node("DynamicGeometry")
	var shell: Node = game.get_node("GameShell");shell.show_selection();shell.selection.toggle_ready(0);shell.selection.toggle_ready(1);await frames(2)
	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/calibration_preparation_cases.json"))
	for name: String in ["solid","three","hole","corner","perspective_solid","perspective_hole"]:
		await fresh();var result: Dictionary = await send(cases[name])
		check(name+"_accepted",adapter.applied_sequence>0,{"result":result,"errors":adapter.errors})
		if adapter.logical_active.is_empty():continue
		check(name+"_no_fixture_offset",adapter.logical_active.values()[0].position==cases[name].structures[0].position)
		var expected_regions: int = 0
		for c: Dictionary in cases[name].structures:
			for r: Dictionary in c.material_regions:
				expected_regions += 1
				var body: Node = manager.get_body(StringName(r.region_id))
				if body==null:continue
				check(name+"_material_"+r.region_id,body.material_kind==r.material)
				for i: int in range(r.convex_parts.size()):
					for j: int in range(r.convex_parts[i].size()):
						var expected_x: float = float(r.convex_parts[i][j][0])+float(c.position[0])
						var expected_y: float = float(r.convex_parts[i][j][1])+float(c.position[1])
						var actual: Vector2 = body.global_transform*body.convex_parts[i][j]
						max_vertex_error_px = maxf(max_vertex_error_px,sqrt(pow(float(actual.x)-expected_x,2)+pow(float(actual.y)-expected_y,2)))
		check(name+"_region_count",manager.object_ids().size()==expected_regions)
		check(name+"_projection_error",max_vertex_error_px<0.001,max_vertex_error_px)
		if name=="hole":check("holes_retained",adapter.logical_active.values()[0].regions[0].holes.size()==1)
	# Old fixtures retain their original offset; the default game is unaffected.
	await fresh();var old: Dictionary = cases.solid.duplicate(true);old.erase("spatial_mapping")
	for c: Dictionary in old.structures:c.mapping = "IDENTITY_SYNTHETIC_LAB_ONLY"
	await send(old)
	check("legacy_offset_retained",adapter.logical_active.values()[0].position[0]==old.structures[0].position[0]+300)
	await fresh();await send(cases.solid)
	var original_ids: Array = manager.object_ids()
	var bad: Dictionary = cases.solid.duplicate(true);bad.sequence = 5;bad.logical_time = 1;bad.erase("spatial_mapping")
	check("missing_metadata_rejected",gateway.submit(bad).status=="REJECTED")
	bad = cases.solid.duplicate(true);bad.sequence = 6;bad.logical_time = 2;bad.spatial_mapping.calibration_signature = "b".repeat(64)
	check("changed_calibration_requires_reset",gateway.submit(bad).status=="REJECTED")
	bad = cases.solid.duplicate(true);bad.sequence = 7;bad.logical_time = 3;bad.spatial_mapping.arena_size = [1920,1080]
	check("wrong_arena_rejected",gateway.submit(bad).status=="REJECTED")
	bad = cases.solid.duplicate(true);bad.sequence = 8;bad.logical_time = 3.5;bad.structures[0].position[0] += 2000
	check("out_of_arena_geometry_rejected",gateway.submit(bad).status=="REJECTED")
	check("rejections_preserve_physics",manager.object_ids()==original_ids)
	check("invalid_mapping_sets_error",gateway.scene_state=="SCENE_ERROR")
	bad = cases.perspective_hole.duplicate(true);bad.session_id = cases.solid.session_id;bad.sequence = 8;bad.logical_time = 4
	var changed_mapping: Dictionary = gateway.submit(bad)
	check("calibration_switch_requires_reset",changed_mapping.status=="REJECTED" and changed_mapping.reason=="mapping_change_requires_source_reset" and manager.object_ids()==original_ids)
	# Return the source to its healthy last valid state without changing geometry.
	await fresh();await send(cases.solid);original_ids = manager.object_ids()
	# Player collision in the correctly mapped position, using the original Player.
	var p: Node = game.players[0];var c: Dictionary = cases.solid.structures[0]
	p.position = Vector2(c.position[0],350);p.velocity = Vector2.ZERO;p.collision_mask = 3;p.set_physics_process(true)
	p.combat.reset_after_respawn();p.combat.respawn_left = 0;p.combat.invulnerability_left = 0;p.force_update_transform();p.reset_physics_interpolation()
	await frames(75)
	check("player_lands_on_calibrated_surface",p.is_on_floor() and p.position.y<400,p.position)
	p.collision_mask = 0;p.set_physics_process(false)
	gateway.set_health("SCENE_STALE");await frames();check("stale_keeps_colliders",manager.object_ids()==original_ids)
	gateway.set_health("SCENE_ERROR");await frames();check("error_keeps_colliders",manager.object_ids()==original_ids)
	check("no_deep_penetrations",game.penetrations==0,game.penetrations)
	var notch: PackedVector2Array = PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,8),Vector2(5,10),Vector2(6,8),Vector2(6,0),Vector2(20,0),Vector2(20,20),Vector2(0,20)])
	var chord: PackedVector2Array = PackedVector2Array([Vector2(1,8),Vector2(19,8),Vector2(10,18)])
	check("concave_vertex_chord_not_contained",not manager.CompoundValidator._contained(chord,notch))
	await fresh()
	var receiver: Node = game.get_node("UdpTransport");receiver.port = 5031
	game.get_node("Sources").select_mode("UDP");await frames(3)
	var script: String = ProjectSettings.globalize_path("res://../tests/send_calibrated_synthetic.py")
	var pid: int = OS.create_process("C:/Users/tkixi/AppData/Local/Programs/Python/Python314/python.exe",PackedStringArray([script,"--port","5031"]),false)
	var states: Dictionary = {};var had_geometry: bool = false;var geometry_lost: bool = false
	var until: int = Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<until:
		await tree.physics_frame
		states[gateway.scene_state] = true
		if manager.object_ids().size()==3:had_geometry = true
		if had_geometry and manager.object_ids().size()!=3:geometry_lost = true
	if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	check("calibrated_python_udp_received",receiver.protocol.metrics.accepted>10)
	check("calibrated_udp_reaches_physics",had_geometry and not geometry_lost)
	check("calibrated_udp_error_and_stale",states.has("SCENE_ERROR") and states.has("SCENE_STALE"))
	check("calibrated_udp_restart_session",receiver.protocol.metrics.sessions>=2)
	check("calibrated_udp_materials",manager.object_ids().size()==3)
	check("camera_fault_never_empty",not states.has("SCENE_EMPTY"))
	var failures: Array = rows.filter(func(r: Dictionary) -> bool:return not r.passed)
	var result: Dictionary = {"label":label,"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"maximum_vertex_error_px":max_vertex_error_px,"synthetic_only":true,"gateway_metrics":gateway.metrics,"backend":adapter.get_status()}
	var file: FileAccess = FileAccess.open("res://validation/calibration_preparation_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	game.set_meta("calibration_preparation_results",result);print("CALIBRATION_PREP ",result.passed,"/",result.total," ",failures)
	return result
