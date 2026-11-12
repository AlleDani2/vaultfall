extends GutTest
## Salvataggi (docs/17 §10, CLAUDE.md regola 7), integrazione finale (resoconto 47):
## 1) salvataggio "dorato" della versione 0.1 (tests/golden/, generato dal bot di quella versione a fine Cap. I):
##    si carica in questa versione (SaveCodec.SCHEMA_VERSION + migrazioni) e la partita prosegue;
## 2) salvataggio di fine partita grande (20.000 istanze + gli stati di tutti i sistemi) scritto sul THREAD,
##    round-trip senza perdite (codec) e di nuovo attraverso i sistemi (from_state/to_state).

const GOLDEN := "res://tests/golden/save_v0_1_fine_cap1.sav"
const BIG_INSTANCES := 20000

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_save_endgame_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


## Scrive i byte del salvataggio dorato nello slot (come se il giocatore avesse copiato il file della 0.1).
func _install_golden(slot: int) -> void:
	var bytes := FileAccess.get_file_as_bytes(GOLDEN)
	assert_gt(bytes.size(), 0, "il salvataggio dorato esiste")
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	assert_eq(SaveService.write_atomic(slot, bytes), OK)


func test_salvataggio_dorato_v0_1_si_carica_e_si_continua_a_giocare() -> void:
	var dec := SaveCodec.decode(FileAccess.get_file_as_bytes(GOLDEN))
	assert_true(dec.ok, "si decodifica")
	assert_lte(int(dec.data.schema_version), SaveCodec.SCHEMA_VERSION, "versione di schema della 0.1")
	var res := SaveCodec.load_bytes(FileAccess.get_file_as_bytes(GOLDEN), Game.sim.int_paths())
	assert_true(res.ok, "migrazione e normalizzazione senza errori: %s %s" % [res.get("error", ""), res.get("paths", [])])
	_install_golden(1)
	var lr := Game.load_game(1)
	assert_true(lr.ok, "Game.load_game del salvataggio 0.1")
	var qs := Game.system("quests") as QuestSystem
	assert_true(qs.is_done("main_c1_q6"), "il Capitolo I resta completato")
	assert_eq(qs.current_main(), "main_c2_q1", "la storia riprende dal Capitolo II")
	assert_gt(int(GameState.data.skills.hero.level), 10, "livelli conservati")
	assert_eq(int(GameState.data.schema_version), SaveCodec.SCHEMA_VERSION)
	# i sistemi arrivati dopo la 0.1 hanno il loro stato di partenza e girano
	for sid in ["prestige", "compendium", "secrets", "estate", "mercenaries", "expeditions", "farming"]:
		if Game.system(sid) != null and not Game.system(sid).state_key.is_empty():
			assert_true(GameState.data.has(Game.system(sid).state_key), "sezione di %s creata" % sid)
	# si continua a giocare: il bot finisce la prima missione del Cap. II
	var bot := BotPlayer.new(Game.sim, func(dt: float) -> void: Game._on_step(dt))
	var r := bot.run_until_quest("main_c2_q1", 3600.0)
	assert_eq(r.blocks, [], "nessun blocco dopo il caricamento")
	assert_true(bool(r.ok), "main_c2_q1 completata partendo dal salvataggio 0.1")
	# e il nuovo salvataggio si riapre
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)


