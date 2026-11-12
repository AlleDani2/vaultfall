extends GutTest
## F17 (docs/ui_redesign/02 §5.7): ricerca del Deposito con attesa (constants.bank.ui.search_debounce_ms), minuscolo e senza
## accenti, parole in AND, operatori cat: t: lock: q: rar:, scheda virtuale «Risultati (n)» che attraversa schede e Armeria,
## Esc che la chiude e torna alla scheda di prima senza perdere la posizione.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
const GEAR := "plate_helm_copper"
const SKIN := "skin_millbrook_01"
var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_search_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("bank_view", "grid")
	Settings.set_value("locale", "it")


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(n_items: int = 300) -> Array:
	assert_true(Game.new_game(1, "normal", 31337))
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = 2000
	var n := 0
	for it in DataRegistry.all_items().values():
		if n >= n_items:
			break
		if it.category != "currency" and bool(it.get("stackable", false)):
			b.add(it.id, 2 + n)
			n += 1
	var host := Control.new()
	host.size = Vector2(1300, 720)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	await wait_process_frames(2)
	return [b, scr]


func test_normalizzazione_e_corrispondenze() -> void:
	assert_eq(BankSystem.search_norm("  Àncora  CITTÀ  perché "), "ancora citta perche")
	assert_true(BankSystem.search_soft_match("materiale", "materiali"), "singolare ~ plurale")
	assert_true(BankSystem.search_soft_match("mat", "materiali"), "prefisso")
	assert_false(BankSystem.search_soft_match("cibo", "materiali"))
	var pq := BankSystem.parse_search("Spàda  rame t:3 lock: cat:x", {"cat": {"material": ["materiali"]}})
	assert_eq(pq.words, ["spada", "rame"])
	assert_eq(int(pq.ops.t), 3)
	assert_true(bool(pq.ops.lock))
	assert_eq(pq.ops.cat, {}, "operatore senza corrispondenza: nessun risultato")
	var names := {"cat": {"material": ["materiali"], "seed": ["semi"]}, "cat_group": {"material": ["materiali"], "seed": ["materiali"]}}
	assert_eq(BankSystem.parse_search("cat:materiale", names).ops.cat, {"material": true}, "prima il nome della categoria")
	var only_group := {"cat": {"seed": ["semi"]}, "cat_group": {"seed": ["orto"]}}
	assert_eq(BankSystem.parse_search("cat:orto", only_group).ops.cat, {"seed": true}, "poi, se serve, il nome del gruppo")
	assert_true(BankSystem.search_matches(BankSystem.parse_search("rame spada", {}), {"name": "spada di rame"}), "AND in qualunque ordine")
	assert_false(BankSystem.search_matches(BankSystem.parse_search("rame ferro", {}), {"name": "spada di rame"}))


func test_accenti_e_and_sul_deposito() -> void:
	var r: Array = await _open()
	var scr: Control = r[1]
	var first: Dictionary = scr._entries[0]
	var words: PackedStringArray = BankSystem.search_norm(str(first.label)).split(" ", false)
	scr._on_query(str(first.label).to_upper())
	assert_gt(scr._entries.size(), 0, "maiuscole indifferenti")
	for e in scr._entries:
		for w in words:
			assert_true(BankSystem.search_norm(str(e.label)).contains(w), "tutte le parole: " + str(e.label))
	scr._on_query(words[0] + " zzzqqq")
	assert_eq(scr._entries.size(), 0, "AND: una parola che non c'è esclude tutto")
	assert_true(scr._empty_label.visible)
	assert_true(scr._empty_btn.visible, "stato vuoto con «Cancella ricerca»")
	scr._on_empty_action()
	assert_eq(scr._query, "")


func test_operatori() -> void:
	var r: Array = await _open()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var u := b.add_instance({"def": GEAR, "quality": "masterwork"})
	b.add_instance({"def": GEAR, "quality": "normal"})
	b.add_instance({"def": SKIN})
	b.set_def_locked("log_pine", true)
	b.add(str(DataRegistry.items_by_category("seed")[0].id), 5)          # i semi stanno nel gruppo «Materiali», ma non sono materiali
	scr._mark_dirty()
	scr._on_query("t:1")
	assert_gt(scr._entries.size(), 0)
	for e in scr._entries:
		assert_eq(int(e.tier), 1, "t:1")
	scr._on_query("cat:materiale")
	assert_gt(scr._entries.size(), 0)
	for e in scr._entries:
		assert_eq(str(DataRegistry.item(str(e.def)).category), "material", "cat:materiale -> " + str(e.def))
	scr._on_query("lock:")
	assert_eq(scr._entries.size(), 1)
	assert_eq(str(scr._entries[0].def), "log_pine", "lock: solo i bloccati")
	scr._on_query("q:capolavoro")
	assert_eq(scr._entries.size(), 1, "q: qualità dell'istanza (anche dall'Armeria)")
	assert_eq(str(scr._entries[0].uid), u)
	scr._on_query("rar:rara")
	assert_gt(scr._entries.size(), 0)
	for e in scr._entries:
		assert_eq(str(e.rar), "rare")


func test_scheda_risultati_attraversa_schede_e_armeria_ed_esc_torna_indietro() -> void:
	var r: Array = await _open(400)
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	b.add_instance({"def": GEAR})
	var t := b.create_tab("Mia")
	var keys: Array = []
	for d in b.state.stacks:
		keys.append(BankSystem.tab_key(str(d), ""))
	b.assign_to_tab(keys, t)
	scr._select_tab(t)
	assert_eq(scr.current_tab(), t)
	await wait_process_frames(2)
	scr._grid.scroll_to_row(5)
	var row: int = scr._grid.first_row()
	var gear_name := Loc.t(DataRegistry.item(GEAR).name)
	scr._on_query(gear_name)
	assert_eq(scr.current_tab(), BankTabsBar.RESULTS)
	var found := false
	for e in scr._entries:
		found = found or str(e.def) == GEAR
	assert_true(found, "la ricerca trova anche nell'Armeria")
	var rb: Button = scr._tabs_bar.buttons.get(BankTabsBar.RESULTS)
	assert_not_null(rb, "scheda «Risultati (n)» davanti alle altre")
	assert_true(rb.text.contains(str(scr._entries.size())))
	assert_eq(scr._tabs_bar.order()[0], BankTabsBar.RESULTS)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	scr._unhandled_key_input(esc)
	assert_eq(scr._query, "")
	assert_eq(scr.current_tab(), t, "Esc torna alla scheda di prima")
	assert_eq(scr._grid.first_row(), row, "senza perdere la posizione")
	assert_null(scr._tabs_bar.buttons.get(BankTabsBar.RESULTS), "Risultati chiusa")


func test_attesa_dopo_l_ultimo_tasto() -> void:
	var r: Array = await _open(50)
	var scr: Control = r[1]
	var ms := int(DataRegistry.constants.bank.ui.search_debounce_ms)
	assert_almost_eq(scr._debounce.wait_time, ms / 1000.0, 0.0001, "attesa dai dati")
	scr._search.text = "zzz"
	scr._on_query_typed("zzz")
	assert_eq(scr._query, "", "subito: ancora niente ricerca")
	await wait_seconds(ms / 1000.0 + 0.15)
	assert_eq(scr._query, "zzz", "dopo l'attesa la ricerca parte")
