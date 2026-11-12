extends GutTest
## SHARK 1.0 (docs/review_1_0/01_SHARK_CODICE.md): salvataggi e robustezza tecnica. Un test per ogni punto sistemato:
##   #1 backup a profondita' di ore + copia pre-migrazione + copia giornaliera · #2 import validato e con conferma ·
##   #3 stato non salvabile -> saturazione · #4 interi oltre 2^53 esatti · #5 NumberFormat con NaN/inf ·
##   #6 numeri di bilanciamento di CombatSim da constants.json · #7 load_game/new_game con partita sporca ·
##   #8 uscita con salvataggio fallito · #9 impostazioni atomiche · #10 debug solo in build di sviluppo.

const GS := preload("res://src/autoload/GameState.gd")
const T0 := 1_700_000_000
const INT64_MAX := 9223372036854775807

var _old_dir: String
var _dir: String
var _t: Array = [T0]


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_dir = "user://test_save_safety_%d" % Time.get_ticks_usec()
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	SaveService.backup_interval_s = SaveService.BACKUP_INTERVAL_S
	_t = [T0]
	SaveService.time_source = func() -> int: return _t[0]


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for slot in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(slot)
	for f in DirAccess.get_files_at(_dir) if DirAccess.dir_exists_absolute(_dir) else PackedStringArray():
		DirAccess.remove_absolute(_dir + "/" + f)
	DirAccess.remove_absolute(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	SaveService.backup_interval_s = SaveService.BACKUP_INTERVAL_S
	SaveService.time_source = Callable()
	SaveService.last_save_ok = true


func _sample(marker: int) -> Dictionary:
	var d := GS.default_state("normal")
	d["currencies"]["gold"] = marker
	d["rng"] = RngStreams.new(marker).to_state()
	return d


func _handle_engine_errors() -> int:
	var n := 0
	for e in get_errors():
		e.handled = true
		n += 1
	return n


func _gold_of(path: String) -> int:
	return int(SaveCodec.decode(FileAccess.get_file_as_bytes(path)).data.currencies.gold)


# ------------------------------------------------------------------ #1 backup

func test_01_venti_salvataggi_in_un_minuto_non_consumano_i_backup() -> void:
	for i in range(1, 21):
		assert_eq(SaveService.save_data(1, _sample(i)), OK)
		_t[0] += 3
	assert_eq(_gold_of(SaveService.slot_path(1)), 20)
	assert_eq(_gold_of(SaveService.backup_path(1, 1)), 1, "il backup resta il primo stato: non e' stato rimpiazzato dai salvataggi ravvicinati")
	assert_false(FileAccess.file_exists(SaveService.backup_path(1, 2)), "nessuna rotazione ulteriore in un minuto")


func test_01_i_backup_coprono_decine_di_minuti() -> void:
	# un'ora di gioco con un salvataggio ogni 30 s: i tre backup distano almeno 10 minuti l'uno dall'altro
	var n := 0
	for i in 121:
		n += 1
		assert_eq(SaveService.save_data(1, _sample(n)), OK)
		_t[0] += 30
	var g1 := _gold_of(SaveService.backup_path(1, 1))
	var g2 := _gold_of(SaveService.backup_path(1, 2))
	var g3 := _gold_of(SaveService.backup_path(1, 3))
	assert_gte(g1 - g2, 20, "bak1 e bak2 distano >= 10 min (20 salvataggi da 30 s)")
	assert_gte(g2 - g3, 20, "bak2 e bak3 distano >= 10 min")
	assert_gte(n - g3, 40, "il backup piu' vecchio ha almeno 20 minuti")
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(res.source, "main")


func test_01_la_copia_giornaliera_tiene_le_ultime_7() -> void:
	for day in 10:
		assert_eq(SaveService.save_data(1, _sample(day * 10 + 1)), OK)
		assert_eq(SaveService.save_data(1, _sample(day * 10 + 2)), OK)
		_t[0] += 86400
	var copies := SaveService.day_copies(1)
	assert_eq(copies.size(), SaveService.DAY_COPIES, "al massimo 7 copie giornaliere")
	for p in copies:
		assert_true(SaveCodec.decode(FileAccess.get_file_as_bytes(p)).ok, p)
	# la piu' recente e' lo stato prima dell'ultimo giorno (primo salvataggio del giorno 10 ha copiato il file del giorno 9)
	assert_gt(_gold_of(copies[0]), _gold_of(copies[copies.size() - 1]), "ordine dalla piu' recente")


func test_01_la_copia_giornaliera_e_l_ultimo_salvagente() -> void:
	SaveService.backup_interval_s = 0.0
	for i in range(1, 5):
		assert_eq(SaveService.save_data(1, _sample(i)), OK)
	assert_false(SaveService.day_copies(1).is_empty())
	for p in [SaveService.slot_path(1), SaveService.backup_path(1, 1), SaveService.backup_path(1, 2), SaveService.backup_path(1, 3)]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("rovinato")
		f.close()
	var res := SaveService.load_slot(1)
	assert_true(res.ok, str(res.get("error", "")))
	assert_eq(res.source, "day")
	_handle_engine_errors()


func test_01_copie_pre_migrazione_una_per_versione() -> void:
	var v3 := FileAccess.get_file_as_bytes("res://tests/golden/save_v3_reale_c3q1.sav")
	var v4 := FileAccess.get_file_as_bytes("res://tests/golden/save_v4_reale_c3q1.sav")
	DirAccess.make_dir_recursive_absolute(_dir)
	assert_eq(SaveService.write_atomic(1, v3), OK)
	assert_true(SaveService.load_slot(1).ok)
	assert_eq(FileAccess.get_file_as_bytes(SaveService.pre_migration_path(1, 3)), v3)
	# un secondo file v3 (altra partita nello stesso slot) NON sostituisce la copia
	var other: Dictionary = SaveCodec.decode(v3).data
	other["currencies"]["gold"] = 123456
	assert_eq(SaveService.write_atomic(1, SaveCodec.encode(other)), OK)
	assert_true(SaveService.load_slot(1).ok)
	assert_eq(FileAccess.get_file_as_bytes(SaveService.pre_migration_path(1, 3)), v3, "mai sovrascritta")
	# un file v4 ha la sua copia
	assert_eq(SaveService.write_atomic(1, v4), OK)
	assert_true(SaveService.load_slot(1).ok)
	assert_eq(FileAccess.get_file_as_bytes(SaveService.pre_migration_path(1, 4)), v4)
	assert_eq(SaveService.pre_migration_copies(1), PackedStringArray([SaveService.pre_migration_path(1, 4), SaveService.pre_migration_path(1, 3)]))
	# un file gia' alla versione corrente non genera copie
	assert_eq(SaveService.write_atomic(1, SaveCodec.encode(_sample(5))), OK)
	assert_true(SaveService.load_slot(1).ok)
	assert_false(FileAccess.file_exists(SaveService.pre_migration_path(1, SaveCodec.SCHEMA_VERSION)))
	# eliminare lo slot toglie anche le copie
	SaveService.delete_slot(1)
	assert_true(SaveService.pre_migration_copies(1).is_empty())
	assert_true(SaveService.day_copies(1).is_empty())


# ------------------------------------------------------------------ #2 import

func _export_string(gold: int) -> String:
	assert_true(Game.new_game(3, "normal", 77))
	GameState.data.currencies["gold"] = gold
	var s := SaveCodec.to_base64(Game.snapshot(true))
	Game.stop_game(false)
	SaveService.delete_slot(3)
	return s


func test_02_import_con_sezione_di_tipo_sbagliato_e_rifiutato_e_lo_slot_resta() -> void:
	assert_true(Game.new_game(3, "normal", 78))
	var snap: Dictionary = Game.snapshot(true).duplicate(true)
	Game.stop_game(false)
	SaveService.delete_slot(3)
	assert_true(Game.new_game(2, "normal", 5))
	GameState.data.currencies["gold"] = 4321
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	for bad in [{"currencies": "oops"}, {"hero": {"hp": "x"}}, {"bank": {"instances": {}}}]:
		var broken := snap.duplicate(true)
		for k in bad:
			if broken.get(k) is Dictionary and bad[k] is Dictionary:
				(broken[k] as Dictionary).merge(bad[k], true)
			else:
				broken[k] = bad[k]
		var res := SaveService.import_string(SaveCodec.to_base64(broken), 2, true)
		assert_false(res.ok, "sezione sbagliata %s: non si importa" % str(bad.keys()))
		assert_eq(res.error, "corrupt_types", str(bad))
		assert_eq(int(SaveService.load_slot(2).data.currencies.gold), 4321, "lo slot di destinazione e' intatto")
	_handle_engine_errors()


func test_02_import_su_slot_occupato_chiede_conferma_e_conserva_la_partita_vecchia() -> void:
	var s := _export_string(5555)
	assert_true(Game.new_game(2, "normal", 5))
	GameState.data.currencies["gold"] = 4321
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	var res := SaveService.import_string(s, 2)
	assert_false(res.ok)
	assert_eq(res.error, "slot_occupied", "senza conferma uno slot occupato non si sovrascrive")
	assert_eq(int(SaveService.load_slot(2).data.currencies.gold), 4321)
	res = SaveService.import_string(s, 2, true)
	assert_true(res.ok, str(res.get("error", "")))
	assert_eq(int(SaveService.load_slot(2).data.currencies.gold), 5555, "con la conferma l'import scrive")
	assert_eq(_gold_of(SaveService.backup_path(2, 1)), 4321, "la partita sostituita resta in .bak1 anche con salvataggi ravvicinati")
	# slot libero: nessuna conferma
	res = SaveService.import_string(s, 3)
	assert_true(res.ok)
	# senza slot = solo validazione
	assert_true(SaveService.import_string(s, 0).ok)


func test_02_i_codici_d_errore_dell_import_hanno_un_messaggio_per_ciascuno() -> void:
	var generic := TranslationServer.translate("UI_IMPORT_FAILED")
	for code in ["empty", "base64", "gzip", "json", "not_object", "no_version", "newer", "missing_migration", "migration_failed", "corrupt_types", "write_failed"]:
		var t := SaveService.import_error_text(code)
		assert_ne(t, "", code)
		assert_ne(t, "UI_SAVESAFE_IMPORT_ERR_" + code.to_upper(), "chiave tradotta: " + code)
		assert_ne(t, generic, "messaggio specifico per " + code)
	assert_eq(SaveService.import_error_text("codice_sconosciuto"), generic, "codice ignoto: messaggio generico")
	assert_eq(SaveService.import_string("xyz", 1).error, "base64")


# ------------------------------------------------------------------ #3 saturazione

## Pianta `value` nel punto indicato da un percorso intero di Simulation.int_paths() (con * e []).
func _plant(root: Dictionary, path: String, value: Variant) -> bool:
	var node: Variant = root
	var parts := path.split(".")
	for i in parts.size():
		var part := parts[i]
		var arr := part.ends_with("[]")
		if arr:
			part = part.substr(0, part.length() - 2)
		if part.ends_with("[]"):
			return false
		var key := "k" if part == "*" else part
		var last := i == parts.size() - 1
		if arr:
			node[key] = [value] if last else [{}]
			node = (node[key] as Array)[0] if not last else null
		elif last:
			node[key] = value
		else:
			node[key] = {}
			node = node[key]
	return true


func test_03_ogni_percorso_intero_al_massimo_si_salva_e_si_ricarica() -> void:
	var paths := Game.sim.int_paths()
	assert_gt(paths.size(), 100)
	var planted := 0
	for p in paths:
		if p == "schema_version":
			continue
		for v in [INT64_MAX, -INT64_MAX - 1, 1.0e300, -1.0e300, NAN, INF]:
			var d := {"schema_version": SaveCodec.SCHEMA_VERSION}
			if not _plant(d, p, v):
				continue
			planted += 1
			var one := PackedStringArray([p])
			var fixed := SaveCodec.prepare_for_write(d, one)
			assert_false(fixed.is_empty(), "%s = %s: corretto" % [p, str(v)])
			var res := SaveCodec.load_bytes(SaveCodec.encode(d), one)
			assert_true(res.ok, "%s = %s: dopo la preparazione il file si riapre (%s)" % [p, str(v), str(res.get("paths", ""))])
	assert_gt(planted, 500)


func test_03_stato_non_salvabile_si_satura_e_non_si_perde_nulla() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.currencies["gold"] = 777
	GameState.data.stats["kills"] = INT64_MAX
	(GameState.data.factions as Dictionary)["order_of_wardens"] = -INT64_MAX - 1
	assert_true(SaveService.save_now(), "il salvataggio riesce")
	assert_true(SaveService.last_save_ok)
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(int(res.data.currencies.gold), 777)
	assert_eq(int(res.data.stats.kills), SaveCodec.SAFE_INT_MAX, "saturato al limite sicuro")
	assert_eq(int(res.data.factions.order_of_wardens), -SaveCodec.SAFE_INT_MAX)
	# anche il salvataggio su thread (autosalvataggio)
	GameState.data.currencies["gold"] = 778
	SaveService.request_save()
	SaveService._finish_thread()
	assert_eq(int(SaveService.load_slot(1).data.currencies.gold), 778)
	_handle_engine_errors()


# ------------------------------------------------------------------ #4 precisione oltre 2^53

func test_04_interi_oltre_2_alla_53_restano_esatti() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var big := (1 << 60) + 1
	var odd := 9007199254740993          # 2^53 + 1: un double non lo rappresenta
	GameState.data.currencies["gold"] = big
	GameState.data.stats["gold_earned"] = odd
	assert_true(SaveService.save_now())
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(int(res.data.currencies.gold), big, "2^60+1 esatto dopo salva/carica")
	assert_eq(typeof(res.data.currencies.gold), TYPE_INT)
	assert_eq(int(res.data.stats.gold_earned), odd, "2^53+1 esatto")
	# round trip dallo stato vivo: la partita ricaricata ha lo stesso valore
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	assert_eq(int(GameState.data.currencies.gold), big)
	# il file contiene una stringa di cifre, non un double (R-SAV-7); il codec la riconverte in int
	assert_true(SaveCodec._as_int("9007199254740993")[1] is int)
	assert_eq(SaveCodec._as_int("9007199254740993")[1], 9007199254740993)
	assert_eq(SaveCodec._as_int("123456789012345678901")[1], "123456789012345678901", "oltre il tetto resta stringa (invariato)")


# ------------------------------------------------------------------ #5 NumberFormat

func test_05_numberformat_con_nan_inf_e_durate_enormi() -> void:
	for lang in ["en", "it"]:
		assert_eq(NumberFormat.format_number(NAN, "short", lang), "-")
		assert_eq(NumberFormat.format_number(INF, "short", lang), "∞")
		assert_eq(NumberFormat.format_number(-INF, "short", lang), "-∞")
		assert_eq(NumberFormat.format_number(INF, "scientific", lang), "∞")
		assert_eq(NumberFormat.format_number(NAN, "full", lang), "-")
		assert_eq(NumberFormat.cell(NAN, lang), "-")
		assert_eq(NumberFormat.cell(INF, lang), "∞")
		assert_eq(NumberFormat.decimal(NAN, 2, lang), "-")
		assert_eq(NumberFormat.format_pct(INF, lang), "∞")
		assert_eq(NumberFormat.format_number(-0.0001, "short", lang), "0", "mai «-0»")
		assert_eq(NumberFormat.format_number(-0.4, "short", lang), "0")
		assert_eq(NumberFormat.format_number(-1234.0, "short", lang), "-1.234" if lang == "it" else "-1,234")
	var units := {"s": "s", "min": "min", "h": "h", "d": "d"}
	assert_eq(NumberFormat.format_duration(INF, units), "∞")
	assert_eq(NumberFormat.format_duration(1.0e300, units), "∞")
	assert_eq(NumberFormat.format_duration(NAN, units), "-")
	assert_eq(NumberFormat.format_duration(86400.0 * 400.0, units), "400 d")
	assert_eq(NumberFormat.fmt(NAN), "-")
	assert_eq(NumberFormat.fmt_time(INF), "∞")
	assert_eq(NumberFormat.fmt_time(1.0e300), "∞")


# ------------------------------------------------------------------ #6 numeri di bilanciamento

func test_06_seconda_possibilita_e_pavimento_vita_vengono_dai_dati() -> void:
	var rules: Dictionary = DataRegistry.constants.combat.rules
	assert_eq(int(rules.revive_once_hp_pct), 30, "valore di gioco (tools/gamedata/core.py)")
	assert_eq(int(rules.enemy_hp_floor_pct), 5)
	var sim := CombatSim.new()
	sim.st = {"hp": 200.0, "revive_once": true}
	sim.rules = {"revive_once_hp_pct": 50, "enemy_hp_floor_pct": 10}
	var h := {"hp": 0.0, "rt": CombatSim.new_rt()}
	assert_true(sim._revive_if_possible(h))
	assert_almost_eq(float(h.hp), 100.0, 1e-9, "50% di 200: il numero e' quello dei dati, non uno fisso nel codice")
	assert_false(sim._revive_if_possible(h), "una sola volta per scontro")
	sim.ms = {"hp": 1000.0}
	sim.mon = {"id": "x"}
	assert_almost_eq(float(sim.new_enemy(1.0, 1.0, false, -5000.0).hp), 100.0, 1e-9, "pavimento = 10% della vita base")
	var src := FileAccess.get_file_as_string("res://src/systems/CombatSim.gd")
	assert_false(src.contains("* 0.3\n"), "nessun 0.3 di bilanciamento nel codice")


# ------------------------------------------------------------------ #7 partita sporca

func test_07_caricare_un_altro_slot_salva_prima_la_partita_in_corso() -> void:
	assert_true(Game.new_game(1, "normal", 11))
	assert_true(Game.new_game(2, "normal", 12))
	GameState.data.currencies["gold"] = 4242                 # solo in memoria
	assert_true(Game.load_game(1).ok)
	assert_eq(int(SaveService.load_slot(2).data.currencies.gold), 4242, "lo slot 2 e' stato salvato prima di sostituirlo")
	assert_eq(GameState.slot, 1)


func test_07_nuova_partita_salva_quella_in_corso_e_conserva_la_vecchia_in_bak1() -> void:
	assert_true(Game.new_game(1, "normal", 11))
	GameState.data.currencies["gold"] = 999
	assert_true(Game.new_game(2, "normal", 12))
	assert_eq(int(SaveService.load_slot(1).data.currencies.gold), 999, "i progressi non salvati della partita 1 non sono persi")
	# nuova partita sopra uno slot occupato: la vecchia passa a .bak1 anche con salvataggi ravvicinati
	assert_true(Game.new_game(1, "normal", 13))
	assert_eq(_gold_of(SaveService.backup_path(1, 1)), 999)


func test_07_ricaricare_lo_stesso_slot_torna_all_ultimo_salvataggio() -> void:
	assert_true(Game.new_game(1, "normal", 11))
	GameState.data.currencies["gold"] = 31
	assert_true(SaveService.save_now())
	GameState.data.currencies["gold"] = 32
	assert_true(Game.load_game(1).ok)
	assert_eq(int(GameState.data.currencies.gold), 31, "ricaricare lo stesso slot scarta lo stato in memoria (voluto)")


# ------------------------------------------------------------------ #8 uscita

func test_08_uscita_con_salvataggio_fallito_chiede_conferma_e_non_chiude() -> void:
	assert_true(Game.new_game(1, "normal", 11))
	var blocker := "user://test_blocker_%d" % Time.get_ticks_usec()
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("sono un file, non una cartella")
	f.close()
	SaveService.save_dir = blocker + "/saves"                # impossibile da creare: simula disco pieno / cartella non scrivibile
	assert_false(SaveService.final_save_ok(), "il salvataggio finale fallisce")
	assert_false(SaveService.last_save_ok)
	SaveService.quit_game()                                   # NON chiude: mostra la domanda
	assert_not_null(get_tree(), "il gioco e' ancora in esecuzione")
	assert_true(is_instance_valid(SaveService._fail_dialog), "finestra «uscire comunque?»")
	assert_ne(SaveService.last_error, "")
	assert_true(SaveService._fail_dialog.dialog_text.contains(SaveService.last_error), "il messaggio riporta l'errore: " + SaveService._fail_dialog.dialog_text)
	assert_ne(SaveService._fail_dialog.title, "UI_SAVESAFE_QUIT_TITLE", "titolo tradotto")
	SaveService._fail_dialog.queue_free()
	SaveService.save_dir = _dir
	assert_true(SaveService.final_save_ok(), "con una cartella valida il salvataggio finale riesce")
	assert_true(SaveService.last_save_ok)
	DirAccess.remove_absolute(blocker)
	_handle_engine_errors()


func test_08_senza_partita_il_salvataggio_finale_e_banale() -> void:
	assert_false(GameState.active)
	assert_true(SaveService.final_save_ok())


# ------------------------------------------------------------------ #9 impostazioni

func test_09_impostazioni_atomiche_con_ripiego_sul_tmp() -> void:
	var old_path := Settings.path
	var old_values: Dictionary = Settings._values.duplicate(true)
	Settings.path = "user://test_settings_atomic_%d.cfg" % Time.get_ticks_usec()
	Settings._last_write_ms = -100000
	Settings._key_hits.clear()
	assert_true(Settings.set_value("volume_music", 0.25))
	assert_true(FileAccess.file_exists(Settings.path))
	assert_false(FileAccess.file_exists(Settings.path + ".tmp"), "nessun .tmp lasciato")
	assert_eq(Settings.last_save_error, OK)
	# trascinamento di un cursore: la prima scrittura va subito, le successive si fondono e flush() scrive l'ultima
	assert_true(Settings.set_value("volume_music", 0.30))
	assert_true(Settings.set_value("volume_music", 0.35))
	assert_true(Settings.set_value("volume_music", 0.40))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.path), OK)
	assert_true(Settings._dirty, "scrittura ritardata in attesa")
	Settings.flush()
	assert_false(Settings._dirty)
	assert_eq(cfg.load(Settings.path), OK)
	assert_almost_eq(float(cfg.get_value(Settings.SECTION, "volume_music")), 0.40, 1e-9, "l'ultimo valore e' su disco")
	# chiusura brusca tra .tmp e rinomina: main assente, .tmp completo -> si legge il .tmp
	DirAccess.rename_absolute(Settings.path, Settings.path + ".tmp")
	Settings.load_settings()
	assert_almost_eq(float(Settings.get_value("volume_music")), 0.40, 1e-9)
	# file principale troncato e nessun .tmp: valori predefiniti, nessun errore
	DirAccess.remove_absolute(Settings.path + ".tmp")
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string("[settings\nvolume_mu")
	f.close()
	Settings.load_settings()
	assert_eq(Settings.get_value("volume_music"), Settings.DEFAULTS.volume_music)
	DirAccess.remove_absolute(Settings.path)
	Settings._dirty = false
	Settings.path = old_path
	Settings._values = old_values
	Settings.apply_all()
	_handle_engine_errors()


