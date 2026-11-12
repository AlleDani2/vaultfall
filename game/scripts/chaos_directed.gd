extends "res://scripts/chaos_bot.gd"
## QA 83 — prove MIRATE (non casuali) accanto al bot caotico: coop con input malformati e giganti, migrazione dello schema 1 -> 2,
## tolleranza a sezioni mancanti/null/di tipo sbagliato, e i sistemi nuovi (Loadout, Clessidra, Codex, Assist, Modalità, Commesse).
## Uso: godot --headless --path game scripts/chaos_directed.tscn -- --seed=3 --only=coop,migr,miss,sys --out=/percorso/dir.json
## Ogni sezione annota i problemi con `note()` (stessa forma del bot caotico); non fa mai asserzioni che fermano il processo.

var only: Array = []
var base_snap: Dictionary = {}
var results: Dictionary = {}              # sezione -> riepilogo di cosa è stato provato


func _ready() -> void:
	await get_tree().process_frame
	_parse_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	_setup()
	Settings.set_value("locale", "it")
	cur = "base_game"
	_make_base()
	for sec in ["coop", "migr", "miss", "sys", "hg"]:
		if only.is_empty() or only.has(sec):
			var t0 = Time.get_ticks_msec()
			cur = "section " + sec
			call("_sec_" + sec)
			results[sec + "_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	stats["results"] = results
	stats["sim_h"] = sim_t / 3600.0
	_write_out()
	OS.remove_logger(logger)
	get_tree().quit(0)


func _make_base() -> void:
	Game.new_game(slot, "normal", seed_v)
	bot = BotPlayer.new(Game.sim, Callable(Game, "_on_step"))
	bot.long_mode = true
	bot.step_long = Callable(Game, "_on_long_gap")
	var h = float(OS.get_environment("CHAOS_BASE_H")) if OS.get_environment("CHAOS_BASE_H") != "" else 5.0
	_run_bot(h * 3600.0)
	_unlock(["feature:coop", "feature:market", "feature:factions"])
	base_snap = Game.snapshot(true)
	results["base"] = {"hours": sim_t / 3600.0, "level": GameState.total_level(), "unlocks": (GameState.data.unlocks as Array).size()}


func _unlock(tokens: Array) -> void:
	for t in tokens:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)


func _reload_base() -> void:
	# riparte dallo stato di base (nessuna partita residua dai test precedenti)
	cur_hostile = false
	SaveService.write_atomic(slot, SaveCodec.encode(base_snap))
	var r = Game.load_game(slot)
	if not bool(r.ok):
		note("save", "base_reload_failed", "ricarica dello stato di base: %s" % str(r.error))


func _now() -> int:
	return Clock.now_unix()


