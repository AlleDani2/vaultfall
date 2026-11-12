extends GutTest
## Tutorial guidato (TutorialSystem + TutorialDirector + Guida): catalogo coerente, testi bilingui con numeri dai dati,
## flusso completo dalla nuova partita (anche saltando), stato nel salvataggio, partite già avviate, controlli assenti.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const GRANTED_BY_SYSTEMS: PackedStringArray = ["feature:run", "feature:prestige", "feature:coop"]
const KNOWN_COND: PackedStringArray = ["quest_done", "quest_reached", "queue_slots", "building", "item", "bank_nearly_full", "bank_used_over"]

var _old_dir: String
var _old_tut: Variant
var _old_motion: Variant
var _old_locale: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_tutorial_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_tut = Settings.get_value("tutorials")
	_old_motion = Settings.get_value("reduce_motion")
	_old_locale = Settings.get_value("locale")
	Settings.set_value("tutorials", true)
	Settings.set_value("reduce_motion", true)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("tutorials", _old_tut)
	Settings.set_value("reduce_motion", _old_motion)
	Settings.set_value("locale", _old_locale)


func _ts() -> TutorialSystem:
	return Game.system("tutorial") as TutorialSystem


func _quests() -> QuestSystem:
	return Game.system("quests") as QuestSystem


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


## Fa scegliere subito il prossimo passo (senza aspettare i tempi reali) e lascia disegnare un paio di fotogrammi.
func _kick(main: Control) -> TutorialDirector:
	var d: TutorialDirector = main.tutorial()
	for i in 600:                        # il banner «Missione completata» ha la precedenza sul tutorial: lo si lascia finire
		if not Fx.banner_active():
			break
		await wait_process_frames(2)
	for round in 2:                      # un passo appena finito lascia una breve pausa: si riprova una volta
		d._gap = 0.0
		d._poll = 0.0
		await wait_process_frames(3)
		if not d.current_step_id().is_empty():
			break
	return d


func _welcome_done(main: Control) -> void:
	var host: OverlayHost
	for c in main.get_children():
		if c is OverlayHost:
			host = c
	var go: Button = host.find_child("WelcomeGo", true, false)
	go.pressed.emit()
	await wait_process_frames(3)


# ------------------------------------------------------------------ catalogo e testi

func test_catalogo_coerente() -> void:
	var seen := {}
	for s in TutorialCatalog.STEPS:
		var sid := str(s.id)
		assert_false(seen.has(sid), "id duplicato " + sid)
		seen[sid] = true
		assert_true(TutorialCatalog.CATS.has(str(s.cat)), "categoria di " + sid)
	for s in TutorialCatalog.STEPS:
		var sid := str(s.id)
		var after := str(s.get("after", ""))
		assert_true(after.is_empty() or seen.has(after), "after di %s esiste" % sid)
		var scr := str(s.get("screen", ""))
		assert_true(scr.is_empty() or not ScreenRegistry.get_entry(scr, DataRegistry).is_empty(), "schermata di %s esiste: %s" % [sid, scr])
		for c in s.get("skip_if", []):
			assert_true(KNOWN_COND.has(str(c[0])), "condizione nota in " + sid)
		if s.has("cond"):
			assert_true(KNOWN_COND.has(str(s.cond[0])), "condizione nota in " + sid)
		var tok := str(s.get("token", ""))
		if not tok.is_empty():
			assert_true(tok.contains(":"), "token ben formato in " + sid)
		if str(s.get("mode", "ack")) == "act":
			assert_true(s.has("done"), "un passo 'act' dichiara come finisce: " + sid)
	assert_gte(TutorialCatalog.STEPS.size(), 40, "copre tutte le dinamiche")


func test_token_dei_passi_esistono_nei_dati() -> void:
	var known := {}
	for q in DataRegistry.table("quests"):
		for u in q.get("unlocks", []):
			known[str(u)] = true
	for sk in DataRegistry.table("skills"):
		known["skill:" + str(sk.id)] = true
	for t in GRANTED_BY_SYSTEMS:             # sblocchi concessi dal codice (livello di rito, Corsa, prima Incursione), non da missioni
		known[t] = true
	for s in TutorialCatalog.STEPS:
		var tok := str(s.get("token", ""))
		if not tok.is_empty() and not tok.begins_with("era:"):
			assert_true(known.has(tok), "il token %s del passo %s è concesso da qualche missione" % [tok, s.id])


