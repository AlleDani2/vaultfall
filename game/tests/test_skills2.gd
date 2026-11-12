extends GutTest
## M5 mansioni speciali: Coltivazione (FarmingSystem), coda azioni (QueueSystem), automazione a 1 Stella, Padronanza,
## pozioni e banchetti (PotionSystem + BuffSystem). Offline analitico contro tick con tolleranza del 2%.


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var instances: Array = []
	var gold_amount: int = 0
	var next_uid: int = 0
	func _init() -> void:
		id = "bank"
	func add(def_id: String, qty: int, source: String = "") -> int:
		if qty <= 0:
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


func _world(seed_value: int = 7) -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var bus: Node = autofree(preload("res://src/autoload/EventBus.gd").new())     # bus isolato: niente effetti sul Game globale
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(seed_value), bus)
	var sim := Simulation.new()
	var bank := FakeBank.new()
	var sk := SkillSystem.new()
	var q := QueueSystem.new()
	var farm := FarmingSystem.new()
	var buffs := BuffSystem.new()
	var pot := PotionSystem.new()
	sim.setup(ctx, [bank, sk, q, farm, buffs, pot])
	sim.bind_state(state)
	return {"sim": sim, "ctx": ctx, "sk": sk, "q": q, "farm": farm, "buffs": buffs, "pot": pot, "bank": bank,
		"state": state, "stack": stack, "bus": bus}


func _run(w: Dictionary, seconds: float) -> void:
	var sim: Simulation = w.sim
	for i in int(round(seconds / 0.1)):
		sim.tick(0.1)


func _rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(1.0, maxf(absf(a), absf(b)))


func _slots(w: Dictionary, n: int) -> void:
	(w.stack as ModifierStack).set_source("shop:test", [{"key": "action_queue_slots", "value": n, "mode": "add"}])


# ================================================================== COLTIVAZIONE

func test_stato_iniziale_dai_dati() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	assert_eq(f.plot_count("garden"), 4, "orto: 4 appezzamenti")
	assert_eq(f.plot_count("orchard"), 2, "frutteto: 2 appezzamenti")
	assert_eq(f.next_plot_cost("garden"), 5000)
	assert_eq(f.next_plot_cost("orchard"), 50000)


func test_semina_e_crescita_a_tempo() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	(w.bank as FakeBank).stacks["seed_potato"] = 3
	assert_true(f.plant("garden", 0, "farm_potato"))
	assert_eq((w.bank as FakeBank).count("seed_potato"), 2, "il seme si consuma")
	assert_almost_eq(float(f.plot("garden", 0).remaining_s), 600.0, 1e-6, "Patata: 10 minuti")
	assert_gt((w.sk as SkillSystem).xp("farming"), 0.0, "XP di semina subito")
	_run(w, 300.0)
	assert_almost_eq(f.growth_fraction("garden", 0), 0.5, 0.01)
	assert_false(f.is_ready("garden", 0))
	_run(w, 301.0)
	assert_true(f.is_ready("garden", 0))
	_run(w, 5000.0)
	assert_true(f.is_ready("garden", 0), "il raccolto pronto resta in attesa, nessuna perdita")
	assert_eq(f.ready_count(), 1)


func test_raccolta_rese_xp_e_ripulitura() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	var b: FakeBank = w.bank
	b.stacks["seed_potato"] = 1
	assert_false(f.harvest("garden", 0), "nulla da raccogliere")
	f.plant("garden", 0, "farm_potato")
	var xp_plant := (w.sk as SkillSystem).xp("farming")
	_run(w, 601.0)
	watch_signals(w.bus)
	assert_true(f.harvest("garden", 0))
	assert_between(b.count("crop_potato"), 5, 9, "resa 5-9 al livello 1")
	assert_gt((w.sk as SkillSystem).xp("farming"), xp_plant, "XP di raccolta")
	assert_signal_emitted(w.bus, "action_completed", "le missioni 'raccogli' ascoltano action_completed")
	assert_eq(str(f.plot("garden", 0).crop), "", "appezzamento libero")
	assert_false(f.harvest("garden", 0))


