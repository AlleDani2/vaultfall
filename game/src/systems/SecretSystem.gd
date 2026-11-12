class_name SecretSystem
extends GameSystem
## Luoghi Segreti (docs/11 §7, GUILD-2): 10 Frammenti di Mappa rivelano per 24 h un luogo di una mansione di raccolta;
## nella finestra si fanno fino a `runs_per_reveal` esplorazioni a tempo (una alla volta). Ogni esplorazione dà l'XP
## dell'azione di maggior livello sbloccata nella mansione x `xp_mult` per la sua durata e `bonus_chance` per ciclo di
## ottenere l'oggetto di tier 11 del luogo. La prima scoperta di ogni luogo paga Polvere Stellare ed alimenta gli incarichi
## dei Ranger (objective_event "secret_spot" / "secret_spot_all"). Tutti i numeri sono in `social_rules.secrets`.
##
## Stato `secrets`: {"t": tempo di gioco (s), "spots": {id: {"until": s, "runs_left": int}}, "discovered": [id],
##   "active": {} | {"spot": id, "left": s, "total": s}, "done_runs": int}. Tempo di gioco proprio (come Tenuta e Spedizioni):
##   mai l'orologio di sistema; offline analitico (stesso codice del tick).

const HOUR_S := 3600.0

var _unlock_sent: bool = false


func _init() -> void:
	id = "secrets"
	state_key = "secrets"


func default_state() -> Variant:
	return _fresh_state()


static func _fresh_state() -> Dictionary:
	return {"t": 0.0, "spots": {}, "discovered": [], "active": {}, "done_runs": 0}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["spots.*.runs_left", "done_runs"])


func setup() -> void:
	ctx.events.item_gained.connect(_cb_item_gained)


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh_state()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	_unlock_sent = false          # il token si concede al primo tick: UnlockSystem è agganciato dopo di noi


func rules() -> Dictionary:
	return ctx.data.rules("social_rules").get("secrets", {})


func spot_ids() -> Array:
	return ctx.data.table("secret_spots").map(func(s: Dictionary) -> String: return str(s.id))


func spot_def(spot_id: String) -> Dictionary:
	return ctx.data.get_def("secret_spots", spot_id)


func _bank() -> Variant:
	return ctx.get_system("bank")


func fragments() -> int:
	var b: Variant = _bank()
	return int(b.call("count", _fragment_item())) if b != null else 0


func _fragment_item() -> String:
	return "map_fragment"


func _cb_item_gained(def_id: String, _qty: int, _src: String) -> void:
	if def_id == _fragment_item():
		_check_unlock()


## Il menù «Luoghi Segreti» compare col primo Frammento di Mappa (o se ne possiedi già).
func _check_unlock() -> void:
	if state == null or _unlock_sent:
		return
	if fragments() > 0 or not (state.discovered as Array).is_empty():
		var u := ctx.get_system("unlock")
		if u != null:
			u.call("grant", str(rules().get("unlock_token", "feature:secrets")))
			_unlock_sent = true


# ------------------------------------------------------------------ interrogazioni

func game_time() -> float:
	return float(state.t)


func is_discovered(spot_id: String) -> bool:
	return (state.discovered as Array).has(spot_id)


func discovered_count() -> int:
	return (state.discovered as Array).size()


## true se il luogo è rivelato (finestra aperta o esplorazione in corso).
func is_revealed(spot_id: String) -> bool:
	var sp: Dictionary = state.spots.get(spot_id, {})
	return not sp.is_empty() and (float(sp.until) > game_time() or active_spot() == spot_id)


func active_spot() -> String:
	return str((state.active as Dictionary).get("spot", ""))


func time_left(spot_id: String) -> float:
	return maxf(0.0, float(state.spots.get(spot_id, {}).get("until", 0.0)) - game_time())


func runs_left(spot_id: String) -> int:
	return int(state.spots.get(spot_id, {}).get("runs_left", 0)) if is_revealed(spot_id) else 0


## Frazione 0..1 e secondi rimasti dell'esplorazione in corso.
func run_progress() -> Dictionary:
	var a: Dictionary = state.active
	if a.is_empty():
		return {"spot": "", "left": 0.0, "total": 0.0, "fraction": 0.0}
	return {"spot": str(a.spot), "left": float(a.left), "total": float(a.total),
		"fraction": 1.0 - float(a.left) / maxf(1.0, float(a.total))}


func _skill_level(skill: String) -> int:
	return int(ctx.state.get("skills", {}).get(skill, {}).get("level", 0))


## "" se si può rivelare; altrimenti "level" | "fragments" | "revealed" | "unknown".
func can_reveal(spot_id: String) -> String:
	var d := spot_def(spot_id)
	if d.is_empty():
		return "unknown"
	if is_revealed(spot_id):
		return "revealed"
	if _skill_level(str(d.skill)) < int(d.level_req):
		return "level"
	if fragments() < int(d.map_fragments_required):
		return "fragments"
	return ""