# ------------------------------------------------------------------ #10 debug solo in sviluppo

func test_10_gli_strumenti_di_debug_non_si_accendono_in_rilascio() -> void:
	assert_false(DevTools.is_enabled(false, "1"), "VAULTFALL_DEBUG=1 non basta in un export di rilascio")
	assert_false(DevTools.is_enabled(false, ""))
	assert_true(DevTools.is_enabled(true, "1"))
	assert_true(DevTools.is_enabled(true, ""))
	assert_eq(DevTools.is_dev_build(), OS.has_feature("editor") or OS.has_feature("debug"))
	Feedback.simulate_release = true
	assert_false(Feedback.dev_enabled())
	assert_false(Feedback.handle_key(KEY_F10))
	Feedback.simulate_release = false
	# nessun altro punto del codice di produzione legge VAULTFALL_DEBUG per accendere qualcosa
	var users := 0
	for p in ["res://src/autoload/Feedback.gd", "res://src/feedback/DevTools.gd", "res://src/feedback/DevMenu.gd"]:
		users += FileAccess.get_file_as_string(p).count("OS.get_environment")
	assert_eq(users, 2, "solo Feedback.dev_enabled e DevTools.is_enabled leggono la variabile, e solo dopo il controllo della build")
	var fb := FileAccess.get_file_as_string("res://src/autoload/Feedback.gd")
	assert_true(fb.contains('OS.has_feature("editor") or OS.has_feature("debug")'))
