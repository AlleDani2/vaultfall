class_name FuzzSave
extends RefCounted
## Mutatori di salvataggio (QA 72): da un salvataggio buono (Dictionary) produce centinaia di varianti corrotte
## in modo deterministico. Ogni variante = {"name": String, "bytes": PackedByteArray}.

const WRONG_TYPES: Array = [null, 5, -7, 1.5, "testo", true, [], {}, [1, 2, 3], {"x": 1}]


static func gz(text: String) -> PackedByteArray:
	return text.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


static func good_bytes(base: Dictionary) -> PackedByteArray:
	return SaveCodec.encode(base)


## Varianti a livello di byte del file compresso.
static func byte_mutations(base: Dictionary, r: RandomNumberGenerator) -> Array:
	var good := SaveCodec.encode(base)
	var json := JSON.stringify(base, "", false, true)
	var out: Array = []
	out.append({"name": "vuoto", "bytes": PackedByteArray()})
	out.append({"name": "1 byte", "bytes": PackedByteArray([0x1f])})
	out.append({"name": "solo intestazione gzip", "bytes": good.slice(0, 10)})
	out.append({"name": "18 byte", "bytes": good.slice(0, 18)})
	for pct in [10, 30, 50, 75, 90, 99]:
		out.append({"name": "troncato %d%%" % pct, "bytes": good.slice(0, good.size() * pct / 100)})
	out.append({"name": "troncato -1", "bytes": good.slice(0, good.size() - 1)})
	out.append({"name": "troncato -8 (senza trailer)", "bytes": good.slice(0, good.size() - 8)})
	for n in [1, 4, 16, 64, 256]:
		for rep in 3:
			var b := good.duplicate()
			for i in n:
				b[r.randi() % b.size()] = r.randi() % 256
			out.append({"name": "byte casuali x%d #%d" % [n, rep], "bytes": b})
	var z := good.duplicate()
	z.fill(0)
	out.append({"name": "tutto zero", "bytes": z})
	z.fill(0xff)
	out.append({"name": "tutto 0xFF", "bytes": z})
	var rnd := PackedByteArray()
	rnd.resize(good.size())
	for i in rnd.size():
		rnd[i] = r.randi() % 256
	out.append({"name": "byte casuali stessa lunghezza", "bytes": rnd})
	var rnd_gz := rnd.duplicate()
	rnd_gz[0] = 0x1f
	rnd_gz[1] = 0x8b
	out.append({"name": "casuali con intestazione gzip", "bytes": rnd_gz})
	out.append({"name": "JSON non compresso", "bytes": json.to_utf8_buffer()})
	out.append({"name": "gzip di testo non JSON", "bytes": gz("questo non e' un salvataggio")})
	out.append({"name": "gzip di []", "bytes": gz("[]")})
	out.append({"name": "gzip di stringa", "bytes": gz("\"ciao\"")})
	out.append({"name": "gzip di {}", "bytes": gz("{}")})
	out.append({"name": "gzip di null", "bytes": gz("null")})
	out.append({"name": "gzip di JSON incompleto", "bytes": gz("{\"schema_version\": 1, \"currencies\": ")})
	out.append({"name": "BOM + JSON", "bytes": gz("﻿" + json)})
	out.append({"name": "gzip + spazzatura in coda", "bytes": good + PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9])})
	out.append({"name": "due gzip concatenati", "bytes": good + good})
	out.append({"name": "UTF-8 non valido nel JSON", "bytes": (json.to_utf8_buffer().slice(0, 40) + PackedByteArray([0xff, 0xfe, 0xc3]) + json.to_utf8_buffer().slice(40)).compress(FileAccess.COMPRESSION_GZIP)})
	return out


