extends "res://scripts/geometry/OfflineGeometryAdapter.gd"
const MaterialValidator = preload("res://scripts/geometry/MaterialGeometryValidator.gd")
var logical_active: Dictionary = {}
var logical_ledger: Dictionary = {}
var logical_pending: Dictionary = {}
var logical_pending_ledger: Dictionary = {}
var logical_events: Array = []
var session_id: String = ""
var logical_diff: Dictionary = {}
var pending_logical_diff: Dictionary = {}
var logical_metrics: Dictionary = {"received":0,"queued":0,"rejected":0,"merges":0,"splits":0,"validation_us":[]}

func accepts_material_replay() -> bool: return true

func cancel_pending_source(reason: String) -> void:
	if pending_frame.is_empty():return
	var token: int = int(pending_frame.sequence)
	manager.pending.clear();pending_frame.clear();pending_ledger.clear()
	logical_pending.clear();logical_pending_ledger.clear();pending_logical_diff.clear();logical_events.clear()
	manager.motion_paused = true;metrics.cancelled += 1
	# Committed ledgers and identities survive. Only the unapplied target is gone.
	batch_result.emit(token,"CANCELLED",reason)

func reset_source_preserving_geometry() -> void:
	# Source boundary only. The previous complete physical/logical state remains.
	if not pending_frame.is_empty():
		metrics.cancelled += 1
		batch_result.emit(int(pending_frame.sequence),"CANCELLED","source_reset")
	manager.pending.clear()
	for id: StringName in manager.object_ids():
		var body: Node = manager.get_body(id)
		body.constant_linear_velocity = Vector2.ZERO;body.constant_angular_velocity = 0.0
	manager.motion_paused = true
	pending_frame.clear();pending_ledger.clear();logical_pending.clear();logical_pending_ledger.clear()
	logical_ledger.clear();ledger.clear();logical_events.clear();pending_logical_diff.clear()
	high_sequence = 0;high_time = -1;applied_sequence = 0;session_id = ""

func migrate_legacy_frame(frame: Dictionary) -> Dictionary:
	var copy: Dictionary = frame.duplicate(true)
	if not copy.get("structures") is Array: return copy
	for c: Variant in copy.structures:
		if not c is Dictionary or c.has("material_contract_version"): continue
		var id: String = "legacy_"+String(c.get("id","")).sha256_text().substr(0,24)
		c.material_contract_version = 1
		c.material_regions = [{"region_id":id,"structure_id":c.get("id"),"material":"GREEN_SOLID","geometry_version":c.get("geometry_version"),"regions":c.get("regions"),"convex_parts":c.get("convex_parts")}]
	return copy

func _logical_difference(target: Dictionary) -> Dictionary:
	var diff: Dictionary = {"structures_created":[],"structures_removed":[],"pose_changed":[],"regions_created":[],"regions_removed":[],"geometry_changed":[],"material_changed":[],"reparented":[],"unchanged":[]}
	var old_regions: Dictionary = {}
	var new_regions: Dictionary = {}
	for id: String in logical_active:
		if not target.has(id): diff.structures_removed.append(id)
		for r: Dictionary in logical_active[id].material_regions: old_regions[r.region_id] = r
	for id: String in target:
		if not logical_active.has(id): diff.structures_created.append(id)
		elif target[id].position!=logical_active[id].position or target[id].orientation_radians!=logical_active[id].orientation_radians: diff.pose_changed.append(id)
		for r: Dictionary in target[id].material_regions: new_regions[r.region_id] = r
	for id: String in old_regions:
		if not new_regions.has(id): diff.regions_removed.append(id)
	for id: String in new_regions:
		if not old_regions.has(id): diff.regions_created.append(id);continue
		var a: Dictionary = old_regions[id]
		var b: Dictionary = new_regions[id]
		var changed: bool = false
		if a.material!=b.material: diff.material_changed.append(id);changed = true
		if a.structure_id!=b.structure_id: diff.reparented.append(id);changed = true
		if a.regions!=b.regions or a.convex_parts!=b.convex_parts: diff.geometry_changed.append(id);changed = true
		if not changed: diff.unchanged.append(id)
	return diff

func _fingerprint(data: Dictionary) -> String:
	return JSON.stringify({"geometry":super._fingerprint(data),"kind":data.get("material_kind")},"",true,true).sha256_text()

func submit(frame: Dictionary) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	logical_metrics.received += 1
	var result: Dictionary = _submit_material_frame(frame)
	logical_metrics.validation_us.append(Time.get_ticks_usec()-start)
	if logical_metrics.validation_us.size()>4096: logical_metrics.validation_us.pop_front()
	if result.status=="QUEUED": logical_metrics.queued += 1
	else: logical_metrics.rejected += 1
	return result

