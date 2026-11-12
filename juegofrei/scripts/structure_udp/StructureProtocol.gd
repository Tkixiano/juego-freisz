extends RefCounted
## Transport-only state machine. Does NOT instantiate/modify any physical object.
const Compound = preload("res://scripts/geometry/CompoundGeometryValidator.gd")
const MaterialContract = preload("res://scripts/geometry/MaterialGeometryValidator.gd")
const WIRE: String = "DYNAMIC_STRUCTURES_FRAGMENT"
const PROTOCOL: String = "DYNAMIC_STRUCTURES"
const CHUNK: int = 600
static var BASE64_PATTERN: RegEx = RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")
static var ASCII_PATTERN: RegEx = RegEx.create_from_string("^(?:[0-7][0-9a-f])*+$")
var max_datagram: int = 1200
var max_message: int = 262144
var max_fragments: int = 512
var max_pending: int = 8
var memory_limit: int = 1048576
var fragment_ttl_ms: int = 1000
var stale_ms: int = 1000
var max_snapshot_parts: int = 512
var max_snapshot_vertices: int = 16384
var max_sender_age_ms: int = 0
var pending: Dictionary = {}
var reserved_bytes: int = 0
var session_id: String = ""
var session_started_ms: int = 0
var sequence: int = 0
var logical_time: float = -1.0
var last_received_ms: int = -1
var scene_state: String = "SCENE_STALE"
var initial_without_structures: bool = true
var last_snapshot: Dictionary = {}
var ledger: Dictionary = {}
var active: Dictionary = {}
var geometry_cache: Dictionary = {}
var region_ledger: Dictionary = {}
var region_active: Dictionary = {}
var session_protocol_version: int = 0
var metrics: Dictionary = {"datagrams":0,"accepted":0,"rejected":0,"expired":0,"fragment_duplicates":0,"sessions":0,"merges":0,"splits":0,"gaps":0,"geometry_validations":0,"geometry_cache_hits":0,"peak_reserved_bytes":0,"peak_pending":0,"validation_us":[],"processing_us":[],"transport_age_ms":[],"accepted_at_ms":[]}
var errors: Array[Dictionary] = []
var rejection_counts: Dictionary = {}

func reject(reason: String) -> Dictionary:
	metrics.rejected += 1
	rejection_counts[reason] = int(rejection_counts.get(reason,0))+1
	errors.append({"reason":reason,"session":session_id,"sequence":sequence})
	if errors.size()>128: errors.pop_front()
	return {"ok":false,"reason":reason}

static func integer(value: Variant,minimum: int=0,maximum: int=2147483647) -> bool:
	return Compound.number(value) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

static func hex_string(value: Variant,length: int) -> bool:
	if not value is String or value.length()!=length: return false
	return value==value.to_lower() and value.is_valid_hex_number(false)

static func base64_valid(value: String) -> bool:
	if value.is_empty() or value.length()%4!=0: return false
	return BASE64_PATTERN.search(value)!=null

static func utf8_valid(bytes: PackedByteArray) -> bool:
	# Validate before decoding: corrupt UDP must not flood Godot's Unicode logger.
	# Normal wire traffic is ASCII (JSON escapes + base64); native fast path.
	if ASCII_PATTERN.search(bytes.hex_encode())!=null: return true
	var i: int = 0
	while i<bytes.size():
		var first: int = bytes[i]
		if first<128:
			i += 1
			continue
		var length: int = 2 if first>=194 and first<=223 else (3 if first>=224 and first<=239 else (4 if first>=240 and first<=244 else 0))
		if length==0 or i+length>bytes.size(): return false
		for j: int in range(1,length):
			if bytes[i+j]<128 or bytes[i+j]>191: return false
		if first==224 and bytes[i+1]<160: return false
		if first==237 and bytes[i+1]>=160: return false
		if first==240 and bytes[i+1]<144: return false
		if first==244 and bytes[i+1]>=144: return false
		i += length
	return true

func _sample(key: String,value: float) -> void:
	metrics[key].append(value)
	if metrics[key].size()>2048: metrics[key].pop_front()

