extends SceneTree
## Catture della scheda Eroe (feedback giocatore: cibo, soglia, pozione, Glifi). Stato del giocatore: tre slot con lo stesso cibo, soglia 2%.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_hero.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_hero"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_hero_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var code := OS.execute("import", ["-window", "root", abs_path])
	if code != 0:
		root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name, " codice ", code)


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
	data.skills["hero"] = {"xp": 0.0, "level": 12, "record_level": 12, "stars": 0, "perks": {}, "unlocked": true}
	for t in ["feature:combat", "skill:hero", "zone:millbrook", "skill:cooking"]:
		(data.unlocks as Array).append(t)
	var bank: Object = game.call("system", "bank")
	var combat: Object = game.call("system", "combat")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	for d in ["food_bleak"]:
		bank.call("remove", d, int(bank.call("count", d)))
		bank.call("add", d, 51, "capture")
	for i in 3:
		(combat.get("state").food as Array)[i] = "food_bleak"
	combat.call("set_eat_pct", int(OS.get_environment("EATPCT")) if OS.get_environment("EATPCT") != "" else 2)
	main.call("show_screen", "hero")
	await _calm(main)
	var hs: Node = main.call("current_screen")
	var sc := hs.get_child(0) as ScrollContainer
	await _shot("eroe_in_alto")
	sc.scroll_vertical = 500
	await _shot("eroe_meta")
	sc.scroll_vertical = 1000
	await _shot("eroe_cibo")
	sc.scroll_vertical = 1600
	await _shot("eroe_fondo")
	quit(0)
