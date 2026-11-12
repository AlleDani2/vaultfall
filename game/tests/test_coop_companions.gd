extends GutTest
## COOP-1: Compagni d'armi nelle Incursioni, nei Boss mondiali e nella Breccia: potere simulato (CombatSim), tick contro
## offline analitico, ricompense normali (nessuno scambio), titolo e sblocco, compagni scaduti o disattivati.

const Env := preload("res://tests/helpers/coop_env.gd")
const RAID_ID := "collectors_den"
const NOW := 1760000000


func _env(seed_v: int = 5, lvl: int = 55, tier: int = 6, cls: String = "warrior", created: int = 1700000000) -> Object:
	var env: Object = Env.make(seed_v, lvl, cls, tier, created)
	env.unlock_raid(RAID_ID)
	return env


## Importa in `env` il codice di un amico (altro ambiente, altra partita) e ne ritorna l'id.
func _befriend(env: Object, lvl: int = 55, tier: int = 6, cls: String = "warrior", created: int = 1700111111) -> String:
	var friend: Object = Env.make(9, lvl, cls, tier, created)
	var r: Dictionary = friend.share_to(env, NOW)
	assert_true(r.ok, str(r))
	return str(friend.coop.my_uid())


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


func _comp(env: Object) -> Dictionary:
	return env.coop.companions()[0]


func after_each() -> void:
	Env.free_all()


func test_un_amico_forte_quanto_te_vale_un_compagno_alla_pari() -> void:
	var env: Object = _env()
	_befriend(env)
	var rd: Dictionary = DataRegistry.get_def("raids", RAID_ID)
	var mon: Dictionary = DataRegistry.get_def("monsters", str(rd.boss))
	var ms: Dictionary = env.combat._scaled(mon, 1)
	var q: float = env.coop.quality(_comp(env), mon, ms, 600.0, 0.1)
	assert_almost_eq(q, 1.0, 0.05, "stessa classe, stesso equipaggiamento: qualità 1")


func test_potere_simulato_cresce_con_la_forza_del_compagno() -> void:
	var env: Object = _env()
	var rd: Dictionary = DataRegistry.get_def("raids", RAID_ID)
	var mon: Dictionary = DataRegistry.get_def("monsters", str(rd.boss))
	var ms: Dictionary = env.combat._scaled(mon, 1)
	var qs: Array = []
	var ids: Array = []
	for spec in [[20, 2], [55, 6], [90, 10]]:
		var e2: Object = _env()
		var fid := _befriend(e2, int(spec[0]), int(spec[1]), "warrior", 1700200000 + int(spec[0]))
		ids.append(fid)
		qs.append(e2.coop.quality(e2.coop.get_companion(fid), mon, ms, 600.0, 0.1))
	print("COOP_QUALITA deboli/pari/forti: ", qs)
	assert_lt(float(qs[0]), float(qs[1]), "un amico debole vale meno")
	assert_lte(float(qs[1]), float(qs[2]) + 1e-9, "uno più forte non vale meno")
	assert_lte(float(qs[2]), 1.5 + 1e-9, "tetto dei mercenari")
	assert_gt(float(qs[2]), 1.0)


func test_il_compagno_occupa_un_posto_libero_e_la_squadra_migliora() -> void:
	var env: Object = _env()
	var cid := _befriend(env, 55, 6, "ranger", 1700111999)
	var solo: Dictionary = env.combat.eg.raid_preview(RAID_ID, [])
	assert_true(env.combat.eg.start_raid(RAID_ID, []), "squadra vuota + compagno in squadra")
	var party: Array = env.state.activity.party
	assert_eq(party, ["c:" + cid], "il compagno è nella squadra")
	var fx: Dictionary = env.state.activity.fx
	assert_gt(float(fx.power), 0.0)
	assert_gt(float(fx.striker), 0.0, "il Ranger è un assaltatore")
	assert_lt(float(fx.defender), float(fx.striker), "ruoli scoperti: solo la quota dell'Eroe (MURI)")
	assert_almost_eq(float(fx.healer), float(fx.defender), 1e-9)
	# senza compagni la stessa anteprima è più lenta
	var e2: Object = _env()
	var nobody: Dictionary = e2.combat.eg.raid_preview(RAID_ID, [])
	assert_lt(float(solo.time_s), float(nobody.time_s), "con un amico assaltatore il boss cade prima")
	# un amico difensore tiene l'Eroe più in alto di vita
	var e3: Object = _env()
	_befriend(e3, 55, 6, "warrior", 1700111888)
	var tank: Dictionary = e3.combat.eg.raid_preview(RAID_ID, [])
	assert_gt(float(tank.fx.defender), 0.0, "il Guerriero è un difensore")
	var st0: Dictionary = e3.combat._stats_for("")
	var st1: Dictionary = e3.combat.eg.apply_fx(st0, tank.fx)
	assert_lt(float(st1.dmg_taken_mult), float(st0.dmg_taken_mult), "il difensore assorbe i colpi")
	assert_lte(float(tank.food), float(nobody.food), "e costa meno cibo")


