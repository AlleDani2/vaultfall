extends Node
## BOT CAOTICO (QA 83). Una partita VERA (autoload Game) con azioni a caso: invoca ogni metodo pubblico dei sistemi con
## argomenti sani o ostili, salva/ricarica, cambia impostazioni/lingua/Cozy, avanza il tempo (tick e offline) e dopo ogni
## passo controlla le invarianti. Alterna al "bot giocatore" (BotPlayer) così lo stato arriva in profondità.
## Uso (da tools/chaos_run.py, che isola user:// con XDG_DATA_HOME):
##   godot --headless --path game -s scripts/chaos_bot.gd -- --seed=7 --hours=20 --out=/percorso/seed7.json [--mode=normal]
##         [--skip=sys.metodo,...] [--bot=0.5] (quota di tempo simulato lasciata al bot giocatore)
## Esce con risultato JSON: {seed, hours, findings:[{kind, sig, msg, ctx, hostile, count}], stats}.
## NB: il solo scopo è trovare errori. Nessun numero di bilanciamento qui.

const LIFECYCLE := ["setup", "tick", "from_state", "to_state", "default_state", "simulate_offline", "has_tick", "int_paths"]
const QUERY_PREFIX := ["get_", "is_", "can_", "has_", "count", "list_", "preview", "all_", "total", "describe", "status", "label"]
const JUNK_STRINGS := ["", " ", "x", "UI_" + "NOPE", "../../etc/passwd", "%s %d {x}", "[b]x[/b]", "💥", "ǅ", "null", "NaN", "-1", "1e999",
	"__proto__", "gold", "*", "..", "a.b.c", "\\"]
const BIG_INTS := [-1, -100, 0, 1, 2, 3, 7, 100, 1000, 2147483647, 4294967296, 9007199254740992, 4611686018427387904, 9223372036854775807, -9223372036854775808]
const BAD_FLOATS := [0.0, -0.0, 1.0, -1.0, 0.5, 1e300, -1e300, 1e-300, INF, -INF, NAN, 3.4e38]
# percorsi che dipendono dall'orologio reale (ancora del calendario stagionale, ora del salvataggio): non sono perdite
const IGNORE_PATHS := [".saved_at_unix", ".seasonal.anchor_unix", ".seasonal.anchor_game_s", ".seasonal.tz_min"]

# ---------------------------------------------------------------- stato del bot
var rng = RandomNumberGenerator.new()
var seed_v: int = 0
var hours: float = 20.0
var out_path: String = ""
var mode_arg: String = ""
var skip: Dictionary = {}
var bot_share: float = 0.5
var hb_path: String = ""
var findings: Dictionary = {}               # firma -> {kind, msg, ctx, hostile, count, ...}
var stats: Dictionary = {"calls": 0, "hostile_calls": 0, "saves": 0, "loads": 0, "forks": 0, "ticks": 0.0, "offline_s": 0.0,
	"roundtrips": 0, "settings": 0, "bursts": 0, "new_games": 0, "slow_calls": 0, "coverage": {}}
var ring: Array = []
var cur: String = "":
	set(v):
		cur = v
		_hb(v)
var cur_hostile: bool = false
var sim_t: float = 0.0                      # secondi simulati totali (tick + offline + bot)
var extra_t: float = 0.0
var methods: Array = []                     # [{sys, name, args, ndef, weight}]
var static_methods: Array = []              # [{script, cname, name, args, ndef}]
var total_weight: float = 0.0
var pools: Dictionary = {}                  # nome tabella -> Array[String]
var all_ids: Array = []
var id_set: Dictionary = {}
var logger: ErrLog
var mutex = Mutex.new()
var slot: int = 1
var bot: BotPlayer
var op_n: int = 0
var in_bot: bool = false
var script_paths: Array = []
var tmp_dir: String = ""
var _taint: bool = false            # l'ultimo argomento generato non è nel dominio atteso (id di un'altra tabella, spazzatura)


class ErrLog extends Logger:
	var owner_bot: Object
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
		if owner_bot != null:
			owner_bot.on_engine_error(function, file, line, code, rationale, error_type)


func _ready() -> void:
	await get_tree().process_frame
	_parse_args()
	await _run()
	get_tree().quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_v = int(a.substr(7))
		elif a.begins_with("--hours="): hours = float(a.substr(8))
		elif a.begins_with("--out="): out_path = a.substr(6)
		elif a.begins_with("--mode="): mode_arg = a.substr(7)
		elif a.begins_with("--bot="): bot_share = float(a.substr(6))
		elif a == "--ui": use_ui = true
		elif a.begins_with("--skip="):
			for s in a.substr(7).split(","):
				if not s.is_empty(): skip[s] = true
	if out_path.is_empty():
		out_path = "/tmp/chaos_seed%d.json" % seed_v
	hb_path = out_path + ".hb"
	rng.seed = seed_v * 7919 + 13


# ---------------------------------------------------------------- errori del motore
func on_engine_error(function: String, file: String, line: int, code: String, rationale: String, error_type: int) -> void:
	mutex.lock()
	var kind = "script_error" if error_type == Logger.ERROR_TYPE_SCRIPT else ("warning" if error_type == Logger.ERROR_TYPE_WARNING else "error")
	var msg = (rationale if not rationale.is_empty() else code).strip_edges()
	var sig = "%s|%s:%d|%s" % [kind, file.get_file(), line, msg.left(90)]
	if findings.has(sig):
		findings[sig].count += 1
	else:
		findings[sig] = {"kind": kind, "msg": msg.left(300), "where": "%s:%d (%s)" % [file, line, function], "ctx": _ctx(), "hostile": cur_hostile,
			"count": 1, "in_bot": in_bot}
	mutex.unlock()


func _ctx() -> Dictionary:
	return {"seed": seed_v, "op": op_n, "t_h": snappedf(sim_t / 3600.0, 0.01), "cur": cur, "last": ring.slice(maxi(0, ring.size() - 6))}


