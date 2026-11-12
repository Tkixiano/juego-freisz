extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	create_timer(240).timeout.connect(func() -> void:push_error("INTEGRATED_WATCHDOG");quit(2))
	var game: Node = load("res://scenes/IntegratedMatch.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame
	var suite: RefCounted = load("res://validation/IntegratedMatchValidation.gd").new()
	var result: Dictionary = await suite.run(self,"headless")
	quit(0 if result.failures.is_empty() else 1)
