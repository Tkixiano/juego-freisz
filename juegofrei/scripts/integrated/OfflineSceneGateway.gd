extends Node
## Source-neutral full-state boundary. No networking. Replay uses this as adapter.
signal batch_result(sequence: int,status: String,reason: String)
const Validator = preload("res://scripts/geometry/MaterialGeometryValidator.gd")
@export var confirmation_seconds: float = 0.10
@export var confirmation_updates: int = 3
@export var arena_offset: Vector2 = Vector2(300,180)
@onready var backend: Node = $"../Adapter"
@onready var manager: Node = $"../DynamicGeometry"
@onready var floor_controller: Node = $"../SafetyFloor"
var reset_requested: bool = false
var pending_frame: Dictionary:
	get:return backend.pending_frame
var scene_state: String = "SCENE_EMPTY"
var applied_state: String = "SCENE_EMPTY"
var session_id: String = ""
var spatial_mapping_key: String = ""
var high_sequence: int = 0
var high_time: float = -1
var clock: float = 0
var candidate: Dictionary = {}
var candidate_state: String = ""
var candidate_since: float = 0
var candidate_count: int = 0
var proposed_state: String = ""
var proposed_deadline_usec: int = 0
var buffered_events: Array = []
var metrics: Dictionary = {"received":0,"rejected":0,"held":0,"queued":0,"applied":0,"deferred":0,"source_resets":0,"validation_us":[]}
var errors: Array = []

func _ready() -> void:
	process_physics_priority = -75
	backend.batch_result.connect(_result)
	manager.environment_guard = self
	floor_controller.manager = manager
func accepts_material_replay() -> bool:return true
func migrate_legacy_frame(frame: Dictionary) -> Dictionary:return backend.migrate_legacy_frame(frame)
func request_reset() -> void:reset_requested = true
func set_health(state: String) -> void:
	if state not in ["SCENE_STALE","SCENE_ERROR"]:return
	backend.cancel_pending_source("source_health:"+state)
	scene_state = state;floor_controller.scene_state = state;manager.motion_paused = true
	candidate.clear();candidate_count = 0;candidate_state = ""
func _reject(seq: int,reason: String) -> Dictionary:
	metrics.rejected += 1;errors.append({"sequence":seq,"reason":reason})
	if errors.size()>128:errors.pop_front()
	batch_result.emit(seq,"REJECTED",reason)
	return {"status":"REJECTED","reason":reason}
func _spatial_mapping(frame: Dictionary) -> Dictionary:
	if not frame.has("spatial_mapping"):
		for c: Dictionary in frame.structures:
			if c.get("mapping")=="CALIBRATED_CAMERA_TO_ARENA_V1":return {"ok":false,"reason":"missing_spatial_mapping"}
		return {"ok":true,"key":"legacy_fixture","offset":arena_offset}
	var m: Variant = frame.spatial_mapping
	if not m is Dictionary or m.get("version")!=1 or m.get("space")!="GODOT_ARENA_PIXELS" or m.get("mapping")!="CALIBRATED_CAMERA_TO_ARENA_V1" or m.get("cell_convention")!="PIXEL_CELL_EDGES":return {"ok":false,"reason":"spatial_mapping_schema"}
	if not m.get("arena_size") is Array or m.arena_size.size()!=2 or not manager.CompoundValidator.number(m.arena_size[0]) or not manager.CompoundValidator.number(m.arena_size[1]) or float(m.arena_size[0])!=1280 or float(m.arena_size[1])!=720 or not m.get("arena_rect") is Array or m.arena_rect.size()!=4:return {"ok":false,"reason":"spatial_mapping_arena"}
	for v: Variant in m.arena_rect:
		if not manager.CompoundValidator.number(v):return {"ok":false,"reason":"spatial_mapping_rect"}
	var rect: Rect2 = Rect2(m.arena_rect[0],m.arena_rect[1],m.arena_rect[2],m.arena_rect[3])
	if rect.position.x<0 or rect.position.y<0 or rect.size.x<=0 or rect.size.y<=0 or rect.end.x>1280 or rect.end.y>720:return {"ok":false,"reason":"spatial_mapping_rect"}
	var signature: Variant = m.get("calibration_signature")
	if not signature is String or signature.length()!=64 or not signature.is_valid_hex_number(false):return {"ok":false,"reason":"calibration_signature"}
	for c: Dictionary in frame.structures:
		if c.get("mapping")!="CALIBRATED_CAMERA_TO_ARENA_V1":return {"ok":false,"reason":"mixed_coordinate_mappings"}
		var pose: Transform2D = Transform2D(float(c.orientation_radians),Vector2(c.position[0],c.position[1]))
		for part: Array in c.convex_parts:
			for p: Array in part:
				var point: Vector2 = pose*Vector2(p[0],p[1])
				if not rect.grow(0.001).has_point(point):return {"ok":false,"reason":"calibrated_geometry_outside_arena"}
	return {"ok":true,"key":JSON.stringify(m,"",true,true),"offset":Vector2.ZERO}
