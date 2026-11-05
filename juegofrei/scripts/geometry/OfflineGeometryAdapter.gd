extends Node
## Full snapshots -> validated, versioned transactions. Never opens sockets/files.
signal batch_result(sequence: int,status: String,reason: String)
@export var manager_path: NodePath = NodePath("../DynamicGeometry")
@onready var manager: Node = get_node(manager_path)
var high_sequence: int = 0
var high_time: float = -1.0
var applied_sequence: int = 0
var ledger: Dictionary = {}
var active: Dictionary = {}
var pending_frame: Dictionary = {}
var pending_ledger: Dictionary = {}
var reset_requested: bool = false
var errors: Array[Dictionary] = []
var metrics: Dictionary = {"received":0,"accepted":0,"rejected":0,"deferred":0,"applied":0,"cancelled":0,"validation_us":[],"application_us":[],"identity_changes":0,"merges":0,"splits":0,"player_penetration_deferrals":0}
var last_diff: Dictionary = {}

func _ready() -> void:
	process_physics_priority = -80
	manager.transaction_finished.connect(_on_transaction)

func _record_error(category: String,sequence: int,reason: String) -> void:
	errors.append({"category":category,"sequence":sequence,"reason":reason,"physics_frame":Engine.get_physics_frames()})
	if errors.size()>128: errors.pop_front()

func _reject(sequence: int,reason: String) -> Dictionary:
	metrics.rejected += 1
	_record_error("validation",sequence,reason)
	batch_result.emit(sequence,"REJECTED",reason)
	return {"status":"REJECTED","reason":reason}

func _fingerprint(data: Dictionary) -> String:
	return JSON.stringify({"regions":data.get("regions"),"convex_parts":data.get("convex_parts")},"",true,true).sha256_text()

func submit(frame: Dictionary) -> Dictionary:
	metrics.received += 1
	var start: int = Time.get_ticks_usec()
	var result: Dictionary = _prepare(frame)
	metrics.validation_us.append(Time.get_ticks_usec()-start)
	if metrics.validation_us.size()>4096: metrics.validation_us.pop_front()
	return result

func _prepare(frame: Dictionary) -> Dictionary:
	var seq: Variant = frame.get("sequence")
	if not manager.CompoundValidator.number(seq) or float(seq)<1 or float(seq)>2147483647 or floorf(float(seq))!=float(seq): return _reject(0,"sequence_type")
	var sequence: int = int(seq)
	if not pending_frame.is_empty() or reset_requested: return _reject(sequence,"adapter_busy")
	if sequence<=high_sequence: return _reject(sequence,"duplicate_or_old_sequence")
	var time: Variant = frame.get("logical_time")
	if not manager.CompoundValidator.number(time) or float(time)<0 or float(time)<high_time: return _reject(sequence,"logical_time")
	high_sequence = sequence
	high_time = float(time)
	if not frame.get("structures") is Array or not frame.get("identity_epochs") is Dictionary or not frame.get("events") is Array: return _reject(sequence,"snapshot_structure")
	if ledger.size()+frame.structures.size()>4096: return _reject(sequence,"identity_ledger_budget")
	var proposed: Dictionary = ledger.duplicate(true)
	var target: Dictionary = {}
	for value: Variant in frame.structures:
		if not value is Dictionary or not value.get("id") is String: return _reject(sequence,"structure_id")
		var id: String = value.id
		if target.has(id): return _reject(sequence,"duplicate_id")
		var epoch: Variant = frame.identity_epochs.get(id)
		if not manager.CompoundValidator.number(epoch) or float(epoch)<1 or float(epoch)>2147483647 or floorf(float(epoch))!=float(epoch): return _reject(sequence,"identity_epoch")
		var version: Variant = value.get("geometry_version")
		if not manager.CompoundValidator.number(version): return _reject(sequence,"geometry_version")
		var key: String = _fingerprint(value)
		if ledger.has(id):
			var prior: Dictionary = ledger[id]
			if float(version)<prior.version or (float(version)==prior.version and key!=prior.fingerprint): return _reject(sequence,"geometry_version_regression_or_reused_version")
			if (active.has(id) and int(epoch)!=prior.epoch) or (not active.has(id) and int(epoch)<=prior.epoch): return _reject(sequence,"identity_reuse_without_new_epoch")
	# First observation may be a recovery snapshot after skipped births/merges.
	# Its epoch need not be 1; once known, reuse rules are strict.
		proposed[id] = {"version":int(version),"fingerprint":key,"epoch":int(epoch)}
		target[id] = value.duplicate(true)
	if frame.identity_epochs.size()!=target.size(): return _reject(sequence,"extra_identity_epochs")
	for event: Variant in frame.events:
		if not event is Dictionary or event.get("type") not in ["MERGE","SPLIT"] or not event.get("parents") is Array or not event.get("children") is Array: return _reject(sequence,"event_structure")
		for id: Variant in event.parents+event.children:
			if not id is String: return _reject(sequence,"event_identity")
	var prepared: Dictionary = manager.prepare_snapshot(frame.structures)
	if not prepared.ok: return _reject(sequence,prepared.reason)
	last_diff = _diff(target,prepared.objects)
	pending_frame = frame.duplicate(true)
	pending_ledger = proposed
	var topology: bool = not last_diff.added.is_empty() or not last_diff.removed.is_empty() or not last_diff.geometry_changed.is_empty()
	if not manager.queue_snapshot(prepared,sequence,topology):
		pending_frame.clear()
		return _reject(sequence,"manager_busy")
	metrics.accepted += 1
	return {"status":"QUEUED","diff":last_diff}

