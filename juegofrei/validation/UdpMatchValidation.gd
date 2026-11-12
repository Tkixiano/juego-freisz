extends RefCounted
const Protocol = preload("res://scripts/structure_udp/StructureProtocol.gd")
var tree: SceneTree
var game: Node
var sources: Node
var receiver: Node
var gateway: Node
var backend: Node
var manager: Node
var floor_node: Node
var vectors: Dictionary
var rows: Array = []
var p: Node
var q: Node
var driver: Node
func frames(n: int) -> void:
	for i: int in range(n):await tree.physics_frame
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
	game.set_meta("udp_match_progress",name)
	if not ok:push_error("UDP_MATCH "+name+" "+str(detail))
func park() -> void:
	driver.events.clear()
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("p1_") or String(action).begins_with("p2_"):Input.action_release(action)
	for player: Node in [p,q]:player.position = Vector2(100+player.player_id*100,-100);player.velocity = Vector2.ZERO;player.collision_mask = 0;player.set_physics_process(false)
func place(player: Node,pos: Vector2,velocity: Vector2=Vector2.ZERO) -> void:
	player.position = pos;player.velocity = velocity;player.collision_mask = 3;player.set_physics_process(true)
	player.combat.reset_after_respawn();player.combat.respawn_left = 0;player.combat.invulnerability_left = 0
	player.force_update_transform();player.reset_physics_interpolation()
func action(name: String,pressed: bool) -> void:
	var e: InputEventAction = InputEventAction.new();e.action = name;e.pressed = pressed;driver.events.append(e)
func inject(item: Dictionary,reverse: bool=false,partial: bool=false) -> Dictionary:
	var packets: Array = item.packets.duplicate()
	if reverse:packets.reverse()
	if partial:packets.pop_back()
	var result: Dictionary = {}
	for encoded: String in packets:
		result = receiver.protocol.feed(Marshalls.base64_to_raw(encoded),Time.get_ticks_msec())
		if result.get("complete",false):
			# Deterministic wire vectors use synthetic generation/timestamps. Clock
			# substitution here is TEST ONLY; real socket tests measure real clocks.
			var frame: Dictionary = result.snapshot
			frame._rx_usec = Time.get_ticks_usec();frame._validated_usec = frame._rx_usec
			frame._rx_unix_ms = Time.get_unix_time_from_system()*1000;frame.sent_unix_ms = frame._rx_unix_ms
			receiver.snapshot_accepted.emit(frame)
	return result
func send_series(name: String,limit: int=-1) -> void:
	var count: int = 0
	for item: Dictionary in vectors[name]:
		if limit>=0 and count>=limit:break
		inject(item);await frames(4);count += 1
	await frames(8)
func fresh() -> void:
	park();sources.select_mode("OFFLINE");await frames(3)
	backend.request_reset();await frames(3)
	floor_node.set_enabled(true);floor_node.scene_state = "SCENE_EMPTY"
	receiver.protocol = Protocol.new();receiver.protocol.stale_ms = 1000000
	sources.select_mode("UDP");await frames(3)
