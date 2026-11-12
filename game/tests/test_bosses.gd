extends GutTest
## M7 (COMBAT-2): meccaniche dei boss lette da data/boss_mechanics.json (non più dai valori fissi di PENDING) e DoT, spine,
## colpo multiplo, rubavita, resistenza agli stati.

const Env := preload("res://tests/helpers/combat2_env.gd")


func _arena(env: Object, mon_id: String, expect: bool = true, enemy_hp: float = 1.0e9) -> Dictionary:
	var mon: Dictionary = DataRegistry.get_def("monsters", mon_id)
	var ms: Dictionary = env.combat._scaled(mon, 1)
	var st: Dictionary = env.combat._stats_for(env.combat.stance_for(mon))
	var sim: CombatSim = CombatSim.new()
	sim.configure(env.combat._sim_params(st, mon, ms, expect))
	if not expect:
		sim.rng = env.combat.ctx.rng
	var a := {"type": "combat", "enemy": {}, "hero_cd": 1.0e9, "mon_cd": 1.0e9}
	sim.spawn(env.combat.state, a)
	a.enemy["hp"] = enemy_hp
	a.enemy["max"] = enemy_hp
	a["hero_cd"] = 1.0e9
	a["mon_cd"] = 1.0e9
	return {"sim": sim, "a": a, "h": env.combat.state, "mon": mon, "ms": ms, "st": st}


func _step(ar: Dictionary, n: int = 1) -> int:
	var r := 0
	for i in n:
		(ar.sim as CombatSim).tick_timers(ar.h, FixedStepClock.STEP, true)
		r = (ar.sim as CombatSim).step(ar.h, ar.a, FixedStepClock.STEP)
	return r


func _hero(lvl: int = 90, tier: int = 9, cls: String = "warrior") -> Object:
	var env: Object = Env.make(6, lvl, cls)
	env.gear(cls, tier)
	env.combat.state["hp"] = env.combat.max_hp()
	return env


func test_dati_delle_meccaniche_completi_e_usati_dai_mostri() -> void:
	var table: Array = DataRegistry.table("boss_mechanics")
	assert_eq(table.size(), 7)
	var ids := {}
	for m in table:
		ids[str(m.id)] = true
		assert_true(m.has("trigger") and m.has("effect") and m.has("name") and m.has("desc"))
	for mon in DataRegistry.table("monsters"):
		for mid in mon.get("mechanics", []):
			assert_true(ids.has(str(mid)), "meccanica nota: %s (%s)" % [mid, mon.id])
	assert_true(_hero(10, 1).combat.mechanics().has("summon_adds"))


func test_colpo_devastante_ogni_15_secondi_dai_dati() -> void:
	var env: Object = _hero()
	var ar := _arena(env, "hornet_queen", false)
	var count := [0]
	(ar.sim as CombatSim).sink = func(e: Dictionary) -> void:
		if str(e.k) == "heavy":
			count[0] += 1
	var every := float(DataRegistry.get_def("boss_mechanics", "heavy_blow").trigger.every_s)
	_step(ar, int(every / FixedStepClock.STEP) - 2)
	assert_eq(count[0], 0)
	_step(ar, 4)
	assert_eq(count[0], 1, "primo colpo a ~15 s")
	_step(ar, int(every / FixedStepClock.STEP))
	assert_eq(count[0], 2)
	# il valore viene dai dati, non dal codice: cambiandolo cambia il ritmo
	var m: Dictionary = DataRegistry.get_def("boss_mechanics", "heavy_blow")
	m.trigger["every_s"] = 5.0
	var ar2 := _arena(env, "hornet_queen", false)
	var c2 := [0]
	(ar2.sim as CombatSim).sink = func(e: Dictionary) -> void:
		if str(e.k) == "heavy":
			c2[0] += 1
	_step(ar2, 205)
	m.trigger["every_s"] = every
	assert_eq(c2[0], 4)


func test_nube_tossica_danneggia_nel_tempo_e_si_resiste() -> void:
	var env: Object = _hero()
	var ar := _arena(env, "spider_matriarch")
	var fx: Dictionary = DataRegistry.get_def("boss_mechanics", "poison_cloud").effect
	var every := float(DataRegistry.get_def("boss_mechanics", "poison_cloud").trigger.every_s)
	var mx: float = env.combat.max_hp()
	_step(ar, int(every / FixedStepClock.STEP) + 1)
	assert_gt(float(ar.a.enemy.poison_s), 0.0)
	var hp0 := float(env.combat.state.hp)
	_step(ar, int(float(fx.duration_s) / FixedStepClock.STEP) + 2)
	var lost := hp0 - float(env.combat.state.hp)
	var resist: float = ar.st.status_resist
	assert_almost_eq(lost, mx * float(fx.dot_pct_max_hp) / 100.0 * float(fx.duration_s) * (1.0 - resist), mx * 0.01)
	# con resistenza agli stati il danno cala
	var env2: Object = _hero()
	env2.mods.set_source("t", [{"key": "combat_status_resist_pct", "value": 50, "mode": "add"}])
	var ar2 := _arena(env2, "spider_matriarch")
	_step(ar2, int(every / FixedStepClock.STEP) + 1)
	var hpa := float(env2.combat.state.hp)
	_step(ar2, int(float(fx.duration_s) / FixedStepClock.STEP) + 2)
	assert_lt(hpa - float(env2.combat.state.hp), lost * 0.7)


