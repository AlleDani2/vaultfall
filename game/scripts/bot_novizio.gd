extends SceneTree
## Bot NOVIZIO (QA 95). Gioca SOLO attraverso la UI vera: menù iniziale -> MainScreen, pulsanti premuti con eventi
## mouse (Viewport.push_input), tasti scorciatoia con eventi tastiera. Il tempo di gioco avanza a passi da 0,1 s
## chiamando GM._on_step (come farebbe Clock), poi la UI gira a 10 Hz come nel gioco vero.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/bot_novizio.gd -- <cartella_out> <it|en> [ore_novizio=3] [ore_casuali=10] [seme=1]
## Fasi: A) novizio che segue missioni e suggerimenti; B) scelte casuali di menù; C) controlli fissi (scorciatoie,
## Tab/frecce, perdite di nodi, tempi di aggiornamento, salva/riprendi). I difetti finiscono in <out>/findings.json.

const START = "res://src/ui/start/StartScreen.tscn"
const MAIN = "res://src/ui/main/MainScreen.tscn"
const STEP_S = 0.1
const SIM_STEP_BATCH = 50                 # passi da 0,1 s tra due occhiate (5 s di gioco)
const SLOW_MS = 16.0

var out_dir = "user://novizio"
var locale = "it"
var hours_a = 3.0
var hours_b = 10.0
var seed_v = 1
var lib
var brain: Object
var main: Control
var findings: Dictionary = {}
var trail: PackedStringArray = []
var stats: Dictionary = {"clicks": 0, "clicks_disabled": 0, "screens": {}, "noop": 0}
var timings: Dictionary = {}                # id schermata -> [ms...]
var samples: Array = []                      # memoria / nodi / orfani nel tempo
var quest_log: Array = []
var rng = RandomNumberGenerator.new()
var GS
var SET
var GM
var CLK
var SAVE
var _wall0 = 0
var _res = ""
var fast_until = ""        # opzionale: porta la partita a questa missione con il bot diretto (solo per sviluppare/provare stati avanzati)
var _last_progress_t = 0.0
var _seen_text: Dictionary = {}


func _initialize() -> void:
	GS = root.get_node("GameState")
	SET = root.get_node("Settings")
	GM = root.get_node("Game")
	CLK = root.get_node("Clock")
	SAVE = root.get_node("SaveService")
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		locale = args[1]
	if args.size() > 2:
		hours_a = float(args[2])
	if args.size() > 3:
		hours_b = float(args[3])
	if args.size() > 4:
		seed_v = int(args[4])
	if args.size() > 5:
		fast_until = args[5]
	rng.seed = seed_v
	DirAccess.make_dir_recursive_absolute(out_dir)
	lib = load("res://scripts/novizio_lib.gd").new(self)
	SAVE.set("save_dir", "user://novizio_saves")
	SAVE.set("autosave_enabled", true)
	SET.call("set_value", "locale", locale)
	_res = "%dx%d" % [root.size.x, root.size.y]
	_run.call_deferred()


# ------------------------------------------------------------------ registro dei difetti

func note(kind: String, where: String, text: String, sev: String = "medio") -> void:
	var key = "%s|%s|%s" % [kind, where, text]
	if findings.has(key):
		findings[key].count += 1
		return
	var shot_path = ""
	if shots < 60 and kind in ["sovrapposti", "fuori_schermo", "coperto", "schermata_vuota", "testo_lingua_sbagliata", "chiave_nuda", "pulsante_senza_effetto"]:
		shots += 1
		shot_path = "shot_%02d_%s.png" % [shots, kind]
		var img = root.get_texture().get_image()
		if img != null:
			img.save_png(out_dir.path_join(shot_path))
	findings[key] = {"kind": kind, "sev": sev, "where": where, "text": text, "count": 1,
		"t_play_s": snappedf(_play(), 1.0), "repro": list(trail), "lang": locale, "res": _res, "shot": shot_path}
	print("DIFETTO [%s] %s @ %s: %s" % [kind, sev, where, text])


func list(p: PackedStringArray) -> Array:
	var r: Array = []
	for s in p:
		r.append(s)
	return r


var trace_all = PackedStringArray()
var shots = 0


func act(s: String) -> void:
	trail.append("t=%ds %s" % [int(_play()), s])
	print("ACT t=%ds [%s] %s" % [int(_play()), _where(), s])
	if trace_all.size() < 300000:
		trace_all.append("t=%ds [%s] %s" % [int(_play()), _where(), s])
	if trail.size() > 14:
		trail.remove_at(0)


func _play() -> float:
	return float(GS.data.get("stats", {}).get("playtime_s", 0.0)) if GS.active else 0.0


func frames(n: int) -> void:
	for i in n:
		await process_frame


func settle(real_s: float = 0.12) -> void:
	await create_timer(real_s).timeout
	await process_frame


# ------------------------------------------------------------------ mani: clic e tasti

## Preme un pulsante come un giocatore: lo porta in vista, muove il mouse, controlla che sia davvero lui sotto il
## cursore, clic. Ritorna "ok" | "disabled" | "invisible" | "offscreen" | "covered".
func click(b, why: String = "", retry: bool = true) -> String:
	if b == null or not is_instance_valid(b) or not b.is_visible_in_tree():
		return "invisible"
	var label = "%s [%s]" % [lib.disp(b), b.name]
	if b.disabled:
		stats.clicks_disabled += 1
		return "disabled"
	lib.scroll_to(b)
	await process_frame
	await process_frame
	if not is_instance_valid(b) or not b.is_visible_in_tree():
		return "invisible"
	if not lib.in_view(b):
		note("fuori_schermo", _where(), "pulsante «%s» non raggiungibile: fuori dalla finestra" % label)
		return "offscreen"
	if not lib.really_visible(b):
		return "clipped"          # riga di un elenco fuori dall'area visibile: non è cliccabile, non è un difetto
	var vp = lib.viewport_of(b)
	var pos = lib.center_of(b)
	var emb = vp != root                                   # dentro un dialogo incorporato: coordinate della finestra principale
	if emb:
		pos += Vector2(vp.position)
	lib.mouse_move(vp, pos, emb)
	await process_frame
	if not is_instance_valid(b):
		return "invisible"
	var covered = not lib.hover_ok(vp, b)
	if covered and retry:
		var hh = vp.gui_get_hovered_control()
		if hh != null and _under(hh, "TutorialDirector"):
			if await tutorial_step():              # la scheda del tutorial copriva il pulsante: il novizio la legge e va avanti
				return await click(b, why, false)
	if covered:
		var h = vp.gui_get_hovered_control()
		note("coperto", _where(), "pulsante «%s» coperto da %s (%s)" % [label, h.get_class() if h else "niente", h.name if h else "-"])
		return "covered"
	act("clic «%s» %s" % [lib.disp(b), why])
	stats.clicks += 1
	lib.mouse_click(vp, pos, emb)
	await process_frame
	return "ok"


## Sceglie la voce `idx` di una tendina GIÀ aperta con le frecce + Invio (all'apertura col mouse nessuna voce è evidenziata).
func popup_choose(ob, idx: int) -> void:
	if ob == null or not is_instance_valid(ob):
		return
	var pm = ob.get_popup()
	var f = pm.get_focused_item()
	var steps = idx - f if f >= 0 else idx + 1
	for i in absi(steps):
		key(KEY_DOWN if steps > 0 else KEY_UP)
		await process_frame
	key(KEY_ENTER)
	await frames(4)


func key(code: Key, shift: bool = false, ctrl: bool = false) -> void:
	act("tasto %s%s" % ["Ctrl+" if ctrl else "", OS.get_keycode_string(code)])
	lib.key_press(code, shift, ctrl)


func _where() -> String:
	return str(main.get("current_id")) if main != null and is_instance_valid(main) else "avvio"


## Firma dello stato visibile + dati: serve a capire se un clic ha avuto effetto.
func signature() -> int:
	var parts = PackedStringArray()
	parts.append(str(main.get("current_id")))
	parts.append(str(GS.data.hash()))
	parts.append(str(SET.call("get_value", "locale")))
	for w in lib.open_windows():
		parts.append("W:" + w.name)
	for c in lib.visible_controls(main):
		if c is Label or c is BaseButton or c is RichTextLabel:
			var t = lib.disp(c)
			if t.length() > 0:
				parts.append(t)
		if c is BaseButton:
			parts.append(str((c as BaseButton).button_pressed))
			parts.append(str((c as BaseButton).disabled))
		if c is Range:
			parts.append(str(snappedf((c as Range).value, 0.01)))
	return "|".join(parts).hash()


# ------------------------------------------------------------------ occhi: controllo della schermata

