extends SceneTree
## Giro fotografico UI-B (G22 badge e Paralleli, G23 scorciatoie, G24 colonna destra, G34 Città, G37 requisiti cliccabili,
## G53 tempo al livello e Cozy) in uno stato di gioco realistico (bot + aiuti di prova), it/en, 1280x720 e 1920x1080.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_ui_b.gd -- <cartella> <it|en> [reuse]

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://ui_b"
var _tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://ui_b_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)      # catture ferme
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
		_tag = args[1]
	if DisplayServer.window_get_size().x >= 1500:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, frames: int = 6) -> void:
	await _frames(frames)
	var tc: Node = root.find_child("Toasts", true, false)
	if tc != null:
		for c in tc.get_children():
			c.free()
	await _frames(2)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s_%dx%d.png" % [_out, name, _tag, img.get_width(), img.get_height()]
	img.save_png(path)
	print("CATTURA ", path)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var reuse := FileAccess.file_exists("user://ui_b_saves/slot_1.sav") and OS.get_cmdline_user_args().has("reuse")
	if reuse:
		print("carico ", game.call("load_game", 1).ok)
	else:
		game.call("new_game", 1, "normal", 20261023)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	for k in 6:
		_press(main, "WelcomeGo")
		_press(main, "TutorialOk")
		await _frames(1)
	if not reuse:
		_build(game)
	main.call("build_menu")
	await _dismiss(main)
	_state(game)
	main.call("_update_slow")

	# 1) Riepilogo con badge, Paralleli, tempo al livello
	main.call("show_screen", "summary")
	await _shot("1_riepilogo_paralleli")
	# 2) Città: Deposito con striscia (chiacchiera + Gazzetta), poi Mercato
	main.call("show_screen", "bank")
	await _shot("2_citta_deposito")
	main.call("show_screen", "market")
	await _shot("3_citta_mercato")
	# 3) Mansione con requisiti cliccabili: Fabbro (ingredienti mancanti) e il filtro «produce»
	main.call("show_screen", "skill:smithing")
	await _frames(6)
	_chain(main.get("_current"))
	print("MAIN min=", (main as Control).get_combined_minimum_size())
	await _shot("4_mansione_requisiti")
	var item := "ore_copper"
	main.call("show_screen", "skill:mining", {"skill": "mining", "produces": item})
	await _shot("5_mansione_filtro_produce")
	# 4) Tenuta con edificio in vista e missioni con missione in vista
	main.call("show_screen", "estate", {"building": "academy"})
	await _shot("6_tenuta_edificio")
	main.call("show_screen", "quests")
	await _shot("7_missioni")
	# 5) Impostazioni: blocco UI-B (tutorial, Cozy, scorciatoie)
	main.call("show_screen", "settings")
	await _frames(4)
	var sc := (main.get("_current") as Node).find_children("*", "ScrollContainer", true, false)
	var extras: Node = main.find_child("SettingsExtras", true, false)
	if extras != null and not sc.is_empty():
		(sc[0] as ScrollContainer).ensure_control_visible(extras.get_child(extras.get_child_count() - 1) as Control)
		(sc[0] as ScrollContainer).scroll_vertical += 200
	await _shot("8_impostazioni_ui_b")
	# 6) Cozy acceso: barra con tempo al livello più breve
	root.get_node("Settings").call("set_value", "cozy_mode", true)
	main.call("show_screen", "summary")
	main.call("_update_slow")
	await _shot("9_cozy_attivo")
	root.get_node("Settings").call("set_value", "cozy_mode", false)
	# 7) Colonna larga e nascosta
	root.get_node("Settings").call("set_value", "right_col_width", 420)
	await _shot("10_colonna_larga")
	root.get_node("Settings").call("set_value", "right_col_width", 250)
	main.call("toggle_column")
	await _shot("11_colonna_nascosta")
	main.call("toggle_column")
	# 8) voce bloccata col tooltip
	var btn: Button = main.get("_buttons").get("skill:thievery") if main.get("_buttons").has("skill:thievery") else null
	print("bloccata cliccabile: ", btn != null and btn.has_meta("req_target"))
	quit(0)


