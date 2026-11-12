extends SceneTree
## Catture dei talenti di mansione e dell'Emporio (rapporto 116).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_perks.gd -- <cartella> <it|en> <schermate separate da virgola, es. skill:farming,shop> [prefisso]
## Mansioni a livello 20 (talenti da scegliere). Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_perks"
var _prefix := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_perks_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 3:
		_prefix = args[3]
	if args.size() > 4:                            # scala dell'interfaccia (0,75–1,25): 1,25 restringe l'area logica
		root.get_node("Settings").call("set_value", "ui_scale", float(args[4]))
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _calm(main: Node) -> void:
	await _frames(20)
	for k in 60:
		var any := false
		for nm in ["WelcomeGo", "TutorialOk"]:
			var b := main.find_child(nm, true, false) as Button
			if b != null:
				b.pressed.emit()
				any = true
		if not any:
			break
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _tour() -> void:
	var args := OS.get_cmdline_user_args()
	var screens: PackedStringArray = (args[2] if args.size() > 2 else "skill:farming").split(",")
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 5)
	var data: Dictionary = root.get_node("GameState").get("data")
	if data.has("tutorial"):
		data.tutorial["off"] = true
	var sk: Object = game.call("system", "skills")
	for t in ["feature:combat", "feature:market", "feature:perks", "feature:bounties", "feature:shop"]:
		(data.unlocks as Array).append(t)
	for row in root.get_node("DataRegistry").call("table", "skills"):
		(data.unlocks as Array).append("skill:" + str(row.id))
		sk.state[str(row.id)]["level"] = 20
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	for sc in screens:
		var open_it := sc.ends_with("+open")           # «skill:farming+open»: con il pannello dei talenti aperto
		var scr := sc.trim_suffix("+open")
		root.get_node("EventBus").emit_signal("screen_requested", scr, {})
		await _frames(25)
		if open_it:
			var pp := main.find_child("SkillPerkPanel", true, false)
			if pp != null:
				pp.call("set_open", true)
				await _frames(10)
		for r in main.find_children("ShopRow_*", "", true, false):
			print("RIGA vp=", root.size, " win=", root.get_window().size, " cs=", root.get_window().content_scale_size, " ", r.name, " larghezza ", r.size.x, " azioni sotto ", (r as Node).get_child(0).get_child(-1).visible)
			break
		var path := "%s/%s%s%s_%s.png" % [_out, _prefix, scr.replace(":", "_"), "_aperto" if open_it else "", str(root.get_texture().get_width())]
		root.get_texture().get_image().save_png(path)
		print("CATTURA ", path)
	quit()
