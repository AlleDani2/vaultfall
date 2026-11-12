class_name ItemTooltip
extends RefCounted
## Tooltip degli oggetti (docs/16 §4, UI-A G25): nome (colore e simbolo della rarità), categoria e tier, qualità, statistiche
## già scalate da qualità e grado, bonus, valore e CONFRONTO con ciò che l'eroe indossa nello stesso slot.
## Il testo si costruisce in `build()` (puro, testabile); `make_control()` lo mette in un RichTextLabel per i tooltip
## personalizzati (Control._make_custom_tooltip). Solo lettura.

const COL_UP := "7fcf8a"
const COL_DOWN := "d9544d"
const COL_MUTED := "9a968c"
const STAT_ORDER: PackedStringArray = ["damage", "armor", "ward", "hp", "ap", "accuracy", "evasion", "str", "dex", "int", "vit", "crit_chance"]
const STAT_KEYS := {
	"damage": "UI_HERO_STAT_DAMAGE", "armor": "UI_BANK_STAT_ARMOR", "ward": "UI_BANK_STAT_WARD", "hp": "UI_BANK_STAT_HP",
	"ap": "UI_BANK_STAT_AP", "evasion": "UI_BANK_STAT_EVASION", "accuracy": "UI_BANK_STAT_ACCURACY", "int": "UI_BANK_STAT_INT",
	"dex": "UI_BANK_STAT_DEX", "str": "UI_BANK_STAT_STR", "vit": "UI_BANK_STAT_VIT", "crit_chance": "UI_BANK_STAT_CRIT",
}


## Statistiche effettive di un pezzo: {"damage": x, "armor": y, ...} con qualità e grado applicati come in CombatSystem._gear_blocks.
static func effective_stats(def: Dictionary, inst: Dictionary) -> Dictionary:
	var eq: Dictionary = def.get("equipment", {})
	var out: Dictionary = {}
	if eq.is_empty():
		return out
	var qm := 1.0
	if bool(def.get("quality_applies", true)) and not inst.is_empty():
		for qd in DataRegistry.constants.get("quality", []):
			if qd.id == str(inst.get("quality", "normal")):
				qm = float(qd.mult)
	var info: Dictionary = DataRegistry.rules("era_rules").get("item_rank", {})
	var rk := pow(float(info.get("stat_mult_per_rank", 1.0)), float(inst.get("rank", 0))) if not inst.is_empty() else 1.0
	var rank_stats: Array = info.get("applies_to_stats", [])
	if eq.has("damage"):
		out["damage"] = float(eq.damage) * qm * (rk if rank_stats.has("damage") else 1.0)
	for key in eq.get("stats", {}):
		var v := float(eq.stats[key])
		if key != "crit_chance":
			v *= qm
		if rank_stats.has(key):
			v *= rk
		out[key] = v
	return out


## Lo slot "reale" dove andrebbe indossato l'oggetto (gli anelli confrontano con il primo anello).
static func slot_of(def: Dictionary) -> String:
	return str(def.get("equipment", {}).get("slot", ""))


## L'istanza indossata nello slot dell'oggetto ({} se nessuna o se l'oggetto non è un pezzo indossabile).
static func equipped_instance(def: Dictionary) -> Dictionary:
	var slot := slot_of(def)
	if slot.is_empty() or not GameState.active:
		return {}
	var cb := Game.system("combat") as CombatSystem
	var bank := Game.system("bank") as BankSystem
	if cb == null or bank == null:
		return {}
	var uid := cb.equipped(slot)
	return bank.get_instance(uid) if not uid.is_empty() else {}


## Righe di confronto: [{"key": statistica, "diff": float, "text": "+3 danno"}], solo le differenze.
static func compare(def: Dictionary, inst: Dictionary, other_inst: Dictionary) -> Array:
	var out: Array = []
	if other_inst.is_empty():
		return out
	var other_def := DataRegistry.item(str(other_inst.get("def", "")))
	var a := effective_stats(def, inst)
	var b := effective_stats(other_def, other_inst)
	for key in STAT_ORDER:
		var diff := float(a.get(key, 0.0)) - float(b.get(key, 0.0))
		if absf(diff) < 0.05:
			continue
		var n := NumberFormat.fmt_pct(absf(diff) * 100.0) if key == "crit_chance" else NumberFormat.decimal(absf(diff), 1, Loc.locale())
		out.append({"key": key, "diff": diff, "text": "%s%s %s" % ["+" if diff > 0.0 else "−", n, TranslationServer.translate(STAT_KEYS[key])]})
	return out


