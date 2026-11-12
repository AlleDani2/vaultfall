class_name Milestones
extends RefCounted
## Righe del pannello "Prossimi traguardi" (docs/03 §6, audit 03): prossimo sblocco, missione attiva,
## obiettivo più vicino. Funzione pura: legge QuestSystem e i dati, restituisce testi già tradotti.


## [{"text": String, "muted": bool}] — al più 3 righe di contenuto + 1 riga fissa sul domani.
static func lines(quests: QuestSystem, data: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var unlock_line := _next_unlock(quests, data)
	if not unlock_line.is_empty():
		out.append({"text": unlock_line, "muted": false})
	var main_id := quests.current_main()
	if not main_id.is_empty():
		var d := quests.quest_def(main_id)
		if quests.is_ready(main_id):
			out.append({"text": Loc.tf("UI_QUESTS_NEXT_QUEST_READY", {"title": QuestText.title(d)}), "muted": false})
		else:
			out.append({"text": Loc.tf("UI_QUESTS_NEXT_QUEST", {"title": QuestText.title(d),
				"pct": int(round(quests.fraction(main_id) * 100.0))}), "muted": false})
	var best := ""
	var best_f := -1.0
	for a in quests.active_quests():
		if a.id == main_id:
			continue
		var f := quests.fraction(a.id)
		if f > best_f:
			best_f = f
			best = a.id
	if not best.is_empty():
		out.append({"text": Loc.tf("UI_QUESTS_NEXT_CLOSEST", {"title": QuestText.title(quests.quest_def(best)),
			"pct": int(round(best_f * 100.0))}), "muted": false})
	if out.is_empty():
		out.append({"text": TranslationServer.translate("UI_QUESTS_NEXT_NOTHING"), "muted": false})
	out.append({"text": TranslationServer.translate("UI_QUESTS_NEXT_TOMORROW"), "muted": true})
	return out


## Primo sistema (mansione/funzione) non ancora aperto tra le missioni principali non completate.
static func _next_unlock(quests: QuestSystem, data: Object) -> String:
	var unlocks: Array = quests.ctx.state.get("unlocks", []) if quests.ctx != null else []
	for q in data.table("quests"):
		if str(q.get("kind", "")) != "main" or quests.is_done(str(q.id)):
			continue
		var names := PackedStringArray()
		for t in q.get("unlocks", []):
			if UnlockSystem.has_tutorial(str(t)) and not unlocks.has(t):
				names.append(UnlockSystem.token_name(str(t), data))
		if not names.is_empty():
			return Loc.tf("UI_QUESTS_NEXT_UNLOCK", {"name": ", ".join(names)})
	return ""
