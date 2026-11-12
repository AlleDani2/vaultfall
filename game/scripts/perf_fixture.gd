extends SceneTree
## Costruisce il salvataggio di prova per i profili di prestazione (resoconto 100): partita VERA giocata dal bot in
## `long_mode` fino alla prima incursione, poi ore di gioco "via" (offline analitico) fino a N ore simulate, poi il
## Deposito viene riempito con ogni oggetto dei dati (molte istanze di equipaggiamento). Scrive lo slot 1 in
## `user://perf_fixture/` e stampa il riepilogo.
##   <godot> --headless --path game -s res://scripts/perf_fixture.gd -- <ore_totali>
## Non tocca i salvataggi veri (cartella a parte).

const SEED := 20261100
const DIR := "user://perf_fixture"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var hours := float(args[0]) if args.size() > 0 else 50.0
	var ss: Node = root.get_node("SaveService")
	var game: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	ss.set("save_dir", DIR)
	ss.set("autosave_enabled", false)
	game.call("new_game", 1, "normal", SEED)
	var bot = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	bot.long_mode = true
	bot.step_long = func(s: float) -> void: game.call("_on_long_gap", s)
	bot.clock = PerfGate.clock_usec
	bot.wall_limit_ms = 900000
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = bot.run_until_quest("main_c6_q2", 120.0 * 3600.0)
	print("BOT ok=%s t=%.2f h (reale %.0f s)" % [res.get("ok"), float(res.get("t", 0)) / 3600.0, float(Time.get_ticks_msec() - t0) / 1000.0])
	var cur := float(res.get("t", 0)) / 3600.0
	var chunks := 0
	while cur < hours:
		game.call("_on_long_gap", 1800.0)
		cur += 0.5
		chunks += 1
	print("ore simulate ~%.1f (blocchi offline aggiunti %d)" % [cur, chunks])
	var bk: Object = game.call("system", "bank")
	var n := 0
	for it in root.get_node("DataRegistry").call("all_items").values():
		if bk.call("free_slots") <= 0:
			break
		bk.call("add", str(it.id), 3, "perf")
		n += 1
	print("oggetti aggiunti: ", n, " posti usati ", bk.call("used_slots"), "/", bk.call("capacity"))
	ss.call("save_now")
	print("FIXTURE pronta in ", ProjectSettings.globalize_path(DIR))
	quit(0)