func scan(tag: String = "") -> void:
	var where = _where() if tag.is_empty() else tag
	var n_text = 0
	var ctrls = lib.visible_controls(root)
	var btns: Array = []
	for c in ctrls:
		var t = lib.disp(c)
		var tt = lib.tip(c)
		if not t.is_empty():
			n_text += 1
			_check_text(where, t, c, "testo")
		if not tt.is_empty():
			_check_text(where, tt, c, "tooltip")
		if c is OptionButton:
			var ob = c as OptionButton
			for i in ob.item_count:
				_check_text(where, ob.atr(ob.get_item_text(i)), c, "voce di menù")
		if c is BaseButton and not (c as BaseButton).disabled and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and lib.really_visible(c):
			btns.append(c)
	# pulsanti sovrapposti (non uno dentro l'altro)
	for i in btns.size():
		var a = btns[i] as Control
		var ra = a.get_global_rect()
		if ra.size.x < 4 or ra.size.y < 4:
			continue
		for j in range(i + 1, btns.size()):
			var b2 = btns[j] as Control
			if a.is_ancestor_of(b2) or b2.is_ancestor_of(a) or a.get_viewport() != b2.get_viewport():
				continue
			if _under(a, "TutorialDirector") or _under(b2, "TutorialDirector") or _under(a, "PauseMenu") or _under(b2, "PauseMenu"):
				continue
			var inter = ra.intersection(b2.get_global_rect())
			if inter.size.x * inter.size.y > 0.3 * minf(ra.size.x * ra.size.y, b2.get_global_rect().size.x * b2.get_global_rect().size.y):
				note("sovrapposti", where, "pulsanti «%s» e «%s» si sovrappongono" % [lib.disp(a), lib.disp(b2)])
	# schermata vuota
	var cur: Control = main.call("current_screen") if (main != null and main.has_method("current_screen")) else null
	if cur != null and tag.is_empty():
		var texts = 0
		for c in lib.visible_controls(cur):
			if (c is Label or c is RichTextLabel or c is BaseButton) and not lib.disp(c).is_empty():
				texts += 1
		if texts < 3:
			note("schermata_vuota", where, "schermata con %d testi visibili" % texts, "alto")
		var cs = cur.get_global_rect()
		if cs.size.x < 200 or cs.size.y < 100:
			note("schermata_vuota", where, "area della schermata minuscola %s" % str(cs.size), "alto")


func _check_text(where: String, t: String, c: Control, what: String) -> void:
	var keys = lib.bare_keys(t)
	if not keys.is_empty():
		note("chiave_nuda", where, "%s «%s» (%s %s)" % [what, keys[0], c.get_class(), c.name], "alto")
	var fw = lib.foreign_words(t, locale)
	if not fw.is_empty():
		note("testo_lingua_sbagliata", where, "«%s» contiene %s (%s)" % [t.substr(0, 90), str(fw), what], "basso")


