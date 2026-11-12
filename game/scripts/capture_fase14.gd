extends SceneTree
## Catture della fase F14 del progetto di interfaccia (docs/ui_redesign/07, F14): pulsante della Sabbia del Custode, stati A-E e cassetto fissato.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase14.gd -- <cartella> states       (5 stati A-E, intero + dettaglio del binario ingrandito)
##   ... --resolution 1536x864 -s res://scripts/capture_fase14.gd -- <cartella> pinned     (cassetto fissato in banda larga)
## Partita nuova con seme 4242, tutto sbloccato, tutorial spenti, Taglialegna in corso. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase14"
var _mode := "states"
var _main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mode = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase14_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", false)
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


func _crop(name: String) -> void:
	var img := root.get_texture().get_image()
	var w := img.get_width()
	var r := Rect2i(w - 90, img.get_height() - 190, 90, 190)
	var c := img.get_region(r)
	c.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)       # solo documentazione: ingrandimento per guardare il pulsante
	c.save_png("%s/%s_dettaglio.png" % [_out, name])


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
	un.call("grant", "feature:time_push")
	var tp: Object = game.call("system", "time_push")
	tp.state["gift_given"] = true
	tp.state["reserve_s"] = 400.0
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
	main.call("show_screen", "skill:woodcutting")
	var pb: Control = main.find_child("PushButton", true, false)
	if _mode == "pinned":
		root.content_scale_factor = 1280.0 / 1536.0
		await _frames(4)
		root.get_node("Settings").call("set_value", "right_col_visible", true)
		main.call("show_screen", "skill:woodcutting")
		await _shot("fissato_%dx%d" % [int(root.size.x), int(root.size.y)])
		quit()
		return
	await _shot("1_A_pronta")
	_crop("1_A_pronta")
	for i in 6:
		pb.call("click")
	pb.set("_last_click_msec", Time.get_ticks_msec() + 100000)
	pb.get("feedback").call("flush")
	await _frames(2)
	pb.set("_last_click_msec", Time.get_ticks_msec() + 100000)
	pb.call("refresh")
	await _shot("2_B_in_uso")
	pb.set("_last_click_msec", Time.get_ticks_msec() + 100000)
	pb.get("feedback").set("_show_until_msec", Time.get_ticks_msec() + 100000)
	pb.call("refresh")
	_crop("2_B_in_uso")
	pb.set("_last_click_msec", -1000000)
	pb.get("feedback").call("clear")
	tp.state["pending_s"] = 0.0
	tp.state["reserve_s"] = 0.0
	await _shot("3_C_vuota")
	_crop("3_C_vuota")
	tp.state["reserve_s"] = 400.0
	sk.call("stop")
	root.get_node("GameState").data["activity"].clear()
	await _shot("4_D_non_disponibile")
	_crop("4_D_non_disponibile")
	sk.call("start", "wc_pine")
	root.get_node("Settings").call("set_value", "push_assist", "auto")
	pb.set("_last_click_msec", -1000000)
	pb.call("refresh")
	await _shot("5_E_automatica")
	_crop("5_E_automatica")
	quit()
