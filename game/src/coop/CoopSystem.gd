class_name CoopSystem
extends GameSystem
## Modalità «Amici» senza rete (COOP-1). id "coop", sezione di stato `coop` (additiva: nessun bump di SCHEMA_VERSION).
## Studio e decisioni: docs/audit_2026-10-22/qa/60_STUDIO_COOP.md · formato dei codici/protocollo: .../69_PROTOCOLLO_COOP.md.
##
##  1. Codice-eroe («Scheda del Compagno»): export/import di una copia in sola lettura dello stato di combattimento.
##  2. Compagni d'armi: fino a 3 schede importate che occupano il posto di un mercenario nelle Incursioni, aiutano nei
##     Boss mondiali e nella Breccia. Potere = simulazione vera (CoopSim). Ricompense NORMALI per chi gioca: nulla va a chi
##     ha creato il codice, nessun oggetto o valuta si muove tra giocatori (CLAUDE.md regola 5: niente scambi).
##  3. Prova della settimana: stessa Breccia per tutti (CoopWeekly), punteggio confrontabile, classifica LOCALE di amici.
##
## Regole di sistema: classe pura, niente tempo reale (l'istante UNIX arriva dall'interfaccia come argomento), niente rete,
## nessuna telemetria. Tutto lo stato che conta sta in `state` (README_SISTEMI §9): nulla di privato influenza il futuro.
##
## Stato ctx.state.coop:
##   v, uid ("" = si deriva dalla partita), name, rev (schede esportate)
##   companions [{id, sheet{...}, enabled, added, expired, outdated}]
##   results {settimana: {uid: risultato}} (classifica locale) · mine {settimana: risultato migliore}
##   stats {exported, imported, raid_clears, weekly_runs} · unlocked · title_given · poll_t

const STATE_V := 1
const COMPANION_PREFIX := "c:"
const ROLES: PackedStringArray = ["defender", "healer", "striker"]
const SIM_CACHE_MAX := 512

var _rules: Dictionary = {}
var _sim: CoopSim = CoopSim.new()
var _self_cache: Dictionary = {}
var _wb_cache: Dictionary = {}
var _epoch: int = 0                      # cresce a ogni cambio dei compagni: invalida le cache (non influisce sullo stato)
var suspended: bool = false             # true durante la Prova della settimana: nessun compagno (punteggi confrontabili)


func _init() -> void:
	id = "coop"
	state_key = "coop"


func setup() -> void:
	_rules = ctx.data.rules("coop_rules")


func default_state() -> Variant:
	return {"v": STATE_V, "uid": "", "name": "", "rev": 0, "companions": [], "results": {}, "mine": {},
		"stats": {"exported": 0, "imported": 0, "raid_clears": 0, "weekly_runs": 0}, "unlocked": false, "title_given": false,
		"poll_t": 0.0}


func from_state(section: Variant) -> void:
	state = section
	if not (state is Dictionary):
		state = default_state()
		ctx.state[state_key] = state
	var d: Dictionary = default_state()
	for k in d:
		if not state.has(k) or typeof(state[k]) != typeof(d[k]):
			if typeof(d[k]) == TYPE_FLOAT and typeof(state.get(k)) == TYPE_INT:
				state[k] = float(state[k])
			else:
				state[k] = d[k]
	for k in d.stats:
		state.stats[k] = int(state.stats.get(k, 0))
	state["rev"] = int(state.rev)
	# le schede salvate si ricontrollano come quelle appena incollate (salvataggio manomesso o di un'altra versione dei dati)
	var keep: Array = []
	var seen: Dictionary = {}
	for c in state.companions:
		if not (c is Dictionary) or not (c.get("sheet") is Dictionary):
			continue
		var v := CoopSheet.sanitize(c.sheet, ctx.data, 0)
		if not bool(v.ok) or seen.has(str(v.sheet.uid)) or keep.size() >= int(_rules.companions.max):
			continue
		seen[str(v.sheet.uid)] = true
		keep.append(_record(v.sheet, bool(c.get("enabled", true)), int(c.get("added", 0)), bool(c.get("expired", false))))
	state["companions"] = keep
	# risultati della classifica locale: stessi controlli di quando si incollano (tipi e intervalli)
	for key in ["results", "mine"]:
		var clean: Dictionary = {}
		for wk in state[key]:
			var src: Variant = state[key][wk]
			if key == "mine":
				var vm := sanitize_result(src, 0)
				if bool(vm.ok):
					clean[str(wk)] = vm.result
				continue
			if not (src is Dictionary):
				continue
			var bucket: Dictionary = {}
			for uid in src:
				var vr := sanitize_result(src[uid], 0)
				if bool(vr.ok):
					bucket[str(uid)] = vr.result
			clean[str(wk)] = bucket
		state[key] = clean
	_self_cache.clear()
	_sim.clear_cache()


