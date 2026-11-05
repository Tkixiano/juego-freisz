extends RefCounted
const Controller = preload("res://scripts/PlayerController.gd")
var results: Array[Dictionary] = []
var tree: SceneTree
var primary_id: int = 1

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func action(key: StringName, pressed: bool) -> void:
	if primary_id == 2:
		key = StringName(("p2_" if String(key).begins_with("p1_") else "p1_") + String(key).substr(3))
	if pressed:
		Input.action_press(key)
	else:
		Input.action_release(key)

func check(name: String, passed: bool, detail: String = "") -> void:
	results.append({"test": name, "passed": passed, "detail": detail})

func place(p: Controller, point: Vector2) -> void:
	for key: StringName in [p.left_action, p.right_action, p.jump_action, p.down_action]:
		Input.action_release(key)
	p.respawn()
	p.combat.respawn_left = 0
	p.global_position = point
	p.velocity = Vector2.ZERO
	await frames(4)

func run(scene_tree: SceneTree, tested_player: int = 1) -> Array[Dictionary]:
	tree = scene_tree
	primary_id = tested_player
	var main: Node2D = tree.current_scene
	var p: Controller = main.get_node("Players/Player%d" % primary_id)
	var p2: Controller = main.get_node("Players/Player%d" % (3-primary_id))
	await place(p, Vector2(440, 540))
	await place(p2, Vector2(840, 540))
	check("floor_and_gravity", p.is_on_floor() and absf(p.position.y - 542.0) < 1.0, str(p.position))
	action(&"p1_right", true)
	action(&"p2_left", true)
	await frames(12)
	check("simultaneous_independent_movement", p.position.x > 475.0 and p2.position.x < 805.0 and p.velocity.x > 0 and p2.velocity.x < 0)
	check("acceleration_speed_cap", p.velocity.x <= p.movement.speed and p.velocity.x > 300.0)
	action(&"p1_right", false)
	action(&"p2_left", false)
	await frames(12)
	check("deceleration", is_zero_approx(p.velocity.x) and is_zero_approx(p2.velocity.x))
	await place(p, Vector2(640, 540))
	action(&"p1_jump", true)
	await frames(4)
	var before_cut: float = p.velocity.y
	action(&"p1_jump", false)
	await frames(1)
	check("variable_jump", p.velocity.y > before_cut * 0.7 and p.velocity.y < 0.0)
	action(&"p1_jump", true)
	await frames(1)
	check("double_jump", p.jumps_used == 2 and p.velocity.y < -p.movement.double_jump_speed * 0.85)
	action(&"p1_jump", false)
	await frames(2)
	action(&"p1_jump", true)
	await frames(1)
	check("third_jump_rejected", p.jumps_used == 2 and p.velocity.y > -500.0)
	action(&"p1_jump", false)
	await place(p, Vector2(640, 350))
	action(&"p1_right", true)
	await frames(8)
	check("air_control", p.velocity.x > 0.0 and p.position.x > 645.0)
	action(&"p1_right", false)
	p.velocity.y = 100.0
	action(&"p1_down", true)
	await frames(14)
	check("fast_fall", p.velocity.y > 100.0 + p.movement.descent_gravity * (14.0/60.0) and p.velocity.y <= p.movement.fast_fall_speed)
	action(&"p1_down", false)
	await place(p, Vector2(385, 400))
	await frames(10)
	check("one_way_landing", p.is_on_floor() and absf(p.position.y - 406.0) < 1.0)
	action(&"p1_down", true)
	await frames(8)
	check("drop_through", p.position.y > 435.0 and not p.get_collision_mask_value(2))
	action(&"p1_down", false)
	await frames(20)
	check("drop_mask_restored_and_solid_floor", p.get_collision_mask_value(2) and p.is_on_floor() and absf(p.position.y - 542.0) < 1.0)
	await place(p, Vector2(385, 540))
	action(&"p1_jump", true)
	var apex: float = p.position.y
	for i: int in range(52):
		await frames(1)
		apex = minf(apex, p.position.y)
	action(&"p1_jump", false)
	await frames(8)
	check("pass_platform_from_below_and_land", apex < 406.0 and p.is_on_floor() and absf(p.position.y - 406.0) < 1.0, "apex=%s landing=%s" % [apex, p.position.y])
	await place(p, Vector2(1120, 540))
	action(&"p1_right", true)
	var left_floor: bool = false
	for i: int in range(20):
		await frames(1)
		if not p.is_on_floor():
			left_floor = true
			break
	action(&"p1_right", false)
	action(&"p1_jump", true)
	await frames(1)
	check("coyote_time", left_floor and p.jumps_used == 1 and p.velocity.y < -p.movement.jump_speed * 0.85)
	action(&"p1_jump", false)
	await place(p, Vector2(640, 480))
	p.jumps_used = 2
	p.coyote_left = 0.0
	p.velocity.y = 600.0
	action(&"p1_jump", true)
	await frames(8)
	check("jump_buffer_on_landing", p.jumps_used == 1 and p.velocity.y < -p.movement.double_jump_speed * 0.85)
	action(&"p1_jump", false)
	await place(p2, Vector2(840, 540))
	action(&"p2_jump", true)
	await frames(3)
	check("player2_jump", p2.jumps_used == 1 and p2.velocity.y < 0.0)
	action(&"p2_jump", false)
	var old_returns: int = main.returns[primary_id-1]
	p.position = Vector2(-200, 920)
	await frames(3)
	check("elimination_respawn", main.returns[primary_id-1] == old_returns + 1 and p.position.distance_to(p.spawn_position) < 20.0)
	await place(p, p.spawn_position)
	await place(p2, p2.spawn_position)
	main.returns[0] = 0
	main.returns[1] = 0
	main.get_node("UI/HUD/Returns").text = "REAPARICIONES   P1  00    /    P2  00"
	tree.current_scene.set_meta("validation_results", results)
	return results
