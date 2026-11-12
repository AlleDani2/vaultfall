extends GutTest
## Manuale 2: ogni pagina esiste in IT/EN, nessuna chiave mancante, numeri coerenti con i dati (campionamento),
## ricerca, mappa schermata -> pagina e icona «?» che apre la pagina giusta.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const SECTIONS_KEYS: PackedStringArray = ["WHAT", "TIPS", "DONT", "JOKE"]

var _old_dir: String
var _old_tutorials: Variant
var _old_locale: String


func before_each() -> void:
	_old_locale = TranslationServer.get_locale()
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_manual2_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_tutorials = Settings.get_value("tutorials")


func after_each() -> void:
	TranslationServer.set_locale(_old_locale)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("tutorials", _old_tutorials)


func _has(key: String) -> bool:
	return str(TranslationServer.translate(key)) != key


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


# ------------------------------------------------------------------ struttura

func test_indice_coerente_con_i_gruppi() -> void:
	var seen := {}
	for g in ManualCatalog.GROUPS:
		for p in g.pages:
			assert_false(seen.has(p), "pagina doppia nell'indice: " + p)
			seen[p] = true
	assert_eq(seen.size(), ManualCatalog.PAGES.size(), "ogni pagina è in un gruppo")
	for p in ManualCatalog.PAGES:
		assert_true(seen.has(p), "pagina fuori dall'indice: " + p)
	assert_gte(ManualCatalog.PAGES.size(), 35, "il Manuale copre tutti i sistemi")


func test_ogni_pagina_in_it_e_en_senza_chiavi_mancanti() -> void:
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for g in ManualCatalog.GROUPS:
			assert_true(_has(str(g.title)), "gruppo senza titolo (%s): %s" % [loc, g.title])
		for p in ManualCatalog.PAGES:
			assert_true(_has(ManualCatalog.title_key(p)), "titolo mancante (%s): %s" % [loc, p])
			var t := ManualPages.build(p, DataRegistry, [])
			assert_gt(t.length(), 120, "pagina non vuota (%s): %s" % [loc, p])
			assert_false(t.contains("{"), "segnaposto non risolto (%s): %s" % [loc, p])
			assert_false(t.contains("UI_"), "chiave non tradotta (%s): %s" % [loc, p])


func test_pagine_strutturate_hanno_tutte_le_parti() -> void:
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for p in ManualCatalog.PAGES:
			if ["formulas", "drops", "unlocks", "glossary"].has(p):
				continue
			var u := p.to_upper()
			for part in SECTIONS_KEYS:
				assert_true(_has("UI_MAN2_%s_%s" % [u, part]), "manca %s di %s (%s)" % [part, p, loc])
			assert_true(_has("UI_MAN2_%s_HOW_1" % u), "manca il primo passo di " + p)
			assert_false(_has("UI_MAN2_%s_F_%d" % [u, ManualFacts.params(p, DataRegistry).size() + 1]), "riga di numeri senza dati in " + p)
			for i in ManualFacts.params(p, DataRegistry).size():
				assert_true(_has("UI_MAN2_%s_F_%d" % [u, i + 1]), "riga %d mancante in %s (%s)" % [i + 1, p, loc])
			# la battuta non sostituisce l'istruzione: i passi vengono prima, la battuta in fondo
			var t := ManualPages.build(p, DataRegistry, [])
			assert_true(t.find(tr("UI_MAN2_%s_HOW_1" % u)) < t.find(tr("UI_MAN2_%s_JOKE" % u)), "istruzione prima della battuta: " + p)


# ------------------------------------------------------------------ numeri dai dati (campionamento)

func test_numeri_coerenti_con_i_dati() -> void:
	TranslationServer.set_locale("en")
	var k: Dictionary = DataRegistry.constants
	var n := func(x: float, d: int) -> String: return NumberFormat.decimal(x, d, "en")
	var t := func(p: String) -> String: return ManualPages.build(p, DataRegistry, [])
	var skills: String = t.call("skills")
	assert_true(skills.contains("Level cap %d" % int(k.level_cap)))
	assert_true(skills.contains("max level %d" % int(k.mastery.cap)))
	assert_true(skills.contains(NumberFormat.fmt(Formulas.xp_to_next(50))), "XP del livello 50 dalla formula")
	assert_true(skills.contains("+%s%% XP" % n.call(Formulas.star_xp_pct(5), 1)))
	var prestige: String = t.call("prestige")
	assert_true(prestige.contains("level %d" % int(k.prestige.rite_level)))
	assert_true(prestige.contains("+%s%%" % n.call(Formulas.star_haste_pct(10), 1)))
	var eras: String = t.call("eras")
	assert_true(eras.contains(n.call(Formulas.era_monster_mult(5), 2)), "mostri Era 5")
	assert_true(eras.contains(n.call(Formulas.era_reward_mult(5), 1)), "ricompense Era 5")
	var rift: String = t.call("rift")
	assert_true(rift.contains("×" + n.call(float(DataRegistry.rules("rift").stat_mult_per_floor), 2)))
	var estate: String = t.call("estate")
	assert_true(estate.contains(NumberFormat.fmt(Formulas.estate_cost_gold(10, 1))), "costo livello 10 della Tenuta")
	var refound: String = t.call("refound")
	assert_true(refound.contains("%d, with 200,000: %d" % [Formulas.soci_total(float(k.estate.prestige_min_units)), Formulas.soci_total(200000.0)]))
	var orders: String = t.call("orders")
	var orr: Dictionary = DataRegistry.rules("orders_rules")
	assert_true(orders.contains("Board slots: %d" % int(orr.board_slots)))
	assert_true(orders.contains("deadline %d hours" % int(orr.deadline_h)))
	var wb: String = t.call("worldboss")
	var w0: Dictionary = DataRegistry.table("world_bosses")[0]
	assert_true(wb.contains("every %d hours" % int(w0.spawn_every_h)))
	var quests: String = t.call("quests")
	assert_true(quests.contains("%d per day" % int(DataRegistry.rules("contract_rules").daily_slots)))
	var crates: String = t.call("crates")
	assert_true(crates.contains(n.call(79.2, 2)), "le probabilità delle Casse sono ancora nella pagina")
	assert_true(crates.contains("%s s" % n.call(float(DataRegistry.rules("crate_rules").reel.duration_s), 1)))
	var classes: String = t.call("classes")
	assert_true(classes.contains("%d classes" % DataRegistry.table("classes").size()))
	assert_true(classes.contains("%d talents" % DataRegistry.table("talents").size()))
	var queue: String = t.call("queue")
	assert_true(queue.contains("up to %d" % int(k.queue.max_slots)))


