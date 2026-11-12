extends GutTest
## F17, regola 7 (docs/ui_redesign/02 §4.3, 06 §3.9): schema 4 -> 5 per le schede del Deposito. Migrazione additiva e
## idempotente, oggetti identici, schede corrotte ripulite con una riga nel Registro, campi nuovi innocui per il resto del
## codice, import Base64 di un salvataggio della versione precedente, formato di rete del coop invariato.

const STACK := "log_pine"
const COLLECT := "skin_millbrook_01"
const GEAR := "plate_helm_copper"
var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_save_tabs_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _make(state: Dictionary) -> BankSystem:
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(1), EventBus)
	var sim := Simulation.new()
	var bank := BankSystem.new()
	sim.setup(ctx, [bank])
	sim.bind_state(state)
	ctx.set_meta("sim", sim)
	bank.set_meta("ctx", ctx)
	return bank


func _v4_bank() -> Dictionary:
	return {"stacks": {STACK: 12.0, "ore_copper": 3.0}, "instances": [
		{"uid": "i_000001", "def": COLLECT, "quality": "normal", "sockets": [], "rank": 0.0, "locked": true},
		{"uid": "i_000002", "def": GEAR, "quality": "fine", "sockets": [], "rank": 2.0, "locked": false}],
		"slots_bought": 4.0, "next_uid": 5.0, "recent": {STACK: 3.0}, "locked_defs": {"ore_copper": true}, "gift_done": true,
		"overflow_stacks": {}, "overflow_instances": []}


func test_versione_corrente_e_migrazione_registrata() -> void:
	assert_eq(SaveCodec.SCHEMA_VERSION, 5, "F17: 4 -> 5")
	assert_true(SaveCodec.migrations().has(4))
	for v in range(1, SaveCodec.SCHEMA_VERSION):
		assert_true(SaveCodec.migrations().has(v), "catena completa da %d" % v)


func test_v4_diventa_v5_con_oggetti_identici() -> void:
	var old := {"schema_version": 4, "bank": _v4_bank(), "currencies": {"gold": 77.0}}
	var before := JSON.stringify(old.bank, "", true)
	var res := SaveCodec.migrate(old.duplicate(true))
	assert_true(res.ok, str(res.get("error", "")))
	assert_eq(int(res.data.schema_version), 5)
	var b: Dictionary = res.data.bank
	assert_eq(b.tabs, [])
	assert_eq(b.tab_of, {})
	assert_eq(int(b.next_tab), 1)
	var after := b.duplicate(true)
	for k in ["tabs", "tab_of", "next_tab"]:
		after.erase(k)
	assert_eq(JSON.stringify(after, "", true), before, "nessuna quantità né istanza cambia")
	assert_eq(int(res.data.currencies.gold), 77)
	var again := SaveCodec.migrate_v4_to_v5(res.data.duplicate(true))
	assert_eq(JSON.stringify(again, "", true), JSON.stringify(res.data, "", true), "idempotente")


func test_migrazione_tollerante() -> void:
	assert_true(SaveCodec.migrate({"schema_version": 4}).ok, "senza Deposito non si rompe")
	var bad := SaveCodec.migrate_v4_to_v5({"bank": {"tabs": "x", "tab_of": [], "next_tab": -3}})
	assert_eq(bad.bank.tabs, [])
	assert_eq(bad.bank.tab_of, {})
	assert_eq(int(bad.bank.next_tab), 1)
	var keep := SaveCodec.migrate_v4_to_v5({"bank": {"tabs": [{"id": "t_0001", "name": "A"}], "tab_of": {"s:x": "t_0001"}, "next_tab": 2}})
	assert_eq((keep.bank.tabs as Array).size(), 1, "campi già validi non si toccano")
	assert_eq(int(keep.bank.next_tab), 2)


func test_un_v4_con_340_pezzi_e_deposito_pieno_si_apre_con_lo_spazio_sceso() -> void:
	var gids: Array = []
	for it in DataRegistry.items_by_category("equipment"):
		gids.append(str(it.id))
	var insts: Array = []
	for i in 340:
		insts.append({"uid": "i_%06d" % (i + 1), "def": gids[i % gids.size()], "quality": "normal", "sockets": [], "rank": 0, "locked": false})
	var stacks := {}
	var n := 0
	for it in DataRegistry.items_by_category("material"):
		if n >= 60:
			break
		stacks[str(it.id)] = 3
		n += 1
	var old := {"schema_version": 4, "bank": {"stacks": stacks, "instances": insts, "slots_bought": 300, "next_uid": 341,
		"recent": {}, "locked_defs": {}, "gift_done": true, "overflow_stacks": {}, "overflow_instances": []}}
	var res := SaveCodec.migrate(old)
	assert_true(res.ok)
	var b := _make({"bank": res.data.bank})
	assert_eq(b.used_slots(), 60, "Spazio sceso: il gear sta nell'Armeria")
	assert_eq(b.instance_count(), 340, "nessun pezzo tolto")
	assert_eq(b.state.stacks.size(), 60)
	assert_eq(b.tab_count(), 0)


