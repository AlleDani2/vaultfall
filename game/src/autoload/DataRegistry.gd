extends Node
## DataRegistry (autoload) — docs/17 §3 ("GameData"). Carica TUTTI i JSON di res://data/ all'avvio,
## costruisce indici per id ed espone getter tipizzati. SOLA LETTURA: nessuno modifica i dizionari restituiti
## (sono condivisi; se serve una copia usare .duplicate(true)).
##
## Uso tipico (da sistemi e UI):
##   DataRegistry.constants.xp.base           # constants.json
##   DataRegistry.item("log_pine")            # qualunque oggetto di items/*.json
##   DataRegistry.action("mine_copper")       # qualunque azione di actions/*.json
##   DataRegistry.actions_for_skill("mining") # Array ordinato come nel file
##   DataRegistry.get_def("monsters", "mud_slime")
##   DataRegistry.table("zones")              # Array grezzo del file zones.json
##   DataRegistry.rules("crate_rules")        # file "regole" con un solo record
##   DataRegistry.modifier_family("skill_xp_pct")

const DATA_DIR := "res://data"

## Tabelle senza campo "id": campo usato come chiave dell'indice. Se più record hanno la stessa chiave
## (es. skill_perks: più righe per mansione) l'indice by_key contiene un Array.
const KEY_FIELD := {"modifier_catalog": "family", "skill_perks": "skill", "skill_prestige": "skill"}

signal loaded

var constants: Dictionary = {}
var xp_table: Dictionary = {}
var manifest: Dictionary = {}
var load_ms: float = 0.0
var errors: PackedStringArray = []

var _tables: Dictionary = {}        # nome -> Array (contenuto del file)
var _index: Dictionary = {}         # nome -> {id -> record}
var _grouped: Dictionary = {}       # nome -> {chiave -> Array di record} (tabelle di KEY_FIELD)
var _items: Dictionary = {}
var _actions: Dictionary = {}
var _actions_by_skill: Dictionary = {}
var _items_by_category: Dictionary = {}
var _loaded := false


func _ready() -> void:
	load_all()


func is_loaded() -> bool:
	return _loaded


## Carica (o ricarica) tutti i file. Ritorna true se non ci sono errori di lettura.
func load_all(dir: String = DATA_DIR) -> bool:
	var t0 := Time.get_ticks_usec()
	_reset()
	if not DirAccess.dir_exists_absolute(dir):
		errors.append("cartella dati mancante: %s (lanciare python tools/sync_data.py)" % dir)
		push_error(errors[-1])
		return false
	for f in _list_json(dir):
		var rel: String = f.substr(dir.length() + 1)
		var v: Variant = _read_json(f)
		if v == null:
			continue
		var tname := rel.get_basename()
		if rel.begins_with("items/"):
			for it in v:
				_items[it.id] = it
				var cat: String = it.get("category", "")
				if not _items_by_category.has(cat):
					_items_by_category[cat] = []
				_items_by_category[cat].append(it)
		elif rel.begins_with("actions/"):
			var skill := tname.get_file()
			_actions_by_skill[skill] = v
			for a in v:
				_actions[a.id] = a
		elif tname == "constants":
			constants = v
		elif tname == "xp_table":
			xp_table = v
		elif tname == "manifest":
			manifest = v
		else:
			_tables[tname] = v
			_build_index(tname, v)
	Formulas.configure(constants, _formula_extras())
	load_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_loaded = errors.is_empty()
	if OS.is_debug_build():
		var ref_errors := validate_references()
		for e in ref_errors.slice(0, 20):
			push_warning("DataRegistry: " + e)
	loaded.emit()
	return _loaded


# ------------------------------------------------------------------ getter

func item(id: String) -> Dictionary:
	return _items.get(id, {})


func has_item(id: String) -> bool:
	return _items.has(id)


func items_by_category(category: String) -> Array:
	return _items_by_category.get(category, [])


func all_items() -> Dictionary:
	return _items


func action(id: String) -> Dictionary:
	return _actions.get(id, {})


func has_action(id: String) -> bool:
	return _actions.has(id)


func actions_for_skill(skill: String) -> Array:
	return _actions_by_skill.get(skill, [])


func all_actions() -> Dictionary:
	return _actions


func skill_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in table("skills"):
		out.append(s.id)
	return out


## Array grezzo di una tabella (nome del file senza .json, es. "zones", "monsters").
func table(tname: String) -> Array:
	return _tables.get(tname, [])


func has_table(tname: String) -> bool:
	return _tables.has(tname)


func table_names() -> PackedStringArray:
	return PackedStringArray(_tables.keys())


## Record per id in una tabella (anche "items" e "actions"). {} se non esiste.
func get_def(table_name: String, id: String) -> Dictionary:
	if table_name == "items":
		return item(id)
	if table_name == "actions":
		return action(id)
	return _index.get(table_name, {}).get(id, {})


func has_def(table_name: String, id: String) -> bool:
	return not get_def(table_name, id).is_empty()


## Record raggruppati per chiave per le tabelle senza id (KEY_FIELD), es. grouped("skill_perks", "mining").
func grouped(table_name: String, key: String) -> Array:
	return _grouped.get(table_name, {}).get(key, [])


## File di "regole" con un solo record (crate_rules, estate_rules, market_rules, ...).
func rules(table_name: String) -> Dictionary:
	var t := table(table_name)
	return t[0] if t.size() > 0 else {}