func submit(frame: Dictionary) -> Dictionary:
	var start: int = Time.get_ticks_usec();metrics.received += 1
	var result: Dictionary = _submit(frame)
	metrics.validation_us.append(Time.get_ticks_usec()-start)
	if metrics.validation_us.size()>4096:metrics.validation_us.pop_front()
	return result
func _submit(frame: Dictionary) -> Dictionary:
	if reset_requested or not pending_frame.is_empty():return _reject(0,"source_busy")
	var seq: Variant = frame.get("sequence")
	var time: Variant = frame.get("logical_time")
	if not manager.CompoundValidator.number(seq) or float(seq)<1 or floorf(float(seq))!=float(seq) or float(seq)>2147483647:return _reject(0,"sequence")
	if not manager.CompoundValidator.number(time) or float(time)<0 or float(time)<high_time or seq<=high_sequence:return _reject(int(seq),"duplicate_or_old")
	var sid: Variant = frame.get("session_id","legacy")
	if not sid is String or sid.is_empty() or sid.length()>64 or (not session_id.is_empty() and sid!=session_id):return _reject(int(seq),"source_session")
	if not frame.get("structures") is Array or not frame.get("identity_epochs") is Dictionary or not frame.get("events") is Array:return _reject(int(seq),"full_state")
	if frame.structures.size()>manager.max_objects or frame.events.size()>128:return _reject(int(seq),"snapshot_budget")
	if frame.has("diagnostic") and not frame.diagnostic is Dictionary:return _reject(int(seq),"diagnostic_type")
	for event: Variant in frame.events:
		if not event is Dictionary or event.get("type") not in ["MERGE","SPLIT"] or not event.get("parents") is Array or not event.get("children") is Array:return _reject(int(seq),"event")
		for id: Variant in event.parents+event.children:
			if not id is String:return _reject(int(seq),"event_identity")
	for c: Variant in frame.structures:
		if not c is Dictionary or not Validator.validate(c).ok:
			set_health("SCENE_ERROR");return _reject(int(seq),"material_contract")
	var spatial: Dictionary = _spatial_mapping(frame)
	if not spatial.ok:
		set_health("SCENE_ERROR");return _reject(int(seq),spatial.reason)
	if not spatial_mapping_key.is_empty() and spatial_mapping_key!=spatial.key:
		set_health("SCENE_ERROR");return _reject(int(seq),"mapping_change_requires_source_reset")
	spatial_mapping_key = spatial.key
	high_sequence = int(seq);high_time = float(time);session_id = sid
	buffered_events.append_array(frame.events.duplicate(true))
	if buffered_events.size()>128:buffered_events = buffered_events.slice(-128)
	var diagnostic: Dictionary = frame.get("diagnostic",{}) if frame.get("diagnostic",{}) is Dictionary else {}
	var status: String = String(diagnostic.get("status",diagnostic.get("tracking_status","TRACKING")))
	var health: String = String(frame.get("scene_state",""))
	if health in ["SCENE_STALE","SCENE_ERROR"] or status!="TRACKING":
		set_health("SCENE_ERROR" if health=="SCENE_ERROR" or status=="REJECTED" else "SCENE_STALE")
		metrics.held += 1;return {"status":"HELD"}
	var desired: String = "SCENE_EMPTY" if frame.structures.is_empty() else "SCENE_ACTIVE"
	if not health.is_empty() and health!=desired:return _reject(int(seq),"scene_state_mismatch")
	if desired!=candidate_state:
		candidate_state = desired;candidate_since = clock;candidate_count = 0
	candidate_count += 1;candidate = frame.duplicate(true);candidate.session_id = sid
	# Trusted UDP ingress counts validated observations even when coalesced.
	# The OFFLINE port removes these local-only fields.
	if frame.has("_observed_count"):
		candidate_count = maxi(candidate_count,int(frame._observed_count))
		candidate_since = minf(candidate_since,clock-maxf(0,float(frame.get("_observed_elapsed",0))))
	for c: Dictionary in candidate.structures:
		c.position = [float(c.position[0])+spatial.offset.x,float(c.position[1])+spatial.offset.y]
	if candidate_count>=confirmation_updates and clock-candidate_since+0.00001>=confirmation_seconds:return _dispatch()
	metrics.held += 1;return {"status":"HELD","reason":"scene_confirmation"}
