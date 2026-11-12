extends GutTest
## PrestigeSystem (docs/13): Stelle e Rito, Polvere, Costellazioni, Rifondazione, Consigliere, Grandi Obiettivi,
## reset sicuri (cosa si conserva), bonus asintotici, anteprima = risultato, round-trip del salvataggio.
## Usa BankSystem e SkillSystem VERI; la Tenuta è un finto sistema con le firme concordate (lifetime_units, reset_for_refounding).

const _GS := preload("res://src/autoload/GameState.gd")


class FakeEstate extends GameSystem:
	var units: float = 0.0
	var resets: int = 0
	func _init() -> void:
		id = "estate"
	func lifetime_units() -> float:
		return units
	func reset_for_refounding() -> void:
		resets += 1


func _world(with_estate: bool = false) -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(5), EventBus)
	var sim := Simulation.new()
	var list: Array = [BankSystem.new(), SkillSystem.new(), UnlockSystem.new()]
	var est: FakeEstate = null
	if with_estate:
		est = FakeEstate.new()
		list.append(est)
	var ps := PrestigeSystem.new()
	list.append(ps)
	sim.setup(ctx, list)
	sim.bind_state(state)
	return {"sim": sim, "ctx": ctx, "state": state, "ps": ps, "stack": stack, "bank": sim.get_system("bank"),
		"sk": sim.get_system("skills"), "estate": est}


## Azzera i Grandi Obiettivi (i test sulla sola Polvere delle Stelle non devono vedere i premi extra).
func _no_goals(w: Dictionary) -> void:
	for g in DataRegistry.constants.prestige.goals:
		w.state.prestige.goals[str(g.id)] = true


func _set_level(w: Dictionary, skill: String, lv: int) -> void:
	var st: Dictionary = w.state.skills[skill]
	st["level"] = lv
	st["record_level"] = maxi(int(st.record_level), lv)


func _xp_pct(w: Dictionary, skill: String) -> float:
	return (w.stack.total_more("skill_xp_pct", [skill]) - 1.0) * 100.0


# ------------------------------------------------------------------ Stelle e Rito

func test_stella_richiede_livello_100() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.can_star("woodcutting"), "UI_PRESTIGE_REASON_LEVEL")
	assert_false(ps.preview_star("woodcutting").ok)
	assert_eq(ps.do_star("woodcutting"), {}, "rifiutata: nulla cambia")
	assert_eq(w.sk.level("woodcutting"), 1)
	_set_level(w, "woodcutting", 99)
	assert_ne(ps.can_star("woodcutting"), "")
	_set_level(w, "woodcutting", 100)
	assert_eq(ps.can_star("woodcutting"), "")


func test_stella_reset_e_conservazioni() -> void:
	var w := _world()
	_no_goals(w)
	var ps: PrestigeSystem = w.ps
	_set_level(w, "woodcutting", 100)
	_set_level(w, "mining", 40)
	w.state.mastery["wc_pine"] = {"xp": 500.0, "level": 8}
	w.state.skills.woodcutting.perks = {"10": "a"}
	w.bank.add("log_pine", 25)
	var gold_before: int = w.bank.gold()
	var p := ps.do_star("woodcutting")
	assert_false(p.is_empty())
	assert_eq(w.sk.level("woodcutting"), 1, "livello torna a 1")
	assert_eq(w.sk.xp("woodcutting"), 0.0)
	assert_eq(w.sk.record_level("woodcutting"), 100, "il record resta (alimenta l'Eco)")
	assert_eq(ps.stars("woodcutting"), 1)
	assert_eq(w.state.skills.woodcutting.perks, {}, "talenti azzerati")
	assert_true(ps.has_perk_memory("woodcutting"), "ma ricordati")
	assert_eq(w.state.mastery["wc_pine"].level, 8, "maestria conservata")
	assert_eq(w.bank.count("log_pine"), 25, "oggetti conservati")
	assert_eq(w.bank.gold(), gold_before, "oro conservato")
	assert_eq(w.sk.level("mining"), 40, "altre mansioni intatte")
	assert_eq(w.bank.currency("stardust"), 10, "Polvere della prima stella")


