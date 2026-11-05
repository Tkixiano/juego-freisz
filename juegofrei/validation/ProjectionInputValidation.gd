extends RefCounted
var rows: Array[Dictionary] = []
var sender: PacketPeerUDP = PacketPeerUDP.new()

func frames(tree: SceneTree,count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(label: String,passed: bool) -> void:
	rows.append({"test":label,"passed":passed})

func packet(sequence: int,point: Vector2) -> Dictionary:
	return {"version":2,"coordinate_space":"PROJECTOR","projection_size":[1280,720],"orientation_space":"PROJECTOR_PIXELS","sequence":sequence,"modules":[{"id":1,"x":point.x/1279,"y":point.y/719,"angle":32.0,"visible":true}]}

func send(data: Dictionary) -> void:
	sender.put_packet(JSON.stringify(data).to_utf8_buffer())

func run(tree: SceneTree) -> void:
	var game: Node = tree.current_scene
	game.restart_match()
	var manager: Node = game.get_node("PlatformManager")
	var receiver: Node = game.get_node("ExternalPlatformReceiver")
	manager.set_control_mode(0)
	manager.set_control_mode(1)
	sender.set_dest_address("127.0.0.1",5005)
	await frames(tree,3)
	var left: Node2D = manager.get_platform("left")
	var initial: Vector2 = left.position
	send(packet(100,Vector2(610,330)))
	await frames(tree,3)
	check("v2_projects_into_full_game_canvas_without_second_mapping",left.target_position.is_equal_approx(Vector2(610,330)) and receiver.coordinate_space=="PROJECTOR")
	check("projector_axis_angle_preserved_after_python_mapping",absf(left.target_rotation-deg_to_rad(32))<.0001)
	check("projector_target_is_not_teleport",left.position.distance_to(initial)<15 and left.position.distance_to(left.target_position)>15)
	send(packet(99,Vector2(900,300)))
	await frames(tree,3)
	check("v2_old_sequence_rejected",left.target_position.is_equal_approx(Vector2(610,330)) and receiver.stale_packets>0)
	for kind: String in ["missing_space","bad_resolution","missing_orientation","v1_projection","unknown_id"]:
		var bad: Dictionary = packet(1000,Vector2(900,300))
		match kind:
			"missing_space": bad.erase("coordinate_space")
			"bad_resolution": bad.projection_size=[1920,1080]
			"missing_orientation": bad.erase("orientation_space")
			"v1_projection": bad.version=1
			"unknown_id": bad.modules[0].id=99
		check("reject_"+kind,receiver.validate_packet(JSON.stringify(bad).to_utf8_buffer()).is_empty())
	send(packet(101,Vector2(100,100)))
	await frames(tree,3)
	check("outside_arena_freezes_instead_of_clamping_incorrect_alignment",not left.detected and receiver.outside_arena==1 and left.target_position.is_equal_approx(left.position))
	var legacy: Dictionary = {"version":1,"sequence":102,"modules":[{"id":1,"x":(500.0-150)/980,"y":(400.0-180)/340,"angle":0.0,"visible":true}]}
	send(legacy)
	await frames(tree,3)
	check("legacy_camera_v1_still_uses_arena_normalization",receiver.coordinate_space=="CAMERA" and left.detected and left.target_position.is_equal_approx(Vector2(500,400)))
	manager.set_control_mode(0)
	check("mouse_control_retained_after_projection",manager.update_platform_position("left",Vector2(520,410)) and not manager.update_platform_position("left",Vector2(900,300),1))
	sender.close()
	var passed: int = 0
	for row: Dictionary in rows:
		if row.passed:
			passed+=1
	var report: Dictionary = {"total":rows.size(),"passed":passed,"rows":rows}
	var file: FileAccess = FileAccess.open("res://validation/projection_input_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	game.set_meta("projection_input_results",report)
