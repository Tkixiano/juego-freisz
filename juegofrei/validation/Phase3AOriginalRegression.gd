extends RefCounted
## Exercises the original game; the structure receiver is deliberately absent.
func run(tree: SceneTree) -> void:
	var game: Node = tree.current_scene
	var full: RefCounted = load("res://validation/FullRegression.gd").new()
	await full.run_all(tree,"phase3a")
	var characters: RefCounted = load("res://validation/Phase2BValidation.gd").new()
	var selection_result: Dictionary = await characters.run(tree,"phase3a")
	var udp: RefCounted = load("res://validation/ExternalInputValidation.gd").new()
	await udp.run(tree,"phase3a")
	var result: Dictionary = {"full":game.get_meta("full_results"),"selection":selection_result,"udp":game.get_meta("udp_results"),"structure_receiver_absent":game.get_node_or_null("StructureUdpReceiver")==null}
	var file: FileAccess = FileAccess.open("res://validation/phase3a_original_regression.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	game.set_meta("phase3a_original_regression",result)
	print("PHASE3A_ORIGINAL_COMPLETE")
