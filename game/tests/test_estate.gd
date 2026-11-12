extends GutTest
## EstateSystem (T-6.1/T-6.2): formule, produzione, coloni, Dispensa, Bottega, Rifondazione, offline vs tick, salvataggio.


func _fx(seed_value: int = 11) -> EstateFixtures:
	var f := EstateFixtures.make(seed_value)
	autofree(f.events)
	return f


# ------------------------------------------------------------------ formule

func test_unita_ora_come_formula() -> void:
	var f := _fx()
	f.set_levels({"cottage": 10, "sawmill": 30})
	var expected := Formulas.estate_units_per_hour(30)
	assert_almost_eq(f.estate.units_per_hour("sawmill"), expected, 1e-6, "30·L·2^traguardi")
	assert_eq(Formulas.estate_milestone_mult(30), 4, "traguardi 10 e 25")
	assert_eq(f.estate.units_per_hour("cottage"), 0.0, "il Casolare non produce")


func test_costi_come_formula() -> void:
	var f := _fx()
	var gb := float(f.estate.def_of("sawmill").cost.gold_base)
	var expected := Formulas.round_nice(gb * pow(1.11, 12) * pow(1.45, 1))
	assert_eq(f.estate.cost_at("sawmill", 12).gold, expected, "oro = round_nice(base·1,11^L·1,45^(banda−1))")
	var c0: Dictionary = f.estate.cost_at("sawmill", 0)
	assert_eq(c0.items.get("plank_pine"), 2, "assi: ceil(2 + 0,5·L)")
	assert_eq(c0.items.get("bar_copper"), 1, "lingotti: ceil(1 + 0,3·L)")
	var c20: Dictionary = f.estate.cost_at("sawmill", 20)
	assert_eq(c20.items.get("granite"), 4, "granito L//5 da L 15")
	var cw: Dictionary = f.estate.cost_at("warehouse", 9)
	var locks := 0
	for k in cw.items:
		if str(k).begins_with("padlock"):
			locks += 1
	assert_eq(locks, 1, "un lucchetto ogni 10 livelli (Magazzino)")


func test_riduzione_costi_con_cap() -> void:
	var f := _fx()
	var base: int = f.estate.cost_at("sawmill", 40).gold
	f.mods.set_source("t", [{"key": "estate_cost_reduction_pct", "value": 80, "mode": "add"}])
	var cut: int = f.estate.cost_at("sawmill", 40).gold
	assert_almost_eq(float(cut) / float(base), 0.5, 0.01, "cap 50%")


func test_capienza_e_posti() -> void:
	var f := _fx()
	f.set_levels({"cottage": 4, "warehouse": 10})
	assert_eq(f.estate.settler_cap(), 5 + 3 * 4)
	assert_almost_eq(f.estate.capacity(), 500.0 * pow(10.0, 1.2), 1e-6)


# ------------------------------------------------------------------ coloni

func test_coloni_arrivano_ogni_arrival_min() -> void:
	var f := _fx()
	var arrival_s := float(DataRegistry.rules("estate_rules").settlers.arrival_min) * 60.0
	f.set_levels({"cottage": 2}, 0)
	f.run(arrival_s, 1.0)
	assert_eq(f.estate.settlers(), 1)
	f.run(2.0 * arrival_s, 1.0)
	assert_eq(f.estate.settlers(), 3)
	f.run(36000.0, 10.0)
	assert_eq(f.estate.settlers(), f.estate.settler_cap(), "si fermano al limite del Casolare")


func test_ogni_livello_richiede_un_colono() -> void:
	var f := _fx()
	f.bank.add_gold(1000000)
	f.bank.add("plank_pine", 100)
	f.bank.add("bar_copper", 100)
	assert_true(f.estate.upgrade("cottage"), "il Casolare non usa coloni")
	assert_eq(f.estate.can_upgrade("sawmill"), "UI_ESTATE_REASON_SETTLERS")
	f.run(float(DataRegistry.rules("estate_rules").settlers.arrival_min) * 60.0 + 5.0, 1.0)   # un solo colono
	assert_eq(f.estate.can_upgrade("sawmill"), "")
	assert_true(f.estate.upgrade("sawmill"))
	assert_eq(f.estate.settlers_free(), 0)
	assert_false(f.estate.upgrade("sawmill"), "nessun colono libero")


