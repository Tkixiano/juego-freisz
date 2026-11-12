extends RefCounted
const Validator = preload("res://scripts/geometry/MaterialGeometryValidator.gd")
var rows: Array[Dictionary] = []
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
func run() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://validation/material_contract_fixtures.json",FileAccess.READ)
	var fixtures: Dictionary = JSON.parse_string(file.get_as_text())
	for c: Dictionary in fixtures.cases:
		var area: float = 0
		var ids: Dictionary = {}
		var areas: Dictionary = {}
		for s: Dictionary in c.structures:
			var valid: Dictionary = Validator.validate(s)
			check(c.name+":geometry",valid.ok,valid.get("reason"))
			if not valid.ok: continue
			area += valid.area
			for region: Dictionary in s.material_regions:
				check(c.name+":unique_region",not ids.has(region.region_id))
				ids[region.region_id] = true
			for material: String in valid.areas: areas[material] = float(areas.get(material,0))+valid.areas[material]
		check(c.name+":reference_area",absf(area-float(c.expected_area))<0.001,area)
		for material: String in c.material_area:
			check(c.name+":"+material+":area",absf(float(areas.get(material,0))-float(c.material_area[material]))<0.001,areas.get(material,0))
	var source: Dictionary = fixtures.cases[6].structures[0]
	var legacy: Dictionary = source.duplicate(true)
	legacy.erase("material_contract_version");legacy.erase("material_regions")
	check("legacy_v1_unchanged",Validator.Compound.validate(legacy).ok and Validator.validate(legacy).legacy_only)
	for field: String in ["material_contract_version","unknown_material","wrong_owner","duplicate_id","version","empty_region","overlap","hole_filled","outside","bool_version","typed_owner","nonfinite"]:
		var invalid: Dictionary = source.duplicate(true)
		match field:
			"material_contract_version": invalid.material_contract_version = 99
			"bool_version": invalid.material_contract_version = true
			"typed_owner": invalid.material_regions[0].structure_id = 17
			"nonfinite": invalid.material_regions[0].convex_parts[0][0][0] = INF
			"unknown_material": invalid.material_regions[0].material = "UNSUPPORTED"
			"wrong_owner": invalid.material_regions[0].structure_id = "other"
			"duplicate_id": invalid.material_regions[1].region_id = invalid.material_regions[0].region_id
			"version": invalid.material_regions[0].geometry_version = -1
			"empty_region": invalid.material_regions[0].regions = []
			"overlap":
				invalid.material_regions[1].regions = invalid.material_regions[0].regions.duplicate(true)
				invalid.material_regions[1].convex_parts = invalid.material_regions[0].convex_parts.duplicate(true)
			"hole_filled":
				invalid = fixtures.cases[11].structures[0].duplicate(true)
				invalid.material_regions[0].regions[0].holes = []
			"outside":
				invalid.material_regions[0].convex_parts[0][0][0] += 500
		check("reject:"+field,not Validator.validate(invalid).ok)
	var failures: Array = rows.filter(func(r: Dictionary) -> bool:return not r.passed)
	var result: Dictionary = {"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows}
	var output: FileAccess = FileAccess.open("res://validation/material_geometry_results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  "))
	if Engine.get_main_loop().current_scene!=null: Engine.get_main_loop().current_scene.set_meta("material_validation",result)
	print("MATERIAL_GEOMETRY ",result.passed,"/",result.total," ",failures)
	return result