func _dispatch() -> Dictionary:
	if candidate.is_empty() or not pending_frame.is_empty():return {"status":"HELD"}
	var frame: Dictionary = candidate;candidate = {}
	# Events are advisory; retain delayed topology diagnostics through hysteresis.
	var roots: Dictionary = frame.identity_epochs
	frame.events = buffered_events.filter(func(e: Dictionary) -> bool:
		for id: Variant in e.children:
			if not roots.has(id):return false
		return true)
	var result: Dictionary = backend.submit(frame)
	if result.status=="QUEUED":
		buffered_events.clear()
		proposed_state = candidate_state;scene_state = proposed_state;metrics.queued += 1
		proposed_deadline_usec = int(frame.get("_apply_deadline_usec",0))
		manager.motion_paused = false
	return result
func _result(seq: int,status: String,reason: String) -> void:
	if status=="APPLIED":
		metrics.applied += 1;applied_state = proposed_state;scene_state = applied_state
		floor_controller.scene_state = applied_state
		if applied_state=="SCENE_EMPTY":floor_controller.last_reason = "";floor_controller.previous_reason = ""
	elif status=="DEFERRED":metrics.deferred += 1
	elif status=="REJECTED":metrics.rejected += 1
	batch_result.emit(seq,status,reason)
func preflight(targets: Dictionary,poses: Dictionary) -> String:
	if scene_state in ["SCENE_STALE","SCENE_ERROR"]:return "source_not_healthy"
	if proposed_deadline_usec>0 and Time.get_ticks_usec()>proposed_deadline_usec:return "external_state_expired"
	if targets.is_empty() and proposed_state=="SCENE_EMPTY":
		var reason: String = floor_controller.activation_reason()
		if not reason.is_empty():
			if floor_controller.last_reason!=reason:floor_controller.metrics.activation_deferrals += 1
			floor_controller.last_reason = reason
		return reason
	if floor_controller.enabled and floor_controller.target_overlaps(targets,poses):
		var reason: String = floor_controller.retirement_reason()
		if not reason.is_empty():floor_controller.record_deferral(reason);return "floor_required:"+reason
	return ""
func before_commit(targets: Dictionary,poses: Dictionary) -> void:
	if targets.is_empty() and proposed_state=="SCENE_EMPTY":floor_controller.set_enabled(true)
	elif floor_controller.enabled and floor_controller.target_overlaps(targets,poses):floor_controller.set_enabled(false)
func _physics_process(delta: float) -> void:
	clock += delta
	if reset_requested:
		backend.reset_source_preserving_geometry();reset_requested = false
		session_id = "";spatial_mapping_key = "";high_sequence = 0;high_time = -1;metrics.source_resets += 1
		buffered_events.clear()
		proposed_deadline_usec = 0
		set_health("SCENE_STALE")
	elif not candidate.is_empty() and candidate_count>=confirmation_updates and clock-candidate_since>=confirmation_seconds and pending_frame.is_empty():_dispatch()