## Varianti testuali del JSON (numeri sostituiti con valori assurdi).
static func text_mutations(base: Dictionary, r: RandomNumberGenerator) -> Array:
	var json := JSON.stringify(base, "", false, true)
	var re := RegEx.new()
	re.compile("(?<=[:\\[,])-?[0-9]+(\\.[0-9]+)?(?=[,\\]}])")
	var ms := re.search_all(json)
	var out: Array = []
	if ms.is_empty():
		return out
	var tokens: Array = ["NaN", "Infinity", "-Infinity", "nan", "inf", "1e999", "-1e999", "1e308", "-1", "-999999999",
		"99999999999999999999", "9223372036854775807", "-9223372036854775808", "0.5", "1e-320", "0", "1.7976931348623157e308"]
	for rep in 36:
		var m: RegExMatch = ms[r.randi() % ms.size()]
		var tok: String = tokens[r.randi() % tokens.size()]
		var t := json.substr(0, m.get_start()) + tok + json.substr(m.get_end())
		out.append({"name": "numero #%d -> %s" % [m.get_start(), tok], "bytes": gz(t)})
	# molti numeri insieme
	for tok in ["NaN", "-1", "1e308"]:
		var t2 := json
		var cnt := 0
		for m2 in ms:
			if r.randf() < 0.2:
				cnt += 1
		var rr := RegEx.new()
		rr.compile("(?<=[:\\[,])-?[0-9]+(?=[,\\]}])")
		var parts := PackedStringArray()
		var last := 0
		for m3 in rr.search_all(json):
			parts.append(json.substr(last, m3.get_start() - last))
			parts.append(tok if r.randf() < 0.25 else m3.get_string())
			last = m3.get_end()
		parts.append(json.substr(last))
		out.append({"name": "25%% degli interi -> %s" % tok, "bytes": gz("".join(parts))})
	return out


## Varianti strutturali sistematiche: ogni chiave di primo livello sostituita con ogni tipo sbagliato / rimossa.
static func top_level_mutations(base: Dictionary) -> Array:
	var out: Array = []
	for k in base.keys():
		var d := base.duplicate(true)
		d.erase(k)
		out.append({"name": "manca '%s'" % k, "bytes": SaveCodec.encode(d)})
		for w in WRONG_TYPES:
			if typeof(w) == typeof(base[k]) and (w is bool or w is String or w is float or w is int):
				continue
			var d2 := base.duplicate(true)
			d2[k] = w.duplicate(true) if (w is Array or w is Dictionary) else w
			out.append({"name": "'%s' = %s" % [k, JSON.stringify(w)], "bytes": SaveCodec.encode(d2)})
	return out


## Varianti ai campi di secondo livello (sezione.campo) delle sezioni-dizionario: tipo sbagliato / rimosso.
static func second_level_mutations(base: Dictionary, r: RandomNumberGenerator, per_field: int = 2) -> Array:
	var out: Array = []
	for k in base.keys():
		var sec: Variant = base[k]
		if not (sec is Dictionary):
			continue
		for f in (sec as Dictionary).keys():
			var d := base.duplicate(true)
			d[k].erase(f)
			out.append({"name": "manca '%s.%s'" % [k, f], "bytes": SaveCodec.encode(d)})
			for i in per_field:
				var w: Variant = WRONG_TYPES[r.randi() % WRONG_TYPES.size()]
				if typeof(w) == typeof(sec[f]) and not (w is Array or w is Dictionary):
					continue
				var d2 := base.duplicate(true)
				d2[k][f] = w.duplicate(true) if (w is Array or w is Dictionary) else w
				out.append({"name": "'%s.%s' = %s" % [k, f, JSON.stringify(w)], "bytes": SaveCodec.encode(d2)})
	return out


