extends SceneTree
## Catture della schermata iniziale e dei Crediti (finitura): menù, slot, conferma su slot pieno, Crediti, Impostazioni.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 -s res://scripts/capture_title.gd -- <cartella> <it|en> <larghezza> <altezza>
## Non tocca i salvataggi veri (cartella temporanea in user://).
const START := "res://src/ui/start/StartScreen.tscn"
var _out := "user://capture_title"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_title_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 3:
		root.size = Vector2i(int(args[2]), int(args[3]))
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await _frames(40)
	_n += 1
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_out, _n, shot_name])
	print("CATTURA ", shot_name, " ", img.get_size())


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("titolo_vuoto")
	game.call("new_game", 1, "normal")
	game.call("save_game") if game.has_method("save_game") else null
	start.queue_free()
	await _frames(2)
	start = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("titolo_con_partita")
	start.call("show_slots")
	await _shot("slot")
	start.call("_on_new_in_slot", 1, true)
	await _shot("conferma_slot_pieno")
	(start.get_node("Confirm") as Window).hide()
	if start.has_method("show_credits"):
		start.call("show_credits")
		await _shot("crediti")
	start.call("show_settings")
	await _shot("impostazioni")
	quit()
