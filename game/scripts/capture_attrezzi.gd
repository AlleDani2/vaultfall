extends SceneTree
## Catture del feedback ATTREZZI (Deposito pieno di Grimaldelli, costruzioni «una per volta», «A cosa serve»).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_attrezzi.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_attrezzi"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_attrezzi_saves")
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
	for t in ["feature:market", "skill:thievery", "skill:keysmithing", "skill:smithing", "skill:woodcutting"]:
		(data.unlocks as Array).append(t)
	data.skills["keysmithing"] = {"xp": 0.0, "level": 20, "record_level": 20, "stars": 0, "perks": {}, "unlocked": true}
	var bank: Object = game.call("system", "bank")
	var skills: Object = game.call("system", "skills")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	# PRIMA: lo scenario del giocatore, 50 Grimaldelli di Rame uguali nel Deposito (nel gioco di prima: una riga ciascuno)
	var first := ""
	for i in 50:
		var u: String = bank.call("add_instance", {"def": "lockpick_copper", "quality": "normal"})
		if first == "":
			first = u
	for d in ["axe_copper", "pickaxe_copper", "rod_pine"]:
		bank.call("add_instance", {"def": d, "quality": "normal"})
	bank.call("add_instance", {"def": "plate_helm_copper", "quality": "normal"})
	bank.call("add_instance", {"def": "plate_helm_copper", "quality": "normal"})
	bank.call("add", "bar_copper", 200, "capture")
	bank.call("add", "food_bleak", 12, "capture")
	var combat: Object = game.call("system", "combat")
	combat.call("equip_tool", first)
	main.call("show_screen", "bank")
	await _calm(main)
	var scr: Node = main.call("current_screen")
	await _shot("1_prima_deposito_pieno")
	scr.set("_selected", first)
	scr.call("_mark_dirty")
	await _shot("2_dettaglio_attrezzo_in_uso")
	# un doppione: vendita rapida disponibile
	var other := ""
	for inst in bank.call("list_instances"):
		if str(inst.def) == "lockpick_copper" and str(inst.uid) != first:
			other = str(inst.uid)
			break
	scr.set("_selected", other)
	scr.call("_mark_dirty")
	await _shot("3_dettaglio_doppione")
	# DOPO: un clic su «Vendi i doppioni»
	_press(scr, "DupesButton")
	scr.set("_selected", first)
	scr.call("_mark_dirty")
	await _shot("4_dopo_vendi_i_doppioni")
	# banner di Deposito quasi pieno
	var cap: int = bank.call("capacity")
	var i := 0
	while not bool(bank.call("nearly_full")) and i < cap:
		bank.call("add_instance", {"def": "sword_copper", "quality": "normal"})
		bank.call("add_instance", {"def": "greatsword_copper", "quality": "normal"})
		i += 2
	scr.call("_mark_dirty")
	await _shot("5_quasi_pieno")
	# Mansione: «Una per volta»
	main.call("show_screen", "skill:keysmithing")
	await _calm(main)
	await _shot("6_forgiachiavi_una_per_volta")
	skills.call("start", "key_lockpick_copper")
	await _frames(2)
	for k in 200:
		(game.call("system", "skills") as Object).call("tick", 0.1)
	await _shot("7_costruzione_completata")
	print("FINE")
	quit()
