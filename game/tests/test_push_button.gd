extends GutTest
## F14 del progetto di interfaccia (docs/ui_redesign/06 §3.5, D24-D26, 03 §7.3-7.4): pulsante «Sabbia del Custode» (PushButton),
## feedback (PushFeedback), Clic assistito, tasto T, controller X, impostazioni. Il motore è quello di F13 (non si tocca).

const MAIN := "res://src/ui/main/MainScreen.tscn"
const KEYS := ["push_enabled", "push_assist", "push_assist_rate", "push_floaters", "push_sound", "reduce_motion", "fx_mode",
	"right_col_visible", "right_col_width", "ui_layout_rev", "drawer_section", "tutorials", "locale"]

var _old_dir: String
var _old: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_push_button_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in KEYS:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
	Settings.set_value("ui_layout_rev", 2)
	Settings.set_value("right_col_visible", false)
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "full")
	Settings.set_value("push_enabled", true)
	Settings.set_value("push_assist", "off")
	Settings.set_value("push_assist_rate", 3)
	Settings.set_value("push_floaters", true)
	Settings.set_value("push_sound", true)
	Game.click_limiter = null
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
	Game.click_limiter = null
	ReqLink.reset_cache()


## Partita con la Sabbia sbloccata, 50 s di riserva e un'azione di Taglialegna in corso.
func _game(unlock: bool = true, act: bool = true) -> TimePushSystem:
	assert_true(Game.new_game(1, "normal", 77))
	var tp := Game.system("time_push") as TimePushSystem
	if unlock:
		(Game.system("unlock") as UnlockSystem).grant(str(DataRegistry.constants.time_push.unlock_token))
	tp.state["gift_given"] = true
	tp.state["reserve_s"] = 50.0
	if act:
		GameState.data.unlocks.append("skill:woodcutting")
		var sk := Game.system("skills") as SkillSystem
		for a in DataRegistry.actions_for_skill("woodcutting"):
			if int(a.get("level_req", 1)) <= 1 and sk.start(str(a.id)):
				break
	return tp


func _btn() -> PushButton:
	var b := PushButton.new()
	add_child_autofree(b)
	b.refresh()
	return b


func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


func _pad(pressed: bool, index: int = JOY_BUTTON_X) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = pressed
	return e


# ------------------------------------------------------------------ stati A-E e nascosto

func test_nascosto_prima_dello_sblocco_e_con_push_enabled_spento() -> void:
	_game(false)
	var b := _btn()
	assert_eq(b.state, PushButton.HIDDEN)
	assert_false(b.visible)
	assert_eq(b.tooltip(), "")
	(Game.system("unlock") as UnlockSystem).grant(str(DataRegistry.constants.time_push.unlock_token))
	b.refresh()
	assert_true(b.visible, "sbloccata: si vede")
	Settings.set_value("push_enabled", false)
	assert_eq(b.state, PushButton.HIDDEN, "push_enabled = false la nasconde")
	assert_false(b.visible)
	assert_true(b.click().is_empty(), "nascosto: nessun clic")
	assert_eq(b.clicks_done, 0)


func test_stati_a_b_c_d_e() -> void:
	var tp := _game()
	var b := _btn()
	assert_eq(b.state, PushButton.A, "A pronta")
	assert_eq(b.time_label.text, "0:50")
	b.click()
	assert_eq(b.state, PushButton.B, "B in uso subito dopo un clic")
	b._last_click_msec = -1000000
	b.refresh()
	assert_eq(b.state, PushButton.A, "dopo 300 ms torna A")
	tp.state["pending_s"] = 0.0
	tp.state["reserve_s"] = 0.0
	b.refresh()
	assert_eq(b.state, PushButton.C, "C vuota (riserva < un clic)")
	assert_true(b.time_label.text.contains("6"), "«fra 6 s»: %s" % b.time_label.text)
	assert_true(b.tooltip().contains("6"), "tooltip C: prossimo clic")
	tp.state["reserve_s"] = 50.0
	Settings.set_value("push_assist", "auto")
	b._last_click_msec = -1000000
	b.refresh()
	assert_eq(b.state, PushButton.E, "E automatica")
	Settings.set_value("push_assist", "off")
	GameState.data["activity"].clear()
	b.refresh()
	assert_eq(b.state, PushButton.D, "D senza azione")
	assert_eq(b.reason_key, "UI_PUSH_REASON_NONE")
	assert_eq(b.time_label.text, "—")


