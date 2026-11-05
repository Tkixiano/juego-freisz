extends RefCounted
const Player = preload("res://scripts/PlayerController.gd")
const GeometryManager = preload("res://scripts/geometry/DynamicGeometryManager.gd")
var tree: SceneTree
var game: Node
var p: Player
var q: Player
var rows: Array[Dictionary] = []
var measures: Dictionary = {}

func frames(n: int) -> void:
	for i: int in range(n):
		await tree.physics_frame
		await tree.process_frame

func check(name: String,passed: bool,details: Variant="") -> void:
	rows.append({"name":name,"passed":passed,"details":str(details)})
	if not passed: push_error("PHASE2A "+name+": "+str(details))

func place(body: Player,point: Vector2) -> void:
	body.global_position = point
	body.velocity = Vector2.ZERO
	body.force_update_transform()
	body.reset_physics_interpolation()

func fresh(air: bool=false,point: Vector2=Vector2(600,540)) -> void:
	game.restart_match()
	# Flush previous just-pressed flags while the normal respawn lock is active.
	await frames(1)
	for body: Player in [p,q]:
		body.combat.respawn_left = 0
		body.combat.invulnerability_left = 0
		body.combat.accepted_hits = 0
	place(p,Vector2(point.x,350) if air else point)
	place(q,Vector2(1050,540))
	await frames(4)
	p.velocity = Vector2.ZERO

