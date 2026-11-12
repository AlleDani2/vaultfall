class_name ExpeditionSystem
extends GameSystem
## Spedizioni della Taverna (docs/11 §6, T-6.3). id "expeditions". Tempo di gioco, anche offline.
##
## Stato ctx.state.expeditions:
##   t, seq        secondi di gioco e contatore degli id
##   board         [{id, type, zone, dur_idx, size}] offerte del tabellone (3 + L//10, max 6)
##   active        [{id, type, zone, dur_idx, size, team[], start_t, end_t, power, required, p_success}]
##   log           ultimi esiti [{id, type, zone, success, gold, items{}, crates{}, injured[], t}]
##   done, wins    contatori a vita
## Regole: potere richiesto 30·1,35^(zona−1)·taglia; successo = clamp(1,6·P/(P+Req) − 0,15 (+tratti), 5%, 98%);
## ricompensa/ora ≈ 0,6·gph(tier zona)·taglia/4 × moltiplicatore di durata; fallimento = 25% delle ricompense e 30%
## (tratti permettendo) di infortunio per mercenario (2 h). I mercenari sono gestiti da MercenarySystem (set_busy/grant_xp/injure).
## Il risultato si estrae al COMPLETAMENTO (flusso "world"), in ordine cronologico: tick e offline coincidono.

## Numeri di bilanciamento: data/constants.json -> `expedition_tuning` (fonte: tools/gamedata/tuning.py), nessun valore qui (regola 2).
static func tuning() -> Dictionary:
	return Formulas.k().get("expedition_tuning", {})


## Soglie puramente TECNICHE (tolleranze numeriche, guardie dei cicli): non sono numeri di bilanciamento.
const TECH := {
	"eps": 1e-9,
}

var _rules: Dictionary = {}
var _mrules: Dictionary = {}
var _zones: Array = []
var _by_sub_tier: Dictionary = {}       # sub -> {tier: [item_id...]}


func _init() -> void:
	id = "expeditions"
	state_key = "expeditions"


func setup() -> void:
	_rules = ctx.data.rules("expedition_rules")
	_mrules = ctx.data.rules("mercenary_rules")
	_zones = ctx.data.table("zones")
	_by_sub_tier.clear()
	for it in ctx.data.items_by_category("material"):
		var sub := str(it.get("subcategory", ""))
		if not _by_sub_tier.has(sub):
			_by_sub_tier[sub] = {}
		var t := int(it.get("tier", 1))
		if not _by_sub_tier[sub].has(t):
			_by_sub_tier[sub][t] = []
		_by_sub_tier[sub][t].append(str(it.id))


func default_state() -> Variant:
	return {"t": 0.0, "seq": 0, "board": [], "active": [], "log": [], "done": 0, "wins": 0}


func from_state(section: Variant) -> void:
	state = section
	if not (state is Dictionary):         # il GameState di base ha liste vuote al posto delle sezioni
		state = default_state()
		ctx.state[state_key] = state
	var d: Dictionary = default_state()
	for k in d:
		if not state.has(k) or typeof(state[k]) != typeof(d[k]):
			if typeof(d[k]) == TYPE_FLOAT and typeof(state.get(k)) == TYPE_INT:
				state[k] = float(state[k])
			elif typeof(d[k]) == TYPE_INT and typeof(state.get(k)) == TYPE_FLOAT:
				state[k] = int(state[k])
			else:
				state[k] = d[k]
	for o in state.board:
		o["dur_idx"] = int(o.get("dur_idx", 0))
		o["size"] = int(o.get("size", 2))
	for a in state.active:
		a["dur_idx"] = int(a.get("dur_idx", 0))
		a["size"] = int(a.get("size", 2))
		a["start_t"] = float(a.get("start_t", 0.0))
		a["end_t"] = float(a.get("end_t", 0.0))


func int_paths() -> PackedStringArray:
	return PackedStringArray(["seq", "done", "wins", "board.*.dur_idx", "board.*.size", "active.*.dur_idx", "active.*.size"])


## Interi «morbidi» (GameSystem.soft_int_paths): voci del registro delle spedizioni.
func soft_int_paths() -> PackedStringArray:
	return PackedStringArray(["log[].gold", "log[].levels"])


# ------------------------------------------------------------------ riferimenti

func _estate() -> GameSystem:
	return ctx.get_system("estate")


func _merc() -> GameSystem:
	return ctx.get_system("mercenaries")


func _bank() -> GameSystem:
	return ctx.get_system("bank")


