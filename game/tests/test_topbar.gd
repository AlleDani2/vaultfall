extends GutTest
## Barra superiore (F2 del progetto di interfaccia, docs/ui_redesign/06 §3.2): Polvere Stellare, Deposito (neutro/ambra/rosso),
## clic su Oro/Polvere/Deposito/attività, stati dell'attività, tempo al livello mai schiacciato a 1024/1280/1536 px logici
## (IT ed EN), tooltip con il tasto, tasto P. Nessun numero di bilanciamento: la soglia di avviso si legge dai dati.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const WIDTHS: Array[int] = [1024, 1280, 1536]
const LONG_ETA := "Liv. 100 tra 12 h 30 min"

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_locale: String
var _old_fps: int


func before_all() -> void:
	_old_fps = Engine.max_fps
	Engine.max_fps = 0
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor
	_old_locale = TranslationServer.get_locale()


func after_all() -> void:
	Engine.max_fps = _old_fps


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_topbar_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Game.new_game(1, "normal", 4242)
	Settings.set_value("tutorials", false)


func after_each() -> void:
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	get_tree().root.content_scale_factor = _old_scale
	TranslationServer.set_locale(_old_locale)
	Clock.set_paused(false)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	return main


func _bar(main: Control) -> HBoxContainer:
	return main.get_node("Root/TopBar/HBox") as HBoxContainer


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _grant(token: String) -> void:
	(Game.system("unlock") as UnlockSystem).grant(token)


## Porta la capacità del Deposito a `cap` (cambia solo gli spazi comprati: nessun numero di bilanciamento qui).
func _set_capacity(cap: int) -> void:
	var b := _bank()
	b.state.slots_bought = int(b.state.slots_bought) + cap - b.capacity()
	assert_eq(b.capacity(), cap)


func _fill_stacks(n: int) -> void:
	var b := _bank()
	var ids: Array = []
	for it in DataRegistry.items_by_category("material"):
		ids.append(str(it.id))
	var i := 0
	while b.used_slots() < n and i < ids.size():
		b.add(ids[i], 1)
		i += 1
	assert_gte(b.used_slots(), n, "abbastanza oggetti diversi per riempire")


func _warn_pct() -> float:
	return float(DataRegistry.constants.bank.warn_pct)


# ------------------------------------------------------------------ Polvere Stellare

func test_polvere_nascosta_prima_del_prestigio_e_visibile_dopo() -> void:
	var main := await _main()
	var chip := _bar(main).get_node("DustChip") as Control
	main._on_ui_tick()
	assert_false(TopBar.prestige_unlocked(), "una partita nuova non ha il Prestigio")
	assert_false(chip.visible, "nascosta finché il Prestigio non è sbloccato e la Polvere è 0")
	_grant("feature:prestige")
	main._on_ui_tick()
	assert_true(TopBar.prestige_unlocked())
	assert_true(chip.visible, "visibile dal primo sblocco")
	assert_eq(main.get_node("%DustValue").text, "0")


func test_polvere_visibile_se_maggiore_di_zero_anche_senza_sblocco() -> void:
	var main := await _main()
	_bank().add_currency(PrestigeSystem.DUST, 134)
	main._on_ui_tick()
	assert_true((_bar(main).get_node("DustChip") as Control).visible)
	assert_ne(main.get_node("%DustValue").text, "0")


## Pulizia A: la Polvere apre il Prestigio sulla scheda Costellazioni passando il parametro `tab` a show_screen/open
## (niente più chiamata al metodo privato _goto_tab).
func _prestige_tab(main: Control) -> String:
	var scr: Control = main.current_screen()
	var tc := scr.find_children("*", "TabContainer", true, false)[0] as TabContainer
	var ids: Array = scr.get("_tab_ids")
	var i: int = tc.current_tab - 2      # prima ci sono le due schede fisse (Consigliere, Obiettivo)
	return str(ids[i]) if i >= 0 and i < ids.size() else ""


