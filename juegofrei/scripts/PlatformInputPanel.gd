extends VBoxContainer
const Manager = preload("res://scripts/PlatformManager.gd")
@onready var manager: Manager = get_node("../../PlatformManager") as Manager
@onready var receiver: Node = get_node("../../ExternalPlatformReceiver")
@onready var mode_button: Button = $ModeButton
@onready var status: Label = $Status
var refresh_left: float = 0
var diagnostics_visible: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mode_button.pressed.connect(toggle_mode)
	call_deferred("_refresh")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		diagnostics_visible = not diagnostics_visible
		status.visible = diagnostics_visible
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("platform_control_mode"):
		toggle_mode()
		get_viewport().set_input_as_handled()

func toggle_mode() -> void:
	manager.set_control_mode(Manager.ControlMode.EXTERNAL if manager.control_mode==Manager.ControlMode.MOUSE else Manager.ControlMode.MOUSE)
	_refresh()

func _physics_process(delta: float) -> void:
	refresh_left -= delta
	if refresh_left <= 0:
		refresh_left = 0.1
		_refresh()

func _refresh() -> void:
	var info: Dictionary = receiver.diagnostics()
	mode_button.text = "Plataformas: %s  ·  F2 cambiar" % info.mode
	if not diagnostics_visible:
		return
	var age: String = "—" if info.age_seconds < 0 else "%.0f ms" % (info.age_seconds*1000)
	status.text = "UDP %s · Rx %.1f / aplica %.1f Hz\nSecuencia %d · Módulos %d/%d · %s\nEdad local %s (no latencia E2E)" % [info.udp,info.packets_per_second,info.updates_per_second,info.last_sequence,info.detected,info.known,info.tracking,age]
	var module_text: PackedStringArray=[]
	for id: String in ["left","right"]:
		var state: Dictionary=info.modules[id]
		var state_text: String="MANUAL" if info.mode=="MOUSE" else ("OK" if state.detected else "LOST")
		var module_age: String="—" if state.age_seconds<0 else "%.0fms" % (state.age_seconds*1000)
		module_text.append("ID%d %s %s %s #%d" % [1 if id=="left" else 2,id,state_text,module_age,state.transform_updates])
	status.text += "\n"+" / ".join(module_text)
	status.text += "\nCoordenadas %s · Fuera de arena %d" % [info.coordinate_space,info.outside_arena]
	if info.packet_age_ms >= 0:
		var source_age: String="—" if info.source_age_ms<0 else "%.0fms" % info.source_age_ms
		status.text += "\nEdad paquete %.0fms · Frame a TX %s" % [info.packet_age_ms,source_age]
	if not info.lost.is_empty():
		status.text += "\nSin seguimiento: "+", ".join(info.lost)
