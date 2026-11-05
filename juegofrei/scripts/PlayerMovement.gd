extends Resource
## Tuning shared by both fighters. All values are pixels and seconds.
@export var speed: float = 410.0
@export var acceleration: float = 3200.0
@export var deceleration: float = 3800.0
@export_range(0.0, 1.0) var air_control: float = 0.72
@export var ascent_gravity: float = 1250.0
@export var descent_gravity: float = 1450.0
@export var jump_speed: float = 650.0
@export var double_jump_speed: float = 620.0
@export var terminal_speed: float = 640.0
@export var fast_fall_speed: float = 800.0
@export var fast_fall_acceleration: float = 2100.0
@export var fast_fall_release_brake: float = 1800.0
@export var jump_cut_multiplier: float = 0.46
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.12
@export var drop_time: float = 0.20

func horizontal(current: float, direction: float, grounded: bool, delta: float) -> float:
	var rate: float = acceleration if direction != 0.0 else deceleration
	if not grounded:
		rate *= air_control
	return move_toward(current, direction * speed, rate * delta)

func vertical(current: float, down_strength: float, delta: float) -> float:
	if current < 0.0:
		return current + ascent_gravity * delta
	var pressure: float = clampf(down_strength,0.0,1.0)
	var limit: float = lerpf(terminal_speed,fast_fall_speed,pressure)
	var gravity: float = lerpf(descent_gravity,fast_fall_acceleration,pressure)
	# Releasing down eases back to normal fall speed instead of snapping.
	if current > limit:
		return move_toward(current,limit,fast_fall_release_brake * delta)
	return minf(current + gravity * delta,limit)
