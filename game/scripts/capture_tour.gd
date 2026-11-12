extends SceneTree
## Giro fotografico della prima esperienza (controllo a occhio, integrazione): menù iniziale -> slot -> nuova
## partita -> benvenuto con dedica -> tutorial -> Riepilogo -> Missioni -> Taglialegna -> Deposito -> Missioni dopo
## qualche minuto di gioco. Scrive PNG in una cartella e stampa i testi delle voci grigie del menù con il loro
## suggerimento ("Si sblocca con: ..."). Serve un display (anche virtuale):
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path game --rendering-driver opengl3 -s res://scripts/capture_tour.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const START := "res://src/ui/start/StartScreen.tscn"
const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_tour"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var save_dir := "user://capture_tour_saves"
	root.get_node("SaveService").set("save_dir", save_dir)
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	_n += 1
	var img := root.get_texture().get_image()
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	img.save_png(path)
	print("CATTURA ", path, " ", img.get_size())


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("menu_iniziale")
	start.call("show_slots")
	await _shot("slot")
	start.call("start_new", 1)
	await _frames(2)
	start.queue_free()
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _shot("benvenuto")
	var overlay: Node = main.find_child("*OverlayHost*", true, false)
	_press(main, "WelcomeGo")
	await _shot("tutorial")
	_press(main, "TutorialOk")
	await _frames(3)
	await _shot("riepilogo")
	_dump_menu(main)
	main.call("show_screen", "quests")
	await _shot("missioni")
	main.call("show_screen", "skill:woodcutting")
	await _shot("taglialegna")
	var sk: Object = game.call("system", "skills")
	sk.call("start", "wc_pine")
	for i in 600:       # 60 s simulati a passi diretti
		game.call("_on_step", 0.1)
	main.call("_on_ui_tick")
	await _shot("taglialegna_in_corso")
	main.call("show_screen", "bank")
	await _shot("deposito")
	main.call("show_screen", "manual")
	await _shot("manuale")
	if overlay != null:
		print("overlay presente")
	# qualche minuto con il bot: missioni avanzate, nuovi sblocchi, schermate che si aprono
	var bot = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	bot.call("run_until_quest", "main_c0_q4", 3600.0)
	main.call("build_menu")
	for k in 20:
		_press(main, "TutorialOk")
		await _frames(2)
	main.call("show_screen", "quests")
	await _shot("missioni_dopo_il_prologo")
	main.call("show_screen", "combat")
	await _shot("combattimento")
	main.call("show_screen", "hero")
	await _shot("eroe")
	main.call("show_screen", "vault_hall")
	await _shot("sala_dei_caveau")
	main.call("show_screen", "summary")
	await _shot("riepilogo_dopo")
	_dump_menu(main)
	# rientro dopo 2 ore: finestra "Bentornato" con le sezioni dei sistemi
	game.call("system", "skills").call("start", "wc_pine")
	game.call("_on_long_gap", 7200.0)
	await _shot("bentornato")
	quit(0)


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()


func _dump_menu(main: Node) -> void:
	var menu: Node = main.get("_menu")
	if menu == null:
		return
	print("--- MENU ---")
	for c in menu.get_children():
		if c is Button:
			var b := c as Button
			var shown: String = b.text if b.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else TranslationServer.translate(b.text)
			var tip := TranslationServer.translate(b.tooltip_text)
			print("%s %s%s" % ["[grigio]" if b.disabled else "[ok]   ", shown, ("  -> " + tip) if not tip.is_empty() else ""])
		elif c is Label:
			print("== ", TranslationServer.translate((c as Label).text))
