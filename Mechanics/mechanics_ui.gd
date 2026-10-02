extends CanvasLayer

var world: Node3D
var status: Label
var hint: Label
var notice: Label
var battle_panel: PanelContainer
var actions: VBoxContainer
var log_view: RichTextLabel
var ally_info: Label
var enemy_info: Label
var ally_hp: ProgressBar
var enemy_hp: ProgressBar
var party_panel: PanelContainer
var party_rows: VBoxContainer
var reset_dialog: ConfirmationDialog
var recovery_dialog: AcceptDialog
var submenu: String = "main"
var last_battle: BattleEngine
var notice_serial: int = 0

func _ready() -> void:
	layer = 10
	var overlay := Control.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status = _label(overlay, "", Vector2(20, 16))
	hint = _label(overlay, "", Vector2(20, 49))
	notice = _label(overlay, "", Vector2(20, 80))
	var crosshair := _label(overlay, "+", Vector2.ZERO)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(6, 12)
	battle_panel = PanelContainer.new()
	overlay.add_child(battle_panel)
	battle_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	battle_panel.offset_left = 20
	battle_panel.offset_right = -20
	battle_panel.offset_top = -305
	battle_panel.offset_bottom = -15
	var battle_box := HBoxContainer.new()
	battle_box.add_theme_constant_override("separation", 25)
	battle_panel.add_child(_margin(battle_box))
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 245
	battle_box.add_child(stats)
	ally_info = _label(stats, "")
	ally_hp = ProgressBar.new()
	stats.add_child(ally_hp)
	enemy_info = _label(stats, "")
	enemy_hp = ProgressBar.new()
	stats.add_child(enemy_hp)
	actions = VBoxContainer.new()
	actions.custom_minimum_size.x = 270
	battle_box.add_child(actions)
	log_view = RichTextLabel.new()
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(190, 255)
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 18)
	battle_box.add_child(log_view)
	party_panel = PanelContainer.new()
	overlay.add_child(party_panel)
	party_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	party_panel.offset_left = -370
	party_panel.offset_right = 370
	party_panel.offset_top = -280
	party_panel.offset_bottom = 280
	var scroll := ScrollContainer.new()
	party_panel.add_child(_margin(scroll))
	party_rows = VBoxContainer.new()
	party_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(party_rows)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "Start a new game?"
	reset_dialog.dialog_text = "Start over with level-5 Pikachu and 20 Poké Balls?\nYour current save will be archived."
	add_child(reset_dialog)
	reset_dialog.confirmed.connect(func() -> void: GameSession.new_game())
	recovery_dialog = AcceptDialog.new()
	recovery_dialog.title = "Save recovery"
	add_child(recovery_dialog)
	recovery_dialog.confirmed.connect(func() -> void: GameSession.set_mode(GameSession.Mode.EXPLORATION))
	recovery_dialog.canceled.connect(func() -> void: GameSession.set_mode(GameSession.Mode.EXPLORATION))
	GameSession.changed.connect(refresh)
	GameSession.mode_changed.connect(refresh)
	GameSession.message.connect(show_notice)
	GameSession.battle_started.connect(func() -> void: submenu = "main"; refresh())
	refresh()

func _label(parent: Node, text: String, at: Vector2 = Vector2.ZERO) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	if not parent is Container: label.position = at
	return label

