extends GutTest
## Playtest del combattente (audit 118): regressioni trovate giocando dall'inizio alla fine con la UI vera.

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_locale: String
var _old_ts_locale: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_pt118_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor
	_old_locale = str(Settings.get_value("locale"))
	_old_ts_locale = TranslationServer.get_locale()


func after_each() -> void:
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	get_tree().root.content_scale_factor = _old_scale
	Settings.set_value("locale", _old_locale)
	TranslationServer.set_locale(_old_ts_locale)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _main_with(tokens: Array) -> Control:
	Game.new_game(1, "normal", 1181)
	var un: Object = Game.system("unlock")
	for t in tokens:
		un.grant(str(t))
	Settings.set_value("tutorials", false)
	Settings.set_value("locale", "it")          # i testi italiani sono i più larghi: il caso peggiore dei layout
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	return main


## Mette un cibo vero nel primo slot Cibo (con uno slot pieno la colonna destra è più larga: è il caso reale).
func _equip_some_food() -> void:
	var data: Object = Game.get("sim").ctx.data
	for it in DataRegistry.all_items().values():
		if not (it.get("food", {}) as Dictionary).is_empty():
			Game.system("bank").add(str(it.id), 5, "test")
			assert_true(Game.system("combat").set_food(0, str(it.id)))
			return
	fail_test("nessun cibo nei dati")


## PT118-1: a 1280x720 lo scontro (eroe e nemico) sta in alto, nel quadro, e i bersagli sotto (prima la colonna destra era 3 px
## troppo larga e finiva sotto la piega: il giocatore premeva «Combatti» e in alto a destra c'era il vuoto).
func test_combattimento_scontro_accanto_alla_lista_a_720p() -> void:
	var sz := Vector2i(1280, 720)
	DisplayServer.window_set_size(sz)
	get_tree().root.size = sz
	get_tree().root.content_scale_factor = 1.0
	var main: Control = await _main_with(["feature:combat", "skill:hero"])
	_equip_some_food()
	assert_true(main.show_screen("combat"))
	await wait_process_frames(10)                          # il layout dell'arena si assesta in più passate: a 4 frame a volte è ancora a metà
	var cs: Control = main.call("current_screen")
	var portrait := cs.get("_portrait") as Control
	var list := cs.get("_monster_list") as Control          # revisione grafica 1.0: i bersagli sono carte sotto il quadro
	var hero := cs.get("_hero_sprite") as Control
	assert_not_null(portrait)
	assert_lt(portrait.global_position.y, 450.0, "il ritratto del nemico è in alto, non sotto l'elenco")
	assert_gt(portrait.global_position.x, hero.global_position.x, "il nemico è a destra dell'eroe")
	assert_gt(list.global_position.y, portrait.global_position.y + portrait.size.y - 1.0, "i bersagli stanno sotto il quadro")


## PT118-2: «Hai 1 punti», «1 pezzi»: il numero 1 davanti a un plurale diventa singolare, in IT e in EN.
func test_plurale_dopo_uno() -> void:
	assert_eq(Loc.fix_plural("Hai 1 pezzi e 11 pezzi, 0,1 ore, 1 ore e 21 volte", "it"), "Hai 1 pezzo e 11 pezzi, 0,1 ore, 1 ora e 21 volte")
	assert_eq(Loc.fix_plural("1 livelli e 2 livelli. 1 Stelle", "it"), "1 livello e 2 livelli. 1 Stella")
	assert_eq(Loc.fix_plural("1 levels, 12 levels, 1 kills", "en"), "1 level, 12 levels, 1 kill")
	assert_eq(Loc.fix_plural("1 oreficeria", "it"), "1 oreficeria", "una parola più lunga non si tocca")
	TranslationServer.set_locale("it")
	var txt := Loc.tf("UI_QUESTS_DONE_COUNT", {"n": 1})
	assert_false(txt.contains("1 missioni"), txt)


## PT118-3: un talento che dà +0,05 per rango non si legge «+0» (Colazione Abbondante).
func test_valore_talento_sotto_uno() -> void:
	TranslationServer.set_locale("it")
	assert_eq(NumberFormat.fmt_signed(0.05), "+0,05")
	assert_eq(NumberFormat.fmt_signed(5.0), "+5")
	assert_eq(NumberFormat.fmt_signed(-2.5), "−2,5")
	TranslationServer.set_locale("en")
	assert_eq(NumberFormat.fmt_signed(0.05), "+0.05")


