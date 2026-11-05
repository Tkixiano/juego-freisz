extends RefCounted
## Real viewport input, never Button.pressed.emit(). Run through Godot MCP.
var tree: SceneTree
var rows: Array[Dictionary] = []
var label: String

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(name: String, passed: bool, detail: Variant = "") -> void:
	rows.append({"test":name,"passed":passed,"detail":str(detail)})

func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code,true)
	await frames(2)
	key(code,false)
	await frames(2)

func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)

func motion(point: Vector2, dragging: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	Input.parse_input_event(event)

func click(button: Button) -> void:
	check("visible_enabled_"+str(button.name),button.is_visible_in_tree() and not button.disabled)
	var point: Vector2 = button.get_global_rect().get_center()
	motion(point)
	await frames(1)
	mouse(point,true)
	await frames(1)
	mouse(point,false)
	await frames(3)

func ui() -> void:
	var r: Node = tree.current_scene
	var s: Node = r.get_node("GameShell")
	s.show_main_menu()
	await frames(2)
	check("boot_main_menu_pauses",s.page==0 and tree.paused and s.screen.visible)
	await click(s.controls_button)
	check("mouse_controls_from_main",s.page==3 and s.controls.visible and not s.play_button.visible)
	await click(s.back_button)
	check("mouse_back_to_main",s.page==0 and tree.paused)
	await click(s.play_button)
	check("mouse_play",s.page==1 and not tree.paused and not s.screen.visible)
	await frames(35)
	await tap(KEY_ESCAPE)
	check("escape_pause",s.page==2 and tree.paused)
	var position: Vector2 = r.players[0].position
	var platform_pose: Transform2D = r.get_node("Arena/LeftPlatform").transform
	Input.action_press("p1_right")
	Input.action_press("editor_rotate_right")
	await frames(10)
	check("paused_physics_frozen",r.players[0].position==position and r.get_node("Arena/LeftPlatform").transform==platform_pose)
	Input.action_release("p1_right")
	Input.action_release("editor_rotate_right")
	await click(s.controls_button)
	check("mouse_controls_from_pause",s.page==3 and tree.paused)
	await click(s.back_button)
	check("mouse_back_to_pause",s.page==2 and tree.paused)
	await click(s.play_button)
	check("mouse_continue",s.page==1 and not tree.paused)
	Input.action_press("p1_right")
	await frames(5)
	check("movement_after_continue",r.players[0].position.x>position.x)
	Input.action_release("p1_right")
	await tap(KEY_F1)
	check("f1_opens_controls_live",s.page==3 and tree.paused)
	await click(s.back_button)
	check("back_resumes_live",s.page==1 and not tree.paused)
	await tap(KEY_ESCAPE)
	r.players[0].combat.damage_model.percent=95
	r.players[1].combat.damage_model.stocks=1
	await click(s.restart_button)
	check("mouse_restart_resets_match",not tree.paused and not r.game_over and r.players[0].combat.damage_model.percent==0 and r.players[1].combat.damage_model.stocks==3)
	await tap(KEY_ESCAPE)
	await click(s.menu_button)
	check("mouse_main_menu",s.page==0 and tree.paused)
	await click(s.play_button)
	await frames(30)
	check("new_match_no_overlay",s.page==1 and not s.screen.visible and not r.get_node("UI/HUD/Victory").visible)
	var nodes: int = r.find_children("*","",true,false).size()
	var connections: int = s.play_button.get_signal_connection_list("pressed").size()
	for i: int in range(5):
		r.restart_match()
		await frames(1)
	check("restart_no_node_or_signal_growth",r.find_children("*","",true,false).size()==nodes and connections==1 and s.play_button.get_signal_connection_list("pressed").size()==1)
	check("two_fighters_three_platforms",r.get_node("Players").get_child_count()==2 and r.get_node("PlatformManager").platforms.size()==3)

func fresh() -> void:
	var r: Node = tree.current_scene
	r.restart_match()
	for p: Node in r.players:
		p.combat.respawn_left=0
		p.combat.invulnerability_left=0
		p.combat.accepted_hits=0
	r.players[0].position=Vector2(600,540)
	r.players[1].position=Vector2(655,540)
	r.players[0].combat.facing=1
	r.players[1].combat.facing=-1
	await frames(6)

func duel(heavy: bool, reverse_order: bool) -> void:
	await fresh()
	var r: Node = tree.current_scene
	r.players[0].process_physics_priority=1 if reverse_order else 0
	r.players[1].process_physics_priority=0 if reverse_order else 1
	var suffix: String = "heavy" if heavy else "light"
	Input.action_press("p1_"+suffix)
	Input.action_press("p2_"+suffix)
	await frames(1)
	Input.action_release("p1_"+suffix)
	Input.action_release("p2_"+suffix)
	await frames(17 if heavy else 9)
	var expected: float = 14 if heavy else 6
	check("simultaneous_"+suffix+("_reversed_order" if reverse_order else "_normal_order"),r.players[0].combat.damage_model.percent==expected and r.players[1].combat.damage_model.percent==expected,[r.players[0].combat.damage_model.percent,r.players[1].combat.damage_model.percent])
	await frames(40)
	check("trade_no_duplicate_"+suffix+str(reverse_order),r.players[0].combat.accepted_hits==1 and r.players[1].combat.accepted_hits==1)
	r.players[0].process_physics_priority=0
	r.players[1].process_physics_priority=0

func edges() -> void:
	var r: Node = tree.current_scene
	for heavy: bool in [false,true]:
		for reverse_order: bool in [false,true]:
			await duel(heavy,reverse_order)
	await fresh()
	Input.action_press("p1_light")
	Input.action_press("p2_heavy")
	await frames(1)
	Input.action_release("p1_light")
	Input.action_release("p2_heavy")
	await frames(7)
	check("earlier_light_interrupts_heavy_startup",r.players[1].combat.damage_model.percent==6 and r.players[0].combat.damage_model.percent==0 and r.players[1].combat.attack_frame<0)
	await fresh()
	Input.action_press("p1_light")
	Input.action_press("p2_dodge")
	await frames(1)
	Input.action_release("p1_light")
	Input.action_release("p2_dodge")
	await frames(12)
	check("real_attack_evaded_with_dodge",r.players[1].combat.damage_model.percent==0 and r.players[0].combat.accepted_hits==0)
	for id: int in range(2):
		await fresh()
		var p: Node=r.players[id]
		var q: Node=r.players[1-id]
		p.position=Vector2(600 if id==0 else 655,350)
		q.position=Vector2(655 if id==0 else 600,350)
		await frames(2)
		Input.action_press("p%d_light"%(id+1))
		await frames(1)
		Input.action_release("p%d_light"%(id+1))
		await frames(9)
		check("actual_air_light_hit_p%d"%(id+1),q.combat.damage_model.percent==8 and p.combat.accepted_hits==1,q.combat.damage_model.percent)
		for downward: bool in [false,true]:
			await fresh()
			p=r.players[id]
			q=r.players[1-id]
			p.position=Vector2(600,350)
			q.position=Vector2(600,400 if downward else 300)
			await frames(2)
			var direction_action: String="p%d_"%(id+1)+("down" if downward else "jump")
			Input.action_press(direction_action)
			Input.action_press("p%d_heavy"%(id+1))
			await frames(1)
			Input.action_release("p%d_heavy"%(id+1))
			await frames(12)
			Input.action_release(direction_action)
			check("actual_air_heavy_"+("down" if downward else "up")+"_p%d"%(id+1),q.combat.damage_model.percent==12 and (q.velocity.y>0 if downward else q.velocity.y<0),[q.combat.damage_model.percent,q.velocity])
	await fresh()
	var victim: Node=r.players[1]
	victim.combat.receive_hit(r.players[0].combat.ground_heavy,Vector2.RIGHT)
	victim.position=Vector2(1500,950)
	await frames(2)
	check("death_in_hitstun_clears_attack_and_stun",victim.combat.damage_model.stocks==2 and victim.combat.hitstun_left==0 and victim.combat.attack_frame<0 and victim.combat.respawn_left>0)
	await fresh()
	victim=r.players[1]
	victim.combat.damage_model.percent=200
	victim.position=Vector2(1360,500)
	victim.combat.receive_hit(r.players[0].combat.ground_heavy,Vector2.RIGHT)
	await frames(10)
	check("edge_knockback_causes_one_stock_loss",victim.combat.damage_model.stocks==2 and victim.combat.damage_model.percent==0)
	await fresh()
	r.players[0].combat.damage_model.stocks=1
	r.players[1].combat.damage_model.stocks=1
	r.players[0].position=Vector2(-200,950)
	r.players[1].position=Vector2(1500,950)
	await frames(2)
	check("double_ko_is_draw",r.game_over and r.winner_id==0 and r.get_node("UI/HUD/Victory").visible)
	await tap(KEY_R)
	check("r_replay_resets_both",not r.game_over and r.players[0].visible and r.players[1].visible and r.players[0].combat.damage_model.stocks==3 and not tree.paused)
	await frames(35)
	r.players[1].combat.damage_model.stocks=1
	r.players[1].position=Vector2(1500,950)
	await frames(2)
	check("single_winner_screen",r.game_over and r.winner_id==1 and r.get_node("UI/HUD/Victory/Message").text.contains("JUGADOR 1"))
	await tap(KEY_ESCAPE)
	await click(r.get_node("GameShell").menu_button)
	await click(r.get_node("GameShell").play_button)
	check("menu_after_victory_restarts_cleanly",not r.game_over and not tree.paused and not r.get_node("UI/HUD/Victory").visible)

func operator() -> void:
	var r: Node=tree.current_scene
	r.restart_match()
	await frames(35)
	var m: Node=r.get_node("PlatformManager")
	var c: Node=r.get_node("MousePlatformController")
	c.set_editing(true)
	for p: Node in m.platforms.values():
		m.update_platform_transform(p.platform_id,p.home_transform)
	await frames(180)
	var audit: RefCounted=load("res://validation/QAAudit.gd").new()
	audit.tree=tree
	var before: Array=audit.geometry()
	var p: Node=m.get_platform("left")
	motion(p.position)
	mouse(p.position,true)
	await frames(2)
	check("mouse_select_left",c.selected_id==&"left" and c.dragging)
	motion(Vector2(465,435),true)
	await frames(75)
	check("mouse_drag_horizontal",absf(p.position.x-465)<2,p.position)
	motion(Vector2(465,365),true)
	await frames(75)
	check("mouse_drag_vertical",absf(p.position.y-365)<2,p.position)
	mouse(Vector2(465,365),false)
	await frames(2)
	check("mouse_release_stops_drag",not c.dragging)
	key(KEY_E,true)
	await frames(30)
	key(KEY_E,false)
	await frames(30)
	check("e_rotates_selected",p.rotation>0.2,p.rotation)
	key(KEY_Q,true)
	await frames(30)
	key(KEY_Q,false)
	await frames(30)
	check("q_rotates_back",absf(p.rotation)<0.03,p.rotation)
	mouse(Vector2(1230,500),true)
	await frames(1)
	mouse(Vector2(1230,500),false)
	await frames(2)
	check("empty_click_deselects",c.selected_id.is_empty() and not c.dragging)
	var right: Node=m.get_platform("right")
	mouse(right.position,true)
	await frames(1)
	mouse(right.position,false)
	await frames(2)
	check("select_other_platform",c.selected_id==&"right")
	await tap(KEY_TAB)
	check("tab_hides_editor",not c.editing and not c.panel.visible and not c.dragging)
	mouse(p.position,true)
	await frames(1)
	mouse(p.position,false)
	await frames(2)
	check("hidden_editor_ignores_mouse",c.selected_id==&"right" and not c.dragging)
	await tap(KEY_TAB)
	check("tab_restores_editor",c.editing and c.panel.visible)
	check("mouse_rotation_preserves_all_geometry",before==audit.geometry())
	for platform: Node in m.platforms.values():
		m.update_platform_transform(platform.platform_id,platform.home_transform)
	await frames(180)
	r.restart_match()

func run_all(scene_tree: SceneTree, run_label: String) -> void:
	tree=scene_tree
	label=run_label
	await ui()
	tree.current_scene.set_meta("functional_progress","combat")
	await edges()
	tree.current_scene.set_meta("functional_progress","operator")
	await operator()
	var failed: Array=rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var report: Dictionary={"label":label,"total":rows.size(),"passed":rows.size()-failed.size(),"failed":failed.size(),"failures":failed,"results":rows}
	var file: FileAccess=FileAccess.open("res://validation/functional_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	tree.current_scene.set_meta("functional_results",report)
	tree.current_scene.set_meta("functional_progress","complete")
