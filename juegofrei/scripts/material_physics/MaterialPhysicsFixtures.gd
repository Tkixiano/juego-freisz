extends RefCounted
## Hand-authored local synthetic contracts; no Python/OpenCV/network dependency.
static func region(id: String,kind: String,ring: Array) -> Dictionary:
	return {"region_id":id,"structure_id":"","material":kind,"geometry_version":1,"regions":[{"exterior":ring,"holes":[]}],"convex_parts":[ring.duplicate(true)]}
static func rect(x: float,y: float,w: float,h: float) -> Array:
	return [[x,y],[x+w,y],[x+w,y+h],[x,y+h]]
static func structure(id: String,position: Vector2,regions: Array,angle: float=0.0) -> Dictionary:
	var whole_regions: Array = []
	var parts: Array = []
	for r: Dictionary in regions:
		r.structure_id = id
		whole_regions.append_array(r.regions.duplicate(true))
		parts.append_array(r.convex_parts.duplicate(true))
	# Touching rectangular exteriors are represented by disjoint interiors; a
	# material boundary is not a duplicate region. Validator checks total coverage.
	return {"contract_version":1,"id":id,"geometry_version":1,"coordinate_space":"ARENA_PIXELS","units":"pixels","axis":"X_RIGHT_Y_DOWN","position":[position.x,position.y],"orientation_radians":angle,"confidence":1.0,"tracking":{"state":"TRACKED","age_frames":0},"regions":whole_regions,"convex_parts":parts,"material_contract_version":1,"material_regions":regions}
static func single(kind: String,position: Vector2=Vector2(640,400),angle: float=0.0) -> Dictionary:
	return structure("test",position,[region("test_r",kind,rect(-120,0,240,35))],angle)
static func defaults() -> Array:
	return [structure("green",Vector2(230,520),[region("green_r","GREEN_SOLID",rect(-140,0,280,40))]),
		structure("blue",Vector2(640,570),[region("blue_r","BLUE_BOUNCE",rect(-90,0,180,35))]),
		structure("orange",Vector2(1020,480),[region("orange_r","ORANGE_ONE_WAY",rect(-140,0,280,45))]),
		structure("green_orange",Vector2(430,310),[region("go_g","GREEN_SOLID",rect(-120,0,120,35)),region("go_o","ORANGE_ONE_WAY",rect(0,0,120,35))]),
		structure("green_blue",Vector2(840,240),[region("gb_g","GREEN_SOLID",rect(-100,0,100,35)),region("gb_b","BLUE_BOUNCE",rect(0,0,100,35))])]
