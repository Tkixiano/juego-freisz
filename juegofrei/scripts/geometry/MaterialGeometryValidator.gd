extends RefCounted
## Offline material extension validator only. No bodies, sockets or input sources.
const Compound = preload("res://scripts/geometry/CompoundGeometryValidator.gd")
const MATERIALS: Array[String] = ["GREEN_SOLID","BLUE_BOUNCE","ORANGE_ONE_WAY"]
static var exact_cache: Dictionary = {}
static func reject(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func validate(data: Dictionary) -> Dictionary:
	# Validate dynamic metadata EVERY call. Cache only exact local geometry and
	# ownership: changing pose must not repeat polygon coverage/decomposition.
	var metadata: Dictionary = Compound.validate_metadata(data)
	if not metadata.ok:return metadata
	var key: PackedByteArray = var_to_bytes([data.id,data.has("material_contract_version"),data.get("material_contract_version"),data.get("regions"),data.get("convex_parts"),data.get("material_regions")])
	if exact_cache.has(key):
		var cached: Dictionary = exact_cache[key].duplicate(true)
		cached.base.merge(metadata,true)
		return cached
	var result: Dictionary = _validate(data)
	if result.ok:
		if exact_cache.size()>=128:exact_cache.erase(exact_cache.keys()[0])
		exact_cache[key] = result.duplicate(true)
	return result
static func _validate(data: Dictionary) -> Dictionary:
	var base: Dictionary = Compound.validate(data)
	if not base.ok: return base
	if not data.has("material_contract_version"): return {"ok":true,"legacy_only":true,"base":base,"material_regions":[]}
	if not Compound.number(data.material_contract_version) or float(data.material_contract_version)!=1: return reject("material_contract_version")
	if not data.get("material_regions") is Array or data.material_regions.is_empty() or data.material_regions.size()>128: return reject("material_regions")
	var ids: Dictionary = {}
	var parts: Array[PackedVector2Array] = []
	var regions: Array[Dictionary] = []
	var area: float = 0
	var areas: Dictionary = {}
	for entry: Variant in data.material_regions:
		if not entry is Dictionary or entry.get("material") not in MATERIALS: return reject("unknown_material")
		var id: Variant = entry.get("region_id")
		if not id is String or id.is_empty() or id.length()>64 or ids.has(id): return reject("region_id")
		ids[id] = true
		if not entry.get("structure_id") is String or entry.structure_id!=data.id: return reject("region_owner")
		var version: Variant = entry.get("geometry_version")
		if not Compound.number(version) or float(version)<1 or float(version)>2147483647 or floorf(float(version))!=float(version): return reject("region_geometry_version")
		if not entry.get("convex_parts") is Array or parts.size()+entry.convex_parts.size()>512: return reject("material_parts_budget")
		var subset: Dictionary = data.duplicate(true)
		subset.regions = entry.get("regions")
		subset.convex_parts = entry.convex_parts
		var valid: Dictionary = Compound.validate(subset,512,2048,4096.0,0.0001)
		if not valid.ok: return reject("material_geometry:"+valid.reason)
		for part: PackedVector2Array in valid.parts:
			var inside: float = 0
			for parent: PackedVector2Array in base.parts: inside += Compound.intersection_area(part,parent)
			if absf(inside-absf(Compound.Simple.signed_area(part)))>0.001: return reject("material_outside")
			for previous: PackedVector2Array in parts:
				if Compound.intersection_area(previous,part)>0.0001: return reject("material_overlap")
			parts.append(part)
		area += valid.area
		areas[entry.material] = float(areas.get(entry.material,0))+valid.area
		regions.append({"id":id,"material":entry.material,"parts":valid.parts,"area":valid.area})
	if absf(area-base.area)>0.001: return reject("material_coverage")
	return {"ok":true,"legacy_only":false,"base":base,"material_regions":regions,"area":area,"areas":areas}
