extends GutTest
## SkillScreen (scena unica delle mansioni), barra fluida e mansione attiva nella barra superiore.

const SCREEN := "res://src/ui/screens/SkillScreen.tscn"
const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old_reduce: bool


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_skill_screen_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_reduce = Settings.get_value("reduce_motion")
	Settings.set_value("reduce_motion", false)
	assert_true(Game.new_game(1, "normal", 5))


func after_each() -> void:
	Settings.set_value("reduce_motion", _old_reduce)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _screen(skill: String) -> GameScreen:
	var s: GameScreen = (load(SCREEN) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({"skill": skill})
	return s


func _floaters(s: Node) -> int:
	var n := 0
	for c in s.get_children():
		if c is Label and (c as Label).top_level:
			n += 1
	return n


func test_registro_usa_la_scena_unica() -> void:
	assert_eq(ScreenRegistry.SKILL_SCENE, SCREEN)
	var e := ScreenRegistry.get_entry("skill:woodcutting")
	assert_eq(e.params, {"skill": "woodcutting"})
	assert_true(ScreenRegistry.is_available(e, ["skill:woodcutting"]))
	assert_false(ScreenRegistry.is_available(e, []), "bloccata finche' la storia non la sblocca")


func test_apre_ogni_mansione_con_le_sue_azioni() -> void:
	for sk in ["woodcutting", "smithing", "cooking", "thievery", "tailoring", "farming", "hero"]:
		var s := _screen(sk)
		await wait_process_frames(1)
		var expected := 0
		for a in DataRegistry.actions_for_skill(sk):
			if str(a.get("kind", "")) != "crop":
				expected += 1
		assert_eq(s._rows.size(), expected, "una riga per azione: " + sk)
		s.refresh()
		s.close()


func test_avvia_e_ferma_dal_pulsante() -> void:
	var s := _screen("woodcutting")
	var sk := Game.system("skills") as SkillSystem
	s._on_row_pressed("wc_pine")
	assert_eq(sk.current_action(), "wc_pine")
	assert_true(s._stop_btn.visible)
	assert_eq(s._rows["wc_pine"].btn.text, "UI_SKILLS_STOP")
	s._on_row_pressed("wc_pine")
	assert_eq(sk.current_action(), "")
	assert_false(s._stop_btn.visible)


func test_azione_bloccata_dal_livello() -> void:
	var s := _screen("mining")
	s.refresh()
	assert_true(s._rows["mine_tin"].locked, "Lv 10 richiesto")
	assert_true(s._rows["mine_tin"].btn.disabled)
	assert_false(s._rows["mine_copper"].btn.disabled)


func test_effetto_piu_uno_a_ogni_completamento() -> void:
	var s := _screen("woodcutting")
	var sk := Game.system("skills") as SkillSystem
	sk.start("wc_pine")
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 1}])
	assert_true(s._gain_l.text.begins_with("+1"), "testo dell'ultimo guadagno")
	assert_eq(_floaters(s), 1, "un '+1' fluttuante")
	for i in 20:
		EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 1}])
	assert_lte(_floaters(s), s.FX_MAX, "il numero di effetti e' limitato (offline = molti segnali)")
	# altra mansione: nessun effetto
	var before := _floaters(s)
	EventBus.action_completed.emit("mine_copper", [{"item": "ore_copper", "qty": 1}])
	assert_eq(_floaters(s), before)


func test_riduci_animazioni_niente_tween() -> void:
	Settings.set_value("reduce_motion", true)
	var s := _screen("woodcutting")
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 2}])
	assert_true(s._gain_l.text.begins_with("+2"), "il testo si aggiorna comunque")
	assert_eq(_floaters(s), 0, "nessun effetto fluttuante")
	EventBus.level_up.emit("woodcutting", 5)
	assert_eq(s._head_panel.modulate, Color.WHITE, "nessun lampo")


func test_lampo_sul_livello() -> void:
	var s := _screen("woodcutting")
	EventBus.level_up.emit("woodcutting", 7)
	assert_ne(s._head_panel.modulate, Color.WHITE, "lampo dorato all'inizio del tween")
	assert_eq(_floaters(s), 1, "'Livello 7!' fluttuante")
	EventBus.level_up.emit("mining", 3)
	assert_eq(_floaters(s), 1, "altre mansioni non fanno scena")


