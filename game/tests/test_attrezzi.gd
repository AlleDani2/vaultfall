extends GutTest
## Feedback giocatore (Deposito pieno di Grimaldelli di Rame, 23/10/2026):
##  1) «una costruzione per volta» (`single_craft`): dopo UNA costruzione l'azione si ferma, anche con coda e offline;
##  2) «A cosa serve» generato dai dati per OGNI oggetto (ItemUse), in italiano e in inglese;
##  3) doppioni: «Vendi i doppioni», riciclo al caricamento senza perdere valore, motivi dei pulsanti spenti;
##  4) avviso a Deposito quasi pieno (soglia dai dati).
## Docs: docs/04 §8.2, docs/07 §7.1.

const PICK := "key_lockpick_copper"
const PICK_ITEM := "lockpick_copper"
const _GS := preload("res://src/autoload/GameState.gd")


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var made: int = 0
	func _init() -> void:
		id = "bank"
	func add(def_id: String, qty: int, source: String = "") -> int:
		stacks[def_id] = int(stacks.get(def_id, 0)) + qty
		ctx.events.item_gained.emit(def_id, qty, source)
		return qty
	func remove(def_id: String, qty: int) -> bool:
		if int(stacks.get(def_id, 0)) < qty:
			return false
		stacks[def_id] -= qty
		return true
	func count(def_id: String) -> int:
		return int(stacks.get(def_id, 0)) + (made if def_id == PICK_ITEM else 0)
	func has(def_id: String, qty: int = 1) -> bool:
		return count(def_id) >= qty
	func add_instance(_inst: Dictionary) -> String:
		made += 1
		return "i_%06d" % made
	func get_instance(_uid: String) -> Dictionary:
		return {}
	func add_gold(_n: int) -> void:
		pass
	func gold() -> int:
		return 0


func _world() -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var bus: Node = autofree(preload("res://src/autoload/EventBus.gd").new())
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(11), bus)
	var sim := Simulation.new()
	var bank := FakeBank.new()
	var sk := SkillSystem.new()
	var q := QueueSystem.new()
	sim.setup(ctx, [bank, sk, q])
	sim.bind_state(state)
	var w := {"sim": sim, "sk": sk, "q": q, "bank": bank, "stack": stack, "bus": bus, "state": state}
	sk.add_xp("keysmithing", float(Formulas.xp_total_for_level(5)))
	bank.stacks["bar_copper"] = 500
	return w


func _run(w: Dictionary, seconds: float) -> void:
	for i in int(round(seconds / 0.1)):
		(w.sim as Simulation).tick(0.1)


# ------------------------------------------------------------------ dati

func test_flag_per_regola_dai_dati() -> void:
	var flagged := 0
	for aid in DataRegistry.all_actions():
		var a: Dictionary = DataRegistry.all_actions()[aid]
		var non_stack := false
		for o in a.get("outputs", []):
			if not bool(DataRegistry.item(str(o.item)).get("stackable", true)):
				non_stack = true
		assert_eq(bool(a.get("single_craft", false)), non_stack, "single_craft solo e sempre per uscite non impilabili: " + str(aid))
		if non_stack:
			flagged += 1
	assert_gt(flagged, 300, "equipaggiamento e attrezzi di Forgiatura, Carpenteria, Sartoria, Gioielleria, Forgiachiavi")
	assert_true(bool(DataRegistry.action(PICK).get("single_craft", false)), "il Grimaldello è una costruzione singola")
	assert_false(bool(DataRegistry.action("smelt_copper").get("single_craft", false)), "i lingotti si ripetono")
	assert_false(bool(DataRegistry.action("key_key_t1").get("single_craft", false)), "le chiavi (impilabili) si ripetono")


# ------------------------------------------------------------------ ripetizione

func test_dopo_una_costruzione_si_ferma() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	var b: FakeBank = w.bank
	assert_true(sk.start(PICK))
	watch_signals(w.bus)
	_run(w, 120.0)                                         # il ciclo dura pochi secondi: prima sarebbe andato avanti all'infinito
	assert_eq(b.made, 1, "UNA sola costruzione")
	assert_eq(sk.current_action(), "", "l'attività si ferma da sola")
	assert_signal_emitted(w.bus, "notice", "il Registro lo dice")
	assert_true(sk.start(PICK), "si può costruirne un altro, scegliendolo")
	_run(w, 120.0)
	assert_eq(b.made, 2)


