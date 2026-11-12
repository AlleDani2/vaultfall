extends SceneTree
## Strumenti comuni dei playtest del novizio (resoconto 121): clic VERI (eventi del mouse nella finestra, si vede se un
## controllo è coperto), pulsanti per testo tradotto, catture, diario. Usato da novice_ui.gd e novice_coop.gd.

var out := "/tmp/novice"
var loc := "it"
var _n := 0
var _diary := PackedStringArray()
var _main: Control
var _shots_taken := {}
var _problems: Array = []
var _tag := "nv"
var shared := ""


# ------------------------------------------------------------------ utilità

func frames(n: int) -> void:
	for i in n:
		await process_frame


func say(s: String) -> void:
	var line := "[t=%6.0fs] %s" % [float(root.get_node("GameState").data.get("stats", {}).get("playtime_s", 0.0)) if root.get_node("GameState").active else 0.0, s]
	_diary.append(line)
	print(line)


func problem(s: String) -> void:
	_problems.append(s)
	say("PROBLEMA: " + s)


func shot(name: String) -> void:
	await frames(6)
	_n += 1
	var path := "%s/%03d_%s.png" % [out, _n, name]
	root.get_texture().get_image().save_png(path)
	say("cattura " + path.get_file())


func shot_once(key: String, name: String) -> void:
	if _shots_taken.has(key):
		return
	_shots_taken[key] = true
	await shot(name)


func save_diary() -> void:
	var f := FileAccess.open(out + "/diario.txt", FileAccess.WRITE)
	f.store_string("\n".join(_diary) + "\n\nPROBLEMI:\n" + "\n".join(PackedStringArray(_problems.map(func(x): return str(x)))) + "\n")
	f.close()


func game() -> Node:
	return root.get_node("Game")


func system(id: String) -> Object:
	return game().call("system", id)


func uns() -> Array:
	return root.get_node("GameState").data.unlocks


## Clic VERO: muove il mouse sul centro del controllo, controlla che sia davvero il controllo sotto il mouse (non coperto dal
## velo o dalla scheda del tutorial) e preme/rilascia il tasto sinistro. Ritorna false se coperto o non cliccabile.
func click(c: Control, why: String = "") -> bool:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return false
	TutorialTargets.reveal(c)
	await frames(2)
	if not c.is_visible_in_tree():
		return false
	var r := c.get_global_rect()
	var vp := root.get_visible_rect()
	var pos := r.get_center()
	pos.x = clampf(pos.x, 1.0, vp.size.x - 2.0)
	pos.y = clampf(pos.y, 1.0, vp.size.y - 2.0)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	root.push_input(mm, true)
	await frames(2)
	var hov := root.gui_get_hovered_control()
	var ok := hov != null and (hov == c or c.is_ancestor_of(hov))
	if not ok:
		var who := str(hov.get_path()) if hov != null else "nessuno"
		var extra := ""
		if hov != null:
			extra = " [bersaglio %s centro %s; coperto da %s]" % [str(r), str(pos), str(hov.get_global_rect())]
		problem("clic su «%s» (%s) COPERTO da %s%s" % [_label_of(c), why, who, extra])
		return false
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mb, true)
		await frames(1)
	await frames(2)
	return true


func shown(c: Control) -> String:
	var t: String = c.get("text") if c.get("text") != null else ""
	return t if c.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else c.tr(t)


func _label_of(c: Control) -> String:
	return shown(c) if c is Button else str(c.name)


