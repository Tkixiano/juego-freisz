extends RefCounted
## Records the real PacketPeerUDP receiver while an independent Python process sends.
var observations: Array[Dictionary] = []
var rows: Array[Dictionary] = []
func check(name: String,ok: bool) -> void: rows.append({"name":name,"passed":ok})
func run(tree: SceneTree,label: String,duration: float) -> void:
	var receiver: Node = tree.current_scene.get_node("Receiver")
	var Protocol = load("res://scripts/structure_udp/StructureProtocol.gd")
	receiver.protocol = Protocol.new()
	receiver.protocol.max_sender_age_ms = receiver.max_sender_age_ms
	receiver.tick_cost_us.clear()
	var until: int = Time.get_ticks_msec()+int(duration*1000)
	var seen_states: Dictionary = {}
	var seen_sequences: Dictionary = {}
	var read: int = -1
	while Time.get_ticks_msec()<until:
		await tree.create_timer(0.05).timeout
		var state: String = receiver.protocol.scene_state
		seen_states[state] = true
		if receiver.protocol.last_received_ms!=read or observations.is_empty() or observations[-1].state!=state:
			read = receiver.protocol.last_received_ms
			var key: String = receiver.protocol.session_id
			if key!="":
				var prior: int = int(seen_sequences.get(key,0))
				check("sequence_never_rewinds",receiver.protocol.sequence>=prior)
				seen_sequences[key] = receiver.protocol.sequence
			observations.append({"state":state,"objects":receiver.protocol.active.size(),"session":key,"sequence":receiver.protocol.sequence,"at":Time.get_ticks_msec()})
	var status: Dictionary = receiver.get_status()
	check("receiver_bound",receiver.listening)
	check("received_python",status.metrics.accepted>0)
	check("no_physical_manager",tree.current_scene.get_node_or_null("DynamicGeometry")==null)
	check("bounded_pending",status.pending_messages<=receiver.protocol.max_pending)
	check("bounded_reserved",status.reserved_bytes<=receiver.protocol.memory_limit)
	if label.begins_with("faults"):
		for state: String in ["SCENE_ACTIVE","SCENE_EMPTY","SCENE_STALE","SCENE_ERROR"]:
			check("observed_"+state,seen_states.has(state))
		check("new_session_accepted",status.metrics.sessions==2)
		check("merge_event_received",status.metrics.merges==1)
		check("split_event_received",status.metrics.splits==1)
		check("incomplete_expired",status.metrics.expired>=1)
		check("obsolete_session_rejected",status.rejections.has("obsolete_session"))
		check("duplicate_rejected",status.rejections.has("duplicate_or_old_sequence"))
		check("final_state_recovered",status.objects==2 and status.sequence==7)
		check("timeout_preserves_snapshot",status.scene_state=="SCENE_STALE" and receiver.protocol.last_snapshot.scene_state=="SCENE_ACTIVE")
	if label.begins_with("prolonged"):
		check("all_confirmed_source_states_received",status.metrics.accepted==3598 and status.sequence==3598)
		check("no_network_gaps",status.metrics.gaps==0)
		check("no_unexpected_rejections",status.metrics.rejected==0)
		check("all_merge_events",status.metrics.merges==30)
		check("all_split_events",status.metrics.splits==29)
		check("one_session",status.metrics.sessions==1)
	var failures: Array = rows.filter(func(r: Dictionary) -> bool: return not r.passed)
	var result: Dictionary = {"label":label,"passed":rows.size()-failures.size(),"total":rows.size(),"failures":failures,"observations":observations,"seen_states":seen_states,"status":status}
	var out: FileAccess = FileAccess.open("res://validation/structure_udp_"+label+".json",FileAccess.WRITE)
	out.store_string(JSON.stringify(result,"  "))
	tree.current_scene.set_meta("structure_udp_result",result)
	print("STRUCTURE_UDP_INTEGRATION ",label," ",result.passed,"/",result.total)
