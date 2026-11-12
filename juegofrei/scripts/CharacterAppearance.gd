extends Node2D
## Standard presentation scene for placeholders or per-character SpriteFrames.
var definition: Resource
var requested_state: StringName = &"idle"
var played_animation: StringName = &""
var using_placeholder: bool = true
var facing: float = 1.0
var flash: bool = false
@onready var sprite: AnimatedSprite2D = $Sprite

func configure(data: Resource) -> void:
	definition = data
	played_animation = &""
	requested_state = &""
	sprite.sprite_frames = data.sprite_frames
	apply_visual_state(&"idle",1.0,false)
	queue_redraw()

func apply_visual_state(state: StringName,direction: float,impact_flash: bool) -> void:
	var changed: bool = state!=requested_state or direction!=facing or flash!=impact_flash
	var previous_animation: StringName = played_animation
	requested_state = state
	facing = direction
	flash = impact_flash
	if changed and sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("flash_amount",1.0 if flash else 0.0)
	played_animation = &""
	if definition!=null and definition.sprite_frames!=null:
		for key: StringName in [state,&"idle"]:
			var mapped: StringName = StringName(str(definition.animation_map.get(String(key),"")))
			if definition.sprite_frames.has_animation(mapped) and definition.sprite_frames.get_frame_count(mapped)>0:
				played_animation = mapped
				break
	using_placeholder = played_animation==&""
	sprite.visible = not using_placeholder
	if not using_placeholder:
		sprite.flip_h = facing<0
		if sprite.animation!=played_animation or previous_animation!=played_animation: sprite.play(played_animation)
	else:
		sprite.stop()
	if changed: queue_redraw()

func _draw() -> void:
	if not using_placeholder or definition==null: return
	var color: Color = Color.WHITE if flash else definition.accent
	draw_rect(Rect2(-20,-20,40,40),color)
	draw_rect(Rect2(-20,-20,40,40),color.lightened(0.5),false,2)
	match definition.placeholder_style:
		0: draw_rect(Rect2(-14,-14,28,5),Color(0.95,0.98,1,0.8))
		1: draw_colored_polygon(PackedVector2Array([Vector2(0,-14),Vector2(13,0),Vector2(0,14),Vector2(-13,0)]),Color(1,1,1,0.8))
		2:
			draw_rect(Rect2(-4,-14,8,28),Color(0.04,0.12,0.15,0.8))
			draw_rect(Rect2(-14,-4,28,8),Color(0.04,0.12,0.15,0.8))
		3: draw_arc(Vector2.ZERO,12,0,TAU,20,Color.WHITE,4,true)
	draw_circle(Vector2(11*facing,-4),2,Color("#172534"))
