extends RefCounted
const Catalog = preload("res://scripts/CharacterCatalog.gd")
const AppearanceScene = preload("res://scenes/CharacterAppearance.tscn")
var tree: SceneTree
var game: Node
var shell: Node
var panel: Node
var p: Node
var q: Node
var rows: Array[Dictionary] = []

func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame

func check(name: String,passed: bool,details: Variant="") -> void:
	rows.append({"name":name,"passed":passed,"details":str(details)})
	if not passed: push_error("PHASE2B "+name+": "+str(details))

func action(name: String) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = name;event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func shift_key(location: KeyLocation) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_SHIFT;event.physical_keycode = KEY_SHIFT
		event.location = location;event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func click(button: Button) -> void:
	check("visible_"+button.text,button.is_visible_in_tree() and not button.disabled)
	var point: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point;motion.global_position = point
	Input.parse_input_event(motion)
	await frames(1)
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point;event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT;event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func run(scene_tree: SceneTree,label: String="mcp") -> Dictionary:
	tree = scene_tree;game = tree.current_scene;shell = game.get_node("GameShell");panel = shell.selection
	p = game.players[0];q = game.players[1]
	await frames(3)
	await selection_tests()
	await combat_tests()
	await animation_tests()
	if DisplayServer.get_name()!="headless": await mouse_tests()
	var failed: Array = rows.filter(func(r: Dictionary)->bool:return not r.passed)
	var result: Dictionary = {"label":label,"total":rows.size(),"passed":rows.size()-failed.size(),"failures":failed,"rows":rows,"graphical_tests":DisplayServer.get_name()!="headless","hardware_used":false}
	game.set_meta("phase2b_results",result)
	var file: FileAccess = FileAccess.open("res://validation/phase2b_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("PHASE2B_QA ",JSON.stringify({"label":label,"passed":result.passed,"total":result.total,"failures":failed}))
	return result

func selection_tests() -> void:
	shell.show_main_menu()
	shell._on_play()
	await frames(2)
	check("play_opens_selection",shell.page==4 and tree.paused and panel.visible)
	var ids: Dictionary = {}
	for definition: Resource in Catalog.ENTRIES: ids[definition.character_id] = true
	check("four_unique_definitions",Catalog.ENTRIES.size()==4 and ids.size()==4)
	var first: int = panel.choices[0]
	var second: int = panel.choices[1]
	for i: int in range(4):
		await action("p1_right")
		check("p1_navigate_%d"%i,panel.choices[0]==(first+i+1)%4 and panel.choices[1]==second)
	await action("p2_left")
	check("p2_independent_navigation",panel.choices[0]==first and panel.choices[1]==posmod(second-1,4))
	panel.choose(0,2);panel.choose(1,2)
	check("same_character_allowed",panel.choices==[2,2])
	var portrait_definition: Resource = Catalog.ENTRIES[2]
	var old_portrait: Texture2D = portrait_definition.portrait
	var test_portrait: GradientTexture2D = GradientTexture2D.new()
	portrait_definition.portrait = test_portrait;panel._refresh()
	check("portrait_resource_displayed",panel.portraits[0].texture==test_portrait and panel.portraits[0].visible and not panel.previews[0].visible)
	portrait_definition.portrait = old_portrait;panel._refresh()
	await action("p1_light")
	check("p1_ready_does_not_start",panel.ready_flags==[true,false] and shell.page==4 and tree.paused)
	panel.choose(0,3)
	check("ready_locks_choice",panel.choices[0]==2)
	await action("p1_dodge")
	check("cancel_ready",not panel.ready_flags[0])
	await action("p1_right")
	check("change_after_cancel",panel.choices[0]==3)
	panel.choose(0,2)
	await action("p2_light")
	check("p2_ready_does_not_start",panel.ready_flags==[false,true] and shell.page==4 and tree.paused)
	await shift_key(KEY_LOCATION_LEFT)
	check("left_shift_does_not_cancel_p2",panel.ready_flags[1])
	await shift_key(KEY_LOCATION_RIGHT)
	check("right_shift_cancels_only_p2",panel.ready_flags==[false,false])
	await action("p1_light")
	await action("p2_light")
	await frames(3)
	check("both_ready_start_match",shell.page==1 and not tree.paused and not panel.visible)
	check("selected_visuals_instantiated",p.get_node("Presentation").definition==Catalog.ENTRIES[2] and q.get_node("Presentation").definition==Catalog.ENTRIES[2])
	check("same_character_independent_instances",p.get_node("Presentation").appearance!=q.get_node("Presentation").appearance)
	check("player_ids_controls_preserved",p.player_id==1 and q.player_id==2 and p.left_action==&"p1_left" and q.left_action==&"p2_left")
	await frames(8)
	check("ready_input_does_not_attack_in_match",p.combat.damage_model.percent==0 and q.combat.damage_model.percent==0 and p.combat.attack_frame<0 and q.combat.attack_frame<0)
	shell.show_main_menu();shell._on_play()
	panel.choose(0,3);panel.choose(1,0)
	panel.toggle_ready(0);panel.toggle_ready(1)
	await frames(2)
	check("change_between_matches",p.get_node("Presentation").definition.character_id==&"violet" and q.get_node("Presentation").definition.character_id==&"indigo")
	shell.show_main_menu();shell._on_play();panel.toggle_ready(0)
	await action("game_pause")
	check("selection_back_to_main",shell.page==0 and tree.paused)
	shell._on_play()
	check("new_selection_resets_ready_preserves_committed_choices",panel.ready_flags==[false,false] and panel.choices==[3,0])
	shell.show_controls();shell.back()
	check("controls_return_to_selection",shell.page==4 and panel.visible and tree.paused)
	game.restart_match()

func prepare_pair(definition: Resource) -> void:
	var pair: Array[Resource] = [definition,definition]
	game.set_character_selection(pair);game.restart_match()
	await frames(1)
	for body: Node in [p,q]:
		body.combat.respawn_left = 0;body.combat.invulnerability_left = 0;body.combat.accepted_hits = 0
		body.velocity = Vector2.ZERO
	p.position = Vector2(600,540);q.position = Vector2(655,540)
	p.force_update_transform();q.force_update_transform()
	await frames(5)

func combat_tests() -> void:
	var collider: Shape2D = p.get_node("CollisionShape2D").shape
	var hurt: Shape2D = p.get_node("Hurtbox/CollisionShape2D").shape
	var movement: Resource = p.movement
	for definition: Resource in Catalog.ENTRIES:
		await prepare_pair(definition)
		var prefix: String = String(definition.character_id)
		check(prefix+"_placeholder_without_sheets",p.get_node("Presentation").appearance.using_placeholder)
		check(prefix+"_name_identifiable",p.get_node("Identifier").text.contains(definition.display_name))
		check(prefix+"_identical_physics",p.movement==movement and p.get_node("CollisionShape2D").shape==collider and p.get_node("Hurtbox/CollisionShape2D").shape==hurt and p.scale==Vector2.ONE)
		Input.action_press("p1_light");await frames(1);Input.action_release("p1_light")
		await frames(10)
		check(prefix+"_light_damage",q.combat.damage_model.percent==6 and p.combat.accepted_hits==1,q.combat.damage_model.percent)
		await frames(35)
		await prepare_pair(definition)
		Input.action_press("p1_heavy");await frames(1);Input.action_release("p1_heavy")
		await frames(18)
		check(prefix+"_heavy_damage",q.combat.damage_model.percent==14 and p.combat.accepted_hits==1,q.combat.damage_model.percent)
		await frames(36)
		Input.action_press("p1_right");Input.action_press("p1_dodge")
		await frames(1)
		check(prefix+"_dash",p.combat.horizontal_dash and p.combat.invulnerability_left>0 and p.get_node("Presentation").logical_state==&"dash")
		Input.action_release("p1_right");Input.action_release("p1_dodge")
		await frames(22)
		p.combat.invulnerability_left = 0
		check(prefix+"_receive_damage",p.combat.receive_hit(q.combat.ground_light,Vector2.LEFT))
		await frames(1)
		check(prefix+"_hurt_animation_state",p.get_node("Presentation").logical_state==&"hurt")
		p.position = Vector2(-200,950)
		await frames(3)
		check(prefix+"_respawn_keeps_selection",p.combat.damage_model.stocks==2 and p.get_node("Presentation").definition==definition and p.combat.damage_model.percent==0)
		p.combat.damage_model.stocks = 1;p.position = Vector2(-200,950)
		await frames(3)
		check(prefix+"_defeat_and_victory",p.combat.eliminated and game.game_over and p.get_node("Presentation").logical_state==&"defeat")
		game.restart_match()
		await frames(1)
		check(prefix+"_restart_keeps_selection",p.get_node("Presentation").definition==definition and p.combat.damage_model.stocks==3)
	var count: int = game.find_children("*","",true,false).size()
	for i: int in range(5): game.restart_match();await frames(1)
	check("restart_does_not_duplicate_nodes",game.find_children("*","",true,false).size()==count and game.get_node("Players").get_child_count()==2)

func animation_tests() -> void:
	game.restart_match()
	var data: Resource = Catalog.ENTRIES[0].duplicate(true)
	var frames_resource: SpriteFrames = SpriteFrames.new()
	frames_resource.add_animation(&"espera_artistica")
	frames_resource.add_animation(&"carrera_artistica")
	frames_resource.add_animation(&"golpe_unico")
	var texture_a: GradientTexture2D = GradientTexture2D.new();texture_a.width = 12;texture_a.height = 20
	var texture_b: GradientTexture2D = GradientTexture2D.new();texture_b.width = 30;texture_b.height = 16
	frames_resource.add_frame(&"espera_artistica",texture_a,0.5)
	frames_resource.add_frame(&"espera_artistica",texture_b,1.0)
	frames_resource.set_animation_speed(&"espera_artistica",7)
	frames_resource.add_frame(&"carrera_artistica",texture_b)
	frames_resource.set_animation_speed(&"carrera_artistica",19)
	frames_resource.add_frame(&"golpe_unico",texture_a)
	frames_resource.set_animation_speed(&"golpe_unico",60)
	frames_resource.set_animation_loop(&"golpe_unico",false)
	data.sprite_frames = frames_resource
	data.animation_map = {"idle":"espera_artistica","run":"carrera_artistica","light":"golpe_unico","up":"missing"}
	var appearance: Node2D = AppearanceScene.instantiate();game.add_child(appearance);appearance.configure(data)
	appearance.apply_visual_state(&"idle",1,false)
	check("custom_names_frames_and_fps",appearance.played_animation==&"espera_artistica" and frames_resource.get_frame_count(appearance.played_animation)==2 and frames_resource.get_animation_speed(appearance.played_animation)==7)
	check("arbitrary_frame_sizes",frames_resource.get_frame_texture(&"espera_artistica",0).get_size()!=frames_resource.get_frame_texture(&"espera_artistica",1).get_size())
	appearance.apply_visual_state(&"idle",1,true)
	check("sprite_flash_parameter",appearance.sprite.material.get_shader_parameter("flash_amount")==1.0)
	check("player_flash_materials_are_independent",p.get_node("Presentation").appearance.sprite.material!=q.get_node("Presentation").appearance.sprite.material)
	appearance.apply_visual_state(&"run",-1,false)
	check("run_mapping_and_facing",appearance.played_animation==&"carrera_artistica" and appearance.sprite.flip_h and frames_resource.get_animation_speed(appearance.played_animation)==19)
	appearance.apply_visual_state(&"up",1,false)
	check("missing_attack_falls_back_to_idle",appearance.played_animation==&"espera_artistica" and not appearance.using_placeholder)
	appearance.apply_visual_state(&"light",1,false)
	await frames(5)
	appearance.apply_visual_state(&"light",1,false)
	check("one_shot_does_not_restart_every_tick",not appearance.sprite.is_playing())
	appearance.configure(data)
	check("reconfigure_restarts_correct_idle",appearance.played_animation==&"espera_artistica" and appearance.sprite.is_playing())
	data.sprite_frames = null;appearance.configure(data)
	for state: StringName in [&"idle",&"run",&"jump",&"fall",&"light",&"heavy",&"up",&"down",&"dash",&"hurt",&"defeat"]:
		appearance.apply_visual_state(state,1,false)
		check("placeholder_fallback_"+String(state),appearance.using_placeholder and appearance.requested_state==state)
	appearance.free()
	var presentation: Node = p.get_node("Presentation")
	var baseline_shape: Shape2D = p.get_node("CollisionShape2D").shape
	data.visual_scale = Vector2(3,2);data.visual_offset = Vector2(5,-8)
	presentation.set_definition(data)
	check("visual_transform_does_not_scale_body_or_hitbox",p.scale==Vector2.ONE and p.get_node("Combat/Hitbox").scale==Vector2.ONE and p.get_node("CollisionShape2D").shape==baseline_shape)
	var bad_root: Node2D = Node2D.new()
	var bad_collision: CollisionShape2D = CollisionShape2D.new();bad_root.add_child(bad_collision);bad_collision.owner = bad_root
	var packed: PackedScene = PackedScene.new();packed.pack(bad_root);bad_root.free()
	data.visual_scene = packed
	var rejected: int = presentation.rejected_visuals
	# A different Resource triggers a visual replacement; same reference is a no-op.
	var bad_data: Resource = data.duplicate(true)
	presentation.set_definition(bad_data)
	check("physics_nodes_in_visual_rejected_safely",presentation.rejected_visuals==rejected+1 and presentation.appearance.has_method("apply_visual_state") and p.get_node("CollisionShape2D").shape==baseline_shape)
	var invalid: Resource = Catalog.ENTRIES[0].duplicate(true);invalid.visual_scale = Vector2(-1,1)
	check("invalid_visual_definition_rejected",not presentation.set_definition(invalid))
	await prepare_pair(Catalog.ENTRIES[0])
	if DisplayServer.get_name()!="headless": await rendered_sprite_tests()

func rendered_sprite_tests() -> void:
	# Temporary synthetic texture, never an imported/final artist asset.
	var image: Image = Image.create(8,8,false,Image.FORMAT_RGBA8)
	var color: Color = Color(0.6,0.4,0.2,1)
	image.fill(color)
	var frames_resource: SpriteFrames = SpriteFrames.new()
	frames_resource.add_animation(&"test_color")
	frames_resource.add_frame(&"test_color",ImageTexture.create_from_image(image))
	var data: Resource = Catalog.ENTRIES[0].duplicate(true)
	data.sprite_frames = frames_resource;data.animation_map = {"idle":"test_color"}
	var appearance: Node2D = AppearanceScene.instantiate();game.add_child(appearance)
	appearance.position = Vector2(650,180);appearance.configure(data)
	# Allow new CanvasItem draw commands and runtime texture upload to reach GPU.
	await frames(2)
	await RenderingServer.frame_post_draw
	var pixel: Color = tree.root.get_texture().get_image().get_pixel(650,180)
	check("sprite_texture_color_not_multiplied_twice",Vector3(pixel.r-color.r,pixel.g-color.g,pixel.b-color.b).length()<0.04,[pixel,color])
	appearance.apply_visual_state(&"idle",1,true)
	await RenderingServer.frame_post_draw
	pixel = tree.root.get_texture().get_image().get_pixel(650,180)
	check("sprite_impact_flash_renders_white",pixel.r>0.97 and pixel.g>0.97 and pixel.b>0.97,pixel)
	appearance.visible = false
	await RenderingServer.frame_post_draw
	var background: Color = tree.root.get_texture().get_image().get_pixel(650,180)
	appearance.visible = true;appearance.modulate.a = 0.5
	appearance.apply_visual_state(&"idle",1,false)
	await RenderingServer.frame_post_draw
	pixel = tree.root.get_texture().get_image().get_pixel(650,180)
	var expected: Color = background.lerp(color,0.5)
	check("sprite_alpha_respects_invulnerability_modulate",Vector3(pixel.r-expected.r,pixel.g-expected.g,pixel.b-expected.b).length()<0.06,[pixel,expected])
	appearance.free()

func mouse_tests() -> void:
	shell.show_main_menu()
	await frames(2);await click(shell.play_button)
	check("mouse_play_selection",shell.page==4 and tree.paused)
	await click(panel.cards[0][1]);await click(panel.cards[1][3])
	check("mouse_independent_choices",panel.choices==[1,3])
	await RenderingServer.frame_post_draw
	var image: Image = tree.root.get_texture().get_image()
	for slot: int in range(2):
		var point: Vector2 = panel.previews[slot].get_global_transform_with_canvas()*Vector2(-15,12)
		var pixel: Color = image.get_pixelv(Vector2i(point))
		var expected: Color = Catalog.ENTRIES[panel.choices[slot]].accent
		check("preview_pixels_follow_selection_%d"%slot,Vector3(pixel.r-expected.r,pixel.g-expected.g,pixel.b-expected.b).length()<0.06,[pixel,expected])
	await click(panel.ready_buttons[0])
	check("mouse_single_ready_waits",shell.page==4)
	await click(panel.ready_buttons[0])
	check("mouse_cancel_ready",not panel.ready_flags[0])
	await click(panel.ready_buttons[0]);await click(panel.ready_buttons[1])
	check("mouse_both_start",shell.page==1 and not tree.paused)
	shell.show_main_menu();shell._on_play();await frames(2)
	await click(panel.back_button)
	check("mouse_back_main",shell.page==0)
