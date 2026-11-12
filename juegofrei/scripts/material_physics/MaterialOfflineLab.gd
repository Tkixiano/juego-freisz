extends "res://scripts/material_physics/MaterialPhysicsLab.gd"
## Reuses the material lab's Player, combat resolver, bodies and measurements.
var selected_file: int = 0
var selection_generation: int = 0
var offline_refresh: float = 0
var event_history: Array = []
var manifest: Array = []

func _ready() -> void:
	# Override load_home below prevents installing the original lab fixtures.
	super._ready()
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://validation/material_replays/manifest.json")).scenarios
	for entry: Dictionary in manifest: $UI/Panel/Files.add_item(entry.file)
	$UI/Panel/Files.item_selected.connect(select_file)
	$UI/Panel/Play.pressed.connect($Replay.play)
	$UI/Panel/Pause.pressed.connect($Replay.pause)
	$UI/Panel/Restart.pressed.connect($Replay.restart)
	$UI/Panel/Step.pressed.connect($Replay.step)
	$UI/Panel/Speed.item_selected.connect(func(i: int) -> void:$Replay.set_speed([0.25,0.5,1.0,2.0][i]))
	adapter.batch_result.connect(_accepted)

func load_home() -> void:
	await get_tree().physics_frame
	select_file(selected_file)

func select_file(index: int) -> void:
	selection_generation += 1
	var generation: int = selection_generation
	selected_file = index
	$Replay.pause();adapter.request_reset()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if generation!=selection_generation: return
	event_history.clear()
	$Replay.load_replay("res://validation/material_replays/"+manifest[index].file)
	for p: Node in players: p.respawn()
	$UI/Panel/Files.select(index)

func _accepted(seq: int,status: String,reason: String) -> void:
	if status=="APPLIED":
		for event: Dictionary in adapter.logical_events:
			event_history.append({"sequence":seq,"event":event.duplicate(true)})
	elif status in ["REJECTED","DEFERRED"]: event_history.append({"sequence":seq,"status":status,"reason":reason})
	while event_history.size()>8: event_history.pop_front()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	offline_refresh -= delta
	if offline_refresh>0: return
	offline_refresh = 0.2
	var replay: Node = $Replay
	var s: Dictionary = adapter.get_status()
	var summaries: Array[String] = []
	for row: Dictionary in event_history: summaries.append("S%d %s" % [row.sequence,row.event.type if row.has("event") else row.status])
	var events: String = " | ".join(summaries)
	var a: Dictionary = players[0].get_node("MaterialContact").metrics
	var b: Dictionary = players[1].get_node("MaterialContact").metrics
	var reader_error: String = "—" if replay.errors.is_empty() else replay.errors[-1].reason
	$UI/Status.tooltip_text = JSON.stringify({"events":event_history,"replayer_errors":replay.errors},"  ")
	$UI/Status.text = "Archivo %s · estado %d/%d · %.2fx · %s\nEstructuras %d · regiones %d · formas %d · reconstrucciones %d\nRecibidos %d · aplicados %d · rechazados %d · diferidos %d · MERGE %d / SPLIT %d\nConflicto: %s · penetraciones >1px: %d · pérdidas de apoyo: %d\nRebotes J1/J2 %d/%d · descensos %d/%d · último error lector: %s\nEventos: %s\nJ1 A/D W S F/G H · J2 flechas K/L Shift der. · La pausa detiene los datos, no a los jugadores." % [replay.loaded_path.get_file(),replay.cursor,replay.frames.size(),replay.speed,"REPRODUCIENDO" if replay.playing else "PAUSA",s.logical_structures,s.material_regions,s.physical_shapes,s.geometry_rebuilds,s.logical_metrics.received,s.metrics.applied,s.logical_metrics.rejected,s.metrics.deferred,s.logical_metrics.merges,s.logical_metrics.splits,manager.last_conflict,physical_metrics.solid_penetration_frames_over_1px,physical_metrics.support_losses_during_motion,a.bounces,b.bounces,a.drops,b.drops,reader_error,events]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_R: $Replay.restart()
