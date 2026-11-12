class_name ManualPages
extends RefCounted
## Pagine del Manuale (docs/16 §3.8), GENERATE dai dati (constants.json e tabelle) tramite Formulas: non vanno
## mai fuori sincronia. Funzioni pure: restituiscono testo BBCode già tradotto.

const PAGES: PackedStringArray = ManualCatalog.PAGES
const GLOSSARY_COUNT := 10
const HEADER_COLOR := "#d8c690"


static func page_title_key(page: String) -> String:
	return ManualCatalog.title_key(page)


static func build(page: String, data: Object, unlocks: Array) -> String:
	match page:
		"start":
			return _guide("start", data)
		"formulas":
			return _formulas(data)
		"crates":
			return _guide("crates", data, _crates_odds(data))
		"drops":
			return _drops(data, unlocks)
		"unlocks":
			return _unlocks(data, unlocks)
		"glossary":
			return _glossary()
	if ManualCatalog.has_page(page):
		return _guide(page, data)
	return ""


## Una chiave di testo esiste (tr() rende la chiave stessa se manca).
static func _has(key: String) -> bool:
	return str(TranslationServer.translate(key)) != key


static func _section(key: String) -> String:
	return "\n[color=%s][b]%s[/b][/color]\n" % [HEADER_COLOR, _tr(key)]


## Pagina strutturata (docs/16 §3.8): a cosa serve, come si usa, [parte generata extra], i numeri dai dati,
## consigli, da non fare, battuta. `middle` è un blocco già pronto (es. le probabilità delle Casse) dopo i passi.
static func _guide(page: String, data: Object, middle: String = "") -> String:
	var u := page.to_upper()
	var out := _title(ManualCatalog.title_key(page))
	out += _section("UI_MAN2_H_WHAT") + _tr("UI_MAN2_%s_WHAT" % u) + "\n"
	out += _section("UI_MAN2_H_HOW")
	var i := 1
	while _has("UI_MAN2_%s_HOW_%d" % [u, i]):
		out += "%d. %s\n" % [i, _tr("UI_MAN2_%s_HOW_%d" % [u, i])]
		i += 1
	if not middle.is_empty():
		out += "\n" + middle
	var facts: Array[Dictionary] = ManualFacts.params(page, data)
	if not facts.is_empty():
		out += _section("UI_MAN2_H_FACTS")
		for n in facts.size():
			out += "• " + Loc.tf("UI_MAN2_%s_F_%d" % [u, n + 1], facts[n]) + "\n"
	out += _section("UI_MAN2_H_TIPS") + _tr("UI_MAN2_%s_TIPS" % u) + "\n"
	out += _section("UI_MAN2_H_DONT") + _tr("UI_MAN2_%s_DONT" % u) + "\n"
	out += "\n[i]%s[/i]\n" % _tr("UI_MAN2_%s_JOKE" % u)
	return out


static func _n(x: float, decimals: int = 1) -> String:
	return NumberFormat.decimal(x, decimals, Loc.locale())


static func _tr(key: String) -> String:
	return str(TranslationServer.translate(key))


static func _title(key: String) -> String:
	return "[font_size=24][color=#c9a45c]%s[/color][/font_size]\n" % _tr(key)


static func _formulas(data: Object) -> String:
	var k: Dictionary = data.constants
	var out := _title("UI_QUESTS_MAN_P_FORMULAS")
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_XP", {"base": _n(float(k.xp.base), 0), "growth": _n(float(k.xp.growth), 2),
		"l": 10, "l2": 11, "xp": NumberFormat.fmt(Formulas.xp_to_next(10))}) + "\n"
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_MASTERY", {"cap": int(k.mastery.cap), "base": _n(float(k.mastery.base), 0),
		"growth": _n(float(k.mastery.growth), 2), "xp": NumberFormat.fmt(Formulas.mastery_to_next(10))}) + "\n"
	var c: Dictionary = k.combat
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_HIT", {"base": _n(float(c.hit_base), 2), "min": _n(float(c.hit_min) * 100.0, 0),
		"max": _n(float(c.hit_max) * 100.0, 0), "ex": _n(Formulas.hit_chance(100.0, 80.0) * 100.0, 1)}) + "\n"
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_DR", {"cap": _n(float(c.dr_cap) * 100.0, 0), "a": _n(float(c.dr_k.a), 0),
		"r": _n(float(c.dr_k.r), 4), "ex": _n(Formulas.damage_reduction(200.0, 10.0) * 100.0, 1)}) + "\n"
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_TRIANGLE", {"adv": _n(float(c.triangle.advantage), 2), "dis": _n(float(c.triangle.disadvantage), 2)}) + "\n"
	var s: Dictionary = k.stars
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_STARS", {"xpcap": _n(float(s.xp_cap_pct), 0), "xpdecay": _n(float(s.xp_decay), 2),
		"hcap": _n(float(s.haste_cap_pct), 0), "hdecay": _n(float(s.haste_decay), 2),
		"ex1": _n(Formulas.star_xp_pct(3), 1), "ex2": _n(Formulas.star_haste_pct(3), 1)}) + "\n"
	var o: Dictionary = k.offline
	out += "\n" + Loc.tf("UI_QUESTS_MAN_F_OFFLINE", {"base": int(o.cap_base_h), "max": int(o.cap_max_h), "eff": int(o.efficiency_pct)}) + "\n"
	return out