func _margin(content: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_child(content)
	return margin

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _button(parent: Node, text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.disabled = disabled
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func set_world_hint(text: String) -> void:
	hint.text = text if GameSession.mode == GameSession.Mode.EXPLORATION else ""

func show_notice(text: String) -> void:
	notice.text = text
	notice_serial += 1
	var serial := notice_serial
	await get_tree().create_timer(5.0).timeout
	if serial == notice_serial: notice.text = ""

func show_recovery(text: String) -> void:
	GameSession.set_mode(GameSession.Mode.MENU)
	recovery_dialog.dialog_text = text
	recovery_dialog.popup_centered(Vector2i(650, 180))

func toggle_party() -> void:
	if reset_dialog.visible or recovery_dialog.visible: return
	GameSession.set_mode(GameSession.Mode.EXPLORATION if GameSession.mode == GameSession.Mode.MENU else GameSession.Mode.MENU)

func refresh() -> void:
	if status == null: return
	status.text = "Pokémon Ash Version | Poké Balls: %d | Party: %d/6%s" % [GameSession.balls, GameSession.party.size(), " | SAVE RECOVERY: progress not saved" if GameSession.save_blocked else ""]
	battle_panel.visible = GameSession.mode == GameSession.Mode.BATTLE
	party_panel.visible = GameSession.mode == GameSession.Mode.MENU and not recovery_dialog.visible
	if battle_panel.visible: _refresh_battle()
	if party_panel.visible: _refresh_party()

func _refresh_battle() -> void:
	var battle := GameSession.battle
	if battle != last_battle:
		last_battle = battle
		log_view.clear()
	log_view.text = "\n".join(battle.log_messages)
	ally_info.text = "%s Lv.%d\nHP %d / %d" % [battle.active().species.display_name, battle.active().level, battle.active().current_hp, battle.active().max_hp()]
	enemy_info.text = "Wild %s Lv.%d\nHP %d / %d" % [battle.wild.species.display_name, battle.wild.level, battle.wild.current_hp, battle.wild.max_hp()]
	ally_hp.max_value = battle.active().max_hp()
	ally_hp.value = battle.active().current_hp
	enemy_hp.max_value = battle.wild.max_hp()
	enemy_hp.value = battle.wild.current_hp
	_clear(actions)
	if battle.state in [BattleEngine.Phase.INTRODUCTION, BattleEngine.Phase.RESOLVING]:
		_label(actions, "Resolving turn…" if battle.state == BattleEngine.Phase.RESOLVING else "Wild encounter!")
		return
	if battle.state == BattleEngine.Phase.FORCE_SWITCH:
		_label(actions, "Choose a healthy Pokémon")
		_party_buttons(actions, true)
		return
	match submenu:
		"fight":
			if not battle.active().has_pp():
				_button(actions, "Struggle (recoil)", func() -> void: _act("fight", -1))
			else:
				for i in battle.active().species.moves.size():
					var move := battle.active().species.moves[i]
					_button(actions, "%s · %d/%d PP" % [move.display_name, battle.active().move_pp[i], move.max_pp], func() -> void: _act("fight", i), battle.active().move_pp[i] == 0)
		"bag":
			var reason := "Party full — catching unavailable" if battle.party.size() >= 6 else ("No Poké Balls left" if battle.balls == 0 else "Lower HP improves catching")
			_label(actions, reason)
			_button(actions, "Throw Poké Ball (%d)" % battle.balls, func() -> void: _act("catch"), battle.balls == 0 or battle.party.size() >= 6)
		"party": _party_buttons(actions, true)
		_:
			_button(actions, "Fight", func() -> void: _show_submenu("fight"))
			_button(actions, "Bag", func() -> void: _show_submenu("bag"))
			_button(actions, "Pokémon", func() -> void: _show_submenu("party"))
			_button(actions, "Run", func() -> void: _act("run"))
	if submenu != "main": _button(actions, "Back", func() -> void: _show_submenu("main"))

func _show_submenu(value: String) -> void:
	submenu = value
	refresh()

func _act(action: String, index: int = -1) -> void:
	submenu = "main"
	world.queue_action(action, index)

func _party_buttons(parent: Node, in_battle: bool) -> void:
	for i in GameSession.party.size():
		var pokemon := GameSession.party[i]
		var lead := GameSession.battle.active_index if in_battle else GameSession.lead_index
		_button(parent, "%s Lv.%d · %d/%d HP%s" % [pokemon.species.display_name, pokemon.level, pokemon.current_hp, pokemon.max_hp(), " (active)" if i == lead else ""],
			func() -> void: _act("switch", i) if in_battle else GameSession.select_lead(i), pokemon.current_hp == 0 or i == lead)

func _refresh_party() -> void:
	_clear(party_rows)
	_label(party_rows, "PARTY — Select a healthy Pokémon to lead")
	_party_buttons(party_rows, false)
	for pokemon in GameSession.party:
		var moves: Array[String] = []
		for i in pokemon.species.moves.size(): moves.append("%s %d/%d PP" % [pokemon.species.moves[i].display_name, pokemon.move_pp[i], pokemon.species.moves[i].max_pp])
		_label(party_rows, "%s · EXP %d · %s\n%s" % [pokemon.species.display_name, pokemon.experience, "/".join(pokemon.species.types), ", ".join(moves)])
	_button(party_rows, "Return to exploration [Tab / Esc]", func() -> void: GameSession.set_mode(GameSession.Mode.EXPLORATION))
	_button(party_rows, "New Game…", func() -> void: reset_dialog.popup_centered())
