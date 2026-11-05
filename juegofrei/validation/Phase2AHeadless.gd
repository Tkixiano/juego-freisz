extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame
	var suite: RefCounted = load("res://validation/Phase2AValidation.gd").new()
	var result: Dictionary = await suite.run(self,"headless")
	quit(0 if result.failures.is_empty() else 1)
