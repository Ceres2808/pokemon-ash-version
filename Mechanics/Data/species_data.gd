class_name SpeciesData
extends Resource

@export var id: String
@export var display_name: String
@export var types: Array[String] = ["normal"]
@export var base_hp: int = 40
@export var base_attack: int = 45
@export var base_defense: int = 40
@export var base_speed: int = 50
@export var experience_yield: int = 50
@export var color: Color = Color.WHITE
@export var moves: Array[MoveData] = []