## Pulizia A: «salvato N min fa» nel tooltip del tasto Salva conta dall'ultimo salvataggio vero (SaveService), non dall'apertura.
func test_tooltip_salva_usa_l_istante_di_saveservice() -> void:
	var main := await _main()
	var save_btn := main.get_node("%SaveButton") as Control
	SaveService.last_saved_unix = Clock.now_unix() - 600
	main.get("_topbar").refresh_top()
	assert_string_contains(save_btn.tooltip_text, NumberFormat.fmt_time(600.0), "dieci minuti fa, anche se la barra è appena nata")
	assert_false(save_btn.tooltip_text.contains(tr("UI_TOP_SAVE_NOW")))
	SaveService.last_saved_unix = Clock.now_unix()
	main.get("_topbar").refresh_top()
	assert_string_contains(save_btn.tooltip_text, tr("UI_TOP_SAVE_NOW"))


func test_polvere_apre_il_prestigio_sulle_costellazioni() -> void:
	_grant("feature:prestige")
	_bank().add_currency(PrestigeSystem.DUST, 50)
	var main := await _main()
	main._on_ui_tick()
	(_bar(main).get_node("DustChip") as TopCurrency).activated.emit()
	await wait_process_frames(2)
	assert_eq(main.current_id, "prestige")
	assert_eq(_prestige_tab(main), "constellations", "la barra alta chiede la scheda Costellazioni con il parametro tab")
	# il parametro funziona anche da solo; uno sconosciuto lascia la prima scheda
	main.show_screen("prestige", {"tab": "star"})
	await wait_process_frames(2)
	assert_eq(_prestige_tab(main), "star")
	main.show_screen("prestige", {"tab": "inesistente"})
	await wait_process_frames(2)
	assert_eq(_prestige_tab(main), "", "scheda sconosciuta: resta la scheda fissa iniziale (Consigliere)")
	main.show_screen("prestige")
	await wait_process_frames(2)
	assert_eq(_prestige_tab(main), "", "senza parametro: la scheda fissa iniziale (Consigliere)")


# ------------------------------------------------------------------ Deposito

func test_deposito_neutro_ambra_rosso_con_soglia_dai_dati_e_carro() -> void:
	var main := await _main()
	var chip := _bar(main).get_node("BankChip") as BankChip
	var lab := chip.label()
	_fill_stacks(12)
	var used := _bank().used_slots()
	# neutro: molto spazio libero
	_set_capacity(used * 2 + 10)
	main._on_ui_tick()
	assert_eq(chip.state, BankChip.State.NORMAL)
	assert_eq(chip.tint.a, 0.0, "nessuno sfondo")
	assert_true(lab.text.contains(str(_bank().free_slots())), "il numero di spazi liberi: " + lab.text)
	# ambra: usati >= warn_pct% della capacità (la soglia si legge dai dati)
	var cap_warn := int(floor(float(used) * 100.0 / _warn_pct()))
	assert_gt(cap_warn, used, "scenario valido: c'è ancora uno spazio libero")
	_set_capacity(cap_warn)
	main._on_ui_tick()
	assert_true(float(used) * 100.0 >= float(cap_warn) * _warn_pct())
	assert_eq(chip.state, BankChip.State.WARN)
	assert_eq(chip.tint, UiKit.BADGE_AMBER)
	# un posto sopra la soglia: ancora neutro
	_set_capacity(int(ceil(float(used) * 100.0 / _warn_pct())) + 1)
	main._on_ui_tick()
	assert_eq(chip.state, BankChip.State.NORMAL)
	# rosso a pieno, con il numero di pezzi nel Carro
	_set_capacity(used)
	_bank().state.overflow_stacks = {"log_pine": 3}
	main._on_ui_tick()
	assert_eq(chip.state, BankChip.State.FULL)
	assert_eq(chip.tint, UiKit.DANGER)
	assert_true(lab.text.contains("3"), "PIENO · 3: " + lab.text)
	assert_true(lab.text.contains(tr("UI_TOP_BANK_FULL")), lab.text)
	assert_true(chip.tooltip_text.contains(str(used) + "/" + str(used)), "spazi usati/totale nel tooltip: " + chip.tooltip_text)
	assert_true(chip.tooltip_text.contains(TopBar.key_for("bank")), "tasto B nel tooltip")


