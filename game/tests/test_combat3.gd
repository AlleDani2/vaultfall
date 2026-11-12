extends GutTest
## COMBAT-3: reliquie di combattimento (bonus reali via Modificatori), bottino dei mostri (monster_drop_pct), postura delle
## classi ibride a ogni fase del boss, regole di Prova imposte (Digiuno, Maratona, Silenzio, Stile Sbagliato), riepiloghi
## e avvisi del combattimento, rumore della stima offline sui boss.

const Env := preload("res://tests/helpers/combat2_env.gd")
const RaidsEnv := preload("res://tests/helpers/raids_env.gd")
const RAID_ID := "collectors_den"      # boss «master_fence»: distanza, distanza, arcano


func _relic_env(seed_v: int = 11) -> Object:
	var crates := CrateSystem.new()
	var env: Object = Env.make(seed_v, 40, "warrior", false, [crates])
	env.gear("warrior", 4)
	env.food()
	env.set_meta("crates", crates)
	return env


func _give_relic(env: Object, def_id: String, cond: String = "marked") -> String:
	return env.bank.add_instance({"def_id": def_id, "def": def_id, "kind": "relic", "rarity": "relic", "condition": cond, "float": 0.4})


# ------------------------------------------------------------------ reliquie

func test_ogni_reliquia_di_combattimento_cambia_davvero_le_statistiche() -> void:
	var env: Object = _relic_env()
	var crates: CrateSystem = env.get_meta("crates")
	var combat: CombatSystem = env.combat
	var ids: Array = []
	for it in DataRegistry.items_by_category("relic"):
		ids.append(str(it.id) if it is Dictionary else str(it))
	ids.sort()
	assert_eq(ids.size(), 48, "le 48 reliquie dei dati")
	var checked := 0
	for rid in ids:
		var uid := _give_relic(env, rid)
		var s0: Dictionary = combat.hero_stats()
		var p0: Dictionary = combat._sim_params(combat._stats(), {"id": "x"}, {}, true)
		assert_true(crates.equip_relic(uid), rid)
		var s1: Dictionary = combat.hero_stats()
		var p1: Dictionary = combat._sim_params(combat._stats(), {"id": "x"}, {}, true)
		var rel_mods: Array = crates.relic_modifiers(env.bank.get_instance(uid))
		for m in rel_mods:
			var v := float(m.value)
			var key := str(m.key)
			var tag := "%s %s" % [rid, key]
			match key:
				"combat_dmg_pct":
					assert_almost_eq(float(s1.max_hit), float(s0.max_hit) * (1.0 + v / 100.0), 1.0, tag + " (colpo massimo arrotondato)")
				"combat_acc_pct":
					assert_almost_eq(float(s1.acc) / float(s0.acc), 1.0 + v / 100.0, 1e-9, tag)
				"combat_hp_pct":
					assert_almost_eq(float(s1.hp) / float(s0.hp), 1.0 + v / 100.0, 1e-9, tag)
				"combat_eva_pct":
					assert_almost_eq(float(s1.eva) / float(s0.eva), 1.0 + v / 100.0, 1e-9, tag)
				"combat_arm_pct":
					assert_almost_eq(float(s1.arm) / float(s0.arm), 1.0 + v / 100.0, 1e-9, tag)
				"combat_ward_pct":
					assert_almost_eq(float(s1.ward) / float(s0.ward), 1.0 + v / 100.0, 1e-9, tag)
				"combat_defense_pct":
					assert_almost_eq(float(s1.arm) / float(s0.arm), 1.0 + v / 100.0, 1e-9, tag + " armatura")
					assert_almost_eq(float(s1.ward) / float(s0.ward), 1.0 + v / 100.0, 1e-9, tag + " resistenza")
				"combat_crit_chance_pct":
					assert_almost_eq(float(s1.crit) - float(s0.crit), v / 100.0, 1e-9, tag)
				"combat_crit_dmg_pct":
					assert_almost_eq(float(s1.critd) - float(s0.critd), v / 100.0, 1e-9, tag)
				"combat_haste_pct":
					assert_almost_eq(float(s0.interval) / float(s1.interval), 1.0 + v / 100.0, 1e-9, tag)
				"combat_thorns_pct":
					assert_almost_eq(float(s1.thorns) - float(s0.thorns), v / 100.0, 1e-9, tag)
				"combat_multihit_pct":
					assert_almost_eq(float(s1.multihit) - float(s0.multihit), v / 100.0, 1e-9, tag)
				"combat_status_resist_pct":
					assert_gt(float(s1.status_resist), float(s0.status_resist), tag)
				"combat_dot_dmg_pct":
					assert_almost_eq(float(s1.dot_mult) / float(s0.dot_mult), 1.0 + v / 100.0, 1e-9, tag)
				"combat_revive_once":
					assert_false(bool(s0.revive_once), tag)
					assert_true(bool(s1.revive_once), tag)
				"combat_dmg_vs_bounty_pct":
					assert_almost_eq(float(s1.vs_bounty) - float(s0.vs_bounty), v, 1e-9, tag)
				"ammo_save_pct":
					assert_almost_eq(env.mods.total_add("ammo_save_pct"), v, 1e-9, tag)
					assert_gt(combat._ammo_recovery(), 0.0, tag)
				_:
					if key.begins_with("element_dmg_pct:"):
						var el := key.get_slice(":", 1)
						for e2 in (CombatSystem.ELEMENTS if el == "all" else PackedStringArray([el])):
							assert_almost_eq(float(p1.elem_add[e2]) - float(p0.elem_add[e2]), v, 1e-9, tag + " " + e2)
						checked += 1
						continue
					elif not _is_combat_key(key):
						continue
			checked += 1
		crates.unequip_relic(uid)
		var s2: Dictionary = combat.hero_stats()
		assert_eq(s2.max_hit, s0.max_hit, rid + ": tolta la reliquia, tornano le statistiche")
		assert_eq(s2.hp, s0.hp, rid)
	assert_gt(checked, 20, "gli effetti di combattimento controllati")


