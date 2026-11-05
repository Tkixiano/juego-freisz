extends RefCounted

func frames(tree: SceneTree,count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = code
	release.pressed = false
	Input.parse_input_event(release)

func run(tree: SceneTree) -> void:
	var lab: Node = tree.current_scene
	var manager: Node = lab.get_node("DynamicGeometry")
	lab.reset_fixture()
	await frames(tree,10)
	var checks: Dictionary = {}
	checks["fixture_has_three_original_silhouettes"] = manager.object_ids().size()==3
	key(KEY_F5)
	await frames(tree,140)
	checks["f5_starts_reproducible_sequence"] = lab.sequence_running and manager.get_body("green_A").position.distance_to(Vector2(350,400))<1
	await frames(tree,150)
	checks["sequence_moves_and_rotates"] = manager.get_body("green_A").position.distance_to(Vector2(350,350))<1 and absf(manager.get_body("blue_B").rotation-.2)<.01
	await frames(tree,150)
	checks["sequence_replaces_only_c_geometry"] = manager.get_state("green_C").parts>1 and manager.get_state("green_A").geometry_revision==1
	await frames(tree,150)
	checks["sequence_disables_collision"] = not manager.get_state("green_C").collision_enabled
	await frames(tree,150)
	checks["sequence_removes_object"] = not manager.has_object("green_C")
	await frames(tree,40)
	checks["sequence_finishes"] = not lab.sequence_running
	key(KEY_F6)
	await frames(tree,10)
	checks["f6_restores_fixture_without_duplicates"] = manager.object_ids().size()==3 and manager.get_state("green_C").parts==1 and manager.get_state("green_C").collision_enabled
	var passed: int = 0
	for value: bool in checks.values():
		if value:
			passed += 1
	var report: Dictionary = {"total":checks.size(),"passed":passed,"checks":checks}
	var file: FileAccess = FileAccess.open("res://validation/polygon_lab_sequence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	lab.set_meta("polygon_sequence_results",report)