## Blocco delle probabilità delle Casse (dai dati), senza titolo: sta dentro la pagina strutturata.
static func _crates_odds(data: Object) -> String:
	var out := ""
	var crates: Array = data.items_by_category("crate")
	if crates.is_empty():
		return out + "\n" + _tr("UI_QUESTS_MAN_C_NONE") + "\n"
	var k: Dictionary = data.constants.crates
	out += "\n" + _tr("UI_QUESTS_MAN_C_INTRO") + "\n\n"
	var eff := Formulas.effective_rarity_pct()
	for r in k.rarities:
		var rid := str(r[0])
		out += "[color=%s]%s[/color]\n" % [str(r[2]) if r.size() > 2 and str(r[2]).begins_with("#") else "#ffffff",
			Loc.tf("UI_QUESTS_MAN_C_RARITY", {"name": _tr("UI_RARITY_" + rid.to_upper()) + " " + str(r[3]) if r.size() > 3 else rid,
			"nominal": _n(float(r[1]), 2), "eff": _n(float(eff.get(rid, r[1])), 2)})]
	var p: Dictionary = k.pity
	out += "\n" + Loc.tf("UI_QUESTS_MAN_C_PITY", {"soft": int(p.soft_start), "step": _n(float(p.soft_step) * 100.0, 2),
		"hard": int(p.hard), "mean": _n(Formulas.relic_pity_mean_openings(), 0)}) + "\n"
	out += "\n" + _tr("UI_QUESTS_MAN_C_CONDITIONS") + "\n"
	for cond in data.rules("crate_rules").get("conditions", []):
		out += Loc.tf("UI_QUESTS_MAN_C_COND", {"name": Loc.t(cond.get("name", cond.id)), "pct": _n(float(cond.weight_pct), 1),
			"a": _n(float(cond.float_min), 2), "b": _n(float(cond.float_max), 2), "bonus": _n(float(cond.bonus_mult), 2)}) + "\n"
	out += "\n"
	for cr in crates:
		var cd: Dictionary = cr.get("crate", {})
		var key_item: Dictionary = data.item(str(cd.get("key", "")))
		out += Loc.tf("UI_QUESTS_MAN_C_CRATE", {"name": Loc.t(cr.name), "key": Loc.t(key_item.get("name", cd.get("key", "-"))),
			"skins": (cd.get("skins", []) as Array).size(), "relics": (cd.get("relic_pool", []) as Array).size()}) + "\n"
	return out


static func _drops(data: Object, unlocks: Array) -> String:
	var out := _title("UI_QUESTS_MAN_P_DROPS")
	out += "\n" + _tr("UI_QUESTS_MAN_D_INTRO") + "\n"
	var any := false
	for z in data.table("zones"):
		if not unlocks.has("zone:" + str(z.id)):
			continue
		any = true
		out += "\n[b]%s[/b]\n" % Loc.t(z.name)
		for mid in z.get("monsters", []):
			var m: Dictionary = data.get_def("monsters", str(mid))
			if m.is_empty():
				continue
			var g: Array = m.get("gold", [0, 0])
			out += Loc.tf("UI_QUESTS_MAN_D_MONSTER", {"name": Loc.t(m.name), "lv": int(m.get("level", 1)),
				"g1": int(g[0]) if g.size() > 0 else 0, "g2": int(g[1]) if g.size() > 1 else 0}) + "\n"
			var dt: Dictionary = data.get_def("drop_tables", str(m.get("drop_table", "")))
			for e in dt.get("always", []) + dt.get("entries", []):
				if not (e is Dictionary) or not e.has("item"):
					continue
				var q: Variant = e.get("qty", 1)
				var qtxt := "%d-%d" % [int(q[0]), int(q[1])] if q is Array and q.size() > 1 else str(q)
				var iname := Loc.t(data.item(str(e.item)).get("name", e.item))
				out += "   " + Loc.tf("UI_QUESTS_MAN_D_DROP", {"name": iname, "pct": _n(float(e.get("chance", 1.0)) * 100.0, 2), "q": qtxt}) + "\n"
			var cr: Variant = dt.get("crate")
			if cr is Dictionary and cr.get("id") != null:
				out += "   " + Loc.tf("UI_QUESTS_MAN_D_CRATE", {"name": Loc.t(data.item(str(cr.id)).get("name", cr.id)),
					"pct": _n(float(cr.get("chance", 0.0)) * 100.0, 3)}) + "\n"
	if not any:
		out += "\n" + _tr("UI_QUESTS_MAN_D_LOCKED") + "\n"
	return out


static func _unlocks(data: Object, unlocks: Array) -> String:
	var out := _title("UI_QUESTS_MAN_P_UNLOCKS")
	out += "\n" + _tr("UI_QUESTS_MAN_U_INTRO") + "\n\n"
	var n := 0
	for e in ScreenRegistry.entries(data):
		var tok := str(e.get("unlock", ""))
		if tok.is_empty() or unlocks.has(tok):
			continue
		n += 1
		var nm := Loc.t(e.title_data) if e.has("title_data") else _tr(str(e.title))
		var hint := UnlockSystem.hint_for(str(e.get("hint_unlock", tok)), data)       # come fa il menù laterale (es. Prestigio)
		if hint.is_empty():
			hint = _tr("UI_INTEG_LOCKED_LATER")           # nessun trattino muto: si dice che arriverà
		out += Loc.tf("UI_QUESTS_MAN_U_ROW", {"name": nm, "hint": hint}) + "\n"
	if n == 0:
		out += _tr("UI_QUESTS_MAN_U_NONE") + "\n"
	return out


static func _glossary() -> String:
	var out := _title("UI_QUESTS_MAN_P_GLOSSARY")
	for i in range(1, GLOSSARY_COUNT + 1):
		out += "\n[b]%s[/b]: %s\n" % [_tr("UI_QUESTS_GLOSS_%d_T" % i), _tr("UI_QUESTS_GLOSS_%d_D" % i)]
	return out