func note(kind: String, sig: String, msg: String, extra: Dictionary = {}) -> void:
	mutex.lock()
	var key = "%s|%s" % [kind, sig]
	if findings.has(key):
		findings[key].count += 1
	else:
		var f = {"kind": kind, "msg": msg.left(600), "ctx": _ctx(), "hostile": cur_hostile, "count": 1, "in_bot": in_bot}
		f.merge(extra)
		findings[key] = f
	mutex.unlock()


func _hb(s: String) -> void:
	var f = FileAccess.open(hb_path, FileAccess.WRITE)
	if f != null:
		f.store_string(s)
		f.close()


func _push_ring(s: String) -> void:
	ring.append(s)
	if ring.size() > 40:
		ring.pop_front()


# ---------------------------------------------------------------- avvio
func _setup() -> void:
	tmp_dir = "user://chaos_%d" % seed_v
	SaveService.save_dir = tmp_dir
	SaveService.autosave_enabled = false
	Settings.path = "user://chaos_settings_%d.cfg" % seed_v
	Settings.load_settings()
	Clock.set_paused(true)                # il tempo lo muove il bot, non il tempo reale
	logger = ErrLog.new()
	logger.owner_bot = self
	OS.add_logger(logger)
	_build_pools()
	_build_methods()


func _run() -> void:
	_setup()
	var mode = mode_arg
	if mode.is_empty():
		var r = rng.randf()
		mode = "normal" if r < 0.7 else ("autarchic" if r < 0.85 else "extreme")
	cur = "new_game"
	Game.new_game(slot, mode, seed_v)
	if rng.randf() < 0.3:
		Settings.set_value("cozy_mode", true)
		(Game.system("modes") as ModeSystem).set_cozy(true)
	bot = BotPlayer.new(Game.sim, Callable(Game, "_on_step"))
	bot.long_mode = true
	bot.step_long = Callable(Game, "_on_long_gap")
	var total = hours * 3600.0
	var t_wall0 = Time.get_ticks_msec()
	while sim_t < total:
		op_n += 1
		_wait_frames(1)
		# 1) un tratto di gioco "sensato" (porta lo stato in profondità)
		var chunk = rng.randf_range(600.0, 3600.0) * (bot_share * 2.0)
		if GameState.active and chunk > 60.0:
			var _b0 = Time.get_ticks_usec()
			_run_bot(chunk)
			var pr: Dictionary = stats.get("prof_ms", {})
			pr["bot"] = float(pr.get("bot", 0.0)) + float(Time.get_ticks_usec() - _b0) / 1000.0
			stats["prof_ms"] = pr
		# 2) una raffica di caos
		if GameState.active:
			await _burst()
		else:
			_recover()
		_timeline()
		if (Time.get_ticks_msec() - t_wall0) > 3000000:       # tetto di sicurezza: 50 minuti reali per seme
			note("limit", "wall", "tetto di tempo reale raggiunto a %.2f h simulate" % (sim_t / 3600.0))
			break
	stats["wall_s"] = float(Time.get_ticks_msec() - t_wall0) / 1000.0
	stats["sim_h"] = sim_t / 3600.0
	stats["modes"] = mode
	stats["bot_blocks"] = bot.blocks.size()
	stats["coverage_n"] = (stats.coverage as Dictionary).size()
	stats["methods_total"] = methods.size()
	_final_checks()
	_write_out()
	OS.remove_logger(logger)


func _timeline() -> void:
	if not GameState.active:
		return
	var d: Dictionary = GameState.data
	var tl: Array = stats.get("timeline", [])
	var done = d.get("quests", {}).get("done", [])
	tl.append([snappedf(sim_t / 3600.0, 0.1), GameState.total_level(), (d.get("unlocks", []) as Array).size(), (done as Array).size(),
		(d.get("bank", {}).get("instances", []) as Array).size(), GameState.gold(), int(d.get("prestige", {}).get("era_max", 1))])
	stats["timeline"] = tl
	stats["max_total_level"] = maxi(int(stats.get("max_total_level", 0)), GameState.total_level())


func _wait_frames(n: int) -> void:
	# lascia girare _process di SaveService (thread di salvataggio) senza muovere il tempo di gioco (Clock in pausa)
	for i in n:
		SaveService._process(0.0)


func _write_out() -> void:
	var arr: Array = []
	for k in findings:
		var f: Dictionary = findings[k]
		f["sig"] = k
		arr.append(f)
	var f = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": seed_v, "hours": hours, "findings": arr, "stats": stats}, "  ", false, true))
	f.close()
	DirAccess.remove_absolute(hb_path)


func _final_checks() -> void:
	if GameState.active:
		check_state("final", true)
		roundtrip("final")


# ---------------------------------------------------------------- bot giocatore
func _run_bot(chunk: float) -> void:
	in_bot = true
	cur = "bot_player"
	var t0 = bot.t
	var tgt = bot.t + chunk
	var tries = 0
	while bot.t < tgt and tries < 6 and GameState.active:
		bot._idle_s = 0.0
		bot._last_progress_t = bot.t
		bot.run_until_quest("__chaos__", tgt)
		tries += 1
		if bot.t < tgt and (bot.blocks.size() > 0):
			bot.blocks.clear()
			var rest = minf(120.0, tgt - bot.t)
			advance(rest)
			bot.t += rest
	var dt = bot.t - t0
	sim_t += dt
	in_bot = false
	check_state("after_bot")


# ---------------------------------------------------------------- tempo
func advance(seconds: float) -> void:
	var n = int(seconds / 0.1)
	cur = "ticks(%d)" % n
	for i in n:
		Game._on_step(0.1)
	stats["ticks"] += seconds


func offline(seconds: float) -> void:
	cur = "offline(%.0f)" % seconds
	_hb(cur)
	Game._on_long_gap(seconds)
	stats["offline_s"] += seconds


