extends RefCounted
var tree: SceneTree
var lab: Node
var replay: Node
var adapter: Node
var manager: Node
var player: CharacterBody2D
var rows: Array[Dictionary] = []
var scenarios: Array[Dictionary] = []
var physical: Dictionary = {"max_overlap_px2":0.0,"max_step_px":0.0,"supported_merge_frames":0,"supported_split_frames":0,"floor_losses":0,"duplicate_collision_samples":0}

func frames(n: int) -> void:
	for i: int in range(n):
		await tree.physics_frame
		await tree.process_frame

func check(name: String,passed: bool,details: Variant = "") -> void:
	rows.append({"name":name,"passed":passed,"details":details})
	if not passed: push_error("OFFLINE_QA "+name+": "+str(details))

func place(point: Vector2) -> void:
	player.position = point
	player.velocity = Vector2.ZERO
	player.combat.reset_after_respawn()
	player.combat.respawn_left = 0
	player.combat.invulnerability_left = 0
	player.force_update_transform()
	player.reset_physics_interpolation()

func load_case(name: String) -> void:
	replay.pause()
	adapter.request_reset()
	await frames(3)
	check(name+"_load",replay.load_replay("res://validation/replays/"+name+".json"),replay.errors)
	await frames(3)

func overlap() -> float:
	var box: PackedVector2Array = player.global_transform*PackedVector2Array([Vector2(-20,-20),Vector2(20,-20),Vector2(20,20),Vector2(-20,20)])
	var area: float = 0
	for id: StringName in manager.object_ids():
		var body: Node2D = manager.get_body(id)
		for part: PackedVector2Array in body.convex_parts:
			area += manager.CompoundValidator.intersection_area(box,body.global_transform*part)
	return area

func no_duplicate_geometry() -> bool:
	var ids: Array[StringName] = manager.object_ids()
	for i: int in range(ids.size()):
		for j: int in range(i+1,ids.size()):
			var a: Node2D = manager.get_body(ids[i])
			var b: Node2D = manager.get_body(ids[j])
			for pa: PackedVector2Array in a.convex_parts:
				for pb: PackedVector2Array in b.convex_parts:
					if manager.CompoundValidator.intersection_area(a.global_transform*pa,b.global_transform*pb)>0.001: return false
	return true

