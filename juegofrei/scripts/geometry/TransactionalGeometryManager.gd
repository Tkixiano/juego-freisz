extends "res://scripts/geometry/DynamicGeometryManager.gd"
## Exclusive offline backend. Prepared snapshots commit atomically before players.
signal transaction_finished(token: int,status: String,reason: String,application_us: int)
var pending: Dictionary = {}
var transaction_mode: bool = true
var last_conflict: String = ""
var total_rebuilds: int = 0
var motion_conflicts: int = 0
var motion_paused: bool = false
var _geometry_cache: Dictionary = {}
var prepared_geometry_builds: int = 0
var physical_validation_us: Array[int] = []

func prepare_snapshot(contracts: Array) -> Dictionary:
	if contracts.size()>max_objects:
		return {"ok":false,"reason":"object_limit"}
	var prepared: Dictionary = {}
	var cache_keep: Dictionary = {}
	var total_parts: int = 0
	for value: Variant in contracts:
		if not value is Dictionary:
			return {"ok":false,"reason":"structure_type"}
		var metadata: Dictionary = CompoundValidator.validate_metadata(value)
		if not metadata.ok: return metadata
		var key: String = JSON.stringify({"regions":value.get("regions"),"parts":value.get("convex_parts"),"limits":[max_compound_parts,max_local_coordinate,minimum_area]},"",true,true)
		var valid: Dictionary
		if _geometry_cache.has(key):
			valid = _geometry_cache[key].duplicate()
			valid.merge(metadata,true)
		else:
			valid = CompoundValidator.validate(value,max_compound_parts,2048,max_local_coordinate,minimum_area)
			if not valid.ok: return valid
			valid.resources = []
			for part: PackedVector2Array in valid.parts:
				var shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
				shape.points = part
				valid.resources.append(shape)
			prepared_geometry_builds += 1
		cache_keep[key] = valid
		var id: StringName = StringName(value.id)
		if prepared.has(id) or not _pose_valid(valid.position,valid.rotation):
			return {"ok":false,"reason":"duplicate_id_or_pose"}
		total_parts += valid.parts.size()
		if total_parts>2048:
			return {"ok":false,"reason":"batch_shape_budget"}
		prepared[id] = valid
	# Reject overlapping logical colliders too; a MERGE must retire its parents.
	var ids: Array = prepared.keys()
	for i: int in range(ids.size()):
		var a: Dictionary = prepared[ids[i]]
		var ta: Transform2D = Transform2D(a.rotation,a.position)
		for j: int in range(i+1,ids.size()):
			var b: Dictionary = prepared[ids[j]]
			var tb: Transform2D = Transform2D(b.rotation,b.position)
			for pa: PackedVector2Array in a.parts:
				for pb: PackedVector2Array in b.parts:
					if CompoundValidator.intersection_area(ta*pa,tb*pb)>0.001:
						return {"ok":false,"reason":"overlapping_logical_structures"}
	_geometry_cache = cache_keep
	return {"ok":true,"objects":prepared}

func queue_snapshot(prepared: Dictionary,token: int,protect_support: bool) -> bool:
	if not pending.is_empty(): return false
	pending = {"objects":prepared.objects,"token":token,"protect_support":protect_support,"reported":false}
	return true

func reset_offline() -> void:
	# Called by adapter on a physics boundary, never by UI callbacks.
	pending.clear()
	for record: Dictionary in _objects.values():
		if record.body!=null:
			record.body.set_enabled(false)
			record.body.free()
	_objects.clear()
	_geometry_cache.clear()
	last_conflict = ""

# This backend is exclusively owned by the offline adapter. Legacy producers must
# use the original manager, not mutate a snapshot midway through a transaction.
func create_object(_id: StringName,_points: PackedVector2Array,_point: Vector2,_angle: float=0.0,_color: Color=Color.WHITE) -> bool:
	return _reject(_id,"legacy_write","transactional_backend_owned_by_adapter")
func assign_polygon(_id: StringName,_points: PackedVector2Array) -> bool:
	return _reject(_id,"legacy_write","transactional_backend_owned_by_adapter")
func create_structure(_data: Dictionary,_color: Color=Color.WHITE) -> bool:
	return false
func assign_structure(_data: Dictionary) -> bool:
	return false
func update_transform(_id: StringName,_point: Vector2,_angle: float) -> bool:
	return false
func update_structure_pose(_data: Dictionary) -> bool:
	return false
func set_collision_enabled(_id: StringName,_enabled: bool) -> bool:
	return false
func remove_object(_id: StringName) -> bool:
	return false

func _pose_for(old: Dictionary,target: Dictionary,delta: float) -> Transform2D:
	if old.is_empty() or old.body==null or old.parts!=target.parts or old.outlines!=target.outlines:
		return Transform2D(target.rotation,target.position)
	var body: Node2D = old.body
	if target.tracking.state!="TRACKED": return body.global_transform
	var translation: Vector2 = (Vector2(target.position)-body.global_position).limit_length(max_linear_speed*delta)
	var angle: float = clampf(angle_difference(body.rotation,target.rotation),-max_angular_speed*delta,max_angular_speed*delta)
	var ratio: float = minf(1.0,max_surface_step/maxf(translation.length()+absf(angle)*body.surface_radius,0.000001))
	return Transform2D(body.rotation+angle*ratio,body.position+translation*ratio)

