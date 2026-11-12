class_name ActivityText
extends RefCounted
## Testo "cosa sta facendo l'eroe adesso" (mansione, combattimento o riposo), già tradotto. Unica fonte per la barra
## superiore di MainScreen e per il Riepilogo: così i due non dicono cose diverse. Solo lettura, nessuno stato.


## Testo dell'attività corrente. Vuoto se non c'è nessuna partita.
static func text() -> String:
	var sk := Game.system("skills") as SkillSystem
	var aid := sk.current_action() if sk != null else ""
	if not aid.is_empty():
		var skill_id := sk.skill_of(aid)
		return Loc.tf("UI_SKILLS_TOPBAR", {"skill": Loc.t(DataRegistry.get_def("skills", skill_id).get("name", {})),
			"lv": sk.level(skill_id), "action": Loc.t(DataRegistry.action(aid).get("name", {}))})
	var act: Dictionary = GameState.data.get("activity", {})
	if str(act.get("type", "")).is_empty():
		return TranslationServer.translate("UI_SKILLS_TOPBAR_IDLE")
	if str(act.type) == "combat":
		return combat_text(act)
	return ""


## Testo del combattimento in corso: «Combattimento · zona · mostro». I segmenti vuoti vengono omessi (mai separatori doppi,
## iniziali o finali). Senza zona (Breccia, Boss mondiale...) al posto della zona va il nome dell'attività speciale.
static func combat_text(act: Dictionary) -> String:
	var mode := str(act.get("mode", "zone"))
	var zone := Loc.t(DataRegistry.get_def("zones", str(act.get("zone", ""))).get("name", {})).strip_edges()
	if zone.is_empty():
		var special: String = {"rift": "UI_RAID_TAB_RIFT", "wboss": "UI_RAID_TAB_WB", "raid": "UI_RAID_TAB_RAIDS",
			"dungeon": "UI_RAID_TAB_DUNGEON"}.get(mode, "")
		zone = str(TranslationServer.translate(special)).strip_edges() if not special.is_empty() else ""
	var mid := str(act.get("monster", ""))
	var who := ""
	if not mid.is_empty():
		who = Loc.t(DataRegistry.get_def("monsters", mid).get("name", {})).strip_edges()
	elif mode in ["", "zone"]:
		who = str(TranslationServer.translate("UI_INTEG_TOPBAR_RANDOM"))     # «a caso» solo nelle zone normali
	if not zone.is_empty() and not who.is_empty():
		return Loc.tf("UI_INTEG_TOPBAR_COMBAT", {"zone": zone, "monster": who})
	var parts: Array[String] = [str(TranslationServer.translate("UI_MENU_COMBAT"))]
	for seg in [zone, who]:
		if not str(seg).is_empty():
			parts.append(str(seg))
	return " · ".join(parts)


## Nome della zona del combattimento in corso (vuoto se non si combatte): titolo breve per il riquadro Paralleli.
static func combat_zone() -> String:
	var act: Dictionary = GameState.data.get("activity", {})
	if str(act.get("type", "")) != "combat":
		return ""
	return Loc.t(DataRegistry.get_def("zones", str(act.get("zone", ""))).get("name", {}))


## True se c'è un'attività in corso (mansione o combattimento).
static func is_active() -> bool:
	var sk := Game.system("skills") as SkillSystem
	if sk != null and not sk.current_action().is_empty():
		return true
	return not str(GameState.data.get("activity", {}).get("type", "")).is_empty()
