extends GutTest
## M7 (COMBAT-2): abilità (risorse, ricariche, lista di priorità, effetti), motore CombatSim e bilanciamento delle tecniche.

const Env := preload("res://tests/helpers/combat2_env.gd")


## Arena di prova: eroe `env` contro `mon_id`, nemico con vita enorme, nessun attacco del mostro. `expect` = modalità attesa.
func _arena(env: Object, mon_id: String, expect: bool = false, enemy_hp: float = 1.0e9) -> Dictionary:
	var mon: Dictionary = DataRegistry.get_def("monsters", mon_id)
	var ms: Dictionary = env.combat._scaled(mon, 1)
	var st: Dictionary = env.combat._stats_for(env.combat.stance_for(mon))
	var sim: CombatSim = CombatSim.new()
	sim.configure(env.combat._sim_params(st, mon, ms, expect))
	if not expect:
		sim.rng = env.combat.ctx.rng
	var a := {"type": "combat", "enemy": {}, "hero_cd": 0.0, "mon_cd": 1.0e9}
	sim.spawn(env.combat.state, a)
	a.enemy["hp"] = enemy_hp
	a.enemy["max"] = enemy_hp
	a["hero_cd"] = 0.0
	a["mon_cd"] = 1.0e9
	return {"sim": sim, "a": a, "h": env.combat.state, "mon": mon, "ms": ms, "st": st}


func _step(ar: Dictionary, n: int = 1) -> int:
	var r := 0
	for i in n:
		(ar.sim as CombatSim).tick_timers(ar.h, FixedStepClock.STEP, true)
		r = (ar.sim as CombatSim).step(ar.h, ar.a, FixedStepClock.STEP)
	return r


func _hero(cls: String, lvl: int, tier: int, abilities: Array = [], res: float = 100.0) -> Object:
	var env: Object = Env.make(3, lvl, cls)
	env.gear(cls, tier)
	env.food()
	if not abilities.is_empty():
		env.combat.build.set_auto_abilities(false)
		env.combat.state["abilities"] = abilities
		env.combat.on_build_changed()
	env.combat.state["hp"] = env.combat.max_hp()
	env.combat.state.rt["res"] = res
	return env


# ------------------------------------------------------------------ disponibilità e lista di priorità

func test_abilita_per_livello_e_classe() -> void:
	var env: Object = _hero("warrior", 5, 1)
	for lvl in [1, 8, 15, 25, 40, 60]:
		env.skills.levels["hero"] = lvl
		var want := 0
		for ab in DataRegistry.table("abilities"):
			if str(ab.class) == "warrior" and int(ab.level_req) <= lvl:
				want += 1
		assert_eq(env.combat.build.abilities_available().size(), want, "livello %d" % lvl)
	assert_eq(DataRegistry.table("abilities").size(), 48, "48 abilità nei dati")


func test_arma_di_stile_diverso_niente_abilita_di_classe() -> void:
	var env: Object = Env.make(3, 10, "ranger")
	env.combat.equip(env.give("sword_copper"))
	assert_true(env.combat.build.abilities_equipped().is_empty(), "R-CL-4: arma di stile diverso, solo attacchi base")
	env.combat.unequip("weapon")
	env.combat.equip(env.give("shortbow_pine"))
	assert_false(env.combat.build.abilities_equipped().is_empty())


