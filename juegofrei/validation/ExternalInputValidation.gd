extends RefCounted
var tree: SceneTree
var game: Node
var manager: Node
var receiver: Node
var sender: PacketPeerUDP = PacketPeerUDP.new()
var rows: Array[Dictionary] = []
var sequence: int = 100

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(name: String, passed: bool, detail: Variant = "") -> void:
	rows.append({"test":name,"passed":passed,"detail":str(detail)})

func module(id: int, point: Vector2, angle: float = 0, visible: bool = true) -> Dictionary:
	var normalized: Vector2=(point-receiver.arena_rect.position)/receiver.arena_rect.size
	return {"id":id,"x":normalized.x,"y":normalized.y,"angle":angle,"visible":visible}

func send(modules: Array, seq: int = -1) -> void:
	if seq < 0:
		sequence+=1
		seq=sequence
	sender.put_packet(JSON.stringify({"version":1,"sequence":seq,"modules":modules}).to_utf8_buffer())

func stream(modules: Array, ticks: int) -> void:
	for i: int in range(ticks):
		if i%2==0:
			send(modules)
		await frames(1)

func run(scene_tree: SceneTree, label: String = "external") -> void:
	tree=scene_tree
	game=tree.current_scene
	manager=game.get_node("PlatformManager")
	receiver=game.get_node("ExternalPlatformReceiver")
	game.restart_match()
	manager.set_control_mode(0)
	# Match restart intentionally preserves the operator layout. Establish the
	# authored fixture explicitly before testing a bounded move from home.
	for platform: Node in manager.platforms.values():
		manager.update_platform_transform(platform.platform_id,platform.home_transform)
	await frames(180)
	var helper: RefCounted=load("res://validation/QAAudit.gd").new()
	helper.tree=tree
	var geometry: Array=helper.geometry()
	check("default_mouse_socket_closed",manager.control_mode==0 and not receiver.peer.is_bound())
	check("external_source_rejected_in_mouse",not manager.update_platform_position("left",Vector2(500,400),1))
	var input: RefCounted=load("res://validation/FunctionalAudit.gd").new()
	input.tree=tree
	await input.tap(KEY_F2)
	check("f2_activates_external_and_binds_5005",manager.control_mode==1 and receiver.peer.is_bound() and receiver.peer.get_local_port()==5005)
	receiver.module_timeout=0.3
	receiver.communication_timeout=0.45
	sender.set_dest_address("127.0.0.1",5005)
	check("external_starts_frozen",not manager.get_platform("left").detected and not manager.get_platform("right").detected)
	var left: Node=manager.get_platform("left")
	send([module(1,Vector2(500,400),15)])
	await frames(3)
	check("real_udp_json_received",receiver.last_sequence==sequence and receiver.applied_packets==1,receiver.diagnostics())
	check("normalized_coordinates_and_degrees",left.target_position.is_equal_approx(Vector2(500,400)) and absf(left.target_rotation-deg_to_rad(15))<0.0001)
	check("target_not_teleport",left.position.distance_to(left.target_position)>30 and left.position.distance_to(left.home_transform.origin)<15,left.position)
	var applied: int=receiver.applied_packets
	send([module(1,Vector2(410,410))],105)
	send([module(1,Vector2(450,420))],107)
	send([module(1,Vector2(700,300))],106)
	sender.put_packet("{bad json".to_utf8_buffer())
	await frames(3)
	sequence=107
	check("only_newest_valid_packet_per_tick",receiver.last_sequence==107 and receiver.applied_packets==applied+1 and left.target_position.is_equal_approx(Vector2(450,420)))
	applied=receiver.applied_packets
	send([module(1,Vector2(900,300))],107)
	send([module(1,Vector2(900,300))],106)
	await frames(3)
	check("old_and_duplicate_sequences_rejected",receiver.last_sequence==107 and receiver.applied_packets==applied and receiver.stale_packets>=2)
	receiver.max_packets_per_tick=2
	applied=receiver.applied_packets
	send([module(1,Vector2(410,410))])
	send([module(1,Vector2(420,410))])
	send([module(1,Vector2(430,410))])
	await frames(4)
	check("bounded_flood_drains_before_applying_latest",receiver.applied_packets==applied+1 and receiver.last_sequence==sequence and receiver.overloaded_ticks>0 and left.target_position.is_equal_approx(Vector2(430,410)))
	applied=receiver.applied_packets
	send([module(1,Vector2(455,415))],sequence+3)
	send([module(1,Vector2(700,300))],sequence+1)
	send([module(1,Vector2(800,300))],sequence+2)
	sequence+=3
	await frames(4)
	check("highest_sequence_survives_reordered_bounded_drain",receiver.applied_packets==applied+1 and receiver.last_sequence==sequence and left.target_position.is_equal_approx(Vector2(455,415)))
	receiver.max_packets_per_tick=128
	var expired_before: int=receiver.expired_packets
	var delayed: Dictionary={"version":1,"sequence":sequence+1000,"sent_unix_ms":Time.get_unix_time_from_system()*1000-2000,"modules":[module(1,Vector2(900,300))]}
	sender.put_packet(JSON.stringify(delayed).to_utf8_buffer())
	delayed.sent_unix_ms=Time.get_unix_time_from_system()*1000
	delayed.source_age_ms=1000
	sender.put_packet(JSON.stringify(delayed).to_utf8_buffer())
	await frames(3)
	check("old_wallclock_and_old_source_rejected_without_poisoning_sequence",receiver.expired_packets>=expired_before+2 and receiver.last_sequence==sequence)
	var stable_target: Vector2=left.target_position
	var suppressed_before: int=receiver.suppressed_targets
	send([module(1,stable_target+Vector2(.1,0),rad_to_deg(left.target_rotation)+.05)])
	await frames(3)
	check("subpixel_jitter_suppressed_but_tracking_kept_alive",left.target_position.is_equal_approx(stable_target) and receiver.suppressed_targets>suppressed_before and left.detected)
	var good: Dictionary={"version":1,"sequence":999,"modules":[module(1,Vector2(500,400))]}
	var invalids: Array=[null,[],{}, {"version":1,"sequence":1,"modules":{}}, {"version":2,"sequence":999,"modules":[]}]
	for field: String in ["version","sequence"]:
		for value: Variant in [true,"1",-1,1.5,9007199254740992.0]:
			var bad: Dictionary=good.duplicate(true)
			bad[field]=value
			invalids.append(bad)
	for field: String in ["id","x","y","angle","visible"]:
		var bad: Dictionary=good.duplicate(true)
		bad.modules[0].erase(field)
		invalids.append(bad)
	for pair: Array in [["id",99],["id",1.5],["id",true],["x",-0.1],["x",1.1],["x","0.4"],["y",null],["angle",181],["angle",true],["visible",1]]:
		var bad: Dictionary=good.duplicate(true)
		bad.modules[0][pair[0]]=pair[1]
		invalids.append(bad)
	var duplicate: Dictionary=good.duplicate(true)
	duplicate.modules.append(duplicate.modules[0].duplicate())
	invalids.append(duplicate)
	var scaled: Dictionary=good.duplicate(true)
	scaled.modules[0]["scale"]=2
	invalids.append(scaled)
	var rejected: bool=true
	for bad: Variant in invalids:
		rejected=rejected and receiver.validate_packet(JSON.stringify(bad).to_utf8_buffer()).is_empty()
	check("reject_all_invalid_structures_types_ids_ranges",rejected,invalids.size())
	check("reject_malformed_utf8_and_oversize",receiver.validate_packet(PackedByteArray([0xc0,0xaf])).is_empty() and receiver.validate_packet(PackedByteArray([0xed,0xa0,0x80])).is_empty() and receiver.validate_packet(" ".repeat(5000).to_utf8_buffer()).is_empty())
	var invalid_before: int=receiver.invalid_packets
	for bad: Variant in invalids:
		sender.put_packet(JSON.stringify(bad).to_utf8_buffer())
	sender.put_packet(PackedByteArray([0xff]))
	send([module(1,Vector2(420,400))])
	await frames(3)
	check("invalid_packets_do_not_poison_sequence",receiver.last_sequence==sequence and receiver.invalid_packets>=invalid_before+invalids.size()+1)
	check("unknown_ids_never_create_platforms",manager.platforms.size()==3 and helper.geometry()==geometry)
	var mouse: Node=game.get_node("MousePlatformController")
	mouse.select_at(left.position)
	input.mouse(left.position,true)
	input.motion(Vector2(900,200),true)
	input.mouse(Vector2(900,200),false)
	Input.action_press("editor_rotate_right")
	await frames(4)
	Input.action_release("editor_rotate_right")
	check("external_blocks_mouse_and_rotation_keys",not mouse.dragging and left.target_position.is_equal_approx(Vector2(420,400)) and absf(left.target_rotation)<0.0001)
	check("manager_rejects_wrong_source",not manager.update_platform_position("left",Vector2(900,250)) and not manager.update_platform_rotation("left",1.0) and not manager.update_platform_detection("left",false))
	send([module(1,Vector2(600,400)),module(2,Vector2(850,400))])
	await frames(2)
	await stream([module(1,Vector2(600,400))],24)
	check("per_module_timeout_keeps_other_module_live",left.detected and not manager.get_platform("right").detected)
	var right: Node=manager.get_platform("right")
	check("lost_module_keeps_collider",right.collision_layer==2 and not right.get_node("CollisionShape2D").disabled)
	send([module(1,Vector2(600,400),0,false)])
	await frames(3)
	check("visible_false_stops_immediately",not left.detected and left.target_position.is_equal_approx(left.position))
	send([module(1,Vector2(900,400))])
	await frames(2)
	check("tracking_reacquires_without_teleport",left.detected and left.position.distance_to(left.target_position)>100)
	await frames(40)
	var frozen: Transform2D=left.transform
	await frames(12)
	check("communication_loss_stops_and_holds_pose",not left.detected and left.transform.is_equal_approx(frozen) and receiver.diagnostics().udp=="SIN COMUNICACIÓN")
	check("age_is_local_receipt_age",receiver.diagnostics().age_seconds>0.45 and receiver.diagnostics().tracking=="SEGUIMIENTO PERDIDO")
	var last: int=receiver.last_sequence
	send([module(1,Vector2(900,400))],last)
	await frames(3)
	check("timeout_does_not_accept_old_sequence",not left.detected and receiver.last_sequence==last)
	send([module(1,Vector2(500,400))])
	await frames(3)
	game.get_node("GameShell").show_pause()
	await frames(3)
	frozen=left.transform
	send([module(1,Vector2(1000,300))])
	await frames(5)
	check("pause_drains_udp_without_moving_platforms",tree.paused and left.transform.is_equal_approx(frozen) and not left.detected and receiver.last_sequence==sequence)
	game.get_node("GameShell").enter_game()
	await frames(4)
	check("resume_needs_fresh_pose",not left.detected and left.transform.is_equal_approx(frozen),[left.detected,frozen,left.transform,left.target_position])
	send([module(1,Vector2(385,435))])
	await frames(3)
	check("fresh_pose_after_pause_reacquires",left.detected)
	await stream([module(1,Vector2(385,435))],150)
	for p: Node in game.players:
		p.respawn()
		p.combat.respawn_left=0
		p.combat.invulnerability_left=0
		p.position=Vector2(350 if p.player_id==1 else 420,398)
	await stream([module(1,Vector2(385,435))],15)
	check("both_fighters_collide_with_external_platform",game.players[0].is_on_floor() and game.players[1].is_on_floor())
	var before: Vector2=game.players[0].position
	await stream([module(1,Vector2(465,415),10)],90)
	check("stream_measured_near_30_packets_per_second",receiver.packets_per_second>25 and receiver.packets_per_second<35,receiver.packets_per_second)
	check("udp_translation_rotation_carries_fighters",game.players[0].is_on_floor() and game.players[1].is_on_floor() and game.players[0].position.x>before.x+60 and left.rotation>0.15,[game.players[0].position,game.players[1].position])
	game.players[0].combat.facing=1
	Input.action_press("p1_heavy")
	await stream([module(1,Vector2(475,410),10)],1)
	Input.action_release("p1_heavy")
	await stream([module(1,Vector2(475,410),10)],20)
	check("combat_hits_while_udp_moves_platform",game.players[1].combat.damage_model.percent==14,game.players[1].combat.damage_model.percent)
	check("no_stock_loss_or_geometry_mutation",game.players[0].combat.damage_model.stocks==3 and game.players[1].combat.damage_model.stocks==3 and helper.geometry()==geometry)
	await input.tap(KEY_F2)
	check("f2_restores_mouse_and_closes_socket",manager.control_mode==0 and not receiver.peer.is_bound() and left.detected)
	var pose: Vector2=left.position
	var screen_point: Vector2=mouse.get_canvas_transform()*pose
	input.motion(screen_point)
	await frames(1)
	input.mouse(screen_point,true)
	await frames(2)
	var picked: StringName=mouse.selected_id
	input.motion(screen_point+Vector2(30,10),true)
	await frames(4)
	input.mouse(screen_point+Vector2(30,10),false)
	await frames(50)
	check("mouse_drag_still_works_after_udp",left.position.x>pose.x+25 and not mouse.dragging,[pose,left.position,picked,mouse.editing,left.target_position])
	send([module(1,Vector2(900,300))])
	await frames(3)
	check("udp_cannot_override_mouse_mode",left.target_position.x<pose.x+40)
	for platform: Node in manager.platforms.values():
		manager.update_platform_transform(platform.platform_id,platform.home_transform)
	await frames(180)
	receiver.module_timeout=0.5
	receiver.communication_timeout=1.0
	sender.close()
	game.restart_match()
	var failures: Array=rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var report: Dictionary={"total":rows.size(),"passed":rows.size()-failures.size(),"failed":failures.size(),"failures":failures,"results":rows}
	var file: FileAccess=FileAccess.open("res://validation/udp_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("udp_results",report)
	game.set_meta("udp_complete",true)
