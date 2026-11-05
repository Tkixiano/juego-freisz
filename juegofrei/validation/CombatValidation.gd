extends RefCounted
const Player = preload("res://scripts/PlayerController.gd")
var tree: SceneTree
var results: Array[Dictionary] = []

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(name: String, passed: bool, detail: Variant = "") -> void:
	results.append({"test":name,"passed":passed,"detail":str(detail)})

func fresh() -> void:
	var root: Node = tree.current_scene
	root.restart_match()
	for player: Player in root.players:
		for suffix: String in ["left","right","jump","down","light","heavy","dodge"]:
			Input.action_release("p%d_%s" % [player.player_id,suffix])
		player.combat.respawn_left = 0
		player.combat.invulnerability_left = 0
		player.combat.accepted_hits = 0
	root.players[0].position = Vector2(600,540)
	root.players[1].position = Vector2(655,540)
	await frames(6)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var code: Error = tree.root.get_texture().get_image().save_png("C:/godot 4.6/juego frei/artifacts/"+name)
	check("capture_"+name,code==OK)

func complete() -> Array[Dictionary]:
	tree.current_scene.set_meta("validation_results",results)
	return results

func run_core(scene_tree: SceneTree) -> Array[Dictionary]:
	tree=scene_tree
	await fresh()
	var root: Node = tree.current_scene
	var p: Player = root.players[0]
	var q: Player = root.players[1]
	check("dedicated_combat_layers", p.combat.hitbox.query.collision_mask==8 and p.get_node("Hurtbox").collision_layer==8 and p.collision_mask==3)
	check("independent_hitbox_resources", p.combat.hitbox.collider.shape!=q.combat.hitbox.collider.shape)
	Input.action_press("p1_light")
	await frames(2)
	check("startup_no_damage", q.combat.damage_model.percent==0 and p.state==Player.State.ATTACK)
	check("attack_prevents_contradictory_dodge", not p.combat.start_dodge() and not p.combat.start_attack(true))
	Input.action_release("p1_light")
	await frames(4)
	check("light_hits_once", q.combat.damage_model.percent==6 and p.combat.accepted_hits==1, q.combat.damage_model.percent)
	check("launch_and_hitstun", q.velocity.x>0 and q.velocity.y<0 and q.state==Player.State.HITSTUN,[q.velocity,q.combat.hitstun_left])
	check("brief_local_hitstop", p.combat.freeze_frames>0 and q.combat.freeze_frames>0 and not tree.paused)
	check("impact_feedback", q.combat.flash_left>0 and root.effects.bursts.size()>0)
	check("hitstun_blocks_attack_and_dodge", not q.combat.start_attack(false) and not q.combat.start_dodge())
	await frames(12)
	check("no_duplicate_activation_damage", q.combat.damage_model.percent==6 and p.combat.accepted_hits==1)
	check("recovery_remains_committed", p.combat.attack_frame>=0 and not p.combat.start_attack(true))
	await frames(20)
	check("attack_returns_to_neutral", p.combat.attack_frame<0 and p.combat.cooldown_left<=0 and p.state==Player.State.IDLE)
	var low: float=q.combat.damage_model.launch_strength(p.combat.ground_heavy,0)
	var high: float=q.combat.damage_model.launch_strength(p.combat.ground_heavy,100)
	check("percent_increases_knockback",high>low*2,[low,high])
	q.combat.invulnerability_left=0
	q.combat.damage_model.percent=100
	var accepted: bool=q.combat.receive_hit(p.combat.ground_heavy,Vector2(1,-1))
	check("heavy_damage_accumulates",accepted and q.combat.damage_model.percent==114 and q.velocity.length()>low,q.velocity.length())
	q.combat.invulnerability_left=0
	for i: int in range(40):
		root.effects.burst(Vector2(640,400),Color.WHITE)
	check("bounded_geometric_effects",root.effects.bursts.size()<=root.effects.maximum_bursts)
	await fresh()
	return complete()

func run_defense_and_direction(scene_tree: SceneTree) -> Array[Dictionary]:
	tree=scene_tree
	await fresh()
	var root: Node=tree.current_scene
	var p: Player=root.players[0]
	var q: Player=root.players[1]
	check("dodge_starts", q.combat.start_dodge())
	check("dodge_rejects_hit",not q.combat.receive_hit(p.combat.ground_heavy,Vector2.RIGHT) and q.combat.damage_model.percent==0)
	await frames(20)
	check("dodge_has_cooldown",q.combat.dodge_left<=0 and not q.combat.start_dodge())
	await fresh()
	Input.action_press("p1_jump")
	check("up_direction_attack",p.combat.start_attack(false) and p.combat.aim==Vector2.UP and p.combat.launch_direction.y < -0.9)
	p.combat.cancel_attack()
	Input.action_release("p1_jump")
	Input.action_press("p1_down")
	check("ground_down_attack",p.combat.start_attack(true) and p.combat.attack_direction=="abajo" and p.combat.attack==p.combat.ground_heavy)
	p.combat.cancel_attack()
	Input.action_release("p1_down")
	p.position=Vector2(600,350)
	p.velocity=Vector2.ZERO
	await frames(2)
	Input.action_press("p1_down")
	check("air_heavy_spike",p.combat.start_attack(true) and p.combat.attack==p.combat.air_heavy and p.combat.launch_direction.y>0.9)
	p.combat.cancel_attack()
	Input.action_release("p1_down")
	check("air_light_profile",p.combat.start_attack(false) and p.combat.attack==p.combat.air_light)
	p.combat.cancel_attack()
	q.position=Vector2(850,300)
	q.velocity=Vector2.ZERO
	await frames(2)
	check("air_dodge_once",q.combat.start_dodge())
	await frames(20)
	q.combat.dodge_cooldown_left=0
	check("second_air_dodge_rejected",not q.combat.start_dodge())
	# Check the actual InputMap distinction rather than accepting either Shift.
	var key: InputEventKey=InputEventKey.new()
	key.keycode=KEY_SHIFT
	key.physical_keycode=KEY_SHIFT
	key.location=KEY_LOCATION_LEFT
	key.pressed=true
	Input.parse_input_event(key)
	await frames(1)
	check("left_shift_not_bound",not Input.is_action_pressed("p2_dodge"))
	var released: InputEventKey=key.duplicate()
	released.pressed=false
	Input.parse_input_event(released)
	await frames(1)
	key=InputEventKey.new()
	key.keycode=KEY_SHIFT
	key.physical_keycode=KEY_SHIFT
	key.location=KEY_LOCATION_RIGHT
	key.pressed=true
	Input.parse_input_event(key)
	await frames(1)
	check("right_shift_bound",Input.is_action_pressed("p2_dodge"))
	released=key.duplicate()
	released.pressed=false
	Input.parse_input_event(released)
	await frames(1)
	await fresh()
	return complete()

