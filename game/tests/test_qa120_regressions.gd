extends GutTest
## Regressioni del playtest AFK con salvataggi (QA120, docs/audit_2026-10-22/120_PLAYTEST_AFK_SALVATAGGI.md).

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_qa120_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	SaveService.backup_interval_s = 0.0      # questi test provano la rotazione a ogni scrittura (intervallo reale: test_save_safety)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)


func after_all() -> void:
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto
	SaveService.backup_interval_s = SaveService.BACKUP_INTERVAL_S


func _gold_of(bytes: PackedByteArray) -> int:
	return int(SaveCodec.decode(bytes).data.currencies.gold)


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## Tre salvataggi con oro diverso: main (oro 3), bak1 (2), bak2 (1).
func _three_saves(slot: int) -> Array:
	Game.new_game(slot, "normal", 5)
	var bank := Game.system("bank") as BankSystem
	var snaps: Array = []
	for i in 3:
		bank.add_gold(10)
		snaps.append(Game.snapshot(true).duplicate(true))
		assert_eq(SaveService.save_data(slot, snaps[i]), OK)
	Game.stop_game(false)
	return snaps


# ------------------------------------------------------------------ chiusura brusca durante la rotazione

func test_main_assente_con_tmp_completo_si_carica_il_tmp_non_il_backup_piu_vecchio() -> void:
	var snaps := _three_saves(1)
	var path := SaveService.slot_path(1)
	# la rotazione e' avvenuta (main -> bak1) ma il .tmp completo non e' stato rinominato: il main non c'e'
	var newest := SaveCodec.encode(snaps[2])
	DirAccess.remove_absolute(path)
	_write(path + ".tmp", newest)
	assert_true(SaveService.slot_exists(1), "lo slot esiste ancora, il menu non lo mostra vuoto")
	var info := SaveService.slot_info(1)
	assert_true(info.ok, "slot_info legge il .tmp")
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(res.source, "tmp")
	assert_eq(int(res.data.currencies.gold), _gold_of(newest), "nessun salvataggio perso: oro dell'ultima scrittura")


func test_tmp_parziale_con_main_assente_ripiega_sul_backup() -> void:
	var snaps := _three_saves(1)
	var path := SaveService.slot_path(1)
	DirAccess.remove_absolute(path)
	var half := SaveCodec.encode(snaps[2])
	_write(path + ".tmp", half.slice(0, half.size() / 2))
	assert_true(SaveService.slot_exists(1), "ci sono i backup: lo slot esiste")
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(res.source, "bak1")
	assert_eq(int(res.data.currencies.gold), _gold_of(SaveCodec.encode(snaps[1])))


func test_main_valido_batte_sempre_il_tmp() -> void:
	var snaps := _three_saves(1)
	var path := SaveService.slot_path(1)
	_write(path + ".tmp", SaveCodec.encode(snaps[0]))        # un .tmp vecchio e completo
	var res := SaveService.load_slot(1)
	assert_eq(res.source, "main")
	assert_eq(int(res.data.currencies.gold), _gold_of(SaveCodec.encode(snaps[2])))


func test_un_tmp_da_solo_non_e_un_salvataggio_ma_con_un_backup_si() -> void:
	# primo salvataggio mai completato: niente slot «illeggibile» nel menu e niente caricamento di un .tmp orfano
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	Game.new_game(2, "normal", 5)
	var full := SaveCodec.encode(Game.snapshot(true))
	Game.stop_game(false)
	SaveService.delete_slot(2)
	_write(SaveService.slot_path(2) + ".tmp", full.slice(0, full.size() / 3))
	assert_false(SaveService.slot_exists(2), "tmp parziale e nient'altro: slot vuoto")
	_write(SaveService.slot_path(2) + ".tmp", full)
	assert_false(SaveService.slot_exists(2), "anche un tmp completo da solo non e' uno slot")
	assert_false(SaveService.load_slot(2).ok)
	# con almeno un backup alle spalle (chiusura brusca nella rotazione) il .tmp completo e' il piu' recente
	_write(SaveService.backup_path(2, 1), full)
	assert_true(SaveService.slot_exists(2))
	assert_eq(SaveService.load_slot(2).source, "tmp")


