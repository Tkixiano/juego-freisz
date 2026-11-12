extends Node2D
const Fixture = preload("res://scripts/material_physics/MaterialPhysicsFixtures.gd")
const Contact = preload("res://scripts/material_physics/MaterialContactAdapter.gd")
var players: Array[Node] = []
var sequence: int = 0
var moving: bool = false
var motion_clock: float = 0
var combat_resolver: Node
var stats_clock: float = 0
var inner_probe: RectangleShape2D = RectangleShape2D.new()
var previous_support: Dictionary = {}
var physical_metrics: Dictionary = {"solid_penetration_frames_over_1px":0,"support_losses_during_motion":0,"samples":0}
var penetration_events: Array[Dictionary] = []
@onready var manager: Node = $DynamicGeometry
@onready var adapter: Node = $Adapter

func _ready() -> void:
	process_physics_priority = 20
	combat_resolver = load("res://scripts/GameManager.gd").new()
	inner_probe.size = Vector2(38,38)
	RenderingServer.set_default_clear_color(Color("101925"))
	players = [$Players/Player1,$Players/Player2]
	for p: Node in players:
		p.get_node("UnstuckGuard").set_physics_process(false)
		var contact: Node = Contact.new();contact.name = "MaterialContact"
		p.add_child(contact)
		p.combat.impact.connect($CombatEffects.burst)
	load_home()

func load_home() -> void:
	adapter.request_reset()
	await get_tree().physics_frame
	await get_tree().physics_frame
	sequence = 0
	submit(Fixture.defaults())
	for p: Node in players: p.respawn()

func submit(structures: Array,events: Array=[]) -> Dictionary:
	sequence += 1
	var epochs: Dictionary = {}
	for c: Dictionary in structures: epochs[c.id] = 1
	return adapter.submit({"sequence":sequence,"logical_time":sequence/60.0,"structures":structures,"identity_epochs":epochs,"events":events})

func queue_combat_hit(source: Node,target: Node,data: Resource,direction: Vector2,point: Vector2) -> void:
	combat_resolver.queue_combat_hit(source,target,data,direction,point)

func _exit_tree() -> void:
	if is_instance_valid(combat_resolver): combat_resolver.free()

func _physics_process(delta: float) -> void:
	combat_resolver._resolve_combat_hits()
	_measure_physics()
	for p: Node in players:
		if p.position.y>900 or p.position.y< -700 or absf(p.position.x-640)>1300: p.respawn()
	if moving:
		motion_clock += delta
		if adapter.pending_frame.is_empty() and not adapter.reset_requested:
			var data: Array = []
			for c: Dictionary in adapter.logical_active.values():
				var next: Dictionary = c.duplicate(true)
				if c.id=="orange": next.position = [1020+sin(motion_clock)*50,480+sin(motion_clock*0.5)*30]
				if c.id=="green_orange": next.orientation_radians = sin(motion_clock*0.6)*0.25
				data.append(next)
			submit(data)
	stats_clock -= delta
	if stats_clock<=0:
		stats_clock = 0.2
		var metrics: Array = []
		for p: Node in players: metrics.append(p.get_node("MaterialContact").metrics)
		$UI/Status.text = "P1 A/D W S · F/G H     P2 flechas · K/L Shift der.     R: restablecer · M: movimiento\nVERDE sólido · AZUL rebote · NARANJA atravesable · Sin cámara, OpenCV ni UDP\nRegiones %s · commits %s · diferidos %s · conflicto %s\nP1 contactos %s / rebotes %s / duplicados evitados %s / descensos %s\nP2 contactos %s / rebotes %s / duplicados evitados %s / descensos %s" % [manager.object_ids().size(),adapter.metrics.applied,adapter.metrics.deferred,manager.last_conflict,metrics[0].contacts,metrics[0].bounces,metrics[0].duplicate_bounces_avoided,metrics[0].drops,metrics[1].contacts,metrics[1].bounces,metrics[1].duplicate_bounces_avoided,metrics[1].drops]

func _measure_physics() -> void:
	for p: Node in players:
		if p.collision_mask==0 or not p.is_physics_processing(): continue
		physical_metrics.samples += 1
		var collider: CollisionShape2D = p.get_node("CollisionShape2D")
		for id: StringName in manager.object_ids():
			var body: Node = manager.get_body(id)
			if body.material_kind!="ORANGE_ONE_WAY" and body.overlaps_character(inner_probe,collider.global_transform):
				physical_metrics.solid_penetration_frames_over_1px += 1
				penetration_events.append({"player":p.player_id,"region":body.region_id,"position":p.position,"tick":Engine.get_physics_frames()})
				if penetration_events.size()>128: penetration_events.pop_front()
				break
		var prior: Dictionary = previous_support.get(p.player_id,{})
		if not p.is_on_floor() and not prior.is_empty():
			var body: Node = prior.body.get_ref()
			if body!=null and body.position!=prior.position and p.velocity.y>= -50 and Input.get_axis(p.left_action,p.right_action)==0 and not Input.is_action_pressed(p.jump_action) and not Input.is_action_pressed(p.down_action) and p.combat.dodge_left<=0:
				physical_metrics.support_losses_during_motion += 1
		previous_support.erase(p.player_id)
		if p.is_on_floor():
			for i: int in range(p.get_slide_collision_count()):
				var hit: KinematicCollision2D = p.get_slide_collision(i)
				var body: Node = hit.get_collider()
				if body!=null and body.get("material_kind")!=null and hit.get_normal().y< -0.5:
					previous_support[p.player_id] = {"body":weakref(body),"position":body.position}
					break

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_R: moving = false;load_home()
		if event.keycode==KEY_M: moving = not moving
