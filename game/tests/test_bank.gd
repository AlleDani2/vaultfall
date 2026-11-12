extends GutTest
## BankSystem (Deposito + valute) e schermata Deposito. Contratto: docs/audit_2026-10-22/17_CONTRATTI_TRA_SISTEMI.md.

const STACK := "log_pine"            # impilabile
const STACK2 := "ore_copper"
const GEAR := "plate_helm_copper"    # non impilabile (istanza), equipaggiamento: Armeria, non occupa Spazio (F15)
const COLLECT := "skin_millbrook_01" # non impilabile (istanza), collezionabile: occupa Spazio
const TOKEN := "stardust"            # valuta (categoria currency)

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_saves_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _make(state: Dictionary = {}, mods: ModifierStack = null, gift: bool = false) -> BankSystem:
	if not gift and not state.has("bank"):
		state["bank"] = {"gift_done": true}       # i test contano da Deposito vuoto (regalo provato a parte)
	var m := mods if mods != null else ModifierStack.new()
	var ctx := SystemContext.make(DataRegistry, state, m, RngStreams.new(1), EventBus)
	var sim := Simulation.new()
	var bank := BankSystem.new()
	sim.setup(ctx, [bank])
	sim.bind_state(state)
	ctx.set_meta("sim", sim)        # tiene vivo il Simulation (il contesto lo conosce solo con riferimento debole)
	bank.set_meta("ctx", ctx)
	return bank


func test_impilabili_aggiunta_rimozione() -> void:
	var bank := _make()
	watch_signals(EventBus)
	assert_eq(bank.add(STACK, 10, "test"), 10)
	assert_eq(bank.add(STACK, 5), 5)
	assert_eq(bank.count(STACK), 15)
	assert_true(bank.has(STACK, 15))
	assert_false(bank.has(STACK, 16))
	assert_eq(bank.used_slots(), 1, "una pila = 1 spazio")
	assert_signal_emitted_with_parameters(EventBus, "item_gained", [STACK, 10, "test"], 0)
	assert_false(bank.remove(STACK, 16), "tutto o niente")
	assert_eq(bank.count(STACK), 15)
	assert_true(bank.remove(STACK, 15))
	assert_eq(bank.used_slots(), 0, "pila vuota = spazio liberato")
	assert_signal_emitted_with_parameters(EventBus, "item_removed", [STACK, 15])
	assert_eq(bank.add(STACK, 0), 0)
	assert_eq(bank.add("non_esiste_xyz", 3), 0, "definizione sconosciuta")


func test_capacita_dai_dati_e_modificatori() -> void:
	var mods := ModifierStack.new()
	mods.set_catalog(DataRegistry.table("modifier_catalog"))
	var bank := _make({}, mods)
	var base := int(DataRegistry.get_def("shop", "bank_slot").base_slots)
	assert_eq(bank.capacity(), base)
	bank.state.slots_bought = 5
	assert_eq(bank.capacity(), base + 5)
	mods.set_source("test", [{"key": "bank_slots", "value": 10, "mode": "add"}])
	assert_eq(bank.capacity(), base + 15)
	assert_eq(bank.free_slots(), base + 15)


func test_deposito_pieno() -> void:
	var bank := _make()
	var cap := bank.capacity()
	var stackables: Array = []
	for it in DataRegistry.all_items().values():
		if it.get("stackable", false) and it.category != "currency" and stackables.size() < cap + 1:
			stackables.append(it.id)
	for i in cap:
		assert_eq(bank.add(stackables[i], 1), 1)
	assert_eq(bank.free_slots(), 0)
	assert_true(bank.is_full())
	# resoconto 117: il Deposito pieno non rifiuta piu' nulla, il resto aspetta nel Carro di Ritiro
	assert_eq(bank.add(stackables[cap], 1), 1, "pila nuova: va nel Carro")
	assert_eq(bank.overflow_count(), 1)
	assert_eq(bank.used_slots(), cap, "il Carro non occupa spazi")
	assert_eq(bank.add(stackables[0], 7), 7, "una pila esistente accetta ancora")
	assert_eq(bank.add(COLLECT, 1), 1, "istanza: nel Carro")
	assert_eq(bank.add_instance({"def": COLLECT}), BankSystem.OVERFLOW_UID)
	assert_eq(bank.overflow_instance_count(), 2)
	assert_true(bank.remove(stackables[1], 1))
	bank.tick(0.1)         # libera un posto: scarica per prima la pila (ordine alfabetico delle pile, poi le istanze)
	assert_eq(bank.free_slots(), 0)
	assert_eq(bank.overflow_instance_count(), 2, "il posto liberato lo prende la pila nuova")
	assert_eq(bank.overflow_stacks_count(), 0)
	assert_eq(bank.add(COLLECT, 3), 3, "aggiunta: tutto accettato, il resto nel Carro")
	assert_eq(bank.overflow_instance_count(), 5)


