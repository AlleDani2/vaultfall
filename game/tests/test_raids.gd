extends GutTest
## RAIDS: Incursioni con la squadra di mercenari (docs/05 §8, docs/11 §8): accesso, effetti di ruolo, 3 fasi, ricompense,
## ricarica, rischio e infortuni, Custode (Prestigio), regole di Prova, offline analitico contro il tick, salvataggio.

const Env := preload("res://tests/helpers/raids_env.gd")
const RAID_ID := "collectors_den"


func _env(seed_v: int = 5, lvl: int = 55, tier: int = 6) -> Object:
	var env: Object = Env.make(seed_v, lvl, "warrior", tier)
	env.unlock_raid(RAID_ID)
	return env


func _run(env: Object, max_ticks: int = 30000) -> int:
	var n := 0
	while env.combat.in_combat() and n < max_ticks:
		env.tick(1)
		n += 1
	return n


func _done_entry(env: Object) -> Dictionary:
	for e in env.combat.log_since(0):
		if str(e.k) == "raid_done":
			return e
	return {}


func test_elenco_e_accesso() -> void:
	var env: Object = Env.make(5, 55, "warrior", 6)
	var list: Array = env.combat.raids()
	assert_eq(list.size(), 3)
	assert_false(list[0].unlocked, "serve il gettone della missione")
	assert_false(env.combat.eg.start_raid(RAID_ID, []))
	env.unlock_raid(RAID_ID)
	assert_true(env.combat.raids()[0].unlocked)
	var weak: Object = _env(5, 20, 3)
	assert_false(weak.combat.eg.raid_unlocked(RAID_ID), "serve il livello Eroe dei dati")
	assert_false(env.combat.raids()[1].unlocked)


func test_squadra_non_valida_rifiutata() -> void:
	var env: Object = _env()
	var p: Array = env.party()
	assert_false(env.combat.eg.start_raid(RAID_ID, [p[0], p[0]]), "mercenario ripetuto")
	assert_false(env.combat.eg.start_raid(RAID_ID, ["m_inesistente"]))
	var four: Array = p + [env.merc("striker")]
	assert_false(env.combat.eg.start_raid(RAID_ID, four), "al massimo 3")
	env.mercs.injure(p[0], 3600.0)
	assert_false(env.combat.eg.start_raid(RAID_ID, p), "mercenario ferito")
	env.mercs.get_merc(p[1])["busy"] = "exp_1"
	assert_false(env.combat.eg.start_raid(RAID_ID, [p[1]]), "mercenario occupato")
	assert_true(env.combat.eg.start_raid(RAID_ID, []), "squadra vuota consentita")


func test_effetti_di_ruolo_scalano_col_potere() -> void:
	var env: Object = _env()
	var full: Dictionary = env.combat.eg.raid_fx(RAID_ID, env.party("epic", 40))
	assert_almost_eq(float(full.required), 30.0 * pow(1.35, 4) * 4.0, 1e-6, "30 × 1,35^(zona−1) × 4")
	assert_gt(float(full.ratio), 0.9)
	assert_almost_eq(float(full.defender), minf(1.5, float(full.ratio)), 1e-9)
	var strong: Dictionary = env.combat.eg.raid_fx(RAID_ID, env.party("legendary", 50))
	assert_almost_eq(float(strong.f), 1.5, 1e-9, "tetto ×1,5")
	# MURI (BOT-02/03): senza mercenari l'Eroe conta da solo (quota hero_share) e copre i ruoli per hero_role_share
	var data_rr: Dictionary = DataRegistry.rules("mercenary_rules")["raid_roles"]
	var none: Dictionary = env.combat.eg.raid_fx(RAID_ID, [])
	var rel := minf(55.0 / 55.0, float(data_rr.hero_level_cap))
	assert_almost_eq(float(none.ratio), float(data_rr.hero_share) * rel, 1e-9, "l'Eroe al livello dell'incursione vale hero_share")
	assert_almost_eq(float(none.defender), float(none.f) * float(data_rr.hero_role_share), 1e-9, "ruolo scoperto: l'Eroe copre una parte")
	var only: Object = _env()
	var s: String = only.merc("striker", "epic", 40)
	var fx: Dictionary = only.combat.eg.raid_fx(RAID_ID, [s])
	assert_gt(float(fx.striker), float(fx.defender), "il ruolo presente vale piu' di quello coperto dall'Eroe")
	assert_almost_eq(float(fx.striker), float(fx.f), 1e-9)
	assert_almost_eq(float(fx.defender), float(fx.f) * float(data_rr.hero_role_share), 1e-9)
	assert_almost_eq(float(fx.healer), float(fx.defender), 1e-9)


