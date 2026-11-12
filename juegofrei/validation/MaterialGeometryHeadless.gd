extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var suite: RefCounted = load("res://validation/MaterialGeometryValidation.gd").new()
	var result: Dictionary = suite.run()
	quit(0 if result.failures.is_empty() else 1)
