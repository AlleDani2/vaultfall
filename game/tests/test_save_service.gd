extends GutTest
## T-1.5: SaveCodec + SaveService (docs/17 §10): round-trip, backup a rotazione, corruzione simulata,
## migrazioni, rifiuto dei salvataggi più nuovi, normalizzazione dei tipi, export/import Base64, thread,
## partita completa con Game.

const Spike := preload("res://scripts/save_spike.gd")
const GS := preload("res://src/autoload/GameState.gd")

var _old_dir: String
var _dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_dir = "user://test_saves_%d" % Time.get_ticks_usec()
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	SaveService.backup_interval_s = 0.0          # questi test provano la rotazione a ogni scrittura (l'intervallo reale: test_save_safety)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for slot in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(slot)
	DirAccess.remove_absolute(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	SaveService.backup_interval_s = SaveService.BACKUP_INTERVAL_S


func _sample(marker: int) -> Dictionary:
	var d := GS.default_state("normal")
	d["currencies"]["gold"] = marker
	d["skills"]["mining"] = {"xp": 1234.5, "level": 12, "record_level": 30, "stars": 1, "perks": {"10": "a"}, "unlocked": true}
	d["bank"]["stacks"]["log_pine"] = 120
	d["bank"]["instances"].append({"uid": "i_000001", "def": "sword_copper", "quality": "fine", "sockets": [], "rank": 2, "locked": false})
	d["rng"] = RngStreams.new(marker).to_state()
	d["quests"]["progress"]["main_c0_q1"] = [3, 0, 1]
	return d


## Gli errori del motore attesi (gzip troncato) non devono far fallire il test: si marcano come gestiti.
func _handle_engine_errors() -> int:
	var n := 0
	for e in get_errors():
		e.handled = true
		n += 1
	return n


func _write_raw(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


# ------------------------------------------------------------------ SaveCodec (puro)

func test_codec_round_trip_e_normalizzazione() -> void:
	var d := _sample(77)
	var res := SaveCodec.load_bytes(SaveCodec.encode(d), PackedStringArray(GS.BASE_INT_PATHS))
	assert_true(res.ok, str(res.error))
	var back: Dictionary = res.data
	assert_eq(typeof(back.currencies.gold), TYPE_INT, "int dopo la normalizzazione")
	assert_eq(typeof(back.skills.mining.level), TYPE_INT)
	assert_eq(typeof(back.skills.mining.xp), TYPE_FLOAT, "xp resta float (non dichiarato intero)")
	assert_eq(typeof(back.bank.instances[0].rank), TYPE_INT, "percorso con []")
	assert_eq(typeof(back.quests.progress.main_c0_q1[2]), TYPE_INT, "percorso *[]")
	assert_eq(back.rng, d.rng, "seed/state restano stringhe identiche")
	var out: Array = []
	Spike.diff(d, back, "", out)
	assert_eq(out, [], "nessuna differenza dopo il round-trip")


func test_normalizzazione_segnala_corruzione() -> void:
	var d := {"a": {"x": 3.0, "y": 2.5, "s": "123456789012345678901", "n": null}, "l": [1.0, 2.0, 3.5]}
	var errs := SaveCodec.normalize(d, PackedStringArray(["a.*", "l[]", "manca.del.tutto"]))
	assert_eq(errs.size(), 2, str(errs))
	assert_eq(typeof(d.a.x), TYPE_INT)
	assert_eq(d.a.s, "123456789012345678901", "stringhe intatte (R-SAV-7)")
	assert_eq(d.a.n, null)
	var bad := _sample(1)
	bad["currencies"]["gold"] = 10.5
	var res := SaveCodec.load_bytes(SaveCodec.encode(bad), PackedStringArray(GS.BASE_INT_PATHS))
	assert_false(res.ok)
	assert_eq(res.error, "corrupt_types")


func test_normalizzazione_come_lo_spike_s2() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var original := Spike.build_state(rng)
	var loaded: Dictionary = SaveCodec.decode(SaveCodec.encode(original)).data
	var paths := PackedStringArray(["schema_version", "saved_at_unix", "created_at_unix", "bank.slots_bought",
		"estate.settlers", "bank.instances[].rank", "bank.stacks.*", "skills.mining.level", "skills.mining.record_level",
		"skills.mining.stars", "stats.kills", "stats.gold_earned"])
	assert_eq(SaveCodec.normalize(loaded, paths).size(), 0)
	var expect := original.duplicate(true)
	expect["stats"]["gold_earned"] = loaded.stats.gold_earned     # perdita nota > 2^53 (per questo: stringhe)
	var out: Array = []
	Spike.diff(expect, loaded, "", out)
	assert_eq(out, [], "20.000 istanze senza perdite")


func test_migrazioni() -> void:
	var migs := {
		1: func(d: Dictionary) -> Dictionary:
			d["renamed"] = d.get("old", 0)
			d.erase("old")
			return d,
		2: func(d: Dictionary) -> Dictionary:
			d["added_v3"] = true
			return d,
	}
	var res := SaveCodec.migrate({"schema_version": 1.0, "old": 5}, 3, migs)
	assert_true(res.ok)
	assert_eq(res.data.schema_version, 3)
	assert_eq(res.data.renamed, 5)
	assert_true(res.data.added_v3)
	assert_eq(SaveCodec.migrate({"schema_version": 1}, 3, {1: migs[1]}).error, "missing_migration")
	assert_eq(SaveCodec.migrate({"schema_version": 4}, 3, migs).error, "newer", "salvataggio più nuovo rifiutato")
	assert_eq(SaveCodec.migrate({}, 3, migs).error, "no_version")
	assert_eq(SaveCodec.migrate({"schema_version": SaveCodec.SCHEMA_VERSION}).error, "", "versione corrente: nulla da fare")


func test_base64() -> void:
	var d := _sample(5)
	var s := SaveCodec.to_base64(d)
	assert_true(s.length() > 20)
	var back := SaveCodec.from_base64("  " + s + "\n")
	assert_true(back.ok)
	assert_eq(back.data.rng, d.rng)
	assert_false(SaveCodec.from_base64("non è base64 !!").ok)
	assert_false(SaveCodec.from_base64("").ok)


# ------------------------------------------------------------------ SaveService (file)

func test_scrittura_atomica_e_backup_a_rotazione() -> void:
	for i in range(1, 6):
		assert_eq(SaveService.save_data(1, _sample(i)), OK)
	assert_true(FileAccess.file_exists(SaveService.slot_path(1)))
	assert_false(FileAccess.file_exists(SaveService.slot_path(1) + ".tmp"), "niente .tmp dopo il rename")
	var expected := {"main": 5, "bak1": 4, "bak2": 3, "bak3": 2}
	assert_eq(SaveCodec.decode(FileAccess.get_file_as_bytes(SaveService.slot_path(1))).data.currencies.gold, 5.0)
	for n in range(1, 4):
		var p := SaveService.backup_path(1, n)
		assert_true(FileAccess.file_exists(p), p)
		assert_eq(int(SaveCodec.decode(FileAccess.get_file_as_bytes(p)).data.currencies.gold), expected["bak%d" % n])
	assert_false(FileAccess.file_exists(SaveService.backup_path(1, 4)), "solo 3 backup")
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(res.source, "main")
	assert_eq(res.data.currencies.gold, 5)


func test_corruzione_simulata_ripiega_sui_backup() -> void:
	SaveService.save_data(2, _sample(10))
	SaveService.save_data(2, _sample(11))
	SaveService.save_data(2, _sample(12))
	_write_raw(SaveService.slot_path(2), "spazzatura".to_utf8_buffer())
	var res := SaveService.load_slot(2)
	assert_true(res.ok, "si carica dal backup")
	assert_eq(res.source, "bak1")
	assert_eq(res.data.currencies.gold, 11)
	# file troncato (gzip valido a metà)
	var good := FileAccess.get_file_as_bytes(SaveService.backup_path(2, 1))
	_write_raw(SaveService.backup_path(2, 1), good.slice(0, int(good.size() / 2.0)))
	res = SaveService.load_slot(2)
	assert_eq(res.source, "bak2")
	assert_eq(res.data.currencies.gold, 10)
	# senza la copia giornaliera (ultimo salvagente) e con tutti i backup rovinati: nessun salvataggio apribile
	for dp in SaveService.day_copies(2):
		DirAccess.remove_absolute(dp)
	_write_raw(SaveService.backup_path(2, 2), PackedByteArray([1, 2, 3]))
	res = SaveService.load_slot(2)
	assert_false(res.ok)
	assert_ne(res.error, "")
	assert_false(SaveService.load_slot(3).ok, "slot vuoto")
	assert_eq(SaveService.load_slot(3).error, "missing")
	assert_eq(SaveService.load_slot(9).error, "invalid_slot")
	_handle_engine_errors()


func test_salvataggio_piu_nuovo_non_si_apre() -> void:
	SaveService.save_data(1, _sample(1))
	var newer := _sample(2)
	newer["schema_version"] = SaveCodec.SCHEMA_VERSION + 1
	_write_raw(SaveService.slot_path(1), SaveCodec.encode(newer))
	var res := SaveService.load_slot(1)
	assert_false(res.ok)
	assert_eq(res.error, "newer", "nessun ripiego silenzioso sul backup vecchio")
	assert_false(SaveService.slot_info(1).ok)


func test_tmp_avanzato_non_disturba() -> void:
	SaveService.save_data(1, _sample(3))
	_write_raw(SaveService.slot_path(1) + ".tmp", "resto di un crash".to_utf8_buffer())
	assert_eq(SaveService.save_data(1, _sample(4)), OK)
	assert_eq(SaveService.load_slot(1).data.currencies.gold, 4)


func test_slot_info_ed_eliminazione() -> void:
	var d := _sample(8)
	d["stats"]["playtime_s"] = 7200.0
	d["saved_at_unix"] = 1790000000
	SaveService.save_data(3, d)
	SaveService.save_data(3, d)
	var info := SaveService.slot_info(3)
	assert_true(info.exists and info.ok)
	assert_eq(info.total_level, 12)
	assert_eq(info.mode, "normal")
	assert_almost_eq(info.playtime_s, 7200.0, 1e-6)
	SaveService.delete_slot(3)
	assert_false(SaveService.slot_exists(3))
	assert_false(FileAccess.file_exists(SaveService.backup_path(3, 1)))
	assert_false(SaveService.slot_info(3).exists)


func test_import_export_stringa() -> void:
	var s := SaveCodec.to_base64(_sample(21))
	var res := SaveService.import_string(s, 2)
	assert_true(res.ok)
	assert_eq(SaveService.load_slot(2).data.currencies.gold, 21)
	assert_false(SaveService.import_string("xyz", 2).ok)
	var newer := _sample(1)
	newer["schema_version"] = 999
	assert_eq(SaveService.import_string(SaveCodec.to_base64(newer), 1).error, "newer")
	assert_false(SaveService.slot_exists(1), "un import rifiutato non scrive nulla")


# ------------------------------------------------------------------ partita completa (Game + thread)

func test_partita_completa_round_trip() -> void:
	watch_signals(EventBus)
	assert_true(Game.new_game(1, "normal", 4242))
	assert_signal_emitted(EventBus, "game_started")
	assert_true(SaveService.slot_exists(1), "nuova partita salvata subito")
	GameState.data.currencies.gold = 999
	GameState.data.skills["mining"] = {"xp": 10.0, "level": 3, "record_level": 3, "stars": 0, "unlocked": true}
	var buffs: BuffSystem = Game.system("buffs")
	buffs.add_buff("potion_test", 100000.0, [{"key": "skill_xp_pct:all", "value": 5}])
	Rng.stream("loot").randi()
	assert_true(SaveService.save_now())
	var expect_rng := Rng.stream("loot").randi()
	Game.stop_game(false)
	assert_false(GameState.active)
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["all"]), 0.0, 1e-9, "modificatori azzerati alla chiusura")
	var res := Game.load_game(1)
	assert_true(res.ok, str(res.get("error")))
	assert_eq(GameState.gold(), 999)
	assert_eq(GameState.data.skills.mining.level, 3)
	assert_eq(typeof(GameState.data.skills.mining.level), TYPE_INT)
	assert_eq(Rng.stream("loot").randi(), expect_rng, "il flusso RNG riprende dal punto salvato")
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["all"]), 5.0, 1e-9, "i buff ri-registrano i modificatori")
	assert_gt((Game.system("buffs") as BuffSystem).remaining("potion_test"), 99000.0)
	assert_signal_emitted(EventBus, "state_loaded")


