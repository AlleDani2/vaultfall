extends GutTest
## F3 del progetto di interfaccia (docs/ui_redesign/06 §3.4, D9–D13, D25): la colonna destra da 250 px diventa un BINARIO di
## 52 px (RightRail) più un CASSETTO (RightColumn) chiuso di default; l'Obiettivo è una striscia di una riga (GoalStrip/GoalPanel);
## Paralleli e il blocco «Da scoprire» non sono più nel layout.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const KEYS := ["right_col_visible", "right_col_width", "ui_layout_rev", "drawer_section", "tutorials", "notify_loot", "locale"]

var _old_dir: String
var _old: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_right_rail_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in KEYS:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
	Settings.set_value("ui_layout_rev", 2)              # migrazione già fatta: ogni test parte da «cassetto chiuso»
	Settings.set_value("right_col_visible", false)
	Settings.set_value("right_col_width", int(Settings.DEFAULTS["right_col_width"]))
	Settings.set_value("drawer_section", "log")
	ReqLink.reset_cache()


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	for k in _old:
		Settings.set_value(k, _old[k])
	ReqLink.reset_cache()


func _new() -> void:
	assert_true(Game.new_game(1, "normal", 7))


## MainScreen di dimensione logica `sz` (1280×720 = banda normale, 1600×900 = larga, 900×600 = stretta).
func _main(sz: Vector2 = Vector2(1280, 720)) -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = sz
	await wait_process_frames(3)
	return main


func _right(main: Control) -> Control:
	return main.find_child("RightColumn", true, false) as Control


func _rail(main: Control) -> Control:
	return main.find_child("RightRail", true, false) as Control


func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	return e


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


# ------------------------------------------------------------------ binario e cassetto

func test_chiuso_di_default_con_il_binario_sempre_presente() -> void:
	_new()
	var main := await _main()
	assert_false(bool(Settings.DEFAULTS["right_col_visible"]), "predefinito: non fissata")
	assert_false(_right(main).visible, "il cassetto parte chiuso")
	assert_false(main.drawer_open())
	assert_eq(_right(main).get_parent(), main.get_node("Root/Body"), "chiuso: RightColumn sta al suo posto in Root/Body")
	var rail := _rail(main)
	assert_not_null(rail)
	assert_true(rail.visible)
	assert_almost_eq(rail.size.x, 52.0, 1.0, "binario da 52 px")
	var content := main.get_node("Root/Body/Content") as Control
	assert_gte(content.size.x, 1280.0 - 210.0 - 52.0 - 8.0, "il contenuto usa tutto lo spazio a destra del menù, meno il binario")
	assert_not_null(rail.find_child("PushSlot", true, false), "posto riservato alla Sabbia (F14)")
	assert_true(rail.find_child("PushSlot", true, false) is VBoxContainer)
	assert_eq(rail.find_child("PushSlot", true, false).get_child_count(), 1, "F14: il pulsante della Sabbia (nascosto prima dello sblocco)")
	assert_false((rail.find_child("PushButton", true, false) as Control).visible)


func test_il_binario_resta_in_tutte_le_bande() -> void:
	_new()
	for sz in [Vector2(900, 600), Vector2(1280, 720), Vector2(1600, 900)]:
		var main := await _main(sz)
		assert_true(_rail(main).is_visible_in_tree(), "binario visibile a %s" % str(sz))
		assert_almost_eq(_rail(main).size.x, 52.0, 1.0)
		assert_false(_right(main).visible)
		main.queue_free()
		await wait_process_frames(2)


func test_l_apre_e_chiude_il_cassetto() -> void:
	_new()
	var main := await _main()
	assert_true(main.run_shortcut({"type": "column"}))
	await wait_process_frames(2)
	assert_true(main.drawer_open())
	assert_true(_right(main).visible)
	assert_eq(_right(main).get_parent(), main.get_node("Drawer"), "aperto: sopra il contenuto, dentro Drawer")
	assert_true(main.get_node("Drawer/DrawerCatcher").visible, "velo attivo")
	var vp := main.get_viewport().get_visible_rect()
	assert_true(vp.encloses(_right(main).get_global_rect().grow(-1.0)), "dentro la finestra")
	assert_almost_eq(_right(main).get_global_rect().end.x, main.size.x - 52.0, 1.5, "si ferma al bordo del binario")
	main.run_shortcut({"type": "column"})
	await wait_process_frames(2)
	assert_false(main.drawer_open())
	assert_false(_right(main).visible)
	assert_eq(_right(main).get_parent(), main.get_node("Root/Body"), "chiuso: RightColumn torna in Root/Body")


