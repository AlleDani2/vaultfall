extends GutTest
## Controller e Steam Deck 1.0: glifi, barra dei suggerimenti, azioni dedicate, navigazione col fuoco in tutte le schermate
## principali, tastiera a schermo per i campi di testo.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _saved: Dictionary = {}
var _old_path: String
var _old_dir: String


func before_each() -> void:
	_saved = Settings._values.duplicate(true)
	_old_path = Settings.path
	Settings.path = "user://test_gamepad_%d.cfg" % Time.get_ticks_usec()
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_gamepad_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("tutorials", false)
	InputBindings.reset_all()


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _saved
	Settings.apply_all()
	InputBindings.install()
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _pad(btn: int) -> InputEventJoypadButton:
	var j := InputBindings.pad_event(btn)
	j.pressed = true
	return j


func _main() -> Control:
	assert_true(Game.new_game(1, "normal", 21))
	var un: Object = Game.system("unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.grant(tok)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	return main


# ------------------------------------------------------------------ glifi

func test_etichette_dei_pulsanti_per_stile() -> void:
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_A, "xbox"), "A")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_X, "deck"), "X")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_LEFT_SHOULDER, "xbox"), "LB")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_LEFT_SHOULDER, "deck"), "L1")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_RIGHT_SHOULDER, "playstation"), "R1")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_START, "xbox"), "Menu")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_START, "playstation"), "Options")
	assert_ne(GamepadGlyphs.button_label(JOY_BUTTON_A, "playstation"), "A", "PlayStation: croce, non A")
	assert_eq(GamepadGlyphs.button_label(JOY_BUTTON_DPAD_UP), "↑")
	assert_eq(GamepadGlyphs.button_label(99), "#99")


func test_stile_dal_nome_del_controller() -> void:
	assert_eq(GamepadGlyphs.style_for_name("Xbox 360 Controller"), "xbox")
	assert_eq(GamepadGlyphs.style_for_name("PS5 Controller"), "playstation")
	assert_eq(GamepadGlyphs.style_for_name("Sony DualSense"), "playstation")
	assert_eq(GamepadGlyphs.style_for_name("DualShock 4"), "playstation")
	assert_eq(GamepadGlyphs.style_for_name("Steam Deck Controller"), "deck")
	assert_eq(GamepadGlyphs.style_for_name("Controller sconosciuto"), "xbox")
	assert_eq(GamepadGlyphs.style_for_name(""), "xbox")
	assert_eq(GamepadGlyphs.resolve_style("auto", "PS4 Controller"), "playstation")
	assert_eq(GamepadGlyphs.resolve_style("deck", "PS4 Controller"), "deck", "la scelta del giocatore vince")


func test_il_glifo_si_disegna_e_ha_dimensione() -> void:
	for st in GamepadGlyphs.STYLES:
		for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_START]:
			var g := GamepadGlyphs.make(b, st)
			add_child_autofree(g)
			await wait_process_frames(1)
			assert_gt(g.custom_minimum_size.x, 20.0, "%s %d" % [st, b])
			assert_gt(g.custom_minimum_size.y, 20.0)
			assert_eq(g.mouse_filter, Control.MOUSE_FILTER_IGNORE)


# ------------------------------------------------------------------ barra dei suggerimenti

func test_barra_visibile_solo_col_controller_in_automatico() -> void:
	var h := Settings.runtime.hints
	Settings.set_value("pad_hints", "auto")
	h.device = "keyboard"
	assert_false(h.should_show())
	h.device = "gamepad"
	assert_true(h.should_show())
	Settings.set_value("pad_hints", "never")
	assert_false(h.should_show())
	Settings.set_value("pad_hints", "always")
	h.device = "keyboard"
	assert_true(h.should_show())


