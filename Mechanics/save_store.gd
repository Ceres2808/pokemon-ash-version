class_name SaveStore
extends RefCounted

const VERSION := 1

static func write_save(path: String, team: Array[PokemonInstance], balls: int, lead: int) -> Error:
	var records: Array[Dictionary] = []
	for pokemon in team: records.append(pokemon.to_dict())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "party": records, "balls": balls, "lead": lead}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(path + ".tmp", path)

static func read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Cannot read the save file."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {"error": "The save file contains unreadable JSON."}
	return decode(parser.data)

static func whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT: return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func decode(value: Variant) -> Dictionary:
	if not value is Dictionary: return {"error": "Invalid save contents."}
	if not whole_number(value.get("version"), VERSION, VERSION): return {"error": "Unsupported save version."}
	var records: Variant = value.get("party")
	if not records is Array or records.is_empty() or records.size() > 6: return {"error": "Invalid party."}
	if not whole_number(value.get("balls"), 0, 9999) or not whole_number(value.get("lead"), 0, records.size() - 1):
		return {"error": "Invalid inventory or lead."}
	var team: Array[PokemonInstance] = []
	var ids: Dictionary = {}
	for record in records:
		if not record is Dictionary: return {"error": "Invalid Pokémon record."}
		var id: Variant = record.get("id")
		if not id is String or id.length() != 32 or not id.is_valid_hex_number() or ids.has(id):
			return {"error": "Invalid or duplicated Pokémon ID."}
		var species_id: Variant = record.get("species")
		if not species_id is String: return {"error": "Invalid species."}
		var species := PokemonCatalog.find_species(species_id)
		if species == null or not whole_number(record.get("level"), 1, 100): return {"error": "Unknown species or level."}
		var pokemon := PokemonInstance.create(species, int(record.level))
		var next_level := mini(pokemon.level + 1, 100)
		var max_experience := next_level * next_level * next_level - (0 if pokemon.level == 100 else 1)
		if not whole_number(record.get("experience"), pokemon.experience, max_experience): return {"error": "Invalid experience."}
		if not whole_number(record.get("hp"), 0, pokemon.max_hp()): return {"error": "Invalid HP."}
		var pp: Variant = record.get("pp")
		if not pp is Array or pp.size() != species.moves.size(): return {"error": "Invalid move PP."}
		for i in pp.size():
			if not whole_number(pp[i], 0, species.moves[i].max_pp): return {"error": "Invalid move PP."}
		pokemon.instance_id = id
		pokemon.experience = int(record.experience)
		pokemon.current_hp = int(record.hp)
		for i in pp.size(): pokemon.move_pp[i] = int(pp[i])
		team.append(pokemon)
		ids[id] = true
	if not team.any(func(p: PokemonInstance) -> bool: return p.current_hp > 0): return {"error": "Save has no healthy Pokémon."}
	if team[int(value.lead)].current_hp <= 0: return {"error": "Save lead has fainted."}
	return {"party": team, "balls": int(value.balls), "lead": int(value.lead)}