func test_bonus_resa_ogni_10_livelli() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	var b: FakeBank = w.bank
	(w.sk as SkillSystem).add_xp("farming", float(Formulas.xp_total_for_level(20)))
	assert_eq((w.sk as SkillSystem).level("farming"), 20)
	b.stacks["seed_potato"] = 40
	for i in 4:
		f.plant("garden", i, "farm_potato")
	_run(w, 601.0)
	assert_eq(f.harvest_all(), 4)
	assert_between(b.count("crop_potato"), 4 * 7, 4 * 11, "5-9 piu' 2 (livello 20) per raccolto")
	assert_gte(b.count("crop_potato"), 28)


func test_semina_rifiuti_motivati() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	var b: FakeBank = w.bank
	assert_eq(f.can_plant("garden", 0, "farm_potato"), "UI_FARM_REASON_SEEDS")
	b.stacks["seed_wheat"] = 5
	assert_eq(f.can_plant("garden", 0, "farm_wheat"), "UI_FARM_REASON_LEVEL", "Grano richiede livello 10")
	b.stacks["sapling_apple"] = 1
	assert_eq(f.can_plant("garden", 0, "farm_tree_apple"), "UI_FARM_REASON_KIND", "un albero non va nell'orto")
	b.stacks["seed_potato"] = 1
	f.plant("garden", 0, "farm_potato")
	assert_eq(f.can_plant("garden", 0, "farm_potato"), "UI_FARM_REASON_BUSY")
	assert_eq(f.can_plant("garden", 9, "farm_potato"), "UI_FARM_REASON_UNKNOWN")


func test_acquisto_appezzamenti_in_oro() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	var b: FakeBank = w.bank
	assert_false(f.buy_plot("garden"), "senza oro")
	b.gold_amount = 5000 + 25000
	assert_true(f.buy_plot("garden"))
	assert_eq(f.plot_count("garden"), 5)
	assert_eq(b.gold_amount, 25000)
	assert_true(f.buy_plot("garden"))
	assert_eq(f.next_plot_cost("garden"), 120000)
	b.gold_amount = 10000000
	for i in 10:
		f.buy_plot("garden")
	assert_eq(f.plot_count("garden"), 8, "massimo 8")
	assert_eq(f.next_plot_cost("garden"), 0)


func test_frutteto_alberi_lenti() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	(w.bank as FakeBank).stacks["sapling_apple"] = 1
	(w.sk as SkillSystem).add_xp("farming", float(Formulas.xp_total_for_level(15)))
	assert_true(f.plant("orchard", 0, "farm_tree_apple"))
	assert_almost_eq(float(f.plot("orchard", 0).remaining_s), 120.0 * 60.0, 1e-6, "Melo: 2 ore")


func test_velocita_dai_modificatori() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	(w.stack as ModifierStack).set_source("t", [{"key": "skill_haste_pct:farming", "value": 100, "mode": "add"}])
	assert_almost_eq(f.grow_time("farm_potato"), 300.0, 1e-6, "+100% velocita' = meta' del tempo")


func test_automatico_richiede_la_stella_e_risemina() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	var b: FakeBank = w.bank
	b.stacks["seed_potato"] = 10
	f.plant("garden", 0, "farm_potato")
	assert_false(f.set_auto("garden", 0, true), "serve 1 Stella in Coltivazione")
	w.state.skills.farming.stars = 1
	assert_true(f.set_auto("garden", 0, true))
	_run(w, 601.0)
	assert_gt(b.count("crop_potato"), 0, "raccolto da solo")
	assert_eq(str(f.plot("garden", 0).crop), "farm_potato", "e riseminato")
	assert_eq(b.count("seed_potato"), 8)
	_run(w, 601.0 * 12.0)
	assert_eq(b.count("seed_potato"), 0, "finiti i semi si ferma")
	assert_eq(str(f.plot("garden", 0).crop), "")


