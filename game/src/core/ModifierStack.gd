class_name ModifierStack
extends RefCounted
## Registro unico dei modificatori (docs/14 §4). Classe pura: l'autoload Modifiers ne possiede una istanza,
## i test e i simulatori possono crearne altre.
##
## Regola di cumulo (docs/14 §2):  finale = base × (1 + Σadd/100) × Π(1 + more_i/100)
## Chiave: "famiglia" oppure "famiglia:ambito". Una lettura con ambiti ["mining","gathering","all"] somma
## la famiglia nuda + ogni "famiglia:ambito" richiesto.
## Ogni fonte ("equip:weapon", "pet:pet_skill_mining", "star:mining", ...) registra il PROPRIO blocco intero:
## quando la fonte cambia si richiama set_source con il nuovo blocco (sostituzione, mai somma).

signal changed

const MODE_ADD := "add"
const MODE_MORE := "more"

var _sources: Dictionary = {}       # source_id -> Array[{key, value, mode}]
var _by_key: Dictionary = {}        # key completa -> Array[[source_id, value, mode]]
var _cache: Dictionary = {}         # "key|scope,scope" -> [add, more]
var _caps: Dictionary = {}          # famiglia -> cap (float)
var _families: Dictionary = {}      # famiglia -> true (se il catalogo è impostato: R-MOD-1)
var unknown_keys: PackedStringArray = []


## Catalogo ufficiale (data/modifier_catalog.json): abilita i cap e il controllo delle famiglie.
func set_catalog(catalog: Array) -> void:
	_caps.clear()
	_families.clear()
	for f in catalog:
		_families[f.family] = true
		if f.get("cap") != null:
			_caps[f.family] = float(f.cap)


## Sostituisce TUTTO il blocco di una fonte. mods: Array di {"key": String, "value": float, "mode": "add"|"more"}.
## Ritorna false (e ignora le voci) se una chiave non è nel catalogo o il modo non è valido.
func set_source(source_id: String, mods: Array) -> bool:
	var ok := true
	var clean: Array = []
	for m in mods:
		var key: String = m.get("key", "")
		var mode: String = m.get("mode", MODE_ADD)
		if key.is_empty() or (mode != MODE_ADD and mode != MODE_MORE):
			ok = false
			continue
		if not _families.is_empty() and not _families.has(key.split(":")[0]):
			unknown_keys.append(key)
			push_warning("Modifiers: chiave %s non presente nel catalogo (fonte %s)" % [key, source_id])
			ok = false
			continue
		clean.append({"key": key, "value": float(m.get("value", 0.0)), "mode": mode})
	# stessa fonte con gli stessi valori (es. CombatSystem riallinea l'equipaggiamento ogni secondo): nessun
	# ricalcolo e nessun segnale "changed" (svuoterebbe le cache di mansioni e combattimento a vuoto)
	if (clean.is_empty() and not _sources.has(source_id)) or (_sources.has(source_id) and _sources[source_id] == clean):
		return ok
	_remove(source_id)
	if not clean.is_empty():
		_sources[source_id] = clean
		for m in clean:
			if not _by_key.has(m.key):
				_by_key[m.key] = []
			_by_key[m.key].append([source_id, m.value, m.mode])
	_invalidate()
	return ok


func clear_source(source_id: String) -> void:
	if _sources.has(source_id):
		_remove(source_id)
		_invalidate()


## Rimuove tutte le fonti il cui id inizia con il prefisso (es. "equip:" quando si cambia set).
func clear_prefix(prefix: String) -> void:
	var removed := false
	for sid in _sources.keys():
		if String(sid).begins_with(prefix):
			_remove(sid)
			removed = true
	if removed:
		_invalidate()


func clear_all() -> void:
	_sources.clear()
	_by_key.clear()
	_invalidate()


func has_source(source_id: String) -> bool:
	return _sources.has(source_id)


func source_ids() -> PackedStringArray:
	return PackedStringArray(_sources.keys())


func get_source(source_id: String) -> Array:
	return _sources.get(source_id, [])


## Somma degli add (punti percentuali) su famiglia nuda + ambiti.
func total_add(key: String, scopes: Array = []) -> float:
	return _totals(key, scopes)[0]


## Prodotto dei more come MOLTIPLICATORE (1.0 = nessun bonus; 1.21 = +21%).
func total_more(key: String, scopes: Array = []) -> float:
	return _totals(key, scopes)[1]


## Valore finale secondo la regola add/more.
func apply(base: float, key: String, scopes: Array = []) -> float:
	var t := _totals(key, scopes)
	return base * (1.0 + t[0] / 100.0) * t[1]


## Moltiplicatore complessivo (1 + add/100) × more.
func multiplier(key: String, scopes: Array = []) -> float:
	var t := _totals(key, scopes)
	return (1.0 + t[0] / 100.0) * t[1]


## Cap del catalogo per la famiglia (INF se non c'è).
func cap_of(key: String) -> float:
	return _caps.get(key.split(":")[0], INF)


## total_add limitato al cap del catalogo (per le famiglie con cap: skill_save_pct, crate_find_pct, ...).
func total_add_capped(key: String, scopes: Array = []) -> float:
	return minf(total_add(key, scopes), cap_of(key))


func is_capped(key: String, scopes: Array = []) -> bool:
	return total_add(key, scopes) > cap_of(key)


## Per il pannello "Bonus attivi": [{source, key, value, mode}] di tutte le voci che contribuiscono.
func contributions(key: String, scopes: Array = []) -> Array:
	var out: Array = []
	for full in _keys_for(key, scopes):
		for e in _by_key.get(full, []):
			out.append({"source": e[0], "key": full, "value": e[1], "mode": e[2]})
	return out


## Stato serializzabile (solo per diagnostica: le fonti si ricostruiscono dai sistemi dopo il load).
func to_dict() -> Dictionary:
	return _sources.duplicate(true)


# ------------------------------------------------------------------ interni

func _keys_for(key: String, scopes: Array) -> PackedStringArray:
	var fam := key.split(":")[0]
	var keys := PackedStringArray([key])
	if key != fam:
		keys.append(fam)
	for s in scopes:
		var k := "%s:%s" % [fam, s]
		if not keys.has(k):
			keys.append(k)
	return keys


func _totals(key: String, scopes: Array) -> Array:
	var ck := key + "|" + ",".join(PackedStringArray(scopes))
	var hit: Variant = _cache.get(ck)
	if hit != null:
		return hit
	var add := 0.0
	var more := 1.0
	for full in _keys_for(key, scopes):
		for e in _by_key.get(full, []):
			if e[2] == MODE_MORE:
				more *= 1.0 + e[1] / 100.0
			else:
				add += e[1]
	var res := [add, more]
	_cache[ck] = res
	return res


func _remove(source_id: String) -> void:
	var old: Array = _sources.get(source_id, [])
	for m in old:
		var lst: Array = _by_key.get(m.key, [])
		for i in range(lst.size() - 1, -1, -1):
			if lst[i][0] == source_id:
				lst.remove_at(i)
		if lst.is_empty():
			_by_key.erase(m.key)
	_sources.erase(source_id)


func _invalidate() -> void:
	_cache.clear()
	changed.emit()