func test_istanze_e_uid() -> void:
	var bank := _make()
	var u1 := bank.add_instance({"def": GEAR, "quality": "fine", "sockets": ["glyph_x"], "rank": 2})
	var u2 := bank.add_instance({"def": GEAR})
	assert_eq(u1, "i_000001")
	assert_eq(u2, "i_000002")
	var inst := bank.get_instance(u1)
	assert_eq(inst.def, GEAR)
	assert_eq(inst.quality, "fine")
	assert_eq(inst.rank, 2)
	assert_eq(inst.sockets, ["glyph_x"])
	assert_eq(inst.locked, false)
	assert_eq(bank.get_instance(u2).quality, str(DataRegistry.constants.quality[0].id), "qualità predefinita dai dati")
	assert_eq(bank.count(GEAR), 2)
	assert_eq(bank.list_instances().size(), 2)
	assert_eq(bank.used_slots(), 0, "l'equipaggiamento non occupa Spazio (F15)")
	assert_eq(bank.gear_used(), 2)
	assert_eq(bank.add(GEAR, 2), 2, "add() crea istanze per i non impilabili")
	assert_eq(bank.get_instance("i_000004").def, GEAR)
	assert_true(bank.remove_instance(u1))
	assert_false(bank.remove_instance(u1))
	assert_eq(bank.get_instance(u1), {})
	assert_eq(bank.add_instance({"def": GEAR}), "i_000005", "gli uid non si riusano")
	assert_eq(bank.count(GEAR), 4)


func test_blocco() -> void:
	var bank := _make()
	bank.add(STACK, 4)
	assert_eq(bank.sellable_count(STACK), 4)
	bank.set_def_locked(STACK, true)
	assert_true(bank.is_def_locked(STACK))
	assert_eq(bank.sellable_count(STACK), 0)
	bank.set_def_locked(STACK, false)
	assert_eq(bank.sellable_count(STACK), 4)
	var a := bank.add_instance({"def": GEAR})
	var b := bank.add_instance({"def": GEAR})
	bank.set_instance_locked(b, true)
	assert_eq(bank.sellable_count(GEAR), 1)
	assert_true(bank.remove(GEAR, 1), "il consumo toglie prima l'istanza non bloccata")
	assert_eq(bank.get_instance(a), {})
	assert_true(bank.is_instance_locked(b))


func test_valute() -> void:
	var bank := _make()
	watch_signals(EventBus)
	assert_eq(bank.gold(), 0)
	bank.add_gold(500)
	assert_eq(bank.gold(), 500)
	assert_signal_emitted_with_parameters(EventBus, "currency_changed", ["gold", 500])
	assert_false(bank.spend_gold(501))
	assert_eq(bank.gold(), 500)
	assert_true(bank.spend_gold(200))
	assert_eq(bank.gold(), 300)
	assert_false(bank.spend_gold(-1))
	bank.add_gold(-50)
	assert_eq(bank.gold(), 300, "importi negativi ignorati")
	assert_eq(bank.ctx.state.currencies.gold, 300, "oro in currencies.gold")
	bank.add_currency(TOKEN, 7)
	assert_eq(bank.currency(TOKEN), 7)
	assert_true(bank.spend_currency(TOKEN, 3))
	assert_eq(bank.currency(TOKEN), 4)
	assert_eq(bank.add(TOKEN, 2, "t"), 2, "add() di una valuta non occupa spazi")
	assert_eq(bank.used_slots(), 0)
	assert_eq(bank.count(TOKEN), 6)
	assert_true(bank.remove(TOKEN, 6))
	bank.add_currency("non_valuta_xyz", 5)
	assert_eq(bank.currency("non_valuta_xyz"), 0)
	assert_eq(Array(bank.currency_ids()), ["gold"])


