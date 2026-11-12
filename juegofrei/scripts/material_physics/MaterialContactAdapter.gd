extends Node
## Environment response, NOT a movement/combat controller. Player still moves once.
@export var bounce_impulse: float = 760.0
@export var min_impulse: float = 120.0
@export var max_impulse: float = 1000.0
@export var max_total_speed: float = 1100.0
@export_range(0,1) var tangential_retention: float = 0.35
@export var separation_clearance: float = 3.0
@export var descent_speed: float = 150.0
var fighter: CharacterBody2D
var latches: Dictionary = {}
var ignored: Dictionary = {}
var clearance_shape: RectangleShape2D = RectangleShape2D.new()
var original_snap: float = 8.0
var snap_hold: float = 0
var metrics: Dictionary = {"contacts":0,"bounces":0,"duplicate_bounces_avoided":0,"drops":0,"restored":0,"drop_overstays":0}
var bounce_events: Array[Dictionary] = []

func _ready() -> void:
	fighter = get_parent() as CharacterBody2D
	fighter.material_adapter = self
	original_snap = fighter.floor_snap_length
	clearance_shape.size = fighter.get_node("CollisionShape2D").shape.size+Vector2.ONE*separation_clearance*2

func _exit_tree() -> void:
	if is_instance_valid(fighter): fighter.material_adapter = null

func _clear(body: Node) -> bool:
	return not body.overlaps_character(clearance_shape,fighter.get_node("CollisionShape2D").global_transform)

func before_motion(delta: float) -> void:
	snap_hold = maxf(0,snap_hold-delta)
	for key: int in ignored.keys():
		var entry: Dictionary = ignored[key]
		var body: Node = entry.body.get_ref()
		entry.age += delta
		if body==null:
			ignored.erase(key)
		elif body.material_kind!="ORANGE_ONE_WAY" or (entry.age>0.10 and _clear(body)):
			fighter.remove_collision_exception_with(body)
			ignored.erase(key);metrics.restored += 1
		elif entry.age>2 and not entry.warned:
			entry.warned = true;metrics.drop_overstays += 1
	fighter.floor_snap_length = 0 if not ignored.is_empty() or snap_hold>0 else original_snap

func after_combat_input(_delta: float) -> void:
	# A solid support wins at a seam. No global collision-mask changes or teleport.
	if fighter.is_on_floor() and Input.is_action_just_pressed(fighter.down_action) and fighter.combat.attack_frame<0 and fighter.combat.dodge_left<=0 and fighter.combat.hitstun_left<=0 and fighter.combat.respawn_left<=0 and not fighter.combat.match_locked:
		var supports: Array[PhysicsBody2D] = []
		var solid: bool = false
		for i: int in range(fighter.get_slide_collision_count()):
			var hit: KinematicCollision2D = fighter.get_slide_collision(i)
			if hit.get_normal().dot(Vector2.UP)<0.5: continue
			var body: Node = hit.get_collider()
			if body!=null and body.get("material_kind")=="ORANGE_ONE_WAY": supports.append(body)
			else: solid = true
		if not solid and not supports.is_empty():
			for body: PhysicsBody2D in supports:
				fighter.add_collision_exception_with(body)
				ignored[body.get_instance_id()] = {"body":weakref(body),"age":0.0,"warned":false}
			fighter.velocity.y = maxf(fighter.velocity.y,descent_speed)
			fighter.coyote_left = 0;fighter.buffer_left = 0;fighter.jumps_used = 1
			metrics.drops += 1
	fighter.floor_snap_length = 0 if not ignored.is_empty() or snap_hold>0 else original_snap

func after_motion(_delta: float,incoming: Vector2) -> void:
	var contacts: Dictionary = {}
	var launched: bool = false
	for i: int in range(fighter.get_slide_collision_count()):
		var hit: KinematicCollision2D = fighter.get_slide_collision(i)
		var body: Node = hit.get_collider()
		metrics.contacts += 1
		if body==null or body.get("material_kind")!="BLUE_BOUNCE": continue
		var key: int = body.get_instance_id()
		contacts[key] = true
		if latches.has(key) or launched:
			metrics.duplicate_bounces_avoided += 1
			continue
		var normal: Vector2 = hit.get_normal().normalized()
		if not normal.is_finite() or normal.length_squared()<0.9: continue
		var cap: float = maxf(1,max_total_speed)
		var ceiling: float = minf(cap,maxf(1,max_impulse))
		var impulse: float = clampf(bounce_impulse,minf(maxf(0,min_impulse),ceiling),ceiling)
		var tangent: Vector2 = incoming-normal*incoming.dot(normal)
		fighter.velocity = (normal*impulse+tangent*tangential_retention).limit_length(cap)
		# Environment collision interrupts dash movement, but preserves its i-frames.
		fighter.combat.dodge_left = 0
		fighter.combat.horizontal_dash = false
		fighter.coyote_left = 0;fighter.buffer_left = 0
		fighter.floor_snap_length = 0;snap_hold = 0.06
		latches[key] = weakref(body);launched = true;metrics.bounces += 1
		bounce_events.append({"normal":normal,"velocity":fighter.velocity,"physics_tick":Engine.get_physics_frames(),"region":body.region_id})
		if bounce_events.size()>256: bounce_events.pop_front()
	for key: int in latches.keys():
		var body: Node = latches[key].get_ref()
		if body==null or body.get("material_kind")!="BLUE_BOUNCE" or (not contacts.has(key) and _clear(body)): latches.erase(key)

func ignoring_support() -> bool: return not ignored.is_empty()