func test_stato_d_in_pausa() -> void:
	_game()
	var b := _btn()
	Clock.core.paused = true
	b.refresh()
	assert_eq(b.state, PushButton.D)
	assert_eq(b.reason_key, "UI_PUSH_REASON_PAUSE")
	assert_false(b.can_spend())
	Clock.core.paused = false


func test_stato_d_combattimento_prova_estremo() -> void:
	var tp := _game()
	var b := _btn()
	GameState.data["activity"].clear()
	GameState.data["activity"].merge({"type": "combat", "mode": "zone"})
	b.refresh()
	assert_eq(b.state, PushButton.D)
	assert_eq(b.reason_key, "UI_PUSH_REASON_ACT")
	assert_not_null(tp)
	Game.stop_game(false)
	var tp2 := _game(true, false)
	var b2 := _btn()
	assert_not_null(tp2)
	var pr := Game.system("prestige")
	if pr != null and pr.has_method("is_trial_active"):
		assert_false(bool(pr.call("is_trial_active")), "senza Prova non è bloccata dalla Prova")
	assert_eq(b2.reason_key, "UI_PUSH_REASON_NONE", "senza azione e senza Prova: nessuna azione")


func test_motivi_d_con_tooltip_it_en_senza_chiavi_nude() -> void:
	_game()
	var b := _btn()
	var reasons := ["UI_PUSH_REASON_NONE", "UI_PUSH_REASON_ACT", "UI_PUSH_REASON_TRIAL", "UI_PUSH_REASON_EXTREME", "UI_PUSH_REASON_PAUSE"]
	var old_loc := TranslationServer.get_locale()
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for r in reasons:
			b.state = PushButton.D
			b.reason_key = r
			var t := b.tooltip()
			assert_false(t.contains("UI_"), "%s/%s: chiave nuda nel tooltip «%s»" % [loc, r, t])
			assert_true(t.contains("\n"), "intestazione + motivo")
		for st in [PushButton.A, PushButton.B, PushButton.C, PushButton.E]:
			b.state = st
			var t2 := b.tooltip()
			assert_false(t2.contains("UI_") or t2.contains("{"), "%s/%s: «%s»" % [loc, st, t2])
	TranslationServer.set_locale("it")
	b.state = PushButton.D
	b.reason_key = "UI_PUSH_REASON_ACT"
	var it_txt := b.tooltip()
	TranslationServer.set_locale("en")
	var en_txt := b.tooltip()
	assert_ne(it_txt, en_txt, "IT e EN sono diversi")
	TranslationServer.set_locale(old_loc)


# ------------------------------------------------------------------ feedback

func test_riduci_animazioni_niente_scatto_ne_numero() -> void:
	_game()
	Settings.set_value("reduce_motion", true)
	var b := _btn()
	for i in 5:
		b.click()
	b.feedback.flush()
	assert_eq(b.feedback.flash_count, 0, "nessuno scatto")
	assert_eq(b.feedback.gain_label.text, "", "nessun «+N s»")
	assert_eq(b.feedback.label_updates, 0)
	assert_gt(b.clicks_done, 0, "ma il clic funziona")
	assert_eq(b.time_label.text, PushButton.mmss(float((Game.system("time_push") as TimePushSystem).reserve_s())), "resta il numero")
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "reduced")
	b.feedback.flush()
	b.click()
	assert_eq(b.feedback.flash_count, 0, "effetti ridotti: nessuno scatto")
	b.feedback.flush()
	assert_eq(b.feedback.gain_label.text, "", "effetti ridotti: nessun «+N s»")


