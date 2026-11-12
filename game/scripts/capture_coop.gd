extends SceneTree
## Giro fotografico COOP-1: schermata «Amici» (codici, compagni, Prova della settimana, classifica locale), IT/EN.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_coop.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://). Sporca solo la partita temporanea.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_coop"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_coop_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	root.get_node("Settings").call("set_value", "tutorials", false)
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await _frames(6)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, shot_name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", shot_name)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var state: Node = root.get_node("GameState")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 11)
	var d: Dictionary = state.get("data")
	for t in ["feature:combat", "feature:coop", "feature:rift", "raid:collectors_den"]:
		(d.unlocks as Array).append(t)
	d.skills["hero"] = {"xp": 0.0, "level": 60, "record_level": 60, "stars": 0, "perks": {}, "unlocked": true}
	var co: Object = game.call("system", "coop")
	var now := int(Time.get_unix_time_from_system())
	# due amici (schede costruite dalla tua, con altro nome e identità) e un risultato incollato
	var base: Dictionary = co.call("build_sheet", now)
	var f1 := base.duplicate(true)
	f1["uid"] = "00000000000000a1"
	f1["name"] = "Giulia"
	f1["class"] = "ranger"
	f1["st"]["style"] = "ranged"
	co.call("import_code", CoopCodec.pack("H", 1, f1), now)
	var f2 := base.duplicate(true)
	f2["uid"] = "00000000000000a2"
	f2["name"] = "Marco"
	f2["issued"] = now - 40 * 86400
	co.call("import_code", CoopCodec.pack("H", 1, f2), now)
	co.call("weekly_run", now)
	var wk := str(CoopWeekly.week_of(now).id)
	var res := {"uid": "00000000000000cd", "name": "Marco", "class": "arcanist", "spec": "", "level": 80, "week": wk,
		"floor": 14, "t": 900.0, "dmg": 5.0e9, "issued": now}
	co.call("import_code", CoopCodec.pack("R", 1, res), now)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	var wb := main.find_child("WelcomeGo", true, false) as Button
	if wb != null:
		wb.pressed.emit()
		await _frames(2)
	main.call("show_screen", "coop")
	await _shot("amici_alto")
	var scr: Control = main.call("current_screen")
	scr.call("_on_copy_mine")
	await _shot("amici_codice")
	var sc := scr.find_children("*", "ScrollContainer", true, false)
	if sc.size() > 0:
		(sc[0] as ScrollContainer).scroll_vertical = 700
	await _shot("amici_meta")
	if sc.size() > 0:
		(sc[0] as ScrollContainer).scroll_vertical = 100000
	await _shot("amici_fondo")
	quit(0)