func test_talenti_ricordati_si_riapplicano_con_un_clic() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	_set_level(w, "woodcutting", 100)
	var tier := int(DataRegistry.grouped("skill_perks", "woodcutting")[0].level)
	assert_true(w.sk.choose_perk("woodcutting", tier, "a"))
	ps.do_star("woodcutting")
	assert_eq(w.sk.chosen_letters("woodcutting", tier), "")
	_set_level(w, "woodcutting", tier)
	assert_eq(ps.reapply_perks("woodcutting"), 1)
	assert_eq(w.sk.chosen_letters("woodcutting", tier), "a")


func test_anteprima_uguale_al_risultato() -> void:
	var w := _world()
	_no_goals(w)
	var ps: PrestigeSystem = w.ps
	_set_level(w, "woodcutting", 100)
	for n in 3:
		_set_level(w, "woodcutting", 100)
		var p := ps.preview_star("woodcutting")
		var dust_before: int = w.bank.currency("stardust")
		var q := ps.do_star("woodcutting")
		assert_eq(q.dust_gain, p.dust_gain)
		assert_eq(w.bank.currency("stardust") - dust_before, int(p.dust_gain), "Polvere effettiva = anteprima")
		assert_almost_eq(_xp_pct(w, "woodcutting"), float(p.xp_after), 1e-4, "XP effettivo = anteprima")
		assert_almost_eq(w.stack.total_add("skill_haste_pct", ["woodcutting"]), float(p.haste_after), 1e-4, "velocità = anteprima")
		assert_eq(ps.stars("woodcutting"), int(p.stars_after))
	assert_eq(w.bank.currency("stardust"), 10 + 12 + 14, "Polvere 10 + 2(n-1)")


func test_bonus_stelle_asintotici() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var prev := 0.0
	var prev_step := 1e9
	for n in [1, 5, 10, 25, 100, 400]:
		var m := _by_key(ps.star_mods("woodcutting", n), "skill_xp_pct:woodcutting")
		assert_gt(float(m.value), prev, "cresce")
		assert_lt(float(m.value), 60.0, "mai oltre l'asintoto (cap 60%)")
		prev = float(m.value)
	# i passi si accorciano (curva concava): +1 stella vale sempre meno
	for n in range(1, 30):
		var a := float(_by_key(ps.star_mods("woodcutting", n), "skill_xp_pct:woodcutting").value)
		var b := float(_by_key(ps.star_mods("woodcutting", n + 1), "skill_xp_pct:woodcutting").value)
		assert_lt(b - a, prev_step + 1e-12)
		prev_step = b - a
	var hs := _by_key(ps.star_mods("woodcutting", 400), "skill_haste_pct:woodcutting")
	assert_lte(float(hs.value), 25.0)
	assert_almost_eq(float(hs.value), 25.0, 0.01)
	# valori attesi dalla formula dei docs: 1★ +4,8% XP, 10★ +33,9%
	assert_almost_eq(float(_by_key(ps.star_mods("woodcutting", 1), "skill_xp_pct:woodcutting").value), 4.8, 0.01)
	assert_almost_eq(float(_by_key(ps.star_mods("woodcutting", 10), "skill_xp_pct:woodcutting").value), 33.9, 0.05)


func _by_key(mods: Array, key: String) -> Dictionary:
	for m in mods:
		if m.key == key:
			return m
	return {}


func test_lineari_dell_eroe_e_traguardi() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var mods := ps.star_mods("hero", 4)
	assert_almost_eq(float(_by_key(mods, "combat_dmg_pct").value), 4.0, 1e-9, "lineare: +1% danno per stella")
	var w5 := ps.star_mods("woodcutting", 5)
	assert_false(_by_key(w5, "skill_secondary_pct:woodcutting").is_empty(), "traguardo 5 stelle")
	assert_true(_by_key(ps.star_mods("woodcutting", 4), "skill_secondary_pct:woodcutting").is_empty())
	# sblocchi dei traguardi: 1 stella = automazione
	_set_level(w, "woodcutting", 100)
	ps.do_star("woodcutting")
	assert_true(w.ctx.state.unlocks.has("automation:woodcutting"))


