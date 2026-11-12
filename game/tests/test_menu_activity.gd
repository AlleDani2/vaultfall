extends GutTest
## Menù laterale: evidenziazione dell'attività in corso (resoconto UI 05). Principale/parallela, pausa, «Riduci animazioni»,
## cambio di schermata, tooltip bilingue, pallino numerico spostato, indicatore ai bordi se la voce è fuori vista.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_menu_activity_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in ["tutorials", "reduce_motion", "locale", "sidebar_groups_closed"]:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
	Settings.set_value("reduce_motion", false)
	Settings.set_value("locale", "it")
	assert_true(Game.new_game(1, "normal", 7))
	for t in ["feature:combat", "skill:farming", "skill:woodcutting", "skill:mining", "feature:estate", "dungeon:cursed_granary",
			"feature:mercenaries", "skill:hero", "feature:talents", "feature:crates", "feature:market"]:
		if not (GameState.data.unlocks as Array).has(t):
			(GameState.data.unlocks as Array).append(t)


func after_each() -> void:
	if Clock.paused:
		Clock.set_paused(false)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	for k in _old:
		Settings.set_value(k, _old[k])


func _main(h: float = 900.0) -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1600, h)
	await wait_process_frames(2)
	return main


func _skills() -> SkillSystem:
	return Game.system("skills") as SkillSystem


func _wood() -> String:
	return str(DataRegistry.actions_for_skill("woodcutting")[0].id)


func test_senza_attivita_nessuna_voce_evidenziata() -> void:
	var main := await _main()
	main.refresh_activity_marks()
	assert_true(MenuActivity.marks().is_empty())
	assert_eq(main.main_mark_id(), "")
	for id in ["skill:woodcutting", "combat", "summary"]:
		assert_true(main.activity_mark(id).is_empty(), id)
	assert_false(main.edge_hints().up or main.edge_hints().down)


func test_mansione_avviata_e_fermata() -> void:
	var main := await _main()
	assert_true(_skills().start(_wood()))
	main.refresh_activity_marks()
	var m: Dictionary = main.activity_mark("skill:woodcutting")
	assert_false(m.is_empty(), "la voce della mansione in corso è evidenziata")
	assert_eq(m.role, MenuActivity.ROLE_MAIN)
	assert_eq(m.state, MenuActivity.STATE_RUN)
	assert_true(m.breathing, "respiro lento della principale")
	assert_true(str(m.tip).begins_with("In corso: "), str(m.tip))
	assert_true(str(m.tip).contains("XP/h"), str(m.tip))
	assert_eq(main.main_mark_id(), "skill:woodcutting")
	var b: Button = main.get("_buttons")["skill:woodcutting"]
	assert_true(b.tooltip_text.contains("In corso: "), "il tooltip della voce dice cosa si fa")
	_skills().stop()
	main.refresh_activity_marks()
	assert_true(main.activity_mark("skill:woodcutting").is_empty(), "fermata: niente più evidenziazione")
	assert_false(b.tooltip_text.contains("In corso: "))
	assert_eq(main.main_mark_id(), "")


func test_cambio_di_schermata_non_cambia_l_evidenziazione() -> void:
	var main := await _main()
	_skills().start(_wood())
	main.refresh_activity_marks()
	for id in ["bank", "summary", "skill:mining", "skill:woodcutting"]:
		main.show_screen(id)
		await wait_process_frames(1)
		main.refresh_activity_marks()
		assert_eq(main.main_mark_id(), "skill:woodcutting", "schermata " + id)
		assert_false(main.activity_mark("skill:woodcutting").is_empty(), id)
	# aperta una voce diversa: quella aperta è «selezionata», quella in corso resta evidenziata (due cose distinte)
	main.show_screen("skill:mining")
	var btns: Dictionary = main.get("_buttons")
	assert_true((btns["skill:mining"] as Button).button_pressed)
	assert_false((btns["skill:woodcutting"] as Button).button_pressed)
	assert_true(main.activity_mark("skill:mining").is_empty())
	assert_false(main.activity_mark("skill:woodcutting").is_empty())


func test_passaggio_a_combattimento_sposta_l_evidenziazione() -> void:
	var main := await _main()
	_skills().start(_wood())
	main.refresh_activity_marks()
	var combat := Game.system("combat") as CombatSystem
	assert_true(combat.start("millbrook"))
	main.refresh_activity_marks()
	assert_true(main.activity_mark("skill:woodcutting").is_empty(), "la mansione non gira più")
	var m: Dictionary = main.activity_mark("combat")
	assert_false(m.is_empty())
	assert_eq(m.role, MenuActivity.ROLE_MAIN)
	assert_true(str(m.tip).begins_with("In corso: Combattimento"), str(m.tip))
	assert_eq(main.main_mark_id(), "combat")
	# e di nuovo la mansione: torna sulla mansione
	_skills().start(_wood())
	main.refresh_activity_marks()
	assert_true(main.activity_mark("combat").is_empty())
	assert_false(main.activity_mark("skill:woodcutting").is_empty())