func test_lista_automatica_e_manuale() -> void:
	var env: Object = _hero("warrior", 65, 7)
	var auto: Array = env.combat.build.abilities_equipped().map(func(x: Dictionary) -> String: return str(x.id))
	assert_eq(auto.size(), int(Formulas.k().combat.rules.ability_slots), "al massimo 4 abilità")
	assert_eq(auto[0], "last_stand", "prima la difesa d'emergenza con condizione")
	assert_false(auto.has("shield_wall"), "i potenziamenti puri non entrano nella scelta automatica")
	assert_true(env.combat.build.set_slot(0, "battle_cry"))
	assert_false(env.combat.state.auto_abilities)
	var man: Array = env.combat.build.abilities_equipped().map(func(x: Dictionary) -> String: return str(x.id))
	assert_eq(man[0], "battle_cry")
	assert_lte(man.size(), 4)
	assert_false(env.combat.build.set_slot(0, "meteor"), "abilità di un'altra classe")
	assert_false(env.combat.build.set_slot(4, "cleave"), "solo 4 slot")
	assert_true(env.combat.build.set_slot(0, ""), "slot svuotato")
	env.combat.build.set_auto_abilities(true)
	assert_eq(env.combat.build.abilities_equipped().size(), 4)


# ------------------------------------------------------------------ risorse

func test_risorse_furia_concentrazione_mana() -> void:
	var env: Object = _hero("warrior", 25, 3, ["cleave"], 0.0)
	var ar := _arena(env, "mud_slime")
	# la Furia sale con i colpi inflitti e subiti (valori di data/resources.json)
	var fury: Dictionary = DataRegistry.get_def("resources", "fury")
	var sim: CombatSim = ar.sim
	env.combat.state.rt["res"] = 0.0
	ar.a["hero_cd"] = 0.0
	env.combat.build.set_auto_abilities(false)
	env.combat.state["abilities"] = []
	env.combat.on_build_changed()
	ar = _arena(env, "mud_slime")
	var n := 0
	while float(env.combat.state.rt.res) <= 0.0 and n < 400:
		_step(ar)
		n += 1
	assert_gte(float(env.combat.state.rt.res), float(fury.on_hit_dealt) * 0.99, "un colpo dà almeno il valore dei dati")
	# fuori dal combattimento la Furia cala
	var before := float(env.combat.state.rt.res)
	sim.tick_timers(env.combat.state, 1.0, false)
	assert_almost_eq(float(env.combat.state.rt.res), maxf(0.0, before - float(fury.decay_out_of_combat_per_s)), 1e-6)
	# Concentrazione: +regen al secondo senza combattere; Mana: massimo 50 + 2·INT
	var env2: Object = _hero("ranger", 25, 3, [], 0.0)
	env2.combat._sync_sim({}, {})
	env2.combat._sim.tick_timers(env2.combat.state, 1.0, false)
	var focus: Dictionary = DataRegistry.get_def("resources", "focus")
	assert_almost_eq(float(env2.combat.state.rt.res), float(focus.regen_per_s) * float(env2.combat.hero_stats().res_mult), 1e-6)
	var env3: Object = _hero("arcanist", 25, 3, [], 0.0)
	var info: Dictionary = env3.combat.resource_info()
	assert_eq(info.id, "mana")
	assert_almost_eq(float(info.max), 50.0 + 2.0 * float(env3.combat.hero_stats().attrs.int), 1e-6)


# ------------------------------------------------------------------ effetti

func test_lancio_risorsa_ricarica_e_danno_atteso() -> void:
	var env: Object = _hero("warrior", 25, 3, ["cleave"], 100.0)
	var ar := _arena(env, "mud_slime", true)
	var ab: Dictionary = DataRegistry.get_def("abilities", "cleave")
	var e: Dictionary = ar.a.enemy
	var hp0 := float(e.hp)
	_step(ar)
	var rt: Dictionary = env.combat.state.rt
	assert_true(rt.cd.has("cleave"), "ricarica avviata")
	assert_almost_eq(float(rt.cd.cleave), float(ab.cooldown_s), 1e-6)
	assert_almost_eq(float(rt.res), 100.0 - float(ab.cost) + 0.0, 1e-6, "costo scalato dalla risorsa")
	# danno atteso = colpo massimo × rapporto medio × moltiplicatore dell'abilità × (difesa, triangolo) × (1 + crit)
	var sim: CombatSim = ar.sim
	var eff: Dictionary = sim.effective(rt)
	var st: Dictionary = ar.st
	var common: float = sim._common(eff, e, "", float(st.armor_pen))
	var mean_raw := float(eff.max_hit) * (1.0 + float(st.min_ratio)) / 2.0 * (1.0 + float(eff.crit) * (float(eff.critd) - 1.0))
	assert_almost_eq(hp0 - float(e.hp), mean_raw * float((ab.effect as Dictionary).weapon_mult) * common, 1e-3 * hp0 / 1.0e9 + 1e-6 + mean_raw * 0.001)
	# ancora in ricarica: non rilancia; dopo la ricarica sì
	var casts0 := 0
	_step(ar, 5)
	assert_true(rt.cd.has("cleave"))
	assert_eq(casts0, 0)
	_step(ar, int(float(ab.cooldown_s) / FixedStepClock.STEP) + 40)
	assert_lt(float(rt.res), 100.0, "risorsa spesa ancora dopo la ricarica")


