extends Node
var game: Node
var manager: Node
var floor_controller: Node
var pending: Dictionary = {}
var metrics: Dictionary = {"respawns":0,"deferred":0}
var shape: RectangleShape2D = RectangleShape2D.new()
func _ready() -> void:
	process_physics_priority = -10;game = get_parent();manager = $"../DynamicGeometry";floor_controller = $"../SafetyFloor"
	shape.size = Vector2(42,42)
func choose(player: Node) -> Variant:
	var candidates: Array[Vector2] = []
	if floor_controller.enabled:candidates.append(player.spawn_position)
	for id: StringName in manager.object_ids():
		var body: Node = manager.get_body(id)
		for ring: PackedVector2Array in body.outlines:
			for i: int in range(ring.size()):
				var a: Vector2 = body.to_global(ring[i]);var b: Vector2 = body.to_global(ring[(i+1)%ring.size()])
				var d: Vector2 = b-a;var n: Vector2 = Vector2(d.y,-d.x).normalized()
				if n.dot(Vector2.UP)<0.70:continue
				candidates.append((a+b)/2+n*(20*(absf(n.x)+absf(n.y))+4))
	candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:return a.distance_squared_to(player.spawn_position)<b.distance_squared_to(player.spawn_position))
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new();query.shape = shape;query.collision_mask = 3
	for point: Vector2 in candidates:
		if not game.elimination_bounds.grow(-30).has_point(point):continue
		query.transform = Transform2D(0,point)
		if player.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():return point
	return null
func request(player: Node) -> void:
	metrics.respawns += 1
	var point: Variant = choose(player)
	if point==null:
		pending[player.player_id] = player;metrics.deferred += 1
		player.collision_mask = 0;player.set_physics_process(false);player.position = Vector2(640,0)
	else:_place(player,point)
func _place(player: Node,point: Vector2) -> void:
	player.position = point;player.velocity = Vector2.ZERO;player.force_update_transform();player.reset_physics_interpolation()
	player.collision_mask = 3;player.set_physics_process(true)
	player.combat.respawn_left = player.combat.respawn_duration;player.combat.invulnerability_left = player.combat.respawn_invulnerability
func _physics_process(_delta: float) -> void:
	for id: int in pending.keys():
		var player: Node = pending[id]
		var point: Variant = choose(player)
		if point!=null:_place(player,point);pending.erase(id)
