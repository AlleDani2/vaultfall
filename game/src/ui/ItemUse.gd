class_name ItemUse
extends RefCounted
## «A cosa serve» e «Come si usa» di ogni oggetto, GENERATI dai dati (categoria + effetto + dove si usa), mai scritti a mano
## oggetto per oggetto (feedback giocatore 23/10/2026: «non ho capito a cosa servono»). Classe pura e testabile
## (`test_item_use.gd` controlla che TUTTI gli oggetti dei dati abbiano la riga, in italiano e in inglese).
## Nessun numero di bilanciamento: ogni cifra è letta dal campo dell'oggetto (tool, food, potion, ammo, glyph, ...).

## Famiglie di bonus degli attrezzi, nell'ordine in cui si mostrano.
const TOOL_FX: PackedStringArray = ["haste_pct", "double_pct", "success_pct"]


## Bonus di un attrezzo come testo («velocità +4%, raccolto doppio +2%»). "" se l'attrezzo base non dà nulla.
static func tool_effects(def: Dictionary) -> String:
	var t: Dictionary = def.get("tool", {})
	var parts := PackedStringArray()
	for k in TOOL_FX:
		var v := float(t.get(k, 0.0))
		if v != 0.0:
			parts.append("%s %s" % [TranslationServer.translate("UI_USE_FX_" + k.to_upper()), BonusSummary.fmt_value("pct", v)])
	return ", ".join(parts)


static func skill_name(skill_id: String) -> String:
	var s: Dictionary = DataRegistry.get_def("skills", skill_id)
	return Loc.t(s.get("name", {})) if not s.is_empty() else skill_id


## Traduzione di `key`, o di `fallback` se `key` non esiste.
static func _tr_or(key: String, fallback: String) -> String:
	var t := TranslationServer.translate(key)
	return t if t != key else TranslationServer.translate(fallback)


## Ambito di una pozione in parole: «in combattimento», «in qualunque attività», «solo in Raccolta» (gruppo o mansione).
## QA119: prima gli ambiti `skill_group:...` e `skill:...` finivano come chiave nuda tra parentesi.
static func _potion_scope(scope: String) -> String:
	var kp := scope.split(":")
	if kp.size() < 2:
		return TranslationServer.translate("UI_USE_SCOPE_" + scope.to_upper())
	var nm := ""
	if kp[0] == "skill":
		nm = skill_name(kp[1])
	else:
		nm = TranslationServer.translate("UI_BONUS_SCOPE_" + kp[1].to_upper())
	return Loc.tf("UI_USE_SCOPE_IN", {"name": nm})


static func _modifiers_text(mods: Array) -> String:
	var parts := PackedStringArray()
	for m in mods:
		var kp := str(m.key).split(":")
		var fam: Dictionary = DataRegistry.modifier_family(kp[0])
		var unit := str(fam.get("unit", "pct"))
		# QA119: nome breve del bonus («Qualità: Cucina»), non la descrizione tecnica con le formule («durata = base / (1 + valore/100)»)
		var cd: Dictionary = BonusSummary.family_def(kp[0])
		var label := BonusSummary.title_of(cd, kp[1] if kp.size() > 1 else "") if not cd.is_empty() else (Loc.t(fam.get("desc", {})) if not fam.is_empty() else str(m.key))
		parts.append("%s %s" % [label, BonusSummary.fmt_value(unit, float(m.value))])
	return ", ".join(parts)


## Mansioni in cui l'oggetto è un ingrediente (al massimo 3, nomi nella lingua corrente).
static func used_in(item_id: String) -> String:
	var seen: Dictionary = {}
	for aid in DataRegistry.all_actions():
		var a: Dictionary = DataRegistry.all_actions()[aid]
		for io in a.get("inputs", []):
			if str(io.get("item", "")) == item_id:
				seen[str(a.skill)] = true
				break
		if seen.size() >= 3:
			break
	var names := PackedStringArray()
	for sk in seen:
		names.append(skill_name(str(sk)))
	return ", ".join(names)


## Oggetti che la Tenuta chiede per costruire/potenziare gli edifici (dai dati: costi a tutti i livelli di tutti gli edifici).
static var _estate_items: Dictionary = {}


