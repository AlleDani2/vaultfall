extends Node
## Catture della fase F8 (Combattimento: arena sempre visibile, il resto a sezioni).
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     --script res://scripts/capture_fase8.gd -- <cartella> <sicuro|rischio|corsa> [nome-file]
## Scenari: «sicuro» = zona facile con cibo assegnato, «rischio» = zona alta senza cibo, «corsa» = Corsa con una scelta in attesa
## (la sezione si apre da sola). Non tocca i salvataggi veri. Si lancia come scena: res://scripts/capture_fase8.tscn.

const MAIN := "res://src/ui/main/MainScreen.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	get_tree().root.get_node("SaveService").set("save_dir", "user://capture_fase8_saves")
	get_tree().root.get_node("SaveService").set("autosave_enabled", false)
	get_tree().root.get_node("Settings").call("set_value", "tutorials", false)
	get_tree().root.get_node("Settings").call("set_value", "reduce_motion", false)
	get_tree().root.get_node("Settings").call("set_value", "locale", "it")
	get_tree().root.get_node("Settings").call("set_value", "seen_intro", ["combat"])
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://capture_fase8"
	var mode := args[1] if args.size() > 1 else "sicuro"
	var fname := args[2] if args.size() > 2 else mode
	DirAccess.make_dir_recursive_absolute(out)
	var game: Node = get_tree().root.get_node("Game")
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 60, "record_level": 60, "stars": 0, "perks": {}, "unlocked": true}
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await _frames(30)
	for k in 30:
		var b := main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		var t := main.find_child("TutorialOk", true, false) as Button
		if t != null:
			t.pressed.emit()
		await _frames(2)
	var combat: Object = game.call("system", "combat")
	var bank: Object = game.call("system", "bank")
	var zones: Array = []
	for z in combat.call("zones"):
		if combat.call("zone_unlocked", z.id):
			zones.append(str(z.id))
	if mode == "rischio":
		var cnt: int = bank.call("count", "food_bleak")
		if cnt > 0:
			bank.call("remove", "food_bleak", cnt)
		combat.call("start", zones[zones.size() - 1])
	else:
		bank.call("add", "food_bleak", 300, "capture")
		combat.call("set_food", 0, "food_bleak")
		combat.call("start", zones[0])
	for i in 60:
		game.call("_on_step", 0.1)
	if mode == "corsa":
		var run: Object = game.call("system", "run")
		var perks: Array = []
		for p in DataRegistry.table("run_perks"):
			perks.append(str(p.id))
			if perks.size() >= 3:
				break
		run.state["offer"] = perks
	main.call("show_screen", "combat")
	await _frames(25)
	for i in 10:
		game.call("_on_step", 0.1)
		main.call("_on_ui_tick")
		await _frames(2)
	await _frames(10)
	get_tree().root.get_texture().get_image().save_png("%s/%s.png" % [out, fname])
	print("CATTURA ", fname, " ", get_viewport().get_visible_rect().size)
	get_tree().quit()
