extends GutTest
## SkillSystem (docs/04, docs/03 §2): formule, regole, offline analitico (spike S4) e prestazioni.
## Il bank è un finto sistema con le STESSE firme di docs/audit_2026-10-22/17_CONTRATTI_TRA_SISTEMI.md.


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var instances: Array = []
	var gold_amount: int = 0
	var max_stacks: int = 1000000       # "posti": numero massimo di voci diverse
	var next_uid: int = 0
	func _init() -> void:
		id = "bank"
	func add(def_id: String, qty: int, source: String = "") -> int:
		if qty <= 0:
			return 0
		if not stacks.has(def_id) and stacks.size() >= max_stacks:
			return 0
		stacks[def_id] = int(stacks.get(def_id, 0)) + qty
		ctx.events.item_gained.emit(def_id, qty, source)
		return qty
	func remove(def_id: String, qty: int) -> bool:
		if int(stacks.get(def_id, 0)) < qty:
			return false
		stacks[def_id] -= qty
		return true
	func count(def_id: String) -> int:
		return int(stacks.get(def_id, 0))
	func has(def_id: String, qty: int = 1) -> bool:
		return count(def_id) >= qty
	func add_instance(inst: Dictionary) -> String:
		if instances.size() >= 100000:
			return ""
		next_uid += 1
		var uid := "i_%06d" % next_uid
		var c := inst.duplicate(true)
		c["uid"] = uid
		instances.append(c)
		return uid
	func get_instance(uid: String) -> Dictionary:
		for i in instances:
			if i.uid == uid:
				return i
		return {}
	func add_gold(n: int) -> void:
		gold_amount += n
	func spend_gold(n: int) -> bool:
		if gold_amount < n:
			return false
		gold_amount -= n
		return true
	func gold() -> int:
		return gold_amount


const _GS := preload("res://src/autoload/GameState.gd")


## Mondo isolato: SkillSystem + finto bank + modificatori/RNG propri.
func _world(seed_value: int = 7) -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(seed_value), EventBus)
	var sim := Simulation.new()
	var bank := FakeBank.new()
	var sk := SkillSystem.new()
	sim.setup(ctx, [sk, bank])
	sim.bind_state(state)
	return {"sim": sim, "ctx": ctx, "sk": sk, "bank": bank, "state": state, "stack": stack}


func _run(w: Dictionary, seconds: float) -> void:
	var sim: Simulation = w.sim
	var n := int(round(seconds / 0.1))
	for i in n:
		sim.tick(0.1)


# ------------------------------------------------------------------ XP e livelli

func test_livelli_seguono_xp_to_next() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	watch_signals(EventBus)
	sk.add_xp("woodcutting", float(Formulas.xp_to_next(1)) - 1.0)
	assert_eq(sk.level("woodcutting"), 1)
	sk.add_xp("woodcutting", 1.0)
	assert_eq(sk.level("woodcutting"), 2)
	assert_signal_emitted_with_parameters(EventBus, "level_up", ["woodcutting", 2])
	sk.add_xp("woodcutting", float(Formulas.xp_total_for_level(10)))
	assert_eq(sk.level("woodcutting"), 10, "XP totali del livello 10 -> livello 10 (somma su piu' livelli in un colpo)")
	assert_eq(sk.record_level("woodcutting"), 10)


func test_livello_massimo_dai_dati() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	sk.add_xp("mining", 1.0e9)
	assert_eq(sk.level("mining"), int(DataRegistry.constants.level_cap))
	assert_eq(sk.xp_progress("mining")[1], 0.0, "al massimo non c'e' un livello successivo")


func test_xp_con_bonus_ed_eco() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var stack: ModifierStack = w.stack
	stack.set_source("t", [{"key": "skill_xp_pct:all", "value": 20, "mode": "add"}, {"key": "skill_xp_pct:mining", "value": 10, "mode": "more"}])
	sk.add_xp("mining", 100.0, true)
	assert_almost_eq(sk.xp("mining"), 100.0 * 1.2 * 1.1, 1e-6, "add sommati poi more moltiplicati (docs/14)")
	# Eco: livello sotto il record -> XP moltiplicati
	var st: Dictionary = w.state.skills.mining
	st["record_level"] = 50
	var before := sk.xp("mining")
	sk.add_xp("mining", 100.0, true)
	var lvl := sk.level("mining")
	assert_almost_eq(sk.xp("mining") - before, 100.0 * 1.2 * 1.1 * Formulas.echo_multiplier(lvl, 50), 1e-6)