# ===================================================================== COOP
func _sec_coop() -> void:
	_reload_base()
	var coop = Game.system("coop") as CoopSystem
	var rules: Dictionary = coop.rules()
	var f: Dictionary = rules.format
	var good: String = coop.export_hero_code(_now())
	if good.is_empty():
		note("coop", "export_empty", "export_hero_code ha restituito un codice vuoto")
		return
	results["coop_good_len"] = good.length()
	var up = CoopCodec.unpack(good, int(f.version), "", str(f.prefix), int(rules.code.max_chars), int(rules.code.max_json_bytes))
	if not bool(up.ok):
		note("coop", "export_roundtrip", "il codice esportato non si riapre: %s" % str(up.error))
		return
	var payload: Dictionary = up.payload
	var n_cases = 0
	var accepted = 0
	var crashes = 0

	# --- A) stringhe a caso, troncamenti, mutazioni di un carattere
	var corpus: Array = []
	for i in good.length():
		if i % 7 == 0:
			corpus.append(good.substr(0, i))
	for k in 400:
		var chars = good.split("")
		var pos = rng.randi_range(0, chars.size() - 1)
		chars[pos] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=.! "[rng.randi() % 67]
		corpus.append("".join(chars))
	for k in 200:
		var len = [1, 4, 10, 100, 1000, 6000, 6001, 20000][rng.randi() % 8]
		var s = ""
		for j in len:
			s += "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="[rng.randi() % 65]
		corpus.append(["VFH1.", "VFR1.", "VFM1.", "VF", "", "VFH1."][rng.randi() % 6] + s)
	for pre in ["VFH0.", "VFH2.", "VFH99999.", "VFH-1.", "VFHx.", "VFH1", "VFH1.", ".", "VFH.", "VFH1..", "vfh1.", "VFZ1.", "VFH01.", "VFH1.====", " VFH1. "]:
		corpus.append(pre + good.substr(good.find(".") + 1))
		corpus.append(pre)
	# giganti
	corpus.append("VFH1." + "A".repeat(1000000))
	corpus.append("V".repeat(5000000))
	corpus.append(good + good)
	corpus.append(good.repeat(1000))
	corpus.append("\n".repeat(3000) + good)
	corpus.append(good.substr(0, good.find(".") + 1) + "èèè" + good.substr(good.find(".") + 4))
	corpus.append("VFH1." + Marshalls.raw_to_base64(PackedByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
	# bomba gzip: ISIZE che mente (dichiara 100 byte, espande a MB)
	var zeros = PackedByteArray()
	zeros.resize(4 * 1024 * 1024)
	var gz = zeros.compress(FileAccess.COMPRESSION_GZIP)
	results["coop_bomb_gz_bytes"] = gz.size()
	var lie = gz.duplicate()
	var n = lie.size()
	lie[n - 4] = 100; lie[n - 3] = 0; lie[n - 2] = 0; lie[n - 1] = 0
	corpus.append("VFH1." + Marshalls.raw_to_base64(lie))
	corpus.append("VFH1." + Marshalls.raw_to_base64(gz))
	for code in corpus:
		n_cases += 1
		var desc = "coop.import_code(len=%d, head=%s)" % [str(code).length(), str(code).left(30)]
		cur = desc
		var t0 = Time.get_ticks_usec()
		var r: Variant = coop.import_code(code, _now())
		var ms = float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > 1500.0:
			note("coop", "import_slow:" + str(code).left(8), "import_code lento (%.0f ms) con input di %d caratteri" % [ms, str(code).length()], {"ms": ms})
		if not (r is Dictionary) or not (r as Dictionary).has("ok"):
			note("coop", "import_bad_result", "import_code non ha restituito {ok,...}: %s" % str(r).left(80))
			continue
		if bool(r.ok):
			accepted += 1
			# accettato: è il codice vero (stesso uid: 'self') oppure ha un uid diverso e deve essere sensato
			if str(r.get("error", "")) != "":
				note("coop", "ok_with_error", "ok=true con error=%s" % str(r.error))
	results["coop_corpus"] = n_cases
	results["coop_corpus_accepted"] = accepted

	# --- B) busta valida (checksum giusto) con PAYLOAD ostile
	var mutants: Array = []
	var fields = payload.keys()
	var evil_values: Array = [null, true, false, 0, -1, 1, 2147483648, 9223372036854775807, -9223372036854775808, 1e308, -1e308, 1e-308, 0.5, "", " ", "x",
		"A".repeat(5000), "ǅ💥\u202e", [], {}, [1, 2, 3], {"a": {"b": {"c": []}}}, "NaN", "Infinity", "-0", "1e999"]
	for fld in fields:
		for ev in evil_values:
			var p = payload.duplicate(true)
			p[fld] = ev
			mutants.append(["field " + str(fld), p])
	for fld in ["st", "tot", "elem_add", "elem_more", "res"]:
		if payload.get(fld) is Dictionary:
			for k2 in (payload[fld] as Dictionary).keys():
				for ev in [null, "x", -1e308, 1e308, 9223372036854775807, -9223372036854775808, [], {}, true]:
					var p2 = payload.duplicate(true)
					p2[fld][k2] = ev
					mutants.append(["sub %s.%s" % [fld, k2], p2])
	# campi in più, grandi, profondi
	var p3 = payload.duplicate(true)
	for i in 400:
		p3["extra%d" % i] = "x"
	mutants.append(["many_keys", p3])
	var deep: Variant = []
	for i in 400:
		deep = [deep]
	var p4 = payload.duplicate(true)
	p4["deep"] = deep
	mutants.append(["deep400", p4])
	var p5 = payload.duplicate(true)
	p5["abilities"] = ["x".repeat(20)] if false else _repeat_arr("heavy_strike", 2000)
	mutants.append(["abilities2000", p5])
	for forbidden in ["items", "inventory", "currencies", "gold", "bank", "equipment"]:
		var p6 = payload.duplicate(true)
		p6[forbidden] = {"gold": 999}
		mutants.append(["forbidden " + forbidden, p6])
	var mut_ok = 0
	var seen_uids = {}
	for m in mutants:
		var p: Dictionary = m[1]
		# uid diverso dal nostro, così non viene scartata come 'self'
		if m[0] != "field uid" and not str(m[0]).begins_with("field uid"):
			p["uid"] = "%016x" % rng.randi_range(1, 1 << 40)
		var code = CoopCodec.pack(str(f.kind_hero), int(f.version), p, str(f.prefix), 10000000, 10000000)
		if code.is_empty():
			continue
		cur = "coop.import_code(mutant %s)" % m[0]
		_hb(cur)
		var before = (coop.state.companions as Array).size()
		var t0 = Time.get_ticks_usec()
		var r = coop.import_code(code, _now())
		var ms = float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > 1500.0:
			note("coop", "mutant_slow:" + str(m[0]), "import_code lento (%.0f ms) con %s" % [ms, str(m[0])], {"ms": ms})
		if r is Dictionary and bool(r.ok):
			mut_ok += 1
		# svuota i compagni per non riempire il posto (max 3) e provare tutti i casi
		(coop.state.companions as Array).clear()
		_check_companions_sane(coop, str(m[0]))
	results["coop_mutants"] = mutants.size()
	results["coop_mutants_accepted"] = mut_ok

	# --- C) compagni validi: stato, salvataggio, ricarica, uso in combattimento
	_reload_base()
	coop = Game.system("coop") as CoopSystem
	var accepted_names = []
	for i in 5:
		var p7 = payload.duplicate(true)
		p7["uid"] = "%016x" % (0xabc000 + i)
		p7["name"] = ["Zoé", "A B", "😀", "<script>", "N" + "m".repeat(60)][i]
		p7["issued"] = _now() - i * 100
		var c7 = CoopCodec.pack(str(f.kind_hero), int(f.version), p7, str(f.prefix), 10000000, 10000000)
		var r7 = coop.import_code(c7, _now())
		accepted_names.append("%s:%s" % [str(r7.get("status", "")), str(r7.get("error", ""))])
	results["coop_five_imports"] = accepted_names
	if (coop.state.companions as Array).size() > int(rules.companions.max):
		note("coop", "companions_over_max", "più compagni del massimo: %d" % (coop.state.companions as Array).size())
	# stessa scheda più volte: stato 'same'
	var rr1 = coop.import_code(good, _now())
	if str(rr1.get("error", "")) != "self":
		note("coop", "self_import_not_rejected", "il proprio codice non è rifiutato come 'self': %s" % str(rr1))
	_check_companions_sane(coop, "five")
	for c in coop.companions():
		cur = "coop companion use"
		coop.companion_status(c)
		coop.role_of(c)
	for i in 3:
		advance(30.0)
		sim_t += 30.0
	check_state("coop_companions_tick", true)
	roundtrip("coop_companions")

	# --- D) codici-risultato
	_reload_base()
	coop = Game.system("coop") as CoopSystem
	var wk = coop.week_info(_now())
	results["coop_week"] = str(wk.get("id", ""))
	var rcode = coop.export_result_code(str(wk.get("id", "")))
	results["coop_result_code_len"] = rcode.length()
	var hostile_results: Array = [null, [], {}, "x", 5, {"floor": 1e308}, {"floor": -5, "level": -1}, {"floor": "x"},
		{"floor": 9223372036854775807, "level": 9223372036854775807, "issued": -1, "uid": "zz"},
		{"uid": "abcdef0123456789", "floor": 3, "level": 10, "issued": _now(), "time": -1.0, "score": 1e308, "name": "x"}]
	for hr in hostile_results:
		cur = "coop.sanitize_result(%s)" % str(hr).left(50)
		var sr = coop.sanitize_result(hr, _now())
		if sr is Dictionary and bool(sr.get("ok", false)):
			_scan_result(sr.result)
	for hp in [{"k": "R"}, {"week": "2026-W43"}, {"week": "x", "uid": "abcdef0123456789", "floor": 99999999, "level": 5}, {"week": "../..", "uid": "0"}]:
		var envp = CoopCodec.pack("R", int(f.version), hp, str(f.prefix), 10000000, 10000000)
		cur = "coop.import_code(result %s)" % str(hp).left(50)
		coop.import_code(envp, _now())
	_check_companions_sane(coop, "results")
	roundtrip("coop_results")

	# --- E) classifica con tanti risultati realistici: limiti di dimensione, ordine, settimane vecchie/future
	_reload_base()
	coop = Game.system("coop") as CoopSystem
	var wkid = str(coop.week_info(_now()).get("id", ""))
	var maxn = int(rules.weekly.max_entries_per_week)
	var added_ok = 0
	for i in 300:
		var pr = {"uid": "%016x" % (0x2000 + i), "week": wkid, "floor": rng.randi_range(1, int(rules.weekly.max_floors) + 5), "t": rng.randf_range(0.0, 5000.0),
			"dmg": rng.randf_range(0.0, 1.0e9), "class": "warrior", "level": rng.randi_range(1, 120), "name": "Amico %d" % i, "issued": _now(), "cozy": rng.randf() < 0.3}
		var rc = CoopCodec.pack("R", int(f.version), pr, str(f.prefix), 10000000, 10000000)
		var ri = coop.import_code(rc, _now())
		if bool(ri.ok):
			added_ok += 1
	var bucket: Dictionary = coop.state.results.get(wkid, {})
	results["coop_board"] = [added_ok, bucket.size(), maxn]
	if bucket.size() > maxn + 1:
		note("coop", "board_over_max", "la classifica locale ha %d voci (massimo %d)" % [bucket.size(), maxn])
	var lb = coop.leaderboard(wkid)
	for i in range(1, lb.size()):
		if CoopSystem.better(lb[i], lb[i - 1]):
			note("coop", "leaderboard_unsorted", "classifica non ordinata alla riga %d" % i)
			break
	for wk_try in ["2020-W01", "2999-W01", "2026-W99", "2026-W00", "2026-W4", "x", "", "2026-W43\n"]:
		var pr2 = {"uid": "%016x" % 0x3001, "week": wk_try, "floor": 3, "t": 1.0, "dmg": 1.0, "class": "warrior", "level": 5, "name": "Z", "issued": _now()}
		var ri2 = coop.import_code(CoopCodec.pack("R", int(f.version), pr2, str(f.prefix), 10000000, 10000000), _now())
		if bool(ri2.ok):
			note("coop", "result_bad_week_accepted:" + wk_try, "risultato con settimana '%s' accettato" % wk_try)
	_check_companions_sane(coop, "board")
	roundtrip("coop_board")

	# --- F) schede estreme ACCETTATE (al limite dei tetti) usate nella simulazione: nessun NaN/inf, qualità nel tetto
	_reload_base()
	coop = Game.system("coop") as CoopSystem
	var cb = Game.system("combat") as CombatSystem
	var rd_ids: Array = []
	for r in DataRegistry.table("raids"):
		rd_ids.append(str(r.id))
	var extremes: Array = []
	for mode_x in ["max", "min", "mid"]:
		var px = payload.duplicate(true)
		px["uid"] = "%016x" % (0x4000 + extremes.size())
		for k in px["st"].keys():
			if px["st"][k] is float or px["st"][k] is int:
				px["st"][k] = (1e30 if mode_x == "max" else (-1e30 if mode_x == "min" else px["st"][k] * 0.5))
		for k in px["tot"].keys():
			px["tot"][k] = 1e30 if mode_x == "max" else (-1e30 if mode_x == "min" else 0.0)
		px["res"]["max"] = 1e30 if mode_x == "max" else 0.0
		px["level"] = 10000 if mode_x == "max" else 1
		extremes.append(px)
	var qres = []
	for px in extremes:
		coop.state.companions.clear()
		var ri3 = coop.import_code(CoopCodec.pack("H", int(f.version), px, str(f.prefix), 10000000, 10000000), _now())
		if not bool(ri3.ok):
			qres.append("rifiutata:" + str(ri3.error))
			continue
		var comp = coop.companions()[0]
		for rid in rd_ids.slice(0, 3):
			var rdef: Dictionary = DataRegistry.get_def("raids", rid)
			var mon: Dictionary = DataRegistry.get_def("monsters", str(rdef.get("boss", "")))
			if mon.is_empty():
				continue
			cur = "coop.quality(extreme %s, %s)" % [str(px.uid), rid]
			var ms: Dictionary = cb._scaled(mon, 1)
			var q = coop.quality(comp, mon, ms, 600.0, 0.1)
			qres.append(snappedf(q, 0.001))
			if is_nan(q) or is_inf(q) or q < 0.0 or q > 1.5 + 1e-9:
				note("coop", "quality_out_of_range", "quality = %s per una scheda estrema contro %s" % [str(q), rid])
	results["coop_extreme_quality"] = qres


func _repeat_arr(v: Variant, n: int) -> Array:
	var a = []
	for i in n:
		a.append(v)
	return a


func _scan_result(res: Variant) -> void:
	var tmp = []
	_nonfinite(res, "result", tmp)
	for t in tmp:
		note("coop", "result_nonfinite", t)


func _nonfinite(v: Variant, path: String, out: Array) -> void:
	if v is float and (is_nan(v) or is_inf(v)):
		out.append("%s = %s" % [path, str(v)])
	elif v is Dictionary:
		for k in v:
			_nonfinite(v[k], path + "." + str(k), out)
	elif v is Array:
		for i in v.size():
			_nonfinite(v[i], "%s[%d]" % [path, i], out)


## Dopo ogni importazione: lo stato coop deve restare sano e ogni scheda deve essere un punto fisso di sanitize.
func _check_companions_sane(coop: CoopSystem, tag: String) -> void:
	var rules: Dictionary = coop.rules()
	var cs: Array = coop.state.companions
	if cs.size() > int(rules.companions.max):
		note("coop", "companions_over_max", "compagni oltre il massimo (%d) dopo %s" % [cs.size(), tag])
	for c in cs:
		var tmp = []
		_nonfinite(c, "companion", tmp)
		for t in tmp:
			note("coop", "companion_nonfinite", "%s (dopo %s)" % [t, tag])
		var again = CoopSheet.sanitize(c.sheet, Game.ctx.data, 0)
		if not bool(again.ok):
			note("coop", "stored_sheet_not_valid", "scheda salvata non supera di nuovo sanitize (%s): %s" % [tag, str(again.error)])
		else:
			var d = []
			deep_diff(c.sheet, again.sheet, "", d, [])
			if not d.is_empty():
				note("coop", "sanitize_not_idempotent", "sanitize(sanitize(x)) != sanitize(x) (%s): %s" % [tag, str(d.slice(0, 4))])
			var st: Dictionary = again.sheet.st
			if float(st.hp) < 1.0 or float(st.interval) <= 0.0:
				note("coop", "sheet_degenerate", "hp/intervallo degeneri dopo sanitize (%s)" % tag)
	scan(coop.state, ".coop", "coop_" + tag)


# ===================================================================== MIGRAZIONE
func _sec_migr() -> void:
	# 1) salvataggio v1 sintetico: stato attuale riportato alla forma dello schema 1
	_reload_base()
	var v1: Dictionary = base_snap.duplicate(true)
	v1["schema_version"] = 1
	v1["relics"] = {"owned": ["x"]}
	v1["settings_snapshot"] = {"locale": "it"}
	var c: Dictionary = v1["contracts"]
	c.erase("daily")
	c.erase("weekly")
	for k in c.keys():
		if k != "tokens":
			c.erase(k)
	v1["contracts"] = c
	cur = "migr synthetic v1"
	SaveService.write_atomic(slot, SaveCodec.encode(v1))
	var r = Game.load_game(slot)
	results["migr_synthetic_ok"] = bool(r.ok)
	if not bool(r.ok):
		note("migration", "synthetic_v1_failed", "caricamento v1 sintetico: %s" % str(r.error))
	else:
		var after: Dictionary = Game.snapshot(true)
		if int(after.schema_version) != SaveCodec.SCHEMA_VERSION:
			note("migration", "schema_not_bumped", "schema_version dopo load = %s" % str(after.schema_version))
		if after.has("relics") or after.has("settings_snapshot"):
			note("migration", "dead_sections_kept", "relics/settings_snapshot ancora nello stato")
		var d = []
		var exp: Dictionary = base_snap.duplicate(true)
		exp["contracts"] = after["contracts"]            # le Commesse sono rigenerate (campi nuovi) e non si confrontano
		deep_diff(exp, after, "", d, IGNORE_PATHS + [".contracts"])
		if not d.is_empty():
			note("migration", "v1_loses_progress", "migrazione 1->2 cambia altro oltre le Commesse: %s" % str(d.slice(0, 6)))
		advance(60.0)
		check_state("after_v1_load", true)
		roundtrip("after_v1")

	# 2) il salvataggio dorato vero (versione 0.1, schema 1) del repository
	var gold = FileAccess.get_file_as_bytes("res://tests/golden/save_v0_1_fine_cap1.sav")
	results["golden_bytes"] = gold.size()
	if gold.size() > 0:
		cur = "migr golden"
		SaveService.write_atomic(slot, gold)
		var rg = Game.load_game(slot)
		results["migr_golden_ok"] = bool(rg.ok)
		if not bool(rg.ok):
			note("migration", "golden_failed", "salvataggio dorato 0.1: %s" % str(rg.error))
		else:
			var dg = []
			var sn = Game.snapshot(true)
			advance(300.0)
			offline(3600.0)
			check_state("after_golden", true)
			roundtrip("golden")
			results["golden_total_level"] = GameState.total_level()
			if int(sn.schema_version) != SaveCodec.SCHEMA_VERSION:
				note("migration", "golden_schema", "schema dopo il dorato = %s" % str(sn.schema_version))

	# 3) schema 0, versioni future, tipi sbagliati: devono essere rifiutati con codice, mai crash
	for sv in [0, -1, 3, 99, 2.5, "2", null, true, [], {}, 1e300, NAN]:
		var d2: Dictionary = base_snap.duplicate(true)
		d2["schema_version"] = sv
		cur = "migr schema_version=%s" % str(sv)
		var bytes = SaveCodec.encode(d2)
		var res = SaveCodec.load_bytes(bytes, Game.sim.int_paths())
		if bool(res.ok) and not (sv is int and sv in [1, 2]):
			note("migration", "schema_accepted:" + str(sv), "schema_version=%s accettata" % str(sv))
	d2_remove_version()
	_reload_base()


func d2_remove_version() -> void:
	var d: Dictionary = base_snap.duplicate(true)
	d.erase("schema_version")
	var res = SaveCodec.load_bytes(SaveCodec.encode(d), Game.sim.int_paths())
	if bool(res.ok):
		note("migration", "no_version_accepted", "salvataggio senza schema_version accettato")


# ===================================================================== SEZIONI MANCANTI / NULL / TIPO SBAGLIATO
func _sec_miss() -> void:
	var wrongs: Array = [0, "x", [], 1.5, true]
	var keys: Array = base_snap.keys()
	var total = 0
	var failures = 0
	var variants_names = ["erase", "null", "int", "str", "arr", "float", "bool", "dict"]
	for k in keys:
		if k in ["schema_version"]:
			continue
		var vs: Array = ["erase", null, 0, "x", [], 1.5, true, {}]
		for vi in vs.size():
			if base_snap[k] is Dictionary and vs[vi] is Dictionary:
				continue
			if base_snap[k] is Array and vs[vi] is Array:
				continue
			total += 1
			if not _try_mutation([str(k)], vs[vi], vi == 0):
				failures += 1
	results["miss_top_total"] = total
	results["miss_top_failures"] = failures
	# secondo livello: ogni sottochiave delle sezioni-dizionario
	var total2 = 0
	var fail2 = 0
	for k in keys:
		var sec: Variant = base_snap[k]
		if not (sec is Dictionary):
			continue
		for k2 in (sec as Dictionary).keys():
			var vs2: Array = ["erase", null, "x", 0, []] if not ((sec[k2]) is Array) else ["erase", null, "x", 0]
			for vi in vs2.size():
				total2 += 1
				if not _try_mutation([str(k), str(k2)], vs2[vi], vi == 0):
					fail2 += 1
	results["miss_sub_total"] = total2
	results["miss_sub_failures"] = fail2
	_reload_base()


## Carica lo stato di base con una modifica e lo fa girare un po'. Ritorna false se compaiono errori.
func _try_mutation(path: Array, value: Variant, erase: bool) -> bool:
	var d: Dictionary = base_snap.duplicate(true)
	var holder: Dictionary = d
	for i in path.size() - 1:
		holder = holder[path[i]]
	if erase:
		holder.erase(path[-1])
	else:
		holder[path[-1]] = value
	var tag = "%s %s" % [".".join(path), "ERASE" if erase else ("=" + str(value).left(8) + ":" + type_string(typeof(value)))]
	cur = "miss " + tag
	cur_hostile = not erase
	var before = findings.size()
	var cnt_before = _total_count()
	SaveService.write_atomic(slot, SaveCodec.encode(d))
	var r = Game.load_game(slot)
	if not bool(r.ok):
		return true                      # rifiutato con un codice: comportamento accettabile
	for i in 30:
		Game._on_step(0.1)
	Game._on_long_gap(600.0)
	var tmp = Game.snapshot(true)
	SaveService.save_data(slot, tmp)
	var ok = _total_count() == cnt_before
	if not ok:
		var ctxn = findings.size() - before
		# annota un riepilogo mirato (una riga per mutazione che ha prodotto errori)
		note("tolerance", "%s:%s" % ["erase" if erase else "wrong", ".".join(path)], "caricamento di uno stato con %s ha prodotto errori di script" % tag,
			{"variant": "erase" if erase else "wrong_type"})
	return ok


func _total_count() -> int:
	var n = 0
	mutex.lock()
	for k in findings:
		if str(findings[k].get("kind", "")) in ["script_error", "error"]:
			n += int(findings[k].count)
	mutex.unlock()
	return n


# ===================================================================== SISTEMI NUOVI
func _sec_sys() -> void:
	_sys_hourglass()
	_sys_loadouts()
	_sys_codex()
	_sys_assist()
	_sys_modes()
	_sys_contracts()
	_sys_cozy_coop()


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


## Libera posti nel Deposito (la partita di base è quasi piena di bottino): toglie intere pile finché ce ne sono `n` liberi.
func _make_room(n: int) -> void:
	var bank = _bank()
	for id in bank.state.stacks.keys():
		if bank.free_slots() >= n:
			break
		bank.remove(str(id), int(bank.state.stacks[id]))
	for u in (bank.state.instances as Array).duplicate():
		if bank.free_slots() >= n:
			break
		bank.remove_instance(str(u.uid))


func _sys_hourglass() -> void:
	_reload_base()
	cur = "hourglass"
	var bank = _bank()
	var skills = Game.system("skills") as SkillSystem
	# a) senza Clessidra, senza attività: nessun cambiamento di stato
	var s0: Dictionary = Game.snapshot(true)
	var res0 = Game.use_hourglass()
	var s1: Dictionary = Game.snapshot(true)
	var d = []
	deep_diff(s0, s1, "", d, IGNORE_PATHS)
	if bool(res0.ok) or not d.is_empty():
		note("hourglass", "use_without_item_changes", "Clessidra senza oggetto: ok=%s, diff=%s" % [str(res0.ok), str(d.slice(0, 4))])
	# b) con oggetto e attività: consuma esattamente 1; stato avanza
	_make_room(10)
	bank.add("hourglass_1h", 3, "test")
	var act: String = ""
	for a in DataRegistry.actions_for_skill("woodcutting"):
		act = str(a.id)
		break
	var started = skills.start(act)
	results["hourglass_started"] = started
	var n0 = bank.count("hourglass_1h")
	var xp0 = float(GameState.data.skills.woodcutting.xp) if GameState.data.skills.has("woodcutting") else 0.0
	var res1 = Game.use_hourglass()
	var n1 = bank.count("hourglass_1h")
	var xp1 = float(GameState.data.skills.woodcutting.xp) if GameState.data.skills.has("woodcutting") else 0.0
	if bool(res1.ok):
		if n0 - n1 != 1:
			note("hourglass", "consumes_not_one", "la Clessidra ha consumato %d oggetti (attesi 1)" % (n0 - n1))
		if xp1 <= xp0:
			note("hourglass", "no_progress", "1 h di Clessidra non ha dato XP (da %s a %s)" % [str(xp0), str(xp1)])
	else:
		results["hourglass_reason"] = str(res1.get("reason", ""))
	# c) equivalenza con l'offline vero: stessa attività, stesso stato di partenza
	_reload_base()
	bank = _bank()
	skills = Game.system("skills") as SkillSystem
	_make_room(10)
	bank.add("hourglass_1h", 1, "test")
	skills.start(act)
	var snap_a: Dictionary = Game.snapshot(true)
	SaveService.write_atomic(slot, SaveCodec.encode(snap_a))
	var ra = Game.use_hourglass()
	var after_h: Dictionary = Game.snapshot(true)
	# stesso stato -> offline 1 h dei soli sistemi mansione/coda
	Game.load_game(slot)
	var t_same = Clock.now_unix() == int(snap_a.saved_at_unix)
	var sim: Simulation = Game.sim
	sim.offline_running = true
	for sid in ["skills", "queue"]:
		Game.system(sid).simulate_offline(3600.0)
	sim.offline_running = false
	_bank().remove("hourglass_1h", 1)
	var after_o: Dictionary = Game.snapshot(true)
	var dd = []
	results["hourglass_xp"] = [snap_a.skills.get("woodcutting", {}).get("xp"), after_h.skills.get("woodcutting", {}).get("xp"), after_o.skills.get("woodcutting", {}).get("xp"), bool(ra.ok), t_same]
	deep_diff(after_h, after_o, "", dd, IGNORE_PATHS + [".rng"])
	if t_same and bool(ra.ok) and not dd.is_empty():
		note("hourglass", "not_equal_to_offline", "Clessidra != offline vero di 1 h: %s" % str(dd.slice(0, 6)))
	# d) in Prova / dungeon: rifiutata
	_reload_base()
	bank = _bank()
	_make_room(10)
	bank.add("hourglass_1h", 2, "test")
	for i in 20:
		fuzz_call()
		Game.use_hourglass()
		_check_hourglass_stock()
	check_state("after_hourglass", true)


func _check_hourglass_stock() -> void:
	var n = _bank().count("hourglass_1h")
	if n < 0:
		note("hourglass", "negative_stock", "scorta Clessidre negativa: %d" % n)


func _sys_loadouts() -> void:
	_reload_base()
	cur = "loadouts"
	var lo = Game.system("loadouts") as LoadoutSystem
	var cb = Game.system("combat") as CombatSystem
	var bank = _bank()
	var mk = Game.system("market") as MarketSystem
	# compra 3 posti (Emporio): scrive nello stato come farebbe l'acquisto
	if mk != null:
		var shop_owned = mk.state.get("shop", {})
		results["loadouts_slots_before"] = lo.slot_count()
	_make_room(20)
	# fabbrica due armi/armature indossabili e prova set
	var gear: Array = []
	for it in DataRegistry.items_by_category("equipment"):
		if int(it.get("tier", 9)) <= 1 and str(it.get("slot", "")) != "" and gear.size() < 8:
			gear.append(it)
	var uids = []
	for it in gear:
		var u = bank.add_instance({"def_id": it.id, "source": "test"})
		if u != "":
			uids.append(u)
	# posti: forza l'effetto aggiungendo l'acquisto nello stato del Mercato
	var forced = _force_loadout_slots(3)
	results["loadouts_forced"] = forced
	var before_instances = (bank.state.instances as Array).size()
	for i in 3:
		for u in uids:
			cb.equip(u)
		lo.save_set(i, "Set %d" % i)
		for sl in CombatSystem.EQUIP_SLOTS:
			cb.unequip(sl)
	# applica a ripetizione con pezzi che spariscono
	for round_i in 12:
		var idx = rng.randi_range(-1, 3)
		match rng.randi() % 5:
			0:
				lo.apply_set(idx)
			1:
				if not uids.is_empty():
					bank.remove_instance(uids[rng.randi() % uids.size()])
			2:
				lo.rename_set(idx, "N".repeat(rng.randi_range(0, 60)))
			3:
				lo.clear_set(idx)
			4:
				lo.save_set(idx, "S")
		_check_equipment_unique("loadout round %d" % round_i)
	check_bank()
	var after_instances = (bank.state.instances as Array).size()
	results["loadouts_instances"] = [before_instances, after_instances]
	roundtrip("loadouts")
	# ricarica: i set sopravvivono, nomi ≤ NAME_MAX
	for s in lo.state.sets:
		if s is Dictionary and str(s.get("name", "")).length() > LoadoutSystem.NAME_MAX:
			note("loadouts", "name_too_long", "nome set oltre %d caratteri" % LoadoutSystem.NAME_MAX)
	# stato manomesso: stesso uid in due slot, uid inesistenti, gear non-dizionario
	var snap: Dictionary = Game.snapshot(true)
	var evil_sets: Array = [
		[{"name": "x", "gear": {"weapon": "u1", "offhand": "u1"}, "ammo": ""}],
		[{"name": 5, "gear": [], "ammo": 7}],
		[null, 3, "x", {}],
		[{"name": "A".repeat(500), "gear": {"nope": "u9999999"}, "ammo": "ghost"}],
	]
	for es in evil_sets:
		var d = snap.duplicate(true)
		d["loadouts"] = {"sets": es}
		SaveService.write_atomic(slot, SaveCodec.encode(d))
		var r = Game.load_game(slot)
		if bool(r.ok):
			var lo2 = Game.system("loadouts") as LoadoutSystem
			for i in 3:
				lo2.apply_set(i)
				lo2.missing_slots(i)
				lo2.can_apply(i)
			_check_equipment_unique("evil set")
			check_state("evil_loadout", true)


func _force_loadout_slots(n: int) -> bool:
	# il Mercato calcola i posti dagli acquisti dello Shop: si guarda come sono memorizzati
	var mk = Game.system("market") as MarketSystem
	for e in DataRegistry.table("shop"):
		if str(e.id) == "loadout_slot":
			var st: Dictionary = mk.state
			for key in ["shop", "shop_owned", "owned_shop", "purchases"]:
				if st.has(key) and st[key] is Dictionary:
					st[key]["loadout_slot"] = n
					return mk.shop_effect_total("loadouts") >= float(n)
	return false


func _check_equipment_unique(tag: String) -> void:
	var eqs: Dictionary = GameState.data.get("equipment", {})
	var seen = {}
	for slot_name in eqs:
		var v: Variant = eqs[slot_name]
		if v is String and not v.is_empty():
			if seen.has(v):
				note("loadouts", "equip_dup", "la stessa istanza %s indossata in %s e %s (%s)" % [v, seen[v], slot_name, tag])
			seen[v] = slot_name
			if _bank().get_instance(v).is_empty():
				note("loadouts", "equip_dangling", "slot %s punta a un'istanza inesistente %s (%s)" % [slot_name, v, tag])


func _sys_codex() -> void:
	_reload_base()
	cur = "codex"
	var cx = Game.system("codex") as CodexSystem
	# pct con totali strani
	for have in [-1, 0, 1, 5, 9223372036854775807]:
		for total in [-1, 0, 1, 5, 9223372036854775807]:
			cur = "codex.pct(%s,%s)" % [str(have), str(total)]
			var p = cx.pct(have, total)
			var pt = cx.pct_text(have, total)
			if p is float and (is_nan(p) or is_inf(p)):
				note("codex", "pct_nonfinite:%s,%s" % [str(have), str(total)], "pct(%s,%s) = %s" % [str(have), str(total), str(p)])
	# monotonia: i conteggi non scendono mai nel tempo
	var c0 = cx.completion()
	var l0 = cx.lifetime()
	advance(600.0)
	sim_t += 600
	var c1 = cx.completion()
	var l1 = cx.lifetime()
	var da = []
	_monotone(l0, l1, "lifetime", da)
	for t in da:
		note("codex", "lifetime_decreases", t)
	if c1 is float and c0 is float and c1 < c0 - 1e-9:
		note("codex", "completion_decreases", "completamento sceso da %s a %s" % [str(c0), str(c1)])
	if c1 is float and (c1 > 1.0 + 1e-9 or c1 < 0.0):
		results["codex_completion_range"] = c1
	# vendere/scartare un oggetto non deve far "dimenticare" un oggetto visto
	var seen_before = {}
	for id in cx.collectible_ids():
		seen_before[id] = cx.item_seen(id)
	var bank = _bank()
	for u in (bank.state.instances as Array).duplicate():
		bank.remove_instance(str(u.uid))
	for id in bank.state.stacks.keys():
		bank.remove(str(id), int(bank.state.stacks[id]))
	var forgot = []
	for id in seen_before:
		if bool(seen_before[id]) and not bool(cx.item_seen(id)):
			forgot.append(id)
	if not forgot.is_empty():
		note("codex", "forgets_items", "dopo aver svuotato il Deposito il Codex dimentica %d oggetti: %s" % [forgot.size(), str(forgot.slice(0, 4))])
	# selezione cosmetici con id sbagliati
	for kind in ["title", "frame", "x", ""]:
		cx.select(kind, "nope")
		cx.select(kind, "")
		cx.owned_cosmetics(kind)
	check_state("after_codex", true)
	roundtrip("codex")


func _monotone(a: Variant, b: Variant, path: String, out: Array) -> void:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if b.has(k):
				_monotone(a[k], b[k], path + "." + str(k), out)
	elif (a is int or a is float) and (b is int or b is float):
		if float(b) < float(a) - 1e-9:
			out.append("%s scende da %s a %s" % [path, str(a), str(b)])


func _sys_assist() -> void:
	_reload_base()
	cur = "assist"
	var asx = Game.system("assist") as AssistSystem
	var bank = _bank()
	# sblocca la funzione (nodo + token), poi regole "peggiori": tutto, vuote, oltre il massimo
	Modifiers.set_source("test:autosell", [{"key": "auto_sell_unlock", "value": 1.0}])
	var unlocked = asx.auto_sell_unlocked()
	results["assist_unlocked"] = unlocked
	# stato: regole inserite a mano come in un salvataggio (la UI non lascia farlo, un salvataggio manomesso sì)
	var rules_list: Array = []
	for cat in SellRules.CATEGORIES:
		rules_list.append({"cat": cat, "max_tier": 0, "max_quality": "", "max_rarity": "", "on": true})
	asx.state["rules"] = rules_list.slice(0, 6)
	# prepara cose che NON devono essere vendute: indossate, bloccate, in uso
	var eq_uid = ""
	for it in DataRegistry.items_by_category("equipment"):
		if int(it.get("tier", 9)) <= 1 and str(it.get("slot", "")) == "weapon":
			eq_uid = bank.add_instance({"def_id": it.id, "source": "test"})
			break
	var cb = Game.system("combat") as CombatSystem
	if eq_uid != "":
		cb.equip(eq_uid)
	var locked_uid = ""
	for it in DataRegistry.items_by_category("equipment"):
		if int(it.get("tier", 9)) <= 2 and str(it.get("slot", "")) != "":
			locked_uid = bank.add_instance({"def_id": it.id, "source": "test", "locked": true})
			if locked_uid != "":
				break
	var guard = {}
	for u in [eq_uid, locked_uid]:
		if u != "":
			guard[u] = true
	# se la funzione non è sbloccata, la prova diretta di SellRules.collect/execute basta
	for r in asx.state.rules:
		var plan = SellRules.collect(bank, Game.system("market") as MarketSystem, r)
		for u in plan.uids:
			if guard.has(u):
				note("assist", "sells_protected:" + str(r.cat), "SellRules.collect include un'istanza protetta (indossata/bloccata) %s con la regola %s" % [u, str(r.cat)])
	var g = asx.run_auto_sell()
	for u in guard:
		if bank.get_instance(u).is_empty():
			note("assist", "autosell_removed_protected", "la vendita automatica ha venduto un oggetto protetto %s" % u)
	# tutte le regole manomesse nel salvataggio
	var snap: Dictionary = Game.snapshot(true)
	var evil: Array = [[{"cat": "equipment", "max_tier": -5, "max_quality": "zzz", "max_rarity": "mythic"}], [null, 5, "x"], [{"cat": 7}], [{}, {}, {}, {}, {}, {}, {}, {}, {}], "x", 4]
	for er in evil:
		var d = snap.duplicate(true)
		d["assist"] = {"rules": er, "auto_on": true, "wb_slot": "x"}
		SaveService.write_atomic(slot, SaveCodec.encode(d))
		var rr = Game.load_game(slot)
		if bool(rr.ok):
			var a2 = Game.system("assist") as AssistSystem
			if (a2.state.rules as Array).size() > AssistSystem.MAX_RULES:
				note("assist", "rules_over_max", "regole oltre il massimo dopo il load")
			a2.run_auto_sell()
			advance(20.0)
			check_state("evil_assist", true)
	# la regola 'ammo' non deve vendere le munizioni indossate (equipment.ammo)
	_reload_base()
	roundtrip("assist")


func _sys_modes() -> void:
	_reload_base()
	cur = "modes"
	var ms = Game.system("modes") as ModeSystem
	# set_cozy ripetuto: il Modificatore non si accumula
	var m0 = Modifiers.total_add("skill_xp_pct", ["all"])
	for i in 5:
		ms.set_cozy(true)
		ms.apply_cozy()
	var m1 = Modifiers.total_add("skill_xp_pct", ["all"])
	ms.set_cozy(false)
	ms.apply_cozy()
	var m2 = Modifiers.total_add("skill_xp_pct", ["all"])
	results["cozy_xp_pct"] = [m0, m1, m2]
	if absf(m2 - m0) > 1e-9:
		note("modes", "cozy_leaks", "dopo aver spento la Cozy il modificatore xp_pct non torna come prima (%s -> %s -> %s)" % [str(m0), str(m1), str(m2)])
	if m1 < m0:
		note("modes", "cozy_negative", "la Cozy riduce xp_pct")
	# Cozy salvata e ricaricata
	ms.set_cozy(true)
	var s = Game.snapshot(true)
	SaveService.save_data(slot, s)
	Game.load_game(slot)
	var m3 = Modifiers.total_add("skill_xp_pct", ["all"])
	if absf(m3 - m1) > 1e-9:
		note("modes", "cozy_reload", "xp_pct dopo il ricaricamento %s != %s" % [str(m3), str(m1)])
	if not (Game.system("modes") as ModeSystem).is_cozy_run():
		note("modes", "cozy_used_lost", "cozy_used perso dopo il ricaricamento")
	# lingua e Cozy non interferiscono
	Settings.set_value("locale", "en")
	check_locale()
	Settings.set_value("locale", "it")
	check_locale()
	# Estrema: morte -> perdita di livello e di equipaggiamento; stato coerente
	for mode in ["extreme", "autarchic"]:
		Game.new_game(slot, mode, seed_v + 5)
		bot = BotPlayer.new(Game.sim, Callable(Game, "_on_step"))
		bot.long_mode = true
		bot.step_long = Callable(Game, "_on_long_gap")
		_run_bot(2.0 * 3600.0)
		var bank = _bank()
		var inst_before = (bank.state.instances as Array).size()
		var lvl_before = int(GameState.data.skills.get("hero", {}).get("level", 0))
		for i in 3:
			Game.sim.ctx.events.player_died.emit("chaos_test")
			check_state("after_death_%s" % mode, true)
		var mstate: Dictionary = GameState.data.modes
		results["mode_%s" % mode] = {"deaths": mstate.deaths_lost, "levels_lost": mstate.levels_lost, "items_lost": mstate.items_lost,
			"level": [lvl_before, int(GameState.data.skills.get("hero", {}).get("level", 0))],
			"instances": [inst_before, (bank.state.instances as Array).size()]}
		if int(GameState.data.skills.get("hero", {}).get("level", 0)) < 1:
			note("modes", "level_below_1:" + mode, "livello Eroe < 1 dopo la morte in %s" % mode)
		if mode == "autarchic" and (bank.state.instances as Array).size() < inst_before:
			note("modes", "autarchic_loses_items", "Autarchica: istanze scese da %d a %d con player_died" % [inst_before, (bank.state.instances as Array).size()])
		roundtrip("mode_" + mode)
	_reload_base()


func _sys_contracts() -> void:
	_reload_base()
	cur = "contracts"
	var ct = Game.system("contracts") as ContractSystem
	_unlock(["feature:contracts", "feature:market"])
	var tok0 = ct.tokens()
	results["contracts_open"] = ct.is_open()
	var list: Array = []
	for per in ["daily", "weekly", "x", ""]:
		list.append_array(ct.contracts(per))
	results["contracts_n"] = list.size()
	# riscatto doppio, reroll a oltranza, acquisto con gettoni insufficienti/negativi
	for c in list:
		var cid = str(c.get("id", ""))
		var t_before = ct.tokens()
		var g_before = GameState.gold()
		var r1 = ct.claim(cid)
		var r2 = ct.claim(cid)
		if bool(r1) and bool(r2):
			note("contracts", "double_claim", "claim ripetuto riesce due volte per %s" % cid)
		if ct.tokens() < 0:
			note("contracts", "negative_tokens", "gettoni negativi dopo claim")
	for i in 30:
		var cs = ct.contracts("daily")
		if not cs.is_empty():
			ct.reroll(str(cs[rng.randi() % cs.size()].get("id", "")))
	# riscatto con il Deposito PIENO: la ricompensa in oggetti (Cassa settimanale / chiave) non deve sparire in silenzio
	_reload_base()
	ct = Game.system("contracts") as ContractSystem
	var bank = _bank()
	var filler = 0
	var fid = str(DataRegistry.items_by_category("equipment")[0].id)
	while bank.free_slots() > 0 and filler < 2000:
		bank.add_instance({"def_id": fid, "source": "test"})
		filler += 1
	results["contracts_full_bank_free"] = bank.free_slots()
	for per in ["weekly", "daily"]:
		for c in ct.contracts(per).duplicate():
			c["progress"] = int(c.target)               # completata
			var n_before = (ct.contracts(per) as Array).size()
			var crates_before = _count_crates()
			var ok = ct.claim(str(c.id))
			var gone = (ct.contracts(per) as Array).size() < n_before
			var crates_after = _count_crates()
			if ok and gone and per == "weekly" and crates_after <= crates_before:
				note("contracts", "claim_full_bank_loses_crate", "riscatto settimanale con Deposito pieno: la commessa e' consumata ma la Cassa non e' arrivata (crates %d -> %d)" % [crates_before, crates_after])
	var toks = ct.tokens()
	if toks < 0:
		note("contracts", "negative_tokens", "gettoni negativi dopo reroll: %d" % toks)
	for shop_item in DataRegistry.table("contract_templates").slice(0, 3):
		pass
	# cambio del giorno: stato dei contratti con date strane
	var snap: Dictionary = Game.snapshot(true)
	var evil: Array = [{"daily": [{"id": "x"}], "weekly": "x", "tokens": -50}, {"daily": [null, 3, "x"], "weekly": [], "tokens": 1e30},
		{"daily": [], "weekly": [], "tokens": "x", "day": -1, "week": 1e300}, {"tokens": 9223372036854775807}]
	for ev in evil:
		var d = snap.duplicate(true)
		d["contracts"] = ev
		SaveService.write_atomic(slot, SaveCodec.encode(d))
		var rr = Game.load_game(slot)
		if bool(rr.ok):
			var c2 = Game.system("contracts") as ContractSystem
			advance(30.0)
			offline(86400.0 * 2)
			c2.contracts("daily")
			if c2.tokens() < 0:
				note("contracts", "negative_tokens_from_save", "gettoni negativi dopo il caricamento di uno stato con %s" % str(ev).left(60))
			check_state("evil_contracts", true)
	_reload_base()
	roundtrip("contracts")


func _count_crates() -> int:
	var n = 0
	var bank = _bank()
	for id in bank.state.stacks:
		if str(id).begins_with("crate_"):
			n += int(bank.state.stacks[id])
	return n


func _sys_cozy_coop() -> void:
	# la marcatura Cozy deve arrivare nelle schede e nei codici-risultato del coop (ModeSystem.run_tags)
	_reload_base()
	cur = "cozy_coop"
	var ms = Game.system("modes") as ModeSystem
	var coop = Game.system("coop") as CoopSystem
	ms.set_cozy(true)
	var f: Dictionary = coop.rules().format
	var code: String = coop.export_hero_code(_now())
	var up = CoopCodec.unpack(code, int(f.version), "", str(f.prefix), int(coop.rules().code.max_chars), int(coop.rules().code.max_json_bytes))
	if bool(up.ok) and not bool(up.payload.get("cozy", false)):
		note("coop", "cozy_not_marked", "la Scheda del Compagno esportata in Cozy NON porta la marcatura cozy (CoopSystem.is_cozy non legge ModeSystem)")
	var wk = coop.week_info(_now())
	var rc = coop.my_result(str(wk.get("id", "")))
	results["cozy_coop"] = {"sheet_cozy": bool(up.payload.get("cozy", false)) if bool(up.ok) else null, "run_tags": ms.run_tags()}


func _xp() -> float:
	return float(GameState.data.skills.woodcutting.xp)


## Confronto del guadagno di 1 h: Clessidra / skills.simulate_offline / Game._on_long_gap / 36000 tick.
func _sec_hg() -> void:
	var act = ""
	for a in DataRegistry.actions_for_skill("woodcutting"):
		act = str(a.id)
		break
	var out = {}
	for variant in ["hourglass", "skills_offline", "long_gap", "ticks", "skills_queue_offline"]:
		_reload_base()
		_make_room(10)
		_bank().add("hourglass_1h", 1, "test")
		(Game.system("skills") as SkillSystem).start(act)
		var x0 = _xp()
		cur = "hg " + variant
		match variant:
			"hourglass": Game.use_hourglass()
			"skills_offline": Game.system("skills").simulate_offline(3600.0)
			"skills_queue_offline":
				Game.system("skills").simulate_offline(3600.0)
				Game.system("queue").simulate_offline(3600.0)
			"long_gap": Game._on_long_gap(3600.0)
			"ticks":
				for i in 36000:
					Game._on_step(0.1)
		out[variant] = snappedf(_xp() - x0, 0.1)
	results["hg_xp_gain_1h"] = out