func test_deposito_banda_compatta_mostra_solo_il_numero() -> void:
	var main := await _main()
	var chip := _bar(main).get_node("BankChip") as BankChip
	main._on_ui_tick()
	var full_txt := chip.label().text
	main._topbar.set_compact(true)
	main._on_ui_tick()
	assert_true(chip.label().text.length() < full_txt.length(), "compatto più corto di: " + full_txt)
	assert_false(chip.label().text.contains(tr("UI_TOP_BANK_FREE").replace("{n}", "").strip_edges()), "senza la parola «liberi»")
	assert_false(_bar(main).get_node("Title").visible, "niente marchio in banda compatta")
	main._topbar.set_compact(false)
	assert_true(_bar(main).get_node("Title").visible)


# ------------------------------------------------------------------ clic

func test_clic_su_oro_polvere_deposito_e_attivita() -> void:
	_grant("feature:prestige")
	var main := await _main()
	main._on_ui_tick()
	var bar := _bar(main)
	(bar.get_node("GoldChip") as TopCurrency).activated.emit()
	await wait_process_frames(2)
	var pop := main.get_node_or_null("CurrencyPopup") as CurrencyPopup
	assert_not_null(pop, "l'Oro apre la finestra Valute")
	var rows := CurrencyPopup.rows(_bank())
	assert_eq(str(rows[0].id), "gold", "l'oro è la prima riga")
	assert_eq(int(rows[0].qty), GameState.gold())
	if pop != null:
		pop.hide()
		pop.queue_free()
	(bar.get_node("DustChip") as TopCurrency).activated.emit()
	assert_eq(main.current_id, "prestige", "la Polvere porta al Prestigio")
	(bar.get_node("BankChip") as TopCurrency).activated.emit()
	assert_eq(main.current_id, "bank", "il Deposito porta al Deposito")
	(Game.system("skills") as SkillSystem).start("wc_pine")
	main._on_ui_tick()
	(bar.get_node("ActivityChip") as TopCurrency).activated.emit()
	assert_eq(main.current_id, "skill:woodcutting", "l'attività porta alla sua schermata")
	(Game.system("skills") as SkillSystem).stop()
	main._on_ui_tick()
	main.show_screen("bank")
	(bar.get_node("ActivityChip") as TopCurrency).activated.emit()
	assert_eq(main.current_id, "summary", "a riposo porta al Riepilogo")


# ------------------------------------------------------------------ attività

func test_attivita_a_riposo_in_corso_in_pausa_e_in_attesa() -> void:
	var main := await _main()
	var chip := _bar(main).get_node("ActivityChip") as ActivityChip
	var sk := Game.system("skills") as SkillSystem
	main._on_ui_tick()
	assert_eq(chip.state, ActivityChip.State.IDLE)
	assert_eq(main.get_node("%Activity").text, tr("UI_SKILLS_TOPBAR_IDLE"))
	assert_true(chip.get_node("Row/IdleHint").visible, "«— scegli un'attività ▸»")
	await wait_process_frames(2)
	var act := main.get_node("%Activity") as Label
	var need := act.get_theme_font("font").get_string_size(act.text, HORIZONTAL_ALIGNMENT_LEFT, -1, act.get_theme_font_size("font_size")).x
	assert_gte(act.size.x, need - 1.0, "«A riposo» si legge per intero (non collassa a 0 px)")
	assert_false(main.get_node("%ActivityBar").visible)
	sk.start("wc_pine")
	for i in 5:
		Game.sim.tick(0.1)
	main._on_ui_tick()
	main._update_slow()
	assert_eq(chip.state, ActivityChip.State.RUN)
	assert_true(main.get_node("%Activity").text.contains(Loc.t(DataRegistry.action("wc_pine").name)))
	assert_false(chip.get_node("Row/IdleHint").visible)
	assert_true(main.get_node("%ActivityBar").visible)
	assert_ne(main.get_node("%LevelEta").text, "", "tempo al livello")
	Clock.set_paused(true)
	main._on_ui_tick()
	assert_eq(chip.state, ActivityChip.State.PAUSED)
	assert_true(chip.get_node("Row/PausedTag").visible, "❚❚ IN PAUSA")
	assert_eq((_bar(main).get_node("PauseButton") as TopIcon).kind, TopIcon.Kind.PLAY)
	Clock.set_paused(false)
	sk._activity["waiting"] = true
	main._on_ui_tick()
	assert_eq(chip.state, ActivityChip.State.WAITING)
	assert_eq(main.get_node("%LevelEta").text, tr("UI_TOP_WAITING"))
	assert_true(chip.tooltip_text.contains(tr("UI_SKILLS_WAITING_MATERIALS")), "il testo già esistente nel tooltip")


