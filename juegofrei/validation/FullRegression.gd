extends RefCounted
var groups: Dictionary = {}

func run_all(tree: SceneTree, label: String) -> void:
	var game: Node=tree.current_scene
	game.set_meta("full_progress","qa")
	var audit: RefCounted=load("res://validation/QAAudit.gd").new()
	await audit.run_all(tree)
	groups["qa"]=game.get_meta("qa_results")
	game.set_meta("full_progress","functional")
	var functional: RefCounted=load("res://validation/FunctionalAudit.gd").new()
	await functional.run_all(tree,label)
	groups["functional"]=game.get_meta("functional_results")
	game.set_meta("full_progress","player2")
	var movement: RefCounted=load("res://validation/MovementValidation.gd").new()
	game.restart_match()
	var rows: Array=await movement.run(tree,2)
	var failures: Array=rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	groups["player2"]={"total":rows.size(),"passed":rows.size()-failures.size(),"failed":failures.size(),"failures":failures,"results":rows}
	game.set_meta("full_progress","controlled_fall")
	game.restart_match()
	var fall: RefCounted=load("res://validation/ControlledFallValidation.gd").new()
	await fall.run(tree)
	var file: FileAccess=FileAccess.open("res://validation/controlled_fall_results.json",FileAccess.READ)
	var fall_report: Dictionary=JSON.parse_string(file.get_as_text())
	var fall_rows: Array=[]
	for checks: Array in fall_report.values():
		fall_rows.append_array(checks)
	var fall_failures: Array=fall_rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	groups["controlled_fall"]={"total":fall_rows.size(),"passed":fall_rows.size()-fall_failures.size(),"failed":fall_failures.size(),"failures":fall_failures,"results":fall_rows}
	file.close()
	var total: int=0
	var passed: int=0
	for group: Dictionary in groups.values():
		total+=int(group.total)
		passed+=int(group.passed)
	var report: Dictionary={"label":label,"total":total,"passed":passed,"failed":total-passed,"groups":groups}
	file=FileAccess.open("res://validation/full_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	game.set_meta("full_results",report)
	game.set_meta("full_progress","complete")
	game.restart_match()
