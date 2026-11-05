extends Control
## Dedicated scene: no fighters, platform manager, input receiver or combat.
const CANVAS_SIZE: Vector2i = Vector2i(1280,720)
var screen_selector: OptionButton
var status: Label
var output: Window
var preview_button: Button
var fullscreen_button: Button
var close_button: Button
var pattern_rect: TextureRect
var selected_screen: int = 0

func _ready() -> void:
	get_viewport().gui_embed_subwindows = false
	get_window().title = "Calibración de proyección · operador"
	var column: VBoxContainer = VBoxContainer.new()
	column.position = Vector2(36,36)
	column.custom_minimum_size = Vector2(800,0)
	add_child(column)
	var title: Label = Label.new()
	title.text = "CALIBRACIÓN CÁMARA → PROYECCIÓN"
	title.add_theme_font_size_override("font_size",28)
	column.add_child(title)
	screen_selector = OptionButton.new()
	for index: int in range(DisplayServer.get_screen_count()):
		var screen_size: Vector2i = DisplayServer.screen_get_size(index)
		screen_selector.add_item("Monitor %d · %d × %d · posición %s" % [index,screen_size.x,screen_size.y,str(DisplayServer.screen_get_position(index))],index)
	column.add_child(screen_selector)
	screen_selector.item_selected.connect(_select_screen)
	preview_button = _button(column,"Mostrar patrón en ventana",show_preview)
	fullscreen_button = _button(column,"Mostrar patrón en pantalla completa",show_fullscreen)
	close_button = _button(column,"Ocultar patrón / cancelar salida",hide_output)
	_button(column,"Salir de calibración",func() -> void: get_tree().quit())
	status = Label.new()
	status.text = "Lienzo 1280 × 720, aspecto conservado.\nFIT: IDs 10–13. Verificación independiente: 14–17.\nEl rectángulo gris delimita centros permitidos de plataformas.\nUsá Python para detectar, verificar error y guardar; aquí no se modifica la homografía."
	column.add_child(status)
	output = Window.new()
	output.title = "Patrón de proyección · 1280 × 720"
	output.size = CANVAS_SIZE
	output.content_scale_size = CANVAS_SIZE
	output.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	output.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	output.close_requested.connect(hide_output)
	add_child(output)
	pattern_rect = TextureRect.new()
	pattern_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pattern_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pattern_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pattern_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	output.add_child(pattern_rect)
	var image: Image = Image.new()
	var error: Error = image.load("res://calibration/projector_pattern.png")
	if error == OK:
		pattern_rect.texture = ImageTexture.create_from_image(image)
	else:
		status.text += "\nFalta patrón: ejecutá python -m vision.projector_calibration --generate-pattern"
		preview_button.disabled = true
		fullscreen_button.disabled = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--projection-screen="):
			var value: String = argument.get_slice("=",1)
			if value.is_valid_int() and int(value)>=0 and int(value)<DisplayServer.get_screen_count():
				selected_screen = int(value)
				screen_selector.select(selected_screen)
				call_deferred("show_fullscreen")
			else:
				status.text += "\nMonitor solicitado no disponible; seleccioná uno de la lista."

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _select_screen(index: int) -> void:
	selected_screen = screen_selector.get_item_id(index)
	if output.visible:
		show_fullscreen()

func show_preview() -> void:
	if preview_button.disabled:
		return
	output.mode = Window.MODE_WINDOWED
	output.current_screen = selected_screen
	output.size = Vector2i(960,540)
	output.position = DisplayServer.screen_get_position(selected_screen)+Vector2i(120,160)
	output.show()

func show_fullscreen() -> void:
	if fullscreen_button.disabled or selected_screen<0 or selected_screen>=DisplayServer.get_screen_count():
		return
	output.mode = Window.MODE_WINDOWED
	output.current_screen = selected_screen
	output.position = DisplayServer.screen_get_position(selected_screen)
	output.show()
	output.mode = Window.MODE_FULLSCREEN

func hide_output() -> void:
	output.hide()
