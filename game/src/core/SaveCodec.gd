class_name SaveCodec
extends RefCounted
## Codifica, migrazione e normalizzazione dei salvataggi (docs/17 §10). Funzioni pure, testabili senza file.
## SaveService (autoload) le usa per i file degli slot e per esportazione/importazione Base64.
##
## Per cambiare la forma dello stato:
##   1) SCHEMA_VERSION += 1;
##   2) aggiungere `static func migrate_vN_to_vN1(d: Dictionary) -> Dictionary` qui sotto;
##   3) registrarla in migrations() con la chiave N;
##   4) aggiungere un test in tests/test_save_service.gd con un salvataggio vN di esempio.
## Mai rompere un salvataggio esistente senza migrazione (CLAUDE.md regola 7).

const SCHEMA_VERSION := 5
## Tetto alla dimensione dello stato decompresso (256 MB).
const MAX_RAW_BYTES := 268435456
## Tetto «sicuro» di un campo intero dichiarato (sotto 2^63 con margine): oltre questo valore il codec rifiuta il file
## (`_as_int`), quindi lo stato in memoria viene saturato PRIMA della scrittura (prepare_for_write).
const SAFE_INT_MAX := 9000000000000000000
## Oltre 2^53 un double non rappresenta piu' ogni intero: i campi interi dichiarati cosi' grandi si scrivono come stringa.
const EXACT_INT_MAX := 9007199254740992
## Versioni:
##   1 -> 2 (PROGRESSIONE): la sezione `contracts` (Commesse, ContractSystem) ha campi nuovi; le sezioni morte `relics` e
##   `settings_snapshot` (mai lette né scritte da alcun sistema) escono dallo stato. I campi nuovi di `contracts` si
##   completano da soli (ContractSystem.from_state): la migrazione li aggiunge comunque in modo esplicito e non perde nulla.
##   2 -> 3 (QA82 Q82-1, anti save-scum delle Casse): `crates.draw_seed` (stringa uint64) e `crates.draw_n` (contatori di
##   estrazione per cassa). Il seme si deriva dal seme principale della partita (`rng.master`), esattamente come farebbe
##   CrateSystem alla prima apertura; i contatori partono da 0. Nessun oggetto, pity o album viene toccato.
##   3 -> 4 (UI F13, Sabbia del Custode): sezione additiva `time_push` (riserva, spinta totale, coda, oggi, regalo di sblocco).
##   Una partita vecchia la riceve vuota; il regalo di sblocco (una tantum) lo assegna TimePushSystem se il token e' gia' presente.
##   4 -> 5 (UI F17, schede del Deposito): campi additivi della sezione `bank`: `tabs` = [] (schede del giocatore), `tab_of` = {}
##   (assegnazioni «s:<def>» / «u:<uid>» -> id scheda), `next_tab` = 1 (contatore degli id, mai riusati). Nessuna quantita' ne'
##   istanza cambia; BankSystem.from_state ripulisce schede e assegnazioni non valide (una riga nel Registro).


## Migrazioni registrate: versione di partenza -> Callable(Dictionary) -> Dictionary.
static func migrations() -> Dictionary:
	return {
		1: SaveCodec.migrate_v1_to_v2,
		2: SaveCodec.migrate_v2_to_v3,
		3: SaveCodec.migrate_v3_to_v4,
		4: SaveCodec.migrate_v4_to_v5,
	}


## v1 -> v2: vedi l'elenco delle versioni in cima. Idempotente; non tocca nessun progresso del giocatore.
static func migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	var c: Variant = d.get("contracts")
	if not (c is Dictionary):
		c = {}
	for k in ["daily", "weekly"]:
		if not ((c as Dictionary).get(k) is Array):
			c[k] = []
	c["tokens"] = int((c as Dictionary).get("tokens", 0))
	d["contracts"] = c
	d.erase("relics")
	d.erase("settings_snapshot")
	return d


## v2 -> v3: vedi l'elenco delle versioni in cima. Idempotente; non tocca nessun progresso del giocatore.
static func migrate_v2_to_v3(d: Dictionary) -> Dictionary:
	var c: Variant = d.get("crates")
	if not (c is Dictionary):
		return d                                   # niente sezione Casse: se la creera' default_state con il seme giusto
	var rng_d: Variant = d.get("rng")
	var master := 0
	if rng_d is Dictionary and RngStreams.is_u64_string(str((rng_d as Dictionary).get("master", ""))):
		master = RngStreams.parse_u64(str((rng_d as Dictionary).master))
	var cur := str((c as Dictionary).get("draw_seed", ""))
	if not RngStreams.is_u64_string(cur) or cur == "0":
		c["draw_seed"] = RngStreams.u64_to_string(RngStreams.derive_seed(master, "crate-draw-seed", 0))
	if not ((c as Dictionary).get("draw_n") is Dictionary):
		c["draw_n"] = {}
	d["crates"] = c
	return d