func test_barra_ha_conferma_indietro_schede_e_in_partita_menu_e_sabbia() -> void:
	var h := Settings.runtime.hints
	var ids := []
	for it in h.items():
		ids.append_array(it.ids)
	assert_true(ids.has("pad_confirm") and ids.has("pad_back") and ids.has("pad_tab_prev") and ids.has("pad_tab_next"))
	assert_false(ids.has("pad_menu"), "fuori partita niente menù di pausa")
	assert_true(Game.new_game(1, "normal", 3))
	ids = []
	for it in h.items():
		ids.append_array(it.ids)
	assert_true(ids.has("pad_menu"))
	assert_true(ids.has("pad_sand"))
	Settings.set_value("push_enabled", false)
	ids = []
	for it in h.items():
		ids.append_array(it.ids)
	assert_false(ids.has("pad_sand"), "Sabbia spenta: niente suggerimento")


func test_barra_costruisce_i_glifi_dello_stile_scelto() -> void:
	var h := Settings.runtime.hints
	Settings.set_value("pad_hints", "always")
	Settings.set_value("pad_glyphs", "playstation")
	h.rebuild()
	var glyphs := h.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is GamepadGlyphs)
	assert_gt(glyphs.size(), 3)
	for g in glyphs:
		assert_eq((g as GamepadGlyphs).style, "playstation")
	Settings.set_value("pad_glyphs", "xbox")
	h.rebuild()
	for g in h.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is GamepadGlyphs):
		assert_eq((g as GamepadGlyphs).style, "xbox")


func test_barra_segue_i_pulsanti_rimappati() -> void:
	var h := Settings.runtime.hints
	Settings.set_value("pad_hints", "always")
	InputBindings.assign("pad_sand", _pad(JOY_BUTTON_RIGHT_STICK))
	assert_true(Game.new_game(1, "normal", 3))
	h.rebuild()
	var found := false
	for g in h.find_children("*", "Control", true, false):
		if g is GamepadGlyphs and (g as GamepadGlyphs).button == JOY_BUTTON_RIGHT_STICK:
			found = true
	assert_true(found)


func test_barra_non_blocca_i_clic() -> void:
	var h := Settings.runtime.hints
	Settings.set_value("pad_hints", "always")
	h.rebuild()
	var p := h.get_node("Panel") as Control
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(h.layer, 100)


# ------------------------------------------------------------------ dispositivo

func test_il_dispositivo_si_riconosce_dall_evento() -> void:
	assert_eq(UiRuntime.device_of(_pad(JOY_BUTTON_A)), "gamepad")
	var m := InputEventJoypadMotion.new()
	m.axis_value = 0.9
	assert_eq(UiRuntime.device_of(m), "gamepad")
	m.axis_value = 0.1
	assert_eq(UiRuntime.device_of(m), "", "una levetta ferma non conta")
	var k := InputBindings.key_event(KEY_A)
	k.pressed = true
	assert_eq(UiRuntime.device_of(k), "keyboard")
	var mb := InputEventMouseButton.new()
	mb.pressed = true
	assert_eq(UiRuntime.device_of(mb), "keyboard")


func test_il_cambio_di_dispositivo_emette_il_segnale() -> void:
	var rt := Settings.runtime
	rt.device = "keyboard"
	var got := []
	var cb := func(d: String) -> void: got.append(d)
	EventBus.input_device_changed.connect(cb)
	rt._input(_pad(JOY_BUTTON_B))
	rt._input(_pad(JOY_BUTTON_B))
	var k := InputBindings.key_event(KEY_Z)
	k.pressed = true
	rt._input(k)
	EventBus.input_device_changed.disconnect(cb)
	assert_eq(got, ["gamepad", "keyboard"], "un solo segnale per cambio")


# ------------------------------------------------------------------ azioni dedicate nella schermata principale

func test_start_apre_la_pausa_e_b_la_chiude() -> void:
	var main := await _main()
	assert_false(Feedback.is_pause_menu_open())
	assert_true(main.run_pad(_pad(JOY_BUTTON_START)))
	assert_true(Feedback.is_pause_menu_open(), "Start = menù di pausa")
	assert_true(main.run_pad(_pad(JOY_BUTTON_B)))
	assert_false(Feedback.is_pause_menu_open(), "B chiude la pausa")
	main.run_pad(_pad(JOY_BUTTON_START))
	main.run_pad(_pad(JOY_BUTTON_START))
	assert_false(Feedback.is_pause_menu_open(), "Start di nuovo chiude")


