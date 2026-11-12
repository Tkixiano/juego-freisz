extends SceneTree
var rows: Array = []
var udp: PacketPeerUDP = PacketPeerUDP.new()
func _initialize() -> void:call_deferred("run")
func check(name: String,ok: bool) -> void:
	rows.append({"name":name,"passed":ok})
	if not ok:push_error("STAGING "+name)
func packets(m: Dictionary) -> void:
	var body: PackedByteArray = JSON.stringify(m,"",true,true).to_utf8_buffer()
	var hash: HashingContext = HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(body)
	var digest: String = hash.finish().hex_encode();var count: int = ceili(body.size()/600.0)
	for i: int in range(count):
		var h: Dictionary = {"wire":"DYNAMIC_STRUCTURES_FRAGMENT","version":1,"session_id":m.session_id,"session_started_ms":m.session_started_ms,"sequence":m.sequence,"index":i,"count":count,"total_bytes":body.size(),"sha256":digest,"data":Marshalls.raw_to_base64(body.slice(i*600,mini((i+1)*600,body.size())))}
		udp.put_packet(JSON.stringify(h).to_utf8_buffer())
func run() -> void:
	var receiver: Node = load("res://scripts/structure_udp/StructureUdpReceiver.gd").new()
	receiver.auto_start = false;receiver.port = 5028;receiver.poll_budget_us = 100000;receiver.prioritize_latest_full_state = true
	root.add_child(receiver);receiver.start();receiver.protocol.max_sender_age_ms = 0;udp.set_dest_address("127.0.0.1",5028)
	var states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/performance_states.json"))
	var good: Dictionary = states["1"].duplicate(true);good.sequence = 1;good.logical_time = 1
	var bad: Dictionary = good.duplicate(true);bad.sequence = 2;bad.logical_time = 2;bad.structures[0].material_regions[0].material = "UNKNOWN"
	packets(good);packets(bad)
	for i: int in range(5):await physics_frame
	check("invalid_newest_falls_back_to_valid",receiver.protocol.sequence==1)
	check("invalid_material_not_published",receiver.protocol.metrics.accepted==1 and receiver.protocol.metrics.rejected>0)
	var later: Dictionary = good.duplicate(true);later.sequence = 4;later.logical_time = 4;later.message_type = "SNAPSHOT"
	var older: Dictionary = later.duplicate(true);older.sequence = 3;older.logical_time = 3
	packets(later);packets(older)
	for i: int in range(5):await physics_frame
	check("arrival_order_does_not_override_sequence",receiver.protocol.sequence==4)
	check("coalescing_is_bounded",receiver.full_states_coalesced==1 and receiver.protocol.pending.size()<=8)
	packets(later);packets(later)
	for i: int in range(5):await physics_frame
	check("duplicates_rejected",receiver.protocol.rejection_counts.has("duplicate_or_old_sequence") and receiver.protocol.metrics.accepted==2)
	var validator: GDScript = load("res://scripts/geometry/MaterialGeometryValidator.gd")
	var c: Dictionary = good.structures[0].duplicate(true);check("geometry_valid",validator.validate(c).ok)
	c.position[0] += 17;var moved: Dictionary = validator.validate(c)
	check("pose_cache_refreshes_metadata",moved.ok and moved.base.position.x==c.position[0])
	c.confidence = -1;check("pose_cache_validates_metadata",not validator.validate(c).ok)
	c.confidence = 1;c.material_regions[0].structure_id = "wrong";check("geometry_cache_validates_ownership",not validator.validate(c).ok)
	udp.close();receiver.stop()
	var failed: Array = rows.filter(func(r: Dictionary) -> bool:return not r.passed)
	var file: FileAccess = FileAccess.open("res://validation/staging_results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"total":rows.size(),"passed":rows.size()-failed.size(),"failures":failed}));file.close()
	print("STAGING ",rows.size()-failed.size(),"/",rows.size())
	quit(0 if failed.is_empty() else 1)