func press_key(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		root.push_input(k)
		await frames(1)
	await frames(2)


## Pulsanti visibili e attivi sotto un nodo (per testo o per gruppo).
func buttons(under: Node, pred: Callable = Callable()) -> Array:
	var res: Array = []
	_collect(under, res, pred)
	return res


func _collect(n: Node, res: Array, pred: Callable) -> void:
	if n is Button and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
		if not pred.is_valid() or pred.call(n):
			res.append(n)
	for c in n.get_children(true):         # anche i figli interni: i pulsanti OK/Annulla di un dialogo sono interni
		_collect(c, res, pred)


func tr_en(key: String) -> String:
	return str(TranslationServer.translate(key))


func cur() -> String:
	return str(_main.get("current_id")) if _main != null else ""


func goal_panel() -> Node:
	return _main.find_child("GoalPanel", true, false)


func goal_text() -> String:
	var g: Object = goal_panel()
	if g == null or not g.visible:
		return "(nessun obiettivo)"
	var d: Dictionary = g.call("goal")
	return "%s | %s | vai=%s" % [str(d.get("title", "")), str(d.get("how", "")), str((d.get("target", {}) as Dictionary).get("screen", "-"))]


func overlay_btn() -> Button:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"OverlayHost":
			for n in ["WelcomeGo", "TutorialOk", "WbCollect"]:
				var b := c.find_child(n, true, false) as Button
				if b != null and b.is_visible_in_tree():
					return b
	return null


## Avanza il tempo di gioco di `sim_s` secondi simulati con passi da 0,1 s (come il Clock, ma senza dipendere dal tempo reale:
## la macchina di prova è lenta e un salto di frame lungo verrebbe scambiato per assenza). Un frame ogni 20 passi per la UI.
func run_sim(sim_s: float) -> void:
	var g := game()
	var steps := int(sim_s / 0.1)
	for i in steps:
		g.call("_on_step", 0.1)
		if i % 20 == 19:
			await process_frame


const START := "res://src/ui/start/StartScreen.tscn"


## Dal menù iniziale con clic veri: «Nuova partita» -> slot 1 -> MainScreen pronta. true se riuscito.
func start_new_game_ui() -> bool:
	for sl in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", sl)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	current_scene = start
	await frames(10)
	await shot("menu_iniziale")
	await click(start.find_child("NewGameButton", true, false), "Nuova partita")
	await frames(4)
	var nb2 := buttons(start.find_child("Slots", true, false), func(b): return shown(b) == tr_en("UI_NEW_GAME"))
	if nb2.is_empty():
		problem("nessun pulsante «Nuova partita» negli slot")
		return false
	await click(nb2[0], "Nuova partita slot 1")
	for i in 80:
		await frames(5)
		_main = current_scene
		if _main != null and _main.get("current_id") != null:
			break
	if _main == null or _main.get("current_id") == null:
		problem("MainScreen non caricata")
		return false
	await frames(10)
	return true


## Un clic sulla voce del menù laterale con la chiave `menu:<id>` (la voce giusta, come fa il novizio).
func open_menu(screen_id: String) -> bool:
	var b := TutorialTargets.find(self, "menu:" + screen_id)
	if b == null:
		# la voce sta in un gruppo richiuso (finestre basse: Città, Caveau e Progresso partono chiusi): si apre l'intestazione
		# con un clic vero, come farebbe il giocatore, e si riprova
		var sb: Object = _main.get("_sidebar") if _main != null else null
		var gid := str((sb.get("_entry_group") as Dictionary).get(screen_id, "")) if sb != null and sb.get("_entry_group") is Dictionary else ""
		var hb: Button = sb.call("header_button", gid) as Button if sb != null and gid != "" else null
		if hb != null:
			await click(hb, "intestazione del gruppo " + gid)
			await frames(4)
			b = TutorialTargets.find(self, "menu:" + screen_id)
	if b == null:
		problem("voce di menù «%s» non trovata o non visibile" % screen_id)
		return false
	var ok := await click(b, "menu " + screen_id)
	await frames(8)
	if cur() != screen_id:
		problem("clic su menu «%s» ma la schermata è %s" % [screen_id, cur()])
		return false
	return ok


## Tutti i testi visibili (Label, Button, RichTextLabel) sotto un nodo, tradotti come li vede il giocatore.
func visible_texts(under: Node) -> PackedStringArray:
	var res := PackedStringArray()
	_texts(under, res)
	return res


func _texts(n: Node, res: PackedStringArray) -> void:
	var c := n as Control
	if c != null and not c.is_visible_in_tree():
		return
	if n is Label or n is Button or n is CheckBox or n is RichTextLabel:
		var t: String = str(n.get("text")) if n.get("text") != null else ""
		if n is Control and (n as Control).auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED and not t.is_empty():
			t = (n as Control).tr(t)
		if not t.is_empty():
			res.append(t)
	for ch in n.get_children():
		_texts(ch, res)


## Segnala testi non tradotti (chiavi UI_ rimaste) sotto un nodo.
func check_texts(under: Node, where: String) -> void:
	for t in visible_texts(under):
		if t.begins_with("UI_") or t.contains("{") and t.contains("}"):
			problem("%s: testo non risolto «%s»" % [where, t.left(80)])


func sync_set(name: String, content: String = "1") -> void:
	var f := FileAccess.open(shared + "/" + name, FileAccess.WRITE)
	f.store_string(content)
	f.close()


## Aspetta un file di sincronizzazione scritto dall'altro processo (ritorna il contenuto, "" se scaduto).
func sync_wait(name: String, timeout_s: float = 120.0) -> String:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < timeout_s:
		if FileAccess.file_exists(shared + "/" + name):
			await frames(3)
			return FileAccess.get_file_as_string(shared + "/" + name)
		await frames(6)
	problem("sincronizzazione scaduta: manca «%s»" % name)
	return ""


## Digitazione VERA in un campo di testo (clic per dargli il focus, poi un evento tastiera per carattere).
func type_text(le: Control, text: String) -> bool:
	if not await click(le, "campo di testo"):
		return false
	if le is LineEdit:
		(le as LineEdit).select_all()
		(le as LineEdit).delete_char_at_caret()
	for ch in text:
		for pressed in [true, false]:
			var k := InputEventKey.new()
			k.keycode = ch.unicode_at(0) as Key
			k.unicode = ch.unicode_at(0)
			k.pressed = pressed
			root.push_input(k)
		await process_frame
	await frames(2)
	return true