func int_paths() -> PackedStringArray:
	return PackedStringArray(["v", "rev", "stats.*", "companions[].added", "companions[].sheet.level", "companions[].sheet.issued",
		"companions[].sheet.rev", "companions[].sheet.era", "results.*.*.floor", "results.*.*.level", "results.*.*.issued",
		"mine.*.floor", "mine.*.level", "mine.*.issued"])


# ------------------------------------------------------------------ riferimenti

func _combat() -> Variant:
	return ctx.get_system("combat")


func _eg() -> Variant:
	var c: Variant = _combat()
	return c.eg if c != null else null


func rules() -> Dictionary:
	return _rules


func _outdated(sheet: Dictionary) -> bool:
	return str(sheet.get("dv", "")) != str(ctx.data.constants.get("data_version", ""))


# ------------------------------------------------------------------ identità (nessun dato personale)

## Identificativo della partita: derivato dalla data di creazione, non dall'utente. 16 cifre esadecimali.
func my_uid() -> String:
	if str(state.uid) != "":
		return str(state.uid)
	var base := "vf-uid|%d|%s" % [int(ctx.state.get("created_at_unix", 0)), str(ctx.state.get("mode", "normal"))]
	return CoopCodec.checksum(base) + CoopCodec.checksum(base + "|2")


## Marcatura «Cozy» della partita (ModeSystem.run_tags(), UI-B): vale per sempre una volta giocata in Cozy (`modes.cozy_used`).
## I risultati della Prova e le Schede la portano, così la classifica non mescola partite con e senza bonus.
func is_cozy() -> bool:
	var ms: Variant = ctx.get_system("modes")
	if ms != null and ms.has_method("run_tags"):
		return (ms.run_tags() as Array).has("cozy")
	return false


func my_name() -> String:
	var n := str(state.name)
	return n if not n.is_empty() else Loc.t(_rules.code.default_name)


func set_my_name(raw: String) -> String:
	var clean := CoopSheet.clean_name(raw, int(_rules.code.name_max))
	state["name"] = "" if clean == "?" else clean
	return my_name()


func is_unlocked() -> bool:
	return (ctx.state.get("unlocks", []) as Array).has(str(_rules.unlock.token))


# ------------------------------------------------------------------ esportazione

func _selected_title() -> String:
	var comp: Variant = ctx.get_system("compendium")
	if comp != null and comp.has_method("selected_title"):
		return str(comp.selected_title())
	return ""


## Scheda dell'Eroe corrente (Dictionary pulito). `now_unix` = istante UTC (dall'interfaccia).
func build_sheet(now_unix: int) -> Dictionary:
	var c: Variant = _combat()
	if c == null:
		return {}
	return CoopSheet.export_from(c, ctx.data, my_uid(), my_name(), _selected_title(), now_unix, int(state.rev) + 1, is_cozy())


func export_hero_code(now_unix: int) -> String:
	var sheet := build_sheet(now_unix)
	if sheet.is_empty():
		return ""
	var f: Dictionary = _rules.format
	var code := CoopCodec.pack(str(f.kind_hero), int(f.version), sheet, str(f.prefix), int(_rules.code.max_chars),
		int(_rules.code.max_json_bytes))
	if not code.is_empty():
		state["rev"] = int(state.rev) + 1
		state.stats["exported"] = int(state.stats.exported) + 1
	return code


# ------------------------------------------------------------------ importazione

