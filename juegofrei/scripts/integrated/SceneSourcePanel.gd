extends Control
var game: Node
var manifest: Array = []
var selection_generation: int = 0
var refresh: float = 0
func initialize() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = get_tree().current_scene
	# In headless initialization current_scene may be assigned after ready.
	game = get_parent().get_parent()
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://validation/material_replays/manifest.json")).scenarios
	$Files.add_item("ESCENARIO VACÍO CONFIRMADO")
	for entry: Dictionary in manifest:$Files.add_item(entry.file)
	$Files.item_selected.connect(select_file)
	$Play.pressed.connect(_play_source)
	$Pause.pressed.connect(func() -> void:
		if game.get_node("Sources").mode=="OFFLINE":game.get_node("Replay").pause())
	$RestartSource.pressed.connect(_restart_source)
	$Step.pressed.connect(func() -> void:
		if game.get_node("Sources").mode=="OFFLINE":game.get_node("Replay").step())
	$Mode.item_selected.connect(func(index: int) -> void:
		game.get_node("Sources").select_mode("OFFLINE" if index==0 else "UDP")
		if index==0:select_file($Files.selected))
func _play_source() -> void:
	if game.get_node("Sources").mode!="OFFLINE":return
	if $Files.selected==0 and game.get_node("Replay").frames.is_empty():select_file(0)
	else:game.get_node("Replay").play()
func _restart_source() -> void:
	if game.get_node("Sources").mode!="OFFLINE":return
	if game.get_node("Replay").frames.is_empty():select_file($Files.selected)
	else:game.get_node("Replay").restart()
func select_file(index: int) -> void:
	if game.get_node("Sources").mode!="OFFLINE":return
	var source_generation: int = game.get_node("Sources").generation
	selection_generation += 1;var generation: int = selection_generation
	var replay: Node = game.get_node("Replay")
	replay.pause();game.get_node("SceneSource").request_reset()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if generation!=selection_generation or game.get_node("Sources").mode!="OFFLINE" or source_generation!=game.get_node("Sources").generation:return
	$Files.select(index)
	if index==0:
		# A synthetic, complete and explicitly confirmed empty source, not a timeout.
		replay.frames = [];replay.cursor = 0;replay.hz = 30;replay.replay_version = 2
		replay.session_id = "synthetic-empty";replay.loaded_path = "synthetic://confirmed_empty"
		for i: int in range(5):replay.frames.append({"session_id":"synthetic-empty","sequence":i+1,"logical_time":i/30.0,"structures":[],"identity_epochs":{},"region_identity_epochs":{},"events":[],"scene_state":"SCENE_EMPTY","diagnostic":{"status":"TRACKING"}})
		replay.play();return
	if replay.load_replay("res://validation/material_replays/"+manifest[index-1].file):replay.play()
func _process(delta: float) -> void:
	if game==null:return
	visible = game.get_node("GameShell").page==1
	var offline: bool = game.get_node("Sources").mode=="OFFLINE"
	for control: BaseButton in [$Files,$Play,$Pause,$RestartSource,$Step]:control.disabled = not offline
	$Mode.select(0 if offline else 1)
	refresh -= delta
	if refresh>0:return
	refresh = 0.2
	var gateway: Node = game.get_node("SceneSource");var floor_node: Node = game.get_node("SafetyFloor")
	var status: Dictionary = game.get_node("Adapter").get_status()
	$Status.text = "%s · estructuras %d · regiones %d · piso %s\nFuente OFFLINE · recibidos %d · aplicados %d · rechazados %d · diferidos %d\n%s · respawns pendientes %d" % [gateway.scene_state,status.logical_structures,status.material_regions,"ACTIVO" if floor_node.enabled else "RETIRADO",gateway.metrics.received,gateway.metrics.applied,gateway.metrics.rejected,gateway.metrics.deferred,floor_node.last_reason,game.get_node("SafeSpawn").pending.size()]
	if not offline:
		var udp: Dictionary = game.get_node("Sources").get_status()
		$Status.text = $Status.text.replace("Fuente OFFLINE","UDP 127.0.0.1:%d"%game.get_node("UdpTransport").port)
		$Status.text += "\nCola %d · secuencia aplicada %d · edad local %.0f ms · descartados %d" % [udp.queue_depth,udp.last_applied_sequence,udp.applied_state_age_ms,udp.metrics.coalesced+udp.metrics.expired+udp.metrics.superseded]