static func _estate_uses(item_id: String) -> bool:
	if _estate_items.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		var g: Node = tree.root.get_node_or_null("Game") if tree != null else null
		var es: Object = g.call("system", "estate") if g != null and g.has_method("system") else null
		if es == null:
			return false
		for b in DataRegistry.table("estate_buildings"):
			for lv in range(0, 131):
				for it in (es.call("cost_at", str(b.id), lv) as Dictionary).get("items", {}):
					_estate_items[str(it)] = true
		if _estate_items.is_empty():
			_estate_items["-"] = true
	return _estate_items.has(item_id)


## Altri usi di un materiale oltre agli ingredienti delle mansioni, in parole ("" se nessuno): Tenuta, Luoghi Segreti, Ere e Rango.
static func other_uses(item_id: String) -> String:
	var parts := PackedStringArray()
	if _estate_uses(item_id):
		parts.append(TranslationServer.translate("UI_USE_OTHER_ESTATE"))
	if item_id == "map_fragment" and DataRegistry.has_table("secret_spots"):
		parts.append(TranslationServer.translate("UI_USE_OTHER_SECRETS"))
	if item_id == "era_essence":
		parts.append(TranslationServer.translate("UI_USE_OTHER_ERA"))
	return ", ".join(parts)


## Frase «A cosa serve»: SEMPRE non vuota per un oggetto esistente. "" solo per un id sconosciuto.
static func purpose(def_id: String) -> String:
	var def: Dictionary = DataRegistry.item(def_id)
	if def.is_empty():
		return ""
	var cat := str(def.get("category", ""))
	var sub := str(def.get("subcategory", ""))
	var tier := int(def.get("tier", 1))
	match cat:
		"tool":
			var t: Dictionary = def.get("tool", {})
			var fx := tool_effects(def)
			return Loc.tf("UI_USE_TOOL" if fx != "" else "UI_USE_TOOL_BASE",
				{"skill": skill_name(str(t.get("skill", ""))), "fx": fx, "lv": int(t.get("level_req", 1))})
		"equipment":
			var eq: Dictionary = def.get("equipment", {})
			return Loc.tf("UI_USE_EQUIPMENT", {"slot": TranslationServer.translate("UI_BANK_SLOT_" + str(eq.get("slot", "")).to_upper()),
				"lv": int(eq.get("level_req", 1))})
		"food":
			if def.has("feast"):
				var f: Dictionary = def.feast
				return Loc.tf("UI_USE_FEAST", {"fx": _modifiers_text(f.get("modifiers", [])), "min": int(f.get("duration_min", 0))})
			return Loc.tf("UI_USE_FOOD", {"heal": int(def.get("food", {}).get("heal", 0))})
		"potion":
			var p: Dictionary = def.get("potion", {})
			return Loc.tf("UI_USE_POTION", {"fx": _modifiers_text(p.get("modifiers", [])), "n": int(p.get("charges", 0)),
				"scope": _potion_scope(str(p.get("scope", "combat")))})
		"ammo":
			var am: Dictionary = def.get("ammo", {})
			return Loc.tf("UI_USE_AMMO", {"style": TranslationServer.translate("UI_USE_STYLE_" + str(am.get("style", "melee")).to_upper()),
				"dmg": NumberFormat.fmt(float(am.get("damage", 0)))})
		"glyph":
			return Loc.tf("UI_USE_GLYPH", {"fx": _modifiers_text(def.get("glyph", {}).get("modifiers", []))})
		"seed":
			return TranslationServer.translate("UI_USE_SAPLING" if sub == "sapling" else "UI_USE_SEED")
		"key":
			return Loc.tf("UI_USE_KEY", {"t": int(def.get("key_tier", tier))})
		"crate":
			return _tr_or("UI_USE_CRATE_" + sub.to_upper(), "UI_USE_CRATE")
		"skin":
			var sk: Dictionary = def.get("skin", {})
			var m: Dictionary = sk.get("modifier", {})
			return Loc.tf("UI_USE_SKIN", {"fx": _modifiers_text([m]) if not m.is_empty() else "-"})
		"relic":
			return TranslationServer.translate("UI_USE_RELIC")
		"cosmetic":
			return TranslationServer.translate("UI_USE_COSMETIC")
		"consumable":
			if def.has("tome"):
				return TranslationServer.translate("UI_USE_XP_TOME")
			if def.has("hourglass"):
				return Loc.tf("UI_USE_HOURGLASS", {"h": NumberFormat.fmt(float(def.hourglass.get("hours", 1)))})
			return TranslationServer.translate("UI_USE_SUMMON")
		"openable":
			return TranslationServer.translate("UI_USE_OPENABLE")
		"currency":
			return _tr_or("UI_USE_CURRENCY_" + sub.to_upper(), "UI_USE_CURRENCY")
		"quest":
			return TranslationServer.translate("UI_USE_QUEST")
		"material":
			var where := used_in(def_id)
			var other := other_uses(def_id)       # QA119: Tenuta, Luoghi Segreti, Ere/Rango: prima il testo diceva «nessuna mansione lo usa»
			if where != "" and other != "":
				return Loc.tf("UI_USE_MATERIAL_ALSO", {"where": where, "other": other})
			if where != "":
				return Loc.tf("UI_USE_MATERIAL", {"where": where})
			if other != "":
				return Loc.tf("UI_USE_MATERIAL_OTHER", {"other": other})
			return TranslationServer.translate("UI_USE_MATERIAL_ALONE")
		"misc":
			return TranslationServer.translate("UI_USE_MISC")
	return TranslationServer.translate("UI_USE_GENERIC")


