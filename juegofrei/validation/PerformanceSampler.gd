extends Node
## Wall-clock sampling: rendering FPS is measured, not inferred from max_fps.
@export var duration_seconds: float = 45.0
var elapsed: float = 0.0
var frame_count: int = 0
var sample_count: int = 0
var last_usec: int = 0
var start_usec: int = 0
var frame_times: PackedFloat64Array = PackedFloat64Array()
var process_sum: float = 0.0
var physics_sum: float = 0.0
var nodes_start: int = 0
var nodes_max: int = 0
var memory_start: int = 0
var memory_max: int = 0
var draw_calls_max: int = 0
var orphans_start: int = 0
var finished: bool = false
@onready var game: Node = get_tree().current_scene

func _ready() -> void:
	process_physics_priority = -30
	frame_times.resize(10000)
	game.restart_match()
	last_usec = Time.get_ticks_usec()

func _physics_process(delta: float) -> void:
	elapsed += delta
	frame_count += 1
	if game.game_over:
		game.restart_match()
	var manager: Node = game.get_node("PlatformManager")
	var index: int = 0
	for platform: Node in manager.platforms.values():
		var home: Vector2 = platform.home_transform.origin
		manager.update_platform_position(platform.platform_id,home+Vector2(sin(elapsed*1.3+index)*80,cos(elapsed+index)*25))
		manager.update_platform_rotation(platform.platform_id,sin(elapsed*0.7+index)*0.35)
		index += 1
	var tick: int = frame_count%120
	for id: int in range(1,3):
		var prefix: String = "p%d_"%id
		if tick == 0:
			Input.action_press(prefix+("right" if id==1 else "left"))
		if tick == 40:
			Input.action_release(prefix+("right" if id==1 else "left"))
		if tick == 10:
			Input.action_press(prefix+"jump")
		if tick == 15:
			Input.action_release(prefix+"jump")
		if tick == 30 or tick == 70:
			Input.action_press(prefix+("light" if tick==30 else "heavy"))
		if tick == 31 or tick == 71:
			Input.action_release(prefix+("light" if tick==31 else "heavy"))
		if tick == 100:
			Input.action_press(prefix+"dodge")
		if tick == 101:
			Input.action_release(prefix+"dodge")
	if frame_count%5==0:
		game.effects.burst(Vector2(500+sin(elapsed)*180,350),Color("#7be8ce"))

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var milliseconds: float = (now-last_usec)/1000.0
	last_usec = now
	if elapsed < 2.0:
		return
	if start_usec == 0:
		start_usec = now
		nodes_start = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		orphans_start = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		memory_start = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		return
	frame_times[sample_count] = milliseconds
	sample_count += 1
	process_sum += Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
	physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
	nodes_max = maxi(nodes_max,int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	memory_max = maxi(memory_max,int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	draw_calls_max = maxi(draw_calls_max,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if now-start_usec >= duration_seconds*1000000.0 or sample_count>=9999:
		_finish(now)

func _finish(now: int) -> void:
	set_process(false)
	set_physics_process(false)
	finished = true
	frame_times.resize(sample_count)
	frame_times.sort()
	var over25: int = 0
	var over33: int = 0
	var over50: int = 0
	for value: float in frame_times:
		if value>25:
			over25 += 1
		if value>33.34:
			over33 += 1
		if value>50:
			over50 += 1
	var report: Dictionary = {"duration_seconds":(now-start_usec)/1000000.0,"frames":sample_count,"measured_average_fps":sample_count*1000000.0/(now-start_usec),"frame_ms_p50":frame_times[int(sample_count*0.5)],"frame_ms_p95":frame_times[int(sample_count*0.95)],"frame_ms_p99":frame_times[int(sample_count*0.99)],"frame_ms_max":frame_times[-1],"frames_over_25_ms":over25,"frames_over_33_ms":over33,"frames_over_50_ms":over50,"process_mean_ms":process_sum/sample_count,"physics_mean_ms":physics_sum/sample_count,"nodes_start":nodes_start,"nodes_max":nodes_max,"nodes_end":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans_start":orphans_start,"orphans_end":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"static_memory_start_bytes":memory_start,"static_memory_peak_bytes":memory_max,"static_memory_end_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"draw_calls_max":draw_calls_max,"stress":"two fighters, three translating/rotating platforms, attacks, jumps, dodges, 12 impact bursts per second","engine":Engine.get_version_info()["string"]}
	var file: FileAccess = FileAccess.open("res://validation/performance_qa.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("performance_qa",report)
	for platform: Node in game.get_node("PlatformManager").platforms.values():
		game.get_node("PlatformManager").update_platform_transform(platform.platform_id,platform.home_transform)
	game.restart_match()