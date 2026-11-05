extends RefCounted
const Player = preload("res://scripts/PlayerController.gd")
const Manager = preload("res://scripts/PlatformManager.gd")
const Platform = preload("res://scripts/DynamicPlatform.gd")
var tree: SceneTree
var results: Array[Dictionary] = []

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(name: String, passed: bool, detail: Variant = "") -> void:
	results.append({"test":name, "passed":passed, "detail":str(detail)})

func place(player: Player, point: Vector2) -> void:
	player.respawn()
	player.combat.respawn_left = 0
	player.position = point
	await frames(15)

func reset_platforms(manager: Manager) -> void:
	for platform: Platform in manager.platforms.values():
		manager.update_platform_transform(platform.platform_id, platform.home_transform)
	await frames(180)

func run_carry(scene_tree: SceneTree) -> Array[Dictionary]:
	tree = scene_tree
	var main: Node = tree.current_scene
	var manager: Manager = main.get_node("PlatformManager")
	await reset_platforms(manager)
	var platform: Platform = manager.get_platform(&"left")
	var p: Player = main.get_node("Players/Player1")
	var p2: Player = main.get_node("Players/Player2")
	await place(p, Vector2(350, 398))
	await place(p2, Vector2(420, 398))
	check("both_players_standing", p.is_on_floor() and p2.is_on_floor())
	manager.update_platform_position(&"left", Vector2(465, 435))
	await frames(90)
	check("both_carried_laterally", absf(p.position.x-430.0)<4 and absf(p2.position.x-500.0)<4 and p.is_on_floor() and p2.is_on_floor(), [p.position,p2.position])
	manager.update_platform_position(&"left", Vector2(465, 365))
	await frames(90)
	check("rising_platform_pushes_both", p.position.y<340 and p2.position.y<340 and p.is_on_floor() and p2.is_on_floor(), [p.position,p2.position])
	manager.update_platform_position(&"left", Vector2(465, 435))
	await frames(90)
	check("descending_platform_carries_both", absf(p.position.y-406.0)<3 and absf(p2.position.y-406.0)<3 and p.is_on_floor() and p2.is_on_floor(), [p.position,p2.position])
	manager.update_platform_rotation(&"left", deg_to_rad(25))
	await frames(90)
	check("rotation_and_inclined_floor", p.is_on_floor() and p2.is_on_floor() and p.position.is_finite() and p2.position.is_finite(), [p.position,p2.position])
	Input.action_press("p1_jump")
	await frames(4)
	check("jump_from_rotating_platform", p.velocity.y<0 and not p.is_on_floor())
	Input.action_release("p1_jump")
	manager.update_platform_rotation(&"left", 0.0)
	manager.update_platform_position(&"left", Vector2(495,435))
	await frames(100)
	check("land_on_moving_platform", p.is_on_floor() and p.position.y<450, p.position)
	check("colliders_still_enabled", not platform.get_node("CollisionShape2D").disabled and platform.collision_layer==2 and platform.sync_to_physics)
	await reset_platforms(manager)
	p.respawn()
	p2.respawn()
	tree.current_scene.set_meta("validation_results", results)
	return results