func tick(now_ms: int) -> void:
	for key: String in pending.keys():
		if now_ms-int(pending[key].at)>=fragment_ttl_ms:
			reserved_bytes -= int(pending[key].header.total_bytes)
			pending.erase(key)
			metrics.expired += 1
	if last_received_ms>=0 and now_ms-last_received_ms>=stale_ms:
		scene_state = "SCENE_STALE"

func feed(bytes: PackedByteArray,now_ms: int,defer_complete: bool=false) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = _feed(bytes,now_ms,defer_complete)
	_sample("processing_us",Time.get_ticks_usec()-begin)
	return result

func _feed(bytes: PackedByteArray,now_ms: int,defer_complete: bool=false) -> Dictionary:
	tick(now_ms)
	metrics.datagrams += 1
	if bytes.is_empty() or bytes.size()>max_datagram: return reject("datagram_size")
	if not utf8_valid(bytes): return reject("utf8")
	var text: String = bytes.get_string_from_utf8()
	if text.to_utf8_buffer()!=bytes: return reject("utf8")
	var parser: JSON = JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary: return reject("fragment_json")
	var h: Dictionary = parser.data
	if h.get("wire")!=WIRE or h.get("version")!=1: return reject("wire_version")
	if not hex_string(h.get("session_id"),32) or not integer(h.get("session_started_ms"),1,9007199254740991) or not integer(h.get("sequence"),1): return reject("fragment_identity")
	if not integer(h.get("count"),1,max_fragments) or not integer(h.get("index"),0,int(h.count)-1) or not integer(h.get("total_bytes"),1,max_message): return reject("fragment_limits")
	if int(h.count)!=ceili(float(h.total_bytes)/CHUNK) or not hex_string(h.get("sha256"),64) or not h.get("data") is String: return reject("fragment_layout")
	if not session_id.is_empty():
		if h.session_id==session_id:
			if int(h.session_started_ms)!=session_started_ms: return reject("session_generation_changed")
			if int(h.sequence)<=sequence: return reject("duplicate_or_old_sequence")
		elif int(h.session_started_ms)<=session_started_ms: return reject("obsolete_session")
	if not base64_valid(h.data): return reject("fragment_payload")
	var raw: PackedByteArray = Marshalls.base64_to_raw(h.data)
	if raw.size()!=mini(CHUNK,int(h.total_bytes)-int(h.index)*CHUNK) or Marshalls.raw_to_base64(raw)!=h.data: return reject("fragment_payload")
	var key: String = "%s:%s:%s" % [h.session_id,h.session_started_ms,h.sequence]
	if not pending.has(key):
		if pending.size()>=max_pending or reserved_bytes+int(h.total_bytes)>memory_limit: return reject("reassembly_budget")
		pending[key] = {"at":now_ms,"header":h,"parts":{}}
		reserved_bytes += int(h.total_bytes)
		metrics.peak_reserved_bytes = maxi(metrics.peak_reserved_bytes,reserved_bytes)
		metrics.peak_pending = maxi(metrics.peak_pending,pending.size())
	var p: Dictionary = pending[key]
	for field: String in ["count","total_bytes","sha256"]:
		if h[field]!=p.header[field]: return reject("conflicting_header")
	var index: int = int(h.index)
	if p.parts.has(index):
		if p.parts[index]!=raw: return reject("conflicting_fragment")
		metrics.fragment_duplicates += 1
	else: p.parts[index] = raw
	if p.parts.size()!=int(h.count): return {"ok":true,"complete":false}
	var body: PackedByteArray = []
	for i: int in range(int(h.count)): body.append_array(p.parts[i])
	reserved_bytes -= int(h.total_bytes)
	pending.erase(key)
	var hash_context: HashingContext = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(body)
	if hash_context.finish().hex_encode()!=h.sha256: return reject("integrity")
	if not utf8_valid(body): return reject("utf8")
	text = body.get_string_from_utf8()
	if text.to_utf8_buffer()!=body or parser.parse(text)!=OK or not parser.data is Dictionary: return reject("message_json")
	var m: Dictionary = parser.data
	if m.get("session_id")!=h.session_id or m.get("session_started_ms")!=h.session_started_ms or m.get("sequence")!=h.sequence: return reject("envelope_mismatch")
	# Optional bounded receiver staging. Integrity is already verified, but this
	# candidate is NOT accepted and cannot reach physics before _accept succeeds.
	if defer_complete:return {"ok":true,"wire_complete":true,"candidate":m}
	return accept_snapshot(m,now_ms)

