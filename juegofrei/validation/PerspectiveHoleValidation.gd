extends RefCounted
const Contract = preload("res://scripts/geometry/MaterialGeometryValidator.gd")
const Compound = preload("res://scripts/geometry/CompoundGeometryValidator.gd")
var rows: Array = []
var tree: SceneTree
var game: Node
var hole_queries: int = 0
var hole_hits: int = 0
var maximum_hole_overlap_px2: float = 0
func check(name: String,ok: bool,detail: Variant=null) -> void:
	rows.append({"name":name,"passed":ok,"detail":detail})
	if not ok:push_error("PERSPECTIVE_HOLE "+name+" "+str(detail))
func frames(n: int=4) -> void:
	for i: int in range(n):await tree.physics_frame
func fresh() -> void:
	game.get_node("Sources").select_mode("OFFLINE");game.get_node("Replay").pause()
	for p: Node in game.players:p.collision_mask = 0;p.set_physics_process(false);p.position = Vector2(100,-100)
	game.get_node("Adapter").request_reset();game.get_node("SceneSource").request_reset();await frames(5)
func send(input: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for i: int in range(4):
		var f: Dictionary = input.duplicate(true);f.sequence = i+1;f.logical_time = i*.05
		result = game.get_node("SceneSource").submit(f);await frames(4)
	return result
func run(scene_tree: SceneTree,label: String="headless") -> Dictionary:
	tree = scene_tree;game = tree.current_scene
	var shell: Node = game.get_node("GameShell");shell.show_selection();shell.selection.toggle_ready(0);shell.selection.toggle_ready(1);await frames()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/perspective_hole_cases.json"))
	var original: Dictionary = data.valid.unwelded_original.structures[0]
	check("old_geometry_still_rejected",Compound.validate(original).get("reason")=="part_fills_hole")
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new();query.collision_mask = 3;query.collide_with_areas = false
	for name: String in data.valid:
		if name=="unwelded_original":continue
		await fresh();var f: Dictionary = data.valid[name];var validation: Dictionary = Contract.validate(f.structures[0])
		check(name+"_contract",validation.ok,validation.get("reason"))
		var response: Dictionary = await send(f)
		var adapter: Node = game.get_node("Adapter");var manager: Node = game.get_node("DynamicGeometry")
		var expected: int = 0
		for c: Dictionary in f.structures:expected += c.material_regions.size()
		var applied: bool = adapter.applied_sequence>0 and manager.object_ids().size()==expected
		check(name+"_atomic_apply",applied,response)
		if not applied:continue
		var before_queries: int = hole_queries;var before_hits: int = hole_hits;var solid_checks: int = 0
		var case_overlap: float = 0
		for c: Dictionary in f.structures:
			var origin: Vector2 = Vector2(c.position[0],c.position[1])
			for region: Dictionary in c.regions:
				for raw: Array in region.holes:
					var hole: PackedVector2Array = Compound.points(raw,2048,4096)
					for raw_part: Array in c.convex_parts:
						case_overlap = maxf(case_overlap,Compound.intersection_area(Compound.points(raw_part,64,4096),hole))
					var box: Rect2 = Rect2(hole[0],Vector2.ZERO)
					for p: Vector2 in hole:box = box.expand(p)
					for iy: int in range(1,16):
						for ix: int in range(1,16):
							var point: Vector2 = box.position+box.size*Vector2(ix/16.0,iy/16.0)
							if not Geometry2D.is_point_in_polygon(point,hole):continue
							query.position = origin+point;hole_queries += 1
							if not game.get_world_2d().direct_space_state.intersect_point(query,8).is_empty():hole_hits += 1
			for material: Dictionary in c.material_regions:
				if material.material=="ORANGE_ONE_WAY":continue
				for part: Array in material.convex_parts:
					var center: Vector2 = Vector2.ZERO
					for p: Array in part:center += Vector2(p[0],p[1])
					query.position = origin+center/part.size()
					if not game.get_world_2d().direct_space_state.intersect_point(query,8).is_empty():solid_checks += 1
		check(name+"_hole_sampling",hole_queries-before_queries>=100,hole_queries-before_queries)
		check(name+"_zero_geometric_hole_overlap",case_overlap<=0.00000001,case_overlap)
		maximum_hole_overlap_px2 = maxf(maximum_hole_overlap_px2,case_overlap)
		check(name+"_no_hole_collisions",hole_hits==before_hits,hole_hits-before_hits)
		check(name+"_actual_solid_collisions",solid_checks>0,solid_checks)
	# All invalid cases must retain an already committed valid structure.
	await fresh();await send(data.valid.original)
	var manager: Node = game.get_node("DynamicGeometry");var before: Array = manager.object_ids()
	var before_geometry: Dictionary = {}
	for id: StringName in before:
		var body: Node = manager.get_body(id)
		before_geometry[id] = var_to_bytes([body.convex_parts,body.global_transform,body.geometry_revision,body.shape_builds,body.material_kind])
	var sequence: int = 10
	for name: String in data.invalid:
		var bad: Dictionary = data.invalid[name].duplicate(true);bad.session_id = data.valid.original.session_id;bad.sequence = sequence;bad.logical_time = sequence;sequence += 1
		var response: Dictionary = game.get_node("SceneSource").submit(bad);await frames(2)
		check(name+"_rejected",response.status=="REJECTED",response)
		var unchanged: bool = manager.object_ids()==before
		for id: StringName in before:
			var body: Node = manager.get_body(id)
			unchanged = unchanged and before_geometry[id]==var_to_bytes([body.convex_parts,body.global_transform,body.geometry_revision,body.shape_builds,body.material_kind])
		check(name+"_no_partial_apply",unchanged)
	var benchmark: Dictionary = {}
	for key: String in ["unwelded_original","original"]:
		var values: Array = [];var c: Dictionary = data.valid[key].structures[0]
		for i: int in range(110):
			var start: int = Time.get_ticks_usec();Compound.validate(c)
			if i>=10:values.append((Time.get_ticks_usec()-start)/1000.0)
		benchmark[key] = values
	check("no_deep_penetrations",game.penetrations==0,game.penetrations)
	var failures: Array = rows.filter(func(r: Dictionary) -> bool:return not r.passed)
	var result: Dictionary = {"label":label,"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"rows":rows,"hole_queries":hole_queries,"hole_hits":hole_hits,"maximum_hole_overlap_px2":maximum_hole_overlap_px2,"compound_validation_ms":benchmark,"synthetic_only":true}
	var file: FileAccess = FileAccess.open("res://validation/perspective_hole_"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	game.set_meta("perspective_hole_results",result);print("PERSPECTIVE_HOLE ",result.passed,"/",result.total," ",failures)
	return result
