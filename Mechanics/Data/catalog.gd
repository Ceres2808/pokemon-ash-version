class_name PokemonCatalog
extends RefCounted

const PIKACHU: SpeciesData = preload("res://Mechanics/Data/pikachu.tres")
const PIDGEY: SpeciesData = preload("res://Mechanics/Data/pidgey.tres")
const RATTATA: SpeciesData = preload("res://Mechanics/Data/rattata.tres")
const STRUGGLE: MoveData = preload("res://Mechanics/Data/struggle.tres")

static func find_species(id: String) -> SpeciesData:
	match id:
		"pikachu": return PIKACHU
		"pidgey": return PIDGEY
		"rattata": return RATTATA
	return null
