extends SceneTree
## Giro fotografico POLISH FINALE (testi lunghi e schermate nuove: Missioni, Talenti, Deposito, Guardaroba, Album,
## Compendio, Fazioni, Luoghi Segreti, Officina Casse, Dungeon con Incursioni/Boss/Breccia, Prestigio con Ere/Prove). Stampa TRUNC per i testi troncati.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_polish.gd -- <cartella> <it|en> [filtro_schermate_separate_da_virgola]

const SCREENS := ["quests", "talents", "bank", "wardrobe", "album", "compendium", "factions", "secrets", "vault_workshop", "dungeon", "prestige", "skill:woodcutting", "combat"]
const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://polish"
var _n := 0
var _only: PackedStringArray = []
var _tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://polish_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
		_tag = args[1]
	if args.size() > 2:
		_only = args[2].split(",")
		if _only.has("all"):
			_only = PackedStringArray()
	if DisplayServer.window_get_size().x >= 1500:
		# stretch "canvas_items" + scala intera: a 1080p la scala è 1x, cioè area utile di 1920x1080 (get_texture() darebbe 1280x720)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _shot(name: String, frames: int = 6) -> void:
	await _frames(frames)
	var tc: Node = root.find_child("Toasts", true, false)
	if tc != null:
		for c in tc.get_children():
			c.free()
	await _frames(2)
	_n += 1
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s_%dx%d.png" % [_out, name, _tag, img.get_width(), img.get_height()]
	img.save_png(path)
	print("CATTURA ", path)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var reuse := FileAccess.file_exists("user://polish_saves/slot_1.sav") and OS.get_cmdline_user_args().has("reuse")
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
		await _build(game)
	root.get_node("Settings").call("set_value", "tutorials", false)
	main.call("build_menu")
	await _dismiss(main)
	for sid in SCREENS:
		if not _want(sid):
			continue
		await _go(main, game, sid)
		_overflow(main, sid)
		_trunc(main, sid)
		await _shot(sid.replace(":", "_"))
	if _want("extra"):
		await _extras(main, game)
	quit(0)


func _build(game: Node) -> void:
	var bot = load("res://scripts/bot_player.gd").new(game.get("sim"), func(dt: float) -> void: game.call("_on_step", dt))
	var t0 := Time.get_ticks_msec()
	bot.call("run_until_quest", "main_c1_q6", 3.0 * 3600.0)
	print("bot ", (Time.get_ticks_msec() - t0), " ms")
	_cheat(game)
	_cheat_more(game)
	game.call("system", "unlock")
	print("salvo ", root.get_node("SaveService").call("save_now"))


## Stato avanzato per le schermate nuove: capitoli fatti, fazioni, Luoghi Segreti, Ere, Prove, Stelle.
func _cheat_more(game: Node) -> void:
	var done: Array = game.get("sim").ctx.state.quests.done
	for q in root.get_node("DataRegistry").call("table", "quests"):
		var id := str(q.id)
		if id.begins_with("main_c1_") or id.begins_with("main_c2_") or id.begins_with("main_c3_"):
			if not done.has(id):
				done.append(id)
	var un: Object = game.call("system", "unlock")
	for t in ["secrets", "world_bosses", "rift", "raids", "factions", "eras", "trials", "skill_prestige"]:
		un.call("grant", "feature:" + t)
	var bank: Object = game.call("system", "bank")
	bank.call("add", "map_fragment", 30, "qa")
	var mk: Object = game.call("system", "market")
	mk.call("add_reputation", "merchant_league", 1300)
	var pr: Object = game.call("system", "prestige")
	pr.state["era_max"] = 3
	var comp: Object = game.call("system", "compendium")
	for p in ["pet_skill_woodcutting", "pet_skill_mining"]:
		comp.call("found_pet", p)
	for t in ["title_firmament", "title_vaultbreaker"]:
		comp.call("grant_title", t)


func _go(main: Node, game: Node, sid: String) -> void:
	if sid == "combat":
		var cb: Object = game.call("system", "combat")
		cb.call("start", _first_zone(cb))
		for i in 150:
			game.call("_on_step", 0.1)
	main.call("show_screen", sid)
	if sid == "combat":
		for i in 40:
			game.call("_on_step", 0.1)
			if i % 8 == 0:
				await _frames(1)
	await _frames(4)
	main.call("_on_ui_tick")
	await _dismiss(main)


