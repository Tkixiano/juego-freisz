extends Node2D
const Attack = preload("res://scripts/AttackData.gd")
const Damage = preload("res://scripts/DamageModel.gd")
const Hitbox = preload("res://scripts/CombatHitbox.gd")
signal impact(point: Vector2, color: Color)
signal attack_started(name: String)
@export var ground_light: Attack
@export var ground_heavy: Attack
@export var air_light: Attack
@export var air_heavy: Attack
@export var dodge_duration: float = 0.30
@export var dodge_invulnerability: float = 0.18
@export var dodge_cooldown: float = 0.85
@export var dodge_speed: float = 580.0
@export var respawn_duration: float = 0.45
@export var respawn_invulnerability: float = 2.0
@export var hit_invulnerability: float = 0.12
@export var knockback_drag: float = 110.0
@onready var fighter: CharacterBody2D = get_parent() as CharacterBody2D
@onready var damage_model: Damage = $"../Damage"
@onready var hitbox: Hitbox = $Hitbox

var attack: Attack
var attack_frame: int = -1
var aim: Vector2 = Vector2.RIGHT
var launch_direction: Vector2 = Vector2.RIGHT
var facing: float = 1.0
var airborne_attack: bool = false
var attack_direction: String = "frente"
var cooldown_left: float = 0.0
var dodge_left: float = 0.0
var dodge_cooldown_left: float = 0.0
var dodge_vector: Vector2 = Vector2.ZERO
var air_dodge_used: bool = false
var hitstun_left: float = 0.0
var invulnerability_left: float = 0.0
var respawn_left: float = 0.0
var freeze_frames: int = 0
var flash_left: float = 0.0
var eliminated: bool = false
var match_locked: bool = false
var prefix: String
var accepted_hits: int = 0
var horizontal_dash: bool = false
var attack_serial: int = 0
## Landing/cover cancellation invalidates pending hits; hitstun still allows trades.
var cancelled_attack_serial: int = -1

func _ready() -> void:
	prefix = "p%d_" % int(fighter.get("player_id"))
	facing = 1.0 if int(fighter.get("player_id")) == 1 else -1.0

func tick(delta: float) -> bool:
	if is_descending_attack():
		if fighter.is_on_floor():
			cancel_attack(true,true)
		elif Input.is_action_just_pressed(prefix+"dodge"):
			# Cancellation is immediate even when cooldown/air-use/hitstop blocks dodge.
			cancel_attack(true,true)
	flash_left = maxf(0, flash_left - delta)
	if freeze_frames > 0:
		freeze_frames -= 1
		update_feedback()
		return false
	cooldown_left = maxf(0, cooldown_left - delta)
	dodge_cooldown_left = maxf(0, dodge_cooldown_left - delta)
	invulnerability_left = maxf(0, invulnerability_left - delta)
	hitstun_left = maxf(0, hitstun_left - delta)
	respawn_left = maxf(0, respawn_left - delta)
	dodge_left = maxf(0, dodge_left - delta)
	if dodge_left<=0: horizontal_dash = false
	if fighter.is_on_floor():
		air_dodge_used = false
	if not eliminated and not match_locked and hitstun_left <= 0 and respawn_left <= 0:
		if attack_frame < 0 and dodge_left <= 0:
			var horizontal: float = Input.get_axis(prefix+"left", prefix+"right")
			if horizontal != 0:
				facing = signf(horizontal)
			if Input.is_action_just_pressed(prefix+"dodge"):
				start_dodge()
			elif Input.is_action_just_pressed(prefix+"heavy"):
				start_attack(true)
			elif Input.is_action_just_pressed(prefix+"light"):
				start_attack(false)
	if attack_frame >= 0:
		_step_attack()
	update_feedback()
	return true

func start_attack(heavy: bool) -> bool:
	if eliminated or match_locked or attack_frame >= 0 or dodge_left > 0 or hitstun_left > 0 or respawn_left > 0 or cooldown_left > 0 or freeze_frames > 0:
		return false
	airborne_attack = not fighter.is_on_floor()
	attack = (air_heavy if heavy else air_light) if airborne_attack else (ground_heavy if heavy else ground_light)
	if attack == null:
		return false
	var vertical: float = Input.get_axis(prefix+"jump", prefix+"down")
	attack_direction = "frente"
	aim = Vector2(facing, 0)
	var degrees: float = attack.launch_angle
	if vertical < 0:
		aim = Vector2.UP
		degrees = attack.up_angle
		attack_direction = "arriba"
	elif vertical > 0:
		aim = Vector2.DOWN if airborne_attack else Vector2(facing, 0.25).normalized()
		degrees = attack.aerial_down_angle if airborne_attack else attack.down_angle
		attack_direction = "abajo"
	if airborne_attack and aim==Vector2.DOWN:
		var cap: float = float(fighter.get("movement").fast_fall_speed)
		fighter.velocity.y = clampf(maxf(fighter.velocity.y,attack.descent_initial_speed),0.0,cap)
	launch_direction = Vector2(cos(deg_to_rad(degrees))*facing, -sin(deg_to_rad(degrees))).normalized()
	hitbox.begin(attack.radius, aim * attack.reach)
	attack_frame = 0
	attack_serial += 1
	attack_started.emit(attack.title)
	return true

