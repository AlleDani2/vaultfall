extends GutTest
## F17 (docs/ui_redesign/02 §4.3, §5.1): schede del Deposito create dal giocatore. Limiti dai dati (constants.bank.ui), nomi
## ripuliti e unici, eliminazione che non perde oggetti, assegnazione «appiccicosa», gear non assegnabile, salvataggio identico.

const STACK := "log_pine"
const STACK2 := "ore_copper"
const COLLECT := "skin_millbrook_01"
const GEAR := "plate_helm_copper"
const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_tabs_%d" % Time.get_ticks_usec()
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


func _screen() -> Array:
	assert_true(Game.new_game(1, "normal", 2468))
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = 300
	for d in b.state.stacks.keys():
		b.remove(str(d), b.count(str(d)))
	var n := 0
	for it in DataRegistry.all_items().values():
		if n >= 60:
			break
		if bool(it.get("stackable", false)) and it.category != "currency":
			b.add(str(it.id), 3)
			n += 1
	b.add_instance({"def": GEAR})
	b.add_instance({"def": COLLECT})
	var host := Control.new()
	host.size = Vector2(1300, 720)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	await wait_process_frames(2)
	return [b, scr]


func _make(state: Dictionary = {}) -> BankSystem:
	if not state.has("bank"):
		state["bank"] = {"gift_done": true, "slots_bought": 500}
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(1), EventBus)
	var sim := Simulation.new()
	var bank := BankSystem.new()
	sim.setup(ctx, [bank])
	sim.bind_state(state)
	ctx.set_meta("sim", sim)
	bank.set_meta("ctx", ctx)
	return bank


func _ui() -> Dictionary:
	return DataRegistry.constants.bank.ui


func test_limiti_dai_dati() -> void:
	var b := _make()
	assert_eq(b.max_tabs(), int(_ui().max_tabs), "max_tabs dai dati")
	assert_eq(b.tab_name_max(), int(_ui().tab_name_max))
	for i in b.max_tabs():
		assert_ne(b.create_tab("Scheda %d" % i), "", "scheda %d" % i)
	assert_false(b.can_add_tab())
	assert_eq(b.create_tab("Troppe"), "", "oltre il limite non si crea")
	assert_eq(b.tab_count(), b.max_tabs())


func test_nomi_ripuliti_e_unici() -> void:
	var b := _make()
	var lim := b.tab_name_max()
	assert_eq(b.create_tab("   "), "", "nome vuoto: rifiutato")
	assert_eq(b.create_tab("[ ] {} <>"), "", "solo segni di markup: rifiutato")
	var t1 := b.create_tab("  [color=red]Forgia[/color]  ")
	assert_eq(str(b.get_tab(t1).name), "color=redForgia/color".substr(0, lim), "niente parentesi: nessun markup possibile")
	var t2 := b.create_tab("Riga\nnuova\tcon​spazi")
	assert_eq(str(b.get_tab(t2).name), "Riga nuova con spazi".substr(0, lim).strip_edges(), "controlli e larghezza zero -> spazio")
	var long := b.create_tab("x".repeat(lim * 3))
	assert_eq(str(b.get_tab(long).name).length(), lim, "al più tab_name_max caratteri")
	var a := b.create_tab("Pozioni")
	var dup := b.create_tab("POZIONI")
	assert_eq(str(b.get_tab(a).name), "Pozioni")
	assert_eq(str(b.get_tab(dup).name), "POZIONI 2", "doppione senza distinzione di maiuscole: suffisso")
	assert_true(b.rename_tab(dup, "pozioni"))
	assert_eq(str(b.get_tab(dup).name), "pozioni 2")
	assert_true(b.rename_tab(a, "Pozioni"), "una scheda può tenere il suo nome")
	assert_eq(str(b.get_tab(a).name), "Pozioni")
	assert_false(b.rename_tab(a, ""), "rinomina vuota rifiutata")
	var full := b.create_tab("y".repeat(lim))
	var full2 := b.create_tab("y".repeat(lim))
	assert_eq(str(b.get_tab(full2).name).length(), lim, "il suffisso accorcia la base, non sfora")
	assert_ne(str(b.get_tab(full2).name), str(b.get_tab(full).name))


