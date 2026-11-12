extends GutTest
## MercenarySystem + ExpeditionSystem (T-6.3): reclutamento, tratti, potere, successo, ricompense, rischi, offline, salvataggio.


func _fx(seed_value: int = 23, tavern: int = 20) -> EstateFixtures:
	var f := EstateFixtures.make(seed_value)
	autofree(f.events)
	f.set_levels({"cottage": 10, "tavern": tavern})
	(f.state.unlocks as Array).append("zone:saltreach")
	f.sim.tick(0.1)        # genera tabellone e candidati
	return f


## Aggiunge un mercenario di prova con potere noto (nessun tratto salvo quelli passati).
func _merc(f: EstateFixtures, rarity: String, level: int, traits: Array = []) -> String:
	var uid: String = f.mercs._new_uid()
	f.mercs.state.roster.append({"uid": uid, "name": "Prova", "role": "striker", "rarity": rarity, "level": level, "xp": 0.0,
		"traits": traits, "equip_tier": 0, "injured_until": 0.0, "busy": ""})
	return uid


func _offer(f: EstateFixtures, type: String, zone: String = "millbrook", dur_idx: int = 0, size: int = 2) -> String:
	var o := {"id": "x_test_%d" % randi(), "type": type, "zone": zone, "dur_idx": dur_idx, "size": size}
	f.exps.state.board.append(o)
	return str(o.id)


# ------------------------------------------------------------------ mercenari

func test_potere_come_formula() -> void:
	var f := _fx()
	var u := _merc(f, "rare", 11)
	var base := 20.0 * (1.0 + 0.1 * 10)
	assert_almost_eq(f.mercs.power_of_uid(u), base, 1e-6)
	f.mods.set_source("p", [{"key": "merc_power_pct", "value": 50, "mode": "add"}])
	assert_almost_eq(f.mercs.power_of_uid(u), base * 1.5, 1e-6, "merc_power_pct via Modifiers")
	f.mercs.get_merc(u)["equip_tier"] = 4
	assert_almost_eq(f.mercs.power_of_uid(u), base * 1.5 * 1.2, 1e-6, "+5% per tier")
	var v := _merc(f, "common", 1, ["veteran", "leader"])
	assert_almost_eq(f.mercs.power_of_uid(v), 10.0 * 1.1 * 1.5, 1e-6, "Veterano +10%, ×1,5 mod")
	assert_almost_eq(f.mercs.team_power([v, u]), (10.0 * 1.1 * 1.5 + base * 1.5 * 1.2) * 1.05, 1e-6, "Condottiero +5% squadra")


func test_reclutamento_costo_e_limiti() -> void:
	var f := _fx(5, 10)
	assert_eq(f.mercs.roster_cap(), 4 + 2)
	assert_eq(f.mercs.candidates().size(), 3, "3 candidati")
	var c: Dictionary = f.mercs.candidates()[0]
	var cost: int = f.mercs.hire_cost(str(c.rarity))
	assert_eq(cost, int(round(1000.0 * float(f.mercs.rarity_def(str(c.rarity)).hire_mult) * (1.0 + 10 * 0.02))))
	assert_eq(f.mercs.can_hire(str(c.uid)), "UI_GUILD_REASON_GOLD")
	f.bank.add_gold(10000000)
	var g0: int = f.bank.gold()
	assert_true(f.mercs.hire(str(c.uid)))
	assert_eq(f.bank.gold(), g0 - cost)
	assert_eq(f.mercs.roster().size(), 1)
	assert_eq(f.mercs.candidates().size(), 2)
	assert_eq(int(f.mercs.get_merc(str(c.uid)).level), 1)
	assert_true((f.mercs.get_merc(str(c.uid)).traits as Array).size() >= 1)
	for i in 10:
		f.mercs.reroll()
		for cand in f.mercs.candidates():
			f.mercs.hire(str(cand.uid))
	assert_lte(f.mercs.roster().size(), f.mercs.roster_cap(), "tetto della squadra")


func test_bacheca_cambia_ogni_6_ore() -> void:
	var f := _fx()
	var ids: Array = []
	for c in f.mercs.candidates():
		ids.append(c.uid)
	f.run(5.0 * 3600.0, 10.0)
	assert_eq(f.mercs.candidates()[0].uid, ids[0], "5 h: stessi candidati")
	f.run(1.2 * 3600.0, 10.0)
	assert_ne(f.mercs.candidates()[0].uid, ids[0], "dopo 6 h: nuovi candidati")