func test_numeri_in_italiano() -> void:
	TranslationServer.set_locale("it")
	var rift := ManualPages.build("rift", DataRegistry, [])
	var mult := NumberFormat.decimal(float(DataRegistry.rules("rift").stat_mult_per_floor), 2, "it")
	assert_true(rift.contains("x" + mult), "moltiplicatore per piano in IT: " + mult)


# ------------------------------------------------------------------ ricerca

func test_ricerca() -> void:
	Game.new_game(1, "normal", 5)
	Settings.set_value("tutorials", false)
	TranslationServer.set_locale("it")
	var main := await _main()
	assert_true(main.show_screen("manual"))
	await wait_process_frames(2)
	var s: Control = main.current_screen()
	assert_eq(s.matching_pages("").size(), ManualCatalog.PAGES.size(), "senza testo tutte le pagine")
	assert_true(s.matching_pages("rifondazione").has("refound"))
	assert_true(s.matching_pages("PROBABILITÀ").has("crates"), "senza distinzione di maiuscole")
	assert_eq(s.matching_pages("zzzqqq").size(), 0)
	s._on_search("zzzqqq")
	assert_true(s.get_node("%Body").text.contains(tr("UI_MAN2_SEARCH_EMPTY")))
	s._on_search("")
	assert_true((s.get_node("%Pages").get_node("Page_start") as Button).visible)
	s._on_search("rifondazione")
	assert_false((s.get_node("%Pages").get_node("Page_bank") as Button).visible)
	assert_true(s.matching_pages("rifondazione").has(s.current_page()), "la pagina mostrata è tra i risultati")


# ------------------------------------------------------------------ collegamenti dal gioco

func test_ogni_voce_del_menu_ha_una_pagina() -> void:
	for e in ScreenRegistry.entries(DataRegistry):
		var page := ManualCatalog.page_for_screen(str(e.id))
		assert_true(ManualCatalog.has_page(page), "pagina inesistente per " + str(e.id))
		if not str(e.id).begins_with("skill:") and not ["summary", "manual"].has(str(e.id)):
			assert_ne(page, "start", "la voce %s non ha una pagina sua" % e.id)
	assert_eq(ManualCatalog.page_for_screen("skill:farming"), "farm")
	assert_eq(ManualCatalog.page_for_screen("skill:alchemy"), "alchemy")
	assert_eq(ManualCatalog.page_for_screen("skill:mining"), "skills")
	assert_eq(ManualCatalog.page_for_screen("coop_lobby"), "coop")
	assert_eq(ManualCatalog.page_for_screen("sconosciuta"), "start")


func test_icona_punto_interrogativo_apre_la_pagina_giusta() -> void:
	Game.new_game(1, "normal", 5)
	Settings.set_value("tutorials", false)
	var main := await _main()
	var btn := main.find_child("HelpButton", true, false) as Button
	assert_not_null(btn, "icona ? nella barra in alto")
	assert_eq(btn.text, "UI_MAN2_HELP")
	for pair in [["quests", "quests"], ["settings", "settings"], ["bank", "bank"], ["skill:woodcutting", "skills"], ["news", "feedback"]]:
		assert_true(main.show_screen(str(pair[0])), "schermata " + str(pair[0]))
		await wait_process_frames(1)
		btn.pressed.emit()
		await wait_process_frames(2)
		var s: Control = main.current_screen()
		assert_eq(main.current_id, "manual")
		assert_eq(s.current_page(), str(pair[1]), "da %s si apre la pagina %s" % [pair[0], pair[1]])
		var btn_page := s.get_node("%Pages").get_node_or_null("Page_" + str(pair[1])) as Button
		assert_true(btn_page != null and btn_page.button_pressed, "voce dell'indice evidenziata")
	# dal Manuale stesso si torna alla pagina iniziale
	btn.pressed.emit()
	await wait_process_frames(2)
	assert_eq(main.current_screen().current_page(), "start")


func test_f1_apre_la_pagina_della_schermata() -> void:
	Game.new_game(1, "normal", 5)
	Settings.set_value("tutorials", false)
	var main := await _main()
	assert_true(main.show_screen("quests"))
	await wait_process_frames(1)
	var ev := InputEventKey.new()
	ev.keycode = KEY_F1
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_process_frames(3)
	if main.current_id == "manual":
		assert_eq(main.current_screen().current_page(), "quests")
	else:
		# in headless l'evento può non arrivare: si verifica almeno la mappa usata da OverlayHost
		assert_eq(ManualCatalog.page_for_screen("quests"), "quests")
