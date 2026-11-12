class_name FuzzLib
extends RefCounted
## Utilità comuni dei fuzzer (QA 72): cattura degli errori del motore con Logger (funzione, file, riga),
## generatori di valori assurdi, partita di prova, mutatori di salvataggio. Tutto deterministico (seme fisso).
## Usata da tests/test_fuzz_*.gd e da tools/analysis/fuzz_run.gd.


## Logger che registra ogni errore di script/motore con la sorgente (non interrompe nulla).
class ErrLog extends Logger:
	var entries: Array = []        # [{fn, file, line, msg, kind}]
	var enabled := true

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _bt: Array) -> void:
		if not enabled:
			return
		entries.append({"fn": function, "file": file, "line": line, "msg": (rationale if rationale != "" else code),
			"kind": error_type})

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func clear() -> void:
		entries.clear()

	func count() -> int:
		return entries.size()

	## Chiavi uniche "file:riga msg" delle voci da `from` in poi.
	## `scripts_only` = true: solo errori di script (GDScript, kind 2) e di tutto cio' che non e' rumore di motore su file
	## corrotti; false: solo il rumore del motore (zlib/JSON/parsing), atteso con file corrotti. I WARNING sono scartati.
	func sigs_since(from: int, scripts_only: bool = true) -> Array:
		var out: Array = []
		for i in range(from, entries.size()):
			var e: Dictionary = entries[i]
			if int(e.kind) == 1:
				continue
			var noise := str(e.file).get_file() in ["compression.cpp", "variant_call.cpp", "ustring.cpp", "json.cpp", "file_access.cpp"]
			if noise == scripts_only:
				continue
			var s := "%s:%d %s" % [str(e.file).get_file(), int(e.line), str(e.msg).substr(0, 110)]
			if not out.has(s):
				out.append(s)
		return out


static func make_log() -> ErrLog:
	var l := ErrLog.new()
	OS.add_logger(l)
	return l


static func drop_log(l: ErrLog) -> void:
	l.enabled = false
	OS.remove_logger(l)


# ------------------------------------------------------------------ valori assurdi

const NASTY_INTS: Array = [0, 1, -1, 2, 3, 7, 10, 99, 100, 1000, -1000, 65535, 2147483647, -2147483648, 4294967296,
	9007199254740993, 9223372036854775807, -9223372036854775808]
const NASTY_FLOATS: Array = [0.0, -0.0, 0.5, -0.5, 1.0, 1e-9, 1e9, 1e300, -1e300, INF, -INF, NAN]
const NASTY_STRINGS: Array = ["", " ", "x", "nonexistent_id", "__proto__", "../../etc/passwd", "ÿ\u0000ü", "🙂", "%s%d", "{}", "[]",
	"null", "NaN", "999999999999999999999999999"]


static func nasty_int(r: RandomNumberGenerator) -> int:
	if r.randf() < 0.55:
		return NASTY_INTS[r.randi() % NASTY_INTS.size()]
	return r.randi_range(-5, 60)


static func nasty_float(r: RandomNumberGenerator) -> float:
	if r.randf() < 0.5:
		return NASTY_FLOATS[r.randi() % NASTY_FLOATS.size()]
	return r.randf_range(-3.0, 300.0)


## Raccoglie id reali dai dati (oggetti, azioni, zone, mostri, casse, missioni, ...) per argomenti "validi".
static func id_pool(dr: Object) -> Array:
	var pool: Array = []
	for k in dr.all_items():
		pool.append(str(k))
	for k in dr.all_actions():
		pool.append(str(k))
	for t in dr.table_names():
		for row in dr.table(t):
			if row is Dictionary and row.has("id") and not pool.has(str(row.id)):
				pool.append(str(row.id))
	return pool


const KIND_BY_ARG: Dictionary = {
	"skill_id": "skills", "skill": "skills", "def_id": "items", "item_id": "items", "item": "items", "glyph_id": "items",
	"action_id": "actions", "aid": "actions", "action": "actions", "crate_id": "crate_items", "zone_id": "zones", "zone": "zones",
	"monster_id": "monsters", "mon": "monsters", "mid": "monsters", "quest_id": "quests", "bid": "estate_buildings",
	"building": "estate_buildings", "node_id": "constellations", "spot_id": "secret_spots", "raid_id": "raids",
	"trial_id": "trials", "faction_id": "factions", "shop_id": "shop", "shop_item_id": "shop", "pet_id": "pets",
	"event_id": "events", "class_id": "classes", "dungeon_id": "dungeons", "boss_id": "world_bosses", "ability_id": "abilities",
	"talent_id": "talents", "achievement_id": "achievements", "id": "any",
}