# ---------------------------------------------------------------- raffica di caos
func _burst() -> void:
	stats["bursts"] += 1
	var n = rng.randi_range(80, 400)
	for i in n:
		if not GameState.active:
			_recover()
			if not GameState.active:
				return
		var r = rng.randf()
		var p0 = Time.get_ticks_usec()
		var bucket = "fuzz"
		if r < 0.80:
			fuzz_call()
		elif r < 0.83:
			bucket = "tick"
			var s: float = [10.0, 30.0, 60.0][rng.randi() % 3]
			advance(s)
			sim_t += s; extra_t += s
			check_state("after_ticks")
		elif r < 0.845:
			bucket = "offline"
			var s = rng.randf_range(60.0, 1800.0) if rng.randf() < 0.8 else rng.randf_range(1800.0, 8.0 * 3600.0)
			offline(s)
			sim_t += s; extra_t += s
			check_state("after_offline")
		elif r < 0.89:
			bucket = "roundtrip"
			roundtrip("random")
		elif r < 0.90:
			bucket = "fork"
			fork_check()
		elif r < 0.94:
			bucket = "settings"
			chaos_settings()
		elif r < 0.96:
			bucket = "static"
			chaos_static()
		elif r < 0.98:
			bucket = "reload"
			chaos_reload_variants()
		elif r < 0.99:
			bucket = "game_level"
			chaos_game_level()
		elif r < 0.997 and use_ui:
			bucket = "ui"
			await ui_op()
		else:
			fuzz_call()
		_prof(bucket, p0)
	if is_instance_valid(main_ui):
		main_ui.queue_free()
		main_ui = null
	check_state("burst_end", true)


var use_ui: bool = false
var main_ui: Control = null


## Interfaccia vera accanto al caos: schermata principale, schermate a caso, risoluzioni, lingua. Gli errori di script
## dell'interfaccia finiscono nei finding con `cur` = "ui: ...".
func ui_op() -> void:
	cur_hostile = false
	if not GameState.active:
		return
	if not is_instance_valid(main_ui):
		cur = "ui: istanzia MainScreen"
		main_ui = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(main_ui)
		await get_tree().process_frame
		if not is_instance_valid(main_ui):
			return
	var r = rng.randi() % 6
	match r:
		0, 1, 2:
			var ids: Array = []
			for sc in ScreenRegistry.SCREENS:
				if str(sc.scene) != "":
					ids.append(str(sc.id))
			for sk in DataRegistry.skill_ids():
				ids.append("skill:" + str(sk))
			var id: String = ids[rng.randi() % ids.size()]
			cur = "ui: show_screen(%s)" % id
			_push_ring(cur)
			main_ui.call("show_screen", id)
		3:
			var sizes = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1024, 600), Vector2i(1280, 800),
				Vector2i(800, 480), Vector2i(640, 360)]
			var sz: Vector2i = sizes[rng.randi() % sizes.size()]
			cur = "ui: risoluzione %s" % str(sz)
			_push_ring(cur)
			get_tree().root.size = sz
			Settings.set_value("ui_scale", [0.75, 1.0, 1.25, 1.5][rng.randi() % 4])
		4:
			var lc = ["it", "en"][rng.randi() % 2]
			cur = "ui: lingua %s" % lc
			_push_ring(cur)
			Settings.set_value("locale", lc)
		_:
			cur = "ui: _on_ui_tick"
			main_ui.call("_on_ui_tick")
	for i in 2:
		await get_tree().process_frame
	if is_instance_valid(main_ui):
		cur = "ui: _on_ui_tick (dopo)"
		main_ui.call("_on_ui_tick")