func _preflight(targets: Dictionary,poses: Dictionary,protect_support: bool) -> String:
	for id: StringName in targets:
		var shapes: Array[ConvexPolygonShape2D] = []
		shapes.assign(targets[id].resources)
		if _would_enclose_character(shapes,poses[id]): return "character_penetration"
	# Bounded motions can create overlap even when final targets do not overlap.
	var ids: Array = targets.keys()
	for i: int in range(ids.size()):
		for j: int in range(i+1,ids.size()):
			for a: PackedVector2Array in targets[ids[i]].parts:
				for b: PackedVector2Array in targets[ids[j]].parts:
					if CompoundValidator.intersection_area(poses[ids[i]]*a,poses[ids[j]]*b)>0.001:
						return "intermediate_structure_overlap"
	if protect_support and not targets.is_empty():
		for player: Node in get_tree().get_nodes_in_group("players"):
			if not player is CharacterBody2D or not player.is_on_floor(): continue
			var collider: CollisionShape2D = player.get_node_or_null("CollisionShape2D")
			if collider==null: continue
			var probe_pose: Transform2D = collider.global_transform
			probe_pose.origin.y += minf(player.floor_snap_length,4.0)
			var old_support: bool = false
			for old: Dictionary in _objects.values():
				if old.body==null: continue
				for shape_node: CollisionShape2D in old.body.colliders:
					if shape_node.shape.collide(old.body.global_transform,collider.shape,probe_pose): old_support = true
			if not old_support: continue
			var new_support: bool = false
			for id: StringName in targets:
				for shape: ConvexPolygonShape2D in targets[id].resources:
					if shape.collide(poses[id],collider.shape,probe_pose): new_support = true
			if not new_support: return "support_discontinuity"
	return ""

func _physics_process(delta: float) -> void:
	if not pending.is_empty():
		var poses: Dictionary = {}
		for id: StringName in pending.objects:
			poses[id] = _pose_for(_objects.get(id,{}),pending.objects[id],delta)
		var validation_start: int = Time.get_ticks_usec()
		var conflict: String = _preflight(pending.objects,poses,pending.protect_support)
		physical_validation_us.append(Time.get_ticks_usec()-validation_start)
		if physical_validation_us.size()>4096: physical_validation_us.pop_front()
		if not conflict.is_empty():
			last_conflict = conflict
			for old: Dictionary in _objects.values():
				if old.body!=null:
					old.body.constant_linear_velocity = Vector2.ZERO
					old.body.constant_angular_velocity = 0.0
			if not pending.reported:
				pending.reported = true
				transaction_finished.emit(pending.token,"DEFERRED",conflict,0)
			return
		var start: int = Time.get_ticks_usec()
		var replacements: Dictionary[StringName,Dictionary] = {}
		# No awaits or callbacks between retiring old bodies and publishing new ones.
		for id: StringName in _objects:
			if not pending.objects.has(id):
				_objects[id].body.set_enabled(false)
				_objects[id].body.free()
		for id: StringName in pending.objects:
			var target: Dictionary = pending.objects[id]
			var old: Dictionary = _objects.get(id,{})
			var body: PolygonObject = old.get("body") as PolygonObject
			var previous_pose: Transform2D = body.global_transform if body!=null else poses[id]
			var changed: bool = old.is_empty() or old.parts!=target.parts or old.outlines!=target.outlines
			if body==null:
				body = PolygonObject.new()
				body.object_id = id
				body.tint = Color("#4fc3a1")
				body.display_parts = display_convex_parts
				add_child(body)
			if changed:
				var resources: Array[ConvexPolygonShape2D] = []
				resources.assign(target.resources)
				var rings: Array[PackedVector2Array] = []
				rings.assign(target.outlines)
				body.commit_geometry(target.polygon,target.parts,resources,rings)
				total_rebuilds += 1
			body.global_transform = poses[id]
			body.force_update_transform()
			if changed: body.reset_physics_interpolation()
			body.constant_linear_velocity = (body.position-previous_pose.origin)/delta if not changed else Vector2.ZERO
			body.constant_angular_velocity = angle_difference(previous_pose.get_rotation(),body.rotation)/delta if not changed else 0.0
			replacements[id] = {"body":body,"polygon":target.polygon,"outlines":target.outlines,"parts":target.parts,"area":target.area,"contract_geometry_version":target.geometry_version,"tracking":target.tracking,"confidence":target.confidence,"geometry_dirty":false,"prepared_shapes":[],"blocked":false,"remove":false,"enabled":true,"target_position":target.position,"target_rotation":target.rotation,"color":body.tint,"resources":target.resources}
		_objects = replacements
		var token: int = pending.token
		pending.clear()
		last_conflict = ""
		transaction_finished.emit(token,"APPLIED","",Time.get_ticks_usec()-start)
		return
	# Continue pose targets only if ALL next poses are safe; hold the whole step.
	if motion_paused:
		for old: Dictionary in _objects.values():
			old.body.constant_linear_velocity = Vector2.ZERO
			old.body.constant_angular_velocity = 0.0
		return
	var targets: Dictionary = {}
	var poses: Dictionary = {}
	for id: StringName in _objects:
		var old: Dictionary = _objects[id]
		targets[id] = {"parts":old.parts,"outlines":old.outlines,"position":old.target_position,"rotation":old.target_rotation,"resources":old.resources,"tracking":old.tracking}
		poses[id] = _pose_for(old,targets[id],delta)
	var conflict: String = _preflight(targets,poses,false)
	if not conflict.is_empty():
		motion_conflicts += 1
		last_conflict = conflict
		for old: Dictionary in _objects.values():
			old.body.constant_linear_velocity = Vector2.ZERO
			old.body.constant_angular_velocity = 0.0
		return
	for id: StringName in _objects:
		var body: PolygonObject = _objects[id].body
		var old_pose: Transform2D = body.global_transform
		body.global_transform = poses[id]
		body.force_update_transform()
		body.constant_linear_velocity = (body.position-old_pose.origin)/delta
		body.constant_angular_velocity = angle_difference(old_pose.get_rotation(),body.rotation)/delta