func test_testi_bilingui_con_numeri_dai_dati() -> void:
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for s in TutorialCatalog.STEPS:
			var sid := str(s.id)
			var t := TranslationServer.translate(TutorialCatalog.title_key(sid))
			assert_ne(t, TutorialCatalog.title_key(sid), "titolo %s (%s)" % [sid, loc])
			var raw := TranslationServer.translate(TutorialCatalog.body_key(sid))
			assert_ne(raw, TutorialCatalog.body_key(sid), "testo %s (%s)" % [sid, loc])
			var body := raw.format(TutorialSystem.text_params(sid, DataRegistry))
			assert_false(body.contains("{"), "segnaposto non risolti in %s (%s): %s" % [sid, loc, body])
			assert_lt(body.length(), 760, "testo breve: " + sid)
	TranslationServer.set_locale("it")


func test_livello_vs_maestria_usa_i_numeri_veri() -> void:
	var p := TutorialSystem.text_params("b_compare", DataRegistry)
	assert_eq(int(p.mcap), int(DataRegistry.constants.mastery.cap))
	assert_eq(int(p.cap), int(DataRegistry.constants.level_cap))
	assert_gt(int(p.next_lvl), 1, "livello che sblocca la prossima azione, dai dati")
	assert_false(str(p.next_name).is_empty())
	TranslationServer.set_locale("it")
	var txt := TranslationServer.translate(TutorialCatalog.body_key("b_compare")).format(p)
	assert_true(txt.contains("LIVELLO") and txt.contains("MAESTRIA"), "la scheda spiega la differenza")
	assert_true(txt.contains(str(p.mcap)))


# ------------------------------------------------------------------ stato e salvataggio

func test_sezione_additiva_e_sanificata() -> void:
	Game.new_game(1, "normal", 5)
	var ts := _ts()
	assert_eq(ts.default_state(), {"v": 1, "started": false, "off": false, "seen": []})
	ts.from_state({"seen": ["a", "a", 3, "b"], "off": "no"})
	assert_eq(ts.state.seen, ["a", "b"], "doppioni e tipi sbagliati ripuliti")
	assert_eq(ts.state.off, false, "tipo sbagliato -> valore iniziale")
	assert_eq(ts.state.v, 1)


func test_stato_nel_salvataggio_e_non_riproposto() -> void:
	Game.new_game(1, "normal", 5)
	var ts := _ts()
	ts.begin()                                  # partita nuova: il benvenuto non è ancora stato visto, si parte da zero
	_quests().mark_intro_seen()
	ts.mark_seen("g_sidebar")
	ts.mark_seen("g_open_pine")
	assert_true(SaveService.save_now())
	var res := Game.load_game(1)
	assert_true(bool(res.get("ok", false)), "caricamento")
	var ts2 := _ts()
	assert_true(ts2.is_seen("g_sidebar") and ts2.is_seen("g_open_pine"))
	assert_false(ts2.is_seen("g_pine"))
	assert_true(bool(ts2.state.started))


func test_salvataggio_vecchio_senza_sezione() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	GameState.data.erase("tutorial")           # come un salvataggio di prima del tutorial guidato
	assert_true(SaveService.save_now())
	var res := Game.load_game(1)
	assert_true(bool(res.get("ok", false)), "il vecchio salvataggio si apre senza migrazione")
	var ts := _ts()
	assert_false(bool(ts.state.started))
	ts.begin()
	for s in TutorialCatalog.STEPS:
		if str(s.cat) == "guide":
			assert_true(ts.is_seen(str(s.id)), "partita già avviata: i passi base si danno per visti (%s)" % s.id)


func test_partita_avviata_non_riparte_da_zero() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	GameState.data.unlocks.append("feature:combat")
	_ts().begin()
	assert_true(_ts().is_seen("f_combat"), "sistema già sbloccato: già visto")
	assert_false(_ts().is_seen("f_market"), "sistema ancora da sbloccare: resta da vedere")


func test_si_spegne_da_solo_a_catalogo_completo() -> void:
	Game.new_game(1, "normal", 5)
	var ts := _ts()
	assert_true(ts.active())
	for s in TutorialCatalog.STEPS:
		ts.mark_seen(str(s.id))
	assert_true(ts.finished())
	assert_false(ts.active())
	ts.reset()
	assert_true(ts.active())
	assert_eq(int(ts.counts().seen), 0)


# ------------------------------------------------------------------ flusso completo