func _first_zone(cb: Object) -> String:
	var best := ""
	for z in cb.call("zones"):
		if cb.call("zone_unlocked", z.id):
			best = z.id
	return best


func _cheat(game: Node) -> void:
	var un: Object = game.call("system", "unlock")
	for t in ["bounties", "collectors_challenge", "combat", "constellations", "crates", "eras", "estate", "expeditions", "factions", "golden_contract", "market", "mercenaries", "orders", "prestige", "refinery", "rift", "skill_prestige", "tradeup", "trials", "wardrobe", "world_bosses"]:
		un.call("grant", "feature:" + t)
	var bank: Object = game.call("system", "bank")
	bank.call("add", "gold", 5000000, "qa")
	for k in ["key_t1", "key_t2", "key_t3"]:
		bank.call("add", k, 40, "qa")
	for f in ["food_rabbit", "food_bleak"]:
		bank.call("add", f, 30, "qa")
	var cb: Object = game.call("system", "combat")
	cb.call("set_food", 0, "food_rabbit")
	# talenti: spende qualche punto
	var hb: Object = cb.get("build")
	for id in ["warrior_general_01", "warrior_general_02"]:
		pass
	var spent := 0
	for t in hb.call("talent_nodes"):
		if spent >= 7:
			break
		if str(t.branch) == "general" and hb.call("rank_up", t.id):
			spent += 1
	# Tenuta (sblocca gli edifici come farebbero le missioni)
	var done: Array = game.get("sim").ctx.state.quests.done
	for bd in root.get_node("DataRegistry").call("table", "estate_buildings"):
		var uq := str(bd.get("unlock", {}).get("quest", ""))
		if uq != "" and not done.has(uq):
			done.append(uq)
	var es: Object = game.call("system", "estate")
	var lv := {"cottage": 8, "sawmill": 5, "mine_shaft": 4, "fishery": 3, "fields": 3, "ranch": 0, "shopfront": 3, "warehouse": 4, "private_vault": 0, "academy": 4, "tavern": 4}
	for bid in lv:
		var e: Dictionary = es.call("_entry", bid)
		e["level"] = lv[bid]
	es.state.settlers = int(es.call("settler_cap"))
	es.state.pantry = 800.0
	es.state.prosperity = 1200.0
	for bid in ["sawmill", "mine_shaft", "fishery", "fields"]:
		var opts: Array = es.call("product_options", bid)
		if not opts.is_empty():
			es.call("set_product", bid, str(opts[0].id if opts[0] is Dictionary else opts[0]))
	# mercenari + apprendisti
	var mc: Object = game.call("system", "mercenaries")
	mc.call("_refill_board")
	for c in mc.call("candidates").duplicate():
		mc.call("hire", c.uid)
	var ap: Object = game.call("system", "apprentices")
	var sk: Object = game.call("system", "skills")
	sk.call("add_xp", "woodcutting", 3000000.0)
	sk.call("add_xp", "mining", 3000000.0)
	sk.call("add_xp", "fishing", 60000.0)
	ap.call("assign", 0, "wc_pine")
	ap.call("assign", 1, "mine_copper")
	# Casse: aperte per riempire Album e Guardaroba
	var cr: Object = game.call("system", "crates")
	for c in ["crate_millbrook", "crate_saltreach", "crate_ironroot"]:
		cr.call("grant_crate", c, 12)
	cr.call("grant_crate", "capsule_banners", 2)
	for c in ["crate_millbrook", "crate_saltreach"]:
		cr.call("open", c, 7, false)
	for sl in cr.call("wardrobe_slots"):
		pass
	for inst in bank.call("list_instances"):
		if str(inst.get("kind", "")) == "skin":
			cr.call("equip", str(inst.uid))
	# Prestigio
	var pr: Object = game.call("system", "prestige")
	pr.call("_add_dust", 4000)
	pr.call("do_star", "woodcutting")
	for nd in pr.call("nodes"):
		if str(pr.call("can_buy_node", nd.id)) == "":
			pr.call("buy_node", nd.id, 1)
	# Mercato: qualche vendita per dare storia
	pass


func _cur(main: Node) -> Node:
	return main.get("_current")


