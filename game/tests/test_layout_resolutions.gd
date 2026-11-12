extends GutTest
## QA overflow (resoconto 107): l'interfaccia non esce mai dalla finestra, a qualsiasi dimensione/proporzione e scala.
## Per ogni risoluzione e per OGNI schermata registrata, nessun Control visibile ha il rettangolo globale fuori dall'area
## logica (esclusi i contenuti dentro uno ScrollContainer / controllo che ritaglia). Elenca i trasgressori.
## Il giro completo (10 dimensioni x 3 scale, 4:3, 21:9) e le catture: `scripts/layout_audit.gd` (qui solo 3 casi: ogni caso costa ~40 s).

## [dimensione finestra, scala interfaccia]
const CASES := [
	[Vector2i(1280, 720), 1.0], [Vector2i(1280, 720), 1.25], [Vector2i(1920, 800), 1.0],
]

## F5: finestre con la scala automatica accesa (dimensione 100%): l'area logica la decide UiScale.
## Scala a gradini (revisione grafica 1.0): [finestra, larghezza logica attesa, altezza logica attesa, banda attesa].
const AUTO_CASES := [
	[Vector2i(1600, 900), 1600.0, 900.0, "wide"], [Vector2i(1920, 1080), 1280.0, 720.0, "normal"],
	[Vector2i(2560, 1440), 1280.0, 720.0, "normal"], [Vector2i(3840, 2160), 1280.0, 720.0, "normal"],
	[Vector2i(1280, 800), 1280.0, 800.0, "normal"],
]

var _old_auto: bool
var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_fps: int


func before_all() -> void:
	_old_fps = Engine.max_fps
	Engine.max_fps = 0                    # i fotogrammi d'attesa non devono aspettare i 60 fps
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor


func after_all() -> void:
	Engine.max_fps = _old_fps


