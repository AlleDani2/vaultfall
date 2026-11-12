extends GutTest
## RAIDS: boss mondiali (docs/05 §8): finestre a rotazione ogni 4 h per 30 minuti "a gioco aperto", Corno dell'Adunata,
## alleati simulati, livelli di contributo e ricompense, ritirata e caduta, offline analitico contro il tick.

const Env := preload("res://tests/helpers/raids_env.gd")
const H := 3600.0


func _env(seed_v: int = 5, lvl: int = 60, tier: int = 6) -> Object:
	var env: Object = Env.make(seed_v, lvl, "warrior", tier)
	env.state.unlocks.append("feature:world_bosses")
	return env


func _open(env: Object, slot: int = 1) -> void:
	env.combat.state.wb["t"] = float(slot) * 4.0 * H + 10.0


func _run(env: Object, max_ticks: int = 30000) -> int:
	var n := 0
	while env.combat.in_combat() and n < max_ticks:
		env.tick(1)
		n += 1
	return n


func _done(env: Object) -> Dictionary:
	for e in env.combat.log_since(0):
		if str(e.k) == "wb_done":
			return e
	return {}


func test_finestre_a_rotazione() -> void:
	var env: Object = _env()
	var eg: EndgameCombat = env.combat.eg
	assert_true(eg.wb_window().is_empty(), "all'inizio nessun boss")
	assert_almost_eq(float(eg.wb_next().in_s), 4.0 * H, 1.0)
	var order := ["wandering_colossus", "sand_leviathan", "star_titan", "wandering_colossus"]
	for i in 4:
		_open(env, i + 1)
		assert_eq(str(eg.wb_window().boss), order[i], "rotazione dei 3 boss")
		assert_almost_eq(float(eg.wb_window().left_s), 1790.0, 1.0)
	env.combat.state.wb["t"] = 4.0 * H + 31.0 * 60.0
	assert_true(eg.wb_window().is_empty(), "dopo 30 minuti la finestra chiude")
	assert_almost_eq(float(eg.wb_next().in_s), 4.0 * H - 31.0 * 60.0, 1.0)


func test_l_orologio_corre_a_gioco_aperto_non_offline() -> void:
	var env: Object = _env()
	env.tick(100)
	assert_almost_eq(float(env.combat.state.wb.t), 10.0, 1e-6)
	env.combat.simulate_offline(8.0 * H)
	assert_almost_eq(float(env.combat.state.wb.t), 10.0, 1e-6, "offline non apre finestre")


func test_accesso_dalla_storia() -> void:
	var env: Object = Env.make(5, 60, "warrior", 6)
	_open(env)
	assert_false(env.combat.eg.start_world_boss("rotation"), "serve il capitolo dei boss mondiali")
	env.quests.active["main_c9_q2"] = true
	assert_true(env.combat.eg.start_world_boss("rotation"), "la missione che chiede di sconfiggerne uno lo permette")


func test_livelli_di_contributo() -> void:
	var env: Object = _env()
	var d: Dictionary = env.combat.eg.wb_def("wandering_colossus")
	var eg: EndgameCombat = env.combat.eg
	# soglie dai dati (FIX-COMBATTIMENTO: 15/35/55/70% della vita, prima 1/3/6/10 davano Platino a tutti)
	var th := {}
	for t in d.contribution_tiers:
		th[str(t.id)] = float(t.damage_pct)
	assert_eq(eg.wb_tier_for(d, th.bronze - 0.5), "")
	assert_eq(eg.wb_tier_for(d, th.bronze), "bronze")
	assert_eq(eg.wb_tier_for(d, th.silver), "silver")
	assert_eq(eg.wb_tier_for(d, th.gold), "gold")
	assert_eq(eg.wb_tier_for(d, th.platinum + 5.0), "platinum")
	assert_gte(th.bronze, 10.0, "le fasce devono discriminare (QA4: 33-81% per tutte le build)")


