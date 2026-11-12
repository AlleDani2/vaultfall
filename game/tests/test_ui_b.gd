extends GutTest
## UI-B (audit G22, G23, G24, G34, G37, G38, G53): badge del menù, riquadro Paralleli, scorciatoie, colonna destra
## nascondibile/ridimensionabile, chiacchiera dei PNG e ticker della Gazzetta, requisiti cliccabili, tempo al livello,
## Modalità Cozy e interruttori nelle Impostazioni.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ui_b_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in ["right_col_visible", "right_col_width", "cozy_mode", "tutorials", "reduce_motion"]:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
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
	Modifiers.clear_source(CozyMode.SOURCE)
	ReqLink.reset_cache()


func _new() -> void:
	assert_true(Game.new_game(1, "normal", 7))


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1600, 900)       # sotto ~1100 px la colonna destra diventa un cassetto (layout adattivo): i test la vogliono al suo posto
	await wait_process_frames(2)
	return main


func _key(code: Key, ctrl: bool = false, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.echo = echo
	e.ctrl_pressed = ctrl
	return e


func _first_action(skill: String) -> String:
	return str(DataRegistry.actions_for_skill(skill)[0].id)


# ------------------------------------------------------------------ G22: badge e Paralleli

func test_badge_vuoti_a_inizio_partita() -> void:
	_new()
	# nessuna cosa da aprire o riscattare; resta solo il pallino di «Missioni» per i passi di scoperta (Manuale, Deposito, Compendio)
	var news := QuestGuide.discoveries(Game.system("quests") as QuestSystem).size()
	assert_eq(SidebarBadges.counts(), {"quests": news} if news > 0 else {}, "nessuna cosa in attesa")


func test_badge_casse_da_aprire() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	var cs := Game.system("crates") as CrateSystem
	bank.add("crate_millbrook", 2, "test")
	var key: Variant = cs.crate_def("crate_millbrook").get("key")
	if key != null:
		bank.add(str(key), 2, "test")
	var expected := 0
	for it in DataRegistry.items_by_category("crate"):
		expected += cs.openable(str(it.id))
	assert_true(expected > 0, "almeno una cassa apribile (se serve una chiave, il test la fornisce sotto)")
	assert_eq(int(SidebarBadges.counts().get("vault_hall", 0)), expected)


func test_badge_missioni_completabili() -> void:
	_new()
	var q := Game.system("quests") as QuestSystem
	var qid := q.current_main()
	var d := q.quest_def(qid)
	var pr: Array = []
	for o in d.objectives:
		pr.append(QuestSystem.target_of(o))
	q.state.progress[qid] = pr
	assert_true(q.is_ready(qid))
	assert_eq(int(SidebarBadges.counts().get("quests", 0)), q.ready_count() + QuestGuide.discoveries(q).size())
	assert_eq(SidebarBadges.label(150), "9+", "F4: tetto del numero nel menù")
	assert_eq(SidebarBadges.label(10), "9+")
	assert_eq(SidebarBadges.label(9), "9")
	assert_eq(SidebarBadges.label(7), "7")


func test_badge_commesse_consegnabili() -> void:
	_new()
	var mk := Game.system("market") as MarketSystem
	var bank := Game.system("bank") as BankSystem
	GameState.data["orders"] = [{"id": "o_t", "item": "log_pine", "qty": 3, "gold": 10, "rep": 1, "faction": "merchant_league",
		"npc": "bertoldo", "crate": "", "created_t": 0.0, "expires_t": float(mk.state.t) + 1e6}]
	assert_eq(int(SidebarBadges.counts().get("orders", 0)), 0, "senza gli oggetti non si può consegnare")
	bank.add("log_pine", 3, "test")
	assert_eq(int(SidebarBadges.counts().get("orders", 0)), 1)


func test_badge_talenti_da_scegliere() -> void:
	_new()
	var sk := Game.system("skills") as SkillSystem
	assert_false(SidebarBadges.counts().has("skill:woodcutting"))
	sk.state["woodcutting"]["level"] = 10
	assert_true(sk.pending_perk_tiers("woodcutting").size() > 0)
	assert_eq(int(SidebarBadges.counts()["skill:woodcutting"]), sk.pending_perk_tiers("woodcutting").size())


func test_badge_disegnati_nel_menu_e_nel_tooltip() -> void:
	_new()
	var main := await _main()
	(Game.system("quests") as QuestSystem).state.progress[(Game.system("quests") as QuestSystem).current_main()] = [999999]
	main._update_slow()
	var q := Game.system("quests") as QuestSystem
	if q.ready_count() > 0:
		var n := q.ready_count()       # F4: il numero ambra conta solo le missioni da riscattare (i passi di scoperta sono un puntino)
		assert_eq(main.badge_count("quests"), n)
		assert_true(main._badges["quests"].visible)
		assert_true((main._buttons["quests"] as Button).tooltip_text.contains(str(n)))
	var b: PanelContainer = main._badges["bank"]
	assert_false(b.visible, "nessun badge dove non c'è nulla")


func test_paralleli_righe_dai_sistemi() -> void:
	_new()
	assert_eq(ParallelsPanel.rows().size(), 0, "tutto fermo e niente sbloccato")
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start(_first_action("woodcutting")))
	var rows := ParallelsPanel.rows()
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].id, "active")
	assert_eq(rows[0].screen, "skill:woodcutting")
	assert_true(float(rows[0].frac) >= 0.0 and float(rows[0].frac) <= 1.0)
	# Orto sbloccato: riga presente anche se vuoto
	(GameState.data.unlocks as Array).append("skill:farming")
	var ids: Array = ParallelsPanel.rows().map(func(r: Dictionary) -> String: return str(r.id))
	assert_true(ids.has("farm"))


