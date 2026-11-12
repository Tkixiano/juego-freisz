extends RefCounted
var rows: Array = []
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
	if not ok:push_error("UDP_MATCH_LIVE "+name+" "+str(detail))
func run(tree: SceneTree,label: String="faults",port: int=5015,duration: float=15,offered_hz: float=30,expected_regions: int=32) -> Dictionary:
	var game: Node = tree.current_scene
	var draw_intervals_ms: Array = [];var previous_draw: Array = [Time.get_ticks_usec()]
	var draw_probe: Callable = func() -> void:
		var now: int = Time.get_ticks_usec();draw_intervals_ms.append((now-previous_draw[0])/1000.0);previous_draw[0] = now
	RenderingServer.frame_post_draw.connect(draw_probe)
	var shell: Node = game.get_node("GameShell");shell.show_selection();shell.selection.toggle_ready(0);shell.selection.toggle_ready(1)
	await tree.process_frame
	var sources: Node = game.get_node("Sources");var receiver: Node = game.get_node("UdpTransport")
	receiver.port = port;sources.select_mode("UDP")
	var python: String = "C:/Users/tkixi/AppData/Local/Programs/Python/Python314/python.exe"
	var root: String = ProjectSettings.globalize_path("res://../")
	var args: PackedStringArray = [root+"tests/udp_match_live_sender.py","--port",str(port),"--mode",label,"--seconds",str(duration),"--hz",str(offered_hz),"--regions",str(expected_regions),"--stats",root+"artifacts/phase3d/live_"+label+"_sender.json"]
	var pid: int = OS.create_process(python,args,false)
	check("python_process_started",pid>0)
	var states: Dictionary = {};var regions_peak: int = 0;var trade_done: bool = false;var trade_checked: bool = false;var trade_tick: int = 0
	var driver: Node = load("res://validation/MaterialPhysicsTestInput.gd").new();game.add_child(driver)
	if label=="load":
		for p: Node in game.players:p.collision_mask = 0;p.set_physics_process(false)
	var until: int = Time.get_ticks_msec()+int((duration+1.2)*1000)
	var physics_frame_us: Array = []
	var first_rx: int = -1;var bootstrap_deadline: int = Time.get_ticks_msec()+15000
	until = bootstrap_deadline+int((duration+1.2)*1000)
	while Time.get_ticks_msec()<until:
		await tree.physics_frame
		physics_frame_us.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000.0)
		if first_rx<0 and receiver.protocol.metrics.accepted>0:
			first_rx = Time.get_ticks_msec();until = first_rx+int((duration+1.2)*1000)
		if first_rx<0 and Time.get_ticks_msec()>bootstrap_deadline:break
		states[game.get_node("SceneSource").scene_state] = true
		regions_peak = maxi(regions_peak,game.get_node("DynamicGeometry").object_ids().size())
		if label=="faults" and not trade_done and regions_peak==3:
			trade_done = true;trade_tick = Engine.get_physics_frames()
			for index: int in range(2):
				var p: Node = game.players[index];p.position = Vector2(490+index*40,460);p.velocity = Vector2.ZERO;p.reset_physics_interpolation();p.force_update_transform();p.combat.reset_after_respawn();p.combat.respawn_left = 0;p.combat.invulnerability_left = 0
		if trade_done and Engine.get_physics_frames()==trade_tick+5:
			for name: String in ["p1_light","p2_light"]:
				var event: InputEventAction = InputEventAction.new();event.action = name;event.pressed = true;driver.events.append(event)
		if trade_done and not trade_checked and Engine.get_physics_frames()>=trade_tick+30:
			trade_checked = true
			check("real_udp_two_player_trade",game.players[0].combat.damage_model.percent==6 and game.players[1].combat.damage_model.percent==6,[game.players[0].combat.damage_model.percent,game.players[1].combat.damage_model.percent])
			Input.action_release("p1_light");Input.action_release("p2_light")
			for index: int in range(2):
				var p: Node = game.players[index];p.position = Vector2(510,460) if index==0 else Vector2(1000,-100);p.velocity = Vector2.ZERO;p.force_update_transform();p.combat.reset_after_respawn();p.combat.respawn_left = 0;p.combat.invulnerability_left = 0
				if index==1:p.collision_mask = 0;p.set_physics_process(false)
	if OS.is_process_running(pid):OS.kill(pid)
	var receiver_status: Dictionary = receiver.get_status();var status: Dictionary = sources.get_status()
	check("real_udp_received",receiver_status.metrics.accepted>10,receiver_status.metrics.accepted)
	check("real_udp_physical_applied",status.metrics.applied>0,status.metrics.applied)
	check("real_udp_bounded_queue",status.queue_depth<=2 and status.metrics.queue_peak<=2)
	check("real_udp_no_deep_penetrations",game.penetrations==0,game.penetrations)
	check("real_udp_full_final_state",game.get_node("DynamicGeometry").object_ids().size()==(expected_regions if label=="load" else 3),game.get_node("DynamicGeometry").object_ids().size())
	if label=="faults":
		for state: String in ["SCENE_ACTIVE","SCENE_EMPTY","SCENE_STALE","SCENE_ERROR"]:check("real_seen_"+state,states.has(state))
		check("real_merge_split",receiver_status.metrics.merges>0 and receiver_status.metrics.splits>0)
		check("real_duplicate_rejected",receiver_status.rejections.has("duplicate_or_old_sequence"))
		check("real_obsolete_session_rejected",receiver_status.rejections.has("obsolete_session"))
		check("real_restart_sessions",receiver_status.metrics.sessions>=4,receiver_status.metrics.sessions)
	else:check("real_high_load_%d_regions"%expected_regions,regions_peak==expected_regions,regions_peak)
	driver.queue_free()
	RenderingServer.frame_post_draw.disconnect(draw_probe)
	var failures: Array = rows.filter(func(r: Dictionary) -> bool:return not r.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"receiver":receiver_status,"bridge":status,"backend":game.get_node("Adapter").get_status(),"floor":game.get_node("SafetyFloor").metrics.duplicate(),"states":states,"regions_peak":regions_peak,"geometry_update_us":game.get_node("DynamicGeometry").update_us.duplicate(),"match_update_us":game.update_us.duplicate(),"unexpected_support_losses":game.unexpected_support_losses,"physics_frame_us":physics_frame_us,"draw_intervals_ms":draw_intervals_ms,"offered_hz":offered_hz,"real_socket":true,"human_tested":false}
	var file: FileAccess = FileAccess.open("res://validation/udp_match_live_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
	game.set_meta("udp_live_results",result);print("UDP_MATCH_LIVE ",label," ",result.passed,"/",result.total," ",failures)
	return result