func test_rito_una_volta_per_mansione_a_livello_di_rito() -> void:
	var w := _world()
	_no_goals(w)
	var ps: PrestigeSystem = w.ps
	var rl := ps.rite_level()
	assert_eq(rl, int(DataRegistry.constants.prestige.rite_level))
	_set_level(w, "mining", rl - 1)
	assert_eq(ps.can_rite("mining"), "UI_PRESTIGE_REASON_RITE_LEVEL")
	_set_level(w, "mining", rl)
	assert_eq(ps.can_rite("mining"), "")
	var pv := ps.preview_star("mining", true)
	assert_eq(pv.kind, "rite")
	var p := ps.do_star("mining", true)
	assert_false(p.is_empty())
	assert_eq(ps.stars("mining"), 1, "il Rito vale una Stella")
	assert_eq(w.sk.level("mining"), 1)
	assert_eq(w.bank.currency("stardust"), int(pv.dust_gain), "stessa Polvere della prima Stella")
	_set_level(w, "mining", rl)
	assert_eq(ps.can_rite("mining"), "UI_PRESTIGE_REASON_RITE_DONE", "una sola volta")
	assert_eq(ps.do_star("mining", true), {})
	assert_eq(ps.preview_best("mining").kind, "star", "poi si mostra la Stella vera")


func test_star_gained_e_autosave() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var got: Array = []
	var cb := func(sk: String) -> void: got.append(sk)
	var imp: Array = []
	var cb2 := func(r: String) -> void: imp.append(r)
	EventBus.star_gained.connect(cb)
	EventBus.important_event.connect(cb2)
	_set_level(w, "woodcutting", 100)
	ps.do_star("woodcutting")
	EventBus.star_gained.disconnect(cb)
	EventBus.important_event.disconnect(cb2)
	assert_eq(got, ["woodcutting"])
	assert_true(imp.has("star"))


func test_stima_ore_di_ritorno_cala_con_le_stelle_ma_resta_alta() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	_set_level(w, "woodcutting", 100)
	var h1 := ps.estimate_return_hours("woodcutting", 1)
	var h2 := ps.estimate_return_hours("woodcutting", 2)
	var h50 := ps.estimate_return_hours("woodcutting", 50)
	assert_gt(h1, 6.0, "mai sotto il pavimento anti-fuga")
	assert_lt(h2, h1)
	assert_gt(h50, 6.0)
	assert_eq(ps.estimate_return_hours("hero", 1), -1.0, "l'Eroe non ha azioni")


# ------------------------------------------------------------------ Costellazioni

func test_nodo_costo_catena_e_modificatori() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.node_cost("c_vi_xp", 0), 5)
	assert_eq(ps.node_cost("c_vi_xp", 1), 7, "ceil(5*1.35)")
	assert_eq(ps.can_buy_node("c_vi_xp"), "UI_PRESTIGE_REASON_NO_DUST")
	assert_eq(ps.can_buy_node("c_vi_haste"), "UI_PRESTIGE_REASON_NODE_REQ")
	w.bank.add_currency("stardust", 100)
	assert_eq(ps.can_buy_node("c_vi_haste"), "UI_PRESTIGE_REASON_NODE_REQ", "serve il nodo precedente")
	var p := ps.preview_node("c_vi_xp", 3)
	assert_eq(p.cost, 5 + 7 + 10, "ceil(5*1.35^livello)")
	var r := ps.buy_node("c_vi_xp", 3)
	assert_eq(r.cost, p.cost, "anteprima = risultato")
	assert_eq(w.bank.currency("stardust"), 100 - int(p.cost))
	assert_eq(ps.node_level("c_vi_xp"), 3)
	assert_almost_eq(w.stack.total_more("skill_xp_pct", ["woodcutting", "all"]), pow(1.02, 3), 1e-9, "more composto per livello")
	assert_almost_eq(float(r.effect_after), (pow(1.02, 3) - 1.0) * 100.0, 1e-9)
	assert_eq(ps.can_buy_node("c_vi_haste"), "", "ora sbloccato")
	assert_true(ps.buy_node("c_vi_haste").has("cost"))
	assert_almost_eq(w.stack.total_add("skill_haste_pct", ["woodcutting", "all"]), 1.0, 1e-9, "add lineare")