func test_offline_coltivazione_analitico_vs_tick() -> void:
	var make := func() -> Dictionary:
		var w := _world(11)
		var f: FarmingSystem = w.farm
		var b: FakeBank = w.bank
		b.gold_amount = 100000000
		for i in 4:
			f.buy_plot("garden")
		b.stacks["seed_potato"] = 100000
		w.state.skills.farming.stars = 1
		f.plant_all("garden", "farm_potato")
		for i in f.plot_count("garden"):
			f.set_auto("garden", i, true)
		return w
	var a: Dictionary = make.call()
	var o: Dictionary = make.call()
	var hours := 8.0
	_run(a, hours * 3600.0)
	var rep: Dictionary = (o.sim as Simulation).run_offline(hours * 3600.0)
	var ba: FakeBank = a.bank
	var bo: FakeBank = o.bank
	assert_true(rep.has("farming"), "resoconto per il Bentornato")
	assert_lte(_rel(ba.count("crop_potato"), bo.count("crop_potato")), 0.02, "ortaggi: %d tick vs %d offline" % [ba.count("crop_potato"), bo.count("crop_potato")])
	assert_lte(_rel(ba.count("seed_potato"), bo.count("seed_potato")), 0.02, "semi")
	assert_lte(_rel((a.sk as SkillSystem).xp("farming"), (o.sk as SkillSystem).xp("farming")), 0.02, "XP")
	assert_lte(absi(int(a.state.farming.harvests) - int(o.state.farming.harvests)), 8, "raccolti")
	assert_gt(int(o.state.farming.harvests), 350)


func test_offline_manuale_lascia_pronto() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	(w.bank as FakeBank).stacks["seed_potato"] = 4
	f.plant_all("garden", "farm_potato")
	var rep: Dictionary = (w.sim as Simulation).run_offline(10.0 * 3600.0)
	assert_eq(f.ready_count(), 4, "dopo 10 ore tutto pronto e in attesa")
	assert_eq(int(rep.farming.ready), 4)
	assert_eq((w.bank as FakeBank).count("crop_potato"), 0, "la raccolta manuale non avviene da sola")
	assert_eq(f.harvest_all(), 4)
	assert_gte((w.bank as FakeBank).count("crop_potato"), 20)


func test_offline_semi_finiti_svuota_il_campo() -> void:
	var w := _world()
	var f: FarmingSystem = w.farm
	var b: FakeBank = w.bank
	b.stacks["seed_potato"] = 4
	w.state.skills.farming.stars = 1
	f.plant("garden", 0, "farm_potato")
	f.set_auto("garden", 0, true)           # 3 semi rimasti: 1 + 3 raccolti, poi vuoto
	(w.sim as Simulation).run_offline(10.0 * 3600.0)
	assert_eq(str(f.plot("garden", 0).crop), "")
	assert_eq(b.count("seed_potato"), 0)
	assert_between(b.count("crop_potato"), 4 * 5, 4 * 9 * 2)


# ================================================================== CODA AZIONI

func test_coda_posti_dai_modificatori() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	assert_eq(q.slots(), 0)
	assert_false(q.add("wc_pine", "qty", 5), "senza posti non si accoda")
	assert_eq(q.can_add("wc_pine", "qty", 5), "UI_QUEUE_REASON_FULL")
	_slots(w, 3)
	assert_eq(q.slots(), 3)
	assert_true(q.add("wc_pine", "qty", 5))
	assert_true(q.add("mine_copper", "qty", 5))
	assert_true(q.add("wc_pine", "time", 60))
	assert_false(q.add("wc_pine", "qty", 5), "quarto posto no")
	_slots(w, 99)
	assert_eq(q.slots(), int(DataRegistry.constants.queue.max_slots), "tetto dai dati")