func test_salvataggio_grande_su_thread_e_round_trip_senza_perdite() -> void:
	_install_golden(2)
	assert_true(Game.load_game(2).ok)
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = BIG_INSTANCES + 500
	bank.add_currency("stardust", 12345)
	bank.add_currency("vault_shard", 999999)
	var skins: Array = []
	for cid in ["crate_millbrook", "crate_saltreach", "crate_rift"]:
		skins.append_array(DataRegistry.item(cid).crate.skins)
	var cr := Game.system("crates") as CrateSystem
	var failed := 0
	for i in BIG_INSTANCES:
		var def_id := str(skins[i % skins.size()])
		var d := DataRegistry.item(def_id)
		var f := lerpf(float(d.skin.float_min), float(d.skin.float_max), float(i % 997) / 997.0)
		var uid := bank.add_instance({"def_id": def_id, "kind": "skin", "rarity": d.rarity, "crate": "crate_" + str(d.crate),
			"condition": cr.condition_for_float(f), "float": f, "annalist": i % 50 == 0, "seed": i % 1000, "phase": "", "polish": 0, "locked": i % 7 == 0})
		if uid.is_empty():
			failed += 1
	assert_eq(failed, 0, "tutte le istanze nel Deposito")
	assert_gte(bank.state.instances.size(), BIG_INSTANCES)
	# stati di fine partita di altri sistemi
	var ps := Game.system("prestige") as PrestigeSystem
	ps.state.era_max = 7
	ps.state.era_kills = {"1": 3, "2": 1, "6": 2}
	ps.state.trials = {"trial_silence": 5, "trial_race": 2}
	ps.state.stardust = 4321
	(Game.system("compendium") as CompendiumSystem).state.counters["tradeup"] = 77
	GameState.data.stats["gold_earned"] = 9007199254740000
	# salvataggio su thread: sul principale solo lo snapshot
	var f0 := PerfGate.load_factor()
	var t0 := PerfGate.clock_usec()
	SaveService.request_save()
	var main_ms := float(PerfGate.clock_usec() - t0) / 1000.0
	assert_true(SaveService.is_saving() or FileAccess.file_exists(SaveService.slot_path(2)), "scrittura avviata su un thread")
	t0 = PerfGate.clock_usec()
	var expect := Game.snapshot()          # stesso contenuto di quello passato al thread (tempo di gioco fermo)
	var inc_ms := float(PerfGate.clock_usec() - t0) / 1000.0
	SaveService._finish_thread()
	for k in 2:          # migliore di 3 per l'incrementale (nulla è cambiato: ogni chiamata riusa i pezzi)
		t0 = PerfGate.clock_usec()
		Game.snapshot()
		inc_ms = minf(inc_ms, float(PerfGate.clock_usec() - t0) / 1000.0)
	# snapshot incrementale (E47-6, resoconto 50): costo, e dopo una modifica resta uguale alla copia completa
	t0 = PerfGate.clock_usec()
	var full_snap := Game.snapshot(true)
	var full_ms := float(PerfGate.clock_usec() - t0) / 1000.0
	for k in 2:          # migliore di 3 anche per la copia completa
		t0 = PerfGate.clock_usec()
		Game.snapshot(true)
		full_ms = minf(full_ms, float(PerfGate.clock_usec() - t0) / 1000.0)
	gut.p("Snapshot: incrementale %.1f ms, completo %.1f ms" % [inc_ms, full_ms])
	assert_lt(inc_ms, full_ms, "l'incrementale costa meno del completo")
	bank.state.instances[777]["locked"] = not bool(bank.state.instances[777].locked)
	bank.state.instances.remove_at(20)
	var inc2 := Game.snapshot()
	var diffs0: Array = []
	_diff(Game.snapshot(true), inc2, "", diffs0, ["saved_at_unix"])
	assert_eq(diffs0.slice(0, 5), [], "incrementale dopo modifiche = completo")
	assert_eq(full_snap.bank.instances.size(), expect.bank.instances.size())
	bank.state.instances.insert(20, full_snap.bank.instances[20].duplicate(true))
	bank.state.instances[777]["locked"] = not bool(bank.state.instances[777].locked)
	gut.p("Salvataggio grande: %d istanze, principale %.1f ms (snapshot), file %.0f KB" % [bank.state.instances.size(), main_ms,
		FileAccess.get_file_as_bytes(SaveService.slot_path(2)).size() / 1024.0])
	PerfGate.assert_time(self, "thread principale: solo lo snapshot", main_ms, 250.0, PerfGate.factor_around(f0))
	# 1) codec: quello che si rilegge è quello che si è scritto
	var lr := SaveService.load_slot(2, Game.sim.int_paths())
	assert_true(lr.ok, "rilettura: %s" % lr.get("error", ""))
	var diffs: Array = []
	_diff(expect, lr.data, "", diffs, ["saved_at_unix"])
	assert_eq(diffs.slice(0, 10), [], "round-trip del file senza perdite")
	# 2) sistemi: caricando nella partita e risalvando non si perde nulla (niente offline: data nel futuro)
	var future := expect.duplicate(true)
	future["saved_at_unix"] = Clock.now_unix() + 3600
	assert_eq(SaveService.save_data(3, future), OK)
	Game.stop_game(false)
	assert_true(Game.load_game(3).ok)
	var again := Game.snapshot()
	diffs.clear()
	_diff(expect, again, "", diffs, ["saved_at_unix", "rng"])
	assert_eq(diffs.slice(0, 10), [], "from_state/to_state di tutti i sistemi senza perdite")
	assert_eq((Game.system("bank") as BankSystem).state.instances.size(), bank.state.instances.size())


## Confronto profondo con i numeri confrontati per valore (JSON rilegge gli interi non dichiarati come float).
func _diff(a: Variant, b: Variant, path: String, out: Array, skip: Array) -> void:
	if out.size() > 20:
		return
	if (a is int or a is float) and (b is int or b is float):
		if absf(float(a) - float(b)) > 1e-9 * maxf(1.0, absf(float(a))):
			out.append("%s: %s != %s" % [path, str(a), str(b)])
		return
	if a is Dictionary and b is Dictionary:
		for k in a:
			if skip.has(str(k)) and path.is_empty():
				continue
			if not (b as Dictionary).has(k):
				out.append("%s.%s mancante" % [path, str(k)])
				continue
			_diff(a[k], b[k], "%s.%s" % [path, str(k)], out, skip)
		for k in b:
			if not (a as Dictionary).has(k) and not (skip.has(str(k)) and path.is_empty()):
				out.append("%s.%s in più" % [path, str(k)])
		return
	if a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s: lunghezza %d != %d" % [path, a.size(), b.size()])
			return
		for i in a.size():
			_diff(a[i], b[i], "%s[%d]" % [path, i], out, skip)
		return
	if typeof(a) != typeof(b) or a != b:
		out.append("%s: %s != %s" % [path, str(a), str(b)])