## Id veri raggruppati per genere (per argomenti "validi" scelti dal nome del parametro).
static func kind_pools(dr: Object) -> Dictionary:
	var out: Dictionary = {"items": dr.all_items().keys(), "actions": dr.all_actions().keys(), "crate_items": []}
	for k in dr.all_items():
		if str(dr.all_items()[k].get("category", "")) == "crate":
			out["crate_items"].append(k)
	for t in dr.table_names():
		var ids: Array = []
		for row in dr.table(t):
			if row is Dictionary and row.has("id"):
				ids.append(str(row.id))
		out[t] = ids
	out["any"] = id_pool(dr)
	return out


## Argomento scelto dal NOME del parametro (stessi tipi dichiarati). Quantita': per lo più piccole, ogni tanto assurde.
static func arg_named(r: RandomNumberGenerator, type: int, aname: String, kp: Dictionary, uids: Array) -> Variant:
	var kind: String = KIND_BY_ARG.get(aname, "")
	if type == TYPE_STRING or type == TYPE_STRING_NAME:
		if aname.begins_with("uid") and not uids.is_empty() and r.randf() < 0.8:
			return uids[r.randi() % uids.size()]
		var x := r.randf()
		if kind != "" and kp.has(kind) and not (kp[kind] as Array).is_empty() and x < 0.75:
			return kp[kind][r.randi() % (kp[kind] as Array).size()]
		return nasty_string(r, kp["any"])
	if type == TYPE_INT and aname in ["qty", "n", "count", "amount", "num", "quantity"]:
		var y := r.randf()
		if y < 0.45:
			return r.randi_range(1, 10)
		if y < 0.70:
			return r.randi_range(11, 1000)
		if y < 0.85:
			return [0, -1, -5][r.randi() % 3]
		return nasty_int(r)
	if type == TYPE_ARRAY and (aname.begins_with("uid") or aname == "entries"):
		var a: Array = []
		for i in r.randi_range(0, 5):
			a.append(uids[r.randi() % uids.size()] if (not uids.is_empty() and r.randf() < 0.7) else nasty_string(r, kp["any"]))
		return a
	return arg_for(r, type, kp["any"], uids)


static func nasty_string(r: RandomNumberGenerator, pool: Array) -> String:
	var x := r.randf()
	if x < 0.55 and not pool.is_empty():
		return pool[r.randi() % pool.size()]
	if x < 0.85:
		return NASTY_STRINGS[r.randi() % NASTY_STRINGS.size()]
	return "id_%d" % r.randi_range(0, 99999)


## Argomento casuale rispettando il tipo dichiarato (GDScript non converte i tipi sbagliati: la chiamata verrebbe
## rifiutata dal motore e non proverebbe nulla sul gioco).
static func arg_for(r: RandomNumberGenerator, type: int, pool: Array, uids: Array) -> Variant:
	match type:
		TYPE_BOOL:
			return r.randf() < 0.5
		TYPE_INT:
			return nasty_int(r)
		TYPE_FLOAT:
			return nasty_float(r)
		TYPE_STRING, TYPE_STRING_NAME:
			if not uids.is_empty() and r.randf() < 0.3:
				return uids[r.randi() % uids.size()]
			return nasty_string(r, pool)
		TYPE_ARRAY:
			var n := r.randi_range(0, 4)
			var a: Array = []
			for i in n:
				a.append(nasty_string(r, pool) if r.randf() < 0.5 else nasty_int(r))
			if not uids.is_empty() and r.randf() < 0.5:
				a.append(uids[r.randi() % uids.size()])
			return a
		TYPE_DICTIONARY:
			return {} if r.randf() < 0.6 else {"id": nasty_string(r, pool), "qty": nasty_int(r)}
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray([nasty_string(r, pool)])
		TYPE_NIL:     # Variant
			var k := r.randi() % 6
			match k:
				0: return null
				1: return nasty_int(r)
				2: return nasty_float(r)
				3: return nasty_string(r, pool)
				4: return []
				_: return {}
		_:
			return null


