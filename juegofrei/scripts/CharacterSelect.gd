extends Control
const Catalog = preload("res://scripts/CharacterCatalog.gd")
const PreviewScene = preload("res://scenes/CharacterAppearance.tscn")
signal completed(pair: Array[Resource])
signal back_requested
var choices: Array[int] = [0,1]
var ready_flags: Array[bool] = [false,false]
var cards: Array[Array] = [[],[]]
var ready_buttons: Array[Button] = []
var previews: Array[Node2D] = []
var portraits: Array[TextureRect] = []
var captions: Array[Label] = []
var back_button: Button
var status: Label
var _start_pending: bool = false

func _label(text: String,point: Vector2,size: Vector2,font_size: int=20) -> Label:
	var label: Label = Label.new()
	label.text = text;label.position = point;label.size = size
	label.add_theme_font_size_override("font_size",font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(text: String,point: Vector2,size: Vector2) -> Button:
	var button: Button = Button.new()
	button.text = text;button.position = point;button.size = size
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label("ELEGÍ TU PERSONAJE",Vector2(100,45),Vector2(1080,55),36)
	_label("Provisionales · mismas estadísticas y mecánicas · pueden repetir personaje",Vector2(100,108),Vector2(1080,30),18)
	for slot: int in range(2):
		var x: float = 65+slot*620
		_label("JUGADOR %d"%(slot+1),Vector2(x,165),Vector2(530,40),25)
		var preview: Node2D = PreviewScene.instantiate()
		add_child(preview);preview.position = Vector2(x+265,265);preview.scale = Vector2(2,2)
		previews.append(preview)
		var portrait: TextureRect = TextureRect.new()
		portrait.position = Vector2(x+215,215);portrait.size = Vector2(100,100)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait);portraits.append(portrait)
		captions.append(_label("",Vector2(x,320),Vector2(530,36),24))
		for index: int in range(Catalog.ENTRIES.size()):
			var button: Button = _button(Catalog.ENTRIES[index].display_name,Vector2(x+(index%2)*270,375+(index/2)*55),Vector2(260,45))
			button.modulate = Catalog.ENTRIES[index].accent.lightened(0.3)
			button.pressed.connect(choose.bind(slot,index))
			cards[slot].append(button)
		var ready_button: Button = _button("LISTO",Vector2(x+50,505),Vector2(430,48))
		ready_button.pressed.connect(toggle_ready.bind(slot))
		ready_buttons.append(ready_button)
	status = _label("",Vector2(80,565),Vector2(1120,32),18)
	back_button = _button("Volver al menú principal",Vector2(450,610),Vector2(380,42))
	back_button.pressed.connect(func()->void:back_requested.emit())
	_label("J1  A/D: elegir · F: listo · H: cancelar     |     J2  ←/→: elegir · K: listo · Shift der.: cancelar",Vector2(30,675),Vector2(1220,28),16)
	_refresh()

func open(pair: Array[Resource]) -> void:
	for slot: int in range(2):
		var found: int = Catalog.ENTRIES.find(pair[slot])
		choices[slot] = maxi(0,found)
	ready_flags.assign([false,false])
	_start_pending = false
	_refresh()

func choose(slot: int,index: int) -> void:
	if slot<0 or slot>1 or index<0 or index>=Catalog.ENTRIES.size() or ready_flags[slot]: return
	choices[slot] = index
	_refresh()

func toggle_ready(slot: int) -> void:
	if slot<0 or slot>1: return
	ready_flags[slot] = not ready_flags[slot]
	_refresh()
	if ready_flags[0] and ready_flags[1] and not _start_pending:
		_start_pending = true
		call_deferred("start_if_ready")

func start_if_ready() -> void:
	_start_pending = false
	if is_visible_in_tree() and ready_flags[0] and ready_flags[1]:
		var pair: Array[Resource] = [Catalog.ENTRIES[choices[0]],Catalog.ENTRIES[choices[1]]]
		completed.emit(pair)

func _refresh() -> void:
	if ready_buttons.size()!=2: return
	for slot: int in range(2):
		var definition: Resource = Catalog.ENTRIES[choices[slot]]
		previews[slot].configure(definition)
		portraits[slot].texture = definition.portrait
		portraits[slot].visible = definition.portrait!=null
		previews[slot].visible = definition.portrait==null
		captions[slot].text = definition.display_name+ (" · LISTO" if ready_flags[slot] else "")
		ready_buttons[slot].text = "Cancelar LISTO" if ready_flags[slot] else "LISTO J%d"%(slot+1)
		ready_buttons[slot].modulate = Color("#85f0bd") if ready_flags[slot] else Color.WHITE
		for index: int in range(cards[slot].size()):
			cards[slot][index].disabled = ready_flags[slot]
			cards[slot][index].text = ("● " if choices[slot]==index else "")+Catalog.ENTRIES[index].display_name
	status.text = "Esperando confirmación de ambos jugadores" if not (ready_flags[0] and ready_flags[1]) else "¡Ambos listos!"

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.echo:
		get_viewport().set_input_as_handled()
		return
	for slot: int in range(2):
		var prefix: String = "p%d_"%(slot+1)
		if event.is_action_pressed(prefix+"left") or event.is_action_pressed(prefix+"right"):
			var delta: int = -1 if event.is_action_pressed(prefix+"left") else 1
			choose(slot,posmod(choices[slot]+delta,Catalog.ENTRIES.size()))
			get_viewport().set_input_as_handled();return
		if event.is_action_pressed(prefix+"light"):
			if not ready_flags[slot]:toggle_ready(slot)
			get_viewport().set_input_as_handled();return
		if event.is_action_pressed(prefix+"dodge"):
			if ready_flags[slot]:toggle_ready(slot)
			get_viewport().set_input_as_handled();return
	if event.is_action_pressed("game_pause"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