func _submit_material_frame(frame: Dictionary) -> Dictionary:
	if not pending_frame.is_empty() or reset_requested: return _reject(int(frame.get("sequence",0)),"adapter_busy")
	var incoming_session: Variant = frame.get("session_id","")
	if not incoming_session is String or incoming_session.length()>64: return _reject(0,"session_id")
	if not session_id.is_empty() and incoming_session!=session_id: return _reject(0,"session_mismatch_requires_reset")
	if not frame.get("structures") is Array or not frame.get("identity_epochs") is Dictionary: return _reject(0,"logical_snapshot")
	if frame.has("region_identity_epochs") and not frame.region_identity_epochs is Dictionary: return _reject(0,"regional_epochs")
	if logical_ledger.size()+frame.structures.size()>4096: return _reject(0,"logical_identity_budget")
	var flat: Array = []
	var epochs: Dictionary = {}
	var regional_ids: Dictionary = {}
	var logical: Dictionary = {}
	var proposed: Dictionary = logical_ledger.duplicate(true)
	for c: Variant in frame.structures:
		if not c is Dictionary: return _reject(0,"logical_contract")
		var valid: Dictionary = MaterialValidator.validate(c)
		if not valid.ok or valid.get("legacy_only",true): return _reject(0,"material_contract:"+str(valid.get("reason","extension_required")))
		if logical.has(c.id): return _reject(0,"duplicate_logical_id")
		var epoch: Variant = frame.identity_epochs.get(c.id)
		if not manager.CompoundValidator.number(epoch) or float(epoch)<1 or floorf(float(epoch))!=float(epoch): return _reject(0,"logical_epoch")
		var fingerprint: String = JSON.stringify({"regions":c.regions,"materials":c.material_regions},"",true,true).sha256_text()
		if proposed.has(c.id):
			var prior: Dictionary = proposed[c.id]
			if c.geometry_version<prior.version or (c.geometry_version==prior.version and fingerprint!=prior.fingerprint): return _reject(0,"logical_geometry_version")
			var recovered: bool = frame.get("allow_identity_recovery",false)==true and epoch>prior.epoch
			if (logical_active.has(c.id) and epoch!=prior.epoch and not recovered) or (not logical_active.has(c.id) and epoch<=prior.epoch): return _reject(0,"logical_epoch_reuse")
		proposed[c.id] = {"version":c.geometry_version,"fingerprint":fingerprint,"epoch":epoch}
		logical[c.id] = c.duplicate(true)
		for region: Dictionary in c.material_regions:
			if regional_ids.has(region.region_id): return _reject(0,"duplicate_regional_id")
			regional_ids[region.region_id] = true
			# Read-only local geometry is owned by the incoming snapshot. The base
			# adapter makes its own deep copy at the transaction boundary.
			var copy: Dictionary = c.duplicate()
			copy.erase("material_regions");copy.erase("material_contract_version")
			copy.id = region.region_id
			copy.regions = region.regions
			copy.convex_parts = region.convex_parts
			copy.geometry_version = region.geometry_version
			copy.material_kind = region.material
			copy.structure_id = c.id
			flat.append(copy)
			var prior: Dictionary = ledger.get(copy.id,{})
			if frame.has("region_identity_epochs"):
				var regional_epoch: Variant = frame.region_identity_epochs.get(copy.id)
				if not manager.CompoundValidator.number(regional_epoch) or float(regional_epoch)<1 or float(regional_epoch)>2147483647 or floorf(float(regional_epoch))!=float(regional_epoch): return _reject(0,"regional_epoch")
				epochs[copy.id] = regional_epoch
			else: epochs[copy.id] = int(prior.get("epoch",0))+(0 if active.has(copy.id) else 1)
	if frame.identity_epochs.size()!=logical.size(): return _reject(0,"extra_logical_epochs")
	if frame.has("region_identity_epochs") and frame.region_identity_epochs.size()!=regional_ids.size(): return _reject(0,"extra_regional_epochs")
	var converted: Dictionary = frame.duplicate()
	converted.structures = flat;converted.identity_epochs = epochs
	var result: Dictionary = super.submit(converted)
	if result.status=="QUEUED":
		session_id = incoming_session
		pending_logical_diff = _logical_difference(logical)
		logical_pending = logical;logical_pending_ledger = proposed
		logical_events = frame.get("events",[]).duplicate(true)
	return result

func _on_transaction(token: int,status: String,reason: String,application_us: int) -> void:
	if pending_frame.is_empty() or int(pending_frame.sequence)!=token: return
	if status=="APPLIED":
		for event: Dictionary in logical_events:
			if event.type=="MERGE": logical_metrics.merges += 1
			if event.type=="SPLIT": logical_metrics.splits += 1
		logical_active = logical_pending;logical_ledger = logical_pending_ledger
		logical_diff = pending_logical_diff
		logical_pending = {};logical_pending_ledger = {}
	super._on_transaction(token,status,reason,application_us)

func _physics_process(delta: float) -> void:
	var resetting: bool = reset_requested
	super._physics_process(delta)
	if resetting:
		logical_active.clear();logical_ledger.clear();logical_pending.clear();logical_pending_ledger.clear()
		session_id = "";logical_diff.clear();pending_logical_diff.clear();logical_events.clear()

func get_status() -> Dictionary:
	var result: Dictionary = super.get_status()
	result.logical_structures = logical_active.size()
	result.material_regions = active.size()
	result.session_id = session_id
	result.logical_diff = logical_diff.duplicate(true)
	result.logical_metrics = logical_metrics.duplicate(true)
	return result
