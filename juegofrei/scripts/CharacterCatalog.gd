extends RefCounted
## Four provisional entries; add/replace Resources without changing selection UI.
const Definition = preload("res://scripts/CharacterDefinition.gd")
const ENTRIES: Array[Resource] = [preload("res://resources/characters/Indigo.tres"),preload("res://resources/characters/Amber.tres"),preload("res://resources/characters/Mint.tres"),preload("res://resources/characters/Violet.tres")]

static func valid_pair(pair: Array) -> bool:
	if pair.size()!=2: return false
	for entry: Variant in pair:
		if not entry is Definition or not entry.is_valid(): return false
	return true