func test_barriera_riduce_i_danni_subiti_dal_boss() -> void:
	var env: Object = _hero(50, 6)
	env.combat.build.set_auto_abilities(false)
	env.combat.state["abilities"] = []
	var ar := _arena(env, "ironroot_golem")
	var sim: CombatSim = ar.sim
	var eff: Dictionary = sim.effective(env.combat.state.rt)
	var e: Dictionary = ar.a.enemy
	var base: float = sim._common(eff, e, "", 0.0)
	e["shield_s"] = 5.0
	var shielded: float = sim._common(eff, e, "", 0.0)
	var fx: Dictionary = DataRegistry.get_def("boss_mechanics", "shield_phase").effect
	assert_almost_eq(shielded / base, 1.0 + float(fx.dmg_taken_pct) / 100.0, 1e-9)
	var every := float(DataRegistry.get_def("boss_mechanics", "shield_phase").trigger.every_s)
	_step(ar, int(every / FixedStepClock.STEP) + 1)
	assert_gt(float(e.shield_s), 0.0, "la Barriera scatta ogni 30 s")


func test_stordimento_ritarda_l_eroe_e_scala_con_la_resistenza() -> void:
	var env: Object = _hero()
	var ar := _arena(env, "ice_jarl")
	var every := float(DataRegistry.get_def("boss_mechanics", "stun").trigger.every_s)
	var stun := float(DataRegistry.get_def("boss_mechanics", "stun").effect.stun_s)
	ar.a["hero_cd"] = 1000.0
	_step(ar, int(every / FixedStepClock.STEP) - 1)
	var before := float(ar.a.hero_cd)
	_step(ar, 2)
	assert_almost_eq(float(ar.a.hero_cd), before - 2.0 * FixedStepClock.STEP + stun * (1.0 - float(ar.st.status_resist)), 1e-6)


func test_richiamo_dei_servitori_al_50_per_cento() -> void:
	var env: Object = _hero()
	var ar := _arena(env, "captain_saltgrin", true, 1000.0)
	var e: Dictionary = ar.a.enemy
	_step(ar, 3)
	assert_true((e.adds as Array).is_empty())
	e["hp"] = 400.0
	_step(ar, 2)
	assert_eq((e.adds as Array).size(), int(DataRegistry.get_def("boss_mechanics", "summon_adds").effect.summon))
	assert_true(e.adds_done)
	var fx: Dictionary = DataRegistry.get_def("boss_mechanics", "summon_adds").effect
	assert_almost_eq(float(e.adds[0].hp), 1000.0 * float(fx.hp_pct_of_boss) / 100.0, 1e-6)
	# il danno va prima ai servitori
	var hp_boss := float(e.hp)
	ar.sim._hit_enemy(e, 10.0, false)
	assert_almost_eq(float(e.hp), hp_boss, 1e-9)
	assert_lt(float(e.adds[0].hp), 50.0)
	# solo una volta
	e["hp"] = 100.0
	_step(ar, 5)
	assert_eq((e.adds as Array).size(), 2)


func test_prosciugamento_cura_il_boss() -> void:
	var env: Object = _hero(60, 7)
	var ar := _arena(env, "gall_witch", true, 1000.0)
	var e: Dictionary = ar.a.enemy
	e["hp"] = 500.0
	ar.a["mon_cd"] = 0.0
	_step(ar)
	assert_gt(float(e.hp), 500.0, "il boss si cura col danno inflitto")


func test_furia_sotto_la_soglia() -> void:
	var env: Object = _hero(70, 8)
	var ar := _arena(env, "ice_jarl", true, 1000.0)
	var sim: CombatSim = ar.sim
	var e: Dictionary = ar.a.enemy
	var iv0: float = sim._mon_interval(e)
	var thr := float(DataRegistry.get_def("boss_mechanics", "enrage").trigger.hp_below_pct)
	e["hp"] = 1000.0 * (thr - 1.0) / 100.0
	var iv1: float = sim._mon_interval(e)
	var fx: Dictionary = DataRegistry.get_def("boss_mechanics", "enrage").effect
	assert_almost_eq(iv0 / iv1, 1.0 + float(fx.haste_pct) / 100.0, 1e-9)
	# danno +40%
	var h: Dictionary = env.combat.state
	var eff: Dictionary = sim.effective(h.rt)
	e["hp"] = 1000.0
	h["hp"] = 1.0e9
	h["rt"]["shield"] = 0.0
	sim.acc = {"swings": 0.0, "hits": 0.0, "dmg_in": 0.0, "heal": 0.0, "casts": 0.0, "food": 0.0, "time": 0.0}
	sim._mon_swing(h, e, eff, 1.0, ar.mon)
	var normal := float(sim.acc.dmg_in)
	e["hp"] = 1000.0 * (thr - 1.0) / 100.0
	sim.acc["dmg_in"] = 0.0
	sim._mon_swing(h, e, eff, 1.0, ar.mon)
	assert_almost_eq(float(sim.acc.dmg_in) / normal, 1.0 + float(fx.dmg_pct) / 100.0, 1e-9)