func _is_combat_key(key: String) -> bool:
	for pre in CombatSystem.RELIC_COMBAT_PREFIXES:
		if key.begins_with(pre):
			return true
	return false


func test_condizione_della_reliquia_scala_il_bonus() -> void:
	var env: Object = _relic_env()
	var crates: CrateSystem = env.get_meta("crates")
	var s0: Dictionary = env.combat.hero_stats()
	var uid := _give_relic(env, "relic_stormcrown_1", "pristine")     # +8% danno, +12% fulmine
	assert_true(crates.equip_relic(uid))
	var mult := float(crates.condition_info("pristine").bonus_mult)
	assert_almost_eq(float(env.combat.hero_stats().max_hit), float(s0.max_hit) * (1.0 + 8.0 * mult / 100.0), 1.0)


func test_reliquie_attive_descritte_per_la_schermata() -> void:
	var env: Object = _relic_env()
	var crates: CrateSystem = env.get_meta("crates")
	assert_eq(env.combat.relic_effects().size(), 0)
	var a := _give_relic(env, "relic_frostspire_1")     # danno + gelo: di combattimento
	var b := _give_relic(env, "relic_millbrook_3")      # oro e mercato: l'oro in combattimento conta solo se «combat»
	assert_true(crates.equip_relic(a))
	crates.add_relic_slot()
	assert_true(crates.equip_relic(b))
	var fx: Array = env.combat.relic_effects()
	assert_eq(fx.size(), 1, "la Macina Portafortuna (oro generico e mercato) non è un effetto di combattimento")
	assert_eq(str(fx[0].def), "relic_frostspire_1")
	assert_gte((fx[0].mods as Array).size(), 2)


