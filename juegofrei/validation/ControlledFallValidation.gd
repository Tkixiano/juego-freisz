extends RefCounted
var tree: SceneTree
var results: Array[Dictionary]=[]
func frames(count: int) -> void:
	for i: int in range(count):
		await tree.physics_frame
		await tree.process_frame
func check(name: String, passed: bool, detail: Variant="") -> void:
	results.append({"test":name,"passed":passed,"detail":str(detail)})
func run(scene_tree: SceneTree) -> void:
	tree=scene_tree
	var root: Node=tree.current_scene
	root.restart_match()
	root.set_physics_process(false)
	for player: CharacterBody2D in root.players:
		player.combat.respawn_left=0
		player.position=Vector2(70 if player.player_id==1 else 1210,-100)
		player.velocity=Vector2.ZERO
	await frames(2)
	var p: CharacterBody2D=root.players[0]
	var q: CharacterBody2D=root.players[1]
	p.velocity.y=100
	q.velocity.y=100
	Input.action_press("p1_down")
	await frames(1)
	check("gentle_first_down_frame",p.velocity.y>q.velocity.y and p.velocity.y<150,p.velocity.y)
	await frames(20)
	check("hold_down_reaches_controlled_cap",absf(p.velocity.y-800)<0.1,p.velocity.y)
	check("normal_fall_unchanged",q.velocity.y<640 and q.velocity.y<p.velocity.y,q.velocity.y)
	Input.action_release("p1_down")
	var before: float=p.velocity.y
	await frames(1)
	check("release_is_progressive",p.velocity.y<before and p.velocity.y>640,p.velocity.y)
	await frames(7)
	check("release_returns_to_normal_cap",absf(p.velocity.y-640)<0.1,p.velocity.y)
	p.position=Vector2(70,-100)
	q.position=Vector2(1210,-100)
	p.velocity=Vector2(0,650)
	q.velocity=Vector2(0,650)
	Input.action_press("p2_down")
	Input.action_press("p1_right")
	await frames(4)
	check("player2_down_uses_same_tuning",q.velocity.y>p.velocity.y and q.velocity.y<=800,q.velocity.y)
	check("horizontal_air_control_kept",p.velocity.x>0,p.velocity.x)
	Input.action_release("p2_down")
	Input.action_release("p1_right")
	p.velocity.y=-400
	q.velocity.y=-400
	Input.action_press("p1_down")
	await frames(3)
	check("down_does_not_cut_ascent",absf(p.velocity.y-q.velocity.y)<0.1,[p.velocity.y,q.velocity.y])
	Input.action_release("p1_down")
	var tuning: Resource=p.movement
	check("time_step_independent_vertical",absf(tuning.vertical(tuning.vertical(100,1,1.0/120),1,1.0/120)-tuning.vertical(100,1,1.0/60))<0.001)
	root.set_physics_process(true)
	root.restart_match()
	var regress: RefCounted=load("res://validation/MovementValidation.gd").new()
	var movement_checks: Array=await regress.run(tree)
	var gravity: RefCounted=load("res://validation/DynamicValidation.gd").new()
	var gravity_checks: Array=await gravity.run_gravity(tree)
	root.restart_match()
	var report: Dictionary={"controlled_fall":results,"movement_regression":movement_checks,"gravity_regression":gravity_checks}
	var file: FileAccess=FileAccess.open("res://validation/controlled_fall_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	root.set_meta("controlled_fall_results",report)
