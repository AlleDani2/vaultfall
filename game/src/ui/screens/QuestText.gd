class_name QuestText
extends RefCounted
## Testi delle missioni per la UI (obiettivi, ricompense, titoli): solo presentazione, nessuno stato.


static func title(quest_def: Dictionary) -> String:
	return Loc.t(quest_def.get("title", quest_def.get("id", "")))


static func objective(obj: Dictionary, data: Object) -> String:
	var t := str(obj.get("type", ""))
	var key := "UI_QUESTS_OBJ_" + t.to_upper()
	var params := {"name": _name_for(obj, data), "type": t}
	if TranslationServer.translate(key) == key:
		return Loc.tf("UI_QUESTS_OBJ_GENERIC", params)
	return Loc.tf(key, params)


static func _name_for(obj: Dictionary, data: Object) -> String:
	for field in ["item", "crate"]:
		if obj.has(field) and str(obj[field]) != "any":
			return Loc.t(data.item(str(obj[field])).get("name", obj[field]))
	var tables := {"monster": "monsters", "zone": "zones", "skill": "skills", "building": "estate_buildings",
		"npc": "npcs", "cls": "classes", "crop": "items"}
	for field in tables:
		if obj.has(field) and str(obj[field]) != "any":
			var d: Dictionary = data.get_def(tables[field], str(obj[field]))
			return Loc.t(d.get("name", obj[field]))
	if obj.has("rarity"):
		var rk := "UI_RARITY_" + str(obj.rarity).to_upper()
		var rt := str(TranslationServer.translate(rk))
		return rt if rt != rk else str(obj.rarity)
	for field in ["category", "rank"]:
		if obj.has(field):
			return str(obj[field])
	return ""


## Una riga per ogni voce di QuestSystem.reward_preview().
static func reward_lines(preview: Array, data: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for r in preview:
		match str(r.kind):
			"gold":
				out.append(Loc.tf("UI_QUESTS_RW_GOLD", {"n": NumberFormat.fmt(int(r.qty))}))
			"bank_slots":
				out.append(Loc.tf("UI_BANKX_RW", {"n": int(r.qty)}))
			"unlock":
				out.append(Loc.tf("UI_QUESTS_RW_UNLOCK", {"name": UnlockSystem.token_name(str(r.id), data)}))
			"reputation":
				out.append(Loc.tf("UI_GUILD2_RW_REP", {"n": NumberFormat.fmt(int(r.qty)),
					"name": Loc.t(data.get_def("factions", str(r.id)).get("name", r.id))}))
			"title":
				out.append(Loc.tf("UI_GUILD2_RW_TITLE", {"name": Loc.t(data.get_def("titles", str(r.id)).get("name", r.id))}))
			"cosmetic":
				out.append(Loc.tf("UI_GUILD2_RW_FRAME", {"name": Loc.t(data.get_def("frames", str(r.id)).get("name", r.id))}))
			_:
				out.append(Loc.tf("UI_QUESTS_RW_ITEM", {"n": NumberFormat.fmt(int(r.qty)), "name": Loc.t(data.item(str(r.id)).get("name", r.id))}))
	return out


## Ricompense come CHIP con icona e quantità (oro, oggetti, casse, tomi); le altre (reputazione, titolo, sblocco…) restano a testo.
## Il suggerimento di ogni chip è la riga completa di `reward_lines`. Solo presentazione.
static func reward_chips(preview: Array, data: Object) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "RewardChips"
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	for r in preview:
		var line := reward_lines([r], data)
		var full := line[0] if line.size() > 0 else ""
		var icon: Texture2D = null
		var text := full
		match str(r.kind):
			"gold":
				icon = IconLib.ui("ui_currency_gold")
				text = NumberFormat.fmt(int(r.qty))
			"item", "crate", "tome":
				var it: Dictionary = data.item(str(r.id))
				icon = IconLib.icon("crates" if str(r.kind) == "crate" else "items", str(r.id))
				text = "%s × %s" % [NumberFormat.fmt(int(r.qty)), Loc.t(it.get("name", r.id))]
		ScreenKit.chip(flow, text, icon, full)
	return flow


static func chapter_name(chapter: int, data: Object) -> String:
	for c in data.table("chapters"):
		if int(c.get("id", -1)) == chapter:
			return Loc.t(c.get("name", ""))
	return ""