func test_bonus_dell_oro_di_combattimento_della_reliquia_arriva_al_bottino() -> void:
	var env: Object = _relic_env()
	var crates: CrateSystem = env.get_meta("crates")
	var mon: Dictionary = DataRegistry.get_def("monsters", "cave_bat")
	var base: int = env.combat._roll_gold(mon, 1)
	var uid := _give_relic(env, "relic_saltreach_3")     # Uncino del Capitano: oro combattimento +6%
	assert_true(crates.equip_relic(uid))
	var with_relic := 0.0
	var without := 0.0
	for i in 400:
		with_relic += env.combat._roll_gold(mon, 1)
	crates.unequip_relic(uid)
	for i in 400:
		without += env.combat._roll_gold(mon, 1)
	assert_gt(with_relic, without * 1.02, "oro maggiore con la reliquia (base %d)" % base)


# ------------------------------------------------------------------ bottino dei mostri

func _drops_of(env: Object, table: String, item: String, n: int) -> int:
	var c := 0
	for i in n:
		var r: Dictionary = env.combat.loot_roll(table)
		for it in r.items:
			if str(it.id) == item:
				c += int(it.qty)
	return c


func test_monster_drop_pct_aumenta_la_probabilita_dei_drop_ma_non_di_famigli_e_casse() -> void:
	var env: Object = Env.make(21, 30, "warrior")
	var table := ""
	var item := ""
	for t in DataRegistry.table("drop_tables"):
		for e in t.get("entries", []):
			if e.has("chance") and float(e.chance) > 0.05 and float(e.chance) < 0.4 and not e.has("pet") and not e.has("pick_equipment_tier") \
					and not (e.get("qty", 1) is Array):
				table = str(t.id)
				item = str(e.item)
				break
		if not table.is_empty():
			break
	assert_false(table.is_empty(), "una tabella con un drop non banale")
	var n := 3000
	var base := _drops_of(env, table, item, n)
	env.mods.set_source("t", [{"key": "monster_drop_pct", "value": 100.0, "mode": "add"}])
	var boosted := _drops_of(env, table, item, n)
	print("MONSTER_DROP base %d boosted %d" % [base, boosted])
	assert_gt(boosted, int(base * 1.5), "+100% probabilità: circa il doppio")
	assert_lt(boosted, int(base * 2.6))


# ------------------------------------------------------------------ postura delle ibride a ogni fase

func _hybrid_raid_env(cls: String, seed_v: int = 5) -> Object:
	var env: Object = RaidsEnv.make(seed_v, 60, "warrior", 6)
	env.unlock_raid(RAID_ID)
	env.state.skills["hero"] = {"stars": 1}
	env.quests.done["class_" + cls] = true
	env.bank.gold_n = 999999
	assert_true(env.combat.set_class(cls), cls)
	return env


func test_pick_stance_segue_il_triangolo() -> void:
	# mischia > distanza > arcano > mischia
	assert_eq(CombatSim.pick_stance(["ranged", "melee"], "ranged"), "melee")
	assert_eq(CombatSim.pick_stance(["ranged", "melee"], "arcane"), "ranged")
	assert_eq(CombatSim.pick_stance(["melee", "arcane"], "ranged"), "melee")
	assert_eq(CombatSim.pick_stance(["melee", "arcane"], "arcane"), "arcane", "alla pari meglio che in svantaggio")
	assert_eq(CombatSim.pick_stance(["arcane", "ranged"], "melee"), "arcane")


