extends StaticBody2D
@export var floor_rect: Rect2 = Rect2(-100,580,1480,24)
var enabled: bool = true
var scene_state: String = "SCENE_EMPTY"
var shape: RectangleShape2D = RectangleShape2D.new()
var blocker: CollisionShape2D
var manager: Node
var metrics: Dictionary = {"activations":1,"retirements":0,"deferred_retirements":0,"activation_deferrals":0}
var last_reason: String = ""
var previous_reason: String = ""
var inner: RectangleShape2D = RectangleShape2D.new()

func _ready() -> void:
	process_physics_priority = -70
	shape.size = floor_rect.size;inner.size = Vector2(39,39)
	position = floor_rect.get_center();collision_layer = 1;collision_mask = 0
	blocker = CollisionShape2D.new();blocker.shape = shape;add_child(blocker)
	queue_redraw()
func _draw() -> void:
	if enabled:draw_rect(Rect2(-floor_rect.size/2,floor_rect.size),Color("526c82"))
func set_enabled(value: bool) -> void:
	if value==enabled:return
	enabled = value;collision_layer = 1 if value else 0;blocker.disabled = not value
	metrics["activations" if value else "retirements"] += 1
	last_reason = "";previous_reason = "";queue_redraw()
func retirement_reason() -> String:
	for p: Node in get_tree().get_nodes_in_group("players"):
		if not p is CharacterBody2D or p.collision_mask==0:continue
		var on_other: bool = false
		for i: int in range(p.get_slide_collision_count()):
			var c: KinematicCollision2D = p.get_slide_collision(i)
			if c.get_normal().y> -0.5:continue
			if c.get_collider()==self:return "player_%d_supported_by_floor"%p.player_id
			on_other = true
		if shape.collide(global_transform,inner,p.get_node("CollisionShape2D").global_transform):return "player_intersects_floor"
		if not on_other and p.velocity.y>=0:return "player_falling_needs_floor"
	return ""
func activation_reason() -> String:
	for p: Node in get_tree().get_nodes_in_group("players"):
		if not p is CharacterBody2D or p.collision_mask==0:continue
		if p.position.y+20>floor_rect.position.y:return "player_below_or_inside_floor"
	return ""
func target_overlaps(targets: Dictionary,poses: Dictionary) -> bool:
	for id: StringName in targets:
		for resource: ConvexPolygonShape2D in targets[id].resources:
			if resource.collide(poses[id],shape,global_transform):return true
	return false
func record_deferral(reason: String) -> void:
	last_reason = reason
	if reason!=previous_reason:
		metrics.deferred_retirements += 1;previous_reason = reason
func _physics_process(_delta: float) -> void:
	if not enabled or scene_state!="SCENE_ACTIVE":return
	var reason: String = retirement_reason()
	if reason.is_empty():set_enabled(false)
	else:record_deferral(reason)
