extends GutTest
## GUILD-2: schermate Compendio, Fazioni e Luoghi Segreti, Scarta del Deposito, riassunto del registro (LogDigest),
## salvataggio completo con partita vera, Bentornato, registri delle schermate e dei sistemi.

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_guild2_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String) -> Control:
	var scr: Control = (load(path) as PackedScene).instantiate()
	add_child_autofree(scr)
	await wait_process_frames(1)
	scr.open({})
	scr.refresh()
	return scr


func _texts(node: Node) -> String:
	var out := ""
	for c in node.get_children():
		if c is Label or c is Button:
			out += str(c.text) + "\n"
		out += _texts(c)
	return out


# ------------------------------------------------------------------ registri

func test_registri_righe_mie() -> void:
	for id in ["compendium", "factions", "secrets"]:
		var e := ScreenRegistry.get_entry(id)
		assert_false(e.is_empty(), id)
		assert_true(ResourceLoader.exists(e.scene), id + ": scena")
	assert_eq(ScreenRegistry.get_entry("factions").unlock, "feature:factions")
	assert_eq(ScreenRegistry.get_entry("secrets").unlock, "feature:secrets")
	assert_eq(ScreenRegistry.get_entry("compendium").unlock, "", "il Compendio è sempre aperto")
	var ids := PackedStringArray()
	for s in SystemRegistry.create_all():
		ids.append(s.id)
	assert_gt(ids.find("compendium"), ids.find("quests"), "il Compendio legge dopo le Missioni")
	assert_gt(ids.find("secrets"), ids.find("expeditions"))


# ------------------------------------------------------------------ Compendio

func test_compendio_tutte_le_schede() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var comp := Game.system("compendium") as CompendiumSystem
	comp.found_pet("pet_skill_mining")
	comp.grant_title("title_firmament")
	comp.grant_cosmetic("cosmetic_frame_mining_bronze")
	(GameState.data.skills as Dictionary)["mining"] = {"xp": 0.0, "level": 50}
	comp.evaluate()
	var scr: Control = await _open("res://src/ui/screens/CompendiumScreen.tscn")
	for tab in 4:
		scr._tabs.current_tab = tab
		scr.refresh()
		assert_gt(scr._bodies[tab].get_child_count(), 0, "scheda %d popolata" % tab)
	var t := _texts(scr._bodies[1])
	assert_true(t.contains("Firmamento") or t.contains("Firmament"), "titolo posseduto visibile")
	# indossare un titolo dalla UI
	scr._on_wear("title_firmament")
	assert_eq(comp.selected_title(), "title_firmament")
	scr._on_frame("cosmetic_frame_mining_bronze")
	assert_eq(comp.selected_frame(), "cosmetic_frame_mining_bronze")
	scr._on_companion("pet_skill_mining")
	assert_eq(comp.companion(), "pet_skill_mining")
	# filtro per categoria
	scr._tabs.current_tab = 0
	scr._filter_cat = "skills"
	scr._sigs[0] = ""
	scr.refresh()
	assert_gt(scr._bodies[0].get_child_count(), 3)
	scr.close()


func test_impresa_nascosta_resta_misteriosa() -> void:
	assert_true(Game.new_game(1, "normal", 6))
	var scr: Control = await _open("res://src/ui/screens/CompendiumScreen.tscn")
	var t := _texts(scr._bodies[0])
	assert_false(t.contains("Chef Distratto") or t.contains("Distracted Chef"), "impresa nascosta non spoilerata")
	assert_true(t.contains("segreta") or t.contains("Secret"))


# ------------------------------------------------------------------ Fazioni

func test_fazioni_accetta_e_riscuoti_da_schermata() -> void:
	assert_true(Game.new_game(1, "normal", 8))
	(GameState.data.unlocks as Array).append("feature:factions")
	(GameState.data.unlocks as Array).append("feature:market")
	Game.sim.tick(0.1)
	var qs := Game.system("quests") as QuestSystem
	var scr: Control = await _open("res://src/ui/screens/FactionsScreen.tscn")
	assert_gt(scr._col.get_child_count(), 4, "cinque fazioni")
	var t := _texts(scr._col)
	assert_true(t.contains("Lega dei Mercanti") or t.contains("Merchant League"))
	scr._on_accept("side_merchant_league_1")
	assert_true(qs.is_active("side_merchant_league_1"))
	EventBus.objective_event.emit("sell_market", {"gold": 10000})
	Game.sim.tick(0.1)
	scr.refresh()
	assert_true(qs.is_ready("side_merchant_league_1"))
	scr._on_claim("side_merchant_league_1")
	scr.refresh()
	assert_eq((Game.system("market") as MarketSystem).reputation("merchant_league"), 250)
	assert_true(qs.is_done("side_merchant_league_1"))


# ------------------------------------------------------------------ Luoghi Segreti

