extends RefCounted
## Simple, finite, ordered polygon. Holes/multiple rings are not accepted.

static func signed_area(points: PackedVector2Array) -> float:
	var result: float = 0.0
	for i: int in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i+1)%points.size()]
		result += float(a.x)*b.y-float(b.x)*a.y
	return result*0.5

static func _on_segment(a: Vector2,b: Vector2,p: Vector2,epsilon: float) -> bool:
	return absf((b-a).cross(p-a))<=epsilon*maxf(1.0,(b-a).length()) and p.x>=minf(a.x,b.x)-epsilon and p.x<=maxf(a.x,b.x)+epsilon and p.y>=minf(a.y,b.y)-epsilon and p.y<=maxf(a.y,b.y)+epsilon

static func _intersects(a: Vector2,b: Vector2,c: Vector2,d: Vector2,epsilon: float) -> bool:
	if _on_segment(a,b,c,epsilon) or _on_segment(a,b,d,epsilon) or _on_segment(c,d,a,epsilon) or _on_segment(c,d,b,epsilon):
		return true
	return ((b-a).cross(c-a)*(b-a).cross(d-a)<0.0) and ((d-c).cross(a-c)*(d-c).cross(b-c)<0.0)

static func validate(points: PackedVector2Array,max_vertices: int = 64,min_area: float = 32.0,epsilon: float = 0.01,max_coordinate: float = 4096.0) -> Dictionary:
	if points.size()<3 or points.size()>max_vertices:
		return {"ok":false,"reason":"vertex_count"}
	for point: Vector2 in points:
		if not point.is_finite():
			return {"ok":false,"reason":"nonfinite_vertex"}
		if absf(point.x)>max_coordinate or absf(point.y)>max_coordinate:
			return {"ok":false,"reason":"coordinate_limit"}
	for i: int in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i+1)%points.size()]
		if a.distance_to(b)<=epsilon:
			return {"ok":false,"reason":"degenerate_edge"}
		for j: int in range(i+1,points.size()):
			if a.distance_to(points[j])<=epsilon:
				return {"ok":false,"reason":"repeated_vertex"}
		var incoming: Vector2 = b-a
		var outgoing: Vector2 = points[(i+2)%points.size()]-b
		if absf(incoming.cross(outgoing))<=epsilon*maxf(incoming.length(),outgoing.length()) and incoming.dot(outgoing)<0:
			return {"ok":false,"reason":"adjacent_edge_overlap"}
		for j: int in range(i+1,points.size()):
			if j==i+1 or (i==0 and j==points.size()-1):
				continue
			if _intersects(a,b,points[j],points[(j+1)%points.size()],epsilon):
				return {"ok":false,"reason":"self_intersection"}
	var area: float = absf(signed_area(points))
	if area<min_area:
		return {"ok":false,"reason":"area_minimum"}
	var normalized: PackedVector2Array = points.duplicate()
	if Geometry2D.is_polygon_clockwise(normalized):
		normalized.reverse()
	var parts: Array[PackedVector2Array] = Geometry2D.decompose_polygon_in_convex(normalized)
	if parts.is_empty():
		return {"ok":false,"reason":"decomposition_failed"}
	var decomposed_area: float = 0.0
	for part: PackedVector2Array in parts:
		var part_area: float = absf(signed_area(part))
		if part.size()<3 or part_area<=epsilon*epsilon:
			return {"ok":false,"reason":"degenerate_convex_part"}
		var turn: float = 0.0
		for i: int in range(part.size()):
			if not part[i].is_finite():
				return {"ok":false,"reason":"nonfinite_convex_part"}
			var cross: float = (part[(i+1)%part.size()]-part[i]).cross(part[(i+2)%part.size()]-part[(i+1)%part.size()])
			if absf(cross)>epsilon*epsilon:
				if turn!=0.0 and turn*cross<0.0:
					return {"ok":false,"reason":"nonconvex_decomposition"}
				turn = cross
		decomposed_area += part_area
	if absf(decomposed_area-area)>maxf(0.05,area*0.0001):
		return {"ok":false,"reason":"decomposition_area_mismatch"}
	return {"ok":true,"polygon":normalized,"parts":parts,"area":area}
