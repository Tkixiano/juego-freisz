extends Node
## UDP ingress is bounded to one latest validated state + one physical transaction.
signal mode_changed(mode: String)
@export_enum("OFFLINE","UDP") var startup_mode: String = "OFFLINE"
@export var maximum_state_age_ms: float = 500
@export var minimum_udp_submit_interval: float = 1.0/30.0
@onready var receiver: Node = $"../UdpTransport"
@onready var gateway: Node = $"../SceneSource"
@onready var replay: Node = $"../Replay"
var mode: String = "OFFLINE"
var generation: int = 0
var bound_session: String = ""
var latest: Dictionary = {}
var events: Array = []
var pending_metadata: Dictionary = {}
var last_applied_rx_usec: int = -1
var last_applied_sequence: int = 0
var next_submit_usec: int = 0
var observed_state: String = ""
var observed_session: String = ""
var observed_count: int = 0
var observed_since_usec: int = 0
var metrics: Dictionary = {"received":0,"coalesced":0,"expired":0,"superseded":0,"source_switches":0,"session_switches":0,"submitted":0,"applied":0,"rejected":0,"deferred":0,"obsolete_events":0,"queue_peak":0,"receiver_age_ms":[],"validation_ms":[],"application_ms":[],"applied_sender_age_ms":[],"tick_us":[]}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS;process_physics_priority = -85
	receiver.process_mode = Node.PROCESS_MODE_ALWAYS;receiver.process_physics_priority = -100
	receiver.prioritize_latest_full_state = true
	receiver.snapshot_accepted.connect(_received)
	gateway.batch_result.connect(_batch)
func initialize() -> void:
	if startup_mode=="UDP":select_mode("UDP")
func select_mode(value: String) -> bool:
	if value not in ["OFFLINE","UDP"]:return false
	if value==mode:return true
	replay.pause();replay.step_requested = false;replay.set_physics_process(value=="OFFLINE")
	receiver.stop();receiver.protocol.pending.clear();receiver.protocol.reserved_bytes = 0
	latest.clear();events.clear();pending_metadata.clear();bound_session = ""
	last_applied_rx_usec = -1;last_applied_sequence = 0
	observed_state = "";observed_session = "";observed_count = 0
	generation += 1;mode = value;metrics.source_switches += 1
	gateway.request_reset()
	if mode=="UDP" and not receiver.start():gateway.set_health("SCENE_ERROR")
	mode_changed.emit(mode)
	return mode!="UDP" or receiver.listening
func sample(key: String,value: float) -> void:
	metrics[key].append(value)
	if metrics[key].size()>2048:metrics[key].pop_front()
func _received(frame: Dictionary) -> void:
	if mode!="UDP":return
	if frame.get("protocol_version")!=2:metrics.rejected += 1;return
	metrics.received += 1
	if observed_state!=frame.scene_state or observed_session!=frame.session_id:
		observed_state = frame.scene_state;observed_session = frame.session_id;observed_count = 0;observed_since_usec = int(frame._rx_usec)
	observed_count += 1
	frame._observed_count = observed_count
	frame._observed_elapsed = (int(frame._rx_usec)-observed_since_usec)/1000000.0
	if not latest.is_empty():metrics.coalesced += 1
	if not latest.is_empty() and latest.session_id!=frame.session_id:events.clear()
	latest = frame
	events.append_array(frame.events.duplicate(true))
	if events.size()>64:metrics.obsolete_events += events.size()-64;events = events.slice(-64)
	metrics.queue_peak = maxi(metrics.queue_peak,1+(0 if gateway.pending_frame.is_empty() else 1))
	var age: float = float(frame._rx_unix_ms)-float(frame.get("sent_unix_ms",frame._rx_unix_ms))
	if age>=0:sample("receiver_age_ms",age)
	sample("validation_ms",(int(frame._validated_usec)-int(frame._rx_usec))/1000.0)
