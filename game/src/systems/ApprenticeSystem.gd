class_name ApprenticeSystem
extends GameSystem
## Apprendisti dell'Accademia (docs/11 §2, docs/04 §12, T-6.2). id "apprentices". Tempo di gioco.
##
## Ogni apprendista (slot) svolge UN'azione di raccolta o produzione (gruppi gathering/artisan, mai combattimento,
## mai Coltivazione) in parallelo al giocatore. Un ciclo dura durata_dell'azione / efficienza, con efficienza
## min(0,75; 0,35 + 0,01 · livello Accademia). Ogni ciclo dà le uscite attese dell'azione (SkillSystem.expected_per_cycle:
## stessi bonus del giocatore), XP della mansione al 100%, e può far cadere una Cassa (crate_found). Ingredienti dal Deposito.
## Slot: dai livelli dell'Accademia (effect.slots_by_level) + modifica `apprentice_slots` (max 5 totali).
##
## Stato ctx.state.apprentices: {"slots": [{"action": "", "progress_s": float, "carry": {item: float}, "stalled": bool}]}
## Offline: lo stesso codice del tick in blocchi (le uscite sono valori attesi con resto riportato; secondari/casse
## a Poisson col flusso RNG "loot"), così coincide col tick.

## Numeri di bilanciamento: data/constants.json -> `apprentice_tuning` (fonte: tools/gamedata/tuning.py), nessun valore qui (regola 2).
static func tuning() -> Dictionary:
	return Formulas.k().get("apprentice_tuning", {})


## Soglie puramente TECNICHE (tolleranze numeriche, guardie dei cicli): non sono numeri di bilanciamento.
const TECH := {
	"eps": 1e-9,
}

var _slots: Array = []


func _init() -> void:
	id = "apprentices"
	state_key = "apprentices"


func default_state() -> Variant:
	return {"slots": []}


func from_state(section: Variant) -> void:
	state = section
	if not (state is Dictionary):         # GameState di base ha "apprentices": []
		state = default_state()
		ctx.state[state_key] = state
	if not (state.get("slots") is Array):
		state["slots"] = []
	_slots = state.slots
	for s in _slots:
		if not (s is Dictionary):
			continue
		s["action"] = str(s.get("action", ""))
		s["progress_s"] = float(s.get("progress_s", 0.0))
		if not (s.get("carry") is Dictionary):
			s["carry"] = {}
		s["stalled"] = bool(s.get("stalled", false))
		if s.action != "" and (not ctx.data.has_action(s.action) or bool(ctx.data.action(s.action).get("single_craft", false))):
			s["action"] = ""          # QA119: i pezzi singoli non si assegnano (vecchi salvataggi: lo slot torna libero)


# ------------------------------------------------------------------ accesso

func _estate() -> GameSystem:
	return ctx.get_system("estate")


func _skills() -> GameSystem:
	return ctx.get_system("skills")


func _bank() -> GameSystem:
	return ctx.get_system("bank")


func academy_level() -> int:
	var e := _estate()
	return 0 if e == null else int(e.level_of_type("apprentices"))


func efficiency() -> float:
	var l := academy_level()
	if l <= 0:
		return 0.0
	return minf(float(tuning().eff_cap), float(tuning().eff_base) + float(tuning().eff_per_level) * l)


## Slot dell'Accademia dal solo livello (tabella dei dati).
func academy_slots() -> int:
	var l := academy_level()
	var e := _estate()
	if l <= 0 or e == null:
		return 0
	var tbl: Dictionary = e.def_of("academy").get("effect", {}).get("slots_by_level", {})
	var n := 0
	for k in tbl:
		if l >= int(k):
			n = maxi(n, int(tbl[k]))
	return n


func slots_total() -> int:
	var base := academy_slots()
	if base <= 0:
		return 0
	var extra := int(ctx.modifiers.total_add_capped("apprentice_slots"))
	return mini(int(tuning().max_slots), base + maxi(0, extra))


func slot_action(i: int) -> String:
	return str(_slots[i].action) if i >= 0 and i < _slots.size() else ""


func slot_progress(i: int) -> float:
	if i < 0 or i >= _slots.size() or slot_action(i) == "":
		return 0.0
	var c := cycle_s(slot_action(i))
	return clampf(float(_slots[i].progress_s) / c, 0.0, 1.0) if c > 0.0 else 0.0


func slot_stalled(i: int) -> bool:
	return i >= 0 and i < _slots.size() and bool(_slots[i].stalled)


