extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game: Node = load("res://scenes/IntegratedMatch.tscn").instantiate();root.add_child(game);current_scene = game;await process_frame
	var suite: RefCounted = load("res://validation/PerformanceValidation.gd").new()
	await suite.run(self,"before" if OS.get_cmdline_user_args().has("before") else "after")
	quit()
