extends Node
## Catture della fase F1 (difetto I2): numeri di danno con il mostro in cima all'arena, a 1280x720.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     res://scripts/capture_fase1.tscn -- <cartella> <prima|dopo>
## «prima» = chiamate senza confine (come prima della correzione), «dopo» = con il rettangolo dell'arena.
## Il centro del nemico è portato al bordo alto del palco. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	get_tree().root.get_node("SaveService").set("save_dir", "user://capture_fase1_saves")
	get_tree().root.get_node("SaveService").set("autosave_enabled", false)
	get_tree().root.get_node("Settings").call("set_value", "tutorials", false)
	get_tree().root.get_node("Settings").call("set_value", "reduce_motion", false)
	get_tree().root.get_node("Settings").call("set_value", "locale", "it")
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://capture_fase1"
	var mode := args[1] if args.size() > 1 else "dopo"
	DirAccess.make_dir_recursive_absolute(out)
	var game: Node = get_tree().root.get_node("Game")
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
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
	var best := ""
	for z in combat.call("zones"):
		if combat.call("zone_unlocked", z.id):
			best = str(z.id)
	combat.call("start", best)
	for i in 40:
		game.call("_on_step", 0.1)
	main.call("show_screen", "combat")
	await _frames(20)
	var cs: Node = main.find_child("CombatScreen", true, false)
	if cs == null:
		for c in main.find_children("*", "GameScreen", true, false):
			if c.get_script() != null and str(c.get_script().resource_path).ends_with("CombatScreen.gd"):
				cs = c
	var stage: Control = cs.get("_stage")
	var rect: Rect2 = cs.call("_arena_rect")
	var top := Vector2(stage.get_global_rect().get_center().x, stage.get_global_rect().position.y)
	Fx.force_level = 2
	Fx.ensure()
	await _frames(4)
	var sizes := [Fx.NUM_M, Fx.NUM_XL, Fx.NUM_L, Fx.NUM_M, Fx.NUM_XL]
	for i in 5:
		var p := top + Vector2((i - 2) * 70.0, -50.0)
		if mode == "dopo":
			Fx.number(p, str(244226 + i * 111) + "!", Color(1.0, 0.85, 0.3), sizes[i], 58.0, 1.4, 1, 0.0, rect)
		else:
			Fx.number(p, str(244226 + i * 111) + "!", Color(1.0, 0.85, 0.3), sizes[i], 58.0, 1.4, 1)
	await get_tree().create_timer(0.55).timeout
	get_tree().root.get_texture().get_image().save_png("%s/combattimento_%s.png" % [out, mode])
	print("CATTURA ", mode)
	get_tree().quit()
