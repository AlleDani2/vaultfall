extends GutTest
## Missioni chiare (feedback dei giocatori): voce «Missioni» in alto nel menù, «Obiettivo attuale», istruzioni «Come fare» con
## «Vai», passi di scoperta e copertura di tutti i sistemi. Controlla l'intera catena principale: ogni missione ha testo
## di istruzione non vuoto in IT ed EN e un «Vai» che porta a una schermata esistente.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const NO_GUIDE_NEEDED: PackedStringArray = ["summary", "quests", "settings", "news", "guide"]

var _old_dir: String
var _old_locale: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_locale = Loc.locale()
	SaveService.save_dir = "user://test_quest_guide_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("reduce_motion", true)
	QuestGuide.reset_cache()


func after_each() -> void:
	Loc.set_locale(_old_locale)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _q() -> QuestSystem:
	return Game.system("quests") as QuestSystem


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


## Sblocca ogni token concesso da una missione: serve a verificare i bersagli «Vai» anche per le schermate lontane.
func _unlock_everything() -> void:
	var un: Array = GameState.data.unlocks
	for q in DataRegistry.table("quests"):
		for t in q.get("unlocks", []):
			if not un.has(t):
				un.append(t)
	for t in ["feature:secrets", "feature:prestige", "feature:coop", "feature:run"]:
		if not un.has(t):
			un.append(t)
	ReqLink.reset_cache()


# ------------------------------------------------------------------ catena principale

func test_ogni_missione_principale_ha_istruzione_e_vai_validi() -> void:
	Game.new_game(1, "normal", 5)
	_unlock_everything()
	var n := 0
	for lang in ["it", "en"]:
		Loc.set_locale(lang)
		for q in DataRegistry.table("quests"):
			if str(q.get("kind", "")) != "main":
				continue
			var qid := str(q.id)
			assert_ne(Loc.t(q.title).strip_edges(), "", qid + ": titolo " + lang)
			assert_ne(Loc.t(q.desc).strip_edges(), "", qid + ": descrizione " + lang)
			assert_gt((q.objectives as Array).size(), 0, qid + ": almeno un obiettivo")
			for obj in q.objectives:
				var h: Dictionary = QuestGuide.howto(obj)
				var txt := str(h.text).strip_edges()
				assert_ne(txt, "", "%s %s: istruzione vuota" % [qid, obj.type])
				assert_false(txt.contains("UI_QG_") or txt.contains("{"), "%s %s [%s]: chiave o segnaposto a schermo: %s" % [qid, obj.type, lang, txt])
				var tgt: Dictionary = h.target
				assert_false(tgt.is_empty(), "%s %s: manca il bersaglio «Vai»" % [qid, obj.type])
				if not tgt.is_empty():
					var e := ScreenRegistry.get_entry(str(tgt.screen))
					assert_false(e.is_empty(), "%s %s: schermata inesistente %s" % [qid, obj.type, tgt.screen])
					assert_false(QuestGuide.go_label(tgt).is_empty())
				for ex in h.extra:
					assert_ne(str(ex.text).strip_edges(), "")
					assert_false(str(ex.text).contains("UI_QG_"))
				n += 1
			if not (q.get("unlocks", []) as Array).is_empty() and lang == "it":
				var w := QuestGuide.why(q)
				assert_true(w.is_empty() or w.begins_with("Sblocca"), qid + ": motivo")
				assert_false(w.contains("_"), qid + ": nome grezzo di un token nel motivo: " + w)
	assert_gt(n, 150, "tutta la catena principale verificata in due lingue")


func test_tutte_le_missioni_hanno_istruzione() -> void:
	Game.new_game(1, "normal", 5)
	_unlock_everything()
	for lang in ["it", "en"]:
		Loc.set_locale(lang)
		for q in DataRegistry.table("quests"):
			for obj in q.objectives:
				var h: Dictionary = QuestGuide.howto(obj)
				assert_ne(str(h.text).strip_edges(), "", "%s %s" % [q.id, obj.type])
				assert_false(str(h.text).contains("UI_QG_"), "%s %s [%s]: %s" % [q.id, obj.type, lang, h.text])


func test_traduzioni_delle_chiavi_it_en() -> void:
	var missing: PackedStringArray = []
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	var keys := {}
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0].begins_with("UI_QG_"):
			keys[row[0]] = row
	for k in keys:
		if str(keys[k][1]).strip_edges().is_empty() or str(keys[k][2]).strip_edges().is_empty():
			missing.append(k)
	assert_gt(keys.size(), 50)
	assert_eq(missing.size(), 0, "chiavi senza IT/EN: " + ", ".join(missing))


