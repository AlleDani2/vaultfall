class_name BountySystem
extends GameSystem
## Caccia alle Taglie (docs/05 §11, data/bounty_board.json): bacheca con 3 offerte, un incarico alla volta
## ("N uccisioni di un mostro bersaglio"), Marchi per uccisione, XP della mansione `bounty`, bonus di completamento,
## cambi gratuiti al giorno, Ricercati (variante rara con vita e danno maggiorati).
## I progressi arrivano da CombatSystem (on_kill / on_kill_offline): niente ascolto di EventBus, così i Ricercati
## restano coerenti tra il combattimento a tick e l'offline.
##
## Stato (sezione `bounty`):
##   offers  [{id, tier, monster, kills, marks}]   bacheca corrente
##   active  {} oppure {offer:{...}, progress, xp}  incarico in corso
##   rerolls_used / day_t   cambi gratuiti usati oggi e secondi dall'ultimo "giorno" di gioco
##   completed / marks_total / wanted_killed   contatori
##   seq    progressivo degli id delle offerte

func _init() -> void:
	id = "bounty"
	state_key = "bounty"


func default_state() -> Variant:
	return {"offers": [], "active": {}, "rerolls_used": 0, "day_t": 0.0, "completed": 0, "marks_total": 0,
		"wanted_killed": 0, "seq": 0}


func from_state(section: Variant) -> void:
	state = section
	var d: Dictionary = default_state()
	for k in d:
		if not state.has(k) or typeof(state[k]) != typeof(d[k]):
			if k == "day_t" and state.has(k) and (state[k] is int):
				state[k] = float(state[k])
			else:
				state[k] = d[k]


func int_paths() -> PackedStringArray:
	return PackedStringArray(["rerolls_used", "completed", "marks_total", "wanted_killed", "seq", "active.progress", "offers[].kills"])


## Interi «morbidi» (GameSystem.soft_int_paths): restano int dopo salva e ricarica senza poter rifiutare un salvataggio.
func soft_int_paths() -> PackedStringArray:
	return PackedStringArray(["offers[].marks"])


# ====================================================================== dati

func _board() -> Dictionary:
	var t: Array = ctx.data.table("bounty_board")
	return t[0] if not t.is_empty() else {}


func tiers() -> Array:
	return _board().get("tiers", [])


func tier_def(tier_id: String) -> Dictionary:
	for t in tiers():
		if str(t.id) == tier_id:
			return t
	return {}


func tier_index(tier_id: String) -> int:
	var ts := tiers()
	for i in ts.size():
		if str(ts[i].id) == tier_id:
			return i + 1
	return 1


func _combat() -> Variant:
	return ctx.get_system("combat")


func _skills() -> Variant:
	return ctx.get_system("skills")


func _bank() -> Variant:
	return ctx.get_system("bank")


func bounty_level() -> int:
	var sk: Variant = _skills()
	return maxi(1, int(sk.level("bounty"))) if sk != null else 1


## La fascia è sbloccata dal livello della mansione Caccia alle Taglie.
func tier_unlocked(tier_id: String) -> bool:
	return bounty_level() >= int(tier_def(tier_id).get("bounty_level", 1))


# ====================================================================== bacheca

func offers() -> Array:
	if (state.offers as Array).is_empty() and _combat() != null:
		refill()
	return state.offers


func active() -> Dictionary:
	return state.active


func has_active() -> bool:
	return not (state.active as Dictionary).is_empty()


## Mostri che possono essere bersaglio di una fascia: zone sbloccate, livello ≤ Eroe + 5 (docs/05 §11).
func candidates(tier_id: String) -> Array:
	var combat: Variant = _combat()
	if combat == null:
		return []
	var td := tier_def(tier_id)
	var types: Array = td.get("monster_types", [])
	var hl: int = combat.hero_level()
	var near: Array = []
	var any: Array = []
	for m in ctx.data.table("monsters"):
		if not types.has(str(m.type)) or int(m.level) > hl + 5:
			continue
		if not _monster_reachable(combat, m):
			continue
		any.append(m)
		if int(m.level) >= hl - 10:
			near.append(m)
	return near if not near.is_empty() else any