func test_luoghi_segreti_schermata() -> void:
	assert_true(Game.new_game(1, "normal", 9))
	var bank := Game.system("bank") as BankSystem
	bank.add("map_fragment", 10, "test")
	assert_true(GameState.has_unlock("feature:secrets"), "il menù si sblocca col primo frammento")
	(GameState.data.skills as Dictionary)["woodcutting"] = {"xp": 0.0, "level": 60}
	var scr: Control = await _open("res://src/ui/screens/SecretsScreen.tscn")
	assert_eq(scr._cards.size(), 5)
	scr._on_reveal("hidden_grove")
	scr.refresh()
	var sc := Game.system("secrets") as SecretSystem
	assert_true(sc.is_revealed("hidden_grove"))
	scr._on_explore("hidden_grove")
	scr.refresh()
	assert_eq(sc.active_spot(), "hidden_grove")
	assert_true(scr._cards["hidden_grove"].bar.visible, "barra dell'esplorazione")
	scr.close()


# ------------------------------------------------------------------ Deposito: Scarta con conferma

func test_bank_scarta_con_conferma() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var bank := Game.system("bank") as BankSystem
	bank.add("log_pine", 12, "test")
	var scr: Control = await _open("res://src/ui/screens/BankScreen.tscn")
	scr._selected = "log_pine"
	scr._mark_dirty()
	scr.refresh()
	scr._on_discard()
	var dlg: ConfirmationDialog = null
	for c in scr.get_children():
		if c is ConfirmationDialog:
			dlg = c
	assert_not_null(dlg, "finestra di conferma")
	assert_eq(bank.count("log_pine"), 12, "nulla viene scartato prima della conferma")
	dlg.confirmed.emit()
	assert_eq(bank.count("log_pine"), 0, "scartate tutte (la quantità predefinita è il massimo)")


func test_bank_scarta_rifiuta_bloccati() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var bank := Game.system("bank") as BankSystem
	bank.add("log_pine", 5, "test")
	bank.set_def_locked("log_pine", true)
	var scr: Control = await _open("res://src/ui/screens/BankScreen.tscn")
	scr._selected = "log_pine"
	scr.refresh()
	scr._on_discard()
	for c in scr.get_children():
		assert_false(c is ConfirmationDialog, "nessuna conferma per un oggetto bloccato")
	assert_eq(bank.count("log_pine"), 5)


# ------------------------------------------------------------------ riassunto del registro

func test_registro_undici_livelli_una_riga() -> void:
	var d := LogDigest.new()
	for lv in range(12, 23):
		d.add_level("Taglialegna", lv)
	var lines := d.flush()
	assert_eq(lines.size(), 1, "undici livelli = una riga")
	assert_true(str(lines[0].text).contains("22"), lines[0].text)
	assert_true(d.is_empty())
	assert_eq(d.flush().size(), 0)


func test_registro_un_livello_varia_la_battuta() -> void:
	var seen := {}
	for lv in range(2, 40):
		var d := LogDigest.new()
		d.add_level("Pesca", lv)
		var l := d.flush()
		assert_eq(l.size(), 1)
		seen[str(l[0].text).replace(str(lv), "#")] = true
	assert_gt(seen.size(), 2, "le battute del livello singolo cambiano")


func test_registro_piu_mansioni_si_compattano() -> void:
	var d := LogDigest.new()
	d.max_listed = 3
	for nm in ["A", "B", "C", "D", "E"]:
		d.add_level(nm, 5)
		d.add_level(nm, 6)
	var l := d.flush()
	assert_eq(l.size(), 1)
	assert_true(str(l[0].text).contains("5"), "numero di mansioni")
	var d2 := LogDigest.new()
	d2.add_level("A", 5)
	d2.add_level("B", 5)
	assert_eq(d2.flush().size(), 2, "due mansioni = due righe (una ciascuna)")


func test_registro_deposito_pieno_raggruppa() -> void:
	var d := LogDigest.new()
	for i in 14:
		assert_true(d.absorb("warning", "Deposito pieno: Cassa", {"reason": "bank_full", "item": "Cassa della Valle"}))
	for i in 2:
		assert_true(d.absorb("warning", "Deposito pieno: Spada", {"reason": "bank_full", "item": "Spada"}))
	var l := d.flush()
	assert_eq(l.size(), 1, "16 perdite = una riga")
	var txt := str(l[0].text)
	assert_true(txt.contains("16"), txt)
	assert_true(txt.contains("Cassa della Valle"), txt)
	assert_true(txt.contains("14"), txt)
	var d2 := LogDigest.new()
	d2.absorb("warning", "Deposito pieno: Mela", {"reason": "bank_full", "item": "Mela"})
	var one := d2.flush()
	assert_eq(one.size(), 1)
	assert_true(str(one[0].text).begins_with("Deposito pieno: Mela"), "un solo caso: testo originale + suggerimento")


func test_registro_altri_messaggi_non_assorbiti() -> void:
	var d := LogDigest.new()
	assert_false(d.absorb("info", "ciao", {}))
	assert_false(d.absorb("warning", "orto", {"reason": "other"}))
	assert_true(d.is_empty())


