extends Node2D
@onready var replay: Node = $Replay
@onready var adapter: Node = $Adapter
@onready var files: OptionButton = $UI/Panel/Files
@onready var status: Label = $UI/Status
var refresh: float = 0.0
var selection_generation: int = 0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#101c2b"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/replays/manifest.json"))
	for scenario: Dictionary in manifest.scenarios: files.add_item(scenario.file)
	files.item_selected.connect(_select)
	$UI/Panel/Play.pressed.connect(replay.play)
	$UI/Panel/Pause.pressed.connect(replay.pause)
	$UI/Panel/Restart.pressed.connect(replay.restart)
	$UI/Panel/Step.pressed.connect(replay.step)
	$UI/Panel/Speed.item_selected.connect(_speed)
	_select(0)

func _select(index: int) -> void:
	selection_generation += 1
	var generation: int = selection_generation
	replay.pause()
	# A file switch is a new replay session and resets sequence/version ledgers.
	if not adapter.pending_frame.is_empty(): adapter.request_reset()
	await get_tree().physics_frame
	await get_tree().process_frame
	if generation!=selection_generation: return
	replay.load_replay("res://validation/replays/"+files.get_item_text(index))

func _speed(index: int) -> void:
	replay.set_speed([0.25,0.5,1.0,2.0][index])

func _process(delta: float) -> void:
	refresh += delta
	if refresh<0.15: return
	refresh = 0
	if not files.get_popup().visible:
		for i: int in range(files.item_count):
			if files.get_item_text(i)==replay.loaded_path.get_file() and files.selected!=i: files.select(i)
	var speed_menu: OptionButton = $UI/Panel/Speed
	if not speed_menu.get_popup().visible:
		var speeds: Array[float] = [0.25,0.5,1.0,2.0]
		for i: int in range(speeds.size()):
			if is_equal_approx(replay.speed,speeds[i]) and speed_menu.selected!=i: speed_menu.select(i)
	var s: Dictionary = adapter.get_status()
	status.text = "Offline | frame %d/%d | seq %d | %.1fx\nObjetos %d | formas %d | reconstrucciones %d\nRecibidos %d | aplicados %d | rechazados %d | diferidos %d\nConflicto: %s\nA/D: mover  W: saltar. Pausa detiene la reproduccion, no al personaje." % [replay.cursor,replay.frames.size(),s.applied_sequence,replay.speed,s.active_objects,s.physical_shapes,s.geometry_rebuilds,s.metrics.received,s.metrics.applied,s.metrics.rejected,s.metrics.deferred,$DynamicGeometry.last_conflict]
