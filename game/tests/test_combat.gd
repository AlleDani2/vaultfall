extends GutTest
## M3: CombatSystem — statistiche (contro i valori di riferimento), tick vs stima offline, morte, drop, equipaggiamento.
## Bank e skills sono finti con le stesse firme dei contratti (docs/audit_2026-10-22/17_CONTRATTI_TRA_SISTEMI.md).

const SimFx := preload("res://tests/helpers/sim_fixtures.gd")
const _GameStateScript := preload("res://src/autoload/GameState.gd")


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var inst: Dictionary = {}
	var gold_n: int = 0
	var counter: int = 0
	func _init() -> void:
		id = "bank"
	func add(def_id: String, qty: int, _source: String = "") -> int:
		stacks[def_id] = int(stacks.get(def_id, 0)) + qty
		return qty
	func remove(def_id: String, qty: int) -> bool:
		if int(stacks.get(def_id, 0)) < qty:
			return false
		stacks[def_id] = int(stacks[def_id]) - qty
		return true
	func count(def_id: String) -> int:
		return int(stacks.get(def_id, 0))
	func has(def_id: String, qty: int = 1) -> bool:
		return count(def_id) >= qty
	func add_instance(i: Dictionary) -> String:
		counter += 1
		var uid := "i_%06d" % counter
		i["uid"] = uid
		inst[uid] = i
		return uid
	func get_instance(uid: String) -> Dictionary:
		return inst.get(uid, {})
	func remove_instance(uid: String) -> bool:
		return inst.erase(uid)
	func list_instances() -> Array:
		return inst.values()
	func add_gold(n: int) -> void:
		gold_n += n
	func spend_gold(n: int) -> bool:
		if gold_n < n:
			return false
		gold_n -= n
		return true


class FakeSkills extends GameSystem:
	var levels: Dictionary = {"hero": 1}
	var xp_total: float = 0.0
	func _init() -> void:
		id = "skills"
	func level(skill_id: String) -> int:
		return int(levels.get(skill_id, 1))
	func add_xp(_skill_id: String, amount: float) -> void:
		xp_total += amount
	func stop() -> void:
		pass


var sim: Simulation
var state: Dictionary
var bank: FakeBank
var skills: FakeSkills
var combat: CombatSystem
var mods: ModifierStack


func _make(seed_v: int = 7, hero_level: int = 5, cls: String = "warrior") -> void:
	state = _GameStateScript.default_state()
	mods = ModifierStack.new()
	mods.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx := SystemContext.make(DataRegistry, state, mods, RngStreams.new(seed_v), EventBus)
	bank = FakeBank.new()
	skills = FakeSkills.new()
	skills.levels["hero"] = hero_level
	combat = CombatSystem.new()
	sim = Simulation.new()
	sim.setup(ctx, [combat, bank, skills])
	sim.bind_state(state)
	combat.state["class"] = cls


func _give(def_id: String, quality: String = "normal", rank: int = 0) -> String:
	return bank.add_instance({"def": def_id, "quality": quality, "sockets": [], "rank": rank})


func _equip_set(cls: String, t: int) -> void:
	for gid in SimFx.gear_ids(cls, t):
		combat.equip(_give(gid))
	var g: Dictionary = SimFx.CLASS_GEAR[cls]
	if g.ammo != "":
		var ammo_id: String = ("arrow_" + SimFx.WOODS[t - 1]) if g.ammo == "arrow" else ("rune_t%d" % t)
		bank.add(ammo_id, 100000, "test")
		combat.equip_ammo(ammo_id)


func _run_ticks(n: int) -> void:
	for i in n:
		sim.tick(FixedStepClock.STEP)


func test_statistiche_come_il_simulatore() -> void:
	for cls in ["warrior", "ranger", "arcanist"]:
		_make(1, 10, cls)
		_equip_set(cls, 2)
		var ref: Dictionary = SimFx.hero(DataRegistry, cls, 10, 2)
		var got := combat.hero_stats()
		for key in ["hp", "ap", "acc", "eva", "arm", "ward", "max_hit", "interval", "crit", "critd"]:
			assert_almost_eq(float(got[key]), float(ref[key]), absf(float(ref[key])) * 1e-6 + 1e-9, "%s %s" % [cls, key])
		assert_eq(got.style, ref.style)