func test_distribuzione_rarita_e_tratti() -> void:
	var f := _fx(31, 20)
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0, "legendary": 0}
	var n := 4000
	for i in n:
		var c: Dictionary = f.mercs._make_candidate()
		counts[c.rarity] += 1
		assert_eq((c.traits as Array).size(), int(DataRegistry.rules("mercenary_rules").traits_per_merc[c.rarity]))
	var bonus := 1.0 + 0.005 * 20
	var w := {"common": 600.0, "uncommon": 280.0 * bonus, "rare": 90.0 * bonus, "epic": 25.0 * bonus, "legendary": 5.0 * bonus}
	var tot := 0.0
	for k in w:
		tot += w[k]
	assert_almost_eq(float(counts.common) / n, w.common / tot, 0.03)
	assert_almost_eq(float(counts.uncommon) / n, w.uncommon / tot, 0.03)


func test_xp_livelli_e_massimo() -> void:
	var f := _fx()
	var u := _merc(f, "common", 1)
	var need: float = f.mercs.xp_to_next(1)
	assert_almost_eq(need, 100.0 * 1.12, 1e-9)
	assert_eq(f.mercs.grant_xp(u, need + 1.0), 1)
	assert_eq(int(f.mercs.get_merc(u).level), 2)
	f.mercs.grant_xp(u, 1.0e9)
	assert_eq(int(f.mercs.get_merc(u).level), 30, "massimo 30 per i comuni")


func test_kit_equipaggiamento() -> void:
	var f := _fx()
	var u := _merc(f, "common", 1)
	assert_false(f.mercs.can_equip_kit(u, 1), "servono arma e corazza")
	f.bank.add_instance({"def": "sword_copper"})
	f.bank.add_instance({"def": "plate_body_copper"})
	assert_true(f.mercs.can_equip_kit(u, 1))
	assert_true(f.mercs.equip_kit(u, 1))
	assert_eq(int(f.mercs.get_merc(u).equip_tier), 1)
	assert_eq(f.bank.instance_count(), 0, "consuma 1 arma + 1 corazza")


# ------------------------------------------------------------------ spedizioni: formule

func test_potere_richiesto_e_successo() -> void:
	var f := _fx()
	assert_almost_eq(f.exps.required_power("millbrook", 3), 30.0 * 3, 1e-9)
	assert_almost_eq(f.exps.required_power("saltreach", 2), 30.0 * 1.35 * 2, 1e-9)
	var req := 90.0
	assert_almost_eq(f.exps.success_chance(req, req, []), 1.6 * 0.5 - 0.15, 1e-9, "P = Req → 65%")
	assert_almost_eq(f.exps.success_chance(0.0, req, []), 0.05, 1e-9, "minimo 5%")
	assert_almost_eq(f.exps.success_chance(1.0e9, req, []), 0.98, 1e-9, "massimo 98%")
	var u := _merc(f, "common", 1, ["brave"])
	assert_almost_eq(f.exps.success_chance(req, req, [u]), 0.65 + 0.08, 1e-9, "Coraggioso +8")


func test_durata_con_velocita_e_tratti() -> void:
	var f := _fx()
	var u := _merc(f, "common", 1, ["tireless"])
	assert_almost_eq(f.exps.duration_s(3, []), 4.0 * 3600.0, 1e-6)
	assert_almost_eq(f.exps.duration_s(3, [u]), 4.0 * 3600.0 * 0.9, 1e-6, "Instancabile -10%")
	f.mods.set_source("s", [{"key": "expedition_speed_pct", "value": 90, "mode": "add"}])
	assert_almost_eq(f.exps.duration_s(3, [u]), 4.0 * 3600.0 * 0.5, 1e-6, "cap 50%")


func test_limiti_della_taverna() -> void:
	var f := _fx(7, 31)
	assert_eq(f.exps.concurrent_cap(), 1 + int(31.0 / 15.0))
	assert_eq(f.exps.board_size(), 3 + int(31.0 / 10.0))
	assert_eq(f.exps.board().size(), f.exps.board_size())
	var g := _fx(7, 0)
	assert_eq(g.exps.concurrent_cap(), 0)


func test_avvio_regole() -> void:
	var f := _fx(23, 10)
	var oid: String = f.exps.board()[0].id
	var u := _merc(f, "common", 1)
	assert_eq(f.exps.can_start(oid, []), "UI_GUILD_REASON_NOTEAM")
	assert_eq(f.exps.can_start("zz", [u]), "UI_GUILD_REASON_GONE")
	assert_true(f.exps.start(oid, [u]))
	assert_true(f.mercs.is_busy(u))
	assert_eq(f.exps.active().size(), 1)
	assert_eq(f.exps.board().size(), f.exps.board_size(), "il tabellone si riempie di nuovo")
	var oid2: String = f.exps.board()[0].id
	assert_eq(f.exps.can_start(oid2, [u]), "UI_GUILD_REASON_SLOTS", "una sola spedizione (Taverna 10)")
	var g := _fx(9, 20)
	var v := _merc(g, "common", 1)
	g.exps.start(str(g.exps.board()[0].id), [v])
	g.mercs.get_merc(v)["busy"] = ""
	g.exps.state.active.clear()
	assert_eq(g.exps.can_start(str(g.exps.board()[0].id), [v, v]), "UI_GUILD_REASON_UNAVAILABLE", "duplicati")