func test_stance_for_considera_la_fase() -> void:
	var env: Object = _hybrid_raid_env("shadowstalker")
	var boss: Dictionary = DataRegistry.get_def("monsters", "master_fence")
	assert_eq(env.combat.stance_for(boss, 0), "melee")
	assert_eq(env.combat.stance_for(boss, 1), "melee")
	assert_eq(env.combat.stance_for(boss, 2), "ranged", "ultima fase arcana: l'Ombra Cacciatrice passa alla distanza")
	assert_eq(env.combat.stance_for(boss), env.combat.stance_for(boss, 0))
	var normal: Dictionary = DataRegistry.get_def("monsters", "cave_bat")
	assert_eq(env.combat.stance_for(normal, 2), env.combat.stance_for(normal, 0), "senza fasi la fase non conta")
	var plain: Object = RaidsEnv.make(5, 60, "warrior", 6)
	assert_eq(plain.combat.stance_for(boss, 2), "", "le classi non ibride non hanno postura")


func test_incursione_la_postura_cambia_alla_fase_del_boss() -> void:
	var env: Object = _hybrid_raid_env("shadowstalker", 7)
	assert_true(env.combat.eg.start_raid(RAID_ID, env.party("epic", 40)))
	var stance_events: Array = []
	var phases: Array = []
	var styles_at_stance: Array = []
	var last_id := 0
	var n := 0
	while env.combat.in_combat() and n < 40000:
		env.tick(1)
		n += 1
		for e in env.combat.log_since(last_id):
			last_id = int(e.id)
			if str(e.k) == "stance":
				stance_events.append(str(e.style))
				styles_at_stance.append(str(env.combat.hero_stats().style))
			elif str(e.k) == "phase":
				phases.append(int(e.i))
	assert_eq(phases, [1, 2], "il boss attraversa le due soglie")
	assert_eq(stance_events, ["ranged"], "una sola mossa: nella fase arcana (le prime due restano in mischia)")
	assert_eq(styles_at_stance, ["ranged"], "le statistiche mostrate seguono la postura")


func test_lama_arcana_sceglie_per_ogni_fase() -> void:
	var env: Object = _hybrid_raid_env("spellblade", 9)
	var queen: Dictionary = DataRegistry.get_def("monsters", "endless_frost_queen")
	assert_eq(env.combat.stance_for(queen, 0), "arcane", "arcano contro arcano è alla pari, la mischia sarebbe in svantaggio")
	assert_eq(env.combat.stance_for(queen, 2), "arcane", "contro la mischia l'arcano è in vantaggio")
	var warden: Dictionary = DataRegistry.get_def("monsters", "vault_warden")
	assert_eq(env.combat.stance_for(warden, 0), "arcane")
	assert_eq(env.combat.stance_for(warden, 2), "melee", "il Custode passa alla distanza: la mischia ha il vantaggio")


func test_boss_pass_ibrida_cambia_postura_come_il_tick() -> void:
	var env: Object = _hybrid_raid_env("shadowstalker", 3)
	var c: CombatSystem = env.combat
	var boss: Dictionary = DataRegistry.get_def("monsters", "master_fence")
	var ms := c._scaled(boss, 1)
	var fx: Dictionary = c.eg.raid_fx(RAID_ID, env.party("epic", 40))
	var st: Dictionary = c.eg.apply_fx(c._stats_for(c.stance_for(boss)), fx)
	assert_eq(str(st.style), "melee")
	var res: Dictionary = c.eg.boss_pass(boss, ms, st, {"hp0": float(st.hp), "food": 100000, "fx": fx})
	assert_true(bool(res.won), "il passaggio medio vince")
	assert_eq(int(res.phase), 2)
	assert_eq(str(c._est_sim.st.style), "ranged", "a fine passaggio l'eroe era nella postura dell'ultima fase")
	# partendo già a metà boss (offline con scontro in corso) la postura è subito quella giusta
	var res2: Dictionary = c.eg.boss_pass(boss, ms, st, {"hp0": float(st.hp), "food": 100000, "hp_frac": 0.2, "limit_s": 0.1, "fx": fx})
	assert_eq(int(res2.phase), 2)
	assert_eq(str(c._est_sim.st.style), "ranged")
	# un nuovo scontro riparte dalla postura iniziale
	var fresh := CombatSim.new()
	fresh.configure(c._sim_params(st, boss, ms, true, fx))
	assert_eq(str(fresh.st.style), "melee")
	assert_eq(fresh.st_alt.keys().size(), 2)