func test_il_pulsante_registro_del_binario_apre_e_chiude() -> void:
	_new()
	var main := await _main()
	var btn := main.find_child("Btn_log", true, false) as Button
	assert_not_null(btn)
	btn.pressed.emit()
	await wait_process_frames(2)
	assert_true(main.drawer_open())
	btn.pressed.emit()
	await wait_process_frames(2)
	assert_false(main.drawer_open())


func test_clic_fuori_chiude() -> void:
	_new()
	var main := await _main()
	main.toggle_column()
	await wait_process_frames(2)
	assert_true(main.drawer_open())
	var catcher := main.get_node("Drawer/DrawerCatcher") as Control
	catcher.gui_input.emit(_click())
	await wait_process_frames(2)
	assert_false(main.drawer_open(), "un clic sul velo chiude il cassetto")
	assert_false(catcher.visible)


func test_esc_chiude_il_cassetto_e_non_cambia_schermata() -> void:
	_new()
	var main := await _main()
	main.show_screen("bank")
	main.toggle_column()
	await wait_process_frames(2)
	assert_true(main.drawer_open())
	# L'EscCatcher è figlio di Drawer: l'input non gestito scende dai figli ai genitori, quindi prende Esc prima di MainScreen
	# (verificato con la finestra vera in scripts/capture_fase3.gd; nei test senza finestra non arrivano eventi dal sistema)
	var esc := main.get_node("Drawer/EscCatcher")
	esc._unhandled_key_input(_esc())
	await wait_process_frames(2)
	assert_false(main.drawer_open(), "Esc chiude il cassetto")
	assert_eq(main.current_id, "bank", "e non porta al Riepilogo")
	esc._unhandled_key_input(_esc())
	assert_eq(main.current_id, "bank", "a cassetto chiuso l'EscCatcher non fa nulla")
	assert_true(main.run_shortcut({"type": "escape"}))
	assert_true(Feedback.is_pause_menu_open(), "e l'Esc di MainScreen apre il menù di pausa")
	assert_eq(main.current_id, "bank")
	Feedback.close_pause_menu()


