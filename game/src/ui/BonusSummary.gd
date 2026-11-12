class_name BonusSummary
extends RefCounted
## Pannello «Bonus attivi» (docs/14 §4, UI-A G17, rapporto 112): per ogni bonus il totale, un nome comprensibile e le fonti
## con il loro nome vero, raggruppati per categoria, con «limite raggiunto» quando il tetto del catalogo taglia il totale.
## Classe pura: legge una ModifierStack (quella vera passa da Modifiers.stack) e produce righe di testo; non cambia
## nessun bonus (regola 4: un solo sistema di modificatori). Nomi, descrizioni e categorie vengono dal catalogo dei dati
## (`modifier_catalog`: name/blurb/cat/scope_all, generati da tools/gamedata/modifier_names.py); mai chiavi tecniche a schermo.

## Prefisso della fonte -> chiave del testo (le fonti con un nome proprio nei dati lo mostrano dopo i due punti).
const SOURCE_KEYS := {
	"equip": "UI_UIA_SRC_EQUIP", "wardrobe": "UI_UIA_SRC_WARDROBE", "relic": "UI_UIA_SRC_RELIC", "pet": "UI_UIA_SRC_PET",
	"star": "UI_UIA_SRC_STAR", "constellation": "UI_UIA_SRC_CONSTELLATION", "talents": "UI_UIA_SRC_TALENTS",
	"collection": "UI_UIA_SRC_COLLECTION", "collection_gold": "UI_UIA_SRC_COLLECTION_GOLD", "potion": "UI_UIA_SRC_POTION",
	"buff": "UI_UIA_SRC_BUFF", "event": "UI_UIA_SRC_EVENT", "faction": "UI_UIA_SRC_FACTION", "dungeon": "UI_UIA_SRC_DUNGEON",
	"trial": "UI_UIA_SRC_TRIAL", "trial_active": "UI_BONUS_SRC_TRIAL_ACTIVE", "perk": "UI_UIA_SRC_PERK", "skilltool": "UI_UIA_SRC_TOOL",
	"partners": "UI_UIA_SRC_PARTNERS", "estate": "UI_UIA_SRC_ESTATE", "mode": "UI_UIA_SRC_MODE", "era": "UI_UIA_SRC_ERA",
	"shop": "UI_BONUS_SRC_SHOP", "guild": "UI_BONUS_SRC_GUILD", "run": "UI_BONUS_SRC_RUN", "combat": "UI_BONUS_SRC_COMBAT",
	"prestige": "UI_BONUS_SRC_PRESTIGE", "feast": "UI_BONUS_SRC_FEAST",
}

## Categorie del pannello nell'ordine in cui si mostrano (sono sezioni di LogCategory: colore e sigla in comune).
const CAT_ORDER: PackedStringArray = ["skills", "combat", "loot", "market", "estate", "prestige", "system"]


static func _tr(key: String) -> String:
	return str(TranslationServer.translate(key))


## Nome di una chiave del CSV, oppure "" se la chiave non esiste (la traduzione restituirebbe la chiave stessa).
static func _tr_opt(key: String) -> String:
	var t := _tr(key)
	return "" if t == key else t


static func _def_name(table: String, id: String) -> String:
	var d := DataRegistry.get_def(table, id)
	return Loc.t(d.get("name", "")) if not d.is_empty() else ""


## Nome leggibile di una fonte («Stella: Estrazione», «Evento: Notte delle Lanterne», «Famiglio: Scoiattolo Boscaiolo»).
## Mai l'id grezzo: se un nome manca resta solo il tipo di fonte.
static func source_label(source_id: String) -> String:
	var parts := source_id.split(":", true, 1)
	var head := parts[0]
	var rest := parts[1] if parts.size() > 1 else ""
	if source_id == "prestige:partners":
		return _tr("UI_UIA_SRC_PARTNERS")
	if source_id == "mode:cozy":
		return _tr("UI_UIB_SET_COZY_TITLE")
	if source_id == "buff:feast":
		return _tr("UI_BONUS_SRC_FEAST")
	var base := _tr(str(SOURCE_KEYS[head])) if SOURCE_KEYS.has(head) else _tr("UI_BONUS_SRC_OTHER")
	var detail := _detail(head, rest)
	return base if detail.is_empty() else "%s: %s" % [base, detail]


static func _slot_name(slot: String) -> String:
	return _tr_opt("UI_HERO_SLOT_" + slot.to_upper())