func test_classi_non_ibride_non_hanno_posture_alternative() -> void:
	var env: Object = RaidsEnv.make(5, 60, "warrior", 6)
	var c: CombatSystem = env.combat
	var boss: Dictionary = DataRegistry.get_def("monsters", "master_fence")
	var p: Dictionary = c._sim_params(c._stats(), boss, c._scaled(boss, 1), true)
	assert_true((p.st_alt as Dictionary).is_empty())


# ------------------------------------------------------------------ regole di Prova

func _casts_in(env: Object, ticks: int) -> int:
	var casts := 0
	var last: int = env.combat.log_last_id()
	for i in ticks:
		env.tick(1)
		if i % 20 == 0:
			for e in env.combat.log_since(last):
				last = int(e.id)
				if str(e.k) == "cast":
					casts += 1
	for e in env.combat.log_since(last):
		if str(e.k) == "cast":
			casts += 1
	return casts


func test_prova_silenzio_nessuna_tecnica_nel_combattimento_vero() -> void:
	var env: Object = RaidsEnv.make(5, 40, "warrior", 4)
	env.state.unlocks.append("zone:ironroot")
	assert_true(env.combat.start("ironroot", ""))
	var free := _casts_in(env, 1500)
	assert_gt(free, 3, "senza Prova le tecniche scattano")
	env.prestige.rules = {"no_abilities": true}
	env.combat.stop()
	assert_true(env.combat.start("ironroot", ""))
	assert_eq(_casts_in(env, 1500), 0, "Silenzio: nessuna tecnica")


func test_prova_stile_sbagliato_riduce_il_danno_inflitto() -> void:
	var dmg := []
	for rules in [{}, {"forced_disadvantage": true}]:
		var env: Object = RaidsEnv.make(8, 40, "warrior", 4)
		env.state.unlocks.append("zone:ironroot")
		env.prestige.rules = rules
		env.combat.start("ironroot", "ironroot_golem")
		env.tick(3000)
		dmg.append(float(env.combat._run.get("dealt", 0.0)) / maxf(1.0, float(env.combat._run.get("t", 1.0))))
	# FIX-COMBATTIMENTO: con i potenziamenti gratuiti e la Furia dei colpi subiti (scontri piu lunghi) il rapporto misurato e ~0,92
	assert_lt(dmg[1], dmg[0] * 0.95, "sempre in svantaggio: 0,85 al posto di 1,0/1,15 (dps %.1f vs %.1f)" % [dmg[1], dmg[0]])


func test_prova_maratona_la_stima_offline_conosce_la_vita_maggiorata() -> void:
	var env: Object = RaidsEnv.make(5, 40, "warrior", 4)
	env.state.unlocks.append("zone:ironroot")
	var plain: Dictionary = env.combat.estimate("ironroot_golem")
	env.prestige.rules = {"monster_hp_mult": 1.5}
	var harder: Dictionary = env.combat.estimate("ironroot_golem")
	assert_gt(float(harder.ttk), float(plain.ttk) * 1.35, "scontri più lunghi con la vita ×1,5 (%.1f vs %.1f)" % [harder.ttk, plain.ttk])
	assert_almost_eq(float(harder.mhp), float(plain.mhp) * 1.5, float(plain.mhp) * 0.001)


