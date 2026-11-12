extends SceneTree
## Catture della scena di apertura delle casse (Sala dei Caveau): sala, cassa che trema, rullo, carta-risultato, ×10.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1600x900 \
##     -s res://scripts/capture_rullo_b.gd -- <cartella> <it|en> [larghezza altezza]
## Gli effetti restano accesi (niente «riduci animazioni»): si vede la scena vera. Il risultato è estratto PRIMA (docs/24).

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://rullo_b"
var _tag := "it"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://rullo_b_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "reduce_motion", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		_tag = args[1]
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s_%dx%d.png" % [_out, name, _tag, img.get_width(), img.get_height()]
	img.save_png(path)
	print("CATTURA ", path)


func _press(main: Node, node_name: String) -> bool:
	var b := main.find_child(node_name, true, false) as Button
	if b != null and b.is_visible_in_tree() and not b.disabled:
		b.pressed.emit()
		return true
	return false


func _tour() -> void:
	var game: Node = root.get_node("Game")
	game.call("new_game", 1, "normal", 20261023)
	var un: Object = game.call("system", "unlock")
	for t in ["feature:crates", "feature:wardrobe", "feature:tradeup", "feature:refinery", "feature:collectors_challenge", "feature:market"]:
		un.call("grant", t)
	var bank: Object = game.call("system", "bank")
	bank.call("add", "gold", 5000000, "qa")
	for k in ["key_t1", "key_t2", "key_t3"]:
		bank.call("add", k, 30, "qa")
	var n := 0
	for it in root.get_node("DataRegistry").call("items_by_category", "crate"):
		n += 1
		bank.call("add", str(it.id), 12 + n, "qa")
		if n >= 6:
			break
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	for k in 6:
		_press(main, "WelcomeGo")
		_press(main, "TutorialOk")
		await _frames(1)
	var args := OS.get_cmdline_user_args()
	if args.size() > 3:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(args[2]), int(args[3]))
		root.position = Vector2i(0, 0)
		await _frames(20)
	main.call("build_menu")
	main.call("show_screen", "vault_hall")
	await _frames(10)
	for t in root.find_children("*", "Control", true, false):
		var sc = t.get_script()
		if sc != null and str(sc.resource_path).ends_with("FxBanner.gd"):
			t.visible = false
	await _shot("a_sala")
	var scr: Node = main.get("_host").get_child(main.get("_host").get_child_count() - 1)
	_press(main, "OpenButton")
	await create_timer(0.25).timeout
	await _shot("b_cassa")
	await create_timer(1.6).timeout
	await _shot("c_rullo")
	await create_timer(5.0).timeout
	await _shot("d_risultato")
	scr.call("_on_close_panel")
	await _frames(5)
	scr.call("_do_open", 10)
	await create_timer(4.0).timeout
	await _shot("e_x10")
	quit(0)