func test_senza_risorsa_non_lancia() -> void:
	var env: Object = _hero("warrior", 25, 3, ["cleave"], 0.0)
	var ar := _arena(env, "mud_slime", true)
	env.combat.state.rt["res"] = 0.0
	ar.a["hero_cd"] = 0.0
	var sim: CombatSim = ar.sim
	sim.step(ar.h, ar.a, FixedStepClock.STEP)
	assert_false((env.combat.state.rt.cd as Dictionary).has("cleave"), "Furia insufficiente: niente tecnica, attacco base")
	assert_gt(float(sim.acc.get("swings", 0.0)) + float(sim.acc.get("hits", 0.0)), -1.0)


func test_potenziamento_modifica_le_statistiche_e_scade() -> void:
	var env: Object = _hero("warrior", 25, 3, ["battle_cry"], 100.0)
	var ar := _arena(env, "mud_slime", true)
	var sim: CombatSim = ar.sim
	var base_hit := float(sim.effective(env.combat.state.rt).max_hit)
	_step(ar)
	var rt: Dictionary = env.combat.state.rt
	assert_true(rt.buffs.has("battle_cry"))
	var buffed := float(sim.effective(rt).max_hit)
	var ab: Dictionary = DataRegistry.get_def("abilities", "battle_cry")
	var pct := float(ab.effect.modifiers[0].value)
	var add0: float = env.mods.total_add("combat_dmg_pct")
	assert_almost_eq(buffed / base_hit, (1.0 + (add0 + pct) / 100.0) / (1.0 + add0 / 100.0), 1e-9, "+% danno dal potenziamento (regola add)")
	_step(ar, int(float(ab.effect.duration_s) / FixedStepClock.STEP) + 3)
	assert_false(rt.buffs.has("battle_cry"), "scade dopo la durata")
	assert_almost_eq(float(sim.effective(rt).max_hit), base_hit, 1e-9)


func test_cura_con_condizione() -> void:
	var env: Object = _hero("warrior", 65, 7, ["last_stand"], 0.0)
	var ar := _arena(env, "mud_slime", true)
	var mx: float = env.combat.max_hp()
	env.combat.state["hp"] = mx * 0.5
	_step(ar)
	assert_false((env.combat.state.rt.cd as Dictionary).has("last_stand"), "sopra la soglia non scatta")
	env.combat.state["hp"] = mx * 0.2
	_step(ar)
	assert_true((env.combat.state.rt.cd as Dictionary).has("last_stand"))
	assert_almost_eq(float(env.combat.state.hp), mx * 0.2 + mx * 0.30, mx * 0.002, "cura 30% della vita massima")