func test_dove_ottenere_un_oggetto_dai_dati() -> void:
	Game.new_game(1, "normal", 5)
	_unlock_everything()
	Loc.set_locale("it")
	var w: Dictionary = QuestGuide.where_item("key_t3")                 # chiave: si forgia
	assert_true(str(w.text).contains(QuestGuide.skill_name("keysmithing")), "Forgiachiavi: " + str(w.text))
	assert_false(w.target.is_empty())
	var d: Dictionary = QuestGuide.where_item("mm_witch_eye")           # materiale di mostro: cade da un mostro, in una zona
	assert_true(str(d.text).begins_with("lo lascia"), "cade da un mostro: " + str(d.text))
	assert_eq(str(d.target.screen), "combat")
	assert_ne(str(d.target.params.zone), "")
	var m := DataRegistry.get_def("monsters", "mud_slime")
	assert_eq(DataRegistry.get_def("monsters", "mud_slime").zone, "millbrook")
	assert_false(m.is_empty())


# ------------------------------------------------------------------ obiettivo attuale e Vai

func test_obiettivo_attuale_all_inizio() -> void:
	Game.new_game(1, "normal", 5)
	Loc.set_locale("it")
	var g: Dictionary = QuestGuide.current_goal(_q())
	assert_eq(g.kind, "quest")
	assert_eq(g.qid, "main_c0_q1")
	assert_eq(str(g.target.screen), "skill:woodcutting")
	assert_eq(str(g.target.params.produces), "log_pine")
	assert_true(str(g.how).contains("Avvia"), str(g.how))
	assert_true(str(g.how).contains(Loc.t(DataRegistry.action("wc_pine").name)), str(g.how))
	assert_eq(int(g.tg), 25)
	Loc.set_locale("en")
	g = QuestGuide.current_goal(_q())
	assert_true(str(g.how).contains("Start"), str(g.how))


func test_vai_apre_la_schermata_giusta() -> void:
	Game.new_game(1, "normal", 5)
	_q().mark_intro_seen()
	var main := await _main()
	var panel: GoalPanel = main.find_child("GoalPanel", true, false)
	assert_not_null(panel, "riquadro «Obiettivo attuale» nella colonna destra")
	panel.refresh(true)
	assert_true(panel.visible)
	var go: Button = panel.find_child("GoButton", true, false)
	assert_true(go.visible and not go.text.is_empty())
	go.pressed.emit()
	await wait_process_frames(3)
	assert_eq(main.current_id, "skill:woodcutting")


func test_missione_pronta_si_riscatta_dal_riquadro() -> void:
	Game.new_game(1, "normal", 5)
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 25}])
	Game.sim.tick(0.1)
	var g: Dictionary = QuestGuide.current_goal(_q())
	assert_eq(g.kind, "claim")
	assert_eq(str(g.target.screen), "quests")


# ------------------------------------------------------------------ menù e scorciatoia

func test_voce_missioni_subito_dopo_il_riepilogo() -> void:
	var ids: Array = []
	for e in ScreenRegistry.entries():
		ids.append(e.id)
	assert_eq(ids[0], "summary")
	assert_eq(ids[1], "quests", "Missioni è la seconda voce del menù")
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_M
	assert_eq(ShortcutMap.resolve(ev, ["summary", "quests"]), {"type": "screen", "id": "quests"})
	assert_eq(ShortcutMap.key_label_for("quests", ["summary", "quests"]), "M")


func test_badge_conta_riscatti_e_novita() -> void:
	Game.new_game(1, "normal", 5)
	var base: int = SidebarBadges.counts().get("quests", 0)
	assert_eq(base, QuestGuide.discoveries(_q()).size(), "all'inizio: solo i passi da scoprire")
	assert_gt(base, 0)
	_q().note_screen("manual")
	_q().note_screen("compendium")
	_q().note_screen("bank")
	assert_false(SidebarBadges.counts().has("quests"), "vista ogni novità: nessun pallino")
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 25}])
	Game.sim.tick(0.1)
	assert_eq(SidebarBadges.counts().get("quests", 0), 1)


# ------------------------------------------------------------------ schermata Missioni

