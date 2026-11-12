extends Resource
## Appearance only. No movement/combat values or collision dimensions here.
@export var character_id: StringName = &""
@export var display_name: String = "Personaje"
@export var portrait: Texture2D
@export var visual_scene: PackedScene
@export var sprite_frames: SpriteFrames
@export var animation_map: Dictionary = {"idle":"idle","run":"run","jump":"jump","fall":"fall","light":"light","heavy":"heavy","up":"up","down":"down","dash":"dash","hurt":"hurt","defeat":"defeat"}
@export var accent: Color = Color.CORNFLOWER_BLUE
@export_range(0,3) var placeholder_style: int = 0
@export var visual_scale: Vector2 = Vector2.ONE
@export var visual_offset: Vector2 = Vector2.ZERO

func is_valid() -> bool:
	return not String(character_id).is_empty() and not display_name.is_empty() and visual_scale.is_finite() and visual_scale.x>0 and visual_scale.y>0 and visual_scale.x<=8 and visual_scale.y<=8 and visual_offset.is_finite()
