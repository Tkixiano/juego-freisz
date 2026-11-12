extends Node
## An exclusive adapter port for the existing replay, not a second replayer.
signal batch_result(sequence: int,status: String,reason: String)
@onready var gateway: Node = $"../SceneSource"
@onready var manager: Node = $"../DynamicGeometry"
@onready var sources: Node = $"../Sources"
var pending_frame: Dictionary:
	get:return gateway.pending_frame if sources.mode=="OFFLINE" else {}
var reset_requested: bool:
	get:return gateway.reset_requested if sources.mode=="OFFLINE" else false
func _ready() -> void:
	gateway.batch_result.connect(func(seq: int,status: String,reason: String) -> void:
		if sources.mode=="OFFLINE":batch_result.emit(seq,status,reason))
func accepts_material_replay() -> bool:return true
func migrate_legacy_frame(frame: Dictionary) -> Dictionary:return gateway.migrate_legacy_frame(frame)
func request_reset() -> void:
	if sources.mode=="OFFLINE":gateway.request_reset()
func submit(frame: Dictionary) -> Dictionary:
	if sources.mode!="OFFLINE":return {"status":"REJECTED","reason":"inactive_source"}
	var safe: Dictionary = frame.duplicate()
	for field: String in ["_observed_count","_observed_elapsed","_apply_deadline_usec","allow_identity_recovery"]:safe.erase(field)
	return gateway.submit(safe)