func tavern_level() -> int:
	var e := _estate()
	return 0 if e == null else int(e.level_of_type("guild"))


func game_time() -> float:
	return float(state.t)


func concurrent_cap() -> int:
	var l := tavern_level()
	if l <= 0:
		return 0
	return mini(int(tuning().conc_max), int(tuning().conc_base) + int(floor(float(l) / float(tuning().conc_per_levels))))


func board_size() -> int:
	var l := tavern_level()
	if l <= 0:
		return 0
	return mini(int(tuning().board_max), int(tuning().board_base) + int(floor(float(l) / float(tuning().board_per_levels))))


func active() -> Array:
	return state.active


func board() -> Array:
	return state.board


func log_entries() -> Array:
	return state.log


func type_def(type_id: String) -> Dictionary:
	for t in _rules.types:
		if t.id == type_id:
			return t
	return {}


func type_ids() -> Array:
	var out: Array = []
	for t in _rules.types:
		out.append(str(t.id))
	return out


func zone_def(zone_id: String) -> Dictionary:
	for z in _zones:
		if z.id == zone_id:
			return z
	return {}


func zone_unlocked(zone_id: String) -> bool:
	var c := ctx.get_system("combat")
	if c != null and c.has_method("zone_unlocked"):
		return bool(c.zone_unlocked(zone_id))
	var z := zone_def(zone_id)
	return (ctx.state.get("unlocks", []) as Array).has("zone:" + zone_id) or (not z.is_empty() and z.get("unlock", {}).get("quest", "x") == null)


func unlocked_zones() -> Array:
	var out: Array = []
	for z in _zones:
		if zone_unlocked(str(z.id)):
			out.append(str(z.id))
	return out


func duration_h(dur_idx: int) -> float:
	return float(_rules.durations_h[clampi(dur_idx, 0, _rules.durations_h.size() - 1)])


func duration_mult(dur_idx: int) -> float:
	return float(_rules.duration_reward_mult[clampi(dur_idx, 0, _rules.duration_reward_mult.size() - 1)])


# ------------------------------------------------------------------ tabellone

func _new_id() -> String:
	state.seq = int(state.seq) + 1
	return "x_%06d" % int(state.seq)


func _make_offer() -> Dictionary:
	var zs := unlocked_zones()
	if zs.is_empty():
		zs = [str(_zones[0].id)]
	var types := type_ids()
	return {"id": _new_id(), "type": str(types[ctx.rng.randi_range("world", 0, types.size() - 1)]),
		"zone": str(zs[ctx.rng.randi_range("world", 0, zs.size() - 1)]),
		"dur_idx": ctx.rng.randi_range("world", 0, _rules.durations_h.size() - 1),
		"size": ctx.rng.randi_range("world", int(tuning().size_min), int(tuning().size_max))}


func _fill_board() -> void:
	var n := board_size()
	while (state.board as Array).size() < n:
		var o := _make_offer()
		if (state.board as Array).is_empty() and int(state.get("wins", 0)) == 0 and int(state.get("done", 0)) == 0:
			var best := 0                     # QA1: la prima Spedizione dura la durata minima (prima: timer di 60 min e nessuna ricompensa per 55 minuti)
			for i in (_rules.durations_h as Array).size():
				if float(_rules.durations_h[i]) < float(_rules.durations_h[best]):
					best = i
			o["dur_idx"] = best
		(state.board as Array).append(o)
	while (state.board as Array).size() > n:
		(state.board as Array).pop_back()


func get_offer(offer_id: String) -> Dictionary:
	for o in state.board:
		if str(o.id) == offer_id:
			return o
	return {}


func get_active(exp_id: String) -> Dictionary:
	for a in state.active:
		if str(a.id) == exp_id:
			return a
	return {}


# ------------------------------------------------------------------ calcoli (anteprima = valori usati)

func required_power(zone_id: String, size: int) -> float:
	var z := zone_def(zone_id)
	var order := int(z.get("order", 1))
	return float(tuning().req_base) * pow(float(tuning().req_growth), order - 1) * size


func success_chance(power: float, required: float, team: Array) -> float:
	var m := _merc()
	var trait_pct := 0.0
	if m != null:
		for u in team:
			trait_pct += float(m.trait_sum(m.get_merc(str(u)), "success_pct"))
	var p := float(tuning().success_gain) * power / maxf(1e-9, power + required) - float(tuning().success_bias) + trait_pct / 100.0
	return clampf(p, float(tuning().success_min), float(tuning().success_max))