# ------------------------------------------------------------------ avvio / requisiti

func test_requisiti_e_stati_non_avviabili() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	assert_false(sk.start("mine_tin"), "livello 10 richiesto")
	assert_eq(sk.can_start("mine_tin"), "UI_SKILLS_REASON_LEVEL")
	assert_false(sk.start("smelt_copper"), "mancano i minerali")
	assert_eq(sk.can_start("smelt_copper"), "UI_SKILLS_REASON_MATERIALS")
	assert_false(sk.start("farm_potato"), "la Coltivazione ha il proprio sistema")
	assert_false(sk.start("non_esiste"))
	assert_true(sk.start("wc_pine"))
	assert_eq(sk.current_action(), "wc_pine")
	sk.stop()
	assert_eq(sk.current_action(), "")


func test_start_sostituisce_il_combattimento() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	w.state.activity.merge({"type": "combat", "zone": "millbrook"})
	assert_true(sk.start("wc_pine"))
	assert_eq(w.state.activity.type, "skill")
	assert_false(w.state.activity.has("zone"))


func test_tick_ignora_il_combattimento() -> void:
	var w := _world()
	w.state.activity.merge({"type": "combat", "zone": "millbrook"})
	_run(w, 5.0)
	assert_eq(w.state.activity.type, "combat")
	assert_eq((w.bank as FakeBank).count("log_pine"), 0)


# ------------------------------------------------------------------ raccolta a tick

func test_raccolta_tempo_xp_maestria_e_segnali() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	watch_signals(EventBus)
	sk.start("wc_pine")
	_run(w, 2.9)
	assert_eq(bank.count("log_pine"), 0, "prima dei 3,0 s non e' completa")
	assert_between(sk.cycle_fraction(), 0.9, 1.0)
	_run(w, 0.1)
	assert_eq(bank.count("log_pine"), 1)
	assert_almost_eq(sk.xp("woodcutting"), 7.0, 1e-9, "xp dai dati")
	assert_almost_eq(sk.mastery_xp("wc_pine"), 3.0, 1e-9, "XP maestria = durata base")
	assert_signal_emit_count(EventBus, "action_completed", 1)
	assert_signal_emit_count(EventBus, "xp_gained", 1)
	assert_signal_emitted_with_parameters(EventBus, "item_gained", ["log_pine", 1, "skill:woodcutting"])
	_run(w, 27.0)
	assert_eq(bank.count("log_pine"), 10, "un ciclo ogni 3 s")


func test_velocita_dai_modificatori() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	w.stack.set_source("t", [{"key": "skill_haste_pct:woodcutting", "value": 50, "mode": "add"}])
	assert_almost_eq(sk.duration_of("wc_pine"), 2.0, 1e-9, "durata = base / (1 + haste/100)")
	w.stack.set_source("t", [{"key": "skill_haste_pct:woodcutting", "value": 50, "mode": "add"}, {"key": "skill_haste_pct:gathering", "value": 50, "mode": "add"}])
	assert_almost_eq(sk.duration_of("wc_pine"), 1.5, 1e-9, "ambiti sommati: skill + gruppo")
	sk.start("wc_pine")
	_run(w, 3.0)
	assert_eq((w.bank as FakeBank).count("log_pine"), 2)


func test_doppio_e_oltre_cento() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	w.stack.set_source("t", [{"key": "skill_double_pct:woodcutting", "value": 100, "mode": "add"}])
	sk.start("wc_pine")
	_run(w, 30.0)
	assert_eq(bank.count("log_pine"), 20, "100% di doppio = sempre 2 tronchi")
	bank.stacks.clear()
	w.stack.set_source("t", [{"key": "skill_double_pct:woodcutting", "value": 250, "mode": "add"}])
	_run(w, 3.0 * 200)
	var avg := float(bank.count("log_pine")) / 200.0
	assert_between(avg, 3.3, 3.7, "250% = 3 garantiti + 50% di un quarto")


func test_doppio_dalla_maestria_per_livello() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	assert_almost_eq(sk.mastery_double_pct(10), 5.0, 1e-9, "0,5% per livello")
	assert_almost_eq(sk.mastery_double_pct(DataRegistry.constants.mastery.cap), 25.0, 1e-9, "max +25%")


