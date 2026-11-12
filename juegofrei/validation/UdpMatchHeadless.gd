extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	create_timer(240).timeout.connect(func() -> void:push_error("UDP_MATCH_WATCHDOG");quit(2))
	var packed: PackedScene = load("res://scenes/IntegratedMatch.tscn")
	var boot: Node = packed.instantiate();boot.get_node("Sources").startup_mode = "UDP";boot.get_node("UdpTransport").port = 5026
	root.add_child(boot);current_scene = boot;await process_frame
	var startup: bool = boot.get_node("Sources").mode=="UDP" and boot.get_node("UdpTransport").listening and boot.get_node("SafetyFloor").enabled
	var startup_file: FileAccess
	for attempt: int in range(20):
		startup_file = FileAccess.open("res://validation/udp_startup.json",FileAccess.WRITE)
		if startup_file!=null:break
		await process_frame
	if startup_file==null:
		push_error("UDP_STARTUP_REPORT_WRITE_FAILED "+str(FileAccess.get_open_error()));quit(3);return
	startup_file.store_string(JSON.stringify({"startup_udp":startup}));startup_file.close()
	boot.get_node("Sources").select_mode("OFFLINE");boot.free();await process_frame
	var game: Node = packed.instantiate();root.add_child(game);current_scene = game;await process_frame
	var suite: RefCounted = load("res://validation/UdpMatchValidation.gd").new()
	var result: Dictionary = await suite.run(self,"headless")
	result.startup_udp = startup
	quit(0 if result.failures.is_empty() and startup else 1)
