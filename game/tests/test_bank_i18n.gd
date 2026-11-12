extends GutTest
## F17, regola 6 (docs/ui_redesign/02 R12, 07 F17): ogni testo nuovo del Deposito è bilingue (chiavi in bank_grid.csv) e nessuna
## chiave resta a vista; i NOMI DELLE SCHEDE scritti dal giocatore non si traducono mai e stanno in Button/Label (mai markup).

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"
const FILES := ["res://src/ui/screens/BankScreen.gd", "res://src/ui/screens/BankTabsBar.gd", "res://src/ui/screens/BankTabDialog.gd",
	"res://src/ui/screens/SellDialog.gd", "res://src/systems/BankSystem.gd", "res://src/systems/SellRules.gd",
	"res://src/ui/main/ShortcutMap.gd"]
var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_i18n_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("locale", "it")


func _csv() -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	var head := f.get_csv_line()
	var ie := Array(head).find("en")
	var ii := Array(head).find("it")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > maxi(ie, ii):
			out[row[0]] = [row[ie], row[ii]]
	return out


func test_ogni_chiave_nuova_e_bilingue() -> void:
	var csv := _csv()
	var re := RegEx.create_from_string("UI_BANKG_[A-Z0-9_]+")
	var n := 0
	for p in FILES:
		var src := FileAccess.get_file_as_string(p)
		for m in re.search_all(src):
			var k := m.get_string()
			if k.ends_with("_"):
				continue                                  # prefisso composto in codice (UI_BANKG_EMPTY_ACT_<AZIONE>)
			n += 1
			assert_true(csv.has(k), "chiave presente: " + k)
			if csv.has(k):
				assert_ne(str(csv[k][0]), "", "inglese: " + k)
				assert_ne(str(csv[k][1]), "", "italiano: " + k)
	for act in ["EXIT", "CLEAR_SEARCH", "CLEAR_FILTERS", "GO_SMITHING", "SELECT_MOVE", "GO_SKILLS"]:
		assert_true(csv.has("UI_BANKG_EMPTY_ACT_" + act), act)
	for k in ["UI_TUT_F_BANK_TABS_T", "UI_TUT_F_BANK_TABS_B", "UI_MAN2_BANK_HOW_7"]:
		assert_true(csv.has(k), k)
	assert_gt(n, 60)


func _texts(n: Node, out: Array) -> void:
	if n is Button or n is Label or n is LineEdit:
		var c := n as Control
		if c.is_visible_in_tree():
			var t: String = (n as LineEdit).placeholder_text if n is LineEdit else (n.get("text") as String)
			var shown := t if c.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else c.tr(t)
			out.append([c.get_path(), shown])
	for ch in n.get_children():
		_texts(ch, out)


func _open() -> Array:
	assert_true(Game.new_game(1, "normal", 99))
	GameState.data.unlocks.append("feature:market")
	var b := Game.system("bank") as BankSystem
	b.add("log_pine", 10)
	b.add("ore_copper", 4)
	var host := Control.new()
	host.size = Vector2(1300, 720)
	add_child_autofree(host)
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	host.add_child(scr)
	scr.open({})
	await wait_process_frames(2)
	return [b, scr]


func test_nessuna_chiave_a_vista_in_italiano_e_inglese() -> void:
	var r: Array = await _open()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	b.create_tab("Forgia", "log_pine")
	scr.enter_mode("sell")
	scr.toggle_key("log_pine")
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		scr._mark_dirty()
		await wait_process_frames(2)
		var all: Array = []
		_texts(scr, all)
		assert_gt(all.size(), 10)
		for pair in all:
			assert_false(str(pair[1]).contains("UI_"), "%s: chiave a vista «%s» in %s" % [pair[0], pair[1], loc])
	Settings.set_value("locale", "it")
	scr._mark_dirty()
	var it_all := str((scr._tabs_bar.buttons[""] as Button).text)
	Settings.set_value("locale", "en")
	scr._mark_dirty()
	assert_ne(str((scr._tabs_bar.buttons[""] as Button).text), it_all, "«Tutto» cambia lingua")


func test_i_nomi_delle_schede_non_si_traducono() -> void:
	var r: Array = await _open()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	var t := b.create_tab("UI_BANK_TITLE")            # una chiave vera usata come nome: deve restare scritta così
	var t2 := b.create_tab("Città 💎")
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		scr._mark_dirty()
		await wait_process_frames(1)
		var btn: Button = scr._tabs_bar.buttons[t]
		assert_eq(btn.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED)
		assert_true(btn.text.begins_with("UI_BANK_TITLE "), "nome dell'utente mai tradotto (%s)" % loc)
		assert_true((scr._tabs_bar.buttons[t2] as Button).text.begins_with("Città 💎"))
	assert_eq(scr._tabs_bar.find_children("*", "RichTextLabel", true, false).size(), 0, "mai RichTextLabel/BBCode per i nomi")
	var pm: PopupMenu = scr.open_move_menu([BankSystem.tab_key("log_pine", "")], Vector2.ZERO)
	assert_eq(pm.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED, "il menù «Sposta in…» mostra i nomi come sono")
	assert_eq(pm.get_item_text(0), "UI_BANK_TITLE")
	pm.hide()


func test_nome_predefinito_e_finestra_bilingue() -> void:
	var r: Array = await _open()
	var b: BankSystem = r[0]
	var scr: Control = r[1]
	Settings.set_value("locale", "it")
	var dlg: BankTabDialog = scr.open_create_tab([BankSystem.tab_key("log_pine", "")])
	assert_eq(dlg.name_edit.text, Loc.tf("UI_BANKG_TAB_DEFAULT_N", {"n": 1}), "«Scheda 1»")
	assert_eq(dlg.name_edit.max_length, b.tab_name_max(), "limite di caratteri dai dati")
	assert_eq(dlg.icon_def, "log_pine", "icona = il primo oggetto spostato")
	dlg.name_edit.text = "   "
	dlg._validate()
	assert_true(dlg.get_ok_button().disabled, "nome vuoto: Crea spento")
	dlg.name_edit.text = "Legna"
	dlg._validate()
	dlg.confirmed.emit()
	assert_eq(b.tab_count(), 1)
	assert_eq(str(b.tabs()[0].name), "Legna")
	assert_eq(b.tab_of(BankSystem.tab_key("log_pine", "")), str(b.tabs()[0].id), "la voce spostata è entrata nella scheda nuova")
	assert_eq(scr.current_tab(), str(b.tabs()[0].id), "la scheda nuova si apre")
