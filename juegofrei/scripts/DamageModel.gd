extends Node
const Attack = preload("res://scripts/AttackData.gd")
signal damage_changed(percent: float)
signal stocks_changed(stocks: int)
@export var starting_stocks: int = 3
@export var percent_growth: float = 0.012
@export var knockback_multiplier: float = 1.0
@export var maximum_knockback: float = 1800.0
var percent: float = 0.0
var stocks: int = 3

func launch_strength(data: Attack, accumulated_percent: float) -> float:
	return minf(maximum_knockback, data.base_knockback * (1.0 + accumulated_percent * percent_growth) * knockback_multiplier)

func apply_hit(data: Attack, direction: Vector2) -> Vector2:
	percent = minf(999.0, percent + data.damage)
	damage_changed.emit(percent)
	return direction.normalized() * launch_strength(data, percent)

func lose_stock() -> int:
	stocks = maxi(0, stocks - 1)
	stocks_changed.emit(stocks)
	return stocks

func reset_damage() -> void:
	percent = 0.0
	damage_changed.emit(percent)

func reset_match() -> void:
	stocks = starting_stocks
	reset_damage()
	stocks_changed.emit(stocks)
