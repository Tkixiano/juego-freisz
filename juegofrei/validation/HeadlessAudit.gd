extends SceneTree
var failures: Array[String] = []
var loaded: int = 0

func _initialize() -> void:
	call_deferred("_audit")

func _scan(directory: String) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() in ["gd","tscn","tres"]:
			var path: String = directory.path_join(file)
			var resource: Resource = load(path)
			loaded += 1
			if resource == null or (resource is GDScript and not (resource as GDScript).can_instantiate()):
				failures.append(path)
	for child: String in DirAccess.get_directories_at(directory):
		_scan(directory.path_join(child))

func _audit() -> void:
	for directory: String in ["res://scripts","res://scenes","res://resources","res://validation"]:
		_scan(directory)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	if not paused or main.get_node("GameShell").page != 0:
		failures.append("Main menu did not initialize")
	main.restart_match()
	for i: int in range(5):
		await physics_frame
	if main.players.size()!=2 or main.get_node("PlatformManager").platforms.size()!=3:
		failures.append("Missing players/platforms")
	var report: Dictionary = {"engine":Engine.get_version_info()["string"],"loaded_resources":loaded,"failures":failures,"passed":failures.is_empty(),"mode":"headless load, parse, instantiate and physics startup"}
	var file: FileAccess = FileAccess.open("res://validation/headless_qa.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("HEADLESS_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)