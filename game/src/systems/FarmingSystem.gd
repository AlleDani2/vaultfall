class_name FarmingSystem
extends GameSystem
## Coltivazione (docs/04 §11, docs/03 R-AZ-2): Orto (ortaggi, kind "crop") e Frutteto (alberi, kind "tree") a timer
## paralleli. Cresce col tempo di gioco (anche offline); i raccolti pronti restano in attesa, nessuna perdita.
## id "farming", stato "farming":
##   {"owned": {"garden": 4, "orchard": 2},
##    "plots": {"garden": [{"crop": action_id|"", "remaining_s": float, "total_s": float, "auto": bool}, ...], "orchard": [...]},
##    "harvests": int}
## Un appezzamento è PRONTO se crop != "" e remaining_s <= 0. Semina = XP di semina subito; raccolta = XP di raccolta,
## uscite al Deposito (resa 5–9 +1 ogni 10 livelli, doppio da skill_double_pct), cassa e famiglio per raccolto.
## Automatico (con constants.farming.auto_stars Stelle in Coltivazione): raccoglie e risemina da solo finché ci sono semi.
## Gli XP vanno alla mansione "farming" di SkillSystem (add_xp con bonus); le uscite al bank, solo con le sue firme.
## Offline analitico: cicli di raccolta/risemina in forma chiusa a blocchi di tempo (resa attesa, secondari di Poisson).

const SKILL := "farming"
const SCOPES := ["farming", "special", "all"]
const OFFLINE_CHUNKS := 16

var _actions: Dictionary = {}        # action_id -> dati
var _kinds: Dictionary = {}          # plot kind ("garden"/"orchard") -> definizione di farming_plots.json
var _pet_id: String = ""
var _warned: Dictionary = {}         # "kind:idx" -> true quando l'avviso di banca piena è già stato dato

signal changed()


func _init() -> void:
	id = "farming"
	state_key = "farming"


func setup() -> void:
	_actions.clear()
	for a in ctx.data.actions_for_skill(SKILL):
		_actions[str(a.id)] = a
	_kinds.clear()
	for k in ctx.data.table("farming_plots"):
		_kinds[str(k.id)] = k
	_pet_id = ""
	for p in ctx.data.table("pets"):
		var src: Variant = p.get("source", {})
		if src is Dictionary and src.get("type", "") == "skill_action" and str(src.get("skill", "")) == SKILL:
			_pet_id = str(p.id)


func default_state() -> Variant:
	var owned := {}
	var plot_map := {}
	for kid in _kinds:
		owned[kid] = int(_kinds[kid].base_plots)
		plot_map[kid] = []
		for i in int(_kinds[kid].base_plots):
			plot_map[kid].append(_new_plot())
	return {"owned": owned, "plots": plot_map, "harvests": 0}


func _new_plot() -> Dictionary:
	return {"crop": "", "remaining_s": 0.0, "total_s": 0.0, "auto": false}


func from_state(section: Variant) -> void:
	if not (section is Dictionary):
		section = default_state()
		ctx.state[state_key] = section
	state = section
	if not (state.get("owned") is Dictionary):
		state["owned"] = {}
	if not (state.get("plots") is Dictionary):
		state["plots"] = {}
	state["harvests"] = int(state.get("harvests", 0))
	for kid in _kinds:
		var n := clampi(int(state.owned.get(kid, _kinds[kid].base_plots)), int(_kinds[kid].base_plots), int(_kinds[kid].max_plots))
		state.owned[kid] = n
		if not (state.plots.get(kid) is Array):
			state.plots[kid] = []
		var arr: Array = state.plots[kid]
		while arr.size() < n:
			arr.append(_new_plot())
		while arr.size() > n:
			arr.pop_back()
		for pl in arr:
			pl["crop"] = str(pl.get("crop", ""))
			if not _actions.has(pl.crop):
				pl["crop"] = ""
			pl["remaining_s"] = maxf(0.0, float(pl.get("remaining_s", 0.0)))
			pl["total_s"] = float(pl.get("total_s", 0.0))
			pl["auto"] = bool(pl.get("auto", false))


