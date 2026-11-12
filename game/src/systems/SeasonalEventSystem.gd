class_name SeasonalEventSystem
extends GameSystem
## Eventi stagionali (docs/27 §2, T-11.3): 4 eventi l'anno (data/events.json), valuta evento, Cassa cosmetica, missioni,
## bonus temporaneo, Negozio a prezzo fisso e Eco (rigioco di un evento passato a metà ritmo). Funziona offline.
##
## Principi anti-FOMO (docs/audit_2026-10-22/03_retention.md): nessuna serie di accessi, nessuna penalità per l'assenza,
## nessuna ricompensa persa per sempre. Ogni cosmetico dell'evento si recupera: (1) l'evento torna ogni anno, (2) l'Eco fuori
## dalle date, (3) il Negozio lo vende a prezzo fisso. La Cassa evento è SOLO cosmetica: nessun potere. Il bonus temporaneo
## (modificatori fonte "event:<id>") esiste solo durante le date, mai nell'Eco.
##
## CALENDARIO. La data è quella LOCALE del sistema (fuso compreso), letta da `wall_source` (Callable -> {unix, tz_min, ok}); in
## gioco è `system_wall` (unico punto che tocca l'orologio: i test lo sostituiscono). Se l'orologio non è affidabile (data
## anteriore a `min_valid_unix`, oppure torna indietro di più di `clock_tolerance_s` rispetto al tempo di gioco trascorso dall'ultimo
## punto fidato) il calendario avanza col TEMPO DI GIOCO a partire dall'ultima data fidata ("data virtuale"): nessun danno e nessun
## premio extra, perché valuta e missioni dipendono dal tempo giocato (1 unità ogni `drop_every_s`), non dalla data, e ogni edizione
## ha un tetto (`max_drops_per_occurrence`). Un orologio spostato in avanti non si distingue da un'assenza lunga: vale la stessa
## garanzia (si guadagna solo giocando, con il tetto).
##
## Stato (GameState.data.seasonal):
##   opt_out bool · game_s float (tempo di gioco accumulato) · anchor_unix int / anchor_game_s float (ultimo punto fidato) ·
##   tz_min int · echo_event String ("" = l'ultimo concluso) · acc {chiave: s} (resti delle cadute) · earned {chiave: n} (cadute
##   già ottenute, per il tetto) · occ {chiave: {prog {id_missione: n}, claimed [id], title bool}} · owned [id cosmetici ottenuti] ·
##   last_notice String · stats {drops, bought, claimed}.
## Chiave di edizione: "<evento>:<anno d'inizio>"; chiave dell'Eco: "<evento>:echo".

const SOURCE_PREFIX := "event:"
const ECHO_SUFFIX := "echo"
const EVAL_PERIOD_S := 1.0
const MODE_NONE := "none"
const MODE_EVENT := "event"
const MODE_ECHO := "echo"
const MODE_OFF := "off"
const KINDS: PackedStringArray = ["actions", "kills", "crates", "currency"]

## Sorgente dell'orologio: Callable senza argomenti -> {"unix": int, "tz_min": int, "ok": bool}.
var wall_source: Callable = Callable()

var _fake_wall: Dictionary = {}
var _since_eval: float = 1e9
var _cur: Dictionary = {}                # contesto corrente: {mode, event, occ, currency, every_s, cap} (vuoto = niente cadute)
var _cal: Dictionary = {}                # ultimo calendario valutato
var _mods_event: String = "?"            # evento di cui sono applicati i modificatori ("" = nessuno, "?" = da riapplicare)
var _crate_events: Dictionary = {}       # id cassa evento -> id evento


func _init() -> void:
	id = "seasonal"
	state_key = "seasonal"


func default_state() -> Variant:
	return _complete({})


func setup() -> void:
	if not wall_source.is_valid():
		wall_source = SeasonalEventSystem.system_wall
	_crate_events.clear()
	for ev in ctx.data.table("events"):
		_crate_events[str(ev.crate)] = str(ev.id)
	if ctx.events != null:
		ctx.events.action_completed.connect(_on_action)
		ctx.events.action_batch_completed.connect(_on_action_batch)
		ctx.events.monster_killed.connect(_on_kill)
		ctx.events.monsters_killed_batch.connect(_on_kill_batch)
		ctx.events.crate_opened.connect(_on_crate_opened)