## Importa un codice incollato (scheda o risultato). Ritorna {"ok", "kind", "status", "error", "name", "clamped"}.
## status: added · updated · same · older · result_added · result_updated · result_older
func import_code(text: String, now_unix: int) -> Dictionary:
	var f: Dictionary = _rules.format
	var r := CoopCodec.unpack(text, int(f.version), "", str(f.prefix), int(_rules.code.max_chars), int(_rules.code.max_json_bytes))
	if not bool(r.ok):
		return {"ok": false, "kind": "", "status": "", "error": str(r.error), "name": "", "clamped": 0}
	match str(r.kind):
		"H":
			return _import_hero(r.payload, now_unix)
		"R":
			return _import_result(r.payload, now_unix)
	return {"ok": false, "kind": str(r.kind), "status": "", "error": "kind", "name": "", "clamped": 0}


func _import_hero(payload: Dictionary, now_unix: int) -> Dictionary:
	var v := CoopSheet.sanitize(payload, ctx.data, now_unix)
	if not bool(v.ok):
		return {"ok": false, "kind": "H", "status": "", "error": str(v.error), "name": "", "clamped": 0}
	var sheet: Dictionary = v.sheet
	var uid := str(sheet.uid)
	if uid == my_uid():
		return {"ok": false, "kind": "H", "status": "", "error": "self", "name": str(sheet.name), "clamped": 0}
	var cs: Array = state.companions
	for i in cs.size():
		if str(cs[i].id) != uid:
			continue
		var old: Dictionary = cs[i].sheet
		var newer := int(sheet.issued) > int(old.issued) or (int(sheet.issued) == int(old.issued) and int(sheet.rev) > int(old.rev))
		if not newer:
			var same := int(sheet.issued) == int(old.issued) and int(sheet.rev) == int(old.rev)
			return {"ok": true, "kind": "H", "status": "same" if same else "older", "error": "", "name": str(old.name), "clamped": int(v.clamped)}
		cs[i] = _record(sheet, bool(cs[i].enabled), int(cs[i].added), _is_expired(sheet, now_unix))
		_touch()
		return {"ok": true, "kind": "H", "status": "updated", "error": "", "name": str(sheet.name), "clamped": int(v.clamped)}
	if cs.size() >= int(_rules.companions.max):
		return {"ok": false, "kind": "H", "status": "", "error": "full", "name": str(sheet.name), "clamped": int(v.clamped)}
	cs.append(_record(sheet, true, now_unix, _is_expired(sheet, now_unix)))
	state.stats["imported"] = int(state.stats.imported) + 1
	_touch()
	return {"ok": true, "kind": "H", "status": "added", "error": "", "name": str(sheet.name), "clamped": int(v.clamped)}


func _record(sheet: Dictionary, is_on: bool, added: int, expired: bool) -> Dictionary:
	return {"id": str(sheet.uid), "sheet": sheet, "enabled": is_on, "added": added, "expired": expired,
		"outdated": _outdated(sheet), "sig": CoopSheet.signature(sheet)}


func _touch() -> void:
	_epoch += 1
	_wb_cache.clear()
	_sim.clear_cache()
	var c: Variant = _combat()
	if c != null:
		CoopCombatAdapter.mark_dirty(c)               # le stime in cache delle squadre vanno rifatte
	ctx.events.important_event.emit("coop")


func _is_expired(sheet: Dictionary, now_unix: int) -> bool:
	if now_unix <= 0:
		return false
	return now_unix - int(sheet.issued) > int(_rules.companions.valid_days) * 86400


## Aggiorna i segnalini «scaduta»: lo chiama l'interfaccia (ha l'orologio) all'apertura della schermata e dopo un carico.
func refresh(now_unix: int) -> void:
	var changed := false
	for c in state.companions:
		var e := _is_expired(c.sheet, now_unix)
		changed = changed or e != bool(c.expired)
		c["expired"] = e
	if changed:
		_epoch += 1
		_wb_cache.clear()


# ------------------------------------------------------------------ compagni

func companions() -> Array:
	return state.companions


func get_companion(cid: String) -> Dictionary:
	for c in state.companions:
		if str(c.id) == cid:
			return c
	return {}


func remove_companion(cid: String) -> bool:
	var c := get_companion(cid)
	if c.is_empty():
		return false
	(state.companions as Array).erase(c)
	_touch()
	return true


