class_name MercenarySystem
extends GameSystem
## Mercenari della Taverna (docs/11 §5, T-6.3). id "mercenaries". Tempo di gioco.
##
## Stato ctx.state.mercenaries:
##   t        secondi di gioco della Gilda
##   seq      contatore per gli uid ("m_000001")
##   roster   [{uid, name, role, rarity, level, xp, traits[], equip_tier, injured_until, busy}]
##   board    {"candidates": [{uid, name, role, rarity, traits[]}], "next_s": secondi al prossimo cambio, "rerolls": int}
## Potere = base × (1 + 0,1·(livello−1)) × (1 + merc_power_pct/100) × (1 + 0,05·tier equipaggiamento) × (1 + tratti).
## Le spedizioni (ExpeditionSystem) usano set_busy / grant_xp / injure: nessun altro sistema scrive qui.

## Numeri di bilanciamento: data/constants.json -> `mercenary_tuning` (fonte: tools/gamedata/tuning.py), nessun valore qui (regola 2).
static func tuning() -> Dictionary:
	return Formulas.k().get("mercenary_tuning", {})


## Soglie puramente TECNICHE (tolleranze numeriche, guardie dei cicli): non sono numeri di bilanciamento.
const TECH := {
	"eps": 1e-9,
}

var _rules: Dictionary = {}
var _rarity: Dictionary = {}
var _rarity_ids: Array = []
var _traits: Dictionary = {}


func _init() -> void:
	id = "mercenaries"
	state_key = "mercenaries"


func setup() -> void:
	_rules = ctx.data.rules("mercenary_rules")
	_rarity.clear()
	_rarity_ids.clear()
	for r in _rules.rarities:
		_rarity[r.id] = r
		_rarity_ids.append(r.id)
	_traits.clear()
	for t in _rules.traits:
		_traits[t.id] = t


func default_state() -> Variant:
	return {"t": 0.0, "seq": 0, "roster": [], "board": {"candidates": [], "next_s": 0.0, "rerolls": 0}}


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
	for m in state.roster:
		m["level"] = int(m.get("level", 1))
		m["xp"] = float(m.get("xp", 0.0))
		m["equip_tier"] = int(m.get("equip_tier", 0))
		m["injured_until"] = float(m.get("injured_until", 0.0))
		m["busy"] = str(m.get("busy", ""))


func int_paths() -> PackedStringArray:
	return PackedStringArray(["seq", "roster.*.level", "roster.*.equip_tier", "board.rerolls"])


## Interi «morbidi» (GameSystem.soft_int_paths): i candidati della bacheca non sono tra i percorsi rigidi del Registro.
func soft_int_paths() -> PackedStringArray:
	return PackedStringArray(["board.candidates[].level", "board.candidates[].equip_tier"])


# ------------------------------------------------------------------ riferimenti

func _estate() -> GameSystem:
	return ctx.get_system("estate")


func _bank() -> GameSystem:
	return ctx.get_system("bank")


func tavern_level() -> int:
	var e := _estate()
	return 0 if e == null else int(e.level_of_type("guild"))


func game_time() -> float:
	return float(state.t)


func roster() -> Array:
	return state.roster


func roster_cap() -> int:
	var l := tavern_level()
	if l <= 0:
		return 0
	return mini(int(tuning().roster_max), int(tuning().roster_base) + int(floor(float(l) / float(tuning().roster_per_levels))))


func get_merc(uid: String) -> Dictionary:
	for m in state.roster:
		if str(m.uid) == uid:
			return m
	return {}


func role_name(role: String) -> Dictionary:
	for r in _rules.roles:
		if r.id == role:
			return r.name
	return {}


func trait_def(trait_id: String) -> Dictionary:
	return _traits.get(trait_id, {})


func rarity_def(rarity: String) -> Dictionary:
	return _rarity.get(rarity, {})


func rarity_ids() -> Array:
	return _rarity_ids.duplicate()


func max_level(m: Dictionary) -> int:
	return int(_rarity[m.rarity].max_level)


# ------------------------------------------------------------------ potere

func trait_sum(m: Dictionary, effect_key: String) -> float:
	var s := 0.0
	for t in m.traits:
		s += float(_traits.get(t, {}).get("effect", {}).get(effect_key, 0.0))
	return s


func power_of(m: Dictionary) -> float:
	if m.is_empty():
		return 0.0
	var base := float(_rarity[m.rarity].base_power)
	var p := base * (1.0 + float(tuning().level_power_step) * (int(m.level) - 1))
	p *= ctx.modifiers.multiplier("merc_power_pct", [])
	p *= 1.0 + float(tuning().equip_power_step) * int(m.equip_tier)
	p *= 1.0 + trait_sum(m, "power_pct") / 100.0
	return p