func int_paths() -> PackedStringArray:
	return PackedStringArray(["owned.*", "harvests"])


# ------------------------------------------------------------------ letture

func kinds() -> Array:
	return _kinds.keys()


func plot_count(kind: String) -> int:
	return int(state.owned.get(kind, 0))


func plots(kind: String) -> Array:
	return state.plots.get(kind, [])


func plot(kind: String, idx: int) -> Dictionary:
	var arr: Array = plots(kind)
	return arr[idx] if idx >= 0 and idx < arr.size() else {}


func is_ready(kind: String, idx: int) -> bool:
	var pl := plot(kind, idx)
	return not pl.is_empty() and str(pl.crop) != "" and float(pl.remaining_s) <= 0.0


func is_growing(kind: String, idx: int) -> bool:
	var pl := plot(kind, idx)
	return not pl.is_empty() and str(pl.crop) != "" and float(pl.remaining_s) > 0.0


func ready_count() -> int:
	var n := 0
	for kid in _kinds:
		for i in plot_count(kid):
			if is_ready(kid, i):
				n += 1
	return n


## Frazione 0..1 di crescita dell'appezzamento (1 = pronto o vuoto non applicabile).
func growth_fraction(kind: String, idx: int) -> float:
	var pl := plot(kind, idx)
	if pl.is_empty() or str(pl.crop) == "":
		return 0.0
	if float(pl.total_s) <= 0.0:
		return 1.0
	return clampf(1.0 - float(pl.remaining_s) / float(pl.total_s), 0.0, 1.0)


func level() -> int:
	var sk := ctx.get_system("skills")
	return int(sk.level(SKILL)) if sk != null else 1


func stars() -> int:
	var sk := ctx.get_system("skills")
	return int(ctx.state.get("skills", {}).get(SKILL, {}).get("stars", 0)) if sk != null else 0


func can_automate() -> bool:
	return stars() >= int(ctx.constants().farming.auto_stars)


## Azioni (colture o alberi) dell'Orto/Frutteto, ordinate per livello.
func actions_for(kind: String) -> Array:
	var out: Array = []
	var accepts: Array = _kinds.get(kind, {}).get("accepts", [])
	for aid in _actions:
		if str(_actions[aid].kind) in accepts:
			out.append(_actions[aid])
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.level_req) < int(y.level_req))
	return out


## Durata di crescita in secondi con la velocità attuale (skill_haste_pct su Coltivazione).
func grow_time(action_id: String) -> float:
	var a: Dictionary = _actions.get(action_id, {})
	if a.is_empty():
		return 0.0
	var haste := maxf(0.01, ctx.modifiers.apply(1.0, "skill_haste_pct", SCOPES))
	return float(a.grow_time_min) * 60.0 / haste


## Resa media per raccolto (per l'interfaccia e l'offline): quantità media + bonus di livello, con il doppio.
func expected_yield(action_id: String) -> float:
	var a: Dictionary = _actions.get(action_id, {})
	if a.is_empty():
		return 0.0
	var o: Dictionary = a.outputs[0]
	return (_mean(o.qty) + _level_bonus(a)) * (1.0 + _double_pct() / 100.0)


func _mean(q: Variant) -> float:
	return (float(q[0]) + float(q[1])) / 2.0 if q is Array else float(q)


func _level_bonus(a: Dictionary) -> int:
	return int(a.get("harvest_bonus_per_10_levels", 0)) * floori(float(level()) / 10.0)


func _double_pct() -> float:
	return maxf(0.0, ctx.modifiers.total_add("skill_double_pct", SCOPES))


func _bank() -> Object:
	return ctx.get_system("bank")


func _seeds(a: Dictionary) -> int:
	var b := _bank()
	return int(b.count(str(a.seed))) if b != null else 1000000000


# ------------------------------------------------------------------ appezzamenti