func modifier_family(family: String) -> Dictionary:
	return _index.get("modifier_catalog", {}).get(family, {})


## Valore di constants.json per percorso puntato ("combat.hit_base"); default se assente.
func const_value(path: String, default: Variant = null) -> Variant:
	var cur: Variant = constants
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


# ------------------------------------------------------------------ validazione (debug, T-1.1)

## Controlli principali di validate_data.py sui riferimenti incrociati. Ritorna l'elenco degli errori.
func validate_references() -> PackedStringArray:
	var out := PackedStringArray()
	var skills := {}
	for s in table("skills"):
		skills[s.id] = true
	for a in _actions.values():
		if not skills.has(a.get("skill", "")):
			out.append("azione %s: mansione %s inesistente" % [a.id, a.get("skill", "")])
		for sect in ["inputs", "outputs"]:
			for io in a.get(sect, []):
				if io is Dictionary and io.has("item") and not _items.has(io.item):
					out.append("azione %s: oggetto %s inesistente (%s)" % [a.id, io.item, sect])
		for sec in a.get("secondary", []):
			for p in sec.get("pick", []):
				if not _items.has(p.get("item", "")):
					out.append("azione %s: drop secondario %s inesistente" % [a.id, p.get("item", "")])
		var cr: Variant = a.get("crate")
		if cr is Dictionary and not _items.has(cr.get("id", "")):
			out.append("azione %s: cassa %s inesistente" % [a.id, cr.get("id", "")])
	for m in table("monsters"):
		var zone: Variant = m.get("zone")
		if zone is String and not has_def("zones", zone):
			out.append("mostro %s: zona %s inesistente" % [m.id, zone])
		var dt: Variant = m.get("drop_table")
		if dt is String and not has_def("drop_tables", dt):
			out.append("mostro %s: tabella %s inesistente" % [m.id, dt])
	for z in table("zones"):
		for mid in z.get("monsters", []):
			if not has_def("monsters", mid):
				out.append("zona %s: mostro %s inesistente" % [z.id, mid])
	for d in table("drop_tables"):
		for e in d.get("entries", []) + d.get("always", []):
			if not (e is Dictionary) or not e.has("item"):
				continue
			if e.get("pet", false):
				if not has_def("pets", e.item):
					out.append("drop %s: famiglio %s inesistente" % [d.id, e.item])
			elif not _items.has(e.item):
				out.append("drop %s: oggetto %s inesistente" % [d.id, e.item])
	# R-MOD-1: ogni chiave di modificatore usata nei dati esiste nel catalogo
	var fams: Dictionary = _index.get("modifier_catalog", {})
	if not fams.is_empty():
		var seen := {}
		for tname in _tables:
			_collect_modifier_keys(_tables[tname], seen)
		for it in _items.values():
			_collect_modifier_keys(it, seen)
		for key in seen:
			var fam: String = String(key).split(":")[0]
			if not fams.has(fam):
				out.append("modificatore %s: famiglia %s assente dal catalogo" % [key, fam])
	return out


func _collect_modifier_keys(o: Variant, seen: Dictionary) -> void:
	if o is Dictionary:
		for k in o:
			var v: Variant = o[k]
			if (k == "modifiers" or k == "modifier_per_level") and v is Array:
				for m in v:
					if m is Dictionary and m.get("key") is String:
						seen[m.key] = true
			elif k == "modifier_per_level" and v is Dictionary and v.get("key") is String:
				seen[v.key] = true
			else:
				_collect_modifier_keys(v, seen)
	elif o is Array:
		for v in o:
			_collect_modifier_keys(v, seen)


# ------------------------------------------------------------------ interni

func _reset() -> void:
	constants = {}
	xp_table = {}
	manifest = {}
	errors = PackedStringArray()
	_tables.clear()
	_index.clear()
	_grouped.clear()
	_items.clear()
	_actions.clear()
	_actions_by_skill.clear()
	_items_by_category.clear()
	_loaded = false


func _build_index(tname: String, v: Variant) -> void:
	if not (v is Array):
		return
	var idx := {}
	var grp := {}
	var key_field: String = KEY_FIELD.get(tname, "id")
	for rec in v:
		if not (rec is Dictionary) or not rec.has(key_field):
			continue
		var key: String = str(rec[key_field])
		if idx.has(key) and key_field == "id":
			errors.append("%s: id duplicato %s" % [tname, key])
		if not idx.has(key):
			idx[key] = rec
		if not grp.has(key):
			grp[key] = []
		grp[key].append(rec)
	_index[tname] = idx
	if KEY_FIELD.has(tname):
		_grouped[tname] = grp


## Extra per Formulas presi da altri file di dati (hanno la precedenza su Formulas.PENDING_CONSTANTS).
func _formula_extras() -> Dictionary:
	var ex := {}
	var key_tiers := {}
	for it in items_by_category("key"):
		if it.has("key_tier") and it.has("tier"):
			key_tiers[str(int(it.key_tier))] = int(it.tier)
	if not key_tiers.is_empty():
		ex["crates"] = {"key_econ_tier": key_tiers}
	var er := rules("estate_rules")
	if er.has("milestone_mult"):
		ex["estate"] = {"milestone_mult": er.milestone_mult}
	return ex


func _list_json(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_list_json(dir + "/" + sub))
	out.sort()
	return out


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("file vuoto o illeggibile: " + path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: JSON non valido (riga %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