func test_flusso_completo_nuova_partita() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	var d: TutorialDirector = main.tutorial()
	d._gap = 0.0
	d._poll = 0.0
	await wait_process_frames(3)
	assert_false(d.is_showing(), "prima il benvenuto: nessun passo mentre la finestra è aperta")
	await _welcome_done(main)
	d = await _kick(main)
	# 1) barra laterale
	assert_eq(d.current_step_id(), "g_sidebar")
	assert_eq(d.highlighted_key(), "sidebar")
	assert_gt(d.highlight_rect().size.x, 50.0, "la barra è evidenziata")
	assert_false(d.is_blocking(), "passo informativo: il gioco resta cliccabile")
	d.press_next()
	# 2) Taglialegna: solo quel pulsante risponde
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_open_pine")
	assert_eq(d.highlighted_key(), "menu:skill:woodcutting")
	assert_true(d.is_blocking())
	main.show_screen("skill:woodcutting")
	await wait_process_frames(3)
	# 3) «inizia col Pino»: evidenzia il pulsante Avvia di Pino e avanza quando lo si preme
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_pine")
	assert_eq(d.highlighted_key(), "action:wc_pine")
	var btn: Button = TutorialTargets.find(get_tree(), "action:wc_pine")
	assert_not_null(btn)
	assert_true(d.highlight_rect().grow(-6.0).has_point(btn.get_global_rect().get_center()), "la cornice circonda il pulsante di Pino")
	assert_true(d.is_blocking())
	btn.pressed.emit()
	d = await _kick(main)
	assert_eq((Game.system("skills") as SkillSystem).current_action(), "wc_pine")
	# 4) Missioni
	assert_eq(d.current_step_id(), "g_quests")
	d.press_next()
	d = await _kick(main)
	assert_false(d.is_showing(), "il passo del Rame aspetta la missione")
	# la missione Pino è finita: arriva «Rame»
	var need := QuestSystem.target_of(_quests().quest_def("main_c0_q1").objectives[0])
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": need}])
	Game.sim.tick(0.1)
	assert_true(_quests().claim("main_c0_q1"))
	main._on_ui_tick()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_open_copper")
	assert_eq(d.highlighted_key(), "menu:skill:mining")
	main.show_screen("skill:mining")
	await wait_process_frames(3)
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_copper")
	assert_eq(d.highlighted_key(), "action:mine_copper")
	var cu: Button = TutorialTargets.find(get_tree(), "action:mine_copper")
	cu.pressed.emit()
	# 5) come muoversi
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_move")
	assert_eq(d.highlighted_key(), "sidebar")
	d.press_next()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_move2")
	assert_eq(d.highlighted_key(), "topbar:settings")
	d.press_next()
	# 6) Livello vs Maestria
	d = await _kick(main)
	assert_eq(d.current_step_id(), "b_level")
	assert_eq(main.current_id, "skill:woodcutting", "il passo porta sulla schermata giusta")
	assert_eq(d.highlighted_key(), "skill_header")
	d.press_next()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "b_mastery")
	assert_eq(d.highlighted_key(), "mastery:wc_pine")
	d.press_next()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "b_compare")
	d.press_next()
	d = await _kick(main)
	assert_false(d.is_showing(), "finiti i passi base: niente finché non si sblocca altro")
	assert_true(_ts().is_seen("b_compare"))


func test_salta_il_tutorial() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var d := await _kick(main)
	assert_true(d.is_showing())
	d.press_skip_all()
	assert_false(d.is_showing())
	assert_true(bool(_ts().state.off))
	assert_false(bool(Settings.get_value("tutorials")), "saltare spegne anche le schede «Novità» di 3 righe")
	d = await _kick(main)
	assert_false(d.is_showing(), "saltato: non si riaffaccia")
	# la Guida lo riaccende
	d.restart()
	assert_false(bool(_ts().state.off))
	d = await _kick(main)
	assert_eq(d.current_step_id(), "g_sidebar", "riparte dal primo passo")


func test_impostazione_spenta_niente_suggerimenti() -> void:
	Settings.set_value("tutorials", false)
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	var main := await _main()
	var d := await _kick(main)
	assert_false(d.is_showing())


func test_passo_a_sblocco_reale_e_ricompare_dal_menu() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	var ts := _ts()
	ts.begin()
	GameState.data.unlocks.append("feature:combat")
	EventBus.unlocked.emit("feature:combat")
	GameState.data.unlocks.append("skill:hero")          # l'Eroe si apre insieme al Combattimento
	EventBus.unlocked.emit("skill:hero")
	ts.state.seen.erase("f_combat")
	ts.mark_seen("f_hero")                              # il passo Eroe viene prima: qui è già stato letto
	var main := await _main()
	var d := await _kick(main)
	assert_eq(d.current_step_id(), "f_combat", "al primo sblocco reale")
	assert_eq(d.highlighted_key(), "menu:combat", "prima il pulsante del menù")
	assert_true(d._hint.visible, "dice a parole quale voce premere")
	assert_false(d.is_blocking())
	main.show_screen("combat")
	await wait_process_frames(3)
	assert_eq(d.highlighted_key(), "combat_start", "poi il controllo dentro la schermata")
	d.press_later()
	assert_false(d.is_showing())
	d = await _kick(main)
	assert_false(d.is_showing(), "«Più tardi» lo rimanda")
	assert_false(ts.is_seen("f_combat"))
	d._later_until.clear()
	d = await _kick(main)
	assert_eq(d.current_step_id(), "f_combat", "poi torna")
	d.press_next()
	assert_true(ts.is_seen("f_combat"))


