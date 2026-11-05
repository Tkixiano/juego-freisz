extends Node2D
## Bounded geometric impact pool; effects never create scene nodes.
@export var maximum_bursts: int = 16
var bursts: Array[Dictionary] = []

func _ready() -> void:
	set_process(false)

func burst(point: Vector2, color: Color) -> void:
	set_process(true)
	if bursts.size() >= maximum_bursts:
		bursts.pop_front()
	bursts.append({"point":point,"color":color,"age":0.0})

func _process(delta: float) -> void:
	for i: int in range(bursts.size()-1,-1,-1):
		bursts[i]["age"] += delta
		if bursts[i]["age"] > 0.30:
			bursts.remove_at(i)
	queue_redraw()
	if bursts.is_empty():
		set_process(false)

func _draw() -> void:
	for effect: Dictionary in bursts:
		var t: float = float(effect["age"])/0.30
		var point: Vector2 = effect["point"]
		var color: Color = effect["color"]
		color.a = 1.0-t
		draw_arc(point,12+45*t,0,TAU,20,color,2.5,true)
		for i: int in range(8):
			var direction: Vector2 = Vector2.RIGHT.rotated(i*TAU/8.0)
			var center: Vector2 = point+direction*(10+70*t)
			draw_rect(Rect2(center-Vector2.ONE*3,Vector2.ONE*6),color)
