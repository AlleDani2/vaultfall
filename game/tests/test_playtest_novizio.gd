extends GutTest
## Regressioni del playtest del novizio (resoconto 121): ogni difetto trovato giocando dall'inizio con la sola UI vera ha qui
## la sua prova.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old_motion: Variant
var _old_tut: Variant
var _old_locale: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_novizio_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_motion = Settings.get_value("reduce_motion")
	_old_tut = Settings.get_value("tutorials")
	_old_locale = Settings.get_value("locale")
	Settings.set_value("reduce_motion", true)
	Settings.set_value("tutorials", true)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("reduce_motion", _old_motion)
	Settings.set_value("tutorials", _old_tut)
	Settings.set_value("locale", _old_locale)


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func _welcome_done(main: Control) -> void:
	for c in main.get_children():
		if c is OverlayHost:
			var go: Button = c.find_child("WelcomeGo", true, false)
			if go != null:
				go.pressed.emit()
	await wait_process_frames(3)


func _kick(main: Control) -> TutorialDirector:
	var d: TutorialDirector = main.tutorial()
	for i in 600:                        # il banner «Missione completata» ha la precedenza sul tutorial: lo si lascia finire
		if not Fx.banner_active():
			break
		await wait_process_frames(2)
	for round in 2:
		d._gap = 0.0
		d._poll = 0.0
		await wait_process_frames(3)
		if not d.current_step_id().is_empty():
			break
	return d


## Al passo «Apri il Taglialegna» solo il menù evidenziato risponde, MA il «Vai» dell'Obiettivo attuale (che porta nello stesso
## posto) non resta muto sotto il velo: prima il novizio lo premeva e non succedeva nulla.
func test_il_vai_dell_obiettivo_passa_attraverso_il_passo_bloccante() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	assert_eq(d.current_step_id(), "g_sidebar")
	d.press_next()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_open_pine")
	assert_true(d.is_blocking())
	var go: Button = TutorialTargets.find(get_tree(), "goal_go") as Button
	assert_not_null(go, "il «Vai» dell'Obiettivo attuale è marcato")
	await wait_process_frames(2)
	var c := go.get_global_rect().get_center()
	for b in d._blockers:
		assert_false(b._has_point(c - b.position), "il clic sul «Vai» non è fermato da %s" % b.name)
	# il bersaglio evidenziato (menù Taglialegna) resta cliccabile: nessun bloccante lo copre (regressione: _has_point senza rettangolo)
	var target: Control = TutorialTargets.find(get_tree(), d.highlighted_key())
	assert_not_null(target)
	var tc := target.get_global_rect().get_center()
	for b in d._blockers:
		assert_false(b.visible and Rect2(b.position, b.size).has_point(tc) and b._has_point(tc - b.position), "il bersaglio non è coperto da %s" % b.name)
		assert_false(b._has_point(tc - b.position), "%s non prende il clic sul bersaglio" % b.name)
	# lontano dal bersaglio e dal «Vai» il bloccante ferma ancora i clic
	var stopped := false
	for b in d._blockers:
		if b.visible and b.size.x > 40.0 and b.size.y > 40.0 and b._has_point(Vector2(5, 5)):
			stopped = true
	assert_true(stopped, "il resto dello schermo resta bloccato")
	go.pressed.emit()
	await wait_process_frames(3)
	assert_eq(main.current_id, "skill:woodcutting", "il «Vai» apre il Taglialegna: il passo è fatto")


func test_clic_fermato_ricorda_cosa_premere() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	d.press_next()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_open_pine")
	d._blockers[0].blocked.emit()
	await wait_process_frames(3)
	var hint: Label = d.find_child("TutorialHint", true, false)
	assert_true(hint.visible)
	assert_eq(hint.text, tr("UI_TUT_BLOCKED"))
	assert_false(hint.text.begins_with("UI_"))


## «Riscatta» nel riquadro Obiettivo attuale ritira DAVVERO la ricompensa (prima apriva solo Missioni: due clic per un pulsante
## che prometteva di riscattare).
func test_riscatta_dal_riquadro_ritira_la_ricompensa() -> void:
	Game.new_game(1, "normal", 5)
	Settings.set_value("tutorials", false)
	var main := await _main()
	await _welcome_done(main)
	var q := Game.system("quests") as QuestSystem
	var need := QuestSystem.target_of(q.quest_def("main_c0_q1").objectives[0])
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": need}])
	Game.sim.tick(0.1)
	var panel: GoalPanel = main.find_child("GoalPanel", true, false)
	panel.refresh(true)
	assert_eq(panel.goal().kind, "claim")
	var go: Button = panel.find_child("GoButton", true, false)
	assert_eq(go.text, tr("UI_QUESTS_CLAIM"))
	go.pressed.emit()
	await wait_process_frames(2)
	assert_true(q.is_done("main_c0_q1"), "la ricompensa è stata ritirata con un solo clic")
	assert_eq(panel.goal().kind, "quest", "il riquadro passa subito alla missione successiva")
	assert_ne(main.current_id, "quests", "non serve aprire Missioni")


