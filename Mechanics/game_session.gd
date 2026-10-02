extends Node

signal changed
signal mode_changed
signal battle_started
signal battle_ended(outcome: String)
signal message(text: String)

enum Mode { EXPLORATION, MENU, BATTLE }
const SAVE_PATH := "user://pokemon_save_v1.json"
var party: Array[PokemonInstance] = []
var balls: int = 20
var lead_index: int = 0
var mode: Mode = Mode.EXPLORATION
var battle: BattleEngine
var save_blocked: bool = false
var recovery_message: String = ""
var last_save_error: String = ""
var save_path: String = SAVE_PATH

func _ready() -> void:
	# Test runs never read or overwrite the player's save.
	if OS.get_cmdline_user_args().has("--mechanics-test"):
		save_path = "user://mechanics_test_session.json"
		_fresh_party()
		return
	load_progress()

func load_progress() -> void:
	save_blocked = false
	recovery_message = ""
	last_save_error = ""
	var loaded := SaveStore.read_save(save_path)
	if loaded.has("error"):
		_fresh_party()
		save_blocked = true
		recovery_message = "%s Your original save is preserved. You can play without saving, or choose New Game to archive it and start fresh." % loaded.error
	elif loaded.has("missing"):
		_fresh_party()
	else:
		party = loaded.party
		balls = loaded.balls
		lead_index = loaded.lead

func _fresh_party() -> void:
	party = [PokemonInstance.create(PokemonCatalog.PIKACHU, 5)]
	balls = 20
	lead_index = 0

func set_mode(next_mode: Mode) -> void:
	mode = next_mode
	mode_changed.emit()

func start_battle(wild: PokemonInstance) -> bool:
	if mode != Mode.EXPLORATION: return false
	battle = BattleEngine.new()
	battle.finished.connect(_on_battle_finished)
	battle.changed.connect(func() -> void: changed.emit())
	battle.start(party, wild, lead_index, balls)
	set_mode(Mode.BATTLE)
	battle_started.emit()
	changed.emit()
	return true

func _on_battle_finished(outcome: String) -> void:
	balls = battle.balls
	lead_index = battle.active_index
	if outcome == "defeated":
		for pokemon in party: pokemon.heal()
		lead_index = 0
	elif party[lead_index].current_hp <= 0:
		for i in party.size():
			if party[i].current_hp > 0:
				lead_index = i
				break
	set_mode(Mode.EXPLORATION)
	save_progress()
	battle_ended.emit(outcome)
	changed.emit()

func select_lead(index: int) -> void:
	if mode == Mode.BATTLE or index < 0 or index >= party.size() or party[index].current_hp <= 0: return
	lead_index = index
	save_progress()
	changed.emit()

func heal_party() -> void:
	if mode != Mode.EXPLORATION: return
	for pokemon in party: pokemon.heal()
	save_progress()
	changed.emit()
	message.emit("Your party's HP and PP are fully restored.")

func save_progress() -> void:
	last_save_error = ""
	if save_blocked: return
	var error := SaveStore.write_save(save_path, party, balls, lead_index)
	if error != OK:
		last_save_error = "Could not save progress: %s" % error_string(error)
		message.emit(last_save_error)

func new_game() -> bool:
	if mode == Mode.BATTLE: return false
	if FileAccess.file_exists(save_path):
		var backup := save_path + ".backup-" + str(Time.get_unix_time_from_system()).replace(".", "-")
		if DirAccess.rename_absolute(save_path, backup) != OK:
			message.emit("Could not archive the old save. New Game was cancelled.")
			return false
	_fresh_party()
	save_blocked = false
	recovery_message = ""
	battle = null
	set_mode(Mode.EXPLORATION)
	save_progress()
	battle_ended.emit("reset")
	changed.emit()
	message.emit("New game started. Your previous save was archived.")
	return true