func _prof(bucket: String, t0: int) -> void:
	var pr: Dictionary = stats.get("prof_ms", {})
	pr[bucket] = float(pr.get(bucket, 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0
	stats["prof_ms"] = pr


func _recover() -> void:
	# nessuna partita attiva (es. dopo stop_game): si ricarica o si ricomincia
	cur = "recover"
	if SaveService.slot_exists(slot):
		var res = Game.load_game(slot)
		if bool(res.ok):
			return
	Game.new_game(slot, "normal", seed_v + op_n)
	stats["new_games"] += 1


# ---------------------------------------------------------------- metodi e argomenti
func _build_pools() -> void:
	var seen = {}
	for tn in DataRegistry.table_names():
		var ids: Array = []
		for r in DataRegistry.table(tn):
			if r is Dictionary and r.has("id") and r.id is String:
				ids.append(r.id)
				seen[r.id] = true
		if not ids.is_empty():
			pools[tn] = ids
	var items: Array = DataRegistry.all_items().keys()
	pools["items"] = items
	pools["actions"] = DataRegistry.all_actions().keys()
	for i in items: seen[i] = true
	for a in pools["actions"]: seen[a] = true
	all_ids = seen.keys()
	id_set = seen


func _is_query(n: String) -> bool:
	for p in QUERY_PREFIX:
		if n.begins_with(p):
			return true
	return false


func _build_methods() -> void:
	for gs in Game.sim.systems:
		var seen_names = {}
		for m in gs.get_script().get_script_method_list():
			var nm = str(m.name)
			if nm.begins_with("_") or LIFECYCLE.has(nm) or seen_names.has(nm):
				continue
			seen_names[nm] = true
			var skip_it = false
			for a in m.args:
				if a.type == TYPE_OBJECT and str(a.class_name) != "":
					skip_it = true
			if skip_it or skip.has("%s.%s" % [gs.id, nm]):
				continue
			var w = 0.35 if _is_query(nm) else 1.0
			methods.append({"sys": gs.id, "name": nm, "args": m.args, "ndef": (m.default_args as Array).size(), "w": w})
			total_weight += w
	# classi statiche (nucleo, coop, formattazione)
	for p in ["res://src/core/NumberFormat.gd", "res://src/core/SaveCodec.gd", "res://src/core/Formulas.gd", "res://src/coop/CoopCodec.gd",
			"res://src/coop/CoopSheet.gd", "res://src/coop/CoopWeekly.gd", "res://src/core/ModeRules.gd", "res://src/systems/SellRules.gd"]:
		var sc: GDScript = load(p)
		for m in sc.get_script_method_list():
			var nm = str(m.name)
			if nm.begins_with("_") or nm == "configure" or not (int(m.flags) & METHOD_FLAG_STATIC):
				continue
			var skip_it = false
			for a in m.args:
				if a.type == TYPE_OBJECT:
					skip_it = true
			if skip_it or skip.has("%s.%s" % [p.get_file().get_basename(), nm]):
				continue
			static_methods.append({"script": sc, "cname": p.get_file().get_basename(), "name": nm, "args": m.args, "ndef": (m.default_args as Array).size()})


func _pool_for(argname: String) -> Array:
	var n = argname.to_lower()
	if n.ends_with("_id"): n = n.trim_suffix("_id")
	if n in ["id", "def", "def_id", "item", "uid", "iid", "key"]:
		return []
	for tn in pools:
		var stem: String = str(tn).trim_suffix("s")
		if stem.length() >= 3 and (n.find(stem) >= 0 or (n.length() >= 3 and stem.find(n) >= 0)):
			return pools[tn]
	return []


func _live_uid() -> String:
	var bank = Game.system("bank") as BankSystem
	if bank == null or bank.state == null:
		return ""
	var inst: Array = bank.state.get("instances", [])
	if inst.is_empty():
		return ""
	return str(inst[rng.randi() % inst.size()].get("uid", ""))


func gen_string(argname: String, hostile: bool) -> String:
	var r = rng.randf()
	if hostile and r < 0.35:
		_taint = true
		if rng.randf() < 0.1:
			return "A".repeat(rng.randi_range(5000, 200000))
		return JUNK_STRINGS[rng.randi() % JUNK_STRINGS.size()]
	var n = argname.to_lower()
	if n.find("uid") >= 0 or n == "iid" or n == "inst":
		var u = _live_uid()
		if not u.is_empty() and rng.randf() < 0.85:
			return u
		_taint = true
	if n in ["mode", "kind"] and rng.randf() < 0.5:
		return ["normal", "autarchic", "extreme", "gold", "skill", "combat", "main", "side"][rng.randi() % 8]
	var pool = _pool_for(argname)
	if not pool.is_empty() and rng.randf() < 0.85:
		return pool[rng.randi() % pool.size()]
	_taint = true
	if rng.randf() < 0.85 and not all_ids.is_empty():
		return all_ids[rng.randi() % all_ids.size()]
	return JUNK_STRINGS[rng.randi() % JUNK_STRINGS.size()]


func gen_int(argname: String, hostile: bool) -> int:
	if hostile and rng.randf() < 0.5:
		return BIG_INTS[rng.randi() % BIG_INTS.size()]
	var n = argname.to_lower()
	if n.find("slot") >= 0:
		return rng.randi_range(1, 3)
	if n.find("index") >= 0 or n == "idx" or n == "i":
		return rng.randi_range(0, 6) if rng.randf() < 0.9 else -1
	if n.find("now") >= 0 or n.find("unix") >= 0:
		return Clock.now_unix() + rng.randi_range(-86400, 86400 * 3)
	if n.find("qty") >= 0 or n.find("count") >= 0 or n.find("amount") >= 0 or n == "n":
		return rng.randi_range(1, 30)
	if n.find("level") >= 0 or n.find("floor") >= 0 or n.find("tier") >= 0 or n.find("era") >= 0:
		return rng.randi_range(0, 12)
	return rng.randi_range(0, 10)


func gen_float(argname: String, hostile: bool) -> float:
	if hostile and rng.randf() < 0.6:
		return BAD_FLOATS[rng.randi() % BAD_FLOATS.size()]
	var n = argname.to_lower()
	if n.find("dt") >= 0 or n.find("second") >= 0 or n.find("window") >= 0:
		return rng.randf_range(0.0, 600.0)
	return rng.randf_range(0.0, 100.0)


func gen_dict(argname: String, hostile: bool, depth: int = 0) -> Dictionary:
	var d = {}
	var n = rng.randi_range(0, 4)
	for i in n:
		var k: String = ["id", "qty", "name", "kind", "type", "uid", "item", "amount", "level", "slot", "raid", "monster", "zone"][rng.randi() % 13]
		d[k] = gen_variant(k, hostile, depth + 1)
	return d


func gen_variant(argname: String, hostile: bool, depth: int = 0) -> Variant:
	var r = rng.randi() % 8
	match r:
		0: return gen_string(argname, hostile)
		1: return gen_int(argname, hostile)
		2: return gen_float(argname, hostile)
		3: return rng.randf() < 0.5
		4: return gen_dict(argname, hostile, depth + 1) if depth < 3 else {}
		5:
			var a = []
			if depth < 3:
				for i in rng.randi_range(0, 4):
					a.append(gen_variant(argname, hostile, depth + 1))
			return a
		6: return null
		_: return gen_string(argname, hostile)


func gen_arg(a: Dictionary, hostile: bool) -> Variant:
	var nm = str(a.name)
	match int(a.type):
		TYPE_STRING: return gen_string(nm, hostile)
		TYPE_STRING_NAME: return StringName(gen_string(nm, hostile))
		TYPE_INT: return gen_int(nm, hostile)
		TYPE_FLOAT: return gen_float(nm, hostile)
		TYPE_BOOL: return rng.randf() < 0.5
		TYPE_DICTIONARY: return gen_dict(nm, hostile)
		TYPE_ARRAY:
			var arr = []
			var pool = _pool_for(nm)
			for i in rng.randi_range(0, 5):
				if rng.randf() < 0.7:
					arr.append(gen_string(nm, hostile))
				else:
					arr.append(gen_variant(nm, hostile))
			return arr
		TYPE_PACKED_STRING_ARRAY: return PackedStringArray([gen_string(nm, hostile)])
		TYPE_PACKED_BYTE_ARRAY: return PackedByteArray([rng.randi() % 256, rng.randi() % 256])
		TYPE_VECTOR2: return Vector2(gen_float(nm, hostile), gen_float(nm, hostile))
		TYPE_VECTOR2I: return Vector2i(rng.randi_range(-3, 30), rng.randi_range(-3, 30))
		TYPE_OBJECT: return null
		_: return gen_variant(nm, hostile)


func _args_for(m: Dictionary, hostile: bool) -> Array:
	var args: Array = m.args
	var nreq: int = args.size() - int(m.ndef)
	var n = nreq + (rng.randi_range(0, int(m.ndef)) if int(m.ndef) > 0 else 0)
	var out = []
	for i in n:
		out.append(gen_arg(args[i], hostile))
	return out


func fuzz_call() -> void:
	if methods.is_empty():
		return
	var r = rng.randf() * total_weight
	var m: Dictionary = methods[0]
	for mm in methods:
		r -= float(mm.w)
		if r <= 0.0:
			m = mm
			break
	var hostile = rng.randf() < 0.3
	_taint = false
	var args = _args_for(m, hostile)
	hostile = hostile or _taint
	for a in m.args:
		if int(a.type) in [0, TYPE_DICTIONARY, TYPE_ARRAY]:
			hostile = true            # non sappiamo generare una struttura "sana": l'esito conta come robustezza
	var gs: GameSystem = Game.system(m.sys)
	var desc = "%s.%s(%s)" % [m.sys, m.name, str(args).left(160)]
	cur = desc
	cur_hostile = hostile
	_push_ring(desc + (" [H]" if hostile else ""))
	_hb(desc)
	stats["calls"] += 1
	if hostile: stats["hostile_calls"] += 1
	var key = "%s.%s" % [m.sys, m.name]
	stats.coverage[key] = int(stats.coverage.get(key, 0)) + 1
	var t0 = Time.get_ticks_usec()
	gs.callv(m.name, args)
	var ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if ms > 1500.0:
		stats["slow_calls"] += 1
		note("slow_call", key, "%s ha impiegato %.0f ms" % [desc, ms], {"ms": ms})
	# controlli leggeri sulle sezioni toccate
	if not _is_query(m.name):
		check_section(m.sys, desc)
	if op_n % 7 == 0 or ms > 200.0:
		check_state("after_call")


func chaos_static() -> void:
	if static_methods.is_empty():
		return
	var m: Dictionary = static_methods[rng.randi() % static_methods.size()]
	var hostile = rng.randf() < 0.6
	var args = _args_for(m, hostile)
	var desc = "%s.%s(%s)" % [m.cname, m.name, str(args).left(160)]
	cur = desc
	cur_hostile = hostile
	_push_ring(desc + " [S]")
	_hb(desc)
	stats["calls"] += 1
	(m.script as GDScript).callv(m.name, args)


func chaos_settings() -> void:
	stats["settings"] += 1
	var keys: Array = Settings.DEFAULTS.keys() + ["nope", ""]
	var k: String = keys[rng.randi() % keys.size()]
	var v: Variant = gen_variant(k, true)
	var r = rng.randf()
	if k == "locale" and r < 0.7:
		v = ["it", "en"][rng.randi() % 2]
	elif k == "cozy_mode" and r < 0.7:
		v = rng.randf() < 0.5
	elif k == "ui_scale" and r < 0.6:
		v = rng.randf_range(0.5, 2.0)
	elif Settings.DEFAULTS.has(k) and Settings.DEFAULTS[k] is float and r < 0.5:
		v = BAD_FLOATS[rng.randi() % BAD_FLOATS.size()]
	elif k == "number_format" and r < 0.7:
		v = ["short", "full", "scientific", "weird"][rng.randi() % 4]
	cur = "Settings.set_value(%s, %s)" % [k, str(v).left(40)]
	cur_hostile = true
	_push_ring(cur)
	_hb(cur)
	var ok: bool = Settings.set_value(k, v)
	# la finestra: risoluzioni a caso (contenuto, non ci sono nodi UI nel bot ma il root deve reggere)
	if rng.randf() < 0.3:
		var sizes = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(800, 600), Vector2i(1280, 800),
			Vector2i(320, 240), Vector2i(7680, 4320), Vector2i(1, 1)]
		var sz: Vector2i = sizes[rng.randi() % sizes.size()]
		cur = "get_tree().root.size=%s" % str(sz)
		get_tree().root.size = sz
	# i valori letti dopo l'impostazione devono essere sani
	var val: Variant = Settings.get_value(k)
	if val is float and (is_nan(val) or is_inf(val)):
		note("invariant", "settings_nonfinite:" + k, "Settings.%s = %s dopo set_value(%s)" % [k, str(val), str(v)], {"hostile": true})
	if k.begins_with("volume") and val is float and (val < 0.0 or val > 1.0 or is_nan(val)):
		note("invariant", "settings_range:" + k, "Settings.%s fuori range: %s" % [k, str(val)])
	if ok and k == "locale":
		check_locale()
	if rng.randf() < 0.3:
		# Cozy a caldo
		var ms = Game.system("modes") as ModeSystem
		if ms != null and GameState.active:
			ms.set_cozy(rng.randf() < 0.5)
			check_state("after_cozy")


var ui_keys: Array = []

func check_locale() -> void:
	var loc = TranslationServer.get_locale().substr(0, 2)
	cur = "check_locale(%s)" % loc
	if ui_keys.is_empty():
		var f = FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
		f.get_csv_line()
		while not f.eof_reached():
			var row = f.get_csv_line()
			if row.size() >= 3 and not row[0].is_empty():
				ui_keys.append(row[0])
	for i in 25:
		var key: String = ui_keys[rng.randi() % ui_keys.size()]
		var s = tr(key)
		if s == key or s.is_empty():
			note("invariant", "tr_missing:" + loc + ":" + key, "tr(%s) non tradotta in %s" % [key, loc])
	var ids: Array = pools.get("items", [])
	for i in 30:
		if ids.is_empty():
			break
		var it = DataRegistry.item(ids[rng.randi() % ids.size()])
		var nm = Loc.t(it.get("name", {}))
		if nm.is_empty():
			note("invariant", "name_empty:" + loc, "nome oggetto vuoto in %s: %s" % [loc, str(it.get("id", "?"))])
	if Loc.locale() != loc:
		note("invariant", "locale_mismatch", "Loc.locale()=%s ma TranslationServer=%s" % [Loc.locale(), loc])


func chaos_game_level() -> void:
	# funzioni di Game / SaveService con input strani
	var r = rng.randi() % 8
	cur_hostile = true
	match r:
		0:
			cur = "Game.use_hourglass"
			Game.use_hourglass()
		1:
			cur = "SaveService.import_string(junk)"
			var junk = ["", "AAAA", "not base64!!", "H4sI" + "A".repeat(rng.randi_range(0, 4000)), Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4]))]
			var res: Dictionary = SaveService.import_string(junk[rng.randi() % junk.size()], 0)
			if bool(res.get("ok", false)):
				note("invariant", "import_junk_ok", "import_string ha accettato spazzatura: %s" % str(junk))
		2:
			cur = "SaveService.import_string(modified_state)"
			_import_mangled()
		3:
			cur = "Game.offline_gap"
			Game.offline_gap(rng.randi_range(-100, 100) * 1000000, rng.randi_range(-100, 100) * 1000000)
		4:
			cur = "SaveService.slot_info"
			SaveService.slot_info(rng.randi_range(-1, 5))
		5:
			cur = "Game.snapshot(false)x3"
			for i in 3:
				Game.snapshot(false)
		6:
			cur = "Loc/NumberFormat"
			NumberFormat.fmt(BAD_FLOATS[rng.randi() % BAD_FLOATS.size()])
			NumberFormat.fmt_time(BAD_FLOATS[rng.randi() % BAD_FLOATS.size()])
		_:
			cur = "Game.offline_cap_s"
			Game.offline_cap_s()
	_push_ring(cur)


