extends SceneTree
## Spike S2 (docs/audit_2026-10-22/09_SCHEMA_OPERATIVO.md, docs/17 §10 R-SAV-1/7/8).
## Round-trip del salvataggio: 20.000 istanze, seed/state uint64 come stringhe, interi grandi, gzip.
## Uso:  godot --headless --path game -s res://scripts/save_spike.gd
## Codice di uscita: 0 = nessuna perdita, 1 = perdite o tipi diversi.

const N_INSTANCES := 20000
const SAVE_DIR := "user://spike_s2"
const SLOT := "user://spike_s2/slot_1.sav"
const MAX_U64_STR := "18446744073709551615"
const TWO53_PLUS_1 := 9007199254740993          # 2^53 + 1: il primo intero non rappresentabile in un double
const BIG_GOLD_STR := "123456789012345678901"   # oltre int64: solo stringa


# ---- uint64 come stringhe decimali (candidato per Rng.parse_u64 / u64_to_string) ----

static func parse_u64(s: String) -> int:
	# Restituisce i 64 bit come int con segno (wraparound): per RNG basta la stessa sequenza di bit.
	var v := 0
	for i in s.length():
		var c := s.unicode_at(i) - 48
		assert(c >= 0 and c <= 9, "cifra non valida in uint64")
		v = v * 10 + c      # il wraparound di int64 conserva i 64 bit bassi: corretto modulo 2^64
	return v


static func u64_to_string(v: int) -> String:
	if v >= 0:
		return str(v)
	# valore con bit alto acceso: si divide per 10 in aritmetica senza segno
	@warning_ignore("integer_division")
	var q := ((v >> 1) & 0x7FFFFFFFFFFFFFFF) / 5     # floor(v_unsigned / 10)
	var r := v - q * 10                              # resto 0..9 (wraparound corretto)
	return str(q) + str(r)


# ---- stato sintetico ----

static func build_state(rng: RandomNumberGenerator) -> Dictionary:
	var qualities := ["worn", "common", "fine", "superior", "masterwork"]
	var instances: Array = []
	for i in N_INSTANCES:
		instances.append({
			"uid": "i_%06d" % i,
			"def": "item_%03d" % rng.randi_range(0, 599),
			"quality": qualities[rng.randi_range(0, 4)],
			"sockets": ["glyph_%02d" % rng.randi_range(0, 40)] if rng.randi() % 3 == 0 else [],
			"rank": rng.randi_range(0, 10),
			"locked": rng.randi() % 20 == 0,
		})
	var streams := {}
	for name in ["loot", "crates", "combat", "market", "world"]:
		# seed/state uint64: generati da due metà da 32 bit, anche con il bit alto acceso
		var hi := rng.randi()
		var lo := rng.randi()
		var seed_v := (hi << 32) | lo
		var state_v := ((rng.randi() as int) << 32) | rng.randi()
		streams[name] = {"seed": u64_to_string(seed_v), "state": u64_to_string(state_v)}
	streams["world"]["seed"] = MAX_U64_STR          # caso limite 2^64-1
	streams["market"]["state"] = "0"
	return {
		"schema_version": 1, "saved_at_unix": 1790000000, "created_at_unix": 1780000000, "mode": "normal",
		"rng": streams,
		"bank": {"stacks": {"log_pine": 120, "ore_copper": 987654321}, "instances": instances, "slots_bought": 12},
		"skills": {"mining": {"xp": 123456789.5, "level": 87, "record_level": 99, "stars": 3, "unlocked": true}},
		"estate": {"coins": BIG_GOLD_STR, "settlers": 41, "pantry": 2310.75},
		"stats": {"kills": 4000000000, "gold_earned": TWO53_PLUS_1},   # NB: gold_earned intero grande = rischio R-SAV-7
	}


# ---- normalizzazione dei tipi dopo il load (R-SAV-8): float intero -> int ----

const INT_FIELDS_UNDER := {          # percorso -> campi interi dichiarati (esempio per lo spike)
	"bank": ["slots_bought"],
	"estate": ["settlers"],
}