func power_of_uid(uid: String) -> float:
	return power_of(get_merc(uid))


## Potere di una squadra: somma dei poteri × (1 + Σ team_power_pct dei Condottieri / 100).
func team_power(uids: Array) -> float:
	var p := 0.0
	var lead := 0.0
	for u in uids:
		var m := get_merc(str(u))
		p += power_of(m)
		lead += trait_sum(m, "team_power_pct")
	return p * (1.0 + lead / 100.0)


func xp_to_next(level: int) -> float:
	return float(tuning().xp_base) * pow(float(tuning().xp_growth), level)


# ------------------------------------------------------------------ stato di impiego

func is_busy(uid: String) -> bool:
	return str(get_merc(uid).get("busy", "")) != ""


func injured_left(uid: String) -> float:
	return maxf(0.0, float(get_merc(uid).get("injured_until", 0.0)) - game_time())


func is_injured(uid: String) -> bool:
	return injured_left(uid) > 0.0


func is_available(uid: String) -> bool:
	var m := get_merc(uid)
	return not m.is_empty() and not is_busy(uid) and not is_injured(uid)


func set_busy(uid: String, expedition_id: String) -> void:
	var m := get_merc(uid)
	if not m.is_empty():
		m["busy"] = expedition_id


## Infortunio: indisponibile per `duration_s`, contati a partire da `ago_s` secondi fa (offline).
func injure(uid: String, duration_s: float, ago_s: float = 0.0) -> void:
	var m := get_merc(uid)
	if not m.is_empty():
		m["injured_until"] = maxf(float(m.injured_until), game_time() - ago_s + duration_s)


## XP della spedizione; sale di livello fino al massimo della rarità. Ritorna i livelli guadagnati.
func grant_xp(uid: String, xp: float) -> int:
	var m := get_merc(uid)
	if m.is_empty() or xp <= 0.0:
		return 0
	var gained := 0
	m["xp"] = float(m.xp) + xp
	while int(m.level) < max_level(m) and float(m.xp) >= xp_to_next(int(m.level)):
		m["xp"] = float(m.xp) - xp_to_next(int(m.level))
		m["level"] = int(m.level) + 1
		gained += 1
	if int(m.level) >= max_level(m):
		m["xp"] = 0.0
	return gained


# ------------------------------------------------------------------ equipaggiamento (kit per tier)

## Oggetti del Deposito che servono per il kit del tier (arma + corazza qualsiasi): {"weapon": uid, "armor": uid} o {}.
func kit_items(tier: int) -> Dictionary:
	var b := _bank()
	if b == null or tier < 1:
		return {}
	var out := {}
	for inst in b.list_instances():
		var def: Dictionary = ctx.data.item(str(inst.get("def", "")))
		if def.is_empty() or str(def.get("category", "")) != "equipment" or int(def.get("tier", 0)) != tier:
			continue
		if b.has_method("is_instance_locked") and b.is_instance_locked(str(inst.uid)):
			continue
		var sub := str(def.get("subcategory", ""))
		if (sub == "weapon" or sub == "armor") and not out.has(sub):
			out[sub] = str(inst.uid)
	return out if out.has("weapon") and out.has("armor") else {}


func can_equip_kit(uid: String, tier: int) -> bool:
	var m := get_merc(uid)
	return not m.is_empty() and tier > int(m.equip_tier) and tier <= int(tuning().equip_tier_max) and not kit_items(tier).is_empty()


## Consuma 1 arma + 1 corazza del tier e porta il mercenario a quel tier di equipaggiamento (+5% potere per tier).
func equip_kit(uid: String, tier: int) -> bool:
	if not can_equip_kit(uid, tier):
		return false
	var kit := kit_items(tier)
	var b := _bank()
	b.remove_instance(str(kit.weapon))
	b.remove_instance(str(kit.armor))
	get_merc(uid)["equip_tier"] = tier
	return true


# ------------------------------------------------------------------ reclutamento

func hire_cost(rarity: String) -> int:
	return int(round(float(tuning().hire_base) * float(_rarity[rarity].hire_mult) * (1.0 + float(tuning().hire_per_tavern_level) * tavern_level())))


func candidates() -> Array:
	return state.board.candidates


func board_refresh_s() -> float:
	return float(_rules.recruit_board.refresh_h) * 3600.0


func board_next_s() -> float:
	return maxf(0.0, float(state.board.next_s))


func reroll_cost() -> int:
	return int(_rules.recruit_board.reroll_cost_gold)


func _new_uid() -> String:
	state.seq = int(state.seq) + 1
	return "m_%06d" % int(state.seq)


func _rarity_weights() -> Array:
	var w: Array = []
	var bonus := 1.0 + float(tuning().rarity_bonus_per_tavern_level) * tavern_level()
	for rid in _rarity_ids:
		var x := float(_rarity[rid].weight)
		w.append(x if rid == "common" else x * bonus)
	return w