func _import_mangled() -> void:
	# import di uno stato valido ma con una sezione rimossa/alterata: deve rifiutare o completare, mai crashare
	var snap: Dictionary = Game.snapshot(true)
	var keys = snap.keys()
	var k: String = keys[rng.randi() % keys.size()]
	var v: Variant = rng.randi() % 3
	match int(v):
		0: snap.erase(k)
		1: snap[k] = null
		2: snap[k] = gen_variant(k, true)
	if snap.has("schema_version") and rng.randf() < 0.2:
		snap["schema_version"] = [0, 1, 2, 3, 99, "2", 2.5][rng.randi() % 7]
	cur = "import mangled(%s,%d)" % [k, int(v)]
	var txt = SaveCodec.to_base64(snap)
	# SaveService.import_string valida e (slot 0) non scrive nulla
	var res: Dictionary = SaveService.import_string(txt, 0)
	if bool(res.ok):
		# anche se "ok", un caricamento reale deve reggere: si carica in uno slot di prova e poi si torna indietro
		var good = Game.snapshot(true)
		var tmp_slot = 3
		SaveService.save_data(tmp_slot, res.data)
		var lr = Game.load_game(tmp_slot)
		if bool(lr.ok):
			check_state("after_mangled_load", true)
			# torna alla partita buona
			SaveService.save_data(slot, good)
			Game.load_game(slot)
		else:
			SaveService.save_data(slot, good)
			Game.load_game(slot)