func test_regalo_iniziale_solo_dai_dati() -> void:
	# regalo dei dati (constants.new_game_gift, resoconto 29): consegnato una sola volta, a tempo di gioco zero
	var gift: Dictionary = DataRegistry.constants.get("new_game_gift", {})
	var bank := _make({}, null, true)
	assert_eq(bank.gold(), int(gift.get("gold", 0)), "oro del regalo")
	for e in gift.get("items", []):
		assert_eq(bank.count(str(e.item)), int(e.qty), "oggetto del regalo " + str(e.item))
	assert_true(bank.state.gift_done)
	bank.from_state(bank.state)
	assert_eq(bank.gold(), int(gift.get("gold", 0)), "il regalo non si ripete al caricamento")
	var old_save := _make({"stats": {"playtime_s": 120.0}}, null, true)
	assert_eq(old_save.gold(), 0, "nessun regalo a una partita già iniziata")
	var saved: Variant = DataRegistry.constants.get("new_game_gift")
	DataRegistry.constants["new_game_gift"] = {"gold": 7, "items": [{"item": STACK, "qty": 3}]}
	var b2 := _make({"stats": {"playtime_s": 0.0}}, null, true)
	if saved == null:
		DataRegistry.constants.erase("new_game_gift")
	else:
		DataRegistry.constants["new_game_gift"] = saved
	assert_eq(b2.gold(), 7)
	assert_eq(b2.count(STACK), 3)


func test_offline_non_fa_nulla() -> void:
	var bank := _make()
	assert_eq(bank.simulate_offline(3600.0), {})


func test_round_trip_20000_istanze() -> void:
	var state := {}
	var bank := _make(state)
	bank.state.slots_bought = 30000
	var sample := {"def": COLLECT, "quality": "excellent", "sockets": ["g1", "g2"], "rank": 3}
	for i in 20000:
		var inst := sample.duplicate(true)
		inst.rank = i % 13
		bank.add_instance(inst)
	bank.add(STACK, 123456)
	bank.add_gold(9000000000000)
	bank.add_currency(TOKEN, 11)
	bank.set_instance_locked("i_000007", true)
	bank.set_def_locked(STACK, true)
	assert_eq(bank.instance_count(), 20000)
	var sim: Simulation = bank.ctx.simulation()
	var snapshot := state.duplicate(true)
	snapshot["bank"] = bank.to_state()
	snapshot["schema_version"] = SaveCodec.SCHEMA_VERSION
	var bytes := SaveCodec.encode(snapshot)
	var res := SaveCodec.load_bytes(bytes, sim.int_paths())
	assert_true(res.ok, str(res.get("error", "")))
	var loaded: Dictionary = res.data
	assert_eq(loaded.bank, snapshot.bank, "stato bank identico (tipi inclusi)")
	assert_eq(loaded.currencies.gold, snapshot.currencies.gold)
	var state2: Dictionary = loaded
	var b2 := _make(state2)
	assert_eq(b2.instance_count(), 20000)
	assert_eq(b2.count(COLLECT), 20000)
	assert_eq(b2.get_instance("i_000007").locked, true)
	assert_eq(b2.get_instance("i_020000").rank, 19999 % 13)
	assert_eq(b2.count(STACK), 123456)
	assert_true(b2.is_def_locked(STACK))
	assert_eq(b2.gold(), 9000000000000)
	assert_eq(b2.currency(TOKEN), 11)
	assert_typeof(state2.currencies[TOKEN], TYPE_INT)
	assert_eq(b2.add_instance({"def": COLLECT}), "i_020002", "il contatore uid prosegue")


