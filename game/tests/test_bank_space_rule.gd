extends GutTest
## F15 (docs/ui_redesign/02 §4.1, R-SP-1…9): l'equipaggiamento e gli attrezzi non occupano Spazio, hanno l'Armeria (tetto tecnico
## dai dati) e il Carro di Ritiro ragiona per classe. Sistema vero (BankSystem) con dati veri; nessun numero scritto qui che
## non venga da constants.bank.space.

const STACK := "log_pine"
const COLLECT := "skin_millbrook_01"          # collezionabile: occupa Spazio
const GEAR := "plate_helm_copper"             # equipaggiamento: Armeria
const TOOLISH := "axe_copper"                # attrezzo (categoria tool): Armeria

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_space_rule_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _make(state: Dictionary = {}) -> BankSystem:
	if not state.has("bank"):
		state["bank"] = {"gift_done": true}
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(1), EventBus)
	var sim := Simulation.new()
	var bank := BankSystem.new()
	sim.setup(ctx, [bank])
	sim.bind_state(state)
	ctx.set_meta("sim", sim)
	bank.set_meta("ctx", ctx)
	return bank


func _space() -> Dictionary:
	return DataRegistry.constants.bank.space


func _gear_ids() -> Array:
	var out: Array = []
	for c in _space().free_categories:
		for it in DataRegistry.items_by_category(str(c)):
			out.append(str(it.id))
	return out


func _stack_ids(n: int, skip: Array = []) -> Array:
	var out: Array = []
	for it in DataRegistry.items_by_category("material"):
		if not skip.has(str(it.id)):
			out.append(str(it.id))
		if out.size() >= n:
			break
	return out


func _fill_gear(bank: BankSystem) -> void:
	var ids := _gear_ids()
	var i := 0
	while not bank.gear_is_full() and i < 5000:
		bank.add_instance({"def": ids[i % ids.size()]})
		i += 1
	assert_true(bank.gear_is_full())


func _fill_space(bank: BankSystem) -> void:
	for id in _stack_ids(bank.capacity() + 5, [STACK]):
		if bank.is_full():
			break
		bank.add(id, 1)
	assert_true(bank.is_full())


func _check_invariants(bank: BankSystem, label: String) -> void:
	assert_eq(bank.used_slots() + bank.gear_used(), bank.state.stacks.size() + bank.instance_count(), "R-SP-7c nessun oggetto perso: " + label)
	assert_gte(bank.free_slots(), 0, "R-SP-7d free_slots mai negativo: " + label)
	assert_gte(bank.gear_free(), 0)
	var gear := 0
	for inst in bank.state.instances:
		if _space().free_categories.has(str(DataRegistry.item(str(inst.def)).get("category", ""))):
			gear += 1
	assert_eq(bank.gear_used(), gear, "gear_used = istanze di categoria libera: " + label)


# ------------------------------------------------------------------ dati

func test_la_regola_viene_dai_dati_e_le_categorie_libere_non_sono_impilabili() -> void:
	var sp := _space()
	assert_eq(sp.free_categories, ["equipment", "tool"])
	assert_gt(int(sp.gear_cap), 0)
	assert_between(int(sp.gear_warn_pct), 1, 100)
	for c in sp.free_categories:
		for it in DataRegistry.items_by_category(str(c)):
			assert_false(bool(it.get("stackable", false)), "%s non impilabile" % it.id)
	assert_eq(int(DataRegistry.constants.bank.study.need_base), 12, "need_base ritarato (era 30)")
	assert_true(DataRegistry.item(GEAR).category in sp.free_categories)
	assert_true(DataRegistry.item(TOOLISH).category in sp.free_categories)
	assert_false(DataRegistry.item(COLLECT).category in sp.free_categories, "le Finiture contano come Spazio")


# ------------------------------------------------------------------ R-SP-1, R-SP-2, R-SP-4, R-SP-8

