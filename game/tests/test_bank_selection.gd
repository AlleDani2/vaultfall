extends GutTest
## F17 (docs/ui_redesign/02 §5.5, §5.2): UN SOLO motore di selezione (BankScreen._selection) per Sposta, Blocca e Vendi;
## esclusioni della modalità vendita uguali a SellRules (un solo punto di verità); Ctrl+A = tutto il visibile selezionabile;
## tasti locali del Deposito (ShortcutMap.resolve_bank) senza alcun tasto che venda o elimini.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
const STACK := "log_pine"
const STACK2 := "ore_copper"
const LOCKED := "food_carp"
const QUEST := "celestial_key"
const RELIC := "relic_millbrook_1"
const SKIN := "skin_millbrook_01"
const GEAR := "plate_helm_copper"
const UNIQUE := "queens_stinger"
var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_sel_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("bank_view", "grid")


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


## Deposito di prova: pile libere e bloccate, oggetto-missione, Reliquia, Finitura bloccata, gear indossato e unico.
func _setup(market: bool = true) -> Array:
	assert_true(Game.new_game(1, "normal", 4242))
	if market and not (GameState.data.unlocks as Array).has("feature:market"):
		GameState.data.unlocks.append("feature:market")
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = 200
	for d in b.state.stacks.keys():
		b.remove(str(d), b.count(str(d)))
	b.add(STACK, 30)
	b.add(STACK2, 12)
	b.add(LOCKED, 5)
	b.set_def_locked(LOCKED, true)
	b.add(QUEST, 1)
	var relic := b.add_instance({"def": RELIC})
	var skin := b.add_instance({"def": SKIN})
	b.set_instance_locked(skin, true)
	var worn := b.add_instance({"def": GEAR})
	var spare := b.add_instance({"def": GEAR})
	var uniq := b.add_instance({"def": UNIQUE})
	var cb := Game.system("combat") as CombatSystem
	assert_true(cb.equip(worn), "pezzo indossato per la prova")
	var host := Control.new()
	host.size = Vector2(1300, 720)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	await wait_process_frames(2)
	return [b, scr, {"relic": relic, "skin": skin, "worn": worn, "spare": spare, "unique": uniq}]


func _keys_of(scr: Control) -> Array:
	var out: Array = []
	for e in scr._entries:
		out.append(str(e.key))
	return out


func test_esclusioni_della_modalita_vendita_uguali_a_sellrules() -> void:
	var r: Array = await _setup()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var u: Dictionary = r[2]
	assert_true(scr.enter_mode("sell"))
	for key in [LOCKED, QUEST, str(u.relic), str(u.skin)]:
		scr.toggle_key(key)
	assert_eq(scr.selection_keys(), [], "bloccati, oggetti-missione, Reliquie e Finiture bloccate non si selezionano")
	scr.toggle_key(STACK)
	assert_eq(scr.selection_keys(), [STACK])
	var market := Game.system("market") as MarketSystem
	for e in scr._entries:
		var rule := SellRules.block_reason(b, market, str(e.def), str(e.uid), true)
		assert_eq(scr.is_selectable(e), rule == "", "stessa regola di SellRules: " + str(e.key))
	scr._on_group("gear")                                  # Armeria: indossato e unico protetti, il pezzo di scorta no
	scr.toggle_key(str(u.worn))
	scr.toggle_key(str(u.unique))
	scr.toggle_key(str(u.spare))
	assert_true(scr.selection_keys().has(str(u.spare)))
	assert_false(scr.selection_keys().has(str(u.worn)), "indossato mai selezionabile")
	assert_false(scr.selection_keys().has(str(u.unique)), "unico mai selezionabile")


func test_ctrl_a_seleziona_tutto_il_visibile_selezionabile() -> void:
	var r: Array = await _setup()
	var scr: Control = r[1]
	var u: Dictionary = r[2]
	var ev := InputEventKey.new()
	ev.keycode = KEY_A
	ev.ctrl_pressed = true
	ev.pressed = true
	scr._unhandled_key_input(ev)
	assert_eq(scr.selection_keys(), [], "fuori dalla modalità Ctrl+A non seleziona nulla")
	scr.enter_mode("sell")
	scr._unhandled_key_input(ev)
	var sel: Array = scr.selection_keys()
	sel.sort()
	var want := [STACK, STACK2]
	want.sort()
	assert_eq(sel, want, "solo le voci vendibili della vista (Tutto)")
	scr.exit_mode()
	scr.enter_mode("select")
	scr._unhandled_key_input(ev)
	assert_eq(scr.selection_keys().size(), scr._entries.size(), "in selezione: tutto il visibile")
	assert_true(scr.selection_keys().has(str(u.relic)))
	var t0 := Time.get_ticks_usec()
	scr.select_all_visible()
	assert_lt(Time.get_ticks_usec() - t0, 200000, "Ctrl+A: solo dizionario, nessun nodo")


