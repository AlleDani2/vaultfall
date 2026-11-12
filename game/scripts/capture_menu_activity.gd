extends SceneTree
## Catture dell'evidenziazione dell'attività in corso nel menù laterale (resoconto UI 05).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_menu_activity.gd -- <cartella> [it|en]
## Gira anche sul codice di PRIMA (stesse schermate, senza evidenziazione). Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_menu_activity"
var _n := 0
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_menu_activity_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(12)
	await _calm(_main)
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
	for t in ["feature:market", "feature:combat", "feature:estate", "feature:mercenaries", "skill:smithing", "skill:woodcutting",
			"skill:mining", "skill:farming", "skill:hero", "chapter:1", "dungeon:cursed_granary", "feature:talents", "feature:crates"]:
		(data.unlocks as Array).append(t)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm(main)
	main.call("build_menu")
	await _shot("nulla_in_corso")
	var sk: Object = game.call("system", "skills")
	sk.call("start", "wc_pine")
	main.call("show_screen", "summary")
	await _frames(40)
	await _shot("mansione_in_riepilogo")
	main.call("show_screen", "skill:woodcutting")
	await _shot("mansione_aperta")
	main.call("show_screen", "bank")
	await _shot("mansione_altra_schermata")
	var combat: Object = game.call("system", "combat")
	combat.call("start", "millbrook")
	main.call("show_screen", "combat")
	await _frames(40)
	await _shot("combattimento")
	main.call("show_screen", "summary")
	await _shot("combattimento_riepilogo")
	sk.call("start", "wc_pine")
	main.call("show_screen", "skill:woodcutting")
	var farm: Object = game.call("system", "farming")
	var kind := str(root.get_node("DataRegistry").call("table", "farming_plots")[0].id)
	farm.get("state").plots[kind][0] = {"crop": "x", "remaining_s": 30.0, "total_s": 60.0, "auto": false}
	await _frames(40)
	await _shot("mansione_aperta_e_orto_parallelo")
	var fb: Control = main.get("_buttons").get("skill:farming")
	if fb != null:
		(main.get("_menu_scroll") as ScrollContainer).ensure_control_visible(fb)
		await _shot("menu_scorso_all_orto")
	main.call("show_screen", "summary")
	root.get_node("Clock").call("toggle_pause")
	await _frames(20)
	await _shot("in_pausa")
	root.get_node("Clock").call("toggle_pause")
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	await _frames(20)
	await _shot("riduci_animazioni")
	quit()
