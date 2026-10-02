class_name PokemonInstance
extends RefCounted

var instance_id: String
var species: SpeciesData
var level: int
var experience: int
var current_hp: int
var move_pp: Array[int] = []

static func create(data: SpeciesData, starting_level: int) -> PokemonInstance:
	var pokemon := PokemonInstance.new()
	pokemon.instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
	pokemon.species = data
	pokemon.level = clampi(starting_level, 1, 100)
	pokemon.experience = pokemon.level * pokemon.level * pokemon.level
	pokemon.heal()
	return pokemon

func max_hp() -> int:
	return floori(2.0 * species.base_hp * level / 100.0) + level + 10

func attack() -> int:
	return floori(2.0 * species.base_attack * level / 100.0) + 5

func defense() -> int:
	return floori(2.0 * species.base_defense * level / 100.0) + 5

func speed() -> int:
	return floori(2.0 * species.base_speed * level / 100.0) + 5

func heal() -> void:
	current_hp = max_hp()
	move_pp.clear()
	for move in species.moves:
		move_pp.append(move.max_pp)

func gain_experience(amount: int) -> int:
	var previous_level := level
	var previous_max := max_hp()
	experience = mini(experience + maxi(amount, 0), 1000000)
	while level < 100 and experience >= (level + 1) * (level + 1) * (level + 1):
		level += 1
	if current_hp > 0: current_hp = mini(current_hp + max_hp() - previous_max, max_hp())
	return level - previous_level

func has_pp() -> bool:
	return move_pp.any(func(value: int) -> bool: return value > 0)

func to_dict() -> Dictionary:
	return {"id": instance_id, "species": species.id, "level": level,
		"experience": experience, "hp": current_hp, "pp": move_pp.duplicate()}
