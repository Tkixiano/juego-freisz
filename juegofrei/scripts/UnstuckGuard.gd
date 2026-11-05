extends Node
## Only persistent deep overlaps trigger recovery; touching a floor is not embedding.
signal recovered(player_id: int)
@export var check_interval: float = 0.1
@export var recovery_delay: float = 0.5
var elapsed: float = 0.0
var embedded_time: float = 0.0
var recoveries: int = 0
var last_recovery: Dictionary = {}
var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
@onready var fighter: CharacterBody2D = get_parent() as CharacterBody2D

func _ready() -> void:
	process_physics_priority = 10
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(34,34)
	query.shape = shape
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [fighter.get_rid()]

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed < check_interval:
		return
	var interval: float = elapsed
	elapsed = 0
	query.collision_mask = fighter.collision_mask & 3
	if query.collision_mask == 0 or not _occupied(fighter.global_position):
		embedded_time = 0
		return
	embedded_time += interval
	if embedded_time >= recovery_delay:
		_recover()

func _occupied(point: Vector2) -> bool:
	query.transform = Transform2D(0,point)
	return not fighter.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func _recover() -> void:
	query.transform=Transform2D(0,fighter.global_position)
	var objects: Array[String]=[]
	for hit: Dictionary in fighter.get_world_2d().direct_space_state.intersect_shape(query,8):
		objects.append(str(hit["collider"].get_path()))
	last_recovery={"position":fighter.global_position,"velocity":fighter.velocity,"on_floor":fighter.is_on_floor(),"floor_normal":fighter.get_floor_normal(),"colliders":objects}
	var contacts: Array=[]
	for index: int in range(fighter.get_slide_collision_count()):
		var collision: KinematicCollision2D=fighter.get_slide_collision(index)
		var body: Node2D=collision.get_collider()
		contacts.append({"collider":str(body.get_path()),"normal":collision.get_normal(),"point":collision.get_position(),"visual_pose":body.global_transform,"physics_pose":PhysicsServer2D.body_get_state(body.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM)})
	last_recovery["contacts"]=contacts
	embedded_time = 0
	recoveries += 1
	# Prefer a lateral exit: moving above an inverted one-way ceiling would fall
	# straight back into the same crush. Platforms retain their original geometry.
	for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		for distance: int in range(16,161,16):
			var point: Vector2 = fighter.global_position + direction * distance
			if not _occupied(point):
				fighter.global_position = point
				fighter.velocity = Vector2.ZERO
				fighter.reset_physics_interpolation()
				recovered.emit(int(fighter.get("player_id")))
				return
	# Extreme enclosure: return safely to spawn without subtracting another stock.
	fighter.call("respawn")
	recovered.emit(int(fighter.get("player_id")))