## Durata effettiva in secondi: base × (1 − min(cap, expedition_speed_pct + tratti "Instancabile")/100).
func duration_s(dur_idx: int, team: Array) -> float:
	var m := _merc()
	var pct := ctx.modifiers.total_add("expedition_speed_pct")
	if m != null:
		for u in team:
			pct += -float(m.trait_sum(m.get_merc(str(u)), "duration_pct"))
	pct = clampf(pct, 0.0, ctx.modifiers.cap_of("expedition_speed_pct"))
	return duration_h(dur_idx) * 3600.0 * (1.0 - pct / 100.0)


func injury_chance(team_member: String) -> float:
	var m := _merc()
	var p := float(_mrules.injury.chance_on_fail)
	if m != null:
		p *= maxf(0.0, 1.0 + float(m.trait_sum(m.get_merc(team_member), "injury_chance_pct")) / 100.0)
	return clampf(p, 0.0, 1.0)


## Valore d'oro della ricompensa di un'offerta riuscita (0,6·gph(tier)·taglia/4·ore·moltiplicatore di durata).
func reward_value(zone_id: String, size: int, dur_idx: int) -> float:
	var tier := int(zone_def(zone_id).get("tier", 1))
	return float(tuning().value_per_hour) * Formulas.gph(tier) * float(size) / 4.0 * duration_h(dur_idx) * duration_mult(dur_idx)


## Anteprima per l'interfaccia: tutto ciò che il giocatore deve vedere prima di partire (rischio e ricompensa).
func preview(offer: Dictionary, team: Array) -> Dictionary:
	var m := _merc()
	var power := 0.0 if m == null else float(m.team_power(team))
	var req := required_power(str(offer.zone), int(offer.size))
	var p := success_chance(power, req, team)
	var inj := 0.0
	if not team.is_empty():
		for u in team:
			inj += injury_chance(str(u))
		inj /= team.size()
	var tdef := type_def(str(offer.type))
	var value := reward_value(str(offer.zone), int(offer.size), int(offer.dur_idx))
	var frag := _fragment_chance(str(offer.type), team)
	return {"power": power, "required": req, "p_success": p, "duration_s": duration_s(int(offer.dur_idx), team),
		"value": value, "fail_pct": float(_rules.fail_reward_pct), "injury_p": inj, "fragment_p": frag,
		"type": str(offer.type), "reward_desc": tdef.get("reward_desc", {}), "team_size": team.size()}


# ------------------------------------------------------------------ avvio

## "" se la squadra può partire, altrimenti la chiave UI della ragione.
func can_start(offer_id: String, team: Array) -> String:
	var m := _merc()
	if tavern_level() <= 0 or m == null:
		return "UI_GUILD_REASON_NOTAVERN"
	if get_offer(offer_id).is_empty():
		return "UI_GUILD_REASON_GONE"
	if (state.active as Array).size() >= concurrent_cap():
		return "UI_GUILD_REASON_SLOTS"
	if team.is_empty():
		return "UI_GUILD_REASON_NOTEAM"
	if team.size() > int(tuning().team_max):
		return "UI_GUILD_REASON_TOOBIG"
	var seen := {}
	for u in team:
		if seen.has(str(u)) or not m.is_available(str(u)):
			return "UI_GUILD_REASON_UNAVAILABLE"
		seen[str(u)] = true
	return ""


func start(offer_id: String, team: Array) -> bool:
	if can_start(offer_id, team) != "":
		return false
	var o := get_offer(offer_id)
	var pv := preview(o, team)
	var m := _merc()
	for u in team:
		m.set_busy(str(u), str(o.id))
	var a := o.duplicate(true)
	a["team"] = team.duplicate()
	a["start_t"] = game_time()
	a["end_t"] = game_time() + float(pv.duration_s)
	a["power"] = float(pv.power)
	a["required"] = float(pv.required)
	a["p_success"] = float(pv.p_success)
	(state.board as Array).erase(o)
	(state.active as Array).append(a)
	_fill_board()
	return true


func time_left(exp_id: String) -> float:
	return maxf(0.0, float(get_active(exp_id).get("end_t", 0.0)) - game_time())


func progress(exp_id: String) -> float:
	var a := get_active(exp_id)
	if a.is_empty():
		return 0.0
	var total := float(a.end_t) - float(a.start_t)
	return 1.0 if total <= 0.0 else clampf((game_time() - float(a.start_t)) / total, 0.0, 1.0)


# ------------------------------------------------------------------ ricompense