## Il riquadro «Amici» non compare finché gli Amici sono chiusi: il suo «Apri la Lobby» portava a una schermata bloccata e il
## clic restava muto.
func test_riquadro_amici_compare_solo_con_gli_amici_sbloccati() -> void:
	Game.new_game(1, "normal", 5)
	Settings.set_value("tutorials", false)
	var main := await _main()
	var fp: FriendsPanel
	for n in main.find_children("*", "PanelContainer", true, false):
		if n is FriendsPanel:
			fp = n
	assert_not_null(fp)
	assert_false(fp.visible, "a inizio partita il riquadro Amici non c'è")
	assert_false((GameState.data.unlocks as Array).has("feature:coop"))
	Game.system("unlock").grant("feature:coop")
	await wait_process_frames(2)
	assert_true(fp.visible, "con feature:coop il riquadro compare")


## Nessun vicolo cieco nella storia principale: con i SOLI sblocchi già ottenuti (missioni precedenti + quelli dati all'accettazione)
## ogni obiettivo ancora da fare ha un «Vai» che porta a una schermata AGIBILE. Regressione: main_c2_q2 chiedeva di costruire nella
## Tenuta, che si apriva solo riscattando la missione stessa (la storia si fermava al Capitolo II).
func test_storia_principale_senza_vicoli_ciechi() -> void:
	Game.new_game(1, "normal", 5)
	var q := Game.system("quests") as QuestSystem
	var unlocks: Array = GameState.data.unlocks
	var main: Array = []
	for d in DataRegistry.table("quests"):
		if str(d.get("kind", "")) == "main":
			main.append(d)
	var dead: PackedStringArray = []
	var granted: Array = unlocks.duplicate()
	for t in ["feature:run", "feature:prestige", "feature:coop"]:      # concessi dal codice (livello di rito, Corsa, prima Incursione), non da missioni
		granted.append(t)
	for d in main:
		var early: Array = q._early_tokens(d)
		var have: Array = granted.duplicate()
		for t in early:
			if not have.has(t):
				have.append(t)
		unlocks.clear()
		unlocks.append_array(have)
		ReqLink.reset_cache()
		for obj in d.get("objectives", []):
			var h := QuestGuide.howto(obj)
			var t: Dictionary = h.target
			if t.is_empty():
				dead.append("%s: %s senza Vai" % [d.id, JSON.stringify(obj)])
				continue
			var e := ScreenRegistry.get_entry(str(t.screen))
			if e.is_empty() or not ScreenRegistry.is_available(e, have):
				dead.append("%s: il Vai porta a «%s» che non è agibile" % [d.id, t.screen])
		for t in d.get("unlocks", []):
			if not granted.has(t):
				granted.append(t)
	assert_eq(dead.size(), 0, "vicoli ciechi:\n" + "\n".join(dead))


## Il banner «Missione completata» non copre più la scheda del tutorial: il passo aspetta che il banner sparisca.
func test_il_tutorial_aspetta_il_banner() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	assert_eq(d.current_step_id(), "g_sidebar")
	assert_true(d.visible)
	assert_true(Fx.banner("Prova", "banner"))
	await wait_process_frames(2)
	assert_true(Fx.banner_active())
	assert_false(d.visible, "con il banner in scena la scheda del tutorial sta ferma e nascosta")
	for i in 400:
		if not Fx.banner_active():
			break
		await wait_process_frames(2)
	await wait_process_frames(3)
	assert_true(d.visible, "finito il banner la scheda torna")


# ------------------------------------------------------------------ coop (playtest a due processi)

