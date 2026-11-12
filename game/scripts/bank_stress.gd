extends SceneTree
## Giro di layout del Deposito in stato di stress (resoconto 123): 5 valute, 90% pieno, Carro con pezzi, pezzi indossati,
## finestra «Espandi Deposito». Per ogni risoluzione: controlli fuori finestra (LayoutChecker), larghezze insufficienti
## (controllo più stretto del proprio minimo = testo tagliato), scorrimento orizzontale, finestra Espandi dentro l'area.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 \
##     -s res://scripts/bank_stress.gd -- <1280x720,...> <scala> <it|en> <both|nearly|full|empty> [shot:<cartella>] [nocurr] [expand] [view:grid|list] [dens:auto|comfortable|compact]

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _shot_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var sizes: PackedStringArray = (args[0] if args.size() > 0 else "1280x720").split(",")
	var scale := float(args[1]) if args.size() > 1 else 1.0
	var loc := args[2] if args.size() > 2 else "it"
	var mode := args[3] if args.size() > 3 else "both"
	for a in args:
		if a.begins_with("shot:"):
			_shot_dir = a.substr(5)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	root.get_node("SaveService").set("save_dir", "user://bank_stress_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "locale", loc)
	for a in args:                                          # F16: vista e densità del Deposito
		if a.begins_with("view:"):
			root.get_node("Settings").call("set_value", "bank_view", a.substr(5))
		elif a.begins_with("dens:"):
			root.get_node("Settings").call("set_value", "bank_density", a.substr(5))
	root.content_scale_factor = scale
	_run.call_deferred(sizes, scale, loc, mode, args.has("expand"))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run(sizes: PackedStringArray, scale: float, loc: String, mode: String, expand: bool) -> void:
	var game: Node = root.get_node("Game")
	game.call("new_game", 1, "normal", 20261024)
	(load("res://scripts/BankStress.gd") as GDScript).call("prepare", game, mode)      # caricato qui: gli autoload esistono solo a scena avviata
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	for k in 6:
		_press(main, "WelcomeGo")
		_press(main, "TutorialOk")
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
		main.call("show_screen", "bank")
		await _frames(4)
		main.call("_on_ui_tick")
		await _frames(3)
		if mode != "empty":                                 # un pezzo indossato scelto: il dettaglio più lungo (stato, confronto, pulsanti)
			for e in (main.call("current_screen").get("_entries") as Array):
				if str(e.worn) != "" and str(e.uid) != "":
					main.call("current_screen").set("_selected", e.key)
					main.call("current_screen").call("_mark_dirty")
					break
			await _frames(3)
		var tc: Node = root.find_child("Toasts", true, false)
		if tc != null:
			for c in tc.get_children():
				c.free()
		var view := root.get_visible_rect()
		var bad := LayoutChecker.scan(main, view)
		var scr := main.call("current_screen") as Control
		if mode == "both" and scr.get("_full_row") != null:
			(scr.get("_full_row") as Control).visible = true            # avviso 90% e Carro insieme (nel gioco si escludono: il peggiore dei due)
			await _frames(3)
			bad = LayoutChecker.scan(main, view)
		var narrow := _narrow(scr)
		var lines := PackedStringArray()
		for w in LayoutChecker.wide_scrolls(main):
			lines.append("LARGO%s %s: contenuto %d su %d" % ["(TAGLIATO)" if w.hidden else "", w.name, w.content, w.page])
		var ss := main.get("_screen_scroll") as ScrollContainer
		if ss != null and ss.get_h_scroll_bar().visible and ss.get_h_scroll_bar().max_value > ss.get_h_scroll_bar().page + 1.0:
			lines.append("HSCROLL: contenuto %d px su %d" % [int(ss.get_h_scroll_bar().max_value), int(ss.get_h_scroll_bar().page)])
		var n_bad := bad.size() + narrow.size()
		print("=== %s scala=%s %s %s area %dx%d  → %s (%d fuori, %d stretti)" % [sz, str(scale), loc, mode, int(view.size.x), int(view.size.y),
			"OK " if n_bad == 0 and lines.is_empty() else "XX ", bad.size(), narrow.size()])
		for l in LayoutChecker.worst(bad, 8):
			print(l)
		for l in narrow.slice(0, 8):
			print("    STRETTO ", l)
		for l in lines:
			print("    ", l)
		total += n_bad + lines.size()
		if _shot_dir != "":
			root.get_texture().get_image().save_png("%s/deposito_%s_%s_%s_x%s_%s.png" % [_shot_dir, mode, sz, loc, str(scale).replace(".", ""),
				str(root.get_node("Settings").call("get_value", "bank_view")) + str(root.get_node("Settings").call("get_value", "bank_density"))])
		if expand:
			scr.call("open_expand")
			await _frames(6)
			var dlg: Window = null
			for c in scr.get_children():
				if c is Window and c.get_script() != null and str((c.get_script() as Script).get_global_name()) == "BankExpandDialog":
					dlg = c
			if dlg != null:
				var r := Rect2(Vector2(dlg.position), Vector2(dlg.size))
				var ok := view.grow(1.0).encloses(r) and dlg.size.x >= dlg.get_contents_minimum_size().x
				var inner := LayoutChecker.scan(dlg, Rect2(Vector2.ZERO, Vector2(dlg.size)))
				print("    Espandi: %s rect=%s area=%s interni fuori=%d" % ["OK" if ok and inner.is_empty() else "XX", str(r), str(view), inner.size()])
				for l in LayoutChecker.worst(inner, 4):
					print(l)
				if not (ok and inner.is_empty()):
					total += 1
				if _shot_dir != "":
					root.get_texture().get_image().save_png("%s/espandi_%s_%s_x%s.png" % [_shot_dir, sz, loc, str(scale).replace(".", "")])
				dlg.hide()
				dlg.queue_free()
				await _frames(2)
	print("TOTALE_PROBLEMI ", total)
	quit(0)


## Controlli visibili del Deposito più stretti del proprio minimo (testo tagliato o schiacciato): [percorso larghezza/minimo].
func _narrow(scr: Control) -> PackedStringArray:
	var out := PackedStringArray()
	if scr == null:
		return out
	var stack: Array[Node] = [scr]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var c := n as Control
		if c != null:
			if not c.visible:
				continue
			if c.get_script() != null and ["VirtualList", "VirtualGrid", "ItemCell"].has(str((c.get_script() as Script).get_global_name())):
				continue
			if (c is Button or c is Label or c is LineEdit or c is OptionButton) and c.size.x > 0:
				var m := c.get_combined_minimum_size().x
				if c.size.x + 0.5 < m:
					out.append("%s %s «%s» %d/%d" % [c.get_class(), c.name, str(c.get("text")).left(24), int(c.size.x), int(m)])
		for k in n.get_children():
			if not (k is Window):
				stack.append(k)
	return out


func _press(main: Node, name: String) -> void:
	var b := main.find_child(name, true, false) as Button
	if b != null and b.is_visible_in_tree():
		b.pressed.emit()