func sample(tag: String) -> void:
	samples.append({"tag": tag, "t": snappedf(_play(), 1.0), "static_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))})


# ------------------------------------------------------------------ tempo di gioco

## Fa passare `seconds` di gioco: passi da 0,1 s alla simulazione, poi un aggiornamento della UI a ogni occhiata.
func play_for(seconds: float) -> void:
	var left = seconds
	while left > 0.0:
		var n = mini(SIM_STEP_BATCH, int(ceil(left / STEP_S)))
		CLK.core.paused = true       # il tempo lo fa avanzare il bot, non l'orologio reale
		for i in n:
			GM._on_step(STEP_S)
		left -= n * STEP_S
		var t0 = Time.get_ticks_usec()
		main.call("_on_ui_tick")
		var ms = (Time.get_ticks_usec() - t0) / 1000.0
		var id = _where()
		if not timings.has(id):
			timings[id] = []
		var arr: Array = timings[id]
		if arr.size() < 400:
			arr.append(ms)
		await process_frame


# ------------------------------------------------------------------ avvio

func _run() -> void:
	_wall0 = Time.get_ticks_msec()
	for s in [1, 2, 3]:
		SAVE.call("delete_slot", s)
	change_scene_to_file(START)
	await frames(6)
	var start = current_scene
	scan("start_menu")
	await _new_game_via_ui(start)
	if main == null:
		print("NOVIZIO: impossibile avviare la partita")
		_finish()
		return
	brain = load("res://scripts/novizio_brain.gd").new(GM.get("sim"), func(_dt: float) -> void: pass)
	await frames(10)
	if fast_until != "":
		await modals()
		var bp = load("res://scripts/bot_player.gd").new(GM.get("sim"), func(dt: float) -> void: GM.call("_on_step", dt))
		var r = bp.call("run_until_quest", fast_until, 20000.0)
		print("FAST ", fast_until, " ok=", r.get("ok"), " t=", r.get("t"))
		main.call("build_menu")
		await frames(5)
	sample("inizio")
	if OS.get_environment("NV_PROBE") != "":
		if OS.get_environment("NV_PROBE") == "tut2":
			await probe_tut2()
		elif OS.get_environment("NV_PROBE") == "tut":
			await probe_tut()
		elif OS.get_environment("NV_PROBE") == "dosell":
			await probe_dosell()
		elif OS.get_environment("NV_PROBE") == "farm2":
			await probe_farm2()
		elif OS.get_environment("NV_PROBE") == "sellclick":
			await probe_sellclick()
		elif OS.get_environment("NV_PROBE") == "mining":
			await probe_mining()
		else:
			await probe(OS.get_environment("NV_PROBE"))
		_finish()
		return
	await _phase_a()
	sample("fine_A")
	await _phase_b()
	sample("fine_B")
	await _phase_c()
	sample("fine_C")
	_finish()


func _new_game_via_ui(start) -> void:
	var nb = lib.find_buttons(start, ["UI_NEW_GAME"])
	if nb.is_empty():
		note("vicolo_cieco", "start_menu", "nessun pulsante «Nuova partita»", "alto")
		return
	await click(nb[0], "(menù iniziale)")
	await settle(0.3)
	scan("start_slot")
	var cards = lib.find_buttons(current_scene, ["UI_NEW_GAME"])
	cards.erase(nb[0])
	if cards.is_empty():
		note("vicolo_cieco", "start_menu", "nessuno slot dopo «Nuova partita»", "alto")
		return
	await click(cards[0], "(slot 1)")
	for i in 90:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == MAIN:
			break
	if current_scene != null and current_scene.scene_file_path == MAIN:
		main = current_scene
	else:
		note("vicolo_cieco", "start_menu", "«Nuova partita» non porta alla schermata di gioco", "alto")


# ------------------------------------------------------------------ navigazione

func btn_of(id: String):
	var d = main.get("_buttons")
	return d.get(id) if d != null else null


func screen_id() -> String:
	return str(main.get("current_id"))


func goto(id: String) -> bool:
	if screen_id() == id:
		return true
	var b = btn_of(id)
	if b == null:
		note("vicolo_cieco", screen_id(), "voce di menù «%s» inesistente" % id)
		return false
	var r = await click(b, "(menù laterale)")
	if r == "invisible":                   # dal F4 la voce può stare in un gruppo chiuso (finestre basse): il novizio apre il gruppo dall'intestazione
		var sm = main.get("_sidebar")
		if sm != null:
			for gid in sm.group_ids():
				if (sm.get("_group_ids").get(gid, []) as Array).has(id) and not sm.is_group_open(gid):
					var hb = sm.header_button(gid)
					if hb != null and await click(hb, "(apro il gruppo)") == "ok":
						await frames(3)
						r = await click(b, "(menù laterale)")
					break
	await frames(3)
	if r != "ok":
		return false
	var seen = str(stats.screens.get(id, 0))
	stats.screens[id] = int(seen) + 1
	if b.has_meta("req_target"):
		return false                       # voce bloccata: il clic porta alla missione che la sblocca
	if screen_id() != id:
		note("clic_senza_effetto", id, "il clic sul menù «%s» non apre la schermata" % lib.disp(b))
		return false
	if int(seen) == 0 or int(seen) % 25 == 0:
		await frames(3)
		scan()
	return true


func current():
	return main.call("current_screen")


## Chiude tutte le finestre in primo piano. confirm = preme OK sulle domande di conferma.
func modals(confirm: bool = true) -> void:
	var guard = 0
	while guard < 60:
		guard += 1
		await process_frame
		var fb = root.get_node("Feedback")
		var pm = fb.get("_pause_menu")
		if pm != null and is_instance_valid(pm):
			scan("menu_pausa")
			var rb = lib.find_buttons(pm, ["UI_FB_PAUSE_RESUME"], true)
			if rb.is_empty():
				key(KEY_ESCAPE)
			else:
				await click(rb[0], "(Riprendi)")
			await frames(4)
			if is_instance_valid(pm) and not pm.is_queued_for_deletion():
				note("vicolo_cieco", "menu_pausa", "il menu di pausa non si chiude né con «Riprendi» né con Esc", "alto")
				fb.call("close_pause_menu")
			continue
		if await tutorial_step():
			continue
		var ov = main.get("_overlay")
		if ov != null and ov.call("is_busy"):
			var node = ov.get("_active")
			if node == null:
				await frames(4)
				continue
			var ttl = lib.find_buttons(node, ["TutorialTitle"])
			var title = ""
			for c in lib.visible_controls(node):
				if c.name == "TutorialTitle":
					title = lib.disp(c)
			scan("finestra:" + (title if title != "" else "benvenuto/bentornato"))
			var bt = lib.find_buttons(node, ["WelcomeGo", "TutorialOk", "WbCollect"])
			if bt.is_empty():
				note("vicolo_cieco", "overlay", "finestra modale senza pulsante per chiuderla", "alto")
				key(KEY_ESCAPE)
				await frames(5)
				if ov.get("_active") == node:
					return
				continue
			if title != "":
				stats["tutorials"] = stats.get("tutorials", []) + [title]
			await click(bt[0], "(finestra)")
			var closed = false
			for i in 40:
				await process_frame
				if not is_instance_valid(node) or node.is_queued_for_deletion() or ov.get("_active") != node:
					closed = true
					break
			if not closed:
				note("tutorial_non_si_chiude", "overlay", "dopo il clic su «%s» la finestra «%s» resta aperta" % [lib.disp(bt[0]), title], "alto")
				key(KEY_ESCAPE)
				await frames(5)
			continue
		var wins = lib.open_windows()
		if wins.is_empty():
			return
		var w = wins[0]
		var okb = lib.find_buttons(w, ["UI_CONFIRM", "OK", "Ok"], true)
		var cb = lib.find_buttons(w, ["UI_CANCEL", "Cancel", "Annulla"], true)
		if w is AcceptDialog and w.get_ok_button() != null and w.get_ok_button().is_visible_in_tree() and not w.get_ok_button().disabled:
			okb = [w.get_ok_button()]
		if w is ConfirmationDialog and w.get_cancel_button() != null and w.get_cancel_button().is_visible_in_tree():
			cb = [w.get_cancel_button()]
		var pick = null
		if confirm and not okb.is_empty():
			pick = okb[0]
		elif not cb.is_empty():
			pick = cb[0]
		elif not okb.is_empty():
			pick = okb[0]
		else:
			var any = lib.buttons(w)
			if not any.is_empty():
				pick = any[0]
		if pick != null:
			await click(pick, "(dialogo %s)" % w.name)
		else:
			key(KEY_ESCAPE)
		await frames(4)
		if is_instance_valid(w) and w.visible:
			key(KEY_ESCAPE)
			await frames(4)
			if is_instance_valid(w) and w.visible:
				note("vicolo_cieco", screen_id(), "finestra «%s» che non si chiude (OK/Annulla/Esc)" % w.name, "alto")
				w.hide()


## Vero se il gioco è tornato al menù iniziale: si riprende dallo slot.
func back_to_game() -> void:
	if current_scene != null and current_scene.scene_file_path == START:
		act("(il gioco è tornato al menù iniziale)")
		var c = lib.find_buttons(current_scene, ["UI_CONTINUE"], true)
		if c.is_empty():
			note("vicolo_cieco", "start_menu", "nessun «Continua» dopo il ritorno al menù", "alto")
			return
		await click(c[0], "(Continua)")
		for i in 90:
			await process_frame
			if current_scene != null and current_scene.scene_file_path == MAIN:
				main = current_scene
				break


# ------------------------------------------------------------------ azioni di gioco via UI

func quests_sys():
	return GM.call("system", "quests")



func _under(n, node_name: String) -> bool:
	var p = n
	while p != null:
		if p.name == node_name:
			return true
		p = p.get_parent()
	return false


## Tutorial guidato (TutorialDirector): il novizio legge la scheda e preme «Avanti»; nei passi «premi proprio questo» tocca il
## controllo evidenziato (gruppo `tut:<chiave>`); se non c'e' nulla di premibile usa «Salta questo passo». true se ha agito.
func tutorial_step() -> bool:
	var td = root.find_child("TutorialDirector", true, false)
	if td == null or not td.call("is_showing"):
		return false
	if not lib.open_windows().is_empty():
		return false                      # un dialogo modale (es. «Non sei pronto») va risposto prima: copre anche la scheda del tutorial
	var sid = str(td.call("current_step_id"))
	if int(stuck_tut.get(sid, 0)) >= 6:
		# il passo non si chiude con «Avanti»: il novizio prova «Più tardi», poi «Salta il tutorial»; poi lo ignora
		var tries = int(stuck_tut.get(sid + "#alt", 0))
		stuck_tut[sid + "#alt"] = tries + 1
		var alt_name = "TutorialLater" if tries == 0 else ("TutorialSkipAll" if tries == 1 else "")
		if alt_name != "":
			var ab = td.find_child(alt_name, true, false)
			if ab != null and ab.is_visible_in_tree():
				await click(ab, "(tutorial bloccato: %s)" % alt_name, false)
				await frames(3)
				return true
		return false
	scan("tutorial_guidato:" + sid)
	var seen = stats.get("guided_steps", [])
	if not seen.has(sid):
		seen.append(sid)
		stats["guided_steps"] = seen
	var nxt = td.find_child("TutorialNext", true, false)
	var acted = false
	if td.call("is_blocking"):
		var key = str(td.call("highlighted_key"))
		var cand = null
		for n in get_nodes_in_group("tut:" + key):
			if n is Control and n.is_visible_in_tree() and n.size.x > 1.0:
				cand = n
				break
		if cand != null:
			await click(cand, "(tutorial: tocca cio' che e' evidenziato «%s»)" % key, false)
			acted = true
	elif nxt != null and nxt.is_visible_in_tree() and not nxt.disabled:
		await click(nxt, "(tutorial: Avanti)", false)
		acted = true
	if not acted:
		var sk = td.find_child("TutorialSkipStep", true, false)
		if sk != null and sk.is_visible_in_tree():
			await click(sk, "(tutorial: Salta questo passo)", false)
			acted = true
	await frames(3)
	if acted and td.call("is_showing") and str(td.call("current_step_id")) == sid:
		stuck_tut[sid] = int(stuck_tut.get(sid, 0)) + 1
		if int(stuck_tut[sid]) == 6:
			var tds = root.find_children("TutorialDirector", "", true, false)
			var ts = td.get("_ts")
			print("DIAG tutorial: step=", sid, " direttori=", tds.size(), " visto=", ts.call("is_seen", sid), " forced=", td.get("_forced"),
				" schermata=", screen_id(), " card_visible=", td.find_child("TutorialCard", true, false).visible, " next_vis=", nxt.is_visible_in_tree() if nxt else "-",
				" in_combat=", brain.call("_combat").in_combat())
			note("tutorial_non_si_chiude", "tutorial_guidato", "il passo «%s» del tutorial guidato resta dopo 6 clic sul suo pulsante" % sid, "alto")
	return acted


var stuck_tut = {}
var disc_done = {}


## «Da scoprire» (QuestGuide): i pulsanti «Vai» portano alle schermate che il gioco suggerisce di guardare.
func follow_discoveries() -> int:
	var n = 0
	for i in 6:
		var cands = []
		for g in ["tut:quest_go", "tut:goal_go"]:
			for c in get_nodes_in_group(g):
				if c is Control and c.is_visible_in_tree() and not (c as BaseButton).disabled:
					var lbl = lib.disp(c)
					if _play() - float(disc_done.get(lbl, -99999.0)) > 900.0:        # lo stesso «Vai» al massimo ogni 15 min di gioco
						cands.append(c)
		if cands.is_empty():
			break
		disc_done[lib.disp(cands[0])] = _play()
		var r = await click(cands[0], "(Da scoprire: Vai)")
		await frames(4)
		await modals()
		if r != "ok":
			break
		n += 1
		scan()
		if not await goto("quests"):
			break
		await frames(3)
	return n


func claim_all() -> int:
	if not await goto("quests"):
		return 0
	var n = 0
	for k in 8:
		await frames(2)
		var cur = current()
		var cb = lib.find_buttons(cur, ["ClaimButton"], true)
		var extra = lib.find_buttons(cur, ["TalkButton", "UI_QUESTS_DELIVER"], true)
		var all = cb + extra
		if all.is_empty():
			break
		var r = await click(all[0], "(Missioni)")
		if r != "ok":
			break
		n += 1
		await settle(0.7)
		await modals()
	return n


func open_crates() -> int:
	var cr = GM.call("system", "crates")
	if cr == null or btn_of("vault_hall") == null or btn_of("vault_hall").disabled:
		return 0
	var bank = GM.call("system", "bank")
	var any = false
	for sid in bank.state.stacks.keys():
		if cr.is_crate(str(sid)) and cr.openable(str(sid)) > 0:
			any = true
	main.call("_update_slow")
	var vb = int(main.call("badge_count", "vault_hall"))
	if any and vb == 0:
		note("badge_sbagliato", "vault_hall", "ci sono casse apribili ma il pallino della Sala dei Caveau è spento", "medio")
	if not any:
		if vb > 0:
			note("badge_sbagliato", "vault_hall", "il pallino della Sala dei Caveau dice %d ma non ci sono casse apribili" % vb, "medio")
		return 0
	if not await goto("vault_hall"):
		return 0
	var n = 0
	for round in 6:
		await frames(3)
		var ob = lib.find_buttons(current(), ["UI_CRATES_OPEN"], true)
		if ob.is_empty():
			if round == 0:
				note("badge_sbagliato", "vault_hall", "casse apribili e pallino acceso, ma nella Sala non c'è un «Apri» attivo", "alto")
			break
		if await click(ob[0], "(Sala dei Caveau: Apri)") != "ok":
			break
		n += 1
		# il rullo: «Salta» è sempre visibile (docs/09); poi «Chiudi»
		for i in 80:
			await settle(0.1)
			var sk = lib.find_buttons(current(), ["UI_CRATES_SKIP"], true)
			if not sk.is_empty() and rng.randf() < 0.5:
				await click(sk[0], "(Salta il rullo)")
				break
			var cl = lib.find_buttons(current(), ["UI_CRATES_CLOSE"], true)
			if not cl.is_empty():
				break
		scan("rullo")
		var cl2 = lib.find_buttons(current(), ["UI_CRATES_CLOSE"], true)
		if cl2.is_empty():
			await settle(1.5)
			cl2 = lib.find_buttons(current(), ["UI_CRATES_CLOSE"], true)
		if cl2.is_empty():
			note("vicolo_cieco", "vault_hall", "dopo l'apertura della cassa non c'è «Chiudi»", "alto")
			break
		await click(cl2[0], "(Chiudi il rullo)")
		await frames(3)
		await modals()
		var left = false
		for sid in bank.state.stacks.keys():
			if cr.is_crate(str(sid)) and cr.openable(str(sid)) > 0:
				left = true
		if not left:
			break
	return n


func row_button(cur, text: String):
	var l = lib.label_with(cur, text)
	if l == null:
		return null
	var p = l.get_parent()
	while p != null and not (p is PanelContainer):
		p = p.get_parent()
	if p == null:
		return null
	var bs = lib.buttons(p, false)
	return bs.back() if not bs.is_empty() else null


func do_action(aid: String) -> bool:
	var sk = brain.call("_skills")
	if sk.current_action() == aid:
		return true
	var a = brain.call("_data").action(aid)
	var sid = str(a.get("skill", ""))
	var gid = "skill:" + sid
	if not await goto(gid):
		return false
	await frames(2)
	var nm = Loc_t(a.get("name", {}))
	var b = row_button(current(), nm)
	if b == null:
		note("riga_non_trovata", gid, "azione «%s» (%s) non ha una riga con pulsante nella schermata" % [nm, aid])
		return false
	if b.disabled:
		note("azione_bloccata", gid, "il pulsante di «%s» è spento ma il piano lo richiede" % nm, "basso")
		return false
	if await click(b, "(avvia «%s»)" % nm) != "ok":
		return false
	await frames(2)
	if sk.current_action() != aid:
		note("pulsante_senza_effetto", gid, "«Avvia» su «%s» non avvia l'azione (can_start=%s)" % [nm, str(sk.can_start(aid))], "alto")
		return false
	return true


func Loc_t(d) -> String:
	return root.get_node("Loc").call("t", d)


func do_combat(zone: String, monster: String) -> bool:
	var cb = brain.call("_combat")
	var a = GS.data.get("activity", {})
	if cb.in_combat() and str(a.get("zone", "")) == zone and (monster == "" or str(a.get("monster", "")) == monster):
		return true
	if not await goto("combat"):
		return false
	await frames(3)
	var cur = current()
	var zo = cur.get("_zone_opt")
	var zids = cur.get("_zone_ids")
	var zi = zids.find(zone)
	if zo != null and zi >= 0 and str(cur.get("_zone_id")) != zone:
		if await click(zo, "(zona)") == "ok":
			await frames(3)
			if lib.open_windows().is_empty():
				note("pulsante_senza_effetto", "combat", "il menù a tendina delle zone non si apre", "alto")
			else:
				await popup_choose(zo, zi)
		if str(cur.get("_zone_id")) != zone:
			note("tendina_non_seleziona", "combat", "scegliere la zona «%s» con tastiera/menù a tendina non cambia la zona (resta %s)" % [zone, str(cur.get("_zone_id"))], "medio")
			zo.select(zi)
			zo.item_selected.emit(zi)
			await frames(3)
	if monster != "":
		var md = brain.call("_data").get_def("monsters", monster)
		var nm = Loc_t(md.get("name", {}))
		for b in lib.buttons(cur, true):
			if lib.disp(b).begins_with(nm):
				await click(b, "(mostro «%s»)" % nm)
				break
	var st = cur.get("_start_btn")
	if st == null or st.disabled:
		return false
	if lib.disp(st) == root.tr("UI_COMBAT_STOP") and cb.in_combat():
		await click(st, "(Ferma)")        # sta combattendo altro: si riavvia con quello giusto
		await frames(2)
	var r = await click(st, "(Combatti)")
	await frames(3)
	if not lib.open_windows().is_empty():
		await modals(true)                    # «Non sei pronto: Combatti lo stesso / Mi preparo»
		await frames(3)
	if r == "ok" and not cb.in_combat():
		note("pulsante_senza_effetto", "combat", "«Combatti» in %s contro %s non avvia il combattimento" % [zone, monster], "alto")
		return false
	return true


func ui_task_exec(task: Dictionary) -> void:
	var kind = str(task.get("kind", ""))
	match kind:
		"action":
			await do_action(str(task.action))
		"combat":
			await do_combat(str(task.zone), str(task.monster))
		"ui_talk", "ui_deliver":
			await claim_all()
		"ui_equip":
			await do_equip(task)
		"ui_sell":
			await do_sell()


func do_equip(task: Dictionary) -> void:
	var idef = brain.call("_data").item(str(task.item))
	var nm = Loc_t(idef.get("name", {}))
	var cb = brain.call("_combat")
	# 1) Deposito: cerco l'oggetto (ricerca), lo scelgo e premo «Equipaggia» nel dettaglio (funziona anche con l'Eroe bloccato)
	if await goto("bank"):
		await frames(3)
		var vl = current().find_child("View_list", true, false)      # dal F16 la vista predefinita è la griglia (celle disegnate, senza righe): il novizio passa alla Lista
		if vl is BaseButton and not vl.button_pressed and not vl.disabled:
			await click(vl, "(vista Lista)")
			await frames(3)
		var row = await bank_row(nm)
		if row != null:
			await click(row, "(oggetto «%s»)" % nm)
			await frames(4)
			var eq = []
			for b in lib.buttons(current(), true):
				var t = lib.disp(b).to_lower()
				if b.name == "WornButton" or t == "equip" or t == "equipaggia" or t == "indossa":
					eq.append(b)
			if not eq.is_empty():
				await click(eq[0], "(Equipaggia)")
				await frames(3)
				await modals()
				if cb.is_equipped(str(task.uid)):
					return
				note("pulsante_senza_effetto", "bank", "«Equipaggia» nel dettaglio di «%s» non lo indossa" % nm, "alto")
	# 2) Eroe: clic sullo slot e scelta dall'elenco (se lo slot apre un elenco a tendina)
	var hb = btn_of("hero")
	if hb != null and not hb.has_meta("req_target") and not hb.disabled and await goto("hero"):
		await frames(3)
		var cur = current()
		var slot = str(idef.get("equipment", {}).get("slot", ""))
		var rows = cur.get("_slot_rows")
		if slot != "" and rows != null and rows.has(slot) and await click(rows[slot].btn, "(slot %s)" % slot) == "ok":
			await frames(4)
			var uids = cur.get("_pick_uids")
			var idx = uids.find(str(task.uid)) if uids != null else -1
			if not lib.open_windows().is_empty() and idx >= 0:
				for i in idx + 1:
					key(KEY_DOWN)
					await process_frame
				key(KEY_ENTER)
				await frames(4)
				await modals()
				return
			if not lib.open_windows().is_empty():
				key(KEY_ESCAPE)
				await frames(3)
	note("no_se_como", screen_id(), "per «%s» il novizio non riesce a indossarlo (Deposito e Eroe provati)" % nm)


## Riga del Deposito con quel nome: il novizio scrive il nome nella ricerca (come Ctrl+F) e poi guarda l'elenco.
func bank_row(nm: String):
	for attempt in 2:
		for b in lib.visible_controls(current()):
			if b is BaseButton and b.has_method("set_item") and lib.really_visible(b):
				for l in lib.visible_controls(b):
					if l is Label and lib.disp(l).begins_with(nm):
						return b
		if attempt == 1:
			break
		var le = null
		for c in lib.visible_controls(current()):
			if c is LineEdit and c.editable:
				le = c
		if le == null:
			note("no_se_como", "bank", "il Deposito non ha un campo di ricerca visibile", "medio")
			return null
		lib.mouse_move(le.get_viewport(), lib.center_of(le))
		await process_frame
		lib.mouse_click(le.get_viewport(), lib.center_of(le))
		await frames(2)
		lib.type_text(le, nm.substr(0, 6))
		await frames(6)
	return null


func do_sell() -> void:
	var bank = GM.call("system", "bank")
	var g0 = GS.call("gold")
	var used0 = bank.used_slots()
	if not await goto("bank"):
		return
	await frames(3)
	var sb = lib.find_buttons(current(), ["UI_UIA_SELL_BTN"], true)
	if sb.is_empty():
		note("no_se_como", "bank", "nessun pulsante di vendita in blocco nel Deposito")
		return
	await click(sb[0], "(vendi in blocco)")
	await frames(6)
	if lib.open_windows().is_empty():
		note("pulsante_senza_effetto", "bank", "«Vendi in blocco» non apre la finestra", "alto")
		return
	scan("vendita_in_blocco")
	await modals(true)             # «Vendi tutto»
	await frames(4)
	if GS.call("gold") <= g0 and bank.used_slots() >= used0:
		note("vendita_vuota", "bank", "«Vendi in blocco» ha venduto 0 oggetti con il Deposito a %d/%d (filtri iniziali della finestra)" % [used0, bank.capacity()], "basso")


func tidy_bank_if_needed() -> void:
	var bank = GM.call("system", "bank")
	if bank == null or bank.capacity() <= 0:
		return
	if float(bank.used_slots()) / float(bank.capacity()) < 0.85:
		return
	if btn_of("market") == null or btn_of("market").disabled or btn_of("market").has_meta("req_target"):
		pass
	act("(Deposito al %d%%: il novizio vende)" % int(100.0 * bank.used_slots() / bank.capacity()))
	await do_sell()


# ------------------------------------------------------------------ fase A: il novizio

func main_quest() -> String:
	var q = quests_sys()
	return q.current_main() if q != null else ""


func _phase_a() -> void:
	var end_t = _play() + hours_a * 3600.0
	await modals()
	scan("riepilogo_iniziale")
	# primo passo suggerito dal Riepilogo: «Comincia con ...»
	var sb = lib.find_buttons(current(), [], true)
	for b in lib.buttons(current(), true):
		if lib.disp(b).begins_with(root.tr("UI_UXC_GO_SKILL").split("{")[0].strip_edges()) and root.tr("UI_UXC_GO_SKILL").split("{")[0].strip_edges() != "":
			await click(b, "(primo passo suggerito)")
			await frames(4)
			break
	var last_quest = main_quest()
	var last_quest_t = _play()
	var known_menu = (main.get("_menu_ids") as Array).duplicate()
	var next_sample = _play() + 600.0
	var next_claim = 0.0
	var cycles = 0
	var stuck_noted = ""
	while _play() < end_t:
		cycles += 1
		if over_wall():
			note("watchdog", "fase A", "tempo reale massimo raggiunto a %d minuti di gioco" % int(_play() / 60.0), "basso")
			break
		await modals()
		await back_to_game_check()
		# nuove voci di menù: il novizio le va a vedere
		var menu_now = main.get("_menu_ids") as Array
		for id in menu_now:
			if not known_menu.has(id):
				known_menu.append(id)
				act("(nuova voce di menù: %s)" % id)
				if await goto(str(id)):
					await frames(4)
					scan()
					await settle(0.3)
					await modals()
		# riscatta quando il segnale dice che c'è qualcosa
		main.call("_update_slow")
		var qb = int(main.call("badge_count", "quests"))
		if qb > 0 or _play() >= next_claim:
			next_claim = _play() + 300.0
			var cb0 = await claim_all()
			if qb > 0 and cb0 == 0:
				cb0 = await follow_discoveries()
			if qb > 0 and cb0 == 0:
				note("badge_sbagliato", "quests", "il pallino delle Missioni dice %d ma non c'è nulla da riscattare/consegnare" % qb, "medio")
			elif qb == 0 and cb0 > 0:
				note("badge_sbagliato", "quests", "il pallino delle Missioni è spento ma c'erano %d azioni nella schermata" % cb0, "basso")
		await open_crates()
		if cycles % 6 == 0:
			await service_badges()
		if cycles % 12 == 0:
			await tidy_bank_if_needed()
		var task = brain.call("decide_now", _play())
		if stuck_noted != "" and cycles % 2 == 0:
			await modals(rng.randf() < 0.5)
			await random_step()               # il novizio bloccato prova cose a caso
		else:
			await ui_task_exec(task)
		await play_for(10.0)
		var mq = main_quest()
		if mq != last_quest:
			quest_log.append({"from": last_quest, "to": mq, "t_s": snappedf(_play(), 1.0)})
			last_quest = mq
			last_quest_t = _play()
			stuck_noted = ""
		elif _play() - last_quest_t > 2400.0 and stuck_noted != mq:
			stuck_noted = mq
			var q = quests_sys()
			var d = q.quest_def(mq)
			note("novizio_bloccato", "quests", "missione «%s» ferma da %d min; compito=%s; motivo del cervello=%s" % [mq, int((_play() - last_quest_t) / 60.0), str(task), str(brain.get("_reason"))], "alto")
			print("BLOCCO ", mq, " ", task, " ", brain.get("_reason"), "\n  ", "\n  ".join(trail))
		if _play() >= next_sample:
			next_sample = _play() + 900.0
			sample("A")
			print("A t=%dmin quest=%s cicli=%d clic=%d difetti=%d mem=%.0fMB nodi=%d" % [int(_play() / 60.0), mq, cycles, stats.clicks, findings.size(),
				OS.get_static_memory_usage() / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	await modals()



## Il novizio guarda i pallini rossi del menù e fa quello che dicono; poi controlla che il pallino si sia spento.
## Verifica anche che la schermata offra davvero qualcosa da fare (pallino bugiardo = difetto).
func service_badges() -> void:
	main.call("_update_slow")
	var ids = (main.get("_badges") as Dictionary).keys()
	for id in ids:
		var n = int(main.call("badge_count", id))
		if n <= 0 or id == "quests" or id == "vault_hall" or id == "talents":
			continue
		var sid = str(id)
		var keys = []
		var tag = ""
		match sid:
			"skill:farming":
				keys = ["UI_FARM_HARVEST_ALL", "UI_FARM_HARVEST"]
			"orders":
				keys = ["UI_ORDERS_DELIVER"]
			"events":
				keys = []
			_:
				keys = ["PERK"]
		if not await goto(sid):
			continue
		await frames(4)
		await settle(0.3)                  # almeno due giri del timer a 10 Hz: la schermata si aggiorna da sola
		var done = 0
		if keys == ["PERK"]:
			var cur = current()
			var pb = cur.find_child("PerkToggle", true, false)
			if pb != null and pb.is_visible_in_tree():
				if not pb.button_pressed:
					await click(pb, "(talenti di mansione)")
					await frames(4)
				var opts = []
				var box = cur.find_child("PerkRows", true, false)
				if box != null:
					for b in lib.buttons(box, true):
						if b.toggle_mode and not b.button_pressed:
							opts.append(b)
				if not opts.is_empty():
					await click(opts[rng.randi() % opts.size()], "(scegli talento)")
					done += 1
					await frames(4)
			else:
				note("badge_sbagliato", sid, "il pallino di «%s» dice %d talenti da scegliere ma la schermata non mostra il pannello dei talenti" % [sid, n])
		elif sid == "events":
			for b in lib.buttons(current(), true):
				if lib.disp(b).begins_with(root.tr("UI_EVENTS_CLAIM").split("{")[0].strip_edges()):
					await click(b, "(riscatta evento)")
					done += 1
					await frames(3)
					break
		else:
			var bs = lib.find_buttons(current(), keys, true)
			if not bs.is_empty():
				await click(bs[0], "(%s)" % sid)
				done += 1
				await frames(3)
			if sid == "skill:farming":
				# il pallino di Coltivazione conta anche i talenti di mansione da scegliere (pannello «Talenti» del Giardino)
				var pbs = lib.find_buttons(current(), ["PerkToggle"], false)
				if not pbs.is_empty() and pbs[0].is_visible_in_tree():
					if not pbs[0].button_pressed:
						await click(pbs[0], "(talenti di Coltivazione)")
						await frames(4)
					var box = current().find_child("PerkRows", true, false)
					var opts = []
					if box != null:
						for b in lib.buttons(box, true):
							if b.toggle_mode and not b.button_pressed:
								opts.append(b)
					if not opts.is_empty():
						await click(opts[rng.randi() % opts.size()], "(scegli talento di Coltivazione)")
						done += 1
						await frames(4)
		await modals()
		main.call("_update_slow")
		var n2 = int(main.call("badge_count", id))
		if done == 0:
			var dbg = []
			for b in lib.buttons(current(), false):
				dbg.append("%s%s" % [lib.disp(b), "(spento)" if b.disabled else ""])
			var extra = ""
			if sid == "skill:farming":
				extra = " ready_count=%d" % GM.call("system", "farming").ready_count()
			note("badge_sbagliato", sid, "il pallino di «%s» dice %d ma nella schermata non c'è un pulsante attivo per farlo.%s Pulsanti: %s" % [sid, n, extra, " | ".join(dbg).substr(0, 300)], "medio")
		elif n2 >= n and keys != ["PERK"] and sid != "skill:farming":
			note("badge_sbagliato", sid, "dopo aver agito su «%s» il pallino resta %d (era %d); Deposito %s" % [sid, n2, n, "PIENO" if GM.call("system", "bank").is_full() else "non pieno"], "basso")


func back_to_game_check() -> void:
	if current_scene != null and current_scene.scene_file_path == START:
		await back_to_game()


# ------------------------------------------------------------------ fase B: scelte casuali

const RISKY := ["quit", "exit", "esci", "main menu", "menù principale", "menu principale", "delete", "elimina", "cancella", "abandon", "abbandona"]


func risky(b) -> bool:
	var t = lib.disp(b).to_lower()
	for r in RISKY:
		if t.contains(r):
			return true
	return false


func over_wall() -> bool:
	var lim = OS.get_environment("NV_MAX_WALL")
	var secs = float(lim) if lim != "" else 10800.0
	return (Time.get_ticks_msec() - _wall0) / 1000.0 > secs


## Una scelta casuale di menù: voce della barra laterale, pulsante della schermata o un tasto scorciatoia.
func random_step() -> void:
	var roll = rng.randf()
	var target = null
	var label = ""
	if roll < 0.35:
		var ids = main.get("_buttons").keys()
		var id = ids[rng.randi() % ids.size()]
		target = btn_of(id)
		label = "menù"
	elif roll < 0.92:
		var bs = []
		var pool = lib.buttons(main.get("_host"), true)
		for b in pool:
			if not risky(b) and lib.really_visible(b):
				bs.append(b)
		if not bs.is_empty():
			target = bs[rng.randi() % bs.size()]
			label = "schermata"
	else:
		var codes = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_L, KEY_B, KEY_C, KEY_Q, KEY_ESCAPE, KEY_F1, KEY_TAB]
		key(codes[rng.randi() % codes.size()])
		await frames(3)
	if target != null:
		await press_judge(target, "casuale " + label)
	scan()


## Preme un pulsante e giudica: ha cambiato qualcosa di visibile o dello stato? Se no, è un candidato «pulsante morto».
func press_judge(target, label: String) -> String:
	var before = signature()
	var r = await click(target, "(%s)" % label)
	if r == "ok":
		await frames(3)
		var after = signature()
		if after == before:
			await settle(0.35)
			after = signature()
		if after == before and is_instance_valid(target) and not (target is OptionButton):
			stats.noop += 1
			if target.has_meta("req_target"):
				note("voce_bloccata_senza_riscontro", screen_id(), "da «%s» il clic sulla voce bloccata «%s» non mostra nulla (la missione che la sblocca è già lì o non si vede)" % [screen_id(), lib.disp(target)], "basso")
			else:
				note("pulsante_senza_effetto", screen_id(), "il clic su «%s» (%s) non cambia nulla di visibile né nello stato" % [lib.disp(target), target.name], "medio")
	return r


func _phase_b() -> void:
	var end_t = _play() + hours_b * 3600.0
	var next_sample = _play() + 900.0
	while _play() < end_t:
		if over_wall():
			note("watchdog", "fase B", "tempo reale massimo raggiunto a %d minuti di gioco" % int(_play() / 60.0), "basso")
			break
		await modals(rng.randf() < 0.3)
		await back_to_game_check()
		await random_step()
		await play_for(rng.randf_range(8.0, 24.0))
		if _play() >= next_sample:
			next_sample = _play() + 1800.0
			sample("B")
			print("B t=%dh%02d clic=%d difetti=%d mem=%.0fMB nodi=%d orfani=%d" % [int(_play() / 3600.0), int(fmod(_play(), 3600.0) / 60.0), stats.clicks, findings.size(),
				OS.get_static_memory_usage() / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	await modals()


# ------------------------------------------------------------------ fase C: controlli fissi

func _phase_c() -> void:
	var only = OS.get_environment("NV_C")          # es. "timing,shortcuts"; vuoto = tutti
	await modals()
	await goto("summary")
	if only == "" or only.contains("shortcuts"):
		await check_shortcuts()
	if only == "" or only.contains("tab"):
		await check_tab_nav()
	if only == "" or only.contains("leaks"):
		await check_leaks()
	if only == "" or only.contains("timing"):
		await check_timing()
	if only == "" or only.contains("sweep"):
		await check_sweep()
	if only == "" or only.contains("lang"):
		await check_language_switch()
	if only == "" or only.contains("save"):
		await check_save_roundtrip()


func check_shortcuts() -> void:
	await goto("summary")
	var ids = main.get("_menu_ids") as Array
	var codes = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	for i in range(mini(9, ids.size())):
		await goto("summary")
		key(codes[i])
		await frames(4)
		await modals()
		if screen_id() != str(ids[i]):
			var b = btn_of(str(ids[i]))
			var req = b != null and b.has_meta("req_target")
			if not req:
				note("scorciatoia", "tasto %d" % (i + 1), "il tasto %d dovrebbe aprire «%s» ma la schermata è «%s»" % [i + 1, str(ids[i]), screen_id()], "alto")
	await goto("summary")
	var vis0 = main.call("column_visible")
	key(KEY_L)
	await frames(3)
	if main.call("column_visible") == vis0:
		note("scorciatoia", "tasto L", "il tasto L non mostra/nasconde la colonna destra", "alto")
	key(KEY_L)
	await frames(3)
	for pair in [[KEY_B, "bank"], [KEY_C, "hero"], [KEY_F1, "manual"]]:
		await goto("summary")
		key(pair[0])
		await frames(4)
		await modals()
		var avail = btn_of(pair[1]) != null and not btn_of(pair[1]).disabled and not btn_of(pair[1]).has_meta("req_target")
		if avail and screen_id() != pair[1]:
			note("scorciatoia", "tasto " + OS.get_keycode_string(pair[0]), "dovrebbe aprire «%s», aperta «%s»" % [pair[1], screen_id()], "medio")
	await goto("bank")
	key(KEY_Q)
	await frames(4)
	if not screen_id().begins_with("skill:"):
		note("scorciatoia", "tasto Q", "Q dovrebbe portare alla coda azioni di una mansione, schermata «%s»" % screen_id(), "medio")
	key(KEY_ESCAPE)
	await frames(4)
	await modals()
	if screen_id() != "summary":
		note("scorciatoia", "tasto Esc", "Esc da una schermata non riporta al Riepilogo (è «%s»)" % screen_id(), "medio")
	await goto("bank")
	key(KEY_F, false, true)
	await frames(3)
	var fo = main.get_viewport().gui_get_focus_owner()
	if not (fo is LineEdit):
		note("scorciatoia", "Ctrl+F", "Ctrl+F nel Deposito non porta il cursore nella ricerca (focus: %s)" % (fo.get_class() if fo else "nessuno"), "basso")
	else:
		key(KEY_ESCAPE)
		await frames(2)


func check_tab_nav() -> void:
	var ids = (main.get("_menu_ids") as Array).duplicate()
	for id in ids:
		if not await goto(str(id)):
			continue
		await frames(4)
		await modals()
		main.get_viewport().gui_release_focus()
		var seen = {}
		var order = []
		var stuck = 0
		var last = null
		var offscreen = 0
		var invisible = 0
		for i in 60:
			key(KEY_TAB)
			await frames(2)
			var fo = main.get_viewport().gui_get_focus_owner()
			if fo == null:
				continue
			if fo == last:
				stuck += 1
			last = fo
			if not seen.has(fo.get_instance_id()):
				seen[fo.get_instance_id()] = true
				order.append(fo)
				if not fo.is_visible_in_tree():
					invisible += 1
				elif not lib.in_view(fo):
					offscreen += 1
		var enabled = lib.buttons(main, true).size()
		if order.size() < 2 and enabled >= 3:
			note("tab_navigazione", str(id), "con Tab il focus tocca solo %d controlli su %d pulsanti attivi" % [order.size(), enabled], "medio")
		if stuck >= 20:
			note("tab_navigazione", str(id), "Tab resta fermo sullo stesso controllo %d volte (trappola del focus)" % stuck, "alto")
		if invisible > 0:
			note("tab_navigazione", str(id), "Tab porta il focus su %d controlli invisibili" % invisible, "medio")
		if offscreen > 3:
			note("tab_navigazione", str(id), "Tab porta il focus su %d controlli fuori finestra senza scorrere" % offscreen, "basso")
		# nel contenuto: almeno un controllo raggiunto con Tab appartiene alla schermata (non solo al menù)
		var cur = current()
		var in_content = 0
		for f in order:
			if cur != null and cur.is_ancestor_of(f):
				in_content += 1
		var cbtn = lib.buttons(cur, true).size() if cur != null else 0
		if cbtn >= 2 and in_content == 0:
			note("tab_navigazione", str(id), "Tab non raggiunge mai i %d pulsanti del contenuto (60 pressioni)" % cbtn, "medio")
		# frecce: dal menù laterale
		var sidebar_btn = btn_of(str(id))
		if sidebar_btn != null and sidebar_btn.focus_mode != Control.FOCUS_NONE:
			sidebar_btn.grab_focus()
			await frames(3)
			key(KEY_DOWN)
			await frames(3)
			var f2 = main.get_viewport().gui_get_focus_owner()
			if f2 == sidebar_btn and sidebar_btn.find_valid_focus_neighbor(SIDE_BOTTOM) != null:
				note("tab_navigazione", str(id), "freccia giù dal menù laterale non sposta il focus", "basso")
	# Invio/Spazio attivano il pulsante con il focus
	await goto("summary")
	var hero = btn_of("hero")
	if hero != null and not hero.disabled and not hero.has_meta("req_target"):
		hero.grab_focus()
		await process_frame
		key(KEY_ENTER)
		await frames(4)
		if screen_id() != "hero":
			note("tab_navigazione", "menu", "Invio sul pulsante «Eroe» con il focus non lo apre (schermata %s)" % screen_id(), "alto")


func check_leaks() -> void:
	var ids = (main.get("_menu_ids") as Array).duplicate()
	for id in ids:
		await goto("summary")
		for i in 3:
			await goto(str(id))
			await goto("summary")
		await frames(6)
		var n0 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var o0 = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var m0 = OS.get_static_memory_usage()
		for i in 15:
			await goto(str(id))
			await frames(2)
			await goto("summary")
			await frames(2)
		await frames(8)
		var n1 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var o1 = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var m1 = OS.get_static_memory_usage()
		stats["leak_" + str(id)] = [n1 - n0, o1 - o0, snappedf((m1 - m0) / 1024.0, 1.0)]
		if n1 - n0 > 30:
			note("fuga_di_nodi", str(id), "aprendo e chiudendo la schermata 15 volte i nodi crescono di %d (orfani %+d, memoria %+.0f KB)" % [n1 - n0, o1 - o0, (m1 - m0) / 1024.0], "alto")
		elif o1 - o0 > 5:
			note("nodi_orfani", str(id), "15 aperture lasciano %d nodi orfani in più" % (o1 - o0), "medio")


## Tempo di CPU del thread principale in ns (Linux: schedstat del thread). Con la macchina carica il tempo d'orologio
## di un aggiornamento e' gonfiato dagli altri processi; il tempo di CPU no.
func cpu_ns() -> int:
	var f = FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)     # get_file_as_string non legge i file di /proc (lunghezza 0)
	if f == null:
		return -1
	var t = f.get_line()
	return int(t.split(" ")[0]) if t != "" else -1


func check_timing() -> void:
	var ids = (main.get("_menu_ids") as Array).duplicate()
	var cur_state = {}
	for id in ids:
		if not await goto(str(id)):
			continue
		await frames(4)
		await modals()
		var arr = []
		var cpu = []
		for i in 40:
			var c0 = cpu_ns()
			var t0 = Time.get_ticks_usec()
			main.call("_on_ui_tick")
			arr.append((Time.get_ticks_usec() - t0) / 1000.0)
			if c0 >= 0:
				cpu.append((cpu_ns() - c0) / 1000000.0)
			await process_frame
		arr.sort()
		cpu.sort()
		var n = arr.size()
		var has_cpu = cpu.size() == n
		cur_state[str(id)] = {"wall_p50": arr[n / 2], "wall_p95": arr[int(n * 0.95)], "wall_max": arr[n - 1],
			"cpu_p50": cpu[n / 2] if has_cpu else -1, "cpu_p95": cpu[int(n * 0.95)] if has_cpu else -1,
			"cpu_max": cpu[n - 1] if has_cpu else -1}
		var ref = cpu[int(n * 0.95)] if has_cpu else arr[int(n * 0.95)]
		if ref > SLOW_MS:
			note("schermata_lenta", str(id), "aggiornamento (_on_ui_tick) p95 %.1f ms di CPU (%.1f ms d'orologio), max %.1f ms (soglia 16)" % [ref, arr[int(n * 0.95)], cpu[n - 1] if has_cpu else arr[n - 1]], "alto" if ref > 33.0 else "medio")
		elif arr[int(n * 0.95)] > SLOW_MS:
			note("schermata_lenta_solo_orologio", str(id), "p95 %.1f ms d'orologio ma solo %.1f ms di CPU: rallentamento da carico della macchina" % [arr[int(n * 0.95)], ref], "basso")
	stats["timing_ms"] = cur_state
	var live = {}
	for id in timings.keys():
		var arr2 = (timings[id] as Array).duplicate()
		if arr2.size() < 5:
			continue
		arr2.sort()
		live[id] = {"n": arr2.size(), "p95": arr2[int(arr2.size() * 0.95)], "max": arr2.back()}
	stats["timing_live_ms"] = live


func _finish() -> void:
	stats["wall_s"] = (Time.get_ticks_msec() - _wall0) / 1000.0
	stats["play_s"] = _play()
	stats["quest_log"] = quest_log
	Node.print_orphan_nodes()
	var ids = Node.get_orphan_node_ids()
	var by = {}
	for oid in ids:
		var o = instance_from_id(oid)
		if o == null:
			continue
		var scr = o.get_script()
		var key = "%s|%s" % [o.get_class(), scr.resource_path if scr != null else "-"]
		by[key] = int(by.get(key, 0)) + 1
		if int(by[key]) <= 4:
			var info = []
			for ch in o.get_children():
				info.append("%s:%s" % [ch.get_class(), (ch.text if "text" in ch else ch.name)])
			print("ORFANO ", key, " figli=", info.slice(0, 4), " meta=", o.get_meta_list(), " nome=", o.name)
	stats["orfani_per_tipo"] = by
	print("ORFANI ", by)
	var tf = FileAccess.open(out_dir.path_join("trace.txt"), FileAccess.WRITE)
	tf.store_string("\n".join(trace_all))
	tf.close()
	var f = FileAccess.open(out_dir.path_join("findings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"findings": findings.values(), "stats": stats, "samples": samples}, "  "))
	f.close()
	print("NOVIZIO DONE findings=", findings.size(), " clicks=", stats.clicks, " wall=", stats.wall_s)
	quit(0)


## Salva dal pulsante, esce al menù principale dal menu di pausa (Esc), «Continua» e confronta lo stato.
func check_save_roundtrip() -> void:
	await modals()
	await goto("summary")
	var snap = _state_snap()
	var saved = [false]
	var cb = func(ok: bool) -> void: saved[0] = ok
	root.get_node("EventBus").connect("save_completed", cb)
	var sb = lib.find_buttons(main, ["SaveButton"], true)
	if sb.is_empty():
		note("vicolo_cieco", "summary", "nessun pulsante «Salva» nella barra superiore", "alto")
	else:
		await click(sb[0], "(Salva)")
		for i in 120:
			await process_frame
			if saved[0]:
				break
		if not saved[0]:
			note("pulsante_senza_effetto", "summary", "«Salva» non produce save_completed(ok) entro 2 s", "alto")
	root.get_node("EventBus").disconnect("save_completed", cb)
	key(KEY_ESCAPE)
	await frames(4)
	var fb = root.get_node("Feedback")
	var pm = fb.get("_pause_menu")
	if pm == null or not is_instance_valid(pm):
		note("scorciatoia", "tasto Esc", "Esc dal Riepilogo non apre il menu di pausa", "alto")
		return
	var mm = lib.find_buttons(pm, ["UI_MAIN_MENU"], true)
	if mm.is_empty():
		note("vicolo_cieco", "menu_pausa", "il menu di pausa non ha «Menù principale»", "alto")
		return
	await click(mm[0], "(Menù principale)")
	for i in 90:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == START:
			break
	if current_scene == null or current_scene.scene_file_path != START:
		note("pulsante_senza_effetto", "menu_pausa", "«Menù principale» non riporta al menù iniziale", "alto")
		return
	await frames(5)
	scan("start_menu_dopo")
	await back_to_game()
	await frames(10)
	await modals()
	if main == null or current_scene == null or current_scene.scene_file_path != MAIN:
		note("vicolo_cieco", "start_menu", "«Continua» non riporta alla partita", "alto")
		return
	var snap2 = _state_snap()
	for k in snap:
		if str(snap[k]) != str(snap2.get(k)):
			note("salvataggio", "menu", "dopo salva -> menù -> Continua «%s» cambia: %s -> %s" % [k, str(snap[k]), str(snap2.get(k))], "alto")
	sample("dopo_ricarica")


func _state_snap() -> Dictionary:
	var q = quests_sys()
	return {"gold": GS.call("gold"), "unlocks": (GS.data.get("unlocks", []) as Array).size(), "main_quest": main_quest(),
		"menu": (main.get("_menu_ids") as Array).size(), "locale": SET.call("get_value", "locale"),
		"total_level": GS.call("total_level"), "bank_slots": GM.call("system", "bank").used_slots()}


func probe(what: String) -> void:
	await modals()
	if what == "sell":
		await goto("bank")
		await frames(3)
		var sb = lib.find_buttons(current(), ["UI_UIA_SELL_BTN"], true)
		print("sell buttons ", sb.size())
		await click(sb[0], "(vendi in blocco)")
		await frames(6)
		for w in lib.open_windows():
			print("WINDOW ", w.name, " class=", w.get_class(), " embedded=", w.is_embedded(), " pos=", w.position, " size=", w.size)
			for b in lib.visible_controls(w):
				if b is BaseButton:
					var vp = b.get_viewport()
					lib.mouse_move(vp, lib.center_of(b))
					await process_frame
					print("  BTN ", b.name, " | ", lib.disp(b), " | ", b.get_class(), " dis=", b.disabled, " rect=", b.get_global_rect(), " hover=", vp.gui_get_hovered_control(), " vp_is_root=", vp == root)
	if what == "farm":
		for i in 3:
			main.call("_update_slow")
			print("farm badge=", main.call("badge_count", "skill:farming"), " ready=", GM.call("system", "farming").ready_count())
			await goto("skill:farming")
			await frames(5)
			for b in lib.buttons(current(), false):
				print("  BTN ", b.name, " | ", lib.disp(b), " dis=", b.disabled, " vis=", lib.really_visible(b))
			var hb = lib.find_buttons(current(), ["UI_FARM_HARVEST_ALL", "UI_FARM_HARVEST"], true)
			print("harvest candidates ", hb.size())
			if not hb.is_empty():
				print("click ", await click(hb[0], "(raccolta)"))
				await frames(5)
			print("dopo: ready=", GM.call("system", "farming").ready_count())
			await play_for(30.0)
	if what == "bankbtn":
		await goto("bank")
		await frames(4)
		var rows = []
		for b in lib.visible_controls(current()):
			if b is BaseButton and b.has_method("set_item") and lib.really_visible(b):
				rows.append(b)
		print("righe ", rows.size())
		await click(rows[0], "(riga)")
		await frames(4)
		for key_text in ["UI_BANK_LOCK", "UI_BANK_UNLOCK", "UI_BANK_QUICK_SELL"]:
			var bt = lib.find_buttons(current(), [key_text], true)
			print(key_text, " -> ", bt.size())
			if not bt.is_empty():
				print(" click ", await click(bt[0], "(" + key_text + ")"))
				await frames(5)


## Prova ogni pulsante attivo di ogni schermata, una volta: errori di script e pulsanti morti.
func check_sweep() -> void:
	var ids = (main.get("_menu_ids") as Array).duplicate()
	for id in ids:
		await modals(false)
		if not await goto(str(id)):
			continue
		await frames(4)
		await modals(false)
		var list = []
		for b in lib.buttons(main.get("_host"), true):
			if not risky(b) and lib.really_visible(b) and not b.has_meta("req_target"):
				list.append(b)
		var n = 0
		for b in list:
			if n >= 25:
				break
			if not is_instance_valid(b) or not b.is_visible_in_tree() or b.disabled:
				continue
			n += 1
			var r = await press_judge(b, "giro dei pulsanti")
			await modals(false)
			scan()
			if screen_id() != str(id):
				await goto(str(id))
				await frames(3)
		stats["sweep_" + str(id)] = n
func probe_mining() -> void:
	if true:
		for aid in ["mine_copper"]:
			await do_action(aid)
		await goto("skill:mining")
		await play_for(30.0)
		await frames(5)
		scan()
		var img = root.get_texture().get_image()
		img.save_png(out_dir.path_join("mining.png"))
		var sb = lib.find_buttons(current(), ["UI_SKILLS_STOP"], true)
		print("stop ", sb.size())
		for b in lib.buttons(current(), false):
			print("  BTN ", b.name, " | ", lib.disp(b), " rect=", b.get_global_rect(), " vis=", b.is_visible_in_tree())


## Cambia lingua dalle Impostazioni (tendina, tastiera), controlla menù e schermate nella nuova lingua e torna indietro.
func check_language_switch() -> void:
	await modals()
	if not await goto("settings"):
		return
	await frames(4)
	var obs = []
	for c in lib.visible_controls(current()):
		if c is OptionButton:
			obs.append(c)
	var lang_ob = null
	for o in obs:
		if o.item_count == 2 and (o.get_item_text(0) == "UI_LANG_IT" or o.get_item_text(1) == "UI_LANG_EN"):
			lang_ob = o
	if lang_ob == null:
		note("no_se_como", "settings", "nessuna tendina della lingua nelle Impostazioni", "medio")
		return
	var orig = str(SET.call("get_value", "locale"))
	var before_txt = lib.disp(btn_of("bank"))
	var target_i = 1 if lang_ob.selected == 0 else 0
	await click(lang_ob, "(lingua)")
	await frames(3)
	await popup_choose(lang_ob, target_i)
	await frames(2)
	var now = str(SET.call("get_value", "locale"))
	if now == orig:
		note("tendina_non_seleziona", "settings", "la tendina della lingua non cambia la lingua (resta %s)" % orig, "alto")
		return
	locale = now
	await frames(6)
	var after_txt = lib.disp(btn_of("bank"))
	if after_txt == before_txt:
		note("lingua_non_aggiorna", "menu", "dopo il cambio di lingua il menù laterale dice ancora «%s»" % after_txt, "alto")
	scan("impostazioni_altra_lingua")
	for id in (main.get("_menu_ids") as Array).duplicate():
		if str(id) != "settings" and await goto(str(id)):
			await frames(4)
			await modals(false)
			scan("lingua_cambiata:" + str(id))
	await goto("settings")
	await frames(4)
	for c in lib.visible_controls(current()):
		if c is OptionButton and c.item_count == 2 and c.get_item_text(0) == "UI_LANG_IT":
			lang_ob = c
	if lang_ob == null or not is_instance_valid(lang_ob) or not lang_ob.is_visible_in_tree():
		note("no_se_como", "settings", "dopo il cambio di lingua la tendina della lingua non si ritrova nelle Impostazioni", "medio")
		SET.call("set_value", "locale", orig)
		locale = orig
		return
	await click(lang_ob, "(lingua, ritorno)")
	await frames(3)
	await popup_choose(lang_ob, 0 if orig == "it" else 1)
	await frames(2)
	locale = str(SET.call("get_value", "locale"))
	if locale != orig:
		note("tendina_non_seleziona", "settings", "il ritorno alla lingua %s non riesce" % orig, "alto")
		SET.call("set_value", "locale", orig)
		locale = orig


func probe_sellclick() -> void:
	await modals()
	await goto("bank")
	await frames(3)
	var sb = lib.find_buttons(current(), ["UI_UIA_SELL_BTN"], true)
	await click(sb[0], "(vendi in blocco)")
	await frames(6)
	var ws = lib.open_windows()
	print("finestre ", ws.size())
	var w = ws[0]
	var okb = w.get_ok_button()
	print("ok rect=", okb.get_global_rect(), " w.position=", w.position, " w.size=", w.size, " decor=", w.get_position_with_decorations(), " disabled=", okb.disabled)
	var c = lib.center_of(okb)
	var absp = Vector2(w.position) + c
	print("abs=", absp)
	var g0 = GS.call("gold")
	for m in [true, false]:
		var ev = InputEventMouseMotion.new()
		ev.position = absp
		ev.global_position = absp
		Input.parse_input_event(ev)
		await frames(2)
	for pressed in [true, false]:
		var ev2 = InputEventMouseButton.new()
		ev2.button_index = MOUSE_BUTTON_LEFT
		ev2.pressed = pressed
		ev2.position = absp
		ev2.global_position = absp
		ev2.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(ev2)
		await frames(2)
	await frames(4)
	print("dopo clic: finestra visibile=", w.visible if is_instance_valid(w) else "liberata", " oro ", g0, " -> ", GS.call("gold"))


func probe_farm2() -> void:
	await modals()
	var fm = GM.call("system", "farming")
	var bank = GM.call("system", "bank")
	bank.add("seed_potato", 4, "test")
	print("plant ", fm.plant("garden", 0, "farm_potato"), " ", fm.plant("garden", 1, "farm_potato"))
	fm.plot("garden", 0)["remaining_s"] = 0.0
	fm.plot("garden", 1)["remaining_s"] = 0.0
	print("ready_count=", fm.ready_count())
	main.call("_update_slow")
	print("badge=", main.call("badge_count", "skill:farming"))
	await goto("skill:farming")
	await frames(4)
	for b in lib.buttons(current(), false):
		print("  BTN ", b.name, " | ", lib.disp(b), " dis=", b.disabled, " vis=", b.is_visible_in_tree())
	await frames(10)
	print("dopo 10 frame:")
	for b in lib.buttons(current(), false):
		print("  BTN ", b.name, " | ", lib.disp(b), " dis=", b.disabled)


func probe_dosell() -> void:
	await modals()
	var g0 = GS.call("gold")
	await do_sell()
	print("DOSELL oro ", g0, " -> ", GS.call("gold"), " finestre ", lib.open_windows().size())


func probe_tut() -> void:
	await modals()
	var ts0 = GM.call("system", "tutorial")
	for sid0 in ["g_sidebar", "g_open_pine", "g_pine", "g_quests", "g_open_copper", "g_move", "g_move2", "b_level", "b_mastery", "b_compare"]:
		ts0.call("mark_seen", sid0)
	(GS.data.get("unlocks", []) as Array).append("feature:perks")
	GM.call("system", "skills").call("add_xp", "woodcutting", float(Formulas.xp_total_for_level(12)))
	await goto("skill:woodcutting")
	for i in 80:
		var td = root.find_child("TutorialDirector", true, false)
		if td == null:
			print("TUT nessun director")
			break
		var showing = td.call("is_showing")
		var sid = td.call("current_step_id")
		var nxt = td.find_child("TutorialNext", true, false)
		print("TUT i=", i, " showing=", showing, " step=", sid, " next_visible=", nxt.is_visible_in_tree() if nxt else "-", " blocking=", td.call("is_blocking"))
		if showing:
			var ts = td.get("_ts")
			print("   seen? ", ts.call("is_seen", sid), " card vis=", td.find_child("TutorialCard", true, false).visible)
			if nxt != null and nxt.is_visible_in_tree():
				await click(nxt, "(probe Avanti)", false)
			await frames(4)
			print("   dopo: showing=", td.call("is_showing"), " step=", td.call("current_step_id"), " seen=", ts.call("is_seen", sid))
		else:
			await play_for(6.0)


func probe_tut2() -> void:
	await modals()
	var ts0 = GM.call("system", "tutorial")
	for sid0 in ["g_sidebar", "g_open_pine", "g_pine", "g_quests", "g_open_copper", "g_move", "g_move2", "b_level", "b_mastery", "b_compare", "f_hero", "f_combat", "f_feast", "f_keysmith", "f_perks", "f_queue"]:
		ts0.call("mark_seen", sid0)
	(GS.data.get("unlocks", []) as Array).append("feature:crates")
	await goto("combat")
	for i in 60:
		var td = root.find_child("TutorialDirector", true, false)
		var showing = td.call("is_showing")
		var sid = td.call("current_step_id")
		if showing:
			var nxt = td.find_child("TutorialNext", true, false)
			var ts = td.get("_ts")
			print("T2 i=", i, " step=", sid, " screen=", screen_id(), " next_vis=", nxt.is_visible_in_tree(), " seen=", ts.call("is_seen", sid), " _step=", td.get("_step").get("id", "?"))
			var r = await click(nxt, "(probe Avanti)", false)
			await frames(4)
			print("   click=", r, " dopo: showing=", td.call("is_showing"), " step=", td.call("current_step_id"), " seen=", ts.call("is_seen", sid), " seen_list=", (ts.get("state").get("seen") as Array).size())
		else:
			await play_for(3.0)
