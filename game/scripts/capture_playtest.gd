extends SceneTree
## Giro fotografico del PLAYTEST (audit 118): carica i checkpoint salvati dal bot (qa118_runner) e fotografa la UI vera.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_playtest.gd -- <cartella_out> <cartella_checkpoint> <ckpt1,ckpt2,...> [it|en] [schermate_extra,separate,da,virgola]
## <cartella_checkpoint> = .../qa81_saves (contiene ckpt_<nome>/). Non tocca i salvataggi veri (cartella temporanea in user://).
## Per ogni checkpoint: Riepilogo (con eventuali finestre), Missioni, Combattimento, Eroe + le schermate comparse rispetto al
## checkpoint precedente; poi prova salva -> ricarica e stampa «PT».

const MAIN := "res://src/ui/main/MainScreen.tscn"
const ALWAYS := ["summary", "quests", "combat", "hero"]

var _out := "user://capture_playtest"
var _n := 0
var _seen: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_pt_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 3:
		root.get_node("Settings").call("set_value", "locale", args[3])
	_tour.call_deferred(args)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	var code := OS.execute("import", ["-window", "root", path])
	if code != 0:
		root.get_texture().get_image().save_png(path)
	print("CATTURA ", path, " codice ", code)


var _re: RegEx = null
var _seen_txt: Dictionary = {}


## Cerca testi sospetti (chiavi nude, segnaposto non sostituiti, nan/inf, null) in tutti i controlli visibili.
func _scan_texts(main: Node, label: String) -> void:
	if _re == null:
		_re = RegEx.new()
		_re.compile("UI_[A-Z0-9_]{3,}|\\{[a-z_0-9]+\\}|%[sd]\\b|\\bnan\\b|\\binf\\b|\\bnull\\b|<null>|Object#|\\bNaN\\b")
	for n in main.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var txt := ""
		if c is Label:
			txt = (c as Label).text
		elif c is Button:
			txt = (c as Button).text
		elif c is RichTextLabel:
			txt = (c as RichTextLabel).get_parsed_text()
		if txt.is_empty():
			continue
		if c.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
			txt = TranslationServer.translate(txt)
		var m := _re.search(txt)
		if m != null and not _seen_txt.has(txt):
			_seen_txt[txt] = true
			print("PT TESTO-SOSPETTO [", label, "] ", c.name, ": ", txt.substr(0, 120).replace("\n", " "))


func _press(main: Node, node_name: String) -> bool:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()
		return true
	return false