## v3 -> v4: vedi l'elenco delle versioni in cima. Idempotente; aggiunge la sezione `time_push` solo se manca o e' danneggiata
## (valori a zero: TimePushSystem.from_state completa il resto). Non tocca nessun progresso del giocatore.
static func migrate_v3_to_v4(d: Dictionary) -> Dictionary:
	if not (d.get("time_push") is Dictionary):
		d["time_push"] = {"reserve_s": 0.0, "pushed_total_s": 0.0, "pending_s": 0.0, "today_s": 0.0, "day_age_s": 0.0, "gift_given": false}
	return d


## v4 -> v5: vedi l'elenco delle versioni in cima. Idempotente e additiva: aggiunge alla sezione `bank` (se c'e') solo i campi
## delle schede che mancano o hanno il tipo sbagliato. Non tocca pile, istanze, Carro, valute ne' alcun altro campo.
static func migrate_v4_to_v5(d: Dictionary) -> Dictionary:
	var b: Variant = d.get("bank")
	if not (b is Dictionary):
		return d                                   # niente Deposito: lo creera' BankSystem.default_state
	if not ((b as Dictionary).get("tabs") is Array):
		b["tabs"] = []
	if not ((b as Dictionary).get("tab_of") is Dictionary):
		b["tab_of"] = {}
	var nt: Variant = (b as Dictionary).get("next_tab")
	if not ((nt is int or nt is float) and is_finite(float(nt)) and float(nt) >= 1.0 and float(nt) == floor(float(nt))):
		b["next_tab"] = 1
	return d


# ------------------------------------------------------------------ codifica

## JSON -> UTF-8 -> gzip.
static func encode(data: Dictionary) -> PackedByteArray:
	# full_precision=true: i decimali non perdono le ultime cifre (una partita ricaricata resta identica a quella che continua)
	return JSON.stringify(data, "", false, true).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


## gzip -> JSON. Ritorna {"ok": bool, "data": Dictionary, "error": String}.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return _fail("empty")
	if bytes.size() < 18 or bytes[0] != 0x1f or bytes[1] != 0x8b:     # intestazione gzip
		return _fail("gzip")
	# La dimensione originale sta nel trailer gzip (ISIZE, ultimi 4 byte): decompress_dynamic non termina con byte
	# in coda al flusso, quindi si decomprime con la dimensione dichiarata (tetto contro le bombe di decompressione).
	var n: int = bytes.decode_u32(bytes.size() - 4)
	if n == 0 or n > MAX_RAW_BYTES:
		return _fail("gzip")
	var raw := bytes.decompress(n, FileAccess.COMPRESSION_GZIP)
	if raw.size() != n:
		return _fail("gzip")
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		return _fail("json")
	if not (json.data is Dictionary):
		return _fail("not_object")
	return {"ok": true, "data": json.data, "error": ""}


static func to_base64(data: Dictionary) -> String:
	return Marshalls.raw_to_base64(encode(data))


static func from_base64(text: String) -> Dictionary:
	var clean := text.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	if clean.is_empty():
		return _fail("empty")
	if clean.length() % 4 != 0:
		return _fail("base64")
	for i in clean.length():
		var c := clean.unicode_at(i)
		var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 43 or c == 47 or c == 61
		if not ok:
			return _fail("base64")
	var bytes := Marshalls.base64_to_raw(clean)
	return decode(bytes)


# ------------------------------------------------------------------ preparazione alla scrittura

## Prepara in PLACE uno snapshot (copia di proprieta' di chi chiama) alla scrittura, sui campi interi dichiarati `int_paths`:
##  - saturazione: un valore oltre ±SAFE_INT_MAX (o infinito) diventa ±SAFE_INT_MAX; NaN diventa 0; un decimale diventa l'intero
##    piu' vicino. Senza questo il codec rifiuterebbe il file e OGNI salvataggio successivo fallirebbe (la partita sarebbe persa).
##  - precisione (R-SAV-7): un intero oltre 2^53 si scrive come stringa di cifre (JSON lo rileggerebbe come double); `_as_int`
##    lo riconverte in int esatto al caricamento.
## Ritorna i percorsi saturati/corretti (vuoto = nessuna correzione), in formato leggibile per il Registro.
static func prepare_for_write(data: Dictionary, int_paths: PackedStringArray) -> PackedStringArray:
	var fixed := PackedStringArray()
	for p in int_paths:
		_prepare_path(data, _tokens(p), 0, p, fixed)
	return fixed