func run_stocks(scene_tree: SceneTree) -> Array[Dictionary]:
	tree=scene_tree
	await fresh()
	var root: Node=tree.current_scene
	var p: Player=root.players[0]
	var q: Player=root.players[1]
	var events: Dictionary={"stocks":0,"wins":0}
	root.stock_lost.connect(func(_id: int,_remaining: int) -> void: events["stocks"]+=1)
	root.match_ended.connect(func(_id: int) -> void: events["wins"]+=1)
	q.combat.damage_model.percent=80
	q.position=Vector2(-200,950)
	await frames(3)
	check("stock_loss_respawns",q.combat.damage_model.stocks==2 and q.combat.damage_model.percent==0 and q.position.distance_to(q.spawn_position)<30)
	check("respawn_state_and_invulnerability",q.state==Player.State.RESPAWN and q.combat.invulnerability_left>1.0 and not q.combat.receive_hit(p.combat.ground_light,Vector2.RIGHT))
	for i: int in range(2):
		q.position=Vector2(-200,950)
		await frames(3)
	check("three_stocks_then_eliminated",q.combat.damage_model.stocks==0 and q.state==Player.State.ELIMINATED and not q.visible)
	check("victory_condition_and_overlay",root.game_over and root.winner_id==1 and root.get_node("UI/HUD/Victory").visible)
	check("stock_and_victory_signals",events["stocks"]==3 and events["wins"]==1,events)
	check("no_attack_after_victory",not p.combat.start_attack(false))
	await capture("combat_victory.png")
	Input.action_press("match_restart")
	await frames(2)
	Input.action_release("match_restart")
	check("restart_input",not root.game_over and p.combat.damage_model.stocks==3 and q.combat.damage_model.stocks==3 and p.combat.damage_model.percent==0 and not root.get_node("UI/HUD/Victory").visible)
	await fresh()
	p.combat.damage_model.stocks=1
	q.combat.damage_model.stocks=1
	p.position=Vector2(-200,950)
	q.position=Vector2(1500,950)
	await frames(3)
	check("simultaneous_last_stock_draw",root.game_over and root.winner_id==0)
	await fresh()
	return complete()

func run_platform_combat(scene_tree: SceneTree) -> Array[Dictionary]:
	tree=scene_tree
	await fresh()
	var root: Node=tree.current_scene
	var p: Player=root.players[0]
	var q: Player=root.players[1]
	var manager: Node=root.get_node("PlatformManager")
	var platform: Node2D=manager.get_platform("left")
	manager.update_platform_transform("left",Transform2D(0,Vector2(385,435)))
	await frames(90)
	p.position=Vector2(350,395)
	q.position=Vector2(405,395)
	p.velocity=Vector2.ZERO
	q.velocity=Vector2.ZERO
	await frames(15)
	var fixed_polygon: PackedVector2Array=platform.get_node("Visual").polygon.duplicate()
	manager.update_platform_transform("left",Transform2D(deg_to_rad(15),Vector2(455,395)))
	Input.action_press("p1_heavy")
	await frames(1)
	Input.action_release("p1_heavy")
	var before: Vector2=platform.position
	await frames(13)
	check("heavy_hits_on_moving_rotating_platform",q.combat.damage_model.percent==14,p.combat.phase())
	check("hitstop_does_not_pause_platform",platform.position.distance_to(before)>2 and not tree.paused,platform.position)
	await frames(55)
	check("inclined_platform_collision_kept",platform.get_node("CollisionShape2D").disabled==false and platform.rotation>0.2 and p.is_on_floor(),[platform.rotation,p.position])
	check("combat_does_not_deform_platform",platform.scale==Vector2.ONE and fixed_polygon==platform.get_node("Visual").polygon)
	manager.update_platform_transform("left",platform.home_transform)
	await frames(90)
	await fresh()
	# Attacks and player motion remain independent while editor rotation is active.
	p.position=Vector2(400,540)
	q.position=Vector2(850,540)
	Input.action_press("p1_right")
	Input.action_press("p2_left")
	Input.action_press("p1_light")
	Input.action_press("p2_heavy")
	await frames(1)
	Input.action_release("p1_light")
	Input.action_release("p2_heavy")
	await frames(12)
	check("simultaneous_player_attacks",p.state==Player.State.ATTACK and q.state==Player.State.ATTACK)
	Input.action_release("p1_right")
	Input.action_release("p2_left")
	await frames(50)
	await fresh()
	return complete()
