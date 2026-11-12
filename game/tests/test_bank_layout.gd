extends GutTest
## Deposito in stato di stress (resoconto 123): 5 valute in intestazione, Deposito al 90% o pieno con il Carro, pezzo indossato scelto.
## Per ogni dimensione/scala/lingua nessun controllo esce dalla finestra e nessun pulsante/etichetta è più stretto del proprio
## minimo (testo troncato come «Sol» al posto di «Solo equipaggiati»). Il giro completo (4 risoluzioni x IT/EN x 2 scale, finestra
## Espandi, catture): `scripts/bank_stress.gd`.

## [dimensione, scala, lingua, modo]
const CASES := [
	[Vector2i(1280, 720), 1.0, "it", "nearly"],
	[Vector2i(1280, 720), 1.0, "it", "both"],
	[Vector2i(1280, 720), 1.25, "en", "both"],
	[Vector2i(1024, 600), 1.0, "en", "full"],
]

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_fps: int
var _old_locale: String


func before_all() -> void:
	_old_fps = Engine.max_fps
	Engine.max_fps = 0
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor
	_old_locale = Loc.locale()


func after_all() -> void:
	Engine.max_fps = _old_fps


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_banklayout_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	get_tree().root.content_scale_factor = _old_scale
	Settings.set_value("locale", _old_locale)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


## Controlli del Deposito più stretti del proprio minimo.
func _narrow(scr: Control) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [scr]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var c := n as Control
		if c != null:
			if not c.visible:
				continue
			if c is VirtualList:
				continue
			if (c is Button or c is Label or c is LineEdit or c is OptionButton) and c.size.x > 0 and c.size.x + 0.5 < c.get_combined_minimum_size().x:
				out.append("%s %s «%s» %d/%d" % [c.get_class(), c.name, str(c.get("text")).left(24), int(c.size.x), int(c.get_combined_minimum_size().x)])
		for k in n.get_children():
			if not (k is Window):
				stack.append(k)
	return out


func _open_bank(mode: String) -> Control:
	Game.new_game(1, "normal", 20261024)
	BankStress.prepare(Game, mode)
	Settings.set_value("tutorials", false)
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	return main


func test_deposito_stress_non_esce_dalla_finestra() -> void:
	var report := PackedStringArray()
	var total := 0
	for c in CASES:
		var sz: Vector2i = c[0]
		Settings.set_value("locale", str(c[2]))
		var mode := str(c[3])
		var main: Control = await _open_bank(mode)
		get_tree().root.content_scale_factor = float(c[1])
		DisplayServer.window_set_size(sz)
		get_tree().root.size = sz
		await wait_process_frames(3)
		assert_true(main.show_screen("bank"), "il Deposito si apre")
		await wait_process_frames(4)
		main.call("_on_ui_tick")
		var scr := main.call("current_screen") as Control
		if mode == "both":
			(scr.get("_full_row") as Control).visible = true       # avviso e Carro insieme: il caso peggiore
		for e in (scr.get("_entries") as Array):
			if str(e.worn) != "" and str(e.uid) != "":
				scr.set("_selected", e.key)                         # dettaglio di un pezzo indossato
				scr.call("_mark_dirty")
				break
		await wait_process_frames(4)
		var tc := main.find_child("Toasts", true, false) as Control
		if tc != null:
			tc.visible = false
		var view := get_tree().root.get_visible_rect()
		var bad := LayoutChecker.scan(main, view)
		var narrow := _narrow(scr)
		var wide := LayoutChecker.wide_scrolls(scr)
		var tag := "%dx%d x%s %s %s" % [sz.x, sz.y, str(c[1]), str(c[2]), mode]
		if not bad.is_empty() or not narrow.is_empty() or not wide.is_empty():
			total += bad.size() + narrow.size() + wide.size()
			report.append("%s: %d fuori, %d stretti, %d larghi" % [tag, bad.size(), narrow.size(), wide.size()])
			report.append_array(LayoutChecker.worst(bad, 4))
			for l in narrow.slice(0, 4):
				report.append("    STRETTO " + l)
		main.queue_free()
		await wait_process_frames(2)
		Game.stop_game(false)
	if total > 0:
		gut.p("\n".join(report))
	assert_eq(total, 0, "controlli fuori finestra o troncati (elenco sopra)")


func test_righe_a_capo_e_nomi_stabili() -> void:
	Settings.set_value("locale", "it")
	var main: Control = await _open_bank("nearly")
	assert_true(main.show_screen("bank"))
	await wait_process_frames(4)
	var scr := main.call("current_screen") as Control
	assert_null(scr.find_child("CurrencyFlow", true, false), "F12: le valute stanno nella barra alta, non nel Deposito")
	assert_null(scr.find_child("GroupFlow", true, false), "rapporto 08: le categorie non sono più una riga di pulsanti")
	assert_true(scr.find_child("CategoryMenu", true, false) is MenuButton, "le categorie sono un menù nella barra compatta")
	assert_true(scr.find_child("ToolsFlow", true, false) is HFlowContainer, "ricerca, ordinamento e azioni vanno a capo")
	assert_true(scr.find_child("HeadFlow", true, false) is HFlowContainer, "spazi, Espandi e valore vanno a capo")
	assert_true(scr.find_child("SellMenu", true, false) is MenuButton, "«Vendita ▾» contiene «Vendi i doppioni»")
	assert_true(scr.find_child("FiltersMenu", true, false) is MenuButton, "«Filtri ▾»")
	assert_not_null(scr.find_child("ExpandButton", true, false))
	assert_not_null(scr.find_child("ExpandBannerButton", true, false))