func set_enabled(cid: String, on: bool) -> bool:
	var c := get_companion(cid)
	if c.is_empty():
		return false
	c["enabled"] = on
	_touch()
	return true


## «ok» · «expired» (scheda vecchia: si può aggiornare con un codice nuovo) · «outdated» (altra versione dei dati).
func companion_status(c: Dictionary) -> String:
	if bool(c.get("expired", false)):
		return "expired"
	if bool(c.get("outdated", false)):
		return "outdated"
	return "ok"


## Compagni che partecipano adesso: attivi, non scaduti, in ordine di id (deterministico), al massimo `companions.max`.
func active_companions() -> Array:
	var out: Array = []
	if suspended:
		return out
	for c in state.companions:
		if bool(c.enabled) and not bool(c.expired):
			out.append(c)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x.id) < str(y.id))
	return out.slice(0, int(_rules.companions.max))


static func puid(cid: String) -> String:
	return COMPANION_PREFIX + cid


static func is_puid(u: Variant) -> bool:
	return str(u).begins_with(COMPANION_PREFIX)


func companion_of_puid(u: String) -> Dictionary:
	return get_companion(u.trim_prefix(COMPANION_PREFIX)) if is_puid(u) else {}


func role_of(c: Dictionary) -> String:
	return str(_rules.roles.get(str(c.sheet["class"]), "striker"))


# ------------------------------------------------------------------ potere simulato

func _ratio_cap() -> float:
	return float(ctx.data.rules("mercenary_rules")["raid_roles"].get("ratio_cap", 1.5))


func _trim_cache() -> void:
	if _self_cache.size() > 8:
		_self_cache.clear()


## La Scheda del tuo Eroe (stessa esportazione dei codici), in cache finché non cambia il suo assetto.
func _self_sheet() -> Dictionary:
	var c: Variant = _combat()
	var key := CoopCombatAdapter.build_key(c)
	if _self_cache.get("key") == key:
		return _self_cache.sheet
	_trim_cache()
	var sheet := CoopSheet.export_from(c, ctx.data, my_uid(), my_name(), "", 0, 0)
	_self_cache = {"key": key, "sheet": sheet, "sig": CoopSheet.signature(sheet)}
	return sheet


func _mon_key(mon: Dictionary, ms: Dictionary) -> String:
	return "%s|%s|%s" % [str(mon.get("ckey", mon.get("id", ""))), str(ms.get("hp", 0.0)), str(ms.get("max_hit", 0.0))]


## Punteggio simulato di una Scheda contro `mon`/`ms` (in cache).
func score_of(sheet: Dictionary, sig: String, mon: Dictionary, ms: Dictionary, window_s: float, dt: float) -> float:
	var c: Variant = _combat()
	if _sim.cache_size() > SIM_CACHE_MAX:
		_sim.clear_cache()
	var key := "%s|%s|%s|%d" % [sig, _mon_key(mon, ms), str(window_s), CoopCombatAdapter.era(c)]
	var sc: Dictionary = _sim_cache_run(sheet, c, mon, ms, window_s, dt, key)
	return float(sc.score)


func _sim_cache_run(sheet: Dictionary, c: Variant, mon: Dictionary, ms: Dictionary, window_s: float, dt: float, key: String) -> Dictionary:
	return _sim.run(sheet, c, mon, ms, window_s, dt, float(_rules.sim.min_score), key)


## Qualità di un compagno rispetto al tuo Eroe: punteggio / tuo punteggio, tra 0 e il tetto dei mercenari.
func quality(comp: Dictionary, mon: Dictionary, ms: Dictionary, window_s: float, dt: float) -> float:
	var my_sheet := _self_sheet()
	var me: float = score_of(my_sheet, str(_self_cache.sig), mon, ms, window_s, dt)
	var sc: float = score_of(comp.sheet, str(comp.sig), mon, ms, window_s, dt)
	var cap := _ratio_cap()
	if sc <= 0.0:
		return 0.0
	if me <= 0.0:
		return cap
	return clampf(sc / me, 0.0, cap)


# ------------------------------------------------------------------ agganci di EndgameCombat