func test_paralleli_orto_conta_pronti_e_conto_alla_rovescia() -> void:
	_new()
	(GameState.data.unlocks as Array).append("skill:farming")
	var f := Game.system("farming") as FarmingSystem
	var kind := str(DataRegistry.table("farming_plots")[0].id)
	f.state.plots[kind][0] = {"crop": "x", "remaining_s": 0.0, "total_s": 10.0, "auto": false}
	f.state.plots[kind][1] = {"crop": "x", "remaining_s": 30.0, "total_s": 60.0, "auto": false}
	var row := {}
	for r in ParallelsPanel.rows():
		if r.id == "farm":
			row = r
	assert_false(row.is_empty())
	assert_true(str(row.value).contains("1/2"), "1 pronto su 2 piantati: " + str(row.value))
	assert_almost_eq(float(row.frac), 0.5, 0.01, "barra = avanzamento del più vicino a finire")
	assert_eq(row.screen, "skill:farming")


func test_paralleli_pannello_crea_righe_e_clic_apre_la_schermata() -> void:
	_new()
	var sk := Game.system("skills") as SkillSystem
	sk.start(_first_action("woodcutting"))
	var panel := ParallelsPanel.new()
	add_child_autofree(panel)
	panel.refresh()
	assert_true(panel.visible)
	assert_eq(panel.row_ids(), ["active"])
	for r in ParallelsPanel.side_rows():
		assert_ne(str(r.id), "active", "side_rows (sorgente dei segni del menù) non include l'attività principale")
	watch_signals(EventBus)
	panel.row_button("active").pressed.emit()
	assert_signal_emitted_with_parameters(EventBus, "screen_requested", ["skill:woodcutting", {"skill": "woodcutting"}])


func test_paralleli_nascosto_quando_non_c_e_nulla() -> void:
	_new()
	var panel := ParallelsPanel.new()
	add_child_autofree(panel)
	panel.refresh()
	assert_false(panel.visible)
	var main := await _main()
	assert_null(main.find_child("Parallels", true, false), "nel layout non c'è più il pannello Paralleli (F3, D11)")


# ------------------------------------------------------------------ G23: scorciatoie