func test_il_compagno_sostituisce_il_mercenario_piu_debole_e_non_si_ferisce() -> void:
	var env: Object = _env()
	var strong1: String = env.merc("defender", "epic", 40)
	var weak: String = env.merc("healer", "common", 5)
	var strong2: String = env.merc("striker", "epic", 40)
	var cid := _befriend(env)
	assert_true(env.combat.eg.start_raid(RAID_ID, [strong1, weak, strong2]))
	var party: Array = env.state.activity.party
	assert_eq(party.size(), 3)
	assert_true(party.has("c:" + cid))
	assert_false(party.has(weak), "il più debole cede il posto")
	assert_false(env.mercs.is_busy(weak), "il mercenario sostituito resta libero")
	assert_true(env.mercs.is_busy(strong1))
	_run(env)
	assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 1, "incursione vinta")
	for m in env.mercs.roster():
		assert_false(env.mercs.is_injured(str(m.uid)))
		assert_false(env.mercs.is_busy(str(m.uid)))
	assert_eq(env.mercs.roster().size(), 3, "il compagno non entra mai nella Taverna")


func test_ricompense_normali_e_nessuno_scambio() -> void:
	var with_f: Object = _env(61)
	_befriend(with_f)
	with_f.combat.eg.start_raid(RAID_ID, with_f.party("epic", 40))
	_run(with_f)
	var a := _done_entry(with_f)
	var without: Object = _env(61)
	without.combat.eg.start_raid(RAID_ID, without.party("epic", 40))
	_run(without)
	var b := _done_entry(without)
	assert_false(a.is_empty())
	assert_false(b.is_empty())
	assert_eq(int(a.gold), int(b.gold), "stesso oro")
	assert_eq(JSON.stringify(a.items), JSON.stringify(b.items), "stessi oggetti")
	assert_eq((a.crates as Array).size(), (b.crates as Array).size(), "stesse casse")
	# l'unica differenza nel Deposito: nessun oggetto o valuta in più dovuti all'amico
	for k in with_f.bank.stacks:
		if str(k).begins_with("food"):
			continue
		assert_lte(int(with_f.bank.stacks[k]), int(without.bank.stacks.get(k, 0)) + 0, "nulla in più: " + str(k))
	assert_eq(with_f.bank.inst.size(), without.bank.inst.size())


func test_titolo_e_sblocco_al_primo_completamento_con_un_amico() -> void:
	var env: Object = _env()
	assert_false(env.coop.is_unlocked())
	env.tick(15)
	assert_true(env.coop.is_unlocked(), "con un'incursione sbloccata compare «Amici»")
	assert_true((env.state.unlocks as Array).has("feature:coop"))
	_befriend(env)
	env.combat.eg.start_raid(RAID_ID, env.party("epic", 40))
	_run(env)
	assert_eq(int(env.coop.state.stats.raid_clears), 1)
	assert_true(env.comp.titles.has("title_companion_in_arms"), "titolo «Compagno d'armi»")
	assert_false(DataRegistry.get_def("titles", "title_companion_in_arms").is_empty())
	# senza amico: nessun titolo
	var e2: Object = _env()
	e2.combat.eg.start_raid(RAID_ID, e2.party("epic", 40))
	_run(e2)
	assert_eq(e2.comp.titles.size(), 0)
	assert_true(e2.coop.is_unlocked(), "la prima vittoria sblocca comunque")


func test_scaduto_o_disattivato_non_partecipa() -> void:
	var env: Object = _env()
	var cid := _befriend(env)
	assert_true(env.coop.set_enabled(cid, false))
	assert_false(env.combat.eg.start_raid(RAID_ID, ["c:" + cid]), "disattivato: non si può mettere in squadra")
	assert_true(env.combat.eg.start_raid(RAID_ID, []))
	assert_eq((env.state.activity.party as Array).size(), 0)
	env.combat.stop()
	env.coop.set_enabled(cid, true)
	env.coop.refresh(NOW + 90 * 86400)
	assert_eq(env.coop.active_companions().size(), 0, "scaduto")
	assert_false(env.combat.eg.start_raid(RAID_ID, ["c:" + cid]))
	assert_false(env.combat.eg.start_raid(RAID_ID, ["c:inesistente"]))