func test_prova_digiuno_il_mangiare_automatico_resta_fermo() -> void:
	var env: Object = RaidsEnv.make(5, 40, "warrior", 4)
	env.state.unlocks.append("zone:ironroot")
	env.combat.start("ironroot", "")
	env.combat.state["hp"] = float(env.combat.max_hp()) * 0.2
	var before: int = env.bank.count("food_bleak")
	env.combat._auto_eat()
	assert_lt(env.bank.count("food_bleak"), before, "senza Prova l'eroe mangia")
	env.combat.state["hp"] = float(env.combat.max_hp()) * 0.2
	env.prestige.rules = {"no_food": true}
	var b2: int = env.bank.count("food_bleak")
	assert_true(env.combat.trial_food_blocked())
	env.combat._auto_eat()
	assert_eq(env.bank.count("food_bleak"), b2, "Digiuno: il mangiare automatico non tocca il cibo")
	assert_eq(env.combat.danger_level(), "critical", "vita bassa e cibo vietato: pericolo")
	var warned := false
	for e in env.combat.log_since(0):
		if str(e.k) == "trial_nofood":
			warned = true
	assert_true(warned, "una riga nel registro spiega perché non mangia")
	assert_true(env.combat.food_info().blocked)


func test_prova_digiuno_porzioni_concesse_poi_si_blocca() -> void:
	var env: Object = RaidsEnv.make(5, 40, "warrior", 4)
	env.prestige.rules = {"max_food": 3}
	env.prestige.active = {"id": "trial_fasting", "tier": 4, "food_eaten": 2}
	assert_false(env.combat.trial_food_blocked())
	env.prestige.active = {"id": "trial_fasting", "tier": 4, "food_eaten": 3}
	assert_true(env.combat.trial_food_blocked(), "porzioni concesse finite")


# ------------------------------------------------------------------ riepiloghi e avvisi

func test_riepilogo_dello_scontro_e_della_corsa() -> void:
	var env: Object = Env.make(5, 30, "warrior")
	env.gear("warrior", 3)
	env.food()
	env.unlock_zone("ironroot")
	assert_true(env.combat.last_fight().is_empty())
	env.combat.start("ironroot", "cave_bat")
	var kill: Dictionary = {}
	var last := 0
	for i in 3000:
		env.tick(1)
		for e in env.combat.log_since(last):
			last = int(e.id)
			if str(e.k) == "kill" and kill.is_empty():
				kill = e
		if not kill.is_empty():
			break
	assert_false(kill.is_empty(), "una uccisione")
	var f: Dictionary = kill.fight
	assert_gt(float(f.t), 0.0)
	assert_gt(float(f.dealt), 0.0)
	assert_eq(str(f.monster), "cave_bat")
	assert_false(bool(f.died))
	assert_eq(f.xp, kill.xp)
	assert_eq(env.combat.last_fight().monster, "cave_bat")
	var run: Dictionary = env.combat.run_summary()
	assert_eq(int(run.kills), 1)
	assert_gte(float(run.wall), float(f.t))
	var txt := CombatUi.fight_text(f)
	assert_true(txt.length() > 20 and not txt.contains("{"), txt)


func test_avvisi_del_boss_scandiscono_il_colpo_devastante() -> void:
	var env: Object = Env.make(5, 30, "warrior")
	env.gear("warrior", 3)
	env.food()
	env.unlock_zone("ironroot")
	env.combat.start("ironroot", "ironroot_golem")
	env.tick(40)
	var th: Array = env.combat.threats()
	assert_gt(th.size(), 0)
	var heavy := {}
	for t in th:
		if str(t.id) == "heavy_blow":
			heavy = t
	assert_false(heavy.is_empty(), "il Colpo Devastante del Golem")
	assert_eq(str(heavy.kind), "timer")
	assert_lte(float(heavy.in_s), 15.0)
	var first := float(heavy.in_s)
	env.tick(20)
	var again := 0.0
	for t in env.combat.threats():
		if str(t.id) == "heavy_blow":
			again = float(t.in_s)
	assert_lt(again, first, "il conto alla rovescia scende")


