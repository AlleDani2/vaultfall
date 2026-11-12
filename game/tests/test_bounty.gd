extends GutTest
## M7 (COMBAT-2): Caccia alle Taglie (bacheca, incarichi, Marchi, cambi, Ricercati, offline).

const Env := preload("res://tests/helpers/combat2_env.gd")


func _env(lvl: int = 20, bounty_lvl: int = 1) -> Object:
	var env: Object = Env.make(8, lvl, "warrior", true)
	env.gear("warrior", 3)
	env.food()
	env.unlock_zone("millbrook")
	env.skills.levels["bounty"] = bounty_lvl
	return env


func test_bacheca_con_tre_offerte_e_fasce_sbloccate() -> void:
	var env: Object = _env(20, 1)
	var offers: Array = env.bounty.offers()
	assert_eq(offers.size(), 3)
	for o in offers:
		assert_eq(o.tier, "easy", "con Taglie 1 solo la fascia Facile")
		var m: Dictionary = DataRegistry.get_def("monsters", str(o.monster))
		assert_lte(int(m.level), 20 + 5, "bersagli fino a livello Eroe + 5")
		assert_between(int(o.kills), 20, 60)
		assert_eq(int(o.marks), 1)
	var env2: Object = _env(40, 35)
	env2.unlock_zone("saltreach")
	env2.unlock_zone("ironroot")
	var tiers := {}
	for i in 12:
		env2.bounty.state["offers"] = []
		for o in env2.bounty.offers():
			tiers[o.tier] = true
	assert_true(tiers.has("medium"), "con Taglie 30+ compare la fascia Media")
	assert_false(tiers.has("hard"))


func test_accettare_e_completare_un_incarico() -> void:
	var env: Object = _env(25, 1)
	var evs: Array = []
	env.bus.objective_event.connect(func(k: String, pr: Dictionary) -> void: evs.append([k, pr]))
	env.bounty.offers()
	var target := ""
	env.bounty.state.offers[0]["monster"] = "mud_slime"
	env.bounty.state.offers[0]["kills"] = 4
	target = "mud_slime"
	assert_true(env.bounty.accept(0))
	assert_true(env.bounty.has_active())
	assert_eq(env.bounty.offers().size(), 3, "la bacheca si riempie di nuovo")
	assert_true(env.bounty.is_target(target))
	env.combat.start("millbrook", target)
	for i in 6000:
		env.sim.tick(FixedStepClock.STEP)
		if not env.bounty.has_active():
			break
	assert_false(env.bounty.has_active(), "incarico concluso")
	assert_eq(int(env.bounty.state.completed), 1)
	assert_gte(env.bank.count("bounty_mark"), 4, "1 Marchio per uccisione (Facile)")
	assert_gt(float(env.skills.xp.get("bounty", 0.0)), 0.0, "XP della mansione Taglie")
	assert_true(evs.has(["bounty_complete", {"qty": 1}]), "evento per le missioni")


func test_xp_per_uccisione_e_bonus_di_completamento() -> void:
	var env: Object = _env(25, 1)
	env.bounty.offers()
	env.bounty.state.offers[0]["monster"] = "mud_slime"
	env.bounty.state.offers[0]["kills"] = 2
	env.bounty.accept(0)
	var mon: Dictionary = DataRegistry.get_def("monsters", "mud_slime")
	var k: float = Formulas.k().combat.rules.bounty_xp_per_kill_mult
	env.bounty.on_kill("mud_slime", false, float(mon.xp))
	assert_almost_eq(float(env.skills.xp.bounty), float(mon.xp) * k, 1e-6)
	env.bounty.on_kill("mud_slime", false, float(mon.xp))
	var board: Dictionary = DataRegistry.table("bounty_board")[0]
	var total: float = 2.0 * float(mon.xp) * k
	assert_almost_eq(float(env.skills.xp.bounty), total * (1.0 + float(board.completion_bonus.xp_mult_of_task)), 1e-6, "+50% a fine incarico")