func test_lo_spazio_conta_pile_e_collezionabili_ma_non_equipaggiamento() -> void:
	var b := _make()
	b.add(STACK, 50)
	b.add(COLLECT, 2)
	for i in 5:
		b.add_instance({"def": GEAR})
	b.add(TOOLISH, 1)
	b.add_gold(500)
	assert_eq(b.used_slots(), 3, "1 pila + 2 Finiture (R-SP-1); l'oro non conta (R-SP-8)")
	assert_eq(b.gear_used(), 6, "R-SP-2")
	assert_eq(b.free_slots(), b.capacity() - 3)
	_check_invariants(b, "misto")
	var uid := b.add_instance({"def": GEAR})
	b.set_instance_locked(uid, true)
	assert_eq(b.used_slots(), 3, "bloccare non cambia la classe")
	assert_true(b.remove_instance(uid))
	assert_eq(b.gear_used(), 6, "togliere un pezzo scala il contatore")


func test_l_equipaggiamento_indossato_resta_nell_armeria() -> void:
	assert_true(Game.new_game(1, "normal", 15001))
	var b := Game.system("bank") as BankSystem
	var cb := Game.system("combat") as CombatSystem
	var before := b.gear_used()
	var uid := b.add_instance({"def": GEAR})
	if cb.equip(uid):
		assert_true(b.is_in_use(uid))
	assert_eq(b.gear_used(), before + 1, "R-SP-4: indossato = ancora un'istanza dell'Armeria")


# ------------------------------------------------------------------ tetto, Carro per classe (R-SP-3, R-SP-5)

func test_oltre_il_tetto_il_pezzo_aspetta_nel_carro_e_lo_spazio_resta_libero() -> void:
	var b := _make()
	_fill_gear(b)
	assert_eq(b.gear_used(), int(_space().gear_cap))
	assert_eq(b.used_slots(), 0, "300 pezzi di equipaggiamento: nessuno Spazio usato")
	assert_eq(b.free_slots(), b.capacity())
	assert_eq(b.add_instance({"def": GEAR}), BankSystem.OVERFLOW_UID, "R-SP-3: oltre il tetto, nel Carro")
	assert_eq(b.add(GEAR, 2), 2)
	assert_eq(b.overflow_gear_count(), 3)
	assert_eq(b.overflow_space_count(), 0)
	assert_eq(b.gear_used(), int(_space().gear_cap), "il Deposito non supera mai il tetto")
	assert_eq(b.add(COLLECT, 1), 1)
	assert_eq(b.overflow_instance_count(), 3, "una Finitura entra nello Spazio libero, non nel Carro")
	assert_eq(b.used_slots(), 1)
	_check_invariants(b, "Armeria piena")


func test_spazio_pieno_ma_armeria_libera_il_gear_entra_e_la_finitura_aspetta() -> void:
	var b := _make()
	_fill_space(b)
	assert_eq(b.add_instance({"def": GEAR}) != BankSystem.OVERFLOW_UID, true, "R-SP-5: il gear non aspetta se l'Armeria ha posto")
	assert_eq(b.gear_used(), 1)
	assert_eq(b.add_instance({"def": COLLECT}), BankSystem.OVERFLOW_UID)
	assert_eq(b.overflow_gear_count(), 0)
	assert_eq(b.overflow_space_count(), 1)
	_check_invariants(b, "Spazio pieno")


func test_il_carro_si_scarica_per_classe() -> void:
	var b := _make()
	_fill_gear(b)
	_fill_space(b)
	b.add_instance({"def": GEAR})
	b.add_instance({"def": COLLECT})
	assert_eq(b.overflow_gear_count(), 1)
	assert_eq(b.overflow_space_count(), 1)
	b.tick(0.1)
	assert_eq(b.overflow_count(), 2, "nulla si muove senza posto")
	# libero un posto nell'Armeria: parte solo il gear
	var gear_uid := ""
	for inst in b.state.instances:
		if b.is_gear_def(str(inst.def)):
			gear_uid = str(inst.uid)
			break
	assert_true(b.remove_instance(gear_uid))
	b.tick(0.1)
	assert_eq(b.overflow_gear_count(), 0, "il gear entra nell'Armeria")
	assert_eq(b.overflow_space_count(), 1, "la Finitura aspetta ancora")
	# libero uno Spazio: parte la Finitura
	var stack_id := str(b.state.stacks.keys()[0])
	assert_true(b.remove(stack_id, b.count(stack_id)))
	b.tick(0.1)
	assert_eq(b.overflow_count(), 0)
	_check_invariants(b, "dopo gli scarichi")


