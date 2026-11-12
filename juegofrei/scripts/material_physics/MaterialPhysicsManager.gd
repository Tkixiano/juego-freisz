extends "res://scripts/geometry/TransactionalGeometryManager.gd"
const MaterialBody = preload("res://scripts/material_physics/MaterialPolygonBody.gd")
@export var one_way_max_slope: float = 46.0
@export var one_way_margin: float = 1.5
var predicted_players: Dictionary = {}
var update_us: Array[int] = []
var safety_cache: Dictionary = {}
var inner_shapes: Dictionary = {}
var conflict_counts: Dictionary = {}
var environment_guard: Node = null

func _before_commit(targets: Dictionary,poses: Dictionary) -> void:
	if is_instance_valid(environment_guard): environment_guard.before_commit(targets,poses)

func prepare_snapshot(contracts: Array) -> Dictionary:
	var prepared: Dictionary = super.prepare_snapshot(contracts)
	if not prepared.ok: return prepared
	var keep_cache: Dictionary = {}
	for c: Dictionary in contracts:
		var target: Dictionary = prepared.objects[StringName(c.id)]
		target.kind = c.material_kind
		target.structure_id = c.structure_id
		target.region_id = c.id
		var neighbors: Array = []
		for other: Dictionary in contracts:
			if other.structure_id==c.structure_id: neighbors.append(other.convex_parts)
		var cache_key: String = JSON.stringify([target.kind,target.outlines,neighbors],"",true,true).sha256_text()
		if safety_cache.has(cache_key):
			target.edges = safety_cache[cache_key].edges
			target.safe_surfaces = safety_cache[cache_key].safe_surfaces
			keep_cache[cache_key] = safety_cache[cache_key]
			continue
		target.edges = []
		if target.kind=="ORANGE_ONE_WAY":
			for ring: PackedVector2Array in target.outlines:
				for i: int in range(ring.size()):
					var a: Vector2 = ring[i]
					var b: Vector2 = ring[(i+1)%ring.size()]
					var direction: Vector2 = b-a
					var normal: Vector2 = Vector2(direction.y,-direction.x).normalized()
					var edges: Array[PackedVector2Array] = [PackedVector2Array([a+normal*0.05,b+normal*0.05])]
					for other: Dictionary in contracts:
						if other.id==c.id or other.structure_id!=c.structure_id: continue
						for raw: Array in other.convex_parts:
							var polygon: PackedVector2Array = CompoundValidator.points(raw,64,4096)
							var remaining: Array[PackedVector2Array] = []
							for edge: PackedVector2Array in edges: remaining.append_array(Geometry2D.clip_polyline_with_polygon(edge,polygon))
							edges = remaining
					for edge: PackedVector2Array in edges:
						if edge.size()==2 and edge[0].distance_to(edge[1])>0.05: target.edges.append(PackedVector2Array([edge[0]-normal*0.05,edge[1]-normal*0.05]))
		target.safe_surfaces = []
		for edge: PackedVector2Array in target.edges:
			var d: Vector2 = edge[1]-edge[0]
			var n: Vector2 = Vector2(d.y,-d.x).normalized()
			var shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
			shape.points = PackedVector2Array([edge[0],edge[1],edge[1]-n*2,edge[0]-n*2])
			target.safe_surfaces.append({"normal":n,"shape":shape})
		keep_cache[cache_key] = {"edges":target.edges,"safe_surfaces":target.safe_surfaces}
	safety_cache = keep_cache
	return prepared

func _make_body(_id: StringName,_target: Dictionary) -> PolygonObject: return MaterialBody.new()
func _configure_body(body: PolygonObject,_id: StringName,target: Dictionary) -> void:
	body.set("material_kind",target.kind)
	body.set("structure_id",target.structure_id)
	body.set("region_id",target.region_id)
	body.set("surface_edges",target.edges)
	body.set("max_slope_degrees",clampf(one_way_max_slope,1,46))
	body.set("one_way_margin",maxf(0.01,one_way_margin))
	body.tint = Color("49d772") if target.kind=="GREEN_SOLID" else (Color("438cff") if target.kind=="BLUE_BOUNCE" else Color("ff9d36"))
func _after_body_pose(body: PolygonObject,_target: Dictionary) -> void: body.call("update_upper_edges")
func _needs_rebuild(old: Dictionary,target: Dictionary) -> bool:
	return super._needs_rebuild(old,target) or old.get("kind")!=target.kind or old.get("edges",[])!=target.edges
func _decorate_record(record: Dictionary,target: Dictionary) -> Dictionary:
	for key: String in ["kind","structure_id","region_id","edges","safe_surfaces"]: record[key] = target[key]
	return record

