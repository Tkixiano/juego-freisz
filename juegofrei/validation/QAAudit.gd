extends RefCounted
var tree: SceneTree
var groups: Dictionary = {}
var current: Array[Dictionary] = []

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(name: String, passed: bool, detail: Variant = "") -> void:
	current.append({"test":name,"passed":passed,"detail":str(detail)})

func action(name: String, pressed: bool) -> void:
	var event: InputEventAction=InputEventAction.new()
	event.action=name
	event.pressed=pressed
	Input.parse_input_event(event)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory: String=ProjectSettings.globalize_path("res://../artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	check("capture_"+name,tree.root.get_texture().get_image().save_png(directory+"/"+name)==OK)

func geometry() -> Array:
	var values: Array=[]
	for platform: Node in tree.current_scene.get_node("PlatformManager").platforms.values():
		var shape: Shape2D=platform.get_node("CollisionShape2D").shape
		var outline: Variant
		if shape is RectangleShape2D:
			outline=(shape as RectangleShape2D).size
		else:
			outline=(shape as ConvexPolygonShape2D).points
		values.append([platform.platform_id,platform.scale,outline,platform.get_node("Visual").polygon.duplicate()])
	return values

func run_ux() -> void:
	current=[]
	var root: Node=tree.current_scene
	var shell: Node=root.get_node("GameShell")
	shell.show_main_menu()
	check("main_menu_pauses_game",tree.paused and shell.page==0 and shell.play_button.visible)
	await capture("qa_menu.png")
	shell.controls_button.pressed.emit()
	check("controls_button_connected",shell.page==3 and shell.controls.visible and tree.paused)
	await capture("qa_controls.png")
	shell.back_button.pressed.emit()
	check("controls_back_to_menu",shell.page==0)
	shell.play_button.pressed.emit()
	check("start_button_starts_match",not tree.paused and shell.page==1 and root.players[0].combat.damage_model.stocks==3)
	await frames(30)
	root.get_node("MousePlatformController").dragging=true
	root.get_node("PlatformManager").update_platform_position("left",Vector2(480,400))
	action("game_pause",true)
	await frames(2)
	action("game_pause",false)
	var point: Vector2=root.players[0].position
	var pose: Transform2D=root.get_node("Arena/LeftPlatform").transform
	check("escape_pauses_and_cancels_drag",tree.paused and shell.page==2 and not root.get_node("MousePlatformController").dragging)
	await frames(15)
	check("pause_freezes_fighters_and_platforms",root.players[0].position==point and root.get_node("Arena/LeftPlatform").transform==pose)
	await capture("qa_pause.png")
	action("game_pause",true)
	await frames(2)
	action("game_pause",false)
	check("escape_resumes",not tree.paused and shell.page==1)
	action("show_controls",true)
	await frames(2)
	action("show_controls",false)
	check("f1_controls_pause_match",tree.paused and shell.page==3)
	shell.back_button.pressed.emit()
	check("controls_return_to_live_match",not tree.paused and shell.page==1)
	shell.show_pause()
	root.players[0].combat.damage_model.percent=90
	shell.restart_button.pressed.emit()
	check("restart_from_pause",not tree.paused and root.players[0].combat.damage_model.percent==0)
	shell.show_pause()
	shell.menu_button.pressed.emit()
	check("return_to_main_menu",tree.paused and shell.page==0)
	root.restart_match()
	root.get_node("PlatformManager").update_platform_transform("left",root.get_node("Arena/LeftPlatform").home_transform)
	await frames(100)
	groups["ux"]=current.duplicate()

func run_api_and_guard() -> void:
	current=[]
	var root: Node=tree.current_scene
	root.restart_match()
	var manager: Node=root.get_node("PlatformManager")
	var before: Array=geometry()
	var platform: Node=manager.get_platform("left")
	var changes: Dictionary={"count":0}
	manager.platform_detection_changed.connect(func(_id: StringName,_value: bool) -> void: changes["count"]+=1)
	check("stable_ids",manager.platforms.keys()==[&"left",&"right",&"top"])
	check("unknown_detection_id_rejected",not manager.update_platform_detection("missing",false))
	manager.update_platform_position("left",Vector2(600,390))
	await frames(10)
	manager.update_platform_detection("left",false)
	await frames(2)
	var frozen: Vector2=platform.position
	await frames(12)
	check("lost_detection_freezes_pose",platform.position.distance_to(frozen)<0.01 and not manager.get_platform_state("left")["detected"])
	check("lost_detection_keeps_collider",platform.collision_layer==2 and not platform.get_node("CollisionShape2D").disabled)
	check("commands_rejected_while_lost",not manager.update_platform_position("left",Vector2(900,400)) and not manager.update_platform_rotation("left",1.0))
	manager.update_platform_detection("left",true)
	check("detection_signal_once_per_change",changes["count"]==2,changes)
	check("input_independent_pose_api",manager.update_platform_transform("left",Transform2D(0.2,Vector2(400,420))))
	await frames(90)
	check("external_pose_reaches_target",platform.position.distance_to(Vector2(400,420))<1 and absf(platform.rotation-0.2)<0.01)
	check("reject_scaled_and_invalid_transform",not manager.update_platform_transform("left",Transform2D(0,Vector2(2,2),0,Vector2(400,420))) and not manager.update_platform_position("left",Vector2(INF,0)))
	manager.update_platform_transform("left",platform.home_transform)
	await frames(90)
	var player: CharacterBody2D=root.players[0]
	var guard: Node=player.get_node("UnstuckGuard")
	var previous_recoveries: int=guard.recoveries
	var previous_stocks: int=player.combat.damage_model.stocks
	player.set_physics_process(false)
	player.position=Vector2(640,580)
	player.reset_physics_interpolation()
	await frames(42)
	check("persistent_embedding_recovers",guard.recoveries>previous_recoveries and not guard._occupied(player.position),player.position)
	check("recovery_does_not_subtract_stock",player.combat.damage_model.stocks==previous_stocks)
	player.set_physics_process(true)
	player.respawn()
	await frames(40)
	var settled_count: int=guard.recoveries
	await frames(35)
	check("standing_floor_not_false_recovery",guard.recoveries==settled_count)
	check("platform_geometry_unchanged",geometry()==before)
	var p: Node=root.players[0]
	check("combat_and_stage_layers_separate",p.collision_mask==3 and p.get_node("Hurtbox").collision_layer==8 and p.combat.hitbox.query.collision_mask==8)
	check("impact_and_respawn_connections",p.respawned.is_connected(root._on_respawned) and p.combat.impact.is_connected(root.effects.burst))
	check("shared_physics_and_independent_hitboxes",p.movement==root.players[1].movement and p.combat.hitbox.collider.shape!=root.players[1].combat.hitbox.collider.shape)
	check("slow_gravity_preserved",p.movement.ascent_gravity==1250 and p.movement.descent_gravity==1450 and p.movement.terminal_speed==640 and p.movement.fast_fall_speed==800)
	check("physics_interpolation_enabled",ProjectSettings.get_setting("physics/common/physics_interpolation",false) and root.get_node("Camera2D").process_callback==0)
	check("idle_effects_stop_processing",root.effects.bursts.is_empty() and not root.effects.is_processing())
	var required: Array[String]=["p1_left","p1_right","p1_jump","p1_down","p2_left","p2_right","p2_jump","p2_down","p1_light","p1_heavy","p1_dodge","p2_light","p2_heavy","p2_dodge","editor_rotate_left","editor_rotate_right","editor_toggle","match_restart","game_pause","show_controls"]
	var valid: bool=true
	for name: String in required:
		valid=valid and InputMap.has_action(name) and not InputMap.action_get_events(name).is_empty()
	check("all_20_actions_have_bindings",valid)
	var key: InputEventKey=InputMap.action_get_events("p2_dodge")[0] as InputEventKey
	check("right_shift_physical_location",key.physical_keycode==KEY_SHIFT and key.location==KEY_LOCATION_RIGHT)
	groups["api_guard_audit"]=current.duplicate()

func run_crush() -> void:
	current=[]
	var root: Node=tree.current_scene
	root.restart_match()
	var original: Array=geometry()
	var manager: Node=root.get_node("PlatformManager")
	manager.update_platform_transform("left",Transform2D(PI,Vector2(640,520)))
	await frames(420)
	root.restart_match()
	var p: CharacterBody2D=root.players[0]
	p.combat.respawn_left=0
	p.position=Vector2(640,542)
	p.velocity=Vector2.ZERO
	p.reset_physics_interpolation()
	var guard: Node=p.get_node("UnstuckGuard")
	var before: int=guard.recoveries
	await frames(130)
	check("inverted_platform_floor_crush_escapes_once",guard.recoveries==before+1 and not guard._occupied(p.position) and p.is_on_floor(),{"recoveries":guard.recoveries-before,"position":p.position})
	check("crush_keeps_stocks_and_geometry",p.combat.damage_model.stocks==3 and geometry()==original)
	manager.update_platform_transform("left",manager.get_platform("left").home_transform)
	await frames(420)
	groups["real_crush"]=current.duplicate()

func run_all(scene_tree: SceneTree) -> void:
	tree=scene_tree
	await run_ux()
	await run_api_and_guard()
	await run_crush()
	for item: Array in [
		["combat_core","res://validation/CombatValidation.gd","run_core"],
		["combat_defense","res://validation/CombatValidation.gd","run_defense_and_direction"],
		["combat_stocks","res://validation/CombatValidation.gd","run_stocks"],
		["platform_combat","res://validation/CombatValidation.gd","run_platform_combat"],
		["movement","res://validation/MovementValidation.gd","run"],
		["platform_carry","res://validation/DynamicValidation.gd","run_carry"],
		["platform_limits","res://validation/DynamicValidation.gd","run_limits"],
		["gravity","res://validation/DynamicValidation.gd","run_gravity"]
	]:
		tree.current_scene.restart_match()
		tree.current_scene.set_meta("qa_progress",item[0])
		var suite: RefCounted=load(item[1]).new()
		var result: Array=await suite.call(item[2],tree)
		groups[item[0]]=result
	var passed: int=0
	var total: int=0
	var failures: Array=[]
	for group: String in groups:
		for result: Dictionary in groups[group]:
			total+=1
			if result["passed"]:
				passed+=1
			else:
				failures.append({"group":group,"test":result})
	var report: Dictionary={"total":total,"passed":passed,"failed":total-passed,"failures":failures,"groups":groups}
	var file: FileAccess=FileAccess.open("res://validation/qa_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	tree.current_scene.set_meta("qa_results",report)
	tree.current_scene.set_meta("qa_progress","complete")
	tree.current_scene.restart_match()