## Contenuto del tooltip: {"title", "color", "lines": [BBCode], "compare": [{key,diff,text}], "has_compare": bool}.
## `compare_to` = istanza con cui confrontare; omessa, si usa quella indossata nello slot (se l'oggetto non è già indossato).
static func build(def_id: String, inst: Dictionary = {}, compare_to: Variant = null) -> Dictionary:
	var def := DataRegistry.item(def_id)
	if def.is_empty():
		return {}
	var rarity := str(inst.get("rarity", def.get("rarity", "")))
	var col := CrateUi.rarity_color(rarity) if not rarity.is_empty() else Color("f2efe4")
	var title := Loc.t(def.get("name", {}))
	if not rarity.is_empty():
		title = "%s %s" % [CrateUi.rarity_symbol(rarity), title]
	var lines: Array = []
	var cat := TranslationServer.translate("UI_UIA_CAT_" + str(def.get("category", "")).to_upper())
	var sub := Loc.tf("UI_BANK_D_TIER", {"t": int(def.get("tier", 0))})
	lines.append("[color=#%s]%s · %s[/color]" % [COL_MUTED, cat, sub])
	var worn_name := ItemLabel.worn_slot_name(str(inst.get("uid", "")))
	if not worn_name.is_empty():              # FEEDBACK EQUIP-UI: si vede subito che il pezzo è indossato e dove
		lines.append("[color=#edc26b][b]%s[/b][/color]" % Loc.tf("UI_EQ_BANK_BADGE_TIP", {"slot": worn_name}))
	var eq: Dictionary = def.get("equipment", {})
	if not eq.is_empty():
		lines.append("[color=#%s]%s[/color]" % [COL_MUTED, Loc.tf("UI_BANK_D_SLOT",
			{"slot": TranslationServer.translate("UI_BANK_SLOT_" + str(eq.get("slot", "")).to_upper()), "lv": int(eq.get("level_req", 1))})])
		var q := str(inst.get("quality", ""))
		if not q.is_empty() and q != "normal":
			lines.append(Loc.tf("UI_BANK_D_QUALITY", {"q": TranslationServer.translate("UI_BANK_Q_" + q.to_upper())}))
		if int(inst.get("rank", 0)) > 0:
			lines.append(Loc.tf("UI_UIA_TIP_RANK", {"r": int(inst.rank)}))
		var st := effective_stats(def, inst)
		for key in STAT_ORDER:
			if not st.has(key):
				continue
			var v := float(st[key])
			var shown := NumberFormat.fmt_pct(v * 100.0) if key == "crit_chance" else NumberFormat.decimal(v, 1, Loc.locale())
			lines.append("%s: %s" % [TranslationServer.translate(STAT_KEYS[key]).capitalize(), shown])
		if eq.has("attack_interval_s"):
			lines.append(Loc.tf("UI_UIA_TIP_SPEED", {"s": NumberFormat.decimal(float(eq.attack_interval_s), 1, Loc.locale())}))
		for m in eq.get("modifiers", []):
			lines.append("[color=#%s]%s[/color]" % [COL_MUTED, BonusSummary.effect_text(m)])
	var desc := Loc.t(def.get("desc", {}))
	if not desc.is_empty():
		lines.append("[color=#%s]%s[/color]" % [COL_MUTED, desc])
	if float(def.get("value", 0)) > 0.0:
		lines.append("[color=#%s]%s[/color]" % [COL_MUTED, Loc.tf("UI_UIA_TIP_VALUE", {"v": NumberFormat.fmt(float(def.value))})])
	var other: Dictionary = {}
	if compare_to is Dictionary:
		other = compare_to
	elif not eq.is_empty() and (inst.is_empty() or not _is_equipped(str(inst.get("uid", "")))):
		other = equipped_instance(def)
	var cmp := compare(def, inst, other)
	return {"title": title, "color": col, "lines": lines, "compare": cmp, "has_compare": not other.is_empty(),
		"compare_name": Loc.t(DataRegistry.item(str(other.get("def", ""))).get("name", {})) if not other.is_empty() else ""}


static func _is_equipped(uid: String) -> bool:
	var cb := Game.system("combat") as CombatSystem if GameState.active else null
	return cb != null and not uid.is_empty() and cb.is_equipped(uid)


## BBCode completo (titolo, righe, confronto).
static func to_bbcode(c: Dictionary) -> String:
	if c.is_empty():
		return ""
	var out := PackedStringArray()
	out.append("[b][color=#%s]%s[/color][/b]" % [(c.color as Color).to_html(false), c.title])
	out.append_array(PackedStringArray(c.lines))
	if bool(c.has_compare):
		out.append("")
		out.append("[color=#%s]%s[/color]" % [COL_MUTED, Loc.tf("UI_UIA_TIP_VS", {"name": c.compare_name})])
		if (c.compare as Array).is_empty():
			out.append(TranslationServer.translate("UI_UIA_TIP_SAME"))
		for r in c.compare:
			out.append("[color=#%s]%s[/color]" % [COL_UP if float(r.diff) > 0.0 else COL_DOWN, r.text])
	return "\n".join(out)


## Tooltip personalizzato già pronto (da restituire da _make_custom_tooltip).
static func make_control(def_id: String, inst: Dictionary = {}, compare_to: Variant = null) -> Control:
	var c := build(def_id, inst, compare_to)
	if c.is_empty():
		return null
	var rt := RichTextLabel.new()
	rt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(300, 0)
	rt.text = to_bbcode(c)
	FxUi.tooltip_in(rt)                     # compare con una dissolvenza breve (0,1 s; nulla con «riduci animazioni»)
	return rt