func test_scorciatoie_risoluzione() -> void:
	var ids := ["summary", "skill:woodcutting", "bank"]
	assert_eq(ShortcutMap.resolve(_key(KEY_1), ids), {"type": "screen", "id": "summary"})
	assert_eq(ShortcutMap.resolve(_key(KEY_3), ids), {"type": "screen", "id": "bank"})
	assert_eq(ShortcutMap.resolve(_key(KEY_9), ids), {}, "voce inesistente: niente")
	assert_eq(ShortcutMap.resolve(_key(KEY_F, true), ids), {"type": "search"})
	assert_eq(ShortcutMap.resolve(_key(KEY_F), ids), {}, "F senza Ctrl non fa nulla")
	assert_eq(ShortcutMap.resolve(_key(KEY_ESCAPE), ids), {"type": "escape"})
	assert_eq(ShortcutMap.resolve(_key(KEY_Q), ids), {"type": "queue"})
	assert_eq(ShortcutMap.resolve(_key(KEY_B), ids), {"type": "screen", "id": "bank"})
	assert_eq(ShortcutMap.resolve(_key(KEY_C), ids), {"type": "screen", "id": "hero"})
	assert_eq(ShortcutMap.resolve(_key(KEY_F1), ids), {"type": "screen", "id": "manual"})
	assert_eq(ShortcutMap.resolve(_key(KEY_L), ids), {"type": "column"})
	assert_eq(ShortcutMap.resolve(_key(KEY_Q, false, true), ids), {}, "i tasti ripetuti non contano")
	assert_eq(ShortcutMap.resolve(_key(KEY_Q, true), ids), {}, "con Ctrl solo Ctrl+F")
	assert_eq(ShortcutMap.resolve(InputEventMouseButton.new(), ids), {})


func test_scorciatoie_etichette_per_i_tooltip() -> void:
	var ids := ["summary", "skill:woodcutting"]
	assert_eq(ShortcutMap.key_label_for("skill:woodcutting", ids), "2")
	assert_eq(ShortcutMap.key_label_for("bank", ids), "B")
	assert_eq(ShortcutMap.key_label_for("secrets", ids), "")


func test_scorciatoie_tabella_ha_tutti_i_tasti_del_doc16() -> void:
	var keys := ""
	for e in ShortcutMap.TABLE:
		keys += str(e.keys) + "|"
	for k in ["1 – 9", "Ctrl + F", "Esc", "Q", "B", "C", "F1"]:
		assert_true(keys.contains(k), "manca " + k)


func test_scorciatoie_menu_apre_voci_e_coda_porta_alla_mansione() -> void:
	_new()
	var main := await _main()
	assert_true(main.run_shortcut({"type": "screen", "id": "quests"}))
	assert_eq(main.current_id, "quests")
	assert_true(main.run_shortcut({"type": "escape"}), "Esc senza finestre: apre il menù di pausa")
	assert_true(Feedback.is_pause_menu_open())
	assert_eq(main.current_id, "quests", "la schermata sotto non cambia")
	assert_true(main.run_shortcut({"type": "escape"}), "e un secondo Esc lo chiude")
	assert_false(Feedback.is_pause_menu_open())
	assert_true(main.run_shortcut({"type": "queue"}))
	assert_eq(main.current_id, "skill:woodcutting", "Q apre la prima mansione sbloccata, con la coda in vista")
	var t := ShortcutMap.queue_target()
	assert_eq(t.params.focus, "queue")


func test_scorciatoie_tasti_reali_arrivano_a_main_screen() -> void:
	_new()
	(Game.system("quests") as QuestSystem).mark_intro_seen()      # con la finestra di benvenuto aperta i tasti sono suoi
	var main := await _main()
	main._unhandled_key_input(_key(KEY_2))
	assert_ne(main.current_id, "summary", "il tasto 2 apre la seconda voce disponibile")
	main._unhandled_key_input(_key(KEY_1))
	assert_eq(main.current_id, "summary")


func test_scorciatoia_ctrl_f_mette_il_fuoco_sulla_ricerca() -> void:
	_new()
	var main := await _main()
	main.show_screen("bank")
	await wait_process_frames(2)
	assert_true(main.run_shortcut({"type": "search"}))
	assert_true(main.get_viewport().gui_get_focus_owner() is LineEdit)


func test_esc_chiude_la_finestra_di_benvenuto() -> void:
	Settings.set_value("tutorials", true)
	_new()
	var main := await _main()
	var host: OverlayHost = null
	for c in main.get_children():
		if c is OverlayHost:
			host = c
	await wait_process_frames(2)
	assert_true(host.is_busy())
	assert_true(host.dismiss_active())
	await wait_process_frames(2)
	assert_false((Game.system("quests") as QuestSystem).intro_pending())


