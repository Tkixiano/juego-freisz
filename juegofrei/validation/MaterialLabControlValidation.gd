extends RefCounted
var rows: Array = []
func frames(tree: SceneTree,n: int) -> void:
	for i: int in range(n): await tree.physics_frame
func key(code: Key,pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code;event.pressed = pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func check(name: String,ok: bool) -> void:
	rows.append({"name":name,"passed":ok})
	if not ok: push_error("MATERIAL_LAB_CONTROL "+name)
func run(tree: SceneTree) -> void:
	var lab: Node = tree.current_scene
	await frames(tree,5)
	check("initial_fixture",lab.adapter.logical_active.size()==5 and lab.manager.object_ids().size()==7)
	var body: Node = lab.manager.get_body(&"orange_r")
	var initial: Vector2 = body.position
	var builds: int = body.shape_builds
	key(KEY_M,true);key(KEY_M,false);await frames(tree,2)
	check("m_starts_motion",lab.moving)
	await frames(tree,65)
	check("m_moves_region",body.position.distance_to(initial)>10)
	check("m_does_not_rebuild",body.shape_builds==builds)
	key(KEY_M,true);key(KEY_M,false);await frames(tree,2)
	check("m_stops_motion",not lab.moving)
	key(KEY_R,true);key(KEY_R,false);await frames(tree,50)
	check("r_restores_fixture",lab.manager.object_ids().size()==7 and lab.adapter.logical_active.size()==5 and lab.manager.get_body(&"orange_r").position.distance_to(initial)<0.1)
	check("r_restores_players",lab.players[0].combat.damage_model.percent==0 and lab.players[1].combat.damage_model.percent==0 and lab.players[0].is_on_floor() and lab.players[1].is_on_floor())
	var failures: Array = rows.filter(func(row: Dictionary) -> bool:return not row.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"human_tested":false}
	lab.set_meta("lab_control_results",result)
	var file: FileAccess = FileAccess.open("res://validation/material_lab_controls.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("MATERIAL_LAB_CONTROLS ",result.passed,"/",result.total)