func test_registro_imprese_raggruppate() -> void:
	var d := LogDigest.new()
	d.absorb("success", "a1", {"digest": "ach", "ach": "ach_pets_1"})
	d.absorb("success", "a2", {"digest": "ach", "ach": "ach_crates_1"})
	d.absorb("success", "a3", {"digest": "ach", "ach": "ach_kills_100"})
	d.absorb("info", "p1", {"digest": "pet_dupe", "dust": 3})
	d.absorb("info", "p2", {"digest": "pet_dupe", "dust": 8})
	var l := d.flush()
	assert_eq(l.size(), 2)
	assert_true(str(l[0].text).contains("3"))
	assert_true(str(l[1].text).contains("11"), "polvere sommata: " + str(l[1].text))
	var d1 := LogDigest.new()
	d1.absorb("success", "unico", {"digest": "ach", "ach": "ach_pets_1"})
	assert_eq(d1.flush()[0].text, "unico", "un caso solo: testo originale")


func test_main_screen_riassume_i_livelli_di_un_rientro() -> void:
	assert_true(Game.new_game(1, "normal", 77))
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var before: int = main._log.row_count()
	for lv in range(2, 13):
		EventBus.level_up.emit("woodcutting", lv)
	assert_eq(main._log.row_count(), before, "nessuna riga finché la finestra è aperta")
	main._flush_digest()
	assert_eq(main._log.row_count(), before + 1, "undici livelli = UNA riga di registro")
	assert_true(main._log.last_text().contains("12"))
	# Deposito pieno: 20 casse perse = una riga sola
	before = main._log.row_count()
	for i in 20:
		EventBus.notice.emit("warning", "Deposito pieno", {"reason": "bank_full", "item": "Cassa della Valle", "def_id": "crate_millbrook"})
	assert_eq(main._log.row_count(), before)
	main._flush_digest()
	assert_eq(main._log.row_count(), before + 1)
	assert_true(main._log.last_text().contains("20"))
	# i messaggi normali passano subito
	EventBus.notice.emit("info", "messaggio normale", {})
	assert_eq(main._log.row_count(), before + 2)


func test_main_screen_timer_chiude_la_finestra() -> void:
	assert_true(Game.new_game(1, "normal", 78))
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var before: int = main._log.row_count()
	EventBus.level_up.emit("mining", 4)
	EventBus.level_up.emit("mining", 5)
	await wait_seconds(float(DataRegistry.rules("social_rules").log_digest.window_s) + 0.5)
	assert_eq(main._log.row_count(), before + 1)


# ------------------------------------------------------------------ salvataggio e Bentornato

func test_salvataggio_completo_compendio_e_segreti() -> void:
	assert_true(Game.new_game(1, "normal", 31))
	var comp := Game.system("compendium") as CompendiumSystem
	comp.found_pet("pet_skill_fishing")
	comp.found_pet("pet_skill_fishing")
	comp.grant_title("title_gardener")
	comp.grant_cosmetic("cosmetic_frame_fishing_bronze")
	EventBus.objective_event.emit("tradeup", {"qty": 3})
	var bank := Game.system("bank") as BankSystem
	(GameState.data.skills as Dictionary)["fishing"] = {"xp": 0.0, "level": 60}
	bank.add("map_fragment", 10, "test")
	var sc := Game.system("secrets") as SecretSystem
	assert_true(sc.reveal("moonlit_pool"))
	assert_true(sc.explore("moonlit_pool"))
	Game.sim.tick(0.1)
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	var res := Game.load_game(1)
	assert_true(res.ok, str(res.get("error")))
	var comp2 := Game.system("compendium") as CompendiumSystem
	assert_true(comp2.has_pet("pet_skill_fishing"))
	assert_eq(comp2.pet_dupes("pet_skill_fishing"), 1)
	assert_true(comp2.has_title("title_gardener"))
	assert_true(comp2.has_frame("cosmetic_frame_fishing_bronze"))
	assert_eq(comp2.counter("tradeup"), 3)
	assert_typeof(comp2.state.counters.tradeup, TYPE_INT)
	var sc2 := Game.system("secrets") as SecretSystem
	assert_true(sc2.is_discovered("moonlit_pool"))
	assert_eq(sc2.active_spot(), "moonlit_pool")
	assert_typeof(sc2.state.spots.moonlit_pool.runs_left, TYPE_INT)
	# bonus del famiglio riapplicato dopo il caricamento
	assert_gt(Modifiers.apply(100.0, "skill_double_pct", ["fishing"]), 100.0)
	# offline di 2 ore: l'esplorazione finisce e compare la riga nel Bentornato
	var report: Dictionary = Game.sim.run_offline(2.0 * 3600.0)
	assert_true(report.has("secrets"), "sezione secrets nel resoconto")
	var wb := WelcomeBack.build(2.0 * 3600.0, report, DataRegistry, 12.0 * 3600.0)
	var text := ""
	for sec in wb.sections:
		text += "\n".join(sec.lines) + "\n"
	assert_true(text.contains("Pozza") or text.contains("Moonlit"), "riga dell'esplorazione: " + text)