func test_salvataggio_su_thread() -> void:
	Game.new_game(2, "normal", 7)
	GameState.data.currencies.gold = 31337
	watch_signals(EventBus)
	SaveService.request_save()
	var waited := 0
	while SaveService.is_saving() and waited < 5000:
		OS.delay_msec(5)
		waited += 5
	SaveService._poll_thread()
	assert_signal_emitted_with_parameters(EventBus, "save_completed", [true])
	assert_eq(SaveService.load_slot(2).data.currencies.gold, 31337)


func test_modalita_sconosciuta_rifiutata() -> void:
	assert_false(Game.new_game(1, "hardcore"), "modalità inesistente")
	assert_false(GameState.active)
	assert_true(Game.new_game(1, "extreme"), "Estrema abilitata (docs/05 §7)")
	assert_eq(GameState.mode(), "extreme")


# ------------------------------------------------------------------ istante dell'ultimo salvataggio (pulizia A, «salvato N min fa»)

func test_ultimo_salvataggio_istante_e_secondi_trascorsi() -> void:
	SaveService.last_saved_unix = 0
	assert_eq(SaveService.seconds_since_save(), -1.0, "nessun salvataggio noto")
	assert_true(Game.new_game(1, "normal", 77))              # new_game salva subito (save_now)
	var t := Clock.now_unix()
	assert_gt(SaveService.last_saved_unix, 0)
	assert_lte(absi(SaveService.last_saved_unix - t), 2, "l'istante è quello del salvataggio appena fatto")
	assert_eq(SaveService.seconds_since_save(SaveService.last_saved_unix + 125), 125.0)
	assert_eq(SaveService.seconds_since_save(SaveService.last_saved_unix - 50), 0.0, "orologio tornato indietro: mai negativo")