func test_id_mai_riusati_icone_e_ordine() -> void:
	var b := _make()
	var t1 := b.create_tab("A", STACK)
	var t2 := b.create_tab("B", "oggetto_che_non_esiste")
	assert_eq(str(b.get_tab(t1).icon), STACK)
	assert_eq(str(b.get_tab(t2).icon), "", "icona sconosciuta: icona predefinita")
	assert_false(b.set_tab_icon(t1, "oggetto_che_non_esiste"))
	b.delete_tab(t1)
	var t3 := b.create_tab("C")
	assert_ne(t3, t1, "l'id di una scheda eliminata non torna")
	assert_true(b.move_tab(t3, -1))
	assert_eq(str(b.tabs()[0].id), t3, "riordino senza trascinare")
	assert_false(b.move_tab(t3, -1), "già prima")
	assert_true(b.set_tab_sort(t3, "qty", false))
	assert_false(b.set_tab_sort(t3, "a_caso", true))
	assert_eq(b.get_tab(t3).sort, {"id": "qty", "desc": false})


func test_eliminare_una_scheda_non_perde_oggetti() -> void:
	var b := _make()
	b.add(STACK, 50)
	b.add(STACK2, 7)
	var u := b.add_instance({"def": COLLECT})
	var t := b.create_tab("Roba")
	assert_eq(b.assign_to_tab([BankSystem.tab_key(STACK, ""), BankSystem.tab_key("", u)], t), 2)
	assert_eq(int(b.tab_counts()[t]), 2)
	var used := b.used_slots()
	var val := b.total_value()
	assert_eq(b.delete_tab(t), 2, "si tolgono solo le assegnazioni")
	assert_eq(b.count(STACK), 50)
	assert_eq(b.count(STACK2), 7)
	assert_false(b.get_instance(u).is_empty())
	assert_eq(b.used_slots(), used)
	assert_eq(b.total_value(), val)
	assert_eq(b.tab_of(BankSystem.tab_key(STACK, "")), "", "torna solo in Tutto")


func test_una_scheda_per_voce_e_gear_non_assegnabile() -> void:
	var b := _make()
	b.add(STACK, 3)
	var g := b.add_instance({"def": GEAR})
	var t1 := b.create_tab("Uno")
	var t2 := b.create_tab("Due")
	var k := BankSystem.tab_key(STACK, "")
	b.assign_to_tab([k], t1)
	b.assign_to_tab([k], t2)
	assert_eq(b.tab_of(k), t2, "una voce sta in UNA scheda: l'ultima vince")
	assert_eq(int(b.tab_counts()[t1]), 0)
	assert_false(b.can_assign(BankSystem.tab_key("", g)), "l'Armeria non va nelle schede")
	assert_eq(b.assign_to_tab([BankSystem.tab_key("", g)], t1), 0)
	assert_false(b.can_assign("s:gold"), "le valute non sono caselle")
	assert_false(b.can_assign("x:qualcosa"))
	assert_eq(b.assign_to_tab([k], "t_9999"), 0, "scheda inesistente")
	assert_eq(b.assign_to_tab([k], ""), 1, "togli dalla scheda")
	assert_eq(b.tab_of(k), "")


func test_assegnazione_appiccicosa() -> void:
	var b := _make()
	b.add(STACK, 5)
	var u := b.add_instance({"def": COLLECT})
	var t := b.create_tab("Legna")
	b.assign_to_tab([BankSystem.tab_key(STACK, ""), BankSystem.tab_key("", u)], t)
	var used := b.used_slots()
	assert_true(b.remove(STACK, 5))
	assert_eq(b.tab_of(BankSystem.tab_key(STACK, "")), t, "la pila esaurita resta assegnata (segnaposto)")
	assert_eq(int(b.tab_counts()[t]), 1, "ma non conta come casella")
	assert_eq(b.used_slots(), used - 1, "e non occupa spazio")
	b.add(STACK, 2)
	assert_eq(int(b.tab_counts()[t]), 2, "quando torna, rientra nella SUA scheda")
	assert_true(b.remove_instance(u))
	assert_false((b.state.tab_of as Dictionary).has(BankSystem.tab_key("", u)), "l'istanza sparita non resta assegnata")


func test_tetto_delle_assegnazioni_scarta_prima_le_pile_esaurite() -> void:
	var b := _make()
	var t := b.create_tab("Tutto qui")
	var cap := b.tab_of_cap()
	assert_gt(cap, 0)
	var mats: Array = DataRegistry.items_by_category("material")
	# riempie il tetto con assegnazioni di pile ESAURITE (finte, ma di oggetti veri), poi una pila presente entra comunque
	var i := 0
	while (b.state.tab_of as Dictionary).size() < cap:
		b.state.tab_of["s:%s" % str(mats[i % mats.size()].id) + ("" if i < mats.size() else "#%d" % i)] = t
		i += 1
	b.add(STACK, 1)
	assert_eq(b.assign_to_tab([BankSystem.tab_key(STACK, "")], t), 1, "posto fatto scartando le esaurite")
	assert_lte((b.state.tab_of as Dictionary).size(), cap)
	assert_eq(b.tab_of(BankSystem.tab_key(STACK, "")), t)