func test_acquisto_scala_oro_e_materiali() -> void:
	var f := _fx()
	f.bank.add_gold(5000)
	f.bank.add("plank_pine", 10)
	f.bank.add("bar_copper", 10)
	var g0: int = f.bank.gold()
	var cost: Dictionary = f.estate.cost_of("cottage")
	assert_true(f.estate.upgrade("cottage"))
	assert_eq(f.bank.gold(), g0 - int(cost.gold))
	assert_eq(f.bank.count("plank_pine"), 10 - int(cost.items.plank_pine))
	assert_eq(f.estate.level_of("cottage"), 1)
	f.bank.spend_gold(f.bank.gold())
	assert_eq(f.estate.can_upgrade("cottage"), "UI_ESTATE_REASON_GOLD")


func test_edificio_non_sbloccato() -> void:
	var f := _fx()
	(f.state.unlocks as Array).erase("building:cottage")
	f.bank.add_gold(100000)
	assert_eq(f.estate.can_upgrade("cottage"), "UI_ESTATE_REASON_LOCKED")


func test_taverna_concede_feature_guild() -> void:
	var f := _fx()
	f.bank.add_gold(1000000)
	f.bank.add("plank_pine", 100)
	f.bank.add("bar_copper", 100)
	f.set_levels({"cottage": 5})
	f.estate.state.settlers = 3
	assert_false((f.state.unlocks as Array).has("feature:mercenaries"))
	assert_true(f.estate.upgrade("tavern"))
	assert_true((f.state.unlocks as Array).has("feature:mercenaries"), "la Gilda si apre con la Taverna")


# ------------------------------------------------------------------ produzione

func test_produzione_un_ora() -> void:
	var f := _fx()
	f.set_levels({"cottage": 20, "sawmill": 10, "warehouse": 5})
	var u: float = f.estate.units_per_hour("sawmill")
	f.run(3600.0, 1.0)
	var item: String = f.estate.product_of("sawmill")
	assert_eq(item, "log_pine", "senza mansione collegata al tier 1 il prodotto è il tronco di tier 1")
	assert_almost_eq(f.estate.stored(item), u, u * 0.001)
	assert_almost_eq(float(f.estate.state.prosperity), u, u * 0.001, "Punti Prosperità = unità prodotte")


func test_dispensa_vuota_riduce_la_produzione() -> void:
	var f := _fx()
	f.set_levels({"cottage": 2, "sawmill": 10, "warehouse": 20}, 11, 0.0)    # 11 coloni = limite del Casolare
	var u1: float = Formulas.estate_units_per_hour(10)
	var m := float(DataRegistry.rules("estate_rules").settlers.starving_mult)     # QA81: dai dati (0,75), non più 0,5
	f.run(3600.0, 1.0)
	var item: String = f.estate.product_of("sawmill")
	assert_almost_eq(f.estate.stored(item), u1 * m, u1 * 0.01, "Dispensa vuota: moltiplicatore dei dati")
	f.estate.state.storage = {}
	f.estate.state.pantry = 11.0   # 11 razioni = 1 ora per 11 coloni
	f.run(7200.0, 1.0)
	assert_almost_eq(f.estate.stored(item), u1 * (1.0 + m), u1 * 0.02, "1 ora piena + 1 ora a Dispensa vuota")
	assert_eq(f.estate.pantry(), 0.0)


func test_rifornire_la_dispensa_dal_deposito() -> void:
	var f := _fx()
	f.bank.add("food_bleak", 50)
	assert_eq(f.estate.stock_pantry("food_bleak", 30), 30)
	assert_eq(f.bank.count("food_bleak"), 20)
	assert_almost_eq(f.estate.pantry(), 30.0, 1e-9)
	assert_eq(f.estate.stock_pantry("log_pine", 1), 0, "solo cibo")


func test_magazzino_pieno_ferma_la_produzione() -> void:
	var f := _fx()
	f.set_levels({"cottage": 40, "sawmill": 100, "warehouse": 1})
	f.run(600.0, 1.0)
	assert_almost_eq(f.estate.stored_total(), 500.0, 0.5, "capienza 500·1^1,2")
	var pp: float = float(f.estate.state.prosperity)
	f.run(600.0, 1.0)
	assert_almost_eq(float(f.estate.state.prosperity), pp, 0.5, "pieno: niente Prosperità")


