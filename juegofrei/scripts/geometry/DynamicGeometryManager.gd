extends Node2D
## Phase 1A boundary. No color-to-ID mapping, camera, network or old platforms.
## API calls update desired state only. Physics objects commit on the next tick.
const Validator = preload("res://scripts/geometry/PolygonValidator.gd")
const PolygonObject = preload("res://scripts/geometry/DynamicPolygonObject.gd")
const CompoundValidator = preload("res://scripts/geometry/CompoundGeometryValidator.gd")
@export var max_compound_parts: int = 512
@export var max_objects: int = 64
@export var max_vertices: int = 64
@export var minimum_area: float = 32.0
@export var edge_epsilon: float = 0.01
@export var max_local_coordinate: float = 4096.0
@export var max_world_coordinate: float = 32768.0
@export var max_linear_speed: float = 90.0
@export var max_angular_speed: float = 0.45
@export var max_surface_step: float = 2.0
@export var display_convex_parts: bool = true
@export var convey_velocity: bool = true
## Conservatively postpone creation/shape replacement/reactivation that would
## enclose a player. This is not a swept collision solver for StaticBody2D.
@export_flags_2d_physics var protected_body_mask: int = 4
var _occupancy_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _objects: Dictionary[StringName,Dictionary] = {}
var _deleted: Array[StringName] = []
var _serial: int = 0
var rejected_requests: int = 0
var last_error: Dictionary = {}
var physics_commits: int = 0

func _ready() -> void:
	process_physics_priority = -40

func _reject(id: StringName,operation: String,reason: String) -> bool:
	rejected_requests += 1
	last_error = {"id":String(id),"operation":operation,"reason":reason}
	return false

func _pose_valid(point: Vector2,angle: float) -> bool:
	return point.is_finite() and is_finite(angle) and absf(point.x)<=max_world_coordinate and absf(point.y)<=max_world_coordinate

func create_object(id: StringName,points: PackedVector2Array,point: Vector2,angle: float = 0.0,color: Color = Color.WHITE) -> bool:
	if String(id).is_empty() or String(id).length()>64 or _objects.has(id) or _objects.size()>=max_objects:
		return _reject(id,"create","id_or_object_limit")
	if not _pose_valid(point,angle) or not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
		return _reject(id,"create","invalid_pose_or_color")
	var result: Dictionary = Validator.validate(points,max_vertices,minimum_area,edge_epsilon,max_local_coordinate)
	if not result.ok:
		return _reject(id,"create",result.reason)
	_objects[id] = {"body":null,"polygon":result.polygon,"outlines":[],"contract_geometry_version":0,"tracking":{},"confidence":1.0,"parts":result.parts,"area":result.area,"geometry_dirty":true,"prepared_shapes":[],"blocked":false,"target_position":point,"target_rotation":wrapf(angle,-PI,PI),"color":color,"enabled":true,"remove":false}
	return true

func assign_polygon(id: StringName,points: PackedVector2Array) -> bool:
	if not _objects.has(id) or _objects[id].remove:
		return _reject(id,"geometry","unknown_id")
	var result: Dictionary = Validator.validate(points,max_vertices,minimum_area,edge_epsilon,max_local_coordinate)
	if not result.ok:
		return _reject(id,"geometry",result.reason)
	var record: Dictionary = _objects[id]
	if record.polygon!=result.polygon or not record.outlines.is_empty():
		record.polygon = result.polygon
		record.parts = result.parts
		record.area = result.area
		record.geometry_dirty = true
		record.prepared_shapes = []
		record.outlines = []
		record.contract_geometry_version = 0
	return true

func create_structure(data: Dictionary,color: Color = Color.WHITE) -> bool:
	var id: StringName = StringName(str(data.get("id","")))
	if _objects.has(id) or _objects.size()>=max_objects or not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
		return _reject(id,"create_structure","id_object_limit_or_color")
	var result: Dictionary = CompoundValidator.validate(data,max_compound_parts,2048,max_local_coordinate,minimum_area)
	if not result.ok:
		return _reject(id,"create_structure",result.reason)
	if not _pose_valid(result.position,result.rotation):
		return _reject(id,"create_structure","invalid_pose")
	_objects[id] = {"body":null,"polygon":result.polygon,"outlines":result.outlines,"parts":result.parts,"area":result.area,"geometry_dirty":true,"prepared_shapes":[],"blocked":false,"target_position":result.position,"target_rotation":wrapf(result.rotation,-PI,PI),"color":color,"enabled":true,"remove":false,"contract_geometry_version":result.geometry_version,"tracking":result.tracking,"confidence":result.confidence}
	return true

