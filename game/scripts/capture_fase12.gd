extends SceneTree
## Catture della fase F12 del progetto di interfaccia (docs/ui_redesign/07, F12): Deposito (lista riordinata).
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase12.gd -- <cartella> <suffisso> [it|en] [fresh|full]
## Scatta: 1 lista senza selezione, 2 con oggetto selezionato (dettaglio a destra), 3 menù Filtri aperto con 2 filtri attivi.
## Seme 4242, tutorial spenti, animazioni ridotte. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase12"
var _suffix := ""
var _main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_suffix = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase12_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	if args.size() > 2:
		root.get_node("Settings").call("set_value", "locale", args[2])
	_run.call_deferred(args[3] if args.size() > 3 else "full")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _calm() -> void:
	for k in 60:
		if _main.find_child("TutorialOk", true, false) == null and _main.find_child("WelcomeGo", true, false) == null:
			break
		var b := _main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		var t := _main.find_child("TutorialOk", true, false) as Button
		if t != null:
			t.pressed.emit()
		await _frames(2)
	var toasts: Node = _main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _shot(name: String, late: Callable = Callable()) -> void:
	_main.call("_on_ui_tick")
	await _frames(12)
	await _calm()
	if late.is_valid():
		late.call()                      # impostato all'ultimo momento: il Carro si scarica da solo se c'è posto
		_main.call("_on_ui_tick")
		await _frames(1)
	var path := "%s/%s_%s.png" % [_out, name, _suffix]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name)


func _set_capacity(bank: Object, cap: int) -> void:
	var st: Dictionary = bank.get("state")
	st["slots_bought"] = int(st["slots_bought"]) + cap - int(bank.call("capacity"))


func _run(_mode: String) -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(30)
	await _calm()
	_main.call("build_menu")
	var bank: Object = game.call("system", "bank")
	bank.call("add_currency", "gold", 423000)
	var dr: Node = root.get_node("DataRegistry")
	var st: Dictionary = bank.get("state")
	st["slots_bought"] = int(st["slots_bought"]) + 300
	for cat in ["material", "equipment", "food", "crate"]:
		var n := 0
		for it in dr.call("items_by_category", cat):
			bank.call("add", str(it.id), 2 if cat == "equipment" else 120)
			n += 1
			if n >= 14:
				break
	_main.call("show_screen", "bank")
	await _shot("1_lista_senza_selezione")
	var scr: Object = _main.call("current_screen")
	var ents: Array = scr.get("_entries")
	scr.set("_selected", ents[2].key)
	scr.call("_mark_dirty")
	await _shot("2_con_selezione")
	scr.set("_selected", "")
	scr.call("_on_only_worn", true)
	scr.call("_on_only_locked", true)
	scr.call("_mark_dirty")
	var fm: MenuButton = (scr as Node).find_child("FiltersMenu", true, false)
	fm.get_popup().popup(Rect2i(Vector2i(fm.get_screen_position()) + Vector2i(0, int(fm.size.y)), Vector2i(0, 0)))
	await _shot("3_menu_filtri")
	quit()
