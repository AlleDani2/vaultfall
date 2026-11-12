extends SceneTree
## Sonda del «Vai» (resoconto 121): porta il bot a ogni missione principale e controlla che l'«Obiettivo attuale» abbia un
## bersaglio valido e un testo «come fare». Senza UI (headless):
##   <godot> --headless --path game -s res://scripts/probe_goal.gd -- [missione_finale]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var last := args[0] if args.size() > 0 else "main_c3_q6"
	root.get_node("SaveService").set("save_dir", "user://probe_goal_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	var game: Node = root.get_node("Game")
	game.call("new_game", 1, "normal", 11)
	var q: Object = game.call("system", "quests")
	q.call("mark_intro_seen")
	var bot: Object = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	var guide: Object = load("res://src/ui/screens/QuestGuide.gd")
	var bad := 0
	for i in 80:
		var qid := str(q.call("current_main"))
		if qid.is_empty():
			break
		var g: Dictionary = guide.call("current_goal", q)
		var tgt: Dictionary = g.get("target", {})
		var scr := str(tgt.get("screen", ""))
		var ok := not tgt.is_empty() and not str(g.get("how", "")).is_empty()
		print("%s kind=%s vai=%s %s | %s" % [qid, str(g.kind), scr if not scr.is_empty() else "NESSUNO", "" if ok else "<<<< PROBLEMA", str(g.get("how", "")).replace("\n", " ")])
		if not ok:
			bad += 1
			var unl: Array = root.get_node("GameState").data.unlocks
			print("   sblocchi: ", ", ".join(PackedStringArray(unl.map(func(x): return str(x)))))
		var res: Dictionary = bot.call("run_until_quest", qid, float(bot.get("t")) + 6.0 * 3600.0)
		if not bool(res.ok):
			print("bot bloccato su ", qid)
			break
		if qid == last:
			break
	print("PROBLEMI: ", bad)
	quit(0)
