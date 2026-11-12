extends SceneTree
func _initialize() -> void:
	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/calibration_preparation_cases.json"))
	var validator: GDScript = load("res://scripts/geometry/MaterialGeometryValidator.gd")
	var compound: GDScript = load("res://scripts/geometry/CompoundGeometryValidator.gd")
	for name: String in ["solid","three","hole","corner","perspective_hole"]:
		for c: Dictionary in cases[name].structures:
			var v: Dictionary = validator.validate(c)
			print(name," ",v.get("reason","OK"))
			for r: Dictionary in c.regions:
				for raw: Array in r.holes:
					var hole: PackedVector2Array = compound.points(raw,2048,4096)
					var ext: PackedVector2Array = compound.points(r.exterior,2048,4096)
					print("HOLE_DELTA ",compound.intersection_area(hole,ext)-absf(compound.Simple.signed_area(hole)))
					for raw_part: Array in c.convex_parts:
						var part: PackedVector2Array = compound.points(raw_part,64,4096)
						var overlap: float = compound.intersection_area(hole,part)
						if overlap>0.0001:print("PART_HOLE_OVERLAP ",overlap," ",part," ",hole)
			for r: Dictionary in c.material_regions:
				var copy: Dictionary = c.duplicate();copy.regions = r.regions;copy.convex_parts = r.convex_parts
				var result: Dictionary = compound.validate(copy,512,2048,4096,0.0001)
				print("  ",r.material," ",result.get("reason","OK"))
	quit()
