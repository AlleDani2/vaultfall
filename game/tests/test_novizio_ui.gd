extends GutTest
## Difetti di interfaccia trovati dal bot NOVIZIO (docs/audit_2026-10-22/qa/95_BOT_NOVIZIO_UI.md):
## tooltip con chiave nuda (auto-traduzione spenta), Tab che porta il focus fuori vista.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const KEY_RE := "(?<![A-Za-z0-9_])UI_[A-Z0-9_]{3,}"

var _old_dir: String
var _old_tut: bool


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_novizio_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_tut = bool(Settings.get_value("tutorials"))
	Settings.set_value("tutorials", false)
	assert_true(Game.new_game(1, "normal", 5))


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("tutorials", _old_tut)


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func test_tooltip_della_colonna_destra_si_traduce() -> void:
	var main := await _main()
	# dalla pulizia A il vecchio pulsante della barra alta non c'è più: il tooltip da tradurre è quello del Registro nel binario
	assert_null(main.find_child("ColumnButton", true, false), "il vecchio ColumnButton è stato rimosso")
	var b := main.find_child("Btn_log", true, false) as Button
	assert_not_null(b)
	assert_true(b.can_auto_translate(), "senza traduzione automatica il giocatore leggerebbe UI_RAIL_LOG_TIP")
	assert_ne(b.atr(b.tooltip_text), b.tooltip_text)


func test_tooltip_dei_paralleli_si_traducono() -> void:
	(Game.system("skills") as SkillSystem).start("wc_pine")
	var main := await _main()
	main.call("_on_ui_tick")
	main.call("_update_slow")
	var panel := ParallelsPanel.new()          # dalla F3 il pannello non è più nel layout di MainScreen: si prova da solo
	add_child_autofree(panel)
	panel.refresh()
	var found := 0
	for n in panel.find_children("Row_*", "Button", true, false):
		var b := n as Button
		if b.tooltip_text.is_empty():
			continue
		found += 1
		assert_false(b.tooltip_text.begins_with("UI_"), "tooltip tradotto, non la chiave: " + b.tooltip_text)
	assert_gt(found, 0, "almeno una riga attiva nei Paralleli")


func test_scroll_segue_il_focus_con_tab() -> void:
	var main := await _main()
	for sc in main.find_children("*", "ScrollContainer", true, false):
		assert_true((sc as ScrollContainer).follow_focus, "ScrollContainer %s deve seguire il focus" % sc.name)
	main.call("show_screen", "skill:woodcutting")
	await wait_process_frames(2)
	# anche quelli creati dopo (schermate aperte dal menù)
	for sc in main.find_children("*", "ScrollContainer", true, false):
		assert_true((sc as ScrollContainer).follow_focus, "ScrollContainer %s (schermata) deve seguire il focus" % sc.name)
	var late := ScrollContainer.new()
	main.add_child(late)
	assert_true(late.follow_focus)


func test_tooltip_del_pallino_talenti_non_e_una_chiave() -> void:
	var main := await _main()
	var b: Button = main.get("_buttons")["talents"]
	main.call("_set_badge", "talents", 2, "UI_BADGE_TALENTS")
	assert_false(b.tooltip_text.is_empty())
	assert_false(b.tooltip_text.begins_with("UI_"), "il pulsante non si traduce da solo: il tooltip deve essere già tradotto (%s)" % b.tooltip_text)
	var sk := main.get("_buttons")["skill:woodcutting"] as Button
	main.call("_set_badge", "skill:woodcutting", 1, "UI_BADGE_PERKS")
	assert_false(sk.tooltip_text.begins_with("UI_"), sk.tooltip_text)


func test_attrezzo_a_ciclo_inoltrato_non_lascia_tween_vuoti() -> void:
	# QA 95: ERROR «Tween started with no Tweeners» quando il ciclo riparte oltre la carica (GUT segna rosso ogni ERROR)
	var tool := TextureRect.new()
	tool.custom_minimum_size = Vector2(32, 32)
	tool.texture = PlaceholderTexture2D.new()
	add_child_autofree(tool)
	await wait_process_frames(2)
	FxToolAnim.start(tool, null, "woodcutting", 1.0, 0.95)      # già nella carica
	await wait_process_frames(4)
	assert_true(is_instance_valid(tool))


func test_dialogo_liberato_prima_dell_adattamento_non_scrive_errori() -> void:
	# QA 95: «Error calling deferred method: GDScript::fit_dialog: Cannot convert argument 1 from Object to Object»
	var d := ConfirmationDialog.new()
	add_child(d)
	WindowFit.hook(d)
	d.popup_centered(Vector2i(300, 120))
	d.free()                                   # nello stesso fotogramma: la chiamata differita di fit_dialog parte con un oggetto già liberato
	await wait_process_frames(3)
	assert_true(true)