## Squadra dell'incursione con i compagni in squadra: occupano i posti liberi e, se non ce ne sono, quello del
## mercenario più debole. I compagni non si feriscono e non guadagnano XP: sono copie, non persone.
func party_with_companions(raid_id: String, party: Array) -> Array:
	var eg: Variant = _eg()
	var actives := active_companions()
	if eg == null or actives.is_empty():
		return party
	var size := int(eg.raid_def(raid_id).get("party", {}).get("size", 0))
	var out: Array = []
	for u in party:
		if not is_puid(u):
			out.append(str(u))
	var mercs: Variant = ctx.get_system("mercenaries")
	for c in actives:
		var pu := puid(str(c.id))
		if out.size() < size:
			out.append(pu)
			continue
		var worst := -1
		var wp := INF
		for i in out.size():
			if is_puid(out[i]) or mercs == null:
				continue
			var p := float(mercs.power_of_uid(str(out[i])))
			if p < wp:
				wp = p
				worst = i
		if worst >= 0:
			out[worst] = pu
	return out


func party_member_ok(u: String) -> bool:
	var c := companion_of_puid(u)
	return not c.is_empty() and bool(c.enabled) and not bool(c.expired)


## Contributo dei compagni di `party` a un'incursione: {"power": in unità dei mercenari, "roles": {ruolo: bonus tratti}}.
## Potere di un compagno = qualità × (potere richiesto / dimensione di riferimento): un amico forte quanto te vale un
## «quarto» della squadra, come un mercenario al potere giusto.
func raid_contrib(raid_id: String, party: Array) -> Dictionary:
	var out := {"power": 0.0, "roles": {}}
	var eg: Variant = _eg()
	var c: Variant = _combat()
	if eg == null or c == null:
		return out
	var rd: Dictionary = eg.raid_def(raid_id)
	var mon: Dictionary = ctx.data.get_def("monsters", str(rd.get("boss", "")))
	if mon.is_empty():
		return out
	var ms: Dictionary = CoopCombatAdapter.scaled(c, mon)
	var rr: Dictionary = ctx.data.rules("mercenary_rules")["raid_roles"]
	var unit := float(eg.raid_required_power(raid_id)) / maxf(float(rr["power_party_size"]), 1.0)
	for u in party:
		if not is_puid(u):
			continue
		var comp := companion_of_puid(str(u))
		if comp.is_empty() or not bool(comp.enabled):
			continue
		var q := quality(comp, mon, ms, float(_rules.sim.window_s), float(eg.PASS_DT))
		out.power = float(out.power) + q * unit
		out.roles[role_of(comp)] = float(out.roles.get(role_of(comp), 0.0))
	return out


## Effetti di ruolo dei compagni alla Breccia (piano `fl`): stesso modello della squadra d'incursione, senza mercenari.
## {} se non ci sono compagni attivi.
func rift_fx(fl: int) -> Dictionary:
	var actives := active_companions()
	var eg: Variant = _eg()
	var c: Variant = _combat()
	if actives.is_empty() or eg == null or c == null:
		return {}
	var mon: Dictionary = eg.rift_mon(fl, 0)
	var ms: Dictionary = CoopCombatAdapter.scaled(c, mon)
	var rr: Dictionary = ctx.data.rules("mercenary_rules")["raid_roles"]
	var psize := maxf(float(rr["power_party_size"]), 1.0)
	var ratio := 0.0
	var present: Dictionary = {}
	for comp in actives:
		var q := quality(comp, mon, ms, float(_rules.sim.rift_window_s), float(eg.RIFT_PASS_DT))
		ratio += q / psize
		present[role_of(comp)] = true
	var f := minf(ratio, float(rr["ratio_cap"]))
	var out := {"required": 0.0, "power": ratio, "ratio": ratio, "f": f, "defender": 0.0, "healer": 0.0, "striker": 0.0}
	for role in ROLES:
		if present.has(role):
			out[role] = f
	return out


## Ritmo aggiuntivo (frazione di vita del boss al secondo) degli amici in un boss mondiale. `base` = ritmo di un alleato.
func wb_ally_bonus(d: Dictionary, base: float) -> float:
	var ckey := "%s|%d|%d|%s" % [str(d.get("id", "")), int(_combat()._era()) if _combat() != null else 1, _epoch, str(base)]
	if _wb_cache.has(ckey):
		return float(_wb_cache[ckey])
	var v := _wb_bonus(d, base)
	_wb_cache[ckey] = v
	return v