func test_raccolta_manuale_e_automatica() -> void:
	var f := _fx()
	f.set_levels({"cottage": 20, "sawmill": 10, "warehouse": 10})
	f.run(1800.0, 1.0)
	var item: String = f.estate.product_of("sawmill")
	var have := int(floor(f.estate.stored(item) + 1e-6))
	var got: Dictionary = f.estate.collect_all()
	assert_eq(int(got.get(item, 0)), have)
	assert_eq(f.bank.count(item), have)
	assert_lt(f.estate.stored(item), 1.0)
	f.mods.set_source("auto", [{"key": "estate_auto_collect", "value": 1, "mode": "add"}])
	f.run(1800.0, 1.0)
	assert_lt(f.estate.stored(item), 1.0, "raccolta automatica")
	assert_gte(f.bank.count(item), have * 2 - 1)


func test_bonus_via_modifiers() -> void:
	var f := _fx()
	f.set_levels({"cottage": 20, "sawmill": 10})
	var base: float = f.estate.units_per_hour("sawmill")
	f.mods.set_source("x", [{"key": "estate_prod_pct", "value": 50, "mode": "add"}])
	assert_almost_eq(f.estate.units_per_hour("sawmill"), base * 1.5, 1e-6)


func test_bottega_vende_con_tetto() -> void:
	var f := _fx()
	f.set_levels({"cottage": 60, "sawmill": 40, "shopfront": 5, "warehouse": 20})
	f.run(3600.0, 1.0)
	var cap: float = f.estate.shop_gold_cap_per_h()
	var gold: int = f.bank.gold()
	assert_gt(gold, 0)
	assert_lte(float(gold), cap * 1.01, "oltre 0,8·gph(tier) all'ora conta solo la Prosperità")
	f.estate.set_listed("log_pine", false)
	var g0: int = f.bank.gold()
	f.run(600.0, 1.0)
	assert_eq(f.bank.gold(), g0, "merce non in vendita: la Bottega non la vende")


func test_prodotto_limitato_da_tier_e_grado() -> void:
	var f := _fx()
	f.set_levels({"cottage": 20, "sawmill": 25})
	f.skills.state["woodcutting"]["level"] = 95
	f.skills.state["woodcutting"]["xp"] = float(f.skills._xp_cum[95])
	assert_eq(f.estate.tier_limit("sawmill"), 3, "grado dal livello dell'edificio: 25 → grado 3")
	var opts: Array = f.estate.product_options("sawmill")
	assert_eq(opts[0], "log_chestnut")
	assert_true(f.estate.set_product("sawmill", "log_birch"))
	assert_eq(f.estate.product_of("sawmill"), "log_birch")
	assert_false(f.estate.set_product("sawmill", "log_cedar"), "tier 4 oltre il grado")


# ------------------------------------------------------------------ Rifondazione

func test_rifondazione_soci() -> void:
	var f := _fx()
	f.set_levels({"cottage": 20, "sawmill": 10})
	f.estate.state.prosperity = float(f.estate.prestige_min_units()) - 1.0
	assert_false(f.estate.can_refound(), "servono i Punti della soglia dei dati (30.000)")
	f.estate.state.prosperity = 60000.0
	assert_true(f.estate.can_refound())
	var soci: int = f.estate.partners_pending()
	assert_eq(soci, int(floor(15.0 * sqrt(60000.0 / 10000.0))))
	var u0: float = f.estate.units_per_hour("sawmill")
	f.estate.state.storage = {"log_pine": 40.0}
	assert_true(f.estate.refound())
	assert_eq(f.estate.partners(), soci)
	assert_eq(f.estate.level_of("cottage"), 1, "il Casolare torna a 1")
	assert_eq(f.estate.level_of("sawmill"), 0)
	assert_eq(f.estate.settlers(), 0)
	assert_true((f.estate.state.storage as Dictionary).is_empty(), "il Magazzino si azzera")
	assert_almost_eq(float(f.estate.state.prosperity), 60000.0, 1e-6, "i Punti restano (statistiche a vita)")
	f.estate.state.buildings.sawmill.level = 10
	assert_almost_eq(f.estate.units_per_hour("sawmill"), u0 * (1.0 + 0.02 * soci), u0 * 0.001, "+2% per Socio")
	assert_false(f.estate.can_refound(), "nessun Socio nuovo")