func test_pastiglia_del_registro_non_lascia_nodi_orfani() -> void:
	# QA 95 (bot NOVIZIO, 78 min): +115 nodi orfani e +60 MB; ogni riga del Registro lasciava un HBoxContainer vuoto
	var sec := LogCategory.of_notify_category("progress")
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 30:
		var c := LogView.chip(sec, false)
		c.free()
		var d := LogView.chip(sec, true)
		d.free()
	var after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_eq(after, before, "nessun nodo orfano dopo 30 pastiglie create e liberate")


func _sell_dialog() -> SellDialog:
	var dlg := SellDialog.new()
	add_child_autofree(dlg)
	await wait_process_frames(2)
	return dlg


func test_vendita_in_blocco_si_apre_sulla_categoria_con_qualcosa_da_vendere() -> void:
	# QA 95: Deposito pieno di legname, la finestra partiva da «Attrezzatura» con «Non corrisponde niente» e OK spento
	var bank := Game.system("bank") as BankSystem
	bank.add("log_pine", 30)
	var dlg := await _sell_dialog()
	assert_eq(str(dlg.editor.get_filter().cat), "material")
	assert_gt(int(dlg.plan.pieces), 0)
	assert_false(dlg.get_ok_button().disabled)


func test_vendita_in_blocco_resta_su_attrezzatura_se_ce_n_e() -> void:
	var bank := Game.system("bank") as BankSystem
	bank.add_instance({"def": "plate_helm_copper"})
	bank.add("log_pine", 30)
	var dlg := await _sell_dialog()
	assert_eq(str(dlg.editor.get_filter().cat), "equipment")
	assert_eq(int(dlg.plan.pieces), 1)