func test_il_cassetto_ricorda_l_ultima_sezione() -> void:
	_new()
	var main := await _main()
	Game.system("unlock").grant("feature:coop")
	(GameState.data["coop_net"] as Dictionary)["nick"] = "Ale"
	main.call("_update_slow")
	var fr := main.find_child("Btn_friends", true, false) as Button
	assert_true(fr.visible)
	fr.pressed.emit()
	await wait_process_frames(2)
	assert_true(main.drawer_open())
	assert_eq(str(Settings.get_value("drawer_section")), "friends")
	assert_true((main.find_child("AmiciSlot", true, false) as Control).visible)
	assert_false((main.find_child("Log", true, false) as Control).visible)
	main.toggle_column()
	await wait_process_frames(1)
	main.toggle_column()
	await wait_process_frames(2)
	assert_true((main.find_child("AmiciSlot", true, false) as Control).visible, "L riapre sull'ultima sezione")
	(main.find_child("Btn_log", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_true(main.drawer_open(), "dalla sezione Amici il Registro cambia sezione senza chiudere")
	assert_eq(str(Settings.get_value("drawer_section")), "log")
	assert_true((main.find_child("Log", true, false) as Control).visible)


# ------------------------------------------------------------------ fissa

func test_pin_spento_in_banda_normale_e_attivo_in_larga() -> void:
	_new()
	var main := await _main(Vector2(1280, 720))
	main.toggle_column()
	await wait_process_frames(2)
	var pin := main.find_child("Btn_pin", true, false) as Button
	assert_not_null(pin)
	assert_true(pin.disabled, "banda normale: 📌 spento")
	assert_ne(pin.tooltip_text, "", "con il tooltip che dice perché")
	pin.pressed.emit()
	assert_false(bool(Settings.get_value("right_col_visible")), "e non fa nulla")
	main.size = Vector2(1600, 900)
	await wait_process_frames(3)
	assert_eq(main.call("is_narrow"), false)
	assert_false(pin.disabled, "banda larga: 📌 attivo")
	pin.pressed.emit()
	await wait_process_frames(2)
	assert_true(bool(Settings.get_value("right_col_visible")), "fissato = right_col_visible")
	assert_false(main.drawer_open(), "il cassetto è diventato colonna")
	assert_true(_right(main).visible)
	assert_eq(_right(main).get_parent(), main.get_node("Root/Body"), "colonna fissa in Root/Body")
	assert_true(main._grip.visible, "maniglia per ridimensionarla")
	assert_true(pin.active if "active" in pin else true)
	# la preferenza resta, ma tornando in banda normale si usa di nuovo il cassetto (chiuso)
	main.size = Vector2(1280, 720)
	await wait_process_frames(3)
	assert_true(bool(Settings.get_value("right_col_visible")), "la preferenza non si perde")
	assert_false(_right(main).visible, "in banda normale la colonna non si fissa")
	assert_false(main._grip.visible)
	# sblocco del pin con 📌 e con L
	main.size = Vector2(1600, 900)
	await wait_process_frames(3)
	assert_true(_right(main).visible)
	main.toggle_column()
	assert_false(bool(Settings.get_value("right_col_visible")), "L toglie la colonna fissata")
	assert_false(_right(main).visible)


# ------------------------------------------------------------------ Registro (I3)

func test_registro_a_tutta_altezza_a_1280x720() -> void:
	_new()
	var main := await _main(Vector2(1280, 720))
	for i in 60:
		main.add_log("Riga di prova numero %d con un po' di testo" % i, LogCategory.LOOT)
	await wait_process_frames(2)
	main.toggle_column()
	await wait_process_frames(4)
	var right := _right(main)
	var scroll := right.get_node("RightScroll") as ScrollContainer
	var log := main.find_child("Log", true, false) as LogView
	var col := right.get_global_rect()
	assert_true(log.is_visible_in_tree())
	assert_true(col.encloses(log.get_global_rect().grow(-1.0)), "il Registro sta dentro il cassetto")
	assert_gte(log.size.y, col.size.y - 120.0, "e occupa quasi tutta l'altezza (resta solo l'intestazione)")
	var bar := scroll.get_v_scroll_bar()
	assert_lte(bar.max_value, bar.page + 1.0, "nessun figlio tagliato: il cassetto non ha bisogno dello scorrimento esterno")
	var lbar := log.get_v_scroll_bar()
	assert_gt(lbar.max_value, lbar.page, "le righe sono tante: scorrono dentro il Registro")
	assert_gte(log.scroll_vertical, int(lbar.max_value - lbar.page) - 8, "aperto, il Registro è agganciato in fondo")
	var vp := main.get_viewport().get_visible_rect()
	for ch in right.find_children("*", "Control", true, false):
		var c := ch as Control
		if not c.is_visible_in_tree() or c.size.x < 1.0 or c.size.y < 1.0:
			continue
		if log.is_ancestor_of(c):
			continue                                # le righe del Registro stanno nello scorrimento interno
		assert_true(vp.encloses(c.get_global_rect().grow(-1.0)), "%s dentro la finestra" % c.name)


# ------------------------------------------------------------------ Amici

func test_amici_assenti_senza_coop_e_presenti_dopo_una_lobby() -> void:
	_new()
	var main := await _main()
	var fr := main.find_child("Btn_friends", true, false) as Button
	assert_false(fr.visible, "senza coop: niente Amici nel binario")
	Game.system("unlock").grant("feature:coop")
	main.call("_update_slow")
	assert_false(fr.visible, "coop sbloccato ma nessuna lobby aperta: ancora niente")
	var svc := CoopNetService.instance()
	var old_dir := svc.store.dir
	svc.store.dir = SaveService.save_dir + "/coop"
	var err := svc.host_room(24900 + (Time.get_ticks_usec() % 50), "Ale", "Amici", "")
	assert_eq(err, "", "lobby aperta")
	main.call("_update_slow")
	assert_true(fr.visible, "dopo una lobby: Amici nel binario")
	svc.leave_room()
	for gid in svc.store.list_ids():
		svc.store.delete(gid)
	svc.store.dir = old_dir
	main.call("_update_slow")
	assert_true(fr.visible, "il soprannome salvato ricorda che una lobby è stata usata")


# ------------------------------------------------------------------ striscia Obiettivo

func test_striscia_obiettivo_nascosta_in_riepilogo_e_missioni() -> void:
	_new()
	var main := await _main()
	main.call("_on_ui_tick")
	var strip := main.find_child("GoalStrip", true, false) as Control
	var panel := main.find_child("GoalPanel", true, false) as GoalPanel
	assert_not_null(strip)
	assert_not_null(panel)
	assert_true(panel.visible, "c'è un obiettivo")
	await wait_process_frames(2)
	assert_eq(main.current_id, "summary")
	assert_false(strip.is_visible_in_tree(), "Riepilogo: l'obiettivo è già nel contenuto")
	assert_true(main.show_screen("quests"))
	main.call("_on_ui_tick")
	await wait_process_frames(2)
	assert_false(strip.is_visible_in_tree(), "Missioni: idem")
	assert_true(main.show_screen("bank"))
	main.call("_on_ui_tick")
	await wait_process_frames(2)
	assert_true(strip.is_visible_in_tree(), "altrove la striscia c'è")
	assert_lte(strip.size.y, 32.0, "una riga (circa 28 px)")
	assert_gte(strip.size.y, 26.0)
	var content := main.get_node("Root/Body/Content") as Control
	assert_true(content.get_global_rect().encloses(strip.get_global_rect().grow(-1.0)), "dentro il contenuto, sopra lo ScreenScroll")
	assert_lt(strip.get_global_rect().position.y, main.find_child("ScreenScroll", true, false).get_global_rect().position.y)
	var go := TutorialTargets.find(get_tree(), "goal_go") as Button
	assert_not_null(go, "goal_go è sul pulsante «Vai» della striscia")
	assert_true(strip.is_ancestor_of(go))
	assert_eq(go, panel.find_child("GoButton", true, false))
	assert_null(main.find_child("DiscoverGo", true, false), "«Da scoprire» non c'è più")
	var text := panel.find_child("GoalText", true, false) as Label
	assert_true(text.text.begins_with("◎ "), "◎ titolo · testo")
	assert_ne(text.tooltip_text, "", "tooltip con il «Come» completo")
	assert_true(text.tooltip_text.contains(str(panel.goal().how)))


func test_striscia_obiettivo_si_riscatta_dalla_striscia() -> void:
	_new()
	var main := await _main()
	main.show_screen("bank")
	var q := Game.system("quests") as QuestSystem
	var need := QuestSystem.target_of(q.quest_def("main_c0_q1").objectives[0])
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": need}])
	Game.sim.tick(0.1)
	var panel := main.find_child("GoalPanel", true, false) as GoalPanel
	panel.refresh(true)
	assert_eq(panel.goal().kind, "claim")
	var go := panel.find_child("GoButton", true, false) as Button
	assert_eq(go.text, tr("UI_QUESTS_CLAIM"))
	go.pressed.emit()
	await wait_process_frames(2)
	assert_true(q.is_done("main_c0_q1"))


# ------------------------------------------------------------------ migrazione e toast

func test_migrazione_layout_una_sola_volta_con_toast() -> void:
	_new()
	Settings.set_value("ui_layout_rev", 1)
	Settings.set_value("right_col_visible", true)
	var main := await _main(Vector2(1600, 900))
	assert_false(bool(Settings.get_value("right_col_visible")), "la colonna fissa diventa cassetto")
	assert_eq(int(Settings.get_value("ui_layout_rev")), 2)
	assert_false(_right(main).visible)
	var toasts := main.find_child("Toasts", true, false) as Control
	var found := false
	for p in toasts.get_children():
		for l in p.find_children("*", "Label", true, false):
			if (l as Label).text == tr("UI_RAIL_MIGRATION"):
				found = true
	assert_true(found, "toast «La colonna destra ora è un cassetto: tasto L»")
	Settings.set_value("right_col_visible", true)      # il giocatore la fissa di nuovo, per scelta
	var main2 := await _main(Vector2(1600, 900))
	assert_true(bool(Settings.get_value("right_col_visible")), "la migrazione non si ripete")
	assert_true(_right(main2).visible)
	for p in (main2.find_child("Toasts", true, false) as Control).get_children():
		for l in p.find_children("*", "Label", true, false):
			assert_ne((l as Label).text, tr("UI_RAIL_MIGRATION"), "nessun secondo toast")


func test_toast_stanno_in_alto_al_centro_e_non_coprono_il_binario_o_la_colonna() -> void:
	_new()
	var main := await _main(Vector2(1600, 900))
	var toasts := main.find_child("Toasts", true, false) as Control
	var top := main.find_child("TopBar", true, false) as Control
	await wait_process_frames(2)
	assert_gte(toasts.get_global_rect().position.y, top.get_global_rect().end.y - 0.5, "sotto la barra alta, mai sui suoi pulsanti")
	assert_lt(toasts.get_global_rect().end.y, 300.0, "in alto: lontano dai pulsanti d'uso in basso a destra")
	main.toggle_column()
	await wait_process_frames(2)
	assert_lt(toasts.get_global_rect().end.x, _right(main).get_global_rect().position.x + 0.5, "cassetto aperto: mai sopra di esso")
	main.toggle_column()
	await wait_process_frames(2)
	Settings.set_value("right_col_visible", true)
	await wait_process_frames(2)
	assert_lt(toasts.get_global_rect().end.x, _right(main).get_global_rect().position.x + 0.5, "colonna fissata: mai sopra di essa")
	var side := main.find_child("Sidebar", true, false) as Control
	assert_gt(toasts.get_global_rect().position.x, side.get_global_rect().end.x - 0.5, "e mai sopra il menù")



func test_cassetto_in_banda_stretta_non_supera_il_70_per_cento() -> void:
	_new()
	var main := await _main(Vector2(900, 600))
	assert_true(main.is_narrow())
	Settings.set_value("right_col_width", 520)
	main.toggle_column()
	await wait_process_frames(3)
	assert_lte(_right(main).size.x, 900.0 * 0.7 + 1.0)
	assert_true(main.get_viewport().get_visible_rect().encloses(_right(main).get_global_rect().grow(-1.0)))


# ------------------------------------------------------------------ puntino, tutorial, filtri

func test_puntino_sul_registro_per_gli_eventi_rari() -> void:
	_new()
	var main := await _main()
	var btn = main.find_child("Btn_log", true, false)
	assert_false(btn.dot)
	EventBus.level_up.emit("woodcutting", 5)
	assert_false(btn.dot, "una salita di mansione non è un evento raro")
	EventBus.crate_opened.emit({})
	assert_true(btn.dot, "Cassa aperta")
	main.toggle_column()
	await wait_process_frames(2)
	assert_false(btn.dot, "letto: il puntino sparisce")
	EventBus.achievement_unlocked.emit("x")
	assert_false(btn.dot, "con il Registro aperto non serve il puntino")
	main.toggle_column()
	await wait_process_frames(2)
	EventBus.quest_completed.emit("q")
	assert_true(btn.dot, "missione")
	main.toggle_column()
	await wait_process_frames(2)
	main.toggle_column()
	await wait_process_frames(2)
	EventBus.level_up.emit("hero", 3)
	assert_true(btn.dot, "livello dell'Eroe")


func test_chiavi_del_tutorial_sul_binario() -> void:
	_new()
	var main := await _main()
	main.call("_mark_tutorial_targets")
	var log_btn := main.find_child("Btn_log", true, false)
	assert_eq(TutorialTargets.find(get_tree(), "rail:log"), log_btn)
	assert_eq(TutorialTargets.find(get_tree(), "topbar:column"), log_btn, "topbar:column passa al pulsante Registro")
	assert_eq(TutorialTargets.find(get_tree(), "rail"), _rail(main))
	assert_null(main.find_child("ColumnButton", true, false), "il vecchio pulsante «»/«» della barra alta non esiste più")


func test_filtri_del_registro_scrivono_le_impostazioni() -> void:
	_new()
	var main := await _main()
	main.toggle_column()
	await wait_process_frames(2)
	var fb := main.find_child("FilterButton", true, false) as MenuButton
	assert_not_null(fb)
	assert_true(fb.is_visible_in_tree())
	var pop := fb.get_popup()
	pop.about_to_popup.emit()
	assert_eq(pop.item_count, NoticeFilter.CATEGORIES.size())
	var before := bool(Settings.get_value("notify_loot"))
	pop.index_pressed.emit(NoticeFilter.CATEGORIES.find("loot"))
	assert_eq(bool(Settings.get_value("notify_loot")), not before)
	Settings.set_value("notify_loot", before)


func test_paralleli_fuori_dal_layout_ma_i_dati_restano() -> void:
	_new()
	var main := await _main()
	assert_null(main.find_child("Parallels", true, false))
	assert_true(ParallelsPanel.rows() is Array)
	assert_true(ParallelsPanel.side_rows() is Array)
