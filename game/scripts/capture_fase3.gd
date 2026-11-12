extends SceneTree
## Catture della fase F3 del progetto di interfaccia (docs/ui_redesign/07, F3): binario destro, cassetto, striscia Obiettivo.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase3.gd -- <cartella> basic        (Mansione chiuso/aperto, Riepilogo, prova di Esc con un evento vero)
##   ... --resolution 1536x864 -s res://scripts/capture_fase3.gd -- <cartella> pinned     (cassetto fissato in banda larga)
## Partita nuova con seme 4242, tutto sbloccato, tutorial spenti, Taglialegna in corso. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase3"
var _mode := "basic"
var _main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mode = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase3_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	root.get_node("Settings").call("set_value", "ui_layout_rev", 2)
	root.get_node("Settings").call("set_value", "right_col_visible", false)
	root.get_node("Settings").call("set_value", "locale", "it")
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _calm() -> void:
	for k in 60:
		if _main.find_child("TutorialOk", true, false) == null and _main.find_child("WelcomeGo", true, false) == null:
			break
		var b := _main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		var t := _main.find_child("TutorialOk", true, false) as Button
		if t != null:
			t.pressed.emit()
		await _frames(2)
	await _frames(2)


func _shot(name: String) -> void:
	await _frames(12)
	await _calm()
	var path := "%s/%s.png" % [_out, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name, " finestra ", root.get_visible_rect().size)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(3)
	var r := InputEventKey.new()
	r.keycode = code
	r.physical_keycode = code
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(3)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm()
	main.call("build_menu")
	var sk: Object = game.call("system", "skills")
	sk.call("start", "wc_pine")
	for i in 5:
		game.call("_on_step", 0.1)
	for i in 6:
		main.call("add_log", "Prova del Registro numero %d: hai trovato qualcosa" % i, "loot" if i % 2 == 0 else "skills")
	if _mode == "pinned":
		root.content_scale_factor = 1280.0 / 1536.0          # area logica 1536×864 (banda larga) senza passare da UiScale (F5)
		await _frames(4)
		root.get_node("Settings").call("set_value", "right_col_visible", true)
		main.call("show_screen", "skill:woodcutting")
		await _shot("fissato_%dx%d" % [int(root.size.x), int(root.size.y)])
		quit()
		return
	main.call("show_screen", "skill:woodcutting")
	await _shot("mansione_chiuso")
	print("Larghezza del contenuto: ", (main.get_node("Root/Body/Content") as Control).size.x, " binario: ", (main.find_child("RightRail", true, false) as Control).size.x)
	await _key(KEY_L)
	print("L -> cassetto aperto: ", main.call("drawer_open"))
	await _shot("mansione_aperto")
	await _key(KEY_ESCAPE)
	print("Esc -> cassetto aperto: ", main.call("drawer_open"), " schermata ", main.get("current_id"))
	await _key(KEY_L)
	await _key(KEY_L)
	print("L, L -> cassetto aperto: ", main.call("drawer_open"))
	main.call("show_screen", "summary")
	await _shot("riepilogo")
	quit()