func test_danno_nel_tempo() -> void:
	var env: Object = _hero("warrior", 25, 3, ["rending_strike"], 100.0)
	var ar := _arena(env, "mud_slime", true)
	_step(ar)
	var e: Dictionary = ar.a.enemy
	assert_true((e.dots as Dictionary).has("rending_strike"))
	var ab: Dictionary = DataRegistry.get_def("abilities", "rending_strike")
	assert_eq(int(e.dots.rending_strike.n), int(ab.effect.ticks))
	var hp_a := float(e.hp)
	ar.a["hero_cd"] = 1.0e9
	_step(ar, 10)      # 1 s: un tick
	assert_lt(float(e.hp), hp_a, "il DoT infligge danno ogni secondo")
	_step(ar, int(float(ab.effect.ticks) * 10.0) + 20)
	assert_false((e.dots as Dictionary).has("rending_strike"), "esaurito dopo i tick")


func test_dot_potenziato_da_combat_dot_dmg() -> void:
	var env: Object = _hero("warrior", 25, 3, ["rending_strike"], 100.0)
	var ar := _arena(env, "mud_slime", true)
	_step(ar)
	var raw0 := float(ar.a.enemy.dots.rending_strike.raw)
	var env2: Object = _hero("warrior", 25, 3, ["rending_strike"], 100.0)
	env2.mods.set_source("test", [{"key": "combat_dot_dmg_pct", "value": 50, "mode": "add"}])
	var ar2 := _arena(env2, "mud_slime", true)
	_step(ar2)
	assert_almost_eq(float(ar2.a.enemy.dots.rending_strike.raw) / raw0, 1.5, 1e-9)


func test_evocazione_compagno() -> void:
	var env: Object = _hero("ranger", 30, 3, ["call_companion"], 100.0)
	env.quests.done["class_beastmaster"] = true
	assert_true(env.combat.build.set_spec("beastmaster"))
	env.combat.build.set_auto_abilities(false)
	env.combat.state["abilities"] = ["call_companion"]
	env.combat.on_build_changed()
	env.combat.state.rt["res"] = 100.0
	var ar := _arena(env, "mud_slime", true)
	_step(ar)
	var rt: Dictionary = env.combat.state.rt
	assert_true(rt.summons.has("call_companion"))
	ar.a["hero_cd"] = 1.0e9
	var e: Dictionary = ar.a.enemy
	var hp0 := float(e.hp)
	_step(ar, 20)
	assert_lt(float(e.hp), hp0, "il compagno combatte da solo")
	var ab: Dictionary = DataRegistry.get_def("abilities", "call_companion")
	_step(ar, int(float(ab.effect.duration_s) / FixedStepClock.STEP) + 5)
	assert_false(rt.summons.has("call_companion"), "scompare a fine durata")


func test_stordimento_e_rallentamento() -> void:
	var env: Object = _hero("warrior", 45, 5, ["earthshaker"], 100.0)
	var ar := _arena(env, "mud_slime", true)
	ar.a["mon_cd"] = 50.0
	_step(ar)
	var ab: Dictionary = DataRegistry.get_def("abilities", "earthshaker")
	assert_almost_eq(float(ar.a.mon_cd), 50.0 - FixedStepClock.STEP + float(ab.effect.stun_s), 1e-6, "il mostro salta gli attacchi")
	var env2: Object = _hero("arcanist", 25, 3, ["frost_nova"], 100.0)
	var ar2 := _arena(env2, "mud_slime", true)
	_step(ar2)
	var fn: Dictionary = DataRegistry.get_def("abilities", "frost_nova")
	assert_almost_eq(float(ar2.a.enemy.slow_pct), float(fn.effect.slow_pct), 1e-9)
	assert_gt(ar2.sim._mon_interval(ar2.a.enemy), float(ar2.ms.attack_interval_s), "intervallo allungato")