## Costo in oro del prossimo appezzamento (0 se già al massimo).
func next_plot_cost(kind: String) -> int:
	var def: Dictionary = _kinds.get(kind, {})
	var n := plot_count(kind)
	if def.is_empty() or n >= int(def.max_plots):
		return 0
	return int(def.unlock_costs_gold[n - int(def.base_plots)])


func buy_plot(kind: String) -> bool:
	var cost := next_plot_cost(kind)
	if cost <= 0:
		return false
	var b := _bank()
	if b != null and not b.spend_gold(cost):
		return false
	state.owned[kind] = plot_count(kind) + 1
	state.plots[kind].append(_new_plot())
	changed.emit()
	return true


## "" se si può seminare, altrimenti la chiave della ragione (UI_FARM_REASON_*).
func can_plant(kind: String, idx: int, action_id: String) -> String:
	var pl := plot(kind, idx)
	var a: Dictionary = _actions.get(action_id, {})
	if pl.is_empty() or a.is_empty():
		return "UI_FARM_REASON_UNKNOWN"
	if not (str(a.kind) in _kinds[kind].accepts):
		return "UI_FARM_REASON_KIND"
	if str(pl.crop) != "":
		return "UI_FARM_REASON_BUSY"
	if level() < int(a.level_req):
		return "UI_FARM_REASON_LEVEL"
	if _seeds(a) < int(a.seeds_per_plant):
		return "UI_FARM_REASON_SEEDS"
	return ""


func plant(kind: String, idx: int, action_id: String) -> bool:
	if can_plant(kind, idx, action_id) != "":
		return false
	_do_plant(plot(kind, idx), _actions[action_id])
	changed.emit()
	return true


func _do_plant(pl: Dictionary, a: Dictionary) -> void:
	var b := _bank()
	if b != null:
		b.remove(str(a.seed), int(a.seeds_per_plant))
	pl["crop"] = str(a.id)
	var t := grow_time(str(a.id))
	pl["remaining_s"] = t
	pl["total_s"] = t
	_add_xp(float(a.xp_plant))


## Semina rapida: pianta l'azione in tutti gli appezzamenti liberi del tipo giusto finché ci sono semi. Ritorna il numero.
func plant_all(kind: String, action_id: String) -> int:
	var n := 0
	for i in plot_count(kind):
		if plant(kind, i, action_id):
			n += 1
	return n


func set_auto(kind: String, idx: int, on: bool) -> bool:
	var pl := plot(kind, idx)
	if pl.is_empty() or (on and not can_automate()):
		return false
	pl["auto"] = on
	changed.emit()
	return true


## Svuota un appezzamento senza raccogliere (il seme è perso).
func clear_plot(kind: String, idx: int) -> void:
	var pl := plot(kind, idx)
	if not pl.is_empty():
		pl["crop"] = ""
		pl["remaining_s"] = 0.0
		pl["total_s"] = 0.0
		pl["auto"] = false
		changed.emit()


# ------------------------------------------------------------------ raccolta

func harvest(kind: String, idx: int) -> bool:
	if not is_ready(kind, idx):
		return false
	var ok := _harvest_plot(kind, idx, plot(kind, idx))
	if ok:
		changed.emit()
	return ok


## Raccoglie tutto ciò che è pronto. Ritorna il numero di appezzamenti raccolti.
func harvest_all() -> int:
	var n := 0
	for kid in _kinds:
		for i in plot_count(kid):
			if is_ready(kid, i) and harvest(kid, i):
				n += 1
	return n