func test_nodo_livello_massimo_e_nodi_infiniti() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	w.bank.add_currency("stardust", 10000000)
	assert_eq(ps.node_max_level("c_vi_xp"), 14)
	assert_eq(ps.max_buyable("c_vi_xp"), 14, "si ferma al massimo")
	ps.buy_node("c_vi_xp", 14)
	assert_eq(ps.can_buy_node("c_vi_xp"), "UI_PRESTIGE_REASON_NODE_MAX")
	assert_eq(ps.node_max_level("c_me_gold"), -1, "infinito")
	# costo esponenziale: effetto lineare, potere a crescita logaritmica
	var c10 := ps.node_cost("c_me_gold", 10)
	var c40 := ps.node_cost("c_me_gold", 40)
	assert_gt(c40, c10 * 1000, "il costo esplode molto prima dell'effetto")


func test_nessun_nodo_infinito_accelera_le_stelle() -> void:
	var ps := PrestigeSystem.new()
	for nd in DataRegistry.table("constellations"):
		var fam := str(nd.modifier_per_level.key).split(":")[0]
		if nd.max_level == null:
			assert_false(["skill_xp_pct", "skill_haste_pct", "skill_double_pct", "echo_mult_pct"].has(fam),
				"nodo senza limite che accelera le Stelle: " + str(nd.id))
	assert_not_null(ps)


func test_rimborso_gratis_poi_a_pagamento() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	w.bank.add_currency("stardust", 200)
	ps.buy_node("c_vi_xp", 4)
	var spent: int = w.state.prestige.stardust_spent
	assert_gt(spent, 0)
	var pv := ps.preview_respec()
	assert_true(pv.ok)
	assert_eq(pv.cost, 0, "il primo è gratis")
	var left: int = w.bank.currency("stardust")
	var r := ps.respec()
	assert_eq(r.refund, spent)
	assert_eq(w.bank.currency("stardust"), left + spent)
	assert_eq(ps.node_level("c_vi_xp"), 0)
	assert_almost_eq(w.stack.total_more("skill_xp_pct", ["woodcutting", "all"]), 1.0, 1e-9, "bonus tolti")
	assert_eq(w.state.prestige.stardust_spent, 0)
	# subito dopo: costa 50
	ps.buy_node("c_vi_xp", 2)
	assert_eq(ps.preview_respec().cost, 50)
	assert_gt(ps.respec_free_in(), 0.0)
	# passano 7 giorni di gioco (anche offline): di nuovo gratis
	ps.simulate_offline(7.0 * 86400.0 + 1.0)
	assert_eq(ps.respec_free_in(), 0.0)
	assert_eq(ps.preview_respec().cost, 0)


func test_rimborso_a_pagamento_senza_fondi() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	w.bank.add_currency("stardust", 5)
	ps.buy_node("c_vi_xp", 1)
	ps.respec()                                   # gratis
	w.bank.spend_currency("stardust", w.bank.currency("stardust"))
	w.bank.add_currency("stardust", 5)
	ps.buy_node("c_vi_xp", 1)
	assert_false(ps.preview_respec().ok, "50 Polvere che non hai")
	assert_eq(ps.respec(), {})
	assert_eq(ps.node_level("c_vi_xp"), 1)


func test_polvere_aumentata_dal_nodo_polvere() -> void:
	var w := _world()
	_no_goals(w)
	var ps: PrestigeSystem = w.ps
	w.ctx.modifiers.set_source("test", [{"key": "stardust_gain_pct", "value": 50.0, "mode": "add"}])
	_set_level(w, "woodcutting", 100)
	assert_eq(ps.preview_star("woodcutting").dust_gain, 15, "10 x 1,5")
	ps.do_star("woodcutting")
	assert_eq(w.bank.currency("stardust"), 15)