func test_schermata_impostazioni_mostra_le_scorciatoie_e_gli_interruttori() -> void:
	var panel := SettingsExtras.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var grid := panel.find_child("ShortcutsGrid", true, false) as GridContainer
	assert_not_null(grid)
	assert_eq(grid.get_child_count(), ShortcutMap.TABLE.size() * 2)
	var cozy := panel.find_child("CozyCheck", true, false) as CheckBox
	assert_not_null(cozy)
	assert_false(cozy.button_pressed)
	var scr: Control = (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	assert_not_null(scr.find_child("SettingsExtras", true, false), "agganciato alle Impostazioni")


func test_interruttore_tutorial_scrive_la_preferenza() -> void:
	Settings.set_value("tutorials", true)
	var panel := SettingsExtras.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var checks := panel.find_children("*", "CheckBox", true, false)
	var tut: CheckBox = null
	for c in checks:
		for sib in c.get_parent().get_children():            # la riga è [casella][etichetta] (revisione grafica 1.0, problema 13)
			if sib is Label and (sib as Label).text == "UI_UIB_SET_TUTORIALS":
				tut = c
	assert_not_null(tut, "interruttore dei tutorial raggiungibile")
	tut.button_pressed = false
	assert_false(bool(Settings.get_value("tutorials")))
	tut.button_pressed = true
	assert_true(bool(Settings.get_value("tutorials")))


# ------------------------------------------------------------------ G24: colonna destra

func test_impostazioni_colonna_destra_limiti() -> void:
	Settings.set_value("right_col_width", 9999)
	assert_eq(int(Settings.get_value("right_col_width")), 520)
	Settings.set_value("right_col_width", 10)
	assert_eq(int(Settings.get_value("right_col_width")), 180)
	assert_false(Settings.set_value("right_col_width", "larga"), "tipo sbagliato rifiutato")
	assert_false(bool(Settings.DEFAULTS["right_col_visible"]), "dalla F3 la colonna destra è un cassetto: fissata solo su richiesta")


func test_colonna_destra_si_nasconde_e_si_ricorda() -> void:
	# F3: la colonna destra è un cassetto chiuso di default; la preferenza «fissata» si ricorda e vale solo in banda larga
	_new()
	var main := await _main()
	var right := main.get_node("Root/Body/RightColumn") as Control
	assert_false(right.visible, "chiuso di default")
	assert_false(bool(Settings.get_value("right_col_visible")))
	main.toggle_column()
	assert_true(main.drawer_open(), "L apre il cassetto")
	assert_false(bool(Settings.get_value("right_col_visible")), "il cassetto non cambia la preferenza")
	main.run_shortcut({"type": "column"})
	assert_false(main.drawer_open(), "L lo richiude")
	Settings.set_value("right_col_visible", true)          # fissata (la finestra del test è larga)
	assert_true(right.visible, "fissata: è di nuovo una colonna")
	assert_true(main._grip.visible)
	main.toggle_column()
	assert_false(right.visible, "L toglie la colonna fissata")
	assert_false(bool(Settings.get_value("right_col_visible")), "preferenza salvata")
	assert_false(main._grip.visible)


func test_colonna_destra_si_ridimensiona_trascinando() -> void:
	_new()
	var main := await _main()
	var right := main.get_node("Root/Body/RightColumn") as Control
	Settings.set_value("right_col_visible", true)          # la maniglia c'è solo con la colonna fissata (banda larga)
	Settings.set_value("right_col_width", 250)
	main._apply_column()
	main._grip.dragged.emit(-100.0)           # verso sinistra = più larga
	assert_almost_eq(right.custom_minimum_size.x, 350.0, 0.1)
	main._grip.released.emit()
	assert_eq(int(Settings.get_value("right_col_width")), 350)
	main._grip.dragged.emit(10000.0)
	assert_almost_eq(right.custom_minimum_size.x, 180.0, 0.1, "minimo")
	main._grip.dragged.emit(-10000.0)
	assert_almost_eq(right.custom_minimum_size.x, 520.0, 0.1, "massimo")
	main._grip.reset_requested.emit()
	assert_almost_eq(right.custom_minimum_size.x, 250.0, 0.1, "doppio clic = larghezza di base")


func test_colonna_destra_ha_lo_slot_amici_per_il_coop() -> void:
	_new()
	var main := await _main()
	var vbox := main.get_node("Root/Body/RightColumn/RightScroll/VBox")
	var slot := vbox.get_node_or_null("AmiciSlot") as VBoxContainer
	assert_not_null(slot, "slot riservato a COOP-2")
	assert_eq(main.find_child("AmiciSlot", true, false), slot, "stesso nodo anche per %AmiciSlot")
	assert_not_null(vbox.get_node_or_null("DrawerHead"), "intestazione del cassetto in cima")
	assert_null(vbox.get_node_or_null("Parallels"), "Paralleli non è più nel layout (D11)")
	assert_true(vbox.get_node("DrawerHead").get_index() < slot.get_index(), "intestazione, poi gli amici, poi il registro")
	assert_true(slot.get_index() < vbox.get_node("Log").get_index())
	assert_eq(slot.get_child_count(), 1, "il riquadro Amici sta dentro lo slot")
	assert_true(slot.get_child(0) is FriendsPanel)


# ------------------------------------------------------------------ G34: PNG e Gazzetta

func test_dati_chat_3_5_battute_bilingui() -> void:
	var n_chat := 0
	for n in DataRegistry.table("npcs"):
		if not n.has("chat"):
			continue
		n_chat += 1
		var lines: Array = n.chat
		assert_true(lines.size() >= 3 and lines.size() <= 5, "%s: %d battute" % [n.id, lines.size()])
		for l in lines:
			assert_true(str(l.it).length() > 3 and str(l.en).length() > 3)
	assert_true(n_chat >= 8, "almeno otto PNG chiacchierano")


func test_chat_a_rotazione() -> void:
	var seen := {}
	var npcs := {}
	for i in 60:
		var c := CityStrip.chat_at(i)
		assert_false(c.is_empty())
		seen[str(c.line)] = true
		npcs[str(c.npc)] = true
	assert_true(npcs.size() >= 8, "PNG diversi a turno")
	assert_true(seen.size() >= 30, "battute diverse nel tempo")
	assert_ne(CityStrip.chat_at(0).line, CityStrip.chat_at(1).line)
	assert_eq(CityStrip.chat_at(0), CityStrip.chat_at(0), "deterministica")


func test_ticker_gazzetta_usa_le_notizie_dei_dati() -> void:
	_new()
	var mk := Game.system("market") as MarketSystem
	var quiet := TranslationServer.translate("UI_MARKET_GAZETTE_QUIET")
	assert_eq(CityStrip.news_items(), PackedStringArray([quiet]), "tranquillo")
	var ev: Dictionary = DataRegistry.table("gazette_events")[0]
	mk.state.gazette.active.append({"id": ev.id, "category": ev.category, "mult": float(ev.mult), "ends_t": float(mk.state.t) + 3600.0})
	var items := CityStrip.news_items()
	assert_eq(items.size(), 1)
	assert_eq(items[0], Loc.t(ev.text))


func test_striscia_citta_visibile_solo_nelle_voci_della_citta() -> void:
	# F6 (D16): la striscia non sta più nella cornice di nessuna schermata; è una riga in fondo al Riepilogo
	_new()
	var main := await _main()
	assert_false(main._city_strip.visible, "Riepilogo: fuori dalla cornice")
	assert_true(main.show_screen("bank"))
	assert_false(main._city_strip.visible, "Deposito: la striscia non c'è più")
	assert_false(main.city_strip_visible_for("bank"))
	main.show_screen("quests")
	assert_false(main._city_strip.visible)
	main.show_screen("summary")
	await wait_process_frames(2)
	var row := main.current_screen().find_child("CityRow", true, false) as CityStrip
	assert_not_null(row, "la riga Città è nel Riepilogo")
	assert_true(row.is_visible_in_tree())
	assert_ne((row.find_child("Chat", true, false) as Label).text, "", "una battuta è mostrata")
	assert_ne((row.find_child("News", true, false) as Label).text, "")


func test_striscia_citta_ticker_scorre_e_con_riduci_animazioni_alterna_fermo() -> void:
	_new()
	Settings.set_value("reduce_motion", false)
	var strip := CityStrip.make_row()      # F6: la striscia è una riga del Riepilogo
	strip.custom_minimum_size.x = 600
	add_child_autofree(strip)
	await wait_process_frames(2)
	var x0: float = strip._news.position.x
	strip._process(0.5)
	assert_lt(strip._news.position.x, x0, "scorre verso sinistra")
	Settings.set_value("reduce_motion", true)
	strip.next_news()
	assert_eq(strip._news.position.x, 0.0, "fermo")
	var i0: int = strip._news_i
	strip._process(CityStrip.NEWS_HOLD_SECONDS + 0.1)
	assert_gt(strip._news_i, i0, "alterna la notizia dopo qualche secondo")


# ------------------------------------------------------------------ G37: nessun vicolo cieco

func test_reqlink_oggetto_porta_alla_mansione_che_lo_produce() -> void:
	_new()
	var act: Dictionary = DataRegistry.actions_for_skill("woodcutting")[0]
	var item := str(act.outputs[0].item)
	var t := ReqLink.target_for_item(item)
	assert_eq(t.screen, "skill:woodcutting")
	assert_eq(t.params.produces, item)
	assert_eq(t.params.skill, "woodcutting")


func test_reqlink_mansione_bloccata_porta_alla_missione() -> void:
	_new()
	var item := str(DataRegistry.actions_for_skill("mining")[0].outputs[0].item)
	var t := ReqLink.target_for_item(item)
	assert_eq(t.screen, "quests", "il Minatore è bloccato: si va alla missione che lo sblocca")
	assert_eq(t.params.quest, UnlockSystem.quest_for_token("skill:mining", DataRegistry))
	assert_eq(ReqLink.target_for_token("feature:inesistente"), {})


func test_reqlink_livello_e_edificio() -> void:
	_new()
	var t := ReqLink.target_for_level("woodcutting")
	assert_eq(t.screen, "skill:woodcutting")
	assert_eq(t.params.filter, "available")
	assert_eq(ReqLink.target_for_building("farm"), {}, "Tenuta ancora bloccata: nessun link morto")
	(GameState.data.unlocks as Array).append("feature:estate")
	ReqLink.reset_cache()
	assert_eq(ReqLink.target_for_building("farm").screen, "estate")


func test_reqlink_link_e_bbcode_navigano() -> void:
	_new()
	var t := {"screen": "quests", "params": {"quest": "q_x"}, "hint": "UI_UIB_REQ_HINT_QUEST"}
	var link := ReqLink.link("vai", t)
	add_child_autofree(link)
	assert_true(link is Button)
	watch_signals(EventBus)
	(link as Button).pressed.emit()
	assert_signal_emitted_with_parameters(EventBus, "screen_requested", ["quests", {"quest": "q_x"}])
	var bb := ReqLink.bbcode("Pino ×3", t)
	assert_true(bb.contains("[url=req:quests|"))
	var meta := bb.get_slice("[url=", 1).get_slice("]", 0)
	ReqLink.meta_go(meta)
	assert_signal_emit_count(EventBus, "screen_requested", 2)
	assert_true(ReqLink.link("x", {}) is Label, "senza strada niente link morto")
	assert_eq(ReqLink.bbcode("x", {}), "x")


func test_voci_bloccate_del_menu_sono_cliccabili_e_portano_alla_missione() -> void:
	_new()
	var main := await _main()
	var btn: Button = main._buttons["skill:mining"]
	assert_false(btn.disabled)
	assert_true(btn.has_meta("req_target"))
	var t: Dictionary = btn.get_meta("req_target")
	assert_eq(t.screen, "quests")
	watch_signals(EventBus)
	btn.pressed.emit()
	assert_signal_emitted(EventBus, "screen_requested")
	assert_ne(main.current_id, "skill:mining", "la mansione bloccata non si apre")
	assert_true(main.show_screen("quests", t.params), "la missione si apre e si porta in vista")


func test_skill_screen_filtra_su_produce_e_disponibili() -> void:
	_new()
	var sk := Game.system("skills") as SkillSystem
	sk.add_xp("woodcutting", 100000.0)
	var scr: Control = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	var acts := DataRegistry.actions_for_skill("woodcutting")
	var item := str(acts[0].outputs[0].item)
	scr.open({"skill": "woodcutting", "produces": item})
	await wait_process_frames(2)
	var shown := 0
	for a in acts:
		if str(a.get("kind", "")) == "crop":
			continue
		var vis: bool = scr._rows[str(a.id)].panel.visible
		var makes := false
		for o in a.get("outputs", []):
			makes = makes or str(o.item) == item
		assert_eq(vis, makes, str(a.id))
		shown += 1 if vis else 0
	assert_true(shown >= 1)
	assert_true(scr._chip.visible, "chip con «Mostra tutto»")
	scr._clear_req_filter()
	assert_false(scr._chip.visible)
	for a in acts:
		if str(a.get("kind", "")) != "crop":
			assert_true(scr._rows[str(a.id)].panel.visible)


func test_skill_screen_filtro_disponibili_nasconde_le_bloccate() -> void:
	_new()
	var scr: Control = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"skill": "woodcutting", "filter": "available"})
	await wait_process_frames(2)
	for aid in scr._rows:
		assert_eq(scr._rows[aid].panel.visible, not scr._rows[aid].locked, aid)


