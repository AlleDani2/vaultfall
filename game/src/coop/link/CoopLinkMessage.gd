class_name CoopLinkMessage
extends RefCounted
## Formato dei messaggi del protocollo coop (versione 1) — docs/audit_2026-10-22/69_PROTOCOLLO_COOP.md.
## Solo tipi JSON, busta e checksum di CoopCodec (tipo «M»). Nessuna rete in questa fase: lo usa CoopLink.
##
##   {"proto": 1, "t": tipo, "s": id sessione, "from": id mittente, "to": destinatario ("" = tutti), "seq": n, "p": {...}}
## Tipi: hello · hello_ack · snapshot_req · snapshot · cmd · state · grant · ping · pong · bye · error
## Regola 5 (CLAUDE.md): NESSUN tipo di messaggio trasporta oggetti o valuta da un giocatore all'altro. «cmd» porta solo
## comandi alla simulazione di gilda (es. versamento a SOLO VERSAMENTO, voto); «grant» porta bonus uguali per tutti.

const PROTOCOL_VERSION := 1
const MAX_PAYLOAD_BYTES := 16000
const MAX_ENVELOPE := 40000
const TYPES: PackedStringArray = ["hello", "hello_ack", "snapshot_req", "snapshot", "cmd", "state", "grant", "ping", "pong", "bye", "error"]
## Campi vietati in un payload (prova di non-trasferimento).
const FORBIDDEN: PackedStringArray = ["item", "items", "instance", "instances", "gold", "currencies", "bank", "gift", "trade", "offer"]


static func make(type: String, from_id: String, session_id: String, seq: int, payload: Dictionary = {}, to_id: String = "") -> Dictionary:
	return {"proto": PROTOCOL_VERSION, "t": type, "s": session_id, "from": from_id, "to": to_id, "seq": seq, "p": payload}


## {"ok", "error"}: tipo noto, versione compatibile, campi presenti, payload piccolo e senza campi vietati.
static func validate(msg: Variant) -> Dictionary:
	if not (msg is Dictionary):
		return {"ok": false, "error": "shape"}
	var m: Dictionary = msg
	for k in ["proto", "t", "s", "from", "seq", "p"]:
		if not m.has(k):
			return {"ok": false, "error": "shape"}
	if not (m.t is String) or not TYPES.has(str(m.t)):
		return {"ok": false, "error": "type"}
	if not (m.proto is float or m.proto is int) or int(m.proto) > PROTOCOL_VERSION or int(m.proto) < 1:
		return {"ok": false, "error": "version"}
	if not (m.s is String) or not (m.from is String) or str(m.from).is_empty() or str(m.from).length() > 64 or str(m.s).length() > 64:
		return {"ok": false, "error": "ids"}
	if not (m.seq is float or m.seq is int) or int(m.seq) < 0:
		return {"ok": false, "error": "seq"}
	if not (m.p is Dictionary):
		return {"ok": false, "error": "payload"}
	if CoopCodec.canonical(m.p).length() > MAX_PAYLOAD_BYTES:
		return {"ok": false, "error": "too_big"}
	if _has_forbidden(m.p, 0):
		return {"ok": false, "error": "forbidden"}
	return {"ok": true, "error": ""}


static func _has_forbidden(v: Variant, depth: int) -> bool:
	if depth > 8:
		return true
	if v is Dictionary:
		for k in v:
			if FORBIDDEN.has(str(k)) or _has_forbidden(v[k], depth + 1):
				return true
	elif v is Array:
		for x in v:
			if _has_forbidden(x, depth + 1):
				return true
	return false


static func encode(msg: Dictionary) -> String:
	return CoopCodec.pack(CoopCodec.KIND_MESSAGE, PROTOCOL_VERSION, msg, "VF", MAX_ENVELOPE, MAX_ENVELOPE)


## Decodifica + validazione. {"ok", "msg", "error"}.
static func decode(text: String) -> Dictionary:
	var r := CoopCodec.unpack(text, PROTOCOL_VERSION, CoopCodec.KIND_MESSAGE, "VF", MAX_ENVELOPE, MAX_ENVELOPE)
	if not bool(r.ok):
		return {"ok": false, "msg": {}, "error": str(r.error)}
	var v := validate(r.payload)
	if not bool(v.ok):
		return {"ok": false, "msg": {}, "error": str(v.error)}
	return {"ok": true, "msg": r.payload, "error": ""}