func assign_structure(data: Dictionary) -> bool:
	var id: StringName = StringName(str(data.get("id","")))
	if not _objects.has(id) or _objects[id].remove:
		return _reject(id,"assign_structure","unknown_id")
	var result: Dictionary = CompoundValidator.validate(data,max_compound_parts,2048,max_local_coordinate,minimum_area)
	if not result.ok:
		return _reject(id,"assign_structure",result.reason)
	var record: Dictionary = _objects[id]
	if result.geometry_version<=record.contract_geometry_version or not _pose_valid(result.position,result.rotation):
		return _reject(id,"assign_structure","old_geometry_version_or_pose")
	# Validation is transactional: last valid geometry survives any rejection.
	var changed: bool = record.parts!=result.parts or record.outlines!=result.outlines
	record.polygon = result.polygon
	record.outlines = result.outlines
	record.parts = result.parts
	record.area = result.area
	if changed:
		record.prepared_shapes = []
		record.geometry_dirty = true
	record.contract_geometry_version = result.geometry_version
	record.tracking = result.tracking
	record.confidence = result.confidence
	record.target_position = result.position
	record.target_rotation = wrapf(result.rotation,-PI,PI)
	return true

func update_transform(id: StringName,point: Vector2,angle: float) -> bool:
	if not _objects.has(id) or _objects[id].remove:
		return _reject(id,"transform","unknown_id")
	if not _pose_valid(point,angle):
		return _reject(id,"transform","invalid_pose")
	_objects[id].target_position = point
	_objects[id].target_rotation = wrapf(angle,-PI,PI)
	return true

func update_structure_pose(data: Dictionary) -> bool:
	var metadata: Dictionary = CompoundValidator.validate_metadata(data)
	var id: StringName = StringName(str(data.get("id","")))
	if not metadata.ok:
		return _reject(id,"structure_pose",metadata.reason)
	if not _objects.has(id) or _objects[id].remove or _objects[id].contract_geometry_version!=metadata.geometry_version or not _pose_valid(metadata.position,metadata.rotation):
		return _reject(id,"structure_pose","unknown_id_version_or_pose")
	var record: Dictionary = _objects[id]
	record.tracking = metadata.tracking
	record.confidence = metadata.confidence
	if metadata.tracking.state=="TRACKED":
		record.target_position = metadata.position
		record.target_rotation = wrapf(metadata.rotation,-PI,PI)
	elif record.body!=null:
		# HELD/LOST never keep travelling to a stale target.
		record.target_position = record.body.global_position
		record.target_rotation = record.body.global_rotation
	return true

func set_collision_enabled(id: StringName,enabled: bool) -> bool:
	if not _objects.has(id) or _objects[id].remove:
		return _reject(id,"enabled","unknown_id")
	_objects[id].enabled = enabled
	return true

func remove_object(id: StringName) -> bool:
	if not _objects.has(id) or _objects[id].remove:
		return _reject(id,"remove","unknown_id")
	_objects[id].remove = true
	return true

func has_object(id: StringName) -> bool:
	return _objects.has(id) and not _objects[id].remove

func object_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _objects:
		if not _objects[id].remove:
			result.append(id)
	return result

func get_body(id: StringName) -> StaticBody2D:
	return _objects[id].body as StaticBody2D if _objects.has(id) else null

func get_state(id: StringName) -> Dictionary:
	if not _objects.has(id):
		return {}
	var record: Dictionary = _objects[id]
	var body: PolygonObject = record.body as PolygonObject
	return {"id":String(id),"committed":body!=null,"outlines":record.outlines.duplicate(true),"committed_outlines":body.outlines.duplicate(true) if body!=null else [],"contract_geometry_version":record.contract_geometry_version,"tracking":record.tracking.duplicate(true),"confidence":record.confidence,"blocked_by_character":record.blocked,"pending_removal":record.remove,"pending_geometry":record.geometry_dirty,"target_position":record.target_position,"target_rotation":record.target_rotation,"requested_enabled":record.enabled,"polygon":record.polygon.duplicate(),"committed_polygon":body.polygon.duplicate() if body!=null else PackedVector2Array(),"area":record.area,"color":record.color,"position":body.global_position if body!=null else record.target_position,"rotation":body.global_rotation if body!=null else record.target_rotation,"collision_enabled":body.collision_enabled if body!=null else false,"parts":body.convex_parts.size() if body!=null else 0,"geometry_revision":body.geometry_revision if body!=null else 0,"shape_builds":body.shape_builds if body!=null else 0}

