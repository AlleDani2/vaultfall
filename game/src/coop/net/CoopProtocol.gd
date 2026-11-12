class_name CoopProtocol
extends RefCounted
## Formato e VALIDAZIONE dei messaggi di rete del coop (COOP-2). Funzioni pure, testate in tests/test_coop_net_protocol.gd.
## Ogni messaggio è un Dictionary JSON con il campo "t" (tipo). Regole:
##   - dimensione controllata PRIMA di leggere il JSON (max_packet_bytes; le istantanee dall'host max_snapshot_bytes);
##   - tipo noto e campi ESATTI (nessun campo in più), tipi e intervalli verificati, stringhe corte e senza controllo;
##   - interi JSON (che arrivano come float) riportati a int solo se senza parte frazionaria;
##   - NESSUN tipo di messaggio sposta oggetti tra giocatori: non esistono "gift", "trade", "withdraw" (regola 5).
## I numeri (limiti) arrivano da data/coop_net_rules.json (rules.net), passati dal chiamante.

const VERSION := CoopTransport.PROTOCOL_VERSION

## Tipi di attività ammessi nella presenza (chiave dell'animazione del personaggino).
const ACTIVITIES: PackedStringArray = ["idle", "rest", "skill", "combat", "dungeon", "raid", "wboss", "rift",
	"estate", "crate", "market", "menu"]

## Operazioni che un socio può chiedere all'host (comandi). Nessuna rimuove valore dal fondo verso un giocatore.
const CMD_OPS: PackedStringArray = ["deposit", "boss_hit", "propose", "vote", "decide", "kick", "leave"]

## Messaggi che il CLIENT può mandare all'host.
const CLIENT_TYPES: PackedStringArray = ["hello", "presence", "ping", "pong", "cmd", "snap_req", "code", "bye"]
## Messaggi che l'HOST può mandare ai client.
const HOST_TYPES: PackedStringArray = ["welcome", "reject", "roster", "ping", "pong", "ack", "op", "hash", "snap", "code", "bye"]

## Schema dei campi: nome -> [tipo, a, b]. Tipi: "int" [min,max] · "str" [min_len,max_len] · "id" (identificatore
## [a-z0-9_:] max 48) · "bool" · "hex" [len] · "b64" [max_len] · "dict" · "array" [max_len] · "name" (soprannome).
## Il campo "t" è implicito.
const SCHEMA := {
	"hello": {"v": ["int", 0, 65535], "name": ["name"], "uid": ["hex", 16], "guild": ["gid"], "pw": ["str", 0, 32],
		"seq": ["int", 0, 2147483647]},
	"welcome": {"v": ["int", 0, 65535], "you": ["int", 0, 2147483647], "gseq": ["int", 0, 2147483647],
		"guild": ["gid"], "seq": ["int", 0, 2147483647]},
	"reject": {"reason": ["id"], "seq": ["int", 0, 2147483647]},
	"presence": {"name": ["name"], "cls": ["id"], "lvl": ["int", 0, 100000], "hl": ["int", 0, 100000],
		"act": ["act"], "sk": ["id"], "det": ["id"], "ping": ["int", 0, 60000]},
	"roster": {"list": ["array", 9]},
	"ping": {"n": ["int", 0, 2147483647]},
	"pong": {"n": ["int", 0, 2147483647]},
	"cmd": {"seq": ["int", 1, 2147483647], "op": ["op"], "args": ["dict"]},
	"ack": {"seq": ["int", 0, 2147483647], "ok": ["bool"], "err": ["id"]},
	"op": {"gseq": ["int", 1, 2147483647], "op": ["dict"]},
	"hash": {"gseq": ["int", 0, 2147483647], "h": ["hex", 32]},
	"snap_req": {},
	"snap": {"gseq": ["int", 0, 2147483647], "data": ["b64", 90000]},
	"code": {"id": ["int", 0, 2147483647], "code": ["b64", 900]},
	"bye": {},
}

