extends SceneTree
## Catture del menù 1.0: titolo, slot (con uno slot danneggiato ripristinabile e uno illeggibile), conferma pericolosa,
## schermata di caricamento, Crediti, Licenze, Novità, menù di pausa in partita.
##   xvfb-run -a -s "-screen 0 3840x2160x24" <godot> --path game --rendering-driver opengl3 -s res://scripts/capture_menu_1_0.gd -- <cartella> <it|en> <larghezza> <altezza>
## Non tocca i salvataggi veri (cartella temporanea in user://). Con la larghezza/altezza si prova la scala (1280×720, 1920×1080, 3840×2160).
const START := "res://src/ui/start/StartScreen.tscn"
const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://capture_menu_1_0"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_menu_1_0_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 3:
		DisplayServer.window_set_size(Vector2i(int(args[2]), int(args[3])))
		root.size = Vector2i(int(args[2]), int(args[3]))
	root.get_node("Settings").call("set_value", "reduce_motion", true)
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
	var ss: Node = root.get_node("SaveService")
	for s in [1, 2, 3]:
		ss.call("delete_slot", s)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("titolo_vuoto")
	# slot 1: partita sana (classe Guerriero, 12 h); slot 2: principale danneggiato con copia di sicurezza; slot 3: illeggibile
	game.call("new_game", 1, "normal")
	root.get_node("GameState").data.stats["playtime_s"] = 45240.0
	ss.call("save_now")
	await _frames(2)
	game.call("stop_game", true)
	game.call("new_game", 2, "normal")
	ss.call("save_now")
	root.get_node("GameState").data.stats["playtime_s"] = 7300.0
	root.get_node("SaveService").set("last_saved_unix", int(root.get_node("SaveService").get("last_saved_unix")) + 1)
	ss.call("save_now")
	game.call("stop_game", false)
	var f := FileAccess.open(ss.call("slot_path", 2), FileAccess.WRITE)
	f.store_string("danneggiato")
	f.close()
	game.call("new_game", 3, "normal")
	ss.call("save_now")
	game.call("stop_game", false)
	for n in range(1, 4):
		DirAccess.remove_absolute(ss.call("backup_path", 3, n))
	f = FileAccess.open(ss.call("slot_path", 3), FileAccess.WRITE)
	f.store_string("illeggibile")
	f.close()
	root.get_node("Settings").call("set_value", "last_slot", 1)
	start.queue_free()
	await _frames(2)
	start = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("titolo_con_partita")
	start.call("show_slots")
	await _shot("slot")
	start.call("_on_new_in_slot", 1, true)
	await _shot("conferma_sovrascrittura")
	(start.get_node("Confirm") as Window).hide()
	start.call("_ask_delete", 3)
	await _shot("conferma_elimina")
	(start.get_node("Confirm") as Window).hide()
	start.call("_on_coop")
	start.call("_back_to_menu")
	await _shot("cooperativa_bloccata")
	start.call("_show_loading")
	await _shot("caricamento")
	start.call("_hide_loading")
	start.call("show_credits")
	await _shot("crediti")
	(load("res://src/ui/screens/CreditsView.gd") as GDScript).call("show_licenses", start)
	await _shot("licenze")
	for d in root.get_children():
		if d is AcceptDialog:
			d.queue_free()
	start.call("show_settings")
	await _shot("impostazioni")
	start.queue_free()
	await _frames(2)
	# pausa in partita
	game.call("load_game", 1)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(20)
	root.get_node("Feedback").call("toggle_pause_menu", true)
	await _shot("pausa")
	root.get_node("Feedback").call("close_pause_menu")
	await _frames(2)
	game.call("stop_game", false)
	for s in [1, 2, 3]:
		ss.call("delete_slot", s)
	quit()