func test_equip_modificatori_e_slot() -> void:
	_make(1, 10)
	var amu := _give("amulet_wrath_t1")
	var base: float = combat.hero_stats().max_hit
	assert_true(combat.equip(amu))
	assert_true(mods.has_source("equip:amulet"), "bonus via Modifiers con fonte equip:<slot>")
	assert_eq(combat.equipped("amulet"), amu)
	assert_gt(float(combat.hero_stats().max_hit), base)
	combat.unequip("amulet")
	assert_false(mods.has_source("equip:amulet"))
	assert_almost_eq(float(combat.hero_stats().max_hit), base, 1e-9)
	var r1 := _give("ring_might_t1")
	var r2 := _give("ring_might_t1")
	var r3 := _give("ring_might_t1")
	combat.equip(r1)
	combat.equip(r2)
	assert_eq(combat.equipped("ring"), r1)
	assert_eq(combat.equipped("ring2"), r2)
	combat.equip(r3)
	assert_eq(combat.equipped("ring"), r3)
	combat.equip(_give("shield_copper"))
	assert_ne(combat.equipped("offhand"), "")
	combat.equip(_give("greatsword_copper"))
	assert_eq(combat.equipped("offhand"), "", "l'arma a due mani libera la mano secondaria")
	assert_false(combat.equip(_give("shield_copper")))
	_make(1, 1)
	assert_false(combat.equip(_give("sword_iron")), "livello Eroe insufficiente")
	_make(1, 10)
	var s := _give("sword_copper")
	combat.equip(s)
	bank.remove_instance(s)
	for i in 12:
		combat.tick(0.1)
	assert_eq(combat.equipped("weapon"), "", "istanza sparita dal bank: slot svuotato")


func test_qualita_e_rango() -> void:
	_make(1, 10)
	combat.equip(_give("sword_copper"))
	var m0: float = combat.hero_stats().max_hit
	combat.unequip("weapon")
	combat.equip(_give("sword_copper", "masterwork", 2))
	var m1: float = combat.hero_stats().max_hit
	var base := 1.28 * pow(1.04, 2.0)    # qualità × rango sul danno; la potenza d'attacco dell'arma cresce solo con la qualità
	assert_between(m1 / m0, base, base * 1.03)


func test_tick_e_offline_concordano() -> void:
	var secs := 6000.0
	var res: Array = []
	for mode in ["tick", "offline"]:
		_make(11, 5)
		_equip_set("warrior", 1)
		bank.add("food_bleak", 100000, "test")
		combat.set_food(0, "food_bleak")
		state.unlocks.append("shop:auto_eat_3")
		assert_true(combat.start("millbrook", ""))
		if mode == "tick":
			_run_ticks(int(secs / FixedStepClock.STEP))
		else:
			var rep := combat.simulate_offline(secs)
			assert_eq(rep.stopped, "", "nessuna morte attesa")
		res.append({"kills": int(state.stats.kills), "xp": skills.xp_total, "gold": bank.gold_n})
	assert_gt(res[0].kills, 300)
	assert_almost_eq(float(res[1].kills), float(res[0].kills), float(res[0].kills) * 0.02, "uccisioni")
	assert_almost_eq(float(res[1].xp), float(res[0].xp), float(res[0].xp) * 0.03, "XP")
	assert_almost_eq(float(res[1].gold), float(res[0].gold), float(res[0].gold) * 0.05, "oro")


func test_morte_e_recupero() -> void:
	_make(3, 1)
	assert_true(combat.start("millbrook", "hornet_queen"))
	var flag := [false]
	var watcher := func(_c: String) -> void: flag[0] = true
	EventBus.player_died.connect(watcher)
	for i in 6000:
		sim.tick(0.1)
		if flag[0]:
			break
	EventBus.player_died.disconnect(watcher)
	assert_true(flag[0], "il livello 1 contro la Regina Vespa muore")
	assert_eq(combat.hp(), 0.0)
	var delay: float = Formulas.k().combat.rules.death_restart_delay_s
	_run_ticks(int(delay / 0.1) + 2)
	assert_gt(combat.hp(), 0.0, "ripartito dopo il ritardo")
	assert_gt(float(combat.state.wounded_s), 0.0, "Ferito")
	assert_true(combat.hero_stats().wounded)
	assert_true(combat.in_combat(), "il combattimento riprende")
	assert_eq(bank.inst.size(), 0, "nessun oggetto perso")