## PT118-4: «Parla» / «Consegna» spariscono quando l'obiettivo è già completo (prima restavano cliccabili a 1 / 1).
func test_pulsante_parla_sparisce_a_obiettivo_completo() -> void:
	var main: Control = await _main_with(["feature:combat"])
	var q: QuestSystem = Game.system("quests") as QuestSystem
	q.state.active.clear()
	q.state.progress.clear()
	for qid in q._main_ids:
		if qid.begins_with("main_c11"):
			break
		if not q.is_done(qid):
			q.state.done.append(qid)
	q.start()
	for i in 3:
		Game._on_step(0.1)
	assert_eq(q.current_main(), "main_c11_q1")
	assert_true(main.show_screen("quests"))
	await wait_process_frames(4)
	var btn := main.find_child("TalkButton", true, false) as Button
	assert_not_null(btn, "prima di parlare il pulsante c'è")
	assert_true(btn.visible)
	assert_true(q.talk("ilde"))
	await wait_process_frames(4)
	main.call("current_screen").call("refresh")
	await wait_process_frames(2)
	btn = main.find_child("TalkButton", true, false) as Button
	assert_true(btn == null or not btn.is_visible_in_tree(), "a obiettivo completo il pulsante non si vede")


## PT118-5: a fine storia il testo dice cosa fare dopo (prima: «Lo scrittore è in pausa» e basta, vicolo cieco apparente).
func test_fine_storia_indica_il_prestigio() -> void:
	TranslationServer.set_locale("it")
	assert_true(tr("UI_QUESTS_STORY_END").contains("Prestigio"), tr("UI_QUESTS_STORY_END"))
	TranslationServer.set_locale("en")
	assert_true(tr("UI_QUESTS_STORY_END").contains("Prestige"), tr("UI_QUESTS_STORY_END"))


## PT118-6: dopo la prima missione completata il Riepilogo non è più «partita nuova» (il consiglio «apri Taglialegna» restava fino a 15 minuti).
func test_riepilogo_non_e_nuova_partita_dopo_la_prima_missione() -> void:
	Game.new_game(1, "normal", 1186)
	var summary: Script = load("res://src/ui/screens/SummaryScreen.gd")
	assert_true(summary.is_new_game(), "all'inizio sì")
	(Game.system("quests") as QuestSystem).state.done.append("main_c0_q1")
	assert_false(summary.is_new_game(), "con una missione fatta no, anche a 7 minuti di gioco")


## PT118-7: genere neutro (CLAUDE.md): nessuna frase italiana rivolta a chi gioca usa participi o aggettivi al maschile.
func test_testi_italiani_senza_genere_esplicito() -> void:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	assert_not_null(f)
	var re := RegEx.new()
	re.compile("(?i)\\b(sei stat[oa]|non sei (pronto|pronta|socio|socia|soddisfatto|soddisfatta|collegato|collegata)|sei (entrato|entrata|collegato|collegata|rimasto|rimasta)|ti sei (stancato|stancata))\\b")
	var bad := PackedStringArray()
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and re.search(row[2]) != null:
			bad.append("%s: %s" % [row[0], row[2].substr(0, 80)])
	assert_eq(bad.size(), 0, "frasi al maschile/femminile: " + "; ".join(bad))


## PT118-8: il Mercato non mostra «0 oro» per un pesce che vale 0,28 oro l'uno (130 pezzi = 36 oro): prezzi sotto 10 con decimali.
func test_prezzo_unitario_sotto_uno() -> void:
	TranslationServer.set_locale("it")
	assert_eq(NumberFormat.fmt_unit(0.28), "0,28")
	assert_eq(NumberFormat.fmt_unit(4.0), "4")
	assert_eq(NumberFormat.fmt_unit(4.3), "4,3")
	assert_eq(NumberFormat.fmt_unit(25.4), NumberFormat.fmt(25.4))


## PT118-9: l'avviso giallo delle incursioni non mescola due cause in una parentesi («... 84% (o cibo insufficiente)»).
func test_avviso_giallo_incursione_chiaro() -> void:
	TranslationServer.set_locale("it")
	var txt := Loc.tf("UI_RAID_RISK_YELLOW", {"win": "84%"})
	assert_false(txt.contains("(o cibo"), txt)
	assert_true(txt.contains("84%"))
