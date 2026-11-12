extends GutTest
## T-4.4/4.5/4.6: schermata Missioni, Prossimi traguardi, Bentornato, Manuale, benvenuto e tutorial (UI headless).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old_tutorials: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_quests_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_tutorials = Settings.get_value("tutorials")


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("tutorials", _old_tutorials)


func _quests() -> QuestSystem:
	return Game.system("quests") as QuestSystem


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func _host(main: Control) -> OverlayHost:
	for c in main.get_children():
		if c is OverlayHost:
			return c
	return null


# ------------------------------------------------------------------ partenza della nuova partita

func test_nuova_partita_parte_con_un_solo_mestiere() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	assert_eq(_quests().current_main(), "main_c0_q1")
	assert_eq(GameState.data.unlocks, ["skill:woodcutting"], "solo il Taglialegna: gli altri si aprono uno alla volta")


func test_voci_grigie_con_indicazione() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	var btn: Button = main._buttons["skill:mining"]
	assert_true(btn.disabled or btn.has_meta("req_target"), "grigia: disattivata o (UI-B, G37) cliccabile verso la missione che la sblocca")
	assert_true(btn.tooltip_text.length() > 0 and not btn.tooltip_text.begins_with("UI_"), "tooltip con la missione che la sblocca")
	assert_true(ScreenRegistry.is_unlocked(ScreenRegistry.get_entry("skill:woodcutting"), GameState.data.unlocks), "il Taglialegna è aperto")
	assert_false(main.show_screen("vault_hall"), "bloccata")
	assert_true(main.show_screen("quests"))
	assert_true(main.show_screen("manual"))


func test_benvenuto_poi_tutorial() -> void:
	Settings.set_value("tutorials", true)
	Game.new_game(1, "normal", 5)
	var main := await _main()
	var host := _host(main)
	await wait_process_frames(2)
	assert_null(host.find_child("Dedica", true, false), "nessuna dedica personale: il gioco può uscire su Steam")
	assert_true(_quests().intro_pending())
	# chiusura: primo pulsante della finestra
	var go: Button = host.find_child("WelcomeGo", true, false)
	go.pressed.emit()
	await wait_process_frames(3)
	assert_false(_quests().intro_pending())
	# il Taglialegna ha il passo guidato con evidenziazione (TutorialDirector), non più la scheda a 3 righe
	assert_null(host.find_child("TutorialTitle", true, false))
	assert_false(host.is_busy())
	# una funzione senza passo guidato conserva la scheda a 3 righe
	_quests().state.tut_pending.append("feature:secrets")
	EventBus.unlocked.emit("feature:secrets")
	await wait_process_frames(3)
	var ok: Button = host.find_child("TutorialOk", true, false)
	assert_not_null(ok, "scheda a 3 righe per i sistemi senza passo guidato")
	ok.pressed.emit()
	await wait_process_frames(3)
	assert_false(host.is_busy())


func test_tutorial_disattivabile() -> void:
	Settings.set_value("tutorials", false)
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	var main := await _main()
	var host := _host(main)
	await wait_process_frames(3)
	assert_false(host.is_busy(), "nessuna finestra con i tutorial spenti")
	assert_false(_quests().tutorial_pending())


# ------------------------------------------------------------------ schermata Missioni e traguardi

func test_schermata_missioni_e_riscatto() -> void:
	Settings.set_value("reduce_motion", true)
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	var main := await _main()
	assert_true(main.show_screen("quests"))
	await wait_process_frames(2)
	var screen: Control = main.current_screen()
	assert_not_null(screen.find_child("Card_main_c0_q1", true, false), "scheda della missione attiva")
	assert_null(screen.find_child("ClaimButton", true, false))
	# completa la prima missione: i tronchi di Pino richiesti dai dati
	var need := QuestSystem.target_of(_quests().quest_def("main_c0_q1").objectives[0])
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": need}])
	Game.sim.tick(0.1)
	main._on_ui_tick()
	await wait_process_frames(2)
	var claim: Button = screen.find_child("ClaimButton", true, false)
	assert_not_null(claim, "missione pronta: pulsante Riscatta")
	var before := GameState.gold()
	claim.pressed.emit()
	await wait_process_frames(2)
	assert_true(_quests().is_done("main_c0_q1"))
	assert_eq(_quests().current_main(), "main_c0_q2", "la storia prosegue da sola")
	Settings.set_value("reduce_motion", false)
	assert_gte(GameState.gold(), before)


