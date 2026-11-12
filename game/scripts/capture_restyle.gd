extends SceneTree
## Catture del restyling UX (110): schermate di Tenuta, Gilda, Prestigio, Dungeon, Talenti, Compendio, Taglie, Eventi...
## Ogni schermata: vista iniziale + ogni scheda + pagine di scorrimento (max 3).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_restyle.gd -- <cartella> <it|en> <vuoto|pieno> [id_schermata,...]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"
const SCREENS := ["hero", "estate", "guild", "prestige", "dungeon", "talents", "compendium", "bounty", "events", "coop_guild", "coop_lobby", "secrets", "factions"]
const FEATURES := ["combat", "crates", "estate", "expeditions", "factions", "market", "mercenaries", "orders", "prestige", "constellations", "skill_prestige", "talents", "bounties", "wardrobe", "secrets", "coop"]
var _out := "user://restyle"
var _tag := ""
var _mode := "pieno"
var _only: PackedStringArray = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://restyle_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 2:
		_mode = args[2]
	if args.size() > 3:
		_only = args[3].split(",")
	if DisplayServer.window_get_size().x >= 1500:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	var tc: Node = root.find_child("Toasts", true, false)
	if tc != null:
		for c in tc.get_children():
			c.free()
	for b in root.find_children("*", "FxBanner", true, false):
		b.free()
	await _frames(2)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s_%s_%d.png" % [_out, name, _mode, _tag, img.get_width()]
	img.save_png(path)
	print("CATTURA ", path)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	_tag = str(root.get_node("Settings").call("get_value", "locale"))
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 20261023)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	await _dismiss(main)
	if _mode == "pieno":
		_build(game)
	else:
		_grant(game)
	main.call("build_menu")
	await _dismiss(main)
	main.call("_update_slow")
	for sid in SCREENS:
		if _only.size() > 0 and not _only.has(sid):
			continue
		if not main.call("show_screen", sid):
			print("NON APRIBILE ", sid)
			continue
		await _frames(6)
		await _dismiss(main)
		await _shot(sid)
		var scr: Node = main.get("_current")
		if scr.has_method("_set_tab") and sid == "dungeon":
			for t in ["raids", "worldboss", "rift"]:
				scr.call("_set_tab", t)
				await _frames(4)
				await _shot("%s_%s" % [sid, t])
				await _scroll_pages(scr, "%s_%s" % [sid, t])
			scr.call("_set_tab", "dungeon")
		var tabs := scr.find_children("*", "TabContainer", true, false)
		for t in tabs:
			var tc := t as TabContainer
			if not tc.is_visible_in_tree():
				continue
			for i in tc.get_tab_count():
				tc.current_tab = i
				await _frames(4)
				await _shot("%s_tab%d" % [sid, i])
				await _scroll_pages(scr, "%s_tab%d" % [sid, i])
		await _scroll_pages(scr, sid)
	quit(0)


func _scroll_pages(scr: Node, name: String) -> void:
	var sc: ScrollContainer = null
	var n: Node = scr
	while n != null and sc == null:
		if n is ScrollContainer:
			sc = n
		n = n.get_parent()
	if sc == null or sc.get_v_scroll_bar().max_value <= sc.size.y + 8:
		sc = null
		for c in scr.find_children("*", "ScrollContainer", true, false):
			if (c as Control).is_visible_in_tree() and (c as ScrollContainer).get_v_scroll_bar().max_value > (c as Control).size.y + 8:
				sc = c
				break
	if sc == null:
		return
	var vb := sc.get_v_scroll_bar()
	var page := int(sc.size.y) - 40
	for p in 3:
		var nxt := (p + 1) * page
		if p > 0 and nxt >= vb.max_value - sc.size.y + 40 + page:
			break
		sc.scroll_vertical = nxt
		await _frames(3)
		await _shot("%s_scroll%d" % [name, p + 1])
	sc.scroll_vertical = 0


func _dismiss(main: Node) -> void:
	for k in 40:
		var found := false
		for nm in ["TutorialOk", "WelcomeGo", "WbCollect"]:
			if main.find_child(nm, true, false) != null:
				_press(main, nm)
				found = true
		await _frames(2)
		if not found and k > 2:
			break


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()


func _grant(game: Node) -> void:
	var un: Object = game.call("system", "unlock")
	for t in FEATURES:
		un.call("grant", "feature:" + t)
	un.call("grant", "skill:hero")
	un.call("grant", "dungeon:cursed_granary")
	for t in ["world_bosses", "rift", "raids"]:
		un.call("grant", "feature:" + t)


func _build(game: Node) -> void:
	var bot = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	bot.call("run_until_quest", "main_c1_q6", 3.0 * 3600.0)
	_grant(game)
	var data: Dictionary = root.get_node("GameState").get("data")
	data.skills["hero"] = {"xp": 0.0, "level": 25, "record_level": 25, "stars": 0, "perks": {}, "unlocked": true}
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
	var bank: Object = game.call("system", "bank")
	bank.call("add_gold", 50000)
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