# ------------------------------------------------------------------ interfaccia

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"


func _host() -> Control:
	var h := Control.new()
	h.size = Vector2(1100, 600)
	add_child_autofree(h)
	return h


func _screen_with_items() -> Array:
	assert_true(Game.new_game(1, "normal", 5))
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 2000
	var n := 0
	for it in DataRegistry.all_items().values():
		if n >= 650:
			break
		if it.category != "currency":
			bank.add(it.id, 3)
			n += 1
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	_host().add_child(scr)
	scr.open({})
	return [bank, scr]


func test_schermata_lista_virtualizzata_e_filtri() -> void:
	Settings.set_value("bank_view", "list")          # F16: la griglia ha il suo test (test_virtual_grid); qui la vista a lista
	var r := _screen_with_items()
	var bank: BankSystem = r[0]
	var scr: Control = r[1]
	await wait_process_frames(2)
	var list: VirtualList = scr._list
	assert_gt(list.count(), 250, "tutte le voci che occupano Spazio nella lista")
	assert_eq(list.count(), bank.used_slots(), "«Tutto» = lo Spazio usato (R-SP-7a)")
	assert_lt(list.pool_size(), 40, "solo le righe visibili esistono come nodi")
	var f0 := PerfGate.load_factor()
	var scroll_ms := PerfGate.best_of(func() -> void:
		for i in 200:
			list.scroll_to(i * 3), 3)
	PerfGate.assert_time(self, "scorrimento fluido (200 salti, migliore di 3)", scroll_ms, 1500.0, PerfGate.factor_around(f0))
	list.scroll_to(0)
	scr._on_query("zzzz_nessuno")
	assert_eq(list.count(), 0)
	scr._on_query("")
	scr._on_group("gear")
	assert_gt(list.count(), 0)
	assert_eq(list.count(), bank.gear_used(), "«Armeria» = i pezzi dell'Armeria (R-SP-7b)")
	scr._on_group("all")
	assert_eq(list.count(), bank.used_slots())
	scr._on_sort(1)       # per nome
	assert_true(scr._entries[0].sort_name <= scr._entries[1].sort_name or scr._descending)
	Settings.set_value("bank_view", "grid")


func test_schermata_dettagli_blocco_e_riepilogo() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var bank := Game.system("bank") as BankSystem
	# Deposito vuoto: il regalo di nuova partita (constants.new_game_gift) si toglie prima della prova
	for def_id in bank.state.stacks.keys():
		bank.remove(def_id, bank.count(def_id))
	bank.spend_gold(bank.gold())
	bank.add(STACK, 12)
	var uid := bank.add_instance({"def": GEAR, "quality": "fine"})
	bank.add_gold(1234)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	_host().add_child(scr)
	scr.open({})
	await wait_process_frames(2)
	assert_eq(scr._entries.size(), 1, "«Tutto» non contiene l'equipaggiamento (F15)")
	scr._on_group("gear")
	assert_eq(scr._entries.size(), 1)
	scr._selected = uid
	scr._refresh_detail()
	assert_gt(scr._detail_box.get_child_count(), 4, "dettagli con statistiche dell'equipaggiamento")
	scr._on_toggle_lock()
	assert_true(bank.is_instance_locked(uid))
	scr._on_group("all")
	scr._selected = STACK
	scr._on_toggle_lock()
	assert_true(bank.is_def_locked(STACK))
	scr._on_only_locked(true)
	assert_eq(scr._entries.size(), 1)
	scr._on_group("gear")
	assert_eq(scr._entries.size(), 1, "anche il pezzo bloccato dell'Armeria")
	scr._on_group("all")
	scr._on_only_locked(false)
	# riepilogo: oro dal Deposito
	var summary: Control = (load("res://src/ui/screens/SummaryScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(summary)
	summary.open({})
	assert_eq(summary.get_node("%GoldValue").text, NumberFormat.fmt(1234))
	# registro schermate: Deposito aperto dal menù
	var entry := ScreenRegistry.get_entry("bank")
	assert_true(ScreenRegistry.is_available(entry, []))
