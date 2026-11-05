extends Node2D
const Manager = preload("res://scripts/PlatformManager.gd")
const Platform = preload("res://scripts/DynamicPlatform.gd")
@export var manager_path: NodePath = ^"../PlatformManager"
@export var panel_path: NodePath = ^"../UI/HUD/PlatformEditor"
@export var status_path: NodePath = ^"../UI/HUD/EditorStatus"
@export var rotation_speed: float = 0.65
var selected_id: StringName = &""
var editing: bool = true
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var readout_left: float = 0.0
@onready var manager: Manager = get_node(manager_path) as Manager
@onready var panel: Label = get_node(panel_path) as Label
@onready var status: Label = get_node(status_path) as Label

func _ready() -> void:
	manager.control_mode_changed.connect(_on_control_mode_changed)

func _on_control_mode_changed(_mode: int) -> void:
	dragging = false
	_refresh_highlights()
	_refresh_readout()

func _unhandled_input(event: InputEvent) -> void:
	if manager.control_mode != Manager.ControlMode.MOUSE:
		return
	if event.is_action_pressed("editor_toggle"):
		set_editing(not editing)
		get_viewport().set_input_as_handled()
	elif editing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			select_at(get_canvas_transform().affine_inverse() * event.position)
		else:
			dragging = false
		get_viewport().set_input_as_handled()
	elif editing and dragging and event is InputEventMouseMotion:
		manager.update_platform_position(selected_id, get_canvas_transform().affine_inverse() * event.position + drag_offset)
		get_viewport().set_input_as_handled()

func select_at(point: Vector2) -> void:
	if manager.control_mode != Manager.ControlMode.MOUSE:
		dragging = false
		return
	selected_id = &""
	var ordered: Array = manager.platforms.values()
	ordered.reverse()
	for platform: Platform in ordered:
		if platform.contains_world_point(point):
			selected_id = platform.platform_id
			manager.update_platform_detection(selected_id,true)
			drag_offset = platform.global_position - point
			break
	dragging = not selected_id.is_empty()
	_refresh_highlights()

func set_editing(value: bool) -> void:
	editing = value
	dragging = false
	panel.visible = value
	_refresh_readout()
	_refresh_highlights()

func _refresh_highlights() -> void:
	for platform: Platform in manager.platforms.values():
		platform.set_highlight(platform.platform_id == selected_id, editing and manager.control_mode == Manager.ControlMode.MOUSE)

func _physics_process(delta: float) -> void:
	if manager.control_mode == Manager.ControlMode.MOUSE and editing and not selected_id.is_empty():
		var platform: Platform = manager.get_platform(selected_id)
		if platform != null:
			var direction: float = Input.get_axis("editor_rotate_left", "editor_rotate_right")
			if direction != 0.0:
				manager.update_platform_rotation(selected_id, platform.target_rotation + direction * rotation_speed * delta)
	readout_left -= delta
	if readout_left > 0:
		return
	readout_left = 0.1
	_refresh_readout()

func _refresh_readout() -> void:
	if manager.control_mode == Manager.ControlMode.EXTERNAL:
		status.text = "CONTROL EXTERNO · F2 para volver al mouse"
		panel.text = "ESCENARIO DINÁMICO\nPosición y rotación desde UDP · Mouse desactivado"
		return
	status.text = "EDICIÓN %s  ·  TAB mostrar / ocultar" % ("ACTIVA" if editing else "OCULTA")
	var selected: Platform = manager.get_platform(selected_id)
	if selected == null:
		panel.text = "ESCENARIO DINÁMICO\nClick en una plataforma para seleccionar\nArrastrá para mover  ·  Q / E para rotar"
	else:
		panel.text = "MÓDULO  %s\nPosición   %04.0f, %04.0f    Rotación   %+.1f°\nArrastrá para mover  ·  Q / E para rotar" % [selected_id, selected.position.x, selected.position.y, selected.rotation_degrees]

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