static func _detail(head: String, rest: String) -> String:
	if rest.is_empty():
		return ""
	match head:
		"star", "perk", "skilltool", "potion":
			return _def_name("skills", rest)
		"pet":
			return _def_name("pets", rest)
		"equip":
			var cs := Game.system("combat") as CombatSystem if GameState.active else null
			var worn := DataRegistry.item(cs.equipped(rest)) if cs != null else {}
			return Loc.t(worn.get("name", "")) if not worn.is_empty() else _slot_name(rest)       # il pezzo indossato, se c'è
		"wardrobe":
			return _slot_name(rest)
		"collection", "collection_gold":
			return _def_name("collections", rest)
		"faction":
			return _def_name("factions", rest)
		"dungeon":
			return _def_name("dungeons", rest)
		"event":
			return _def_name("events", rest)
		"trial":
			return _def_name("trials", rest)
		"shop":
			return _def_name("shop", rest)
		"guild":
			for p in DataRegistry.rules("coop_net_rules").get("projects", []):
				if str(p.id) == rest:
					return Loc.t(p.name)
			return ""
		"buff":
			return _tr("UI_BONUS_SRC_FEAST") if rest == "feast" else ""
		"relic":
			var cr := Game.system("crates") as CrateSystem if GameState.active else null
			var inst: Dictionary = cr.instance(rest) if cr != null else {}
			var def_id := str(inst.get("def", inst.get("def_id", "")))
			var it := DataRegistry.item(def_id)
			return Loc.t(it.get("name", "")) if not it.is_empty() else ""
	return ""


static func _catalog() -> Dictionary:
	var out: Dictionary = {}
	for f in DataRegistry.table("modifier_catalog"):
		out[str(f.family)] = f
	return out


## Definizione di catalogo di una famiglia di bonus ({} se sconosciuta).
static func family_def(family: String) -> Dictionary:
	return _catalog().get(family, {})


## Nome breve di un bonus con il suo ambito («Velocità: Taglialegna») dalla chiave del modificatore ("famiglia:ambito").
## QA119: sostituisce `desc` del catalogo (descrizione tecnica con formule e tetti) nei testi per il giocatore.
static func key_title(key: String) -> String:
	var kp := key.split(":")
	var cd := family_def(kp[0])
	if cd.is_empty():
		var fam: Dictionary = DataRegistry.modifier_family(kp[0])
		return Loc.t(fam.get("desc", {})) if not fam.is_empty() else key
	return title_of(cd, kp[1] if kp.size() > 1 else "")


## «Velocità: Taglialegna +4%»: nome breve e valore con l'unità giusta.
static func effect_text(m: Dictionary) -> String:
	var cd := family_def(str(m.key).split(":")[0])
	return "%s %s" % [key_title(str(m.key)), fmt_value(str(cd.get("unit", "pct")), float(m.value))]


## Valore di un bonus in testo, secondo l'unità della famiglia del catalogo.
static func fmt_value(unit: String, v: float) -> String:
	match unit:
		"abs":
			return "%s%s" % ["+" if v >= 0.0 else "", NumberFormat.decimal(v, 0 if is_equal_approx(v, roundf(v)) else 1, Loc.locale())]
		"flag":
			return TranslationServer.translate("UI_UIA_BONUS_ON")
	return "%s%s%%" % ["+" if v >= 0.0 else "", NumberFormat.decimal(v, 0 if is_equal_approx(v, roundf(v)) else 1, Loc.locale())]


static func fmt_more(m: float) -> String:
	return "×" + NumberFormat.decimal(m, 2, Loc.locale())


## Nome dell'ambito di un bonus («Cucina», «tutte le Casse», «fuoco»). "" se la famiglia non ha ambiti.
static func scope_label(cd: Dictionary, scope: String) -> String:
	if cd.is_empty() or cd.get("scopes") == null:
		return ""
	if scope.is_empty() or scope == "all":
		return Loc.t(cd.get("scope_all", ""))
	var n := _def_name("skills", scope)
	if n.is_empty():
		n = _def_name("dungeons", scope)
	if n.is_empty():
		n = _tr_opt("UI_BONUS_SCOPE_" + scope.to_upper())
	return n


## Nome intero di un bonus: «Qualità: Cucina». Per i bonus senza ambito è solo il nome della famiglia.
static func title_of(cd: Dictionary, scope: String) -> String:
	if cd.is_empty():
		return _tr("UI_BONUS_UNKNOWN")
	var nm := Loc.t(cd.get("name", ""))
	var sc := scope_label(cd, scope)
	return nm if sc.is_empty() else "%s: %s" % [nm, sc]


static func category_label(cat: String) -> String:
	return _tr("UI_BONUS_CAT_" + cat.to_upper())


