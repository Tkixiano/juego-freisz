extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	create_timer(180).timeout.connect(func() -> void:push_error("UDP_LIVE_WATCHDOG");quit(2))
	var game: Node = load("res://scenes/IntegratedMatch.tscn").instantiate();root.add_child(game);current_scene = game;await process_frame
	var suite: RefCounted = load("res://validation/UdpMatchLiveValidation.gd").new()
	var mode: String = "load" if OS.get_cmdline_user_args().has("load") or OS.get_cmdline_user_args().has("load120") else "faults"
	var regions: int = 32
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("regions"):regions = arg.trim_prefix("regions").to_int()
	var result: Dictionary = await suite.run(self,mode,5027,(12 if regions>=32 else 6) if mode=="load" else 15,120 if OS.get_cmdline_user_args().has("load120") else 30,regions)
	quit(0 if result.failures.is_empty() else 1)