func test_coda_validazioni() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	_slots(w, 6)
	assert_eq(q.can_add("farm_potato", "qty", 5), "UI_QUEUE_REASON_ACTION", "la Coltivazione ha i suoi timer")
	assert_eq(q.can_add("wc_pine", "boh", 5), "UI_QUEUE_REASON_MODE")
	assert_eq(q.can_add("wc_pine", "qty", 0), "UI_QUEUE_REASON_VALUE")
	assert_eq(q.can_add("wc_pine", "exhaust", 0), "UI_QUEUE_REASON_EXHAUST", "senza ingredienti non si esaurisce")
	assert_eq(q.can_add("smelt_copper", "exhaust", 0), "")
	assert_eq(q.can_add("nope", "qty", 1), "UI_QUEUE_REASON_ACTION")


func test_coda_quantita_in_sequenza() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	var sk: SkillSystem = w.sk
	_slots(w, 3)
	q.add("wc_pine", "qty", 5)
	q.add("mine_copper", "qty", 3)
	assert_true(q.start())
	assert_eq(sk.current_action(), "wc_pine")
	_run(w, 14.0)
	assert_eq(sk.current_action(), "wc_pine", "5 cicli = 15 s")
	_run(w, 2.0)
	assert_eq(sk.current_action(), "mine_copper", "passa alla voce successiva")
	assert_eq(q.size(), 1)
	assert_gte((w.bank as FakeBank).count("log_pine"), 5)
	_run(w, 10.0)
	assert_eq(sk.current_action(), "", "coda finita: l'attivita' si ferma")
	assert_false(q.is_running())
	assert_eq(q.size(), 0)
	assert_gte((w.bank as FakeBank).count("ore_copper"), 3)


func test_coda_fino_al_livello() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	var sk: SkillSystem = w.sk
	_slots(w, 3)
	q.add("wc_pine", "level", 3)
	q.add("mine_copper", "qty", 1)
	q.start()
	_run(w, 200.0)
	assert_eq(sk.level("woodcutting"), 3)
	assert_eq(sk.current_action(), "", "livello 3 raggiunto: avanti, poi coda finita")
	assert_gt(sk.xp("mining"), 0.0)


func test_coda_per_tempo() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	var sk: SkillSystem = w.sk
	_slots(w, 3)
	q.add("wc_pine", "time", 60)
	q.add("mine_copper", "qty", 100)
	q.start()
	_run(w, 58.0)
	assert_eq(sk.current_action(), "wc_pine")
	_run(w, 4.0)
	assert_eq(sk.current_action(), "mine_copper")


func test_coda_finche_dura_e_salto_su_materiali_finiti() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	var sk: SkillSystem = w.sk
	_slots(w, 3)
	(w.bank as FakeBank).stacks["ore_copper"] = 4
	q.add("smelt_copper", "exhaust", 0)
	q.add("wc_pine", "qty", 2)
	q.start()
	_run(w, 12.0)
	assert_eq(sk.current_action(), "wc_pine", "ingredienti finiti: la coda passa oltre")
	assert_eq((w.bank as FakeBank).count("ore_copper"), 0)
	assert_gte((w.bank as FakeBank).count("bar_copper"), 4)


func test_coda_in_pausa_se_avvio_altro_a_mano() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	var sk: SkillSystem = w.sk
	_slots(w, 3)
	q.add("wc_pine", "qty", 50)
	q.add("mine_copper", "qty", 5)
	q.start()
	_run(w, 5.0)
	sk.start("mine_copper")
	_run(w, 1.0)
	assert_false(q.is_running(), "scelta manuale = pausa")
	assert_eq(q.size(), 2, "le voci restano")
	assert_eq(sk.current_action(), "mine_copper")


func test_coda_modifica_voci() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	_slots(w, 6)
	q.add("wc_pine", "qty", 5)
	q.add("mine_copper", "qty", 5)
	q.add("wc_birch", "qty", 5)
	assert_false(q.move(0, 1), "la voce 0 e' in corso/prima")
	assert_true(q.move(2, -1))
	assert_eq(str(q.entries()[1].action), "wc_birch")
	assert_true(q.remove_at(1))
	assert_eq(q.size(), 2)
	q.clear()
	assert_eq(q.size(), 0)


