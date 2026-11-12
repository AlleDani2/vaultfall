extends SceneTree
## Catture della fase F9 del progetto di interfaccia (docs/ui_redesign/07, F9): Tenuta (Dispensa vuota e piena), Dungeon, Breccia, Taglie.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase9.gd -- <cartella> [it|en]
## Stato SIMULATO (il checkpoint del bot a 60 h non è nel repository): partita nuova seme 4242, tutto sbloccato, Eroe di livello 60,
## Tenuta con edifici a vari livelli. Stampa anche il numero di controlli visibili e l'altezza del contenuto (in «pagine» da 720 px)
## per ogni schermata. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase9"
var _main: Control
var _game: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase9_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
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
	_main.call("_update_slow")
	await _frames(4)
	var path := "%s/%s.png" % [_out, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name)


## Controlli visibili e altezza del contenuto della schermata aperta (in pagine da 720 px).
func _metrics(tag: String) -> void:
	var host: Control = _main.get("_host")
	var scr: Node = host.get_child(host.get_child_count() - 1)
	var n := 0
	for c in scr.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and (ctl is Button or ctl is Label or ctl is RichTextLabel or ctl is Range or ctl is OptionButton or ctl is CheckBox or ctl is TextureRect):
			n += 1
	var pages := 0.0
	for c in scr.find_children("*", "ScrollContainer", true, false):
		var sc := c as ScrollContainer
		if not sc.is_visible_in_tree():
			continue
		var inner := sc.get_child(0) as Control
		pages = maxf(pages, (sc.global_position.y - scr.global_position.y + inner.get_combined_minimum_size().y) / 720.0)
	print("METRICA ", tag, " controlli_visibili=", n, " pagine=", snappedf(pages, 0.01))


func _tour() -> void:
	_game = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	_game.call("new_game", 1, "normal", 4242)
	var un: Object = _game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	for b in ["cottage", "sawmill", "mine_shaft", "fishery", "fields", "ranch", "shopfront", "warehouse", "private_vault", "academy", "tavern"]:
		un.call("grant", "building:" + b)
	var gs: Node = root.get_node("GameState")
	gs.data.skills["hero"] = {"xp": 0.0, "level": 60, "record_level": 60, "stars": 0, "perks": {}, "unlocked": true}
	var est: Object = _game.call("system", "estate")
	var levels := {"cottage": 28, "sawmill": 5, "mine_shaft": 4, "fishery": 4, "fields": 9, "ranch": 7, "shopfront": 6, "warehouse": 6, "private_vault": 3, "academy": 8, "tavern": 12}
	for bid in levels:
		est._entry(bid)["level"] = levels[bid]
	est.state.settlers = est.settler_cap()
	est.state.pantry = 0.0
	est.call("set_pantry_auto", false)
	est.state.storage = {"plank_pine": 900.0, "ore_copper": 400.0}
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm(main)
	main.call("build_menu")
	var bank: Object = _game.call("system", "bank")
	bank.call("add_gold", 3000)
	# 1) Tenuta, Dispensa vuota (e niente cibo nel Deposito)
	main.call("show_screen", "estate")
	await _frames(6)
	_metrics("estate_vuota")
	await _shot("estate_dispensa_vuota")
	# 2) Tenuta, Dispensa piena
	est.state.pantry = 800.0
	bank.call("add", "food_bleak", 40)
	main.call("show_screen", "estate")
	await _frames(6)
	_metrics("estate_piena")
	await _shot("estate_dispensa_piena")
	var scr: Node = (main.get("_host") as Control).get_child((main.get("_host") as Control).get_child_count() - 1)
	scr.call("_set_tab", "pantry")
	await _shot("estate_scheda_dispensa")
	# 3) Dungeon
	main.call("show_screen", "dungeon", {"dungeon": "cursed_granary"})
	await _frames(6)
	_metrics("dungeon")
	await _shot("dungeon")
	# 4) Breccia
	main.call("show_screen", "dungeon", {"tab": "rift"})
	await _frames(6)
	_metrics("breccia")
	await _shot("breccia")
	# 5) Taglie
	main.call("show_screen", "bounty")
	await _frames(6)
	_metrics("taglie")
	await _shot("taglie")
	quit(0)
