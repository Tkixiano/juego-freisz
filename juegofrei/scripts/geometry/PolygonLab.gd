extends Node2D
## Synthetic-only independent scene. F5 sequence / F6 fixture reset, no device I/O.
const Manager = preload("res://scripts/geometry/DynamicGeometryManager.gd")
static var CONVEX: PackedVector2Array = PackedVector2Array([Vector2(-115,-8),Vector2(-65,-28),Vector2(65,-28),Vector2(115,-8),Vector2(100,35),Vector2(-100,35)])
static var CONCAVE: PackedVector2Array = PackedVector2Array([Vector2(-110,-35),Vector2(-30,-35),Vector2(-30,10),Vector2(30,10),Vector2(30,-35),Vector2(110,-35),Vector2(110,50),Vector2(-110,50)])
static var TRIANGLE: PackedVector2Array = PackedVector2Array([Vector2(-100,40),Vector2(0,-30),Vector2(110,40)])
@onready var geometry: Manager = $DynamicGeometry
@onready var player: CharacterBody2D = $Player
@onready var status: Label = $UI/Status
var sequence_running: bool = false
var sequence_time: float = 0.0
var sequence_step: int = -1

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#101c2b"))
	reset_fixture()

func reset_fixture() -> void:
	sequence_running = false
	sequence_time = 0.0
	sequence_step = -1
	for id: StringName in geometry.object_ids():
		geometry.remove_object(id)
	# Creation after the queued removals; no immediate physics mutations.
	call_deferred("_create_after_removals")
	player.spawn_position = Vector2(270,210)
	player.respawn()
	status.text = "FASE 1A · DATOS SINTÉTICOS · StaticBody2D\nA/D, W/S: movimiento original · F5: secuencia reproducible · F6: reiniciar laboratorio\nVerde A y verde C: mismo color, IDs distintos. Azul B: cóncavo; las líneas internas muestran partes convexas."

func _create_after_removals() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	geometry.create_object(&"green_A",CONVEX,Vector2(270,400),0,Color("#35c99a"))
	geometry.create_object(&"blue_B",CONCAVE,Vector2(650,410),0,Color("#418eee"))
	geometry.create_object(&"green_C",TRIANGLE,Vector2(1020,360),0,Color("#35c99a"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F5:
			sequence_running = true
			sequence_time = 0.0
			sequence_step = -1
		elif event.keycode==KEY_F6:
			reset_fixture()

func _physics_process(delta: float) -> void:
	if player.position.y>820:
		player.respawn()
	if not sequence_running:
		return
	sequence_time += delta
	var step: int = int(sequence_time/2.5)
	if step==sequence_step:
		return
	sequence_step = step
	match step:
		0:
			geometry.update_transform(&"green_A",Vector2(350,400),0)
		1:
			geometry.update_transform(&"green_A",Vector2(350,350),0)
			geometry.update_transform(&"blue_B",Vector2(670,410),0.20)
		2:
			geometry.update_transform(&"green_A",Vector2(350,410),0)
			geometry.assign_polygon(&"green_C",CONCAVE)
		3:
			geometry.set_collision_enabled(&"green_C",false)
		4:
			geometry.remove_object(&"green_C")
		5:
			sequence_running = false
			status.text += "\nSecuencia terminada: movimiento, rotación, nueva silueta, desactivación y eliminación. F6 restaura."

func _draw() -> void:
	for x: int in range(0,1281,40):
		draw_line(Vector2(x,100),Vector2(x,650),Color(0.2,0.35,0.5,0.2))
	for y: int in range(100,651,40):
		draw_line(Vector2(0,y),Vector2(1280,y),Color(0.2,0.35,0.5,0.2))