func test_offline_coda_in_catena_vs_tick() -> void:
	var make := func() -> Dictionary:
		var w := _world(31)
		_slots(w, 3)
		(w.q as QueueSystem).add("wc_pine", "qty", 2000)
		(w.q as QueueSystem).add("mine_copper", "qty", 1500)
		(w.q as QueueSystem).start()
		return w
	var a: Dictionary = make.call()
	var o: Dictionary = make.call()
	_run(a, 3.0 * 3600.0)
	var rep: Dictionary = (o.sim as Simulation).run_offline(3.0 * 3600.0)
	var ba: FakeBank = a.bank
	var bo: FakeBank = o.bank
	assert_true(rep.has("skills"))
	assert_true(rep.skills.has("chain"), "il resoconto ha la seconda voce")
	assert_lte(_rel(ba.count("log_pine"), bo.count("log_pine")), 0.02, "tronchi %d vs %d" % [ba.count("log_pine"), bo.count("log_pine")])
	assert_lte(_rel(ba.count("ore_copper"), bo.count("ore_copper")), 0.02, "rame %d vs %d" % [ba.count("ore_copper"), bo.count("ore_copper")])
	assert_lte(_rel((a.sk as SkillSystem).xp("woodcutting"), (o.sk as SkillSystem).xp("woodcutting")), 0.02)
	assert_lte(_rel((a.sk as SkillSystem).xp("mining"), (o.sk as SkillSystem).xp("mining")), 0.02)
	assert_eq((o.q as QueueSystem).size(), 0, "coda esaurita anche offline")
	assert_eq((o.sk as SkillSystem).current_action(), "")
	assert_eq((a.sk as SkillSystem).current_action(), "")


func test_offline_coda_ferma_a_meta() -> void:
	var w := _world(3)
	_slots(w, 3)
	(w.q as QueueSystem).add("wc_pine", "qty", 2000)
	(w.q as QueueSystem).add("mine_copper", "qty", 100)
	(w.q as QueueSystem).start()
	(w.sim as Simulation).run_offline(3600.0)
	var q: QueueSystem = w.q
	assert_eq(q.size(), 2, "un'ora non basta a finire 2000 tronchi")
	assert_between(int(q.head().done), 1000, 1300)
	assert_true(q.is_running())
	_run(w, 3.0)
	assert_eq((w.sk as SkillSystem).current_action(), "wc_pine")


func test_coda_salvataggio_e_ripresa() -> void:
	var w := _world()
	_slots(w, 3)
	(w.q as QueueSystem).add("wc_pine", "qty", 50)
	(w.q as QueueSystem).add("mine_copper", "time", 120)
	(w.q as QueueSystem).start()
	_run(w, 10.0)
	w.sim.collect_state(w.state)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w.state))
	var w2 := _world()
	(w2.state as Dictionary).clear()
	(w2.state as Dictionary).merge(saved)
	SaveCodec.normalize(w2.state, w2.sim.int_paths())
	w2.sim.bind_state(w2.state)
	var q2: QueueSystem = w2.q
	assert_eq(q2.size(), 2)
	assert_true(q2.is_running())
	assert_eq(typeof(q2.entries()[0].value), TYPE_INT)
	assert_gte(int(q2.entries()[0].done), 3)
	assert_eq(typeof(q2.entries()[1].value), TYPE_INT)


# ================================================================== AUTOMAZIONE e PADRONANZA

func test_senza_stelle_si_ferma_ai_materiali_finiti() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	(w.bank as FakeBank).stacks["ore_copper"] = 3
	sk.start("smelt_copper")
	assert_false(sk.can_automate("smelt_copper"))
	_run(w, 20.0)
	assert_eq(sk.current_action(), "")


