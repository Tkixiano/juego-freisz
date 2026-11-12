extends Node
## Lab-only receiver. Publishes full snapshots; intentionally has no manager reference.
signal snapshot_accepted(snapshot: Dictionary)
const Protocol = preload("res://scripts/structure_udp/StructureProtocol.gd")
@export var bind_ip: String = "127.0.0.1"
@export var port: int = 5015
@export var auto_start: bool = true
@export var max_packets_per_tick: int = 128
@export var max_completed_per_tick: int = 2
@export var poll_budget_us: int = 8000
@export var max_message_bytes: int = 262144
@export var max_pending_messages: int = 8
@export var reassembly_memory_bytes: int = 1048576
@export var fragment_timeout_ms: int = 1000
@export var stale_timeout_ms: int = 1000
@export var max_sender_age_ms: int = 500
@export var prioritize_latest_full_state: bool = false
var full_states_coalesced: int = 0
var protocol: RefCounted = Protocol.new()
var socket: PacketPeerUDP = PacketPeerUDP.new()
var listening: bool = false
var bind_error: int = OK
var tick_cost_us: Array[int] = []

func _ready() -> void:
	protocol.max_message = clampi(max_message_bytes,1200,262144)
	protocol.max_pending = clampi(max_pending_messages,1,32)
	protocol.memory_limit = clampi(reassembly_memory_bytes,1200,4194304)
	protocol.fragment_ttl_ms = clampi(fragment_timeout_ms,50,10000)
	protocol.stale_ms = clampi(stale_timeout_ms,100,30000)
	protocol.max_sender_age_ms = clampi(max_sender_age_ms,0,10000)
	if auto_start: start()

func start() -> bool:
	if listening: return true
	bind_error = socket.bind(port,bind_ip,2097152)
	listening = bind_error==OK
	return listening

func stop() -> void:
	socket.close()
	listening = false

func _exit_tree() -> void: stop()

func _physics_process(_delta: float) -> void:
	var begin: int = Time.get_ticks_usec()
	protocol.tick(Time.get_ticks_msec())
	if not listening: return
	var packets: int = 0
	var complete: int = 0
	var staged: Array = []
	while socket.get_available_packet_count()>0 and packets<max_packets_per_tick and complete<max_completed_per_tick:
		var bytes: PackedByteArray = socket.get_packet()
		packets += 1
		if socket.get_packet_ip()!="127.0.0.1": continue
		var rx_usec: int = Time.get_ticks_usec()
		var rx_unix_ms: float = Time.get_unix_time_from_system()*1000
		var result: Dictionary = protocol.feed(bytes,Time.get_ticks_msec(),prioritize_latest_full_state)
		if result.get("wire_complete",false):
			complete += 1
			var duplicate: bool = false
			for old: Dictionary in staged:
				if old.message.session_id==result.candidate.session_id and old.message.session_started_ms==result.candidate.session_started_ms and old.message.sequence==result.candidate.sequence:duplicate = true
			if duplicate:protocol.reject("duplicate_or_old_sequence")
			else:staged.append({"message":result.candidate,"rx":rx_usec,"unix":rx_unix_ms})
		if result.get("complete",false):
			complete += 1
			result.snapshot["_rx_usec"] = rx_usec
			result.snapshot["_rx_unix_ms"] = rx_unix_ms
			result.snapshot["_validated_usec"] = Time.get_ticks_usec()
			snapshot_accepted.emit(result.snapshot)
		if Time.get_ticks_usec()-begin>=poll_budget_us: break
	# At most max_completed_per_tick candidates, newest first. A malformed newest
	# candidate cannot suppress the previous valid complete state. Epoch/session
	# checks remain in the exact same acceptance function; no validation is skipped
	# for a snapshot that is actually published.
	staged.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.message.session_started_ms!=b.message.session_started_ms:return a.message.session_started_ms>b.message.session_started_ms
		return a.message.sequence>b.message.sequence)
	for index: int in range(staged.size()):
		var candidate: Dictionary = staged[index]
		var result: Dictionary = protocol.accept_snapshot(candidate.message,Time.get_ticks_msec())
		if not result.get("complete",false):continue
		result.snapshot["_rx_usec"] = candidate.rx;result.snapshot["_rx_unix_ms"] = candidate.unix
		result.snapshot["_validated_usec"] = Time.get_ticks_usec()
		snapshot_accepted.emit(result.snapshot)
		full_states_coalesced += staged.size()-index-1
		break
	tick_cost_us.append(Time.get_ticks_usec()-begin)
	if tick_cost_us.size()>2048: tick_cost_us.pop_front()

func get_status() -> Dictionary:
	var result: Dictionary = protocol.status(Time.get_ticks_msec())
	result.merge({"listening":listening,"bind_ip":bind_ip,"port":port,"bind_error":bind_error,"full_states_coalesced":full_states_coalesced,"tick_cost_us":tick_cost_us.duplicate()})
	return result
