extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var lab: Node = load("res://scenes/CompoundGeometryLab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await process_frame
	var suite: RefCounted = load("res://validation/CompoundGeometryValidation.gd").new()
	var result: Dictionary = await suite.run(self,"headless")
	quit(0 if result.failures.is_empty() else 1)