## Metodi pubblici (non _x) dichiarati dallo script del sistema, con tipi degli argomenti.
static func public_methods(obj: Object, skip: Array = []) -> Array:
	var out: Array = []
	var script: Script = obj.get_script()
	for m in script.get_script_method_list():
		var nm: String = m.name
		if nm.begins_with("_") or skip.has(nm):
			continue
		out.append(m)
	return out


# ------------------------------------------------------------------ partita di prova

static func tmp_save_dir(tag: String) -> String:
	return "user://fuzz_%s_%d" % [tag, Time.get_ticks_usec()]


static func rm_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path + "/" + f)
	DirAccess.remove_absolute(path)


static func write_raw(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()


## Passi diretti della simulazione (tempo simulato, niente tempo reale).
static func run_steps(seconds: float) -> void:
	var n := int(seconds / FixedStepClock.STEP)
	for i in n:
		Game._on_step(FixedStepClock.STEP)


## Dà a una partita nuova un po' di tutto: oro, scorte, istanze, livelli, sblocchi, per esercitare più codice.
static func enrich(r: RandomNumberGenerator) -> void:
	GameState.data["currencies"]["gold"] = 5_000_000
	var bank := Game.system("bank") as BankSystem
	var ids: Array = DataRegistry.all_items().keys()
	for i in 150:
		bank.add(str(ids[r.randi() % ids.size()]), r.randi_range(1, 20), "fuzz")
	for t in ["feature:combat", "feature:crates", "feature:market", "feature:estate", "feature:mercenaries", "feature:secrets",
			"feature:factions", "feature:prestige"]:
		if not GameState.data["unlocks"].has(t):
			GameState.data["unlocks"].append(t)


# ------------------------------------------------------------------ invarianti

## Percorre lo stato cercando NaN/inf; aggiunge le violazioni a `out` come "percorso: valore".
static func scan_numbers(node: Variant, path: String, out: Array, depth: int = 0) -> void:
	if out.size() > 40 or depth > 12:
		return
	if node is float:
		var f: float = node
		if is_nan(f) or is_inf(f):
			out.append("%s: %s" % [path, str(f)])
	elif node is Dictionary:
		for k in node:
			scan_numbers(node[k], path + "." + str(k), out, depth + 1)
	elif node is Array:
		var a: Array = node
		for i in mini(a.size(), 400):
			scan_numbers(a[i], "%s[%d]" % [path, i], out, depth + 1)


## Invarianti di una partita in corso: valute e scorte non negative, niente NaN, uid unici, livelli entro i limiti.
static func invariants() -> Array:
	var out: Array = []
	if not GameState.active:
		return ["partita non attiva"]
	var d: Dictionary = GameState.data
	scan_numbers(d, "state", out)
	var cur: Variant = d.get("currencies")
	if cur is Dictionary:
		for k in cur:
			var v: Variant = cur[k]
			if not (v is int) or int(v) < 0:
				out.append("currencies.%s = %s (negativo o non intero)" % [k, str(v)])
	else:
		out.append("currencies non e' un Dictionary")
	var bank: Variant = d.get("bank")
	if bank is Dictionary:
		var st: Variant = bank.get("stacks")
		if st is Dictionary:
			for k in st:
				if not (st[k] is int) or int(st[k]) <= 0:
					out.append("bank.stacks.%s = %s" % [k, str(st[k])])
		var seen := {}
		var inst: Variant = bank.get("instances")
		if inst is Array:
			for it in inst:
				if it is Dictionary:
					var u := str(it.get("uid", ""))
					if seen.has(u):
						out.append("uid duplicato " + u)
					seen[u] = true
	var sk: Variant = d.get("skills")
	if sk is Dictionary:
		for k in sk:
			var s: Variant = sk[k]
			if s is Dictionary:
				if int(s.get("level", 1)) < 1 or float(s.get("xp", 0.0)) < 0.0:
					out.append("skills.%s livello/xp fuori limite (%s, %s)" % [k, str(s.get("level")), str(s.get("xp"))])
	return out
