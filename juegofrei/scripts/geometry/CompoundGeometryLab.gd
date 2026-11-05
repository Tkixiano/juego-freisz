extends Node2D
## Offline contract fixtures. No OpenCV process, UDP, capture or projection.
const Manager = preload("res://scripts/geometry/DynamicGeometryManager.gd")
@onready var geometry: Manager = $DynamicGeometry
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#101c2b"))
	show_fixtures()

func show_fixtures() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/phase1c_fixtures.json"))
	var i: int = 0
	for fixture: Dictionary in fixtures.cases:
		if fixture.get("validation_only",false): continue
		var contract: Dictionary = fixture.contract.duplicate(true)
		contract.id = "demo_"+fixture.name
		contract.position[0] += 90+(i%3)*360
		contract.position[1] += 90+(i/3)*175
		geometry.create_structure(contract,Color("#48c99b") if i%2==0 else Color("#538be8"))
		i += 1
