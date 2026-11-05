extends Resource
## Durations are physics frames at the project's fixed 60 Hz.
@export var title: String = "Ligero"
@export_range(1, 60) var startup_frames: int = 4
@export_range(1, 60) var active_frames: int = 4
@export_range(1, 120) var recovery_frames: int = 12
@export var damage: float = 6.0
@export var base_knockback: float = 320.0
@export var launch_angle: float = 32.0
@export var up_angle: float = 85.0
@export var down_angle: float = 18.0
@export var aerial_down_angle: float = -80.0
@export var hitstun: float = 0.16
@export var radius: float = 28.0
@export var reach: float = 33.0
@export var cooldown: float = 0.08
@export_range(0, 12) var hitstop_frames: int = 3
## Only used by airborne downward attacks; never modifies shared gravity.
@export_range(0.0, 800.0) var descent_initial_speed: float = 160.0
@export_range(0.0, 800.0) var descent_speed: float = 500.0
@export_range(0.0, 6000.0) var descent_acceleration: float = 1800.0