## Argomenti ammessi per ogni comando.
const CMD_ARGS := {
	"deposit": {"item": ["id"], "qty": ["int", 1, 1000000]},
	"boss_hit": {"week": ["int", 0, 2147483647], "pts": ["int", 0, 1000000], "att": ["int", 0, 2147483647]},
	"propose": {"project": ["id"]},
	"vote": {"yes": ["bool"]},
	"decide": {},
	"kick": {"uid": ["hex", 16]},
	"leave": {},
}

## Voce del roster (host -> client): una per giocatore collegato (host compreso).
const ROSTER_ENTRY := {"id": ["int", 0, 2147483647], "uid": ["hex", 16], "name": ["name"], "cls": ["id"],
	"lvl": ["int", 0, 100000], "hl": ["int", 0, 100000], "act": ["act"], "sk": ["id"], "det": ["id"],
	"ping": ["int", 0, 60000], "age": ["int", 0, 86400]}

static var _re_id: RegEx
static var _re_hex: RegEx
static var _re_b64: RegEx
static var _re_name: RegEx
static var _re_gid: RegEx


static func _init_re() -> void:
	if _re_id != null:
		return
	_re_id = RegEx.create_from_string("^[a-z0-9_:]{0,48}$")
	_re_hex = RegEx.create_from_string("^[0-9a-f]+$")
	_re_b64 = RegEx.create_from_string("^[A-Za-z0-9+/=_-]*$")
	# lettere (anche accentate), cifre, spazio, trattino, trattino basso, punto
	_re_name = RegEx.create_from_string("^[\\p{L}\\p{N} _.\\-]+$")
	_re_gid = RegEx.create_from_string("^(g_[0-9a-f]{12})?$")


# ------------------------------------------------------------------ codifica

