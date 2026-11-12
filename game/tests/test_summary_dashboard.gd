extends GutTest
## Riepilogo come cruscotto, Missioni, Compendio ed Eventi (progetto di interfaccia, docs/ui_redesign/06 D16, D17, D22; fase F6):
## «Da fare» ha la stessa sorgente dei segnali del menù e sparisce se è vuoto; nessuna prosa fissa dopo la prima visita;
## le sezioni richiudibili ricordano lo stato; l'obiettivo compare una sola volta; la striscia Città è una riga del Riepilogo;
## Missioni ha il prossimo passo evidenziato, nessun «Da fare ora» e «Da scoprire» in una scheda propria.

const SUMMARY := "res://src/ui/screens/SummaryScreen.tscn"
const QUESTS := "res://src/ui/screens/QuestScreen.tscn"
const COMPENDIUM := "res://src/ui/screens/CompendiumScreen.tscn"
const EVENTS := "res://src/ui/screens/EventsScreen.tscn"

var _old_dir: String
var _old: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_summary_dashboard_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in ["tutorials", "reduce_motion", "locale", "seen_intro"]:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
	Settings.set_value("reduce_motion", true)
	Settings.set_value("locale", "it")
	Settings.set_value("seen_intro", [])
	assert_true(Game.new_game(1, "normal", 4242))


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


func _open(path: String, params: Dictionary = {}) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open(params)
	return s


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _crates(n: int) -> void:
	var cs := Game.system("crates") as CrateSystem
	_bank().add("crate_millbrook", n, "test")
	var key: Variant = cs.crate_def("crate_millbrook").get("key")
	if key != null:
		_bank().add(str(key), n, "test")


func _quest_ready() -> void:
	var q := Game.system("quests") as QuestSystem
	var qid := q.current_main()
	var pr: Array = []
	for o in q.quest_def(qid).objectives:
		pr.append(QuestSystem.target_of(o))
	q.state.progress[qid] = pr


## Testi di tutte le etichette e i pulsanti VISIBILI sotto `root`.
func _texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue
		if n is Label:
			out.append((n as Label).text)
		elif n is Button:
			out.append((n as Button).text)
		stack.append_array(n.get_children())
	return out


func _count_containing(root: Node, needle: String) -> int:
	var n := 0
	for t in _texts(root):
		if needle in t:
			n += 1
	return n


# ------------------------------------------------------------------ Da fare

func test_da_fare_coincide_con_i_segnali_del_menu() -> void:
	_crates(2)
	_quest_ready()
	var s := await _open_summary()
	var rows := SummaryScreen.todo_rows()
	assert_gt(rows.size(), 0)
	var keys := PackedStringArray()
	for r in rows:
		keys.append(str(r.key))
	var sig := SidebarBadges.signals({"recent": _all_skill_ids()})
	for id in sig:
		for c in sig[id].causes:
			if str(c[0]) == SidebarBadges.CAUSE_NEW_ENTRY:
				continue
			assert_true(keys.has(str(c[0])), "ogni causa dei segnali è una riga di «Da fare»: " + str(c[0]))
	for r in rows:       # e viceversa: nessuna riga che il menù non segnali
		var found := false
		for id in sig:
			for c in sig[id].causes:
				if str(c[0]) == str(r.key):
					found = true
		assert_true(found, "ogni riga ha una causa nei segnali: " + str(r.key))
	assert_true(keys.has("UI_UIB_BADGE_CRATES"))
	assert_true(keys.has("UI_UIB_BADGE_QUESTS"))
	# la carta è visibile, con un pulsante per riga
	var card := s.find_child("TodoCard", true, false) as Control
	assert_true(card.visible)
	assert_eq(card.find_children("TodoGo", "Button", true, false).size(), rows.size())


func test_da_fare_vuoto_la_sezione_non_c_e() -> void:
	var s := await _open_summary()
	# inizio partita: nessun numero e nessun pericolo; restano al massimo i puntini di novità
	for r in SummaryScreen.todo_rows():
		assert_ne(str(r.kind), SidebarBadges.KIND_COUNT, "nessuna azione da fare a inizio partita")
	# senza alcuna causa la carta sparisce: simulo svuotando i passi di scoperta
	var q := Game.system("quests") as QuestSystem
	for d in QuestGuide.discoveries(q):
		(q.state.seen_screens as Array).append(str(d.screen))
	var card := s.find_child("TodoCard", true, false) as Control
	var rows := SummaryScreen.todo_rows()
	s.refresh()
	assert_eq(card.visible, not rows.is_empty(), "la carta c'è se e solo se ci sono righe")


func test_da_fare_pulsante_apre_la_voce() -> void:
	_crates(1)
	var s := await _open_summary()
	var asked: Array = []
	EventBus.screen_requested.connect(func(id: String, _p: Dictionary) -> void: asked.append(id))
	var row := s.find_child("Todo_UI_UIB_BADGE_CRATES", true, false)
	assert_not_null(row)
	(row.find_child("TodoGo", true, false) as Button).pressed.emit()
	assert_eq(asked, ["vault_hall"])