func test_fit_text_accorcia_prima_l_azione_poi_la_mansione() -> void:
	var font := ThemeDB.fallback_font
	var fs := 16
	var full := ActivityChip.fit_text("Taglialegna", "Quercia secolare", 10000.0, font, fs)
	assert_eq(full, "Taglialegna · Quercia secolare")
	var w_full := font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mid := ActivityChip.fit_text("Taglialegna", "Quercia secolare", w_full - 40.0, font, fs)
	assert_true(mid.begins_with("Taglialegna · Qu"), "la mansione intera: " + mid)
	assert_true(mid.ends_with("…"), mid)
	var tiny := ActivityChip.fit_text("Taglialegna", "Quercia secolare", 60.0, font, fs)
	assert_false(tiny.begins_with("Taglialegna"), "poi anche la mansione: " + tiny)


# ------------------------------------------------------------------ larghezza

func _longest_names() -> Array:
	var best := ["", ""]
	var len_best := 0
	var acts: Dictionary = DataRegistry.all_actions()
	for aid in acts:
		var a: Dictionary = acts[aid]
		var sid := str(a.get("skill", ""))
		for lang in ["it", "en"]:
			var sn := str(DataRegistry.get_def("skills", sid).get("name", {}).get(lang, ""))
			var an := str(a.get("name", {}).get(lang, ""))
			if sn.length() + an.length() > len_best:
				len_best = sn.length() + an.length()
				best = [sn, an]
	return best


func test_tempo_al_livello_visibile_e_nulla_esce_dalla_finestra() -> void:
	var names := _longest_names()
	assert_gt(String(names[0]).length(), 0, "nomi più lunghi dai dati")
	var main := await _main()
	(Game.system("skills") as SkillSystem).start("wc_pine")
	_grant("feature:prestige")
	_bank().add_currency(PrestigeSystem.DUST, 123456789)
	_bank().add_currency(BankSystem.GOLD, 999999999)
	for lang in ["it", "en"]:
		TranslationServer.set_locale(lang)
		for w in WIDTHS:
			var sz := Vector2i(w, int(w * 9.0 / 16.0))
			DisplayServer.window_set_size(sz)
			get_tree().root.size = sz
			get_tree().root.content_scale_factor = 1.0
			await wait_process_frames(3)
			main._on_ui_tick()
			main._update_slow()
			var chip := _bar(main).get_node("ActivityChip") as ActivityChip
			chip.set_names(String(names[0]), String(names[1]))
			var eta := main.get_node("%LevelEta") as Label
			eta.text = LONG_ETA
			eta.visible = true
			await wait_process_frames(3)
			var view := get_tree().root.get_visible_rect()
			var where := "%s %d px" % [lang, w]
			assert_true(eta.is_visible_in_tree(), "tempo al livello visibile · " + where)
			assert_gte(eta.size.x, 40.0, "tempo al livello largo almeno 40 px · " + where)
			assert_true(chip.get_global_rect().grow(1.0).encloses(eta.get_global_rect()), "il tempo sta dentro il chip · " + where)
			for c in _bar(main).get_children():
				var ctl := c as Control
				if ctl == null or not ctl.visible:
					continue
				assert_true(view.grow(1.0).encloses(ctl.get_global_rect()), "%s dentro la finestra · %s (%s)" % [ctl.name, where, str(ctl.get_global_rect())])