func accept_snapshot(m: Dictionary,now_ms: int) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = _accept(m,now_ms)
	_sample("validation_us",Time.get_ticks_usec()-begin)
	return result

func _accept(m: Dictionary,now_ms: int) -> Dictionary:
	if m.get("protocol")!=PROTOCOL or (m.get("protocol_version")!=1 and m.get("protocol_version")!=2) or m.get("geometry_contract_version")!=1: return reject("protocol")
	var multimaterial: bool = m.protocol_version==2
	if multimaterial and (m.get("material_contract_version")!=1 or not m.get("region_identity_epochs") is Dictionary):return reject("material_protocol")
	if not hex_string(m.get("session_id"),32) or not integer(m.get("session_started_ms"),1,9007199254740991) or not integer(m.get("sequence"),1): return reject("message_identity")
	if m.get("message_type") not in ["SESSION_START","SNAPSHOT"] or m.get("scene_state") not in ["SCENE_ACTIVE","SCENE_EMPTY","SCENE_ERROR"]: return reject("message_type_or_state")
	var new_session: bool = m.session_id!=session_id
	if not new_session and int(m.protocol_version)!=session_protocol_version:return reject("session_protocol_change")
	if new_session:
		if int(m.session_started_ms)<=session_started_ms or m.message_type!="SESSION_START": return reject("obsolete_or_unannounced_session")
	elif int(m.session_started_ms)!=session_started_ms or int(m.sequence)<=sequence: return reject("duplicate_or_old_sequence")
	if max_sender_age_ms>0:
		if not Compound.number(m.get("sent_unix_ms")): return reject("sender_timestamp")
		var sender_age: float = Time.get_unix_time_from_system()*1000-float(m.sent_unix_ms)
		if sender_age>max_sender_age_ms or sender_age< -1000: return reject("transport_expired_or_clock_skew")
	if not Compound.number(m.get("logical_time")) or float(m.logical_time)<0 or (not new_session and float(m.logical_time)<logical_time): return reject("logical_time")
	if not m.get("structures") is Array or m.structures.size()>32 or not m.get("identity_epochs") is Dictionary or not m.get("events") is Array or m.events.size()>64: return reject("snapshot_budget")
	if m.scene_state=="SCENE_ACTIVE" and m.structures.is_empty(): return reject("active_without_structures")
	if m.scene_state=="SCENE_EMPTY" and (not m.structures.is_empty() or m.get("empty_confirmed")!=true): return reject("unconfirmed_empty")
	if m.scene_state=="SCENE_EMPTY" and m.get("diagnostic") is Dictionary:
		var diagnostic: Dictionary = m.diagnostic
		if diagnostic.get("observed_components",0)!=0 or diagnostic.get("tracking_status")=="PENDING_TOPOLOGY": return reject("unconfirmed_empty")
	var proposed: Dictionary = {} if new_session else ledger.duplicate(true)
	var target: Dictionary = {}
	var cache_keep: Dictionary = {}
	var total_parts: int = 0
	var total_vertices: int = 0
	var regional_proposed: Dictionary = {} if new_session else region_ledger.duplicate(true)
	var regional_target: Dictionary = {}
	for s: Variant in m.structures:
		if not s is Dictionary or not s.get("id") is String or target.has(s.id): return reject("duplicate_or_invalid_id")
		if multimaterial and s.get("material_contract_version")!=1:return reject("material_contract_version")
		var epoch: Variant = m.identity_epochs.get(s.id)
		if not integer(epoch,1): return reject("identity_epoch")
		if not s.get("convex_parts") is Array or not s.get("regions") is Array: return reject("geometry_arrays")
		total_parts += s.convex_parts.size()
		for part: Variant in s.convex_parts:
			if not part is Array: return reject("part_array")
			total_vertices += part.size()
		if total_parts>max_snapshot_parts or total_vertices>max_snapshot_vertices: return reject("snapshot_geometry_budget")
		var metadata: Dictionary = Compound.validate_metadata(s)
		if not metadata.ok: return reject("geometry:"+metadata.reason)
		var fingerprint: String = JSON.stringify({"regions":s.regions,"convex_parts":s.convex_parts,"materials_present":s.has("material_regions"),"material_regions":s.get("material_regions")},"",true,true).sha256_text()
		if proposed.has(s.id):
			var previous: Dictionary = proposed[s.id]
			if int(s.geometry_version)<previous.version or (int(s.geometry_version)==previous.version and fingerprint!=previous.fingerprint): return reject("geometry_version_regression")
			# A higher epoch is recovery evidence of a missed retirement/reappearance.
			# Never confuse it with the previous incarnation or accept a lower epoch.
			if int(epoch)<previous.epoch or (not active.has(s.id) and int(epoch)<=previous.epoch): return reject("identity_epoch_reuse")
		var valid: Dictionary
		if not new_session and geometry_cache.has(s.id) and geometry_cache[s.id].fingerprint==fingerprint:
			valid = geometry_cache[s.id].valid.duplicate()
			valid.merge(metadata,true)
			metrics.geometry_cache_hits += 1
		else:
			valid = Compound.validate(s)
			metrics.geometry_validations += 1
			if not valid.ok: return reject("geometry:"+valid.reason)
			var material_result: Dictionary = _materials(s,valid)
			if not material_result.ok: return reject(material_result.reason)
		if multimaterial:
			if not geometry_cache.has(s.id) or new_session or geometry_cache[s.id].fingerprint!=fingerprint or not geometry_cache[s.id].get("material_checked",false):
				var material_valid: Dictionary = MaterialContract.validate(s)
				if not material_valid.ok or material_valid.get("legacy_only",true):return reject("material_contract:"+str(material_valid.get("reason","missing")))
			for region: Dictionary in s.material_regions:
				var id: String = region.region_id
				var regional_epoch: Variant = m.region_identity_epochs.get(id)
				if regional_target.has(id) or not integer(regional_epoch,1):return reject("regional_epoch_or_id")
				var key: String = JSON.stringify({"regions":region.regions,"parts":region.convex_parts,"material":region.material},"",true,true).sha256_text()
				if regional_proposed.has(id):
					var previous: Dictionary = regional_proposed[id]
					if region.geometry_version<previous.version or (region.geometry_version==previous.version and key!=previous.fingerprint):return reject("regional_version")
					if int(regional_epoch)<previous.epoch or (not region_active.has(id) and int(regional_epoch)<=previous.epoch):return reject("regional_epoch_reuse")
				regional_proposed[id] = {"version":region.geometry_version,"fingerprint":key,"epoch":int(regional_epoch)}
				regional_target[id] = true
		if absf(valid.position.x)>8192 or absf(valid.position.y)>8192 or absf(valid.rotation)>1000: return reject("pose_bounds")
		cache_keep[s.id] = {"fingerprint":fingerprint,"valid":valid,"material_checked":multimaterial}
		proposed[s.id] = {"version":int(s.geometry_version),"fingerprint":fingerprint,"epoch":int(epoch)}
		target[s.id] = true
	if proposed.size()>4096 or m.identity_epochs.size()!=target.size(): return reject("identity_budget_or_extra_epochs")
	if multimaterial and (regional_proposed.size()>4096 or regional_target.size()!=m.region_identity_epochs.size()):return reject("regional_identity_budget")
	for e: Variant in m.events:
		if not e is Dictionary or e.get("type") not in ["MERGE","SPLIT"]: return reject("event")
		for field: String in ["parents","children"]:
			if not e.get(field) is Array or e[field].is_empty() or e[field].size()>32: return reject("event_members")
			for id: Variant in e[field]:
				if not id is String or id.is_empty() or id.length()>64: return reject("event_id")
	# Commit ONLY after every field/geometry has passed. No physical manager exists here.
	if new_session:
		metrics.sessions += 1
		pending.clear()
		reserved_bytes = 0
	else: metrics.gaps += maxi(0,int(m.sequence)-sequence-1)
	# Release incomplete older states after a recovery snapshot supersedes them.
	for key: String in pending.keys():
		var h: Dictionary = pending[key].header
		if h.session_id==m.session_id and int(h.sequence)<=int(m.sequence):
			reserved_bytes -= int(h.total_bytes)
			pending.erase(key)
	session_id = m.session_id
	session_protocol_version = int(m.protocol_version)
	session_started_ms = int(m.session_started_ms)
	sequence = int(m.sequence)
	logical_time = float(m.logical_time)
	ledger = proposed
	active = target
	geometry_cache = cache_keep
	region_ledger = regional_proposed;region_active = regional_target
	last_snapshot = m.duplicate(true)
	scene_state = m.scene_state
	initial_without_structures = false
	last_received_ms = now_ms
	metrics.accepted += 1
	_sample("accepted_at_ms",now_ms)
	for e: Dictionary in m.events:
		if e.type=="MERGE": metrics.merges += 1
		else: metrics.splits += 1
	if Compound.number(m.get("sent_unix_ms")):
		var age: float = Time.get_unix_time_from_system()*1000-float(m.sent_unix_ms)
		if age>=0 and age<60000: _sample("transport_age_ms",age)
	return {"ok":true,"complete":true,"snapshot":last_snapshot.duplicate(true)}