# ---------------------------------------------------------------- salvataggio / ricarica
func roundtrip(tag: String) -> void:
	stats["roundtrips"] += 1
	cur = "roundtrip(%s)" % tag
	cur_hostile = false
	_hb(cur)
	var snap: Dictionary = Game.snapshot(true)
	var err = SaveService.save_data(slot, snap)
	stats["saves"] += 1
	if err != OK:
		note("save", "save_failed", "save_data errore %s" % error_string(err))
		return
	var res = SaveService.load_slot(slot, Game.sim.int_paths())
	if not bool(res.ok):
		note("save", "load_failed:" + str(res.error), "load_slot dopo save: %s" % str(res.error))
		return
	if str(res.source) != "main":
		note("save", "load_not_main", "caricato da %s" % str(res.source))
	var diffs: Array = []
	deep_diff(snap, res.data, "", diffs, IGNORE_PATHS)
	if not diffs.is_empty():
		note("roundtrip", "file_vs_snapshot:" + _shape(str(diffs[0]).split(" ")[0]), "file != snapshot: %s" % str(diffs.slice(0, 6)))
	# Base64
	if rng.randf() < 0.3:
		var b64 = SaveCodec.to_base64(snap)
		var dec = SaveCodec.from_base64(b64)
		if not bool(dec.ok):
			note("save", "b64_fail", "to_base64/from_base64 fallito: %s" % str(dec.error))
		else:
			var d2: Array = []
			deep_diff(snap, dec.data, "", d2, IGNORE_PATHS)
			if not d2.is_empty():
				note("roundtrip", "b64_vs_snapshot:" + _shape(str(d2[0]).split(" ")[0]), "base64 != snapshot: %s" % str(d2.slice(0, 6)))
	# incrementale vs completo
	var inc: Dictionary = Game.snapshot(false)
	var full: Dictionary = Game.snapshot(true)
	var d3: Array = []
	deep_diff(inc, full, "", d3, IGNORE_PATHS, true)
	if not d3.is_empty():
		note("roundtrip", "inc_vs_full:" + _shape(str(d3[0]).split(" ")[0]), "snapshot incrementale != completo: %s" % str(d3.slice(0, 6)))
	# ricarica nel gioco e riconfronto
	if rng.randf() < 0.6:
		stats["loads"] += 1
		var before_s = Clock.now_unix()
		var lr = Game.load_game(slot)
		if not bool(lr.ok):
			note("save", "game_load_failed", "Game.load_game dopo save: %s" % str(lr.error))
			return
		var after_s = Clock.now_unix()
		if before_s == int(snap.saved_at_unix) and after_s == before_s:
			var snap2: Dictionary = Game.snapshot(true)
			var d4: Array = []
			deep_diff(snap, snap2, "", d4, IGNORE_PATHS, true)
			if not d4.is_empty():
				note("roundtrip", "reload_vs_snapshot:" + _shape(str(d4[0]).split(" ")[0]), "stato dopo load != stato salvato: %s" % str(d4.slice(0, 8)))
		check_state("after_reload", true)


