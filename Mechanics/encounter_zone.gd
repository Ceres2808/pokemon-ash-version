class_name EncounterZone
extends Area3D

@export_range(0.0, 1.0) var encounter_chance: float = 0.2
@export_range(0.1, 20.0) var check_distance: float = 2.0
@export var entries: Array[EncounterEntry] = []

func _ready() -> void:
	add_to_group("encounter_zones")

func roll(rng: RandomNumberGenerator) -> PokemonInstance:
	var total := 0.0
	for entry in entries:
		if entry.species != null: total += maxf(0.0, entry.weight)
	if total <= 0.0: return null
	var choice := rng.randf() * total
	for entry in entries:
		if entry.species == null or entry.weight <= 0.0: continue
		choice -= entry.weight
		if choice < 0.0:
			return PokemonInstance.create(entry.species, rng.randi_range(entry.min_level, maxi(entry.min_level, entry.max_level)))
	return null
