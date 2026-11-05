extends Node
## Loopback UDP input; poses are submitted only here, on physics ticks.
const Manager = preload("res://scripts/PlatformManager.gd")
@export var manager_path: NodePath = ^"../PlatformManager"
@export var bind_address: String = "127.0.0.1"
@export_range(1,65535) var port: int = 5005
@export var module_ids: Dictionary[int,StringName] = {1:&"left",2:&"right",3:&"top"}
@export var arena_rect: Rect2 = Rect2(150,180,980,340)
@export_range(0.1,5.0) var module_timeout: float = 0.5
@export_range(0.1,10.0) var communication_timeout: float = 1.0
@export_range(1,256) var max_packets_per_tick: int = 128
@export_range(128,8192) var max_packet_bytes: int = 4096
@export var max_packet_age: float = 0.35
@export var max_source_age: float = 0.25
@export var position_deadband: float = 0.35
@export var angle_deadband_degrees: float = 0.15
var peer: PacketPeerUDP = PacketPeerUDP.new()
var last_sequence: int = -1
var received_packets: int = 0
var invalid_packets: int = 0
var stale_packets: int = 0
var applied_packets: int = 0
var overloaded_ticks: int = 0
var packets_per_second: float = 0.0
var last_valid_usec: int = -1
var bind_error: String = ""
var module_seen: Dictionary[StringName,int] = {}
var module_visible: Dictionary[StringName,bool] = {}
var rate_start_usec: int = 0
var listening_since_usec: int = 0
var rate_packets: int = 0
var was_paused: bool = false
var expired_packets: int = 0
var last_raw_usec: int = -1
var last_packet_age_ms: float = -1
var last_source_age_ms: float = -1
var updates_per_second: float = 0
var rate_updates: int = 0
var suppressed_targets: int = 0
var pending_packet: Dictionary = {}
var pending_received_usec: int = 0
var pending_in_pause: bool = false
## Bounded, optional provenance audit; counters remain available without logs.
@export var trace_updates: bool = false
var module_updates: Dictionary = {}
var module_last_update: Dictionary = {}
var update_trace: Array[Dictionary] = []
var coordinate_space: String = "CAMERA"
var outside_arena: int = 0
@onready var manager: Manager = get_node(manager_path) as Manager

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -30
	manager.control_mode_changed.connect(_on_mode_changed)
	_on_mode_changed(manager.control_mode)

func _exit_tree() -> void:
	peer.close()

func _on_mode_changed(mode: int) -> void:
	peer.close()
	module_seen.clear()
	module_visible.clear()
	module_updates.clear()
	module_last_update.clear()
	update_trace.clear()
	coordinate_space = "CAMERA"
	outside_arena = 0
	last_sequence = -1
	pending_packet.clear()
	expired_packets = 0
	last_raw_usec = -1
	last_packet_age_ms = -1
	last_source_age_ms = -1
	rate_updates = 0
	updates_per_second = 0
	suppressed_targets = 0
	last_valid_usec = -1
	received_packets = 0
	invalid_packets = 0
	stale_packets = 0
	applied_packets = 0
	overloaded_ticks = 0
	rate_packets = 0
	packets_per_second = 0
	rate_start_usec = Time.get_ticks_usec()
	listening_since_usec = rate_start_usec
	bind_error = ""
	was_paused = get_tree().paused
	if mode == Manager.ControlMode.EXTERNAL:
		var error: Error = peer.bind(port,bind_address,65536)
		if error != OK:
			bind_error = error_string(error)

func _physics_process(_delta: float) -> void:
	if manager.control_mode != Manager.ControlMode.EXTERNAL or not peer.is_bound():
		return
	var now: int = Time.get_ticks_usec()
	var paused: bool = get_tree().paused
	if paused and not was_paused:
		_lose_all()
	was_paused = paused
	var latest: Dictionary = pending_packet
	var newest: int = int(latest.get("sequence",last_sequence))
	var received_usec: int = pending_received_usec
	var received_in_pause: bool = pending_in_pause
	var budget: int = mini(peer.get_available_packet_count(),max_packets_per_tick)
	for i: int in range(budget):
		var bytes: PackedByteArray = peer.get_packet()
		received_packets += 1
		last_raw_usec = now
		rate_packets += 1
		if peer.get_packet_error() != OK or peer.get_packet_ip() != "127.0.0.1":
			invalid_packets += 1
			continue
		var packet: Dictionary = validate_packet(bytes)
		if packet.is_empty():
			invalid_packets += 1
			continue
		if not packet_is_fresh(packet):
			expired_packets += 1
			continue
		var sequence: int = int(packet["sequence"])
		if sequence <= last_sequence:
			stale_packets += 1
			continue
		if sequence > newest:
			newest = sequence
			latest = packet
			received_usec = now
			received_in_pause = paused
	# Preserve the highest sequence across bounded drains, even if UDP reordered
	# its datagrams. Never replay an aged candidate after draining a long queue.
	var queue_drained: bool = peer.get_available_packet_count()==0
	if not queue_drained:
		overloaded_ticks += 1
		pending_packet = latest
		pending_received_usec = received_usec
		pending_in_pause = received_in_pause
	else:
		pending_packet = {}
	if not latest.is_empty() and queue_drained:
		last_sequence = newest
		if packet_is_fresh(latest) and (now-received_usec)/1000000.0 <= max_packet_age:
			last_valid_usec = received_usec
			last_packet_age_ms = maxf(0,Time.get_unix_time_from_system()*1000-float(latest["sent_unix_ms"])) if latest.has("sent_unix_ms") else -1.0
			last_source_age_ms = float(latest.get("source_age_ms",-1))
			if not paused and not received_in_pause:
				_apply_packet(latest,now)
				applied_packets += 1
				rate_updates += 1
		else:
			expired_packets += 1
	if not paused:
		_expire_modules(now)
	if now-rate_start_usec >= 1000000:
		packets_per_second = rate_packets*1000000.0/(now-rate_start_usec)
		updates_per_second = rate_updates*1000000.0/(now-rate_start_usec)
		rate_updates = 0
		rate_packets = 0
		rate_start_usec = now

