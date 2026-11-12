extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(240).timeout.connect(func() -> void:push_error("MATERIAL_OFFLINE_WATCHDOG");quit(2))
	var lab: Node = load("res://scenes/MaterialOfflineLab.tscn").instantiate()
	root.add_child(lab);current_scene = lab
	await process_frame
	var suite: RefCounted = load("res://validation/MaterialOfflineValidation.gd").new()
	var result: Dictionary = await suite.run(self,"headless")
	quit(0 if result.failures.is_empty() else 1)
