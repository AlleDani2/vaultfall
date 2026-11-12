extends SceneTree
## Catture della fase F4 del progetto di interfaccia (docs/ui_redesign/07, F4): menù laterale con segnali a tre tipi e gruppi.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase4.gd -- <cartella> [it|en]
## Stato SIMULATO «a metà gioco» (il checkpoint del bot a 60 h non è nel repository): partita nuova seme 4242, tutto sbloccato,
## molte mansioni a livello alto (talenti da scegliere), casse apribili, una missione da riscattare, un raccolto pronto, una
## Commessa consegnabile. Stampa anche i segnali PRIMA (SidebarBadges.counts(): i vecchi pallini numerici) e DOPO (signals()).
## Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase4"
var _main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase4_saves")
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


func _report(tag: String) -> void:
	var badges: GDScript = load("res://src/ui/main/SidebarBadges.gd")
	var before: Dictionary = badges.call("counts")
	var nums := 0
	for id in before:
		nums += 1
	var after: Dictionary = badges.call("signals", _main.get("_sidebar").call("_signal_opts"))
	var c := {"count": 0, "dot": 0, "danger": 0}
	for id in after:
		c[str(after[id].kind)] += 1
	print("SEGNALI ", tag, " PRIMA: ", nums, " pallini numerici ", before, " | DOPO: ", c, " ", JSON.stringify(after))


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	var sk: Object = game.call("system", "skills")
	for s in root.get_node("DataRegistry").call("table", "skills"):
		var st: Dictionary = sk.state.get(str(s.id), {})
		if not st.is_empty():
			st["level"] = 45
	var q: Object = game.call("system", "quests")
	var qid: String = q.call("current_main")
	var pr: Array = []
	for o in q.call("quest_def", qid).objectives:
		pr.append(q.call("target_of", o))
	q.state.progress[qid] = pr
	var bank: Object = game.call("system", "bank")
	var cs: Object = game.call("system", "crates")
	bank.call("add", "crate_millbrook", 3, "cap")
	var key: Variant = cs.call("crate_def", "crate_millbrook").get("key")
	if key != null:
		bank.call("add", str(key), 3, "cap")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm(main)
	main.call("build_menu")
	# mansioni usate di recente
	for id in ["skill:mining", "skill:fishing", "skill:smithing", "skill:woodcutting", "skill:cooking"]:
		main.call("show_screen", id, {"skill": id.substr(6)})
	sk.call("start", "wc_pine")
	for i in 5:
		game.call("_on_step", 0.1)
	main.call("show_screen", "summary")
	var sb: Object = main.get("_sidebar")
	# 1) tutto aperto, «Tutte» chiuse: i segnali (numeri ambra, puntini) e le Recenti
	root.get_node("Settings").call("set_value", "sidebar_groups_closed", ["*"])
	main.call("_update_slow")
	_report("aperti")
	await _shot("menu_gruppi_aperti")
	# 2) «Tutte» aperte
	sb.call("set_all_skills_open", true)
	await _shot("menu_tutte_aperte")
	sb.call("set_all_skills_open", false)
	# 3) predefinito per finestra bassa: Città, Caveau e Progresso chiusi (somma e puntino sulle intestazioni)
	root.get_node("Settings").call("set_value", "sidebar_groups_closed", ["city", "vault", "progress", "*"])
	main.call("_update_slow")
	_report("chiusi")
	await _shot("menu_gruppi_chiusi")
	# 4) rosso: Deposito pieno, gruppo Città chiuso (il rosso sale sull'intestazione)
	var i := 0
	while not bank.call("is_full"):
		bank.state.stacks["zz_fill_%d" % i] = 1
		i += 1
	main.call("_update_slow")
	_report("rosso")
	await _shot("menu_rosso_citta_chiusa")
	# 5) Skills chiuso con l'attività in corso: riga fissa e segno
	root.get_node("Settings").call("set_value", "sidebar_groups_closed", ["skills", "adventure", "city", "vault", "progress", "*"])
	main.call("_update_slow")
	await _shot("menu_tutto_chiuso")
	quit()