func _fragment_chance(type_id: String, team: Array) -> float:
	var base := float(_rules.map_fragment_chance.get("survey" if type_id == "survey" else "other", 0.0))
	var m := _merc()
	var carto := 0.0
	if m != null:
		for u in team:
			carto += float(m.trait_sum(m.get_merc(str(u)), "map_fragment_chance_pct"))
	return clampf(base * (1.0 + carto / 100.0), 0.0, 1.0)


func _random_round(x: float) -> int:
	var f := floorf(x)
	return int(f) + (1 if ctx.rng.randf("world") < x - f else 0)


## Estrae le ricompense di una spedizione (funzione pura sullo stato RNG): {gold, items{}, crates{}, keys{}}.
func roll_rewards(a: Dictionary, success: bool) -> Dictionary:
	var m := _merc()
	var team: Array = a.team
	var scale := 1.0 if success else float(_rules.fail_reward_pct) / 100.0
	var zone := zone_def(str(a.zone))
	var value := reward_value(str(a.zone), int(a.size), int(a.dur_idx)) * scale
	var out := {"gold": 0, "items": {}, "crates": {}, "keys": {}}
	var forager := 0.0
	var lucky := 0.0
	var greedy := 0.0
	if m != null:
		for u in team:
			var mm: Dictionary = m.get_merc(str(u))
			forager += float(m.trait_sum(mm, "material_rolls"))
			lucky += float(m.trait_sum(mm, "crate_reward_pct"))
			greedy += float(m.trait_sum(mm, "gold_reward_pct"))
	match str(a.type):
		"recon":
			var rolls := int(tuning().recon_rolls)
			var share := value / float(rolls)
			var subs: Array = (tuning().recon_subs as Array).duplicate()
			for i in rolls + int(forager):
				if subs.is_empty():
					break
				var sub: String = str(subs.pop_at(ctx.rng.randi_range("world", 0, subs.size() - 1)))
				var it := _item_for(sub, int(zone.get("tier", 1)))
				if it != "":
					var v := maxf(1.0, float(ctx.data.item(it).get("value", 1)))
					var q := _random_round(share / v)
					if q > 0:
						out.items[it] = int(out.items.get(it, 0)) + q
		"escort":
			out.gold = _random_round(value * (1.0 + greedy / 100.0))
		"salvage":
			var hours := duration_h(int(a.dur_idx))
			var expected := hours * duration_mult(int(a.dur_idx)) / 4.0 * float(_rules.salvage_crates_per_4h) * (1.0 + lucky / 100.0) * scale
			var n := _random_round(expected)
			var crate_id := str(zone.get("crate", ""))
			if n > 0 and crate_id != "":
				out.crates[crate_id] = n
				var key := str(ctx.data.item(crate_id).get("crate", {}).get("key", ""))
				var keys := 0
				for i in n:
					if ctx.rng.chance("world", float(_rules.salvage_key_chance)):
						keys += 1
				if keys > 0 and key != "":
					out.keys[key] = keys
		"hunt":
			var common := str(zone.get("common_material", ""))
			var rare := str(zone.get("rare_material", ""))
			var cs := float(tuning().hunt_common_share)
			if common != "":
				var q1 := _random_round(value * cs / maxf(1.0, float(ctx.data.item(common).get("value", 1))))
				if q1 > 0:
					out.items[common] = q1
			if rare != "":
				var q2 := _random_round(value * (1.0 - cs) / maxf(1.0, float(ctx.data.item(rare).get("value", 1))))
				if q2 > 0:
					out.items[rare] = q2
		"survey":
			pass
	if ctx.rng.chance("world", _fragment_chance(str(a.type), team) * scale):
		var fi := str(tuning().map_fragment_item)
		out.items[fi] = int(out.items.get(fi, 0)) + 1
	return out


func _item_for(sub: String, tier: int) -> String:
	var by_t: Dictionary = _by_sub_tier.get(sub, {})
	var best := -1
	for t in by_t:
		if int(t) <= tier and int(t) > best:
			best = int(t)
	if best < 0:
		return ""
	var arr: Array = by_t[best]
	return str(arr[ctx.rng.randi_range("world", 0, arr.size() - 1)])


# ------------------------------------------------------------------ completamento