func _extras(main: Node, game: Node) -> void:
	# Compendio (schede), Prestigio (Ere, Prove), Dungeon (Incursioni, Boss mondiali, Breccia)
	main.call("show_screen", "compendium")
	await _frames(4)
	var cs: Node = _cur(main)
	for i in [1, 2, 3]:
		cs.get("_tabs").set("current_tab", i)
		await _frames(6)
		_trunc(main, "compendio_%d" % i)
		await _shot("compendio_scheda_%d" % i)
	main.call("show_screen", "prestige")
	await _frames(4)
	var pr: Node = _cur(main)
	var tabs: TabContainer = pr.get("_tabs")
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await _frames(8)
		_trunc(main, "prestigio_%d" % i)
		await _shot("prestigio_scheda_%d" % i)
	tabs.current_tab = 1
	await _frames(6)
	pr.call("_on_node_selected", "c_so_pity")
	await _frames(8)
	_trunc(main, "costellazione_lunga")
	await _shot("prestigio_nodo_lungo")
	# Deposito con una finitura dalla descrizione lunga selezionata
	main.call("show_screen", "bank")
	await _frames(4)
	var bscr: Node = _cur(main)
	var bank: Object = game.call("system", "bank")
	var best_uid := ""
	var best_len := 0
	for inst in bank.call("list_instances"):
		var d: Dictionary = root.get_node("DataRegistry").call("item", str(inst.get("def_id", inst.get("def", ""))))
		var ln := str(root.get_node("Loc").call("t", d.get("desc", {}))).length()
		if ln > best_len:
			best_len = ln
			best_uid = str(inst.uid)
	print("istanza con descrizione piu lunga: ", best_uid, " ", best_len)
	if best_uid != "":
		bscr.set("_selected", best_uid)
		bscr.call("_mark_dirty")
		await _frames(6)
		_trunc(main, "deposito_descrizione_lunga")
		await _shot("deposito_descrizione_lunga")
	main.call("show_screen", "dungeon")
	await _frames(4)
	var ds: Node = _cur(main)
	for t in ["raids", "worldboss", "rift"]:
		ds.call("_set_tab", t)
		await _frames(8)
		_trunc(main, "dungeon_" + t)
		await _shot("dungeon_" + t)
	main.call("show_screen", "bank")
	await _frames(4)


func _trunc(main: Node, sid: String) -> void:
	var host := main.get("_host") as Control
	if host == null or host.get_child_count() == 0:
		return
	var stack: Array = [host.get_child(host.get_child_count() - 1)]
	var out := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var ctl := n as Control
		if ctl == null or not ctl.is_visible_in_tree():
			continue
		var txt := ""
		var wrap := false
		var pad := 0.0
		if ctl is Label:
			txt = ctl.atr((ctl as Label).text)
			wrap = (ctl as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
		elif ctl is Button and not (ctl is OptionButton):
			txt = ctl.atr((ctl as Button).text)
			pad = 20.0
			wrap = (ctl as Button).autowrap_mode != TextServer.AUTOWRAP_OFF
		if txt == "" or wrap or ctl.size.x <= 0:
			continue
		var f := ctl.get_theme_font("font")
		var fs := ctl.get_theme_font_size("font_size")
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w + pad > ctl.size.x + 1.5:
			out += 1
			if out <= 14:
				print("TRUNC ", sid, " ", ctl.get_class(), " ", ctl.name, " testo=", int(w), " box=", int(ctl.size.x), " '", txt.left(70), "'")
	print("TRUNC_TOT ", sid, " ", out)


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


## Elenca i controlli visibili che escono dall'area contenuto (sotto il registro / oltre il bordo).
func _overflow(main: Node, sid: String) -> void:
	var host := main.get("_host") as Control
	if host == null or host.get_child_count() == 0:
		return
	var sc: Control = host.get_child(host.get_child_count() - 1)
	var lim := host.get_global_rect()
	var out := 0
	var stack: Array = [sc]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var ctl := n as Control
		if ctl == null or not ctl.is_visible_in_tree() or ctl == sc:
			continue
		var r := ctl.get_global_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		if r.end.x > lim.end.x + 1.0 and (ctl is Button or ctl is Label or ctl is ProgressBar or ctl is OptionButton or ctl is RichTextLabel):
			out += 1
			if out <= 12:
				print("OVERFLOW ", sid, " ", ctl.get_class(), " ", ctl.name, " fine=", int(r.end.x), " limite=", int(lim.end.x), " ", str(ctl.get("text")).left(30))
	print("OVERFLOW_TOT ", sid, " ", out, " host=", lim)


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
	print("popup chiusi")


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()