func _calm(main: Node) -> void:
	if main.has_method("tutorial") and main.call("tutorial").is_showing():
		main.call("tutorial").press_skip_all()
	for k in 60:
		var any := _press(main, "WelcomeGo")
		any = _press(main, "TutorialOk") or any
		any = _press(main, "WbCollect") or any
		if not any:
			break
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _tour(args: Array) -> void:
	var game: Node = root.get_node("Game")
	var ss: Node = root.get_node("SaveService")
	var base: String = args[1]
	var dst := "user://capture_pt_saves"
	DirAccess.make_dir_recursive_absolute(dst)
	var extra: Array = []
	if args.size() > 4:
		extra = str(args[4]).split(",", false)
	for ck in str(args[2]).split(",", false):
		var src := "%s/ckpt_%s" % [base, ck]
		for f in DirAccess.get_files_at(src):
			DirAccess.copy_absolute(src + "/" + f, dst + "/" + f)
		var r: Dictionary = game.call("load_game", 1)
		print("PT carico ", ck, " ok=", r.get("ok"))
		if not bool(r.get("ok", false)):
			continue
		var main: Control = (load(MAIN) as PackedScene).instantiate()
		root.add_child(main)
		await _frames(3)
		await _shot("%s_apertura" % ck)
		main.queue_free()
		await _frames(2)
		root.get_node("Settings").call("set_value", "tutorials", false)
		main = (load(MAIN) as PackedScene).instantiate()
		root.add_child(main)
		await _frames(3)
		await _calm(main)
		root.get_node("Settings").call("set_value", "tutorials", true)
		var ids: Array = main.get("_menu_ids")
		var fresh: Array = []
		for id: String in ids:
			if not _seen.has(id):
				_seen[id] = ck
				fresh.append(id)
		print("PT ", ck, " menu=", ids.size(), " nuove=", fresh)
		var todo: Array = []
		for id in ALWAYS + fresh + extra:
			var sid := str(id).split("@")[0]
			if (ids.has(sid) or str(id) == "run_dungeon" or str(id).begins_with("fight:") or str(id).begins_with("tab:") or str(id) == "press_all" or str(id).begins_with("away:")) and not todo.has(id) and str(id) != "menu":
				todo.append(id)
		for id in todo:
			game.call("_on_step", 5.0)
			if str(id) == "run_dungeon":
				await _run_dungeon(main, ck)
				continue
			if str(id).begins_with("fight:"):
				await _fight(main, ck, str(id))
				continue
			if str(id).begins_with("tab:"):
				await _tab(main, ck, str(id))
				continue
			if str(id).begins_with("away:"):
				await _away(main, ck, float(str(id).split(":")[1]))
				continue
			if str(id) == "press_all":
				await _press_all(main, ck, ids)
				continue
			var parts := str(id).split("@")
			var params := {}
			if parts.size() > 1:
				params["tab"] = parts[1]
			if bool(main.call("show_screen", parts[0], params)):
				await _calm(main)
				main.call("_on_ui_tick")
				_scan_texts(main, "%s/%s" % [ck, id])
				await _shot("%s_%s" % [ck, str(id).replace(":", "_").replace("@", "_")])
			else:
				print("PT show_screen rifiutato: ", id)
		# prova salva -> ricarica
		ss.call("save_now")
		await _frames(30)
		main.queue_free()
		await _frames(2)
		var r2: Dictionary = game.call("load_game", 1)
		print("PT ricarica ", ck, " ok=", r2.get("ok"))
		if extra.has("menu"):
			var start: Control = (load("res://src/ui/start/StartScreen.tscn") as PackedScene).instantiate()
			root.add_child(start)
			await _frames(4)
			await _shot("%s_menu" % ck)
			start.call("show_slots")
			await _shot("%s_slot" % ck)
			start.queue_free()
			await _frames(2)
	quit(0)


## Entra nel primo dungeon disponibile dalla UI vera, lo fa girare e fotografa l'inizio, la metà e la fine.
func _run_dungeon(main: Control, ck: String) -> void:
	var game: Node = root.get_node("Game")
	main.call("show_screen", "dungeon", {})
	await _calm(main)
	var scr: Node = main.call("current_screen")
	var enter := scr.get("_enter_btn") as Button
	print("PT dungeon: scheda=", scr.get("_selected"), " entra_abilitato=", not enter.disabled, " testo=", enter.text)
	await _shot("%s_dungeon_prima" % ck)
	if enter.disabled:
		return
	enter.pressed.emit()
	var combat: Object = game.call("system", "combat")
	var shots := 0
	for i in 400:
		for k in 5:
			game.call("_on_step", 1.0)
		main.call("_on_ui_tick")
		await _frames(1)
		if i in [2, 20, 60] and shots < 3:
			shots += 1
			await _shot("%s_dungeon_corso_%d" % [ck, i])
		if not bool(combat.call("in_dungeon")):
			print("PT dungeon finito dopo ", i * 5, " s")
			break
	await _calm(main)
	await _shot("%s_dungeon_dopo" % ck)


## «fight:<zona>:<mostro>» (mostro vuoto = a caso): avvia lo scontro dalla UI vera, lo lascia girare e fotografa (morte compresa).
func _fight(main: Control, ck: String, spec: String) -> void:
	var game: Node = root.get_node("Game")
	var p := spec.split(":")
	var combat: Object = game.call("system", "combat")
	main.call("show_screen", "combat", {})
	await _calm(main)
	var ok: bool = bool(combat.call("start", p[1], p[2] if p.size() > 2 else ""))
	print("PT fight ", spec, " start=", ok)
	var ndeaths := 0
	for i in 160:
		for k in 5:
			game.call("_on_step", 1.0)
		main.call("_on_ui_tick")
		await _frames(1)
		if i in [1, 12, 40, 100, 159]:
			_scan_texts(main, "%s/fight" % ck)
			await _shot("%s_fight_%d" % [ck, i])
	print("PT fight fine: in_combat=", combat.call("in_combat"))


