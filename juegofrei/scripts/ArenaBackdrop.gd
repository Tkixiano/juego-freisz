extends Node2D
## Static geometry is cached by CanvasItem; no per-frame node allocations.
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#101724"))
	for x: int in range(0, 1281, 40):
		draw_line(Vector2(x, 110), Vector2(x, 650), Color("#192335"), 1.0)
	for y: int in range(130, 651, 40):
		draw_line(Vector2(0, y), Vector2(1280, y), Color("#192335"), 1.0)
	draw_circle(Vector2(640, 345), 195.0, Color("#141e2e"))
	draw_arc(Vector2(640, 345), 195.0, 0.0, TAU, 96, Color("#25344a"), 1.0)
	draw_line(Vector2(640, 150), Vector2(640, 610), Color("#25344a"), 1.0)
	draw_line(Vector2(60, 666), Vector2(1220, 666), Color("#c66768"), 1.0)