## Righe del pannello. Ogni riga: {"key", "family", "cat", "title", "name", "scope", "blurb", "total": testo grande,
## "capped": bool (tetto raggiunto), "cap_text": valore del tetto, "cap_ratio": 0..1, "cap_note": frase sul tetto,
## "has_more": bool, "sources": [{"source", "label", "text", "more": bool}]}. Ordinate per categoria e titolo.
## `filter` cerca (senza maiuscole) nel titolo, nella descrizione, nelle fonti e nel nome della categoria.
static func rows(stack: ModifierStack, filter: String = "") -> Array:
	var cat := _catalog()
	var by_key: Dictionary = {}
	for sid in stack.source_ids():
		for m in stack.get_source(str(sid)):
			var key := str(m.key)
			var fam0 := key.get_slice(":", 0)
			if key == fam0 and cat.get(fam0, {}).get("scopes") != null:
				key = fam0 + ":all"                  # «famiglia» e «famiglia:all» sono lo stesso bonus
			if not by_key.has(key):
				by_key[key] = []
			by_key[key].append({"source": str(sid), "value": float(m.value), "mode": str(m.mode)})
	var out: Array = []
	var q := filter.strip_edges().to_lower()
	for key in by_key:
		var fam := str(key).get_slice(":", 0)
		var scope := str(key).get_slice(":", 1) if str(key).contains(":") else ""
		var cd: Dictionary = cat.get(fam, {})
		var unit := str(cd.get("unit", "pct"))
		var add := 0.0
		var more := 1.0
		var srcs: Array = []
		for e in by_key[key]:
			var is_more: bool = e.mode == ModifierStack.MODE_MORE
			if is_more:
				more *= 1.0 + float(e.value) / 100.0
			else:
				add += float(e.value)
			srcs.append({"source": e.source, "label": source_label(e.source), "value": absf(float(e.value)), "more": is_more,
				"text": fmt_more(1.0 + float(e.value) / 100.0) if is_more else fmt_value(unit, float(e.value))})
		srcs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.value) > float(b.value) or (is_equal_approx(float(a.value), float(b.value)) and str(a.label) < str(b.label)))
		var cap := stack.cap_of(str(key))
		var has_cap := is_finite(cap) and unit != "flag"
		var reached := has_cap and add >= cap - 0.0001 and add > 0.0
		var shown := minf(add, cap) if has_cap else add
		var total := fmt_value(unit, shown) if (add != 0.0 or more == 1.0) else ""
		if more != 1.0:
			total += ("  " if not total.is_empty() else "") + fmt_more(more)
		var title := title_of(cd, scope)
		var blurb := Loc.t(cd.get("blurb", ""))
		var cat_id := str(cd.get("cat", "system"))
		if not q.is_empty():
			var blob := "%s %s %s" % [title, blurb, category_label(cat_id)]
			for s in srcs:
				blob += " " + str(s.label)
			if not blob.to_lower().contains(q):
				continue
		var cap_text := fmt_value(unit, cap) if has_cap else ""
		var cap_note := ""
		var ratio := 0.0
		if has_cap:
			ratio = clampf(shown / cap, 0.0, 1.0) if cap > 0.0 else 1.0
			cap_note = Loc.tf("UI_BONUS_CAP_USING", {"cap": cap_text, "pct": int(roundf(ratio * 100.0))})
			if add > cap + 0.0001:
				cap_note += " " + Loc.tf("UI_BONUS_CAP_OVER", {"have": fmt_value(unit, add)})
		out.append({"key": str(key), "family": fam, "cat": cat_id, "title": title, "name": Loc.t(cd.get("name", "")),
			"scope": scope_label(cd, scope), "blurb": blurb, "total": total, "capped": reached, "cap_text": cap_text,
			"cap_ratio": ratio, "cap_note": cap_note, "has_more": more != 1.0, "sources": srcs})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := CAT_ORDER.find(str(a.cat))
		var cb := CAT_ORDER.find(str(b.cat))
		if ca != cb:
			return ca < cb
		return str(a.title) < str(b.title))
	return out


## Quanti bonus diversi sono attivi (per il numero sul pulsante «Bonus attivi»): lo stesso numero che mostra il pannello.
static func count(stack: ModifierStack) -> int:
	return rows(stack).size()


## Righe raggruppate per categoria: [{"cat", "label", "tag", "color": Color, "rows": [...]}] nell'ordine di CAT_ORDER.
static func groups(p_rows: Array) -> Array:
	var out: Array = []
	for c in CAT_ORDER:
		var list: Array = []
		for r in p_rows:
			if str(r.cat) == c:
				list.append(r)
		if not list.is_empty():
			out.append({"cat": c, "label": category_label(c), "tag": LogCategory.tag(c), "color": LogCategory.color(c), "rows": list})
	return out


## Testo di tutte le parti visibili di una riga (per il test «nessuna chiave tecnica»).
static func visible_text(r: Dictionary) -> String:
	var s := "%s %s %s %s" % [r.title, r.blurb, r.total, r.cap_note]
	for x in r.sources:
		s += " %s %s" % [x.label, x.text]
	return s