func test_secondari_e_casse_con_rng_loot() -> void:
	var w := _world(3)
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	watch_signals(EventBus)
	# nido d'uccello 0,5% per ciclo: in 20000 cicli ~100
	sk.start("wc_pine")
	w.stack.set_source("t", [{"key": "skill_haste_pct:all", "value": 2900, "mode": "add"}])      # 0,1 s a ciclo
	_run(w, 2000.0)
	var nests := bank.count("bird_nest")
	assert_between(nests, 80, 200, "secondari ~ 0,5% dei cicli (+25% e velocita' dalla maestria)")
	var crates: int = get_signal_emit_count(EventBus, "crate_found")
	assert_between(crates, 1, 40, "la cassa dipende dal TEMPO effettivo (docs/04 §9), non dal numero di azioni")


func test_cassa_per_ora_non_cresce_con_la_velocita() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var base_per_h := float(sk.hourly("wc_pine").crates)
	w.stack.set_source("t", [{"key": "skill_haste_pct:all", "value": 100, "mode": "add"}])
	var fast_per_h := float(sk.hourly("wc_pine").crates)
	assert_almost_eq(fast_per_h, base_per_h, 1e-9, "stesse casse all'ora anche con velocita' doppia")
	assert_almost_eq(base_per_h, 1.5, 0.01, "~ 1 cassa ogni 40 minuti")
	w.stack.set_source("t", [{"key": "crate_find_pct:all", "value": 50, "mode": "add"}])
	assert_almost_eq(float(sk.hourly("wc_pine").crates), base_per_h * 1.5, 1e-6, "crate_find_pct e' relativo")
	w.stack.set_source("t", [{"key": "crate_find_pct:all", "value": 900, "mode": "add"}])
	assert_almost_eq(float(sk.hourly("wc_pine").crates), base_per_h * 3.0, 1e-6, "cap +200% dal catalogo")


# ------------------------------------------------------------------ produzione

func test_produzione_consuma_e_si_ferma() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	bank.stacks["ore_copper"] = 3
	watch_signals(EventBus)
	assert_true(sk.start("smelt_copper"))
	_run(w, 6.0)
	assert_eq(bank.count("bar_copper"), 3)
	assert_eq(bank.count("ore_copper"), 0)
	assert_eq(sk.current_action(), "smelt_copper", "ancora attiva finche' il ciclo successivo non scade")
	_run(w, 2.0)
	assert_eq(sk.current_action(), "", "senza ingredienti si ferma")
	assert_signal_emitted(EventBus, "notice")
	assert_eq(bank.count("bar_copper"), 3)


func test_risparmio_ingredienti_con_tetto() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	w.stack.set_source("t", [{"key": "skill_save_pct:all", "value": 500, "mode": "add"}])
	assert_almost_eq(float(sk.profile_of("smelt_copper").save_pct), 50.0, 1e-9, "cap 50% (R-PR-7)")
	var bank: FakeBank = w.bank
	bank.stacks["ore_copper"] = 100000
	sk.start("smelt_copper")
	_run(w, 2.0 * 2000)
	var made := bank.count("bar_copper")
	var used := 100000 - bank.count("ore_copper")
	assert_between(float(used) / float(made), 0.45, 0.55, "metà dei cicli non consuma")


func test_burn_probabilita_esatta() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	w.state.skills.cooking.level = 6                      # d = 5
	w.state.mastery["cook_bleak"] = {"xp": 0.0, "level": 10}
	sk._cache.clear()
	assert_almost_eq(float(sk.profile_of("cook_bleak").burn), 0.30 - 0.05 - 0.05, 1e-9)
	w.state.skills.cooking.level = 60
	sk._cache.clear()
	assert_almost_eq(float(sk.profile_of("cook_bleak").burn), 0.0, 1e-9, "mai negativa")


func test_cucina_produce_cibo_bruciato() -> void:
	var w := _world(5)
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	watch_signals(EventBus)
	bank.stacks["fish_raw_bleak"] = 100000
	sk.start("cook_bleak")
	_run(w, 2.5 * 1000)
	var burnt := bank.count("burnt_food")
	var good := bank.count("food_bleak")
	var cycles: int = get_signal_emit_count(EventBus, "action_completed")
	assert_gt(burnt, 0)
	assert_between(burnt + good, cycles, int(cycles * 1.3), "ogni ciclo produce cibo o cibo bruciato (piu' il doppio di maestria)")
	assert_between(float(burnt) / float(cycles), 0.02, 0.30, "30% a livello 1, scende con maestria e livello")