func _all_skill_ids() -> Array:
	var out: Array = []
	for d in DataRegistry.table("skills"):
		out.append(ScreenRegistry.menu_id_for_skill(str(d.id)))
	return out


func _open_summary() -> GameScreen:
	var s := _open(SUMMARY)
	await wait_process_frames(2)
	s.refresh()
	return s


# ------------------------------------------------------------------ prosa e Disclosure

func test_prosa_fissa_solo_alla_prima_visita() -> void:
	var s1 := await _open_summary()
	assert_true((s1.find_child("IntroText", true, false) as Control).visible, "prima visita: la frase «a cosa serve» c'è")
	assert_true(IntroOnce.seen("summary"))
	s1.queue_free()
	await wait_process_frames(2)
	var s2 := await _open_summary()
	assert_false((s2.find_child("IntroText", true, false) as Control).visible, "seconda visita: la frase è dietro il «?»")
	(s2.find_child("IntroHelp", true, false) as Button).pressed.emit()
	assert_true((s2.find_child("IntroText", true, false) as Control).visible, "il «?» la riapre")
	assert_eq(_count_containing(s2, tr("UI_SUMMARY_INTRO")), 0, "la frase di benvenuto fissa non c'è più")
	assert_eq(_count_containing(s2, tr("UI_MODE")), 0, "«Modalità: Normale» non compare")


func test_modalita_si_vede_solo_se_non_normale() -> void:
	Game.stop_game(false)
	assert_true(Game.new_game(1, "extreme", 71))
	var s := await _open_summary()
	assert_true((s.find_child("ModeRow", true, false) as Control).visible)
	assert_eq((s.get_node("%ModeValue") as Label).text, tr("UI_MODE_EXTREME"))


func test_nessun_suggerimento_comico_in_cima() -> void:
	var q := Game.system("quests") as QuestSystem
	q.state.done.append("zz_fake")        # non è più «partita nuova»: il consiglio del primo passo non c'è
	var s := await _open_summary()
	assert_false((s.get_node("%Tip") as Label).visible)
	assert_eq((s.get_node("%Tip") as Label).text, "")


func test_disclosure_ricordate() -> void:
	var s1 := await _open_summary()
	var btn := s1.find_child("Fold_summary_profile", true, false) as Button
	var body := s1.find_child("Body_summary_profile", true, false) as Control
	assert_true(btn.visible, "la sezione Titolo e profilo e' presente nel riepilogo")
	if not btn.visible:
		return
	assert_false(body.visible, "Titolo e profilo: chiuso di default")
	btn.pressed.emit()
	assert_true(body.visible)
	assert_true(btn.text.begins_with(Disclosure.OPEN))
	s1.queue_free()
	await wait_process_frames(2)
	var s2 := await _open_summary()
	assert_true((s2.find_child("Body_summary_profile", true, false) as Control).visible, "lo stato aperto è ricordato")
	# Prossimi traguardi: aperto nelle prime 2 ore, e se il giocatore lo chiude resta chiuso
	var m := s2.find_child("Body_summary_milestones", true, false) as Control
	assert_true(m.visible, "nelle prime 2 ore è aperto")
	(s2.find_child("Fold_summary_milestones", true, false) as Button).pressed.emit()
	s2.queue_free()
	await wait_process_frames(2)
	var s3 := await _open_summary()
	assert_false((s3.find_child("Body_summary_milestones", true, false) as Control).visible, "chiuso dal giocatore: resta chiuso")


func test_prossimi_traguardi_chiusi_dopo_due_ore() -> void:
	GameState.data.stats["playtime_s"] = 3.0 * 3600.0
	var s := await _open_summary()
	assert_false((s.find_child("Body_summary_milestones", true, false) as Control).visible)


func test_obiettivo_una_volta_sola() -> void:
	var q := Game.system("quests") as QuestSystem
	var d := q.quest_def(q.current_main())
	var obj := QuestText.objective(d.objectives[0], DataRegistry)
	var s := await _open_summary()
	assert_eq(_count_containing(s, obj), 1, "l'obiettivo compare una volta sola nel Riepilogo")
	assert_eq(_count_containing(s, "UI_SCR_SUMMARY_NEXT"), 1, "un solo «Prossimo passo» (l'intestazione porta la chiave, tradotta dal motore)")
	assert_eq(_count_containing(s, tr("UI_QG_HOW_LABEL")), 0, "il testo «Come fare» sta in Missioni, non nel Riepilogo")


func test_striscia_citta_nel_riepilogo_come_riga() -> void:
	var s := await _open_summary()
	var row := s.find_child("CityRow", true, false) as CityStrip
	assert_not_null(row)
	assert_lte(row.custom_minimum_size.y, 40.0, "è una riga, non una striscia da 48 px")
	assert_ne((row.find_child("News", true, false) as Label).text, "")


func test_numeri_chiave_in_una_riga() -> void:
	var s := await _open_summary()
	var line := (s.get_node("%Numbers") as Label).text
	assert_true(line.contains(Loc.tf("UI_SCR_SUMMARY_NUMBERS_LV", {"n": NumberFormat.fmt(GameState.total_level())})))
	assert_false(line.contains("\n"))
	assert_true(line.contains(" · "))