static func _prepare_path(node: Variant, toks: PackedStringArray, i: int, path: String, fixed: PackedStringArray) -> void:
	var tok := toks[i]
	var last := i == toks.size() - 1
	if tok == "[]":
		if not (node is Array):
			return
		for j in (node as Array).size():
			if last:
				_prepare_leaf(node, j, path, fixed)
			else:
				_prepare_path(node[j], toks, i + 1, path, fixed)
		return
	if not (node is Dictionary):
		return
	var keys: Array = (node as Dictionary).keys() if tok == "*" else ([tok] if (node as Dictionary).has(tok) else [])
	for k in keys:
		if last:
			_prepare_leaf(node, k, path, fixed)
		else:
			_prepare_path(node[k], toks, i + 1, path, fixed)


static func _prepare_leaf(c: Variant, k: Variant, path: String, fixed: PackedStringArray) -> void:
	var v: Variant = c[k]
	var iv := 0
	if v is float:
		var f: float = v
		if is_nan(f):
			c[k] = 0
			fixed.append("%s (%s): NaN -> 0" % [path, str(k)])
			return
		if absf(f) > float(SAFE_INT_MAX):
			iv = SAFE_INT_MAX if f > 0.0 else -SAFE_INT_MAX
			c[k] = iv
			fixed.append("%s (%s): %s -> %d" % [path, str(k), str(f), iv])
		elif f != floor(f):
			iv = int(round(f))
			c[k] = iv
			fixed.append("%s (%s): %s -> %d" % [path, str(k), str(f), iv])
		else:
			iv = int(f)
	elif v is int:
		iv = v
		if iv > SAFE_INT_MAX or iv < -SAFE_INT_MAX:
			var old := iv
			iv = SAFE_INT_MAX if iv > 0 else -SAFE_INT_MAX
			c[k] = iv
			fixed.append("%s (%s): %d -> %d" % [path, str(k), old, iv])
	else:
		return
	if iv > EXACT_INT_MAX or iv < -EXACT_INT_MAX:
		c[k] = str(iv)


# ------------------------------------------------------------------ migrazione + normalizzazione

## Porta i dati alla versione `target`. Errori: "no_version", "newer" (salvataggio di una versione del gioco
## più recente: NON si apre, R-SAV-2), "missing_migration", "migration_failed".
static func migrate(data: Dictionary, target: int = SCHEMA_VERSION, migs: Dictionary = {}) -> Dictionary:
	var table := migs if not migs.is_empty() else migrations()
	var v: Variant = data.get("schema_version")
	if not (v is int or v is float) or float(v) != floor(float(v)):
		return _fail("no_version")
	var version := int(v)
	if version > target:
		return _fail("newer")
	var d := data
	while version < target:
		var fn: Variant = table.get(version)
		if not (fn is Callable):
			return _fail("missing_migration")
		var out: Variant = (fn as Callable).call(d)
		if not (out is Dictionary):
			return _fail("migration_failed")
		d = out
		version += 1
		d["schema_version"] = version
	return {"ok": true, "data": d, "error": ""}


## R-SAV-8: i campi interi dichiarati tornano int (JSON li legge come float). Un campo intero con parte
## frazionaria (o non finito) rende il salvataggio CORROTTO: si ritorna l'elenco dei percorsi sbagliati.
## Le stringhe sono lasciate come sono (interi enormi salvati come stringa, R-SAV-7). I percorsi assenti si ignorano.
static func normalize(data: Dictionary, int_paths: PackedStringArray) -> PackedStringArray:
	var errors := PackedStringArray()
	for p in int_paths:
		_normalize_path(data, _tokens(p), 0, p, errors)
	return errors