func _wb_bonus(d: Dictionary, base: float) -> float:
	var actives := active_companions()
	var c: Variant = _combat()
	if actives.is_empty() or c == null:
		return 0.0
	var mon: Dictionary = ctx.data.get_def("monsters", str(d.get("boss", "")))
	if mon.is_empty():
		return 0.0
	var ms: Dictionary = CoopCombatAdapter.scaled(c, mon)
	var wbr: Dictionary = _rules.world_boss
	var total := 0.0
	for comp in actives:
		var s: float = score_of(comp.sheet, str(comp.sig), mon, ms, float(_rules.sim.window_s), float(_eg().PASS_DT))
		total += minf(float(wbr.cap_mult) * base, float(wbr.weight) * s)
	return total


## Vittoria in un'incursione: sblocca la voce «Amici» e, se c'era un compagno in squadra, conta e dà il titolo.
func on_raid_win(a: Dictionary) -> void:
	_grant_unlock()
	var with_friend := false
	for u in a.get("party", []):
		if is_puid(u):
			with_friend = true
	if not with_friend:
		return
	state.stats["raid_clears"] = int(state.stats.raid_clears) + 1
	if not bool(state.title_given):
		var comp: Variant = ctx.get_system("compendium")
		if comp != null and comp.has_method("grant_title"):
			comp.grant_title(str(_rules.title))
		state["title_given"] = true


func _grant_unlock() -> void:
	if bool(state.unlocked) and is_unlocked():
		return
	var un: Variant = ctx.get_system("unlock")
	var tok := str(_rules.unlock.token)
	if un != null and un.has_method("grant"):
		un.grant(tok)
	elif not (ctx.state.unlocks as Array).has(tok):
		(ctx.state.unlocks as Array).append(tok)
	state["unlocked"] = true


## Ogni `poll_s`: se è sbloccata una qualunque incursione (gettone «raid:*»), compare la voce «Amici».
func tick(dt: float) -> void:
	if bool(state.unlocked) and is_unlocked():
		return
	state["poll_t"] = float(state.poll_t) + dt
	if float(state.poll_t) < float(_rules.unlock.poll_s):
		return
	state["poll_t"] = 0.0
	_poll_unlock()


func _poll_unlock() -> void:
	for t in ctx.state.get("unlocks", []):
		if str(t).begins_with("raid:"):
			_grant_unlock()
			return


func simulate_offline(_seconds: float) -> Dictionary:
	if not (bool(state.unlocked) and is_unlocked()):
		_poll_unlock()
	return {}


# ------------------------------------------------------------------ Prova della settimana

func week_info(now_unix: int) -> Dictionary:
	var w := CoopWeekly.week_of(now_unix)
	var eg: Variant = _eg()
	if eg != null:
		w["rift"] = CoopWeekly.rift_def_for(str(w.id), eg.rift_def(), ctx.data)
	return w


func rift_unlocked() -> bool:
	var eg: Variant = _eg()
	return eg != null and bool(eg.rift_unlocked())


func rift_available() -> bool:
	var eg: Variant = _eg()
	return eg != null and not eg.rift_def().is_empty()


## Tenta la Breccia della settimana con il TUO Eroe (nessun compagno, nessuna ricompensa): passaggio in valori attesi,
## quindi lo stesso assetto dà sempre lo stesso punteggio. Ritorna il risultato (anche se non migliora il precedente).
func weekly_run(now_unix: int) -> Dictionary:
	var eg: Variant = _eg()
	var c: Variant = _combat()
	if eg == null or c == null or not rift_available():
		return {}
	var wk := CoopWeekly.week_of(now_unix)
	if not _valid_week_id(str(wk.id)):
		return {}          # orologio impossibile (1970, anno 9999...): il risultato sparirebbe al ricaricamento (QA 83 C-11)
	var def: Dictionary = CoopWeekly.rift_def_for(str(wk.id), eg.rift_def(), ctx.data)
	var res := _dry_rift(def)
	var entry := {"uid": my_uid(), "name": my_name(), "class": str(c.state["class"]), "spec": str(c.state.get("spec", "")),
		"level": int(c.hero_level()), "week": str(wk.id), "floor": int(res.floor), "t": float(res.t), "dmg": float(res.dmg),
		"issued": now_unix, "cozy": is_cozy()}
	state.stats["weekly_runs"] = int(state.stats.weekly_runs) + 1
	_store_result(entry, true)
	return entry


