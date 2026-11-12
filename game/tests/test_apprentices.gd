extends GutTest
## ApprenticeSystem (T-6.2): slot dall'Accademia, efficienza, produzione, ingredienti, offline vs tick, salvataggio.


func _fx(seed_value: int = 17) -> EstateFixtures:
	var f := EstateFixtures.make(seed_value)
	autofree(f.events)
	(f.state.unlocks as Array).append("skill:cooking")
	f.set_levels({"cottage": 10, "academy": 1})
	return f


func test_slot_ed_efficienza_dai_livelli() -> void:
	var f := _fx()
	assert_eq(f.apprentices.slots_total(), 1)
	assert_almost_eq(f.apprentices.efficiency(), 0.16, 1e-9, "15% + 1% per livello (dati)")
	f.estate.state.buildings.academy.level = 15
	assert_eq(f.apprentices.slots_total(), 2)
	f.estate.state.buildings.academy.level = 40
	assert_eq(f.apprentices.slots_total(), 3)
	assert_almost_eq(f.apprentices.efficiency(), 0.35, 1e-9, "tetto 35% (dati)")
	f.estate.state.buildings.academy.level = 90
	assert_almost_eq(f.apprentices.efficiency(), 0.35, 1e-9)
	f.mods.set_source("c", [{"key": "apprentice_slots", "value": 5, "mode": "add"}])
	assert_eq(f.apprentices.slots_total(), 5, "massimo 5 totali (cap del catalogo: +2)")  # 3 + 2 (cap)


func test_senza_accademia_nessuno_slot() -> void:
	var f := EstateFixtures.make()
	autofree(f.events)
	assert_eq(f.apprentices.slots_total(), 0)
	assert_false(f.apprentices.assign(0, "wc_pine"))


func test_assegnazione_regole() -> void:
	var f := _fx()
	assert_true(f.apprentices.assign(0, "wc_pine"))
	assert_eq(f.apprentices.slot_action(0), "wc_pine")
	assert_eq(f.apprentices.can_assign("wc_birch"), "UI_APPRENTICES_REASON_LEVEL", "livello richiesto 10")
	assert_eq(f.apprentices.can_assign("nonesiste"), "UI_APPRENTICES_REASON_UNKNOWN")
	assert_eq(f.apprentices.can_assign("mine_copper"), "", "Miniera sbloccata, livello 1")
	(f.state.unlocks as Array).erase("skill:mining")
	assert_eq(f.apprentices.can_assign("mine_copper"), "UI_APPRENTICES_REASON_LOCKED")
	assert_false(f.apprentices.assign(1, "wc_pine"), "slot inesistente")
	f.apprentices.unassign(0)
	assert_eq(f.apprentices.slot_action(0), "")


func test_produzione_xp_e_velocita() -> void:
	var f := _fx()
	assert_true(f.apprentices.assign(0, "wc_pine"))
	var hr: Dictionary = f.apprentices.hourly("wc_pine")
	var cyc := 3.0 / 0.16        # efficienza al livello 1: 0,15 + 0,01 (dati)
	assert_almost_eq(float(hr.cycles), 3600.0 / cyc, 0.01, "ciclo = durata / efficienza")
	var xp0: float = f.skills.xp("woodcutting")
	f.run(600.0, 0.1)
	var n_exp := 600.0 / cyc
	assert_almost_eq(float(f.bank.count("log_pine")), n_exp, 1.5)
	assert_almost_eq(f.skills.xp("woodcutting") - xp0, 7.0 * n_exp, 7.0 * 2.0, "XP intero per ciclo")


func test_ingredienti_e_blocco() -> void:
	var f := _fx()
	assert_true(f.apprentices.assign(0, "cook_bleak"))
	f.run(60.0, 0.5)
	assert_true(f.apprentices.slot_stalled(0), "senza pesce crudo si ferma")
	assert_eq(f.bank.count("food_bleak"), 0)
	f.bank.add("fish_raw_bleak", 20)
	f.run(120.0, 0.5)
	assert_gt(f.bank.count("food_bleak") + f.bank.count("burnt_food"), 0)
	assert_lt(f.bank.count("fish_raw_bleak"), 20, "consuma gli ingredienti")


func test_offline_coincide_col_tick() -> void:
	var a := _fx(3)
	var b := _fx(3)
	for f in [a, b]:
		f.apprentices.assign(0, "wc_pine")
	a.run(7200.0, 0.1)
	var rep: Dictionary = b.apprentices.simulate_offline(7200.0)
	var na: int = a.bank.count("log_pine")
	var nb: int = b.bank.count("log_pine")
	assert_gt(na, 350)
	assert_lt(absf(float(na - nb)) / float(na), 0.02, "tronchi: tick %d / offline %d" % [na, nb])
	var xa: float = a.skills.xp("woodcutting")
	var xb: float = b.skills.xp("woodcutting")
	assert_lt(absf(xa - xb) / xa, 0.02, "XP")
	assert_true(rep.has("items") and rep.has("xp"), "report per il Bentornato")


func test_salvataggio() -> void:
	var f := _fx()
	f.apprentices.assign(0, "wc_pine")
	f.run(5.0, 0.1)
	var snap: Variant = JSON.parse_string(JSON.stringify(f.apprentices.to_state()))
	var g := _fx()
	g.state["apprentices"] = snap
	g.apprentices.from_state(g.state["apprentices"])
	assert_eq(g.apprentices.slot_action(0), "wc_pine")
	assert_gt(g.apprentices.slot_progress(0), 0.0)