func test_incontro_completo_ricompense_ed_eventi() -> void:
	var env: Object = _env()
	_open(env)
	watch_signals(env.bus)
	var seen_tiers: Array = []
	env.bus.objective_event.connect(func(k: String, p: Dictionary) -> void:
		if k == "world_boss":
			seen_tiers.append(str(p.tier)))
	assert_true(env.combat.eg.start_world_boss("rotation"))
	assert_eq(env.combat.endgame_mode(), "wboss")
	var n := _run(env)
	assert_lt(n, 30000)
	var e := _done(env)
	assert_false(e.is_empty())
	assert_eq(str(e.tier), "platinum")
	assert_true(bool(e.killed))
	assert_gte((e.crates as Array).size(), 4, "4 casse delle Taglie al Platino")
	assert_eq(int(env.combat.state.wb.kills.wandering_colossus), 1)
	assert_eq(str(env.combat.state.wb.best.wandering_colossus), "platinum")
	assert_eq(int(env.combat.state.wb.done_slot), 1)
	assert_true(env.combat.eg.wb_window().is_empty(), "la finestra è stata usata")
	assert_false(env.combat.eg.start_world_boss("rotation"))
	for tier in ["bronze", "silver", "gold", "platinum"]:
		assert_true(seen_tiers.has(tier), "evento world_boss per il livello " + tier)
	assert_gt(env.bank.gold_n, 0, "oro del boss")
	assert_gte(get_signal_emit_count(env.bus, "crate_found"), 4)


func test_alleati_simulati_tolgono_vita_al_minuto() -> void:
	var env: Object = _env()
	_open(env)
	env.combat.eg.start_world_boss("rotation")
	env.tick(3000)         # 300 s
	var w: Dictionary = env.combat.eg.wb_progress()
	assert_almost_eq(float(w.ally_pct), 2.5 * 5.0, 1.0, "2,5% al minuto per 5 minuti")
	assert_lt(float(w.hp_pct), 100.0 - float(w.ally_pct) + 0.1)
	assert_almost_eq(float(w.left_s), 1790.0 - 300.0, 1.0)


func test_ritirata_incassa_il_livello_raggiunto() -> void:
	var env: Object = _env()
	_open(env)
	env.combat.eg.start_world_boss("rotation")
	env.tick(1500)
	var w: Dictionary = env.combat.eg.wb_progress()
	var expected := str(w.tier)
	env.combat.stop()
	assert_false(env.combat.in_combat())
	var e := _done(env)
	assert_false(e.is_empty())
	assert_eq(str(e.tier), expected)
	assert_false(bool(e.killed))


func test_senza_danno_nessun_premio() -> void:
	var env: Object = _env()
	_open(env)
	env.combat.eg.start_world_boss("rotation")
	env.combat.stop()
	var e := _done(env)
	assert_eq(str(e.tier), "")
	assert_eq((e.crates as Array).size(), 0)


func test_caduta_dell_eroe_chiude_l_incontro() -> void:
	var env: Object = _env(5, 25, 2)
	_open(env, 2)               # Leviatano, livello 65: troppo per un Eroe 25
	assert_true(env.combat.eg.start_world_boss("rotation"))
	_run(env, 20000)
	assert_false(env.combat.in_combat(), "caduto")
	assert_eq(int(env.combat.state.deaths), 1)
	var e := _done(env)
	assert_false(e.is_empty())
	assert_false(bool(e.killed))
	assert_eq(int(env.combat.state.wb.done_slot), 2)


func test_corno_evoca_e_si_consuma() -> void:
	var env: Object = _env()
	assert_false(env.combat.eg.summon_world_boss("star_titan"), "serve un Corno")
	env.bank.add("rally_horn", 2, "test")
	assert_true(env.combat.eg.summon_world_boss("sand_leviathan"))
	assert_eq(env.bank.count("rally_horn"), 1)
	assert_false(env.combat.eg.summon_world_boss("star_titan"), "uno alla volta")
	assert_eq(str(env.combat.eg.wb_horn().boss), "sand_leviathan")
	env.tick(100)
	assert_almost_eq(float(env.combat.eg.wb_horn().left_s), 1800.0 - 10.0, 0.5)
	assert_true(env.combat.eg.start_world_boss("horn"))
	assert_eq(str(env.state.activity.wb), "sand_leviathan")
	env.combat.stop()
	assert_true(env.combat.eg.wb_horn().is_empty(), "l'evocazione è finita")
	env.tick(18100)
	assert_true(env.combat.eg.wb_horn().is_empty())