func test_automazione_a_una_stella_aspetta_e_riparte() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var b: FakeBank = w.bank
	w.state.skills.smithing.stars = int(DataRegistry.constants.automation.stars)
	assert_true(sk.can_automate("smelt_copper"))
	b.stacks["ore_copper"] = 3
	sk.start("smelt_copper")
	_run(w, 20.0)
	assert_true(sk.is_waiting(), "ingredienti finiti: in attesa, non fermo")
	assert_eq(sk.current_action(), "smelt_copper")
	var bars := b.count("bar_copper")
	assert_gte(bars, 3)
	_run(w, 10.0)
	assert_eq(b.count("bar_copper"), bars, "in attesa non produce")
	b.stacks["ore_copper"] = 5
	_run(w, 5.0)
	assert_false(sk.is_waiting())
	assert_gt(b.count("bar_copper"), bars, "riparte da sola")
	_run(w, 20.0)
	assert_true(sk.is_waiting(), "e quando finiscono di nuovo, aspetta di nuovo")


func test_automazione_offline_attende_e_riprende() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var b: FakeBank = w.bank
	w.state.skills.smithing.stars = 1
	b.stacks["ore_copper"] = 50
	sk.start("smelt_copper")
	(w.sim as Simulation).run_offline(3600.0)
	assert_true(sk.is_waiting(), "offline: materiali finiti = attesa, non stop")
	assert_eq(sk.current_action(), "smelt_copper")
	b.stacks["ore_copper"] = 10
	(w.sim as Simulation).run_offline(3600.0)
	assert_eq(b.count("ore_copper"), 0, "al ritorno degli ingredienti riprende")


func test_padronanza_dai_dati_e_automazione() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var k: Dictionary = DataRegistry.constants.mastery
	assert_almost_eq(float(k.mastered_save_pct), 10.0, 1e-9, "regola nei dati, non nel codice")
	assert_eq(int(k.mastered_extra_yield), 1)
	assert_eq(int(DataRegistry.constants.automation.perk_double_pick_stars), 3)
	assert_false(sk.is_mastered("smelt_copper"))
	var base_save := float(sk.profile_of("smelt_copper").save_pct)
	var base_yield := int(sk.profile_of("wc_pine").extra_yield)
	assert_eq(base_yield, 0)
	w.state.mastery["smelt_copper"] = {"xp": 48822.0, "level": 50}
	w.state.mastery["wc_pine"] = {"xp": 48822.0, "level": 50}
	sk.refresh_tools()
	# niente "calcio" ai modificatori: il profilo in cache ricorda la maestria con cui è stato calcolato
	assert_true(sk.is_mastered("smelt_copper"))
	assert_true(sk.can_automate("smelt_copper"), "Padronanza = automazione dell'azione")
	assert_almost_eq(float(sk.profile_of("smelt_copper").save_pct), base_save + 10.0, 1e-6, "+10% di non consumare")
	assert_eq(int(sk.profile_of("wc_pine").extra_yield), 1, "+1 resa in raccolta")


func test_talenti_due_su_tre_a_tre_stelle() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	assert_eq(sk.perks_allowed_per_tier("mining"), 1)
	w.state.skills.mining.stars = 3
	assert_eq(sk.perks_allowed_per_tier("mining"), 2)


# ================================================================== POZIONI E BANCHETTI

func test_pozione_di_gruppo_con_cariche() -> void:
	var w := _world()
	var p: PotionSystem = w.pot
	var b: FakeBank = w.bank
	var st: ModifierStack = w.stack
	b.stacks["potion_gatherer_1"] = 2
	assert_true(p.drink("potion_gatherer_1"))
	assert_eq(b.count("potion_gatherer_1"), 1, "si consuma una pozione")
	assert_eq(p.charges("gathering"), 250)
	assert_almost_eq(st.total_add("skill_double_pct", ["woodcutting", "gathering"]), 5.0, 1e-9)
	assert_almost_eq(st.total_add("skill_double_pct", ["smithing", "artisan"]), 0.0, 1e-9, "non vale per le altre mansioni")
	(w.sk as SkillSystem).start("wc_pine")
	_run(w, 30.0)
	assert_eq(p.charges("gathering"), 240, "una carica per azione riuscita")
	assert_true(p.drink("potion_gatherer_1"))
	assert_eq(p.charges("gathering"), 490, "stessa pozione: le cariche si sommano")
	assert_false(p.drink("potion_gatherer_1"), "finite nel Deposito")