func test_livello_di_pericolo_con_e_senza_cibo() -> void:
	var env: Object = Env.make(5, 30, "warrior")
	env.gear("warrior", 3)
	env.food()
	env.unlock_zone("ironroot")
	env.combat.start("ironroot", "")
	assert_eq(env.combat.danger_level(), "", "vita piena")
	env.combat.state["hp"] = float(env.combat.max_hp()) * 0.1
	assert_eq(env.combat.danger_level(), "low", "vita bassa ma c'è cibo")
	env.bank.stacks["food_bleak"] = 0
	assert_eq(env.combat.danger_level(), "critical", "vita bassa e niente cibo")


# ------------------------------------------------------------------ rumore della stima offline

func test_stima_boss_stratificata_per_tipo_ha_poco_rumore() -> void:
	var env: Object = Env.make(99, 25, "warrior")
	env.gear("warrior", 3)
	env.food()
	env.unlock_zone("ironroot")
	var c: CombatSystem = env.combat
	var mon: Dictionary = DataRegistry.get_def("monsters", "ironroot_golem")
	var ms := c._scaled(mon, 1)
	var st := c._stats_for("")
	var truth: Dictionary = c._est_pass(mon, ms, st, {}, {"expect": false, "cycles": 1600, "plain": true})
	var vals: Array = []
	for k in 8:
		var m2 := mon.duplicate()
		m2["id"] = str(mon.id) + str(k)
		vals.append(float(c._est_pass(m2, ms, st, {}, {"expect": false, "cycles": CombatSystem.EST_MC_MIN}).ttk))
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var worst := 0.0
	for v in vals:
		worst = maxf(worst, absf(v / mean - 1.0))
	print("EST_NOISE golem: plain %.2f stratificato %.2f (%+.2f%%) scarto massimo tra semi %.2f%%" % [truth.ttk, mean, (mean / truth.ttk - 1.0) * 100.0, worst * 100.0])
	assert_lt(worst, 0.015, "i semi diversi danno lo stesso tempo di uccisione entro ±1,5%")
	assert_almost_eq(mean, float(truth.ttk), float(truth.ttk) * 0.015, "centrato sul campionamento semplice (campione di 1600 scontri) entro ±1,5%")

func test_passi_fusi_danno_lo_stesso_risultato_del_passo_per_passo() -> void:
	# la misura Monte Carlo fonde i passi senza eventi: il risultato deve essere identico a quello passo per passo
	var cases := [["warrior", 25, 3, "ironroot", "ironroot_golem"], ["arcanist", 30, 3, "ironroot", "ironroot_golem"],
		["ranger", 40, 4, "whisperwood", "spider_matriarch"], ["warrior", 55, 6, "ashen", "nameless_pharaoh"],
		["warrior", 70, 7, "frostspire", "ice_jarl"], ["warrior", 55, 6, "gallmire", "gall_witch"],
		["ranger", 30, 3, "ironroot", "cave_bat"], ["arcanist", 30, 3, "ironroot", "kobold_miner"]]
	for cs in cases:
		var env: Object = Env.make(7, int(cs[1]), str(cs[0]))
		env.gear(str(cs[0]), int(cs[2]))
		env.food()
		env.unlock_zone(str(cs[3]))
		var c: CombatSystem = env.combat
		c.start(str(cs[3]), str(cs[4]))
		var mon: Dictionary = DataRegistry.get_def("monsters", str(cs[4]))
		var ms := c._scaled(mon, 1)
		var st := c._stats_for("")
		var out: Array = []
		for fast in [false, true]:
			c.est_fast = fast
			out.append(c._est_pass(mon, ms, st, {}, {"expect": false, "cycles": 10}))
		c.est_fast = true
		for key in ["ttk", "swings", "hits", "casts", "dmg_per_kill", "heal_per_kill", "food_per_kill", "regen_per_kill"]:
			assert_almost_eq(float(out[1][key]), float(out[0][key]), absf(float(out[0][key])) * 1e-6 + 1e-9, "%s %s" % [cs[4], key])
		assert_eq(out[1].lethal, out[0].lethal, str(cs[4]))