func test_rifondazione_un_solo_ingresso_senza_doppio_conteggio() -> void:
	var f := _fx()
	f.set_levels({"cottage": 20, "sawmill": 10})
	f.estate.state.prosperity = 60000.0
	var u0: float = f.estate.units_per_hour("sawmill")
	assert_true(f.estate.refound(), "EstateScreen -> EstateSystem.refound() -> PrestigeSystem.do_refound()")
	var soci: int = f.prestige.partners()
	assert_gt(soci, 0)
	assert_eq(f.estate.partners(), soci, "la Tenuta legge i Soci da PrestigeSystem")
	assert_eq(int(f.estate.state.partners), 0, "nessun secondo contatore nella Tenuta")
	assert_true(f.mods.get_source("estate:partners").is_empty(), "nessuna fonte Soci della Tenuta")
	assert_eq(f.mods.get_source("prestige:partners").size(), 1, "una sola fonte di bonus Soci")
	f.estate.state.buildings.sawmill.level = 10
	assert_almost_eq(f.estate.units_per_hour("sawmill"), u0 * (1.0 + 0.02 * soci), u0 * 0.001, "+2% per Socio, una volta sola")
	# lo stesso punto di ingresso dalla schermata Prestigio: la stessa Rifondazione non si conta due volte
	assert_eq(f.prestige.do_refound(), {}, "nessun Socio nuovo")
	assert_eq(f.prestige.partners(), soci)
	assert_almost_eq(f.estate.units_per_hour("sawmill"), u0 * (1.0 + 0.02 * soci), u0 * 0.001)
	assert_eq(int(f.prestige.state.refoundings), 1)


func test_rete_di_soci_letta_dalla_tenuta() -> void:
	var f := _fx()
	f.estate.state.prosperity = 60000.0
	var base: int = f.estate.partners_pending()
	f.mods.set_source("rete", [{"key": "soci_gain_pct", "value": 100, "mode": "add"}])
	assert_eq(f.estate.partners_pending(), 2 * base, "Rete di Soci: +100% Soci dalla Rifondazione")
	assert_true(f.estate.refound())
	assert_eq(f.estate.partners(), 2 * base)


func test_soci_vecchio_salvataggio_assorbiti_non_sommati() -> void:
	var f := _fx()
	f.prestige.state["partners"] = 3
	f.prestige.state["partners_basis"] = 3
	f.estate.state["partners"] = 5          # contatore della Tenuta di un salvataggio precedente
	f.prestige.from_state(f.prestige.state)
	assert_eq(f.prestige.partners(), 5, "si tiene il maggiore, non la somma")
	assert_eq(int(f.estate.state.partners), 0)
	assert_eq(f.mods.get_source("prestige:partners")[0].value, 10.0)


# ------------------------------------------------------------------ offline vs tick

func _scenario(f: EstateFixtures) -> void:
	f.set_levels({"cottage": 30, "sawmill": 20, "mine_shaft": 12, "shopfront": 6, "warehouse": 3, "private_vault": 4},
		12, 14.0)     # Dispensa per ~1 h con 12 coloni: si svuota a metà prova
	f.estate.state.settlers = 12


func test_offline_coincide_col_tick() -> void:
	var a := _fx(5)
	var b := _fx(5)
	_scenario(a)
	_scenario(b)
	var secs := 1.75 * 3600.0
	a.run(secs, 0.1)
	b.sim.run_offline(secs)
	var pa := float(a.estate.state.prosperity)
	var pb := float(b.estate.state.prosperity)
	assert_gt(pa, 1000.0)
	assert_lt(absf(pa - pb) / pa, 0.02, "Prosperità: scarto ≤ 2%% (tick %s / offline %s)" % [pa, pb])
	assert_lt(absf(a.estate.stored_total() - b.estate.stored_total()) / maxf(1.0, a.estate.stored_total()), 0.02, "Magazzino")
	assert_lt(absf(float(a.bank.gold()) - float(b.bank.gold())) / maxf(1.0, float(a.bank.gold())), 0.02, "oro Bottega")
	assert_eq(a.estate.settlers(), b.estate.settlers())
	assert_almost_eq(a.estate.pantry(), b.estate.pantry(), 0.01)


