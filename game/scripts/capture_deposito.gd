extends SceneTree
## Catture del feedback DEPOSITO («c'è un modo per aumentare la capacità?», resoconto 114): Deposito quasi pieno prima/dopo,
## finestra «Espandi Deposito» senza oro e con oro, dopo l'acquisto, riepilogo delle fonti.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_deposito.gd -- <cartella> [it|en]
## Gira anche sul codice di PRIMA (senza pulsante): salta i passi che non esistono. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_deposito"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_deposito_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name)


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()


func _calm(main: Node) -> void:
	for k in 60:
		if main.find_child("TutorialOk", true, false) == null and main.find_child("WelcomeGo", true, false) == null:
			break
		_press(main, "WelcomeGo")
		_press(main, "TutorialOk")
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 5)
	var data: Dictionary = root.get_node("GameState").get("data")
	for t in ["feature:market", "skill:smithing", "skill:woodcutting", "skill:mining", "chapter:1"]:
		(data.unlocks as Array).append(t)
	var bank: Object = game.call("system", "bank")
	var reg: Object = root.get_node("DataRegistry")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	# lo scenario del giocatore: materiali di vari tier, un po' di equipaggiamento, Deposito oltre il 90%
	var cap: int = bank.call("capacity")
	var mats: Array = reg.call("items_by_category", "material")
	var i := 0
	while int(bank.call("used_slots")) < int(cap * 0.93) and i < mats.size():
		bank.call("add", str(mats[i].id), 1 + (i * 37) % 400, "capture")
		i += 1
	bank.call("add", "food_bleak", 12, "capture")
	main.call("show_screen", "bank")
	await _calm(main)
	var scr: Node = main.call("current_screen")
	await _shot("1_deposito_quasi_pieno")
	if scr.has_method("open_expand"):
		bank.call("spend_gold", int(bank.call("gold")))
		scr.call("open_expand")
		await _shot("2_espandi_senza_oro")
		for d in scr.get_children():
			if d is AcceptDialog:
				d.queue_free()
		await _frames(3)
		bank.call("add_gold", 5000)
		scr.call("open_expand")
		await _shot("3_espandi_con_oro")
		var dlg: Node = null
		for d in scr.get_children():
			if d is AcceptDialog:
				dlg = d
		var b5 := dlg.find_child("Buy5", true, false) as Button
		if b5 != null:
			b5.pressed.emit()
		await _shot("4_dopo_acquisto_5_spazi")
		dlg.queue_free()
		await _frames(3)
		await _shot("5_deposito_dopo")
	print("FINE")
	quit()
