extends CharacterBody2D
const Movement = preload("res://scripts/PlayerMovement.gd")
const Combat = preload("res://scripts/CombatController.gd")
enum State { IDLE, RUN, JUMP, FALL, ATTACK, DODGE, HITSTUN, RESPAWN, ELIMINATED }
var state: State = State.IDLE
@onready var combat: Combat = $Combat
signal respawned(player_id: int)

@export_range(1, 2) var player_id: int = 1
@export var body_color: Color = Color("#53a5ff")
@export var movement: Movement = Movement.new()

var jumps_used: int = 0
var coyote_left: float = 0.0
var buffer_left: float = 0.0
var drop_left: float = 0.0
var spawn_position: Vector2
var jump_action: StringName
var down_action: StringName
var left_action: StringName
var right_action: StringName
@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	# Keep upward carry on jumps; downward platform velocity must not shorten jumps.
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_ADD_UPWARD_VELOCITY
	floor_snap_length = 8.0
	floor_max_angle = deg_to_rad(46.0)
	spawn_position = global_position
	var prefix: String = "p%d_" % player_id
	left_action = StringName(prefix + "left")
	right_action = StringName(prefix + "right")
	jump_action = StringName(prefix + "jump")
	down_action = StringName(prefix + "down")
	visual.color = body_color
	$Highlight.color = body_color.lightened(0.5)
	$Identifier.text = "P%d" % player_id

func _physics_process(delta: float) -> void:
	if combat.eliminated:
		state = State.ELIMINATED
		return
	if not combat.tick(delta):
		# Freeze voluntary/launch motion while retaining native moving-platform carry.
		var saved_velocity: Vector2 = velocity
		velocity = Vector2.ZERO
		move_and_slide()
		velocity = saved_velocity
		_cancel_descending_on_contact()
		_update_state()
		return
	if combat.hitstun_left > 0 or combat.dodge_left > 0 or combat.respawn_left > 0 or combat.match_locked:
		_forced_motion(delta)
		_update_state()
		return
	var grounded: bool = is_on_floor()
	drop_left = maxf(0.0, drop_left - delta)
	set_collision_mask_value(2, drop_left <= 0.0)
	buffer_left = maxf(0.0, buffer_left - delta)
	if grounded:
		coyote_left = movement.coyote_time
		jumps_used = 0
	else:
		coyote_left = maxf(0.0, coyote_left - delta)
	if Input.is_action_just_pressed(jump_action):
		buffer_left = movement.jump_buffer

	# Only ignore the one-way layer: the main floor remains solid.
	if combat.attack_frame < 0 and grounded and Input.is_action_just_pressed(down_action) and _on_one_way():
		drop_left = movement.drop_time
		set_collision_mask_value(2, false)
		position.y += 3.0
		velocity.y = 100.0
		coyote_left = 0.0
		buffer_left = 0.0
		jumps_used = 1
		grounded = false

	var direction: float = Input.get_axis(left_action, right_action)
	velocity.x = movement.horizontal(velocity.x, direction, grounded, delta)
	if grounded and combat.attack_frame >= 0:
		velocity.x = move_toward(velocity.x, 0.0, movement.deceleration * delta)
	if not grounded:
		velocity.y = movement.vertical(velocity.y,Input.get_action_strength(down_action),delta)
		if combat.is_descending_attack():
			var target: float = minf(combat.attack.descent_speed,movement.fast_fall_speed)
			velocity.y = move_toward(velocity.y,target,combat.attack.descent_acceleration*delta)
			velocity.y = minf(velocity.y,target)

	if buffer_left > 0.0 and drop_left <= 0.0 and combat.attack_frame < 0:
		if grounded or coyote_left > 0.0:
			_jump(movement.jump_speed, 1)
		elif jumps_used < 2:
			# Walking off an edge consumes the ground jump after coyote expires.
			_jump(movement.double_jump_speed, 2)
	if Input.is_action_just_released(jump_action) and velocity.y < 0.0:
		velocity.y *= movement.jump_cut_multiplier
	move_and_slide()
	_cancel_descending_on_contact()
	_update_state()

func _cancel_descending_on_contact() -> void:
	if is_on_floor() and combat.is_descending_attack():
		combat.cancel_attack(true,true)

func _jump(impulse: float, count: int) -> void:
	velocity.y = -impulse
	jumps_used = count
	coyote_left = 0.0
	buffer_left = 0.0

func _on_one_way() -> bool:
	for index: int in range(get_slide_collision_count()):
		var hit: KinematicCollision2D = get_slide_collision(index)
		var collider: Node = hit.get_collider() as Node
		if hit.get_normal().y < -0.5 and collider != null and collider.is_in_group("one_way_platforms"):
			return true
	return false

func respawn() -> void:
	global_position = spawn_position
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	jumps_used = 0
	coyote_left = 0.0
	buffer_left = 0.0
	drop_left = 0.0
	set_collision_mask_value(2, true)
	visible = true
	collision_mask = 3
	combat.reset_after_respawn()
	respawned.emit(player_id)

func _forced_motion(delta: float) -> void:
	drop_left = maxf(0.0, drop_left - delta)
	set_collision_mask_value(2, drop_left <= 0)
	buffer_left = 0.0
	if combat.dodge_left > 0:
		velocity = combat.dodge_vector * combat.dodge_speed * clampf(combat.dodge_left / combat.dodge_duration,0.0,1.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, combat.knockback_drag * delta if combat.hitstun_left > 0 else movement.deceleration * delta)
		var gravity: float = movement.ascent_gravity if velocity.y < 0 else movement.descent_gravity
		velocity.y = minf(velocity.y + gravity * delta, movement.fast_fall_speed if combat.hitstun_left > 0 else movement.terminal_speed)
	move_and_slide()

func _update_state() -> void:
	if combat.eliminated:
		state = State.ELIMINATED
	elif combat.respawn_left > 0:
		state = State.RESPAWN
	elif combat.hitstun_left > 0:
		state = State.HITSTUN
	elif combat.dodge_left > 0:
		state = State.DODGE
	elif combat.attack_frame >= 0:
		state = State.ATTACK
	elif is_on_floor():
		state = State.RUN if absf(velocity.x) > 1.0 else State.IDLE
	else:
		state = State.JUMP if velocity.y < 0 else State.FALL

func eliminate() -> void:
	combat.cancel_attack()
	combat.eliminated = true
	combat.match_locked = true
	velocity = Vector2.ZERO
	collision_mask = 0
	visible = false
	state = State.ELIMINATED