func test_schede_corrotte_ripulite_con_una_riga_nel_registro() -> void:
	var bank := _v4_bank()
	var tabs: Array = []
	for i in 15:
		tabs.append({"id": "t_%04d" % (i + 1), "name": "Scheda %d" % i, "icon": STACK, "sort": {"id": "recent", "desc": true}})
	tabs[1]["name"] = "[b]   [/b]"                 # nome non valido
	tabs[2]["name"] = "x".repeat(60)                # troppo lungo
	tabs[3]["icon"] = "oggetto_sparito"             # icona sconosciuta
	tabs[4]["sort"] = {"id": "boh", "desc": 3}      # ordinamento sbagliato
	tabs[5] = {"id": "t_0001", "name": "id doppio"} # id già usato
	tabs[6] = "non una scheda"
	tabs[7]["name"] = "SCHEDA 0"                    # nome doppio (maiuscole)
	bank["tabs"] = tabs
	bank["tab_of"] = {"s:" + STACK: "t_0001", "u:i_000001": "t_0003", "u:i_000002": "t_0001", "u:i_999999": "t_0001",
		"s:oggetto_sparito": "t_0001", "s:ore_copper": "t_0099", "zzz": "t_0001", "s:gold": "t_0001"}
	bank["next_tab"] = 2
	var notes: Array = []
	var cb := func(_k: String, text: String, meta: Dictionary) -> void:
		if str(meta.get("reason", "")) == "bank_tabs_cleaned":
			notes.append(text)
	EventBus.notice.connect(cb)
	var b := _make({"bank": bank})
	b.tick(0.1)
	b.tick(0.1)
	EventBus.notice.disconnect(cb)
	assert_eq(notes.size(), 1, "una riga sola nel Registro")
	assert_lte(b.tab_count(), b.max_tabs(), "schede oltre il limite tolte")
	var ids: Dictionary = {}
	var names: Dictionary = {}
	for t in b.tabs():
		assert_false(ids.has(str(t.id)), "id unici")
		ids[str(t.id)] = true
		var nm := str(t.name)
		assert_true(nm.length() >= 1 and nm.length() <= b.tab_name_max(), "nome valido: " + nm)
		assert_false(nm.contains("[") or nm.contains("]"))
		assert_false(names.has(nm.to_lower()), "nomi unici: " + nm)
		names[nm.to_lower()] = true
		assert_true(str(t.icon) == "" or DataRegistry.has_item(str(t.icon)))
		assert_true(BankSystem.TAB_SORTS.has(str(t.sort.id)))
	assert_gt(int(b.state.next_tab), 12, "il contatore supera gli id esistenti (mai riusati)")
	assert_eq(b.tab_of("s:" + STACK), "t_0001", "assegnazione valida conservata")
	assert_eq(b.tab_of("u:i_000001"), "t_0003")
	for k in ["u:i_000002", "u:i_999999", "s:oggetto_sparito", "s:ore_copper", "zzz", "s:gold"]:
		assert_false((b.state.tab_of as Dictionary).has(k), "ripulita: " + k)
	assert_eq(b.count(STACK), 12, "nessun oggetto toccato")
	assert_eq(b.instance_count(), 2)
	assert_true(b.is_instance_locked("i_000001"))
	assert_true(b.is_def_locked("ore_copper"))


func test_i_campi_nuovi_non_cambiano_nulla_per_il_resto_del_codice() -> void:
	var plain := _make({"bank": _v4_bank()})
	var withtabs := _v4_bank()
	withtabs["tabs"] = [{"id": "t_0001", "name": "A", "icon": "", "sort": {"id": "recent", "desc": true}}]
	withtabs["tab_of"] = {"s:" + STACK: "t_0001"}
	withtabs["next_tab"] = 2
	var tabbed := _make({"bank": withtabs})
	assert_eq(tabbed.used_slots(), plain.used_slots())
	assert_eq(tabbed.capacity(), plain.capacity())
	assert_eq(tabbed.total_value(), plain.total_value())
	assert_eq(tabbed.gear_used(), plain.gear_used())
	assert_eq(SellRules.collect(tabbed, null, SellRules.new_filter("material")).pieces,
		SellRules.collect(plain, null, SellRules.new_filter("material")).pieces, "vendita per filtro invariata")
	# il formato di rete del coop non porta MAI il Deposito (quindi nemmeno le schede): chiave vietata nella scheda e nei messaggi
	assert_true(CoopSheet.FORBIDDEN_KEYS.has("bank"))
	assert_true(CoopLinkMessage.FORBIDDEN.has("bank"))


func test_import_base64_di_un_salvataggio_v4() -> void:
	assert_true(Game.new_game(1, "normal", 1717))
	var b := Game.system("bank") as BankSystem
	b.add(STACK, 40)
	var u := b.add_instance({"def": COLLECT})
	b.set_instance_locked(u, true)
	var snap := Game.snapshot(true).duplicate(true)
	snap["schema_version"] = 4
	for k in ["tabs", "tab_of", "next_tab", "tabs_intro_done"]:
		(snap.bank as Dictionary).erase(k)
	var stacks_before := JSON.stringify(snap.bank.stacks, "", true)
	var inst_before := JSON.stringify(snap.bank.instances, "", true)
	Game.stop_game(false)
	var res := SaveService.import_string(SaveCodec.to_base64(snap), 1, true)
	assert_true(bool(res.ok), str(res.get("error", "")))
	assert_eq(int(res.data.schema_version), SaveCodec.SCHEMA_VERSION)
	var loaded := Game.load_game(1)
	assert_true(bool(loaded.get("ok", false)), str(loaded))
	var b2 := Game.system("bank") as BankSystem
	assert_eq(JSON.stringify(b2.state.stacks, "", true), stacks_before, "pile identiche")
	assert_eq(JSON.stringify(b2.state.instances, "", true), inst_before, "istanze identiche")
	assert_eq(b2.tab_count(), 0)
	assert_eq(b2.state.tab_of, {})
	var t := b2.create_tab("Dopo")
	b2.assign_to_tab([BankSystem.tab_key(STACK, "")], t)
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(bool(Game.load_game(1).get("ok", false)))
	var b3 := Game.system("bank") as BankSystem
	assert_eq(b3.tab_of(BankSystem.tab_key(STACK, "")), t, "salva e ricarica: la scheda resta")
	assert_eq(str(b3.get_tab(t).name), "Dopo")
