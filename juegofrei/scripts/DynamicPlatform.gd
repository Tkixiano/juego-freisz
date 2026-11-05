extends AnimatableBody2D
## Geometry belongs to the authored scene. Runtime commands only set pose targets.
@export var platform_id: StringName = &"platform"
@export var max_linear_speed: float = 180.0
@export var max_angular_speed: float = 0.70
@export var response: float = 8.0
@export var max_surface_step: float = 4.0
@export var movement_bounds: Rect2 = Rect2(150, 180, 980, 340)
var target_position: Vector2
var target_rotation: float
var detected: bool = true
var was_moving: bool = false
var selected: bool = false
var editor_visible: bool = true
var home_transform: Transform2D
var surface_radius: float = 120.0
@onready var visual: Polygon2D = $Visual
@onready var identifier: Label = $Identifier

func _ready() -> void:
	process_physics_priority = -20
	home_transform = global_transform
	target_position = global_position
	target_rotation = global_rotation
	sync_to_physics = true
	identifier.text = String(platform_id)
	for point: Vector2 in visual.polygon:
		surface_radius = maxf(surface_radius, point.length())
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not detected or (global_position.distance_squared_to(target_position) < 0.000001 and absf(angle_difference(global_rotation,target_rotation)) < 0.000001):
		if was_moving:
			# One final stationary submission clears the native carrier velocity.
			global_transform = global_transform
			was_moving = false
		return
	was_moving = true
	var weight: float = 1.0 - exp(-response * delta)
	var linear_step: Vector2 = ((target_position - global_position) * weight).limit_length(max_linear_speed * delta)
	var angle_step: float = clampf(angle_difference(global_rotation, target_rotation) * weight, -max_angular_speed * delta, max_angular_speed * delta)
	# Bound the total swept distance of the outermost point, including rotation.
	var sweep: float = linear_step.length() + absf(angle_step) * surface_radius
	var ratio: float = minf(1.0, max_surface_step / maxf(sweep, 0.00001))
	# sync_to_physics restores the previous pose after each transform write.
	# Commit translation and rotation together so neither cancels the other.
	global_transform = Transform2D(global_rotation + angle_step * ratio, global_position + linear_step * ratio)

func set_pose_target(point: Vector2, angle: float) -> void:
	target_position = Vector2(clampf(point.x, movement_bounds.position.x, movement_bounds.end.x), clampf(point.y, movement_bounds.position.y, movement_bounds.end.y))
	target_rotation = wrapf(angle, -PI, PI)

func freeze_motion() -> void:
	# Read the authoritative physics pose, not a transform awaiting native sync.
	# Pausing must not replay the cached kinematic step on the next physics tick.
	var pose: Transform2D = PhysicsServer2D.body_get_state(get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM)
	sync_to_physics = false
	global_transform = pose
	PhysicsServer2D.body_set_state(get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,pose)
	PhysicsServer2D.body_set_state(get_rid(),PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,Vector2.ZERO)
	PhysicsServer2D.body_set_state(get_rid(),PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY,0.0)
	sync_to_physics = true
	target_position = pose.origin
	target_rotation = pose.get_rotation()
	was_moving = false
	reset_physics_interpolation()

func set_highlight(value: bool, show_editor: bool) -> void:
	selected = value
	editor_visible = show_editor
	identifier.visible = show_editor
	queue_redraw()

func contains_world_point(point: Vector2) -> bool:
	# Uses authored visual outline, also works with future irregular polygons.
	return Geometry2D.is_point_in_polygon(to_local(point), visual.polygon)

func _draw() -> void:
	if selected and editor_visible and is_instance_valid(visual):
		var outline: PackedVector2Array = visual.polygon.duplicate()
		if not outline.is_empty():
			outline.append(outline[0])
			draw_polyline(outline, Color("#f4f8ff"), 3.0, true)
		draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