func test_numero_aggregato_non_per_singolo_clic() -> void:
	_game()
	var b := _btn()
	for i in 6:
		b.click()
	assert_eq(b.feedback.label_updates, 0, "nessun numero finché non scade la finestra da 200 ms")
	assert_eq(b.feedback.gain_label.text, "")
	b.feedback.flush()
	assert_eq(b.feedback.label_updates, 1, "un solo aggiornamento per finestra")
	var click_s := float(DataRegistry.constants.time_push.click_s)
	var want := NumberFormat.decimal(6.0 * click_s, 1, Loc.locale())
	assert_true(b.feedback.gain_label.text.contains(want), "somma «%s» in «%s»" % [want, b.feedback.gain_label.text])
	b.feedback.flush()
	assert_eq(b.feedback.label_updates, 1, "niente da aggiungere: l'etichetta non si riscrive")
	assert_eq(b.find_children("PushGain", "Label", true, false).size(), 1, "un'unica etichetta, mai una per clic")
	assert_gte(b.feedback.flash_count, 1, "con animazioni piene c'è uno scatto")
	assert_lte(PushFeedback.FLASH_S, 0.12, "scatto <= 120 ms")


func test_floaters_spenti() -> void:
	_game()
	Settings.set_value("push_floaters", false)
	var b := _btn()
	b.click()
	b.feedback.flush()
	assert_eq(b.feedback.gain_label.text, "")


func test_suono_sempre_lo_stesso_stream_e_la_stessa_altezza() -> void:
	_game()
	var b := _btn()
	var streams := []
	var pitches := []
	for i in 4:
		b.feedback._last_tick_msec = -1000000
		b.click()
		streams.append(b.feedback.last_stream)
		pitches.append(b.feedback.last_pitch)
	assert_eq(b.feedback.tick_count, 4)
	assert_not_null(streams[0], "stream caricato")
	for i in streams.size():
		assert_same(streams[i], streams[0], "stesso stream")
		assert_eq(pitches[i], 1.0, "stessa altezza (nessuna salita di tono)")
	b.feedback._last_tick_msec = -1000000
	b.feedback.tick_count = 0
	for i in 15:
		b.click()
	assert_eq(b.feedback.tick_count, 1, "al massimo 10 tick al secondo: 15 clic nello stesso istante = 1 tick")


func test_suono_spento() -> void:
	_game()
	Settings.set_value("push_sound", false)
	var b := _btn()
	b.click()
	assert_eq(b.feedback.tick_count, 0)


# ------------------------------------------------------------------ input

func test_eventi_echo_ignorati() -> void:
	_game()
	var b := _btn()
	b._unhandled_key_input(_key(KEY_T, true, true))
	assert_eq(b.clicks_done, 0, "T ripetuto dal sistema operativo non è un clic")
	b.hit._gui_input(_key(KEY_SPACE, true, true))
	assert_eq(b.clicks_done, 0)
	assert_true(ClickLimiter.is_echo(_key(KEY_T, true, true)))


func test_tasto_t() -> void:
	_game()
	var b := _btn()
	b._unhandled_key_input(_key(KEY_T))
	assert_eq(b.clicks_done, 1, "T = un clic")
	assert_true(b.is_held(), "T premuto = tenuto")
	b._unhandled_key_input(_key(KEY_T, false))
	assert_false(b.is_held())
	assert_eq(ShortcutMap.resolve(_key(KEY_T), []).get("type", ""), "push")
	var found := false
	for e in ShortcutMap.TABLE:
		if str(e.id) == "push":
			found = true
	assert_true(found, "riga T nella tabella delle scorciatoie")
	Settings.set_value("push_enabled", false)
	b._unhandled_key_input(_key(KEY_T))
	assert_eq(b.clicks_done, 1, "pulsante spento: T non fa nulla")


