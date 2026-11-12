extends SceneTree
## Catture del feedback EQUIP-UI (Deposito con marcatore «E», Eroe a slot disegnati, blocco Cibo del Combattimento).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_equip.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_equip"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_equip_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
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
	data.skills["hero"] = {"xp": 0.0, "level": 25, "record_level": 25, "stars": 0, "perks": {}, "unlocked": true}
	for t in ["feature:combat", "feature:market", "zone:saltreach", "skill:hero", "skill:cooking", "skill:smithing"]:
		(data.unlocks as Array).append(t)
	var bank: Object = game.call("system", "bank")
	var combat: Object = game.call("system", "combat")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	# Deposito: due Manopole di Rame identiche, una indossata
	var g1: String = bank.call("add_instance", {"def": "plate_gloves_copper", "quality": "normal"})
	var g2: String = bank.call("add_instance", {"def": "plate_gloves_copper", "quality": "normal"})
	var helm: String = bank.call("add_instance", {"def": "plate_helm_copper", "quality": "fine"})
	var helm2: String = bank.call("add_instance", {"def": "plate_helm_copper", "quality": "normal"})
	var body: String = bank.call("add_instance", {"def": "plate_body_copper", "quality": "normal"})
	var legs: String = bank.call("add_instance", {"def": "plate_legs_copper", "quality": "normal"})
	var sword: String = bank.call("add_instance", {"def": "sword_copper", "quality": "excellent"})
	bank.call("add_instance", {"def": "greatsword_copper", "quality": "normal"})
	bank.call("add_instance", {"def": "shield_copper", "quality": "normal"})
	bank.call("add_instance", {"def": "axe_copper", "quality": "normal"})
	for d in ["food_bleak", "food_carp"]:
		bank.call("add", d, 14, "capture")
	bank.call("add_gold", 2000)
	combat.call("equip", g1)
	combat.call("equip", helm)
	combat.call("equip", sword)
	main.call("show_screen", "bank")
	await _calm(main)
	await _shot("deposito")
	var scr: Node = main.call("current_screen")
	scr.set("_selected", g1)
	scr.call("_mark_dirty")
	await _shot("deposito_dettaglio_indossato")
	scr.set("_selected", g2)
	scr.call("_mark_dirty")
	await _shot("deposito_dettaglio_non_indossato")
	scr.set("_sort", "worn")
	scr.call("_mark_dirty")
	(scr.get("_worn_chk") as CheckBox).button_pressed = true
	await _shot("deposito_solo_indossati")
	# Eroe
	main.call("show_screen", "hero")
	await _calm(main)
	await _shot("eroe_paperdoll")
	var hs: Node = main.call("current_screen")
	var doll: Node = hs.get("_doll")
	doll.call("_select_slot", "gloves")
	await _shot("eroe_slot_manopole")
	doll.call("_select_slot", "helm")
	var items: Array = doll.get("_entries")
	if items.size() > 0:
		doll.set("picked_key", str(items[0].key))
		doll.call("refresh", true)
	await _shot("eroe_slot_elmo_scelto")
	doll.call("_select_slot", "ring")
	await _shot("eroe_slot_anello_vuoto")
	var sc := hs.get_child(0) as ScrollContainer
	sc.scroll_vertical = 700
	await _shot("eroe_cibo_e_resto")
	sc.scroll_vertical = 0
	# Combattimento: nessun cibo assegnato (con cibo nel Deposito), poi assegnato, poi senza cibo
	main.call("show_screen", "combat")
	await _calm(main)
	await _shot("combattimento_cibo_da_assegnare")
	if OS.get_environment("NOPANEL") == "1":
		main.call("current_screen").get("_food_panel").visible = false
		await _shot("combattimento_senza_pannello")
	var csc := main.call("current_screen").get_parent() as ScrollContainer
	if csc != null:
		csc.scroll_vertical = 300
		await _shot("combattimento_scorrimento")
		csc.scroll_vertical = 0
	combat.call("set_food", 0, "food_bleak")
	combat.call("set_food", 1, "food_carp")
	await _frames(3)
	var cs: Node = main.call("current_screen")
	cs.call("refresh")
	await _shot("combattimento_cibo_assegnato")
	bank.call("remove", "food_bleak", 14)
	bank.call("remove", "food_carp", 14)
	cs.get("_food_panel").call("refresh", true)
	await _shot("combattimento_senza_cibo")
	quit(0)
