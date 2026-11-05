extends Node
## Local bounded JSON file -> full snapshots; no networking or capture.
@export var adapter_path: NodePath = NodePath("../Adapter")
@onready var adapter: Node = get_node(adapter_path)
var frames: Array = []
var cursor: int = 0
var playing: bool = false
var speed: float = 1.0
var hz: float = 30
var accumulator: float = 0.0
var errors: Array[Dictionary] = []
var loaded_path: String = ""
var step_requested: bool = false

func _ready() -> void:
	process_physics_priority = -60
	adapter.batch_result.connect(_batch_result)
	adapter.manager.motion_paused = true

func _batch_result(_seq: int,status: String,_reason: String) -> void:
	if not playing and status in ["APPLIED","REJECTED","CANCELLED"]: adapter.manager.motion_paused = true

func _error(reason: String) -> bool:
	errors.append({"category":"replayer","reason":reason,"cursor":cursor})
	if errors.size()>128: errors.pop_front()
	return false

func load_replay(path: String) -> bool:
	if playing or not adapter.pending_frame.is_empty(): return _error("load_while_active")
	if not path.begins_with("res://") and not path.begins_with("user://"): return _error("local_resource_path_required")
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>33554432: return _error("file_missing_or_size_limit")
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text())!=OK: return _error("invalid_json")
	var data: Variant = parser.data
	if not data is Dictionary or data.get("replay_version")!=1 or data.get("geometry_contract_version")!=1 or data.get("synthetic_only")!=true or not data.get("frames") is Array: return _error("replay_header")
	if not adapter.manager.CompoundValidator.number(data.get("tick_hz")) or float(data.tick_hz)<1 or float(data.tick_hz)>120 or data.frames.is_empty() or data.frames.size()>10000: return _error("frame_count_or_hz")
	frames = data.frames
	hz = float(data.tick_hz)
	speed = minf(speed,Engine.physics_ticks_per_second/hz)
	cursor = 0
	accumulator = 0
	loaded_path = path
	adapter.request_reset()
	return true

func play() -> void:
	if not frames.is_empty():
		playing = true
		adapter.manager.motion_paused = false

func pause() -> void:
	playing = false
	adapter.manager.motion_paused = true

func restart() -> void:
	playing = false
	adapter.manager.motion_paused = true
	cursor = 0
	accumulator = 0
	step_requested = false
	adapter.request_reset()

func step() -> void:
	playing = false
	step_requested = true

func set_speed(value: float) -> bool:
	if not is_finite(value) or value<0.1 or value>minf(4.0,Engine.physics_ticks_per_second/hz): return _error("speed_range_or_physics_limit")
	speed = value
	return true

func _physics_process(delta: float) -> void:
	if adapter.reset_requested or not adapter.pending_frame.is_empty(): return
	if cursor>=frames.size():
		playing = false
		step_requested = false
		return
	if not playing and not step_requested: return
	if playing: accumulator += delta*speed
	if not step_requested and accumulator<1.0/hz: return
	accumulator = 0.0 if step_requested else maxf(0.0,accumulator-1.0/hz)
	step_requested = false
	adapter.manager.motion_paused = false
	if not frames[cursor] is Dictionary:
		_error("frame_not_dictionary")
	else:
		adapter.submit(frames[cursor])
	cursor += 1
	# At most ONE transaction per physics tick; speed never skips topology states.
	accumulator = minf(accumulator,1.0/hz)

func get_status() -> Dictionary:
	return {"path":loaded_path,"cursor":cursor,"frames":frames.size(),"playing":playing,"speed":speed,"logical_time":float(frames[cursor-1].get("logical_time",0)) if cursor>0 and frames[cursor-1] is Dictionary else 0.0,"errors":errors.duplicate(true)}