# ------------------------------------------------------------------ Missioni

func test_missioni_senza_blocco_da_fare_ora_e_prossimo_passo_evidenziato() -> void:
	var s := _open(QUESTS)
	await wait_process_frames(2)
	s.refresh()
	assert_eq(_count_containing(s, tr("UI_QG_TODO")), 0, "il blocco «Da fare ora» non c'è")
	var q := Game.system("quests") as QuestSystem
	var card := s.find_child("Card_" + q.current_main(), true, false)
	assert_not_null(card, "la missione principale è nell'elenco")
	assert_true(card.has_meta("next_step"), "ed è evidenziata come prossimo passo")


func test_missioni_da_scoprire_in_scheda_propria() -> void:
	var q := Game.system("quests") as QuestSystem
	assert_gt(QuestGuide.discoveries(q).size(), 0)
	var s := _open(QUESTS)
	await wait_process_frames(2)
	s.refresh()
	var tab := s.find_child("TabDiscover", true, false) as Button
	assert_not_null(tab, "la scheda c'è perché ci sono novità")
	var disc := s.find_children("Discover_*", "PanelContainer", true, false)
	assert_gt(disc.size(), 0)
	for d in disc:
		assert_false((d as Control).is_visible_in_tree(), "nella scheda Missioni le carte di scoperta non si vedono")
	assert_true((s.find_child("Card_" + q.current_main(), true, false) as Control).is_visible_in_tree())
	tab.pressed.emit()
	for d in disc:
		assert_true((d as Control).is_visible_in_tree(), "nella scheda Da scoprire sì")
	assert_false((s.find_child("Card_" + q.current_main(), true, false) as Control).is_visible_in_tree(), "e le missioni stanno nell'altra scheda")


func test_missioni_apre_da_scoprire_dal_riepilogo() -> void:
	var s := _open(QUESTS, {"tab": "discover"})
	await wait_process_frames(2)
	s.refresh()
	var disc := s.find_children("Discover_*", "PanelContainer", true, false)
	assert_gt(disc.size(), 0)
	assert_true((disc[0] as Control).is_visible_in_tree(), "la scheda aperta è «Da scoprire»")


func test_missioni_senza_novita_niente_scheda() -> void:
	var q := Game.system("quests") as QuestSystem
	for d in QuestGuide.discoveries(q):
		(q.state.seen_screens as Array).append(str(d.screen))
	assert_eq(QuestGuide.discoveries(q).size(), 0)
	var s := _open(QUESTS)
	await wait_process_frames(2)
	s.refresh()
	assert_null(s.find_child("TabDiscover", true, false))


# ------------------------------------------------------------------ Compendio ed Eventi

func test_compendio_frase_introduttiva_solo_alla_prima_visita() -> void:
	var c1 := _open(COMPENDIUM)
	await wait_process_frames(2)
	assert_true((c1.find_child("IntroText", true, false) as Control).visible)
	c1.queue_free()
	await wait_process_frames(2)
	var c2 := _open(COMPENDIUM)
	await wait_process_frames(2)
	assert_false((c2.find_child("IntroText", true, false) as Control).visible)
	assert_eq(_count_containing(c2, tr("UI_GUILD2_ACH_HELP")), 0, "la spiegazione delle Imprese sta in una sezione chiusa")
	var fold := c2.find_child("Fold_compendium_ach", true, false) as Button
	assert_not_null(fold)
	fold.pressed.emit()
	assert_eq(_count_containing(c2, tr("UI_GUILD2_ACH_HELP")), 1, "aperta, la spiegazione c'è")
	assert_true(IntroOnce.fold_is_open("compendium_ach", false), "e la scelta è ricordata")


func test_eventi_prosa_in_sezione_richiudibile() -> void:
	var e1 := _open(EVENTS)
	await wait_process_frames(2)
	e1.refresh()
	assert_true((e1.find_child("IntroText", true, false) as Control).visible, "prima visita")
	var fold := e1.find_child("Fold_events_how", true, false) as Button
	assert_not_null(fold, "la sezione richiudibile «come funziona» e' presente nella scheda Eventi")
	if fold == null:
		return
	assert_false((e1.find_child("Body_events_how", true, false) as Control).visible)
	assert_eq(_count_containing(e1, tr("UI_EVENTS_SHOP_NOTE")), 0)
	fold.pressed.emit()
	assert_eq(_count_containing(e1, tr("UI_EVENTS_SHOP_NOTE")), 1)
	e1.queue_free()
	await wait_process_frames(2)
	var e2 := _open(EVENTS)
	await wait_process_frames(2)
	e2.refresh()
	assert_false((e2.find_child("IntroText", true, false) as Control).visible, "seconda visita: niente frase")
	assert_true((e2.find_child("Body_events_how", true, false) as Control).visible, "la sezione aperta resta aperta")
	assert_eq(_count_containing(e2, tr("UI_EVENTS_ODDS")), 1, "le probabilità della Cassa restano sempre visibili (docs/24)")
