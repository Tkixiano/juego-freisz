extends RefCounted

func run(tree: SceneTree) -> void:
	var game: Node=tree.current_scene
	game.set_meta("integration_progress","udp_second_pass")
	var udp: RefCounted=load("res://validation/ExternalInputValidation.gd").new()
	await udp.run(tree,"final")
	game.set_meta("integration_progress","full_regression")
	var regression: RefCounted=load("res://validation/FullRegression.gd").new()
	await regression.run_all(tree,"udp_final")
	var udp_result: Dictionary=game.get_meta("udp_results")
	var full_result: Dictionary=game.get_meta("full_results")
	var report: Dictionary={"udp_total":udp_result.total,"udp_passed":udp_result.passed,"udp_failed":udp_result.failed,"regression_total":full_result.total,"regression_passed":full_result.passed,"regression_failed":full_result.failed,"engine":Engine.get_version_info()["string"]}
	var file: FileAccess=FileAccess.open("res://validation/external_integration_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("integration_results",report)
	game.set_meta("integration_progress","complete")