func test_b_torna_al_riepilogo() -> void:
	var main := await _main()
	main.show_screen("quests")
	assert_eq(main.current_id, "quests")
	assert_true(main.run_pad(_pad(JOY_BUTTON_B)))
	assert_eq(main.current_id, "summary")
	assert_false(main.run_pad(_pad(JOY_BUTTON_B)), "dal Riepilogo non c'è dove tornare")


func test_select_apre_il_deposito() -> void:
	var main := await _main()
	assert_true(main.run_pad(_pad(JOY_BUTTON_BACK)))
	assert_eq(main.current_id, "bank")


func test_lb_rb_scorrono_le_voci_del_menu_o_le_schede() -> void:
	var main := await _main()
	main.show_screen("summary")
	var ids: Array = main._sidebar.menu_ids
	assert_gt(ids.size(), 2)
	var first: String = main.current_id
	assert_true(main.run_pad(_pad(JOY_BUTTON_RIGHT_SHOULDER)))
	assert_ne(main.current_id, first)
	assert_true(main.run_pad(_pad(JOY_BUTTON_LEFT_SHOULDER)))
	assert_eq(main.current_id, first, "RB e poi LB tornano dove si era")


func test_sabbia_col_pulsante_dedicato_e_rimappabile() -> void:
	assert_true(InputBindings.matches(_pad(JOY_BUTTON_X), "pad_sand"))
	InputBindings.assign("pad_sand", _pad(JOY_BUTTON_RIGHT_STICK))
	assert_false(InputBindings.matches(_pad(JOY_BUTTON_X), "pad_sand"))
	assert_true(InputBindings.matches(_pad(JOY_BUTTON_RIGHT_STICK), "pad_sand"))


func test_i_pulsanti_rimappati_valgono_in_schermata() -> void:
	var main := await _main()
	InputBindings.assign("pad_menu", _pad(JOY_BUTTON_LEFT_STICK))
	assert_false(main.run_pad(_pad(JOY_BUTTON_START)), "Start non è più il menù")
	assert_true(main.run_pad(_pad(JOY_BUTTON_LEFT_STICK)))
	assert_true(Feedback.is_pause_menu_open())
	main.run_pad(_pad(JOY_BUTTON_B))


# ------------------------------------------------------------------ fuoco

func test_senza_fuoco_la_prima_pressione_porta_il_fuoco_nella_schermata() -> void:
	var main := await _main()
	get_viewport().gui_release_focus()
	assert_null(get_viewport().gui_get_focus_owner())
	assert_true(FocusAssist.ensure_focus(get_tree()))
	var f := get_viewport().gui_get_focus_owner()
	assert_not_null(f)
	assert_true(main.is_ancestor_of(f), "dentro la schermata principale")


func test_con_il_fuoco_gia_presente_non_lo_sposta() -> void:
	var main := await _main()
	FocusAssist.ensure_focus(get_tree())
	var f := get_viewport().gui_get_focus_owner()
	assert_false(FocusAssist.ensure_focus(get_tree()))
	assert_eq(get_viewport().gui_get_focus_owner(), f)


func test_la_pausa_prende_il_fuoco_su_riprendi() -> void:
	var main := await _main()
	main.run_pad(_pad(JOY_BUTTON_START))
	await wait_process_frames(2)
	var f := get_viewport().gui_get_focus_owner()
	assert_not_null(f)
	assert_eq(f.name, "ResumeButton")
	main.run_pad(_pad(JOY_BUTTON_START))


func test_un_dialogo_aperto_ha_la_precedenza_per_il_fuoco() -> void:
	var main := await _main()
	var d := ConfirmationDialog.new()
	add_child_autofree(d)
	d.popup_centered()
	await wait_process_frames(2)
	get_viewport().gui_release_focus()
	d.gui_release_focus()
	var roots := FocusAssist.focus_roots(get_tree())
	assert_true(roots[0] == d, "la finestra in primo piano viene per prima")
	assert_not_null(main)