func test_schermata_ha_le_sezioni_e_il_come_fare() -> void:
	Game.new_game(1, "normal", 5)
	_q().mark_intro_seen()
	var main := await _main()
	assert_true(main.show_screen("quests"))
	await wait_process_frames(2)
	var s: Control = main.current_screen()
	var card: Control = s.find_child("Card_main_c0_q1", true, false)
	assert_not_null(card)
	assert_not_null(card.find_child("HowTo", true, false), "blocco «Come fare»")
	var go: Button = card.find_child("GoButton", true, false)
	assert_not_null(go, "«Vai» nella scheda")
	assert_not_null(s.find_child("Discover_guide_manual", true, false), "passo di scoperta")
	watch_signals(EventBus)
	go.pressed.emit()
	assert_signal_emitted(EventBus, "screen_requested")
	assert_signal_emitted_with_parameters(EventBus, "screen_requested", ["skill:woodcutting", {"skill": "woodcutting", "produces": "log_pine"}])


func test_riscatta_tutto() -> void:
	Game.new_game(1, "normal", 5)
	_q().mark_intro_seen()
	_q().accept("path_woodcutting_1")
	var main := await _main()
	for qid in [_q().current_main(), "path_woodcutting_1"]:                 # due missioni pronte insieme
		var objs: Array = _q().quest_def(qid).objectives
		for i in objs.size():
			_q().state.progress[qid][i] = QuestSystem.target_of(objs[i])
	assert_eq(_q().ready_count(), 2)
	main.show_screen("quests")
	await wait_process_frames(2)
	var all: Button = main.current_screen().find_child("ClaimAllButton", true, false)
	assert_not_null(all, "«Riscatta tutto» con più missioni pronte")
	all.pressed.emit()
	await wait_process_frames(2)
	assert_eq(_q().ready_count(), 0)
	assert_true(_q().is_done("main_c0_q1"))


# ------------------------------------------------------------------ copertura dei sistemi

func test_ogni_sistema_ha_una_missione_o_una_guida() -> void:
	var granted := {}
	for q in DataRegistry.table("quests"):
		if str(q.get("kind", "")) == "main":
			for t in q.get("unlocks", []):
				granted[str(t)] = true
	var guide_tokens := {}
	var guide_screens := {}
	for g in DataRegistry.table("guides"):
		guide_screens[str(g.screen)] = true
		for t in g.get("requires", []):
			guide_tokens[str(t)] = true
	var uncovered: PackedStringArray = []
	for e in ScreenRegistry.entries():
		var id := str(e.id)
		var tok := str(e.get("unlock", ""))
		var covered := false
		if tok.is_empty():
			covered = NO_GUIDE_NEEDED.has(id) or guide_screens.has(id)
		else:
			covered = granted.has(tok) or guide_tokens.has(tok) or guide_screens.has(id)
		if not covered:
			uncovered.append(id)
	assert_eq(uncovered.size(), 0, "schermate senza missione né guida: " + ", ".join(uncovered))


func test_le_guide_hanno_testi_e_bersaglio() -> void:
	Game.new_game(1, "normal", 5)
	_unlock_everything()
	assert_gt(DataRegistry.table("guides").size(), 4)
	for lang in ["it", "en"]:
		Loc.set_locale(lang)
		for g in DataRegistry.table("guides"):
			assert_ne(Loc.t(g.title), "", str(g.id))
			assert_ne(Loc.t(g.text), "", str(g.id))
			assert_ne(Loc.t(g.why), "", str(g.id))
			assert_false(ScreenRegistry.get_entry(str(g.screen)).is_empty(), str(g.id) + ": schermata")
			assert_false(ScreenRegistry.get_entry(str(g.goto.screen)).is_empty(), str(g.id) + ": bersaglio")
	assert_eq(QuestGuide.discoveries(_q()).size(), DataRegistry.table("guides").size(), "con tutto sbloccato e nulla visto, tutte")


func test_guida_sparisce_dopo_la_visita() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	var before := QuestGuide.discoveries(_q()).size()
	main.show_screen("manual")
	assert_eq(QuestGuide.discoveries(_q()).size(), before - 1)
	assert_true(_q().has_seen_screen("manual"))


func test_prossime_con_motivo_e_requisito() -> void:
	Game.new_game(1, "normal", 5)
	Loc.set_locale("it")
	var up: Array = QuestGuide.upcoming(_q(), 3)
	assert_eq(up.size(), 3)
	assert_eq(str(up[0].id), "main_c0_q2")
	var lock: Dictionary = QuestGuide.lock_reason(up[0], _q())
	assert_true(str(lock.text).begins_with("Si apre dopo"))
	assert_false(QuestGuide.why(up[0]).is_empty(), "il motivo (cosa sblocca) si legge anche prima di poterla fare")
