extends Node
var game: Node
var receiver: Node
var manager: Node
var sessions: int = 0
var active: bool = false
var first_live_usec: int = 0
var gap_usec: int = 0
var started_usec: int
var previous_sequence: int = -1
var restart_sequence_ok: bool = false
var lost: Dictionary = {"left":false,"right":false}
var recovered: Dictionary = {"left":false,"right":false}
var poses: Array[Transform2D] = []
var maximum_steps: Vector2 = Vector2.ZERO
var maximum_angles: Vector2 = Vector2.ZERO
var frame_times: PackedFloat64Array = []
var last_render_usec: int = 0
var render_started_usec: int = 0
var physics_frames: int = 0
var sampling_physics_frames: int = 0
var guards: Array[int] = []
var invalid_initial: int = 0
var peak_rx: float = 0
var rows: Array[Dictionary] = []
var completed: bool = false
var drawn_at_start: int

func _ready() -> void:
	game=get_tree().current_scene
	receiver=game.get_node("ExternalPlatformReceiver")
	manager=game.get_node("PlatformManager")
	started_usec=Time.get_ticks_usec()
	drawn_at_start=Engine.get_frames_drawn()
	process_physics_priority=40
	poses=[manager.get_platform("left").transform,manager.get_platform("right").transform]
	guards=[game.players[0].get_node("UnstuckGuard").recoveries,game.players[1].get_node("UnstuckGuard").recoveries]
	invalid_initial=receiver.invalid_packets

func _physics_process(_delta: float) -> void:
	physics_frames+=1
	var now: int=Time.get_ticks_usec()
	var info: Dictionary=receiver.diagnostics()
	peak_rx=maxf(peak_rx,info.packets_per_second)
	for i: int in range(2):
		var id: String="left" if i==0 else "right"
		var platform: Node2D=manager.get_platform(id)
		var step: float=platform.position.distance_to(poses[i].origin)+absf(angle_difference(poses[i].get_rotation(),platform.rotation))*platform.surface_radius
		maximum_steps[i]=maxf(maximum_steps[i],step)
		maximum_angles[i]=maxf(maximum_angles[i],absf(platform.rotation))
		poses[i]=platform.transform
		if active and not platform.detected and info.detected==1:
			lost[id]=true
		if lost[id] and platform.detected:
			recovered[id]=true
	if info.detected==2 and not active:
		sessions+=1
		active=true
		gap_usec=0
		if first_live_usec==0:
			first_live_usec=now
		if sessions==2:
			restart_sequence_ok=receiver.last_sequence>previous_sequence
	if active and info.detected==0:
		active=false
		previous_sequence=receiver.last_sequence
		gap_usec=now
	if sessions>=2 and not active and gap_usec>0 and now-gap_usec>1200000:
		finish()
	if now-started_usec>90000000:
		check("two_stream_starts_before_timeout",false,info)
		finish()

func _process(_delta: float) -> void:
	var now: int=Time.get_ticks_usec()
	if first_live_usec==0 or now-first_live_usec<1000000:
		last_render_usec=now
		return
	if render_started_usec==0:
		render_started_usec=now
		sampling_physics_frames=physics_frames
	if frame_times.size()<10000:
		frame_times.append((now-last_render_usec)/1000.0)
	last_render_usec=now

func check(case_name: String, passed: bool, detail: Variant="") -> void:
	rows.append({"test":case_name,"passed":passed,"detail":str(detail)})

func finish() -> void:
	if completed:
		return
	completed=true
	set_physics_process(false)
	set_process(false)
	var now: int=Time.get_ticks_usec()
	check("detector_closed_and_restarted",sessions==2 and restart_sequence_ok,sessions)
	check("green_loss_and_recovery",lost.left and recovered.left)
	check("blue_loss_and_recovery",lost.right and recovered.right)
	check("both_rotations_received",maximum_angles.x>.1 and maximum_angles.y>.1,maximum_angles)
	check("no_unbounded_pose_step_on_recovery",maximum_steps.x<4.02 and maximum_steps.y<4.02,maximum_steps)
	check("no_invalid_or_stale_source_packets",receiver.invalid_packets==invalid_initial and receiver.expired_packets==0,receiver.diagnostics())
	var recovery_counts: Array[int]=[]
	var safe: bool=true
	for i: int in range(2):
		var guard: Node=game.players[i].get_node("UnstuckGuard")
		recovery_counts.append(guard.recoveries-guards[i])
		safe=safe and guard.recoveries-guards[i]<=1 and not guard._occupied(game.players[i].position) and game.players[i].combat.damage_model.stocks==3
	check("crossing_platform_crush_has_bounded_recovery_and_no_permanent_embedding",safe,recovery_counts)
	frame_times.sort()
	var duration: float=(now-render_started_usec)/1000000.0
	var total_duration: float=(now-started_usec)/1000000.0
	var performance: Dictionary={"duration_seconds":duration,"render_samples":frame_times.size(),"measured_game_loop_fps":frame_times.size()/duration if duration>0 else 0.0,"measured_physics_hz":(physics_frames-sampling_physics_frames)/duration if duration>0 else 0.0,"configured_physics_hz":Engine.physics_ticks_per_second,"peak_receive_hz":peak_rx,"drawn_frames":Engine.get_frames_drawn()-drawn_at_start,"draw_duration_seconds":total_duration,"measured_draw_fps":(Engine.get_frames_drawn()-drawn_at_start)/total_duration}
	if not frame_times.is_empty():
		performance["frame_ms_p95"]=frame_times[int(frame_times.size()*.95)]
		performance["frame_ms_max"]=frame_times[-1]
	var failures: Array=rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var report: Dictionary={"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"results":rows,"performance":performance}
	var file: FileAccess=FileAccess.open("res://validation/stability_stream_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("stability_stream_results",report)