func test_direzioni_e_conferma_chiedono_il_fuoco() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	assert_true(UiRuntime._wants_focus(down))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	assert_false(UiRuntime._wants_focus(space), "la barra spaziatrice non deve rubare il fuoco")
	var dpad := _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(UiRuntime._wants_focus(dpad))
	assert_true(UiRuntime._wants_focus(_pad(JOY_BUTTON_A)))
	assert_false(UiRuntime._wants_focus(_pad(JOY_BUTTON_X)))
	var alt_left := InputEventKey.new()
	alt_left.keycode = KEY_LEFT
	alt_left.alt_pressed = true
	alt_left.pressed = true
	assert_false(UiRuntime._wants_focus(alt_left), "Alt+freccia è dei tasti del Deposito")


func test_ogni_schermata_principale_si_naviga_col_controller() -> void:
	var main := await _main()
	var nessuna: Array[String] = []
	var senza_fuoco: Array[String] = []
	var count := 0
	for e in ScreenRegistry.entries():
		var id := str(e.id)
		if not main.show_screen(id):
			continue
		count += 1
		await wait_process_frames(2)
		get_viewport().gui_release_focus()
		if FocusAssist.first_focusable(main.current_screen()) == null:
			nessuna.append(id)
		if not FocusAssist.ensure_focus(get_tree()) or get_viewport().gui_get_focus_owner() == null:
			senza_fuoco.append(id)
	assert_gt(count, 20, "schermate provate")
	assert_eq(senza_fuoco, [], "schermate dove il controller non trova dove mettere il fuoco")
	# le schermate di sola lettura possono non avere controlli propri: il fuoco va comunque sul menù
	gut.p("schermate senza controlli propri nel contenuto: %s (su %d)" % [str(nessuna), count])
	assert_lt(nessuna.size(), 6, "poche schermate senza controlli propri: " + str(nessuna))


