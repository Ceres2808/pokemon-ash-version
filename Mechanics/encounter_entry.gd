class_name EncounterEntry
extends Resource

@export var species: SpeciesData
@export_range(0.0, 100.0) var weight: float = 1.0
@export_range(1, 100) var min_level: int = 3
@export_range(1, 100) var max_level: int = 5