func test_pozione_finita_toglie_i_bonus() -> void:
	var w := _world()
	var p: PotionSystem = w.pot
	var st: ModifierStack = w.stack
	(w.bank as FakeBank).stacks["potion_gatherer_1"] = 1
	p.drink("potion_gatherer_1")
	p.consume("gathering", 249)
	assert_eq(p.charges("gathering"), 1)
	p.consume("gathering", 1)
	assert_eq(p.charges("gathering"), 0)
	assert_almost_eq(st.total_add("skill_double_pct", ["woodcutting", "gathering"]), 0.0, 1e-9)
	assert_false(st.has_source("potion:gathering"))


func test_pozione_any_vale_per_lo_slot_scelto() -> void:
	var w := _world()
	var p: PotionSystem = w.pot
	var st: ModifierStack = w.stack
	(w.bank as FakeBank).stacks["potion_wisdom_1"] = 1
	assert_false(p.drink("potion_wisdom_1", "combat"), "non in combattimento")
	assert_true(p.drink("potion_wisdom_1", "artisan"))
	assert_almost_eq(st.total_add("skill_xp_pct", ["smithing", "artisan"]), 5.0, 1e-9)
	assert_almost_eq(st.total_add("skill_xp_pct", ["woodcutting", "gathering"]), 0.0, 1e-9)


func test_pozione_di_combattimento_ha_il_suo_slot() -> void:
	var w := _world()
	var p: PotionSystem = w.pot
	(w.bank as FakeBank).stacks["potion_fury_1"] = 1
	assert_true(p.drink("potion_fury_1"))
	assert_eq(p.charges("combat"), 120)
	assert_gt((w.stack as ModifierStack).total_add("combat_dmg_pct", []), 0.0)
	p.consume("combat", 120)
	assert_almost_eq((w.stack as ModifierStack).total_add("combat_dmg_pct", []), 0.0, 1e-9)


func test_banchetto_a_tempo_via_buffsystem() -> void:
	var w := _world()
	var p: PotionSystem = w.pot
	var st: ModifierStack = w.stack
	(w.bank as FakeBank).stacks["feast_bread"] = 2
	(w.bank as FakeBank).stacks["feast_moon_salad"] = 1
	assert_true(p.eat_feast("feast_bread"))
	assert_almost_eq(p.feast_remaining(), 1200.0, 1e-6, "20 minuti")
	assert_eq(p.feast_item(), "feast_bread")
	assert_almost_eq(st.total_add("skill_xp_pct", ["woodcutting", "gathering"]), 3.0, 1e-9)
	assert_true(p.eat_feast("feast_moon_salad"), "ne resta uno solo: sostituisce")
	assert_eq(p.feast_item(), "feast_moon_salad")
	assert_almost_eq(st.total_add("skill_xp_pct", ["woodcutting", "all"]), 6.0, 1e-9)
	assert_almost_eq(st.total_add("skill_xp_pct", ["woodcutting", "gathering"]), 0.0, 1e-9, "il vecchio bonus e' sparito")
	_run(w, 45.0 * 60.0 + 1.0)
	assert_eq(p.feast_item(), "")
	assert_almost_eq(st.total_add("skill_xp_pct", ["woodcutting", "all"]), 0.0, 1e-9)


