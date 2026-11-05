from __future__ import annotations
import json
import math
from dataclasses import asdict, dataclass, field
from pathlib import Path

@dataclass
class ColorConfig:
    id: int
    name: str
    lower: list[int]
    upper: list[int]
    min_area: int = 600
    max_area_fraction: float = 0.35
    min_dimension: float = 8.0
    max_aspect_ratio: float = 20.0
    min_saturation: int = 80
    min_confidence: float = 0.55
    ambiguity_ratio: float = 0.8

@dataclass
class CameraConfig:
    index: int = 0
    width: int = 640
    height: int = 480
    fps: int = 30
    backend: str = "dshow"
    mirror: bool = False
    frame_timeout: float = 0.5
    reconnect_delay: float = 1.0
    startup_timeout: float = 8.0
    stall_timeout: float = 2.5

@dataclass
class TrackingConfig:
    confirmation_frames: int = 3
    loss_tolerance: float = 0.15
    position_tau: float = 0.06
    angle_tau: float = 0.09
    max_jump: float = 0.14
    max_speed: float = 1.4
    jitter_allowance: float = 0.025
    reacquire_radius: float = 0.045
    min_fill: float = 0.35
    max_area_fraction: float = 0.45
    morphology_kernel: int = 3
    max_angle_jump: float = 45
    angular_speed: float = 360
    angular_jitter: float = 8

@dataclass
class NetworkConfig:
    host: str = "127.0.0.1"
    port: int = 5005
    hz: int = 30

@dataclass
class Config:
    camera: CameraConfig = field(default_factory=CameraConfig)
    tracking: TrackingConfig = field(default_factory=TrackingConfig)
    network: NetworkConfig = field(default_factory=NetworkConfig)
    colors: list[ColorConfig] = field(default_factory=lambda: [
        ColorConfig(1, "verde", [35, 70, 60], [85, 255, 255]),
        ColorConfig(2, "azul", [95, 80, 60], [135, 255, 255])])

def number(value: object, low: float, high: float, integer: bool = False) -> None:
    if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"Expected finite number in [{low}, {high}], got {value!r}")
    if integer and type(value) is not int:
        raise ValueError("Expected integer")

def validate(config: Config) -> Config:
    c, t, n = config.camera, config.tracking, config.network
    for value, low, high in [(c.index, 0, 32), (c.width, 160, 3840), (c.height, 120, 2160), (c.fps, 1, 120), (n.port, 1, 65535), (n.hz, 1, 60)]:
        number(value, low, high, True)
    if c.backend not in ("dshow", "msmf", "auto") or type(c.mirror) is not bool:
        raise ValueError("Invalid camera backend or mirror flag")
    if n.host != "127.0.0.1":
        raise ValueError("This integration uses loopback IPv4 only")
    number(c.frame_timeout, 0.1, 5)
    number(c.reconnect_delay, 0.2, 10)
    number(c.startup_timeout, 1, 30)
    number(c.stall_timeout, 0.5, 10)
    number(t.confirmation_frames, 1, 20, True)
    number(t.loss_tolerance, 0, 0.4)
    for value in (t.position_tau, t.angle_tau):
        number(value, 0.001, 1)
    for value in (t.max_jump, t.jitter_allowance, t.reacquire_radius):
        number(value, 0.001, 1)
    number(t.max_speed, 0.01, 10)
    number(t.max_angle_jump, 1, 90)
    number(t.angular_speed, 1, 1080)
    number(t.angular_jitter, 0, 45)
    number(t.min_fill, 0, 1)
    number(t.max_area_fraction, 0.01, 0.95)
    number(t.morphology_kernel, 1, 15, True)
    if t.morphology_kernel % 2 != 1:
        raise ValueError("Morphology kernel must be odd")
    if len(config.colors) != 2 or sorted(x.id for x in config.colors) != [1, 2]:
        raise ValueError("Colors must have stable IDs 1 and 2")
    for color in config.colors:
        number(color.id, 1, 2, True)
        if not isinstance(color.name, str) or not color.name or len(color.name) > 40:
            raise ValueError("Invalid color name")
        if not isinstance(color.lower, list) or not isinstance(color.upper, list) or len(color.lower) != 3 or len(color.upper) != 3:
            raise ValueError("HSV bounds must have three components")
        for bounds in (color.lower, color.upper):
            for value, maximum in zip(bounds, (179, 255, 255)):
                number(value, 0, maximum, True)
        if color.lower[1] > color.upper[1] or color.lower[2] > color.upper[2]:
            raise ValueError("S/V lower bounds exceed upper bounds")
        number(color.min_area, 10, 1_000_000, True)
        number(color.max_area_fraction, 0.001, 0.95)
        number(color.min_dimension, 2, 1000)
        number(color.max_aspect_ratio, 1, 100)
        number(color.min_saturation, 0, 255, True)
        number(color.min_confidence, 0, 1)
        number(color.ambiguity_ratio, 0.1, 1)
    return config

def load(path: Path) -> Config:
    def reject_constant(value: str) -> None:
        raise ValueError(f"Nonfinite JSON value: {value}")
    data = json.loads(path.read_text(encoding="utf-8-sig"), parse_constant=reject_constant)
    if not isinstance(data, dict) or set(data) != {"camera", "tracking", "network", "colors"}:
        raise ValueError("Invalid configuration structure")
    try:
        return validate(Config(CameraConfig(**data["camera"]), TrackingConfig(**data["tracking"]),
                               NetworkConfig(**data["network"]), [ColorConfig(**c) for c in data["colors"]]))
    except (TypeError, KeyError, AttributeError) as error:
        raise ValueError(f"Invalid configuration: {error}") from error

def save(config: Config, path: Path) -> None:
    validate(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(asdict(config), ensure_ascii=True, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)
