extends RefCounted
const Protocol = preload("res://scripts/structure_udp/StructureProtocol.gd")
var rows: Dictionary = {}
func run(tree: SceneTree,label: String="before") -> Dictionary:
	var game: Node = tree.current_scene
	var shell: Node = game.get_node("GameShell");shell.show_selection();shell.selection.toggle_ready(0);shell.selection.toggle_ready(1)
	await tree.process_frame
	var source: Node = game.get_node("Sources");var gateway: Node = game.get_node("SceneSource");var adapter: Node = game.get_node("Adapter")
	var states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/performance_states.json"))
	var post_draw: Array = [];var previous: Array = [Time.get_ticks_usec()]
	var draw_callback: Callable = func() -> void:
		var now: int = Time.get_ticks_usec();post_draw.append((now-previous[0])/1000.0);previous[0] = now
	RenderingServer.frame_post_draw.connect(draw_callback)
	var viewport: RID = tree.root.get_viewport_rid()
	if RenderingServer.has_method("viewport_set_measure_render_time"):RenderingServer.call("viewport_set_measure_render_time",viewport,true)
	for number: String in states:
		source.select_mode("OFFLINE");game.get_node("Replay").pause();game.get_node("Replay").set_physics_process(false)
		adapter.request_reset()
		for i: int in range(4):await tree.physics_frame
		gateway.request_reset()
		for i: int in range(3):await tree.physics_frame
		for i: int in range(2):
			var player: Node = game.players[i];player.position = Vector2(100+i*40,550);player.velocity = Vector2.ZERO;player.combat.reset_after_respawn();player.combat.respawn_left = 0;player.combat.invulnerability_left = 0
		var protocol: RefCounted = Protocol.new()
		var measured: Dictionary = {"validation_ms":[],"submit_ms":[],"wall_tick_ms":[],"physics_monitor_ms":[],"process_monitor_ms":[],"render_cpu_ms":[],"render_gpu_ms":[]}
		var begin_apply: int = adapter.metrics.application_us.size();var begin_geom: int = game.get_node("DynamicGeometry").update_us.size();var last_tick: int = Time.get_ticks_usec()
		var begin_draw: int = post_draw.size()
		var event_driver: Node = load("res://validation/MaterialPhysicsTestInput.gd").new();game.add_child(event_driver)
		for frame_index: int in range(72):
			await tree.physics_frame
			if frame_index==12:begin_draw = post_draw.size()
			var now: int = Time.get_ticks_usec()
			if frame_index>=12:
				measured.wall_tick_ms.append((now-last_tick)/1000.0)
				measured.physics_monitor_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
				measured.process_monitor_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
				if DisplayServer.get_name()!="headless" and RenderingServer.has_method("viewport_get_measured_render_time_cpu"):
					measured.render_cpu_ms.append(RenderingServer.call("viewport_get_measured_render_time_cpu",viewport))
					measured.render_gpu_ms.append(RenderingServer.call("viewport_get_measured_render_time_gpu",viewport))
			last_tick = now
			if frame_index%30==0:
				for action: String in ["p1_light","p2_light"]:
					var input: InputEventAction = InputEventAction.new();input.action = action;input.pressed = true;event_driver.events.append(input)
			elif frame_index%30==1:Input.action_release("p1_light");Input.action_release("p2_light")
			var f: Dictionary = states[number].duplicate(true)
			f.sequence = frame_index+1;f.logical_time = frame_index/30.0;f.sent_unix_ms = Time.get_unix_time_from_system()*1000
			for c: Dictionary in f.structures:c.position[0] += sin(frame_index/15.0)*3
			var start: int = Time.get_ticks_usec();var valid: Dictionary = protocol.accept_snapshot(f,Time.get_ticks_msec())
			if frame_index>=12:measured.validation_ms.append((Time.get_ticks_usec()-start)/1000.0)
			start = Time.get_ticks_usec()
			var result: Dictionary = gateway.submit(f) if valid.get("complete",false) else {"status":"INVALID"}
			if frame_index>=12:measured.submit_ms.append((Time.get_ticks_usec()-start)/1000.0)
			if result.status=="INVALID":push_error("PERFORMANCE_INVALID "+str(valid))
		for i: int in range(3):await tree.physics_frame
		event_driver.queue_free()
		measured.application_us = adapter.metrics.application_us.slice(begin_apply)
		measured.draw_intervals_ms = post_draw.slice(begin_draw)
		measured.geometry_update_us = game.get_node("DynamicGeometry").update_us.slice(begin_geom)
		measured.active_regions = game.get_node("DynamicGeometry").object_ids().size()
		measured.shapes = 0
		for id: StringName in game.get_node("DynamicGeometry").object_ids():measured.shapes += game.get_node("DynamicGeometry").get_body(id).colliders.size()
		measured.backend = adapter.get_status();measured.penetrations = game.penetrations
		rows[number] = measured
	RenderingServer.frame_post_draw.disconnect(draw_callback)
	var result: Dictionary = {"label":label,"counts":rows,"draw_intervals_ms":post_draw,"graphical":DisplayServer.get_name()!="headless","monitor_note":"Performance monitors may repeat cached values; frame intervals include pacing and debugger. GPU values require renderer support."}
	var file: FileAccess = FileAccess.open("res://validation/performance_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	game.set_meta("performance_results",result);print("PERFORMANCE_COMPLETE ",label)
	return result