func test_controller_x() -> void:
	_game()
	var b := _btn()
	b._input(_pad(true))
	assert_eq(b.clicks_done, 1, "X = un clic")
	assert_true(b.is_held(), "X tenuto = «tieni premuto»")
	b._input(_pad(false))
	assert_false(b.is_held())
	b._input(_pad(true, JOY_BUTTON_A))
	assert_eq(b.clicks_done, 1, "gli altri tasti non c'entrano")


func test_clic_del_mouse_con_il_segnale_del_pulsante() -> void:
	_game()
	var b := _btn()
	b.hit.button_down.emit()
	assert_eq(b.clicks_done, 1)
	b.hit.button_up.emit()
	assert_false(b.is_held())


# ------------------------------------------------------------------ Clic assistito

func test_assist_tieni_premuto() -> void:
	_game()
	Settings.set_value("push_assist", "hold")
	var b := _btn()
	assert_eq(b.assist_step(1.0), 0, "senza tenere premuto non scatta nulla")
	b.press_down("mouse")
	assert_eq(b.clicks_done, 1, "il primo clic è subito")
	assert_eq(b.assist_step(1.0), 3, "a 3 clic/s: 3 clic in un secondo")
	assert_eq(b.assist_step(0.5), 1, "mezzo secondo: 1 clic (accumulatore 1,5)")
	assert_eq(b.assist_step(0.5), 2, "il mezzo clic avanzato si somma")
	b.press_up("mouse")
	assert_eq(b.assist_step(1.0), 0, "rilasciato: si ferma")


func test_assist_interruttore() -> void:
	_game()
	Settings.set_value("push_assist", "toggle")
	var b := _btn()
	b.press_down("mouse")
	b.press_up("mouse")
	assert_true(b.toggle_on())
	assert_eq(b.assist_step(1.0), 3, "acceso: continua senza tenere premuto")
	b.press_down("mouse")
	b.press_up("mouse")
	assert_false(b.toggle_on())
	assert_eq(b.assist_step(1.0), 0)
	Settings.set_value("push_assist", "toggle")
	b.press_down("mouse")
	b.press_up("mouse")
	Settings.set_value("push_assist", "off")
	assert_false(b.toggle_on(), "cambiare modalità spegne l'interruttore")


func test_assist_automatico_solo_con_sabbia() -> void:
	var tp := _game()
	Settings.set_value("push_assist", "auto")
	var b := _btn()
	assert_eq(b.assist_step(1.0), 3)
	tp.state["pending_s"] = 0.0
	tp.state["reserve_s"] = 0.1
	assert_eq(b.assist_step(1.0), 0, "riserva sotto un clic: aspetta che si ricarichi")
	GameState.data["activity"].clear()
	tp.state["reserve_s"] = 50.0
	assert_eq(b.assist_step(1.0), 0, "senza azione non spende")


func test_assist_mai_oltre_max_cps() -> void:
	_game()
	var k: Dictionary = DataRegistry.constants.time_push
	var old_cps = k.max_cps
	Settings.set_value("push_assist", "auto")
	Settings.set_value("push_assist_rate", 10)
	var b := _btn()
	assert_eq(b.assist_rate(), 10.0)
	k["max_cps"] = 4
	assert_eq(b.assist_rate(), 4.0, "il tetto dei dati vince sull'impostazione")
	assert_lte(b.assist_step(5.0), 4, "mai oltre max_cps in una volta")
	k["max_cps"] = old_cps
	Game.click_limiter = null
	var total := 0
	for i in 20:
		total += b.assist_step(0.1)
	assert_lte(total, int(old_cps) * 2, "in 2 s non oltre il tetto")
	assert_eq(total, 20, "10 clic/s per 2 s")


