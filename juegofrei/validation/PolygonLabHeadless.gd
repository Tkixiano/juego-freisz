extends SceneTree
## Repeatable synthetic physics harness. --fixed-fps 60 is simulation, not FPS measurement.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/PolygonCollisionLab.tscn")
	var lab: Node = packed.instantiate()
	root.add_child(lab)
	current_scene = lab
	await process_frame
	var suite: RefCounted = load("res://validation/PolygonLabValidation.gd").new()
	await suite.run(self,"headless")
	var result: Dictionary = lab.get_meta("polygon_validation_results")
	quit(0 if result.failures.is_empty() else 1)