func _harvest_plot(kind: String, idx: int, pl: Dictionary) -> bool:
	var a: Dictionary = _actions[str(pl.crop)]
	var o: Dictionary = a.outputs[0]
	var base_q := ctx.rng.randi_range("loot", int(o.qty[0]), int(o.qty[1])) + _level_bonus(a)
	var dbl := _double_pct()
	var guaranteed := int(floor(dbl / 100.0))
	var copies := 1 + guaranteed + (1 if ctx.rng.chance("loot", dbl / 100.0 - float(guaranteed)) else 0)
	var n := base_q * copies
	var b := _bank()
	var added := n
	if b != null:
		added = int(b.add(str(o.item), n, "skill:" + SKILL))
	if added <= 0 and n > 0:
		var key := kind + ":" + str(idx)
		if not _warned.has(key):
			_warned[key] = true
			ctx.events.notice.emit("warning", tr("UI_SKILLS_STOP_BANK_FULL"), {"reason": "bank_full"})
		return false
	_warned.erase(kind + ":" + str(idx))
	var outs: Array = [{"item": str(o.item), "qty": added}]
	state["harvests"] = int(state.harvests) + 1
	var crate: Dictionary = a.get("crate", {})
	if not crate.is_empty() and ctx.rng.chance("loot", _crate_chance(float(crate.chance))):
		ctx.events.crate_found.emit(str(crate.id), "skill:" + SKILL)
	if not _pet_id.is_empty() and not ctx.state.get("pets", []).has(_pet_id) and ctx.rng.chance("loot", _pet_chance()):
		ctx.events.pet_found.emit(_pet_id)
	_add_xp(float(a.xp_harvest))
	ctx.events.action_completed.emit(str(a.id), outs)
	# automatico: risemina lo stesso seme; altrimenti l'appezzamento torna libero
	pl["crop"] = ""
	pl["remaining_s"] = 0.0
	pl["total_s"] = 0.0
	if bool(pl.auto):
		if can_automate() and _seeds(a) >= int(a.seeds_per_plant) and level() >= int(a.level_req):
			_do_plant(pl, a)
		else:
			ctx.events.notice.emit("info", tr("UI_FARM_AUTO_NO_SEEDS"), {"crop": a.id})
	return true


func _crate_chance(base: float) -> float:
	var find := ctx.modifiers.total_add_capped("crate_find_pct", SCOPES)
	return base * (1.0 + find / 100.0) * ctx.modifiers.total_more("crate_find_pct", SCOPES)


func _pet_chance() -> float:
	var p := 1.0 / float(ctx.constants().farming.pet_one_in)
	return p * (1.0 + ctx.modifiers.total_add("pet_chance_pct", SCOPES) / 100.0)


func _add_xp(amount: float) -> void:
	var sk := ctx.get_system("skills")
	if sk != null and amount > 0.0:
		sk.add_xp(SKILL, amount, true)


# ------------------------------------------------------------------ tick

func tick(dt: float) -> void:
	for kid in _kinds:
		var arr: Array = state.plots.get(kid, [])
		for i in arr.size():
			var pl: Dictionary = arr[i]
			if str(pl.crop) == "":
				continue
			if float(pl.remaining_s) > 0.0:
				pl["remaining_s"] = maxf(0.0, float(pl.remaining_s) - dt)
			if float(pl.remaining_s) <= 0.0 and bool(pl.auto) and can_automate():
				_harvest_plot(kid, i, pl)


# ------------------------------------------------------------------ offline analitico

## Raccolta/risemina in forma chiusa su blocchi di tempo (così livello e semi si aggiornano lungo il percorso).
## Piante manuali: crescono e restano pronte. Automatiche: n raccolti = 1 + floor(t / crescita), limitati dai semi.
## Resa attesa con arrotondamento casuale; cassa/famiglio con estrazioni di Poisson (RNG "loot").
func simulate_offline(seconds: float) -> Dictionary:
	var off: Dictionary = ctx.constants().get("offline", {})
	var eff := (float(off.get("efficiency_pct", 100)) + ctx.modifiers.total_add("offline_efficiency_pct", [])) / 100.0
	var t_total := minf(seconds, float(off.get("cap_max_h", 24)) * 3600.0) * maxf(0.0, eff)
	if t_total <= 0.0:
		return {}
	var any := false
	for kid in _kinds:
		for pl in plots(kid):
			if str(pl.crop) != "":
				any = true
	if not any:
		return {}
	var report := {"harvests": 0, "items": {}, "xp": 0.0, "crates": 0, "ready": 0}
	var chunk := t_total / float(OFFLINE_CHUNKS)
	for c in OFFLINE_CHUNKS:
		for kid in _kinds:
			for pl in plots(kid):
				if str(pl.crop) != "":
					_offline_plot(pl, chunk, report)
	var ready := 0
	for kid in _kinds:
		for i in plot_count(kid):
			if is_ready(kid, i):
				ready += 1
	report["ready"] = ready
	if int(report.harvests) > 0 or ready > 0:
		changed.emit()
	return report


