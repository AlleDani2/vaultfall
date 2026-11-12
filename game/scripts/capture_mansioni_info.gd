extends SceneTree
## Catture delle schermate delle mansioni (resa, quantità richiesta/posseduta, requisiti) per il resoconto 38.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_mansioni_info.gd -- <cartella> <prefisso> [it|en] [LxA]
## Non tocca i salvataggi veri (cartella di salvataggio propria).

const MAIN := "res://src/ui/main/MainScreen.tscn"
const SKILLS := ["woodcutting", "smithing", "cooking", "farming", "alchemy"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://capture_mansioni_info"
	var prefix := args[1] if args.size() > 1 else "m"
	root.get_node("SaveService").set("save_dir", "user://capture_mansioni_info_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 2:
		root.get_node("Settings").call("set_value", "locale", args[2])
		TranslationServer.set_locale(args[2])
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred(out, prefix, args[3] if args.size() > 3 else "", args.size() > 4 and args[4] == "poveri")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _resize(wxh: String) -> void:
	if wxh.is_empty():
		return
	var wh := wxh.split("x")
	var sz := Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_size(sz)
	root.size = sz


func _run(out: String, prefix: String, wxh: String, poor: bool) -> void:
	await _frames(10)
	_resize(wxh)
	var game: Node = root.get_node("Game")
	game.call("new_game", 1, "normal", 5)
	var data: Dictionary = root.get_node("GameState").get("data")
	var un: Object = game.call("system", "unlock")
	for sid in ["woodcutting", "smithing", "cooking", "farming", "alchemy", "fishing", "mining"]:
		un.call("grant", "skill:" + sid)
		data.skills[sid] = {"xp": 0.0, "level": 12 if poor else 25, "record_level": 25, "stars": 0, "perks": {}, "unlocked": true}
	var bank: Object = game.call("system", "bank")
	# scorte parziali: alcune ricette hanno gli ingredienti, altre ne hanno solo una parte
	var reg: Node = root.get_node("DataRegistry")
	var i := 0
	for a in reg.call("all_actions").values():
		if not (str(a.skill) in SKILLS):
			continue
		i += 1
		for io in a.get("inputs", []):
			if poor:
				bank.call("add", str(io.item), int(io.qty) * 4 / 5, "capture")      # quasi abbastanza: manca poco
			elif i % 3 == 0:
				bank.call("add", str(io.item), int(io.qty) * 3, "capture")
			elif i % 3 == 1:
				bank.call("add", str(io.item), maxi(1, int(io.qty) / 2), "capture")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(20)
	for k in 10:
		var b := main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		await _frames(2)
	_resize(wxh)
	bank.call("add", "seed_potato", 6, "capture")
	for s in SKILLS:
		main.call("show_screen", "skill:" + s)
		await _frames(30)
		main.call("_on_ui_tick")
		await _frames(10)
		for b in main.find_children("*", "Button", true, false):
			if (b as Button).text.begins_with("▸ ") and (b as Button).visible and poor:
				(b as Button).pressed.emit()
		await _frames(5)
		var toasts: Node = main.get("_toasts")
		if toasts != null:
			for c in toasts.get_children():
				c.free()
		await _frames(3)
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%s_%dx%d.png" % [out, prefix, s, img.get_width(), img.get_height()])
		print("CATTURA ", prefix, " ", s, " ", img.get_size())
	quit()
