class_name WelcomeBack
extends RefCounted
## Modello della finestra "Bentornato" (docs/03 R-OFF-4, docs/16 §3.7). Funzione pura: unisce il resoconto
## offline `report` (Simulation.run_offline: {id_sistema: Dictionary}) in righe già tradotte.
##
## FORMATO DEL RESOCONTO (ogni sistema aggiunge la propria sezione a report[id_sistema], tutte le chiavi facoltative):
##   "items":  {def_id: qty}              oggetti ottenuti
##   "xp":     {skill_id: amount}         esperienza ottenuta
##   "levels": {skill_id: [da, a]}        livelli guadagnati
##   "crates": {crate_id: qty}            casse trovate
##   "stop":   {"key": "UI_...", "params": {}}   motivo di interruzione (cibo finito, banca piena, morte...)
##   "rows":   [{"key": "UI_...", "params": {}}] righe libere (es. "Tenuta +31.200 unità", "2 spedizioni concluse")
## La sezione "quests" (QuestSystem) aggiunge anche "progressed": [id] e "ready": [id] e un conteggio di ripiego
## di items/xp/levels/crates letto dai segnali: vale SOLO se nessun'altra sezione fornisce quella categoria.

const MAX_ITEM_ROWS := 8


## Porta le sezioni "native" dei sistemi al formato qui sopra (integrazione, resoconto 29). I sistemi hanno
## resoconti propri (SkillSystem.simulate_offline: skill/action/xp float/level_from/level_to/crates int/stopped;
## CombatSystem: kills/xp float/gold/crates int/food_used/stopped/monster/died; MarketSystem: days/orders/
## gazette_total): qui diventano categorie, righe e motivi di stop. Le sezioni già nel formato restano com'erano.
static func normalize(report: Dictionary, data: Object) -> Dictionary:
	var out := report.duplicate(true)
	var sk: Variant = out.get("skills")
	if sk is Dictionary and sk.has("action"):
		out["skills"] = _norm_skills(sk, data)
	var cb: Variant = out.get("combat")
	if cb is Dictionary and cb.has("kills"):
		var c: Dictionary = cb
		var n2 := {"items": c.get("items", {}), "rows": []}
		if float(c.get("xp", 0.0)) > 0.0:
			n2["xp"] = {"hero": float(c.xp)}
		if int(c.get("kills", 0)) > 0:
			var m: Dictionary = data.get_def("monsters", str(c.get("monster", "")))
			n2.rows.append({"key": "UI_INTEG_WB_KILLS" if int(c.kills) != 1 else "UI_UXA_WB_KILLS_ONE", "params": {"n": NumberFormat.fmt(float(c.kills)),
				"name": Loc.t(c.get("monster_name", m.get("name", c.get("monster", ""))))}})
		if int(c.get("gold", 0)) > 0:
			n2.rows.append({"key": "UI_QUESTS_RW_GOLD", "params": {"n": NumberFormat.fmt(float(c.gold))}})
		for extra_row in c.get("rows", []):          # incursioni, boss mondiali, Breccia: righe già pronte
			n2.rows.append(extra_row)
		if int(c.get("food_used", 0)) > 0:
			n2.rows.append({"key": "UI_INTEG_WB_FOOD", "params": {"n": NumberFormat.fmt(float(c.food_used))}})
		if int(c.get("ambushes", 0)) > 0:
			var amr: Dictionary = ((Formulas.k().get("combat", {}) as Dictionary).get("rules", {}) as Dictionary).get("ambush", {})
			n2.rows.append({"key": "UI_FIXC_WB_AMBUSHES", "params": {"n": int(c.ambushes), "reward": NumberFormat.fmt(float(amr.get("reward_mult", 1.0)))}})
		# cadute con rinascita (QA4 #1): l'Eroe è caduto ma ha continuato, come nel gioco aperto
		var falls := int(c.get("deaths", 0)) - (1 if str(c.get("stopped", "")) == "death" else 0)
		if falls > 0:
			var dr: Dictionary = (Formulas.k().get("combat", {}) as Dictionary).get("rules", {})
			n2.rows.append({"key": "UI_FIXC_WB_DEATHS" if falls != 1 else "UI_FIXC_WB_DEATHS_ONE", "params": {"n": falls,
				"pct": int(dr.get("death_wounded_stat_pct", 0)), "min": int(round(float(dr.get("death_wounded_duration_s", 0)) / 60.0))}})
		# mansione di riserva (QA81 M5): il tempo avanzato dopo lo stop del combattimento è andato a una mansione
		var fb: Variant = c.get("fallback")
		if fb is Dictionary:
			var fbd: Dictionary = fb
			if str(fbd.get("action", "")).is_empty():
				n2.rows.append({"key": "UI_OFFL_FALLBACK_NONE", "params": {"time": NumberFormat.fmt_time(float(fbd.get("seconds", 0.0)))}})
			else:
				var fs: Variant = fbd.get("skills")
				if fs is Dictionary and (fs as Dictionary).has("action"):
					out["skills"] = _norm_skills(fs, data)
				n2.rows.append({"key": "UI_OFFL_RESUMED_SKILL" if bool(fbd.get("resumed", false)) else "UI_OFFL_FALLBACK", "params": {"time": NumberFormat.fmt_time(float(fbd.get("seconds", 0.0))),
					"action": Loc.t(data.action(str(fbd.action)).get("name", fbd.action))}})
		match str(c.get("stopped", "")):
			"death":
				n2["stop"] = {"key": "UI_WB_FOOD_OUT" if bool(c.get("food_out", false)) else "UI_INTEG_WB_DIED", "params": {}}
			"death_risk":
				n2["stop"] = {"key": "UI_WB_FOOD_OUT_RISK" if bool(c.get("food_out", false)) else "UI_MODES_STOP_RISK", "params": {}}
			"no_ammo":
				n2["stop"] = {"key": "UI_COMBAT_AMMO_OUT", "params": {}}
			"no_food":
				n2["stop"] = {"key": "UI_INTEG_WB_NO_FOOD", "params": {}}
		out["combat"] = n2
	var mk: Variant = out.get("market")
	if mk is Dictionary and (mk.has("orders") or mk.has("gazette_total") or mk.has("days")):
		var rows: Array = []
		if int(mk.get("orders", 0)) > 0:
			rows.append({"key": "UI_INTEG_WB_ORDERS" if int(mk.orders) != 1 else "UI_UXA_WB_ORDERS_ONE", "params": {"n": int(mk.orders)}})
		if int(mk.get("gazette_total", 0)) > 0:
			rows.append({"key": "UI_INTEG_WB_GAZETTE" if int(mk.gazette_total) != 1 else "UI_UXA_WB_GAZETTE_ONE", "params": {"n": int(mk.gazette_total)}})
		out["market"] = {"rows": rows}
	return out