func _offline_plot(pl: Dictionary, dt: float, report: Dictionary) -> void:
	var a: Dictionary = _actions[str(pl.crop)]
	var auto := bool(pl.auto) and can_automate()
	var rem := float(pl.remaining_s)
	if rem > dt:
		pl["remaining_s"] = rem - dt
		return
	if not auto:
		pl["remaining_s"] = 0.0
		return
	var grow := maxf(1.0, grow_time(str(a.id)))
	var t := dt - rem
	var k := int(floor(t / grow))                    # raccolti dopo il primo
	var seeds := _seeds(a)
	var need := int(a.seeds_per_plant)
	var replants_possible := floori(float(seeds) / float(need))
	var h := 1                                       # il primo raccolto c'è sempre
	var replants := 0
	var cleared := false
	if replants_possible >= k + 1:
		h += k
		replants = k + 1
		pl["remaining_s"] = grow - (t - float(k) * grow)
		pl["total_s"] = grow
	else:
		h += replants_possible
		replants = replants_possible
		cleared = true
	# uscite, XP, extra
	var o: Dictionary = a.outputs[0]
	var mean := (_mean(o.qty) + float(_level_bonus(a))) * (1.0 + _double_pct() / 100.0)
	var qty := _random_round(float(h) * mean)
	var b := _bank()
	var given := qty
	if b != null:
		if replants > 0:
			b.remove(str(a.seed), replants * need)
		given = int(b.add(str(o.item), qty, "skill:" + SKILL))
	var xp := float(h) * float(a.xp_harvest) + float(replants) * float(a.xp_plant)
	_add_xp(xp)
	state["harvests"] = int(state.harvests) + h
	report["harvests"] = int(report.harvests) + h
	report["xp"] = float(report.xp) + xp
	report.items[str(o.item)] = int(report.items.get(str(o.item), 0)) + given
	var crate: Dictionary = a.get("crate", {})
	if not crate.is_empty():
		var nc := _poisson(float(h) * _crate_chance(float(crate.chance)))
		report["crates"] = int(report.crates) + nc
		for i in nc:
			ctx.events.crate_found.emit(str(crate.id), "skill:" + SKILL)
	if not _pet_id.is_empty() and not ctx.state.get("pets", []).has(_pet_id):
		if _poisson(float(h) * _pet_chance()) > 0:
			ctx.events.pet_found.emit(_pet_id)
	ctx.events.action_batch_completed.emit(str(a.id), h, [{"item": str(o.item), "qty": int(mean)}])
	if cleared:
		pl["crop"] = ""
		pl["remaining_s"] = 0.0
		pl["total_s"] = 0.0
	elif given < qty:
		pl["remaining_s"] = 0.0           # banca piena: l'ultimo raccolto resta in attesa (non si risemina)


func _random_round(x: float) -> int:
	var f := floorf(x)
	return int(f) + (1 if ctx.rng.chance("loot", x - f) else 0)


func _poisson(lambda: float) -> int:
	if lambda <= 0.0:
		return 0
	var r: RandomNumberGenerator = ctx.rng.stream("loot")
	if lambda > 30.0:
		return maxi(0, int(round(lambda + sqrt(lambda) * r.randfn())))
	var l := exp(-lambda)
	var kk := 0
	var pr := r.randf()
	var cum := l
	var term := l
	while pr > cum and kk < 1000:
		kk += 1
		term *= lambda / float(kk)
		cum += term
	return kk
