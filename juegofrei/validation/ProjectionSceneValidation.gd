extends RefCounted

func run(tree: SceneTree) -> void:
	var root: Node = tree.current_scene
	var checks: Dictionary = {}
	checks["no_combat_or_udp_nodes"] = root.find_children("*","CharacterBody2D",true,false).is_empty() and root.get_node_or_null("ExternalPlatformReceiver")==null
	checks["monitor_list_matches_display_server"] = root.screen_selector.item_count==DisplayServer.get_screen_count()
	checks["pattern_texture_has_known_canvas"] = root.pattern_rect.texture.get_size()==Vector2(1280,720)
	root.preview_button.pressed.emit()
	for i: int in range(5):
		await tree.process_frame
	checks["preview_button_opens_output"] = root.output.visible and root.output.mode==Window.MODE_WINDOWED
	var image: Image = root.output.get_texture().get_image()
	checks["rendered_output_available"] = image!=null and not image.is_empty()
	if image!=null and not image.is_empty():
		image.save_png("res://validation/projection_render.png")
	root.fullscreen_button.pressed.emit()
	for i: int in range(5):
		await tree.process_frame
	checks["fullscreen_on_selected_monitor"] = root.output.visible and root.output.mode==Window.MODE_FULLSCREEN and root.output.current_screen==root.selected_screen
	checks["aspect_and_resolution_match_game"] = root.output.content_scale_size==Vector2i(1280,720) and root.output.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP
	root.close_button.pressed.emit()
	checks["cancel_hides_output_without_changing_main_scene"] = not root.output.visible and tree.current_scene==root
	var passed: int = 0
	for value: bool in checks.values():
		if value:
			passed += 1
	var report: Dictionary = {"total":checks.size(),"passed":passed,"checks":checks}
	var file: FileAccess = FileAccess.open("res://validation/projection_scene_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	root.set_meta("projection_scene_results",report)