## Decodifica + migrazione + normalizzazione in un colpo solo (usata per file e per Base64). `soft_paths` (Simulation.soft_int_paths):
## campi che DEVONO restare interi per far coincidere lo stato ricaricato con quello vivo, ma che non possono mai rendere
## corrotto un salvataggio (indici, contatori di sola presentazione): si convertono se interi, altrimenti si lasciano.
static func load_bytes(bytes: PackedByteArray, int_paths: PackedStringArray, target: int = SCHEMA_VERSION,
		migs: Dictionary = {}, soft_paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	var dec := decode(bytes)
	if not dec.ok:
		return dec
	var from_version := int(float(dec.data.get("schema_version", target))) if (dec.data.get("schema_version") is int or dec.data.get("schema_version") is float) else target
	var mig := migrate(dec.data, target, migs)
	if not mig.ok:
		return mig
	mig["from_version"] = from_version          # versione di schema trovata nel file (prima della migrazione)
	var errs := normalize(mig.data, int_paths)
	if not errs.is_empty():
		return {"ok": false, "data": {}, "error": "corrupt_types", "paths": errs}
	if not soft_paths.is_empty():
		normalize(mig.data, soft_paths)          # QA120: interi «morbidi»: i float interi tornano int, un valore strano resta com'e' (mai un errore)
	return mig


## Controlla che le sezioni di `data` abbiano la stessa FORMA di `reference` (stato iniziale completo): numero/numero,
## stringa/stringa, booleano/booleano, Dictionary/Dictionary, Array/Array. Si scende nei Dictionary a chiavi note
## (profondita' massima `depth`); i riferimenti null o i Dictionary vuoti (mappe libere) non vincolano oltre.
## Ritorna i percorsi sbagliati (vuoto = forma valida). Le chiavi assenti si ignorano (le completano i sistemi).
static func check_shape(data: Dictionary, shape_ref: Dictionary, depth: int = 3) -> PackedStringArray:
	var errors := PackedStringArray()
	_shape(data, shape_ref, "", depth, errors)
	return errors


static func _shape(node: Dictionary, ref: Dictionary, prefix: String, depth: int, errors: PackedStringArray) -> void:
	for k in ref:
		if not node.has(k):
			continue
		var want: Variant = ref[k]
		var got: Variant = node[k]
		var path := prefix + str(k)
		if want == null:
			continue
		if want is int or want is float:
			if not ((got is int or got is float) and (got is int or is_finite(float(got)))):
				errors.append(path)
		elif want is String:
			if not (got is String):
				errors.append(path)
		elif want is bool:
			if not (got is bool):
				errors.append(path)
		elif want is Array:
			if not (got is Array):
				errors.append(path)
		elif want is Dictionary:
			if not (got is Dictionary):
				errors.append(path)
			elif depth > 1 and not (want as Dictionary).is_empty():
				_shape(got, want, path + ".", depth - 1, errors)


static func _tokens(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in path.split("."):
		var p := part
		var arrays := 0
		while p.ends_with("[]"):
			p = p.substr(0, p.length() - 2)
			arrays += 1
		if not p.is_empty():
			out.append(p)
		for i in arrays:
			out.append("[]")
	return out


static func _normalize_path(node: Variant, toks: PackedStringArray, i: int, path: String, errors: PackedStringArray) -> void:
	var tok := toks[i]
	var last := i == toks.size() - 1
	if tok == "[]":
		if not (node is Array):
			return
		for j in node.size():
			if last:
				_fix_leaf_array(node, j, path, errors)
			else:
				_normalize_path(node[j], toks, i + 1, path, errors)
		return
	if not (node is Dictionary):
		return
	var keys: Array = node.keys() if tok == "*" else ([tok] if node.has(tok) else [])
	for k in keys:
		if last:
			_fix_leaf_dict(node, k, path, errors)
		else:
			_normalize_path(node[k], toks, i + 1, path, errors)


static func _fix_leaf_dict(d: Dictionary, k: Variant, path: String, errors: PackedStringArray) -> void:
	var r: Array = _as_int(d[k])
	if not r[0]:
		errors.append("%s (%s)" % [path, str(k)])
	else:
		d[k] = r[1]


static func _fix_leaf_array(a: Array, j: int, path: String, errors: PackedStringArray) -> void:
	var r: Array = _as_int(a[j])
	if not r[0]:
		errors.append("%s [%d]" % [path, j])
	else:
		a[j] = r[1]


## [ok, valore]: int -> int; float intero e finito -> int; stringa o null -> invariato; altro -> errore.
static func _as_int(v: Variant) -> Array:
	if v is int or v == null:
		return [true, v]
	if v is String:
		# interi enormi salvati come stringa (R-SAV-7): solo cifre (con segno). Un testo qualsiasi in un campo intero è corruzione (QA 83 C-05)
		var t: String = v
		var digits := t.substr(1) if t.begins_with("-") else t
		if digits.is_empty() or not _all_digits(digits):
			return [false, v]
		# gli interi oltre 2^53 scritti come stringa da prepare_for_write (R-SAV-7) tornano int esatti fino al tetto sicuro;
		# le altre stringhe (numeri piccoli, oltre il tetto) restano com'erano: le gestisce il sistema che le legge
		if digits.length() >= 16 and (digits.length() < 19 or (digits.length() == 19 and digits <= str(SAFE_INT_MAX))):
			var iv := t.to_int()
			if iv > EXACT_INT_MAX or iv < -EXACT_INT_MAX:
				return [true, iv]
		return [true, v]
	if v is float:
		var f: float = v
		if is_finite(f) and f == floor(f) and absf(f) <= 9.0e18:
			return [true, int(f)]
	return [false, null]


static func _all_digits(t: String) -> bool:
	for i in t.length():
		var c := t.unicode_at(i)
		if c < 48 or c > 57:
			return false
	return true


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": code}