## Questi test misurano la RESA ripetuta di un pezzo non impilabile: con `single_craft` (una costruzione per volta,
## docs/04 §8.2, test_attrezzi.gd) l'azione si fermerebbe dopo una. Si spegne il flag solo per questa azione e fino a fine test.
func _no_single(aid: String) -> void:
	var a: Dictionary = DataRegistry.action(aid)
	a["single_craft"] = false
	_restore.append(aid)


var _restore: Array = []


func after_each() -> void:
	for aid in _restore:
		DataRegistry.action(str(aid))["single_craft"] = true
	_restore.clear()


func test_qualita_equipaggiamento_in_istanze() -> void:
	var w := _world(9)
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	w.state.skills.smithing.level = 60       # molti livelli oltre il requisito: qualita' alta possibile
	bank.stacks["bar_copper"] = 1000
	watch_signals(EventBus)
	sk._cache.clear()
	var q: Array = sk.profile_of("smith_plate_helm_copper").quality
	var expect := Formulas.quality_chances(60 - 4, 1)
	assert_almost_eq(float(q[3]), float(expect[3]), 1e-9, "stesse probabilita' di Formulas.quality_chances")
	assert_almost_eq(float(q[0]) + float(q[1]) + float(q[2]) + float(q[3]), 1.0, 1e-9)
	_no_single("smith_plate_helm_copper")
	sk.start("smith_plate_helm_copper")
	_run(w, 3.0 * 100)
	var cyc: int = get_signal_emit_count(EventBus, "action_completed")
	assert_between(bank.instances.size(), cyc, int(cyc * 1.3), "gli oggetti non impilabili sono istanze")
	assert_eq(bank.instances[0].def, "plate_helm_copper")
	assert_eq(bank.count("bar_copper"), 1000 - 2 * cyc, "2 lingotti per ciclo")
	var qualities := {}
	for i in bank.instances:
		qualities[i.quality] = true
	assert_gt(qualities.size(), 1, "con 56 livelli oltre il requisito non escono solo Normali")


# ------------------------------------------------------------------ maestria

func test_maestria_livelli_e_traguardi() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	assert_eq(sk.mastery_level("wc_pine"), 1)
	var need1 := float(Formulas.mastery_to_next(1))
	sk._grant_mastery("wc_pine", need1)
	assert_eq(sk.mastery_level("wc_pine"), 2)
	var tot := 0.0
	for m in range(1, 49):
		tot += float(Formulas.mastery_to_next(m))
	sk._grant_mastery("wc_pine", tot)
	assert_eq(sk.mastery_level("wc_pine"), 49)
	sk._grant_mastery("wc_pine", 1.0e9)
	assert_eq(sk.mastery_level("wc_pine"), 50, "tetto 50")
	var t10 := sk.mastery_milestone_totals(10)
	assert_almost_eq(float(t10.action_haste_pct), 5.0, 1e-9)
	var t30 := sk.mastery_milestone_totals(30)
	assert_almost_eq(float(t30.action_haste_pct), 15.0, 1e-9, "5 (Lv10) + 10 (Lv30)")
	assert_almost_eq(float(t30.action_xp_pct), 5.0, 1e-9)
	var t50 := sk.mastery_milestone_totals(50)
	assert_true(t50.has("action_mastered"))
	assert_almost_eq(float(t50.action_secondary_pct), 25.0, 1e-9)


func test_maestria_cambia_il_profilo() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var d0 := sk.duration_of("wc_pine")
	sk._grant_mastery("wc_pine", 1.0e9)
	assert_almost_eq(sk.duration_of("wc_pine"), d0 / 1.15, 1e-9, "+15% velocita' da maestria 30")
	assert_almost_eq(float(sk.profile_of("wc_pine").extra_yield), 1.0, 1e-9, "Padronanza raccolta: +1 resa")
	assert_almost_eq(float(sk.profile_of("wc_pine").double_pct), 25.0, 1e-9)
	var xp0 := 7.0
	assert_almost_eq(float(sk.profile_of("wc_pine").xp), xp0 * 1.05, 1e-9, "+5% XP azione")