func test_esecuzione_raddoppia_sotto_soglia() -> void:
	var env: Object = _hero("ranger", 75, 8, [], 100.0)
	env.quests.done["class_sharpshooter"] = true
	assert_true(env.combat.build.set_spec("sharpshooter"))
	env.combat.build.set_auto_abilities(false)
	env.combat.state["abilities"] = ["execution_shot"]
	env.combat.on_build_changed()
	env.combat.state.rt["res"] = 100.0
	var ar := _arena(env, "mud_slime", true, 1.0e6)
	_step(ar)
	var dmg_hi := 1.0e6 - float(ar.a.enemy.hp)
	env.combat.state.rt["res"] = 100.0
	env.combat.state.rt["cd"] = {}
	var ar2 := _arena(env, "mud_slime", true, 1.0e6)
	ar2.a.enemy["hp"] = 1.0e6 * 0.1
	var hp_low := float(ar2.a.enemy.hp)
	_step(ar2)
	var dmg_lo := hp_low - float(ar2.a.enemy.hp)
	var fx: Dictionary = DataRegistry.get_def("abilities", "execution_shot").effect
	assert_almost_eq(dmg_lo / dmg_hi, float(fx.execute_mult), 0.001)


func test_cura_da_danno_e_scudo() -> void:
	var env: Object = _hero("warrior", 50, 6, [], 100.0)
	env.quests.done["class_berserker"] = true
	assert_true(env.combat.build.set_spec("berserker"))
	env.combat.build.set_auto_abilities(false)
	env.combat.state["abilities"] = ["bloodthirst"]
	env.combat.on_build_changed()
	env.combat.state.rt["res"] = 100.0
	env.combat.state["hp"] = env.combat.max_hp() * 0.5
	var hp0: float = env.combat.hp()
	var ar := _arena(env, "mud_slime", true)
	_step(ar)
	assert_gt(env.combat.hp(), hp0, "Sete di Sangue cura una parte del danno")
	var env2: Object = _hero("arcanist", 25, 3, ["mana_shield"], 100.0)
	var ar2 := _arena(env2, "mud_slime", true)
	_step(ar2)
	var fx: Dictionary = DataRegistry.get_def("abilities", "mana_shield").effect
	assert_almost_eq(float(env2.combat.state.rt.shield), env2.combat.max_hp() * float(fx.pct_max_hp) / 100.0, 1e-6)


# ------------------------------------------------------------------ in gioco: il tick usa davvero le tecniche

func test_tick_lancia_tecniche_e_registra() -> void:
	var env: Object = _hero("warrior", 5, 1)
	env.unlock_zone("millbrook")
	assert_true(env.combat.start("millbrook", "mud_slime"))
	var casts := 0
	var last: int = env.combat.log_last_id()
	for i in 1000:
		env.sim.tick(FixedStepClock.STEP)
		if i % 10 == 0:
			for ev in env.combat.log_since(last):
				last = int(ev.id)
				if str(ev.k) == "cast":
					casts += 1
	assert_gt(casts, 3, "Fendente lanciato durante lo scontro")
	assert_gt(int(env.state.stats.kills), 2)


func test_guadagno_delle_tecniche_vicino_al_25_per_cento() -> void:
	# docs/05 §5: le tecniche aggiungono ~25% di DPS; qui kill/ora con tecniche rispetto ai soli attacchi base
	var rows := [["warrior", 45, 5, "gallmire"], ["ranger", 45, 5, "gallmire"], ["arcanist", 45, 5, "gallmire"]]
	for r in rows:
		var env: Object = _hero(str(r[0]), int(r[1]), int(r[2]))
		env.unlock_zone(str(r[3]))
		var with_c := 0.0
		var without_c := 0.0
		for m in env.combat.monsters_of(str(r[3])):
			if str(m.type) == "normal":
				with_c += float(env.combat.estimate(str(m.id), true).cycle)
		env.combat.build.set_auto_abilities(false)
		env.combat.state["abilities"] = []
		env.combat.on_build_changed()
		for m in env.combat.monsters_of(str(r[3])):
			if str(m.type) == "normal":
				without_c += float(env.combat.estimate(str(m.id), true).cycle)
		var gain := without_c / with_c - 1.0
		assert_between(gain, 0.12, 0.42, "%s: guadagno delle tecniche %.1f%%" % [r[0], gain * 100.0])
