extends SceneTree
## Catture della fase F2 del progetto di interfaccia (docs/ui_redesign/07, F2): i 5 stati della barra alta.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase2.gd -- <cartella> <suffisso> [it|en] [fresh|full]
## «fresh»: partita nuova senza sblocchi, a riposo (stato 4: Polvere nascosta, attività a riposo).
## «full»: tutto sbloccato, Taglialegna in corso; scatta normale, Deposito ambra, Deposito pieno con Carro e in pausa.
## Seme 4242, tutorial spenti, animazioni ridotte. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase2"
var _suffix := ""
var _main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_suffix = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase2_saves")
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


func _run(mode: String) -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	if mode == "full":
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
	if mode == "fresh":
		_main.call("show_screen", "summary")
		await _shot("4_riposo_sin_prestigio")
		quit()
		return
	bank.call("add_currency", "stardust", 134)
	bank.call("add_currency", "gold", 2973)
	var sk: Object = game.call("system", "skills")
	sk.call("start", "wc_pine")
	for i in 5:
		game.call("_on_step", 0.1)
	_main.call("show_screen", "summary")
	var dr: Node = root.get_node("DataRegistry")
	for it in dr.call("items_by_category", "material"):
		if int(bank.call("used_slots")) >= 12:
			break
		bank.call("add", str(it.id), 1)
	var used: int = int(bank.call("used_slots"))
	_set_capacity(bank, used * 2 + 10)
	await _shot("1_normale")
	var warn: float = float(root.get_node("DataRegistry").constants.bank.warn_pct)
	_set_capacity(bank, int(floor(float(used) * 100.0 / warn)))
	await _shot("2_deposito_ambra")
	_set_capacity(bank, used)
	var st: Dictionary = bank.get("state")
	await _shot("3_deposito_pieno_carro", func() -> void: st["overflow_stacks"] = {"log_pine": 3})
	_set_capacity(bank, used * 2 + 10)
	st["overflow_stacks"] = {}
	root.get_node("Clock").call("set_paused", true)
	await _shot("5_in_pausa")
	quit()