func before_each() -> void:
	_old_auto = bool(Settings.get_value("ui_scale_auto"))
	Settings._values["ui_scale_auto"] = false          # i casi CASES fissano il fattore a mano: la scala automatica non deve sovrascriverlo
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_layout_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Settings._values["ui_scale_auto"] = _old_auto
	_set_window(_old_size)
	get_tree().root.content_scale_factor = _old_scale
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _set_window(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	get_tree().root.size = sz


func _main() -> Control:
	Game.new_game(1, "normal", 4242)
	var un: Object = Game.system("unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.grant(tok)
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


func test_nessuna_schermata_esce_dalla_finestra() -> void:
	var main: Control = await _main()
	var report := PackedStringArray()
	var total := 0
	for c in CASES:
		var sz: Vector2i = c[0]
		get_tree().root.content_scale_factor = float(c[1])
		_set_window(sz)
		await wait_process_frames(3)
		var view := get_tree().root.get_visible_rect()
		for e in ScreenRegistry.entries():
			if str(e.get("scene", "")) == "":
				continue
			if not main.show_screen(str(e.id), e.get("params", {})):
				continue
			await wait_process_frames(3)
			var bad := LayoutChecker.scan(main, view)
			if not bad.is_empty():
				total += bad.size()
				report.append("%dx%d scala %s · %s: %d fuori (area %dx%d)" % [sz.x, sz.y, str(c[1]), str(e.id), bad.size(), int(view.size.x), int(view.size.y)])
				report.append_array(LayoutChecker.worst(bad, 4))
	if total > 0:
		gut.p("\n".join(report))
	assert_eq(total, 0, "controlli fuori dalla finestra (elenco sopra)")


func test_nessuna_schermata_esce_dalla_finestra_con_scala_automatica() -> void:
	var main: Control = await _main()
	Settings._values["ui_scale_auto"] = true
	Settings._values["ui_scale"] = 1.0
	var report := PackedStringArray()
	var total := 0
	for ac in AUTO_CASES:
		var sz: Vector2i = ac[0]
		_set_window(sz)
		Settings._apply_ui_scale()
		await wait_process_frames(3)
		var view := get_tree().root.get_visible_rect()
		assert_almost_eq(view.size.x, float(ac[1]), 1.0, "%s: larghezza logica" % str(sz))
		assert_almost_eq(view.size.y, float(ac[2]), 1.0, "%s: altezza logica" % str(sz))
		assert_eq(UiBands.band(view.size.x), str(ac[3]), "%s: banda" % str(sz))
		for e in ScreenRegistry.entries():
			if str(e.get("scene", "")) == "":
				continue
			if not main.show_screen(str(e.id), e.get("params", {})):
				continue
			await wait_process_frames(3)
			var bad := LayoutChecker.scan(main, view)
			if not bad.is_empty():
				total += bad.size()
				report.append("%dx%d auto · %s: %d fuori (area %dx%d)" % [sz.x, sz.y, str(e.id), bad.size(), int(view.size.x), int(view.size.y)])
				report.append_array(LayoutChecker.worst(bad, 4))
	if total > 0:
		gut.p("\n".join(report))
	assert_eq(total, 0, "controlli fuori dalla finestra con la scala automatica (elenco sopra)")


func test_area_stretta_colonna_destra_a_cassetto_e_barra_compatta() -> void:
	var main: Control = await _main()
	get_tree().root.content_scale_factor = 1.0
	_set_window(Vector2i(1280, 720))
	await wait_process_frames(3)
	assert_false(main.call("is_narrow"), "a 1280 la banda è normale")
	assert_false((main.get_node("Root/Body/RightColumn") as Control).visible, "F3: la colonna destra è un cassetto chiuso di default")
	var rail := main.get_node("Root/Body/RightRail") as Control
	assert_true(rail.visible, "il binario c'è sempre")
	assert_almost_eq(rail.size.x, 52.0, 1.0, "binario da 52 px")
	get_tree().root.content_scale_factor = 1.5       # area logica 853x480 (oltre il massimo delle Impostazioni: prova di stress)
	await wait_process_frames(3)
	assert_true(main.call("is_narrow"), "sotto 1100 px logici la banda è stretta")
	assert_true(main.call("is_compact"), "e la barra in alto passa alle etichette brevi")
	assert_true(rail.visible and rail.size.x <= 53.0, "il binario resta anche nella banda stretta")
	main.call("toggle_column")
	await wait_process_frames(2)
	var right := main.get_node("Drawer/RightColumn") as Control
	assert_true(right.visible, "il tasto L apre il cassetto sopra il contenuto")
	assert_true(main.get_viewport().get_visible_rect().encloses(right.get_global_rect().grow(-1.0)), "il cassetto sta dentro la finestra")
	assert_false(right.get_global_rect().intersects(rail.get_global_rect().grow(-1.0)), "il cassetto non copre il binario")
	assert_false(Settings.get_value("right_col_visible"), "la preferenza dell'utente non cambia")
	main.call("toggle_column")
	await wait_process_frames(2)
	assert_false(main.call("drawer_open"), "si richiude")
	get_tree().root.content_scale_factor = 1.0
	await wait_process_frames(3)
	assert_false(main.call("is_narrow"))
	assert_false((main.get_node("Root/Body/RightColumn") as Control).visible, "tornati larghi il cassetto è chiuso e RightColumn è di nuovo nel suo posto")


func test_finestra_si_adatta_allo_schermo() -> void:
	# portatile 1366x768 (area utile 1366x728): 1600x900 deve ridursi in proporzione
	var f := WindowFit.fit_size(Vector2i(1600, 900), Vector2i(1366, 728), Vector2i(0, 31))
	assert_true(f.x <= 1366 and f.y <= 728 - 31, "entra nell'area utile (%s)" % str(f))
	assert_almost_eq(float(f.x) / float(f.y), 16.0 / 9.0, 0.02, "stessa proporzione")
	assert_eq(WindowFit.fit_size(Vector2i(1280, 720), Vector2i(1920, 1040), Vector2i.ZERO), Vector2i(1280, 720), "se entra non si tocca")
	var tiny := WindowFit.fit_size(Vector2i(1600, 900), Vector2i(800, 600), Vector2i.ZERO)
	assert_true(tiny.x <= 800 and tiny.y <= 600, "mai oltre lo schermo, nemmeno sotto il minimo")
	assert_eq(WindowFit.min_for(Vector2i(1920, 1040), Vector2i.ZERO), WindowFit.MIN_SIZE)
	assert_true(WindowFit.min_for(Vector2i(800, 600), Vector2i.ZERO).x <= 800, "il minimo non supera lo schermo")


func test_rettangolo_dialogo_dentro_l_area() -> void:
	var r := WindowFit.dialog_rect(Vector2i(76, 36), Vector2i(1000, 700), Vector2i(853, 480), 30)
	assert_true(Rect2i(Vector2i.ZERO, Vector2i(853, 480)).encloses(r), "un dialogo enorme si riduce e rientra: %s" % str(r))
	assert_gte(r.position.y, 30, "la barra del titolo resta visibile")
	var ok := WindowFit.dialog_rect(Vector2i(100, 80), Vector2i(400, 300), Vector2i(1280, 720), 30)
	assert_eq(ok, Rect2i(100, 80, 400, 300), "un dialogo che entra non si tocca")