func chaos_reload_variants() -> void:
	# salva e ricarica in modi diversi: backup, slot diversi, stop/load, new_game
	var r = rng.randi() % 4
	if rng.randf() < 0.06:
		r = 4
	cur_hostile = false
	match r:
		0:
			cur = "stop_game(save)+load"
			Game.stop_game(true)
			var lr = Game.load_game(slot)
			if not bool(lr.ok):
				note("save", "stop_load_failed", "load dopo stop_game(save): %s" % str(lr.error))
				Game.new_game(slot, "normal", seed_v)
		1:
			cur = "request_save thread"
			SaveService.request_save()
			# la partita continua a cambiare mentre il thread scrive
			for i in 5:
				fuzz_call()
			SaveService._finish_thread()
			var lr2 = SaveService.load_slot(slot, Game.sim.int_paths())
			if not bool(lr2.ok):
				note("save", "thread_save_unreadable", "salvataggio su thread illeggibile: %s" % str(lr2.error))
		2:
			cur = "save in slot 2, load slot 2"
			var snap: Dictionary = Game.snapshot(true)
			SaveService.save_data(2, snap)
			var lr3 = SaveService.load_slot(2, Game.sim.int_paths())
			if not bool(lr3.ok):
				note("save", "slot2_failed", "slot 2: %s" % str(lr3.error))
			SaveService.delete_slot(2)
		3:
			cur = "corrupt main -> backup"
			SaveService.save_now()
			SaveService.save_now()          # il secondo crea .bak1
			var p = SaveService.slot_path(slot)
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_buffer(PackedByteArray([0x1f, 0x8b, 1, 2, 3, 4]))
				f.close()
			var lr4 = SaveService.load_slot(slot, Game.sim.int_paths())
			if not bool(lr4.ok):
				note("save", "backup_not_used", "main corrotto e nessun backup valido: %s" % str(lr4.error))
			elif str(lr4.source) == "main":
				note("save", "corrupt_main_accepted", "un main corrotto è stato accettato")
			SaveService.save_now()
		_:
			cur = "new_game other mode"
			var mode: String = GameState.ENABLED_MODES[rng.randi() % 3]
			Game.new_game(slot, mode, rng.randi())
			stats["new_games"] += 1
	_push_ring(cur)
	if GameState.active:
		check_state("after_reload_variant", true)


func fork_check() -> void:
	# due continuazioni dalla stessa istantanea: viva e ricaricata devono restare IDENTICHE (stato nascosto non salvato)
	stats["forks"] += 1
	cur = "fork_check"
	cur_hostile = false
	_hb(cur)
	var snap0: Dictionary = Game.snapshot(true)
	if SaveService.save_data(slot, snap0) != OK:
		return
	var n: int = [100, 300][rng.randi() % 2]
	for i in n:
		Game._on_step(0.1)
	var a: Dictionary = Game.snapshot(true)
	var t_load = Clock.now_unix()
	var lr = Game.load_game(slot)
	if not bool(lr.ok):
		note("save", "fork_load_failed", str(lr.error))
		return
	if t_load != int(snap0.saved_at_unix) or Clock.now_unix() != t_load:
		# è scattato un secondo: l'offline di 1 s sporca il confronto
		check_state("after_fork_skip")
		return
	for i in n:
		Game._on_step(0.1)
	var b: Dictionary = Game.snapshot(true)
	var diffs: Array = []
	deep_diff(a, b, "", diffs, IGNORE_PATHS, true)
	sim_t += float(n) * 0.1 * 2.0
	extra_t += float(n) * 0.1 * 2.0
	if not diffs.is_empty():
		note("fork", "fork_diverges:" + _shape(str(diffs[0]).split(" ")[0]), "viva != ricaricata dopo %d tick: %s" % [n, str(diffs.slice(0, 8))],
			{"first_ring": ring.slice(maxi(0, ring.size() - 4))})
	check_state("after_fork")


# ---------------------------------------------------------------- confronto profondo
func _num_eq(a: Variant, b: Variant) -> bool:
	if a is int and b is int:
		return a == b
	var fa = float(a)
	var fb = float(b)
	if is_nan(fa) and is_nan(fb):
		return true
	return fa == fb or absf(fa - fb) <= 1e-9 * maxf(absf(fa), absf(fb))


func deep_diff(a: Variant, b: Variant, path: String, out: Array, ignore: Array, strict_int: bool = false) -> void:
	if out.size() >= 12:
		return
	if a is Dictionary and b is Dictionary:
		var ka = {}
		for k in a:
			ka[str(k)] = k
		var kb = {}
		for k in b:
			kb[str(k)] = k
		for ks in ka:
			if ignore.has(path + "." + ks):
				continue
			if not (ka[ks] is String or ka[ks] is StringName):
				if out.size() < 12:
					out.append("%s.%s chiave non-stringa (%s) nello stato" % [path, ks, type_string(typeof(ka[ks]))])
			if not kb.has(ks):
				out.append("%s.%s manca dopo" % [path, ks])
				continue
			deep_diff(a[ka[ks]], b[kb[ks]], path + "." + ks, out, ignore, strict_int)
		for ks in kb:
			if not ka.has(ks) and not ignore.has(path + "." + ks):
				out.append("%s.%s compare dopo" % [path, ks])
		return
	if a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s: lunghezza %d -> %d" % [path, a.size(), b.size()])
			return
		for i in a.size():
			deep_diff(a[i], b[i], "%s[%d]" % [path, i], out, ignore, strict_int)
		return
	var an = a is int or a is float
	var bn = b is int or b is float
	if an and bn:
		if not _num_eq(a, b):
			out.append("%s: %s -> %s" % [path, str(a), str(b)])
		elif strict_int and (a is int) != (b is int):
			out.append("%s: tipo %s -> %s (%s)" % [path, type_string(typeof(a)), type_string(typeof(b)), str(a)])
		return
	if (a is String or a is StringName) and (b is String or b is StringName):
		if str(a) != str(b):
			out.append("%s: '%s' -> '%s'" % [path, str(a).left(40), str(b).left(40)])
		return
	if typeof(a) != typeof(b):
		out.append("%s: tipo %s -> %s (%s)" % [path, type_string(typeof(a)), type_string(typeof(b)), str(a).left(40)])
		return
	if a != b:
		out.append("%s: %s -> %s" % [path, str(a).left(40), str(b).left(40)])