func test_barra_si_restringe_senza_uscire_dalla_finestra_con_scala_1_e_1_25() -> void:
	var names := _longest_names()
	var main := await _main()
	(Game.system("skills") as SkillSystem).start("wc_pine")
	_grant("feature:prestige")
	_bank().add_currency(PrestigeSystem.DUST, 123456789)
	_bank().add_currency(BankSystem.GOLD, 999999999)
	for lang in ["it", "en"]:
		TranslationServer.set_locale(lang)
		for sc in [1.0, 1.25]:
			# dal largo allo stretto: il minimo largo di prima non deve tenere aperta la barra
			for w in [1536, 1280, 1024]:
				var sz := Vector2i(int(ceil(w * sc)), int(ceil(w * sc * 9.0 / 16.0)))
				DisplayServer.window_set_size(sz)
				get_tree().root.size = sz
				get_tree().root.content_scale_factor = sc
				await wait_process_frames(3)
				main._on_ui_tick()
				main._update_slow()
				(_bar(main).get_node("ActivityChip") as ActivityChip).set_names(String(names[0]), String(names[1]))
				var eta := main.get_node("%LevelEta") as Label
				eta.text = LONG_ETA
				await wait_process_frames(4)
				var view := get_tree().root.get_visible_rect()
				var where := "%s scala %.2f, %d px logici" % [lang, sc, int(view.size.x)]
				assert_lte(_bar(main).get_combined_minimum_size().x, view.size.x + 1.0, "la barra entra nella finestra · " + where)
				assert_true(eta.is_visible_in_tree(), "tempo al livello visibile · " + where)
				for c in _bar(main).get_children():
					var ctl := c as Control
					if ctl == null or not ctl.visible:
						continue
					assert_true(view.grow(1.0).encloses(ctl.get_global_rect()), "%s dentro la finestra · %s (%s)" % [ctl.name, where, str(ctl.get_global_rect())])


# ------------------------------------------------------------------ tooltip e tasto P

func test_tooltip_delle_icone_hanno_il_tasto() -> void:
	var main := await _main()
	main._on_ui_tick()
	var bar := _bar(main)
	assert_true((bar.get_node("PauseButton") as Button).tooltip_text.contains("P"), "Pausa · tasto P")
	assert_true((bar.get_node("SettingsButton") as Button).tooltip_text.contains("Esc"))
	assert_true((bar.get_node("SaveButton") as Button).tooltip_text.length() > 0)
	assert_eq((bar.get_node("HelpButton") as Button).tooltip_text, "UI_MAN2_HELP_TIP")
	assert_true(main.atr((bar.get_node("HelpButton") as Button).tooltip_text).contains("F1"))
	assert_eq(TopBar.key_for("pause"), "P", "il tasto P sta nella tabella di ShortcutMap")
	assert_false(tr("UI_TOP_BANK_TIP").begins_with("UI_"), "chiavi tradotte")


func test_tasto_p_mette_in_pausa_e_riprende() -> void:
	var main := await _main()
	var key := InputEventKey.new()
	key.keycode = KEY_P
	key.pressed = true
	assert_true(TopBar.is_pause_key(key))
	var pk := main.get_node("PauseKey")
	assert_false(Clock.paused)
	pk._unhandled_key_input(key)
	assert_true(Clock.paused, "P mette in pausa")
	pk._unhandled_key_input(key)
	assert_false(Clock.paused, "P riprende")
	key.ctrl_pressed = true
	assert_false(TopBar.is_pause_key(key), "Ctrl+P non è la pausa")


func test_tutorial_chiavi_della_barra() -> void:
	_grant("feature:prestige")
	var main := await _main()
	main._on_ui_tick()
	for k in ["topbar:pause", "topbar:save", "topbar:settings", "topbar:help", "topbar:bank", "topbar:stardust", "topbar:activity", "topbar:column"]:
		assert_not_null(TutorialTargets.find(get_tree(), k), "chiave del tutorial " + k)
	assert_not_null(main.get_node("%GoldValue"))