func test_padronanza_produzione_risparmia() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	sk._grant_mastery("smelt_copper", 1.0e9)
	assert_almost_eq(float(sk.profile_of("smelt_copper").save_pct), 10.0, 1e-9, "10% di non consumare")


# ------------------------------------------------------------------ borseggio

func test_borseggio_successo_e_stordimento() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var p := sk.profile_of("thief_farmer")
	assert_almost_eq(float(p.success), 0.70 + 0.003 * 1.0, 1e-9, "70% + 0,3% x maestria")
	w.state.skills.thievery.level = 11
	sk._cache.clear()
	assert_almost_eq(float(sk.profile_of("thief_farmer").success), 0.70 + 0.10 + 0.003, 1e-9)
	w.state.skills.thievery.level = 100
	sk._cache.clear()
	assert_almost_eq(float(sk.profile_of("thief_farmer").success), 0.95, 1e-9, "tetto 95%")
	w.stack.set_source("t", [{"key": "thievery_stun_reduction_pct", "value": 50, "mode": "add"}])
	assert_almost_eq(float(sk.profile_of("thief_farmer").stun_s), 1.5, 1e-9)


func test_borseggio_oro_e_stun_a_tick() -> void:
	var w := _world(4)
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	sk.start("thief_farmer")
	var seen_stun := false
	for i in 20000:
		w.sim.tick(0.1)
		if sk.stun_remaining() > 0.0:
			seen_stun = true
	assert_true(seen_stun, "i fallimenti stordiscono")
	assert_gt(bank.gold(), 0)
	var cycles_xp := sk.xp("thievery") / 10.0
	assert_between(cycles_xp, 400.0, 760.0, "XP solo sui successi: ~ 2000 s / (3 s + 30% x 3 s) x 70%")


# ------------------------------------------------------------------ talenti

func test_talenti_scelta_e_respec() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	assert_eq(sk.pending_perk_tiers("woodcutting"), [])
	assert_false(sk.choose_perk("woodcutting", 10, "a"), "livello non raggiunto")
	sk.add_xp("woodcutting", float(Formulas.xp_total_for_level(10)))
	assert_eq(sk.pending_perk_tiers("woodcutting"), [10])
	assert_true(sk.choose_perk("woodcutting", 10, "b"))
	assert_false(sk.choose_perk("woodcutting", 10, "a"), "una sola scelta per tier senza Stelle")
	assert_eq(sk.pending_perk_tiers("woodcutting"), [])
	assert_almost_eq(w.stack.total_add("skill_double_pct", ["woodcutting"]), 3.0, 1e-9, "talento B Lv10 = +3% doppio")
	bank.gold_amount = 100
	assert_eq(sk.respec_cost("woodcutting", 10), 1000 * 10)
	assert_false(sk.respec_perk("woodcutting", 10), "oro insufficiente")
	bank.gold_amount = 20000
	assert_true(sk.respec_perk("woodcutting", 10))
	assert_eq(bank.gold_amount, 10000)
	assert_almost_eq(w.stack.total_add("skill_double_pct", ["woodcutting"]), 0.0, 1e-9)
	w.state.skills.woodcutting.stars = 3
	assert_true(sk.choose_perk("woodcutting", 10, "a"))
	assert_true(sk.choose_perk("woodcutting", 10, "c"), "con 3 Stelle: 2 talenti su 3")
	assert_false(sk.choose_perk("woodcutting", 10, "b"))


# ------------------------------------------------------------------ attrezzi

func test_attrezzo_equipaggiato() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var bank: FakeBank = w.bank
	var uid := bank.add_instance({"def": "pickaxe_iron", "quality": "normal"})
	w.state.equipment["tools"] = {"mining": uid}
	sk.refresh_tools()
	assert_almost_eq(w.stack.total_add("skill_haste_pct", ["mining"]), 0.0, 1e-9, "livello 20 richiesto: nessun bonus a livello 1")
	w.state.skills.mining.level = 20
	sk.refresh_tools()
	assert_almost_eq(w.stack.total_add("skill_haste_pct", ["mining"]), 8.0, 1e-9)
	assert_almost_eq(w.stack.total_add("skill_double_pct", ["mining"]), 2.0, 1e-9)


