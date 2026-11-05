extends CanvasLayer
enum Page { MAIN, PLAYING, PAUSED, CONTROLS }
var page: Page = Page.MAIN
var return_page: Page = Page.MAIN
@onready var screen: ColorRect = $Screen
@onready var title: Label = $Screen/Title
@onready var controls: Label = $Screen/ControlsText
@onready var play_button: Button = $Screen/Play
@onready var controls_button: Button = $Screen/Controls
@onready var restart_button: Button = $Screen/Restart
@onready var menu_button: Button = $Screen/MainMenu
@onready var back_button: Button = $Screen/Back

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	play_button.pressed.connect(_on_play)
	controls_button.pressed.connect(show_controls)
	restart_button.pressed.connect(_restart)
	menu_button.pressed.connect(show_main_menu)
	back_button.pressed.connect(back)
	show_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_pause"):
		if page == Page.PLAYING:
			show_pause()
		elif page == Page.PAUSED:
			enter_game()
		elif page == Page.CONTROLS:
			back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("show_controls"):
		if page == Page.CONTROLS:
			back()
		else:
			show_controls()
		get_viewport().set_input_as_handled()

func _stop_drag() -> void:
	var mouse: Node = get_parent().get_node_or_null("MousePlatformController")
	if mouse != null:
		mouse.set("dragging", false)

func show_main_menu() -> void:
	_stop_drag()
	page = Page.MAIN
	get_tree().paused = true
	_render()

func show_pause() -> void:
	_stop_drag()
	page = Page.PAUSED
	get_tree().paused = true
	_render()

func enter_game() -> void:
	page = Page.PLAYING
	get_tree().paused = false
	_render()

func show_controls() -> void:
	_stop_drag()
	return_page = page
	page = Page.CONTROLS
	get_tree().paused = true
	_render()

func back() -> void:
	page = return_page
	get_tree().paused = page != Page.PLAYING
	_render()

func _on_play() -> void:
	if page == Page.MAIN:
		_restart()
	else:
		enter_game()

func _restart() -> void:
	get_parent().call("restart_match")

func _render() -> void:
	screen.visible = page != Page.PLAYING
	$Hint.visible = page == Page.PLAYING
	title.text = "CUBOS / ARENA" if page == Page.MAIN else ("CONTROLES" if page == Page.CONTROLS else "PAUSA")
	controls.visible = page == Page.CONTROLS
	play_button.visible = page == Page.MAIN or page == Page.PAUSED
	play_button.text = "Jugar" if page == Page.MAIN else "Continuar"
	controls_button.visible = page == Page.MAIN or page == Page.PAUSED
	restart_button.visible = page == Page.PAUSED
	menu_button.visible = page == Page.PAUSED
	back_button.visible = page == Page.CONTROLS
	if page == Page.CONTROLS:
		back_button.grab_focus()
	elif page != Page.PLAYING:
		play_button.grab_focus()
	else:
		get_viewport().gui_release_focus()
