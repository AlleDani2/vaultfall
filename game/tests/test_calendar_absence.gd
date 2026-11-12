extends GutTest
## Sintesi di bilanciamento (audit 84, R-OFF-6): l'assenza oltre il limite offline fa avanzare solo il calendario
## (Commesse giornaliere/settimanali, limiti giornalieri dell'Emporio), mai la produzione. Sistemi VERI (Game.new_game).

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_calendar_absence_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _open_game() -> void:
	assert_true(Game.new_game(1, "normal", 84))
	for t in ["feature:market", "feature:combat", "feature:crates", "skill:woodcutting", "skill:mining", "skill:fishing", "skill:smithing"]:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)
	var c := Game.system("contracts") as ContractSystem
	assert_true(c.is_open())
	c.tick(1.0)


func test_una_settimana_via_porta_le_commesse_dei_giorni_trascorsi() -> void:
	_open_game()
	var c := Game.system("contracts") as ContractSystem
	var rules := DataRegistry.rules("contract_rules")
	var day := float(rules.day_s)
	var day0 := int(c.state.day)
	var off := Game.apply_absence(day * 7.0 + 60.0)
	assert_eq(off, Game.offline_cap_s(), "la produzione resta limitata al tetto offline")
	assert_eq(int(c.state.day) - day0, 7, "7 giorni di calendario, non solo le ore del tetto offline")
	assert_gt(c.contracts("daily").size(), int(rules.daily_slots), "le giornaliere dei giorni passati sono lì")
	assert_lte(c.contracts("daily").size(), int(rules.daily_slots) * int(rules.rollover_days))


func test_il_calendario_non_produce_nulla() -> void:
	_open_game()
	var gold := GameState.gold()
	var sim_calendar_only := Game.sim
	sim_calendar_only.run_calendar(86400.0 * 10.0)
	assert_eq(GameState.gold(), gold, "il calendario non dà oro")


func test_limite_giornaliero_dell_emporio_si_rinnova_col_calendario() -> void:
	_open_game()
	var m := Game.system("market") as MarketSystem
	var shop_id := "buy_key_t1"
	var day0 := int(m.state.day)
	m.state.shop_daily[shop_id] = {"day": day0, "n": 5}
	assert_eq(m.daily_used(shop_id), 5)
	Game.apply_absence(86400.0 * 3.0)
	assert_eq(m.daily_used(shop_id), 0, "dopo 3 giorni via il limite di oggi è libero")
	assert_eq(int(m.state.day) - day0, 3)