## Riga «Come si usa» (istruzione esplicita) o "" se l'oggetto non si usa a mano (materiali, valute).
static func howto(def_id: String) -> String:
	var def: Dictionary = DataRegistry.item(def_id)
	if def.is_empty():
		return ""
	match str(def.get("category", "")):
		"tool":
			return TranslationServer.translate("UI_USE_HOW_TOOL")
		"equipment":
			return TranslationServer.translate("UI_USE_HOW_EQUIPMENT")
		"food":
			return TranslationServer.translate("UI_USE_HOW_FEAST" if def.has("feast") else "UI_USE_HOW_FOOD")
		"potion":
			return TranslationServer.translate("UI_USE_HOW_POTION")
		"glyph":
			return TranslationServer.translate("UI_USE_HOW_GLYPH")
		"seed":
			return TranslationServer.translate("UI_USE_HOW_SEED")
		"key", "crate":
			return TranslationServer.translate("UI_USE_HOW_CRATE")
		"skin", "relic", "cosmetic":
			return TranslationServer.translate("UI_USE_HOW_WARDROBE")
		"consumable":
			return TranslationServer.translate("UI_USE_HOW_CONSUMABLE")
		"openable":
			return TranslationServer.translate("UI_USE_HOW_OPENABLE")
	return ""


## Riga sul Mercato: vendibile o no, e perché. Sempre non vuota.
static func market_line(def_id: String) -> String:
	var def: Dictionary = DataRegistry.item(def_id)
	if def.is_empty():
		return ""
	if bool(def.get("tradeable", true)) and float(def.get("value", 0)) > 0.0:
		return TranslationServer.translate("UI_USE_SELLABLE")
	return TranslationServer.translate("UI_USE_NOT_SELLABLE")


## Confronto di un attrezzo con quello in uso nella stessa mansione: "" se non è un attrezzo.
## «In uso: X» / «Migliore di quello in uso» / «Peggiore o uguale a quello in uso» / «Nessun attrezzo in uso».
static func tool_status(def_id: String) -> String:
	var def: Dictionary = DataRegistry.item(def_id)
	if str(def.get("category", "")) != "tool":
		return ""
	var skill := str(def.tool.get("skill", ""))
	var bank := Game.system("bank") as BankSystem if GameState.active else null
	var uid := str(GameState.data.get("equipment", {}).get("tools", {}).get(skill, "")) if GameState.active else ""
	var cur: Dictionary = bank.get_instance(uid) if (bank != null and uid != "") else {}
	if cur.is_empty():
		return Loc.tf("UI_USE_TOOL_NONE", {"skill": skill_name(skill)})
	var cur_def: Dictionary = DataRegistry.item(str(cur.def))
	var cname := Loc.t(cur_def.get("name", {}))
	if str(cur.def) == def_id:
		return Loc.tf("UI_USE_TOOL_SAME", {"name": cname})
	var s_new := _tool_score(def)
	var s_cur := _tool_score(cur_def)
	return Loc.tf("UI_USE_TOOL_BETTER" if s_new > s_cur else "UI_USE_TOOL_WORSE", {"name": cname})


static func _tool_score(def: Dictionary) -> float:
	var t: Dictionary = def.get("tool", {})
	var s := 0.0
	for k in TOOL_FX:
		s += float(t.get(k, 0.0))
	return s + float(def.get("tier", 0)) * 0.001