func test_round_trip_identico() -> void:
	var b := _make()
	b.add(STACK, 9)
	var u := b.add_instance({"def": COLLECT})
	var t := b.create_tab("Ricordi", COLLECT)
	b.create_tab("Seconda")
	b.assign_to_tab([BankSystem.tab_key("", u), BankSystem.tab_key(STACK, "")], t)
	b.set_tab_sort(t, "name", false)
	b.mark_tabs_intro_done()
	var json := JSON.stringify(b.to_state(), "", false, true)
	var back: Variant = JSON.parse_string(json)
	var st := {"bank": back}
	var b2 := _make(st)
	SaveCodec.normalize(st, PackedStringArray(["bank.next_tab", "bank.next_uid"]))
	assert_eq(JSON.stringify(b2.tabs(), "", true), JSON.stringify(b.tabs(), "", true), "schede identiche")
	assert_eq(b2.state.tab_of, b.state.tab_of, "assegnazioni identiche")
	assert_eq(int(b2.state.next_tab), int(b.state.next_tab))
	assert_true(b2.tabs_intro_done())
	assert_false(b2._tabs_cleaned, "uno stato valido non si «ripulisce»")
	assert_eq(b2.count(STACK), 9)


# ------------------------------------------------------------------ schermata: barra, invarianti, benvenuto, suggerite, tutorial

func test_barra_delle_schede_e_conteggi() -> void:
	var r: Array = await _screen()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var bar: BankTabsBar = scr._tabs_bar
	assert_eq(bar.order().slice(0, 2), ["", BankTabsBar.ARMORY], "Tutto e Armeria fisse, prima e seconda")
	assert_true((bar.buttons[""] as Button).text.contains(str(b.used_slots())), "Tutto porta le caselle dello Spazio")
	assert_eq(scr._entries.size(), b.used_slots(), "R-SP-7a resta vero con le schede")
	var t := b.create_tab("Metà")
	var keys: Array = []
	for i in 10:
		keys.append(BankSystem.tab_key(str(b.state.stacks.keys()[i]), ""))
	b.assign_to_tab(keys, t)
	scr._mark_dirty()
	assert_true((bar.buttons[t] as Button).text.ends_with(" 10"), "il numero è il conteggio delle caselle")
	scr._on_tab_chosen(t)
	assert_eq(scr._entries.size(), 10, "la scheda mostra solo le sue voci")
	scr._on_tab_chosen("")
	assert_eq(scr._entries.size(), b.used_slots(), "Tutto le contiene tutte")
	for i in b.max_tabs() - 1:
		b.create_tab("S%d" % i)
	scr._mark_dirty()
	assert_true(bar.add_btn.disabled, "[+] spento al limite")
	assert_true(bar.add_btn.tooltip_text.contains(str(b.max_tabs())), "con il perché nel tooltip")


func test_ordina_salvato_per_scheda() -> void:
	var r: Array = await _screen()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var t := b.create_tab("Ordinata")
	scr._on_tab_chosen(t)
	var qi := -1
	for i in scr.SORTS.size():
		if scr.SORTS[i].id == "qty":
			qi = i
	scr._on_sort(qi)
	assert_eq(str(b.get_tab(t).sort.id), "qty", "salvato nella scheda del giocatore")
	scr._on_tab_chosen("")
	scr._on_sort(1)
	scr._on_tab_chosen(t)
	assert_eq(scr._sort, "qty", "tornando nella scheda si ritrova il suo ordinamento")