func _batch(seq: int,status: String,_reason: String) -> void:
	if mode!="UDP":return
	if status=="DEFERRED":metrics.deferred += 1
	if status=="REJECTED":metrics.rejected += 1
	if status=="CANCELLED":pending_metadata.clear()
	if status!="APPLIED" or not pending_metadata.has(seq):return
	var meta: Dictionary = pending_metadata[seq]
	last_applied_rx_usec = int(meta.rx);last_applied_sequence = seq;metrics.applied += 1
	sample("application_ms",(Time.get_ticks_usec()-int(meta.rx))/1000.0)
	var age: float = Time.get_unix_time_from_system()*1000-float(meta.sent)
	if age>=0:sample("applied_sender_age_ms",age)
	pending_metadata.clear()
func _physics_process(_delta: float) -> void:
	if mode!="UDP" or get_tree().paused:return
	var start: int = Time.get_ticks_usec()
	_update_udp()
	sample("tick_us",Time.get_ticks_usec()-start)
func _update_udp() -> void:
	var health: String = receiver.protocol.scene_state
	if not receiver.listening or health in ["SCENE_STALE","SCENE_ERROR"]:
		observed_state = "";observed_count = 0
		gateway.set_health("SCENE_ERROR" if not receiver.listening or health=="SCENE_ERROR" else "SCENE_STALE")
		if not latest.is_empty() and latest.scene_state=="SCENE_ERROR":latest.clear()
		if not latest.is_empty() and Time.get_ticks_usec()-int(latest._rx_usec)>maximum_state_age_ms*1000:latest.clear();metrics.expired += 1
		return
	if latest.is_empty() or gateway.reset_requested:return
	if bound_session!=latest.session_id:
		bound_session = latest.session_id;metrics.session_switches += 1
		last_applied_rx_usec = -1;last_applied_sequence = 0
		pending_metadata.clear();gateway.request_reset();return
	if Time.get_ticks_usec()<next_submit_usec:return
	var age: float = Time.get_unix_time_from_system()*1000-float(latest.sent_unix_ms)
	if age>maximum_state_age_ms:
		latest.clear();metrics.expired += 1;return
	# Every replacement has already passed transport geometry/epoch ledgers.
	# Cancelling an UNAPPLIED batch never removes the last physical state.
	if not gateway.pending_frame.is_empty():
		if int(latest.sequence)<=int(gateway.pending_frame.sequence):return
		events.append_array(gateway.pending_frame.get("events",[]).duplicate(true))
		gateway.backend.cancel_pending_source("newer_valid_full_state");metrics.superseded += 1
	var frame: Dictionary = latest;latest = {}
	frame.allow_identity_recovery = true
	var received_age: float = maxf(0,float(frame._rx_unix_ms)-float(frame.sent_unix_ms))
	frame._apply_deadline_usec = int(frame._rx_usec)+int(maxf(0,maximum_state_age_ms-received_age)*1000)
	frame.events = events.filter(func(e: Dictionary) -> bool:
		for id: String in e.children:
			if not frame.identity_epochs.has(id):return false
		return true)
	metrics.obsolete_events += events.size()-frame.events.size();events.clear()
	var unique_events: Dictionary = {}
	for event: Dictionary in frame.events:unique_events[JSON.stringify(event,"",true,true)] = event
	frame.events = unique_events.values()
	var meta: Dictionary = {"rx":frame._rx_usec,"sent":frame.sent_unix_ms}
	var result: Dictionary = gateway.submit(frame)
	if result.status in ["QUEUED","HELD"]:
		# The gateway may dispatch a held candidate later at a physics boundary.
		pending_metadata.clear();pending_metadata[int(frame.sequence)] = meta;metrics.submitted += 1
	else:metrics.rejected += 1
	next_submit_usec = Time.get_ticks_usec()+int(minimum_udp_submit_interval*1000000)
func get_status() -> Dictionary:
	return {"mode":mode,"generation":generation,"session":bound_session,"queue_depth":(0 if latest.is_empty() else 1)+(0 if gateway.pending_frame.is_empty() else 1),"last_applied_sequence":last_applied_sequence,"applied_state_age_ms":(Time.get_ticks_usec()-last_applied_rx_usec)/1000.0 if last_applied_rx_usec>=0 else -1,"metrics":metrics.duplicate(true)}
