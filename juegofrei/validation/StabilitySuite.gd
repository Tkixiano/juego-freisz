extends RefCounted

func run(tree: SceneTree) -> void:
	var game: Node=tree.current_scene
	for key: String in ["stability_stream_results","vision_udp_results"]:
		if game.has_meta(key):
			game.remove_meta(key)
	game.add_child(load("res://validation/VisionIntegrationValidation.gd").new())
	game.add_child(load("res://validation/StabilityStreamValidation.gd").new())
	game.set_meta("stability_progress","image_stream")
	while not game.has_meta("stability_stream_results"):
		await tree.process_frame
	game.get_node("PlatformManager").set_control_mode(0)
	game.set_meta("stability_progress","udp_and_game_regression")
	var regression: RefCounted=load("res://validation/ExternalIntegrationRegression.gd").new()
	await regression.run(tree)
	var report: Dictionary={"stream":game.get_meta("stability_stream_results"),"vision":game.get_meta("vision_udp_results",{}),"regression":game.get_meta("integration_results")}
	var file: FileAccess=FileAccess.open("res://validation/stability_suite_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("stability_progress","complete")