func active_count() -> int:
	var n := 0
	for i in mini(_slots.size(), slots_total()):
		if str(_slots[i].action) != "":
			n += 1
	return n


func cycle_s(action_id: String) -> float:
	var s := _skills()
	var e := efficiency()
	if s == null or e <= 0.0:
		return INF
	return maxf(0.05, float(s.duration_of(action_id))) / e


## "" se l'azione può essere affidata a un apprendista, altrimenti la chiave UI della ragione.
func can_assign(action_id: String) -> String:
	var a: Dictionary = ctx.data.action(action_id)
	var s := _skills()
	if a.is_empty() or s == null:
		return "UI_APPRENTICES_REASON_UNKNOWN"
	if bool(a.get("single_craft", false)):       # QA119: equipaggiamento e attrezzi si costruiscono a mano, uno per volta
		return "UI_APPRENTICES_REASON_SINGLE"
	var group := str(ctx.data.get_def("skills", str(a.skill)).get("group", ""))
	if not (tuning().groups as Array).has(group) or str(a.get("kind", "")) == "crop":
		return "UI_APPRENTICES_REASON_KIND"
	if not s.is_unlocked(str(a.skill)):
		return "UI_APPRENTICES_REASON_LOCKED"
	if int(s.level(str(a.skill))) < int(a.get("level_req", 1)):
		return "UI_APPRENTICES_REASON_LEVEL"
	return ""


func assign(slot_index: int, action_id: String) -> bool:
	if slot_index < 0 or slot_index >= slots_total() or can_assign(action_id) != "":
		return false
	while _slots.size() <= slot_index:
		_slots.append({"action": "", "progress_s": 0.0, "carry": {}, "stalled": false})
	var sl: Dictionary = _slots[slot_index]
	sl["action"] = action_id
	sl["progress_s"] = 0.0
	sl["carry"] = {}
	sl["stalled"] = false
	return true