func test_slot_senza_nessun_file_non_esiste() -> void:
	assert_false(SaveService.slot_exists(2))
	_three_saves(2)
	SaveService.delete_slot(2)
	assert_false(SaveService.slot_exists(2), "delete_slot toglie anche .tmp e backup")


# ------------------------------------------------------------------ avvisi di caricamento (prima che esista la schermata)

func test_ripiego_sul_backup_e_detto_al_giocatore() -> void:
	_three_saves(1)
	var path := SaveService.slot_path(1)
	var good := FileAccess.get_file_as_bytes(path)
	_write(path, good.slice(0, good.size() / 2))                 # main troncato
	var res := Game.load_game(1)
	assert_true(res.ok)
	assert_eq(res.source, "bak1")
	var notices := Game.take_load_notices()
	assert_eq(notices.size(), 1, "un avviso di ripiego")
	assert_eq(notices[0].kind, "warning")
	assert_false(str(notices[0].text).begins_with("UI_"), "testo tradotto, non la chiave")
	assert_true(Game.take_load_notices().is_empty(), "si consegna una volta sola")


func test_orologio_indietro_avviso_non_si_perde_se_la_schermata_nasce_dopo() -> void:
	# StartScreen carica e SOLO DOPO cambia scena: l'avviso emesso da load_game andava perso (nessun ascoltatore)
	Game.new_game(1, "normal", 5)
	var snap := Game.snapshot(true).duplicate(true)
	snap["saved_at_unix"] = Clock.now_unix() + 3 * 3600
	assert_eq(SaveService.save_data(1, snap), OK)
	Game.stop_game(false)
	var res := Game.load_game(1)
	assert_true(res.ok)
	assert_eq(int(res.clock_rewound_s) > 3 * 3600 - 5, true, "orologio indietro riconosciuto")
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var found := false
	for l in Feedback.game_lines():
		if str(l).find(NumberFormat.fmt_time(float(res.clock_rewound_s))) >= 0:
			found = true
	assert_true(found, "l'avviso «orologio indietro» e' nel registro della schermata nata dopo il caricamento")
	assert_true(Game.take_load_notices().is_empty(), "consegnato a MainScreen")


func test_nuova_partita_e_stop_svuotano_la_coda_degli_avvisi() -> void:
	Game.load_notices.append({"kind": "warning", "text": "x"})
	Game.new_game(1, "normal", 5)
	assert_true(Game.load_notices.is_empty())
	Game.load_notices.append({"kind": "warning", "text": "x"})
	Game.stop_game(false)
	assert_true(Game.load_notices.is_empty())


# ------------------------------------------------------------------ sospensione con il gioco aperto (Steam Deck / portatili)

func test_suspend_gap_pura() -> void:
	var m := 120.0
	assert_eq(FixedStepClock.suspend_gap(0.016, 0.016, m), 0.0, "fotogramma normale")
	assert_eq(FixedStepClock.suspend_gap(30.0, 29.9, m), 0.0, "uno stallo del motore (muro = reale): nessun eccesso")
	assert_eq(FixedStepClock.suspend_gap(60.0, 0.0, m), 0.0, "sotto soglia: aggiustamenti dell'orologio, scatti")
	assert_almost_eq(FixedStepClock.suspend_gap(8.0 * 3600.0 + 0.016, 0.016, m), 8.0 * 3600.0, 0.01, "8 h di sonno")
	assert_eq(FixedStepClock.suspend_gap(-3600.0, 0.016, m), 0.0, "orologio indietro: niente")
	assert_eq(FixedStepClock.suspend_gap(NAN, 0.016, m), 0.0)
	assert_eq(FixedStepClock.suspend_gap(INF, 0.016, m), 0.0)
	assert_lte(FixedStepClock.suspend_gap(1e12, 0.0, m), FixedStepClock.MAX_ADVANCE_S, "tetto tecnico")