func test_offline_banchetto_scade_a_meta_vs_tick() -> void:
	var make := func() -> Dictionary:
		var w := _world(17)
		(w.bank as FakeBank).stacks["feast_celestial_bread"] = 1      # +10% XP per 60 minuti
		(w.pot as PotionSystem).eat_feast("feast_celestial_bread")
		(w.sk as SkillSystem).start("wc_pine")
		return w
	var a: Dictionary = make.call()
	var o: Dictionary = make.call()
	_run(a, 2.0 * 3600.0)
	(o.sim as Simulation).run_offline(2.0 * 3600.0)
	assert_eq((o.pot as PotionSystem).feast_item(), "", "scaduto durante l'offline")
	assert_eq((a.pot as PotionSystem).feast_item(), "")
	assert_lte(_rel((a.sk as SkillSystem).xp("woodcutting"), (o.sk as SkillSystem).xp("woodcutting")), 0.02,
		"XP %f tick vs %f offline" % [(a.sk as SkillSystem).xp("woodcutting"), (o.sk as SkillSystem).xp("woodcutting")])
	# il banchetto vale per la sola prima ora: molto meno di +10% sull'intero periodo
	var plain := _world(17)
	(plain.sk as SkillSystem).start("wc_pine")
	_run(plain, 2.0 * 3600.0)
	var gain := (a.sk as SkillSystem).xp("woodcutting") / (plain.sk as SkillSystem).xp("woodcutting")
	assert_between(gain, 1.03, 1.07, "circa +5% su due ore")


func test_offline_pozione_cariche_finiscono_a_meta_vs_tick() -> void:
	var make := func() -> Dictionary:
		var w := _world(23)
		(w.bank as FakeBank).stacks["potion_wisdom_1"] = 1          # +5% XP per 200 cariche
		(w.pot as PotionSystem).drink("potion_wisdom_1", "gathering")
		(w.sk as SkillSystem).start("wc_pine")
		return w
	var a: Dictionary = make.call()
	var o: Dictionary = make.call()
	_run(a, 2.0 * 3600.0)
	(o.sim as Simulation).run_offline(2.0 * 3600.0)
	assert_eq((o.pot as PotionSystem).charges("gathering"), 0)
	assert_eq((a.pot as PotionSystem).charges("gathering"), 0)
	assert_lte(_rel((a.sk as SkillSystem).xp("woodcutting"), (o.sk as SkillSystem).xp("woodcutting")), 0.02)
	assert_false((o.stack as ModifierStack).has_source("potion:gathering"))


func test_salvataggio_pozioni_e_giardino() -> void:
	var w := _world()
	(w.bank as FakeBank).stacks["potion_gatherer_1"] = 1
	(w.bank as FakeBank).stacks["seed_potato"] = 2
	(w.bank as FakeBank).stacks["feast_bread"] = 1
	(w.pot as PotionSystem).drink("potion_gatherer_1")
	(w.pot as PotionSystem).eat_feast("feast_bread")
	(w.farm as FarmingSystem).plant("garden", 1, "farm_potato")
	_run(w, 100.0)
	w.sim.collect_state(w.state)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w.state))
	var w2 := _world()
	(w2.state as Dictionary).clear()
	(w2.state as Dictionary).merge(saved)
	SaveCodec.normalize(w2.state, w2.sim.int_paths())
	w2.sim.bind_state(w2.state)
	assert_eq((w2.pot as PotionSystem).charges("gathering"), 250)
	assert_eq(typeof((w2.pot as PotionSystem).charges("gathering")), TYPE_INT)
	assert_almost_eq((w2.stack as ModifierStack).total_add("skill_double_pct", ["gathering"]), 5.0, 1e-9, "bonus ripristinati")
	assert_almost_eq((w2.pot as PotionSystem).feast_remaining(), 1100.0, 0.2)
	var f2: FarmingSystem = w2.farm
	assert_eq(str(f2.plot("garden", 1).crop), "farm_potato")
	assert_almost_eq(float(f2.plot("garden", 1).remaining_s), 500.0, 0.2)
	assert_eq(f2.plot_count("garden"), 4)