func from_state(section: Variant) -> void:
	state = _complete(section if section is Dictionary else {})
	_since_eval = 1e9
	_mods_event = "?"
	_cur = {}
	_cal = {}
	_evaluate()


func int_paths() -> PackedStringArray:
	return PackedStringArray(["anchor_unix", "tz_min", "earned.*", "occ.*.prog.*", "stats.*"])


static func _complete(s: Dictionary) -> Dictionary:
	var base := {"opt_out": false, "game_s": 0.0, "anchor_unix": 0, "anchor_game_s": 0.0, "tz_min": 0, "echo_event": "",
		"acc": {}, "earned": {}, "occ": {}, "owned": [], "last_notice": "", "stats": {}}
	for k in base:
		if not s.has(k) or typeof(s[k]) != typeof(base[k]):
			if k in ["game_s", "anchor_game_s"] and (s.get(k) is int):
				s[k] = float(s[k])
			elif k in ["anchor_unix", "tz_min"] and (s.get(k) is float):
				s[k] = int(s[k])
			else:
				s[k] = base[k]
	return s


# ------------------------------------------------------------------ orologio

## L'unico punto che legge l'orologio del sistema (i test impostano `wall_source`).
## Nelle build di sviluppo: la variabile d'ambiente VAULTFALL_FAKE_DATE=AAAA-MM-GG simula quel giorno (alle 12:00, poi l'ora
## scorre davvero) per provare gli eventi a mano; sotto GUT, senza la variabile, la data è neutra (1/6/2026, nessun evento in corso),
## così i test degli altri sistemi non dipendono dal giorno in cui girano.
static func system_wall() -> Dictionary:
	if OS.is_debug_build():
		var fake := OS.get_environment("VAULTFALL_FAKE_DATE").strip_edges()
		if fake.is_empty() and _under_gut():
			fake = "2026-06-01"
		var p := fake.split("-")
		if p.size() == 3 and p[0].is_valid_int() and p[1].is_valid_int() and p[2].is_valid_int():
			return {"unix": unix_of(int(p[0]), int(p[1]), int(p[2]), 12) + floori(float(Time.get_ticks_msec()) / 1000.0), "tz_min": 0, "ok": true}
	var tz: Dictionary = Time.get_time_zone_from_system()
	return {"unix": int(Time.get_unix_time_from_system()), "tz_min": int(tz.get("bias", 0)), "ok": true}


static var _gut_checked: int = -1


static func _under_gut() -> bool:
	if _gut_checked < 0:
		_gut_checked = 0
		for a in OS.get_cmdline_args():
			if a.contains("gut_cmdln") or a.begins_with("-gdir"):
				_gut_checked = 1
	return _gut_checked == 1


## Sorgente fissa per i test: `sys.set_wall(unix, tz_min, ok)`.
func set_wall(unix: int, tz_min: int = 0, ok: bool = true) -> void:
	_fake_wall = {"unix": unix, "tz_min": tz_min, "ok": ok}
	wall_source = Callable(self, "_fake_wall_read")


func _fake_wall_read() -> Dictionary:
	return _fake_wall


func _cfg() -> Dictionary:
	return ctx.data.rules("event_rules").get("seasonal", {})


func _read_wall() -> Dictionary:
	var w: Variant = wall_source.call() if wall_source.is_valid() else {}
	if not (w is Dictionary):
		return {"unix": 0, "tz_min": int(state.tz_min), "ok": false}
	var unix := int(w.get("unix", 0))
	return {"unix": unix, "tz_min": int(w.get("tz_min", int(state.tz_min))),
		"ok": bool(w.get("ok", true)) and unix >= int(_cfg()["min_valid_unix"])}


# ------------------------------------------------------------------ date (aritmetica civile, senza Time)

