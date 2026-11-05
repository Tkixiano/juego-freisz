extends Node2D
const Player = preload("res://scripts/PlayerController.gd")
const Effects = preload("res://scripts/CombatEffects.gd")
signal stock_lost(player_id: int, remaining: int)
signal match_ended(winner_id: int)
@export var elimination_bounds: Rect2 = Rect2(-100, -180, 1480, 1060)
@onready var players: Array[Node] = [$Players/Player1, $Players/Player2]
@onready var effects: Effects = $CombatEffects
var returns: Array[int] = [0, 0]
var game_over: bool = false
var winner_id: int = -1
var pending_hits: Array[Dictionary] = []
@onready var hud_labels: Array[Label] = [$UI/HUD/CombatP1,$UI/HUD/CombatP2]
var last_percent: Array[float] = [-1,-1]
var last_stocks: Array[int] = [-1,-1]
var last_phase: Array[String] = ["",""]
var last_returns: Vector2i = Vector2i(-1,-1)

func _ready() -> void:
	process_physics_priority = 20
	for player: Player in players:
		player.respawned.connect(_on_respawned)
		player.combat.impact.connect(effects.burst)
		player.combat.damage_model.reset_match()
	_update_hud()

func _physics_process(_delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("match_restart"):
			restart_match()
	else:
		_resolve_combat_hits()
		for player: Player in players:
			if not player.combat.eliminated and not elimination_bounds.has_point(player.global_position):
				_lose_stock(player)
		var alive_count: int = 0
		var survivor: int = 0
		for player: Player in players:
			if player.combat.damage_model.stocks > 0:
				alive_count += 1
				survivor = player.player_id
		if alive_count < 2:
			_finish_match(survivor if alive_count==1 else 0)
	_update_hud()

func queue_combat_hit(source: Node, target: Node, data: Resource, direction: Vector2, point: Vector2) -> void:
	if not game_over:
		pending_hits.append({"source":source,"target":target,"data":data,"direction":direction,"point":point,"serial":int(source.get("attack_serial"))})

func _resolve_combat_hits() -> void:
	# GameManager runs after both players. Capture candidates before applying
	# cancellation/hitstop, so tree order cannot decide a simultaneous exchange.
	for hit: Dictionary in pending_hits:
		var source: Node = hit["source"]
		var target: Node = hit["target"]
		if is_instance_valid(source) and is_instance_valid(target) and int(hit["serial"])!=int(source.get("cancelled_attack_serial")) and bool(target.call("receive_hit", hit["data"], hit["direction"])):
			source.call("confirm_hit", hit["data"], hit["point"])
	pending_hits.clear()

func _lose_stock(player: Player) -> void:
	var remaining: int = player.combat.damage_model.lose_stock()
	stock_lost.emit(player.player_id, remaining)
	if remaining > 0:
		player.respawn()
	else:
		player.eliminate()

func _finish_match(winner: int) -> void:
	game_over = true
	winner_id = winner
	for player: Player in players:
		player.combat.cancel_attack()
		player.combat.match_locked = true
	$UI/HUD/Victory.visible = true
	$UI/HUD/Victory/Message.text = ("¡GANA EL JUGADOR %d!" % winner if winner > 0 else "¡EMPATE!") + "\n\nR  ·  Reiniciar partida"
	match_ended.emit(winner)

func restart_match() -> void:
	pending_hits.clear()
	$GameShell.enter_game()
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("p1_") or String(action).begins_with("p2_"):
			Input.action_release(action)
	$MousePlatformController.dragging = false
	game_over = false
	winner_id = -1
	returns[0] = 0
	returns[1] = 0
	for player: Player in players:
		player.combat.damage_model.reset_match()
		player.respawn()
	# Keep the third person's current platform layout.
	returns[0] = 0
	returns[1] = 0
	$UI/HUD/Victory.visible = false

func _on_respawned(player_id: int) -> void:
	returns[player_id-1] += 1

func _update_hud() -> void:
	for player: Player in players:
		var index: int = player.player_id-1
		var percent: float = player.combat.damage_model.percent
		var stocks: int = player.combat.damage_model.stocks
		var phase: String = player.combat.phase()
		if percent != last_percent[index] or stocks != last_stocks[index] or phase != last_phase[index]:
			last_percent[index] = percent
			last_stocks[index] = stocks
			last_phase[index] = phase
			hud_labels[index].text = "P%d   %03.0f%%    VIDAS %d\n%s" % [player.player_id,percent,stocks,phase]
	if last_returns != Vector2i(returns[0],returns[1]):
		last_returns = Vector2i(returns[0],returns[1])
		$UI/HUD/Returns.text = "REAPARICIONES   P1  %02d    /    P2  %02d" % [returns[0],returns[1]]