func test_azioni_impilabili_continuano_a_ripetersi() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	(w.bank as FakeBank).stacks["ore_copper"] = 200
	sk.add_xp("smithing", 10.0)
	assert_true(sk.start("smelt_copper"))
	_run(w, 60.0)
	assert_gt((w.bank as FakeBank).count("bar_copper"), 505, "la fusione continua a ripetersi")
	assert_eq(sk.current_action(), "smelt_copper")


func test_automazione_non_ripete() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	sk.add_xp("keysmithing", float(Formulas.xp_total_for_level(60)))
	(sk.state as Dictionary)["keysmithing"]["stars"] = 5       # automazione sbloccata
	assert_true(sk.can_automate(PICK))
	sk.start(PICK)
	_run(w, 200.0)
	assert_eq((w.bank as FakeBank).made, 1, "nemmeno con l'automazione")


func test_offline_una_sola_per_azione() -> void:
	var w := _world()
	var sk: SkillSystem = w.sk
	sk.start(PICK)
	var rep := sk.simulate_offline(3600.0)
	assert_eq((w.bank as FakeBank).made, 1, "offline ne produce una sola")
	assert_eq(int(rep.get("completions", 0)), 1)
	assert_eq(sk.current_action(), "", "e l'attività è chiusa")


func test_coda_una_costruzione_per_voce() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	(w.stack as ModifierStack).set_source("shop:test", [{"key": "action_queue_slots", "value": 5, "mode": "add"}])
	assert_true(q.add(PICK, "qty", 5), "il valore chiesto viene riportato a 1")
	assert_eq(int(q.entries()[0].value), 1)
	assert_eq(str(q.entries()[0].mode), "qty")
	assert_true(q.add(PICK, "exhaust", 0), "anche 'finché ci sono ingredienti'")
	assert_eq(int(q.entries()[1].value), 1)
	assert_eq(str(q.entries()[1].mode), "qty")
	assert_true(q.start())
	_run(w, 200.0)
	assert_eq((w.bank as FakeBank).made, 2, "due voci = due costruzioni, mai di più")
	assert_false(q.is_running())


func test_coda_offline_rispetta_le_voci() -> void:
	var w := _world()
	var q: QueueSystem = w.q
	(w.stack as ModifierStack).set_source("shop:test", [{"key": "action_queue_slots", "value": 5, "mode": "add"}])
	q.add(PICK, "qty", 9)
	q.add(PICK, "qty", 9)
	q.add(PICK, "qty", 9)
	q.start()
	(w.sk as SkillSystem).simulate_offline(36000.0)
	assert_eq((w.bank as FakeBank).made, 3, "tre voci = tre costruzioni offline")


# ------------------------------------------------------------------ A cosa serve (audit su TUTTI gli oggetti)

func test_audit_a_cosa_serve_per_ogni_oggetto() -> void:
	var missing: Array = []
	var no_market_line: Array = []
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for id in DataRegistry.all_items():
			var p := ItemUse.purpose(str(id))
			if p.strip_edges().is_empty() or p.begins_with("UI_USE_") or p.contains("{"):
				missing.append("%s/%s" % [loc, id])
			var m := ItemUse.market_line(str(id))
			if m.is_empty() or m.begins_with("UI_USE_"):
				no_market_line.append("%s/%s" % [loc, id])
			var h := ItemUse.howto(str(id))
			assert_false(h.begins_with("UI_USE_"), "istruzione tradotta: " + str(id))
	TranslationServer.set_locale("it")
	assert_eq(missing.size(), 0, "oggetti senza «A cosa serve» valido: " + str(missing.slice(0, 8)))
	assert_eq(no_market_line.size(), 0, "oggetti senza riga sul Mercato: " + str(no_market_line.slice(0, 8)))


func test_attrezzo_dice_mansione_bonus_e_come_si_usa() -> void:
	TranslationServer.set_locale("it")
	var p := ItemUse.purpose(PICK_ITEM)
	assert_true(p.contains("Borseggio"), "nomina la mansione che lo usa: " + p)
	assert_true(p.contains("1,5") or p.contains("1.5"), "mostra il bonus concreto dai dati: " + p)
	assert_true(ItemUse.howto(PICK_ITEM).contains("Usa come attrezzo"), "istruzione esplicita")
	var base := ItemUse.purpose("axe_copper")
	assert_true(base.contains("nessun bonus"), "l'attrezzo base lo dichiara: " + base)
	TranslationServer.set_locale("en")
	assert_true(ItemUse.purpose(PICK_ITEM).contains("success"), "anche in inglese")
	TranslationServer.set_locale("it")


