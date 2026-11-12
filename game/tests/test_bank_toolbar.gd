extends GutTest
## F12 (progetto di interfaccia, docs/ui_redesign/06 §3.9): intestazione del Deposito in una riga senza valute, filtri e vendita
## in due menù con le stesse azioni di prima, contatore dei filtri, dettaglio solo con un oggetto selezionato.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
const MAX_PULSANTI_ATTIVI := 30     # prima di F12: 60 (catture 60h_1280x720_bank)

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float


func before_all() -> void:
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_toolbar_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 12712))


func after_each() -> void:
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	get_tree().root.content_scale_factor = _old_scale
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _stock() -> void:
	var b := _bank()
	b.state.slots_bought = int(b.state.slots_bought) + 200
	var n := 0
	for d in DataRegistry.items_by_category("equipment"):
		b.add(str(d.id), 2, "test")
		n += 1
		if n >= 12:
			break
	b.add("log_pine", 40, "test")


func _screen() -> Control:
	_stock()
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	return scr


func _item_texts(m: MenuButton) -> PackedStringArray:
	var out := PackedStringArray()
	var p := m.get_popup()
	for i in p.item_count:
		out.append(p.get_item_text(i))
	return out


func test_intestazione_senza_valute_e_con_spazi_espandi_valore() -> void:
	var scr := _screen()
	await wait_process_frames(2)
	assert_null(scr.find_child("CurrencyFlow", true, false), "nessuna riga di valute nel Deposito")
	var head := scr.find_child("HeadFlow", true, false) as Container
	assert_not_null(head)
	var slots := (scr.get("_slots_label") as Label).text
	assert_true(slots.contains("▰") or slots.contains("▱"), "barra degli spazi: " + slots)
	assert_true(slots.contains("/"), "usati/totale: " + slots)
	assert_not_null(scr.find_child("ExpandButton", true, false))
	assert_not_null(scr.find_child("HelpButton", true, false), "«?»")
	for n in ["Oro", "Gold", "Polvere", "Stardust"]:
		for l in scr.find_children("*", "Label", true, false):
			assert_false((l as Label).text.begins_with(n + " "), "nessuna valuta «%s» in intestazione" % n)


func test_filtri_e_vendita_sono_nei_menu_con_le_stesse_azioni() -> void:
	var scr := _screen()
	for n in ["_locked_chk", "_worn_chk", "_dir_btn", "_multi_btn", "_auto_btn", "_dupes_btn"]:
		assert_null(scr.get(n), "il controllo %s non esiste più" % n)
	var fm := scr.find_child("FiltersMenu", true, false) as MenuButton
	var sm := scr.find_child("SellMenu", true, false) as MenuButton
	assert_not_null(fm)
	assert_not_null(sm)
	assert_eq(fm.get_popup().item_count, 3, "Decrescente, Solo bloccati, Solo equipaggiati")
	assert_eq(sm.get_popup().item_count, 6, "in blocco, automatica, doppioni · filetto · Seleziona, Modalità vendita")
	assert_true(_item_texts(sm)[0].length() > 0 and _item_texts(sm)[1].length() > 0 and _item_texts(sm)[2].length() > 0)
	scr.call("_on_group", "gear")            # F15: «Tutto» non contiene più l'equipaggiamento (sta nell'Armeria)
	# stesse azioni: «Solo bloccati» filtra la lista come prima
	var all_n := (scr.get("_entries") as Array).size()
	assert_gt(all_n, 3)
	var uid := str((scr.get("_entries") as Array).filter(func(e): return str(e.uid) != "")[0].uid)
	_bank().set_instance_locked(uid, true)
	scr.call("_mark_dirty")
	fm.get_popup().id_pressed.emit(1)
	assert_eq((scr.get("_entries") as Array).size(), 1, "solo bloccati")
	fm.get_popup().id_pressed.emit(1)
	assert_eq((scr.get("_entries") as Array).size(), all_n, "filtro tolto")
	# «Decrescente» inverte l'ordine
	assert_true(bool(scr.get("_descending")))
	fm.get_popup().id_pressed.emit(0)
	assert_false(bool(scr.get("_descending")))
	fm.get_popup().id_pressed.emit(0)
	assert_true(bool(scr.get("_descending")))


func test_vendita_apre_gli_stessi_dialoghi() -> void:
	var scr := _screen()
	var sm := scr.find_child("SellMenu", true, false) as MenuButton
	sm.get_popup().id_pressed.emit(0)
	await wait_process_frames(2)
	var found := false
	for c in scr.get_children():
		if c is Window and c.get_script() != null and str(c.get_script().resource_path).ends_with("SellDialog.gd"):
			found = true
			c.hide()
			c.free()
	assert_true(found, "«Vendi in blocco…» apre SellDialog")
	await wait_process_frames(2)
	sm.get_popup().id_pressed.emit(1)
	await wait_process_frames(2)
	found = false
	for c in scr.get_children():
		if c is Window and c.get_script() != null and str(c.get_script().resource_path).ends_with("AutoSellDialog.gd"):
			found = true
			c.hide()
			c.free()
	assert_true(found, "«Vendita automatica…» apre AutoSellDialog")


func test_contatore_dei_filtri_attivi() -> void:
	var scr := _screen()
	var fm := scr.find_child("FiltersMenu", true, false) as MenuButton
	var base := fm.text
	assert_false(base.contains("("), "nessun filtro: nessun numero")
	scr.call("_on_only_locked", true)
	assert_true(fm.text.contains("(1)"), fm.text)
	scr.call("_on_only_worn", true)
	assert_true(fm.text.contains("(2)"), fm.text)
	assert_eq(int(scr.call("active_filter_count")), 2)
	scr.call("_on_only_locked", false)
	scr.call("_on_only_worn", false)
	assert_eq(fm.text, base)
	assert_true(fm.get_popup().is_item_checked(0), "Decrescente spuntato (ordine predefinito)")


func test_dettaglio_solo_con_selezione() -> void:
	var scr := _screen()
	var panel := scr.find_child("DetailPanel", true, false) as Control
	assert_not_null(panel)
	assert_false(panel.visible, "senza selezione la lista usa tutta la larghezza")
	for l in scr.find_children("*", "Label", true, false):
		assert_false((l as Label).text.contains("opinion"), "la frase «Ognuno ha le sue opinioni» non c'è più")
	var e: Dictionary = (scr.get("_entries") as Array)[0]
	scr.set("_selected", e.key)
	scr.call("_refresh_detail")
	assert_true(panel.visible, "con una selezione compare il dettaglio")
	scr.set("_selected", "")
	scr.call("_refresh_detail")
	assert_false(panel.visible)


func test_pulsanti_attivi_del_deposito() -> void:
	Settings.set_value("tutorials", false)
	_stock()
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	get_tree().root.content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_tree().root.size = Vector2i(1280, 720)
	await wait_process_frames(3)
	assert_true(main.show_screen("bank"))
	await wait_process_frames(4)
	main.call("_on_ui_tick")
	await wait_process_frames(4)
	var res := UiCensus.measure(main, get_viewport().get_visible_rect())
	var n := int(res.get("content", {}).get("button_attivi", 999))
	gut.p("Deposito: pulsanti attivi nel contenuto = %d" % n)
	assert_lte(n, MAX_PULSANTI_ATTIVI, "Deposito: ≤ 30 pulsanti attivi (misurati %d)" % n)
