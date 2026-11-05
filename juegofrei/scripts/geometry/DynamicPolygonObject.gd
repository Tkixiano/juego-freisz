extends StaticBody2D
## Mutated only by DynamicGeometryManager on physics ticks, never query callbacks.
var object_id: StringName
var polygon: PackedVector2Array = []
var convex_parts: Array[PackedVector2Array] = []
var geometry_revision: int = 0
var shape_builds: int = 0
var surface_radius: float = 1.0
var collision_enabled: bool = true
var tint: Color = Color.WHITE
var display_parts: bool = true
var visual: Polygon2D
var identifier: Label
var colliders: Array[CollisionShape2D] = []
var outlines: Array[PackedVector2Array] = []

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	visual = Polygon2D.new()
	visual.name = "Silhouette"
	visual.show_behind_parent = true
	add_child(visual)
	identifier = Label.new()
	identifier.name = "ObjectID"
	identifier.add_theme_font_size_override("font_size",15)
	identifier.add_theme_color_override("font_color",Color.WHITE)
	add_child(identifier)

func commit_geometry(points: PackedVector2Array,parts: Array[PackedVector2Array],resources: Array[ConvexPolygonShape2D],rings: Array[PackedVector2Array] = []) -> void:
	# Construct the replacements before removing the previous valid shape set.
	var replacements: Array[CollisionShape2D] = []
	for resource: ConvexPolygonShape2D in resources:
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = resource
		replacements.append(collider)
	for collider: CollisionShape2D in colliders:
		remove_child(collider)
		collider.free()
	colliders = replacements
	for collider: CollisionShape2D in colliders:
		add_child(collider)
	polygon = points.duplicate()
	convex_parts.assign(parts)
	outlines.assign(rings)
	geometry_revision += 1
	shape_builds += 1
	surface_radius = 1.0
	var bottom: float = -INF
	for part: PackedVector2Array in parts:
		for point: Vector2 in part:
			surface_radius = maxf(surface_radius,point.length())
			bottom = maxf(bottom,point.y)
	visual.polygon = polygon
	visual.visible = outlines.is_empty()
	identifier.position = Vector2(-55,bottom+8)
	identifier.text = String(object_id)
	set_enabled(collision_enabled)
	queue_redraw()

func set_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	collision_layer = 1 if enabled else 0
	visual.color = tint if enabled else Color(tint,0.2)
	if not enabled:
		constant_linear_velocity = Vector2.ZERO
		constant_angular_velocity = 0.0
	queue_redraw()

func _draw() -> void:
	if polygon.is_empty():
		return
	if not outlines.is_empty():
		for part: PackedVector2Array in convex_parts:
			draw_colored_polygon(part,tint if collision_enabled else Color(tint,0.2))
	var boundaries: Array[PackedVector2Array] = outlines.duplicate()
	if boundaries.is_empty():
		boundaries.append(polygon)
	for ring: PackedVector2Array in boundaries:
		var outline: PackedVector2Array = ring.duplicate()
		outline.append(ring[0])
		draw_polyline(outline,Color.WHITE if collision_enabled else Color(1,1,1,0.3),2.0)
	if display_parts:
		for part: PackedVector2Array in convex_parts:
			var boundary: PackedVector2Array = part.duplicate()
			boundary.append(part[0])
			draw_polyline(boundary,Color(0,0,0,0.35),1.0)