## IP o porta sbagliati: lo stato dice «Nessuna risposta» (non «Host sparito», che non è mai stato lì) e l'avviso esce una volta sola.
func test_coop_primo_collegamento_fallito_dice_nessuna_risposta() -> void:
	var svc := CoopNetService.instance()
	Game.new_game(1, "normal", 5)
	var notes: Array = []
	var cb := func(key: String, _p: Dictionary) -> void: notes.append(key)
	svc.notice.connect(cb)
	assert_eq(svc.join_room("127.0.0.1", 24990, "Bruno"), "")
	assert_false(svc.ever_connected)
	svc._on_host_lost()
	assert_eq(svc.status, CoopNetService.ST_SUSPENDED)
	assert_eq(svc.status_key(), "UI_COOPNET_ST_NOANSWER")
	svc._on_host_lost()
	svc._on_host_lost()
	var lost := notes.filter(func(k): return str(k).begins_with("UI_COOPNET_NOTE_"))
	assert_eq(lost, ["UI_COOPNET_NOTE_NO_ANSWER"], "l'avviso esce una volta sola e dice «nessuna risposta»")
	for k in ["UI_COOPNET_ST_NOANSWER", "UI_COOPNET_NOTE_NO_ANSWER"]:
		for loc in ["it", "en"]:
			TranslationServer.set_locale(loc)
			assert_ne(tr(k), k, "%s tradotta in %s" % [k, loc])
	TranslationServer.set_locale(str(_old_locale))
	svc.notice.disconnect(cb)
	svc.leave_room()
	# se l'host aveva risposto, invece, è davvero «sparito»
	svc.ever_connected = true
	svc.status = CoopNetService.ST_SUSPENDED
	assert_eq(svc.status_key(), "UI_COOPNET_ST_SUSPENDED")
	svc.ever_connected = false
	svc.status = CoopNetService.ST_OFFLINE


## Il soprannome scelto nella Lobby diventa anche il nome dentro i codici-eroe (prima restava «Eroe»), senza sovrascrivere un nome scelto.
func test_coop_soprannome_lobby_diventa_nome_dei_codici() -> void:
	var svc := CoopNetService.instance()
	Game.new_game(1, "normal", 5)
	var co := Game.system("coop") as CoopSystem
	assert_eq(co.state.name, "")
	assert_eq(svc.host_room(24991 + int(Time.get_ticks_usec() % 8), "Alba", "Brigata"), "")
	assert_eq(str(co.state.name), "Alba")
	svc.leave_room()
	assert_eq(svc.join_room("127.0.0.1", 24990, "Marta"), "")
	assert_eq(str(co.state.name), "Alba", "un nome già scelto non si cambia")
	svc.leave_room()
	co.set_my_name("")
	assert_eq(svc.saved_nick(), "Marta", "il campo soprannome si riempie con l'ultimo usato")


## Nei passi «premi proprio questo» resta cliccabile anche il «Vai» della schermata Missioni (prima, giocando da Missioni, il clic non faceva nulla).
func test_il_vai_di_missioni_passa_attraverso_il_passo_bloccante() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	d.press_next()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_open_pine")
	assert_true(main.show_screen("quests"))
	await wait_process_frames(4)
	var go: Button = TutorialTargets.find(get_tree(), "quest_go") as Button
	assert_not_null(go, "in Missioni c'è il «Vai» della missione in corso")
	var c := go.get_global_rect().get_center()
	for b in d._blockers:
		assert_false(b._has_point(c - b.position), "il «Vai» di Missioni non è fermato da %s" % b.name)
	go.pressed.emit()
	await wait_process_frames(3)
	assert_eq(main.current_id, "skill:woodcutting")


## Un dialogo esclusivo (es. «Non sei pronto a combattere») ha la precedenza: la scheda del tutorial aspetta che si risponda,
## perché i suoi pulsanti non riceverebbero i clic (rapporto 95 R6c).
func test_il_tutorial_aspetta_un_dialogo_aperto() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	assert_true(d.visible)
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "prova"
	main.add_child(dlg)
	dlg.popup_centered()
	await wait_process_frames(30)
	assert_false(d.visible, "con un dialogo aperto la scheda sta ferma")
	dlg.hide()
	await wait_process_frames(30)
	assert_true(d.visible, "chiuso il dialogo la scheda torna")
	dlg.queue_free()


## La freccia del tutorial non prova a disegnare un triangolo non valido (rapporto 95 R7: «triangulation failed»).
func test_la_freccia_non_disegna_triangoli_non_validi() -> void:
	assert_true(TutorialSpotlight.arrow_valid(PackedVector2Array([Vector2(10, 10), Vector2(0, 30), Vector2(20, 30)])))
	assert_false(TutorialSpotlight.arrow_valid(PackedVector2Array([Vector2(10, 10), Vector2(10, 10), Vector2(10, 10)])))
	assert_false(TutorialSpotlight.arrow_valid(PackedVector2Array([Vector2(NAN, 10), Vector2(0, 30), Vector2(20, 30)])))
	assert_false(TutorialSpotlight.arrow_valid(PackedVector2Array([Vector2(INF, 10), Vector2(0, 30), Vector2(20, 30)])))
	assert_false(TutorialSpotlight.arrow_valid(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])), "tre punti allineati")


