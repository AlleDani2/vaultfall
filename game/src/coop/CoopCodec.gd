class_name CoopCodec
extends RefCounted
## Busta dei codici condivisibili (COOP-1): una riga di testo che si copia e si incolla in una chat.
##
##   VF<tipo><versione>.<base64( gzip( {"v","k","p","c"} ) )>
##     tipo     H = Scheda del Compagno · R = risultato della Prova della settimana
##     versione versione di FORMATO dei codici (coop_rules.format.version), NON lo schema del salvataggio
##     p        il contenuto, come TESTO JSON (così il checksum si calcola sul testo trasmesso, senza ambiguità)
##     c        checksum FNV-1a a 32 bit di p (contro gli errori di copia; NON è una firma: la sicurezza sta nei limiti)
##
## Difese: lunghezza massima del testo, caratteri ammessi, decompressione con tetto di byte (niente "bombe" gzip),
## struttura e tipi controllati, versione più recente della nostra rifiutata. Mai crash: ogni errore ha un codice
## (la UI lo traduce con la chiave UI_COOP_ERR_<CODICE>).
## Stesso formato di busta (con altri tipi) per i messaggi del protocollo di rete futuro (docs/audit_2026-10-22/69).

const DEFAULT_MAX_CHARS := 6000
const DEFAULT_MAX_JSON := 12000
const KIND_HERO := "H"
const KIND_RESULT := "R"
const KIND_MESSAGE := "M"
const KINDS: PackedStringArray = ["H", "R", "M"]


## FNV-1a a 32 bit sui byte UTF-8, in esadecimale (8 cifre). Deterministico su ogni piattaforma.
static func checksum(text: String) -> String:
	var h := 0x811C9DC5
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 0x01000193) & 0xFFFFFFFF
	return "%08x" % h


## Testo JSON canonico (chiavi ordinate, numeri a piena precisione).
static func canonical(payload: Variant) -> String:
	return JSON.stringify(payload, "", true, true)


## Impacchetta `payload` (Dictionary) nel codice di tipo `kind`. Ritorna "" se il contenuto supera i limiti.
static func pack(kind: String, version: int, payload: Dictionary, prefix: String = "VF", max_chars: int = DEFAULT_MAX_CHARS,
		max_json: int = DEFAULT_MAX_JSON) -> String:
	if not KINDS.has(kind):
		return ""
	var body := canonical(payload)
	var env := {"v": version, "k": kind, "p": body, "c": checksum(body)}
	var raw := canonical(env).to_utf8_buffer()
	if raw.size() > max_json:
		return ""
	var code := "%s%s%d.%s" % [prefix, kind, version, Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))]
	return code if code.length() <= max_chars else ""


## Apre un codice. Ritorna {"ok", "kind", "version", "payload": Dictionary, "error": codice}.
## `expect_kind` ("" = qualsiasi); `max_version` = la versione di formato che questo gioco capisce.
static func unpack(text: String, max_version: int, expect_kind: String = "", prefix: String = "VF",
		max_chars: int = DEFAULT_MAX_CHARS, max_json: int = DEFAULT_MAX_JSON) -> Dictionary:
	var clean := text.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "")
	if clean.is_empty():
		return _fail("empty")
	if clean.length() > max_chars:
		return _fail("too_long")
	var dot := clean.find(".")
	if dot < 0 or not clean.begins_with(prefix) or dot < prefix.length() + 2:
		return _fail("prefix")
	var head := clean.substr(prefix.length(), dot - prefix.length())
	var kind := head.substr(0, 1)
	var ver_txt := head.substr(1)
	if not KINDS.has(kind):
		return _fail("prefix")
	if ver_txt.is_empty() or not ver_txt.is_valid_int() or ver_txt.length() > 4:
		return _fail("prefix")
	var ver := int(ver_txt)
	if ver < 1:
		return _fail("prefix")
	if not expect_kind.is_empty() and kind != expect_kind:
		return _fail("kind")
	if ver > max_version:
		return _fail("version_newer")
	var b64 := clean.substr(dot + 1)
	if b64.is_empty() or b64.length() % 4 != 0:
		return _fail("base64")
	for i in b64.length():
		var c := b64.unicode_at(i)
		var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 43 or c == 47 or c == 61
		if not ok:
			return _fail("base64")
	var bytes := Marshalls.base64_to_raw(b64)
	if bytes.size() < 18 or bytes[0] != 0x1f or bytes[1] != 0x8b:
		return _fail("gzip")
	# ISIZE: gli ultimi 4 byte del gzip dichiarano la dimensione originale (mod 2^32). Se supera il tetto non si decomprime nemmeno.
	var n := bytes.size()
	var isize := int(bytes[n - 4]) | (int(bytes[n - 3]) << 8) | (int(bytes[n - 2]) << 16) | (int(bytes[n - 1]) << 24)
	if isize == 0:
		return _fail("gzip")       # un gzip che si espande a 0 byte manda in ciclo infinito decompress_dynamic (Godot 4.7.2, QA 83 C-03)
	if isize > max_json:
		return _fail("too_big")
	var raw := bytes.decompress_dynamic(max_json + 1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return _fail("gzip")
	if raw.size() > max_json:
		return _fail("too_big")
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return _fail("json")
	var env: Dictionary = json.data
	if not (env.get("v") is float or env.get("v") is int) or not (env.get("k") is String) or not (env.get("p") is String) \
			or not (env.get("c") is String):
		return _fail("shape")
	if int(env.v) != ver or str(env.k) != kind:
		return _fail("shape")
	if checksum(str(env.p)) != str(env.c):
		return _fail("checksum")
	var pj := JSON.new()
	if pj.parse(str(env.p)) != OK or not (pj.data is Dictionary):
		return _fail("json")
	return {"ok": true, "kind": kind, "version": ver, "payload": pj.data, "error": ""}


## Tipo di un codice senza aprirlo ("H", "R", "M" oppure "" se non sembra un codice).
static func kind_of(text: String, prefix: String = "VF") -> String:
	var clean := text.strip_edges()
	if clean.length() > prefix.length() + 1 and clean.begins_with(prefix):
		var k := clean.substr(prefix.length(), 1)
		if KINDS.has(k):
			return k
	return ""


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "kind": "", "version": 0, "payload": {}, "error": code}