func _monster_reachable(combat: Variant, m: Dictionary) -> bool:
	if str(m.type) == "dungeon_boss":
		for d in ctx.data.table("dungeons"):
			if str(d.boss) == str(m.id):
				return combat.dungeon_unlocked(str(d.id))
		return false
	var z := str(m.get("zone", ""))
	return not z.is_empty() and combat.zone_unlocked(z)


func _make_offer(tier_id: String, exclude_monster: String = "") -> Dictionary:
	var cands := candidates(tier_id)
	var pool: Array = []
	for m in cands:
		if str(m.id) != exclude_monster:
			pool.append(m)
	if pool.is_empty():
		pool = cands
	if pool.is_empty():
		return {}
	var td := tier_def(tier_id)
	var m: Dictionary = pool[ctx.rng.randi_range("world", 0, pool.size() - 1)]
	var kr: Array = td.kills
	state["seq"] = int(state.seq) + 1
	return {"id": "o%d" % int(state.seq), "tier": tier_id, "monster": str(m.id),
		"kills": ctx.rng.randi_range("world", int(kr[0]), int(kr[1])), "marks": int(td.marks_per_kill)}


## Riempie la bacheca fino a `offers` incarichi con fasce diverse tra quelle sbloccate (le più alte per ultime).
func refill() -> void:
	var want := int(_board().get("offers", 3))
	var avail: Array = []
	for t in tiers():
		if tier_unlocked(str(t.id)) and not candidates(str(t.id)).is_empty():
			avail.append(str(t.id))
	if avail.is_empty():
		return
	var guard := 0
	while (state.offers as Array).size() < want and guard < 16:
		guard += 1
		var tid: String = avail[ctx.rng.randi_range("world", 0, avail.size() - 1)]
		var o := _make_offer(tid)
		if not o.is_empty():
			(state.offers as Array).append(o)


func free_rerolls_left() -> int:
	return maxi(0, int(_board().get("free_rerolls_per_day", 0)) - int(state.rerolls_used))


func reroll_cost(offer_index: int) -> int:
	if free_rerolls_left() > 0 or offer_index < 0 or offer_index >= (state.offers as Array).size():
		return 0
	return int(_board().get("reroll_cost_gold_per_tier", 0)) * tier_index(str(state.offers[offer_index].tier))


## Cambia un'offerta: gratis finché restano cambi giornalieri, poi costa oro in base alla fascia.
func reroll(offer_index: int) -> bool:
	if offer_index < 0 or offer_index >= (state.offers as Array).size():
		return false
	var cost := reroll_cost(offer_index)
	if cost > 0:
		var bank: Variant = _bank()
		if bank == null or not bank.spend_gold(cost):
			return false
	else:
		state["rerolls_used"] = int(state.rerolls_used) + 1
	var old: Dictionary = state.offers[offer_index]
	var tid := str(old.tier)
	var o := _make_offer(tid, str(old.monster))
	if o.is_empty():
		return false
	state.offers[offer_index] = o
	return true


## Accetta l'offerta (un solo incarico alla volta: sostituisce quello in corso, perdendone i progressi).
func accept(offer_index: int) -> bool:
	if offer_index < 0 or offer_index >= (state.offers as Array).size():
		return false
	var o: Dictionary = state.offers[offer_index]
	(state.offers as Array).remove_at(offer_index)
	state["active"] = {"offer": o, "progress": 0, "xp": 0.0}
	refill()
	return true


func abandon() -> void:
	state["active"] = {}


# ====================================================================== bersaglio e Ricercati

func is_target(monster_id: String) -> bool:
	return has_active() and str(state.active.offer.monster) == monster_id


func wanted_chance() -> float:
	var w: Dictionary = _board().get("wanted_variant", {})
	return float(w.get("chance_per_kill", 0.0)) * (1.0 + ctx.modifiers.total_add("bounty_wanted_chance_pct") / 100.0)