## Partita realistica: bot fino a una missione avanzata + sblocchi di prova.
func _build(game: Node) -> void:
	var bot = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	bot.call("run_until_quest", "main_c1_q6", 3.0 * 3600.0)
	var un: Object = game.call("system", "unlock")
	for t in ["combat", "crates", "estate", "expeditions", "factions", "market", "mercenaries", "orders"]:
		un.call("grant", "feature:" + t)
	var done: Array = game.get("sim").ctx.state.quests.done
	for bd in root.get_node("DataRegistry").call("table", "estate_buildings"):
		var uq := str(bd.get("unlock", {}).get("quest", ""))
		if uq != "" and not done.has(uq):
			done.append(uq)
	var es: Object = game.call("system", "estate")
	for bid in {"cottage": 6, "academy": 3, "tavern": 3, "sawmill": 3}:
		(es.call("_entry", bid) as Dictionary)["level"] = {"cottage": 6, "academy": 3, "tavern": 3, "sawmill": 3}[bid]
	es.state.settlers = int(es.call("settler_cap"))
	var sk: Object = game.call("system", "skills")
	sk.call("add_xp", "woodcutting", 400000.0)
	sk.call("add_xp", "mining", 200000.0)
	root.get_node("SaveService").call("save_now")


## Rende visibili tutte le parti nuove: casse apribili, Commessa consegnabile, orto, spedizione, apprendisti, coda.
func _state(game: Node) -> void:
	var bank: Object = game.call("system", "bank")
	var sk: Object = game.call("system", "skills")
	var cr: Object = game.call("system", "crates")
	for c in ["crate_millbrook", "crate_saltreach"]:
		cr.call("grant_crate", c, 3)
		var key: Variant = cr.call("crate_def", c).get("key")
		if key != null:
			bank.call("add", str(key), 3, "qa")
	var mk: Object = game.call("system", "market")
	var ctx_state: Dictionary = game.get("sim").ctx.state
	ctx_state["orders"] = [{"id": "o_qa", "item": "log_pine", "qty": 3, "gold": 40, "rep": 1, "faction": "merchant_league",
		"npc": "bertoldo", "crate": "", "created_t": 0.0, "expires_t": float(mk.state.t) + 1e6}]
	bank.call("add", "log_pine", 5, "qa")
	var un: Object = game.call("system", "unlock")
	un.call("grant", "skill:farming")
	var f: Object = game.call("system", "farming")
	for kd in root.get_node("DataRegistry").call("table", "farming_plots"):
		var kid := str(kd.id)
		f.state.plots[kid][0] = {"crop": "x", "remaining_s": 0.0, "total_s": 10.0, "auto": false}
		if (f.state.plots[kid] as Array).size() > 1:
			f.state.plots[kid][1] = {"crop": "x", "remaining_s": 95.0, "total_s": 300.0, "auto": false}
	var ap: Object = game.call("system", "apprentices")
	ap.call("assign", 0, "wc_pine")
	var mc: Object = game.call("system", "mercenaries")
	mc.call("_refill_board")
	for c in mc.call("candidates").duplicate():
		mc.call("hire", c.uid)
	var ex: Object = game.call("system", "expeditions")
	var offers: Array = ex.call("board")
	var roster: Array = mc.call("roster")
	if not offers.is_empty() and not roster.is_empty():
		ex.call("start", offers[0].id, [roster[0].uid])
	var q: Object = game.call("system", "queue")
	q.call("add", "wc_pine", "count", 50)
	var aid := "wc_pine"
	sk.call("start", aid)
	var ev: Dictionary = root.get_node("DataRegistry").call("table", "gazette_events")[0]
	mk.state.gazette.active.append({"id": ev.id, "category": ev.category, "mult": float(ev.mult), "ends_t": float(mk.state.t) + 7200.0})
	var qs: Object = game.call("system", "quests")
	var mid: String = qs.call("current_main")
	if mid != "":
		var d: Dictionary = qs.call("quest_def", mid)
		var pr: Array = []
		var qsc: GDScript = load("res://src/systems/QuestSystem.gd")
		for o in d.objectives:
			pr.append(qsc.call("target_of", o))
		qs.state.progress[mid] = pr


func _dismiss(main: Node) -> void:
	for k in 60:
		var found := false
		for nm in ["TutorialOk", "WelcomeGo", "WbCollect"]:
			if main.find_child(nm, true, false) != null:
				_press(main, nm)
				found = true
		await _frames(2)
		if not found and k > 3:
			break


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()


## Diagnosi: catena dei figli con la larghezza minima più grande (per scovare chi spinge fuori la finestra).
func _chain(n: Node) -> void:
	var dn: Control = n as Control
	var chain := ""
	for d in 14:
		var best: Control = null
		var bm := -1.0
		for c in dn.get_children():
			if c is Control and (c as Control).visible and (c as Control).get_combined_minimum_size().x > bm:
				bm = (c as Control).get_combined_minimum_size().x
				best = c
		if best == null:
			break
		chain += " > %s[%s](%s,%d)" % [best.get_class(), best.name, str(best.get("text")).left(20) if best.get("text") != null else "", int(bm)]
		dn = best
	print("CHAIN", chain)