static func _norm_skills(s: Dictionary, data: Object) -> Dictionary:
	var skill := str(s.get("skill", ""))
	var n := {"items": s.get("items", {}), "rows": []}
	if float(s.get("xp", 0.0)) > 0.0:
		n["xp"] = {skill: float(s.xp)}
	if int(s.get("level_to", 0)) > int(s.get("level_from", 0)):
		n["levels"] = {skill: [int(s.level_from), int(s.level_to)]}
	if int(s.get("completions", 0)) > 0:
		n.rows.append({"key": "UI_INTEG_WB_ACTIONS", "params": {"n": NumberFormat.fmt(float(s.completions)),
			"action": Loc.t(data.action(str(s.action)).get("name", s.action))}})
	match str(s.get("stopped", "")):
		"bank_full":
			n["stop"] = {"key": "UI_SKILLS_STOP_BANK_FULL", "params": {}}
		"no_materials":
			n["stop"] = {"key": "UI_SKILLS_STOP_MATERIALS", "params": {}}
		"single":
			# QA119: equipaggiamento e attrezzi si costruiscono UNO per volta: il resto dell'assenza non è un guasto, e la Coda è la soluzione
			n["stop"] = {"key": "UI_SKILLS_STOP_SINGLE", "params": {}}
	return n


