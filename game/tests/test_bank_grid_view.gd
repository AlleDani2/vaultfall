extends GutTest
## Deposito a griglia (F16, docs/ui_redesign/02 §5): vista predefinita, interruttore griglia/lista, densità, cella, gesti sicuri,
## tasti, nodi e tempi dentro il budget del doc 02 §7.1.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_grid_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("bank_view", "grid")
	Settings.set_value("bank_density", "auto")


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("bank_view", "grid")
	Settings.set_value("bank_density", "auto")


func _open(width: float = 1300.0, items: int = 400) -> Array:
	assert_true(Game.new_game(1, "normal", 5))
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 2000
	var n := 0
	for it in DataRegistry.all_items().values():
		if n >= items:
			break
		if it.category != "currency" and not (it.has("equipment") or it.has("tool")):
			bank.add(it.id, 3 + n)
			n += 1
	var host := Control.new()
	host.size = Vector2(width, 700)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	await wait_process_frames(3)
	return [bank, scr, host]


func _count_nodes(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _count_nodes(c)
	return t


func _lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


func test_la_griglia_e_la_vista_predefinita() -> void:
	assert_eq(Settings.DEFAULTS.bank_view, "grid")
	var r := await _open()
	var scr: Control = r[1]
	assert_true(scr._grid.visible)
	assert_false(scr._list.visible)
	assert_eq(scr._grid.count(), (r[0] as BankSystem).used_slots(), "«Tutto» = lo Spazio usato")
	assert_eq(scr._list.count(), 0, "la vista nascosta non ha voci né nodi")
	assert_eq(scr._list.pool_size(), 0)


func test_interruttore_griglia_lista_e_preferenza() -> void:
	var r := await _open()
	var scr: Control = r[1]
	(scr.find_child("View_list", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_eq(Settings.get_value("bank_view"), "list", "la scelta sta nelle Impostazioni")
	assert_true(scr._list.visible)
	assert_false(scr._grid.visible)
	assert_eq(scr._list.count(), scr._entries.size())
	assert_eq(scr._grid.count(), 0)
	(scr.find_child("View_grid", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_eq(scr._grid.count(), scr._entries.size())
	assert_false(Settings.set_value("bank_view", "tabella"), "valore non valido rifiutato")


func test_densita_auto_dalla_larghezza_e_scelta() -> void:
	var r := await _open(1300.0)
	var scr: Control = r[1]
	assert_false(scr._compact, "1300 px utili: comoda")
	assert_eq(scr._grid.cell_w, ItemCell.COMFORT.x + 4.0)
	(r[2] as Control).size = Vector2(900, 700)
	await wait_process_frames(2)
	assert_true(scr._compact, "sotto 1100 px utili: compatta da sola")
	assert_eq(scr._grid.cell_w, ItemCell.COMPACT.x + 4.0)
	var cols_compact: int = scr._grid.columns()
	assert_gt(cols_compact, 8)
	(scr.find_child("DensityButton", true, false) as Button).button_pressed = false
	await wait_process_frames(2)
	assert_eq(Settings.get_value("bank_density"), "comfortable")
	assert_false(scr._compact)
	assert_lt(scr._grid.columns(), cols_compact)


func test_cella_un_nodo_solo_e_icona_a_fattore_intero() -> void:
	var r := await _open()
	var scr: Control = r[1]
	var c := scr._grid._pool[0] as ItemCell
	assert_eq(c.get_child_count(), 0, "una cella = un nodo, tutto disegnato con _draw")
	assert_eq(c.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "icone nitide, mai interpolate")
	assert_eq(c.icon_px(), 64, "comoda: 2×")
	assert_eq(c.size, ItemCell.COMFORT)
	(r[2] as Control).size = Vector2(800, 700)
	await wait_process_frames(2)
	assert_eq((scr._grid._pool[0] as ItemCell).icon_px(), 32, "compatta: 1×")
	assert_eq((scr._grid._pool[0] as ItemCell).size, ItemCell.COMPACT)


func test_quantita_abbreviata_e_valore_esatto_nel_tooltip() -> void:
	var r := await _open(1300.0, 3)
	var bank: BankSystem = r[0]
	var scr: Control = r[1]
	var first: Dictionary = scr._entries[0]
	bank.add(str(first.def), 203480)
	scr._mark_dirty()
	scr.refresh()
	await wait_process_frames(2)
	var found: ItemCell = null
	for c in scr._grid._pool:
		if c.visible and (c as ItemCell).def_id == str(first.def):
			found = c
	assert_not_null(found)
	var n := float(bank.count(str(first.def)))
	assert_eq(found.qty_text, NumberFormat.cell(n, _lang()))
	assert_true(found.qty_text.ends_with("K"), "203.4xx diventa «203 K»")
	assert_true(found.qty_exact.contains(NumberFormat.group_int(n, _lang())), "il valore esatto è nel tooltip")


func test_budget_nodi_e_tempi_con_molte_voci() -> void:
	var r := await _open(1800.0, 600)
	var scr: Control = r[1]
	assert_gte(scr._entries.size(), 400)
	assert_lte(_count_nodes(scr), 400, "celle + chrome ≤ 400 nodi (doc 02 §7.1)")
	assert_lt(scr._grid.pool_size(), 200)
	var f0 := PerfGate.load_factor()
	var ms := PerfGate.best_of(func() -> void:
		for i in 60:
			scr._grid.scroll_to_row(i), 3)
	PerfGate.assert_time(self, "rebind per scorrimento (60 salti, migliore di 3)", ms, 180.0, PerfGate.factor_around(f0))


func test_doppio_clic_non_vende_e_non_scarta() -> void:
	var r := await _open(1300.0, 20)
	var bank: BankSystem = r[0]
	var scr: Control = r[1]
	var before := bank.used_slots()
	var stacks_before: Dictionary = bank.state.stacks.duplicate()
	var c := scr._grid._pool[0] as ItemCell
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	c._gui_input(ev)
	await wait_process_frames(2)
	assert_eq(bank.used_slots(), before)
	assert_eq(bank.state.stacks, stacks_before, "nessuna quantità cambia con un doppio clic")
	assert_eq(scr._selected, str(c.get_meta("key")), "il doppio clic seleziona e mostra il dettaglio")


func test_doppio_clic_equipaggia_un_pezzo_dell_armeria() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var bank := Game.system("bank") as BankSystem
	var cb := Game.system("combat") as CombatSystem
	var uid := bank.add_instance({"def": "sword_copper"})
	var host := Control.new()
	host.size = Vector2(1300, 700)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	scr._on_group("gear")
	await wait_process_frames(3)
	var cell: ItemCell = null
	for c in scr._grid._pool:
		if c.visible and (c as ItemCell).def_id == "sword_copper":
			cell = c
	assert_not_null(cell)
	scr._on_cell_activated(cell)
	await wait_process_frames(2)
	assert_true(cb.is_equipped(uid), "azione predefinita sicura: equipaggia")
	assert_not_null(bank.get_instance(uid), "il pezzo non è stato venduto né scartato")


func test_tasti_maiusc_l_blocca_esc_a_catena_e_l_da_sola_non_blocca() -> void:
	var r := await _open(1300.0, 20)
	var bank: BankSystem = r[0]
	var scr: Control = r[1]
	var c := scr._grid._pool[0] as ItemCell
	scr._on_cell_pressed(c)
	var def_id: String = c.def_id
	var ev := InputEventKey.new()
	ev.keycode = KEY_L
	ev.pressed = true
	scr._unhandled_key_input(ev)
	assert_false(bank.is_def_locked(def_id), "«L» da sola è il cassetto, non blocca")
	ev.shift_pressed = true
	scr._unhandled_key_input(ev)
	assert_true(bank.is_def_locked(def_id), "Maiusc+L blocca la voce scelta")
	scr._search.text = "a"
	scr._on_query("a")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	scr._unhandled_key_input(esc)
	assert_eq(scr._query, "", "Esc 1: azzera la ricerca")
	assert_ne(scr._selected, "")
	scr._unhandled_key_input(esc)
	assert_eq(scr._selected, "", "Esc 2: chiude il dettaglio")


func test_il_blocco_si_vede_come_forma_sulla_cella() -> void:
	var r := await _open(1300.0, 20)
	var bank: BankSystem = r[0]
	var scr: Control = r[1]
	var c := scr._grid._pool[0] as ItemCell
	assert_false(c.locked)
	bank.set_def_locked(c.def_id, true)
	scr._mark_dirty()
	scr.refresh()
	await wait_process_frames(2)
	var shown: ItemCell = null
	for k in scr._grid._pool:
		if k.visible and (k as ItemCell).def_id == c.def_id:
			shown = k
	assert_true(shown.locked, "la cella disegna il lucchetto")
