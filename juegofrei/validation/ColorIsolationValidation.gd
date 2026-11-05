extends Node
## Observes the real synthetic OpenCV -> UDP fixture, with per-ID apply counters.
var game: Node
var receiver: Node
var manager: Node
var previous_stage: int = -1
var base_sequence: int = -1
var deadline: int
var rows: Array[Dictionary] = []
var stage_initial: Dictionary = {}
var stage_last: Dictionary = {}
var fixed_blue_count: int = -1
var blue_start_pose: Transform2D

func _ready() -> void:
	game = get_tree().current_scene
	game.restart_match()
	manager = game.get_node("PlatformManager")
	receiver = game.get_node("ExternalPlatformReceiver")
	manager.set_control_mode(0)
	manager.set_control_mode(1)
	receiver.trace_updates = true
	blue_start_pose = manager.get_platform("right").transform
	process_physics_priority = 30
	deadline = Time.get_ticks_msec()+60000
	game.set_meta("color_isolation_progress","waiting")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	rows.append({"test":label,"passed":passed,"detail":str(detail)})

func finish_stage(stage: int) -> void:
	var left: int = int(stage_last.left.transform_updates)
	var right: int = int(stage_last.right.transform_updates)
	if stage == 0:
		check("green_moves_left_with_no_blue_wire_application",left>10 and right==0,stage_last)
		check("blue_not_detected_and_never_moved",not stage_last.right.detected and manager.get_platform("right").transform.is_equal_approx(blue_start_pose))
	elif stage == 1:
		check("blue_moves_after_independent_detection",right>10,stage_last)
		check("missing_green_stops_receiving_new_targets",not stage_last.left.detected,stage_last)
	elif stage == 2:
		check("both_colors_independent_and_visible",stage_last.left.detected and stage_last.right.detected and left>int(stage_initial.left.transform_updates) and right>int(stage_initial.right.transform_updates),stage_last)
	elif stage == 3:
		check("green_motion_does_not_change_static_blue_target",fixed_blue_count>=0 and right==fixed_blue_count and left>int(stage_initial.left.transform_updates),stage_last)
	elif stage == 4:
		check("loss_marks_both_invisible",not stage_last.left.detected and not stage_last.right.detected,stage_last)
		var valid_mapping: bool = true
		for entry: Dictionary in receiver.update_trace:
			valid_mapping = valid_mapping and ((entry.wire_id==1 and entry.platform=="left") or (entry.wire_id==2 and entry.platform=="right"))
		check("bounded_provenance_trace_preserves_id_mapping",valid_mapping and not receiver.update_trace.is_empty())
		check("valid_wire_no_receiver_errors",receiver.invalid_packets==0 and receiver.expired_packets==0)
		finish()

func _physics_process(_delta: float) -> void:
	if Time.get_ticks_msec()>deadline:
		check("stream_timeout",false,receiver.diagnostics())
		finish()
		return
	if receiver.last_sequence < 0:
		return
	if base_sequence<0:
		base_sequence = receiver.last_sequence
	var stage: int = int((receiver.last_sequence-base_sequence)/1000.0)
	var frame: int = (receiver.last_sequence-base_sequence)%1000
	var info: Dictionary = receiver.diagnostics().modules
	if stage != previous_stage:
		if previous_stage>=0:
			finish_stage(previous_stage)
		stage_initial = info.duplicate(true)
		previous_stage = stage
		game.set_meta("color_isolation_progress",stage)
	stage_last = info.duplicate(true)
	if stage==3 and frame>25 and fixed_blue_count<0:
		fixed_blue_count = int(info.right.transform_updates)
	if stage==4 and frame>=55:
		finish_stage(4)

func finish() -> void:
	set_physics_process(false)
	var failures: Array = rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"modules":receiver.diagnostics().modules,"trace":receiver.update_trace}
	var file: FileAccess = FileAccess.open("res://validation/color_isolation_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	game.set_meta("color_isolation_results",result)
	game.set_meta("color_isolation_progress","complete")