func test_cambi_gratuiti_poi_a_pagamento() -> void:
	var env: Object = _env()
	env.bounty.offers()
	var board: Dictionary = DataRegistry.table("bounty_board")[0]
	for i in int(board.free_rerolls_per_day):
		assert_eq(env.bounty.reroll_cost(0), 0)
		assert_true(env.bounty.reroll(0))
	assert_eq(env.bounty.free_rerolls_left(), 0)
	var cost: int = env.bounty.reroll_cost(0)
	assert_eq(cost, int(board.reroll_cost_gold_per_tier) * 1)
	assert_false(env.bounty.reroll(0), "senza oro")
	env.bank.gold_n = 1000
	assert_true(env.bounty.reroll(0))
	assert_eq(env.bank.gold_n, 1000 - cost)
	env.bounty._advance(float(Formulas.k().combat.rules.day_s) + 1.0)
	assert_eq(env.bounty.free_rerolls_left(), int(board.free_rerolls_per_day), "tornano gratis il giorno dopo")


func test_ricercato_piu_forte_e_ricompensa() -> void:
	var env: Object = _env(25, 1)
	env.bounty.offers()
	env.bounty.state.offers[0]["monster"] = "mud_slime"
	env.bounty.state.offers[0]["kills"] = 50
	env.bounty.accept(0)
	env.mods.set_source("t", [{"key": "bounty_wanted_chance_pct", "value": 100000, "mode": "add"}])
	assert_true(env.bounty.roll_wanted("mud_slime"), "con probabilità al massimo capita sempre")
	assert_false(env.bounty.roll_wanted("grey_wolf"), "solo il bersaglio dell'incarico")
	env.combat.start("millbrook", "mud_slime")
	var a: Dictionary = env.state.activity
	assert_true(env.combat._spawn(a))
	assert_true(a.enemy.wanted)
	var mon: Dictionary = DataRegistry.get_def("monsters", "mud_slime")
	var w: Dictionary = DataRegistry.table("bounty_board")[0].wanted_variant
	assert_almost_eq(float(a.enemy.max), float(mon.stats.hp) * float(w.hp_mult), 1e-6)
	assert_almost_eq(float(a.enemy.dmg_mult), float(w.dmg_mult), 1e-9)
	watch_signals(env.bus)
	var marks0: int = env.bank.count("bounty_mark")
	env.bounty.on_kill("mud_slime", true, 10.0)
	assert_eq(env.bank.count("bounty_mark") - marks0, 1 + int(w.marks), "Marchi base + 10 del Ricercato")
	assert_signal_emitted_with_parameters(env.bus, "crate_found", ["crate_bounty", "bounty:wanted"])


func test_danno_extra_contro_il_bersaglio() -> void:
	var env: Object = _env(25, 1)
	env.mods.set_source("t", [{"key": "combat_dmg_vs_bounty_pct", "value": 25, "mode": "add"}])
	var mon: Dictionary = DataRegistry.get_def("monsters", "mud_slime")
	var ms: Dictionary = env.combat._scaled(mon, 1)
	var st: Dictionary = env.combat._stats()
	var sim: CombatSim = CombatSim.new()
	sim.configure(env.combat._sim_params(st, mon, ms, true))
	var eff: Dictionary = sim.effective(env.state.hero.rt)
	var e1: Dictionary = sim.new_enemy(1.0, 1.0, false)
	var e2: Dictionary = sim.new_enemy(1.0, 1.0, true)
	assert_almost_eq(sim._common(eff, e2, "", 0.0) / sim._common(eff, e1, "", 0.0), 1.25, 1e-9)


func test_offline_conta_le_uccisioni_del_bersaglio() -> void:
	var env: Object = _env(25, 1)
	env.bounty.offers()
	env.bounty.state.offers[0]["monster"] = "mud_slime"
	env.bounty.state.offers[0]["kills"] = 40
	env.bounty.accept(0)
	env.combat.start("millbrook", "mud_slime")
	var rep: Dictionary = env.combat.simulate_offline(600.0)
	assert_gt(int(rep.kills), 40, "abbastanza uccisioni per chiudere l'incarico")
	assert_false(env.bounty.has_active(), "incarico completato offline")
	assert_eq(int(env.bounty.state.completed), 1)
	assert_gte(env.bank.count("bounty_mark"), 40)


func test_stato_salvabile_e_normalizzato() -> void:
	var env: Object = _env(25, 1)
	env.bounty.offers()
	env.bounty.accept(0)
	var copy: Dictionary = JSON.parse_string(JSON.stringify(env.bounty.state))
	var env2: Object = _env(25, 1)
	env2.bounty.from_state(copy)
	assert_true(env2.bounty.has_active())
	assert_eq(env2.bounty.offers().size(), 3)