func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

func packet_is_fresh(packet: Dictionary) -> bool:
	if packet.has("sent_unix_ms"):
		var age_ms: float = Time.get_unix_time_from_system()*1000-float(packet["sent_unix_ms"])
		if age_ms > max_packet_age*1000 or age_ms < -1000:
			return false
	return not packet.has("source_age_ms") or float(packet["source_age_ms"]) <= max_source_age*1000

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum and floorf(float(value)) == float(value)

func validate_packet(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > max_packet_bytes or not _valid_utf8(bytes):
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var packet: Dictionary = parser.data
	# Optional diagnostics remain compatible with legacy v1 emitters. Module
	# fields are unchanged. Unix timestamps are comparable only on this host.
	for field: String in ["sent_unix_ms","source_age_ms"]:
		if packet.has(field) and (not _number(packet[field]) or float(packet[field]) < 0):
			return {}
	if not _integer(packet.get("version"),1,2) or not _integer(packet.get("sequence"),0,9007199254740991):
		return {}
	if int(packet["version"]) == 1:
		if packet.get("coordinate_space","CAMERA") != "CAMERA" or packet.has("projection_size") or packet.has("orientation_space"):
			return {}
	else:
		if packet.get("coordinate_space") != "PROJECTOR" or packet.get("orientation_space") != "PROJECTOR_PIXELS":
			return {}
		var size: Variant = packet.get("projection_size")
		if typeof(size) != TYPE_ARRAY or size.size()!=2 or not _integer(size[0],1280,1280) or not _integer(size[1],720,720):
			return {}
	if typeof(packet.get("modules")) != TYPE_ARRAY:
		return {}
	var modules: Array = packet["modules"]
	if modules.size() > module_ids.size():
		return {}
	var found: Dictionary[int,bool] = {}
	for item: Variant in modules:
		if typeof(item) != TYPE_DICTIONARY:
			return {}
		var module: Dictionary = item
		if module.size() != 5 or not _integer(module.get("id"),1,2147483647):
			return {}
		var id: int = int(module["id"])
		if not module_ids.has(id) or found.has(id) or manager.get_platform(module_ids[id]) == null:
			return {}
		found[id] = true
		for coordinate: String in ["x","y"]:
			if not _number(module.get(coordinate)) or float(module[coordinate]) < 0 or float(module[coordinate]) > 1:
				return {}
		if not _number(module.get("angle")) or absf(float(module["angle"])) > 180 or typeof(module.get("visible")) != TYPE_BOOL:
			return {}
	return packet

func _valid_utf8(bytes: PackedByteArray) -> bool:
	# Validate before decoding so malformed datagrams cannot flood Godot's log.
	var i: int = 0
	while i < bytes.size():
		var first: int = bytes[i]
		var length: int = 1
		if first <= 0x7f:
			i += 1
			continue
		elif first >= 0xc2 and first <= 0xdf:
			length = 2
		elif first >= 0xe0 and first <= 0xef:
			length = 3
		elif first >= 0xf0 and first <= 0xf4:
			length = 4
		else:
			return false
		if i+length > bytes.size():
			return false
		for j: int in range(1,length):
			if bytes[i+j] < 0x80 or bytes[i+j] > 0xbf:
				return false
		var second: int = bytes[i+1]
		if (first == 0xe0 and second < 0xa0) or (first == 0xed and second >= 0xa0) or (first == 0xf0 and second < 0x90) or (first == 0xf4 and second > 0x8f):
			return false
		i += length
	return true

func _apply_packet(packet: Dictionary, now: int) -> void:
	var incoming_space: String = packet.get("coordinate_space","CAMERA")
	if incoming_space != coordinate_space:
		_lose_all()
		coordinate_space = incoming_space
	for item: Dictionary in packet["modules"]:
		var id: StringName = module_ids[int(item["id"])]
		var detected: bool = item["visible"]
		var point: Vector2 = arena_rect.position+Vector2(float(item["x"]),float(item["y"]))*arena_rect.size
		if coordinate_space == "PROJECTOR":
			# Already calibrated into the whole logical game canvas. Never apply
			# homography or CAMERA's arena normalization again on this path.
			point = Vector2(float(item["x"])*1279.0,float(item["y"])*719.0)
			if detected and (point.x<arena_rect.position.x or point.y<arena_rect.position.y or point.x>arena_rect.end.x or point.y>arena_rect.end.y):
				detected = false
				outside_arena += 1
		module_seen[id] = now
		module_visible[id] = detected
		manager.update_platform_detection(id,detected,Manager.ControlMode.EXTERNAL)
		if detected:
			var platform: Node2D = manager.get_platform(id)
			var angle: float = deg_to_rad(float(item["angle"]))
			if point.distance_to(platform.target_position) < position_deadband:
				point = platform.target_position
			if absf(angle_difference(platform.target_rotation,angle)) < deg_to_rad(angle_deadband_degrees):
				angle = platform.target_rotation
			if point == platform.target_position and angle == platform.target_rotation:
				suppressed_targets += 1
			else:
				if manager.update_platform_transform(id,Transform2D(angle,point),Manager.ControlMode.EXTERNAL):
					module_updates[id] = int(module_updates.get(id,0))+1
					var record: Dictionary = {"sequence":int(packet["sequence"]),"wire_id":int(item["id"]),"platform":String(id),"target_x":point.x,"target_y":point.y,"angle_degrees":rad_to_deg(angle),"received_usec":now,"coordinate_space":coordinate_space}
					module_last_update[id] = record
					if trace_updates:
						update_trace.append(record)
						if update_trace.size()>120:
							update_trace.pop_front()

func _expire_modules(now: int) -> void:
	for id: StringName in manager.platforms:
		if module_seen.has(id) and (now-module_seen[id])/1000000.0 <= minf(module_timeout,communication_timeout):
			continue
		manager.update_platform_detection(id,false,Manager.ControlMode.EXTERNAL)

func _lose_all() -> void:
	module_seen.clear()
	module_visible.clear()
	for id: StringName in manager.platforms:
		manager.update_platform_detection(id,false,Manager.ControlMode.EXTERNAL)

func diagnostics() -> Dictionary:
	var now: int = Time.get_ticks_usec()
	var detected: int = 0
	for id: StringName in module_seen:
		if module_visible.get(id,false) and (now-module_seen[id])/1000000.0 <= module_timeout and manager.get_platform(id).detected:
			detected += 1
	var age: float = -1.0 if last_valid_usec < 0 else (now-last_valid_usec)/1000000.0
	var state: String = "DESACTIVADO"
	if manager.control_mode == Manager.ControlMode.EXTERNAL:
		var waiting_too_long: bool = age < 0 and (now-listening_since_usec)/1000000.0 > communication_timeout
		state = "ERROR: "+bind_error if not bind_error.is_empty() else ("SIN COMUNICACIÓN" if age > communication_timeout or waiting_too_long else ("ESPERANDO" if age < 0 else "RECIBIENDO"))
	var lost: PackedStringArray = []
	for id: StringName in manager.platforms:
		if not manager.get_platform(id).detected:
			lost.append(String(id))
	var tracking: String = "MOUSE ACTIVO"
	var modules: Dictionary = {}
	for id: StringName in manager.platforms:
		var platform: Node2D = manager.get_platform(id)
		modules[String(id)] = {"detected":platform.detected,"age_seconds":(now-module_seen[id])/1000000.0 if module_seen.has(id) else -1.0,"target_error_px":platform.position.distance_to(platform.target_position)}
		modules[String(id)]["transform_updates"] = int(module_updates.get(id,0))
		modules[String(id)]["last_update"] = module_last_update.get(id,{})
	if manager.control_mode == Manager.ControlMode.EXTERNAL:
		tracking = "PAUSADO" if get_tree().paused else ("SEGUIMIENTO PERDIDO" if detected==0 else ("PARCIAL" if detected<module_ids.size() else "ACTIVO"))
	return {"coordinate_space":coordinate_space,"outside_arena":outside_arena,"udp":state,"address":bind_address,"port":port,"mode":"MOUSE" if manager.control_mode==Manager.ControlMode.MOUSE else "EXTERNAL","packets_per_second":packets_per_second,"updates_per_second":updates_per_second,"last_sequence":last_sequence,"detected":detected,"known":module_ids.size(),"age_seconds":age,"tracking":tracking,"lost":lost,"received":received_packets,"invalid":invalid_packets,"stale":stale_packets,"applied":applied_packets,"overloaded_ticks":overloaded_ticks,"expired":expired_packets,"packet_age_ms":last_packet_age_ms,"source_age_ms":last_source_age_ms,"modules":modules,"suppressed_targets":suppressed_targets}