func test_la_sospensione_con_il_gioco_aperto_conta_come_assenza() -> void:
	Game.new_game(1, "normal", 5)
	var t0 := Time.get_unix_time_from_system()
	Clock._last_wall = t0
	watch_signals(EventBus)
	# il motore ha misurato 16 ms, l'orologio di sistema 8 ore (sospensione)
	Clock.check_suspend(t0 + 8.0 * 3600.0 + 0.016, 0.016)
	assert_signal_emitted(EventBus, "offline_progress", "il Bentornato parte come per una chiusura e riapertura")
	var args: Array = get_signal_parameters(EventBus, "offline_progress")
	assert_almost_eq(float(args[0]), 8.0 * 3600.0, 2.0)
	assert_eq(Clock._last_wall, t0 + 8.0 * 3600.0 + 0.016, "riferimento riallineato: la prossima chiamata non conta due volte")


func test_sospensione_nel_limite_offline_e_oltre_il_limite() -> void:
	Game.new_game(1, "normal", 5)
	var cap := Game.offline_cap_s()
	var t0 := Time.get_unix_time_from_system()
	Clock._last_wall = t0
	watch_signals(EventBus)
	Clock.check_suspend(t0 + 3.0 * cap, 0.016)
	var args: Array = get_signal_parameters(EventBus, "offline_progress")
	assert_almost_eq(float(args[0]), cap, 1.0, "oltre il limite conta solo il limite (come al caricamento)")


func test_nessun_accredito_in_pausa_senza_partita_o_con_orologio_indietro() -> void:
	var t0 := Time.get_unix_time_from_system()
	# senza partita
	Clock._last_wall = t0
	watch_signals(EventBus)
	Clock.check_suspend(t0 + 36000.0, 0.016)
	assert_signal_not_emitted(EventBus, "offline_progress")
	Game.new_game(1, "normal", 5)
	# in pausa: e' una scelta del giocatore, il tempo di pausa non e' assenza
	Clock.set_paused(true)
	Clock._last_wall = t0
	Clock.check_suspend(t0 + 36000.0, 0.016)
	assert_signal_not_emitted(EventBus, "offline_progress")
	Clock.set_paused(false)
	# orologio indietro
	Clock._last_wall = t0
	Clock.check_suspend(t0 - 36000.0, 0.016)
	assert_signal_not_emitted(EventBus, "offline_progress")
	assert_eq(Clock._last_wall, t0 - 36000.0, "riallineato")
	# fotogramma normale
	Clock.check_suspend(t0 - 36000.0 + 0.016, 0.016)
	assert_signal_not_emitted(EventBus, "offline_progress")


func test_soglia_della_sospensione_viene_dai_dati() -> void:
	var off: Dictionary = DataRegistry.constants.get("offline", {})
	assert_true(off.has("resume_min_gap_s"), "constants.offline.resume_min_gap_s (da tools/gamedata/core.py)")
	assert_gte(float(off.get("resume_min_gap_s", 0.0)), 60.0, "non deve scattare per aggiustamenti dell'orologio")


# ------------------------------------------------------------------ salvataggio fallito (disco pieno): il messaggio dice cosa fare

func test_salvataggio_fallito_dice_perche_e_cosa_fare() -> void:
	Game.new_game(1, "normal", 5)
	(Game.system("quests") as QuestSystem).mark_intro_seen()
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	EventBus.save_completed.emit(false)
	await wait_process_frames(2)
	var found := false
	for l in Feedback.game_lines():
		if str(l).find(tr("UI_QA120_SAVE_FAILED_HINT")) >= 0:
			found = true
	assert_true(found, "l'avviso di salvataggio fallito contiene il rimedio")
	assert_false(tr("UI_QA120_SAVE_FAILED_HINT").begins_with("UI_"), "stringa tradotta")


# ------------------------------------------------------------------ round-trip identico: i campi interi restano interi