func test_controllo_assente_salta_il_passo() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	_ts().begin()
	var main := await _main()
	var d: TutorialDirector = main.tutorial()
	d._begin({"id": "zz_finto", "cat": "city", "target": "chiave_che_non_esiste"}, false)
	for i in 10:
		d._update_step(0.3)
	assert_false(d.is_showing(), "controllo assente: passo saltato")
	assert_true(d._skipped.has("zz_finto"))
	assert_null(TutorialTargets.find(get_tree(), "chiave_che_non_esiste"))


func test_riduci_animazioni_cornice_ferma() -> void:
	Settings.set_value("reduce_motion", true)
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	_ts().begin()
	_ts().reset()
	var main := await _main()
	var d := await _kick(main)
	assert_true(d._spot.calm)
	assert_eq(d._card.modulate.a, 1.0)


func test_non_durante_un_combattimento_rischioso() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	var d: TutorialDirector = main.tutorial()
	assert_false(d._risky(), "fuori dal combattimento")


func test_mostrami_dalla_guida() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	_ts().begin()
	var main := await _main()
	assert_true(main.show_screen("guide"))
	await wait_process_frames(2)
	var scr: Control = main.current_screen()
	var count: Label = scr.find_child("GuideCount", true, false)
	assert_true(count.text.contains(str(TutorialCatalog.STEPS.size())), "x su N")
	var locked: Button = scr.find_child("Show_f_prestige", true, false)
	assert_true(locked.disabled, "voce non sbloccata: «Mostrami» spento")
	var open: Button = scr.find_child("Show_g_sidebar", true, false)
	assert_false(open.disabled)
	open.pressed.emit()
	await wait_process_frames(3)
	var d: TutorialDirector = main.tutorial()
	assert_eq(d.current_step_id(), "g_sidebar")
	d.press_next()
	var restart: Button = scr.find_child("GuideRestart", true, false)
	restart.pressed.emit()
	assert_eq(int(_ts().counts().seen), 0)


func test_vecchie_schede_non_raddoppiano() -> void:
	Game.new_game(1, "normal", 5)
	var main := await _main()
	await _welcome_done(main)
	var host: OverlayHost
	for c in main.get_children():
		if c is OverlayHost:
			host = c
	assert_null(host.find_child("TutorialTitle", true, false), "il Taglialegna ha il passo guidato, non la scheda a 3 righe")


# ------------------------------------------------------------------ Deposito quasi pieno (resoconto 114)

func test_deposito_quasi_pieno_porta_al_pulsante_espandi() -> void:
	Game.new_game(1, "normal", 5)
	var ts := _ts()
	for s in TutorialCatalog.STEPS:                      # tutto già visto tranne il passo da provare
		if str(s.id) != "f_bank_expand":
			ts.mark_seen(str(s.id))
	var bank := Game.system("bank") as BankSystem
	var n := 0
	for d in DataRegistry.items_by_category("material"):
		if bank.nearly_full():
			break
		bank.add(str(d.id), 1)
		n += 1
	assert_true(bank.nearly_full())
	var main := await _main()
	await _welcome_done(main)
	var dir := await _kick(main)
	assert_eq(dir.current_step_id(), "f_bank_expand", "il passo compare quando il Deposito è quasi pieno")
	await wait_process_frames(4)
	assert_eq(str(main.current_screen().get_script().resource_path.get_file()), "BankScreen.gd", "ti porta nel Deposito")
	assert_eq(dir.highlighted_key(), "bank_expand_btn", "evidenzia «Espandi Deposito»")
	var btn: Button = TutorialTargets.find(get_tree(), "bank_expand_btn")
	assert_not_null(btn)
	assert_true(dir.highlight_rect().grow(-6.0).has_point(btn.get_global_rect().get_center()), "la cornice circonda il pulsante")

func test_eroe_e_combattimento_insieme_prima_l_eroe() -> void:
	Game.new_game(1, "normal", 5)
	_quests().mark_intro_seen()
	var ts := _ts()
	ts.begin()
	for t in ["feature:combat", "skill:hero"]:
		GameState.data.unlocks.append(t)
		EventBus.unlocked.emit(t)
	for st in TutorialCatalog.STEPS:                    # tutto il resto già visto: resta solo il momento dello sblocco
		if not ["f_hero", "f_combat"].has(str(st.id)):
			ts.mark_seen(str(st.id))
	ts.state.seen.erase("f_combat")
	ts.state.seen.erase("f_hero")
	assert_eq(str(ts.next_step().get("id", "")), "f_hero", "l'Eroe compare con il Combattimento, non dopo le missioni dei lupi")
	ts.mark_seen("f_hero")
	assert_eq(str(ts.next_step().get("id", "")), "f_combat")
