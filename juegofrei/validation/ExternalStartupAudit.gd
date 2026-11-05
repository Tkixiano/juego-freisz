extends SceneTree
var checks: Array[Dictionary] = []

func check(name: String, passed: bool) -> void:
	checks.append({"test":name,"passed":passed})

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var blocker: PacketPeerUDP=PacketPeerUDP.new()
	check("fixture_reserves_port",blocker.bind(5006,"127.0.0.1")==OK)
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	game.get_node("PlatformManager").control_mode=1
	game.get_node("ExternalPlatformReceiver").port=5006
	root.add_child(game)
	current_scene=game
	await process_frame
	await process_frame
	var receiver: Node=game.get_node("ExternalPlatformReceiver")
	var manager: Node=game.get_node("PlatformManager")
	check("initial_external_mode_bind_failure_reported",not receiver.peer.is_bound() and receiver.diagnostics().udp.begins_with("ERROR:"))
	check("bind_failure_keeps_colliders",manager.platforms.size()==3 and not manager.get_platform("left").detected and manager.get_platform("left").collision_layer==2)
	check("bind_error_visible_in_panel",game.get_node("UI/PlatformInputPanel/Status").text.contains("ERROR:"))
	manager.set_control_mode(0)
	blocker.close()
	manager.set_control_mode(1)
	check("mode_toggle_retries_bind_successfully",receiver.peer.is_bound() and receiver.bind_error.is_empty())
	manager.set_control_mode(0)
	check("mouse_restores_detection_and_closes_socket",not receiver.peer.is_bound() and manager.get_platform("left").detected)
	game.queue_free()
	await process_frame
	check("exit_releases_port",blocker.bind(5006,"127.0.0.1")==OK)
	blocker.close()
	var failures: Array=checks.filter(func(row: Dictionary) -> bool: return not row.passed)
	var report: Dictionary={"total":checks.size(),"passed":checks.size()-failures.size(),"failed":failures.size(),"results":checks}
	var file: FileAccess=FileAccess.open("res://validation/udp_startup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("UDP_STARTUP ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