func test_istanze_seed_e_lucidatura_restano_interi_dopo_salva_e_ricarica() -> void:
	Game.new_game(1, "normal", 5)
	var bank := Game.system("bank") as BankSystem
	var skin: Dictionary = DataRegistry.item(str(DataRegistry.item("crate_millbrook").crate.skins[0]))
	var uid := bank.add_instance({"def_id": str(skin.id), "kind": "skin", "rarity": skin.rarity, "crate": "crate_millbrook",
		"condition": "field_tested", "float": 0.321, "annalist": false, "seed": 321, "phase": "", "polish": 2, "locked": false})
	assert_ne(uid, "")
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	var found := false
	for inst in (Game.system("bank") as BankSystem).state.instances:
		if str(inst.uid) == uid:
			found = true
			assert_eq(typeof(inst.seed), TYPE_INT, "seed resta int")
			assert_eq(typeof(inst.polish), TYPE_INT, "polish resta int")
			assert_eq(inst.seed, 321)
			assert_almost_eq(float(inst.float), 0.321, 1e-12)
	assert_true(found)


func test_fase_del_nemico_e_turni_degli_effetti_restano_interi() -> void:
	Game.new_game(1, "normal", 5)
	var zone := str(DataRegistry.table("zones")[0].id)
	GameState.data.activity = {"type": "combat", "zone": zone, "mode": "zone", "respawn_s": 0.0,
		"enemy": {"max": 10.0, "hp": 5.0, "phase": 2.0, "dots": {"burn": {"n": 3.0, "dps": 1.5}}}}
	var combat := Game.system("combat") as CombatSystem
	combat.from_state(combat.state)
	var en: Dictionary = GameState.data.activity.enemy
	assert_eq(typeof(en.phase), TYPE_INT)
	assert_eq(typeof(en.dots.burn.n), TYPE_INT)
	assert_eq(typeof(en.dots.burn.dps), TYPE_FLOAT, "i decimali restano decimali")


func test_interi_morbidi_tornano_int_ma_non_rendono_mai_corrotto_il_salvataggio() -> void:
	var d := {"schema_version": SaveCodec.SCHEMA_VERSION, "a": {"n": 3.0, "m": 3.5, "s": "7", "z": null, "list": [{"k": 2.0}, {"k": "x"}]}, "b": 4.0}
	var bytes := SaveCodec.encode(d)
	var res := SaveCodec.load_bytes(bytes, PackedStringArray(["b"]), SaveCodec.SCHEMA_VERSION, {}, PackedStringArray(["a.n", "a.m", "a.s", "a.z", "a.list[].k"]))
	assert_true(res.ok, "i percorsi morbidi non rifiutano mai un file: %s" % str(res.get("paths", "")))
	assert_eq(typeof(res.data.b), TYPE_INT, "percorso rigido: int")
	assert_eq(typeof(res.data.a.n), TYPE_INT, "float intero -> int")
	assert_eq(typeof(res.data.a.m), TYPE_FLOAT, "3.5 resta com'e'")
	assert_eq(res.data.a.s, "7", "stringa invariata")
	assert_eq(res.data.a.z, null)
	assert_eq(typeof(res.data.a.list[0].k), TYPE_INT)
	assert_eq(res.data.a.list[1].k, "x")
	# lo stesso valore con un percorso RIGIDO sarebbe corrotto: e' la differenza
	var strict := SaveCodec.load_bytes(bytes, PackedStringArray(["a.m"]))
	assert_false(strict.ok)