func test_cibo_automatico() -> void:
	_make(5, 5)
	bank.add("food_bleak", 50, "test")
	combat.set_food(0, "food_bleak")
	var mx := combat.max_hp()
	combat.state["hp"] = mx * 0.05
	assert_true(combat.eat_food(true))
	assert_gt(combat.hp(), mx * 0.05)
	assert_eq(bank.count("food_bleak"), 49)
	combat.state["hp"] = mx * 0.05
	assert_true(combat.start("millbrook", "mud_slime"))
	_run_ticks(3)
	assert_lt(bank.count("food_bleak"), 49, "mangia da solo sotto soglia")


func test_drop_distribuzione_e_casse() -> void:
	_make(5, 5)
	var table: Dictionary = DataRegistry.get_def("drop_tables", "drops_hornet_queen")
	var n := 20000
	var fang := 0
	var crates := 0
	for i in n:
		var r := combat.loot_roll("drops_hornet_queen")
		for it in r.items:
			if it.id == "mm_rough_fang":
				fang += 1
				assert_between(int(it.qty), 4, 8)
		crates += (r.crates as Array).size()
	assert_eq(fang, n, "drop garantito (chance 1,0)")
	assert_almost_eq(float(crates) / n, float(table.crate.chance), 0.02, "cassa del boss ~ 1/4")
	_make(99, 5)
	var a := combat.loot_roll("drops_mud_slime")
	_make(99, 5)
	var b := combat.loot_roll("drops_mud_slime")
	assert_eq(a, b, "stesso seed, stessi drop")
	_make(5, 5)
	var found: Array = []
	var cb := func(cid: String, src: String) -> void: found.append([cid, src])
	EventBus.crate_found.connect(cb)
	var killed: Array = []
	var kb := func(mid: String, _d: Array) -> void: killed.append(mid)
	EventBus.monster_killed.connect(kb)
	var mon: Dictionary = DataRegistry.get_def("monsters", "hornet_queen")
	for i in 40:
		combat._kill({"enemy": {}}, mon)
	EventBus.crate_found.disconnect(cb)
	EventBus.monster_killed.disconnect(kb)
	assert_gt(found.size(), 2, "casse trovate")
	assert_eq(found[0][0], "crate_millbrook")
	assert_eq(found[0][1], "combat:hornet_queen")
	assert_eq(killed.size(), 40)
	assert_gt(bank.count("mm_rough_fang"), 100)
	assert_gt(bank.gold_n, 0)
	assert_gt(skills.xp_total, 0.0)
	assert_eq(combat.kills_of("hornet_queen"), 40)


func test_zone_sblocco() -> void:
	_make(5, 1)
	assert_true(combat.zone_unlocked("millbrook"))
	assert_false(combat.zone_unlocked("saltreach"))
	assert_false(combat.start("saltreach"))
	skills.levels["hero"] = 20
	assert_false(combat.zone_unlocked("saltreach"), "serve anche il gettone della missione")
	state.unlocks.append("zone:saltreach")
	assert_true(combat.zone_unlocked("saltreach"))
	assert_false(combat.start("millbrook", "armored_crab"), "mostro non della zona")
	assert_true(combat.start("saltreach"))
	assert_true(combat.in_combat())
	combat.stop()
	assert_false(combat.in_combat())


func test_munizioni_obbligatorie() -> void:
	_make(5, 5, "ranger")
	combat.equip(_give("shortbow_pine"))
	assert_false(combat.start("millbrook"), "senza frecce non si parte")
	bank.add("arrow_pine", 30, "test")
	assert_true(combat.equip_ammo("arrow_pine"))
	assert_eq(combat.ammo_qty(), 30)
	assert_true(combat.start("millbrook", "mud_slime"))
	_run_ticks(100)
	assert_lt(combat.ammo_qty(), 30, "consumo per attacco")
	combat.unequip("ammo")
	assert_gt(bank.count("arrow_pine"), 0)


func test_sicuro_in_idle_e_ttk() -> void:
	_make(5, 5)
	_equip_set("warrior", 1)
	var s := combat.idle_safety("mud_slime")
	assert_true(["green", "yellow", "red"].has(s.level))
	var e := combat.estimate("mud_slime")
	assert_between(float(e.ttk), 2.0, 16.0, "TTK nel range del bilanciamento")