func _diff(target: Dictionary,prepared: Dictionary) -> Dictionary:
	var d: Dictionary = {"added":[],"removed":[],"geometry_changed":[],"pose_changed":[],"merges":0,"splits":0}
	for id: String in active:
		if not target.has(id): d.removed.append(id)
	for id: String in target:
		if not active.has(id): d.added.append(id)
		else:
			if _fingerprint(active[id])!=_fingerprint(target[id]): d.geometry_changed.append(id)
			if active[id].position!=target[id].position or active[id].orientation_radians!=target[id].orientation_radians: d.pose_changed.append(id)
	# Infer topology from geometry overlap, independently of advisory source events.
	var graph: Dictionary = {}
	for old_id: String in d.removed:
		var body: Node2D = manager.get_body(StringName(old_id))
		if body==null: continue
		for new_id: String in d.added:
			var candidate: Dictionary = prepared[StringName(new_id)]
			var transform: Transform2D = Transform2D(candidate.rotation,candidate.position)
			var overlap: bool = false
			for a: PackedVector2Array in body.convex_parts:
				for b: PackedVector2Array in candidate.parts:
					if manager.CompoundValidator.intersection_area(body.global_transform*a,transform*b)>0.001: overlap = true
			if overlap:
				var a: String = "old:"+old_id
				var b: String = "new:"+new_id
				if not graph.has(a): graph[a] = []
				if not graph.has(b): graph[b] = []
				graph[a].append(b)
				graph[b].append(a)
	var visited: Dictionary = {}
	for node: String in graph:
		if visited.has(node): continue
		var todo: Array = [node]
		var parents: int = 0
		var children: int = 0
		while not todo.is_empty():
			var current: String = todo.pop_back()
			if visited.has(current): continue
			visited[current] = true
			if current.begins_with("old:"): parents += 1
			else: children += 1
			todo.append_array(graph[current])
		if parents>1 and children==1: d.merges += 1
		if parents==1 and children>1: d.splits += 1
	return d

func _on_transaction(token: int,status: String,reason: String,application_us: int) -> void:
	if pending_frame.is_empty() or int(pending_frame.sequence)!=token: return
	if status=="DEFERRED":
		metrics.deferred += 1
		if reason=="character_penetration": metrics.player_penetration_deferrals += 1
		_record_error("physical_conflict",token,reason)
		batch_result.emit(token,status,reason)
		return
	metrics.applied += 1
	metrics.application_us.append(application_us)
	if metrics.application_us.size()>4096: metrics.application_us.pop_front()
	metrics.identity_changes += last_diff.added.size()+last_diff.removed.size()
	metrics.merges += last_diff.merges
	metrics.splits += last_diff.splits
	active.clear()
	for c: Dictionary in pending_frame.structures: active[c.id] = c
	ledger = pending_ledger
	applied_sequence = token
	pending_frame.clear()
	pending_ledger = {}
	batch_result.emit(token,"APPLIED","")

func request_reset() -> void:
	reset_requested = true

func _physics_process(_delta: float) -> void:
	if not reset_requested: return
	if not pending_frame.is_empty():
		metrics.cancelled += 1
		batch_result.emit(int(pending_frame.sequence),"CANCELLED","session_reset")
	manager.reset_offline()
	active.clear()
	ledger.clear()
	pending_frame.clear()
	pending_ledger.clear()
	high_sequence = 0
	high_time = -1
	applied_sequence = 0
	reset_requested = false

func get_status() -> Dictionary:
	var shapes: int = 0
	for id: StringName in manager.object_ids(): shapes += manager.get_body(id).colliders.size()
	return {"high_sequence":high_sequence,"applied_sequence":applied_sequence,"pending":not pending_frame.is_empty(),"active_objects":manager.object_ids().size(),"physical_shapes":shapes,"geometry_rebuilds":manager.total_rebuilds,"prepared_geometry_builds":manager.prepared_geometry_builds,"physical_validation_us":manager.physical_validation_us.duplicate(),"motion_conflicts":manager.motion_conflicts,"metrics":metrics.duplicate(true),"errors":errors.duplicate(true),"last_diff":last_diff.duplicate(true)}