static func days_from_civil(y: int, m: int, d: int) -> int:
	var yy := y - (1 if m <= 2 else 0)
	var era := floori(float(yy) / 400.0)
	var yoe := yy - era * 400
	var mp := (m + 9) % 12
	var doy := floori(float(153 * mp + 2) / 5.0) + d - 1
	var doe := yoe * 365 + floori(float(yoe) / 4.0) - floori(float(yoe) / 100.0) + doy
	return era * 146097 + doe - 719468


## (anno, mese, giorno) del giorno `z` dall'epoca.
static func civil_from_days(z: int) -> Vector3i:
	var zz := z + 719468
	var era := floori(float(zz) / 146097.0)
	var doe := zz - era * 146097
	var yoe := floori(float(doe - floori(float(doe) / 1460.0) + floori(float(doe) / 36524.0) - floori(float(doe) / 146096.0)) / 365.0)
	var y := yoe + era * 400
	var doy := doe - (365 * yoe + floori(float(yoe) / 4.0) - floori(float(yoe) / 100.0))
	var mp := floori(float(5 * doy + 2) / 153.0)
	var d := doy - floori(float(153 * mp + 2) / 5.0) + 1
	var m := mp + 3 if mp < 10 else mp - 9
	return Vector3i(y + (1 if m <= 2 else 0), m, d)


## Secondi Unix di una data/ora UTC (utile ai test).
static func unix_of(y: int, m: int, d: int, hh: int = 0, mm: int = 0) -> int:
	return days_from_civil(y, m, d) * 86400 + hh * 3600 + mm * 60


static func _md(s: String) -> Vector2i:
	return Vector2i(int(s.substr(0, 2)), int(s.substr(3, 2)))


## Finestra dell'edizione che INIZIA nell'anno `y`: {start, end} in secondi locali (fine = mezzanotte dopo l'ultimo giorno).
func window(ev: Dictionary, y: int) -> Dictionary:
	var s := _md(str(ev.dates.start))
	var e := _md(str(ev.dates["end"]))
	var wraps := s.x * 100 + s.y > e.x * 100 + e.y
	return {"start": days_from_civil(y, s.x, s.y) * 86400, "end": (days_from_civil(y + (1 if wraps else 0), e.x, e.y) + 1) * 86400, "year": y}


## Edizione attiva di `ev` al secondo locale `t` ({} se nessuna).
func active_window(ev: Dictionary, t: int) -> Dictionary:
	var yr := civil_from_days(floori(float(t) / 86400.0)).x
	for y in [yr - 1, yr]:
		var w := window(ev, y)
		if int(w.start) <= t and t < int(w["end"]):
			return w
	return {}


## Prima edizione di `ev` che INIZIA dopo `t`.
func next_window(ev: Dictionary, t: int) -> Dictionary:
	var yr := civil_from_days(floori(float(t) / 86400.0)).x
	for y in [yr - 1, yr, yr + 1, yr + 2]:
		var w := window(ev, y)
		if int(w.start) > t:
			return w
	return {}


## Ultima edizione conclusa di `ev` (fine <= t).
func last_window(ev: Dictionary, t: int) -> Dictionary:
	var yr := civil_from_days(floori(float(t) / 86400.0)).x
	var best: Dictionary = {}
	for y in [yr - 2, yr - 1, yr]:
		var w := window(ev, y)
		if int(w["end"]) <= t and (best.is_empty() or int(w["end"]) > int(best["end"])):
			best = w
	return best


func occ_key(event_id: String, year: int) -> String:
	return "%s:%d" % [event_id, year]


func echo_key(event_id: String) -> String:
	return "%s:%s" % [event_id, ECHO_SUFFIX]


# ------------------------------------------------------------------ valutazione del calendario