## Varianti mirate: versione di schema, modalità, seme RNG, array giganti, chiavi extra, valori di confine.
static func targeted_mutations(base: Dictionary) -> Array:
	var out: Array = []
	for v in [null, 0, -1, 2, 3, 999, 1.5, "1", "abc", true, [], {}, 1e300, 9223372036854775807]:
		var d := base.duplicate(true)
		d["schema_version"] = v
		out.append({"name": "schema_version=%s" % JSON.stringify(v), "bytes": SaveCodec.encode(d)})
	var d0 := base.duplicate(true)
	d0.erase("schema_version")
	out.append({"name": "schema_version assente", "bytes": SaveCodec.encode(d0)})
	for m in ["", "EXTREME", "hardcore", "normal ", 5, null, []]:
		var d := base.duplicate(true)
		d["mode"] = m
		out.append({"name": "mode=%s" % JSON.stringify(m), "bytes": SaveCodec.encode(d)})
	# seme / stato RNG
	var rng_cases: Array = [
		{"streams": "abc"}, {"seed": "non numerico"}, {"seed": "", "streams": {}}, {"seed": "-1"}, {"seed": "99999999999999999999999"},
		{"seed": 1.5}, {"seed": [1, 2]}, "stringa", [], 7,
	]
	for rc in rng_cases:
		var d := base.duplicate(true)
		d["rng"] = rc
		out.append({"name": "rng=%s" % JSON.stringify(rc), "bytes": SaveCodec.encode(d)})
	for kk in (base.get("rng", {}) as Dictionary).keys():
		for w in ["abc", "", "-5", "1e400", null, [], {}, 1.25, "0x10", "  7  "]:
			var d := base.duplicate(true)
			d["rng"][kk] = w if not (w is Array or w is Dictionary) else w.duplicate(true)
			out.append({"name": "rng.%s=%s" % [kk, JSON.stringify(w)], "bytes": SaveCodec.encode(d)})
	# array e dizionari giganti
	var dg := base.duplicate(true)
	var big: Array = []
	for i in 200000:
		big.append({"uid": "i_%06d" % (i + 900000), "def": "sword_copper", "quality": "fine", "sockets": [], "rank": 0, "locked": false})
	dg["bank"]["instances"] = big
	out.append({"name": "200000 istanze nel Deposito", "bytes": SaveCodec.encode(dg)})
	var dg2 := base.duplicate(true)
	var st: Dictionary = {}
	for i in 50000:
		st["junk_%d" % i] = i + 1
	dg2["bank"]["stacks"] = st
	out.append({"name": "50000 pile inventate", "bytes": SaveCodec.encode(dg2)})
	var dg3 := base.duplicate(true)
	dg3["mastery"] = {}
	for i in 30000:
		dg3["mastery"]["m_%d" % i] = {"xp": 1.0, "level": 1}
	out.append({"name": "30000 maestrie inventate", "bytes": SaveCodec.encode(dg3)})
	# chiavi extra e annidamento profondo
	var de := base.duplicate(true)
	de["campo_futuro"] = {"a": [1, 2, {"b": null}]}
	de["bank"]["campo_extra"] = "x"
	out.append({"name": "chiavi extra", "bytes": SaveCodec.encode(de)})
	var deep: Variant = 1
	for i in 400:
		deep = [deep]
	var dd := base.duplicate(true)
	dd["deep"] = deep
	out.append({"name": "annidamento 400 livelli", "bytes": gz(JSON.stringify(dd, "", false, true))})
	# valori di confine
	var edge := base.duplicate(true)
	edge["currencies"]["gold"] = 9223372036854775807
	out.append({"name": "oro = int64 max", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["currencies"]["gold"] = -50
	out.append({"name": "oro negativo", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["currencies"]["gold"] = "123456789012345678901234"
	out.append({"name": "oro stringa enorme", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["currencies"]["gold"] = [1]
	out.append({"name": "oro array", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["currencies"]["gold"] = 1e300
	out.append({"name": "oro 1e300", "bytes": gz(JSON.stringify(edge, "", false, true))})
	edge = base.duplicate(true)
	edge["saved_at_unix"] = 99999999999
	out.append({"name": "saved_at nel futuro (anno 5138)", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["saved_at_unix"] = -99999999999
	out.append({"name": "saved_at negativo enorme", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["saved_at_unix"] = 0
	out.append({"name": "saved_at = 0 (anni di offline)", "bytes": SaveCodec.encode(edge)})
	edge = base.duplicate(true)
	edge["saved_at_unix"] = "ieri"
	out.append({"name": "saved_at stringa", "bytes": SaveCodec.encode(edge)})
	for k in edge["skills"].keys():
		var e2 := base.duplicate(true)
		e2["skills"][k]["level"] = 100000
		out.append({"name": "skills.%s.level=100000" % k, "bytes": SaveCodec.encode(e2)})
		var e3 := base.duplicate(true)
		e3["skills"][k]["level"] = -3
		e3["skills"][k]["xp"] = -1000.0
		out.append({"name": "skills.%s livello/xp negativi" % k, "bytes": SaveCodec.encode(e3)})
		break
	return out
