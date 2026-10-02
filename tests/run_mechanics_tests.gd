extends SceneTree

var checks := 0
var failures := 0
const TEST_SAVE := "res://.godot/mechanics_test_save.json"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func battle(team: Array[PokemonInstance], enemy: PokemonInstance = null) -> BattleEngine:
	var engine := BattleEngine.new()
	engine.start(team, PokemonInstance.create(PokemonCatalog.RATTATA, 3) if enemy == null else enemy, 0, 20)
	engine.rng.seed = 42
	engine.begin_turn()
	return engine

func seed_for_catch(chance: float, succeeds: bool) -> int:
	var random := RandomNumberGenerator.new()
	for seed_value in 1000:
		random.seed = seed_value
		if (random.randf() < chance) == succeeds: return seed_value
	return 0

func run() -> void:
	var pika := PokemonInstance.create(PokemonCatalog.PIKACHU, 5)
	var other := PokemonInstance.create(PokemonCatalog.PIKACHU, 5)
	check(pika.instance_id != other.instance_id, "Unique instance IDs")
	pika.move_pp[0] = 0
	check(other.move_pp[0] == 30, "PP isn't shared between instances")
	pika.heal()
	var base_hp := pika.max_hp()
	pika.current_hp -= 4
	pika.gain_experience(91)
	check(pika.level == 6 and pika.experience == 216, "Cubic experience threshold")
	check(pika.current_hp == pika.max_hp() - 4 and pika.max_hp() > base_hp, "Level-up increases current HP by max-HP gain")
	pika = PokemonInstance.create(PokemonCatalog.PIKACHU, 5)
	var pidgey := PokemonInstance.create(PokemonCatalog.PIDGEY, 5)
	var rattata := PokemonInstance.create(PokemonCatalog.RATTATA, 5)
	var shock := PokemonCatalog.PIKACHU.moves[0]
	check(BattleEngine.effectiveness("electric", pidgey.species.types) == 2.0, "Electric is effective against Flying")
	check(BattleEngine.effectiveness("normal", pidgey.species.types) == 1.0, "Normal is neutral")
	check(BattleEngine.effectiveness("electric", pika.species.types) == 0.5, "Electric resistance")
	check(BattleEngine.calculate_damage(pika, pidgey, shock) > BattleEngine.calculate_damage(pika, rattata, shock), "Damage uses type effectiveness")
	var engine := battle([pika], PokemonInstance.create(PokemonCatalog.RATTATA, 100))
	check(engine.player_goes_first(PokemonCatalog.PIKACHU.moves[1], PokemonCatalog.RATTATA.moves[0]), "Move priority beats Speed")
	check(not engine.player_goes_first(shock, PokemonCatalog.RATTATA.moves[0]), "Speed determines equal-priority order")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	var old_enemy_pp := engine.wild.move_pp[0]
	engine.wild.current_hp = 1
	check(engine.submit("fight", 1), "Accept a legal fight action")
	check(not engine.submit("fight", 1), "Repeated actions locked during resolution")
	check(engine.wild.move_pp[0] == old_enemy_pp, "Fainted opponent never executes queued attack")
	var old_exp := engine.active().experience
	engine.complete_resolution()
	check(engine.state == BattleEngine.Phase.FINISHED and engine.active().experience > old_exp, "Victory awards experience and finishes")
	var reward_exp := engine.active().experience
	engine.complete_resolution()
	check(engine.active().experience == reward_exp, "Resolution cannot award experience twice")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	engine.active().move_pp = [0, 0]
	check(not engine.submit("fight", 0), "Depleted move is blocked")
	check(engine.submit("fight", -1), "Struggle available when all PP exhausted")
	check(engine.log_messages.any(func(line: String) -> bool: return "Struggle" in line), "Struggle attack used")
	check(engine.active().current_hp < engine.active().max_hp(), "Struggle recoil damages user")
	engine.complete_resolution()
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	engine.balls = 0
	check(not engine.submit("catch") and engine.state == BattleEngine.Phase.CHOOSE_ACTION, "Empty bag doesn't consume a turn")
	engine.balls = 20
	while engine.party.size() < 6: engine.party.append(PokemonInstance.create(PokemonCatalog.PIDGEY, 4))
	check(not engine.submit("catch") and engine.balls == 20, "Full party blocks catching without ball consumption")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	check(is_equal_approx(BattleEngine.catch_chance(engine.wild), 0.15), "Full-HP catch probability")
	engine.wild.current_hp = 1
	check(BattleEngine.catch_chance(engine.wild) > 0.7, "Low HP improves catch chance")
	engine.rng.seed = seed_for_catch(BattleEngine.catch_chance(engine.wild), true)
	var caught_id := engine.wild.instance_id
	old_exp = engine.active().experience
	engine.submit("catch")
	engine.complete_resolution()
	check(engine.party.size() == 2 and engine.party[1].instance_id == caught_id, "Capture keeps exact wild instance")
	check(engine.balls == 19 and engine.pending_outcome == "caught", "Capture consumes exactly one ball")
	check(engine.active().experience == old_exp, "Capture awards no defeat experience")
	check(not engine.submit("catch") and engine.party.size() == 2, "Duplicate capture prevented")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	engine.rng.seed = seed_for_catch(BattleEngine.catch_chance(engine.wild), false)
	engine.submit("catch")
	engine.complete_resolution()
	check(engine.party.size() == 1 and engine.balls == 19 and engine.active().current_hp < engine.active().max_hp(), "Failed capture allows opponent attack")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5), PokemonInstance.create(PokemonCatalog.PIDGEY, 5)])
	check(not engine.submit("switch", 0), "Cannot switch into active Pokémon")
	engine.submit("switch", 1)
	check(engine.party[1].current_hp < engine.party[1].max_hp(), "Voluntary switching consumes a turn")
	engine.complete_resolution()
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5), PokemonInstance.create(PokemonCatalog.PIDGEY, 5)])
	engine.active().current_hp = 1
	engine.submit("catch") # Force a failed attempt, then faint.
	# If this seed caught, use a fresh guaranteed failure instead.
	if engine.pending_outcome == "caught":
		engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5), PokemonInstance.create(PokemonCatalog.PIDGEY, 5)])
		engine.active().current_hp = 1
		engine.rng.seed = seed_for_catch(BattleEngine.catch_chance(engine.wild), false)
		engine.submit("catch")
	engine.complete_resolution()
	check(engine.state == BattleEngine.Phase.FORCE_SWITCH, "Fainting requires healthy replacement")
	var replacement_hp := engine.party[1].current_hp
	check(engine.submit("switch", 1), "Forced switch accepted")
	check(engine.party[1].current_hp == replacement_hp, "Forced switch doesn't trigger an extra attack")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	engine.active().current_hp = 1
	engine.rng.seed = seed_for_catch(BattleEngine.catch_chance(engine.wild), false)
	engine.submit("catch")
	var outcomes: Array[String] = []
	engine.finished.connect(func(outcome: String) -> void: outcomes.append(outcome))
	engine.complete_resolution()
	check(outcomes == ["defeated"], "Entire party defeat reported once")
	engine.complete_resolution()
	check(outcomes.size() == 1, "Finish signal isn't repeated")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	old_exp = engine.active().experience
	engine.submit("run")
	engine.complete_resolution()
	check(engine.pending_outcome == "escaped" and engine.active().experience == old_exp, "Run succeeds without XP")
	engine = battle([PokemonInstance.create(PokemonCatalog.PIKACHU, 5)])
	engine.active().move_pp = [0, 0]
	engine.active().current_hp = 1
	engine.wild.current_hp = 1
	engine.submit("fight", -1)
	engine.complete_resolution()
	check(engine.pending_outcome == "defeated", "Simultaneous last-Pokémon KO returns to healing instead of leaving an unusable party")
	var fainted := PokemonInstance.create(PokemonCatalog.PIKACHU, 5)
	fainted.current_hp = 0
	fainted.gain_experience(91)
	check(fainted.level == 6 and fainted.current_hp == 0, "Leveling doesn't silently revive a fainted Pokémon")
	_test_encounters()
	_test_saves()
	var session := root.get_node("GameSession")
	session.save_path = "res://.godot/mechanics_session_test.json"
	session.party.clear()
	session.party.append(PokemonInstance.create(PokemonCatalog.PIKACHU, 5))
	session.party[0].current_hp = 1
	session.party[0].move_pp[0] = 0
	session.balls = 7
	var exp: int = session.party[0].experience
	session.heal_party()
	check(session.party[0].current_hp == session.party[0].max_hp() and session.party[0].move_pp[0] == 30, "Healing restores HP and PP")
	check(session.balls == 7 and session.party[0].experience == exp, "Healing preserves inventory and XP")
	session.start_battle(PokemonInstance.create(PokemonCatalog.RATTATA, 3))
	session.battle.begin_turn()
	session.battle.active().current_hp = 1
	session.battle.rng.seed = seed_for_catch(BattleEngine.catch_chance(session.battle.wild), false)
	session.battle.submit("catch")
	session.battle.complete_resolution()
	check(session.mode == session.Mode.EXPLORATION and session.party[0].current_hp == session.party[0].max_hp(), "Session heals after defeat and returns to exploration")
	check(session.new_game() and session.party.size() == 1 and session.balls == 20, "New Game resets session after archiving old save")
	var preserved := FileAccess.open(session.save_path, FileAccess.WRITE)
	preserved.store_string("unreadable original")
	preserved.close()
	session.save_blocked = true
	session.balls = 8
	session.save_progress()
	check(FileAccess.get_file_as_string(session.save_path) == "unreadable original", "Recovery mode blocks autosave over unreadable data")
	check(session.new_game() and not session.save_blocked, "Confirmed New Game exits recovery after preserving original")
	print("MECHANICS TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_encounters() -> void:
	var zone: EncounterZone = load("res://Mechanics/encounter_zone.tscn").instantiate()
	zone.encounter_chance = 1.0
	var tracker := EncounterTracker.new()
	tracker.reset_position(Vector3.ZERO)
	check(tracker.update(Vector3.ZERO, true, zone, true) == null, "Standing still cannot trigger encounters")
	check(tracker.update(Vector3(1, 0, 0), true, zone, true) == null, "Movement below two meters doesn't roll")
	check(tracker.update(Vector3(2, 0, 0), true, zone, true) != null, "Two meters of grounded grass movement rolls encounter")
	check(tracker.update(Vector3(5, 0, 0), true, null, true) == null, "Outside grass never encounters")
	check(tracker.update(Vector3(8, 0, 0), false, zone, true) == null, "Airborne movement doesn't count")
	check(tracker.update(Vector3(10, 0, 0), true, zone, false) == null, "Menu and battle movement don't count")
	tracker.after_battle(Vector3.ZERO)
	check(tracker.update(Vector3(4, 0, 0), true, zone, true) == null and tracker.cooldown == 0.0, "Four-meter cooldown blocks post-battle encounters")
	check(tracker.update(Vector3(6, 0, 0), true, zone, true) != null, "Checks resume after cooldown plus two meters")
	var second: EncounterZone = load("res://Mechanics/encounter_zone.tscn").instantiate()
	second.encounter_chance = 1.0
	tracker.reset_position(Vector3.ZERO)
	tracker.update(Vector3.ONE, true, zone, true)
	check(tracker.update(Vector3.ONE, true, second, true) == null, "Overlapping zone checks don't count same movement twice")
	check(tracker.update(Vector3(100, 0, 0), true, second, true) == null, "Teleport distance is discarded")
	var seen := {}
	tracker.rng.seed = 19
	for i in 100:
		var pokemon := zone.roll(tracker.rng)
		seen[pokemon.species.id] = true
		check(pokemon.level >= 3 and pokemon.level <= 5, "Encounter level range")
	check(seen.has("pidgey") and seen.has("rattata"), "Both weighted species can spawn")
	zone.free()
	second.free()

func _test_saves() -> void:
	var team: Array[PokemonInstance] = [PokemonInstance.create(PokemonCatalog.PIKACHU, 5), PokemonInstance.create(PokemonCatalog.PIDGEY, 3)]
	team[1].current_hp = 2
	team[1].move_pp[0] = 3
	check(SaveStore.write_save(TEST_SAVE, team, 12, 1) == OK, "Save written using temporary file and replacement")
	var loaded := SaveStore.read_save(TEST_SAVE)
	check(not loaded.has("error") and loaded.party[1].instance_id == team[1].instance_id and loaded.balls == 12 and loaded.lead == 1, "Save roundtrip keeps instances, inventory, and lead")
	check(loaded.party[1].current_hp == 2 and loaded.party[1].move_pp[0] == 3 and loaded.party[1].experience == 27, "Save roundtrip keeps HP, PP, and XP")
	check(SaveStore.write_save(TEST_SAVE, team, 11, 0) == OK and SaveStore.read_save(TEST_SAVE).balls == 11, "Atomic replacement updates existing save")
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	var bad := valid.duplicate(true)
	bad.party[1].id = bad.party[0].id
	check(SaveStore.decode(bad).has("error"), "Reject duplicate IDs")
	bad = valid.duplicate(true)
	bad.party[0].hp = -1
	check(SaveStore.decode(bad).has("error"), "Reject impossible HP")
	bad = valid.duplicate(true)
	bad.party[0].pp[0] = 100
	check(SaveStore.decode(bad).has("error"), "Reject impossible PP")
	bad = valid.duplicate(true)
	bad.party[0].species = "res://malicious.gd"
	check(SaveStore.decode(bad).has("error"), "Save cannot load arbitrary resource paths")
	bad = valid.duplicate(true)
	bad.version = 999
	check(SaveStore.decode(bad).has("error"), "Unknown save version rejected")
	bad = valid.duplicate(true)
	bad.balls = 1.5
	check(SaveStore.decode(bad).has("error"), "Fractional inventory rejected")
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("not JSON")
	file.close()
	check(SaveStore.read_save(TEST_SAVE).has("error"), "Corrupted JSON returns recovery result")
	check(FileAccess.get_file_as_string(TEST_SAVE) == "not JSON", "Unreadable save remains untouched")