## Calcola il calendario ADESSO (aggiorna il punto fidato e il contesto delle cadute). Si chiama ogni secondo di gioco e dalla UI.
func _evaluate() -> Dictionary:
	if state == null:
		return {}
	var cfg := _cfg()
	var w := _read_wall()
	var tol := int(cfg["clock_tolerance_s"])
	var anchor := int(state.anchor_unix)
	var virt := anchor + int(round(float(state.game_s) - float(state.anchor_game_s)))
	var trusted := false
	var unix := 0
	if bool(w.ok) and (anchor <= 0 or int(w.unix) >= virt - tol):
		trusted = true
		unix = int(w.unix)
		state.anchor_unix = unix
		state.anchor_game_s = float(state.game_s)
		state.tz_min = int(w.tz_min)
	elif anchor > 0:
		unix = virt
	var cal := {"ok": unix > 0, "trusted": trusted, "unix": unix, "local_s": unix + int(state.tz_min) * 60 if unix > 0 else 0,
		"mode": MODE_NONE, "event": "", "occ": "", "ends_in_s": 0, "next_event": "", "next_in_s": 0, "echo_event": ""}
	if not bool(cal.ok):
		_cal = cal
		_cur = {}
		_apply_mods("")
		return cal
	var t := int(cal.local_s)
	var evs: Array = ctx.data.table("events")
	var best_next := {}
	var best_last := {}
	for ev in evs:
		var aw := active_window(ev, t)
		if not aw.is_empty():
			cal.mode = MODE_EVENT
			cal.event = str(ev.id)
			cal.occ = occ_key(str(ev.id), int(aw.year))
			cal.ends_in_s = int(aw["end"]) - t
		else:
			var nw := next_window(ev, t)
			if not nw.is_empty() and (best_next.is_empty() or int(nw.start) < int(best_next.start)):
				best_next = {"event": str(ev.id), "start": int(nw.start)}
			var lw := last_window(ev, t)
			if not lw.is_empty() and (best_last.is_empty() or int(lw["end"]) > int(best_last["end"])):
				best_last = {"event": str(ev.id), "end": int(lw["end"])}
	if not best_next.is_empty():
		cal.next_event = best_next.event
		cal.next_in_s = int(best_next.start) - t
	# Eco: l'evento scelto, altrimenti l'ultimo concluso
	var echo_id := str(state.echo_event)
	if echo_id.is_empty() or not ctx.data.has_def("events", echo_id):
		echo_id = str(best_last.get("event", ""))
	cal.echo_event = echo_id
	if str(cal.mode) == MODE_NONE and not echo_id.is_empty():
		cal.mode = MODE_ECHO
		cal.event = echo_id
		cal.occ = echo_key(echo_id)
	if bool(state.opt_out):
		cal["calendar_mode"] = cal.mode
		cal.mode = MODE_OFF
	_cal = cal
	_set_context(cal)
	return cal


func _set_context(cal: Dictionary) -> void:
	var cfg := _cfg()
	var mode := str(cal.mode)
	var unlocked := has_token()
	if mode == MODE_EVENT:
		var ev: Dictionary = ctx.data.get_def("events", str(cal.event))
		_cur = {"mode": mode, "event": str(cal.event), "occ": str(cal.occ), "currency": str(ev.currency),
			"every_s": float(ev.get("currency_drop_every_s", cfg["drop_every_s"])), "cap": int(cfg["max_drops_per_occurrence"])} if unlocked else {}
		_apply_mods(str(cal.event))
		_notify_start(cal)
	elif mode == MODE_ECHO:
		var ev2: Dictionary = ctx.data.get_def("events", str(cal.event))
		_cur = {"mode": mode, "event": str(cal.event), "occ": str(cal.occ), "currency": str(ev2.currency),
			"every_s": float(cfg["echo_every_s"]), "cap": int(cfg["max_drops_echo"])} if unlocked else {}
		_apply_mods("")
		_notify_end(cal)
	else:
		_cur = {}
		_apply_mods("")


func has_token() -> bool:
	var tok := str(_cfg().get("unlock_token", ""))
	return tok.is_empty() or (ctx.state.get("unlocks", []) as Array).has(tok)


func _apply_mods(event_id: String) -> void:
	if event_id == _mods_event:
		return
	_mods_event = event_id
	ctx.modifiers.clear_prefix(SOURCE_PREFIX)
	if event_id.is_empty():
		return
	var ev: Dictionary = ctx.data.get_def("events", event_id)
	ctx.modifiers.set_source(SOURCE_PREFIX + event_id, ev.get("modifiers", []))


