extends SceneTree
## Giro fotografico QA-UX gruppo A (menù iniziale, layout, Riepilogo, Mansione, Giardino, Deposito, Missioni,
## Bentornato, Benvenuto, Manuale, Impostazioni, tutorial) in stati realistici (bot fino a metà Cap. I).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_ux_a.gd -- <cartella> [it|en] [fino_a_missione]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const START := "res://src/ui/start/StartScreen.tscn"
const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_ux_a"
var _n := 0
var _until := "main_c1_q5"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_ux_a_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 2:
		_until = args[2]
	if args.size() > 3 and args[3] == "frac":
		root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	# pixel reali della finestra (ImageMagick `import` su Xvfb): la texture del viewport resta alla risoluzione di base
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var code := OS.execute("import", ["-window", "root", abs_path])
	if code != 0:
		root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name, " codice ", code)


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var settings: Node = root.get_node("Settings")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("menu_iniziale")
	start.call("show_slots")
	await _shot("slot_vuoti")
	start.call("start_new", 1)
	await _frames(2)
	start.queue_free()
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	print("DIM main=", main.size, " root=", root.size, " vis=", root.get_visible_rect(), " win=", DisplayServer.window_get_size(), " fac=", root.content_scale_factor, " mode=", root.content_scale_mode, " aspect=", root.content_scale_aspect, " smode=", root.content_scale_stretch)
	await _shot("benvenuto")
	_press(main, "WelcomeGo")
	await _shot("tutorial")
	_press(main, "TutorialOk")
	await _frames(3)
	await _shot("riepilogo_inizio")
	main.call("show_screen", "skill:woodcutting")
	await _shot("mansione_ferma")
	main.call("show_screen", "bank")
	await _shot("deposito_vuoto")
	main.call("show_screen", "quests")
	await _shot("missioni_inizio")
	# gioco: mansione in corso, poi il bot fino a metà Cap. I (senza animazioni durante la simulazione veloce)
	main.call("show_screen", "skill:woodcutting")
	var sk: Object = game.call("system", "skills")
	sk.call("start", "wc_pine")
	settings.call("set_value", "reduce_motion", true)
	for i in 300:
		game.call("_on_step", 0.1)
	main.call("_on_ui_tick")
	await _shot("mansione_in_corso")
	var bot = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	var r: Dictionary = bot.call("run_until_quest", _until, 7200.0)
	print("BOT ", r.get("ok"), " t=", r.get("t"))
	settings.call("set_value", "reduce_motion", false)
	main.call("build_menu")
	await _calm(main)
	main.call("show_screen", "summary")
	await _shot("riepilogo")
	main.call("show_screen", "skill:woodcutting")
	sk.call("start", "wc_pine")
	game.call("_on_step", 1.0)
	await _calm(main)
	main.call("_on_ui_tick")
	await _shot("mansione_attiva")
	var bank_sys: Object = game.call("system", "bank")
	bank_sys.call("add_gold", 30000)
	game.call("system", "market").call("buy", "action_queue_1")
	var qs: Object = game.call("system", "queue")
	qs.call("add", "wc_pine", "qty", 25)
	qs.call("add", "wc_pine", "level", 9)
	await _frames(12)
	main.call("show_screen", "skill:woodcutting")
	_open_extras(main)
	await _shot("mansione_coda")
	main.call("show_screen", "skill:cooking")
	await _shot("mansione_cucina")
	main.call("show_screen", "skill:farming")
	await _shot("giardino")
	main.call("show_screen", "bank")
	await _shot("deposito")
	_click_first_item(main)
	await _shot("deposito_dettaglio")
	main.call("show_screen", "quests")
	await _shot("missioni")
	main.call("show_screen", "manual")
	await _shot("manuale")
	for pg in ["formulas", "crates", "unlocks", "glossary"]:
		main.call("current_screen").call("show_page", pg)
		await _shot("manuale_" + pg)
	main.call("show_screen", "settings")
	await _shot("impostazioni")
	# Deposito pieno: ogni oggetto dei dati una volta, finché i posti finiscono
	var bk: Object = game.call("system", "bank")
	for it in root.get_node("DataRegistry").call("all_items").values():
		if int(bk.call("used_slots")) >= int(bk.call("capacity")):
			break
		bk.call("add", str(it.id), 3, "capture")
	main.call("show_screen", "bank")
	await _calm(main)
	await _shot("deposito_pieno")
	main.call("show_screen", "skill:woodcutting")
	game.call("system", "skills").call("start", "wc_pine")
	game.call("_on_step", 3.5)
	await _shot("mansione_deposito_pieno")
	main.call("show_screen", "summary")
	game.call("_on_long_gap", 7200.0)
	await _shot("bentornato")
	_press(main, "WbCollect")
	await _calm(main)
	# menù iniziale con una partita salvata
	root.get_node("SaveService").call("save_now")
	await _frames(30)
	game.call("stop_game", false)
	main.queue_free()
	await _frames(2)
	var start2: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start2)
	await _shot("menu_con_partita")
	start2.call("show_slots")
	await _shot("slot_con_partita")
	quit(0)


func _open_extras(main: Node) -> void:
	for c in main.find_children("*", "Button", true, false):
		var b := c as Button
		if b.toggle_mode and b.text.ends_with(TranslationServer.translate("UI_EXTRAS_TITLE")):
			b.button_pressed = true


func _click_first_item(main: Node) -> void:
	var bank: Node = main.call("current_screen")
	var ents: Array = bank.get("_entries")
	if ents.size() > 2:
		bank.set("_selected", ents[2].key)
		bank.call("_refresh_detail")
		bank.call("_mark_dirty")


## Chiude le finestre dei tutorial in coda e toglie i messaggi a comparsa (per le catture "pulite").
func _calm(main: Node) -> void:
	for k in 60:
		if main.find_child("TutorialOk", true, false) == null:
			break
		_press(main, "TutorialOk")
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)