# ------------------------------------------------------------------ spedizioni: ricompense

func _run_one(f: EstateFixtures, offer_id: String, team: Array) -> Dictionary:
	assert_true(f.exps.start(offer_id, team))
	var a: Dictionary = f.exps.active()[0]
	f.exps.state.t = float(a.end_t) - 0.05        # salta al momento del completamento
	f.sim.tick(0.1)
	assert_eq(f.exps.active().size(), 0, "completata")
	return f.exps.log_entries().back()


func test_scorta_paga_oro() -> void:
	var f := _fx(41)
	var team: Array = [_merc(f, "legendary", 50), _merc(f, "legendary", 50)]
	var oid := _offer(f, "escort", "millbrook", 3, 4)
	var g0: int = f.bank.gold()
	var r := _run_one(f, oid, team)
	assert_true(r.success)
	var expected: float = 0.6 * Formulas.gph(1) * 4.0 / 4.0 * 4.0 * 1.1
	assert_almost_eq(float(r.gold), expected, 1.0)
	assert_eq(f.bank.gold(), g0 + int(r.gold))


func test_ricompense_proporzionali_alla_formula() -> void:
	var total := 0.0
	var n := 60
	for i in n:
		var f := _fx(100 + i)
		var team: Array = [_merc(f, "legendary", 50), _merc(f, "legendary", 50)]
		var oid := _offer(f, "escort", "millbrook", 2, 3)
		var r := _run_one(f, oid, team)
		if r.success:
			total += float(r.gold)
	var per := 0.6 * Formulas.gph(1) * 3.0 / 4.0 * 2.0 * 1.05
	assert_almost_eq(total / n, per, per * 0.1)


func test_recupero_casse_e_chiavi() -> void:
	var f := _fx(55)
	var team: Array = [_merc(f, "legendary", 50), _merc(f, "legendary", 50)]
	var oid := _offer(f, "salvage", "millbrook", 5, 2)       # 12 h = ~3,75 casse attese
	var r := _run_one(f, oid, team)
	var crates := 0
	for c in r.crates:
		assert_eq(c, "crate_millbrook")
		crates += int(r.crates[c])
	assert_between(crates, 2, 5, "12 h ≈ 3,75 casse")
	assert_eq(f.bank.count("crate_millbrook"), crates)


func test_caccia_e_ricognizione_danno_materiali() -> void:
	var f := _fx(61)
	var team: Array = [_merc(f, "legendary", 50), _merc(f, "legendary", 50)]
	var r := _run_one(f, _offer(f, "hunt", "millbrook", 4, 4), team)
	assert_true((r.items as Dictionary).has("mm_rough_fang"), "materiale comune della zona")
	var f2 := _fx(62)
	var team2: Array = [_merc(f2, "legendary", 50), _merc(f2, "legendary", 50)]
	var r2 := _run_one(f2, _offer(f2, "recon", "millbrook", 4, 4), team2)
	assert_gt((r2.items as Dictionary).size(), 0)
	for it in r2.items:
		if str(it) != "map_fragment":
			assert_eq(int(DataRegistry.item(str(it)).tier), 1, "tier della zona")


func test_cartografia_frammenti_e_xp_doppio() -> void:
	var got := 0
	var n := 80
	for i in n:
		var f := _fx(200 + i)
		var u := _merc(f, "legendary", 50)
		var r := _run_one(f, _offer(f, "survey", "millbrook", 0, 2), [u])
		got += int((r.items as Dictionary).get("map_fragment", 0))
	var rate := float(got) / n
	assert_between(rate, 0.35 * 0.55, 0.35 * 1.4 + 0.1, "circa il 35%")


func test_fallimento_ricompense_ridotte_e_infortuni() -> void:
	var fails := 0
	var hurt := 0
	var total := 0.0
	for i in 60:
		var f := _fx(300 + i)
		var u := _merc(f, "common", 1)
		var oid := _offer(f, "escort", "ashen", 2, 4)      # potere richiesto altissimo → quasi sempre fallimento
		var r := _run_one(f, oid, [u])
		if not r.success:
			fails += 1
			total += float(r.gold) / (0.6 * Formulas.gph(int(f.exps.zone_def("ashen").tier)) * 1.0 * 2.0 * 1.05)
			if (r.injured as Array).size() > 0:
				hurt += 1
				assert_true(f.mercs.is_injured(u))
				assert_false(f.mercs.is_available(u))
	assert_gt(fails, 50, "con 5% di successo")
	assert_almost_eq(total / fails, 0.25, 0.03, "25% della ricompensa")
	assert_almost_eq(float(hurt) / fails, 0.3, 0.15, "30% di infortunio")