func _notify_start(cal: Dictionary) -> void:
	var key := "start:" + str(cal.occ)
	if str(state.last_notice) == key or ctx.events == null or not has_token():
		return
	state.last_notice = key
	var ev: Dictionary = ctx.data.get_def("events", str(cal.event))
	ctx.events.notice.emit("success", Loc.tf("UI_EVENTS_NOTICE_START", {"name": Loc.t(ev.get("name", {}))}), {"digest": "event", "event": str(cal.event)})


func _notify_end(cal: Dictionary) -> void:
	var key := "end:" + str(cal.occ)
	if str(state.last_notice) == key or ctx.events == null or not str(state.last_notice).begins_with("start:"):
		return
	state.last_notice = key
	var ev: Dictionary = ctx.data.get_def("events", str(cal.event))
	ctx.events.notice.emit("info", Loc.tf("UI_EVENTS_NOTICE_END", {"name": Loc.t(ev.get("name", {}))}), {"digest": "event", "event": str(cal.event)})


## Calendario attuale (aggiornato).
func calendar() -> Dictionary:
	return _evaluate()


# ------------------------------------------------------------------ impostazioni

func events_enabled() -> bool:
	return not bool(state.opt_out)


## Disattiva/riattiva gli eventi (Impostazioni). Disattivati: niente cadute, missioni, bonus né notifiche; lo stato resta.
func set_events_enabled(on: bool) -> void:
	state.opt_out = not on
	_since_eval = 1e9
	_evaluate()


## Sceglie l'evento dell'Eco (vuoto = l'ultimo concluso).
func set_echo_event(event_id: String) -> bool:
	if not event_id.is_empty() and not ctx.data.has_def("events", event_id):
		return false
	state.echo_event = event_id
	_evaluate()
	return true


func echo_event() -> String:
	return str(_cal.get("echo_event", ""))


func event_ids() -> Array:
	var out: Array = []
	for ev in ctx.data.table("events"):
		out.append(str(ev.id))
	return out


func event_def(event_id: String) -> Dictionary:
	return ctx.data.get_def("events", event_id)


## Sintesi per la UI: {enabled, unlocked, ok, trusted, mode, event, occ, ends_in_s, next_event, next_in_s, echo_event, currency}.
func status() -> Dictionary:
	var cal := _evaluate()
	var out := cal.duplicate()
	out["enabled"] = events_enabled()
	out["unlocked"] = has_token()
	var ev: Dictionary = ctx.data.get_def("events", str(cal.get("event", "")))
	out["currency"] = str(ev.get("currency", ""))
	return out


# ------------------------------------------------------------------ cadute di valuta

func _bank() -> GameSystem:
	return ctx.get_system("bank")


func _has_activity() -> bool:
	var a: Variant = ctx.state.get("activity", {})
	return a is Dictionary and not (a as Dictionary).is_empty() and not str(a.get("type", "")).is_empty()


func tick(dt: float) -> void:
	state.game_s = float(state.game_s) + dt
	_since_eval += dt
	if _since_eval >= EVAL_PERIOD_S:
		_since_eval = 0.0
		_evaluate()
	if not _cur.is_empty() and _has_activity():
		_accumulate(str(_cur.occ), float(_cur.every_s), dt, _cur)


## Aggiunge `seconds` di attività al conteggio della chiave e paga le unità maturate. Ritorna le unità pagate.
func _accumulate(key: String, every_s: float, seconds: float, cur: Dictionary) -> int:
	var acc := float(state.acc.get(key, 0.0)) + seconds
	var n := int(floor(acc / every_s))
	var paid := 0
	if n > 0:
		acc -= float(n) * every_s
		paid = _credit(cur, n)
		if paid < n:
			acc = 0.0                    # tetto raggiunto: nessun arretrato accumulato
	state.acc[key] = acc
	return paid


func _credit(cur: Dictionary, n: int) -> int:
	var key := str(cur.occ)
	var room := maxi(0, int(cur.cap) - int(state.earned.get(key, 0)))
	var k := mini(n, room)
	if k <= 0:
		return 0
	var b := _bank()
	if b == null:
		return 0
	b.add(str(cur.currency), k, "event")
	state.earned[key] = int(state.earned.get(key, 0)) + k
	_stat_add("drops", k)
	_progress("currency", k, "", key, str(cur.event))
	return k