func reveal(spot_id: String) -> bool:
	if can_reveal(spot_id) != "":
		return false
	var d := spot_def(spot_id)
	var b: Variant = _bank()
	if not bool(b.call("remove", _fragment_item(), int(d.map_fragments_required))):
		return false
	state.spots[spot_id] = {"until": game_time() + float(d.duration_h_per_unlock) * HOUR_S, "runs_left": int(rules().runs_per_reveal)}
	var first := not is_discovered(spot_id)
	if first:
		(state.discovered as Array).append(spot_id)
		var dust := int(rules().get("discovery_stardust", 0))
		if dust > 0:
			b.call("add_currency", "stardust", dust)
		ctx.events.objective_event.emit("secret_spot", {"qty": 1})
		ctx.events.objective_event.emit("secret_spot_all", {"qty": 1})
		ctx.events.important_event.emit("secret_spot")
	ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_SECRET_REVEALED", {"name": Loc.t(d.name), "h": int(d.duration_h_per_unlock)}), {"digest": "secret"})
	return true


## Azione di maggior livello sbloccata nella mansione del luogo ("" se nessuna).
func best_action(spot_id: String) -> String:
	var d := spot_def(spot_id)
	var lvl := _skill_level(str(d.get("skill", "")))
	var best := ""
	var best_lv := -1
	for a in ctx.data.actions_for_skill(str(d.get("skill", ""))):
		var rq := int(a.get("level_req", 1))
		if rq <= lvl and rq > best_lv and float(a.get("time_s", 0.0)) > 0.0:
			best = str(a.id)
			best_lv = rq
	return best


## Anteprima di un'esplorazione: {action, minutes, xp, cycles, bonus_item, bonus_expected}.
func preview(spot_id: String) -> Dictionary:
	var d := spot_def(spot_id)
	var aid := best_action(spot_id)
	if d.is_empty() or aid.is_empty():
		return {}
	var a: Dictionary = ctx.data.action(aid)
	var minutes := float(rules().explore_minutes)
	var secs := minutes * 60.0
	var cycles := int(floor(secs / float(a.time_s)))
	var xph := float(a.get("xp", 0.0)) / float(a.time_s) * HOUR_S
	return {"action": aid, "minutes": minutes, "xp": xph * (secs / HOUR_S) * float(rules().xp_mult), "cycles": cycles,
		"bonus_item": str(d.bonus_item), "bonus_expected": float(cycles) * float(rules().bonus_chance)}


## "" se si può esplorare; altrimenti "hidden" | "busy" | "no_runs" | "no_action" | "unknown".
func can_explore(spot_id: String) -> String:
	if spot_def(spot_id).is_empty():
		return "unknown"
	if not is_revealed(spot_id):
		return "hidden"
	if not (state.active as Dictionary).is_empty():
		return "busy"
	if runs_left(spot_id) <= 0:
		return "no_runs"
	if best_action(spot_id).is_empty():
		return "no_action"
	return ""


func explore(spot_id: String) -> bool:
	if can_explore(spot_id) != "":
		return false
	var secs := float(rules().explore_minutes) * 60.0
	state.spots[spot_id]["runs_left"] = runs_left(spot_id) - 1
	state["active"] = {"spot": spot_id, "left": secs, "total": secs}
	return true


# ------------------------------------------------------------------ tempo

func tick(dt: float) -> void:
	if state == null:
		return
	if not _unlock_sent:
		_check_unlock()
	_advance(dt)


## Analitico: l'avanzamento è lineare, quindi coincide con i tick (nessun evento intermedio oltre la fine dell'esplorazione).
func simulate_offline(seconds: float) -> Dictionary:
	if state == null:
		return {}
	_check_unlock()
	var before := int(state.done_runs)
	var spot := active_spot()
	_advance(seconds)
	if int(state.done_runs) > before:
		return {"rows": [{"key": "UI_GUILD2_WB_SECRET", "params": {"name": Loc.t(spot_def(spot).get("name", spot))}}]}
	return {}


func has_tick() -> bool:
	return true


func _advance(dt: float) -> void:
	state.t = float(state.t) + dt
	var a: Dictionary = state.active
	if a.is_empty():
		return
	a.left = float(a.left) - dt
	if float(a.left) <= 0.0:
		_finish(str(a.spot))
		state["active"] = {}
	# le finestre scadute senza esplorazione in corso si dimenticano (la scoperta resta)
	for sid in state.spots.keys():
		var sp: Dictionary = state.spots[sid]
		if float(sp.until) <= game_time() and active_spot() != sid:
			state.spots.erase(sid)


func _finish(spot_id: String) -> void:
	var d := spot_def(spot_id)
	var pv := preview(spot_id)
	state.done_runs = int(state.done_runs) + 1
	if d.is_empty() or pv.is_empty():
		return
	var sk: Variant = ctx.get_system("skills")
	if sk != null and float(pv.xp) > 0.0:
		sk.call("add_xp", str(d.skill), float(pv.xp))
	var e := float(pv.bonus_expected)
	var n := int(floor(e))
	if ctx.rng.chance("world", e - floor(e)):
		n += 1
	var got := 0
	if n > 0:
		var b: Variant = _bank()
		got = int(b.call("add", str(d.bonus_item), n, "secret")) if b != null else 0
	var item_name := Loc.t(ctx.data.item(str(d.bonus_item)).get("name", d.bonus_item))
	ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_SECRET_DONE", {"name": Loc.t(d.name), "xp": NumberFormat.fmt(float(pv.xp)),
		"n": got, "item": item_name}), {"digest": "secret"})
	ctx.events.important_event.emit("secret_run")