func _materials(s: Dictionary,geometry: Dictionary) -> Dictionary:
	if not s.has("material_regions"): return {"ok":true}
	if not s.material_regions is Array or s.material_regions.is_empty() or s.material_regions.size()>32: return {"ok":false,"reason":"material_regions"}
	var seen: Array[PackedVector2Array] = []
	var area: float = 0
	var part_count: int = 0
	for item: Variant in s.material_regions:
		if not item is Dictionary or item.get("material") not in ["GREEN_SOLID","BLUE_BOUNCE","ORANGE_ONE_WAY"]: return {"ok":false,"reason":"material_id"}
		if not item.get("convex_parts") is Array: return {"ok":false,"reason":"material_parts"}
		part_count += item.convex_parts.size()
		if part_count>max_snapshot_parts: return {"ok":false,"reason":"material_budget"}
		var subset: Dictionary = s.duplicate(true)
		subset.regions = item.get("regions")
		subset.convex_parts = item.get("convex_parts")
		var v: Dictionary = Compound.validate(subset,512,2048,4096,0.0001)
		if not v.ok: return {"ok":false,"reason":"material_geometry"}
		for part: PackedVector2Array in v.parts:
			var inside: float = 0
			for parent: PackedVector2Array in geometry.parts: inside += Compound.intersection_area(part,parent)
			if absf(inside-absf(Compound.Simple.signed_area(part)))>0.001: return {"ok":false,"reason":"material_outside"}
			for previous: PackedVector2Array in seen:
				if Compound.intersection_area(previous,part)>0.0001: return {"ok":false,"reason":"material_overlap"}
			seen.append(part)
		area += v.area
	if absf(area-geometry.area)>0.001: return {"ok":false,"reason":"material_coverage"}
	return {"ok":true}

func status(now_ms: int) -> Dictionary:
	var times: Array = metrics.accepted_at_ms
	var hz: float = (times.size()-1)*1000.0/(times[-1]-times[0]) if times.size()>1 and times[-1]>times[0] else 0.0
	return {"session_id":session_id,"sequence":sequence,"scene_state":scene_state,"received_hz":hz,"initial_without_structures":initial_without_structures,"age_ms":now_ms-last_received_ms if last_received_ms>=0 else -1,"objects":active.size(),"pending_messages":pending.size(),"reserved_bytes":reserved_bytes,"metrics":metrics.duplicate(true),"rejections":rejection_counts.duplicate(),"errors":errors.duplicate(true)}
