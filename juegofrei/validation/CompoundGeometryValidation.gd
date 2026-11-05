extends RefCounted
const Validator = preload("res://scripts/geometry/CompoundGeometryValidator.gd")
const Simple = preload("res://scripts/geometry/PolygonValidator.gd")
var rows: Array[Dictionary] = []
var measurements: Array[Dictionary] = []

func check(name: String,passed: bool,details: Variant = "") -> void:
	rows.append({"name":name,"passed":passed,"details":details})
	if not passed:
		push_error("COMPOUND_QA "+name+": "+str(details))

func run(tree: SceneTree,label: String = "mcp") -> Dictionary:
	var lab: Node = tree.current_scene
	var manager: Node = lab.get_node("DynamicGeometry")
	var fixture_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/phase1c_fixtures.json"))
	for id: StringName in manager.object_ids():
		manager.remove_object(id)
	await tree.physics_frame
	await tree.physics_frame
	manager.protected_body_mask = 0
	lab.get_node("Player").position = Vector2(1200,-500)
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.collide_with_areas = false
	for fixture: Dictionary in fixture_data.cases:
		var data: Dictionary = fixture.contract
		var id: StringName = StringName(data.id)
		var start: int = Time.get_ticks_usec()
		check(fixture.name+"_create",manager.create_structure(data),manager.last_error)
		await tree.physics_frame
		await tree.physics_frame
		var body: StaticBody2D = manager.get_body(id)
		check(fixture.name+"_committed",body!=null)
		if body==null:
			continue
		var expected: Dictionary = {}
		for run: Array in fixture.foreground_runs:
			for x: int in range(int(run[1]),int(run[2])):
				expected[Vector2i(x,int(run[0]))] = true
		var false_positive: int = 0
		var false_negative: int = 0
		var width: int = int(fixture.resolution[0])
		var height: int = int(fixture.resolution[1])
		var origin: Vector2 = Vector2(float(fixture.reference_position[0]),float(fixture.reference_position[1]))
		check(fixture.name+"_global_pose",body.position.distance_to(Vector2(float(data.position[0]),float(data.position[1])))<0.001 and absf(angle_difference(body.rotation,float(data.orientation_radians)))<0.0001)
		for y: int in range(height):
			for x: int in range(width):
				query.position = body.to_global(Vector2(x+0.5,y+0.5)-origin)
				var found: bool = not lab.get_world_2d().direct_space_state.intersect_point(query,1).is_empty()
				var wanted: bool = expected.has(Vector2i(x,y))
				if found and not wanted: false_positive += 1
				if wanted and not found: false_negative += 1
			if y%16==0: await tree.process_frame
		var actual_area: float = 0.0
		for collider: CollisionShape2D in body.colliders:
			actual_area += absf(Simple.signed_area((collider.shape as ConvexPolygonShape2D).points))
		var area_error: float = absf(actual_area-float(fixture.expected_area))
		measurements.append({"name":fixture.name,"false_positive_pixels":false_positive,"false_negative_pixels":false_negative,
			"area_error_px2":area_error,"reference_pixels":expected.size(),"tested_pixels":width*height,
			"physics_shapes":body.colliders.size(),"total_validation_ms":(Time.get_ticks_usec()-start)/1000.0})
		check(fixture.name+"_physical_mask_exact",false_positive==0 and false_negative==0,measurements[-1])
		check(fixture.name+"_area",area_error<0.002,area_error)
		var builds: int = body.shape_builds
		manager.update_transform(id,body.position+Vector2(1,0),0.02)
		await tree.physics_frame
		await tree.physics_frame
		check(fixture.name+"_pose_without_rebuild",body.shape_builds==builds)
		manager.remove_object(id)
		await tree.physics_frame
		await tree.physics_frame
	# Invalid updates preserve a previously committed hole, not just an error code.
	var good: Dictionary = fixture_data.cases[5].contract.duplicate(true)
	check("safe_baseline",manager.create_structure(good))
	await tree.physics_frame
	await tree.physics_frame
	var body: StaticBody2D = manager.get_body(StringName(good.id))
	var initial_builds: int = body.shape_builds
	for invalid: Dictionary in fixture_data.invalid:
		var candidate: Dictionary = invalid.contract.duplicate(true)
		candidate.geometry_version = 2
		check(invalid.name+"_rejected",not manager.assign_structure(candidate),manager.last_error)
		await tree.physics_frame
		check(invalid.name+"_preserves_last",body.shape_builds==initial_builds)
	query.position = Vector2(50,40)
	check("hole_still_empty_after_invalid_updates",lab.get_world_2d().direct_space_state.intersect_point(query,1).is_empty())
	var malformed: Dictionary = good.duplicate(true)
	malformed.convex_parts[0][0][0] = INF
	check("nonfinite_rejected",not manager.assign_structure(malformed))
	malformed = good.duplicate(true)
	malformed.geometry_version = 1
	check("duplicate_geometry_version_rejected",not manager.assign_structure(malformed))
	malformed.geometry_version = 2
	check("identical_shape_new_version",manager.assign_structure(malformed))
	await tree.physics_frame
	await tree.physics_frame
	check("identical_shape_does_not_rebuild",body.shape_builds==initial_builds)
	var pose_only: Dictionary = good.duplicate(true)
	pose_only.geometry_version = 2
	pose_only.tracking = {"state":"HELD","age_frames":5}
	pose_only.confidence = 0.0
	pose_only.position[0] += 200
	check("held_metadata_update_without_new_geometry_version",manager.update_structure_pose(pose_only))
	await tree.physics_frame
	await tree.physics_frame
	check("held_pose_stops_and_preserves_geometry",body.shape_builds==initial_builds and body.position.distance_to(Vector2(float(good.position[0]),float(good.position[1])))<0.001 and manager.get_state(StringName(good.id)).tracking.state=="HELD")
	pose_only.geometry_version = 1
	check("pose_for_old_geometry_rejected",not manager.update_structure_pose(pose_only))
	# Reuse the real CharacterBody controller on a compound body's upper strip.
	var player: CharacterBody2D = lab.get_node("Player")
	player.position = Vector2(55,-60)
	player.velocity = Vector2.ZERO
	player.combat.reset_after_respawn()
	player.combat.respawn_left = 0
	player.combat.invulnerability_left = 0
	player.force_update_transform()
	player.reset_physics_interpolation()
	for step: int in range(70):
		await tree.physics_frame
		await tree.process_frame
	check("character_lands_on_compound",player.is_on_floor(),player.position)
	var start_body: Vector2 = body.position
	var start_player: Vector2 = player.position
	var floor_frames: int = 0
	var max_step: float = 0.0
	var max_overlap: float = 0.0
	var previous_position: Vector2 = player.position
	manager.update_transform(StringName(good.id),body.position+Vector2(60,0),0)
	for step: int in range(60):
		await tree.physics_frame
		await tree.process_frame
		if player.is_on_floor(): floor_frames += 1
		max_step = maxf(max_step,player.position.distance_to(previous_position))
		previous_position = player.position
		var rectangle: PackedVector2Array = player.global_transform*PackedVector2Array([Vector2(-20,-20),Vector2(20,-20),Vector2(20,20),Vector2(-20,20)])
		var overlap: float = 0.0
		for part: PackedVector2Array in body.convex_parts:
			overlap += Validator.intersection_area(rectangle,body.global_transform*part)
		max_overlap = maxf(max_overlap,overlap)
	var carry_error: float = ((player.position-start_player)-(body.position-start_body)).length()
	measurements.append({"name":"compound_carrier","frames":60,"floor_frames":floor_frames,"carry_error_px":carry_error,"max_player_step_px":max_step,"max_overlap_area_px2":max_overlap})
	check("compound_carries_character_without_rebuild",body.shape_builds==initial_builds and floor_frames>=54 and carry_error<2.5,measurements[-1])
	check("compound_no_jump_or_deep_penetration",max_step<3 and max_overlap<2,measurements[-1])
	player.position = Vector2(1200,-500)
	player.velocity = Vector2.ZERO
	player.force_update_transform()
	# Repeated hole -> point contact -> hole replacement under ONE logical ID.
	for iteration: int in range(12):
		var index: int = 2 if iteration%2==0 else 5
		var replacement: Dictionary = fixture_data.cases[index].contract.duplicate(true)
		replacement.id = good.id
		replacement.position = good.position
		replacement.geometry_version = iteration+3
		check("topology_update_%d"%iteration,manager.assign_structure(replacement),manager.last_error)
		await tree.physics_frame
		await tree.physics_frame
		check("one_logical_body_%d"%iteration,manager.object_ids().size()==1 and manager.get_body(StringName(good.id))==body)
	manager.remove_object(StringName(good.id))
	await tree.physics_frame
	await tree.physics_frame
	check("final_cleanup",manager.object_ids().is_empty())
	manager.protected_body_mask = 4
	lab.get_node("Player").position = Vector2(260,50)
	var failures: Array = rows.filter(func(row: Dictionary) -> bool: return not row.passed)
	var result: Dictionary = {"label":label,"total":rows.size(),"passed":rows.size()-failures.size(),"failures":failures,"measurements":measurements,"synthetic_only":true,"rows":rows}
	lab.set_meta("compound_results",result)
	var file: FileAccess = FileAccess.open("res://validation/phase1c_geometry_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("COMPOUND_QA ",JSON.stringify({"label":label,"passed":result.passed,"total":result.total,"failures":failures}))
	if lab.has_method("show_fixtures"): lab.show_fixtures()
	return result
