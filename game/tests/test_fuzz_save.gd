extends GutTest
## QA 72 - fuzzing dei salvataggi (seme fisso). I difetti noti sono corretti: ogni controllo e' un controllo vero
## (nessun pending(), SHARK 1.0 #11). Dettagli: docs/audit_2026-10-22/qa/72_QA_FUZZ.md.

var _old_dir: String
var _dir: String
var _log: FuzzLib.ErrLog
var _base: Dictionary
var _good: PackedByteArray


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_dir = FuzzLib.tmp_save_dir("gut")
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	Game.new_game(1, "normal", 99)
	var r := RandomNumberGenerator.new()
	r.seed = 72
	FuzzLib.enrich(r)
	FuzzLib.run_steps(120.0)
	_base = Game.snapshot(true).duplicate(true)
	_good = SaveCodec.encode(_base)
	Game.stop_game(false)
	_log = FuzzLib.make_log()


func after_all() -> void:
	FuzzLib.drop_log(_log)
	if GameState.active:
		Game.stop_game(false)
	FuzzLib.rm_dir(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _handle() -> void:
	for e in get_errors():
		e.handled = true


func _install(main: PackedByteArray) -> void:
	FuzzLib.rm_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	FuzzLib.write_raw(SaveService.slot_path(1), main)
	FuzzLib.write_raw(SaveService.backup_path(1, 1), _good)
	FuzzLib.write_raw(SaveService.backup_path(1, 2), _good)


func test_byte_corrotti_ripiegano_sul_backup() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 72
	var cases := FuzzSave.byte_mutations(_base, r)
	var tried := 0
	for c in cases:
		if str(c.name).begins_with("gzip + spazzatura") or str(c.name).begins_with("due gzip"):
			continue          # F1: blocco
		_install(c.bytes)
		var mark := _log.count()
		var res: Dictionary = Game.load_game(1)
		assert_true(res.get("ok", false), "caricamento con '%s'" % c.name)
		assert_eq(_log.sigs_since(mark, true), [], "nessun errore di script con '%s'" % c.name)
		if res.get("ok", false) and res.source == "main":
			continue
		assert_true(FileAccess.file_exists(SaveService.backup_path(1, 1)), "backup conservato")
		Game.stop_game(false)
		tried += 1
	assert_gt(tried, 20)
	_handle()


func test_file_assenti_o_tutti_rotti_non_crashano() -> void:
	FuzzLib.rm_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	var res: Dictionary = Game.load_game(1)
	assert_false(res.ok)
	assert_eq(res.error, "missing")
	for p in [SaveService.slot_path(1), SaveService.backup_path(1, 1), SaveService.backup_path(1, 2), SaveService.backup_path(1, 3)]:
		FuzzLib.write_raw(p, PackedByteArray([1, 2, 3]))
	res = Game.load_game(1)
	assert_false(res.ok)
	for bad in [0, -1, 4, 999]:
		assert_eq(Game.load_game(bad).error, "invalid_slot")
	# .tmp orfano valido non e' un salvataggio
	FuzzLib.rm_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	FuzzLib.write_raw(SaveService.slot_path(1) + ".tmp", _good)
	assert_false(Game.load_game(1).ok)
	_handle()


func test_base64_import_assurdi() -> void:
	var b64 := SaveCodec.to_base64(_base)
	assert_true(SaveService.import_string(b64, 0).ok)
	for bad in ["", "   ", "!!!!@@@@", b64.substr(0, b64.length() - 1), b64.substr(0, b64.length() / 2), b64 + "A", "ÿÿÿÿ"]:
		var mark := _log.count()
		var out: Dictionary = SaveService.import_string(bad, 0)
		assert_false(out.ok, "rifiutato: %s" % bad.substr(0, 20))
		assert_eq(_log.sigs_since(mark, true), [])
	var fut := _base.duplicate(true)
	fut["schema_version"] = 99
	assert_eq(SaveService.import_string(SaveCodec.to_base64(fut), 0).error, "newer")
	_handle()


func test_byte_in_coda_al_gzip_F1() -> void:
	## F1: byte dopo il flusso gzip bloccavano decompress_dynamic all'infinito. Ora: errore "gzip" e ripiego sul backup.
	for tail in [[0, 0, 0, 0], [1], [0x1f, 0x8b, 8, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]:
		var bytes := _good.duplicate()
		bytes.append_array(PackedByteArray(tail))
		assert_false(SaveCodec.decode(bytes).ok, "coda di %d byte rifiutata" % tail.size())
		_install(bytes)
		var res: Dictionary = SaveService.load_slot(1, Game.sim.int_paths())
		assert_true(res.ok, "ripiego sul backup")
		assert_eq(res.get("source", ""), "bak1")
		assert_true(SaveService.slot_info(1).ok)
		assert_false(SaveService.import_string(Marshalls.raw_to_base64(bytes), 0).ok)
	# trailer con dimensione dichiarata assurda (bomba di decompressione) o nulla
	for n in [0, SaveCodec.MAX_RAW_BYTES + 1, 0xFFFFFFFF]:
		var b := _good.duplicate()
		b.encode_u32(b.size() - 4, n)
		assert_false(SaveCodec.decode(b).ok, "dimensione dichiarata %d rifiutata" % n)
	assert_true(SaveCodec.decode(_good).ok)
	_handle()


func _same_kind(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return true
	return typeof(a) == typeof(b)


func test_sezioni_con_tipo_sbagliato_F2() -> void:
	## F2: JSON valido ma con una sezione di tipo sbagliato non e' un salvataggio buono: si ripiega sul backup.
	var keys := ["skills", "bank", "hero", "quests", "prestige", "market", "rng", "stats", "unlocks", "currencies",
		"crates", "estate", "contracts", "farming", "saved_at_unix", "mode"]
	var tried := 0
	for k in keys:
		for wrong in [5, "x", null, [], {"a": 1}, true]:
			if not _base.has(k) or _same_kind(_base[k], wrong):
				continue
			var d := _base.duplicate(true)
			d[k] = wrong
			_install(SaveCodec.encode(d))
			var res: Dictionary = SaveService.load_slot(1, Game.sim.int_paths())
			assert_eq(res.get("source", ""), "bak1", "%s=%s ripiega sul backup" % [k, str(wrong)])
			tried += 1
	assert_gt(tried, 60)
	# campi di secondo livello
	for pair in [["bank", "stacks", []], ["bank", "instances", {}], ["hero", "attrs", 3], ["stats", "kills", "x"],
			["prestige", "constellations", []], ["currencies", "gold", []], ["currencies", "gold", null]]:
		var d := _base.duplicate(true)
		(d[pair[0]] as Dictionary)[pair[1]] = pair[2]
		_install(SaveCodec.encode(d))
		assert_eq(SaveService.load_slot(1, Game.sim.int_paths()).get("source", ""), "bak1", "%s.%s" % [pair[0], pair[1]])
	# il salvataggio buono non e' mai un falso positivo
	_install(_good)
	assert_eq(SaveService.load_slot(1, Game.sim.int_paths()).get("source", ""), "main")
	_handle()


func test_load_game_con_rng_e_data_non_validi() -> void:
	## Se anche i backup sono sbagliati la partita non parte, ma senza errori e senza stato a meta'.
	var d := _base.duplicate(true)
	d["rng"] = 7
	d["saved_at_unix"] = null
	FuzzLib.rm_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	FuzzLib.write_raw(SaveService.slot_path(1), SaveCodec.encode(d))
	var mark := _log.count()
	var res: Dictionary = Game.load_game(1)
	assert_false(res.ok)
	assert_false(GameState.active)
	assert_eq(_log.sigs_since(mark, true), [])
	_handle()