func _set_activity(d: Dictionary) -> void:
	var a: Dictionary = GameState.data.activity
	a.clear()
	a.merge(d)


func test_dungeon_evidenzia_la_voce_dungeon_con_avanzamento() -> void:
	var main := await _main()
	_set_activity({"type": "combat", "zone": "millbrook", "monster": "", "mode": "dungeon", "dungeon": "cursed_granary", "wave": 1})
	main.refresh_activity_marks()
	var m: Dictionary = main.activity_mark("dungeon")
	assert_false(m.is_empty())
	assert_eq(m.role, MenuActivity.ROLE_MAIN)
	assert_true(str(m.tip).contains("ondata 2/"), str(m.tip))
	assert_true(float(m.frac) > 0.0, "barra: ondate fatte / totali")
	assert_true(main.activity_mark("combat").is_empty(), "dentro il dungeon si evidenzia solo la voce Dungeon")


func test_incursione_boss_mondiale_e_breccia_evidenziano_la_voce_dungeon() -> void:
	var main := await _main()
	var cases := [
		[{"type": "combat", "zone": "", "monster": "", "mode": "raid", "raid": "collectors_den"}, "Incursione"],
		[{"type": "combat", "zone": "", "monster": "", "mode": "wboss", "wb": "wandering_colossus"}, "Boss mondiale"],
		[{"type": "combat", "zone": "", "monster": "", "mode": "rift", "floor": 3}, "Breccia"],
	]
	for c in cases:
		_set_activity(c[0])
		main.refresh_activity_marks()
		var m: Dictionary = main.activity_mark("dungeon")
		assert_false(m.is_empty(), str(c[1]))
		assert_true(str(m.tip).contains(str(c[1])), str(m.tip))
		assert_eq(float(m.frac), -1.0, "nessuna barra senza un avanzamento noto")
		assert_eq(main.main_mark_id(), "dungeon")


func test_pausa_ferma_il_respiro_ma_la_voce_resta_evidenziata() -> void:
	var main := await _main()
	_skills().start(_wood())
	main.refresh_activity_marks()
	assert_true(main.activity_mark("skill:woodcutting").breathing)
	Clock.set_paused(true)
	await wait_process_frames(1)
	var m: Dictionary = main.activity_mark("skill:woodcutting")
	assert_false(m.is_empty(), "in pausa l'attività è ancora «in corso»")
	assert_eq(m.state, MenuActivity.STATE_PAUSED)
	assert_false(m.breathing)
	assert_true(str(m.tip).contains("In pausa"), str(m.tip))
	Clock.set_paused(false)
	await wait_process_frames(1)
	m = main.activity_mark("skill:woodcutting")
	assert_eq(m.state, MenuActivity.STATE_RUN)
	assert_true(m.breathing)
	assert_false(str(m.tip).contains("In pausa"))


func test_riduci_animazioni_resta_visibile_ma_ferma() -> void:
	var main := await _main()
	Settings.set_value("reduce_motion", true)
	_skills().start(_wood())
	main.refresh_activity_marks()
	var m: Dictionary = main.activity_mark("skill:woodcutting")
	assert_false(m.is_empty(), "sfondo, icona e barra restano")
	assert_false(m.breathing, "nessuna animazione")
	# l'impostazione si cambia a partita in corso: il respiro parte e si ferma da solo
	Settings.set_value("reduce_motion", false)
	assert_true(main.activity_mark("skill:woodcutting").breathing)
	Settings.set_value("reduce_motion", true)
	assert_false(main.activity_mark("skill:woodcutting").breathing)


func test_orto_in_crescita_e_parallelo_non_principale() -> void:
	var main := await _main()
	_skills().start(_wood())
	var f := Game.system("farming") as FarmingSystem
	var kind := str(DataRegistry.table("farming_plots")[0].id)
	f.state.plots[kind][0] = {"crop": "x", "remaining_s": 30.0, "total_s": 60.0, "auto": false}
	main.refresh_activity_marks()
	var farm: Dictionary = main.activity_mark("skill:farming")
	assert_false(farm.is_empty())
	assert_eq(farm.role, MenuActivity.ROLE_SIDE)
	assert_true(str(farm.tip).begins_with("Anche in corso: "), str(farm.tip))
	assert_eq(main.activity_mark("skill:woodcutting").role, MenuActivity.ROLE_MAIN)
	assert_eq(main.main_mark_id(), "skill:woodcutting", "la principale resta una sola")
	# tutto pronto da raccogliere: non cresce più nulla, resta il pallino numerico e non l'evidenziazione
	f.state.plots[kind][0] = {"crop": "x", "remaining_s": 0.0, "total_s": 60.0, "auto": false}
	main.refresh_activity_marks()
	assert_true(main.activity_mark("skill:farming").is_empty())