func _make_candidate(avoid: Array = [], force_rarity: String = "") -> Dictionary:
	var rid: String = force_rarity if not force_rarity.is_empty() else str(_rarity_ids[maxi(0, ctx.rng.weighted_index("world", _rarity_weights()))])
	var roles: Array = _rules.roles
	var role: String = str(roles[ctx.rng.randi_range("world", 0, roles.size() - 1)].id)
	var names: Array = _rules.names_pool_it_en
	# QA119: due mercenari con lo stesso nome («Vanda» Assaltatore e «Vanda» Guaritore) si confondono: si evitano i nomi in uso
	var free_names: Array = names.filter(func(nm: Variant) -> bool: return not avoid.has(str(nm)))
	if not free_names.is_empty():
		names = free_names
	var pool: Array = _traits.keys()
	var n_traits := mini(int(_rules.traits_per_merc.get(rid, 1)), pool.size())
	var picked: Array = []
	while picked.size() < n_traits:
		var tid: String = str(pool[ctx.rng.randi_range("world", 0, pool.size() - 1)])
		if not picked.has(tid):
			picked.append(tid)
	return {"uid": _new_uid(), "name": str(names[ctx.rng.randi_range("world", 0, names.size() - 1)]), "role": role,
		"rarity": rid, "level": 1, "xp": 0.0, "traits": picked, "equip_tier": 0, "injured_until": 0.0, "busy": ""}


func _refill_board() -> void:
	var cands: Array = []
	var used: Array = []
	for m in state.roster:
		used.append(str(m.name))
	var n_board := int(_rules.recruit_board.candidates)
	for i in n_board:
		# Prima assunzione (1.0, docs/review_1_0/02 punto 5): se la Taverna è vuota e nessun candidato è Comune, l'ultimo lo è
		# (la storia chiede «recluta 1»: senza questa garanzia c'era il 6,4% di restare 6 h senza un candidato economico).
		var need_common := i == n_board - 1 and (state.roster as Array).is_empty() and not cands.any(func(x: Dictionary) -> bool: return str(x.rarity) == "common")
		var c := _make_candidate(used, "common" if need_common else "")
		used.append(str(c.name))
		cands.append(c)
	state.board.candidates = cands
	state.board.next_s = board_refresh_s()


## "" se si può assumere, altrimenti la chiave UI della ragione.
func can_hire(uid: String) -> String:
	var c := _find_candidate(uid)
	if c.is_empty():
		return "UI_GUILD_REASON_GONE"
	if tavern_level() <= 0:
		return "UI_GUILD_REASON_NOTAVERN"
	if state.roster.size() >= roster_cap():
		return "UI_GUILD_REASON_FULL"
	var b := _bank()
	if b == null or int(b.gold()) < hire_cost(str(c.rarity)):
		return "UI_GUILD_REASON_GOLD"
	return ""


func _find_candidate(uid: String) -> Dictionary:
	for c in state.board.candidates:
		if str(c.uid) == uid:
			return c
	return {}


func hire(uid: String) -> bool:
	if can_hire(uid) != "":
		return false
	var c := _find_candidate(uid)
	var b := _bank()
	if not b.spend_gold(hire_cost(str(c.rarity))):
		return false
	(state.board.candidates as Array).erase(c)
	state.roster.append(c)
	ctx.events.objective_event.emit("recruit", {"qty": 1, "rarity": str(c.rarity)})
	return true


func can_reroll() -> bool:
	var b := _bank()
	return tavern_level() > 0 and b != null and int(b.gold()) >= reroll_cost()


func reroll() -> bool:
	if not can_reroll():
		return false
	if not _bank().spend_gold(reroll_cost()):
		return false
	state.board.rerolls = int(state.board.rerolls) + 1
	_refill_board()
	return true


## Congeda un mercenario (non in spedizione). I livelli si perdono: l'interfaccia chiede conferma.
func dismiss(uid: String) -> bool:
	var m := get_merc(uid)
	if m.is_empty() or is_busy(uid):
		return false
	(state.roster as Array).erase(m)
	return true


# ------------------------------------------------------------------ tempo

func tick(dt: float) -> void:
	_advance(dt)


func simulate_offline(seconds: float) -> Dictionary:
	_advance(seconds)
	return {}


func _advance(dt: float) -> void:
	state.t = float(state.t) + dt
	if tavern_level() <= 0:
		return
	var b: Dictionary = state.board
	if (b.candidates as Array).is_empty():
		_refill_board()
		return
	b["next_s"] = float(b.next_s) - dt
	if float(b.next_s) <= 0.0:
		var period := board_refresh_s()
		var over := -float(b.next_s)
		_refill_board()
		b["next_s"] = period - fposmod(over, period)