# ------------------------------------------------------------------ Rifondazione

func test_rifondazione_soci_e_reset() -> void:
	var w := _world(true)
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.can_refound(), "UI_PRESTIGE_REASON_ESTATE_UNITS")
	assert_eq(ps.do_refound(), {})
	w.estate.units = 50000.0
	var expected := Formulas.soci_total(50000.0)
	assert_eq(expected, 33, "floor(15 * sqrt(5))")
	var pv := ps.preview_refound()
	assert_true(pv.ok)
	assert_eq(pv.partners_gain, expected)
	var r := ps.do_refound()
	assert_eq(r.partners_gain, pv.partners_gain, "anteprima = risultato")
	assert_eq(ps.partners(), expected)
	assert_eq(w.estate.resets, 1, "Tenuta azzerata dal suo sistema")
	assert_almost_eq(w.stack.total_add("estate_prod_pct", []), 2.0 * float(expected), 1e-9, "+2% per Socio")
	# subito dopo non ci sono nuovi Soci; con più produzione solo la differenza
	assert_eq(ps.refound_gain(), 0)
	assert_ne(ps.can_refound(), "")
	w.estate.units = 200000.0
	assert_eq(ps.refound_gain(), Formulas.soci_total(200000.0) - expected)
	ps.do_refound()
	assert_eq(ps.partners(), Formulas.soci_total(200000.0))
	assert_eq(w.state.prestige.refoundings, 2)


func test_rete_di_soci_aumenta_i_soci_guadagnati() -> void:
	var w := _world(true)
	var ps: PrestigeSystem = w.ps
	w.estate.units = 50000.0
	w.ctx.modifiers.set_source("test", [{"key": "soci_gain_pct", "value": 50.0, "mode": "add"}])
	assert_eq(ps.refound_gain(), int(floor(33.0 * 1.5)))


func test_rifondazione_senza_sistema_tenuta_azzera_lo_stato_grezzo() -> void:
	var w := _world(false)
	var ps: PrestigeSystem = w.ps
	w.state.estate.prosperity = 50000.0
	w.state.estate.buildings = {"manor": {"level": 5}}
	assert_true(ps.preview_refound().ok)
	ps.do_refound()
	assert_eq(w.state.estate.buildings, {})
	assert_eq(w.state.estate.prosperity, 50000.0, "i punti prosperità (a vita) restano")


# ------------------------------------------------------------------ Consigliere, obiettivi, sblocchi

func test_sblocco_feature_prestige() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_false(w.ctx.state.unlocks.has("feature:prestige"))
	assert_eq(ps.advise().kind, "none")
	_set_level(w, "woodcutting", ps.rite_level() - 1)
	ps.simulate_offline(1.0)
	assert_false(w.ctx.state.unlocks.has("feature:prestige"))
	_set_level(w, "woodcutting", ps.rite_level())
	ps.simulate_offline(1.0)
	assert_true(w.ctx.state.unlocks.has("feature:prestige"), "mini-prestigio precoce: la voce di menù appare")


func test_consigliere_un_solo_suggerimento_in_ordine() -> void:
	var w := _world(true)
	var ps: PrestigeSystem = w.ps
	w.ctx.state.unlocks.append("feature:prestige")
	w.ctx.state.unlocks.append("feature:estate")
	assert_eq(ps.advise().kind, "none")
	assert_true(ps.advise().has("step_skill"), "dice almeno il passo più vicino")
	# polvere da spendere
	w.bank.add_currency("stardust", 50)
	assert_eq(ps.advise().kind, "node")
	# Rifondazione disponibile batte la Polvere
	w.estate.units = 50000.0
	assert_eq(ps.advise().kind, "refound")
	# il Rito batte la Rifondazione
	_set_level(w, "mining", 80)
	assert_eq(ps.advise().kind, "rite")
	assert_eq(ps.advise().skill, "mining")
	# la Stella batte il Rito
	_set_level(w, "woodcutting", 100)
	var a := ps.advise()
	assert_eq(a.kind, "star")
	assert_eq(a.skill, "woodcutting")
	assert_eq(a.dust, int(ps.preview_star("woodcutting").dust_gain), "il numero del consiglio è quello dell'anteprima")