func test_tenuta_che_produce_e_parallela() -> void:
	var main := await _main()
	var es := Game.system("estate") as EstateSystem
	if es.total_units_per_hour() <= 0.0:
		var sec := MenuActivity.marks()
		assert_false(sec.has("estate"), "senza produzione non è evidenziata")
		return
	main.refresh_activity_marks()
	assert_eq(main.activity_mark("estate").role, MenuActivity.ROLE_SIDE)


func test_tooltip_in_inglese_e_pallino_spostato() -> void:
	Settings.set_value("locale", "en")
	var main := await _main()
	_skills().start(_wood())
	main.refresh_activity_marks()
	var m: Dictionary = main.activity_mark("skill:woodcutting")
	assert_true(str(m.tip).begins_with("In progress: "), str(m.tip))
	assert_false(str(m.tip).contains("UI_MENUACT"), "nessuna chiave nuda")
	# il pallino numerico lascia il posto all'icona e torna al suo posto quando la voce si spegne
	var badge := (main.get("_badges") as Dictionary)["skill:woodcutting"] as PanelContainer
	var right_on := badge.offset_right
	_skills().stop()
	main.refresh_activity_marks()
	assert_almost_eq(badge.offset_right - right_on, MenuMark.ICON_W, 0.01)


func test_ricostruzione_del_menu_mantiene_l_evidenziazione() -> void:
	var main := await _main()
	_skills().start(_wood())
	main.refresh_activity_marks()
	Settings.set_value("locale", "en")
	EventBus.locale_changed.emit("en")
	await wait_process_frames(2)
	assert_false(main.activity_mark("skill:woodcutting").is_empty(), "i segni sono ricreati sui nuovi pulsanti")
	assert_eq(main.main_mark_id(), "skill:woodcutting")


func test_indicatore_ai_bordi_quando_la_voce_e_fuori_vista() -> void:
	Settings.set_value("sidebar_groups_closed", ["*"])      # F4: il test misura un menù più lungo della finestra → nessun gruppo richiuso
	var main := await _main(480.0)
	main.get("_sidebar").set_all_skills_open(true)
	var combat := Game.system("combat") as CombatSystem
	assert_true(combat.start("millbrook"))
	main.refresh_activity_marks()
	await wait_process_frames(2)
	main.refresh_activity_marks()
	var sc := main.get("_menu_scroll") as ScrollContainer
	var btn: Button = main.get("_buttons")["combat"]
	var hidden := btn.global_position.y + btn.size.y > sc.global_position.y + sc.size.y
	assert_true(hidden, "a 480 px di altezza la voce Combattimento e' fuori vista (e' il presupposto del test)")
	if not hidden:
		return
	assert_true(main.edge_hints().down, "voce sotto il bordo: indicatore in basso")
	assert_false(main.edge_hints().up)
	var hint := main.find_child("EdgeDown", true, false) as Button
	assert_true(hint.text.begins_with("In corso: "), hint.text)
	hint.pressed.emit()
	await wait_process_frames(3)
	main.refresh_activity_marks()
	assert_false(main.edge_hints().down, "dopo il clic il menù scorre e la voce è in vista")


func test_indicatore_assente_con_voce_in_vista() -> void:
	var main := await _main(900.0)
	_skills().start(_wood())
	main.refresh_activity_marks()
	await wait_process_frames(2)
	main.refresh_activity_marks()
	assert_false(main.edge_hints().up or main.edge_hints().down)


func test_barra_di_avanzamento_segue_il_ciclo() -> void:
	var main := await _main()
	_skills().start(_wood())
	main.refresh_activity_marks()
	var f0 := float(main.activity_mark("skill:woodcutting").frac)
	assert_true(f0 >= 0.0 and f0 <= 1.0)
	_skills().tick(1.0)
	main.call("_tick_marks")
	var f1 := float(main.activity_mark("skill:woodcutting").frac)
	assert_true(f1 > f0 or f1 < f0, "il ciclo avanza (o riparte)")


func test_costo_dell_aggiornamento_resta_piccolo() -> void:
	var main := await _main()
	_skills().start(_wood())
	var f := Game.system("farming") as FarmingSystem
	var kind := str(DataRegistry.table("farming_plots")[0].id)
	f.state.plots[kind][0] = {"crop": "x", "remaining_s": 30.0, "total_s": 60.0, "auto": false}
	var t0 := Time.get_ticks_usec()
	for i in 100:
		main.refresh_activity_marks()
	var per_call_ms := float(Time.get_ticks_usec() - t0) / 100.0 / 1000.0
	gut.p("refresh_activity_marks: %.3f ms a chiamata (2 Hz)" % per_call_ms)
	assert_lt(per_call_ms, 5.0, "gira a 2 Hz: deve costare molto meno di un fotogramma")
	var t1 := Time.get_ticks_usec()
	for i in 1000:
		main.call("_tick_marks")
	var tick_ms := float(Time.get_ticks_usec() - t1) / 1000.0 / 1000.0
	gut.p("_tick_marks: %.4f ms a chiamata (10 Hz)" % tick_ms)
	assert_lt(tick_ms, 0.5)