func test_xp_e_livello_in_intestazione() -> void:
	var s := _screen("woodcutting")
	var sk := Game.system("skills") as SkillSystem
	sk.add_xp("woodcutting", 40.0)
	s.refresh()
	assert_eq(s._level_l.text, tr("UI_SKILLS_LEVEL").format({"n": 1}))
	await wait_seconds(0.4)
	assert_gt(s._xp_bar.value, 0.0, "la barra XP si anima verso il valore")
	sk.add_xp("woodcutting", float(Formulas.xp_total_for_level(10)))
	s.refresh()
	assert_eq(s._level_l.text, tr("UI_SKILLS_LEVEL").format({"n": 10}))


func test_talenti_visibili_e_scegliibili() -> void:
	var s := _screen("woodcutting")
	var sk := Game.system("skills") as SkillSystem
	sk.add_xp("woodcutting", float(Formulas.xp_total_for_level(10)))
	s.refresh()
	var pp := s._perks as SkillPerkPanel
	assert_eq(pp._perk_btn.text, tr("UI_SKILLS_PERKS") + " •", "F7: «Talenti •», il puntino segnala la scelta")
	assert_eq(pp._perk_btn.tooltip_text, tr("UI_SKILLS_PERK_AVAILABLE"), "la frase lunga sta nel suggerimento")
	assert_eq(pp.perk_button().get_parent(), s._hdr.buttons, "il pulsante sta nella testata")
	pp._perk_btn.button_pressed = true
	await wait_process_frames(1)
	assert_gt(pp._perk_box.get_child_count(), 0)
	pp.on_perk_pressed(10, "b")
	assert_eq(sk.chosen_letters("woodcutting", 10), "b")
	s.refresh()
	assert_eq(pp._perk_btn.text, tr("UI_SKILLS_PERKS"), "scelto: niente puntino")
	assert_eq(pp._perk_btn.tooltip_text, Loc.tf("UI_SKILLS_PERKS_NEXT", {"n": 20}), "scelto: il suggerimento dice quando arriva il prossimo talento")


func test_barra_fluida() -> void:
	var bar := SmoothBar.new()
	add_child_autofree(bar)
	bar.set_target(0.5, 0.0)
	assert_almost_eq(bar.value, 0.5, 1e-9, "senza velocita' salta al valore")
	bar.set_target(0.1, 0.2)
	assert_almost_eq(bar.value, 0.1, 1e-9, "fine ciclo: riparte")
	bar.set_target(0.15, 0.2)
	bar._process(0.1)
	assert_almost_eq(bar.value, 0.15 + 0.02 * Clock.speed, 1e-6, "tra un refresh e l'altro avanza con la velocita' nota")
	bar._process(100.0)
	assert_lte(bar.value, 1.0)
	Settings.set_value("reduce_motion", true)
	bar.set_target(0.3, 0.2)
	bar._process(0.1)
	assert_almost_eq(bar.value, 0.3, 1e-9, "riduci animazioni: nessuna interpolazione")


func test_barra_superiore_mostra_la_mansione_attiva() -> void:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	main._on_ui_tick()
	assert_false(main.get_node("%ActivityBar").visible, "a riposo: nessuna barra")
	assert_eq(main.get_node("%Activity").text, tr("UI_SKILLS_TOPBAR_IDLE"))
	var sk := Game.system("skills") as SkillSystem
	sk.start("wc_pine")
	main._on_ui_tick()
	assert_true(main.get_node("%ActivityBar").visible)
	var txt: String = main.get_node("%Activity").text
	assert_true(txt.contains(Loc.t(DataRegistry.action("wc_pine").name)), "nome dell'azione: " + txt)
	for i in 15:
		Game.sim.tick(0.1)
	main._on_ui_tick()
	assert_gt(main.get_node("%ActivityBar").value, 0.0)
	EventBus.level_up.emit("woodcutting", 2)
	main._flush_digest()        # GUILD-2: i livelli si riassumono in una finestra; qui la si chiude subito
	assert_true(main.get_node("%Log").text.length() > 0, "il livello compare nel registro")
