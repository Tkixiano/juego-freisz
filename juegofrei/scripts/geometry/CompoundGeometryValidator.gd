extends RefCounted
## Local contract v1; validates rings AND disjoint convex coverage. No transport.
const Simple = preload("res://scripts/geometry/PolygonValidator.gd")

static func reject(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func points(value: Variant,max_vertices: int,max_coordinate: float) -> PackedVector2Array:
	var result: PackedVector2Array = []
	if not value is Array or value.size()<3 or value.size()>max_vertices:
		return result
	for item: Variant in value:
		if not item is Array or item.size()!=2 or not number(item[0]) or not number(item[1]):
			return []
		var p: Vector2 = Vector2(float(item[0]),float(item[1]))
		if absf(p.x)>max_coordinate or absf(p.y)>max_coordinate:
			return []
		result.append(p)
	return result

static func intersection_area(a: PackedVector2Array,b: PackedVector2Array) -> float:
	var area: float = 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(a,b):
		area += absf(Simple.signed_area(piece))
	return area

static func validate_metadata(data: Dictionary) -> Dictionary:
	if data.get("contract_version")!=1 or not data.get("id") is String or data.id.is_empty() or data.id.length()>64:
		return reject("contract_version_or_id")
	if not number(data.get("geometry_version")) or float(data.geometry_version)<1 or float(data.geometry_version)>2147483647 or floorf(float(data.geometry_version))!=float(data.geometry_version):
		return reject("geometry_version")
	if data.get("coordinate_space")!="ARENA_PIXELS" or data.get("units")!="pixels" or data.get("axis")!="X_RIGHT_Y_DOWN":
		return reject("coordinate_space")
	var pose: Variant = data.get("position")
	if not pose is Array or pose.size()!=2 or not number(pose[0]) or not number(pose[1]) or not number(data.get("orientation_radians")):
		return reject("pose")
	if not number(data.get("confidence")) or float(data.confidence)<0 or float(data.confidence)>1:
		return reject("confidence")
	var tracking: Variant = data.get("tracking")
	if not tracking is Dictionary or tracking.get("state") not in ["TRACKED","HELD","LOST"] or not number(tracking.get("age_frames")) or float(tracking.age_frames)<0 or float(tracking.age_frames)>2147483647 or floorf(float(tracking.age_frames))!=float(tracking.age_frames):
		return reject("tracking")
	return {"ok":true,"position":Vector2(float(pose[0]),float(pose[1])),"rotation":float(data.orientation_radians),"geometry_version":int(data.geometry_version),"tracking":tracking.duplicate(true),"confidence":float(data.confidence)}

static func validate(data: Dictionary,max_parts: int=512,max_vertices: int=2048,max_coordinate: float=4096.0,min_area: float=32.0) -> Dictionary:
	var metadata: Dictionary = validate_metadata(data)
	if not metadata.ok:
		return metadata
	var input_regions: Variant = data.get("regions")
	var input_parts: Variant = data.get("convex_parts")
	if not input_regions is Array or input_regions.is_empty() or input_regions.size()>64 or not input_parts is Array or input_parts.is_empty() or input_parts.size()>max_parts:
		return reject("region_or_part_limit")
	var regions: Array[Dictionary] = []
	var outlines: Array[PackedVector2Array] = []
	var total_area: float = 0.0
	var vertex_count: int = 0
	for item: Variant in input_regions:
		if not item is Dictionary or not item.get("holes") is Array:
			return reject("region_structure")
		var exterior: PackedVector2Array = points(item.get("exterior"),max_vertices,max_coordinate)
		if vertex_count+exterior.size()>8192:
			return reject("total_vertices_or_area")
		var valid: Dictionary = Simple.validate(exterior,max_vertices,0.0001,0.00001,max_coordinate)
		if not valid.ok or Simple.signed_area(exterior)<=0:
			return reject("invalid_exterior")
		vertex_count += exterior.size()
		outlines.append(exterior)
		var holes: Array[PackedVector2Array] = []
		var region_area: float = absf(Simple.signed_area(exterior))
		if item.holes.size()>64:
			return reject("hole_limit")
		for raw_hole: Variant in item.holes:
			var hole: PackedVector2Array = points(raw_hole,max_vertices,max_coordinate)
			if vertex_count+hole.size()>8192:
				return reject("total_vertices_or_area")
			valid = Simple.validate(hole,max_vertices,0.0001,0.00001,max_coordinate)
			if not valid.ok or Simple.signed_area(hole)>=0:
				return reject("invalid_hole")
			var area: float = absf(Simple.signed_area(hole))
			if absf(intersection_area(hole,exterior)-area)>0.001:
				return reject("hole_outside_exterior")
			# Reject touching hole boundaries; permit only strictly interior holes.
			for j: int in range(hole.size()):
				for k: int in range(exterior.size()):
					if Simple._intersects(hole[j],hole[(j+1)%hole.size()],exterior[k],exterior[(k+1)%exterior.size()],0.00001):
						return reject("hole_touches_boundary")
			for previous: PackedVector2Array in holes:
				if intersection_area(previous,hole)>0.0001:
					return reject("overlapping_holes")
			vertex_count += hole.size()
			holes.append(hole)
			outlines.append(hole)
			region_area -= area
		if region_area<=0:
			return reject("empty_region")
		for previous: Dictionary in regions:
			if intersection_area(previous.exterior,exterior)>0.0001:
				return reject("overlapping_exterior_regions")
		regions.append({"exterior":exterior,"holes":holes})
		total_area += region_area
	if vertex_count>8192 or total_area<min_area:
		return reject("total_vertices_or_area")
	var parts: Array[PackedVector2Array] = []
	var covered_area: float = 0.0
	for raw_part: Variant in input_parts:
		var part: PackedVector2Array = points(raw_part,64,max_coordinate)
		var valid: Dictionary = Simple.validate(part,64,0.0001,0.00001,max_coordinate)
		if not valid.ok or valid.parts.size()!=1:
			return reject("invalid_convex_part")
		var area: float = absf(Simple.signed_area(part))
		var inside_area: float = 0.0
		for region: Dictionary in regions:
			inside_area += intersection_area(part,region.exterior)
			for hole: PackedVector2Array in region.holes:
				if intersection_area(part,hole)>0.0001:
					return reject("part_fills_hole")
		if absf(inside_area-area)>0.001:
			return reject("part_outside_silhouette")
		for previous: PackedVector2Array in parts:
			if intersection_area(part,previous)>0.0001:
				return reject("overlapping_convex_parts")
		parts.append(valid.polygon)
		covered_area += area
	if absf(covered_area-total_area)>0.001:
		return reject("coverage_area_mismatch")
	return {"ok":true,"polygon":regions[0].exterior,"outlines":outlines,"parts":parts,"area":total_area,
		"position":metadata.position,"rotation":metadata.rotation,"geometry_version":metadata.geometry_version,
		"tracking":metadata.tracking,"confidence":metadata.confidence}