func test_ultimo_salvataggio_si_aggiorna_con_ogni_scrittura_riuscita() -> void:
	assert_true(Game.new_game(1, "normal", 78))
	SaveService.last_saved_unix = 1000                       # finto: molto tempo fa
	assert_true(SaveService.save_now())
	assert_gt(SaveService.last_saved_unix, 1000, "save_now aggiorna l'istante")
	SaveService.last_saved_unix = 1000
	SaveService.request_save()
	var n := 0
	while SaveService.is_saving() and n < 200:
		await wait_process_frames(1)
		n += 1
	await wait_process_frames(3)                              # _poll_thread emette l'esito e aggiorna l'istante
	assert_gt(SaveService.last_saved_unix, 1000, "anche il salvataggio su thread aggiorna l'istante")


func test_caricamento_prende_l_istante_del_file() -> void:
	assert_true(Game.new_game(1, "normal", 79))
	assert_true(SaveService.save_now())
	var written := int(GameState.data.get("saved_at_unix", 0))
	Game.stop_game(false)
	SaveService.last_saved_unix = 0
	var res := Game.load_game(1)
	assert_true(res.ok)
	assert_eq(SaveService.last_saved_unix, written, "«salvato N min fa» conta dal file, non dall'apertura della partita")


# ------------------------------------------------------------------ Sabbia del Custode (UI F13): v3 -> v4