func _physics_process(delta: float) -> void:
	_deleted.clear()
	for id: StringName in _objects:
		var record: Dictionary = _objects[id]
		var body: PolygonObject = record.body as PolygonObject
		if record.remove:
			if body!=null:
				remove_child(body)
				body.free()
			_deleted.append(id)
			continue
		if record.geometry_dirty and record.prepared_shapes.is_empty():
			for part: PackedVector2Array in record.parts:
				var resource: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
				resource.points = part
				record.prepared_shapes.append(resource)
		record.blocked = false
		if record.enabled and (record.geometry_dirty or (body!=null and not body.collision_enabled)):
			var resources: Array[ConvexPolygonShape2D] = []
			if record.geometry_dirty:
				resources.assign(record.prepared_shapes)
			else:
				for collider: CollisionShape2D in body.colliders:
					resources.append(collider.shape as ConvexPolygonShape2D)
			var pose: Transform2D = body.global_transform if body!=null else Transform2D(record.target_rotation,record.target_position)
			if _would_enclose_character(resources,pose):
				record.blocked = true
				if body!=null:
					body.constant_linear_velocity = Vector2.ZERO
					body.constant_angular_velocity = 0.0
				continue
		if body==null:
			body = PolygonObject.new()
			_serial += 1
			body.name = "PolygonObject_%d" % _serial
			body.object_id = id
			body.tint = record.color
			body.display_parts = display_convex_parts
			add_child(body)
			body.global_transform = Transform2D(record.target_rotation,record.target_position)
			body.force_update_transform()
			body.reset_physics_interpolation()
			record.body = body
		if record.geometry_dirty:
			var resources: Array[ConvexPolygonShape2D] = []
			resources.assign(record.prepared_shapes)
			var outlines: Array[PackedVector2Array] = []
			outlines.assign(record.outlines)
			body.commit_geometry(record.polygon,record.parts,resources,outlines)
			record.prepared_shapes = []
			body.force_update_transform()
			record.geometry_dirty = false
			physics_commits += 1
		if body.collision_enabled!=record.enabled:
			body.set_enabled(record.enabled)
		_step_pose(body,record,delta)
	for id: StringName in _deleted:
		_objects.erase(id)

func _would_enclose_character(resources: Array[ConvexPolygonShape2D],pose: Transform2D) -> bool:
	if protected_body_mask==0:
		return false
	# Respawns/fixture teleports can have a current node pose but an old broadphase
	# AABB. Test known players directly at their logical pose before space queries.
	for candidate: Node in get_tree().get_nodes_in_group("players"):
		if not candidate is PhysicsBody2D or (candidate.collision_layer & protected_body_mask)==0:
			continue
		for child: Node in candidate.get_children():
			if child is CollisionShape2D and not child.disabled and child.shape!=null:
				for resource: ConvexPolygonShape2D in resources:
					if resource.collide(pose,child.shape,child.global_transform):
						return true
	_occupancy_query.collision_mask = protected_body_mask
	_occupancy_query.collide_with_areas = false
	_occupancy_query.collide_with_bodies = true
	_occupancy_query.transform = pose
	_occupancy_query.margin = 0.0
	for resource: ConvexPolygonShape2D in resources:
		_occupancy_query.shape = resource
		if not get_world_2d().direct_space_state.intersect_shape(_occupancy_query,1).is_empty():
			return true
	return false

func _step_pose(body: PolygonObject,record: Dictionary,delta: float) -> void:
	var translation: Vector2 = (Vector2(record.target_position)-body.global_position).limit_length(max_linear_speed*delta)
	var angle: float = clampf(angle_difference(body.global_rotation,float(record.target_rotation)),-max_angular_speed*delta,max_angular_speed*delta)
	var sweep: float = translation.length()+absf(angle)*body.surface_radius
	var ratio: float = minf(1.0,max_surface_step/maxf(sweep,0.000001))
	translation *= ratio
	angle *= ratio
	# StaticBody does not sweep on relocation. Publish actual bounded motion as
	# contact velocity for CharacterBody2D's native floor transport, then measure.
	body.constant_linear_velocity = translation/delta if convey_velocity and body.collision_enabled else Vector2.ZERO
	body.constant_angular_velocity = angle/delta if convey_velocity and body.collision_enabled else 0.0
	if translation.length_squared()>0.00000001 or absf(angle)>0.000001:
		body.global_transform = Transform2D(body.global_rotation+angle,body.global_position+translation)
		# Static CollisionObject notifications otherwise wait until frame end,
		# while the player queries during this tick. Flush before player physics.
		body.force_update_transform()
