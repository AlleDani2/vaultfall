class_name MenuActivity
extends RefCounted
## Quali voci del menù laterale corrispondono a un'attività IN CORSO (resoconto UI 05). Funzione pura di lettura, come
## SidebarBadges: `marks()` ritorna {id voce: {role, state, frac, tip}}; MainScreen la disegna (MenuMark) a 2 Hz.
##   role   "main" = l'attività principale (una sola: mansione, Combattimento, Dungeon/Incursione/Boss mondiale/Breccia)
##          "side" = lavora in parallelo (Orto con raccolti in crescita, Spedizioni/Apprendisti, Tenuta che produce)
##   state  "run" in corso · "paused" orologio in pausa · "waiting" mansione ferma in attesa di materiali
##   frac   avanzamento del ciclo/della fase (0..1), -1 = nessuna barra
##   tip    riga da aggiungere al tooltip della voce, già tradotta
## Nessun numero di bilanciamento: tutto viene dai sistemi e dai dati.

const ROLE_MAIN := "main"
const ROLE_SIDE := "side"
const STATE_RUN := "run"
const STATE_PAUSED := "paused"
const STATE_WAITING := "waiting"


static func marks() -> Dictionary:
	var out: Dictionary = {}
	if not GameState.active:
		return out
	var main := main_mark()
	if not main.is_empty():
		out[str(main.id)] = main
	for m in _side_marks():
		var id := str(m.id)
		if out.has(id) and str(out[id].role) == ROLE_MAIN:
			continue              # la stessa voce non è insieme principale e parallela: vince la principale
		if out.has(id):
			out[id]["tip"] = str(out[id].tip) + "\n" + str(m.tip)     # due attività parallele sulla stessa voce (Gilda): righe in fila
			if float(out[id].frac) < 0.0:
				out[id]["frac"] = m.frac
			continue
		out[id] = m
	return out


## L'attività principale: {id, role, state, frac, tip, name} oppure {} se non si fa nulla. `name` = nome breve per l'indicatore ai bordi.
static func main_mark() -> Dictionary:
	if not GameState.active:
		return {}
	var sk := Game.system("skills") as SkillSystem
	var aid := sk.current_action() if sk != null else ""
	if not aid.is_empty():
		var skill := sk.skill_of(aid)
		var action_name := Loc.t(DataRegistry.action(aid).get("name", {}))
		var xph := float(sk.hourly(aid).get("xp", 0.0))
		var tip := Loc.tf("UI_MENUACT_SKILL", {"action": action_name, "xp": NumberFormat.fmt(xph)}) if xph > 0.0 \
			else Loc.tf("UI_MENUACT_SKILL_NOXP", {"action": action_name})
		var state := STATE_WAITING if sk.is_waiting() else (STATE_PAUSED if Clock.paused else STATE_RUN)
		if state == STATE_WAITING:
			tip += "\n" + TranslationServer.translate("UI_SKILLS_WAITING_MATERIALS")
		var q := Game.system("queue") as QueueSystem
		if q != null and q.size() > 0:
			tip += "\n" + Loc.tf("UI_MENUACT_QUEUE", {"n": q.size()})
		return _finish({"id": ScreenRegistry.menu_id_for_skill(skill), "role": ROLE_MAIN, "state": state,
			"frac": main_frac(), "tip": tip, "name": action_name})
	var act: Dictionary = GameState.data.get("activity", {})
	if str(act.get("type", "")) != "combat":
		return {}
	var mode := str(act.get("mode", ""))
	var combat := Game.system("combat") as CombatSystem
	match mode:
		"dungeon":
			var p: Dictionary = combat.dungeon_progress() if combat != null else {}
			var dname := Loc.t(DataRegistry.get_def("dungeons", str(act.get("dungeon", ""))).get("name", {}))
			var tip := Loc.tf("UI_MENUACT_DUNGEON", {"name": dname, "n": int(p.get("wave", 0)) + 1, "total": int(p.get("total", 1))})
			return _finish({"id": "dungeon", "role": ROLE_MAIN, "state": STATE_RUN, "frac": main_frac(), "tip": tip, "name": dname})
		"raid":
			var rname := Loc.t(DataRegistry.get_def("raids", str(act.get("raid", ""))).get("name", {}))
			return _finish({"id": "dungeon", "role": ROLE_MAIN, "state": STATE_RUN, "frac": -1.0,
				"tip": Loc.tf("UI_MENUACT_RAID", {"name": rname}), "name": rname})
		"wboss":
			var wname := Loc.t(DataRegistry.get_def("world_bosses", str(act.get("wb", ""))).get("name", {}))
			return _finish({"id": "dungeon", "role": ROLE_MAIN, "state": STATE_RUN, "frac": -1.0,
				"tip": Loc.tf("UI_MENUACT_WBOSS", {"name": wname}), "name": wname})
		"rift":
			var rift := TranslationServer.translate("UI_RAID_TAB_RIFT")
			return _finish({"id": "dungeon", "role": ROLE_MAIN, "state": STATE_RUN, "frac": -1.0,
				"tip": Loc.tf("UI_MENUACT_RIFT", {"n": int(act.get("floor", 1))}), "name": rift})
	var zone := ActivityText.combat_zone()
	var title := TranslationServer.translate("UI_MENU_COMBAT")
	var ctip: String = Loc.tf("UI_MENUACT_COMBAT", {"zone": zone}) if not zone.is_empty() else str(TranslationServer.translate("UI_MENUACT_COMBAT_NOZONE"))
	return _finish({"id": "combat", "role": ROLE_MAIN, "state": STATE_RUN, "frac": -1.0, "tip": ctip, "name": title})