func test_motore_unico_per_sposta_blocca_e_vendi() -> void:
	var r: Array = await _setup()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var u: Dictionary = r[2]
	var t := b.create_tab("Legna")
	scr.enter_mode("select")
	scr.toggle_key(STACK)
	scr.toggle_key(str(u.relic))
	var pm: PopupMenu = scr.open_move_menu(scr._move_keys(), Vector2.ZERO)
	assert_not_null(pm, "menù «Sposta in…»")
	pm.id_pressed.emit(0)                                    # la prima scheda del giocatore
	assert_eq(b.tab_of(BankSystem.tab_key(STACK, "")), t)
	assert_eq(b.tab_of(BankSystem.tab_key("", str(u.relic))), t)
	assert_eq(b.count(STACK), 30, "spostare non cambia quantità")
	assert_eq(scr.selection_keys(), [], "dopo lo spostamento la selezione si svuota")
	scr.toggle_key(STACK)
	scr.toggle_key(STACK2)
	scr.lock_selection()
	assert_true(b.is_def_locked(STACK) and b.is_def_locked(STACK2), "Blocca sulla stessa selezione")
	scr.lock_selection()
	assert_false(b.is_def_locked(STACK) or b.is_def_locked(STACK2), "tutto già bloccato: sblocca")
	var dlg: SellDialog = scr.open_selection_sell()
	assert_not_null(dlg, "Vendi… usa la stessa selezione")
	assert_eq(int(dlg.plan.pieces), 42)
	dlg.hide()
	# il gear non si sposta in una scheda (resta nell'Armeria)
	scr.clear_selection()
	scr._on_group("gear")
	scr.toggle_key(str(u.spare))
	assert_eq(scr._move_keys(), [], "l'Armeria non va nelle schede")


func test_tasti_locali_del_deposito() -> void:
	var cases := [[KEY_S, "", "select"], [KEY_V, "", "sell_mode"], [KEY_O, "", "sort"], [KEY_BRACKETLEFT, "", "tab_prev"],
		[KEY_BRACKETRIGHT, "", "tab_next"], [KEY_PAGEUP, "ctrl", "tab_prev"], [KEY_PAGEDOWN, "ctrl", "tab_next"],
		[KEY_A, "ctrl", "select_all"], [KEY_F2, "", "rename"], [KEY_LEFT, "alt", "tab_left"], [KEY_RIGHT, "alt", "tab_right"],
		[KEY_L, "shift", "lock"], [KEY_M, "shift", "move"], [KEY_ESCAPE, "", "escape"], [KEY_F, "ctrl", "search"],
		[KEY_L, "", ""], [KEY_M, "", ""], [KEY_DELETE, "", ""], [KEY_ENTER, "", ""], [KEY_SPACE, "", ""], [KEY_V, "ctrl", ""]]
	for c in cases:
		var ev := InputEventKey.new()
		ev.keycode = c[0]
		ev.pressed = true
		ev.ctrl_pressed = c[1] == "ctrl"
		ev.alt_pressed = c[1] == "alt"
		ev.shift_pressed = c[1] == "shift"
		assert_eq(ShortcutMap.resolve_bank(ev), str(c[2]), "%s %s" % [OS.get_keycode_string(c[0]), c[1]])
	for row in ShortcutMap.BANK_TABLE:
		assert_ne(tr(str(row.text)), str(row.text), "descrizione tradotta: " + str(row.text))
		assert_false(str(row.act).contains("sell") and str(row.act) != "sell_mode", "nessun tasto vende")


func test_canc_e_invio_non_vendono_ne_eliminano() -> void:
	var r: Array = await _setup()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	scr.enter_mode("sell")
	scr.select_all_visible()
	var before := JSON.stringify(b.state.stacks, "", true)
	var gold := b.gold()
	for code in [KEY_DELETE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_BACKSPACE, KEY_V, KEY_S]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = true
		scr._unhandled_key_input(ev)
	assert_eq(JSON.stringify(b.state.stacks, "", true), before, "nessun tasto vende o elimina")
	assert_eq(b.gold(), gold)


func test_escape_a_catena_ricerca_selezione_dettaglio() -> void:
	var r: Array = await _setup()
	var scr: Control = r[1]
	scr._selected = STACK
	scr.enter_mode("select")
	scr._on_query("pino")
	assert_true(scr.escape_chain())
	assert_eq(scr._query, "", "1: la ricerca")
	assert_eq(scr.mode(), "select")
	assert_true(scr.escape_chain())
	assert_eq(scr.mode(), "", "2: la selezione")
	assert_true(scr.escape_chain())
	assert_eq(scr._selected, "", "3: il dettaglio")
	assert_false(scr.escape_chain(), "niente da chiudere: la scorciatoia globale fa il suo")


func test_gamepad_lb_rb_cambiano_scheda_e_a_seleziona() -> void:
	var r: Array = await _setup()
	var scr: Control = r[1]
	var cell: Control = scr._grid.cell_for_index(0)
	cell.grab_focus()
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	scr._unhandled_input(rb)
	assert_eq(scr.current_tab(), BankTabsBar.ARMORY, "RB: scheda successiva")
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	scr._unhandled_input(lb)
	assert_eq(scr.current_tab(), "", "LB: scheda precedente")
	await wait_process_frames(1)
	cell = scr._grid.cell_for_index(0)
	cell.grab_focus()
	scr.enter_mode("select")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	scr._unhandled_input(a)
	assert_eq(scr.selection_keys(), [str(cell.get_meta("key"))], "A sulla casella a fuoco la seleziona")
	scr._unhandled_input(a)
	assert_eq(scr.selection_keys(), [], "di nuovo A: la toglie")