func test_potere_dell_eroe_cresce_col_livello_fino_al_tetto() -> void:
	var data_rr: Dictionary = DataRegistry.rules("mercenary_rules")["raid_roles"]
	var low: Object = _env(5, 50, 6)
	var hi: Object = _env(5, 55, 6)
	var cap: Object = _env(5, 200, 6)
	var p_low: float = low.combat.eg.raid_hero_power(RAID_ID)
	var p_hi: float = hi.combat.eg.raid_hero_power(RAID_ID)
	var p_cap: float = cap.combat.eg.raid_hero_power(RAID_ID)
	assert_lt(p_low, p_hi)
	assert_almost_eq(p_hi, hi.combat.eg.raid_required_power(RAID_ID) * float(data_rr.hero_share), 1e-6)
	assert_almost_eq(p_cap, hi.combat.eg.raid_required_power(RAID_ID) * float(data_rr.hero_share) * float(data_rr.hero_level_cap), 1e-6, "tetto del livello")
	var fx: Dictionary = hi.combat.eg.raid_fx(RAID_ID, hi.party("common", 5))
	assert_almost_eq(float(fx.hero_power), p_hi, 1e-9)
	assert_gt(float(fx.power), p_hi, "i mercenari sommano all'Eroe")


func test_eroe_al_livello_con_squadra_tipica_vince_la_cittadella() -> void:
	# MURI (BOT-03): la Cittadella (ordine 7) non e' piu' un muro: Eroe 78 (equipaggiamento un tier sotto) e tre mercenari rari di livello 15 -> vittoria probabile
	var env: Object = Env.make(31, 78, "warrior", 7)
	env.unlock_raid("rime_citadel")
	var pv: Dictionary = env.combat.eg.raid_preview("rime_citadel", env.party("rare", 15))
	assert_gt(float(pv.fx.hero_power), 0.0)
	assert_gt(float(pv.p_win), 0.5, "squadra tipica: vittoria probabile")


func test_eroe_al_livello_con_squadra_tipica_vince_il_cuore_del_caveau() -> void:
	# MURI (BOT-02): il Cuore (richiesto 1.787) non e' piu' irraggiungibile: Eroe 100 (equipaggiamento un tier sotto), 3 mercenari
	# rari di livello 15 (potere ~144 = 8% del richiesto) -> vittoria probabile; senza squadra l'Eroe copre i ruoli da solo.
	var env: Object = Env.make(32, 100, "warrior", 10)
	env.unlock_raid("heart_of_the_vault")
	var with_p: Dictionary = env.combat.eg.raid_preview("heart_of_the_vault", env.party("rare", 15))
	var solo: Dictionary = env.combat.eg.raid_preview("heart_of_the_vault", [])
	assert_gt(float(with_p.p_win), 0.5, "squadra tipica: vittoria probabile")
	assert_gt(float(solo.p_win), 0.0, "anche l'Eroe da solo ha una possibilita'")
	assert_gte(float(with_p.p_win), float(solo.p_win), "la squadra non peggiora")
	assert_gt(float(with_p.fx.ratio), 0.6, "rapporto potere/richiesto raggiungibile (prima ~0,04)")