func test_grandi_obiettivi_una_sola_volta() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	w.ctx.state.unlocks.append("feature:prestige")
	_set_level(w, "mining", ps.rite_level())
	ps.do_star("mining", true)
	var goal := {}
	for g in ps.goals():
		if g.id == "goal_rite":
			goal = g
	assert_true(goal.done)
	assert_eq(w.bank.currency("stardust"), 10 + 20 + 30, "Stella 10 + Rito 20 + prima Stella 30")
	ps.check_goals()
	ps.simulate_offline(5.0)
	assert_eq(w.bank.currency("stardust"), 60, "nessun doppione")
	assert_eq(ps.next_goal().id, "goal_stars_5", "il più vicino da raggiungere")


# ------------------------------------------------------------------ Ere e Prove (dettagli in test_eras_trials.gd)

func test_ere_base_custode() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.era_max(), 1)
	assert_false(ps.set_era(2))
	assert_eq(ps.on_warden_defeated(1), 5, "5 x era di Polvere alla prima uccisione")
	assert_eq(ps.era_max(), 2)
	assert_eq(ps.on_warden_defeated(1), 0, "la stessa Era non sblocca di nuovo e non ripaga la Polvere")
	assert_eq(ps.era_max(), 2)
	assert_true(ps.set_era(2))
	assert_eq(ps.era_current(), 2)
	assert_gt(ps.trial_ids().size(), 0)


# ------------------------------------------------------------------ salvataggio

func test_round_trip_salvataggio() -> void:
	var w := _world(true)
	var ps: PrestigeSystem = w.ps
	_set_level(w, "woodcutting", 100)
	_set_level(w, "mining", ps.rite_level())
	ps.do_star("woodcutting")
	ps.do_star("mining", true)
	w.bank.add_currency("stardust", 300)
	ps.buy_node("c_vi_xp", 5)
	ps.buy_node("c_me_gold", 3)
	w.estate.units = 60000.0
	ps.do_refound()
	var xp_before := _xp_pct(w, "woodcutting")
	var gold_more: float = w.stack.total_more("gold_gain_pct", ["all"])
	var prod: float = w.stack.total_add("estate_prod_pct", [])
	w.sim.collect_state(w.state)
	var bytes := SaveCodec.encode(w.state)
	var dec := SaveCodec.decode(bytes)
	assert_true(dec.ok)
	var errs := SaveCodec.normalize(dec.data, w.sim.int_paths())
	assert_eq(errs.size(), 0)
	# nuovo mondo dallo stato salvato
	var stack2 := ModifierStack.new()
	stack2.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx2 := SystemContext.make(DataRegistry, dec.data, stack2, RngStreams.new(5), EventBus)
	var sim2 := Simulation.new()
	var ps2 := PrestigeSystem.new()
	sim2.setup(ctx2, [BankSystem.new(), SkillSystem.new(), UnlockSystem.new(), FakeEstate.new(), ps2])
	sim2.bind_state(dec.data)
	assert_eq(ps2.stars("woodcutting"), 1)
	assert_eq(ps2.stars("mining"), 1)
	assert_true(ps2.rite_done("mining"))
	assert_eq(ps2.node_level("c_vi_xp"), 5)
	assert_eq(ps2.node_level("c_me_gold"), 3)
	assert_eq(ps2.partners(), ps.partners())
	assert_eq(ps2.dust(), ps.dust())
	assert_almost_eq(stack2.total_more("skill_xp_pct", ["woodcutting"]), w.stack.total_more("skill_xp_pct", ["woodcutting"]), 1e-9)
	assert_almost_eq((stack2.total_more("skill_xp_pct", ["woodcutting"]) - 1.0) * 100.0, xp_before, 1e-9)
	assert_almost_eq(stack2.total_more("gold_gain_pct", ["all"]), gold_more, 1e-9)
	assert_almost_eq(stack2.total_add("estate_prod_pct", []), prod, 1e-9)
	assert_eq(ps2.has_perk_memory("woodcutting"), ps.has_perk_memory("woodcutting"))
	assert_eq(dec.data.prestige.respec_last_s, w.state.prestige.respec_last_s)
	# obiettivi già riscossi: non si ripagano dopo il caricamento
	var dust_loaded := ps2.dust()
	ps2.check_goals()
	assert_eq(ps2.dust(), dust_loaded)