func test_migrazione_v3_a_v4_aggiunge_time_push_senza_toccare_il_progresso() -> void:
	assert_gte(SaveCodec.SCHEMA_VERSION, 4)
	var old := {"schema_version": 3, "bank": {"gold": 77}, "skills": {"woodcutting": {"xp": 12.5}}}
	var res := SaveCodec.migrate(old)
	assert_true(res.ok, str(res.get("error", "")))
	assert_eq(int(res.data.schema_version), SaveCodec.SCHEMA_VERSION)
	assert_true(res.data.time_push is Dictionary)
	assert_eq(float(res.data.time_push.reserve_s), 0.0)
	assert_false(bool(res.data.time_push.gift_given))
	assert_eq(int(res.data.bank.gold), 77, "progresso intatto")
	var again := SaveCodec.migrate_v3_to_v4(res.data)
	assert_eq(again.time_push, res.data.time_push, "idempotente")
	var kept := SaveCodec.migrate_v3_to_v4({"time_push": {"reserve_s": 12.0}})
	assert_eq(float(kept.time_push.reserve_s), 12.0, "una sezione gia' valida non si tocca")


func test_salvataggio_vecchio_senza_sezione_si_carica_con_la_sabbia_vuota() -> void:
	assert_true(Game.new_game(1, "normal", 515))
	var snap := Game.snapshot(true).duplicate(true)
	snap["schema_version"] = 3
	snap.erase("time_push")
	var loaded := SaveCodec.load_bytes(SaveCodec.encode(snap), Game.sim.int_paths())
	assert_true(bool(loaded.ok), str(loaded.get("error", "")))
	assert_eq(int(loaded.data.schema_version), SaveCodec.SCHEMA_VERSION)
	assert_true((loaded.data.time_push as Dictionary).has("reserve_s"))
	# anche senza la migrazione, Simulation.bind_state completa la sezione mancante
	var raw: Dictionary = snap.duplicate(true)
	GameState.replace(raw)
	Game.sim.bind_state(GameState.data)
	assert_true(GameState.data.has("time_push"))
	assert_eq(float(GameState.data.time_push.reserve_s), 0.0)
	Game.stop_game(false)