## Tempo in blocco: calendario analitico, nessun tick. Le finestre delle edizioni sono intersecate con l'intervallo trascorso.
func simulate_offline(seconds: float) -> Dictionary:
	if seconds <= 0.0:
		return {}
	state.game_s = float(state.game_s) + seconds
	var cal := _evaluate()
	if not bool(cal.get("ok", false)) or bool(state.opt_out) or not has_token() or not _has_activity():
		return {}
	var cfg := _cfg()
	var t1 := int(cal.local_s)
	var t0 := t1 - int(seconds)
	var paid := {}
	var covered := 0.0
	var yr := civil_from_days(floori(float(t1) / 86400.0)).x
	for ev in ctx.data.table("events"):
		for y in [yr - 1, yr]:
			var w := window(ev, y)
			var ov := float(mini(t1, int(w["end"])) - maxi(t0, int(w.start)))
			if ov <= 0.0:
				continue
			covered += ov
			var cur := {"mode": MODE_EVENT, "event": str(ev.id), "occ": occ_key(str(ev.id), y), "currency": str(ev.currency),
				"every_s": float(ev.get("currency_drop_every_s", cfg["drop_every_s"])), "cap": int(cfg["max_drops_per_occurrence"])}
			var n := _accumulate(str(cur.occ), float(cur.every_s), ov, cur)
			paid[str(ev.currency)] = int(paid.get(str(ev.currency), 0)) + n
	var rest := float(seconds) - covered
	var echo_id := str(cal.get("echo_event", ""))
	if rest > 0.0 and not echo_id.is_empty():
		var ev2: Dictionary = ctx.data.get_def("events", echo_id)
		var cur2 := {"mode": MODE_ECHO, "event": echo_id, "occ": echo_key(echo_id), "currency": str(ev2.currency),
			"every_s": float(cfg["echo_every_s"]), "cap": int(cfg["max_drops_echo"])}
		var n2 := _accumulate(str(cur2.occ), float(cur2.every_s), rest, cur2)
		paid[str(ev2.currency)] = int(paid.get(str(ev2.currency), 0)) + n2
	var total := 0
	for c in paid:
		total += int(paid[c])
	return {"currency": paid, "total": total} if total > 0 else {}


# ------------------------------------------------------------------ missioni

func _occ_state(key: String) -> Dictionary:
	if not state.occ.has(key):
		state.occ[key] = {"prog": {}, "claimed": [], "title": false}
	return state.occ[key]


## Fa avanzare le missioni del contesto corrente (o di `key`/`event_id` se indicati).
func _progress(kind: String, n: int, skill: String = "", key: String = "", event_id: String = "") -> void:
	if n <= 0:
		return
	if key.is_empty():
		if _cur.is_empty():
			return
		key = str(_cur.occ)
		event_id = str(_cur.event)
	var ev: Dictionary = ctx.data.get_def("events", event_id)
	var os: Dictionary = {}
	for m in ev.get("missions", []):
		if str(m.kind) != kind:
			continue
		if not str(m.skill).is_empty() and str(m.skill) != skill:
			continue
		if os.is_empty():
			os = _occ_state(key)
		var cur := int(os.prog.get(str(m.id), 0))
		os.prog[str(m.id)] = mini(int(m.qty), cur + n)


func _on_action(action_id: String, _outputs: Array) -> void:
	if enabled and state != null and not _cur.is_empty():
		_progress("actions", 1, str(ctx.data.action(action_id).get("skill", "")))


func _on_action_batch(action_id: String, count: int, _outputs: Array) -> void:
	if enabled and state != null and not _cur.is_empty():
		_progress("actions", count, str(ctx.data.action(action_id).get("skill", "")))


func _on_kill(_monster_id: String, _drops: Array) -> void:
	if enabled and state != null and not _cur.is_empty():
		_progress("kills", 1)


func _on_kill_batch(_monster_id: String, count: int, _drops: Array) -> void:
	if enabled and state != null and not _cur.is_empty():
		_progress("kills", count)