func test_perf_offline_24_ore_veloce() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	var f0 := PerfGate.load_factor()
	var ms := INF
	var rep: Dictionary = {}
	for k in 3:          # migliore di 3, ogni volta con una Tenuta nuova
		var f := _fx(9)
		_scenario(f)
		var t0 := PerfGate.clock_usec()
		rep = f.sim.run_offline(24.0 * 3600.0)
		ms = minf(ms, (PerfGate.clock_usec() - t0) / 1000.0)
	PerfGate.assert_time(self, "Tenuta: 24 h offline (migliore di 3)", ms, 1000.0, PerfGate.factor_around(f0))
	assert_true(rep.has("estate"))
	assert_true(rep.estate.has("rows"))


func test_report_offline_ha_stop_dispensa() -> void:
	var f := _fx(3)
	f.set_levels({"cottage": 10, "sawmill": 5}, 8, 2.0)
	var rep: Dictionary = f.estate.simulate_offline(2.0 * 3600.0)
	assert_eq(rep.stop.key, "UI_ESTATE_WB_PANTRY")


func test_report_offline_dice_quando_il_magazzino_pieno_ha_fermato_la_produzione() -> void:
	# QA120: senza Bottega e senza raccolta, il Magazzino si riempie e la produzione si ferma: il Bentornato deve dirlo
	var f := _fx(3)
	f.set_levels({"cottage": 10, "sawmill": 10}, 8, 100000.0)
	var rep: Dictionary = f.estate.simulate_offline(24.0 * 3600.0)
	assert_true(f.estate.stored_total() >= f.estate.capacity() - 1.0, "il Magazzino e' pieno")
	var keys: Array = []
	for r in rep.get("rows", []):
		keys.append(str(r.key))
	assert_true(keys.has("UI_QA120_ESTATE_FULL"), "riga «Magazzino pieno» nel Bentornato: %s" % str(keys))
	# una breve assenza che non riempie il Magazzino non la mostra
	var g := _fx(3)
	g.set_levels({"cottage": 10, "sawmill": 10}, 8, 100000.0)
	var rep2: Dictionary = g.estate.simulate_offline(300.0)
	for r in rep2.get("rows", []):
		assert_ne(str(r.key), "UI_QA120_ESTATE_FULL")


# ------------------------------------------------------------------ caveau privato

func test_caveau_privato_genera_casse() -> void:
	var f := _fx(21)
	f.set_levels({"cottage": 5, "private_vault": 10})
	var interval: float = 8.0 * 3600.0 / (1.0 + 0.05 * 10)
	assert_almost_eq(f.estate.vault_interval_s(), interval, 1e-6)
	f.run(interval * 3.0 + 10.0, 10.0)
	assert_eq(int(f.estate.state.stats.crates), 3)
	assert_eq(f.bank.count("crate_millbrook"), 3, "solo le zone sbloccate (Valle del Mulino)")


# ------------------------------------------------------------------ salvataggio

func test_salvataggio_andata_e_ritorno() -> void:
	var f := _fx(4)
	_scenario(f)
	f.run(900.0, 1.0)
	var snap: Variant = JSON.parse_string(JSON.stringify(f.estate.to_state()))
	var g := _fx(4)
	g.state["estate"] = snap
	SaveCodec.normalize(g.state, g.sim.int_paths())
	g.estate.from_state(g.state["estate"])
	assert_eq(g.estate.level_of("sawmill"), 20)
	assert_eq(g.estate.settlers(), f.estate.settlers())
	assert_almost_eq(float(g.estate.state.prosperity), float(f.estate.state.prosperity), 1e-6)
	assert_typeof(g.estate.state.settlers, TYPE_INT)
	g.run(60.0, 1.0)
	assert_gt(float(g.estate.state.prosperity), float(f.estate.state.prosperity))


func test_eventi_di_colore() -> void:
	var f := _fx(8)
	f.set_levels({"cottage": 5, "sawmill": 3}, 5, 500.0)
	f.estate.simulate_offline(24.0 * 3600.0)
	assert_gt(int(f.estate.state.events.count), 5, "circa uno ogni 90 min")
	assert_lte((f.estate.event_log() as Array).size(), 12)
	for e in f.estate.event_log():
		assert_ne(TranslationServer.translate("UI_ESTATE_EV_" + str(e.id).to_upper()), "UI_ESTATE_EV_" + str(e.id).to_upper(), "testo mancante: " + str(e.id))