func test_trascinamento_e_alternativa() -> void:
	var r: Array = await _screen()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var t := b.create_tab("Dest")
	var k := BankSystem.tab_key(str(b.state.stacks.keys()[0]), "")
	var bar: BankTabsBar = scr._tabs_bar
	var data := {"type": BankTabsBar.DRAG_KEYS, "keys": [k]}
	assert_true(bar._can_drop(Vector2.ZERO, data, t), "si rilascia su una scheda")
	assert_false(bar._can_drop(Vector2.ZERO, data, BankTabsBar.ARMORY), "non sull'Armeria")
	bar._drop(Vector2.ZERO, data, t)
	assert_eq(b.tab_of(k), t)
	bar._drop(Vector2.ZERO, data, "")
	assert_eq(b.tab_of(k), "", "rilascio su Tutto = togli dalla scheda")
	var cell: Control = scr._grid.cell_for_index(0)
	var dd: Variant = scr._cell_drag(Vector2.ZERO, cell)
	assert_true(dd is Dictionary and (dd.keys as Array).size() == 1, "la cella si trascina")
	# riordino senza trascinare: Alt+→ sulla scheda e menù del tasto destro
	var t2 := b.create_tab("Dopo")
	scr._mark_dirty()
	var ev := InputEventKey.new()
	ev.keycode = KEY_RIGHT
	ev.alt_pressed = true
	ev.pressed = true
	bar._on_tab_input(ev, t)
	assert_eq(str(b.tabs()[1].id), t, "Alt+→ sposta a destra")
	var pm := bar.open_tab_menu(t2, Vector2.ZERO)
	assert_gt(pm.item_count, 5, "Rinomina, Icona, Sinistra, Destra, Blocca tutta, Elimina")
	pm.hide()


func test_eliminare_con_conferma_non_perde_nulla() -> void:
	var r: Array = await _screen()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var t := b.create_tab("Via")
	var d0 := str(b.state.stacks.keys()[0])
	b.assign_to_tab([BankSystem.tab_key(d0, "")], t)
	scr._on_tab_chosen(t)
	var dlg: ConfirmationDialog = scr.ask_delete_tab(t)
	assert_not_null(dlg, "scheda non vuota: chiede conferma")
	assert_true(dlg.dialog_text.contains("1"))
	assert_eq(b.tab_count(), 1, "niente prima della conferma")
	dlg.confirmed.emit()
	assert_eq(b.tab_count(), 0)
	assert_eq(scr.current_tab(), "", "si torna in Tutto")
	assert_eq(b.count(d0), 3, "nessun oggetto perso")
	var empty := b.create_tab("Vuota")
	assert_null(scr.ask_delete_tab(empty), "scheda vuota: si elimina subito")
	assert_eq(b.tab_count(), 0)


func test_benvenuto_una_tantum_e_schede_suggerite() -> void:
	var r: Array = await _screen()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	assert_true(scr._welcome.visible, "riquadro di benvenuto alla prima apertura")
	var plan: Array = scr.suggested_plan()
	assert_gt(plan.size(), 0)
	var total := 0
	for p in plan:
		assert_true(scr.SUGGESTED_GROUPS.has(str(p.group)))
		assert_ne(str(p.name), "", "nome suggerito = chiave bilingue del gruppo")
		total += (p.keys as Array).size()
	var used := b.used_slots()
	var dlg: ConfirmationDialog = scr.open_suggested()
	assert_eq(b.tab_count(), 0, "mai automatico: prima l'anteprima")
	dlg.confirmed.emit()
	assert_eq(b.tab_count(), plan.size())
	var assigned := 0
	for v in b.tab_counts().values():
		assigned += int(v)
	assert_eq(assigned, total, "le voci dell'anteprima sono nelle schede")
	assert_eq(b.used_slots(), used, "nulla si sposta di spazio")
	assert_false(scr._welcome.visible)
	assert_true(b.tabs_intro_done(), "una volta sola (salvato nella partita)")
	for p in scr.suggested_plan():
		assert_eq((p.keys as Array).size(), 0, "ripetere non ruba voci già assegnate")


func test_passo_del_tutorial_f_bank_tabs() -> void:
	assert_true(Game.new_game(1, "normal", 1357))
	var step := TutorialCatalog.get_step("f_bank_tabs")
	assert_false(step.is_empty())
	assert_true(TutorialCatalog.targets_of(step).has("bank_tabs"))
	var ts := Game.system("tutorial") as TutorialSystem
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = 300
	var lim := int(DataRegistry.constants.bank.ui.tabs_hint_used)
	var mats: Array = DataRegistry.items_by_category("material")
	var i := 0
	while b.used_slots() < lim:
		b.add(str(mats[i].id), 1)
		i += 1
	assert_false(ts.conds_ok(step), "fino alla soglia dei dati non compare")
	b.add(str(mats[i].id), 1)
	assert_true(ts.conds_ok(step), "oltre la soglia sì")
	assert_ne(tr(TutorialCatalog.title_key("f_bank_tabs")), TutorialCatalog.title_key("f_bank_tabs"))
	assert_ne(tr(TutorialCatalog.body_key("f_bank_tabs")), TutorialCatalog.body_key("f_bank_tabs"))