## Percorre i piani della Breccia `def` con l'Eroe attuale finché la somma dei rischi di morte arriva a 1 (stesso criterio della
## Breccia offline e della stima del piano limite). Ritorna {"floor": piano dove si cade (o il tetto), "t", "dmg"}.
func _dry_rift(def: Dictionary) -> Dictionary:
	var eg: Variant = _eg()
	var c: Variant = _combat()
	var cap := int(_rules.weekly.max_floors)
	suspended = true
	eg.rift_override = def
	eg.clear_rift_caches()
	var evals: Dictionary = {}
	var hazard := 0.0
	var t := 0.0
	var dmg := 0.0
	var fl := 1
	while fl <= cap:
		var ev: Dictionary = CoopCombatAdapter.rift_floor_eval(eg, fl, evals)
		hazard += float(ev.p)
		if hazard >= 1.0:
			break
		t += float(ev.t)
		for i in eg.rift_monsters_on(fl):
			dmg += float(CoopCombatAdapter.scaled(c, eg.rift_mon(fl, i)).hp)
		fl += 1
	eg.rift_override = {}
	eg.clear_rift_caches()
	suspended = false
	return {"floor": fl, "t": t, "dmg": dmg}


## Ordine della classifica: più piani, poi meno tempo, poi più danni, poi nome/uid (stabile).
static func better(x: Dictionary, y: Dictionary) -> bool:
	if int(x.floor) != int(y.floor):
		return int(x.floor) > int(y.floor)
	if not is_equal_approx(float(x.t), float(y.t)):
		return float(x.t) < float(y.t)
	if not is_equal_approx(float(x.dmg), float(y.dmg)):
		return float(x.dmg) > float(y.dmg)
	if str(x.name) != str(y.name):
		return str(x.name) < str(y.name)
	return str(x.uid) < str(y.uid)


func _store_result(entry: Dictionary, mine: bool) -> String:
	var wk := str(entry.week)
	var results: Dictionary = state.results
	var bucket: Dictionary = results.get(wk, {})
	var uid := str(entry.uid)
	var status := "result_added"
	if bucket.has(uid):
		var old: Dictionary = bucket[uid]
		if better(entry, old):
			status = "result_updated"
		elif int(entry.floor) == int(old.floor) and is_equal_approx(float(entry.t), float(old.t)) \
				and is_equal_approx(float(entry.dmg), float(old.dmg)):
			status = "result_same"
			return status
		else:
			return "result_older"
	bucket[uid] = entry
	var maxn := int(_rules.weekly.max_entries_per_week)
	if bucket.size() > maxn:
		var rows: Array = bucket.values()
		rows.sort_custom(better)
		for i in range(maxn, rows.size()):
			if str(rows[i].uid) != my_uid():
				bucket.erase(str(rows[i].uid))
	results[wk] = bucket
	if mine:
		state.mine[wk] = entry
	var weeks: Array = results.keys()
	weeks.sort()
	var hist := int(_rules.weekly.history_weeks)
	while weeks.size() > hist:
		results.erase(weeks[0])
		state.mine.erase(weeks[0])
		weeks.remove_at(0)
	return status


func my_result(week_id: String) -> Dictionary:
	return state.mine.get(week_id, {})


func export_result_code(week_id: String) -> String:
	var r := my_result(week_id)
	if r.is_empty():
		return ""
	var f: Dictionary = _rules.format
	return CoopCodec.pack(str(f.kind_result), int(f.version), r, str(f.prefix), int(_rules.code.max_chars), int(_rules.code.max_json_bytes))


