extends Node2D
## Reads existing states; never writes fighter motion, attacks or collisions.
const Catalog = preload("res://scripts/CharacterCatalog.gd")
const FallbackScene = preload("res://scenes/CharacterAppearance.tscn")
var definition: Resource
var appearance: Node2D
var logical_state: StringName = &"idle"
var rejected_visuals: int = 0
@onready var fighter: CharacterBody2D = get_parent()

func _ready() -> void:
	process_physics_priority = 30
	set_definition(Catalog.ENTRIES[clampi(int(fighter.get("player_id"))-1,0,1)])

func _visual_only(node: Node) -> bool:
	if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D: return false
	for child: Node in node.get_children():
		if not _visual_only(child): return false
	return true

func set_definition(data: Resource) -> bool:
	if not data is Catalog.Definition or not data.is_valid(): return false
	if definition==data and appearance!=null: return true
	var scene: PackedScene = data.visual_scene if data.visual_scene!=null else FallbackScene
	var candidate: Node = scene.instantiate()
	if not candidate is Node2D or not _visual_only(candidate) or not candidate.has_method("configure") or not candidate.has_method("apply_visual_state"):
		candidate.free()
		rejected_visuals += 1
		candidate = FallbackScene.instantiate()
	if appearance!=null:
		remove_child(appearance)
		appearance.free()
	definition = data
	appearance = candidate as Node2D
	add_child(appearance)
	appearance.position = data.visual_offset
	appearance.scale = data.visual_scale
	appearance.configure(data)
	_sync_identity()
	queue_redraw()
	return true

func _sync_identity() -> void:
	fighter.get_node("Visual").visible = false
	fighter.get_node("Highlight").visible = false
	var label: Label = fighter.get_node("Identifier")
	label.offset_left = -120
	label.offset_right = 120
	label.text = "P%d · %s" % [int(fighter.get("player_id")),definition.display_name]
	label.modulate = fighter.get("body_color")

func _physics_process(_delta: float) -> void:
	if definition==null or appearance==null: return
	var combat: Node = fighter.get("combat")
	if combat==null: return
	logical_state = &"idle"
	if combat.eliminated: logical_state = &"defeat"
	elif combat.hitstun_left>0: logical_state = &"hurt"
	elif combat.dodge_left>0: logical_state = &"dash"
	elif combat.attack_frame>=0:
		if combat.attack_direction=="arriba": logical_state = &"up"
		elif combat.is_descending_attack(): logical_state = &"down"
		elif combat.attack==combat.ground_heavy or combat.attack==combat.air_heavy: logical_state = &"heavy"
		else: logical_state = &"light"
	elif not fighter.is_on_floor(): logical_state = &"jump" if fighter.velocity.y<0 else &"fall"
	elif absf(fighter.velocity.x)>1: logical_state = &"run"
	appearance.apply_visual_state(logical_state,combat.facing,combat.flash_left>0)
	modulate.a = fighter.get_node("Visual").modulate.a
	_sync_identity()