func test_tratto_predone_potenzia_il_ruolo() -> void:
	var env: Object = _env()
	var a: String = env.merc("defender", "epic", 40)
	var b: String = env.merc("defender", "epic", 40, ["raider"])
	var plain: Dictionary = env.combat.eg.raid_fx(RAID_ID, [a])
	var raider: Dictionary = env.combat.eg.raid_fx(RAID_ID, [b])
	assert_almost_eq(float(raider.defender) / float(plain.defender), 1.15, 1e-6, "+15% all'effetto del ruolo")


func test_apply_fx_usa_i_numeri_dei_dati() -> void:
	var env: Object = _env()
	var st: Dictionary = env.combat._stats().duplicate()
	var out: Dictionary = env.combat.eg.apply_fx(st, {"defender": 1.0, "healer": 1.0, "striker": 1.0})
	assert_almost_eq(float(out.dmg_taken_mult), float(st.dmg_taken_mult) * 0.7, 1e-9)
	assert_almost_eq(float(out.regen_pct), float(st.regen_pct) + 1.5, 1e-9)
	assert_almost_eq(float(out.max_hit), float(st.max_hit) * 1.4, 1e-6)


func test_incursione_completa_ricompense_ricarica_e_missioni() -> void:
	var env: Object = _env()
	var p: Array = env.party("epic", 40)
	watch_signals(env.bus)
	assert_true(env.combat.eg.start_raid(RAID_ID, p))
	assert_eq(env.combat.endgame_mode(), "raid")
	assert_true(env.mercs.is_busy(p[0]), "i mercenari sono in incursione")
	_run(env)
	assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 1, "vinta")
	assert_false(env.combat.in_combat())
	var d: Dictionary = env.combat.eg.raid_def(RAID_ID)
	var entry := _done_entry(env)
	assert_false(entry.is_empty())
	assert_gte(env.bank.gold_n, int(d.completion_reward.gold), "oro del premio")
	assert_gte(env.bank.count("raid_seal"), 3, "Sigilli d'Incursione")
	assert_lte(env.bank.count("raid_seal"), 5)
	assert_eq(env.bank.count("era_essence"), 10, "10 porzioni di Essenza d'Era alla prima Era")
	assert_gte(get_signal_emit_count(env.bus, "crate_found"), 2, "due casse")
	assert_signal_emitted_with_parameters(env.bus, "objective_event", ["complete_raid", {"raid": RAID_ID, "qty": 1, "era": 1}])
	assert_almost_eq(env.combat.eg.raid_cd(RAID_ID), 4.0 * 3600.0, 600.0, "ricarica di 4 h dopo la vittoria")
	assert_false(env.mercs.is_busy(p[0]), "mercenari liberi")
	assert_gt(float(env.mercs.get_merc(p[0]).xp) + float(env.mercs.get_merc(p[0]).level), 40.0, "XP ai mercenari")
	assert_false(env.combat.eg.start_raid(RAID_ID, p), "in ricarica")
	assert_true(env.combat.raids()[0].cd_s > 0.0)


func test_ricarica_scorre_e_poi_si_riparte() -> void:
	var env: Object = _env()
	env.combat.state.raid_cd[RAID_ID] = 100.0
	assert_false(env.combat.eg.start_raid(RAID_ID, []))
	env.tick(1010)
	assert_eq(env.combat.eg.raid_cd(RAID_ID), 0.0)
	assert_true(env.combat.eg.start_raid(RAID_ID, []))


func test_la_ricarica_scorre_anche_offline() -> void:
	var env: Object = _env()
	env.combat.state.raid_cd[RAID_ID] = 5000.0
	env.combat.simulate_offline(3000.0)
	assert_almost_eq(env.combat.eg.raid_cd(RAID_ID), 2000.0, 1e-6)


func test_tre_fasi_cambiano_lo_stile_del_boss() -> void:
	var env: Object = _env()
	assert_true(env.combat.eg.start_raid(RAID_ID, env.party("epic", 40)))
	var seen: Array = []
	var n := 0
	while env.combat.in_combat() and n < 30000:
		env.tick(1)
		n += 1
		for e in env.combat.log_since(0):
			if str(e.k) == "phase" and not seen.has(int(e.i)):
				seen.append(int(e.i))
	assert_eq(seen, [1, 2], "fase 2 al 66%, fase 3 al 33%")
	var boss: Dictionary = DataRegistry.get_def("monsters", "master_fence")
	assert_eq(str(boss.phases[2].style), "arcane")


