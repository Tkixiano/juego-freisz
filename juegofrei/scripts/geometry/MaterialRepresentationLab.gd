extends Node2D
## Diagnostic drawing of offline material partitions. ZERO collision bodies.
var cases: Array = []
var font: Font = ThemeDB.fallback_font
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("101925"))
	var file: FileAccess = FileAccess.open("res://validation/material_contract_fixtures.json",FileAccess.READ)
	if file!=null:
		var fixtures: Dictionary = JSON.parse_string(file.get_as_text())
		for index: int in [6,8,11,12,13,14]: cases.append(fixtures.cases[index])
	queue_redraw()
func _draw() -> void:
	draw_string(font,Vector2(40,38),"FASE 3B.1 · REGIONES DE MATERIAL · DATOS SINTÉTICOS",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color.WHITE)
	draw_string(font,Vector2(40,65),"Sin cuerpos físicos, sin UDP, sin cámara. Verde: SOLID · Azul: BOUNCE · Naranja: ONE_WAY (solo representación)",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.LIGHT_GRAY)
	for i: int in range(cases.size()):
		var offset: Vector2 = Vector2(80+(i%3)*390,110+floori(float(i)/3)*280)
		var c: Dictionary = cases[i]
		draw_string(font,offset+Vector2(0,-5),c.name,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
		for structure: Dictionary in c.structures:
			var pose: Vector2 = Vector2(float(structure.position[0]),float(structure.position[1]))+offset
			for material: Dictionary in structure.material_regions:
				var color: Color = Color("49d772") if material.material=="GREEN_SOLID" else (Color("438cff") if material.material=="BLUE_BOUNCE" else Color("ff9d36"))
				for part: Array in material.convex_parts:
					var points: PackedVector2Array = []
					for point: Array in part: points.append(Vector2(float(point[0]),float(point[1]))+pose)
					draw_colored_polygon(points,color)
				var first: Array = material.regions[0].exterior[0]
				draw_string(font,pose+Vector2(float(first[0]),float(first[1]))+Vector2(2,14),material.region_id,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
