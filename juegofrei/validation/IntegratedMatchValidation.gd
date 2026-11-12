extends RefCounted
var tree: SceneTree
var game: Node
var source: Node
var backend: Node
var manager: Node
var floor_node: Node
var p: Node
var q: Node
var driver: Node
var seq: int = 0
var rows: Array = []
func frames(n: int) -> void:
	for i: int in range(n):await tree.physics_frame
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
	if game!=null:game.set_meta("integrated_progress",name)
	if not ok:push_error("INTEGRATED "+name+" "+str(detail))
func fixture(name: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/material_replays/"+name+".json"))
	return data.frames[-1].duplicate(true)
func action(name: String,pressed: bool) -> void:
	var e: InputEventAction = InputEventAction.new();e.action = name;e.pressed = pressed;driver.events.append(e)
func place(player: Node,point: Vector2,vel: Vector2=Vector2.ZERO) -> void:
	player.position = point;player.velocity = vel;player.collision_mask = 3;player.set_physics_process(true)
	player.combat.reset_after_respawn();player.combat.respawn_left = 0;player.combat.invulnerability_left = 0
	player.force_update_transform();player.reset_physics_interpolation()
func park() -> void:
	driver.events.clear()
	for a: StringName in InputMap.get_actions():
		if String(a).begins_with("p1_") or String(a).begins_with("p2_"):Input.action_release(a)
	for player: Node in [p,q]:
		player.position = Vector2(100+player.player_id*100,-100);player.velocity = Vector2.ZERO;player.collision_mask = 0;player.set_physics_process(false)
func fresh() -> void:
	park();game.get_node("Replay").pause();source.request_reset();await frames(3)
	backend.request_reset();await frames(3)
	source.scene_state = "SCENE_EMPTY";source.applied_state = "SCENE_EMPTY";source.proposed_state = "SCENE_EMPTY"
	floor_node.set_enabled(true);floor_node.scene_state = "SCENE_EMPTY"
	seq = 0
func feed(data: Dictionary,n: int=3) -> void:
	for i: int in range(n):
		var frame: Dictionary = data.duplicate(true);seq += 1
		frame.sequence = seq;frame.logical_time = seq/30.0;frame.session_id = "integrated-qa"
		source.submit(frame);await frames(4)
	await frames(3)
func empty_state() -> Dictionary:
	return {"structures":[],"identity_epochs":{},"region_identity_epochs":{},"events":[],"diagnostic":{"status":"TRACKING"}}
func run(scene_tree: SceneTree,label: String="headless") -> Dictionary:
	tree = scene_tree;game = tree.current_scene;source = game.get_node("SceneSource");backend = game.get_node("Adapter");manager = game.get_node("DynamicGeometry");floor_node = game.get_node("SafetyFloor")
	p = game.players[0];q = game.players[1]
	driver = load("res://validation/MaterialPhysicsTestInput.gd").new();game.add_child(driver)
	var shell: Node = game.get_node("GameShell")
	check("initial_main_menu",tree.paused and shell.page==0)
	shell.play_button.pressed.emit();check("selection_open",shell.page==4)
	shell.selection.choose(0,2);shell.selection.choose(1,3);shell.selection.toggle_ready(0)
	check("one_ready_waits",tree.paused)
	shell.selection.toggle_ready(1);await frames(3)
	check("both_ready_start",not tree.paused and shell.page==1)
	check("selected_characters_kept",game.selected_characters[0]==game.CharacterCatalog.ENTRIES[2] and game.selected_characters[1]==game.CharacterCatalog.ENTRIES[3])
	check("player_controls_kept",p.player_id==1 and q.player_id==2 and p.left_action==&"p1_left" and q.left_action==&"p2_left")
	var originals_disabled: bool = true
	for name: String in ["Ground","LeftPlatform","RightPlatform","TopPlatform"]:
		var body: Node = game.get_node("Arena/"+name)
		originals_disabled = originals_disabled and body.collision_layer==0 and body.get_node("CollisionShape2D").disabled
	check("original_platforms_disabled",originals_disabled)
	check("offline_does_not_listen_udp",game.get_node("Sources").mode=="OFFLINE" and not game.get_node("UdpTransport").listening)
	await frames(55)
	check("initial_empty_floor",floor_node.enabled and source.scene_state=="SCENE_EMPTY" and manager.object_ids().is_empty())
	check("two_players_supported_by_floor",p.is_on_floor() and q.is_on_floor(),[p.position,q.position])
	check("floor_is_not_structure",backend.logical_active.is_empty() and floor_node.get("object_id")==null)
	game.get_node("UI/SourcePanel/Play").pressed.emit();await frames(25)
	check("empty_source_play_button",source.scene_state=="SCENE_EMPTY" and game.get_node("Replay").frames.size()==5 and floor_node.enabled)
	source.request_reset();await frames(3)
	var activations: int = floor_node.metrics.activations
	source.set_health("SCENE_STALE");await frames(4)
	check("stale_preserves_initial_floor",floor_node.enabled and floor_node.metrics.activations==activations)
	source.set_health("SCENE_ERROR");await frames(4)
	check("error_preserves_initial_floor",floor_node.enabled and floor_node.metrics.activations==activations)
	await feed(fixture("07_three"))
	check("three_materials_active",manager.object_ids().size()==3 and source.scene_state=="SCENE_ACTIVE",manager.last_conflict)
	check("floor_retirement_deferred_with_two_players",floor_node.enabled and floor_node.metrics.deferred_retirements>0,floor_node.last_reason)
	place(q,Vector2(610,460));await frames(8)
	check("single_player_on_floor_keeps_it",floor_node.enabled and p.is_on_floor() and q.is_on_floor())
	place(p,Vector2(510,460));place(q,Vector2(610,460));await frames(12)
	check("safe_floor_retirement",not floor_node.enabled and p.is_on_floor() and q.is_on_floor(),floor_node.last_reason)
	source.set_health("SCENE_STALE");await frames(8)
	check("stale_keeps_geometry_without_floor",not floor_node.enabled and manager.object_ids().size()==3)
	source.set_health("SCENE_ERROR");await frames(8)
	check("error_keeps_geometry_without_floor",not floor_node.enabled and manager.object_ids().size()==3)
	await feed(fixture("07_three"));check("recovery",source.scene_state=="SCENE_ACTIVE")
	source.request_reset();await frames(4)
	check("source_restart_preserves_support",manager.object_ids().size()==3 and not floor_node.enabled and p.is_on_floor())
	seq = 0;await feed(fixture("07_three"));check("new_source_recovers",source.scene_state=="SCENE_ACTIVE")
	await feed(empty_state());await frames(55)
	check("confirmed_empty_restores_floor",floor_node.enabled and manager.object_ids().is_empty() and source.scene_state=="SCENE_EMPTY")
	check("empty_transition_no_stock_loss",p.combat.damage_model.stocks==3 and q.combat.damage_model.stocks==3,[p.combat.damage_model.stocks,q.combat.damage_model.stocks])
	await fresh()
	await feed(fixture("07_three"),1);await frames(20)
	check("single_active_detection_does_not_remove_floor",floor_node.enabled and manager.object_ids().is_empty())
	await feed(empty_state())
	# Incoming structure intersects the floor: the entire transaction must wait.
	place(p,Vector2(440,floor_node.floor_rect.position.y-20));place(q,Vector2(840,floor_node.floor_rect.position.y-20));await frames(3)
	var overlap: Dictionary = fixture("01_solid");overlap.structures[0].position[1] = floor_node.floor_rect.position.y+10-source.arena_offset.y
	await feed(overlap)
	check("overlap_floor_batch_deferred",not backend.pending_frame.is_empty() and manager.object_ids().is_empty() and floor_node.enabled,manager.last_conflict)
	source.set_health("SCENE_STALE");await frames(3)
	check("stale_cancels_only_unapplied_target",backend.pending_frame.is_empty() and manager.object_ids().is_empty() and floor_node.enabled)
	await feed(overlap)
	check("recovery_after_deferred_source_interruption",not backend.pending_frame.is_empty() and source.scene_state=="SCENE_ACTIVE")
	action("p1_jump",true);action("p2_jump",true);await frames(5);action("p1_jump",false);action("p2_jump",false);await frames(3)
	check("overlap_floor_retires_atomically_when_safe",not floor_node.enabled and manager.object_ids().size()==1 and backend.pending_frame.is_empty(),manager.last_conflict)
	await fresh();await feed(fixture("02_bounce"));place(p,Vector2(510,430),Vector2(0,250))
	var contact: Node = p.get_node("MaterialContact");var bounces: int = contact.metrics.bounces
	await frames(20);check("blue_bounce_in_match",contact.metrics.bounces==bounces+1,contact.metrics)
	await fresh();await feed(fixture("03_one_way"));place(p,Vector2(510,550),Vector2(0,-650))
	await frames(20);check("orange_from_below",p.position.y<460,p.position)
	await frames(65);check("orange_landing",p.is_on_floor() and p.position.y<465,p.position)
	var drops: int = contact.metrics.drops;action("p1_down",true);await frames(2);action("p1_down",false);await frames(18)
	check("orange_drop_in_match",contact.metrics.drops==drops+1 and contact.ignored.is_empty(),p.position)
	check("active_inaccessible_does_not_activate_floor",not floor_node.enabled)
	await fresh();await feed(fixture("01_solid"));place(p,Vector2(490,460));place(q,Vector2(530,460));await frames(4)
	action("p1_right",true);action("p1_dodge",true);await frames(2)
	check("dash_in_match",p.combat.horizontal_dash and p.combat.invulnerability_left>0)
	park();place(p,Vector2(490,460));place(q,Vector2(530,460));await frames(3)
	action("p1_jump",true);action("p1_light",true);await frames(2)
	check("ascending_attack",p.combat.aim==Vector2.UP and p.combat.attack_frame>=0)
	park();place(p,Vector2(510,390));await frames(2)
	action("p1_down",true);action("p1_heavy",true);await frames(2)
	check("descending_attack",p.combat.is_descending_attack())
	park();place(p,Vector2(490,460));place(q,Vector2(530,460));await frames(3)
	p.combat.accepted_hits = 0;q.combat.accepted_hits = 0
	action("p1_light",true);action("p2_light",true);await frames(30)
	check("two_player_combat",p.combat.damage_model.percent==6 and q.combat.damage_model.percent==6,[p.combat.damage_model.percent,q.combat.damage_model.percent])
	await fresh();var occupied: Dictionary = fixture("01_solid");occupied.structures[0].position = [140,350];await feed(occupied)
	p.combat.damage_model.stocks = 3;game._lose_stock(p);await frames(3)
	check("stock_loss_preserved",p.combat.damage_model.stocks==2)
	check("respawn_avoids_occupied_spawn",not manager.get_body(manager.object_ids()[0]).overlaps_character(game.inner,p.get_node("CollisionShape2D").global_transform),p.position)
	p.combat.damage_model.stocks = 1;game._lose_stock(p);await frames(2)
	check("victory_preserved",game.game_over and game.winner_id==2)
	game.restart_match();await frames(3)
	check("restart_preserves_selection_and_stocks",not game.game_over and p.combat.damage_model.stocks==3 and game.selected_characters[0]==game.CharacterCatalog.ENTRIES[2])
	park();await fresh();await feed(fixture("07_three"))
	var count: int = manager.object_ids().size();var bad: Dictionary = fixture("07_three");bad.sequence = seq;bad.logical_time = seq/30.0;bad.session_id = "integrated-qa"
	check("duplicate_rejected",source.submit(bad).status=="REJECTED" and manager.object_ids().size()==count)
	bad.sequence += 1;bad.structures[0].material_regions[0].material = "INVALID"
	check("invalid_rejected_atomically",source.submit(bad).status=="REJECTED" and manager.object_ids().size()==count)
	bad = fixture("07_three");bad.sequence = seq+2;bad.logical_time = (seq+2)/30.0;bad.session_id = "integrated-qa"
	bad.events = [{"type":"MERGE","parents":[4],"children":[]}]
	check("invalid_event_identity_rejected",source.submit(bad).get("reason")=="event_identity")
	game.get_node("UI/SourcePanel").select_file(0);await frames(50)
	check("ui_empty_source_confirmed",source.scene_state=="SCENE_EMPTY" and manager.object_ids().is_empty() and floor_node.enabled)
	# Never remove a low support to turn on a floor ABOVE its rider.
	await fresh();floor_node.set_enabled(false)
	var low: Dictionary = fixture("01_solid");low.structures[0].position[1] = floor_node.floor_rect.position.y+110-source.arena_offset.y
	await feed(low);place(p,Vector2(510,floor_node.floor_rect.position.y+75));await frames(4)
	await feed(empty_state())
	check("empty_activation_below_player_deferred",not floor_node.enabled and not backend.pending_frame.is_empty() and manager.object_ids().size()==1,manager.last_conflict)
	action("p1_jump",true);await frames(20);action("p1_jump",false);await frames(3)
	check("empty_activation_after_clearance",floor_node.enabled and manager.object_ids().is_empty() and p.combat.damage_model.stocks==3,manager.last_conflict)
	# Inaccessible geometry must not invent a floor. Respawn waits for safe space.
	await fresh();var far: Dictionary = fixture("01_solid");far.structures[0].position = [2000,2000]
	await feed(far);p.respawn();await frames(20)
	check("unsafe_respawn_waits_without_losing_stock",not floor_node.enabled and game.get_node("SafeSpawn").pending.has(1) and p.combat.damage_model.stocks==3)
	await feed(empty_state());await frames(45)
	check("deferred_respawn_recovers_on_empty",floor_node.enabled and game.get_node("SafeSpawn").pending.is_empty() and p.collision_mask==3 and p.combat.damage_model.stocks==3)
	for name: String in ["19_supported_merge","20_supported_split"]:
		await fresh();var replay_support: Node = game.get_node("Replay")
		check(name+"_load",replay_support.load_replay("res://validation/material_replays/"+name+".json"))
		await frames(3);replay_support.set_speed(2);replay_support.play()
		var wait: int = 0
		while manager.object_ids().is_empty() and wait<150:await frames(1);wait += 1
		place(p,Vector2(510,460));await frames(3)
		var lost: int = 0;var observed: int = 0
		while (replay_support.cursor<replay_support.frames.size() or not backend.pending_frame.is_empty() or not source.candidate.is_empty()) and wait<500:
			await frames(1);wait += 1;observed += 1
			if not p.is_on_floor():lost += 1
		check(name+"_native_support_in_match",observed>5 and lost==0 and not floor_node.enabled and p.combat.damage_model.stocks==3,{"ticks":observed,"lost":lost})
	# Actual replay through the source-neutral gateway, including MERGE/SPLIT.
	await fresh();var replay: Node = game.get_node("Replay")
	check("long_replay_load",replay.load_replay("res://validation/material_replays/26_long.json"));await frames(3);replay.set_speed(2);replay.play()
	var before_merge: int = backend.logical_metrics.merges;var before_split: int = backend.logical_metrics.splits
	var ticks: int = 0
	while (replay.cursor<replay.frames.size() or not backend.pending_frame.is_empty() or not source.candidate.is_empty()) and ticks<6000:
		await frames(1);ticks += 1
	check("long_replay_complete",replay.cursor==1800 and backend.pending_frame.is_empty(),[ticks,replay.cursor,manager.last_conflict])
	check("merge_split_in_match",backend.logical_metrics.merges>before_merge and backend.logical_metrics.splits>before_split,[backend.logical_metrics.merges-before_merge,backend.logical_metrics.splits-before_split])
	check("no_measured_deep_penetrations",game.penetrations==0,game.penetrations)
	park();driver.queue_free()
	var failures: Array = rows.filter(func(row: Dictionary) -> bool:return not row.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"source":source.metrics.duplicate(true),"backend":backend.get_status(),"floor":floor_node.metrics.duplicate(),"spawn":game.get_node("SafeSpawn").metrics.duplicate(),"penetrations":game.penetrations,"samples":game.samples,"support_transitions":game.support_transitions,"unexpected_support_losses":game.unexpected_support_losses,"update_us":game.update_us.duplicate(),"geometry_update_us":manager.update_us.duplicate(),"human_tested":false}
	var file: FileAccess = FileAccess.open("res://validation/integrated_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
	game.set_meta("integrated_results",result);print("INTEGRATED ",result.passed,"/",result.total," ",failures)
	return result
