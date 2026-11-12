extends SceneTree
## Catture della sola barra alta (fascia superiore) con i casi peggiori: Oro 999.999.999, Polvere 123.456.789, attività con nomi lunghi.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_barra_alta.gd -- <cartella> <prefisso> [it|en] [scala] [LxA]
## Non tocca i salvataggi veri (cartella di salvataggio propria).

const MAIN := "res://src/ui/main/MainScreen.tscn"
const BAND_H := 64

var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://capture_barra_alta"
	var prefix := args[1] if args.size() > 1 else "barra"
	root.get_node("SaveService").set("save_dir", "user://capture_barra_alta_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 2:
		root.get_node("Settings").call("set_value", "locale", args[2])
		TranslationServer.set_locale(args[2])
	if args.size() > 3:
		root.content_scale_factor = float(args[3])
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred(out, prefix, args[4] if args.size() > 4 else "")


func _resize(wxh: String) -> void:
	if wxh.is_empty():
		return
	var wh := wxh.split("x")
	var sz := Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_size(sz)
	root.size = sz


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run(out: String, prefix: String, wxh: String) -> void:
	await _frames(10)
	_resize(wxh)
	var game: Node = root.get_node("Game")
	game.call("new_game", 1, "normal", 5)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(20)
	for k in 10:
		var b := main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		await _frames(2)
	(game.call("system", "unlock") as Object).call("grant", "feature:prestige")
	var bank: Object = game.call("system", "bank")
	bank.call("add_currency", "stardust", 123456789)
	bank.call("add_currency", "gold", 999999999)
	(game.call("system", "skills") as Object).call("start", "wc_pine")
	_resize(wxh)
	await _frames(40)
	main.call("_on_ui_tick")
	main.call("_update_slow")
	await _frames(20)
	var img := root.get_texture().get_image()
	var band := img.get_region(Rect2i(0, 0, img.get_width(), int(BAND_H * root.content_scale_factor)))
	band.save_png("%s/%s_%dx%d.png" % [out, prefix, img.get_width(), img.get_height()])
	print("CATTURA ", prefix, " ", img.get_size())
	quit()
