extends SceneTree
## Giro di verifica dell'interfaccia a più dimensioni di finestra (QA overflow, resoconto 107).
##   <godot> --path game --rendering-driver opengl3 [--headless] -s res://scripts/layout_audit.gd -- <1024x600,1280x720,...> [scala_ui] [schermate,...|all] [shot:<cartella>]
## Per ogni risoluzione e schermata registrata stampa i controlli che escono dalla finestra (LayoutChecker).
## Usa il salvataggio di capture_qa_b (user://qa_b_saves) se c'è, altrimenti una partita nuova con tutto sbloccato.
## Con `shot:<cartella>` salva anche una cattura per schermata (serve un display, p.es. xvfb).

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _shot_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var sizes: PackedStringArray = (args[0] if args.size() > 0 else "1280x720").split(",")
	var scale := float(args[1]) if args.size() > 1 else 1.0
	var only: PackedStringArray = []
	if args.size() > 2 and args[2] != "all":
		only = args[2].split(",")
	if args.size() > 3 and args[3].begins_with("shot:"):
		_shot_dir = args[3].substr(5)
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	root.get_node("SaveService").set("save_dir", "user://qa_b_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.content_scale_factor = scale      # diretta: la Impostazione è limitata a 1,25, qui si può stressare oltre
	_run.call_deferred(sizes, only, scale)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run(sizes: PackedStringArray, only: PackedStringArray, scale: float) -> void:
	var game: Node = root.get_node("Game")
	if FileAccess.file_exists("user://qa_b_saves/slot_1.sav"):
		game.call("load_game", 1)
	else:
		game.call("new_game", 1, "normal", 20261023)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	root.get_node("Settings").call("set_value", "tutorials", false)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	for k in 6:
		_press(main, "WelcomeGo")
		_press(main, "TutorialOk")
		_press(main, "WbCollect")
		await _frames(1)
	main.call("build_menu")
	var total := 0
	for sz in sizes:
		var wh := sz.split("x")
		var win := Vector2i(int(wh[0]), int(wh[1]))
		root.content_scale_factor = scale
		DisplayServer.window_set_size(win)
		root.size = win
		await _frames(4)
		if OS.get_cmdline_user_args().has("drawer") and main.call("is_narrow") and not main.call("drawer_open"):
			main.call("toggle_column")       # prova con il cassetto aperto
			await _frames(2)
		var view := root.get_visible_rect()
		print("=== %s scala_ui=%s  area logica %dx%d  MainScreen %s" % [sz, str(scale), int(view.size.x), int(view.size.y), str(main.size)])
		for e in ScreenRegistry.entries():
			var sid := str(e.id)
			if not only.is_empty() and not only.has(sid):
				continue
			if str(e.get("scene", "")) == "":
				continue
			if not main.call("show_screen", sid, e.get("params", {})):
				continue
			await _frames(4)
			main.call("_on_ui_tick")
			await _frames(2)
			var bad := LayoutChecker.scan(main, view)
			total += bad.size()
			for w in LayoutChecker.wide_scrolls(main):
				print("LARGO%s %s: %s contenuto %d su %d" % ["(TAGLIATO)" if w.hidden else "", sid, w.name, w.content, w.page])
			var ss := main.get("_screen_scroll") as ScrollContainer
			if ss != null:
				var cur := main.call("current_screen") as Control
				var hb := ss.get_h_scroll_bar()
				if hb.visible and hb.max_value > hb.page + 1.0:
					print("HSCROLL %s: contenuto %d px su %d disponibili (serve scorrimento orizzontale)" % [sid, int(hb.max_value), int(hb.page)])
				if cur != null and ss.get_v_scroll_bar().visible:
					print("VSCROLL %s: contenuto alto %d su %d" % [sid, int(ss.get_v_scroll_bar().max_value), int(ss.get_v_scroll_bar().page)])
			print("%s %s: %d fuori" % ["OK " if bad.is_empty() else "XX ", sid, bad.size()])
			for l in LayoutChecker.worst(bad, 5):
				print(l)
			if _shot_dir != "":
				var img := root.get_texture().get_image()
				img.save_png("%s/%s_%s.png" % [_shot_dir, sid.replace(":", "_"), sz])
	print("TOTALE_FUORI ", total)
	quit(0)


func _press(main: Node, name: String) -> void:
	var b := main.find_child(name, true, false) as Button
	if b != null and b.is_visible_in_tree():
		b.pressed.emit()