func _step_attack() -> void:
	if attack_frame >= attack.startup_frames and attack_frame < attack.startup_frames + attack.active_frames:
		for hurtbox: Area2D in hitbox.candidates():
			var target: Node = hurtbox.get_parent().get_node_or_null("Combat")
			if target == null:
				continue
			var game: Node = get_tree().current_scene
			if game != null and game.has_method("queue_combat_hit"):
				# Resolve after both fighters tick: equal-frame attacks can trade.
				game.call("queue_combat_hit", self, target, attack, launch_direction, hurtbox.global_position)
			elif bool(target.call("receive_hit", attack, launch_direction)):
				confirm_hit(attack, hurtbox.global_position)
	attack_frame += 1
	if attack_frame >= attack.startup_frames + attack.active_frames + attack.recovery_frames:
		cooldown_left = attack.cooldown
		attack_frame = -1

func confirm_hit(data: Attack, point: Vector2) -> void:
	# Use the captured attack: receiving a simultaneous hit may cancel our own.
	accepted_hits += 1
	freeze_frames = maxi(freeze_frames, data.hitstop_frames)
	impact.emit(point, fighter.get("body_color") as Color)

func receive_hit(data: Attack, direction: Vector2) -> bool:
	if eliminated or match_locked or invulnerability_left > 0 or respawn_left > 0:
		return false
	cancel_attack()
	dodge_left = 0.0
	horizontal_dash = false
	fighter.velocity = damage_model.apply_hit(data, direction)
	hitstun_left = minf(0.85, data.hitstun + fighter.velocity.length()*0.00015)
	invulnerability_left = hit_invulnerability
	freeze_frames = data.hitstop_frames
	flash_left = 0.15
	fighter.set("buffer_left", 0.0)
	return true

func start_dodge() -> bool:
	if eliminated or match_locked or attack_frame >= 0 or hitstun_left > 0 or respawn_left > 0 or dodge_left > 0 or dodge_cooldown_left > 0 or freeze_frames > 0:
		return false
	if not fighter.is_on_floor() and air_dodge_used:
		return false
	air_dodge_used = not fighter.is_on_floor()
	dodge_left = dodge_duration
	dodge_cooldown_left = dodge_cooldown
	invulnerability_left = maxf(invulnerability_left, dodge_invulnerability)
	var vertical: float = 0.0 if fighter.is_on_floor() else Input.get_axis(prefix+"jump",prefix+"down")
	var horizontal: float = Input.get_axis(prefix+"left",prefix+"right")
	horizontal_dash = horizontal!=0.0
	# Horizontal input wins over vertical for dodge, both on ground and in air.
	dodge_vector = Vector2(signf(horizontal),0) if horizontal_dash else Vector2(0,vertical).normalized()
	fighter.velocity = dodge_vector * dodge_speed
	return true

func is_descending_attack() -> bool:
	return attack_frame>=0 and attack!=null and airborne_attack and aim==Vector2.DOWN

func cancel_attack(apply_cooldown: bool=false,suppress_pending: bool=false) -> void:
	if attack_frame>=0:
		if apply_cooldown and attack!=null: cooldown_left = maxf(cooldown_left,attack.cooldown)
		if suppress_pending: cancelled_attack_serial = attack_serial
	attack_frame = -1
	attack = null
	hitbox.victims.clear()

func reset_after_respawn() -> void:
	cancel_attack()
	damage_model.reset_damage()
	hitstun_left = 0
	dodge_left = 0
	dodge_cooldown_left = 0
	cooldown_left = 0
	freeze_frames = 0
	flash_left = 0
	air_dodge_used = false
	horizontal_dash = false
	eliminated = false
	match_locked = false
	respawn_left = respawn_duration
	invulnerability_left = respawn_invulnerability

func phase() -> String:
	if eliminated:
		return "ELIMINADO"
	if respawn_left > 0:
		return "REAPARECIENDO"
	if hitstun_left > 0:
		return "HITSTUN"
	if dodge_left > 0:
		return "DASH" if horizontal_dash else "DODGE"
	if attack_frame >= 0:
		if attack_frame <= attack.startup_frames:
			return "PREPARACIÓN"
		if attack_frame <= attack.startup_frames+attack.active_frames:
			return "ACTIVO"
		return "RECUPERACIÓN"
	return "LISTO"

func update_feedback() -> void:
	var visual: Polygon2D = $"../Visual"
	var color: Color = fighter.get("body_color") as Color
	visual.color = Color.WHITE if flash_left > 0 else color
	visual.modulate.a = (0.45 + 0.35 * sin(Time.get_ticks_msec()*0.03)) if invulnerability_left > 0 else 1.0
	$"../Highlight".visible = not eliminated
	queue_redraw()

func _draw() -> void:
	if eliminated:
		return
	if dodge_left > 0:
		draw_arc(Vector2.ZERO, 30, 0, TAU, 24, Color("#80efea"), 3.0, true)
	if invulnerability_left > 0:
		draw_rect(Rect2(-24,-24,48,48), Color(0.7,0.95,1,0.6), false, 1.5)
	if attack_frame >= 0 and attack != null:
		var active: bool = attack_frame > attack.startup_frames and attack_frame <= attack.startup_frames+attack.active_frames
		var color: Color = Color("#fff2a0") if active else Color(1,0.7,0.25,0.35)
		draw_circle(hitbox.position, attack.radius, Color(color,0.2 if active else 0.06))
		draw_arc(hitbox.position,attack.radius,0,TAU,24,color,2.0,true)
