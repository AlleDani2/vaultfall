extends SceneTree
## Catture della fase F5 del progetto di interfaccia (docs/ui_redesign/07, F5): scala automatica dell'area logica.
## Riepilogo e Combattimento a 1920x1080 (area logica attesa 1536x864) e 1280x800; stampa l'area logica misurata.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase5.gd -- <cartella> [it|en]
## Partita nuova con seme 4242, tutto sbloccato, tutorial spenti, Taglialegna in corso. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase5"
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase5_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)     # niente animazioni: le immagini prima/dopo sono confrontabili
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
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm(main)
	main.call("build_menu")
	var sk: Object = game.call("system", "skills")
	sk.call("start", "wc_pine")
	for i in 5:
		game.call("_on_step", 0.1)
	main.call("show_screen", "summary")
	await _shot("summary")
	print("AREA_LOGICA ", root.get_visible_rect().size, " csf=", root.content_scale_factor, " finestra=", root.size)
	var combat: Object = game.call("system", "combat")
	var best := ""
	for z in combat.call("zones"):
		if combat.call("zone_unlocked", z.id):
			best = str(z.id)
	combat.call("start", best)
	for i in 150:
		game.call("_on_step", 0.1)
	main.call("show_screen", "combat")
	await _shot("combat")
	quit()
