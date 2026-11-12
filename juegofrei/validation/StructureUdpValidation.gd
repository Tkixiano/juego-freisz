extends RefCounted
const Protocol = preload("res://scripts/structure_udp/StructureProtocol.gd")
var rows: Array[Dictionary] = []
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
func run() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://validation/structure_udp_vectors.json",FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	var steps: int = 0
	for c: Dictionary in data.cases:
		var vector_core: RefCounted = Protocol.new()
		var now: int = 0
		for command: Dictionary in c.commands:
			steps += 1
			if steps%64==0: await Engine.get_main_loop().process_frame
			if command.has("advance_ms"):
				now += int(command.advance_ms)
				vector_core.tick(now)
			else:
				for packet: String in command.packets:
					vector_core.feed(Marshalls.base64_to_raw(packet),now)
				now += 1
		var status: Dictionary = vector_core.status(now)
		for key: String in c.expect:
			var actual: Variant
			match key:
				"reason": actual = c.expect.reason if vector_core.rejection_counts.has(c.expect.reason) else "missing:"+JSON.stringify(vector_core.rejection_counts)
				"pending": actual = vector_core.pending.size()
				_: actual = status.get(key,vector_core.metrics.get(key))
			check(c.name+":"+key,actual==c.expect[key],actual)
		check(c.name+":memory_bounded",vector_core.reserved_bytes<=vector_core.memory_limit,vector_core.reserved_bytes)
	# Additional safety checks using the exact decoded Python-produced snapshot.
	var core: RefCounted = Protocol.new()
	for packet: String in data.cases[0].commands[0].packets:
		core.feed(Marshalls.base64_to_raw(packet),0)
	var original: Dictionary = core.last_snapshot.duplicate(true)
	var next: Dictionary = original.duplicate(true)
	next.sequence = 2
	next.structures[0].position[0] += 3
	var answer: Dictionary = core.accept_snapshot(next,10)
	check("pose_only_uses_validated_geometry",answer.ok and core.metrics.geometry_cache_hits==next.structures.size())
	answer.snapshot.structures.clear()
	check("published_snapshot_not_internal_storage",not core.last_snapshot.structures.is_empty())
	var prior: Dictionary = core.last_snapshot.duplicate(true)
	next.sequence = 3
	next.structures[0].units = "meters"
	check("metadata_rejection_atomic",not core.accept_snapshot(next,20).ok and core.last_snapshot==prior and core.sequence==2)
	core = Protocol.new()
	core.max_sender_age_ms = 500
	var timestamped: Dictionary = original.duplicate(true)
	timestamped.sent_unix_ms = Time.get_unix_time_from_system()*1000-1000
	check("aged_sender_message_rejected",not core.accept_snapshot(timestamped,0).ok and core.sequence==0)
	timestamped.sent_unix_ms = Time.get_unix_time_from_system()*1000+2000
	check("future_clock_skew_rejected",not core.accept_snapshot(timestamped,0).ok)
	timestamped.sent_unix_ms = Time.get_unix_time_from_system()*1000
	check("fresh_message_recovers",core.accept_snapshot(timestamped,1).ok)
	check("utf8_valid_multibyte",Protocol.utf8_valid("Módulo azul".to_utf8_buffer()))
	check("utf8_reject_overlong",not Protocol.utf8_valid(PackedByteArray([192,128])))
	check("utf8_reject_surrogate",not Protocol.utf8_valid(PackedByteArray([237,160,128])))
	check("utf8_reject_outside_unicode",not Protocol.utf8_valid(PackedByteArray([244,144,128,128])))
	check("utf8_reject_truncated",not Protocol.utf8_valid(PackedByteArray([226,130])))
	var failures: Array = rows.filter(func(r: Dictionary) -> bool: return not r.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows}
	var out: FileAccess = FileAccess.open("res://validation/structure_udp_results.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(result,"  "))
	print("STRUCTURE_UDP_TESTS ",result.passed,"/",result.total," ",failures)
	if Engine.get_main_loop().current_scene!=null: Engine.get_main_loop().current_scene.set_meta("structure_udp_core_result",result)
	return result