static func encode(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()


## Decodifica e valida un pacchetto. `from_host` = il pacchetto arriva dall'host (tipi e dimensioni diversi).
## Ritorna {"ok": bool, "msg": Dictionary, "err": String}.
static func decode(bytes: PackedByteArray, net: Dictionary, from_host: bool) -> Dictionary:
	var max_b := int(net["max_snapshot_bytes"]) if from_host else int(net["max_packet_bytes"])
	if bytes.is_empty():
		return _fail("empty")
	if bytes.size() > max_b:
		return _fail("oversize")
	if not valid_utf8(bytes):
		return _fail("utf8")      # controllo silenzioso: get_string_from_utf8 riempirebbe il registro di errori
	var text := bytes.get_string_from_utf8()
	if text.is_empty():
		return _fail("utf8")
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("json")
	if not (json.data is Dictionary):
		return _fail("not_object")
	var msg: Dictionary = json.data
	var err := validate(msg, from_host, net)
	if not err.is_empty():
		return _fail(err)
	return {"ok": true, "msg": msg, "err": ""}


## Valida (e normalizza gli interi di) un messaggio già letto. "" = valido, altrimenti il codice d'errore.
static func validate(msg: Dictionary, from_host: bool, net: Dictionary = {}) -> String:
	_init_re()
	var t: Variant = msg.get("t")
	if not (t is String):
		return "no_type"
	var allowed := HOST_TYPES if from_host else CLIENT_TYPES
	if not allowed.has(t) or not SCHEMA.has(t):
		return "bad_type"
	var spec: Dictionary = SCHEMA[t]
	var err := _check_fields(msg, spec, ["t"], net)
	if not err.is_empty():
		return err
	if t == "cmd":
		var a: Dictionary = msg.args
		err = _check_fields(a, CMD_ARGS[msg.op], [], net)
		if not err.is_empty():
			return "args_" + err
	elif t == "roster":
		for e in msg.list:
			if not (e is Dictionary):
				return "roster_entry"
			err = _check_fields(e, ROSTER_ENTRY, [], net)
			if not err.is_empty():
				return "roster_" + err
	elif t == "op":
		# l'operazione la ricontrolla CoopGuild.apply; qui solo forma minima
		if not (msg.op.get("k") is String) or str(msg.op.k).length() > 16:
			return "op_kind"
	return ""


static func _check_fields(d: Dictionary, spec: Dictionary, extra_ok: Array, net: Dictionary) -> String:
	for k in d:
		if not (k is String):
			return "key_type"
		if not spec.has(k) and not extra_ok.has(k):
			return "extra_field:" + str(k).left(16)
	for k in spec:
		if not d.has(k):
			return "missing:" + str(k)
		var e := _check_value(d, k, spec[k], net)
		if not e.is_empty():
			return e + ":" + str(k)
	return ""


static func _check_value(d: Dictionary, k: String, s: Array, net: Dictionary) -> String:
	var v: Variant = d[k]
	match str(s[0]):
		"int":
			if not (v is int or v is float):
				return "type"
			var f := float(v)
			if is_nan(f) or is_inf(f) or f != floor(f) or absf(f) > 9.0e15:
				return "not_int"
			var i := int(f)
			if i < int(s[1]) or i > int(s[2]):
				return "range"
			d[k] = i
		"bool":
			if not (v is bool):
				return "type"
		"str":
			if not (v is String):
				return "type"
			var n := (v as String).length()
			if n < int(s[1]) or n > int(s[2]) or _has_control(v):
				return "len"
		"id":
			if not (v is String) or _re_id.search(v) == null:
				return "id"
		"gid":
			if not (v is String) or _re_gid.search(v) == null:
				return "gid"
		"act":
			if not (v is String) or not ACTIVITIES.has(v):
				return "act"
		"op":
			if not (v is String) or not CMD_OPS.has(v):
				return "op"
		"hex":
			if not (v is String) or (v as String).length() != int(s[1]) or _re_hex.search(v) == null:
				return "hex"
		"b64":
			var mx := int(s[1])
			if k == "code":
				mx = int(net.get("max_code_len", mx))
			if not (v is String) or (v as String).length() > mx or _re_b64.search(v) == null:
				return "b64"
		"name":
			if not (v is String) or sanitize_name(v, 16) != v:
				return "name"
		"dict":
			if not (v is Dictionary):
				return "type"
		"array":
			if not (v is Array) or (v as Array).size() > int(s[1]):
				return "type"
	return ""


## UTF-8 ben formato (niente sequenze troncate, sovralunghe o surrogati).
static func valid_utf8(b: PackedByteArray) -> bool:
	var i := 0
	var n := b.size()
	while i < n:
		var c := b[i]
		var extra := 0
		var lo := 0
		if c < 0x80:
			i += 1
			continue
		elif c >= 0xC2 and c <= 0xDF:
			extra = 1
			lo = 0x80
		elif c >= 0xE0 and c <= 0xEF:
			extra = 2
			lo = 0x800
		elif c >= 0xF0 and c <= 0xF4:
			extra = 3
			lo = 0x10000
		else:
			return false
		if i + extra >= n:
			return false
		var cp := c & (0x3F >> extra)
		for j in range(1, extra + 1):
			var cc := b[i + j]
			if (cc & 0xC0) != 0x80:
				return false
			cp = (cp << 6) | (cc & 0x3F)
		if cp < lo or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
			return false
		i += extra + 1
	return true


static func _has_control(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E):
			return true
	return false


## Soprannome pulito: spazi ai bordi tolti, spazi doppi ridotti, solo lettere/cifre/spazio/._-, max `max_len`.
## Ritorna "" se non resta nulla di valido (la UI chiede un altro nome).
static func sanitize_name(raw: String, max_len: int = 16) -> String:
	_init_re()
	var s := raw.strip_edges()
	while s.contains("  "):
		s = s.replace("  ", " ")
	s = s.left(max_len).strip_edges()
	if s.is_empty() or _has_control(s) or _re_name.search(s) == null:
		return ""
	return s


static func _fail(err: String) -> Dictionary:
	return {"ok": false, "msg": {}, "err": err}