# ------------------------------------------------------------------ spine, rubavita, colpo multiplo

func test_spine_rimandano_il_danno_all_attaccante() -> void:
	var env: Object = _hero(30, 3)
	env.mods.set_source("t", [{"key": "combat_thorns_pct", "value": 20, "mode": "add"}])
	var ar := _arena(env, "mud_slime", true, 1.0e6)
	var sim: CombatSim = ar.sim
	var e: Dictionary = ar.a.enemy
	sim.acc = {"swings": 0.0, "hits": 0.0, "dmg_in": 0.0, "heal": 0.0, "casts": 0.0, "food": 0.0, "time": 0.0}
	var eff: Dictionary = sim.effective(env.combat.state.rt)
	sim._mon_swing(env.combat.state, e, eff, 1.0, ar.mon)
	var taken := float(sim.acc.dmg_in)
	assert_gt(taken, 0.0)
	assert_almost_eq(1.0e6 - float(e.hp), taken * 0.20, taken * 0.001)


func test_rubavita_e_tetto() -> void:
	var env: Object = _hero(30, 3)
	env.mods.set_source("t", [{"key": "combat_lifesteal_pct", "value": 99, "mode": "add"}])
	assert_almost_eq(float(env.combat.hero_stats().lifesteal), float(Formulas.k().combat.rules.lifesteal_cap_pct) / 100.0, 1e-9, "tetto 25%")
	env.mods.set_source("t", [{"key": "combat_multihit_pct", "value": 90, "mode": "add"}])
	assert_almost_eq(float(env.combat.hero_stats().multihit), float(Formulas.k().combat.rules.multihit_cap_pct) / 100.0, 1e-9, "tetto 50%")


func test_colpo_multiplo_aumenta_i_colpi() -> void:
	var env: Object = _hero(30, 3)
	var ar := _arena(env, "mud_slime", true, 1.0e6)
	var sim: CombatSim = ar.sim
	var eff: Dictionary = sim.effective(env.combat.state.rt)
	var e: Dictionary = ar.a.enemy
	sim._hero_swing(env.combat.state, ar.a, e, eff)
	var d1 := 1.0e6 - float(e.hp)
	var env2: Object = _hero(30, 3)
	env2.mods.set_source("t", [{"key": "combat_multihit_pct", "value": 40, "mode": "add"}])
	var ar2 := _arena(env2, "mud_slime", true, 1.0e6)
	var sim2: CombatSim = ar2.sim
	var e2: Dictionary = ar2.a.enemy
	sim2._hero_swing(env2.combat.state, ar2.a, e2, sim2.effective(env2.combat.state.rt))
	assert_almost_eq((1.0e6 - float(e2.hp)) / d1, 1.4, 1e-6)


func test_revive_once() -> void:
	var env: Object = _hero(30, 3)
	env.mods.set_source("t", [{"key": "combat_revive_once", "value": 1, "mode": "add"}])
	assert_true(env.combat.hero_stats().revive_once)
	var ar := _arena(env, "mud_slime", false, 1.0e6)
	var sim: CombatSim = ar.sim
	env.combat.state["hp"] = -5.0
	assert_true(sim._revive_if_possible(env.combat.state))
	assert_almost_eq(float(env.combat.state.hp), env.combat.max_hp() * 0.3, 1e-6)
	env.combat.state["hp"] = -5.0
	assert_false(sim._revive_if_possible(env.combat.state), "una sola volta per scontro")


func test_boss_di_zona_in_gioco_con_tutte_le_meccaniche_ricompensa_e_morte() -> void:
	# un boss con Colpo Devastante, Nube Tossica e servitori viene battuto da un eroe forte (tick completo)
	var env: Object = _hero(60, 7)
	env.food()
	env.unlock_zone("whisperwood")
	assert_true(env.combat.start("whisperwood", "spider_matriarch"))
	var killed := [false]
	var cb := func(m: String, _d: Array) -> void:
		if m == "spider_matriarch":
			killed[0] = true
	env.bus.monster_killed.connect(cb)
	for i in 6000:
		env.sim.tick(FixedStepClock.STEP)
		if killed[0]:
			break
	env.bus.monster_killed.disconnect(cb)
	assert_true(killed[0], "boss sconfitto")
	assert_gt(env.skills.xp.get("hero", 0.0), 0.0)
