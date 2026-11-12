extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	create_timer(120).timeout.connect(func() -> void:push_error("CALIBRATION_PREP_TIMEOUT");quit(2))
	var game: Node = load("res://scenes/IntegratedMatch.tscn").instantiate();root.add_child(game);current_scene = game;await process_frame
	var suite: RefCounted = load("res://validation/CalibrationPreparationValidation.gd").new()
	var result: Dictionary = await suite.run(self,"headless")
	quit(0 if result.failures.is_empty() else 1)