func _shape(path: String) -> String:
	# forma del percorso: indici -> [], id noti -> *
	var parts = path.split(".")
	var out = PackedStringArray()
	for p in parts:
		var q = p
		var br = q.find("[")
		var suffix = ""
		if br >= 0:
			suffix = "[]"
			q = q.substr(0, br)
		if id_set.has(q) or q.is_valid_int() or q.length() > 28:
			q = "*"
		out.append(q + suffix)
	return ".".join(out)


# ---------------------------------------------------------------- invarianti
func check_section(sys_id: String, desc: String) -> void:
	var gs: GameSystem = Game.system(sys_id)
	if gs == null or gs.state_key.is_empty():
		return
	var sec: Variant = GameState.data.get(gs.state_key)
	if sec == null:
		note("invariant", "section_null:" + gs.state_key, "sezione %s null dopo %s" % [gs.state_key, desc])
		return
	scan(sec, gs.state_key, desc)
	if sys_id != "bank":
		scan(GameState.data.get("bank", {}), "bank", desc)
	scan(GameState.data.get("currencies", {}), "currencies", desc)


func check_state(tag: String, deep: bool = false) -> void:
	if not GameState.active:
		return
	scan(GameState.data, "", tag)
	if deep:
		check_bank()


var _scan_n = 0

func scan(node: Variant, path: String, tag: String) -> void:
	if node is Dictionary:
		for k in node:
			var kk: Variant = k
			if not (kk is String or kk is StringName):
				note("invariant", "nonstring_key:" + _shape(path), "chiave non-stringa %s in %s (dopo %s)" % [str(kk), path, tag])
			scan(node[k], path + "." + str(k), tag)
	elif node is Array:
		for i in node.size():
			scan(node[i], "%s[%d]" % [path, i], tag)
	elif node is float:
		if is_nan(node) or is_inf(node):
			note("invariant", "nonfinite:" + _shape(path), "%s = %s (dopo %s)" % [path, str(node), tag])
		elif node < 0.0 and _neg_bad(path):
			note("invariant", "negative:" + _shape(path), "%s = %s (dopo %s)" % [path, str(node), tag])
		elif absf(node) > 1.0e300:
			note("invariant", "huge:" + _shape(path), "%s = %s (dopo %s)" % [path, str(node), tag])
	elif node is int:
		if node < 0 and _neg_bad(path):
			note("invariant", "negative:" + _shape(path), "%s = %d (dopo %s)" % [path, node, tag])
		elif node >= 4611686018427387904 or node <= -4611686018427387904:
			note("invariant", "int_huge:" + _shape(path), "%s = %d (vicino all'overflow, dopo %s)" % [path, node, tag])
	elif node is String:
		pass
	elif node == null:
		pass
	elif node is bool:
		pass
	else:
		note("invariant", "bad_type:" + _shape(path), "%s ha tipo non-JSON %s (dopo %s)" % [path, type_string(typeof(node)), tag])


## Percorsi dove un numero negativo è un errore.
func _neg_bad(path: String) -> bool:
	var s = _shape(path)
	if s.begins_with(".bank.stacks") or s.begins_with(".currencies") or s.begins_with(".skills.*.level") or s.begins_with(".skills.*.xp"):
		return true
	for key in [".qty", ".count", ".level", ".xp", ".stardust", ".tokens", ".gold", ".settlers", ".opened", ".kills", ".rank", ".stock", ".amount"]:
		if s.ends_with(key):
			return true
	return false


func check_bank() -> void:
	var bank: Dictionary = GameState.data.get("bank", {})
	var uids = {}
	for inst in bank.get("instances", []):
		if not (inst is Dictionary):
			note("invariant", "inst_not_dict", "istanza non dizionario")
			continue
		var u = str(inst.get("uid", ""))
		if u.is_empty():
			note("invariant", "inst_no_uid", "istanza senza uid: %s" % str(inst).left(100))
		if uids.has(u):
			note("invariant", "inst_dup_uid", "uid duplicato nel Deposito: %s" % u)
		uids[u] = true
		var dd = str(inst.get("def", inst.get("def_id", "")))
		if not DataRegistry.has_item(dd):
			note("invariant", "inst_bad_def:" + dd, "istanza con oggetto sconosciuto: %s" % dd)
	for iid in bank.get("stacks", {}):
		if not DataRegistry.has_item(str(iid)):
			note("invariant", "stack_bad_def:" + str(iid), "pila con oggetto sconosciuto: %s" % str(iid))
		var q: Variant = bank.stacks[iid]
		if (q is int or q is float) and q == 0:
			note("invariant", "stack_zero", "pila a zero non rimossa: %s" % str(iid))
	# l'equipaggiamento deve puntare a uid esistenti, senza duplicati
	var seen = {}
	for slot_name in GameState.data.get("equipment", {}):
		var v: Variant = GameState.data.equipment[slot_name]
		if v is String and not v.is_empty() and uids.has(v):
			if seen.has(v):
				note("invariant", "equip_dup", "la stessa istanza %s in due slot (%s e %s)" % [v, seen[v], slot_name])
			seen[v] = slot_name
	for k in ["currencies"]:
		for cid in GameState.data.get(k, {}):
			var q2: Variant = GameState.data[k][cid]
			if q2 is float and q2 != floor(q2) and cid == "gold":
				note("invariant", "gold_fractional", "oro frazionario: %s" % str(q2))