func run(scene_tree: SceneTree,label: String="mcp") -> Dictionary:
	tree = scene_tree
	lab = tree.current_scene
	replay = lab.get_node("Replay")
	adapter = lab.get_node("Adapter")
	manager = lab.get_node("DynamicGeometry")
	player = lab.get_node("Player")
	await frames(8)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/replays/manifest.json"))
	for entry: Dictionary in manifest.scenarios:
		lab.set_meta("offline_progress",entry.scenario)
		place(Vector2(1100,100))
		await load_case(entry.scenario)
		var before: Dictionary = adapter.metrics.duplicate(true)
		replay.set_speed(2.0)
		replay.play()
		var ticks: int = 0
		while (replay.cursor<replay.frames.size() or not adapter.pending_frame.is_empty()) and ticks<entry.frames*4+100:
			await frames(1)
			ticks += 1
			if not no_duplicate_geometry(): physical.duplicate_collision_samples += 1
		replay.pause()
		var rejected: int = adapter.metrics.rejected-before.rejected
		var expected_rejects: int = 1 if entry.scenario in ["13_duplicate","14_out_of_order","15_invalid_geometry"] else 0
		var result: Dictionary = {"scenario":entry.scenario,"frames":entry.frames,"cursor":replay.cursor,"received":adapter.metrics.received-before.received,"applied":adapter.metrics.applied-before.applied,"rejected":rejected,"deferred":adapter.metrics.deferred-before.deferred,"ticks":ticks,"active_objects":manager.object_ids().size(),"merges":adapter.metrics.merges-before.merges,"splits":adapter.metrics.splits-before.splits}
		scenarios.append(result)
		check(entry.scenario+"_complete",replay.cursor==replay.frames.size() and adapter.pending_frame.is_empty(),result)
		check(entry.scenario+"_expected_rejections",rejected==expected_rejects,result)
		check(entry.scenario+"_full_state_recovery",manager.object_ids().size()==replay.frames[-1].structures.size(),result)
	check("all_twenty_scenarios",scenarios.size()==20)
	check("no_duplicate_collision_at_physics_boundaries",physical.duplicate_collision_samples==0,physical)
	await test_controls()
	await test_atomic_rejection_and_versions()
	await test_occupied()
	await test_carrier()
	var failed: Array = rows.filter(func(r: Dictionary)->bool:return not r.passed)
	var status: Dictionary = adapter.get_status()
	var result: Dictionary = {"label":label,"total":rows.size(),"passed":rows.size()-failed.size(),"failures":failed,"scenarios":scenarios,"physical":physical,"adapter":status,"replayer_errors":replay.errors.duplicate(true),"rows":rows,"synthetic_only":true,"graphical_input_tests_available":DisplayServer.get_name()!="headless"}
	lab.set_meta("offline_results",result)
	lab.set_meta("offline_progress","complete")
	var file: FileAccess = FileAccess.open("res://validation/offline_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("OFFLINE_QA ",JSON.stringify({"label":label,"passed":result.passed,"total":result.total,"failures":failed}))
	return result

func test_controls() -> void:
	place(Vector2(1100,100))
	await load_case("02_movement")
	replay.step()
	await frames(3)
	check("step_exactly_one_frame",replay.cursor==1 and not replay.playing)
	replay.play()
	await frames(14)
	replay.pause()
	var cursor: int = replay.cursor
	var poses: Dictionary = {}
	for id: StringName in manager.object_ids(): poses[id] = manager.get_body(id).transform
	await frames(8)
	check("pause_stops_cursor",replay.cursor==cursor)
	var same: bool = true
	for id: StringName in poses:
		if manager.get_body(id).transform!=poses[id]: same = false
	check("pause_freezes_platform_motion",same)
	check("speed_configurable",replay.set_speed(0.5) and replay.set_speed(2.0))
	check("invalid_speed_rejected",not replay.set_speed(NAN) and not replay.set_speed(0))
	replay.restart()
	await frames(3)
	check("restart_clears_session",replay.cursor==0 and manager.object_ids().is_empty() and adapter.high_sequence==0)
	check("missing_file_is_replayer_error",not replay.load_replay("res://validation/replays/does_not_exist.json"))
	check("replayer_state_query",replay.get_status().frames>0)
	# Input.parse_input_event does not route these GUI clicks in headless here.
	# The same assertions run in the actual graphical MCP game, never fake signals.
	if DisplayServer.get_name()=="headless": return
	await load_case("02_movement")
	await click(lab.get_node("UI/Panel/Play"))
	check("play_button_real_mouse_input",replay.playing)
	await click(lab.get_node("UI/Panel/Pause"))
	check("pause_button_real_mouse_input",not replay.playing)
	await click(lab.get_node("UI/Panel/Restart"))
	await frames(3)
	check("restart_button_real_mouse_input",replay.cursor==0)
	await click(lab.get_node("UI/Panel/Step"))
	await frames(2)
	check("step_button_real_mouse_input",replay.cursor==1 and not replay.playing)
	await click(lab.get_node("UI/Panel/Files"))
	var popup: PopupMenu = lab.get_node("UI/Panel/Files").get_popup()
	# PopupMenu starts with no keyboard item focused; first DOWN selects item 0.
	for i: int in range(5): await key(KEY_DOWN,popup)
	await key(KEY_ENTER,popup)
	await frames(5)
	check("file_selector_real_keyboard_input",replay.loaded_path.ends_with("05_two.json"),replay.loaded_path)
	await click(lab.get_node("UI/Panel/Speed"))
	popup = lab.get_node("UI/Panel/Speed").get_popup()
	await key(KEY_DOWN,popup)
	await key(KEY_ENTER,popup)
	check("speed_selector_real_keyboard_input",is_equal_approx(replay.speed,0.25),replay.speed)

func key(code: Key,popup: PopupMenu = null) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		if popup!=null: event.window_id = popup.get_window_id()
		Input.parse_input_event(event)
		await frames(2)

func run_ui_probe(scene_tree: SceneTree) -> void:
	tree = scene_tree
	lab = tree.current_scene
	replay = lab.get_node("Replay")
	adapter = lab.get_node("Adapter")
	manager = lab.get_node("DynamicGeometry")
	player = lab.get_node("Player")
	await frames(8)
	await test_controls()
	lab.set_meta("ui_probe",rows)

func click(button: Control) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await frames(1)
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func test_atomic_rejection_and_versions() -> void:
	await load_case("05_two")
	for i: int in range(5): replay.step();await frames(2)
	var source: Dictionary = replay.frames[replay.cursor-1].duplicate(true)
	var ids: Array[StringName] = manager.object_ids()
	check("atomic_baseline_two",ids.size()==2)
	check("version_ledger_survives_commits",adapter.ledger.size()==2)
	check("legacy_producer_cannot_mutate_transaction_backend",not manager.update_transform(ids[0],Vector2(999,999),0))
	var initial: Vector2 = manager.get_body(ids[0]).position
	var invalid: Dictionary = source.duplicate(true)
	invalid.sequence = 100
	invalid.logical_time = 10
	invalid.structures[0].position[0] += 60
	invalid.structures[1].geometry_version += 1
	invalid.structures[1].convex_parts = [[[0,0],[1,0],[2,0]]]
	check("invalid_batch_rejected",adapter.submit(invalid).status=="REJECTED")
	await frames(4)
	check("no_partial_pose_or_retirement",manager.get_body(ids[0]).position==initial and manager.object_ids()==ids)
	var good: Dictionary = source.duplicate(true)
	good.sequence = 101;good.logical_time = 11
	check("full_snapshot_recovers_after_rejection",adapter.submit(good).status=="QUEUED")
	await frames(3)
	check("duplicate_state_rejected",adapter.submit(good).status=="REJECTED")
	var old: Dictionary = good.duplicate(true)
	old.sequence = 102;old.logical_time = 12
	old.structures[0].geometry_version = 0
	check("old_geometry_rejected",adapter.submit(old).status=="REJECTED")
	var reused: Dictionary = good.duplicate(true)
	reused.sequence = 103;reused.logical_time = 13
	reused.identity_epochs[reused.structures[0].id] += 1
	check("active_identity_epoch_change_rejected",adapter.submit(reused).status=="REJECTED")
	# A newer sequence with missing source events still restores complete geometry.
	good.sequence = 110;good.logical_time = 20;good.events = []
	check("sequence_gap_full_recovery",adapter.submit(good).status=="QUEUED")
	await frames(3)
	var higher: Dictionary = good.duplicate(true)
	higher.sequence = 111;higher.logical_time = 21
	higher.structures[0].geometry_version = 2
	check("newer_geometry_version_accepted",adapter.submit(higher).status=="QUEUED")
	await frames(3)
	var lower: Dictionary = good.duplicate(true)
	lower.sequence = 112;lower.logical_time = 22
	check("positive_old_geometry_version_rejected",adapter.submit(lower).reason=="geometry_version_regression_or_reused_version")
	check("version_ledger_preserves_high_watermark",adapter.ledger[higher.structures[0].id].version==2)
	# Recover directly from a state whose identities already have epoch > 1.
	var future: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/replays/07_split.json")).frames[-1]
	adapter.request_reset()
	await frames(3)
	check("full_state_recovery_without_event_history",adapter.submit(future).status=="QUEUED")
	await frames(3)
	check("recovered_snapshot_has_two_objects",manager.object_ids().size()==2)

func test_occupied() -> void:
	for name: String in ["16_occupied_change","17_occupied_merge","18_occupied_split"]:
		place(Vector2(170,240))
		await load_case(name)
		replay.set_speed(1.0)
		replay.play()
		var previous: Vector2 = player.position
		var ticks: int = 0
		var floor_seen: bool = false
		var floor_lost: int = 0
		var deferred_start: int = adapter.metrics.deferred
		while (replay.cursor<replay.frames.size() or not adapter.pending_frame.is_empty()) and ticks<400:
			await frames(1)
			ticks += 1
			physical.max_step_px = maxf(physical.max_step_px,player.position.distance_to(previous))
			previous = player.position
			physical.max_overlap_px2 = maxf(physical.max_overlap_px2,overlap())
			if player.is_on_floor(): floor_seen = true
			elif floor_seen: floor_lost += 1
			if name=="16_occupied_change" and not adapter.pending_frame.is_empty() and adapter.metrics.deferred>deferred_start: break
		replay.pause()
		if name=="16_occupied_change":
			check("occupied_geometry_deferred",adapter.metrics.deferred>deferred_start and not adapter.pending_frame.is_empty(),manager.last_conflict)
			check("deferred_keeps_character_supported",player.is_on_floor() and overlap()<0.01)
			var held: int = adapter.applied_sequence
			await frames(8)
			check("deferred_batch_does_not_partially_commit",adapter.applied_sequence==held)
			# Clear the conflict using actual movement input, never auto-teleport.
			Input.action_press("p1_right")
			for i: int in range(90):
				await frames(1)
				if adapter.pending_frame.is_empty(): break
			Input.action_release("p1_right")
			check("deferred_commits_after_player_walks_clear",adapter.pending_frame.is_empty())
		else:
			check(name+"_complete",replay.cursor==replay.frames.size() and adapter.pending_frame.is_empty())
			check(name+"_never_loses_support",floor_seen and floor_lost==0,{"floor_losses":floor_lost})
			check(name+"_expected_resulting_objects",manager.object_ids().size()==(1 if name=="17_occupied_merge" else 2))
			if name=="17_occupied_merge":physical.supported_merge_frames = ticks
			else: physical.supported_split_frames = ticks
		physical.floor_losses += floor_lost
	check("occupied_no_penetration",physical.max_overlap_px2<0.01,physical)
	check("occupied_no_unexpected_teleport",physical.max_step_px<12,physical)

func test_carrier() -> void:
	place(Vector2(170,240))
	await load_case("02_movement")
	for i: int in range(5): replay.step();await frames(2)
	await frames(60)
	check("transactional_carrier_lands",player.is_on_floor())
	var id: StringName = manager.object_ids()[0]
	var body: Node2D = manager.get_body(id)
	var start_player: Vector2 = player.position
	var start_body: Vector2 = body.position
	var builds: int = body.shape_builds
	var floor_count: int = 0
	var ticks: int = 0
	replay.set_speed(1.0);replay.play()
	while replay.cursor<replay.frames.size() and ticks<200:
		await frames(1)
		ticks += 1
		if player.is_on_floor():floor_count += 1
		physical.max_overlap_px2 = maxf(physical.max_overlap_px2,overlap())
	replay.pause()
	physical.carrier_frames = ticks
	physical.carrier_floor_frames = floor_count
	physical.carrier_error_px = ((player.position-start_player)-(body.position-start_body)).length()
	check("transactional_carrier_preserves_support",floor_count==ticks,physical)
	check("transactional_carrier_no_geometry_rebuild",body.shape_builds==builds)
	check("transactional_carrier_offset",physical.carrier_error_px<2.5,physical)