static func build(seconds: float, report_in: Dictionary, data: Object, limit_s: float) -> Dictionary:
	var report := normalize(report_in, data)
	var out := {
		"title": TranslationServer.translate("UI_QUESTS_WB_TITLE"),
		"away": Loc.tf("UI_QUESTS_WB_AWAY", {"time": NumberFormat.fmt_time(seconds), "limit": NumberFormat.fmt_time(limit_s)}),
		"sections": [],      # [{"header": String, "lines": PackedStringArray}]
		"ready_quests": [], "crates": 0, "empty": true,
	}
	var sections: Array = out.sections
	var items := _merged(report, "items")
	var xp := _merged(report, "xp")
	var crates := _merged(report, "crates")
	var levels := _merged_levels(report)
	out.crates = 0
	for k in crates:
		out.crates += int(crates[k])
	_add(sections, "UI_QUESTS_WB_XP", _xp_lines(xp, data))
	_add(sections, "UI_QUESTS_WB_LEVELS", _level_lines(levels, data))
	_add(sections, "UI_QUESTS_WB_ITEMS", _item_lines(items, data))
	_add(sections, "UI_QUESTS_WB_CRATES", _item_lines(crates, data))
	var q: Dictionary = report.get("quests", {})
	var qlines := PackedStringArray()
	var ready: Array = q.get("ready", [])
	for qid in q.get("progressed", []):
		var d: Dictionary = data.get_def("quests", str(qid))
		var line := QuestText.title(d) if not d.is_empty() else str(qid)
		if ready.has(qid):
			line += " " + TranslationServer.translate("UI_QUESTS_WB_QUEST_READY")
		qlines.append(line)
	out.ready_quests = ready
	_add(sections, "UI_QUESTS_WB_QUESTS", qlines)
	var other := PackedStringArray()
	var stops := PackedStringArray()
	for sid in report:
		var r: Variant = report[sid]
		if not (r is Dictionary):
			continue
		for row in r.get("rows", []):
			other.append(_row_text(row))
		var st: Variant = r.get("stop")
		if st is Dictionary and not str(st.get("key", "")).is_empty():
			stops.append(_row_text(st))
	_add(sections, "", other)
	_add(sections, "UI_QUESTS_WB_STOP", stops)
	out.empty = sections.is_empty()
	return out


static func _add(sections: Array, header: String, lines: PackedStringArray) -> void:
	if not lines.is_empty():
		sections.append({"header": header, "lines": lines})


static func _row_text(row: Variant) -> String:
	if row is Dictionary:
		return Loc.tf(str(row.get("key", "")), row.get("params", {}))
	return str(row)


## Somma una categoria sulle sezioni; la sezione "quests" conta solo se nessun'altra la fornisce.
static func _merged(report: Dictionary, cat: String) -> Dictionary:
	var total := {}
	var found := false
	for sid in report:
		if sid == "quests" or not (report[sid] is Dictionary):
			continue
		var d: Variant = report[sid].get(cat)
		if d is Dictionary and not d.is_empty():
			found = true
			for k in d:
				total[k] = total.get(k, 0) + d[k]
	if not found:
		var fallback: Variant = report.get("quests", {}).get(cat)
		if fallback is Dictionary:
			total = fallback.duplicate()
	return total


static func _merged_levels(report: Dictionary) -> Dictionary:
	var total := {}
	var found := false
	for sid in report:
		if sid == "quests" or not (report[sid] is Dictionary):
			continue
		var d: Variant = report[sid].get("levels")
		if d is Dictionary and not d.is_empty():
			found = true
			for k in d:
				var pair: Array = d[k]
				if total.has(k):
					total[k] = [mini(int(total[k][0]), int(pair[0])), maxi(int(total[k][1]), int(pair[1]))]
				else:
					total[k] = [int(pair[0]), int(pair[1])]
	if not found:
		var fb: Variant = report.get("quests", {}).get("levels")
		if fb is Dictionary:
			total = fb.duplicate(true)
	return total


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(d[a]) > float(d[b]))
	return keys


static func _item_lines(d: Dictionary, data: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := _sorted_keys(d)
	for i in mini(keys.size(), MAX_ITEM_ROWS):
		var k: String = keys[i]
		out.append(Loc.tf("UI_QUESTS_RW_ITEM", {"n": NumberFormat.fmt(float(d[k])), "name": Loc.t(data.item(k).get("name", k))}))
	if keys.size() > MAX_ITEM_ROWS:
		out.append(Loc.tf("UI_QUESTS_WB_MORE", {"n": keys.size() - MAX_ITEM_ROWS}))
	return out


static func _xp_lines(d: Dictionary, data: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for k in _sorted_keys(d):
		out.append("%s: +%s" % [Loc.t(data.get_def("skills", str(k)).get("name", k)), NumberFormat.fmt(float(d[k]))])
	return out


static func _level_lines(d: Dictionary, data: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for k in d:
		out.append(Loc.tf("UI_QUESTS_WB_LEVEL_FROM_TO", {"skill": Loc.t(data.get_def("skills", str(k)).get("name", k)),
			"a": int(d[k][0]), "b": int(d[k][1])}))
	return out
