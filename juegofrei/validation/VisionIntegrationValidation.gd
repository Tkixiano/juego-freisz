extends Node
## Runtime observer for the independent Python image -> tracker -> UDP path.
var game: Node
var receiver: Node
var manager: Node
var started_usec: int
var baseline: Array[Vector2] = []
var fixed_geometry: Array = []
var live: Dictionary = {}
var live_seen: bool = false
var stopped_frames: int = 0
var stopped_pose: Array[Transform2D] = []
var rows: Array[Dictionary] = []
var maximum_movement: Vector2 = Vector2.ZERO
var combat_started: bool = false
var combat_verified: bool = false

func frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func test_live_combat() -> void:
	game.restart_match()
	var platform: Node2D=manager.get_platform("left")
	for player: Node in game.players:
		player.combat.respawn_left=0
		player.combat.invulnerability_left=0
		player.combat.accepted_hits=0
		player.position=platform.global_transform*Vector2(-28 if player.player_id==1 else 28,-36)
		player.velocity=Vector2.ZERO
		player.reset_physics_interpolation()
	game.players[0].combat.facing=1
	await frames(15)
	var packets_before: int=receiver.received_packets
	Input.action_press("p1_light")
	await frames(1)
	Input.action_release("p1_light")
	await frames(15)
	combat_verified=game.players[1].combat.damage_model.percent==6 and game.players[0].combat.accepted_hits==1 and receiver.received_packets>packets_before and receiver.diagnostics().detected==2

func geometry() -> Array:
	var result: Array=[]
	for platform: Node in manager.platforms.values():
		var shape: Shape2D=platform.get_node("CollisionShape2D").shape
		var outline: Variant=shape.size if shape is RectangleShape2D else shape.points.duplicate()
		# Rotation matrices can yield scale 1 +/- float epsilon. Geometry is exact;
		# unit scale is checked with Godot's numerical tolerance, not bit equality.
		result.append([platform.platform_id,platform.scale.is_equal_approx(Vector2.ONE),outline,platform.get_node("Visual").polygon.duplicate()])
	return result

func _ready() -> void:
	game=get_tree().current_scene
	game.set_meta("vision_udp_complete",false)
	manager=game.get_node("PlatformManager")
	receiver=game.get_node("ExternalPlatformReceiver")
	process_physics_priority=30
	game.restart_match()
	manager.set_control_mode(0)
	for platform: Node in manager.platforms.values():
		platform.freeze_motion()
	manager.set_control_mode(1)
	baseline=[manager.get_platform("left").position,manager.get_platform("right").position]
	fixed_geometry=geometry()
	started_usec=Time.get_ticks_usec()

func check(case_name: String, passed: bool, detail: Variant="") -> void:
	rows.append({"test":case_name,"passed":passed,"detail":str(detail)})

func _physics_process(_delta: float) -> void:
	var info: Dictionary=receiver.diagnostics()
	if info.detected==2 and info.received>=50:
		live_seen=true
		live=info.duplicate(true)
		maximum_movement.x=maxf(maximum_movement.x,manager.get_platform("left").position.distance_to(baseline[0]))
		maximum_movement.y=maxf(maximum_movement.y,manager.get_platform("right").position.distance_to(baseline[1]))
		live["left_movement"]=maximum_movement.x
		live["right_movement"]=maximum_movement.y
		if not combat_started:
			combat_started=true
			test_live_combat()
	if live_seen and info.detected==0:
		if stopped_frames==0:
			stopped_pose=[manager.get_platform("left").transform,manager.get_platform("right").transform]
		stopped_frames+=1
		if stopped_frames>=15:
			check("independent_python_image_pipeline_received",live.received>=50 and live.invalid==0,live)
			check("two_color_ids_are_detected",live.detected==2)
			check("both_platforms_moved_from_vision",live.left_movement>5 and live.right_movement>5,[live.left_movement,live.right_movement])
			check("loss_or_shutdown_freezes_both",manager.get_platform("left").transform.is_equal_approx(stopped_pose[0]) and manager.get_platform("right").transform.is_equal_approx(stopped_pose[1]))
			check("fixed_geometry_preserved",geometry()==fixed_geometry)
			check("players_and_floor_remain",game.players.size()==2 and game.players[0].combat.damage_model.stocks==3 and game.players[1].combat.damage_model.stocks==3)
			check("light_attack_hits_once_on_live_vision_platform",combat_verified)
			finish()
	if Time.get_ticks_usec()-started_usec>60000000:
		check("vision_stream_received_before_deadline",false,info)
		finish()

func finish() -> void:
	set_physics_process(false)
	var failures: Array=rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var report: Dictionary={"total":rows.size(),"passed":rows.size()-failures.size(),"failed":failures.size(),"results":rows,"live_sample":live}
	var file: FileAccess=FileAccess.open("res://validation/vision_udp_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("vision_udp_results",report)
	game.set_meta("vision_udp_complete",true)