# ------------------------------------------------------------------ Deposito: doppioni, riciclo, avviso

func _bank(state: Dictionary = {}) -> BankSystem:
	if not state.has("bank"):
		state["bank"] = {"gift_done": true}
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(3), EventBus)
	var sim := Simulation.new()
	var bank := BankSystem.new()
	sim.setup(ctx, [bank])
	sim.bind_state(state)
	ctx.set_meta("sim", sim)
	bank.set_meta("ctx", ctx)
	return bank


func test_doppioni_tengono_un_pezzo_e_riciclano_il_resto() -> void:
	var bank := _bank()
	var uids: Array = []
	for i in 5:
		uids.append(bank.add_instance({"def": PICK_ITEM}))
	bank.set_instance_locked(uids[3], true)
	var dup := bank.duplicate_uids()
	assert_eq(dup.size(), 4, "5 uguali, 1 bloccata: la bloccata resta, le altre 4 sono doppioni")
	assert_false(dup.has(uids[3]), "la bloccata non è mai un doppione")
	var gold := bank.recycle_instances(dup)
	assert_eq(gold, 4 * bank.recycle_value(PICK_ITEM), "oro pari al valore (constants.bank.recycle_pct)")
	assert_gt(gold, 0)
	assert_eq(bank.count(PICK_ITEM), 1)
	assert_eq(bank.duplicate_uids().size(), 0, "non restano doppioni")


func test_sell_rules_dupes_attrezzi_senza_mercato() -> void:
	var bank := _bank()
	for i in 4:
		bank.add_instance({"def": PICK_ITEM})
	var plan := SellRules.collect_dupes(bank, null, false)
	assert_eq(int(plan.pieces), 3, "gli attrezzi si riciclano anche senza il Mercato")
	assert_eq(int(plan.gold), 3 * bank.recycle_value(PICK_ITEM))
	var g := SellRules.execute_dupes(bank, null, plan)
	assert_eq(g, int(plan.gold))
	assert_eq(bank.gold(), g)


func test_equipaggiamento_doppio_serve_il_mercato() -> void:
	var bank := _bank()
	bank.add_instance({"def": "plate_helm_copper"})
	bank.add_instance({"def": "plate_helm_copper"})
	var plan := SellRules.collect_dupes(bank, null, false)
	assert_eq(int(plan.pieces), 0)
	assert_eq(int(plan.skipped), 1, "il pezzo in più c'è ma aspetta il Mercato (lo dice il tooltip)")


func test_migrazione_vecchio_salvataggio() -> void:
	var insts: Array = []
	for i in 40:
		insts.append({"uid": "i_%06d" % (i + 1), "def": PICK_ITEM, "quality": "normal", "sockets": [], "rank": 0, "locked": false})
	var state := {"bank": {"gift_done": true, "instances": insts, "next_uid": 41},
		"equipment": {"tools": {"thievery": "i_000007"}}, "currencies": {"gold": 10}}
	var bank := _bank(state)
	assert_eq(bank.count(PICK_ITEM), 1, "restano un solo attrezzo")
	assert_not_null(bank.get_instance("i_000007").get("uid"), "e quello in uso resta")
	assert_eq(bank.gold(), 10 + 39 * bank.recycle_value(PICK_ITEM), "nessun valore perso: 39 riciclati in oro")


func test_avviso_deposito_quasi_pieno() -> void:
	var bank := _bank()
	var cap := bank.capacity()
	var warn := float(DataRegistry.const_value("bank.warn_pct", 100))
	var need := int(ceil(float(cap) * warn / 100.0))
	var mats: Array = DataRegistry.items_by_category("material")      # F15: lo Spazio si riempie con pile, non con equipaggiamento
	for i in need - 1:
		bank.add(str(mats[i].id), 1)
	assert_false(bank.nearly_full())
	bank.add(str(mats[need - 1].id), 1)
	assert_true(bank.nearly_full(), "alla soglia dei dati")
	watch_signals(EventBus)
	bank.tick(0.1)
	bank.tick(0.1)
	assert_signal_emit_count(EventBus, "notice", 1, "l'avviso parte una volta sola")