func wanted_mults() -> Dictionary:
	var w: Dictionary = _board().get("wanted_variant", {})
	return {"hp": float(w.get("hp_mult", 1.0)), "dmg": float(w.get("dmg_mult", 1.0))}


## Estrae se il prossimo bersaglio è un Ricercato (flusso RNG "world").
func roll_wanted(monster_id: String) -> bool:
	return is_target(monster_id) and ctx.rng.chance("world", wanted_chance())


# ====================================================================== progressi

func _marks(per: float) -> int:
	return int(round(ctx.modifiers.apply(per, "bounty_marks_pct")))


## Uccisione di un mostro in combattimento. `wanted` = era un Ricercato. `monster_xp` = XP dell'uccisione (con Era).
func on_kill(monster_id: String, wanted: bool, monster_xp: float) -> void:
	if not is_target(monster_id):
		return
	var act: Dictionary = state.active
	var o: Dictionary = act.offer
	var xp := monster_xp * float(Formulas.k().combat.rules.bounty_xp_per_kill_mult)
	var marks := _marks(float(o.marks))
	var bank: Variant = _bank()
	var board := _board()
	if wanted:
		var w: Dictionary = board.get("wanted_variant", {})
		marks += _marks(float(w.get("marks", 0)))
		for d in w.get("drops", []):
			for i in int(d.get("qty", 1)):
				ctx.events.crate_found.emit(str(d.item), "bounty:wanted")
		state["wanted_killed"] = int(state.wanted_killed) + 1
	if bank != null and marks > 0:
		bank.add("bounty_mark", marks, "bounty")
	state["marks_total"] = int(state.marks_total) + marks
	var sk: Variant = _skills()
	if sk != null and xp > 0.0:
		sk.add_xp("bounty", xp)
	act["xp"] = float(act.xp) + xp
	act["progress"] = int(act.progress) + 1
	if int(act.progress) >= int(o.kills):
		_complete()


## Uccisioni simulate offline: il Ricercato si estrae qui (nessuno scontro vero da allungare).
func on_kill_offline(monster_id: String, monster_xp: float) -> void:
	if not is_target(monster_id):
		return
	on_kill(monster_id, roll_wanted(monster_id), monster_xp)


func _complete() -> void:
	var act: Dictionary = state.active
	var cb: Dictionary = _board().get("completion_bonus", {})
	var sk: Variant = _skills()
	var bonus_xp := float(act.xp) * float(cb.get("xp_mult_of_task", 0.0))
	if sk != null and bonus_xp > 0.0:
		sk.add_xp("bounty", bonus_xp)
	var crate := false
	if ctx.rng.chance("world", float(cb.get("crate_bounty_chance", 0.0))):
		crate = true
		ctx.events.crate_found.emit(str(cb.get("crate", "crate_bounty")), "bounty:complete")
	state["completed"] = int(state.completed) + 1
	var o: Dictionary = act.offer
	state["active"] = {}
	ctx.events.objective_event.emit("bounty_complete", {"qty": 1})
	ctx.events.objective_event.emit("skill_actions", {"skill": "bounty", "qty": 1})
	ctx.events.notice.emit("info", Loc.tf("UI_C2_BOUNTY_DONE", {"crate": ("+1" if crate else "0")}), {"offer": o})


# ====================================================================== tempo

func tick(dt: float) -> void:
	_advance(dt)


func simulate_offline(seconds: float) -> Dictionary:
	_advance(seconds)
	return {}


## R-OFF-6 (audit 84): il giorno dei rinnovi gratuiti è di calendario anche oltre il limite offline.
func advance_calendar(seconds: float) -> void:
	_advance(seconds)


func _advance(dt: float) -> void:
	state["day_t"] = float(state.day_t) + dt
	var day := float(Formulas.k().combat.rules.day_s)
	if float(state.day_t) >= day:
		state["day_t"] = fmod(float(state.day_t), day)
		state["rerolls_used"] = 0
