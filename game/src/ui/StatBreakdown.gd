class_name StatBreakdown
extends RefCounted
## Tooltip di calcolo delle statistiche dell'Eroe (docs/16 §3.6, UI-A G18): «Precisione 812 = 20 base + 3×46 livello + …».
## Rifà il calcolo di CombatSystem._build_stats con gli stessi coefficienti (Formulas.k) e lo scompone in addendi; ciò che
## resta tra il totale vero e quello ricostruito (ibride, ferite…) compare come ultimo fattore, così la somma torna sempre.
## Solo lettura: non cambia nulla del gioco.

## Statistiche scomponibili -> chiave del nome (stesse del pannello Eroe).
const NAMES := {"hp": "HP", "max_hit": "MAX_HIT", "interval": "INTERVAL", "ap": "AP", "acc": "ACC", "eva": "EVA", "arm": "ARMOR",
	"ward": "WARD", "crit": "CRIT", "critd": "CRITD", "regen_pct": "REGEN"}


## {"name": nome, "total": numero, "parts": [{"label": testo, "text": testo}], "factors": [{"label","text"}], "formula": testo}
## o {} se la statistica non è scomponibile.
static func explain(combat: CombatSystem, stat: String) -> Dictionary:
	if combat == null or not NAMES.has(stat):
		return {}
	var st := combat.hero_stats()
	var inp := combat.stat_inputs()
	var sums: Dictionary = inp.sums
	var k: Dictionary = Formulas.k().combat
	var cf: Dictionary = k.hero.coef
	var lvl := int(st.level)
	var attrs: Dictionary = st.attrs
	var prim := float(attrs[st.primary]) + float(sums.get(st.primary, 0.0))
	var m: ModifierStack = combat.ctx.modifiers
	var parts: Array = []        # {"label", "value": float, "coef": float (0 = nessun coefficiente)}
	var factors: Array = []      # {"label", "mult": float}
	var total := float(st[stat])
	var pct := false
	match stat:
		"acc":
			_p(parts, "UI_UIA_BD_BASE", float(cf.acc.base))
			_c(parts, "UI_UIA_BD_LEVEL", float(cf.acc.level), lvl)
			_c(parts, "UI_UIA_BD_PRIMARY", float(cf.acc.primary), prim)
			_p(parts, "UI_UIA_BD_GEAR", float(sums.get("accuracy", 0.0)))
			_f(factors, "UI_UIA_BD_BONUS", m.multiplier("combat_acc_pct"))
		"eva":
			_p(parts, "UI_UIA_BD_BASE", float(cf.eva.base))
			_c(parts, "UI_UIA_BD_LEVEL", float(cf.eva.level), lvl)
			_c(parts, "UI_UIA_BD_DEX", float(cf.eva.dex), float(attrs.dex) + float(sums.get("dex", 0.0)))
			_p(parts, "UI_UIA_BD_GEAR", float(sums.get("evasion", 0.0)))
			_f(factors, "UI_UIA_BD_BONUS", m.multiplier("combat_eva_pct"))
		"hp":
			_p(parts, "UI_UIA_BD_BASE", float(cf.hp.base))
			_c(parts, "UI_UIA_BD_VIT", float(cf.hp.vit), float(attrs.vit) + float(sums.get("vit", 0.0)))
			_c(parts, "UI_UIA_BD_LEVEL", float(cf.hp.level), lvl)
			_p(parts, "UI_UIA_BD_GEAR", float(sums.get("hp", 0.0)))
			_f(factors, "UI_UIA_BD_BONUS", m.multiplier("combat_hp_pct"))
		"ap":
			_c(parts, "UI_UIA_BD_PRIMARY", float(cf.ap.primary), prim)
			_p(parts, "UI_UIA_BD_GEAR", float(sums.get("ap", 0.0)))
			total = float(st.ap)
		"arm":
			_p(parts, "UI_UIA_BD_GEAR", float(sums.get("armor", 0.0)))
			_f(factors, "UI_UIA_BD_BONUS", m.multiplier("combat_defense_pct") * m.multiplier("combat_arm_pct"))
		"ward":
			_p(parts, "UI_UIA_BD_GEAR", float(sums.get("ward", 0.0)))
			_f(factors, "UI_UIA_BD_BONUS", m.multiplier("combat_defense_pct") * m.multiplier("combat_ward_pct"))
		"max_hit":
			var wd := float(inp.weapon.get("damage", 0.0)) + float(inp.ammo_damage)
			_p(parts, "UI_UIA_BD_WEAPON", wd)
			_f(factors, "UI_UIA_BD_POWER", 1.0 + float(st.ap) / 100.0)
			_f(factors, "UI_UIA_BD_BONUS", m.multiplier("combat_dmg_pct"))
		"crit":
			pct = true
			_p(parts, "UI_UIA_BD_BASE", float(k.crit_base) * 100.0)
			_p(parts, "UI_UIA_BD_WEAPON", float(inp.weapon.get("stats", {}).get("crit_chance", 0.0)) * 100.0)
			_p(parts, "UI_UIA_BD_BONUS", m.total_add("combat_crit_chance_pct"))
			total = float(st.crit) * 100.0
		"critd":
			pct = true
			_p(parts, "UI_UIA_BD_BASE", float(k.crit_dmg_base) * 100.0)
			_p(parts, "UI_UIA_BD_BONUS", m.total_add("combat_crit_dmg_pct"))
			total = float(st.critd) * 100.0
		"interval":
			_p(parts, "UI_UIA_BD_WEAPON", float(inp.weapon.get("attack_interval_s", 0.0)))
			_f(factors, "UI_UIA_BD_HASTE", 1.0 / maxf(0.01, (1.0 + Formulas.effective_haste_pct(m.total_add("combat_haste_pct")) / 100.0)
				* m.total_more("combat_haste_pct")))
		"regen_pct":
			pct = true
			_p(parts, "UI_UIA_BD_BASE", float(k.hero.regen_base_pct_per_s))
			_p(parts, "UI_UIA_BD_BONUS", m.total_add("combat_regen_hps_pct"))
			total = float(st.regen_pct)
	# fattore residuo (ibride, ferite, tetto del critico…) perché la formula torni al totale mostrato
	var sum := 0.0
	for p in parts:
		sum += float(p.value) * (float(p.coef) if float(p.coef) != 0.0 else 1.0)
	var mult := 1.0
	for f in factors:
		mult *= float(f.mult)
	var rebuilt := sum * mult
	if absf(rebuilt) > 0.0001 and absf(total / rebuilt - 1.0) > 0.005:
		_f(factors, "UI_UIA_BD_OTHER", total / rebuilt)
	var out_parts: Array = []
	for p in parts:
		if absf(float(p.value)) < 0.0001:
			continue
		var v := float(p.value)
		var txt := _num(v, pct)
		if float(p.coef) != 0.0:
			txt = "%s×%s" % [_num(float(p.coef), false), _num(v, false)]
		out_parts.append({"label": TranslationServer.translate(str(p.label)), "text": txt})
	var out_factors: Array = []
	for f in factors:
		if absf(float(f.mult) - 1.0) < 0.0005 and str(f.label) != "UI_UIA_BD_POWER":
			continue
		out_factors.append({"label": TranslationServer.translate(str(f.label)), "text": "×" + NumberFormat.decimal(float(f.mult), 2, Loc.locale())})
	var name := TranslationServer.translate("UI_HERO_ST_" + str(NAMES[stat]))
	var shown := NumberFormat.fmt_pct(total) if pct else NumberFormat.fmt(total) if stat != "interval" else NumberFormat.fmt_time(total)
	var bits := PackedStringArray()
	for p in out_parts:
		bits.append("%s %s" % [p.text, p.label])
	var formula := " + ".join(bits)
	for f in out_factors:
		formula += "  %s %s" % [f.text, f.label]
	return {"name": name, "total": total, "shown": shown, "parts": out_parts, "factors": out_factors,
		"formula": "%s %s = %s" % [name, shown, formula] if not formula.is_empty() else "%s %s" % [name, shown]}


static func _p(arr: Array, label: String, value: float) -> void:
	arr.append({"label": label, "value": value, "coef": 0.0})


static func _c(arr: Array, label: String, coef: float, value: float) -> void:
	arr.append({"label": label, "value": value, "coef": coef})


static func _f(arr: Array, label: String, mult: float) -> void:
	arr.append({"label": label, "mult": mult})


static func _num(v: float, pct: bool) -> String:
	if pct:
		return NumberFormat.fmt_pct(v)
	return NumberFormat.decimal(v, 0 if absf(v - roundf(v)) < 0.05 else 1, Loc.locale())