func _surface_resources(target: Dictionary,pose: Transform2D) -> Array[ConvexPolygonShape2D]:
	var result: Array[ConvexPolygonShape2D] = []
	if target.kind!="ORANGE_ONE_WAY":
		result.assign(target.resources)
		return result
	for surface: Dictionary in target.safe_surfaces:
		if surface.normal.rotated(pose.get_rotation()).dot(Vector2.UP)>=cos(deg_to_rad(clampf(one_way_max_slope,1,46))): result.append(surface.shape)
	return result

func _preflight(targets: Dictionary,poses: Dictionary,protect_support: bool) -> String:
	if is_instance_valid(environment_guard):
		var environment_reason: String = environment_guard.preflight(targets,poses)
		if not environment_reason.is_empty():
			conflict_counts[environment_reason] = int(conflict_counts.get(environment_reason,0))+1
			return environment_reason
	predicted_players.clear()
	# Predict only native carrier motion for an unchanged support. Never move players.
	for p: Node in get_tree().get_nodes_in_group("players"):
		if not p is CharacterBody2D: continue
		var transform: Transform2D = p.get_node("CollisionShape2D").global_transform
		if p.is_on_floor():
			for i: int in range(p.get_slide_collision_count()):
				var hit: KinematicCollision2D = p.get_slide_collision(i)
				var body: Node = hit.get_collider()
				if body==null or hit.get_normal().y> -0.5: continue
				var id: Variant = body.get("object_id")
				if id!=null and targets.has(id) and _objects.has(id) and not _needs_rebuild(_objects[id],targets[id]):
					transform.origin = poses[id]*(body.global_transform.affine_inverse()*transform.origin)
					break
		predicted_players[p.get_instance_id()] = transform
	# A native carrier must not push its rider into an unmanaged solid obstacle.
	var excluded: Array[RID] = []
	for record: Dictionary in _objects.values():
		if record.body!=null: excluded.append(record.body.get_rid())
	for player: Node in get_tree().get_nodes_in_group("players"):
		if player is PhysicsBody2D: excluded.append(player.get_rid())
	for player: Node in get_tree().get_nodes_in_group("players"):
		if not player is CharacterBody2D or player.collision_mask==0: continue
		var collider: CollisionShape2D = player.get_node("CollisionShape2D")
		var prediction: Transform2D = predicted_players[player.get_instance_id()]
		if prediction.origin.distance_squared_to(collider.global_position)<0.0001: continue
		var inner: RectangleShape2D = inner_shapes.get(player.get_instance_id())
		if inner==null:
			inner = RectangleShape2D.new();inner_shapes[player.get_instance_id()] = inner
		inner.size = collider.shape.size-Vector2.ONE
		var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		query.shape = inner;query.transform = prediction;query.collision_mask = 1;query.exclude = excluded
		if not get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
			conflict_counts["carrier_blocked_by_external_solid"] = int(conflict_counts.get("carrier_blocked_by_external_solid",0))+1
			return "carrier_blocked_by_external_solid"
	var reason: String = super._preflight(targets,poses,protect_support)
	if not reason.is_empty(): conflict_counts[reason] = int(conflict_counts.get(reason,0))+1
	return reason

func _target_penetrates(id: StringName,target: Dictionary,pose: Transform2D) -> bool:
	if protected_body_mask==0: return false
	var resources: Array[ConvexPolygonShape2D] = _surface_resources(target,pose)
	for p: Node in get_tree().get_nodes_in_group("players"):
		if not p is CharacterBody2D or p.collision_mask==0: continue
		var old_body: Node = get_body(id)
		if target.kind=="ORANGE_ONE_WAY" and old_body!=null and p.get_collision_exceptions().has(old_body): continue
		var collider: CollisionShape2D = p.get_node("CollisionShape2D")
		var inner: RectangleShape2D = inner_shapes.get(p.get_instance_id())
		if inner==null:
			inner = RectangleShape2D.new();inner_shapes[p.get_instance_id()] = inner
		inner.size = collider.shape.size-Vector2.ONE*1.0
		for shape: ConvexPolygonShape2D in resources:
			if shape.collide(pose,inner,predicted_players.get(p.get_instance_id(),collider.global_transform)): return true
	return false

func _target_supports(_id: StringName,target: Dictionary,pose: Transform2D,collider: CollisionShape2D,probe: Transform2D) -> bool:
	var player: Node = collider.get_parent()
	if predicted_players.has(player.get_instance_id()): probe.origin += predicted_players[player.get_instance_id()].origin-collider.global_position
	for shape: ConvexPolygonShape2D in _surface_resources(target,pose):
		if shape.collide(pose,collider.shape,probe): return true
	return false

func _physics_process(delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	super._physics_process(delta)
	update_us.append(Time.get_ticks_usec()-start)
	if update_us.size()>4096: update_us.pop_front()
