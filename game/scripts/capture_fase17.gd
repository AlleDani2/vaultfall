extends SceneTree
## Catture della fase F17 (docs/ui_redesign/07 F17): barra delle schede, scheda del giocatore, modalità vendita con un pezzo
## bloccato, anteprima a due passaggi, ricerca con la scheda «Risultati».
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase17.gd -- <cartella> [it|en] [prefisso]
## Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase17"
var _prefix := "f17"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase17_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "bank_view", "grid")
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 2:
		_prefix = args[2]
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	_n += 1
	var path := "%s/%s_%02d_%s.png" % [_out, _prefix, _n, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", path)


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
	for t in ["feature:market", "skill:smithing", "skill:woodcutting", "skill:mining", "chapter:1"]:
		(data.unlocks as Array).append(t)
	var bank: Object = game.call("system", "bank")
	var reg: Object = root.get_node("DataRegistry")
	bank.get("state").slots_bought = 120
	var i := 0
	for cat in ["material", "food", "potion", "crate", "key", "seed"]:
		var list: Array = reg.call("items_by_category", cat)
		for j in mini(list.size(), 14 if cat == "material" else 5):
			bank.call("add", str(list[j].id), 3 + (i * 37) % 900, "capture")
			i += 1
	for d in ["skin_millbrook_01", "skin_millbrook_02", "relic_millbrook_1"]:
		bank.call("add_instance", {"def": d})
	bank.call("add_instance", {"def": "plate_helm_copper"})
	bank.call("set_def_locked", "log_pine", true)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	main.call("show_screen", "bank")
	await _calm(main)
	var scr: Node = main.call("current_screen")
	await _shot("benvenuto_e_barra_schede")
	# schede suggerite: prima l'anteprima, poi la conferma; e una scheda del giocatore
	var sug: Node = scr.call("open_suggested")
	await _shot("schede_suggerite_anteprima")
	if sug != null:
		sug.queue_free()
	scr.call("apply_suggested", scr.call("suggested_plan"))
	var t: String = bank.call("create_tab", "Forgia", "ore_copper")
	var keys: Array = []
	for d in ["ore_copper", "ore_tin", "log_pine"]:
		keys.append("s:" + d)
	bank.call("assign_to_tab", keys, t)
	scr.call("_mark_dirty")
	await _calm(main)
	await _shot("barra_schede_tutto")
	scr.call("_select_tab", str((bank.call("tabs") as Array)[0].id))
	await _calm(main)
	await _shot("scheda_del_giocatore")
	scr.call("_select_tab", "")
	scr.call("enter_mode", "sell")
	scr.call("select_all_visible")
	await _calm(main)
	await _shot("modalita_vendita_bloccato_protetto")
	var dlg: Node = scr.call("open_selection_sell")
	await _shot("anteprima_vendita")
	if dlg != null:
		dlg.call("hide")
	scr.call("exit_mode")
	scr.call("_on_query", "cat:materiale")
	var se: LineEdit = scr.get("_search")
	se.text = "cat:materiale"
	await _calm(main)
	await _shot("ricerca_risultati")
	print("FINE")
	quit()
