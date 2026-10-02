class_name BattleEngine
extends RefCounted

signal changed
signal logged(message: String)
signal finished(outcome: String)

enum Phase { INTRODUCTION, CHOOSE_ACTION, RESOLVING, FORCE_SWITCH, FINISHED }
var state: Phase = Phase.INTRODUCTION
var party: Array[PokemonInstance] = []
var wild: PokemonInstance
var active_index: int = 0
var balls: int = 20
var rng := RandomNumberGenerator.new()
var pending_outcome: String = ""
var log_messages: Array[String] = []

func start(team: Array[PokemonInstance], opponent: PokemonInstance, lead: int, inventory: int) -> void:
	party = team
	wild = opponent
	active_index = lead
	balls = inventory
	rng.randomize()
	_log("A wild %s appeared!" % wild.species.display_name)
	changed.emit()

func active() -> PokemonInstance:
	return party[active_index]

func begin_turn() -> void:
	if state == Phase.INTRODUCTION:
		state = Phase.CHOOSE_ACTION
		changed.emit()

static func effectiveness(element: String, types: Array[String]) -> float:
	var multiplier := 1.0
	for type in types:
		if element == "electric" and type == "flying": multiplier *= 2.0
		elif element == "electric" and type == "electric": multiplier *= 0.5
		elif element == "flying" and type == "electric": multiplier *= 0.5
	return multiplier

static func calculate_damage(attacker: PokemonInstance, defender: PokemonInstance, move: MoveData, variation: float = 1.0) -> int:
	var base := ((2.0 * attacker.level / 5.0 + 2.0) * move.power * attacker.attack() / defender.defense()) / 50.0 + 2.0
	var stab := 1.5 if attacker.species.types.has(move.element) else 1.0
	return maxi(1, floori(base * stab * effectiveness(move.element, defender.species.types) * variation))

static func catch_chance(opponent: PokemonInstance) -> float:
	return 0.15 + 0.65 * (1.0 - float(opponent.current_hp) / opponent.max_hp())

func player_goes_first(player_move: MoveData, enemy_move: MoveData) -> bool:
	if player_move.priority != enemy_move.priority: return player_move.priority > enemy_move.priority
	if active().speed() != wild.speed(): return active().speed() > wild.speed()
	return rng.randi_range(0, 1) == 0

func submit(action: String, index: int = -1) -> bool:
	if state == Phase.FORCE_SWITCH:
		if action != "switch" or not _valid_switch(index): return false
		active_index = index
		_log("Go, %s!" % active().species.display_name)
		state = Phase.CHOOSE_ACTION
		changed.emit()
		return true
	if state != Phase.CHOOSE_ACTION: return false
	if action == "fight":
		if active().has_pp():
			if index < 0 or index >= active().move_pp.size() or active().move_pp[index] <= 0: return false
		elif index != -1: return false
	elif action == "catch":
		if balls <= 0 or party.size() >= 6: return false
	elif action == "switch":
		if not _valid_switch(index): return false
	elif action != "run": return false
	state = Phase.RESOLVING
	changed.emit()
	match action:
		"run":
			_log("You escaped safely.")
			pending_outcome = "escaped"
		"catch":
			balls -= 1
			_log("You threw a Poké Ball!")
			if rng.randf() < catch_chance(wild):
				party.append(wild)
				_log("Caught %s! Added to your party." % wild.species.display_name)
				pending_outcome = "caught"
			else:
				_log("It broke free!")
				_enemy_attack()
		"switch":
			active_index = index
			_log("Go, %s!" % active().species.display_name)
			_enemy_attack()
		"fight":
			var player_move := active().species.moves[index] if index >= 0 else PokemonCatalog.STRUGGLE
			var enemy_index := _enemy_move_index()
			var enemy_move := wild.species.moves[enemy_index] if enemy_index >= 0 else PokemonCatalog.STRUGGLE
			if player_goes_first(player_move, enemy_move):
				_attack(active(), wild, player_move, index)
				if wild.current_hp > 0 and active().current_hp > 0: _attack(wild, active(), enemy_move, enemy_index)
			else:
				_attack(wild, active(), enemy_move, enemy_index)
				if active().current_hp > 0 and wild.current_hp > 0: _attack(active(), wild, player_move, index)
	changed.emit()
	return true

func complete_resolution() -> void:
	if state != Phase.RESOLVING: return
	if pending_outcome.is_empty() and wild.current_hp <= 0:
		var reward := maxi(1, floori(float(wild.species.experience_yield * wild.level) / 7.0))
		_log("Wild %s fainted. %s gained %d EXP." % [wild.species.display_name, active().species.display_name, reward])
		var levels := active().gain_experience(reward)
		if levels > 0: _log("%s reached level %d!" % [active().species.display_name, active().level])
		pending_outcome = "won"
		if not party.any(func(p: PokemonInstance) -> bool: return p.current_hp > 0):
			pending_outcome = "defeated"
			_log("Your party fainted too. Returning to the healing point.")
	if not pending_outcome.is_empty():
		state = Phase.FINISHED
		changed.emit()
		finished.emit(pending_outcome)
		return
	if active().current_hp <= 0:
		if party.any(func(p: PokemonInstance) -> bool: return p.current_hp > 0):
			state = Phase.FORCE_SWITCH
			_log("Choose a healthy Pokémon to continue.")
		else:
			_log("Your party fainted. Returning to the healing point.")
			state = Phase.FINISHED
			changed.emit()
			finished.emit("defeated")
			return
	else:
		state = Phase.CHOOSE_ACTION
	changed.emit()

func _valid_switch(index: int) -> bool:
	return index >= 0 and index < party.size() and index != active_index and party[index].current_hp > 0

func _enemy_move_index() -> int:
	var usable: Array[int] = []
	for i in wild.move_pp.size():
		if wild.move_pp[i] > 0: usable.append(i)
	return usable[rng.randi_range(0, usable.size() - 1)] if not usable.is_empty() else -1

func _enemy_attack() -> void:
	var index := _enemy_move_index()
	_attack(wild, active(), wild.species.moves[index] if index >= 0 else PokemonCatalog.STRUGGLE, index)

func _attack(attacker: PokemonInstance, defender: PokemonInstance, move: MoveData, index: int) -> void:
	if attacker.current_hp <= 0: return
	if index >= 0: attacker.move_pp[index] -= 1
	var damage := calculate_damage(attacker, defender, move, rng.randf_range(0.85, 1.0))
	defender.current_hp = maxi(0, defender.current_hp - damage)
	_log("%s used %s! %d damage." % [attacker.species.display_name, move.display_name, damage])
	var multiplier := effectiveness(move.element, defender.species.types)
	if multiplier > 1.0: _log("It's super effective!")
	elif multiplier < 1.0: _log("It's not very effective.")
	if defender.current_hp == 0: _log("%s fainted!" % defender.species.display_name)
	if move.recoil_fraction > 0.0:
		attacker.current_hp = maxi(0, attacker.current_hp - maxi(1, floori(attacker.max_hp() * move.recoil_fraction)))
		_log("%s took recoil damage." % attacker.species.display_name)

func _log(message: String) -> void:
	log_messages.append(message)
	logged.emit(message)