# ------------------------------------------------------------------ salvataggio

func test_salvataggio_e_ripresa() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	sk.start("wc_pine")
	_run(w, 31.0)
	var xp_before := sk.xp("woodcutting")
	w.sim.collect_state(w.state)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w.state))
	var w2 := _world()
	(w2.state as Dictionary).clear()
	(w2.state as Dictionary).merge(saved)
	SaveCodec.normalize(w2.state, w2.sim.int_paths())
	w2.sim.bind_state(w2.state)
	var sk2: SkillSystem = w2.sk
	assert_almost_eq(sk2.xp("woodcutting"), xp_before, 1e-9)
	assert_eq(sk2.current_action(), "wc_pine")
	assert_eq(typeof(sk2.level("woodcutting")), TYPE_INT)
	assert_true(sk2.mastery_xp("wc_pine") > 0.0)


# ------------------------------------------------------------------ offline analitico vs tick (spike S4)

func _pair(seed_value: int, setup: Callable) -> Array:
	var a := _world(seed_value)
	var b := _world(seed_value)
	setup.call(a)
	setup.call(b)
	return [a, b]


func _rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(1.0, maxf(absf(a), absf(b)))


func test_offline_raccolta_analitico_vs_tick() -> void:
	var pair := _pair(21, func(w: Dictionary) -> void:
		w.stack.set_source("t", [{"key": "skill_double_pct:woodcutting", "value": 12, "mode": "add"},
			{"key": "skill_haste_pct:all", "value": 10, "mode": "add"}])
		(w.sk as SkillSystem).start("wc_pine"))
	var hours := 4.0
	_run(pair[0], hours * 3600.0)
	var rep: Dictionary = (pair[1].sim as Simulation).run_offline(hours * 3600.0)
	var bt: FakeBank = pair[0].bank
	var ba: FakeBank = pair[1].bank
	assert_true(rep.has("skills"), "resoconto per il Bentornato")
	assert_lte(_rel(bt.count("log_pine"), ba.count("log_pine")), 0.02, "tronchi: %d tick vs %d analitico" % [bt.count("log_pine"), ba.count("log_pine")])
	assert_lte(_rel((pair[0].sk as SkillSystem).xp("woodcutting"), (pair[1].sk as SkillSystem).xp("woodcutting")), 0.02, "XP")
	assert_lte(absi((pair[0].sk as SkillSystem).level("woodcutting") - (pair[1].sk as SkillSystem).level("woodcutting")), 1, "livello")
	assert_lte(absi((pair[0].sk as SkillSystem).mastery_level("wc_pine") - (pair[1].sk as SkillSystem).mastery_level("wc_pine")), 1, "maestria")
	assert_lte(_rel(bt.count("bird_nest"), ba.count("bird_nest")), 0.5, "secondari (rari): estrazione, stesso ordine di grandezza")
	assert_gt(int(rep.skills.completions), 1000)


func test_offline_produzione_analitico_vs_tick() -> void:
	var pair := _pair(5, func(w: Dictionary) -> void:
		(w.bank as FakeBank).stacks["ore_copper"] = 20000
		(w.sk as SkillSystem).start("smelt_copper"))
	_run(pair[0], 3.0 * 3600.0)
	(pair[1].sim as Simulation).run_offline(3.0 * 3600.0)
	var bt: FakeBank = pair[0].bank
	var ba: FakeBank = pair[1].bank
	assert_lte(_rel(bt.count("bar_copper"), ba.count("bar_copper")), 0.02, "lingotti %d vs %d" % [bt.count("bar_copper"), ba.count("bar_copper")])
	assert_lte(_rel(bt.count("ore_copper"), ba.count("ore_copper")), 0.02, "minerale rimasto")
	assert_lte(_rel((pair[0].sk as SkillSystem).xp("smithing"), (pair[1].sk as SkillSystem).xp("smithing")), 0.02, "XP")


func test_offline_si_ferma_senza_ingredienti() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	(w.bank as FakeBank).stacks["ore_copper"] = 100
	sk.start("smelt_copper")
	var rep: Dictionary = (w.sim as Simulation).run_offline(5.0 * 3600.0)
	assert_eq(rep.skills.stopped, "no_materials")
	assert_between((w.bank as FakeBank).count("bar_copper"), 100, 126, "100 cicli, con il doppio di maestria (max +25%)")
	assert_eq((w.bank as FakeBank).count("ore_copper"), 0)
	assert_eq(sk.current_action(), "", "attivita' terminata")
	assert_between(float(rep.skills.completions), 99.0, 100.0)


