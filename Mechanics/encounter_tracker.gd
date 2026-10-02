class_name EncounterTracker
extends RefCounted

# One tracker for the trainer prevents overlapping zones doubling checks.
var distance: float = 0.0
var cooldown: float = 0.0
var previous_position: Vector3
var current_zone: EncounterZone
var initialized: bool = false
var rng := RandomNumberGenerator.new()

func reset_position(position: Vector3) -> void:
	previous_position = position
	initialized = true
	distance = 0.0
	current_zone = null

func after_battle(position: Vector3) -> void:
	reset_position(position)
	cooldown = 4.0

func update(position: Vector3, grounded: bool, zone: EncounterZone, exploration: bool) -> PokemonInstance:
	if not initialized:
		reset_position(position)
		return null
	var traveled := Vector2(position.x - previous_position.x, position.z - previous_position.z).length()
	previous_position = position
	if zone != current_zone:
		current_zone = zone
		distance = 0.0
	if not exploration or not grounded or zone == null or traveled > 10.0:
		distance = 0.0
		return null
	if cooldown > 0.0:
		var consumed := minf(cooldown, traveled)
		cooldown -= consumed
		traveled -= consumed
	distance += traveled
	while distance >= zone.check_distance:
		distance -= zone.check_distance
		if rng.randf() < zone.encounter_chance:
			var pokemon := zone.roll(rng)
			if pokemon != null:
				distance = 0.0
				return pokemon
	return null