func test_fase_cambia_il_tipo_di_danno_e_il_triangolo() -> void:
	var env: Object = _env()
	var sim: CombatSim = CombatSim.new()
	var boss: Dictionary = DataRegistry.get_def("monsters", "master_fence")
	sim.configure(env.combat._sim_params(env.combat._stats(), boss, env.combat._scaled(boss, 1), true))
	var e: Dictionary = sim.new_enemy()
	assert_eq(sim.mstyle(e), "ranged")
	e["hp"] = float(e.max) * 0.5
	sim._check_phase(e)
	assert_eq(int(e.phase), 1)
	e["hp"] = float(e.max) * 0.2
	sim._check_phase(e)
	assert_eq(sim.mstyle(e), "arcane")
	e["hp"] = float(e.max)
	sim._check_phase(e)
	assert_eq(int(e.phase), 2, "la fase non torna indietro")


func test_la_squadra_accorcia_lo_scontro() -> void:
	var with_p: Object = _env(11)
	var solo: Object = _env(11)
	var a: Dictionary = with_p.combat.eg.raid_preview(RAID_ID, with_p.party("epic", 40))
	var b: Dictionary = solo.combat.eg.raid_preview(RAID_ID, [])
	assert_lt(float(a.time_s), float(b.time_s) * 0.9, "più danno e meno danni subiti")
	assert_gt(float(a.p_win), 0.9)
	assert_eq(str(a.level), "green")


func test_squadra_vuota_e_hero_debole_indicatore_rosso() -> void:
	var weak: Object = _env(5, 55, 0)
	weak.skills.levels["hero"] = 8
	var r: Dictionary = weak.combat.eg.raid_preview(RAID_ID, [])
	assert_eq(str(r.level), "red")
	assert_lt(float(r.p_win), 0.5)


func test_fallimento_ferisce_i_mercenari_e_non_da_ricarica() -> void:
	var injured_any := false
	for sd in range(1, 7):
		var env: Object = _env(sd, 55, 0)
		var p: Array = env.party("common", 5)
		assert_true(env.combat.eg.start_raid(RAID_ID, p))
		env.skills.levels["hero"] = 8          # l'Eroe che parte alla leggera: cade
		(env.state.activity as Dictionary)["fx"] = env.combat.eg.raid_fx(RAID_ID, p)       # il potere dell'Eroe segue il suo livello
		_run(env)
		assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 0, "persa")
		assert_eq(env.combat.eg.raid_cd(RAID_ID), 0.0, "nessuna ricarica se si perde")
		assert_gt(float(env.combat.state.wounded_s), 0.0, "Ferito dopo la morte")
		for u in p:
			assert_false(env.mercs.is_busy(u), "liberi")
			injured_any = injured_any or env.mercs.is_injured(u)
		var failed := false
		for e in env.combat.log_since(0):
			failed = failed or str(e.k) == "raid_failed"
		assert_true(failed)
	assert_true(injured_any, "con il 30% a testa almeno un infortunio in 6 prove")


func test_ritirata_libera_i_mercenari() -> void:
	var env: Object = _env()
	var p: Array = env.party()
	env.combat.eg.start_raid(RAID_ID, p)
	env.tick(50)
	env.combat.stop()
	assert_false(env.combat.in_combat())
	assert_false(env.mercs.is_busy(p[0]))
	assert_eq(env.combat.eg.raid_cd(RAID_ID), 0.0)


func test_cambio_attivita_libera_i_mercenari_entro_un_secondo() -> void:
	var env: Object = _env()
	var p: Array = env.party()
	env.combat.eg.start_raid(RAID_ID, p)
	env.state.activity.clear()             # come fa SkillSystem.start: l'attività viene sostituita senza avvisare
	env.tick(12)
	assert_false(env.mercs.is_busy(p[0]))


