class_name LogDigest
extends RefCounted
## Riassume i messaggi ripetuti del registro (GUILD-2): invece di una riga per ogni livello, per ogni cassa persa a
## Deposito pieno o per ogni impresa sbloccata dopo un rientro, MainScreen raccoglie tutto in una finestra breve
## (`social_rules.log_digest.window_s`) e scrive UNA riga per gruppo. Classe pura: nessun nodo, nessun tempo.
##
## Uso: add_level(nome_mansione, livello) / absorb(kind, text, data) -> true se il messaggio è stato assorbito;
## poi, a finestra chiusa, flush() -> [{"kind": String, "section": LogCategory.*, "text": String}] e il digest torna vuoto.
## Le battute variano: le chiavi UI_GUILD2_LVL_ONE_<n>, UI_GUILD2_LVL_MANY_<n>, UI_GUILD2_FULL_ONE_<n> sono una famiglia
## numerata da 1 senza buchi; se ne aggiungono quante si vuole nel CSV, la scelta è stabile (hash di nome+livello).

var _levels: Dictionary = {}         # nome mansione -> [primo livello raggiunto, ultimo, quanti]
var _full: Dictionary = {}           # nome oggetto -> pezzi persi
var _full_first: String = ""         # testo originale del primo messaggio "Deposito pieno"
var _full_total: int = 0
var _groups: Dictionary = {}         # digest -> [{"text", "data"}]
var max_listed: int = 3


func is_empty() -> bool:
	return _levels.is_empty() and _full.is_empty() and _groups.is_empty()


func add_level(skill_name: String, level: int) -> void:
	if not NoticeFilter.category_allowed("levels"):         # notifiche spegnibili per categoria (UI-A G19)
		return
	if _levels.has(skill_name):
		var e: Array = _levels[skill_name]
		e[0] = mini(int(e[0]), level)
		e[1] = maxi(int(e[1]), level)
		e[2] = int(e[2]) + 1
	else:
		_levels[skill_name] = [level, level, 1]


## true se il messaggio è raggruppabile (Deposito pieno, imprese, titoli, doppioni dei famigli).
func absorb(kind: String, text: String, data: Dictionary) -> bool:
	if not NoticeFilter.allows(kind, data):
		return true                       # categoria spenta nelle Impostazioni: assorbito e mai mostrato (UI-A G19)
	if str(data.get("reason", "")) == "bank_full":
		var nm := str(data.get("item", ""))
		if _full.is_empty():
			_full_first = text
		_full[nm] = int(_full.get(nm, 0)) + 1
		_full_total += 1
		return true
	var g := str(data.get("digest", ""))
	if g in ["ach", "title", "pet_dupe", "frame"]:
		if not _groups.has(g):
			_groups[g] = []
		_groups[g].append({"text": text, "data": data})
		return true
	return false


func flush() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_level_lines())
	out.append_array(_full_lines())
	for g in _groups:
		out.append(_group_line(str(g), _groups[g]))
	_levels.clear()
	_full.clear()
	_full_first = ""
	_full_total = 0
	_groups.clear()
	return out


# ------------------------------------------------------------------ livelli

func _level_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _levels.is_empty():
		return out
	if _levels.size() > max_listed:
		var names: PackedStringArray = []
		var total := 0
		for nm in _levels:
			names.append(str(nm))
			total += int(_levels[nm][2])
		out.append({"kind": "level", "section": LogCategory.SKILLS, "text": Loc.tf("UI_GUILD2_LVL_SKILLS", {"n": _levels.size(), "levels": total,
			"names": ", ".join(names.slice(0, max_listed))})})
		return out
	for nm in _levels:
		var e: Array = _levels[nm]
		var count := int(e[2])
		var params := {"skill": str(nm), "n": int(e[1]), "from": int(e[0]), "count": count}
		var fam := "UI_GUILD2_LVL_ONE_" if count == 1 else "UI_GUILD2_LVL_MANY_"
		out.append({"kind": "level", "section": LogCategory.SKILLS, "text": Loc.tf(_pick(fam, "%s%d" % [nm, int(e[1])]), params)})
	return out


# ------------------------------------------------------------------ Deposito pieno

func _full_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _full_total <= 0:
		return out
	if _full_total == 1:
		out.append({"kind": "warning", "section": LogCategory.LOOT, "text": _full_first + " " + TranslationServer.translate("UI_GUILD2_FULL_HINT")})
		return out
	var names: PackedStringArray = []
	var keys := _full.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(_full[a]) > int(_full[b]))
	for k in keys.slice(0, max_listed):
		var nm: String = str(k) if not str(k).is_empty() else str(TranslationServer.translate("UI_GUILD2_FULL_SOMETHING"))
		names.append("%s ×%d" % [nm, int(_full[k])])
	var more := keys.size() - max_listed
	var list := ", ".join(names)
	if more > 0:
		list += " " + Loc.tf("UI_GUILD2_FULL_MORE", {"n": more})
	out.append({"kind": "warning", "section": LogCategory.LOOT, "text": Loc.tf(_pick("UI_GUILD2_FULL_MANY_", str(_full_total)), {"n": _full_total, "list": list})})
	return out


# ------------------------------------------------------------------ gruppi di notifiche

func _group_line(g: String, items: Array) -> Dictionary:
	if items.size() == 1:
		return {"kind": "success", "section": LogCategory.FEATS, "text": str(items[0].text)}
	var names: PackedStringArray = []
	var dust := 0
	for it in items:
		var d: Dictionary = it.data
		dust += int(d.get("dust", 0))
		var nm := ""
		match g:
			"ach":
				nm = Loc.t(DataRegistry.get_def("achievements", str(d.get("ach", ""))).get("name", ""))
			"title":
				nm = Loc.t(DataRegistry.get_def("titles", str(d.get("title", ""))).get("name", ""))
			"frame":
				nm = Loc.t(DataRegistry.get_def("frames", str(d.get("frame", ""))).get("name", ""))
		if not nm.is_empty() and names.size() < max_listed:
			names.append(nm)
	var more := items.size() - names.size()
	var list := ", ".join(names)
	if more > 0 and not names.is_empty():
		list += " " + Loc.tf("UI_GUILD2_FULL_MORE", {"n": more})
	return {"kind": "success", "section": LogCategory.FEATS, "text": Loc.tf("UI_GUILD2_DIGEST_" + g.to_upper(), {"n": items.size(), "list": list, "dust": dust})}


# ------------------------------------------------------------------ varianti

## Sceglie una battuta della famiglia `prefix`1..N (N = ultima chiave presente) in modo stabile per `seed_text`.
func _pick(prefix: String, seed_text: String) -> String:
	var n := 0
	while true:
		var k := "%s%d" % [prefix, n + 1]
		if TranslationServer.translate(k) == k:
			break
		n += 1
	if n <= 0:
		return prefix + "1"
	return "%s%d" % [prefix, 1 + (absi(seed_text.hash()) % n)]