func test_impostazioni_push() -> void:
	assert_eq(Settings.DEFAULTS.push_enabled, true)
	assert_eq(Settings.DEFAULTS.push_assist, "off")
	assert_eq(Settings.DEFAULTS.push_assist_rate, 3)
	assert_eq(Settings.DEFAULTS.push_floaters, true)
	assert_eq(Settings.DEFAULTS.push_sound, true)
	assert_false(Settings.set_value("push_assist", "boh"), "modalità sconosciuta rifiutata")
	assert_true(Settings.set_value("push_assist_rate", 99))
	assert_eq(Settings.get_value("push_assist_rate"), 10, "tetto 10")
	assert_true(Settings.set_value("push_assist_rate", 0))
	assert_eq(Settings.get_value("push_assist_rate"), 1, "minimo 1")


func test_sezione_impostazioni() -> void:
	var s := (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	var texts := []
	for l in s.find_children("*", "Label", true, false):
		texts.append(str((l as Label).text))
	assert_true(texts.has("UI_PUSH_SAND"), "sezione «Sabbia del Custode»")
	assert_true(texts.has("UI_PUSH_SET_HELP"), "frase sugli autoclicker")
	assert_not_null(s.find_child("PushAssistRate", true, false))


# ------------------------------------------------------------------ nel binario

func _main(sz: Vector2 = Vector2(1280, 720)) -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = sz
	await wait_process_frames(3)
	return main


func test_nel_binario_e_nel_cassetto_fissato() -> void:
	_game()
	var main := await _main(Vector2(1600, 900))
	var slot := main.find_child("PushSlot", true, false) as Control
	var pb := main.find_child("PushButton", true, false) as PushButton
	assert_not_null(pb)
	assert_eq(pb.get_parent(), slot, "nel binario")
	assert_true(pb.is_visible_in_tree(), "sbloccata: visibile")
	assert_eq(pb.hit.custom_minimum_size, Vector2(48, 48), "bersaglio 48x48")
	assert_eq(TutorialTargets.find(get_tree(), "rail:push"), pb.hit, "chiave rail:push")
	Settings.set_value("right_col_visible", true)
	main._apply_column()
	await wait_process_frames(2)
	var vbox := main.get_node("Root/Body/RightColumn/RightScroll/VBox")
	assert_eq(pb.get_parent(), vbox, "colonna fissata: il pulsante va in fondo alla colonna")
	assert_eq(vbox.get_child(vbox.get_child_count() - 1), pb, "ultimo figlio")
	assert_eq(TutorialTargets.find(get_tree(), "rail:push"), pb.hit, "la chiave resta")
	Settings.set_value("right_col_visible", false)
	main._apply_column()
	await wait_process_frames(2)
	assert_eq(pb.get_parent(), slot, "torna nel binario")
	assert_eq(TutorialTargets.find(get_tree(), "rail:push"), pb.hit)


func test_il_binario_resta_a_52_px_e_nel_budget() -> void:
	_game()
	var main := await _main()
	var rail := main.find_child("RightRail", true, false) as Control
	assert_almost_eq(rail.size.x, 52.0, 1.0, "il pulsante da 48 px sta nel binario da 52")
	var box := rail.find_child("RailBox", true, false)
	assert_lte(box.get_child_count(), 5, "binario <= 5 elementi")


func test_tutorial_f_push() -> void:
	var st := TutorialCatalog.get_step("f_push")
	assert_false(st.is_empty())
	assert_eq(st.token, "feature:time_push")
	assert_eq(TutorialCatalog.targets_of(st), ["rail:push"])
	assert_eq(st.after, "g_move2")
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		assert_ne(tr(TutorialCatalog.title_key("f_push")), TutorialCatalog.title_key("f_push"))
		assert_true(tr(TutorialCatalog.body_key("f_push")).length() > 40)
	TranslationServer.set_locale("it")
