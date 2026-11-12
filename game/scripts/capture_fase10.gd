extends SceneTree
## Catture della fase F10 del progetto di interfaccia (docs/ui_redesign/07, F10): Eroe (ogni scheda), Talenti, Prestigio.
##   xvfb-run -a -s "-screen 0 1400x900x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase10.gd -- <cartella> [it|en]
## Partita nuova con seme 4242, tutto sbloccato, tutorial spenti, Eroe di livello 60 con qualche pezzo, cibo e talenti. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase10"
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase10_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	root.get_node("Settings").call("set_value", "seen_intro", [])           # la prima visita: le frasi «a cosa serve» sono aperte
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _calm(main: Node) -> void:
	for k in 60:
		if main.find_child("TutorialOk", true, false) == null and main.find_child("WelcomeGo", true, false) == null:
			break
		var b := main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		var t := main.find_child("TutorialOk", true, false) as Button
		if t != null:
			t.pressed.emit()
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _shot(name: String) -> void:
	await _frames(12)
	await _calm(_main)
	var path := "%s/%s.png" % [_out, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name)


func _screen() -> Node:
	var host: Node = _main.get("_host")
	return host.get_child(host.get_child_count() - 1)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	var data: Dictionary = root.get_node("GameState").data
	for sk in ["hero", "woodcutting", "mining", "fishing"]:
		data.skills[sk] = {"xp": 0.0, "level": 60 if sk == "hero" else 100, "record_level": 60 if sk == "hero" else 100, "stars": 0, "perks": {}, "unlocked": true}
	var bank: Object = game.call("system", "bank")
	var combat: Object = game.call("system", "combat")
	for def in ["sword_copper", "plate_helm_copper"]:
		var uid: String = bank.call("add_instance", {"def": def, "quality": "normal"})
		combat.call("equip", uid)
	bank.call("add", "food_bleak", 30, "capture")
	combat.call("set_food", 0, "food_bleak")
	var b: Object = combat.get("build")
	for i in 60:
		var done := false
		for t in b.call("talent_nodes"):
			if b.call("rank_up", str(t.id)):
				done = true
				break
		if not done:
			break
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm(main)
	main.call("build_menu")
	await _frames(360)                                           # le «Imprese sbloccate» dell'allestimento passano
	main.call("show_screen", "hero")
	await _frames(6)
	for tab in ["equip", "abilities", "stats", "food", "glyphs"]:
		_screen().call("_set_tab", tab)
		await _shot("hero_" + tab)
	main.call("show_screen", "talents")
	await _shot("talents")
	var ps: Object = game.call("system", "prestige")
	if ps != null:
		ps.call("do_star", "woodcutting", false)
		await _frames(400)                                       # la cerimonia della Stella passa
	main.call("show_screen", "prestige")
	await _frames(4)
	_screen().call("refresh")
	await _shot("prestige_advisor")
	var pr := _screen()
	var tabs: TabContainer = pr.get("_tabs")
	if tabs != null and tabs.get_tab_count() > 2:
		tabs.current_tab = 2
		await _shot("prestige_" + str((pr.get("_tab_ids") as Array)[0]))
	print("PAGINE_ROOT ", root.get_visible_rect().size)
	quit()
