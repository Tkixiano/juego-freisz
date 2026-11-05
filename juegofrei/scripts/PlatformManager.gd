extends Node
const Platform = preload("res://scripts/DynamicPlatform.gd")
enum ControlMode { MOUSE, EXTERNAL }
signal control_mode_changed(mode: int)
@export var control_mode: ControlMode = ControlMode.MOUSE
## Pose command boundary: no mouse, network, scale or geometry dependencies.
@export var platform_root: NodePath = ^"../Arena"
signal platform_detection_changed(id: StringName, detected: bool)
var platforms: Dictionary[StringName, Platform] = {}

func _ready() -> void:
	for candidate: Node in get_node(platform_root).find_children("*", "AnimatableBody2D", true, false):
		if candidate is Platform:
			var platform: Platform = candidate as Platform
			if platforms.has(platform.platform_id):
				push_error("Duplicate platform ID: %s" % platform.platform_id)
				continue
			platforms[platform.platform_id] = platform
	if control_mode == ControlMode.EXTERNAL:
		for id: StringName in platforms:
			_set_detection(id, false)

func set_control_mode(mode: int) -> void:
	if mode not in [ControlMode.MOUSE, ControlMode.EXTERNAL] or mode == control_mode:
		return
	control_mode = mode as ControlMode
	for id: StringName in platforms:
		var platform: Platform = platforms[id]
		platform.freeze_motion()
		_set_detection(id, mode == ControlMode.MOUSE)
	control_mode_changed.emit(mode)

func get_platform(id: StringName) -> Platform:
	return platforms.get(id) as Platform

func update_platform_position(id: StringName, point: Vector2, source: int = ControlMode.MOUSE) -> bool:
	if source != control_mode:
		return false
	var platform: Platform = get_platform(id)
	if platform == null or not platform.detected or not point.is_finite():
		return false
	platform.set_pose_target(point, platform.target_rotation)
	return true

func update_platform_rotation(id: StringName, angle: float, source: int = ControlMode.MOUSE) -> bool:
	if source != control_mode:
		return false
	var platform: Platform = get_platform(id)
	if platform == null or not platform.detected or not is_finite(angle):
		return false
	platform.set_pose_target(platform.target_position, angle)
	return true

func update_platform_transform(id: StringName, pose: Transform2D, source: int = ControlMode.MOUSE) -> bool:
	if source != control_mode:
		return false
	# Reject scale, skew and reflection instead of silently changing geometry.
	if not pose.is_finite() or not pose.x.is_normalized() or not pose.y.is_normalized() or absf(pose.x.dot(pose.y)) > 0.0001 or pose.determinant() < 0.9999:
		return false
	var platform: Platform = get_platform(id)
	if platform == null or not platform.detected:
		return false
	platform.set_pose_target(pose.origin, pose.get_rotation())
	return true

func update_platform_detection(id: StringName, detected: bool, source: int = ControlMode.MOUSE) -> bool:
	if source != control_mode:
		return false
	return _set_detection(id, detected)

func _set_detection(id: StringName, detected: bool) -> bool:
	var platform: Platform = get_platform(id)
	if platform == null:
		return false
	if platform.detected != detected:
		platform.detected = detected
		# Neither losing nor reacquiring detection resumes a stale target.
		platform.set_pose_target(platform.global_position,platform.global_rotation)
		if not detected:
			platform.freeze_motion()
		platform_detection_changed.emit(id,detected)
	return true

func get_platform_state(id: StringName) -> Dictionary:
	var platform: Platform = get_platform(id)
	if platform == null:
		return {}
	return {"id":id,"position":platform.global_position,"rotation":platform.global_rotation,"detected":platform.detected}