func _on_crate_opened(result: Dictionary) -> void:
	if not enabled or state == null:
		return
	var crate_id := str(result.get("crate_id", ""))
	if _crate_events.has(crate_id) and str(result.get("kind", "")) == "cosmetic":
		_own(str(result.get("def_id", "")))
	if not _cur.is_empty():
		_progress("crates", 1)


## Missioni di un evento. Per ogni missione si mostra l'edizione in cui è pronta da riscuotere, altrimenti quella del contesto
## corrente (edizione o Eco), altrimenti l'ultima giocata.
## [{id, name, desc, kind, qty, reward, prog, done, claimed, occ}]
func missions(event_id: String) -> Array:
	var ev: Dictionary = ctx.data.get_def("events", event_id)
	var out: Array = []
	for m in ev.get("missions", []):
		var key := _pick_occ(event_id, str(m.id), int(m.qty))
		var os: Dictionary = state.occ.get(key, {})
		var p := int(os.get("prog", {}).get(str(m.id), 0))
		out.append({"id": str(m.id), "name": m.name, "desc": m.desc, "kind": str(m.kind), "qty": int(m.qty), "reward": int(m.reward),
			"prog": p, "done": p >= int(m.qty), "claimed": (os.get("claimed", []) as Array).has(str(m.id)), "occ": key})
	return out


func _pick_occ(event_id: String, mission_id: String, qty: int) -> String:
	for key in state.occ:
		if str(key).get_slice(":", 0) != event_id:
			continue
		var os: Dictionary = state.occ[key]
		if int(os.prog.get(mission_id, 0)) >= qty and not (os.claimed as Array).has(mission_id):
			return str(key)
	if not _cur.is_empty() and str(_cur.event) == event_id:
		return str(_cur.occ)
	return _latest_occ(event_id)


## Chiave di stato più recente di un evento fuori contesto: l'ultima edizione (anno più alto), altrimenti l'Eco.
func _latest_occ(event_id: String) -> String:
	var best := ""
	var best_year := -1
	for k in state.occ:
		var parts := str(k).split(":")
		if parts.size() == 2 and parts[0] == event_id and str(parts[1]).is_valid_int() and int(parts[1]) > best_year:
			best = str(k)
			best_year = int(parts[1])
	if best.is_empty() and state.occ.has(echo_key(event_id)):
		best = echo_key(event_id)
	return best


## Missioni completate e non ancora riscosse, di qualsiasi edizione: [{occ, event, id}].
func claimable() -> Array:
	var out: Array = []
	for key in state.occ:
		var event_id := str(key).get_slice(":", 0)
		var ev: Dictionary = ctx.data.get_def("events", event_id)
		var os: Dictionary = state.occ[key]
		for m in ev.get("missions", []):
			if int(os.prog.get(str(m.id), 0)) >= int(m.qty) and not (os.claimed as Array).has(str(m.id)):
				out.append({"occ": str(key), "event": event_id, "id": str(m.id)})
	return out


## Riscuote una missione completata: valuta evento nel Deposito; con tutte e 4 le missioni dell'edizione, il titolo.
func claim(mission_id: String, key: String = "") -> bool:
	if not events_enabled():
		return false
	var event_id := ""
	for ev in ctx.data.table("events"):
		for m in ev.missions:
			if str(m.id) == mission_id:
				event_id = str(ev.id)
	if event_id.is_empty():
		return false
	var ev2: Dictionary = ctx.data.get_def("events", event_id)
	if key.is_empty():
		var qty := 0
		for m0 in ev2.missions:
			if str(m0.id) == mission_id:
				qty = int(m0.qty)
		key = _pick_occ(event_id, mission_id, qty)
	if not state.occ.has(key):
		return false
	var os: Dictionary = state.occ[key]
	for m in ev2.missions:
		if str(m.id) != mission_id:
			continue
		if int(os.prog.get(mission_id, 0)) < int(m.qty) or (os.claimed as Array).has(mission_id):
			return false
		var b := _bank()
		if b == null:
			return false
		b.add(str(ev2.currency), int(m.reward), "event")
		(os.claimed as Array).append(mission_id)
		_stat_add("claimed", 1)
		_maybe_title(ev2, os)
		ctx.events.important_event.emit("event_mission")
		return true
	return false