# ------------------------------------------------------------------ avviso dell'Armeria (R-SP-6)

func test_avviso_dell_armeria_una_volta_sola() -> void:
	var b := _make()
	var warns: Array = []
	var cb := func(kind: String, _text: String, meta: Dictionary) -> void:
		if str(meta.get("reason", "")) == "armory_nearly_full":
			warns.append(kind)
	EventBus.notice.connect(cb)
	var ids := _gear_ids()
	var threshold := int(ceil(float(_space().gear_cap) * float(_space().gear_warn_pct) / 100.0))
	for i in threshold - 1:
		b.add_instance({"def": ids[i % ids.size()]})
	b.tick(0.1)
	assert_eq(warns.size(), 0, "sotto la soglia nessun avviso")
	b.add_instance({"def": ids[0]})
	b.tick(0.1)
	b.tick(0.1)
	assert_eq(warns.size(), 1, "una volta sola alla soglia")
	b.add_instance({"def": ids[1]})
	b.tick(0.1)
	assert_eq(warns.size(), 1, "oltre la soglia non si ripete")
	assert_false(b.nearly_full(), "l'avviso dell'Armeria non è quello dello Spazio (R-SP-6)")
	EventBus.notice.disconnect(cb)


# ------------------------------------------------------------------ R-SP-7: invarianti con la schermata