func unassign(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _slots.size():
		_slots[slot_index]["action"] = ""
		_slots[slot_index]["progress_s"] = 0.0
		_slots[slot_index]["stalled"] = false


## Valori attesi all'ora di un'azione affidata agli apprendisti: {"cycles", "xp", "items": {item: n}, "gold"}.
func hourly(action_id: String) -> Dictionary:
	var s := _skills()
	var c := cycle_s(action_id)
	if s == null or c == INF:
		return {}
	var e: Dictionary = s.expected_per_cycle(action_id)
	var per_h := 3600.0 / c
	var items := {}
	for k in e["items"]:
		items[k] = float(e["items"][k]) * per_h
	for k in e["inst"]:
		items[k] = float(items.get(k, 0.0)) + float(e["inst"][k].n) * per_h
	return {"cycles": per_h, "xp": float(e.xp) * per_h, "items": items, "gold": float(e.gold) * per_h, "crates": float(e.crate) * per_h}


# ------------------------------------------------------------------ simulazione

func tick(dt: float) -> void:
	_run(dt, null)


func simulate_offline(seconds: float) -> Dictionary:
	if seconds <= 0.0 or active_count() <= 0:
		return {}
	var rep := {"items": {}, "xp": {}, "levels": {}, "crates": {}, "gold": 0.0}
	var s := _skills()
	var lv0 := {}
	if s != null:
		for sl in _slots:
			var aid := str(sl.action)
			if aid != "":
				var sk := str(ctx.data.action(aid).skill)
				lv0[sk] = int(s.level(sk))
	var left := seconds
	while left > 1e-9:
		var d := minf(left, float(tuning().chunk_s))
		_run(d, rep)
		left -= d
	var out := {}
	if not (rep.items as Dictionary).is_empty():
		out["items"] = rep.items
	if not (rep.xp as Dictionary).is_empty():
		out["xp"] = rep.xp
	var levels := {}
	for sk in lv0:
		var now := int(s.level(sk))
		if now > int(lv0[sk]):
			levels[sk] = [int(lv0[sk]), now]
	if not levels.is_empty():
		out["levels"] = levels
	if not (rep.crates as Dictionary).is_empty():
		out["crates"] = rep.crates
	var rows: Array = []
	if float(rep.gold) >= 1.0:
		rows.append({"key": "UI_APPRENTICES_WB_GOLD", "params": {"n": NumberFormat.fmt(float(rep.gold))}})
	for i in mini(_slots.size(), slots_total()):
		if bool(_slots[i].stalled) and str(_slots[i].action) != "":
			rows.append({"key": "UI_APPRENTICES_WB_STALLED", "params": {"action": Loc.t(ctx.data.action(str(_slots[i].action)).get("name", {}))}})
			break
	if not rows.is_empty():
		out["rows"] = rows
	return out


func _run(dt: float, rep: Variant) -> void:
	var s := _skills()
	var n_slots := mini(_slots.size(), slots_total())
	if s == null or n_slots <= 0:
		return
	for i in n_slots:
		var sl: Dictionary = _slots[i]
		var aid := str(sl.action)
		if aid == "" or not ctx.data.has_action(aid):
			continue
		var cyc := cycle_s(aid)
		if cyc == INF:
			continue
		var prog := float(sl.progress_s) + dt
		var n := int(floor(prog / cyc + 1e-9))
		sl["stalled"] = false
		if n <= 0:
			sl["progress_s"] = prog
			continue
		var e: Dictionary = s.expected_per_cycle(aid)
		# ingredienti: il numero di cicli è limitato dalla scorta del Deposito
		var b := _bank()
		for it in e.consume:
			var need := float(e.consume[it])
			if need > 0.0 and b != null:
				var carry_c: float = float((sl.carry as Dictionary).get("-" + str(it), 0.0))
				var can := int(floor((float(b.count(str(it))) + carry_c) / need + 1e-9))
				if can < n:
					n = can
					sl["stalled"] = true
		if n <= 0:
			sl["progress_s"] = minf(prog, cyc)
			continue
		sl["progress_s"] = prog - n * cyc if not bool(sl.stalled) else 0.0
		_apply_cycles(sl, aid, e, n, rep)


func _apply_cycles(sl: Dictionary, aid: String, e: Dictionary, n: int, rep: Variant) -> void:
	var b := _bank()
	var carry: Dictionary = sl.carry
	var sk := str(ctx.data.action(aid).skill)
	# consumo
	for it in e.consume:
		var need := float(e.consume[it]) * n
		var key := "-" + str(it)
		var tot := float(carry.get(key, 0.0)) + need
		var whole := int(floor(tot + 1e-9))
		carry[key] = tot - whole
		if whole > 0 and b != null:
			b.remove(str(it), mini(whole, int(b.count(str(it)))))
	# prodotti principali (attesa con resto)
	var gain := {}
	for it in e["items"]:
		gain[it] = float(e["items"][it]) * n
	for it in e["inst"]:
		gain[it] = float(gain.get(it, 0.0)) + float(e["inst"][it].n) * n
	# secondari e drop: Poisson
	for it in e.rare:
		var k := _poisson(float(e.rare[it]) * n)
		if k > 0:
			gain[it] = float(gain.get(it, 0.0)) + k
	for it in gain:
		var tot2 := float(carry.get(it, 0.0)) + float(gain[it])
		var w := int(floor(tot2 + 1e-9))
		carry[it] = tot2 - w
		if w > 0 and b != null:
			var added := int(b.add(str(it), w, "apprentice"))
			if rep != null:
				rep.items[it] = int(rep.items.get(it, 0)) + added
	if float(e.gold) > 0.0:
		var gt := float(carry.get("$gold", 0.0)) + float(e.gold) * n
		var gw := int(floor(gt + 1e-9))
		carry["$gold"] = gt - gw
		if gw > 0 and b != null:
			b.add_gold(gw)
			if rep != null:
				rep.gold = float(rep.gold) + gw
	# Casse (docs/11: "le casse possono cadere")
	var crate_id := str(e.get("crate_id", ""))
	if crate_id != "" and float(e.crate) > 0.0:
		var nc := _poisson(float(e.crate) * n)
		for j in nc:
			ctx.events.crate_found.emit(crate_id, "apprentice")
		if nc > 0 and rep != null:
			rep.crates[crate_id] = int(rep.crates.get(crate_id, 0)) + nc
	# XP della mansione al 100%
	var xp := float(e.xp) * n
	if xp > 0.0:
		_skills().add_xp(sk, xp)
		if rep != null:
			rep.xp[sk] = float(rep.xp.get(sk, 0.0)) + xp


## Poisson col flusso "loot" (Knuth per λ piccola, approssimazione normale arrotondata per λ grande).
func _poisson(lambda: float) -> int:
	if lambda <= 0.0:
		return 0
	var r := ctx.rng.stream("loot")
	if lambda < 30.0:
		var l := exp(-lambda)
		var k := 0
		var p := 1.0
		while true:
			p *= r.randf()
			if p <= l:
				return k
			k += 1
		return k
	var x := lambda + sqrt(lambda) * r.randfn()
	return maxi(0, int(round(x)))
