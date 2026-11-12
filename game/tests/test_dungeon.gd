extends GutTest
## M7 (COMBAT-2): dungeon (sequenza di ondate con boss, accesso, ricompense, traguardi, rischio) e incursioni (solo elenco).

const Env := preload("res://tests/helpers/combat2_env.gd")
const DID := "cursed_granary"


func _hero(lvl: int = 20, tier: int = 3, seed_v: int = 5) -> Object:
	var env: Object = Env.make(seed_v, lvl, "warrior")
	env.gear("warrior", tier)
	env.food()
	return env


func _open(env: Object) -> void:
	env.state.unlocks.append("dungeon:" + DID)


func test_accesso_solo_con_gettone_e_livello() -> void:
	var env: Object = _hero(20)
	assert_false(env.combat.dungeon_unlocked(DID), "serve il gettone della missione")
	assert_false(env.combat.start_dungeon(DID))
	_open(env)
	assert_true(env.combat.dungeon_unlocked(DID))
	var weak: Object = _hero(2, 1)
	_open(weak)
	assert_false(weak.combat.dungeon_unlocked(DID), "serve il livello Eroe dei dati")
	var list: Array = env.combat.dungeons()
	assert_eq(list.size(), 10)
	assert_true(list[0].unlocked)
	assert_false(list[1].unlocked)


func test_corsa_completa_premio_e_missioni() -> void:
	var env: Object = _hero(20)
	_open(env)
	watch_signals(env.bus)
	var gold0: int = env.bank.gold_n
	assert_true(env.combat.start_dungeon(DID))
	assert_true(env.combat.in_dungeon())
	var d: Dictionary = env.combat.dungeon_def(DID)
	var seen_waves := {}
	for i in 12000:
		env.sim.tick(FixedStepClock.STEP)
		if env.combat.in_dungeon():
			seen_waves[int(env.combat.dungeon_progress().wave)] = true
		if env.combat.dungeon_clears(DID) >= 1:
			break
	assert_eq(env.combat.dungeon_clears(DID), 1, "completato una volta")
	assert_gte(seen_waves.size(), (d.waves as Array).size() - 1, "tutte le ondate attraversate")
	assert_gte(env.bank.gold_n - gold0, int(d.completion_reward.gold), "oro del premio (più i drop)")
	assert_signal_emitted_with_parameters(env.bus, "objective_event", ["complete_dungeon", {"dungeon": DID, "qty": 1}])
	assert_gt(get_signal_emit_count(env.bus, "crate_found"), 0, "la cassa della zona arriva a fine dungeon")
	assert_true(env.combat.in_dungeon(), "ripete da capo (ripetizione attiva)")
	assert_eq(int(env.combat.dungeon_progress().wave), 0)


func test_senza_ripetizione_si_ferma() -> void:
	var env: Object = _hero(20)
	_open(env)
	env.combat.set_dungeon_repeat(false)
	assert_true(env.combat.start_dungeon(DID))
	for i in 12000:
		env.sim.tick(FixedStepClock.STEP)
		if not env.combat.in_combat():
			break
	assert_false(env.combat.in_combat())
	assert_eq(env.combat.dungeon_clears(DID), 1)


func test_niente_cambio_equipaggiamento_nel_dungeon() -> void:
	var env: Object = _hero(20)
	_open(env)
	var spare: String = env.give("sword_copper")
	assert_true(env.combat.start_dungeon(DID))
	assert_false(env.combat.equip(spare), "docs/05 §8: niente cambio equipaggiamento dentro")
	var slot_before: String = env.combat.equipped("weapon")
	env.combat.unequip("weapon")
	assert_eq(env.combat.equipped("weapon"), slot_before)
	env.combat.stop()
	assert_true(env.combat.equip(spare), "fuori dal dungeon si può")


func test_morte_fa_fallire_la_corsa_ma_si_tiene_il_bottino() -> void:
	var env: Object = Env.make(9, 9, "warrior")     # livello minimo del dungeon, nessun equipaggiamento né cibo
	_open(env)
	assert_true(env.combat.start_dungeon(DID))
	var died := [false]
	var cb := func(_c: String) -> void: died[0] = true
	env.bus.player_died.connect(cb)
	for i in 15000:
		env.sim.tick(FixedStepClock.STEP)
		if died[0] and not env.combat.in_combat():
			break
	env.bus.player_died.disconnect(cb)
	assert_true(died[0], "senza equipaggiamento né cibo si muore")
	assert_false(env.combat.in_combat(), "dopo la rinascita la corsa è finita")
	assert_eq(env.combat.dungeon_clears(DID), 0)
	assert_gt(float(env.combat.state.wounded_s), 0.0, "Ferito")
	assert_gt(env.bank.gold_n, 0, "il bottino delle ondate vinte resta")