func test_celle_di_tutto_e_di_armeria_coincidono_con_i_contatori() -> void:
	assert_true(Game.new_game(1, "normal", 15002))
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = 500
	for id in _stack_ids(30):
		b.add(id, 3)
	b.add(COLLECT, 4)
	var ids := _gear_ids()
	for i in 40:
		b.add_instance({"def": ids[i % ids.size()]})
	var scr: Control = (load("res://src/ui/screens/BankScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	assert_eq(scr._entries.size(), b.used_slots(), "R-SP-7a: «Tutto» senza filtri = used_slots()")
	scr._on_group("gear")
	assert_eq(scr._entries.size(), b.gear_used(), "R-SP-7b: «Armeria» = gear_used()")
	scr._on_group("all")
	var tab_independent := b.used_slots()
	scr._on_group("materials")
	assert_eq(b.used_slots(), tab_independent, "R-SP-7e: lo spazio non dipende dalla scheda")
	scr._on_group("all")
	scr._on_query(Loc.t(DataRegistry.item(GEAR).name).substr(0, 4))
	assert_gt(scr._entries.size(), 0, "con una ricerca «Tutto» attraversa anche l'Armeria")
	scr._on_query("")
	var btn := scr._group_buttons["gear"] as Button
	assert_true(btn.text.contains("%d" % int(_space().gear_cap)), "il pulsante porta il contatore «Armeria n/tetto»")


# ------------------------------------------------------------------ salvataggi esistenti (regola 7)

func _old_state(gear_n: int, stacks_n: int, cart_gear: int, cart_skin: int) -> Dictionary:
	var gids := _gear_ids()
	var insts: Array = []
	for i in gear_n:
		insts.append({"uid": "i_%06d" % (i + 1), "def": gids[i % gids.size()], "quality": "normal", "sockets": [], "rank": 0, "locked": false})
	var stacks := {}
	for id in _stack_ids(stacks_n):
		stacks[id] = 3
	var cart: Array = []
	for i in cart_gear:
		cart.append({"def": gids[i % gids.size()], "quality": "normal", "sockets": [], "rank": 0})
	for i in cart_skin:
		cart.append({"def": COLLECT, "quality": "normal", "sockets": [], "rank": 0})
	return {"bank": {"stacks": stacks, "instances": insts, "slots_bought": 300, "next_uid": gear_n + 1, "recent": {}, "locked_defs": {},
		"gift_done": true, "overflow_stacks": {}, "overflow_instances": cart}}


func test_vecchio_salvataggio_con_340_pezzi_e_deposito_pieno_si_apre_con_lo_spazio_sceso() -> void:
	# prima di F15: 340 pezzi + 60 pile = 400/400 (capacità 100 + 300 comprati); ora lo Spazio usato è 60
	var st := _old_state(340, 60, 0, 0)
	var b := _make(st)
	assert_eq(b.capacity(), int(DataRegistry.get_def("shop", "bank_slot").base_slots) + 300)
	assert_eq(b.used_slots(), 60, "Spazio sceso")
	assert_eq(b.gear_used(), 340, "nessun pezzo tolto, anche oltre il tetto")
	assert_eq(b.gear_free(), 0)
	assert_eq(b.instance_count(), 340)
	assert_eq(b.add_instance({"def": GEAR}), BankSystem.OVERFLOW_UID, "il nuovo gear aspetta nel Carro finché l'Armeria è oltre il tetto")
	assert_ne(b.add_instance({"def": COLLECT}), BankSystem.OVERFLOW_UID, "lo Spazio sceso accoglie le Finiture")
	_check_invariants(b, "340 pezzi")


func test_il_carro_dei_vecchi_salvataggi_si_scarica_una_volta_verso_l_armeria() -> void:
	var st := _old_state(40, 100 + 300, 7, 2)          # Spazio pieno (400/400), 7 pezzi gear e 2 Finiture nel Carro
	var notes: Array = []
	var cb := func(_k: String, text: String, meta: Dictionary) -> void:
		if str(meta.get("reason", "")) == "carro_to_armory":
			notes.append(text)
	EventBus.notice.connect(cb)
	var b := _make(st)
	assert_eq(b.gear_used(), 47, "i 7 pezzi in attesa sono entrati nell'Armeria al caricamento")
	assert_eq(b.overflow_gear_count(), 0)
	assert_eq(b.overflow_space_count(), 2, "le Finiture aspettano: lo Spazio è pieno")
	b.tick(0.1)
	b.tick(0.1)
	assert_eq(notes.size(), 1, "una sola riga nel Registro")
	# idempotente: ricaricare lo stato salvato non scarica altro e non ripete la riga
	var again := _make({"bank": b.to_state()})
	again.tick(0.1)
	assert_eq(again.gear_used(), 47)
	assert_eq(notes.size(), 1, "nessuna seconda riga")
	EventBus.notice.disconnect(cb)
	_check_invariants(b, "dopo la migrazione")


func test_l_esito_delle_casse_non_cambia_con_l_armeria_piena() -> void:
	# regola 5: lo spazio (di qualunque classe) non cambia mai l'estrazione
	var sigs: Array = []
	for full in [false, true]:
		assert_true(Game.new_game(1, "normal", 15003))
		for t in ["feature:market", "feature:crates"]:
			if not (GameState.data.unlocks as Array).has(t):
				GameState.data.unlocks.append(t)
		var b := Game.system("bank") as BankSystem
		b.add("key_t1", 20, "test")
		b.add("crate_millbrook", 20, "test")
		if full:
			_fill_gear(b)
		var res := (Game.system("crates") as CrateSystem).open("crate_millbrook", 10, false)
		var sig: Array = []
		for r in res:
			sig.append([str(r.def_id), str(r.rarity), snappedf(float(r.instance.get("float", 0.0)), 0.000001), int(r.instance.get("seed", 0))])
		sigs.append(sig)
		Game.stop_game(false)
	assert_eq(sigs[0], sigs[1], "stesse estrazioni con l'Armeria vuota o piena")


func test_fuzz_corto_conserva_gli_invarianti() -> void:
	var b := _make()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1500
	var gids := _gear_ids()
	var stacks := _stack_ids(200)
	b.state.slots_bought = 40
	for i in 1500:
		match rng.randi() % 6:
			0, 1:
				b.add(stacks[rng.randi() % stacks.size()], 1 + rng.randi() % 5)
			2:
				b.add_instance({"def": gids[rng.randi() % gids.size()]})
			3:
				b.add(COLLECT, 1 + rng.randi() % 2)
			4:
				var list := b.list_instances()
				if not list.is_empty():
					b.remove_instance(str(list[rng.randi() % list.size()].uid))
			_:
				b.tick(0.1)
		if i % 50 == 0:
			_check_invariants(b, "passo %d" % i)
			assert_lte(b.gear_used(), b.gear_cap())
	_check_invariants(b, "fine")