func run(scene_tree: SceneTree,label: String="headless") -> Dictionary:
	tree = scene_tree;game = tree.current_scene;sources = game.get_node("Sources");receiver = game.get_node("UdpTransport");gateway = game.get_node("SceneSource");backend = game.get_node("Adapter");manager = game.get_node("DynamicGeometry");floor_node = game.get_node("SafetyFloor");p = game.players[0];q = game.players[1]
	vectors = JSON.parse_string(FileAccess.get_file_as_string("res://validation/material_udp_vectors.json"))
	driver = load("res://validation/MaterialPhysicsTestInput.gd").new();game.add_child(driver)
	var shell: Node = game.get_node("GameShell")
	shell.play_button.pressed.emit();shell.selection.choose(0,2);shell.selection.choose(1,3);shell.selection.toggle_ready(0);shell.selection.toggle_ready(1);await frames(5)
	check("startup_offline",sources.mode=="OFFLINE" and not receiver.listening)
	check("selection_preserved",game.selected_characters[0]==game.CharacterCatalog.ENTRIES[2] and game.selected_characters[1]==game.CharacterCatalog.ENTRIES[3])
	receiver.port = 5025
	await fresh();check("switch_offline_udp",receiver.listening and not game.get_node("Replay").is_physics_processing())
	inject(vectors["01_solid"][0],true,true);await frames(3)
	check("incomplete_never_physical",manager.object_ids().is_empty() and receiver.protocol.pending.size()==1)
	receiver.protocol.tick(Time.get_ticks_msec()+1100)
	check("incomplete_expires",receiver.protocol.pending.is_empty())
	inject(vectors["01_solid"][0],true);await frames(4)
	check("fragment_reassembly",receiver.protocol.metrics.accepted==1)
	var rejected: int = receiver.protocol.metrics.rejected
	inject(vectors["01_solid"][0]);check("duplicate_rejected",receiver.protocol.metrics.rejected>rejected)
	inject(vectors["01_solid"][2]);inject(vectors["01_solid"][1]);await frames(4)
	check("out_of_order_rejected",receiver.protocol.rejection_counts.has("duplicate_or_old_sequence"))
	for i: int in range(3,vectors["01_solid"].size()):inject(vectors["01_solid"][i]);await frames(4)
	await frames(8);check("loss_recovery_complete_state",manager.object_ids().size()==1 and receiver.protocol.metrics.gaps>=1)
	check("solid_from_udp",manager.get_body(manager.object_ids()[0]).material_kind=="GREEN_SOLID")
	await send_series("epoch_recovery")
	check("missed_retirement_epoch_recovery",int(backend.ledger.values()[0].epoch)==2,int(backend.ledger.values()[0].epoch))
	var objects: int = manager.object_ids().size()
	var invalid: Dictionary = inject(vectors.invalid[0]);check("invalid_material_rejected",not invalid.get("ok",false) and manager.object_ids().size()==objects)
	check("inactive_offline_port_guard",game.get_node("OfflinePort").submit({}).status=="REJECTED")
	# Source/session boundaries retain the last complete body set.
	sources.select_mode("OFFLINE");await frames(3);check("switch_udp_offline_retains_bodies",not receiver.listening and manager.object_ids().size()==objects)
	sources.select_mode("UDP");await frames(3)
	check("old_source_buffers_invalidated",sources.latest.is_empty() and receiver.protocol.pending.is_empty())
	await send_series("07_three");check("new_session_all_materials",manager.object_ids().size()==3)
	inject(vectors["01_solid"][-1]);check("obsolete_session_rejected",receiver.protocol.rejection_counts.has("obsolete_session"))
	var floor_before: bool = floor_node.enabled
	receiver.protocol.tick(Time.get_ticks_msec()+1000001);await frames(3)
	check("timeout_stale_not_empty",gateway.scene_state=="SCENE_STALE" and manager.object_ids().size()==3 and floor_node.enabled==floor_before)
	await fresh();await send_series("07_three");inject(vectors.error[0]);await frames(3)
	check("producer_error_preserves_geometry",gateway.scene_state=="SCENE_ERROR" and manager.object_ids().size()==3)
	await fresh();await send_series("08_merge");check("merge_via_udp",backend.logical_active.size()==1 and backend.logical_metrics.merges>0)
	await fresh();await send_series("09_split");check("split_via_udp",backend.logical_active.size()==2 and backend.logical_metrics.splits>0)
	await fresh();await send_series("11_hole");check("hole_contract_transported",backend.logical_active.values()[0].regions[0].holes.size()>0)
	await fresh();await send_series("12_corner");check("corner_compound_transported",backend.logical_active.values()[0].regions.size()==2)
	await fresh();await send_series("15_silhouette");check("geometry_update_transported",backend.logical_active.values()[0].geometry_version>1)
	await fresh();await send_series("16_material");check("material_update_transported",manager.get_body(manager.object_ids()[0]).material_kind=="ORANGE_ONE_WAY")
	await fresh();await send_series("17_removal");check("confirmed_empty_floor",gateway.scene_state=="SCENE_EMPTY" and floor_node.enabled and manager.object_ids().is_empty())
	await fresh();await send_series("18_reappearance");check("reappearance",manager.object_ids().size()==1)
	# A floor conflict can be replaced by a newer safe FULL state, never partly applied.
	await fresh();place(p,Vector2(440,560));place(q,Vector2(840,560));await frames(3)
	await send_series("floor_conflict");check("floor_retirement_deferred",floor_node.enabled and not backend.pending_frame.is_empty() and manager.object_ids().is_empty(),manager.last_conflict)
	await send_series("after_conflict");check("newest_state_supersedes_pending",manager.object_ids().size()==1 and backend.pending_frame.is_empty() and sources.metrics.superseded>0)
	await fresh();place(p,Vector2(440,560));place(q,Vector2(840,560));await frames(3)
	await send_series("floor_conflict");sources.select_mode("OFFLINE");await frames(3)
	check("switch_during_pending_safe",backend.pending_frame.is_empty() and floor_node.enabled and manager.object_ids().is_empty())
	# Physical responses use the normal Player/Combat, no test controller.
	await fresh();await send_series("02_bounce");var contact: Node = p.get_node("MaterialContact");var before: int = contact.metrics.bounces
	place(p,Vector2(510,430),Vector2(0,250));await frames(20)
	check("blue_contact_bounce",contact.metrics.bounces==before+1)
	await fresh();await send_series("03_one_way");place(p,Vector2(510,550),Vector2(0,-650));await frames(20)
	check("one_way_passes_below",p.position.y<460,p.position);await frames(65)
	check("one_way_lands",p.is_on_floor())
	var drops: int = contact.metrics.drops;action("p1_down",true);await frames(2);action("p1_down",false);await frames(18)
	check("one_way_drop",contact.metrics.drops==drops+1 and contact.ignored.is_empty())
	await fresh();await send_series("01_solid");place(p,Vector2(490,460));place(q,Vector2(530,460));await frames(4)
	action("p1_right",true);action("p1_dodge",true);await frames(2);check("dash_unchanged",p.combat.horizontal_dash)
	park();place(p,Vector2(490,460));place(q,Vector2(530,460));await frames(3)
	action("p1_jump",true);action("p1_light",true);await frames(2);check("up_attack_unchanged",p.combat.aim==Vector2.UP)
	park();place(p,Vector2(510,390));await frames(2);action("p1_down",true);action("p1_heavy",true);await frames(2);check("down_attack_unchanged",p.combat.is_descending_attack())
	park();place(p,Vector2(490,460));place(q,Vector2(530,460));await frames(3)
	action("p1_light",true);action("p2_light",true);await frames(30);check("two_players_trade_damage",p.combat.damage_model.percent==6 and q.combat.damage_model.percent==6)
	p.combat.damage_model.stocks = 3;game._lose_stock(p);await frames(3);check("respawn_stock_unchanged",p.combat.damage_model.stocks==2 and game.get_node("SafeSpawn").pending.is_empty())
	await fresh()
	var tick: int = 0
	for item: Dictionary in vectors["26_long"]:
		inject(item);await frames(1);tick += 1
	await frames(10)
	check("prolonged_receiver_accepts_all",receiver.protocol.metrics.accepted==vectors["26_long"].size())
	check("bounded_queue",sources.get_status().queue_depth<=2 and sources.metrics.queue_peak<=2)
	check("coalescing_observed",sources.metrics.coalesced+sources.metrics.superseded>0)
	check("no_deep_penetrations",game.penetrations==0,game.penetrations)
	park();driver.queue_free()
	var failed: Array = rows.filter(func(row: Dictionary) -> bool:return not row.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failed.size(),"failures":failed,"rows":rows,"bridge":sources.get_status(),"receiver":receiver.get_status(),"backend":backend.get_status(),"floor":floor_node.metrics.duplicate(true),"penetrations":game.penetrations,"unexpected_support_losses":game.unexpected_support_losses,"synthetic_wire_clock":true,"human_tested":false}
	var file: FileAccess = FileAccess.open("res://validation/udp_match_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
	game.set_meta("udp_match_results",result);print("UDP_MATCH ",result.passed,"/",result.total," ",failed)
	return result