## «tab:<schermata>:<inizio del testo del pulsante>»: apre la schermata, preme il pulsante col testo e fotografa.
func _tab(main: Control, ck: String, spec: String) -> void:
	var p := spec.split(":")
	main.call("show_screen", p[1], {})
	await _calm(main)
	var want := p[2].to_lower()
	for tc in main.find_children("*", "TabContainer", true, false):
		var tabs := tc as TabContainer
		for i in tabs.get_tab_count():
			if TranslationServer.translate(tabs.get_tab_title(i)).to_lower().begins_with(want):
				tabs.current_tab = i
	for c in main.find_children("*", "Button", true, false):
		var b := c as Button
		if b.is_visible_in_tree() and TranslationServer.translate(b.text).to_lower().begins_with(want):
			b.pressed.emit()
			break
	await _frames(3)
	main.call("_on_ui_tick")
	_scan_texts(main, "%s/%s" % [ck, spec])
	await _shot("%s_tab_%s_%s" % [ck, p[1], want.replace(" ", "_")])


func _state_sig(main: Control) -> String:
	var gs: Node = root.get_node("GameState")
	var cur: Node = main.call("current_screen")
	var overlays := 0
	for w in main.find_children("*", "Window", true, false):
		if (w as Window).visible:
			overlays += 1
	var keep := {}
	for k in ["equipment", "wardrobe", "crates", "unlocks", "loadouts", "titles", "activity", "queue", "tutorial", "modes", "pets", "factions", "orders", "farming", "quests", "run", "potions", "buffs"]:
		keep[k] = gs.data.get(k)
	var st: Node = root.get_node("Settings")
	return "%d|%d|%s|%d|%d" % [str(keep).hash(), str(st.get("_values")).hash(), cur.name if cur != null else "", main.get_child_count(), overlays]


## Preme OGNI pulsante visibile e attivo di ogni schermata (una per volta, schermata ricaricata ogni volta) e cerca:
## errori di script (nel log), pulsanti che non cambiano nulla («NOOP», da rivedere a mano).
func _press_all(main: Control, ck: String, ids: Array) -> void:
	var game: Node = root.get_node("Game")
	var total := 0
	var noop := 0
	for sid in ids:
		var n := 0
		var idx := 0
		while idx < 60:
			if not bool(main.call("show_screen", sid, {})):
				break
			await _frames(3)
			var btns: Array = []
			for c in main.find_children("*", "Button", true, false):
				var b := c as Button
				if b.is_visible_in_tree() and not b.disabled and b.get_parent() != null and not _is_chrome(main, b):
					btns.append(b)
			if idx >= btns.size():
				break
			var b: Button = btns[idx]
			var label := TranslationServer.translate(b.text)
			if label.to_lower().begins_with("esci") and str(sid) == "settings":
				idx += 1
				continue
			var before := _state_sig(main)
			var bname := str(b.name)
			var is_toggle := b.toggle_mode
			b.pressed.emit()
			await _frames(3)
			var after := _state_sig(main)
			total += 1
			if before == after and not is_toggle:
				noop += 1
				print("PT NOOP [", sid, "] ", bname, " «", label.substr(0, 50).replace("\n", " "), "»")
			idx += 1
			n += 1
			for k in 4:
				_press(main, "TutorialOk")
				_press(main, "WelcomeGo")
				for d in main.find_children("*", "ConfirmationDialog", true, false):
					(d as Window).hide()
	print("PT press_all fine: pulsanti premuti=", total, " senza effetto=", noop)


## Pulsanti della cornice (menù laterale, barra in alto): non si contano come pulsanti della schermata.
func _is_chrome(main: Control, b: Button) -> bool:
	var cur: Node = main.call("current_screen")
	return cur == null or not cur.is_ancestor_of(b)


## «away:<ore>»: simula un'assenza (percorso vero del Bentornato) e fotografa la finestra e il Riepilogo dopo.
func _away(main: Control, ck: String, hours: float) -> void:
	var game: Node = root.get_node("Game")
	main.call("show_screen", "summary", {})
	await _calm(main)
	game.call("_on_long_gap", hours * 3600.0)
	await _frames(6)
	_scan_texts(main, "%s/away" % ck)
	await _shot("%s_bentornato_%dh" % [ck, int(hours)])
	_press(main, "WbCollect")
	await _frames(4)
	await _shot("%s_dopo_bentornato" % ck)