func run_limits(scene_tree: SceneTree) -> Array[Dictionary]:
	tree = scene_tree
	var manager: Manager = tree.current_scene.get_node("PlatformManager")
	await reset_platforms(manager)
	var left: Platform = manager.get_platform(&"left")
	var right: Platform = manager.get_platform(&"right")
	var original: PackedVector2Array = left.visual.polygon.duplicate()
	var shape: Shape2D = left.get_node("CollisionShape2D").shape
	check("known_ids_only", manager.platforms.size()==3 and not manager.update_platform_position(&"unknown", Vector2.ZERO))
	check("scale_rejected", not manager.update_platform_transform(&"left",Transform2D(0.0,Vector2(2,2),0.0,Vector2(400,400))))
	check("nonfinite_rejected", not manager.update_platform_position(&"left",Vector2(INF,0)) and not manager.update_platform_rotation(&"left",NAN))
	manager.update_platform_position(&"left",Vector2(100000,-100000))
	check("target_bounds", left.target_position==Vector2(1130,180))
	manager.update_platform_transform(&"left", Transform2D(1.0,Vector2(800,380)))
	var previous: Transform2D = left.global_transform
	var linear_max: float = 0
	var angular_max: float = 0
	var sweep_max: float = 0
	for i: int in range(90):
		await frames(1)
		var distance: float = left.position.distance_to(previous.origin)
		var turn: float = absf(angle_difference(previous.get_rotation(), left.rotation))
		linear_max=maxf(linear_max,distance*60)
		angular_max=maxf(angular_max,turn*60)
		sweep_max=maxf(sweep_max,distance+turn*left.surface_radius)
		previous=left.global_transform
	check("linear_angular_and_surface_limits", linear_max<=left.max_linear_speed+0.1 and angular_max<=left.max_angular_speed+0.01 and sweep_max<=left.max_surface_step+0.01, [linear_max,angular_max,sweep_max])
	check("immutable_geometry", left.visual.polygon==original and left.scale.is_equal_approx(Vector2.ONE) and left.get_node("CollisionShape2D").shape==shape)
	manager.update_platform_transform(&"left",Transform2D(0.0,Vector2(500,435)))
	manager.update_platform_transform(&"right",Transform2D(0.0,Vector2(780,435)))
	await frames(150)
	manager.update_platform_position(&"left",Vector2(780,435))
	manager.update_platform_position(&"right",Vector2(500,435))
	await frames(160)
	check("two_platforms_cross", left.position.x>770 and right.position.x<510 and left.collision_layer==2 and right.collision_layer==2, [left.position,right.position])
	await reset_platforms(manager)
	tree.current_scene.set_meta("validation_results", results)
	return results

func run_gravity(scene_tree: SceneTree) -> Array[Dictionary]:
	tree = scene_tree
	var p: Player = tree.current_scene.get_node("Players/Player1")
	var manager: Manager = tree.current_scene.get_node("PlatformManager")
	await reset_platforms(manager)
	# Empty side lane: measure a real 200px fall against the previous 1850px/s².
	tree.current_scene.set_physics_process(false)
	p.position=Vector2(80,200)
	p.velocity=Vector2.ZERO
	p.set_collision_mask_value(2,true)
	await frames(2)
	p.velocity=Vector2.ZERO
	var start_y: float=p.position.y
	var elapsed_frames: int=0
	while p.position.y<start_y+200 and elapsed_frames<90:
		await frames(1)
		elapsed_frames+=1
	var elapsed: float=elapsed_frames/60.0
	check("slower_200px_fall", elapsed>sqrt(400.0/1850.0), elapsed)
	await frames(35)
	check("normal_terminal_speed", absf(p.velocity.y-p.movement.terminal_speed)<0.1,p.velocity.y)
	p.position=Vector2(80,200)
	p.velocity=Vector2(0,100)
	Input.action_press("p1_down")
	await frames(1)
	check("fast_fall_accelerates_without_instant_snap", p.velocity.y>100 and p.velocity.y<p.movement.fast_fall_speed, p.velocity.y)
	await frames(30)
	check("fast_fall_cap", absf(p.velocity.y-p.movement.fast_fall_speed)<0.1,p.velocity.y)
	Input.action_release("p1_down")
	await place(p,Vector2(640,540))
	Input.action_press("p1_jump")
	var lowest: float=p.position.y
	var time_to_apex: int=0
	for i: int in range(70):
		await frames(1)
		lowest=minf(lowest,p.position.y)
		if time_to_apex==0 and p.velocity.y>=0:
			time_to_apex=i+1
	Input.action_release("p1_jump")
	check("agile_reachable_jump", lowest<390 and time_to_apex>=28 and time_to_apex<=34, {"apex_y":lowest,"apex_seconds":time_to_apex/60.0})
	tree.current_scene.set_physics_process(true)
	p.respawn()
	tree.current_scene.get_node("Players/Player2").respawn()
	tree.current_scene.set_meta("validation_results", results)
	return results