func test_traguardi_di_completamento() -> void:
	var env: Object = _hero(20)
	_open(env)
	var hit0: float = env.combat.hero_stats().interval
	env.combat.state.dungeon_clears[DID] = 9
	env.combat.start_dungeon(DID)
	var base_interval: float = env.combat.hero_stats().interval
	var d: Dictionary = env.combat.dungeon_def(DID)
	env.combat._dungeon_complete(d)
	assert_eq(env.combat.dungeon_clears(DID), 10)
	assert_true(env.mods.has_source("dungeon:" + DID), "traguardo 10: +% velocità nel dungeon")
	env.combat._st_dirty = true
	assert_lt(float(env.combat.hero_stats().interval), base_interval, "più veloce DENTRO il dungeon")
	env.combat.stop()
	assert_almost_eq(float(env.combat.hero_stats().interval), hit0, 1e-9, "fuori dal dungeon non cambia")
	# 250 completamenti: titolo
	env.combat.state.dungeon_clears[DID] = 249
	env.combat._dungeon_complete(d)
	assert_true((env.state.titles as Array).has("title_dungeon_" + DID))


func test_bonus_bottino_dungeon() -> void:
	var env: Object = _hero(20)
	_open(env)
	var d: Dictionary = env.combat.dungeon_def(DID)
	var g0: int = env.bank.gold_n
	env.combat._dungeon_complete(d)
	var plain: int = env.bank.gold_n - g0
	env.mods.set_source("t", [{"key": "dungeon_loot_pct:" + DID, "value": 50, "mode": "add"}])
	g0 = env.bank.gold_n
	env.combat._dungeon_complete(d)
	assert_almost_eq(float(env.bank.gold_n - g0), float(plain) * 1.5, 1.0)


func test_boss_del_dungeon_senza_doppioni() -> void:
	var env: Object = _hero(20)
	var d: Dictionary = env.combat.dungeon_def(DID)
	var boss: Dictionary = DataRegistry.get_def("monsters", str(d.boss))
	var res: Dictionary = env.combat.loot_roll(str(boss.drop_table), true)
	assert_false((res.crates as Array).has(str(d.completion_reward.crates[0].id)), "la cassa della zona viene dal premio di fine dungeon")
	for it in res.items:
		assert_false(str(it.id).begins_with("mm_"), "niente materiali garantiti doppi")


func test_ondate_con_bonus_di_livello() -> void:
	var env: Object = _hero(20)
	var d: Dictionary = env.combat.dungeon_def(DID)
	var first: Dictionary = env.combat._wave_mon(d, 0)
	var base: Dictionary = DataRegistry.get_def("monsters", str(d.waves[0].monster))
	assert_eq(int(first.level), int(base.level) + int(d.waves[0].level_bonus))
	assert_gt(float(first.stats.hp), float(base.stats.hp))
	var boss: Dictionary = env.combat._wave_mon(d, (d.waves as Array).size() - 1)
	assert_eq(str(boss.id), str(d.boss))
	assert_eq(boss.level, DataRegistry.get_def("monsters", str(d.boss)).level, "il boss non ha bonus")


func test_offline_dungeon_come_il_tick() -> void:
	var secs := 3600.0
	var ticks_clears := 0
	var env: Object = _hero(20, 3, 21)
	_open(env)
	env.combat.start_dungeon(DID)
	for i in int(secs / FixedStepClock.STEP):
		env.sim.tick(FixedStepClock.STEP)
	ticks_clears = env.combat.dungeon_clears(DID)
	var env2: Object = _hero(20, 3, 22)
	_open(env2)
	env2.combat.start_dungeon(DID)
	var rep: Dictionary = env2.combat.simulate_offline(secs)
	var off_clears: int = env2.combat.dungeon_clears(DID)
	assert_gt(ticks_clears, 3)
	assert_eq(int(rep.get("runs", -1)), off_clears)
	assert_almost_eq(float(off_clears), float(ticks_clears), maxf(1.0, float(ticks_clears) * 0.06), "completamenti: offline vs tick")
	assert_gt(env2.bank.gold_n, 0)


func test_incursioni_elenco_e_disponibilita() -> void:
	var env: Object = _hero(20)
	var raids: Array = env.combat.raids()
	assert_eq(raids.size(), 3)
	for r in raids:
		assert_false(r.unlocked, "senza gettone della missione e livello l'incursione non è disponibile")
