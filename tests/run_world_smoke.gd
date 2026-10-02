extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func wait_frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	var scene: Node3D = load("res://pallet_town.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await wait_frames(45)
	var session := root.get_node("GameSession")
	session.save_path = "res://.godot/world_smoke_save.json"
	var player: PlayerCharacter = scene.get_node("PlayerCharacter")
	var world: Node3D = scene.get_node("Mechanics")
	print("WORLD POSITIONS: player=", player.global_position, " grounded=", player.is_on_floor(), " grass=", world.grass.global_position, " healing=", world.healing_position)
	check(player.is_on_floor(), "Starting location is on walkable ground")
	check(world.grass != null and world.ui != null, "World grass and UI initialize")
	var before := player.global_position
	Input.action_press(player.move_forward_action)
	await wait_frames(60)
	Input.action_release(player.move_forward_action)
	check(player.global_position.distance_to(before) > 0.5, "Walking moves the trainer")
	world.respawn()
	await wait_frames(30)
	world.ui.toggle_party()
	check(player.input_locked and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Party UI releases mouse and freezes trainer")
	before = player.global_position
	Input.action_press(player.move_forward_action)
	await wait_frames(20)
	Input.action_release(player.move_forward_action)
	check(player.global_position.is_equal_approx(before), "Movement is frozen in party menu")
	world.ui.toggle_party()
	check(not player.input_locked and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "Closing menu restores controls")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	world._input(tab)
	check(session.mode == session.Mode.MENU, "Logical-key-only Tab events open party menu")
	world._input(tab)
	check(session.mode == session.Mode.EXPLORATION, "Tab closes party menu")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await wait_frames(3)
	check(session.mode == session.Mode.MENU, "Escape opens party through real input dispatch")
	escape.pressed = false
	Input.parse_input_event(escape)
	await wait_frames(3)
	escape.pressed = true
	Input.parse_input_event(escape)
	await wait_frames(3)
	check(session.mode == session.Mode.EXPLORATION and not player.cam_holder.mouse_free and not player.cam_holder.manage_mouse_capture, "Closing party with Escape avoids legacy mouse-capture conflict")
	escape.pressed = false
	Input.parse_input_event(escape)
	# Walk the actual corridor from spawn to the grass instead of teleporting.
	world.respawn()
	await wait_frames(15)
	player.cam_holder.rotation.y = 0.0
	Input.action_press(player.move_forward_action)
	Input.action_press(player.run_action)
	await wait_frames(130)
	Input.action_release(player.move_forward_action)
	Input.action_release(player.run_action)
	check(player.global_position.z < -34, "Route 1 corridor is reachable without jumping")
	player.cam_holder.rotation.y = PI / 2.0
	Input.action_press(player.move_forward_action)
	await wait_frames(160)
	Input.action_release(player.move_forward_action)
	check(world.grass.overlaps_body(player), "Marked grass is reachable from the corridor on foot")
	# A random encounter on the approach is valid, but finish it for the controlled test.
	if session.mode == session.Mode.BATTLE:
		session.battle.begin_turn()
		session.battle.submit("run")
		session.battle.complete_resolution()
	world.grass.encounter_chance = 1.0
	player.global_position = world.grass.global_position + Vector3(0, 0.85, 0)
	world.tracker.reset_position(player.global_position)
	await wait_frames(20)
	check(player.is_on_floor(), "Grass is on walkable terrain")
	check(world.grass.overlaps_body(player), "Grass Area3D detects player")
	Input.action_press(player.move_forward_action)
	await wait_frames(90)
	Input.action_release(player.move_forward_action)
	check(session.mode == session.Mode.BATTLE, "Actual walking inside grass triggers a battle")
	if session.mode == session.Mode.BATTLE:
		check(player.input_locked and world.battle_props != null, "Battle freezes player and creates proxies")
		while session.battle.state == BattleEngine.Phase.INTRODUCTION: await physics_frame
		check(world.ui.battle_panel.visible, "Battle HUD is visible")
		check(not world.grass_label.visible, "World sign stays out of the battle screen")
		var enemy: PokemonInstance = session.battle.wild
		enemy.current_hp = 1
		var random := RandomNumberGenerator.new()
		for seed_value in 1000:
			random.seed = seed_value
			if random.randf() < BattleEngine.catch_chance(enemy):
				session.battle.rng.seed = seed_value
				break
		world.queue_action("catch")
		await wait_frames(50)
		check(session.party.size() == 2 and session.party[1] == enemy, "Live capture adds exact opponent")
		check(session.mode == session.Mode.EXPLORATION and not player.input_locked, "Capture restores exploration")
		check(world.grass_label.visible, "Grass sign returns after battle")
		check(world.tracker.cooldown > 3.9, "Live battle activates encounter cooldown")
		world.respawn()
		await wait_frames(20)
		player.global_position = world.healing_position + Vector3.UP * 0.9
		await wait_frames(20)
		check(world.near_healing(), "Healing point can be reached")
		session.party[0].current_hp = 2
		session.heal_party()
		check(session.party[0].current_hp == session.party[0].max_hp(), "Live healing restores party")
		check(not SaveStore.read_save(session.save_path).has("error"), "Live progress can reload")
		session.select_lead(1)
		var reloaded: Node = load("res://Mechanics/game_session.gd").new()
		root.add_child(reloaded)
		reloaded.save_path = session.save_path
		reloaded.load_progress()
		check(reloaded.party.size() == 2 and reloaded.party[1].instance_id == enemy.instance_id and reloaded.balls == 19 and reloaded.lead_index == 1, "A fresh session restores captured identity, inventory, party, and lead")
		check(reloaded.party.size() == 2 and reloaded.party[1].current_hp == enemy.max_hp() and reloaded.party[1].move_pp[0] == 35 and reloaded.party[1].experience == enemy.experience, "A fresh session restores healed HP, PP, and experience")
		check(reloaded.battle == null and reloaded.mode == reloaded.Mode.EXPLORATION, "A fresh session resumes exploration without an unfinished battle")
		reloaded.queue_free()
	print("WORLD SMOKE: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