func run(scene_tree: SceneTree,label: String="mcp") -> Dictionary:
	tree = scene_tree
	game = tree.current_scene
	p = game.players[0]
	q = game.players[1]
	await dash_tests()
	await attack_tests()
	await input_and_damage_tests()
	await surface_tests()
	await fresh()
	var failed: Array = rows.filter(func(r: Dictionary)->bool:return not r.passed)
	var result: Dictionary = {"label":label,"total":rows.size(),"passed":rows.size()-failed.size(),"failures":failed,"measurements":measures,"rows":rows,"hardware_used":false}
	game.set_meta("phase2a_results",result)
	var file: FileAccess = FileAccess.open("res://validation/phase2a_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("PHASE2A_QA ",JSON.stringify({"label":label,"passed":result.passed,"total":result.total,"failures":failed}))
	return result

func dash_tests() -> void:
	for direction: int in [-1,1]:
		await fresh()
		Input.action_press("p1_left" if direction<0 else "p1_right")
		Input.action_press("p1_dodge")
		var start: Vector2 = p.position
		await frames(1)
		check("dash_%d_input"%direction,p.combat.horizontal_dash and p.state==Player.State.DODGE and p.combat.dodge_vector==Vector2(direction,0))
		check("dash_%d_invulnerability"%direction,not p.combat.receive_hit(q.combat.ground_light,Vector2.RIGHT) and p.combat.damage_model.percent==0)
		var maximum: float = absf(p.velocity.x)
		for i: int in range(12):
			await frames(1)
			maximum = maxf(maximum,absf(p.velocity.x))
		check("dash_%d_direction_and_cap"%direction,(p.position.x-start.x)*direction>30 and maximum<=p.combat.dodge_speed+0.01,[p.position-start,maximum])
		check("dash_%d_no_retrigger_or_attack"%direction,not p.combat.start_dodge() and not p.combat.start_attack(false))
		Input.action_release("p1_dodge")
		Input.action_release("p1_left" if direction<0 else "p1_right")
		await frames(8)
		check("dash_%d_cooldown"%direction,p.combat.dodge_left<=0 and not p.combat.start_dodge())
		await frames(42)
		check("dash_%d_recovers"%direction,p.combat.dodge_cooldown_left<=0 and p.combat.start_dodge())
		measures["dash_%d_max_speed"%direction] = maximum
	await fresh(true)
	Input.action_press("p1_right");Input.action_press("p1_down");Input.action_press("p1_dodge")
	await frames(1)
	check("air_dash_horizontal_wins_vertical",p.combat.horizontal_dash and p.combat.dodge_vector==Vector2.RIGHT and absf(p.velocity.y)<0.01 and p.combat.air_dodge_used)
	Input.action_release("p1_dodge");Input.action_release("p1_right");Input.action_release("p1_down")
	# Keep the body airborne while the existing dodge expires.
	await frames(19)
	p.combat.dodge_cooldown_left = 0
	check("air_dash_once_per_airtime",not p.combat.start_dodge())
	await fresh()
	var start: Vector2 = p.position
	check("neutral_defense_starts",p.combat.start_dodge() and not p.combat.horizontal_dash and p.combat.dodge_vector==Vector2.ZERO)
	await frames(8)
	check("neutral_defense_does_not_dash",absf(p.position.x-start.x)<0.01)
	await fresh(true)
	Input.action_press("p1_jump")
	check("neutral_horizontal_preserves_vertical_air_dodge",p.combat.start_dodge() and not p.combat.horizontal_dash and p.combat.dodge_vector==Vector2.UP)
	Input.action_release("p1_jump")
	await fresh()
	var wall: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(20,200);collider.shape = shape
	wall.position = Vector2(670,490);wall.add_child(collider);game.add_child(wall)
	await frames(2)
	Input.action_press("p1_right");Input.action_press("p1_dodge")
	await frames(16)
	check("dash_wall_swept_collision_no_teleport",p.position.x<=640.1 and p.position.x>620 and p.combat.dodge_left>0,p.position)
	wall.free()
	await fresh()
	Input.action_press("p1_right");p.combat.start_dodge()
	await frames(12)
	check("dash_vulnerable_tail_can_be_interrupted",p.combat.invulnerability_left<=0 and p.combat.receive_hit(q.combat.ground_light,Vector2.LEFT) and p.combat.dodge_left==0 and not p.combat.horizontal_dash)

func attack_tests() -> void:
	for heavy: bool in [false,true]:
		var suffix: String = "heavy" if heavy else "light"
		await fresh(true)
		Input.action_press("p1_down")
		Input.action_press("p1_heavy" if heavy else "p1_light")
		await frames(1)
		check("down_"+suffix+"_input_profile",p.combat.is_descending_attack() and p.combat.attack==(p.combat.air_heavy if heavy else p.combat.air_light))
		check("down_"+suffix+"_circle_direction",p.combat.aim==Vector2.DOWN and p.combat.hitbox.position==Vector2(0,p.combat.attack.reach) and p.combat.hitbox.collider.shape is CircleShape2D)
		check("down_"+suffix+"_controlled_velocity",p.velocity.y>0 and p.velocity.y<=p.movement.fast_fall_speed,p.velocity)
		Input.action_release("p1_light");Input.action_release("p1_heavy");Input.action_release("p1_down")
		await frames(3)
		check("down_"+suffix+"_direction_locked",p.combat.aim==Vector2.DOWN)
		var peak: float = p.velocity.y
		for i: int in range(6):
			await frames(1)
			peak = maxf(peak,p.velocity.y)
		check("down_"+suffix+"_profile_speed_cap",peak<=p.combat.attack.descent_speed,peak)
		measures["down_"+suffix+"_peak"] = peak
		Input.action_press("p1_dodge")
		await frames(1)
		check("down_"+suffix+"_cover_cancels_and_defends",p.combat.attack_frame<0 and p.combat.attack==null and p.combat.dodge_left>0 and p.combat.cooldown_left>0)
		check("down_"+suffix+"_cancelled_serial",p.combat.cancelled_attack_serial==p.combat.attack_serial)
		await fresh()
		Input.action_press("p1_down")
		check("ground_down_not_descending_"+suffix,p.combat.start_attack(heavy) and not p.combat.is_descending_attack() and p.combat.attack==(p.combat.ground_heavy if heavy else p.combat.ground_light))
		await fresh()
		Input.action_press("p1_jump")
		var vy: float = p.velocity.y
		check("up_"+suffix+"_starts",p.combat.start_attack(heavy))
		check("up_"+suffix+"_circle_profile",p.combat.aim==Vector2.UP and p.combat.hitbox.position==Vector2(0,-p.combat.attack.reach) and is_equal_approx((p.combat.hitbox.collider.shape as CircleShape2D).radius,p.combat.attack.radius))
		check("up_"+suffix+"_no_impulse_at_start",p.velocity.y==vy)
		await frames(3)
		check("up_"+suffix+"_does_not_jump_from_floor",p.is_on_floor() and absf(p.velocity.y)<0.01,p.velocity)
		Input.action_release("p1_jump");Input.action_press("p1_down");Input.action_press("p1_right")
		await frames(1)
		check("up_"+suffix+"_aim_stays_locked",p.combat.aim==Vector2.UP)
		await fresh(true)
		Input.action_press("p1_jump")
		p.velocity.y = 80
		check("air_up_"+suffix+"_starts",p.combat.start_attack(heavy))
		check("air_up_"+suffix+"_no_impulse",p.velocity.y==80)
		await frames(1)
		check("air_up_"+suffix+"_normal_gravity",absf(p.velocity.y-(80+p.movement.descent_gravity/60))<0.1,p.velocity)
	await fresh(true)
	Input.action_press("p1_down");p.combat.start_attack(false)
	p.combat.dodge_cooldown_left = 0.5
	Input.action_press("p1_dodge")
	await frames(1)
	check("cover_cancels_even_if_dodge_on_cooldown",p.combat.attack_frame<0 and p.combat.dodge_left==0 and p.combat.invulnerability_left==0)
	await fresh(true)
	Input.action_press("p1_down");p.combat.start_attack(false)
	p.combat.freeze_frames = 3
	Input.action_press("p1_dodge")
	await frames(1)
	check("cover_cancels_during_hitstop_without_bypassing_freeze",p.combat.attack_frame<0 and p.combat.dodge_left==0 and p.combat.freeze_frames==2)
	await frames(40)
	check("cancel_returns_to_normal_state",p.combat.attack_frame<0 and p.combat.dodge_left<=0 and p.combat.hitstun_left<=0 and p.combat.cooldown_left<=0)

func input_and_damage_tests() -> void:
	await fresh(true)
	Input.action_press("p1_jump");Input.action_press("p1_down");Input.action_press("p1_right")
	p.combat.start_attack(false)
	check("both_vertical_neutral_front",p.combat.aim==Vector2.RIGHT and not p.combat.is_descending_attack())
	await fresh(true)
	Input.action_press("p1_jump");Input.action_press("p1_right")
	p.combat.start_attack(false)
	check("attack_vertical_beats_horizontal",p.combat.aim==Vector2.UP)
	await fresh()
	Input.action_press("p1_light");Input.action_press("p1_heavy")
	await frames(1)
	check("heavy_priority_over_light",p.combat.attack==p.combat.ground_heavy,[p.combat.attack.title if p.combat.attack!=null else "none",p.position,p.is_on_floor(),p.combat.phase()])
	await fresh()
	Input.action_press("p1_light");Input.action_press("p1_dodge");Input.action_press("p1_right")
	await frames(1)
	check("defense_priority_over_attacks",p.combat.attack_frame<0 and p.combat.horizontal_dash)
	await fresh()
	p.combat.cooldown_left = 0.1
	Input.action_press("p1_light")
	await frames(10)
	check("attack_cooldown_no_auto_buffer",p.combat.attack_frame<0)
	Input.action_release("p1_light");await frames(1);Input.action_press("p1_light");await frames(1)
	check("fresh_press_after_cooldown_starts",p.combat.attack_frame>=0)
	# Queue one legitimate candidate, cancel, then resolve: no late damage.
	await fresh(true)
	Input.action_press("p1_down");p.combat.start_attack(false)
	game.queue_combat_hit(p.combat,q.combat,p.combat.attack,p.combat.launch_direction,q.position)
	p.combat.cancel_attack(true,true)
	game._resolve_combat_hits()
	check("cancel_invalidates_queued_damage",q.combat.damage_model.percent==0 and p.combat.accepted_hits==0)
	# Receiving a simultaneous attack still permits the captured opposite hit.
	await fresh()
	place(q,Vector2(655,540));await frames(2)
	p.combat.start_attack(false);q.combat.start_attack(false)
	game.queue_combat_hit(p.combat,q.combat,p.combat.attack,Vector2.RIGHT,q.position)
	game.queue_combat_hit(q.combat,p.combat,q.combat.attack,Vector2.LEFT,p.position)
	game._resolve_combat_hits()
	check("simultaneous_trade_preserved",p.combat.damage_model.percent==6 and q.combat.damage_model.percent==6)
	# Real downward hit between the two reusable fighters, once per activation.
	await fresh(true)
	place(p,Vector2(600,425));place(q,Vector2(600,540));await frames(1)
	Input.action_press("p1_down");Input.action_press("p1_light")
	await frames(1);Input.action_release("p1_light")
	await frames(12)
	check("down_light_hits_other_player_once",q.combat.damage_model.percent==8 and p.combat.accepted_hits==1,q.combat.damage_model.percent)
	await frames(22)
	check("down_hit_does_not_repeat_after_landing",q.combat.damage_model.percent==8 and p.combat.accepted_hits==1)
	await fresh(true)
	place(p,Vector2(600,425));place(q,Vector2(600,540));await frames(1)
	Input.action_press("p1_down");Input.action_press("p1_heavy")
	await frames(1);Input.action_release("p1_heavy")
	await frames(18)
	check("down_heavy_hits_other_player_once",q.combat.damage_model.percent==12 and p.combat.accepted_hits==1,q.combat.damage_model.percent)
	for heavy: bool in [false,true]:
		await fresh()
		place(q,Vector2(600,470));await frames(1)
		Input.action_press("p1_jump");Input.action_press("p1_heavy" if heavy else "p1_light")
		await frames(1)
		Input.action_release("p1_light");Input.action_release("p1_heavy")
		await frames(17)
		check("up_real_hit_"+str(heavy),q.combat.damage_model.percent==(14 if heavy else 6) and p.combat.accepted_hits==1,q.combat.damage_model.percent)
	await fresh(true)
	Input.action_press("p1_down");Input.action_press("p1_light")
	Input.action_press("p2_left");Input.action_press("p2_dodge")
	await frames(1)
	check("independent_player_inputs",p.combat.is_descending_attack() and q.combat.horizontal_dash and q.combat.dodge_vector==Vector2.LEFT)

func landing_case(label: String,start: Vector2,manager: Node=null,target: Vector2=Vector2.ZERO,angle: float=0.0) -> void:
	await fresh()
	place(p,start)
	await frames(2)
	Input.action_press("p1_down")
	p.combat.start_attack(true)
	check(label+"_starts_in_air",p.combat.is_descending_attack(),[p.is_on_floor(),p.position])
	if manager!=null: manager.update_transform(&"surface",target,angle)
	var cancelled_on_contact: bool = false
	var floor: bool = false
	var max_speed: float = 0
	for i: int in range(30):
		await frames(1)
		max_speed = maxf(max_speed,p.velocity.y)
		if p.is_on_floor():
			floor = true
			cancelled_on_contact = p.combat.attack_frame<0 and p.combat.attack==null
			break
	check(label+"_cancels_on_first_floor_frame",floor and cancelled_on_contact,[p.position,p.combat.phase()])
	check(label+"_fall_cap",max_speed<=p.movement.fast_fall_speed+0.1,max_speed)
	check(label+"_normal_state",p.state in [Player.State.IDLE,Player.State.RUN])
	measures[label+"_max_fall"] = max_speed
	# Exercise dash on this actual supporting surface as well as downward landing.
	Input.action_release("p1_down")
	Input.action_press("p1_right");Input.action_press("p1_dodge")
	var floor_ticks: int = 0
	for i: int in range(6):
		await frames(1)
		if p.is_on_floor(): floor_ticks += 1
	check(label+"_dash_contact",p.combat.horizontal_dash and floor_ticks>=5,[p.position,floor_ticks])
	Input.action_release("p1_right");Input.action_release("p1_dodge")

func surface_tests() -> void:
	await landing_case("solid_floor",Vector2(600,510))
	await landing_case("predefined_one_way",Vector2(385,370))
	var geometry: Node = GeometryManager.new()
	game.add_child(geometry)
	geometry.create_object(&"surface",PackedVector2Array([Vector2(-100,-8),Vector2(100,-8),Vector2(100,28),Vector2(20,28),Vector2(20,8),Vector2(-100,8)]),Vector2(640,440))
	await frames(3)
	await landing_case("dynamic_concave",Vector2(610,380))
	await landing_case("dynamic_moving",Vector2(610,380),geometry,Vector2(665,440))
	await frames(25)
	await landing_case("dynamic_inclined",Vector2(640,380),geometry,Vector2(665,440),0.12)
	geometry.free()
	await fresh()
