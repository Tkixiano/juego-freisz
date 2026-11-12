extends "res://scripts/GameManager.gd"
const Contact = preload("res://scripts/material_physics/MaterialContactAdapter.gd")
var samples: int = 0
var penetrations: int = 0
var inner: RectangleShape2D = RectangleShape2D.new()
var update_us: Array[int] = []
var previous_support: Dictionary = {}
var support_transitions: int = 0
var unexpected_support_losses: int = 0
func _ready() -> void:
	super._ready()
	inner.size = Vector2(38,38)
	# Retain legacy resources, but no original collider participates in this match.
	for name: String in ["Ground","LeftPlatform","RightPlatform","TopPlatform"]:
		var body: Node = get_node("Arena/"+name)
		body.process_mode = Node.PROCESS_MODE_DISABLED;body.collision_layer = 0;body.collision_mask = 0;body.hide()
		body.get_node("CollisionShape2D").disabled = true
	for player: Node in players:
		player.get_node("UnstuckGuard").set_physics_process(false)
		var contact: Node = Contact.new();contact.name = "MaterialContact";player.add_child(contact)
	$UI/HUD/PlatformEditor.hide();$UI/HUD/EditorStatus.hide()
	$UI/HUD/Help.text = "VERDE sólido · AZUL rebote · NARANJA atravesable · Abajo: descenso · Doble salto"
	$Adapter.batch_result.connect(_geometry_published)
	$GameShell/Screen/ControlsText.text = "J1: A/D mover · W salto · S descenso · F/G golpes · H defensa/dash\nJ2: flechas · K/L golpes · Shift derecho defensa/dash\nArriba/abajo + ataque: direccional · Doble salto\nVerde sólido · Azul rebote · Naranja atravesable\nESC pausa · F1 controles · R reiniciar partida\nFuente OFFLINE / UDP desde el panel de escenario."
	$Sources.initialize()
	$UI/SourcePanel.initialize()
func _geometry_published(_seq: int,status: String,_reason: String) -> void:
	if status=="APPLIED":
		for id: StringName in $DynamicGeometry.object_ids():$DynamicGeometry.get_body(id).identifier.hide()
func restart_match() -> void:
	$SafeSpawn.pending.clear()
	super.restart_match()
func _on_respawned(id: int) -> void:
	super._on_respawned(id)
	$SafeSpawn.request(players[id-1])
func _physics_process(delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	super._physics_process(delta)
	for p: Node in players:
		if p.collision_mask==0 or not p.is_physics_processing():previous_support.erase(p.player_id);continue
		samples += 1
		if previous_support.has(p.player_id) and not p.is_on_floor():
			support_transitions += 1
			if $SceneSource.applied_state=="SCENE_ACTIVE" and previous_support[p.player_id]!= $Adapter.applied_sequence and p.velocity.y>=0 and p.combat.respawn_left<=0 and p.combat.hitstun_left<=0 and p.combat.dodge_left<=0 and not Input.is_action_pressed(p.jump_action) and not Input.is_action_pressed(p.down_action) and Input.get_axis(p.left_action,p.right_action)==0:unexpected_support_losses += 1
		previous_support.erase(p.player_id)
		if p.is_on_floor() and p.combat.respawn_left<=0:previous_support[p.player_id] = $Adapter.applied_sequence
		for id: StringName in $DynamicGeometry.object_ids():
			var body: Node = $DynamicGeometry.get_body(id)
			if body.material_kind!="ORANGE_ONE_WAY" and body.overlaps_character(inner,p.get_node("CollisionShape2D").global_transform):penetrations += 1;break
	update_us.append(Time.get_ticks_usec()-start)
	if update_us.size()>4096:update_us.pop_front()