static func normalize(data: Dictionary) -> bool:
	## Ritorna false se un campo intero dichiarato ha parte frazionaria (salvataggio corrotto).
	var ok := true
	for k in ["schema_version", "saved_at_unix", "created_at_unix"]:
		ok = _to_int(data, k) and ok
	for sec in INT_FIELDS_UNDER:
		for f in INT_FIELDS_UNDER[sec]:
			ok = _to_int(data[sec], f) and ok
	for inst in data["bank"]["instances"]:
		ok = _to_int(inst, "rank") and ok
	for k in data["bank"]["stacks"]:
		ok = _to_int(data["bank"]["stacks"], k) and ok
	for k in ["level", "record_level", "stars"]:
		ok = _to_int(data["skills"]["mining"], k) and ok
	ok = _to_int(data["stats"], "kills") and ok
	ok = _to_int(data["stats"], "gold_earned") and ok
	return ok


static func _to_int(d: Dictionary, key: String) -> bool:
	var v = d[key]
	if v is int:
		return true
	if v is float and v == floorf(v):
		d[key] = int(v)
		return true
	return false


# ---- confronto profondo, distingue int da float ----

static func diff(a: Variant, b: Variant, path: String, out: Array) -> void:
	if out.size() >= 10:
		return
	if typeof(a) != typeof(b):
		out.append("%s: tipo %s != %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
	elif a is Dictionary:
		if a.size() != b.size():
			out.append("%s: %d chiavi != %d" % [path, a.size(), b.size()])
		for k in a:
			if not b.has(k):
				out.append("%s/%s: manca" % [path, k])
			else:
				diff(a[k], b[k], path + "/" + str(k), out)
	elif a is Array:
		if a.size() != b.size():
			out.append("%s: lunghezza %d != %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				diff(a[i], b[i], "%s[%d]" % [path, i], out)
	elif a != b:
		out.append("%s: %s != %s" % [path, str(a), str(b)])


# ---- salvataggio / caricamento (stesse regole di R-SAV-1) ----

static func save_atomic(data: Dictionary, t: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var t0 := Time.get_ticks_usec()
	var json := JSON.stringify(data)
	var t1 := Time.get_ticks_usec()
	var gz := json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var t2 := Time.get_ticks_usec()
	var tmp := SLOT + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(gz)
	f.close()
	var verify := FileAccess.get_file_as_bytes(tmp)
	if verify != gz:
		return false
	if FileAccess.file_exists(SLOT):
		DirAccess.rename_absolute(SLOT, SLOT + ".bak1")
	var err := DirAccess.rename_absolute(tmp, SLOT)
	var t3 := Time.get_ticks_usec()
	t["json_ms"] = (t1 - t0) / 1000.0
	t["gzip_ms"] = (t2 - t1) / 1000.0
	t["write_ms"] = (t3 - t2) / 1000.0
	t["total_ms"] = (t3 - t0) / 1000.0
	t["json_bytes"] = json.length()
	t["gz_bytes"] = gz.size()
	return err == OK


static func load_slot(t: Dictionary) -> Variant:
	var t0 := Time.get_ticks_usec()
	var gz := FileAccess.get_file_as_bytes(SLOT)
	# La dimensione decompressa va passata: la prendiamo in ingresso dal salvataggio (vedi note nel resoconto).
	var raw := gz.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var t1 := Time.get_ticks_usec()
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	var t2 := Time.get_ticks_usec()
	t["read_gunzip_ms"] = (t1 - t0) / 1000.0
	t["parse_ms"] = (t2 - t1) / 1000.0
	return parsed


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var original := build_state(rng)
	var fails: Array = []
	print("== Spike S2: round-trip salvataggio (%d istanze) ==" % N_INSTANCES)

	# 1) parse_u64 / u64_to_string
	for s in [MAX_U64_STR, "0", "1", "9223372036854775807", "9223372036854775808", "12345678901234567890"]:
		if u64_to_string(parse_u64(s)) != s:
			fails.append("u64 round-trip fallito per " + s)
	if parse_u64(MAX_U64_STR) != -1:
		fails.append("parse_u64(2^64-1) deve avere tutti i bit accesi (-1)")

	# 2) salvataggio e caricamento
	var ts := {}
	if not save_atomic(original, ts):
		fails.append("scrittura atomica fallita")
	var tl := {}
	var loaded = load_slot(tl)
	if not (loaded is Dictionary):
		fails.append("JSON non rileggibile")
		_finish(fails, ts, tl)
		return

	# 3) il rischio documentato: un intero > 2^53 scritto come numero perde precisione
	var raw_gold: Variant = loaded["stats"]["gold_earned"]
	var lost := int(raw_gold) != TWO53_PLUS_1
	print("Intero 2^53+1 salvato come NUMERO JSON: riletto come %s %s -> %s" % [
		type_string(typeof(raw_gold)), str(raw_gold), "PERDITA (atteso: per questo si usano le stringhe)" if lost else "nessuna perdita"])

	# 4) normalizzazione (R-SAV-8) e confronto: gold_earned lo escludiamo dal confronto stretto
	if not normalize(loaded):
		fails.append("normalizzazione: campo intero con parte frazionaria")
	var expect := original.duplicate(true)
	expect["stats"]["gold_earned"] = int(raw_gold)           # unica differenza ammessa e documentata
	diff(expect, loaded, "", fails)

	# 5) salvataggio su thread: sul thread principale resta solo lo snapshot (copia profonda)
	DirAccess.remove_absolute(SLOT)
	var ta0 := Time.get_ticks_usec()
	var snapshot := original.duplicate(true)
	var snapshot_ms := (Time.get_ticks_usec() - ta0) / 1000.0
	var tt := {}
	var th := Thread.new()
	th.start(func() -> bool: return save_atomic(snapshot, tt))
	var frames_ok := 0
	while th.is_alive():                 # il thread principale resta libero
		OS.delay_msec(1)
		frames_ok += 1
	var thread_ok: bool = th.wait_to_finish()
	print("THREAD: snapshot sul thread principale %.1f ms; salvataggio in coda %.1f ms (principale libero per %d cicli da 1 ms)" % [
		snapshot_ms, tt.get("total_ms", 0), frames_ok])
	if not thread_ok:
		fails.append("salvataggio su thread fallito")
	var tl2 := {}
	var loaded2 = load_slot(tl2)
	if loaded2 is Dictionary:
		normalize(loaded2)
		diff(expect, loaded2, "thread", fails)
	else:
		fails.append("rilettura dopo salvataggio su thread fallita")
	_finish(fails, ts, tl)


func _finish(fails: Array, ts: Dictionary, tl: Dictionary) -> void:
	print("Dimensioni: JSON %.2f MB -> gzip %.2f MB (%.0f%%)" % [
		ts.get("json_bytes", 0) / 1048576.0, ts.get("gz_bytes", 0) / 1048576.0,
		100.0 * ts.get("gz_bytes", 0) / maxf(1.0, ts.get("json_bytes", 1))])
	print("SALVATAGGIO: stringify %.1f ms + gzip %.1f ms + scrittura/verifica/rename %.1f ms = %.1f ms" % [
		ts.get("json_ms", 0), ts.get("gzip_ms", 0), ts.get("write_ms", 0), ts.get("total_ms", 0)])
	print("CARICAMENTO: lettura+gunzip %.1f ms + parse %.1f ms" % [tl.get("read_gunzip_ms", 0), tl.get("parse_ms", 0)])
	DirAccess.remove_absolute(SLOT)
	DirAccess.remove_absolute(SLOT + ".bak1")
	if fails.is_empty():
		print("S2: NESSUNA PERDITA")
		quit(0)
	else:
		print("S2: PROBLEMI:")
		for f in fails:
			print("  - " + str(f))
		quit(1)
