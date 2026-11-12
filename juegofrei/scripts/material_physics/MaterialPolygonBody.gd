extends "res://scripts/geometry/DynamicPolygonObject.gd"
## A physical region, with a logical owner distinct from its regional identity.
var material_kind: String = "GREEN_SOLID"
var structure_id: String = ""
var region_id: String = ""
var surface_edges: Array = []
var full_resources: Array[ConvexPolygonShape2D] = []
var max_slope_degrees: float = 46.0
var one_way_margin: float = 1.5
var edge_normals: Array[Vector2] = []

func commit_geometry(points: PackedVector2Array,parts: Array[PackedVector2Array],resources: Array[ConvexPolygonShape2D],rings: Array[PackedVector2Array] = []) -> void:
	full_resources.assign(resources)
	super.commit_geometry(points,parts,resources,rings)
	identifier.add_theme_font_size_override("font_size",12)
	identifier.text = region_id+"\n"+material_kind.trim_prefix("GREEN_").trim_prefix("BLUE_").trim_prefix("ORANGE_")
	identifier.tooltip_text = "Estructura: "+structure_id+" / región: "+region_id
	var bounds: Rect2 = Rect2(parts[0][0],Vector2.ZERO)
	for part: PackedVector2Array in parts:
		for point: Vector2 in part: bounds = bounds.expand(point)
	identifier.position = Vector2(bounds.get_center().x-identifier.get_combined_minimum_size().x/2,bounds.end.y+8)
	edge_normals.clear()
	if material_kind!="ORANGE_ONE_WAY": return
	for collider: CollisionShape2D in colliders:
		remove_child(collider);collider.free()
	colliders.clear()
	for edge: PackedVector2Array in surface_edges:
		var direction: Vector2 = edge[1]-edge[0]
		if direction.length()<0.01: continue
		var shape: SegmentShape2D = SegmentShape2D.new()
		shape.a = Vector2(-direction.length()/2,0)
		shape.b = Vector2(direction.length()/2,0)
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = shape
		collider.position = (edge[0]+edge[1])/2
		collider.rotation = direction.angle()
		collider.one_way_collision = true
		collider.one_way_collision_margin = one_way_margin
		edge_normals.append(Vector2(direction.y,-direction.x).normalized())
		add_child(collider);colliders.append(collider)
	update_upper_edges()

func set_enabled(enabled: bool) -> void:
	super.set_enabled(enabled)
	collision_layer = (2 if material_kind=="ORANGE_ONE_WAY" else 1) if enabled else 0

func update_upper_edges() -> void:
	if material_kind!="ORANGE_ONE_WAY": return
	for i: int in range(colliders.size()):
		colliders[i].disabled = not collision_enabled or edge_normals[i].rotated(global_rotation).dot(Vector2.UP)<cos(deg_to_rad(max_slope_degrees))

func overlaps_character(shape: Shape2D,pose: Transform2D) -> bool:
	for part: ConvexPolygonShape2D in full_resources:
		if part.collide(global_transform,shape,pose): return true
	return false