func test_sconfitta_con_un_compagno_non_rompe_nulla() -> void:
	var env: Object = _env(5, 55, 0)
	_befriend(env, 20, 1, "warrior", 1700333333)
	var m: Array = env.party("common", 5)
	assert_true(env.combat.eg.start_raid(RAID_ID, m))
	env.skills.levels["hero"] = 8              # l'Eroe che parte alla leggera: cade
	(env.state.activity as Dictionary)["fx"] = {"required": 1.0, "power": 0.0, "ratio": 0.0, "f": 0.0, "hero_power": 0.0, "defender": 0.0, "healer": 0.0, "striker": 0.0}      # senza supporto: l Eroe leggero cade
	_run(env)
	assert_false(env.combat.in_combat())
	assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 0)
	var failed := false
	for e in env.combat.log_since(0):
		failed = failed or str(e.k) == "raid_failed"
	assert_true(failed)
	assert_eq(env.coop.companions().size(), 1, "il compagno resta, è una copia")
	assert_eq(int(env.coop.state.stats.raid_clears), 0)
	assert_eq(env.comp.titles.size(), 0, "nessun titolo se si perde")


func test_tick_e_offline_coerenti_con_i_compagni() -> void:
	var tick_t := 0.0
	var seeds := 4
	for sd in seeds:
		var env: Object = _env(400 + sd)
		_befriend(env)
		env.combat.eg.start_raid(RAID_ID, env.party("rare", 16))
		_run(env)
		tick_t += float(_done_entry(env).t)
	tick_t /= seeds
	var off: Object = _env(77)
	_befriend(off)
	var p: Array = off.party("rare", 16)
	var prev: Dictionary = off.combat.eg.raid_preview(RAID_ID, p)
	print("COOP_OFFLINE_VS_TICK tick medio %.1f s, analitico %.1f s (%+.2f%%)" % [tick_t, float(prev.time_s), (float(prev.time_s) / tick_t - 1.0) * 100.0])
	assert_almost_eq(float(prev.time_s), tick_t, tick_t * 0.04, "durata entro il 4% dal tick")
	off.combat.eg.start_raid(RAID_ID, p)
	var rep: Dictionary = off.combat.simulate_offline(3600.0)
	assert_false(off.combat.in_combat(), "l'incursione è finita offline")
	assert_eq(int(off.combat.state.raid_clears.get(RAID_ID, 0)), 1)
	assert_almost_eq(float(rep.seconds), tick_t, tick_t * 0.05)
	assert_eq(int(off.coop.state.stats.raid_clears), 1, "anche offline conta il compagno")
	assert_true(off.comp.titles.has("title_companion_in_arms"))


# ------------------------------------------------------------------ Boss mondiali

func test_boss_mondiale_con_amici_piu_alleati_ma_con_tetto() -> void:
	var env: Object = _env()
	var d: Dictionary = env.combat.eg.world_bosses()[0].def
	var base := float(d.simulated_allies_dps_pct_of_hp_per_min) / 100.0 / 60.0
	assert_almost_eq(float(env.combat.eg._ally_per_s(d)), base, 1e-12, "senza amici: invariato")
	for i in 3:
		_befriend(env, 55, 6, "warrior", 1700400000 + i * 977)
	var with_f: float = env.combat.eg._ally_per_s(d)
	var cap_mult := float(DataRegistry.rules("coop_rules").world_boss.cap_mult)
	print("COOP_WB base %.6f con 3 amici %.6f" % [base, with_f])
	assert_gt(with_f, base, "gli amici aiutano")
	assert_lte(with_f, base * (1.0 + 3.0 * cap_mult) + 1e-12, "con il tetto per amico")


# ------------------------------------------------------------------ Breccia

func test_breccia_con_compagni_effetti_e_stima() -> void:
	var env: Object = _env(5, 100, 9)
	env.state.unlocks.append("feature:rift")
	var eg = env.combat.eg
	assert_true(env.coop.rift_fx(1).is_empty(), "senza compagni nessun effetto")
	var lim0: int = eg.rift_estimate_limit(1)
	_befriend(env, 100, 9, "warrior", 1700500000)
	_befriend(env, 100, 9, "ranger", 1700500777)
	var fx: Dictionary = env.coop.rift_fx(1)
	assert_false(fx.is_empty())
	assert_gt(float(fx.f), 0.0)
	assert_lte(float(fx.f), 1.5)
	eg.clear_rift_caches()
	env.combat._est_cache.clear()
	var lim1: int = eg.rift_estimate_limit(1)
	print("COOP_RIFT limite senza %d con 2 amici %d (f=%.3f)" % [lim0, lim1, float(fx.f)])
	assert_gte(lim1, lim0, "con gli amici si arriva almeno altrettanto in alto")
	# la corsa a tick funziona e usa gli effetti (nessun errore, piani superati)
	assert_true(eg.start_rift(1))
	env.tick(3000)
	assert_gte(int(env.combat.state.rift.best), 1)
	assert_gt(float(env.combat.eg.active_fx().get("f", 0.0)), 0.0, "gli effetti sono attivi nella Breccia a tick")