func test_custode_chiama_il_prestigio_una_volta_per_era() -> void:
	var env: Object = _env(5, 105, 10)
	env.combat.eg._raid_win({"raid": "heart_of_the_vault", "party": [], "t": 10.0})
	assert_eq(env.prestige.calls, [1], "on_warden_defeated(Era corrente)")
	env.combat.eg._raid_win({"raid": RAID_ID, "party": [], "t": 10.0})
	assert_eq(env.prestige.calls.size(), 1, "solo il Custode")
	env.state.prestige = {"era_current": 3}
	env.combat.eg._raid_win({"raid": "heart_of_the_vault", "party": [], "t": 10.0})
	assert_eq(env.prestige.calls, [1, 3])
	assert_eq(env.bank.count("era_essence"), 10 + 10 + 30, "10 porzioni × Era")


func test_regole_di_prova_vita_dei_mostri_abilita_e_triangolo() -> void:
	var env: Object = _env()
	env.prestige.rules = {"monster_hp_mult": 1.5}
	env.state.unlocks.append("zone:millbrook")
	env.combat.start("millbrook", "mud_slime")
	var e: Dictionary = {}
	for i in 60:
		env.tick(1)
		e = env.state.activity.get("enemy", {})
		if not e.is_empty():
			break
	var base: float = float(DataRegistry.get_def("monsters", "mud_slime").stats.hp)
	assert_almost_eq(float(e.max), base * 1.5, base * 0.001, "vita dei mostri ×1,5")
	env.prestige.rules = {"no_abilities": true, "forced_disadvantage": true}
	var p: Dictionary = env.combat._sim_params(env.combat._stats(), {"id": "x"}, {}, true)
	assert_eq((p.abilities as Array).size(), 0, "nessuna abilità attiva")
	assert_true(bool(p.forced_dis))
	var sim: CombatSim = CombatSim.new()
	sim.forced_dis = true
	var t: Dictionary = Formulas.k().combat.triangle
	assert_eq(sim._tri("melee", "melee", true), float(t.disadvantage), "l'eroe è sempre in svantaggio")
	assert_eq(sim._tri("melee", "melee", false), float(t.advantage), "il mostro sempre in vantaggio")


func test_offline_incursione_vinta_come_il_tick() -> void:
	var tick_t := 0.0
	var seeds := 6
	for sd in seeds:
		var env: Object = _env(200 + sd)
		env.combat.eg.start_raid(RAID_ID, env.party("epic", 40))
		_run(env)
		tick_t += float(_done_entry(env).t)
	tick_t /= seeds
	var off: Object = _env(77)
	var p: Array = off.party("epic", 40)
	var prev: Dictionary = off.combat.eg.raid_preview(RAID_ID, p)
	print("RAID_OFFLINE_VS_TICK tick medio %.1f s, analitico %.1f s (%+.2f%%)" % [tick_t, float(prev.time_s), (float(prev.time_s) / tick_t - 1.0) * 100.0])
	# FIX-COMBATTIMENTO: con le fasi sui tre stili lo scarto misurato e -4,0% (obiettivo del resoconto 65: <= 4%)
	assert_almost_eq(float(prev.time_s), tick_t, tick_t * 0.045, "durata dell'incontro entro il 4% dal tick")
	off.combat.eg.start_raid(RAID_ID, p)
	var rep: Dictionary = off.combat.simulate_offline(3600.0)
	assert_false(off.combat.in_combat(), "l'incursione è finita")
	assert_eq(int(off.combat.state.raid_clears.get(RAID_ID, 0)), 1)
	assert_gte(int(rep.gold), 12819)
	assert_eq(int(rep.kills), 1)
	assert_gte(off.bank.count("raid_seal"), 3)
	assert_gte(off.bank.count("era_essence"), 10)
	assert_false(off.mercs.is_busy(p[0]))
	assert_almost_eq(float(rep.seconds), tick_t, tick_t * 0.04)


