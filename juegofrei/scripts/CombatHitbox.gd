extends Area2D
## Dedicated combat layer: stage bodies never participate in attack queries.
var victims: Dictionary[int, bool] = {}
var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
@onready var collider: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	query.collision_mask = 8
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.shape = collider.shape

func begin(radius: float, offset: Vector2) -> void:
	victims.clear()
	(collider.shape as CircleShape2D).radius = radius
	position = offset

func candidates() -> Array[Area2D]:
	query.transform = collider.global_transform
	var result: Array[Area2D] = []
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var hurtbox: Area2D = hit["collider"] as Area2D
		if hurtbox == null or hurtbox.get_parent() == get_parent().get_parent():
			continue
		var id: int = hurtbox.get_instance_id()
		if not victims.has(id):
			victims[id] = true
			result.append(hurtbox)
	return result