func test_offline_borseggio_analitico_vs_tick() -> void:
	var pair := _pair(8, func(w: Dictionary) -> void:
		(w.sk as SkillSystem).start("thief_farmer"))
	_run(pair[0], 6.0 * 3600.0)
	(pair[1].sim as Simulation).run_offline(6.0 * 3600.0)
	var bt: FakeBank = pair[0].bank
	var ba: FakeBank = pair[1].bank
	assert_lte(_rel(bt.gold(), ba.gold()), 0.03, "oro %d vs %d" % [bt.gold(), ba.gold()])
	assert_lte(_rel((pair[0].sk as SkillSystem).xp("thievery"), (pair[1].sk as SkillSystem).xp("thievery")), 0.03, "XP")


func test_offline_limite_ore_dai_dati() -> void:
	var w := _world()
	(w.sk as SkillSystem).start("wc_pine")
	var rep: Dictionary = (w.sim as Simulation).run_offline(100.0 * 3600.0)
	assert_almost_eq(float(rep.skills.seconds), float(DataRegistry.constants.offline.cap_max_h) * 3600.0, 1.0)


func test_offline_non_tocca_il_combattimento() -> void:
	var w := _world()
	w.state.activity.merge({"type": "combat", "zone": "millbrook"})
	var rep: Dictionary = (w.sim as Simulation).run_offline(3600.0)
	assert_false(rep.has("skills"))


func test_perf_offline_24_ore_in_un_secondo() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	var f0 := PerfGate.load_factor()
	var ms_a := INF
	var ms_b := INF
	var w2: Dictionary = {}
	for k in 3:          # migliore di 3, ogni volta con un mondo nuovo
		var w := _world()
		var sk: SkillSystem = w.sk
		(w.bank as FakeBank).stacks["ore_copper"] = 1000000
		sk.start("smelt_copper")
		var t0 := PerfGate.clock_usec()
		(w.sim as Simulation).run_offline(24.0 * 3600.0)
		ms_a = minf(ms_a, (PerfGate.clock_usec() - t0) / 1000.0)
		w2 = _world()
		(w2.sk as SkillSystem).start("wc_pine")
		t0 = PerfGate.clock_usec()
		(w2.sim as Simulation).run_offline(24.0 * 3600.0)
		ms_b = minf(ms_b, (PerfGate.clock_usec() - t0) / 1000.0)
	var f := PerfGate.factor_around(f0)
	PerfGate.assert_time(self, "fonderia: 24 h analitiche (migliore di 3)", ms_a, 1000.0, f)
	PerfGate.assert_time(self, "raccolta: 24 h analitiche (migliore di 3)", ms_b, 1000.0, f)
	assert_gt((w2.sk as SkillSystem).level("woodcutting"), 30, "a 24 h il livello e' salito molto")


func test_offline_qualita_istanze() -> void:
	var w := _world(2)
	var sk: SkillSystem = w.sk
	(w.bank as FakeBank).stacks["bar_copper"] = 5000
	w.state.skills.smithing.level = 40
	sk._cache.clear()
	_no_single("smith_plate_helm_copper")
	sk.start("smith_plate_helm_copper")
	(w.sim as Simulation).run_offline(1.0 * 3600.0)
	var made := (w.bank as FakeBank).instances.size()
	assert_between(made, 1100, 1500, "~ 3600 s / 3 s (piu' maestria)")
	var used := 5000 - (w.bank as FakeBank).count("bar_copper")
	assert_between(float(used) / float(made), 1.5, 2.0, "2 lingotti per ciclo, il doppio da' piu' elmi dello stesso consumo")


func test_senza_bank_non_crasha() -> void:
	var state := _GS.default_state()
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(1), EventBus)
	var sim := Simulation.new()
	var sk := SkillSystem.new()
	sim.setup(ctx, [sk])
	sim.bind_state(state)
	assert_true(sk.start("wc_pine"))
	for i in 100:
		sim.tick(0.1)
	assert_gt(sk.xp("woodcutting"), 0.0)
	sim.run_offline(3600.0)
	assert_gt(sk.level("woodcutting"), 1)