## `ago_s` = secondi trascorsi dal completamento a "adesso" (offline), per far partire gli infortuni dal momento giusto.
func _complete(a: Dictionary, ago_s: float) -> Dictionary:
	var m := _merc()
	var success := ctx.rng.chance("world", float(a.p_success))
	var rew := roll_rewards(a, success)
	var b := _bank()
	if b != null:
		if int(rew.gold) > 0:
			b.add_gold(int(rew.gold))
		for it in rew.items:
			b.add(str(it), int(rew.items[it]), "expedition")
		var cs := ctx.get_system("crates")
		for c in rew.crates:
			if cs != null:
				cs.grant_crate(str(c), int(rew.crates[c]))
			else:
				b.add(str(c), int(rew.crates[c]), "expedition")
		for k in rew.keys:
			b.add(str(k), int(rew.keys[k]), "expedition")
	var hours := (float(a.end_t) - float(a.start_t)) / 3600.0
	var injured: Array = []
	var levels := 0
	if m != null:
		for u in a.team:
			var mm: Dictionary = m.get_merc(str(u))
			if mm.is_empty():
				continue
			var xpm := 1.0 + float(m.trait_sum(mm, "merc_xp_pct")) / 100.0
			var base_xp := float(_rules.merc_xp_per_hour) * hours * xpm
			if str(a.type) == "survey":
				base_xp *= float(tuning().survey_xp_mult)
			levels += int(m.grant_xp(str(u), base_xp))
			m.set_busy(str(u), "")
			if not success and ctx.rng.chance("world", injury_chance(str(u))):
				m.injure(str(u), float(_mrules.injury.duration_h) * 3600.0, ago_s)
				injured.append(str(mm.name))
	state.done = int(state.done) + 1
	if success:
		state.wins = int(state.wins) + 1
	var res := {"id": str(a.id), "type": str(a.type), "zone": str(a.zone), "success": success, "gold": int(rew.gold),
		"items": rew.items, "crates": rew.crates, "keys": rew.keys, "injured": injured, "levels": levels,
		"p_success": float(a.p_success), "t": float(a.end_t)}
	var lg: Array = state.log
	lg.append(res)
	while lg.size() > int(tuning().log_max):
		lg.remove_at(0)
	(state.active as Array).erase(a)
	ctx.events.expedition_finished.emit(str(a.id), res)
	ctx.events.objective_event.emit("expedition", {"qty": 1})
	return res


# ------------------------------------------------------------------ tempo

func tick(dt: float) -> void:
	state.t = float(state.t) + dt
	if tavern_level() > 0:
		_fill_board()
	var now := game_time()
	for a in (state.active as Array).duplicate():
		if float(a.end_t) <= now + 1e-9:
			_complete(a, now - float(a.end_t))


func simulate_offline(seconds: float) -> Dictionary:
	if seconds <= 0.0:
		return {}
	var t_end := game_time() + seconds
	var rep := {"items": {}, "crates": {}}
	var done := 0
	var wins := 0
	var gold := 0
	var hurt := 0
	var lv := 0
	while true:
		var nxt: Dictionary = {}
		for a in state.active:
			if float(a.end_t) <= t_end + 1e-9 and (nxt.is_empty() or float(a.end_t) < float(nxt.end_t)):
				nxt = a
		if nxt.is_empty():
			break
		state.t = maxf(game_time(), float(nxt.end_t))
		var r := _complete(nxt, t_end - float(nxt.end_t))
		done += 1
		wins += 1 if bool(r.success) else 0
		gold += int(r.gold)
		hurt += (r.injured as Array).size()
		lv += int(r.levels)
		for it in r.items:
			rep.items[it] = int(rep.items.get(it, 0)) + int(r.items[it])
		for c in r.crates:
			rep.crates[c] = int(rep.crates.get(c, 0)) + int(r.crates[c])
		for k in r.keys:
			rep.items[k] = int(rep.items.get(k, 0)) + int(r.keys[k])
	state.t = t_end
	if tavern_level() > 0:
		_fill_board()
	var out := {}
	if not (rep.items as Dictionary).is_empty():
		out["items"] = rep.items
	if not (rep.crates as Dictionary).is_empty():
		out["crates"] = rep.crates
	var rows: Array = []
	if done > 0:
		rows.append({"key": "UI_EXPEDITIONS_WB_DONE", "params": {"n": done, "wins": wins}})
	if gold > 0:
		rows.append({"key": "UI_EXPEDITIONS_WB_GOLD", "params": {"n": NumberFormat.fmt(gold)}})
	if hurt > 0:
		rows.append({"key": "UI_EXPEDITIONS_WB_HURT", "params": {"n": hurt}})
	if lv > 0:
		rows.append({"key": "UI_EXPEDITIONS_WB_LEVELS", "params": {"n": lv}})
	if not rows.is_empty():
		out["rows"] = rows
	return out
