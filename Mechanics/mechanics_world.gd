extends Node3D

@export var player_path: NodePath = NodePath("../PlayerCharacter")
@export var grass_center: Vector3 = Vector3(-1.5, 0, -38)
@export var healing_center: Vector3 = Vector3(5, 0, -22)
@export var resolution_delay: float = 0.65
var player: PlayerCharacter
var tracker := EncounterTracker.new()
var grass: EncounterZone
var grass_label: Label3D
var healing_position: Vector3
var respawn_transform: Transform3D
var ui: CanvasLayer
var battle_props: Node3D
var friendly_label: Label3D
var friendly_mesh: MeshInstance3D

func _ready() -> void:
	player = get_node(player_path)
	respawn_transform = player.global_transform
	player.can_jump = false
	player.allow_advanced_movement = false
	player.continious_run = false
	player.hud.hide()
	player.cam_holder.enable_headbob = false
	player.cam_holder.enable_forward_tilt = false
	player.cam_holder.enable_side_tilt = false
	player.cam_holder.manage_mouse_capture = false
	tracker.rng.randomize()
	GameSession.mode_changed.connect(_sync_controls)
	GameSession.battle_started.connect(_battle_started)
	GameSession.battle_ended.connect(_battle_ended)
	ui = preload("res://Mechanics/mechanics_ui.gd").new()
	ui.world = self
	add_child(ui)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_setup_world()
	_sync_controls()
	if not GameSession.recovery_message.is_empty(): ui.show_recovery(GameSession.recovery_message)

func ground_at(position_hint: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(position_hint + Vector3.UP * 80, position_hint + Vector3.DOWN * 80, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else position_hint

func _setup_world() -> void:
	grass = preload("res://Mechanics/encounter_zone.tscn").instantiate()
	add_child(grass)
	grass.global_position = ground_at(grass_center)
	# Simple strips mark the encounter area without replacing imported assets.
	for x in range(-3, 4, 2):
		for z in range(-4, 5, 2):
			var strip := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.5, 0.12, 1.5)
			strip.mesh = box
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.2, 0.7, 0.25)
			strip.material_override = material
			grass.add_child(strip)
			strip.global_position = ground_at(grass.global_position + Vector3(x, 0, z)) + Vector3.UP * 0.08
	grass_label = _make_label(grass, "ROUTE 1 — ENCOUNTER GRASS\nWalk here to find wild Pokémon", Vector3(0, 2.0, 0))
	healing_position = ground_at(healing_center)
	var heal_marker := Node3D.new()
	heal_marker.name = "HealingPoint"
	add_child(heal_marker)
	heal_marker.global_position = healing_position
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.45
	cylinder.bottom_radius = 0.45
	cylinder.height = 0.8
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 0.9)
	mesh.material_override = material
	heal_marker.add_child(mesh)
	mesh.position.y = 0.4
	_make_label(heal_marker, "HEALING POINT\n[E] Restore HP + PP", Vector3(0, 1.6, 0))
	tracker.reset_position(player.global_position)

func _physics_process(_delta: float) -> void:
	if player == null or grass == null: return
	var zone: EncounterZone = null
	for candidate in get_tree().get_nodes_in_group("encounter_zones"):
		if candidate.overlaps_body(player):
			zone = candidate
			break
	var wild := tracker.update(player.global_position, player.is_on_floor(), zone, GameSession.mode == GameSession.Mode.EXPLORATION)
	if wild != null: GameSession.start_battle(wild)
	ui.set_world_hint("[E] Heal party" if near_healing() else ("Encounter grass — keep walking" if zone != null else "WASD move · Shift sprint · Tab party · Esc menu"))
	if GameSession.mode == GameSession.Mode.EXPLORATION and player.global_position.y < -80:
		respawn()

func near_healing() -> bool:
	return player.global_position.distance_to(healing_position + Vector3.UP * 0.8) < 3.0

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_TAB and GameSession.mode != GameSession.Mode.BATTLE:
		ui.toggle_party()
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE:
		if GameSession.mode != GameSession.Mode.BATTLE: ui.toggle_party()
		get_viewport().set_input_as_handled()
	elif key == KEY_E and GameSession.mode == GameSession.Mode.EXPLORATION and near_healing():
		GameSession.heal_party()
		get_viewport().set_input_as_handled()

func _sync_controls() -> void:
	player.input_locked = GameSession.mode != GameSession.Mode.EXPLORATION
	player.velocity = Vector3.ZERO
	player.cam_holder.mouse_free = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if player.input_locked else Input.MOUSE_MODE_CAPTURED

func _battle_started() -> void:
	grass_label.hide()
	battle_props = Node3D.new()
	player.cam.add_child(battle_props)
	# Camera-relative placeholders stay visible on slopes and beside walls.
	_make_pokemon_proxy(GameSession.battle.active(), Vector3(-0.85, 0.05, -2.6), true)
	_make_pokemon_proxy(GameSession.battle.wild, Vector3(0.9, 0.2, -3.3), false)
	GameSession.battle.changed.connect(_update_proxy)
	await get_tree().create_timer(resolution_delay).timeout
	if GameSession.mode == GameSession.Mode.BATTLE: GameSession.battle.begin_turn()

func queue_action(action: String, index: int = -1) -> void:
	if GameSession.mode != GameSession.Mode.BATTLE: return
	var battle := GameSession.battle
	if not battle.submit(action, index): return
	if battle.state != BattleEngine.Phase.RESOLVING: return
	await get_tree().create_timer(resolution_delay).timeout
	if GameSession.battle == battle: battle.complete_resolution()

func _battle_ended(outcome: String) -> void:
	grass_label.show()
	if outcome in ["defeated", "reset"]: respawn()
	tracker.after_battle(player.global_position)
	if is_instance_valid(battle_props): battle_props.queue_free()
	friendly_label = null
	friendly_mesh = null
	_sync_controls()
	var save_status := "not saved (recovery mode)" if GameSession.save_blocked else "saved"
	if not GameSession.last_save_error.is_empty(): save_status = "not saved — " + GameSession.last_save_error
	ui.show_notice("Battle complete — %s. Progress %s." % [outcome, save_status])

func respawn() -> void:
	player.global_transform = respawn_transform
	player.velocity = Vector3.ZERO
	tracker.reset_position(player.global_position)

func _make_pokemon_proxy(pokemon: PokemonInstance, at: Vector3, friendly: bool) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = pokemon.species.color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	mesh.material_override = material
	battle_props.add_child(mesh)
	mesh.position = at
	var label := _make_label(battle_props, pokemon.species.display_name, at + Vector3.UP * 0.55)
	if friendly:
		friendly_label = label
		friendly_mesh = mesh

func _update_proxy() -> void:
	if not is_instance_valid(friendly_label): return
	friendly_label.text = GameSession.battle.active().species.display_name
	friendly_mesh.material_override.albedo_color = GameSession.battle.active().species.color

func _make_label(parent: Node3D, text: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	label.position = at
	return label
