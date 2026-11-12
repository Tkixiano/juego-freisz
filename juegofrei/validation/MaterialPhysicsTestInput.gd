extends Node
## Dispatch synthetic input inside a defined physics tick, before the real Player.
## physics_frame coroutines can resume before Godot increments its input tick.
var events: Array[InputEventAction] = []
var trace: Array = []
func _ready() -> void: process_physics_priority = -100
func _physics_process(_delta: float) -> void:
	for event: InputEventAction in events:
		# action_press is synchronous; parse_input_event may buffer until render.
		if event.pressed: Input.action_press(event.action,event.strength)
		else: Input.action_release(event.action)
		trace.append({"tick":Engine.get_physics_frames(),"action":event.action,"pressed":event.pressed,"just":Input.is_action_just_pressed(event.action)})
		if trace.size()>12: trace.pop_front()
	events.clear()
