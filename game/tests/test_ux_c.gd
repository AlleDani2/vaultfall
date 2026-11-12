extends GutTest
## Revisione UX da nuovo giocatore (docs/audit_2026-10-22/90_REVISIONE_UX.md): primo passo guidato nel Riepilogo,
## riquadro Paralleli senza duplicati né tagli, riga della finitura sotto l'oggetto nell'Eroe, motivi dei pulsanti spenti.

const SUMMARY := "res://src/ui/screens/SummaryScreen.tscn"
const HERO := "res://src/ui/screens/HeroScreen.tscn"
const DUNGEON := "res://src/ui/screens/DungeonScreen.tscn"

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ux_c_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 11))


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String, params: Dictionary = {}) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open(params)
	return s


func test_riepilogo_nuova_partita_guida_al_primo_passo() -> void:
	var s := _open(SUMMARY)
	await wait_process_frames(2)
	s.refresh()
	assert_true(s.is_new_game())
	assert_eq(s._tip.text, tr("UI_UXC_TIP_FIRST"), "al primo avvio il consiglio è il primo passo, non una battuta")
	assert_true(s._start_btn.visible, "pulsante «Comincia con...» quando non c'è nulla in corso")
	assert_eq(s._start_skill, "woodcutting")
	assert_true(s._start_btn.text.contains(Loc.t(DataRegistry.get_def("skills", "woodcutting").name)))
	var asked: Array = []
	EventBus.screen_requested.connect(func(id: String, _p: Dictionary) -> void: asked.append(id))
	s._start_btn.pressed.emit()
	assert_eq(asked, ["skill:woodcutting"])


func test_riepilogo_pulsante_sparisce_con_attivita_o_dopo_i_primi_minuti() -> void:
	var s := _open(SUMMARY)
	await wait_process_frames(2)
	(Game.system("skills") as SkillSystem).start("wc_pine")
	s.refresh()
	assert_false(s._start_btn.visible, "con una mansione in corso non serve")
	(Game.system("skills") as SkillSystem).stop()
	GameState.data.stats["playtime_s"] = 3600.0
	s.refresh()
	assert_false(s.is_new_game())
	assert_false(s._start_btn.visible, "chi gioca da un'ora non vuole il pulsante")


func test_riepilogo_sta_in_uno_scorrimento_e_non_impone_l_altezza() -> void:
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_true(main.show_screen("summary"))
	var cur: Control = main.current_screen()
	assert_true(_in_scroll(cur), "il Riepilogo scorre invece di allungare la finestra")
	assert_true(main.show_screen("bank"))
	await wait_process_frames(2)
	assert_true(_in_scroll(main.current_screen()), "dal QA overflow (107) ogni schermata sta nello scorrimento della finestra")
	assert_true(main.show_screen("summary"))
	await wait_process_frames(2)
	assert_eq(main.find_children("ScreenScroll", "ScrollContainer", true, false).size(), 1, "un solo scorrimento, quello della scena")


func _in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func test_paralleli_combattimento_titolo_breve_e_valore_che_si_accorcia() -> void:
	var zone := str(DataRegistry.table("zones")[0].id)
	GameState.data.activity = {"type": "combat", "zone": zone, "monster": ""}
	assert_eq(ActivityText.combat_zone(), Loc.t(DataRegistry.get_def("zones", zone).name))
	var panel := ParallelsPanel.new()
	add_child_autofree(panel)
	panel.refresh()
	var row := panel.row_button("active")
	assert_not_null(row)
	var head: HBoxContainer = (row.get_child(0) as Control).get_child(0)
	assert_eq((head.get_child(0) as Label).text, ActivityText.combat_zone(), "titolo: la zona")
	assert_eq((head.get_child(1) as Label).text, tr("UI_MENU_COMBAT"), "valore: Combattimento, corto")
	assert_true((head.get_child(1) as Label).clip_text, "un valore lungo si accorcia con i puntini")
	assert_eq((head.get_child(1) as Label).text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	GameState.data.activity = {}


func test_eroe_riga_finitura_separata_dal_nome_dell_oggetto() -> void:
	var s := _open(HERO)
	await wait_process_frames(2)
	for slot in s.SLOT_ORDER:
		var fin: Label = s._finish_labels[slot]
		var row := fin.get_meta("row") as Control
		assert_not_null(row, slot)
		assert_false(row.visible, "senza finitura la riga non occupa spazio: " + slot)
		assert_true(fin.clip_text)


func test_eroe_classe_bloccata_in_combattimento_dice_perche() -> void:
	(Game.system("combat") as CombatSystem).state.class = "warrior"
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 5, "record_level": 5, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "zone:saltreach", "skill:hero"])
	var combat := Game.system("combat") as CombatSystem
	var s := _open(HERO)
	await wait_process_frames(2)
	assert_false(s._class_note.text.contains(tr("UI_UXC_CLASS_NOT_IN_COMBAT")), "fermo: nessun avviso")
	if combat.start(str(DataRegistry.table("zones")[0].id)):
		s._refresh_class()
		assert_true(s._class_opt.disabled)
		assert_true(s._class_note.text.contains(tr("UI_UXC_CLASS_NOT_IN_COMBAT")), "il menù spento spiega il motivo")


func test_dungeon_pulsante_spento_ha_il_motivo_nel_tooltip() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 5, "record_level": 5, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "dungeon:cursed_granary", "zone:saltreach", "skill:hero"])
	var ds := _open(DUNGEON, {"dungeon": "cursed_granary"})
	await wait_process_frames(2)
	ds.refresh()
	assert_true(ds._enter_btn.disabled)
	assert_false(ds._enter_btn.tooltip_text.is_empty(), "il pulsante spento spiega cosa manca")
	GameState.data.skills["hero"].level = 30
	ds.refresh()
	assert_false(ds._enter_btn.disabled)
	assert_eq(ds._enter_btn.tooltip_text, "")


func test_stringhe_nuove_bilingui() -> void:
	for k in ["UI_UXC_TIP_FIRST", "UI_UXC_GO_SKILL", "UI_UXC_CLASS_NOT_IN_COMBAT"]:
		for loc in ["it", "en"]:
			TranslationServer.set_locale(loc)
			assert_ne(tr(k), k, "%s manca in %s" % [k, loc])
	TranslationServer.set_locale(Settings.get_value("locale"))