func test_offline_parziale_lascia_il_boss_a_meta_come_il_tick() -> void:
	var secs := 100.0
	var frac_tick := 0.0
	var seeds := 6
	for sd in seeds:
		var env: Object = _env(300 + sd)
		env.combat.eg.start_raid(RAID_ID, env.party("rare", 16))      # f ~ 1 con il potere dell'Eroe (hero_share) + squadra
		env.tick(int(secs / FixedStepClock.STEP))
		var e: Dictionary = env.state.activity.enemy
		frac_tick += float(e.hp) / float(e.max)
	frac_tick /= seeds
	var off: Object = _env(88)
	off.combat.eg.start_raid(RAID_ID, off.party("rare", 16))
	off.combat.simulate_offline(secs)
	assert_true(off.combat.in_combat(), "ancora in corso")
	var e2: Dictionary = off.state.activity.enemy
	var frac_off: float = float(e2.hp) / float(e2.max)
	print("RAID_PARTIAL tick %.3f offline %.3f" % [frac_tick, frac_off])
	assert_almost_eq(frac_off, frac_tick, 0.04, "vita residua del boss dopo 100 s")
	# e si può riprendere a tick fino alla vittoria
	_run(off)
	assert_eq(int(off.combat.state.raid_clears.get(RAID_ID, 0)), 1)


func test_offline_eroe_troppo_debole_cade_e_si_ferma() -> void:
	var env: Object = _env(5, 55, 0)
	var p: Array = env.party("common", 5)
	env.combat.eg.start_raid(RAID_ID, p)
	env.skills.levels["hero"] = 8
	var rep: Dictionary = env.combat.simulate_offline(3600.0)
	assert_true(bool(rep.get("died", false)))
	assert_eq(str(rep.get("stopped", "")), "death")
	assert_false(env.combat.in_combat())
	assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 0)
	assert_gt(float(env.combat.state.wounded_s), 0.0)
	assert_false(env.mercs.is_busy(p[0]))


func test_salvataggio_round_trip_e_vecchi_salvataggi() -> void:
	var env: Object = _env()
	env.combat.state.raid_cd[RAID_ID] = 1234.5
	env.combat.state.raid_clears[RAID_ID] = 7
	env.combat.state.wb["done_slot"] = 3
	env.combat.state.rift["best"] = 42
	var js := JSON.stringify(env.combat.to_state())
	var back: Dictionary = JSON.parse_string(js)
	var env2: Object = _env()
	env2.combat.from_state(back)
	assert_eq(int(env2.combat.state.raid_clears[RAID_ID]), 7)
	assert_almost_eq(float(env2.combat.state.raid_cd[RAID_ID]), 1234.5, 1e-6)
	assert_eq(int(env2.combat.state.wb.done_slot), 3)
	assert_eq(int(env2.combat.state.rift.best), 42)
	var old: Dictionary = env.combat.to_state().duplicate(true)
	for k in ["raid_cd", "raid_clears", "raid_best_s", "wb", "rift"]:
		old.erase(k)
	env2.combat.from_state(old)
	assert_true(env2.combat.state.has("wb") and env2.combat.state.has("rift"), "campi nuovi con valori di base")
	assert_eq(int(env2.combat.state.rift.best), 0)


func test_negozio_trofei_compra_il_corno() -> void:
	var env: Object = _env()
	env.bank.add("raid_seal", 25, "test")
	assert_true(env.combat.eg.shop_buy("trophy_hall", "rally_horn"))
	assert_eq(env.bank.count("rally_horn"), 1)
	assert_eq(env.bank.count("raid_seal"), 15)
	assert_true(env.combat.eg.shop_buy("trophy_hall", "rally_horn"))
	assert_false(env.combat.eg.shop_buy("trophy_hall", "rally_horn"), "Sigilli finiti")
	assert_false(env.combat.eg.shop_buy("trophy_hall", "oggetto_che_non_c_e"))
