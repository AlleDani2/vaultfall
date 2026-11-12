extends GutTest
## Schermate Tenuta e Gilda + integrazione con la partita vera: registro, apertura, pulsanti, salvataggio completo,
## offline con Bentornato. Come test_market_ui: cartella di salvataggio temporanea.

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_estate_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _unlock_all() -> void:
	for b in EstateFixtures.ALL_BUILDINGS:
		(GameState.data.unlocks as Array).append("building:" + b)
	for t in ["feature:estate", "skill:mining", "skill:fishing", "zone:saltreach"]:
		(GameState.data.unlocks as Array).append(t)


func _setup_estate() -> EstateSystem:
	var e := Game.system("estate") as EstateSystem
	var levels := {"cottage": 10, "sawmill": 12, "mine_shaft": 4, "shopfront": 3, "warehouse": 4, "private_vault": 2, "academy": 15, "tavern": 20}
	for bid in levels:
		e._entry(bid)["level"] = levels[bid]
	e.state.settlers = e.settler_cap()
	e.state.pantry = 50.0
	return e


func test_registro_ha_le_scene() -> void:
	for id in ["estate", "guild"]:
		var e := ScreenRegistry.get_entry(id)
		assert_false(e.is_empty(), id)
		assert_true(ResourceLoader.exists(e.scene), id + ": scena")
	assert_eq(ScreenRegistry.get_entry("estate").unlock, "feature:estate")
	assert_eq(ScreenRegistry.get_entry("guild").unlock, "feature:mercenaries")


func test_sistemi_registrati_nell_ordine() -> void:
	var ids := PackedStringArray()
	for s in SystemRegistry.create_all():
		ids.append(s.id)
	var order := ["skills", "apprentices", "estate", "market", "mercenaries", "expeditions", "buffs", "quests", "unlock"]
	var last := -1
	for id in order:
		var i := ids.find(id)
		assert_gt(i, last, "ordine fisso: " + id)
		last = i


func test_schermate_si_aprono_e_funzionano() -> void:
	assert_true(Game.new_game(1, "normal", 12))
	_unlock_all()
	var e := _setup_estate()
	var bank := Game.system("bank") as BankSystem
	bank.add_gold(10000000)
	bank.add("plank_pine", 500)
	bank.add("bar_copper", 500)
	bank.add("food_bleak", 40)
	(Game.system("apprentices") as ApprenticeSystem).assign(0, "wc_pine")
	Game.sim.tick(0.1)
	for path in ["res://src/ui/screens/EstateScreen.tscn", "res://src/ui/screens/GuildScreen.tscn"]:
		var scr: Control = (load(path) as PackedScene).instantiate()
		add_child_autofree(scr)
		await wait_process_frames(1)
		scr.open({})
		scr.refresh()
		assert_gt(scr.get_child_count(), 2, path)
		for i in 5:
			Game.sim.tick(1.0)
			scr.refresh()
		if path.contains("Estate"):
			var lv0 := e.level_of("sawmill")
			# FIX-MEDIO: Taverna e Accademia non occupano più coloni, quindi qui ci sono coloni liberi: servono
			# anche i materiali della banda della Segheria (livello 12 = banda 2)
			var c := e.cost_of("sawmill")
			for it in c.items:
				bank.add(str(it), int(c.items[it]))
			scr._on_upgrade("sawmill", 1)
			if e.settlers_free() > 0:
				assert_eq(e.level_of("sawmill"), lv0 + 1, "il pulsante +1 sale di un livello")
			scr._food_sig = ""
			scr.refresh()
			scr._on_stock(10)
			assert_gt(e.pantry(), 50.0, "rifornimento dispensa")
			scr._on_collect()
		else:
			var mc := Game.system("mercenaries") as MercenarySystem
			var ex := Game.system("expeditions") as ExpeditionSystem
			assert_gt(mc.candidates().size(), 0)
			assert_gt(ex.board().size(), 0)
			var cand: Dictionary = mc.candidates()[0]
			assert_true(mc.hire(str(cand.uid)))
			scr.refresh()
			scr._selected_offer = str(ex.board()[0].id)
			scr.refresh()
			scr.refresh()
			assert_not_null(scr._preview_label, "anteprima di rischio e ricompensa")
			assert_true(scr._preview_label.text.length() > 10)
		scr.close()


func test_salvataggio_completo_e_bentornato() -> void:
	assert_true(Game.new_game(1, "normal", 21))
	_unlock_all()
	var e := _setup_estate()
	var bank := Game.system("bank") as BankSystem
	bank.add_gold(10000000)
	var mc := Game.system("mercenaries") as MercenarySystem
	var ex := Game.system("expeditions") as ExpeditionSystem
	Game.sim.tick(0.1)
	var cand: Dictionary = mc.candidates()[0]
	assert_true(mc.hire(str(cand.uid)))
	assert_true(ex.start(str(ex.board()[0].id), [str(cand.uid)]))
	(Game.system("apprentices") as ApprenticeSystem).assign(0, "wc_pine")
	for i in 50:
		Game.sim.tick(0.1)
	assert_true(SaveService.save_now())
	var lv := e.level_of("sawmill")
	var pros := float(e.state.prosperity)
	Game.stop_game(false)
	var res := Game.load_game(1)
	assert_true(res.ok, str(res.get("error")))
	var e2 := Game.system("estate") as EstateSystem
	assert_eq(e2.level_of("sawmill"), lv)
	assert_gte(float(e2.state.prosperity), pros - 1e-6)   # il recupero offline del tempo reale tra salvataggio e caricamento puo' aggiungere un po' di Prosperita' (coloni piu' rapidi)
	assert_lt(float(e2.state.prosperity), pros + 5.0)
	assert_typeof(e2.state.settlers, TYPE_INT)
	assert_eq((Game.system("expeditions") as ExpeditionSystem).active().size(), 1)
	assert_eq((Game.system("mercenaries") as MercenarySystem).roster().size(), 1)
	assert_eq((Game.system("apprentices") as ApprenticeSystem).slot_action(0), "wc_pine")
	# offline di 3 ore → Bentornato con le righe di Tenuta, Apprendisti e Spedizioni
	e2.state.pantry = 100000.0
	var report: Dictionary = Game.sim.run_offline(3.0 * 3600.0)
	assert_true(report.has("estate"))
	assert_true(report.has("apprentices"))
	var wb := WelcomeBack.build(3.0 * 3600.0, report, DataRegistry, 12.0 * 3600.0)
	assert_false(wb.empty)
	var text := ""
	for sec in wb.sections:
		text += "\n".join(sec.lines) + "\n"
	assert_true(text.contains("Tenuta") or text.contains("Estate"), "riga della Tenuta nel Bentornato: " + text)
	var ex2 := Game.system("expeditions") as ExpeditionSystem
	assert_eq(ex2.active().size() + ex2.log_entries().size(), 1, "la spedizione o è conclusa o è ancora in corso")
