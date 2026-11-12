extends GutTest
## F17 (docs/ui_redesign/02 §5.5, 06 §5 U4): la vendita a selezione è a due passaggi e non può vendere per sbaglio.
## Bloccati / indossati / unici / speciali mai venduti; «Torna indietro» predefinito; il primo Invio entro
## constants.bank.ui.sell_confirm_guard_ms è ignorato; l'anteprima è l'esito reale (prezzo del Mercato, nessuna casualità);
## la modalità si spegne cambiando schermata; senza Mercato non si entra.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
const STACK := "log_pine"
const STACK2 := "ore_copper"
const LOCKED := "food_carp"
const GEAR := "plate_helm_copper"
const UNIQUE := "queens_stinger"
const RELIC := "relic_millbrook_1"
var _old_dir: String
var _now := 0


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_sell_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_now = 100000


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _clock() -> int:
	return _now


func _setup(market: bool = true) -> Array:
	assert_true(Game.new_game(1, "normal", 777))
	if market and not (GameState.data.unlocks as Array).has("feature:market"):
		GameState.data.unlocks.append("feature:market")
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = 200
	for d in b.state.stacks.keys():
		b.remove(str(d), b.count(str(d)))
	b.add(STACK, 40)
	b.add(STACK2, 9)
	b.add(LOCKED, 6)
	b.set_def_locked(LOCKED, true)
	var relic := b.add_instance({"def": RELIC})
	var worn := b.add_instance({"def": GEAR})
	var spare := b.add_instance({"def": GEAR})
	var locked_gear := b.add_instance({"def": GEAR})
	b.set_instance_locked(locked_gear, true)
	var uniq := b.add_instance({"def": UNIQUE})
	assert_true((Game.system("combat") as CombatSystem).equip(worn))
	var host := Control.new()
	host.size = Vector2(1300, 720)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	await wait_process_frames(2)
	return [b, scr, {"relic": relic, "worn": worn, "spare": spare, "locked_gear": locked_gear, "unique": uniq}]


func _guard() -> int:
	return int(DataRegistry.constants.bank.ui.sell_confirm_guard_ms)


func test_protetti_mai_venduti_e_anteprima_uguale_all_esito() -> void:
	var r: Array = await _setup()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var u: Dictionary = r[2]
	scr.enter_mode("sell")
	scr.select_all_visible()                     # Tutto: le due pile libere (la bloccata e la Reliquia no)
	scr._on_group("gear")
	scr.select_all_visible()                     # Armeria: solo il pezzo di scorta
	# anche forzando nella selezione voci protette, l'anteprima le esclude (regola unica)
	scr._selection[LOCKED] = {"def": LOCKED, "uid": ""}
	for k in ["relic", "worn", "locked_gear", "unique"]:
		scr._selection[str(u[k])] = {"def": str(b.get_instance(str(u[k])).def), "uid": str(u[k])}
	var dlg: SellDialog = scr.open_selection_sell()
	dlg.clock = _clock
	dlg.opened_ms = _now
	await wait_process_frames(2)
	assert_true(dlg.get_cancel_button().has_focus(), "«Torna indietro» ha il fuoco: è il predefinito")
	assert_eq(dlg.get_cancel_button().text, tr("UI_BANKG_SELLP_BACK"))
	assert_eq(int(dlg.plan.skipped), 5, "5 voci protette tolte dall'anteprima")
	var preview_gold := int(dlg.plan.gold)
	var gold0 := b.gold()
	assert_gt(preview_gold, 0)
	_now += _guard() + 1
	dlg._on_confirmed()
	assert_eq(b.gold() - gold0, preview_gold, "oro ricevuto = anteprima (Mercato, nessuna casualità)")
	assert_eq(b.count(STACK), 0)
	assert_eq(b.count(STACK2), 0)
	assert_true(b.get_instance(str(u.spare)).is_empty(), "il pezzo di scorta venduto")
	assert_eq(b.count(LOCKED), 6, "pila bloccata intatta")
	for k in ["relic", "worn", "locked_gear", "unique"]:
		assert_false(b.get_instance(str(u[k])).is_empty(), "protetto intatto: " + k)


func test_guardia_sul_primo_invio() -> void:
	var r: Array = await _setup()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	scr.enter_mode("sell")
	scr.toggle_key(STACK)
	var dlg: SellDialog = scr.open_selection_sell()
	dlg.clock = _clock
	dlg.opened_ms = _now
	assert_eq(dlg.guard_ms, _guard(), "guardia dai dati")
	dlg._on_confirmed()                           # Invio subito (tasto ripetuto): ignorato
	_now += _guard() - 1
	dlg._on_confirmed()
	assert_eq(b.count(STACK), 40, "entro la guardia nulla si vende")
	assert_true(dlg.visible, "la finestra resta aperta")
	_now += 2
	dlg._on_confirmed()
	assert_eq(b.count(STACK), 0, "dopo la guardia la conferma vende")
	assert_false(dlg.visible)
	assert_eq(scr.selection_keys(), [], "dopo la vendita la selezione si svuota; nessun annulla")


func test_quantita_per_pila_nell_anteprima() -> void:
	var r: Array = await _setup()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	scr.enter_mode("sell")
	scr.toggle_key(STACK)
	var dlg: SellDialog = scr.open_selection_sell()
	dlg.clock = _clock
	dlg.opened_ms = _now
	dlg.set_pick_qty(STACK, 15)
	assert_eq(int(dlg.plan.pieces), 15)
	var quote := (Game.system("market") as MarketSystem).quote_sell(STACK, 15)
	assert_eq(int(dlg.plan.gold), quote, "stima del Mercato dinamico per 15 unità")
	_now += _guard() + 1
	dlg._on_confirmed()
	assert_eq(b.count(STACK), 25, "si vendono solo le 15 scelte: non l'ultima scorta")


func test_la_modalita_si_spegne_cambiando_schermata() -> void:
	var r: Array = await _setup()
	var scr: Control = r[1]
	scr.enter_mode("sell")
	scr.toggle_key(STACK)
	assert_true(scr._mode_bar.visible, "barra ambra visibile")
	scr.close()
	assert_eq(scr.mode(), "", "chiudendo il Deposito la modalità vendita si spegne")
	assert_eq(scr.selection_keys(), [])


func test_la_modalita_si_spegne_anche_dal_menu_principale() -> void:
	assert_true(Game.new_game(1, "normal", 778))
	GameState.data.unlocks.append("feature:market")
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	assert_true(main.show_screen("bank"))
	await wait_process_frames(2)
	var scr: Control = main.call("current_screen")
	scr.enter_mode("sell")
	assert_eq(scr.mode(), "sell")
	assert_true(main.show_screen("summary"))
	await wait_process_frames(2)
	assert_true(main.show_screen("bank"))
	await wait_process_frames(2)
	var again: Control = main.call("current_screen")
	assert_eq(again.mode(), "", "tornando nel Deposito la vendita non è più attiva")


func test_senza_mercato_non_si_entra_in_vendita() -> void:
	var r: Array = await _setup(false)
	var scr: Control = r[1]
	(GameState.data.unlocks as Array).erase("feature:market")
	assert_false(scr.enter_mode("sell"))
	assert_eq(scr.mode(), "")
	scr._mark_dirty()
	var pop: PopupMenu = scr._sell_btn.get_popup()
	var mi := pop.get_item_index(scr.SELL_MODE)
	assert_true(pop.is_item_disabled(mi), "voce spenta con il perché nel tooltip")
	assert_ne(pop.get_item_tooltip(mi), "")
	assert_true(scr.enter_mode("select"), "la selezione (sposta, blocca) resta disponibile")