func test_percorsi_morbidi_dei_sistemi_riportano_gli_interi_e_non_rifiutano_il_file() -> void:
	var soft := Game.sim.soft_int_paths()
	assert_gt(soft.size(), 10, "i sistemi dichiarano i loro interi morbidi")
	var strict := Game.sim.int_paths()
	for p in soft:
		assert_false(strict.has(p), "%s non e' anche tra i percorsi rigidi" % p)
	var d := {"schema_version": SaveCodec.SCHEMA_VERSION,
		"contracts": {"daily": [{"obj": {"qty": 3.0, "gold": 5.0}, "text_params": {"qty": 3.0, "gold": 5.0}}], "weekly": [{"obj": {"qty": 7.0}, "text_params": {"qty": 7.5}}]},
		"bounty": {"offers": [{"marks": 2.0}]},
		"mercenaries": {"board": {"candidates": [{"level": 3.0, "equip_tier": 1.0}]}},
		"expeditions": {"log": [{"gold": 120.0, "levels": 2.0}]},
		"run": {"history": [{"picks": 4.0}]},
		"activity": {"floor": 2.0, "idx": 1.0, "start_floor": 1.0, "wave": 5.0, "slot": "weapon"}}
	var res := SaveCodec.load_bytes(SaveCodec.encode(d), strict, SaveCodec.SCHEMA_VERSION, {}, soft)
	assert_true(res.ok)
	var r: Dictionary = res.data
	assert_eq(typeof(r.contracts.daily[0].obj.qty), TYPE_INT)
	assert_eq(typeof(r.contracts.daily[0].text_params.gold), TYPE_INT)
	assert_eq(typeof(r.contracts.weekly[0].text_params.qty), TYPE_FLOAT, "7.5 resta decimale: nessun rifiuto")
	assert_eq(typeof(r.bounty.offers[0].marks), TYPE_INT)
	assert_eq(typeof(r.mercenaries.board.candidates[0].equip_tier), TYPE_INT)
	assert_eq(typeof(r.expeditions.log[0].levels), TYPE_INT)
	assert_eq(typeof(r.run.history[0].picks), TYPE_INT)
	assert_eq(typeof(r.activity.floor), TYPE_INT)
	assert_eq(r.activity.slot, "weapon", "una stringa resta com'e'")


# ------------------------------------------------------------------ Bentornato lungo: sta nella finestra, il pulsante si vede

func test_bentornato_con_molte_righe_non_esce_dalla_finestra() -> void:
	Game.new_game(1, "normal", 5)
	(Game.system("quests") as QuestSystem).mark_intro_seen()
	var old_tut: Variant = Settings.get_value("tutorials")
	Settings.set_value("tutorials", false)
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var host: OverlayHost = null
	for c in main.get_children():
		if c is OverlayHost:
			host = c
	assert_not_null(host)
	# un resoconto enorme: 8 pile, casse, molte righe e 2 motivi di stop
	var items := {}
	var crates := {}
	var mats: Array = DataRegistry.items_by_category("material")
	for i in 8:
		items[str(mats[i].id)] = 100 + i
	crates["crate_millbrook"] = 12
	var rows: Array = []
	for i in 14:
		rows.append({"key": "UI_QUESTS_WB_MORE", "params": {"n": i + 2}})
	var rep := {"skills": {"items": items, "xp": {"woodcutting": 840.0, "mining": 500.0, "hero": 200.0}, "levels": {"woodcutting": [3, 6]},
		"stop": {"key": "UI_QUESTS_WB_NOTHING", "params": {}}}, "estate": {"rows": rows, "crates": crates, "stop": {"key": "UI_QUESTS_WB_NOTHING", "params": {}}},
		"market": {"rows": rows}}
	EventBus.offline_progress.emit(8.0 * 3600.0, rep)
	await wait_process_frames(6)
	assert_true(host.is_busy())
	var collect := host.find_child("WbCollect", true, false) as Button
	assert_not_null(collect)
	var view := host.get_viewport_rect()
	var r := collect.get_global_rect()
	assert_true(view.encloses(r), "il pulsante «Raccogli tutto» e' dentro la finestra: %s in %s" % [str(r), str(view)])
	var scroll := host.find_child("WbScroll", true, false) as ScrollContainer
	assert_not_null(scroll)
	assert_true(view.encloses(scroll.get_global_rect()), "lo scorrimento sta nella finestra")
	collect.pressed.emit()
	await wait_process_frames(3)
	Settings.set_value("tutorials", old_tut)