func test_corno_scade_dopo_30_minuti() -> void:
	var env: Object = _env()
	env.bank.add("rally_horn", 1, "test")
	env.combat.eg.summon_world_boss("wandering_colossus")
	env.tick(18100)
	assert_true(env.combat.eg.wb_horn().is_empty())


func test_offline_stesso_esito_del_tick() -> void:
	var tick_pct := 0.0
	var seeds := 4
	var tier := ""
	for sd in seeds:
		var env: Object = _env(400 + sd)
		_open(env)
		env.combat.eg.start_world_boss("rotation")
		_run(env)
		var e := _done(env)
		tick_pct += float(e.pct)
		tier = str(e.tier)
	tick_pct /= seeds
	var off: Object = _env(66)
	_open(off)
	off.combat.eg.start_world_boss("rotation")
	var rep: Dictionary = off.combat.simulate_offline(3600.0)
	assert_false(off.combat.in_combat())
	var e2 := _done(off)
	print("WB_OFFLINE_VS_TICK pct tick %.2f offline %.2f; durata offline %.0f" % [tick_pct, float(e2.pct), float(rep.seconds)])
	assert_eq(str(e2.tier), tier)
	assert_true(bool(e2.killed))
	assert_almost_eq(float(e2.pct), tick_pct, tick_pct * 0.04, "contributo entro il 4% dal tick")
	assert_gte(int(off.combat.state.wb.kills.wandering_colossus), 1)
	assert_eq(int(off.combat.state.wb.done_slot), 1)


func test_offline_parziale_dopo_100_secondi() -> void:
	var secs := 100.0
	var tick_dealt := 0.0
	var seeds := 4
	for sd in seeds:
		var env: Object = _env(500 + sd)
		_open(env)
		env.combat.eg.start_world_boss("rotation")
		env.tick(int(secs / FixedStepClock.STEP))
		tick_dealt += float(env.combat.eg.wb_progress().pct)
	tick_dealt /= seeds
	var off: Object = _env(61)
	_open(off)
	off.combat.eg.start_world_boss("rotation")
	off.combat.simulate_offline(secs)
	assert_true(off.combat.in_combat(), "ancora in corso")
	var w: Dictionary = off.combat.eg.wb_progress()
	print("WB_PARTIAL contributo tick %.3f%% offline %.3f%%" % [tick_dealt, float(w.pct)])
	assert_almost_eq(float(w.pct), tick_dealt, tick_dealt * 0.05)
	assert_almost_eq(float(w.left_s), 1790.0 - secs, 1.0, "la finestra residua cala")


func test_offline_finestra_scaduta_paga_il_livello() -> void:
	var env: Object = _env(5, 40, 4)        # Eroe 40: contribuisce ma non finisce il Colosso da solo
	_open(env)
	env.combat.eg.start_world_boss("rotation")
	env.combat.simulate_offline(3.0 * H)
	assert_false(env.combat.in_combat())
	var e := _done(env)
	assert_false(e.is_empty())
	assert_ne(str(e.tier), "", "ha dato almeno il Bronzo")


func test_perf_offline_della_finestra_intera() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	var f0 := PerfGate.load_factor()
	var ms := INF
	for k in 3:          # migliore di 3, ogni volta con una partita nuova
		var env: Object = _env(5, 40, 4)
		_open(env)
		env.combat.eg.start_world_boss("rotation")
		var t0 := PerfGate.clock_usec()
		env.combat.simulate_offline(3.0 * H)
		ms = minf(ms, (PerfGate.clock_usec() - t0) / 1000.0)
	PerfGate.assert_time(self, "Boss mondiale: finestra offline (migliore di 3)", ms, 500.0, PerfGate.factor_around(f0))