func _import_result(payload: Dictionary, now_unix: int) -> Dictionary:
	var v := sanitize_result(payload, now_unix)
	if not bool(v.ok):
		return {"ok": false, "kind": "R", "status": "", "error": str(v.error), "name": "", "clamped": 0}
	var entry: Dictionary = v.result
	if str(entry.uid) == my_uid():
		return {"ok": false, "kind": "R", "status": "", "error": "self", "name": str(entry.name), "clamped": 0}
	var status := _store_result(entry, false)
	if status == "result_added" or status == "result_updated":
		_touch()
	return {"ok": true, "kind": "R", "status": status, "error": "", "name": str(entry.name), "clamped": int(v.clamped), "week": str(entry.week)}


## Validazione di un risultato (intervalli del gioco: piani fino al tetto, tempi e danni finiti e non negativi).
func sanitize_result(raw: Variant, now_unix: int) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false, "result": {}, "error": "shape", "clamped": 0}
	var r: Dictionary = raw
	for k in CoopSheet.FORBIDDEN_KEYS:
		if r.has(k):
			return {"ok": false, "result": {}, "error": "forbidden", "clamped": 0}
	var uid := CoopSheet._clean_id(r.get("uid"), 16)
	var week := str(r.get("week", ""))
	if uid.is_empty() or not _valid_week_id(week):
		return {"ok": false, "result": {}, "error": "shape", "clamped": 0}
	if now_unix > 0:
		if week > str(CoopWeekly.week_of(now_unix + int(_rules.companions.future_slack_s)).id):
			return {"ok": false, "result": {}, "error": "future", "clamped": 0}
		if week < str(CoopWeekly.week_of(now_unix - int(_rules.weekly.old_result_days) * 86400).id):
			return {"ok": false, "result": {}, "error": "old", "clamped": 0}
	var cap := int(_rules.weekly.max_floors)
	var clamped := 0
	var fl_raw := CoopSheet._num(r.get("floor"), 0.0)
	var fl := clampi(int(fl_raw), 1, cap + 1)
	var t_raw := CoopSheet._num(r.get("t"), 0.0)
	var t := clampf(t_raw, 0.0, 1.0e9)
	var dmg_raw := CoopSheet._num(r.get("dmg"), 0.0)
	var dmg := clampf(dmg_raw, 0.0, 1.0e30)
	if fl != int(fl_raw) or t != t_raw or dmg != dmg_raw:
		clamped += 1
	var cls := str(r.get("class", ""))
	if ctx.data.get_def("classes", cls).is_empty():
		cls = ""
	var spec := str(r.get("spec", ""))
	if ctx.data.get_def("classes", spec).is_empty():
		spec = ""
	return {"ok": true, "error": "", "clamped": clamped, "result": {"uid": uid, "name": CoopSheet.clean_name(str(r.get("name", "")), int(_rules.code.name_max)),
		"class": cls, "spec": spec, "level": clampi(int(CoopSheet._num(r.get("level"), 1.0)), 1, int(ctx.data.constants.level_cap)),
		"week": week, "floor": fl, "t": t, "dmg": dmg, "issued": int(CoopSheet._num(r.get("issued"), 0.0)),
		"cozy": bool(r.get("cozy", false)) if r.get("cozy") is bool else false}}


static func _valid_week_id(w: String) -> bool:
	if w.length() != 8 or w[4] != "-" or w[5] != "W":
		return false
	var y := w.substr(0, 4)
	var n := w.substr(6, 2)
	if not y.is_valid_int() or not n.is_valid_int():
		return false
	var yi := int(y)
	var ni := int(n)
	return yi >= 2020 and yi <= 2200 and ni >= 1 and ni <= 53


## Classifica LOCALE di una settimana (tua più degli amici di cui hai incollato il codice-risultato): ordinata.
func leaderboard(week_id: String) -> Array:
	var rows: Array = (state.results.get(week_id, {}) as Dictionary).values()
	rows = rows.duplicate()
	rows.sort_custom(better)
	var out: Array = []
	var me := my_uid()
	for i in rows.size():
		var r: Dictionary = rows[i].duplicate()
		r["rank"] = i + 1
		r["me"] = str(r.uid) == me
		out.append(r)
	return out


func weeks_with_results() -> Array:
	var w: Array = state.results.keys()
	w.sort()
	w.reverse()
	return w
