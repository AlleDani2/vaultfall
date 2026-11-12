extends GutTest
## RAIDS: La Breccia (docs/05 §9): piani generati, affissi, Guardiani, ricompense per piano, ripartenza, morte, offline.

const Env := preload("res://tests/helpers/raids_env.gd")


func _env(seed_v: int = 5, lvl: int = 100, tier: int = 11) -> Object:
	var env: Object = Env.make(seed_v, lvl, "warrior", tier)
	env.state.unlocks.append("feature:rift")
	return env


func _run(env: Object, max_ticks: int = 60000) -> int:
	var n := 0
	while env.combat.in_combat() and n < max_ticks:
		env.tick(1)
		n += 1
	return n


func test_mostri_dei_piani() -> void:
	var env: Object = _env()
	var eg: EndgameCombat = env.combat.eg
	assert_eq(eg.rift_monsters_on(1), 5)
	assert_eq(eg.rift_monsters_on(10), 6, "ogni 10 piani un Guardiano")
	var a: Dictionary = eg.rift_mon(10, 0)
	var b: Dictionary = eg.rift_mon(11, 0)
	var s10 := Formulas.monster_stats(110, "normal")
	assert_eq(int(a.level), 110, "livello 100 + piano")
	var rd: Dictionary = eg.rift_def()
	assert_almost_eq(float(a.stats.hp) / (float(s10.hp) * pow(float(rd.stat_mult_per_floor), 10) * 1.3), 1.0, 1e-6, "moltiplicatore per piano e Fortificati dal piano 5")
	assert_gt(float(b.stats.hp), float(a.stats.hp))
	var g: Dictionary = eg.rift_mon(10, 5)
	assert_eq(str(g.type), str(rd.guardian_type))
	assert_eq(str(g.id), "rift_guardian")
	assert_true((g.mechanics as Array).has("enrage"))
	assert_true(g.name.has("it") and g.name.has("en"), "nomi bilingui")
	assert_ne(str(eg.rift_mon(1, 0).style), str(eg.rift_mon(2, 0).style), "gli stili ruotano")
	assert_eq(float(eg.rift_mon(15, 0).get("lifesteal_pct", 0.0)), 0.0)
	assert_eq(float(eg.rift_mon(20, 0).lifesteal_pct), 15.0, "Vampirici dal piano 20")


func test_affissi_cumulativi() -> void:
	var env: Object = _env()
	var eg: EndgameCombat = env.combat.eg
	assert_eq(eg.rift_affixes(4).size(), 0)
	assert_eq(eg.rift_affixes(5).size(), 1)
	assert_eq(eg.rift_affixes(10).size(), 2)
	assert_eq(eg.rift_affixes(30).size(), 5)
	var plain := Formulas.monster_stats(130, "normal")
	var m: Dictionary = eg.rift_mon(30, 0)
	var rd: Dictionary = eg.rift_def()
	var per := float(rd.stat_mult_per_floor)
	var per_d := float(rd.get("dmg_mult_per_floor", per))      # FIX-COMBATTIMENTO: danno piu piatto della vita
	assert_almost_eq(float(m.stats.armor) / (float(plain.armor) * pow(per, 30) * 1.4), 1.0, 1e-6, "Protetti +40% difesa")
	assert_almost_eq(float(m.stats.max_hit) / (float(plain.max_hit) * pow(per_d, 30) * 1.25), 1.0, 1e-6, "Furiosi +25% danno")


func test_accesso() -> void:
	var env: Object = Env.make(5, 100, "warrior", 11)
	assert_false(env.combat.eg.rift_unlocked())
	assert_false(env.combat.eg.start_rift(1))
	env.quests.done["main_c10_q6"] = true
	assert_true(env.combat.eg.rift_unlocked(), "la missione che la apre")
	assert_true(env.combat.eg.start_rift(1))


func test_punti_di_ripartenza_dopo_i_guardiani() -> void:
	var env: Object = _env()
	assert_eq(env.combat.eg.rift_start_options(), [1])
	assert_false(env.combat.eg.start_rift(11))
	env.combat.state.rift["guardian"] = 30
	assert_eq(env.combat.eg.rift_start_options(), [1, 11, 21, 31])
	assert_true(env.combat.eg.start_rift(31))
	assert_eq(int(env.state.activity.floor), 31)


func test_corsa_a_tick_frammenti_eventi_e_morte_al_guardiano() -> void:
	var env: Object = _env()
	var floors_seen: Array = []
	env.bus.objective_event.connect(func(k: String, p: Dictionary) -> void:
		if k == "rift_floor":
			floors_seen.append(int(p.floor)))
	assert_true(env.combat.eg.start_rift(1))
	_run(env)
	assert_false(env.combat.in_combat(), "l'Eroe cade prima o poi")
	var rf: Dictionary = env.combat.state.rift
	assert_gte(int(rf.best), 5)
	assert_eq(int(rf.deaths), 1)
	assert_eq(int(rf.runs), 1)
	var cleared := int(rf.best) - 1
	var shards := 0
	for f in range(1, cleared + 1):
		shards += 1 + floori(f / 10.0)
	assert_eq(env.bank.count("rift_shard"), shards, "1 + piano/10 Frammenti per ogni piano superato")
	assert_eq(int(rf.shards), shards)
	assert_eq(floors_seen, range(1, int(rf.best) + 1), "un evento rift_floor per ogni piano raggiunto")
	assert_gt(float(env.combat.state.wounded_s), 0.0)


