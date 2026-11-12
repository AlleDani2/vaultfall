extends "res://scripts/novice_base.gd"
## Playtest del NOVIZIO (resoconto 121): gioca dall'inizio usando SOLO la UI vera. I clic sono eventi del mouse veri spinti nella
## finestra (si vede se un controllo è coperto dal velo/scheda del tutorial), si segue il tutorial guidato, «Obiettivo attuale»
## e i suoi «Vai», le Missioni. Scrive un diario (diario.txt) e le catture (xvfb). Non tocca i salvataggi veri.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##       -s res://scripts/novice_ui.gd -- <cartella> [it|en] [riduci:0|1] [quest_finale] [seme]
## Passi finali: lo stesso script si ferma alla missione indicata (default main_c1_q6).


var reduce := false
var last_quest := "main_c1_q6"
var seed_value := 7
var _dir: Object
var _steps_seen: Array = []
var _stuck_goal := {}
var _bot: Object
var _assists := 0
var _overlay_n := 0
var _prepared := false
var _no_progress := 0
var _last_q_sig := ""
var mode := "goal"          # goal = segue «Obiettivo attuale» · quests = apre Missioni e preme il primo «Vai»
var keyboard := false
var _skip_done := false
var sweep := false           # alla fine concede gli sblocchi dei passi mancanti (setup) e controlla che ognuno compaia e si possa seguire con la UI
var deep_to := ""           # se non vuoto: dopo la fase UI il bot gioca i sistemi fino a questa missione, con controlli UI a ogni missione
var vai_checked: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		loc = args[1]
	if args.size() > 2:
		reduce = args[2] == "1"
	if args.size() > 3:
		last_quest = args[3]
	if args.size() > 4:
		mode = args[4]
	if args.size() > 5:
		keyboard = args[5] == "1"
	if args.size() > 6:
		deep_to = args[6]
	if args.size() > 7:
		sweep = args[7] == "1"
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("SaveService").set("save_dir", "user://novice_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "locale", loc)
	root.get_node("Settings").call("set_value", "tutorials", true)
	root.get_node("Settings").call("set_value", "reduce_motion", reduce)
	_run.call_deferred()


# ------------------------------------------------------------------ tutorial

## Se c'è un passo del tutorial in mostra: lo guarda (cattura), lo segue come farebbe un novizio. true se ha agito.
func handle_tutorial() -> bool:
	if _dir == null or not _dir.call("is_showing"):
		return false
	var sid := str(_dir.call("current_step_id"))
	var card := _dir.get_node("TutorialCard") as Control
	var title := (_dir.find_child("TutorialTitle", true, false) as Label).text
	var body := (_dir.find_child("TutorialBody", true, false) as Label).text
	var key := str(_dir.call("highlighted_key"))
	if not _steps_seen.has(sid):
		_steps_seen.append(sid)
		say("TUTORIAL %s «%s» bersaglio=%s schermata=%s" % [sid, title, key, cur()])
		say("   testo: " + body.replace("\n", " "))
		await frames(6)
		if title.length() > 60 or title.begins_with("UI_") or body.begins_with("UI_"):
			problem("testo del passo %s non tradotto o troppo lungo" % sid)
		if title.is_empty() or body.is_empty():
			problem("passo %s con testo vuoto" % sid)
		await shot_once("tut_" + sid, "tut_" + sid)
		# la scheda non deve coprire il bersaglio
		var hole: Rect2 = _dir.call("highlight_rect")
		if hole.size.x > 0.0 and card.visible:
			var cr := card.get_global_rect()
			var inter := cr.intersection(hole)
			if hole.size.x * hole.size.y < 0.3 * root.get_visible_rect().size.x * root.get_visible_rect().size.y \
					and inter.get_area() > 0.15 * hole.get_area():
				problem("passo %s: la scheda copre il bersaglio %s (%.0f%%)" % [sid, key, 100.0 * inter.get_area() / hole.get_area()])
		var vr := root.get_visible_rect()
		if card.visible and not vr.encloses(card.get_global_rect().grow(-1.0)):
			problem("passo %s: la scheda esce dallo schermo %s" % [sid, str(card.get_global_rect())])
	if mode == "skip":
		if not _skip_done:
			var sa := _dir.find_child("TutorialSkipAll", true, false) as Button
			say("MODO SALTA: premo «%s» sul passo %s" % [shown(sa), sid])
			_skip_done = true
			await click(sa, "Salta il tutorial")
			await frames(10)
			if bool(_dir.call("is_showing")):
				problem("«Salta il tutorial»: il passo %s è ancora in mostra" % sid)
			return true
		problem("«Salta il tutorial» non ha fermato i suggerimenti: compare ancora %s" % sid)
	var step: Dictionary = load("res://src/tutorial/TutorialCatalog.gd").get_step(sid)
	if str(step.get("mode", "ack")) == "act":
		var tgt: Control = TutorialTargets.find(self, key) if not key.is_empty() else null
		if tgt == null:
			return false
		# un novizio va dove il tutorial dice: se non è sulla schermata giusta, il bersaglio evidenziato è il menù
		var ok := await click(tgt, "passo " + sid)
		if not ok:
			var sk := _dir.find_child("TutorialSkipStep", true, false) as Button
			problem("passo %s: il bersaglio evidenziato non è cliccabile, il novizio usa «Salta questo passo»" % sid)
			if sk != null:
				await click(sk, "salta passo")
		return true
	var nx := _dir.find_child("TutorialNext", true, false) as Button
	if nx != null and nx.is_visible_in_tree():
		await click(nx, "Avanti " + sid)
		return true
	return false


# ------------------------------------------------------------------ obiettivo

func claim_ready() -> bool:
	var g: Object = goal_panel()
	if g == null or not g.visible:
		return false
	await ensure_goal_strip()
	var d: Dictionary = g.call("goal")
	if str(d.get("kind", "")) != "claim":
		return false
	var go := g.find_child("GoButton", true, false) as Button
	if go == null:
		return false
	say("OBIETTIVO: da riscattare «%s»; premo «%s»" % [str(d.get("title", "")), go.text])
	await click(go, "obiettivo riscatta")
	await frames(6)
	if bool(system("quests").call("is_done", str(d.get("qid", "")))):
		say("   riscattata con un solo clic dal riquadro")
		return true
	# arrivati in Missioni: «Riscatta» (ogni pulsante di riscatto visibile)
	var cl := buttons(_main.find_child("Host", true, false), func(b): return shown(b) == tr_en("UI_QUESTS_CLAIM") or shown(b).begins_with(tr_en("UI_QG_CLAIM_ALL").split("%")[0].split("(")[0]))
	if cl.is_empty():
		problem("«Riscatta» non trovato in Missioni dopo il Vai dell'obiettivo (schermata %s)" % cur())
		return true
	await click(cl[0], "riscatta")
	await frames(4)
	return true


## La striscia Obiettivo (F3) è nascosta in Riepilogo e Missioni: se serve un suo pulsante e non si vede, si apre una schermata dove c'è.
func ensure_goal_strip() -> void:
	var go := TutorialTargets.find(self, "goal_go")
	if go != null:
		return
	for id in ["skill:woodcutting", "bank"]:
		if cur() != id and TutorialTargets.find(self, "menu:" + id) != null:
			await open_menu(id)
			await frames(6)
			return


## Segue il «Vai» (dell'Obiettivo attuale, o della schermata Missioni in modalità `quests`) e fa quello che dice la schermata.
func follow_goal() -> bool:
	var g: Object = goal_panel()
	if g == null or not g.visible:
		return false
	var d: Dictionary = g.call("goal")
	if str(d.get("kind", "")) != "quest":
		return false
	var qid := str(d.qid)
	var tgt: Dictionary = d.get("target", {})
	var key := "goal_" + qid
	var go: Button = null
	if mode == "quests":
		if cur() != "quests":
			await open_menu("quests")
		await frames(4)
		go = TutorialTargets.find(self, "quest_go") as Button
		if go == null:
			problem("%s: in Missioni non c'è nessun «Vai» in evidenza (quest_go)" % qid)
			return false
		if not _shots_taken.has(key):
			say("MISSIONI %s: «%s» | «Vai» = «%s»" % [qid, str(d.title), shown(go)])
			await shot_once(key, "missioni_" + qid)
	else:
		await ensure_goal_strip()
		go = g.find_child("GoButton", true, false) as Button
		if go == null or not go.visible:
			return false
		if not _shots_taken.has(key):
			say("OBIETTIVO %s: %s | come: %s | pulsante «%s»" % [qid, str(d.title), str(d.how).replace("\n", " "), go.text])
			await shot_once(key, "obiettivo_" + qid)
	await click(go, "Vai di " + qid)
	await frames(6)
	if not tgt.is_empty() and cur() != str(tgt.screen):
		problem("%s: «Vai» doveva aprire %s ma siamo in %s" % [qid, str(tgt.screen), cur()])
	var did := await act_on_screen(tgt)
	if not did:
		return false
	return true


## Cosa fa un novizio su una schermata aperta dal «Vai»: mansioni = Avvia; combattimento = Combatti; altro = non sa.
func act_on_screen(tgt: Dictionary) -> bool:
	var scr := cur()
	var host := _main.find_child("Host", true, false)
	if scr.begins_with("skill:"):
		var cands := buttons(host, func(b): return b.is_in_group("tut:action:" + str(b.get_meta("tut", "")).substr(7)) and str(b.get_meta("tut", "")).begins_with("action:"))
		var skills: Object = system("skills")
		# prima azione non in corso
		for b in cands:
			var aid := str(b.get_meta("tut")).substr(7)
			if skills.call("current_action") != aid:
				await shot_once("skill_" + scr, "schermata_" + scr.replace(":", "_"))
				say("   azione: premo Avvia su «%s»" % aid)
				return await click(b, "Avvia " + aid)
		return skills.call("current_action") != ""
	if scr == "combat":
		var sb := TutorialTargets.find(self, "combat_start")
		if sb != null and not sb.disabled:
			await shot_once("combat_" + str(_n), "combattimento")
			var ok := await click(sb, "Combatti")
			await frames(4)
			var dl: Window = popup_window()
			say("   dopo «Inizia a combattere»: clic=%s in_combattimento=%s dialogo=%s" % [str(ok), str(system("combat").call("in_combat")), "sì" if dl != null else "no"])
			return ok
		return false
	if scr == "hero":
		var rows := buttons(host, func(b): return b.get_script() != null and b.get_script().get_global_name() == &"EquipPickRow")
		if rows.is_empty():
			return false
		await shot_once("hero_" + str(_n), "eroe_equip")
		await click(rows[0], "scelgo il pezzo")
		var eq := buttons(host, func(b): return shown(b) == tr_en("UI_EQ_EQUIP"))
		if eq.is_empty():
			problem("Eroe: dopo aver scelto il pezzo non c'è «Equipaggia» attivo")
			return false
		say("   equipaggio «%s»" % shown(rows[0].find_child("*", true, false) if false else rows[0]))
		return await click(eq[0], "Equipaggia")
	return false


# ------------------------------------------------------------------ ciclo

func _run() -> void:
	var t_real := Time.get_ticks_msec()
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	current_scene = start
	await frames(10)
	await shot("menu_iniziale")
	var nb := start.find_child("NewGameButton", true, false) as Button
	await click(nb, "Nuova partita")
	await frames(4)
	await shot("scelta_slot")
	var nb2 := buttons(start.find_child("Slots", true, false), func(b): return shown(b) == tr_en("UI_NEW_GAME"))
	if nb2.is_empty():
		problem("nessun pulsante «Nuova partita» negli slot")
		save_diary()
		quit(1)
		return
	await click(nb2[0], "Nuova partita slot 1")
	await frames(30)
	_main = current_scene
	for i in 60:
		if current_scene != null and current_scene.get("current_id") != null:
			break
		await frames(5)
		_main = current_scene
	_main = current_scene
	if _main == null or _main.get("current_id") == null:
		problem("MainScreen non caricata")
		save_diary()
		quit(1)
		return
	_dir = _main.call("tutorial")
	_bot = load("res://scripts/bot_player.gd").new(game().get("sim"), func(dt: float) -> void: game().call("_on_step", dt))
	say("MainScreen pronta, lingua=%s riduci=%s" % [loc, str(reduce)])
	await frames(10)
	await shot("benvenuto")
	var wb := overlay_btn()
	if wb != null:
		await click(wb, "benvenuto")
	await frames(10)
	await run_loop()
	if keyboard:
		await keyboard_test()
	if mode == "skip":
		await skip_restart_test()
	if not deep_to.is_empty() and deep_to != "none":
		await deep_phase()
	if sweep:
		await sweep_steps()
	await guide_test()
	await shot("fine")
	say("FINE: durata reale %.0f s, passi del tutorial visti %d" % [(Time.get_ticks_msec() - t_real) / 1000.0, _steps_seen.size()])
	save_diary()
	quit(0)


func run_loop() -> void:
	var quests: Object = system("quests")
	var idle_rounds := 0
	var last_sig := ""
	for it in 4000:
		await frames(3)
		if quests.call("is_done", last_quest):
			say("raggiunta e riscattata la missione " + last_quest)
			return
		var pw := popup_window()
		if pw != null:
			await handle_popup(pw)
			continue
		var ob := overlay_btn()
		if ob != null:
			say("finestra «%s»: premo il pulsante" % ob.name)
			if mode == "skip" and _skip_done and ob.name == "TutorialOk":
				problem("dopo «Salta il tutorial» compare ancora la scheda «Novità» (TutorialOk)")
			await shot_once("ov_" + ob.name + str(_overlay_n), "finestra_" + ob.name)
			_overlay_n += 1
			await click(ob, "finestra")
			continue
		if await handle_tutorial():
			idle_rounds = 0
			continue
		if await claim_ready():
			idle_rounds = 0
			continue
		var sig := goal_text() + "|" + str(system("skills").call("current_action"))
		if sig != last_sig:
			last_sig = sig
			idle_rounds = 0
		# il novizio fa quello che dice l'obiettivo; se l'azione è già in corso, aspetta
		var g: Object = goal_panel()
		var d: Dictionary = g.call("goal") if g != null else {}
		var busy: bool = str(system("skills").call("current_action")) != "" or bool(system("combat").call("in_combat"))
		if busy and idle_rounds < 3:
			await run_sim(60.0)
			idle_rounds += 1
			continue
		if await follow_goal():
			idle_rounds = 0
			await run_sim(60.0)
			if quest_sig() == _last_q_sig:
				_no_progress += 1
			else:
				_no_progress = 0
				_last_q_sig = quest_sig()
			if _no_progress >= 3:
				await assist("la strada del «Vai» non fa progredire l'obiettivo")
			continue
		idle_rounds += 1
		if idle_rounds >= 3:
			problem("il novizio non sa cosa fare (aiuto del bot): obiettivo «%s» schermata %s" % [goal_text(), cur()])
			await shot("bloccato_%d" % _assists)
			await assist("novizio fermo")
			idle_rounds = 0
		await run_sim(30.0)


func quest_sig() -> String:
	var q: Object = system("quests")
	var id := str(q.call("current_main"))
	return id + str(q.call("progress_of", id))


## Il novizio non sa andare avanti: lo aiuta il bot (sistemi veri, non UI) e lo si annota come BLOCCO da esaminare.
func assist(why: String) -> void:
	_assists += 1
	say("AIUTO DEL BOT #%d (%s): %s" % [_assists, why, goal_text()])
	for i in 6:
		_bot.call("_decide")
		await run_sim(40.0)
	_no_progress = 0
	if _assists > 60:
		say("troppi aiuti: stop")
		save_diary()
		quit(2)


## Finestra di dialogo (ConfirmationDialog/AcceptDialog) aperta, o null.
func popup_window() -> Window:
	for w in root.find_children("*", "AcceptDialog", true, false):
		if (w as Window).visible:
			return w as Window
	return null


func handle_popup(w: Window) -> void:
	var bs := buttons(w)
	if bs.is_empty():
		w.hide()
		return
	var labels := bs.map(func(b): return shown(b))
	say("finestra di dialogo «%s» con pulsanti %s" % [w.title, str(labels)])
	await shot_once("dlg_" + w.title + str(_overlay_n), "dialogo")
	_overlay_n += 1
	var pick: Button = bs[0]
	var first_time := not _prepared
	for b in bs:
		# la prima volta il novizio legge l'avviso e si prepara («Mi preparo» apre l'Eroe); la seconda va comunque
		if shown(b) == (tr_en("UI_Q97_PREP_WAIT") if first_time else tr_en("UI_Q97_PREP_GO")):
			pick = b
	# i dialoghi sono sottofinestre incorporate: il controllo del «sotto il mouse» della finestra principale non li vede, quindi
	# il pulsante si preme direttamente (ogni altro clic di questo playtest è un evento mouse vero)
	var was_wait := shown(pick) == tr_en("UI_Q97_PREP_WAIT")      # il dialogo sparisce con la schermata: si legge PRIMA di premere
	pick.pressed.emit()
	await frames(6)
	if was_wait:
		_prepared = true
		say("   «Mi preparo» -> schermata %s" % cur())
		if cur() != "hero":
			problem("«Mi preparo» non porta all'Eroe (siamo in %s)" % cur())
		await prepare_hero()


## Un novizio che ha letto «Ti manca l'armatura»: apre Eroe, per ogni slot con pezzi disponibili sceglie il primo e preme Equipaggia.
func prepare_hero() -> void:
	if cur() != "hero":
		var hb := TutorialTargets.find(self, "menu:hero")
		if hb == null:
			return
		await click(hb, "menu Eroe")
		await frames(6)
	var host := _main.find_child("Host", true, false)
	var done := 0
	var slots := buttons(host, func(b): return b.get_script() != null and b.get_script().get_global_name() == &"EquipSlotButton")
	for sb in slots:
		await click(sb, "slot")
		var rows := buttons(host, func(b): return b.get_script() != null and b.get_script().get_global_name() == &"EquipPickRow")
		if rows.is_empty():
			continue
		await click(rows[0], "pezzo")
		var eq := buttons(host, func(b): return shown(b) == tr_en("UI_EQ_EQUIP"))
		if not eq.is_empty():
			await click(eq[0], "Equipaggia")
			done += 1
	say("   Eroe: equipaggiati %d pezzi con la UI" % done)
	await shot("eroe_preparato")


## Tastiera: 1–9, B, C, M, Q, L, F1, Esc, Tab (focus) e Invio/Spazio sul pulsante col focus.
func keyboard_test() -> void:
	say("--- prova tastiera ---")
	await ui_settle(600, 30)
	var ov: Object = null
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == &"OverlayHost":
			ov = c
	if ov != null and bool(ov.call("is_busy")):
		problem("tastiera: c'è ancora una finestra aperta (is_busy)")
	await press_key(KEY_ESCAPE)
	if cur() != "summary":
		problem("Esc non riporta al Riepilogo (siamo in %s)" % cur())
	var ids: Array = _main.get("_menu_ids")
	for i in mini(9, ids.size()):
		await press_key((KEY_1 + i) as Key)
		if cur() != str(ids[i]):
			problem("tasto %d dovrebbe aprire «%s» ma siamo in «%s»" % [i + 1, ids[i], cur()])
	for pair in [[KEY_B, "bank"], [KEY_C, "hero"], [KEY_M, "quests"], [KEY_F1, "manual"], [KEY_ESCAPE, "summary"]]:
		var uns_ok := true
		await press_key(pair[0] as Key)
		if cur() != pair[1] and uns().has("chapter:1") or (pair[1] == "summary" or pair[1] == "quests" or pair[1] == "manual") and cur() != pair[1]:
			problem("tasto %s dovrebbe aprire «%s» ma siamo in «%s»" % [OS.get_keycode_string(pair[0]), pair[1], cur()])
	await press_key(KEY_Q)
	say("   Q -> %s" % cur())
	# L: colonna destra
	var rc := _main.find_child("RightColumn", true, false) as Control      # dalla F3 sta in Root/Body (chiuso) o in Drawer (aperto)
	var before := rc.is_visible_in_tree()
	await press_key(KEY_L)
	await frames(6)
	if rc.is_visible_in_tree() == before:
		problem("L non apre/chiude il cassetto destro")
	await shot("tastiera_L")
	await press_key(KEY_L)
	await frames(6)
	# Tab: il focus si sposta e si vede
	await press_key(KEY_ESCAPE)
	var f0 := root.gui_get_focus_owner()
	await press_key(KEY_TAB)
	var f1 := root.gui_get_focus_owner()
	say("   Tab: focus da %s a %s" % [str(f0.name) if f0 != null else "nessuno", str(f1.name) if f1 != null else "nessuno"])
	if f1 == null or f1 == f0:
		problem("Tab non sposta il focus")
	await shot("tastiera_tab")
	# Invio su un pulsante col focus (Impostazioni nella barra)
	var st := _main.get("_settings_btn") as Button
	st.grab_focus()
	await press_key(KEY_ENTER)
	if cur() != "settings":
		problem("Invio su «Impostazioni» col focus non l'ha aperta (siamo in %s)" % cur())
	await press_key(KEY_ESCAPE)


# ------------------------------------------------------------------ fase profonda e Guida

## Tempo di «calma»: gestisce finestre, dialoghi, tutorial e riscatti finché per `quiet` fotogrammi non c'è più nulla da fare.
func ui_settle(max_frames: int = 900, quiet: int = 40) -> void:
	var calm := 0
	var n := 0
	while n < max_frames and calm < quiet:
		n += 1
		await frames(2)
		var pw := popup_window()
		if pw != null:
			await handle_popup(pw)
			calm = 0
			continue
		var ob := overlay_btn()
		if ob != null:
			say("finestra «%s»: premo il pulsante" % ob.name)
			await shot_once("ov_%s_%d" % [ob.name, _overlay_n], "finestra_" + ob.name)
			_overlay_n += 1
			await click(ob, "finestra")
			calm = 0
			continue
		if await handle_tutorial():
			calm = 0
			continue
		calm += 1


## Controllo del «Vai» dell'Obiettivo attuale: il clic porta alla schermata annunciata, e se il bersaglio chiede un oggetto o
## un livello, la schermata mostra davvero un'azione avviabile.
func check_goal_vai(qid: String) -> void:
	var g: Object = goal_panel()
	if g == null or not g.visible:
		problem("%s: l'«Obiettivo attuale» non è visibile" % qid)
		return
	g.call("refresh", true)
	await ensure_goal_strip()
	await frames(2)
	var d: Dictionary = g.call("goal")
	if str(d.get("kind", "")) != "quest":
		return
	if str(d.qid) != qid:
		return
	var go := g.find_child("GoButton", true, false) as Button
	var tgt: Dictionary = d.get("target", {})
	if tgt.is_empty():
		problem("%s: «Obiettivo attuale» senza «Vai» (come: %s)" % [qid, str(d.how).left(80)])
		return
	if go == null or not go.visible:
		problem("%s: pulsante «Vai» non visibile" % qid)
		return
	if str(d.how).is_empty() or str(d.how).begins_with("UI_"):
		problem("%s: istruzione «come fare» vuota o non tradotta" % qid)
	await click(go, "Vai di " + qid)
	await frames(8)
	var scr := cur()
	var want := str(tgt.screen)
	var res := "ok"
	if scr != want:
		res = "NO"
		problem("%s: «Vai» (%s) doveva aprire «%s» ma siamo in «%s»" % [qid, shown(go), want, scr])
	elif want.begins_with("skill:") and (tgt.get("params", {}) as Dictionary).has("produces"):
		var host := _main.find_child("Host", true, false)
		var acts := buttons(host, func(b): return str(b.get_meta("tut", "")).begins_with("action:"))
		if acts.is_empty():
			res = "VUOTO"
			problem("%s: il «Vai» apre %s filtrato su «%s» ma non mostra azioni avviabili" % [qid, scr, str((tgt.params as Dictionary).produces)])
	vai_checked.append(qid)
	say("VAI %s -> %s (%s)  «%s»" % [qid, scr, res, str(d.how).left(100).replace("\n", " ")])


func deep_phase() -> void:
	say("=== FASE PROFONDA: il bot gioca i sistemi fino a %s, la UI controlla ogni missione ===" % deep_to)
	var qs: Object = system("quests")
	var t_real := Time.get_ticks_msec()
	var guard := 0
	while guard < 90:
		guard += 1
		var qid := str(qs.call("current_main"))
		if qid.is_empty():
			say("storia principale finita")
			break
		await ui_settle(400, 25)
		await check_goal_vai(qid)
		await ui_settle(200, 25)
		var res: Dictionary = _bot.call("run_until_quest", qid, float(_bot.get("t")) + 6.0 * 3600.0)
		if not bool(res.ok):
			problem("il bot non riesce a completare %s (blocchi: %s)" % [qid, str(res.blocks).left(200)])
			await shot("bloccoprofondo_" + qid)
			break
		say("   %s completata (bot t=%.0f s, passi del tutorial finora %d, reale %.0f s)" % [qid, float(res.t), _steps_seen.size(), (Time.get_ticks_msec() - t_real) / 1000.0])
		await ui_settle(900, 40)
		if qid == deep_to:
			break
	say("=== fine fase profonda: %d passi del tutorial visti ===" % _steps_seen.size())


func guide_test() -> void:
	say("=== GUIDA: dinamiche scoperte e «Mostrami» ===")
	var ts: Object = system("tutorial")
	var c: Dictionary = ts.call("counts")
	say("contatore: %d su %d" % [int(c.seen), int(c.total)])
	var cat: Object = load("res://src/tutorial/TutorialCatalog.gd")
	var never: Array = []
	for st in cat.STEPS:
		if not bool(ts.call("is_seen", str(st.id))):
			never.append("%s(%s)" % [str(st.id), "disponibile" if bool(ts.call("available", str(st.id))) else "non ancora sbloccato"])
	say("passi NON visti automaticamente: %s" % ", ".join(PackedStringArray(never)))
	if not await open_menu("guide"):
		return
	var host := _main.find_child("Host", true, false)
	check_texts(host, "Guida")
	await shot("guida")
	var shown_ok := 0
	var tries := 0
	for st in cat.STEPS:
		var sid := str(st.id)
		if not bool(ts.call("available", sid)):
			continue
		if cur() != "guide":
			await open_menu("guide")
		var row := _main.find_child("Row_" + sid, true, false)
		if row == null:
			problem("Guida: riga del passo %s non trovata" % sid)
			continue
		var mb := buttons(row)
		if mb.is_empty():
			problem("Guida: il passo %s è sbloccato ma non ha «Mostrami»" % sid)
			continue
		tries += 1
		await click(mb[0], "Mostrami " + sid)
		await frames(12)
		var sc := str(st.get("screen", ""))
		var cid := str(_dir.call("current_step_id"))
		var key := str(_dir.call("highlighted_key"))
		var okk := cid == sid
		if sc != "" and cur() != sc:
			problem("Guida «Mostrami» %s: attesa la schermata %s, siamo in %s" % [sid, sc, cur()])
			okk = false
		if not okk:
			problem("Guida «Mostrami» %s: il passo in mostra è «%s»" % [sid, cid])
		else:
			shown_ok += 1
		if tries % 6 == 1:
			await shot("mostrami_" + sid)
		say("   Mostrami %s -> schermata %s, bersaglio %s" % [sid, cur(), key])
		if str(st.get("target", "")) != "" and key.is_empty() and str(st.get("target")) != "content":
			problem("Guida «Mostrami» %s: nessun bersaglio evidenziato (atteso %s)" % [sid, str(st.get("target"))])
		_dir.call("press_next")
		await frames(4)
		_dir.call("dismiss")
	say("«Mostrami» riusciti: %d su %d" % [shown_ok, tries])


## Dopo «Salta il tutorial»: la Guida dice «spento», e «Ricomincia» rimette in moto i suggerimenti.
func skip_restart_test() -> void:
	say("=== SALTA E RIAVVIA ===")
	await ui_settle(300, 20)
	if not _skip_done:
		problem("modo salta: nessun passo è mai comparso prima di %s" % last_quest)
	var ts: Object = system("tutorial")
	if bool(ts.call("active")):
		problem("dopo «Salta il tutorial» il tutorial risulta ancora attivo")
	if not await open_menu("guide"):
		return
	var host := _main.find_child("Host", true, false)
	await shot("guida_dopo_salta")
	var auto := _main.find_child("GuideAuto", true, false) as CheckBox
	if auto == null or auto.button_pressed:
		problem("Guida: la casella «suggerimenti automatici» dovrebbe essere spenta dopo «Salta»")
	var rb := _main.find_child("GuideRestart", true, false) as Button
	await click(rb, "Ricomincia il tutorial")
	await frames(20)
	for i in 40:
		await frames(6)
		if bool(_dir.call("is_showing")):
			break
	if not bool(_dir.call("is_showing")):
		problem("dopo «Ricomincia» nessun passo compare")
	else:
		say("   ripartito: %s" % str(_dir.call("current_step_id")))
		await shot("guida_riavviata")
		_dir.call("press_skip_all")
	await frames(5)


## Per ogni passo non ancora visto: il SETUP concede lo sblocco e la condizione (token, edificio, oggetto, Deposito quasi pieno, posti
## in coda), poi tutto il resto è UI: il passo deve comparire da solo, col bersaglio evidenziato e visibile, la scheda non deve
## coprirlo, e «Avanti» (o il clic sul bersaglio) lo deve far avanzare. Se un passo non compare è un vicolo cieco del tutorial.
func sweep_steps() -> void:
	say("=== SWEEP: tutti i passi, uno per uno ===")
	var ts: Object = system("tutorial")
	var cat: Object = load("res://src/tutorial/TutorialCatalog.gd")
	var un := uns()
	var shown_n := 0
	var missing: Array = []
	system("combat").call("stop")           # niente combattimento in corso: il tutorial non propone passi durante uno scontro rischioso (di proposito)
	await frames(10)
	for st in cat.STEPS:
		var sid := str(st.id)
		if bool(ts.call("is_seen", sid)):
			continue
		_grant_for_step(st, un)
		_main.call("build_menu")
		await frames(6)
		# la Direzione sceglie il prossimo passo dell'elenco: si lascia lavorare la UI finché compare QUESTO (o un altro, che si segue)
		var got := false
		for tries in 12:
			var d0 := _steps_seen.size()
			await ui_settle(400, 25)
			if bool(ts.call("is_seen", sid)):
				got = true
				break
			await frames(30)
		if got:
			shown_n += 1
			say("   SWEEP %s -> visto" % sid)
		else:
			missing.append(sid)
			problem("SWEEP: il passo %s non compare da solo anche con sblocco e condizione dati (token %s)" % [sid, str(st.get("token", ""))])
	say("SWEEP: %d passi comparsi, mancanti: %s" % [shown_n, str(missing)])


func _grant_for_step(st: Dictionary, un: Array) -> void:
	var tok := str(st.get("token", ""))
	if not tok.is_empty() and not un.has(tok):
		un.append(tok)
		root.get_node("EventBus").emit_signal("unlocked", tok)
	var c: Variant = st.get("cond", [])
	if (c as Array).is_empty():
		return
	match str(c[0]):
		"queue_slots":
			var m: Object = system("market")
			system("bank").call("add_gold", 5000)
			m.call("buy", "action_queue_1", 1)
		"building":
			var es: Object = system("estate")
			es.state.buildings[str(c[1])] = {"level": 1, "product": "", "grade": 1}
		"item":
			system("bank").call("add", str(c[1]), 1, "playtest")
		"bank_nearly_full":
			var bk: Object = system("bank")
			var ids: Array = []
			for it in DataRegistry_items():
				ids.append(it)
			for id in ids:
				if bool(bk.call("nearly_full")):
					break
				bk.call("add", id, 1, "playtest")
		"quest_reached", "quest_done":
			pass


func DataRegistry_items() -> Array:
	var dr: Node = root.get_node("DataRegistry")
	var out: Array = []
	for t in ["materials", "items"]:
		pass
	var all: Variant = dr.call("all_items") if dr.has_method("all_items") else {}
	if all is Dictionary:
		for k in all:
			out.append(str(k))
	return out