func test_skill_screen_requisito_livello_e_ingredienti_sono_link() -> void:
	_new()
	var scr: Control = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"skill": "woodcutting"})
	await wait_process_frames(2)
	var locked := ""
	for aid in scr._rows:
		if scr._rows[aid].locked:
			locked = str(aid)
			break
	assert_ne(locked, "", "al livello 1 qualche azione è bloccata")
	var box: VBoxContainer = scr._rows[locked].req_box
	assert_eq(box.get_child_count(), 1)
	assert_true(box.get_child(0) is Button, "il livello mancante è cliccabile")


func test_skill_screen_focus_coda_apre_il_pannello() -> void:
	_new()
	var scr: Control = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"skill": "woodcutting", "focus": "queue"})
	await wait_process_frames(2)
	assert_true(scr._extras._toggle.button_pressed, "coda azioni aperta")


func test_tenuta_porta_in_vista_l_edificio_e_missione_cliccabile() -> void:
	_new()
	(GameState.data.unlocks as Array).append("feature:estate")
	var scr: Control = (load("res://src/ui/screens/EstateScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	var bid := str((Game.system("estate") as EstateSystem).building_ids()[-1])
	scr.open({"building": bid})
	await wait_process_frames(2)
	assert_true(scr._cards.has(bid))
	scr.refresh()
	# F9: carte compatte: l'oro è sul pulsante di miglioramento, sotto restano solo i materiali che mancano (cliccabili) o il motivo del blocco
	var card: Dictionary = scr._cards[bid]
	assert_true((card.panel as Control).is_visible_in_tree(), "la carta dell'edificio è in vista")
	var txt: String = (card.cost as RichTextLabel).text
	assert_eq((card.cost as RichTextLabel).visible, txt.length() > 0, "la riga dei materiali c'è solo se serve")
	assert_true((card.b1 as Button).text.length() > 0, "il pulsante di miglioramento porta il costo")
	assert_eq((card.menu as PopupMenu).item_count, 3, "+1, +10 e Max stanno nel menù del pulsante")


func test_missioni_porta_in_vista_la_missione_richiesta() -> void:
	_new()
	var q := Game.system("quests") as QuestSystem
	var scr: Control = (load("res://src/ui/screens/QuestScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"quest": q.current_main()})
	await wait_process_frames(2)
	assert_eq(scr._focus_quest, "", "il fuoco è stato consumato")


# ------------------------------------------------------------------ G53: tempo al livello e Modalità Cozy

func test_tempo_al_livello() -> void:
	_new()
	assert_eq(LevelEta.info(), {})
	assert_eq(LevelEta.short_text({}), "")
	var sk := Game.system("skills") as SkillSystem
	sk.start(_first_action("woodcutting"))
	var i := LevelEta.info()
	assert_eq(i.skill, "woodcutting")
	assert_gt(float(i.seconds), 0.0)
	var txt := LevelEta.short_text(i)
	assert_ne(txt, "")
	assert_true(txt.contains(str(int(i.level) + 1)))


func test_tempo_al_livello_nella_barra_in_alto() -> void:
	_new()
	var sk := Game.system("skills") as SkillSystem
	sk.start(_first_action("woodcutting"))
	var main := await _main()
	main._update_slow()
	await wait_process_frames(2)
	assert_true(main._level_eta.visible)
	assert_ne(main._level_eta.text, "")
	assert_gte(main._level_eta.size.x, 40.0, "F2 (I5): il tempo al livello non viene più schiacciato a 1 px")


func _modes() -> ModeSystem:
	return Game.system("modes") as ModeSystem


func test_cozy_aggiunge_il_bonus_xp_dai_modificatori() -> void:
	_new()
	var sk := Game.system("skills") as SkillSystem
	var aid := _first_action("woodcutting")
	var base_xp := float(sk.profile_of(aid).xp)
	sk.start(aid)
	var eta0 := float(LevelEta.info().seconds)
	assert_false(Modifiers.stack.has_source(CozyMode.SOURCE))
	assert_gt(CozyMode.xp_pct(), 0.0, "il valore viene da constants.json")
	Settings.set_value("cozy_mode", true)          # nessuna schermata: la applica ModeSystem
	assert_true(_modes().is_cozy())
	assert_true(Modifiers.stack.has_source(CozyMode.SOURCE))
	assert_almost_eq(float(sk.profile_of(aid).xp), base_xp * (1.0 + CozyMode.xp_pct() / 100.0), base_xp * 0.001, "+50% XP")
	assert_lt(float(LevelEta.info().seconds), eta0, "il tempo al livello scende")
	Settings.set_value("cozy_mode", false)
	assert_false(_modes().is_cozy())
	assert_false(Modifiers.stack.has_source(CozyMode.SOURCE))
	assert_almost_eq(float(sk.profile_of(aid).xp), base_xp, base_xp * 0.001)
	assert_eq(_modes().run_tags(), ["cozy"], "la partita ricorda di essere stata Cozy: codici-risultato marcati")


func test_cozy_nuova_partita_segue_la_preferenza_e_si_salva_nella_partita() -> void:
	Settings.set_value("cozy_mode", true)
	_new()
	assert_true(_modes().is_cozy())
	assert_true(bool(GameState.data.modes.cozy), "è nello stato salvato della partita")
	assert_true(Modifiers.stack.has_source(CozyMode.SOURCE))
	SaveService.save_now()
	Settings.set_value("cozy_mode", false)         # la preferenza del PC cambia, la partita no
	assert_false(Modifiers.stack.has_source(CozyMode.SOURCE) and not _modes().is_cozy())
	assert_true(Game.load_game(1).ok)
	assert_true(_modes().is_cozy(), "la partita ricorda che era Cozy")
	assert_true(Modifiers.stack.has_source(CozyMode.SOURCE), "riapplicata al caricamento, senza MainScreen")
	assert_eq(_modes().run_tags(), ["cozy"])


func test_partita_normale_non_e_marcata() -> void:
	_new()
	assert_false(_modes().is_cozy_run())
	assert_eq(_modes().run_tags(), [])


func _offline_xp(cozy: bool) -> float:
	Settings.set_value("cozy_mode", cozy)
	_new()
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start(_first_action("woodcutting")))
	var before := sk.xp("woodcutting")
	Game.sim.run_offline(1800.0)
	var gained := sk.xp("woodcutting") - before
	Game.stop_game(false)
	return gained


func test_cozy_vale_anche_offline() -> void:
	var plain := _offline_xp(false)
	var cozy := _offline_xp(true)
	assert_gt(plain, 0.0)
	assert_almost_eq(cozy / plain, 1.0 + CozyMode.xp_pct() / 100.0, 0.05, "l'offline del Bentornato dà +50% XP")


func test_cozy_con_partita_chiusa_non_lascia_modificatori() -> void:
	Settings.set_value("cozy_mode", true)
	assert_false(Modifiers.stack.has_source(CozyMode.SOURCE))
