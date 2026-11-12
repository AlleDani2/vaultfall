class_name LevelEta
extends RefCounted
## «Tempo al livello» sempre visibile (G53, docs/16 §3.1): quanto manca al prossimo livello della mansione attiva, alla
## resa attesa di adesso. Solo lettura (SkillSystem): nessuna regola, nessuno stato. Per il combattimento non c'è una
## resa continua di XP della mansione: ritorna {} (la barra mostra solo l'attività).


## {skill, name, level, max, frac, seconds} oppure {} se non c'è una mansione attiva. seconds = -1 se la resa è 0.
static func info() -> Dictionary:
	var sk := Game.system("skills") as SkillSystem
	if sk == null:
		return {}
	var aid := sk.current_action()
	if aid.is_empty():
		return {}
	var skill := sk.skill_of(aid)
	var pr := sk.xp_progress(skill)
	var need := float(pr[1])
	var out := {"skill": skill, "name": Loc.t(DataRegistry.get_def("skills", skill).get("name", {})), "level": sk.level(skill),
		"max": need <= 0.0, "frac": 1.0 if need <= 0.0 else clampf(float(pr[0]) / need, 0.0, 1.0), "seconds": -1.0}
	if need > 0.0:
		var xph := float(sk.hourly(aid).xp)
		if xph > 0.0:
			out["seconds"] = maxf(0.0, (need - float(pr[0])) / xph * 3600.0)
	return out


## Testo breve per la barra in alto («Liv. 14 tra 12 min»). Vuoto se non c'è nulla da dire.
static func short_text(i: Dictionary) -> String:
	if i.is_empty():
		return ""
	if bool(i.max):
		return tr_key("UI_UIB_ETA_MAX")
	if float(i.seconds) < 0.0:
		return ""
	return Loc.tf("UI_UIB_ETA_TOP", {"lv": int(i.level) + 1, "time": NumberFormat.fmt_time(float(i.seconds))})


static func tr_key(k: String) -> String:
	return TranslationServer.translate(k)
