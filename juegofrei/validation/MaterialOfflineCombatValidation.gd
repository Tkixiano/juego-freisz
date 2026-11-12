extends RefCounted
func run(tree: SceneTree) -> void:
	var lab: Node = tree.current_scene
	var replay: Node = lab.get_node("Replay")
	replay.pause();lab.adapter.request_reset()
	for p: Node in lab.players:p.collision_mask = 0;p.set_physics_process(false)
	for i: int in range(3):await tree.physics_frame
	var loaded: bool = replay.load_replay("res://validation/material_replays/01_solid.json")
	for i: int in range(3):await tree.physics_frame
	replay.set_speed(1);replay.play()
	for index: int in range(2):
		var p: Node = lab.players[index]
		p.position = Vector2(190+index*40,240);p.velocity = Vector2.ZERO;p.force_update_transform();p.reset_physics_interpolation()
		p.combat.reset_after_respawn();p.combat.respawn_left = 0;p.combat.invulnerability_left = 0;p.combat.accepted_hits = 0
		p.collision_mask = 3;p.set_physics_process(true)
	for i: int in range(40):await tree.physics_frame
	var support: bool = lab.players[0].is_on_floor() and lab.players[1].is_on_floor()
	var driver: Node = load("res://validation/MaterialPhysicsTestInput.gd").new();lab.add_child(driver)
	for name: String in ["p1_light","p2_light"]:
		var event: InputEventAction = InputEventAction.new();event.action = name;event.pressed = true;driver.events.append(event)
	for i: int in range(30):await tree.physics_frame
	Input.action_release("p1_light");Input.action_release("p2_light");driver.queue_free()
	var trade: bool = lab.players[0].combat.damage_model.percent==lab.players[1].combat.ground_light.damage and lab.players[1].combat.damage_model.percent==lab.players[0].combat.ground_light.damage
	var unique: bool = lab.players[0].combat.accepted_hits==1 and lab.players[1].combat.accepted_hits==1
	var rows: Array = [{"name":"two_players_on_exported_solid","passed":loaded and support},{"name":"simultaneous_combat_on_exported_geometry","passed":trade},{"name":"no_duplicate_damage","passed":unique}]
	var failures: Array = rows.filter(func(row: Dictionary) -> bool:return not row.passed)
	var result: Dictionary = {"total":3,"passed":3-failures.size(),"rows":rows,"failures":failures,"damage":[lab.players[0].combat.damage_model.percent,lab.players[1].combat.damage_model.percent],"human_tested":false}
	var file: FileAccess = FileAccess.open("res://validation/material_offline_combat.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
	print("MATERIAL_OFFLINE_COMBAT ",result.passed,"/3 ",failures)