## «Non sei preparato» non lascia il novizio senza strada: sotto l'avviso rosso c'è «Vai: Eroe», e «Mi preparo» nel dialogo porta all'Eroe.
func test_avviso_impreparato_porta_all_eroe() -> void:
	Game.new_game(1, "normal", 5)
	Settings.set_value("tutorials", false)
	for t in ["feature:combat", "skill:hero", "zone:millbrook"]:
		if not (GameState.data.unlocks as Array).has(t):
			(GameState.data.unlocks as Array).append(t)
	var main := await _main()
	await _welcome_done(main)
	assert_true(main.show_screen("combat"))
	await wait_process_frames(4)
	var scr: Control = main.current_screen()
	scr.refresh()
	var go: Button = scr.find_child("PrepGoHero", true, false)
	assert_not_null(go)
	assert_true(go.visible, "l'avviso di impreparazione ha il suo «Vai»")
	assert_true(go.text.begins_with(tr("UI_QG_GO_TO").split("{")[0].strip_edges()), "testo «Vai: …»: " + go.text)
	go.pressed.emit()
	await wait_process_frames(3)
	assert_eq(main.current_id, "hero")
	# dal dialogo: «Mi preparo» porta all'Eroe, «Combatti lo stesso» no
	assert_true(main.show_screen("combat"))
	await wait_process_frames(4)
	scr = main.current_screen()
	scr._on_start_pressed()
	await wait_process_frames(2)
	assert_true(scr._prep_dlg.visible)
	scr._prep_dlg.get_cancel_button().pressed.emit()
	await wait_process_frames(3)
	assert_eq(main.current_id, "hero", "«Mi preparo» apre l'Eroe")


## Il Quarzo Grezzo di `main_c3_q2` è un ritrovamento raro della Miniera (`secondary`): la guida non manda più a «comprarlo al Mercato»
## (un acquisto non fa avanzare l'obiettivo «raccogli»), ma dice cosa fare e apre la Miniera filtrata sulle azioni che lo lasciano trovare.
func test_guida_ritrovamento_raro_non_manda_al_mercato() -> void:
	Game.new_game(1, "normal", 5)
	for t in ["skill:mining", "feature:market"]:
		if not (GameState.data.unlocks as Array).has(t):
			(GameState.data.unlocks as Array).append(t)
	QuestGuide.reset_cache()
	ReqLink.reset_cache()
	var h := QuestGuide.howto({"type": "gather", "item": "gem_raw_quartz", "qty": 3})
	assert_eq(str(h.target.screen), "skill:mining", "il Vai apre la Miniera, non il Mercato")
	assert_eq(str(h.target.params.produces), "gem_raw_quartz")
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		var t2: String = QuestGuide.howto({"type": "gather", "item": "gem_raw_quartz", "qty": 3}).text
		assert_false(t2.contains("UI_"), "testo tradotto " + loc)
		assert_false(t2.to_lower().contains("mercato") or t2.to_lower().contains("market"), "non dice di comprarlo: " + t2)
	TranslationServer.set_locale(str(_old_locale))
	var a: Dictionary = DataRegistry.action("mine_copper")
	assert_true(QuestGuide.action_yields(a, "gem_raw_quartz"), "mine_copper lo lascia trovare")
	assert_true(QuestGuide.action_yields(a, "ore_copper"), "e produce ancora il rame")
	assert_false(QuestGuide.action_yields(a, "log_pine"))


## La scheda del tutorial si può trascinare dove non copre i controlli (copriva gli slot dell'Eroe); la posizione scelta resta fino
## alla fine del passo, poi la scheda torna a posizionarsi da sola.
func test_la_scheda_si_trascina_e_la_posizione_resta() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	assert_eq(d.current_step_id(), "g_sidebar")
	var card: Control = d.find_child("TutorialCard", true, false)
	var start: Vector2 = card.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(40, 20)
	d._on_card_input(press)
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(40, 20) + Vector2(300, 90)
	d._on_card_input(mv)
	assert_eq(card.position, (start + Vector2(300, 90)).clamp(Vector2(10, 10), get_viewport().get_visible_rect().size - card.size - Vector2(10, 10)),
		"la scheda segue il trascinamento (dentro lo schermo)")
	var dragged: Vector2 = card.position
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	d._on_card_input(rel)
	await wait_process_frames(6)
	assert_eq(card.position, dragged, "la posizione scelta resta mentre il passo è in mostra")
	d.press_next()
	d = await _kick(main)
	assert_true(d._user_pos == null, "al passo dopo la scheda si posiziona da sola")
	assert_ne(tr("UI_TUT_DRAG_TIP"), "UI_TUT_DRAG_TIP")
