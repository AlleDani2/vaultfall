extends SceneTree
## Giro fotografico Missioni chiare (resoconto 105): Riepilogo con «Obiettivo attuale», schermata Missioni all'inizio, a metà storia
## (obiettivo di uccisione, consegna di un oggetto raro, riscatto di più missioni) e in inglese.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_quests.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_quests"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_quests_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	root.get_node("Settings").call("set_value", "tutorials", false)
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var code := OS.execute("import", ["-window", "root", abs_path])
	if code != 0:
		root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name, " codice ", code)


func _fill(q: Object, qid: String) -> void:
	var objs: Array = q.call("quest_def", qid).objectives
	var st: Dictionary = q.get("state")
	for i in objs.size():
		(st.progress[qid] as Array)[i] = q.call("target_of", objs[i])


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var state: Node = root.get_node("GameState")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 11)
	var q: Object = game.call("system", "quests")
	q.call("mark_intro_seen")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(4)
	await create_timer(2.0).timeout
	main.call("show_screen", "summary")
	await _shot("riepilogo_inizio")
	main.call("show_screen", "quests")
	await _shot("missioni_inizio")
	# avanza fino alla missione di combattimento (main_c0_q4)
	for qid in ["main_c0_q1", "main_c0_q2", "main_c0_q3"]:
		_fill(q, qid)
		game.get("sim").call("tick", 0.1)
		q.call("claim", qid)
	game.get("sim").call("tick", 0.1)
	main.call("show_screen", "quests")
	await _shot("missioni_combattimento")
	main.call("show_screen", "summary")
	await _shot("riepilogo_combattimento")
	# più missioni pronte insieme + consegna di un oggetto che si ottiene altrove
	var d: Dictionary = state.get("data")
	for t in ["feature:combat", "feature:crates", "feature:market", "skill:hero", "skill:mining", "skill:smithing", "skill:fishing", "skill:cooking",
			"skill:foraging", "skill:farming", "feature:estate", "feature:secrets", "feature:mercenaries"]:
		if not (d.unlocks as Array).has(t):
			(d.unlocks as Array).append(t)
	q.call("accept", "main_c9_q6")
	q.call("accept", "main_c10_q1")
	q.call("accept", "path_woodcutting_1")
	_fill(q, "path_woodcutting_1")
	game.get("sim").call("tick", 0.1)
	main.call("show_screen", "quests")
	await _shot("missioni_pronte_e_consegna")
	var sc := main.call("current_screen") as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 700
		await _shot("missioni_piu_in_basso")
		sc.scroll_vertical = 2000
		await _shot("missioni_fondo")
	quit()