## In pausa l'orologio è fermo: ogni attività si vede ancora (è «in corso»), ma ferma, e il tooltip lo dice.
static func _finish(m: Dictionary) -> Dictionary:
	if Clock.paused and str(m.state) == STATE_RUN:
		m["state"] = STATE_PAUSED
	if Clock.paused:
		m["tip"] = str(m.tip) + "\n" + TranslationServer.translate("UI_MENUACT_PAUSED")
	return m


## Avanzamento del ciclo dell'attività principale (aggiornabile a 10 Hz, costa quasi nulla): ciclo della mansione o ondata del dungeon.
static func main_frac() -> float:
	var sk := Game.system("skills") as SkillSystem
	if sk != null and not sk.current_action().is_empty():
		return sk.cycle_fraction()
	var combat := Game.system("combat") as CombatSystem
	if combat != null and combat.in_dungeon():
		var p := combat.dungeon_progress()
		return clampf(float(p.get("wave", 0)) / maxf(1.0, float(p.get("total", 1))), 0.0, 1.0)
	return -1.0


## Le attività in parallelo (non principali).
static func _side_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state := STATE_PAUSED if Clock.paused else STATE_RUN
	for r in ParallelsPanel.side_rows():
		var frac := float(r.frac)
		if str(r.id) == "farm" and (frac < 0.0 or frac >= 1.0):
			continue          # nulla di piantato, o tutto pronto: non cresce niente (per i raccolti pronti c'è il pallino numerico)
		if frac < 0.0:
			continue          # Spedizioni/Apprendisti senza lavori in corso
		var id := "guild" if str(r.screen) == "guild" else str(r.screen)
		out.append({"id": id, "role": ROLE_SIDE, "state": state, "frac": frac,
			"tip": Loc.tf("UI_MENUACT_ALSO", {"what": "%s · %s" % [str(r.title), str(r.value)]})})
	var es := Game.system("estate") as EstateSystem
	if es != null and (GameState.data.get("unlocks", []) as Array).has("feature:estate"):
		var per_h := es.total_units_per_hour()
		if per_h > 0.0:
			out.append({"id": "estate", "role": ROLE_SIDE, "state": state, "frac": -1.0,
				"tip": Loc.tf("UI_MENUACT_ALSO", {"what": Loc.tf("UI_MENUACT_ESTATE", {"n": NumberFormat.fmt(per_h)})})})
	return out