func test_piano_di_guardiano_premi() -> void:
	var env: Object = _env()
	watch_signals(env.bus)
	env.combat.eg._rift_floor_done({}, 10)
	assert_eq(int(env.combat.state.rift.guardian), 10)
	assert_eq(env.bank.count("rift_shard"), 2)
	assert_eq(env.bank.count("era_essence"), 1, "Essenza d'Era dal Guardiano")
	assert_signal_emitted_with_parameters(env.bus, "crate_found", ["crate_rift", "rift:10"])
	env.state.prestige = {"era_current": 3}
	env.combat.eg._rift_floor_done({}, 20)
	assert_eq(env.bank.count("era_essence"), 1 + 3, "×Era")


func test_bonus_frammenti_di_breccia() -> void:
	var env: Object = _env()
	env.mods.set_source("test", [{"key": "rift_shard_pct", "value": 100, "mode": "add"}])
	env.combat.eg._rift_floor_done({}, 1)
	assert_eq(env.bank.count("rift_shard"), 2, "+100% Frammenti")


func test_uscita_volontaria_registra_la_fine() -> void:
	var env: Object = _env()
	env.combat.eg.start_rift(1)
	env.tick(100)
	env.combat.stop()
	var found := false
	for e in env.combat.log_since(0):
		if str(e.k) == "rift_end":
			found = true
			assert_false(bool(e.died))
	assert_true(found)
	assert_eq(int(env.combat.state.rift.deaths), 0)


func test_offline_stessa_morte_e_stessi_piani_del_tick() -> void:
	var t: Object = _env(9)
	t.combat.eg.start_rift(1)
	_run(t)
	var tick_best := int(t.combat.state.rift.best)
	var tick_shards: int = t.bank.count("rift_shard")
	var off: Object = _env(9)
	off.combat.eg.start_rift(1)
	var f0 := PerfGate.load_factor()
	var t0 := PerfGate.clock_usec()
	var rep: Dictionary = off.combat.simulate_offline(24.0 * 3600.0)
	var ms := (PerfGate.clock_usec() - t0) / 1000.0
	print("RIFT_OFFLINE_VS_TICK piano massimo tick %d offline %d; frammenti %d / %d; %.0f ms" % [tick_best, int(off.combat.state.rift.best), tick_shards, off.bank.count("rift_shard"), ms])
	assert_true(bool(rep.get("died", false)))
	assert_false(off.combat.in_combat())
	assert_almost_eq(float(off.combat.state.rift.best), float(tick_best), 1.0, "piano massimo entro 1 dal tick")
	assert_almost_eq(float(off.bank.count("rift_shard")), float(tick_shards), maxf(2.0, tick_shards * 0.2))
	PerfGate.assert_time(self, "Faglia: 24 ore offline entro 0,5 s", ms, 500.0, PerfGate.factor_around(f0))
	assert_gt(float(off.state.stats.kills), 0.0)
	assert_eq(int(off.combat.state.rift.deaths), 1)


func test_offline_corto_avanza_come_il_tick() -> void:
	var secs := 400.0
	var t: Object = _env(21, 100, 11)
	t.combat.eg.start_rift(1)
	t.tick(int(secs / FixedStepClock.STEP))
	var tick_floor := int(t.state.activity.floor) if t.combat.in_combat() else int(t.combat.state.rift.best)
	var off: Object = _env(21, 100, 11)
	off.combat.eg.start_rift(1)
	off.combat.simulate_offline(secs)
	var off_floor := int(off.state.activity.floor) if off.combat.in_combat() else int(off.combat.state.rift.best)
	print("RIFT_SHORT piano dopo %d s: tick %d offline %d" % [int(secs), tick_floor, off_floor])
	assert_almost_eq(float(off_floor), float(tick_floor), 1.0)


func test_senza_cibo_l_offline_si_ferma() -> void:
	var env: Object = _env()
	env.bank.stacks["food_bleak"] = 0
	env.combat.eg.start_rift(1)
	var rep: Dictionary = env.combat.simulate_offline(3600.0)
	assert_false(env.combat.in_combat() and not bool(rep.get("died", false)) and str(rep.get("stopped", "")) == "", "si ferma per morte o per mancanza di cibo")


func test_stima_del_piano_limite() -> void:
	var env: Object = _env()
	var lim: int = env.combat.eg.rift_estimate_limit(1)
	assert_gte(lim, 3)
	# FIX-COMBATTIMENTO: Breccia graduale (QA4: muro al piano 10 per tutti); senza Ranghi il limite e 20-30
	assert_lte(lim, 40, "un Guardiano ferma l'Eroe di base")