func test_salvataggio_vecchio_senza_campi_nuovi() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	# sezione "prestige" dei salvataggi precedenti: solo i campi di GameState.default_state
	var old := {"stardust": 0, "constellations": {}, "era_max": 3, "era_current": 2, "trials": {}}
	ps.from_state(old)
	assert_eq(ps.era_max(), 3)
	assert_eq(ps.era_current(), 2)
	assert_eq(old.partners, 0)
	assert_eq(old.rites, {})
	assert_eq(float(old.respec_last_s), -1.0)


# ------------------------------------------------------------------ in partita vera

func test_registrato_nel_gioco_e_con_la_schermata() -> void:
	var old_dir := SaveService.save_dir
	SaveService.save_dir = "user://test_prestige_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 9))
	var ps := Game.system("prestige") as PrestigeSystem
	assert_not_null(ps)
	var e := ScreenRegistry.get_entry("prestige")
	assert_true(ResourceLoader.exists(e.scene), "scena compilata")
	assert_false(ScreenRegistry.is_available(e, []), "bloccata prima di feature:prestige")
	assert_true(ScreenRegistry.is_available(e, ["feature:prestige"]))
	GameState.data.unlocks.append("feature:prestige")
	GameState.data.skills.woodcutting.level = 100
	GameState.data.skills.woodcutting.record_level = 100
	# GUILD-2: le imprese di livello 50/100 pagano Polvere Stellare e farebbero comparire subito le Costellazioni:
	# qui si vuole la schermata «a inizio partita», quindi il Compendio resta spento
	(Game.system("compendium") as CompendiumSystem).enabled = false
	var scr: GameScreen = (load(e.scene) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(1)
	scr.refresh()
	assert_eq(scr._tab_ids, ["star"], "all'inizio solo le Stelle: gli altri strati compaiono quando servono")
	# due passaggi: il primo clic arma, il secondo esegue
	scr._select_star("woodcutting")
	scr._on_star_confirm()
	assert_eq(ps.stars("woodcutting"), 0, "primo clic: nessun reset")
	assert_true(scr.is_armed("star:woodcutting"))
	scr._on_star_confirm()
	assert_eq(ps.stars("woodcutting"), 1, "secondo clic: Stella ottenuta")
	assert_eq(Game.system("skills").level("woodcutting"), 1)
	assert_false(scr.is_armed("star:woodcutting"))
	await wait_process_frames(1)
	scr.refresh()
	assert_true(scr._tab_ids.has("constellations"), "dopo la prima Stella compare l'albero")
	Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = old_dir
	SaveService.autosave_enabled = true


func test_mappa_costellazioni_disegna_e_seleziona() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var map := ConstellationMap.new()
	add_child_autofree(map)
	map.size = Vector2(700, 340)
	map.setup(ps)
	await wait_process_frames(1)
	var p := map.node_position("c_vi_haste")
	assert_ne(p, Vector2.ZERO)
	assert_eq(map.node_at(p), "c_vi_haste")
	assert_eq(map.node_at(Vector2(-500, -500)), "")
	watch_signals(map)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	map._gui_input(ev)
	assert_signal_emitted_with_parameters(map, "node_selected", ["c_vi_haste"])
	assert_eq(map.selected(), "c_vi_haste")
	assert_eq(map._rows.size(), 5, "5 costellazioni")