func test_titolo_e_slot_si_navigano_col_controller() -> void:
	var start: Control = (load("res://src/ui/start/StartScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(start)
	await wait_process_frames(3)
	assert_not_null(FocusAssist.first_focusable(start), "il titolo ha pulsanti raggiungibili")
	start.call("show_slots")
	await wait_process_frames(2)
	assert_not_null(FocusAssist.first_focusable(start), "gli slot pure")
	start.call("show_settings")
	await wait_process_frames(2)
	assert_not_null(FocusAssist.first_focusable(start))


func test_il_menu_laterale_e_raggiungibile_col_fuoco() -> void:
	var main := await _main()
	var f := FocusAssist.first_focusable(main._sidebar.sidebar())
	assert_not_null(f)
	assert_eq(f.focus_mode, Control.FOCUS_ALL)


func test_impostazioni_navigabili_col_controller() -> void:
	var s: Control = (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	await wait_process_frames(2)
	s.focus_tabs()
	assert_eq(get_viewport().gui_get_focus_owner(), s.tabs.get_tab_bar())
	for i in s.tabs.get_tab_count():
		s.tabs.current_tab = i
		var f := FocusAssist.first_focusable(s.tabs.get_tab_control(i))
		assert_not_null(f, "scheda %d ha controlli raggiungibili" % i)


# ------------------------------------------------------------------ tastiera a schermo

func test_tastiera_a_schermo_scrive_nel_campo() -> void:
	var le := LineEdit.new()
	add_child_autofree(le)
	await wait_process_frames(1)
	var kb := OnScreenKeyboard.open_for(le)
	assert_not_null(kb)
	await wait_process_frames(2)
	kb.type_text("c")
	kb.type_text("i")
	kb.type_text("a")
	kb.type_text("o")
	assert_eq(le.text, "ciao")
	kb.backspace()
	assert_eq(le.text, "cia")
	kb._move(-1)
	kb.type_text("X")
	assert_eq(le.text, "ciXa", "scrive alla posizione del cursore")
	kb.close()


func test_tastiera_a_schermo_tasti_e_maiuscole() -> void:
	var le := LineEdit.new()
	add_child_autofree(le)
	await wait_process_frames(1)
	var kb := OnScreenKeyboard.open_for(le)
	await wait_process_frames(2)
	(kb.find_child("Key_q", true, false) as Button).pressed.emit()
	assert_eq(le.text, "q")
	(kb.find_child("Shift", true, false) as Button).button_pressed = true
	(kb.find_child("Key_w", true, false) as Button).pressed.emit()
	assert_eq(le.text, "qW")
	(kb.find_child("Key_1", true, false) as Button).pressed.emit()
	assert_eq(le.text, "qW1", "le cifre non cambiano con Maiusc")
	(kb.find_child("Space", true, false) as Button).pressed.emit()
	assert_eq(le.text, "qW1 ")
	(kb.find_child("Backspace", true, false) as Button).pressed.emit()
	assert_eq(le.text, "qW1")
	(kb.find_child("Key_u224", true, false) as Button).pressed.emit()
	assert_eq(le.text, "qW1À", "lettere accentate (Maiusc era attivo)")
	kb.close()


func test_tastiera_a_schermo_fatto_invia_il_testo_e_annulla_no() -> void:
	var le := LineEdit.new()
	add_child_autofree(le)
	await wait_process_frames(1)
	var sent := []
	le.text_submitted.connect(func(t: String) -> void: sent.append(t))
	var kb := OnScreenKeyboard.open_for(le)
	await wait_process_frames(2)
	kb.type_text("abc")
	kb.done()
	assert_eq(sent, ["abc"])
	var kb2 := OnScreenKeyboard.open_for(le)
	await wait_process_frames(2)
	kb2.type_text("d")
	kb2.close()
	assert_eq(sent.size(), 1, "Annulla non invia")
	assert_eq(le.text, "abcd", "il testo scritto resta nel campo")


func test_tastiera_a_schermo_funziona_anche_nei_campi_di_testo_lunghi() -> void:
	var te := TextEdit.new()
	add_child_autofree(te)
	await wait_process_frames(1)
	var kb := OnScreenKeyboard.open_for(te)
	assert_not_null(kb)
	await wait_process_frames(2)
	kb.type_text("riga")
	kb.type_text("\n")
	kb.type_text("due")
	assert_eq(te.text, "riga\ndue")
	kb.backspace()
	assert_eq(te.text, "riga\ndu")
	kb.close()


func test_una_sola_tastiera_e_solo_per_campi_di_testo() -> void:
	var le := LineEdit.new()
	add_child_autofree(le)
	await wait_process_frames(1)
	var kb := OnScreenKeyboard.open_for(le)
	assert_null(OnScreenKeyboard.open_for(le), "già aperta")
	kb.close()
	var b := Button.new()
	add_child_autofree(b)
	assert_null(OnScreenKeyboard.open_for(b), "un pulsante non è un campo di testo")


func test_a_su_un_campo_col_controller_apre_la_tastiera() -> void:
	var rt := Settings.runtime
	var le := LineEdit.new()
	add_child_autofree(le)
	await wait_process_frames(1)
	rt.device = "keyboard"
	rt._on_text_input(_pad(JOY_BUTTON_A), le)
	assert_null(le.get_window().find_child("OnScreenKeyboard", false, false), "col mouse/tastiera non si apre")
	rt.device = "gamepad"
	Settings.set_value("osk", false)
	rt._on_text_input(_pad(JOY_BUTTON_A), le)
	assert_null(le.get_window().find_child("OnScreenKeyboard", false, false), "spenta nelle impostazioni")
	Settings.set_value("osk", true)
	rt._on_text_input(_pad(JOY_BUTTON_X), le)
	assert_null(le.get_window().find_child("OnScreenKeyboard", false, false), "solo il pulsante di conferma")
	rt._on_text_input(_pad(JOY_BUTTON_A), le)
	var kb := le.get_window().find_child("OnScreenKeyboard", false, false)
	assert_not_null(kb)
	(kb as OnScreenKeyboard).close()
	rt.device = "keyboard"


func test_campi_di_testo_nuovi_vengono_agganciati() -> void:
	var le := LineEdit.new()
	add_child_autofree(le)
	await wait_process_frames(1)
	assert_gt(le.gui_input.get_connections().size(), 0, "la tastiera a schermo ascolta il nuovo campo")