func test_prossimi_traguardi() -> void:
	Game.new_game(1, "normal", 5)
	var lines := Milestones.lines(_quests(), DataRegistry)
	assert_gte(lines.size(), 3)
	assert_true(lines[0].text.length() > 0 and not lines[0].text.contains("{"))
	var main := await _main()
	var sm: Control = main.current_screen()
	assert_eq(sm.get_node("%Milestones").get_child_count(), lines.size())


# ------------------------------------------------------------------ Bentornato

func test_bentornato_unisce_le_sezioni() -> void:
	var rep := {
		"skills": {"items": {"log_pine": 120, "bird_nest": 2}, "xp": {"woodcutting": 840.0}, "levels": {"woodcutting": [3, 6]},
			"stop": {"key": "UI_QUESTS_WB_NOTHING", "params": {}}},
		"estate": {"rows": [{"key": "UI_QUESTS_WB_MORE", "params": {"n": 5}}], "crates": {"crate_millbrook": 2}},
		"quests": {"progressed": ["main_c0_q1"], "ready": ["main_c0_q1"], "items": {"log_pine": 999}},
	}
	var m := WelcomeBack.build(7200.0, rep, DataRegistry, 43200.0)
	assert_false(m.empty)
	assert_eq(m.crates, 2)
	assert_eq(m.ready_quests, ["main_c0_q1"])
	var text := ""
	for s in m.sections:
		text += "\n".join(s.lines) + "\n"
	assert_true(text.contains(NumberFormat.fmt(120)), "somma degli oggetti dalla sezione skills")
	assert_false(text.contains(NumberFormat.fmt(999)), "il ripiego dei segnali non vale se un'altra sezione fornisce gli oggetti")
	assert_true(text.contains("3") and text.contains("6"), "livelli da-a")
	# ripiego: nessuno fornisce le casse -> vale quello della sezione quests
	var m2 := WelcomeBack.build(100.0, {"quests": {"crates": {"crate_millbrook": 3}}}, DataRegistry, 3600.0)
	assert_eq(m2.crates, 3)
	assert_true(WelcomeBack.build(100.0, {}, DataRegistry, 3600.0).empty)


func test_bentornato_finestra_dopo_assenza() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	Settings.set_value("tutorials", false)
	var main := await _main()
	var host := _host(main)
	EventBus.item_gained.emit("log_pine", 50, "woodcutting")
	var rep := Game.sim.run_offline(7200.0)
	EventBus.offline_progress.emit(7200.0, rep)
	await wait_process_frames(2)
	assert_true(host.is_busy(), "finestra Bentornato aperta")
	assert_not_null(host.find_child("WbCollect", true, false))
	(host.find_child("WbCollect", true, false) as Button).pressed.emit()
	await wait_process_frames(3)
	assert_false(host.is_busy())
	EventBus.offline_progress.emit(30.0, {})
	await wait_process_frames(2)
	assert_false(host.is_busy(), "assenze brevi: nessuna finestra")


# ------------------------------------------------------------------ Manuale

func test_manuale_pagine_dai_dati() -> void:
	var unlocks: Array = []
	for p in ManualPages.PAGES:
		var t := ManualPages.build(p, DataRegistry, unlocks)
		assert_gt(t.length(), 40, "pagina non vuota: " + p)
		assert_false(t.contains("{") , "nessun segnaposto non risolto in " + p)
	var f := ManualPages.build("formulas", DataRegistry, unlocks)
	assert_true(f.contains(NumberFormat.fmt(Formulas.xp_to_next(10))), "XP del livello 10 dalla formula")
	var c := ManualPages.build("crates", DataRegistry, unlocks)
	assert_true(c.contains(NumberFormat.decimal(79.2, 2, Loc.locale())), "probabilità nominale della Rara")
	assert_true(c.contains(Loc.t(DataRegistry.item("crate_millbrook").name)), "ogni Cassa elencata")
	var d0 := ManualPages.build("drops", DataRegistry, [])
	assert_true(d0.contains(tr("UI_QUESTS_MAN_D_LOCKED")))
	var d1 := ManualPages.build("drops", DataRegistry, ["zone:millbrook"])
	assert_true(d1.contains(Loc.t(DataRegistry.get_def("monsters", "mud_slime").name)))
	var u := ManualPages.build("unlocks", DataRegistry, unlocks)
	assert_true(u.contains(UnlockSystem.hint_for("feature:crates", DataRegistry)) or u.contains("Si sblocca") or u.contains("Unlocks"))


func test_manuale_schermata() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	Settings.set_value("tutorials", false)
	var main := await _main()
	assert_true(main.show_screen("manual"))
	await wait_process_frames(2)
	var s: Control = main.current_screen()
	assert_gt(s.get_node("%Body").text.length(), 40)
	s.show_page("crates")
	assert_true(s.get_node("%Body").text.length() > 40)