func test_giardino_avvisa_ogni_volta_se_il_deposito_e_pieno() -> void:
	var fm := Game.system("farming") as FarmingSystem
	var bank := Game.system("bank") as BankSystem
	bank.add("seed_potato", 3, "test")
	assert_true(fm.plant("garden", 0, "farm_potato"))
	fm.plot("garden", 0)["remaining_s"] = 0.0
	for id in DataRegistry.all_items():
		if bank.is_full():
			break
		bank.add(str(id), 1, "test")
	assert_true(bank.is_full())
	assert_eq(fm.ready_count(), 1)
	var scr: Control = (load("res://src/ui/screens/FarmScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(2)
	var got: Array = []
	var cb := func(kind: String, text: String, _d: Dictionary) -> void: got.append([kind, text])
	EventBus.notice.connect(cb)
	scr._on_harvest_all()
	scr._on_harvest_all()           # la seconda volta il sistema tace (avviso una tantum): la UI deve parlare comunque
	EventBus.notice.disconnect(cb)
	var full_msgs := 0
	for g in got:
		if str(g[1]) == tr("UI_SKILLS_STOP_BANK_FULL"):
			full_msgs += 1
	# Con il Carro di Ritiro (Deposito pieno non perde né blocca): il raccolto si fa e i pezzi attendono nel Carro
	assert_eq(full_msgs, 0, "nessun blocco «Deposito pieno»: il raccolto passa dal Carro di Ritiro")
	assert_eq(fm.ready_count(), 0, "il raccolto è stato fatto")


func test_deposito_ha_il_pulsante_equipaggia_con_la_voce_eroe_bloccata() -> void:
	# QA 95: missione «equipaggia la Spada di Rame» con Eroe bloccato e nessun pulsante nel dettaglio dell'oggetto
	var bank := Game.system("bank") as BankSystem
	var cb := Game.system("combat") as CombatSystem
	var uid := bank.add_instance({"def": "sword_copper"})
	var scr: Control = (load("res://src/ui/screens/BankScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	scr._on_group("gear")                    # F15: la spada sta nell'Armeria, non in «Tutto»
	await wait_process_frames(2)
	var row: ItemCell = null
	for c in scr._grid._pool:
		if c is ItemCell and (c as ItemCell).def_id == "sword_copper":
			row = c
	assert_not_null(row, "la spada compare nell'elenco")
	scr._on_cell_pressed(row)
	await wait_process_frames(2)
	var b := scr._detail_box.find_child("WornButton", true, false) as Button
	assert_not_null(b, "pulsante Equipaggia nel dettaglio")
	assert_false(b.disabled)
	assert_false(cb.is_equipped(uid))
	b.pressed.emit()
	assert_true(cb.is_equipped(uid), "premendolo la spada viene indossata")
	await wait_process_frames(2)
	var b2 := scr._detail_box.find_child("WornButton", true, false) as Button
	assert_not_null(b2)
	assert_eq(b2.text, "UI_EQ_BANK_UNEQUIP", "ora offre «Togli»")


func _all_text(n: Node) -> String:
	var parts := PackedStringArray()
	for c in n.find_children("*", "Label", true, false):
		parts.append((c as Label).text)
	return "\n".join(parts)


func test_impostazioni_si_ritraducono_al_cambio_di_lingua() -> void:
	# QA 95: dopo il cambio di lingua la nota della Modalità Cozy restava in inglese
	# Indipendente dalla lingua di sistema/di partenza: si parte SEMPRE dall'italiano e poi si passa all'inglese (un
	# set_value con lo stesso valore non emette il cambio di lingua e il test restava a metà).
	var old_loc := str(Settings.get_value("locale"))
	Settings.set_value("locale", "it")
	var scr: Control = (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(2)
	assert_string_contains(_all_text(scr), "Aggiunge")
	Settings.set_value("locale", "en")
	await wait_process_frames(3)
	assert_string_contains(_all_text(scr), "Adds +")
	Settings.set_value("locale", "it")
	await wait_process_frames(3)
	var txt := _all_text(scr)
	assert_false(txt.contains("Adds +"), "la nota Cozy non e' piu' in inglese")
	assert_string_contains(txt, "Aggiunge")
	Settings.set_value("locale", old_loc)


func test_schede_delle_casse_hanno_lo_stesso_sblocco_della_schermata() -> void:
	# QA 95: le schede Album e Guardaroba nella Sala dei Caveau erano attive ma la schermata era ancora bloccata: clic muto
	for t in CrateUi.TAB_DEFS:
		if str(t.tab) != "":
			continue
		var e := ScreenRegistry.get_entry(str(t.screen))
		assert_false(e.is_empty())
		var want := str(e.get("unlock", ""))
		if want == "feature:crates":
			want = ""                  # la Sala dei Caveau stessa: chi vede le schede ha già le Casse
		assert_eq(str(t.token), want, "scheda %s: sblocco coerente con ScreenRegistry" % t.id)


func test_pulsante_che_chiede_una_schermata_bloccata_non_resta_muto() -> void:
	var main := await _main()
	assert_eq(main.get("current_id"), "summary")
	assert_false(bool(main.call("show_screen", "dungeon")), "il Dungeon e' ancora bloccato")
	EventBus.screen_requested.emit("dungeon", {})          # come il pulsante «Dungeon…» del Combattimento
	await wait_process_frames(2)
	assert_ne(main.get("current_id"), "summary", "porta alla missione che lo sblocca")
	assert_eq(main.get("current_id"), "quests")


func test_giardino_permette_di_scegliere_il_talento_e_il_pallino_si_spegne() -> void:
	# QA 95: il pallino «Coltivazione ●N» contava un talento da scegliere, ma il Giardino non aveva dove sceglierlo
	var sk := Game.system("skills") as SkillSystem
	(GameState.data.get("unlocks", []) as Array).append("skill:farming")
	sk.add_xp("farming", float(Formulas.xp_total_for_level(12)))
	assert_eq(sk.pending_perk_tiers("farming").size(), 1)
	assert_eq(int(SidebarBadges.counts().get("skill:farming", 0)), 1, "il pallino conta il talento")
	var scr: Control = (load("res://src/ui/screens/FarmScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(2)
	var panel := scr.find_child("SkillPerkPanel", true, false) as SkillPerkPanel
	assert_not_null(panel, "pannello dei talenti nel Giardino")
	assert_true(panel.has_choice())
	panel.set_open(true)
	await wait_process_frames(3)
	assert_eq(panel.choosable_buttons(), 3, "tre opzioni per il tier raggiunto")
	var opts: Array = []
	for b in scr.find_child("PerkRows", true, false).find_children("*", "Button", true, false):
		if (b as Button).toggle_mode and not (b as Button).disabled:
			opts.append(b)
	(opts[0] as Button).pressed.emit()
	await wait_process_frames(3)
	assert_eq(sk.pending_perk_tiers("farming").size(), 0, "scelta fatta")
	assert_eq(int(SidebarBadges.counts().get("skill:farming", 0)), 0, "il pallino si è spento")


func test_deposito_blocca_dal_dettaglio_senza_errori_e_il_pannello_si_aggiorna() -> void:
	# QA 95: «Blocca» liberava il pulsante mentre emetteva `pressed` («Attempted to free a locked object»)
	# e il pannello restava con «Blocca» anche a oggetto bloccato
	var bank := Game.system("bank") as BankSystem
	var uid := bank.add_instance({"def": "sword_copper"})
	var scr: Control = (load("res://src/ui/screens/BankScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	scr._on_group("gear")                    # F15: la spada sta nell'Armeria, non in «Tutto»
	await wait_process_frames(2)
	var row: ItemCell = null
	for c in scr._grid._pool:
		if c is ItemCell and (c as ItemCell).def_id == "sword_copper":
			row = c
	scr._on_cell_pressed(row)
	await wait_process_frames(2)
	var lock: Button = null
	for b in scr._detail_box.find_children("*", "Button", true, false):
		if (b as Button).text == "UI_BANK_LOCK":
			lock = b
	assert_not_null(lock)
	lock.pressed.emit()
	await wait_process_frames(2)
	assert_true(bank.is_instance_locked(uid))
	var texts: Array = []
	for b in scr._detail_box.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	assert_has(texts, "UI_BANK_UNLOCK", "il pannello mostra ora «Sblocca»")
	assert_does_not_have(texts, "UI_BANK_LOCK")
