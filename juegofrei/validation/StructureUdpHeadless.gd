extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var suite: RefCounted = load("res://validation/StructureUdpValidation.gd").new()
	var result: Dictionary = await suite.run()
	quit(0 if result.failures.is_empty() else 1)