func _maybe_title(ev: Dictionary, os: Dictionary) -> void:
	if bool(os.title) or (os.claimed as Array).size() < (ev.missions as Array).size():
		return
	os["title"] = true
	var comp: GameSystem = ctx.get_system("compendium")
	if comp != null:
		comp.call("grant_title", str(ev.title.id))


# ------------------------------------------------------------------ negozio (prezzo fisso, nessun caso)

func _own(def_id: String) -> void:
	if not def_id.is_empty() and not (state.owned as Array).has(def_id):
		(state.owned as Array).append(def_id)


func is_owned(kind: String, def_id: String) -> bool:
	if kind == "pet":
		var comp: GameSystem = ctx.get_system("compendium")
		return comp != null and bool(comp.call("has_pet", def_id))
	return (state.owned as Array).has(def_id)


func currency_count(event_id: String) -> int:
	var b := _bank()
	var cur := str(ctx.data.get_def("events", event_id).get("currency", ""))
	return int(b.count(cur)) if (b != null and not cur.is_empty()) else 0


## [{kind, id, price, owned, affordable}] — il Negozio di un evento è sempre aperto: non si perde la valuta avanzata.
func shop(event_id: String) -> Array:
	var ev: Dictionary = ctx.data.get_def("events", event_id)
	var have := currency_count(event_id)
	var out: Array = []
	for s in ev.get("shop", []):
		var owned := is_owned(str(s.kind), str(s.id))
		out.append({"kind": str(s.kind), "id": str(s.id), "price": int(s.price), "owned": owned, "affordable": have >= int(s.price)})
	return out


func buy_check(event_id: String, def_id: String) -> String:
	if not events_enabled():
		return "off"
	var entry: Dictionary = {}
	for s in shop(event_id):
		if str(s.id) == def_id:
			entry = s
	if entry.is_empty():
		return "unknown"
	if bool(entry.owned):
		return "owned"
	if not bool(entry.affordable):
		return "funds"
	return ""


func buy(event_id: String, def_id: String) -> bool:
	if buy_check(event_id, def_id) != "":
		return false
	var ev: Dictionary = ctx.data.get_def("events", event_id)
	var entry: Dictionary = {}
	for s in ev.shop:
		if str(s.id) == def_id:
			entry = s
	var b := _bank()
	if b == null or not bool(b.remove(str(ev.currency), int(entry.price))):
		return false
	if str(entry.kind) == "pet":
		ctx.events.pet_found.emit(def_id)
	else:
		var d: Dictionary = ctx.data.item(def_id)
		b.add_instance({"def_id": def_id, "kind": "cosmetic", "rarity": str(d.get("rarity", "rare")), "crate": str(ev.crate), "seed": 0})
		_own(def_id)
	_stat_add("bought", 1)
	ctx.events.important_event.emit("event_shop")
	return true


# ------------------------------------------------------------------ cassa dell'evento

## Probabilità mostrate: le stesse della Cassa (CrateSystem.odds); la Cassa evento non ha pity né probabilità nascoste.
func crate_odds(event_id: String) -> Array:
	var cs: GameSystem = ctx.get_system("crates")
	var ev: Dictionary = ctx.data.get_def("events", event_id)
	return cs.call("odds", str(ev.get("crate", ""))) if cs != null else []


## Riepilogo cadute di un contesto: {earned, cap, every_s}.
func drops_info(event_id: String) -> Dictionary:
	var cfg := _cfg()
	var key := ""
	if not _cur.is_empty() and str(_cur.event) == event_id:
		key = str(_cur.occ)
	else:
		key = _latest_occ(event_id)
	return {"earned": int(state.earned.get(key, 0)), "cap": int(cfg["max_drops_per_occurrence"]),
		"echo_earned": int(state.earned.get(echo_key(event_id), 0)), "echo_cap": int(cfg["max_drops_echo"])}


func _stat_add(key: String, n: int) -> void:
	state.stats[key] = int(state.stats.get(key, 0)) + n