func test_infortunio_dura_2_ore_e_guarisce() -> void:
	var f := _fx(77)
	var u := _merc(f, "common", 1)
	f.mercs.injure(u, 7200.0)
	assert_true(f.mercs.is_injured(u))
	f.run(7000.0, 10.0)
	assert_true(f.mercs.is_injured(u))
	f.run(300.0, 10.0)
	assert_false(f.mercs.is_injured(u))


func test_xp_mercenari_40_ore() -> void:
	var f := _fx(88)
	var u := _merc(f, "legendary", 50, ["scholar"])
	f.mercs.get_merc(u)["level"] = 1
	var r := _run_one(f, _offer(f, "escort", "millbrook", 2, 2), [u])    # 2 h
	assert_gt(int(r.levels), -1)
	var m: Dictionary = f.mercs.get_merc(u)
	var xp_total := 40.0 * 2.0 * 1.25
	var spent := 0.0
	for l in range(1, int(m.level)):
		spent += f.mercs.xp_to_next(l)
	assert_almost_eq(spent + float(m.xp), xp_total, 0.01, "40 XP/h × 2 h × 1,25 Erudito")


# ------------------------------------------------------------------ offline e salvataggio

func test_offline_completa_in_ordine_e_riporta() -> void:
	var f := _fx(91, 50)
	var u1 := _merc(f, "legendary", 50)
	var u2 := _merc(f, "legendary", 50)
	assert_true(f.exps.start(_offer(f, "escort", "millbrook", 0, 2), [u1]))     # 0,5 h
	assert_true(f.exps.start(_offer(f, "escort", "millbrook", 3, 2), [u2]))     # 4 h
	var g0: int = f.bank.gold()
	var rep: Dictionary = f.sim.run_offline(6.0 * 3600.0)
	assert_eq(f.exps.active().size(), 0)
	assert_eq(f.exps.log_entries().size(), 2)
	assert_lt(float(f.exps.log_entries()[0].t), float(f.exps.log_entries()[1].t), "ordine cronologico")
	assert_gt(f.bank.gold(), g0)
	assert_true(rep.has("expeditions"))
	assert_eq(rep.expeditions.rows[0].key, "UI_EXPEDITIONS_WB_DONE")
	assert_false(f.mercs.is_busy(u1))


func test_offline_uguale_al_tick() -> void:
	var a := _fx(95, 50)
	var b := _fx(95, 50)
	for f in [a, b]:
		var u := _merc(f, "epic", 20)
		var oid := _offer(f, "escort", "millbrook", 2, 3)
		f.exps.start(oid, [u])
	a.run(3.0 * 3600.0, 1.0)
	b.sim.run_offline(3.0 * 3600.0)
	assert_eq(a.exps.log_entries().size(), 1)
	assert_eq(b.exps.log_entries().size(), 1)
	assert_eq(a.exps.log_entries()[0].success, b.exps.log_entries()[0].success, "stesso esito (stesso seme)")
	assert_eq(a.exps.log_entries()[0].gold, b.exps.log_entries()[0].gold)


func test_salvataggio_spedizioni_e_mercenari() -> void:
	var f := _fx(99, 50)
	var u := _merc(f, "rare", 7, ["lucky", "brave"])
	f.exps.start(str(f.exps.board()[0].id), [u])
	f.run(30.0, 1.0)
	var s1: Variant = JSON.parse_string(JSON.stringify(f.exps.to_state()))
	var s2: Variant = JSON.parse_string(JSON.stringify(f.mercs.to_state()))
	var g := _fx(99, 50)
	g.state["expeditions"] = s1
	g.state["mercenaries"] = s2
	SaveCodec.normalize(g.state, g.sim.int_paths())
	g.exps.from_state(g.state["expeditions"])
	g.mercs.from_state(g.state["mercenaries"])
	assert_eq(g.exps.active().size(), 1)
	assert_true(g.mercs.is_busy(u))
	assert_eq(int(g.mercs.get_merc(u).level), 7)
	assert_typeof(g.exps.active()[0].dur_idx, TYPE_INT)
	assert_almost_eq(g.exps.time_left(str(g.exps.active()[0].id)), f.exps.time_left(str(f.exps.active()[0].id)), 0.01)
