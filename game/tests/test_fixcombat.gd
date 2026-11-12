extends GutTest
## FIX-COMBATTIMENTO (resoconto 65, rapporto QA4 54): morti offline con rinascita, Imboscata che non uccide,
## potenziamenti che non sostituiscono l'attacco, XP ridotta sui mostri molto più bassi, ibride, fasi del Custode.

const Env := preload("res://tests/helpers/combat2_env.gd")


func _env(lvl: int, cls: String = "warrior", tier: int = 1, zone: String = "millbrook", seed_v: int = 11) -> Object:
	var env: Object = Env.make(seed_v, lvl, cls)
	if tier > 0:
		env.gear(cls, tier)
	env.food()
	env.unlock_zone(zone)
	autofree(env.bus)
	return env


func test_offline_boss_letale_conta_le_morti_e_continua() -> void:
	# Regina Calabrone a Lv 3 senza equipaggiamento: ~10% di morte per scontro; nel tick l'Eroe cade e si rialza
	var env := _env(3, "warrior", 0)
	env.combat.start("millbrook", "hornet_queen")
	var rep: Dictionary = env.combat.simulate_offline(6.0 * 3600.0)
	assert_gt(int(rep.get("deaths", 0)), 2, "l'offline vede le morti (prima: 0 o una sola)")
	assert_gt(int(rep.get("kills", 0)), 0)
	assert_true(bool(rep.get("died", false)))
	assert_eq(str(rep.get("stopped", "")), "", "come il tick: l'Eroe si rialza e continua")
	assert_true(env.combat.in_combat())
	assert_eq(int(env.combat.state.deaths), int(rep.deaths))


func test_offline_estrema_si_ritira_prima_della_morte_attesa() -> void:
	var env := _env(3, "warrior", 0)
	env.state["mode"] = "extreme"
	env.combat.start("millbrook", "hornet_queen")
	var rep: Dictionary = env.combat.simulate_offline(6.0 * 3600.0)
	assert_eq(int(env.combat.state.deaths), 0, "Estrema: nessuna morte offline")
	assert_eq(str(rep.get("stopped", "")), "death_risk")


func test_misura_con_pesi_di_sopravvivenza_non_distorta() -> void:
	# stessa catena di scontri a vita piena: stima pesata e stima a esito binario devono coincidere entro il rumore
	var env := _env(3, "warrior", 0)
	var c: CombatSystem = env.combat
	var mon: Dictionary = DataRegistry.get_def("monsters", "hornet_queen")
	var ms := c._scaled(mon, 1)
	var st := c._stats_for(c.stance_for(mon))
	var p: Array = []
	for sv in [true, false]:
		c.est_surv = sv
		p.append(float(c._est_pass(mon, ms, st, {"chain": 1}, {"expect": false, "cycles": 200}).p_die))
	c.est_surv = true
	assert_gt(p[1], 0.04, "scenario davvero rischioso")
	assert_almost_eq(p[0], p[1], 0.08, "pesata %.3f vs binaria %.3f" % [p[0], p[1]])


func test_imboscata_non_uccide_mai() -> void:
	var rules: Dictionary = Formulas.k().combat.rules
	var saved: Dictionary = (rules.ambush as Dictionary).duplicate()
	rules.ambush["chance_pct"] = 100.0
	rules.ambush["min_interval_s"] = 0.0
	rules.ambush["dmg_mult"] = 500.0         # ogni colpo sarebbe letale
	var env := _env(12)
	env.combat.start("millbrook", "grey_wolf")
	env.tick(6000)
	rules["ambush"] = saved
	assert_eq(int(env.combat.state.deaths), 0, "l'Imboscata si ritira invece di uccidere")
	var fled := 0
	for e in env.combat.log_since(0):
		if str(e.k) == "ambush_fled":
			fled += 1
	assert_gt(fled, 0, "almeno una ritirata registrata")


func test_imboscata_premio_e_offline_atteso() -> void:
	var env := _env(15, "warrior", 2)
	env.combat.start("millbrook", "")
	var rep: Dictionary = env.combat.simulate_offline(4.0 * 3600.0)
	assert_gt(int(rep.get("ambushes", 0)), 0, "offline: imboscate in valore atteso")
	assert_lt(int(rep.get("ambushes", 0)), int(rep.kills) / 20, "poche: ~1 ogni 3+ minuti")
	var env2 := _env(5)
	env2.combat.start("millbrook", "")
	var rep2: Dictionary = env2.combat.simulate_offline(3600.0)
	assert_eq(int(rep2.get("ambushes", 0)), 0, "sotto il livello minimo niente imboscate")


func test_potenziamento_non_sostituisce_l_attacco() -> void:
	var kph: Array = []
	for ids in [[], ["battle_cry"]]:
		var env := _env(30, "warrior", 3, "ironroot")
		env.combat.build.set_auto_abilities(false)
		env.combat.state["abilities"] = ids
		env.combat.on_build_changed()
		var e: Dictionary = env.combat.estimate("cave_bat", true)
		kph.append(float(e.kills_per_h))
		if not ids.is_empty():
			assert_gt(float(e.casts), 0.0, "il Grido si lancia")
	assert_gt(kph[1], kph[0] * 1.01, "un potenziamento gratuito vale sempre qualcosa (%.0f vs %.0f)" % [kph[1], kph[0]])


func test_xp_ridotta_sui_mostri_molto_bassi() -> void:
	var env := _env(40, "warrior", 4)
	var low: Dictionary = DataRegistry.get_def("monsters", "mud_slime")
	var full := float(low.xp)
	assert_lt(env.combat.mon_xp(low, 1), full * 0.5, "Lv 40 contro un mostro di Valle: XP ridotta")
	assert_gte(env.combat.mon_xp(low, 1), full * 0.25 - 1e-6, "mai sotto il minimo")
	var env2 := _env(5)
	assert_almost_eq(env2.combat.mon_xp(low, 1), full, 1e-6, "nessuna riduzione nel distacco ammesso")


func test_ibride_crescono_come_le_classi_base() -> void:
	for hid in ["spellblade", "shadowstalker", "stormweaver"]:
		var cd: Dictionary = DataRegistry.get_def("classes", hid)
		for k in cd.primary_attrs:
			assert_almost_eq(float(cd.growth_per_level[k]), 1.0, 1e-9, "%s cresce di 1 in %s" % [hid, k])
		assert_gt(float(cd.passive.stat_mult), 1.0)


func test_custode_tre_fasi_tre_stili() -> void:
	for r in DataRegistry.table("raids"):
		var m: Dictionary = DataRegistry.get_def("monsters", str(r.boss))
		var styles := {}
		for ph in m.phases:
			styles[str(ph.style)] = true
		assert_eq(styles.size(), 3, "%s: ogni stile in svantaggio in una fase sola" % r.id)
