class_name ContractSystem
extends GameSystem
## Commesse giornaliere e settimanali (docs/12 §6, data/contract_templates.json + contract_rules.json). Anti-FOMO:
## le commissioni si ACCUMULANO (le giornaliere restano `rollover_days` giorni, le settimanali `weekly_keep_days`), non c'è
## nessuna serie di accessi, nessuna penalità per l'assenza, nessuna ricompensa esclusiva a tempo; una commissione già
## completata non scade finché non la riscatti. Premiano chi torna, non puniscono chi non torna (PEGI, docs/24).
##
## TEMPO. Il «giorno» è di GIOCO (secondi giocati + secondi di assenza, come la Bacheca delle Taglie): mai l'orologio del
## sistema, quindi nessun trucco con la data e nessun test che dipenda dal giorno in cui gira. `day_s` è nei dati.
##
## PROGRESSI. QuestSystem inoltra a `apply_event(kind, params)` gli stessi eventi di obiettivo che alimentano le missioni
## (stessa regola di `_matches`), così una sola derivazione degli eventi serve missioni e commissioni.
##
## Stato (sezione `contracts`):
##   daily / weekly [{id, tpl, period, obj, target, progress, born, tier, gold, text_params}]  commissioni aperte
##   tokens        (legacy, non usato: i Gettoni sono la valuta `commission_token` del Deposito)
##   clock_s       secondi dall'ultimo cambio di giorno · day  giorni trascorsi dall'inizio · seq  progressivo degli id
##   rerolls_used  cambi gratuiti usati nel giorno `reroll_day` · started  le prime commissioni sono già state emesse
##   stats         {claimed, tokens_earned}

const TOKEN := "commission_token"
const GATHER_SKILLS: PackedStringArray = ["woodcutting", "mining", "fishing", "foraging", "trapping"]
const CRAFT_SKILLS: PackedStringArray = ["smithing", "woodworking", "tailoring", "cooking", "alchemy", "jewelcrafting", "keysmithing"]
## Ingredienti rari che una commissione non deve richiedere (cadono dai mostri, non si raccolgono a comando).
const RARE_INPUT_PREFIXES: PackedStringArray = ["mm_", "gem_"]
const CATCHUP_LIMIT_DAYS := 64

signal contracts_changed

var _action_cache: Dictionary = {}       # {"gather": [...], "craft": [...]}: azioni dei dati filtrate una volta sola


func _init() -> void:
	id = "contracts"
	state_key = "contracts"


func setup() -> void:
	_action_cache = {}
	_static_actions("gather")        # filtro delle azioni una volta sola all'avvio (non nel primo tick)


static func _fresh() -> Dictionary:
	return {"daily": [], "weekly": [], "tokens": 0, "clock_s": 0.0, "day": 0, "seq": 0, "rerolls_used": 0,
		"reroll_day": 0, "started": false, "stats": {"claimed": 0, "tokens_earned": 0}}


func default_state() -> Variant:
	return _fresh()


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			if k == "clock_s" and (state.get(k) is int):
				state[k] = float(state[k])
			else:
				state[k] = base[k]
	for period in ["daily", "weekly"]:
		var keep: Array = []
		for e in state[period]:
			if e is Dictionary and e.has("obj") and e.has("target"):
				e["progress"] = int(e.get("progress", 0))
				e["target"] = int(e.target)
				e["born"] = int(e.get("born", 0))
				keep.append(e)
		state[period] = keep


func int_paths() -> PackedStringArray:
	return PackedStringArray(["tokens", "day", "seq", "rerolls_used", "reroll_day", "stats.*", "daily[].progress", "daily[].target",
		"daily[].born", "daily[].tier", "daily[].gold", "weekly[].progress", "weekly[].target", "weekly[].born", "weekly[].tier",
		"weekly[].gold"])


## Interi «morbidi» (GameSystem.soft_int_paths): quantita' e oro dell'obiettivo e dei parametri di testo delle commissioni.
func soft_int_paths() -> PackedStringArray:
	return PackedStringArray(["daily[].obj.qty", "daily[].obj.gold", "daily[].text_params.qty", "daily[].text_params.gold",
		"weekly[].obj.qty", "weekly[].obj.gold", "weekly[].text_params.qty", "weekly[].text_params.gold"])


# ------------------------------------------------------------------ dati

func _rules() -> Dictionary:
	return ctx.data.rules("contract_rules")


func _templates() -> Array:
	return ctx.data.table("contract_templates")


func _tpl(tpl_id: String) -> Dictionary:
	for t in _templates():
		if str(t.id) == tpl_id:
			return t
	return {}


func _has_unlock(token: String) -> bool:
	if token.is_empty():
		return true
	var u := ctx.get_system("unlock")
	if u != null:
		return bool(u.call("has", token))
	return (ctx.state.get("unlocks", []) as Array).has(token)


func _skill_level(skill: String) -> int:
	var sk := ctx.get_system("skills")
	if sk != null and sk.has_method("level"):
		return int(sk.call("level", skill))
	return int(ctx.state.get("skills", {}).get(skill, {}).get("level", 0))


## true se il sistema è in funzione (dati presenti e funzione sbloccata).
func is_open() -> bool:
	var r := _rules()
	return not r.is_empty() and not _templates().is_empty() and _has_unlock(str(r.get("unlock_token", "")))


## Fascia (tier) del giocatore: quella del livello dell'Eroe.
func player_tier() -> int:
	return Formulas.tier_of_level(maxi(1, _skill_level("hero")))


# ------------------------------------------------------------------ interrogazioni

func contracts(period: String) -> Array:
	return state.get(period, [])


func entry(contract_id: String) -> Dictionary:
	for period in ["daily", "weekly"]:
		for e in state[period]:
			if str(e.id) == contract_id:
				return e
	return {}


func is_complete(contract_id: String) -> bool:
	var e := entry(contract_id)
	return not e.is_empty() and int(e.progress) >= int(e.target)


func ready_count() -> int:
	var n := 0
	for period in ["daily", "weekly"]:
		for e in state[period]:
			if int(e.progress) >= int(e.target):
				n += 1
	return n


func tokens() -> int:
	var b := ctx.get_system("bank")
	return int(b.call("count", TOKEN)) if b != null else 0


## Giorni che mancano alla scadenza (0 = scade al prossimo cambio di giorno); -1 se già completata (non scade).
func days_left(contract_id: String) -> int:
	var e := entry(contract_id)
	if e.is_empty() or int(e.progress) >= int(e.target):
		return -1
	return maxi(0, _keep_days(str(e.period)) - (int(state.day) - int(e.born)) - 1)


func free_rerolls_left() -> int:
	var used := int(state.rerolls_used) if int(state.reroll_day) == int(state.day) else 0
	return maxi(0, int(_rules()["free_rerolls_daily"]) - used)


func _keep_days(period: String) -> int:
	var r := _rules()
	return int(r["rollover_days"]) if period == "daily" else int(r["weekly_keep_days"])


# ------------------------------------------------------------------ tempo

func tick(dt: float) -> void:
	_advance(dt)


func simulate_offline(seconds: float) -> Dictionary:
	var before := ready_count()
	_advance(seconds)
	return {} if ready_count() == before else {"ready": ready_count()}


## R-OFF-6 (audit 84): i giorni delle Commesse sono di calendario anche oltre il limite offline (chi torna dopo una
## settimana trova le giornaliere degli ultimi giorni, come promette la regola dei 7 giorni).
func advance_calendar(seconds: float) -> void:
	_advance(seconds)


func _advance(seconds: float) -> void:
	if state == null or seconds <= 0.0 or not is_open():
		return
	if not bool(state.started):
		state["started"] = true
		_issue("daily")
		_issue("weekly")
		contracts_changed.emit()
	var day_s := maxf(1.0, float(_rules()["day_s"]))
	state["clock_s"] = float(state.clock_s) + seconds
	if float(state.clock_s) < day_s:
		return
	var days := mini(int(floor(float(state.clock_s) / day_s)), CATCHUP_LIMIT_DAYS)
	state["clock_s"] = fmod(float(state.clock_s), day_s)
	var week_days := maxi(1, int(_rules()["week_days"]))
	# Giorni più vecchi del massimo conservato scadrebbero comunque: si emettono solo gli ultimi.
	var keep := maxi(_keep_days("daily"), _keep_days("weekly"))
	var first := maxi(1, days - keep)
	state["day"] = int(state.day) + (first - 1)
	for _d in range(first, days + 1):
		state["day"] = int(state.day) + 1
		_expire()
		_issue("daily")
		if int(state.day) % week_days == 0:
			_issue("weekly")
	contracts_changed.emit()


## Toglie le commissioni scadute. Quelle completate restano finché non si riscattano.
func _expire() -> void:
	for period in ["daily", "weekly"]:
		var keep: Array = []
		for e in state[period]:
			var age := int(state.day) - int(e.born)
			if int(e.progress) >= int(e.target) or age < _keep_days(period):
				keep.append(e)
		state[period] = keep


# ------------------------------------------------------------------ generazione

func _issue(period: String) -> void:
	var slots := int(_rules().get("daily_slots" if period == "daily" else "weekly_slots", 0))
	var used: Array = []
	for e in state[period]:
		if int(e.born) == int(state.day):
			used.append(str(e.tpl))
	var made := used.size()
	var tries := 0
	while made < slots and tries < 40:
		tries += 1
		var e := _generate(period, used)
		if e.is_empty():
			break
		state[period].append(e)
		used.append(str(e.tpl))
		made += 1


## Una nuova commissione di `period` con un modello non in `avoid` (se possibile). {} se nessun modello è disponibile.
func _generate(period: String, avoid: Array) -> Dictionary:
	var cands: Array = []
	for t in _templates():
		if str(t.period) == period and not avoid.has(str(t.id)):
			cands.append(t)
	while not cands.is_empty():
		var i := ctx.rng.randi_range("world", 0, cands.size() - 1)
		var pick := _build(cands[i])
		cands.remove_at(i)
		if pick.is_empty():
			continue
		state["seq"] = int(state.seq) + 1
		pick["id"] = "ct%d" % int(state.seq)
		pick["born"] = int(state.day)
		pick["progress"] = 0
		return pick
	return {}


## Costruisce {tpl, period, obj, target, tier, gold, text_params} per il modello, oppure {} se non è disponibile.
func _build(t: Dictionary) -> Dictionary:
	for req in t.get("requires", []):
		if not _has_unlock(str(req)):
			return {}
	var tier := player_tier()
	var obj := {"type": str(t.objective)}
	var params := {}
	var qty := int(t.get("qty", 0))
	match str(t.get("pick_rule", "")):
		"gather_best_minus_1":
			var a := _pick_gather_action()
			if a.is_empty():
				return {}
			var o: Dictionary = a.outputs[0]
			obj["item"] = str(o.item)
			qty = maxi(1, roundi(float(t.qty_secs) / maxf(0.1, float(a.time_s))))
			params["item"] = obj.item
		"craft_unlocked":
			var a2 := _pick_craft_action()
			if a2.is_empty():
				return {}
			var o2: Dictionary = a2.outputs[0]
			obj["item"] = str(o2.item)
			var per := maxi(1, int(_avg_qty(o2.get("qty", 1))))
			qty = maxi(1, roundi(float(t.qty_secs) / maxf(0.1, float(a2.time_s)))) * per
			params["item"] = obj.item
		"zone_best_minus_1":
			var z := _pick_zone()
			if z.is_empty():
				return {}
			obj["zone"] = z
			params["zone"] = z
	if t.has("skill"):
		obj["skill"] = str(t.skill)
	if str(t.objective) == "open_crates":
		obj["crate"] = "any"
	if str(t.objective) == "complete_dungeon":
		obj["dungeon"] = "any"
	var target := qty
	if str(t.objective) == "sell_market":
		var gold := maxi(1, roundi(Formulas.gph(tier) * float(t["gold_gph_mult"])))
		obj["gold"] = gold
		target = gold
		params["gold"] = gold
	else:
		obj["qty"] = qty
	if target <= 0:
		return {}
	params["qty"] = qty
	var rewards: Dictionary = _rules().get("rewards", {}).get(str(t.period), {})
	return {"tpl": str(t.id), "period": str(t.period), "obj": obj, "target": target, "tier": tier,
		"gold": maxi(1, roundi(Formulas.gph(tier) * float(rewards.get("gold_gph_mult", 0.0)))), "text_params": params}


static func _avg_qty(q: Variant) -> float:
	if q is Array and q.size() == 2:
		return (float(q[0]) + float(q[1])) / 2.0
	return float(q)


## Azione di raccolta del «tier migliore sbloccato -1» (se ce n'è una sola, quella).
func _pick_gather_action() -> Dictionary:
	var cands: Array = []
	var best := 0
	var levels := _usable_skill_levels(GATHER_SKILLS)
	for a in _static_actions("gather"):
		if levels.has(str(a.skill)) and int(levels[str(a.skill)]) >= int(a.get("level_req", 1)):
			cands.append(a)
			best = maxi(best, int(a.get("tier", 1)))
	return _pick_by_tier(cands, maxi(1, best - 1))


## Mansioni sbloccate fra `skills` -> livello attuale.
func _usable_skill_levels(skills: PackedStringArray) -> Dictionary:
	var out := {}
	for sk in skills:
		if _has_unlock("skill:" + sk):
			out[sk] = _skill_level(sk)
	return out


## Azioni dei dati (statiche, calcolate una volta): "gather" = raccolta senza ingredienti, "craft" = produzione senza ingredienti rari.
func _static_actions(kind: String) -> Array:
	if _action_cache.is_empty():
		_action_cache = {"gather": [], "craft": []}
		for aid in ctx.data.all_actions():
			var a: Dictionary = ctx.data.action(aid)
			if (a.get("outputs", []) as Array).is_empty():
				continue
			var sk := str(a.get("skill", ""))
			var has_inputs := not (a.get("inputs", []) as Array).is_empty()
			if GATHER_SKILLS.has(sk) and not has_inputs:
				_action_cache.gather.append(a)
			elif CRAFT_SKILLS.has(sk) and has_inputs and not _has_rare_input(a) and not bool(a.get("single_craft", false)):    # QA119: i pezzi singoli non si ripetono
				_action_cache.craft.append(a)
	return _action_cache[kind]


## Prodotto artigianale sbloccato, di fascia alta (migliore o migliore -1), senza ingredienti rari da mostro/gemma.
func _pick_craft_action() -> Dictionary:
	var cands: Array = []
	var best := 0
	var levels := _usable_skill_levels(CRAFT_SKILLS)
	for a in _static_actions("craft"):
		if levels.has(str(a.skill)) and int(levels[str(a.skill)]) >= int(a.get("level_req", 1)):
			cands.append(a)
			best = maxi(best, int(a.get("tier", 1)))
	var wide: Array = []
	for a in cands:
		if int(a.get("tier", 1)) >= best - 1:
			wide.append(a)
	if wide.is_empty():
		return {}
	return wide[ctx.rng.randi_range("world", 0, wide.size() - 1)]


static func _has_rare_input(a: Dictionary) -> bool:
	for i in a.get("inputs", []):
		var it := str(i.get("item", "")) if i is Dictionary else str(i[0])
		for p in RARE_INPUT_PREFIXES:
			if it.begins_with(p):
				return true
	return false


func _pick_by_tier(cands: Array, want: int) -> Dictionary:
	if cands.is_empty():
		return {}
	var exact: Array = []
	var lower: Array = []
	for a in cands:
		if int(a.get("tier", 1)) == want:
			exact.append(a)
		elif int(a.get("tier", 1)) < want:
			lower.append(a)
	var pool := exact if not exact.is_empty() else (lower if not lower.is_empty() else cands)
	return pool[ctx.rng.randi_range("world", 0, pool.size() - 1)]


## Zona sbloccata più alta -1 (la prima se è l'unica).
func _pick_zone() -> String:
	var cb := ctx.get_system("combat")
	if cb == null:
		return ""
	var open: Array = []
	for z in ctx.data.table("zones"):
		if bool(cb.call("zone_unlocked", str(z.id))):
			open.append(z)
	if open.is_empty():
		return ""
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return str(open[maxi(0, open.size() - 2)].id)


# ------------------------------------------------------------------ progressi

## Chiamato da QuestSystem con gli stessi eventi degli obiettivi di missione.
func apply_event(kind: String, params: Dictionary) -> void:
	if state == null:
		return
	var changed := false
	for period in ["daily", "weekly"]:
		for e in state[period]:
			var obj: Dictionary = e.obj
			if str(obj.get("type", "")) != kind or int(e.progress) >= int(e.target):
				continue
			if not _matches(obj, params):
				continue
			var add := int(params.get("gold", 0)) if kind == "sell_market" else int(params.get("qty", 1))
			e["progress"] = mini(int(e.target), int(e.progress) + add)
			changed = true
	if changed:
		contracts_changed.emit()


func _matches(obj: Dictionary, params: Dictionary) -> bool:
	for k in obj:
		if QuestSystem.RESERVED_KEYS.has(k):
			continue
		var want: Variant = obj[k]
		if str(want) == "any":
			continue
		if not params.has(k) or not QuestSystem.same_value(params[k], want):
			return false
	return true


# ------------------------------------------------------------------ azioni

## Riscatta una commissione completata: Gettoni, oro, (giornaliera) chiave a probabilità, (settimanale) Cassa della zona più alta.
func claim(contract_id: String) -> bool:
	var e := entry(contract_id)
	if e.is_empty() or int(e.progress) < int(e.target):
		return false
	var period := str(e.period)
	var rw: Dictionary = _rules().get("rewards", {}).get(period, {})
	var bank := ctx.get_system("bank")
	if bank == null:
		return false
	var tk := int(rw.get("commission_token", 0))
	bank.call("add", TOKEN, tk, "contract")
	bank.call("add_gold", int(e.gold))
	state.stats["claimed"] = int(state.stats.get("claimed", 0)) + 1
	state.stats["tokens_earned"] = int(state.stats.get("tokens_earned", 0)) + tk
	var parts: Array = [Loc.tf("UI_CONTRACTS_RW_TOKENS", {"n": tk})]
	if period == "daily":
		if ctx.rng.chance("loot", float(rw.get("key_chance", 0.0))):
			var k := _key_for_tier(int(e.tier))
			bank.call("add", k, 1, "contract")
			parts.append(Loc.t(ctx.data.item(k).get("name", k)))
	else:
		var crate := _best_zone_crate()
		if not crate.is_empty():
			var crates := ctx.get_system("crates")
			if crates != null:
				crates.call("grant_crate", crate, 1)
				parts.append(Loc.t(ctx.data.item(crate).get("name", crate)))
	state[period].erase(e)
	ctx.events.notice.emit("success", Loc.tf("UI_CONTRACTS_CLAIMED", {"rewards": ", ".join(PackedStringArray(parts))}), {"contract": contract_id})
	contracts_changed.emit()
	return true


func _key_for_tier(tier: int) -> String:
	var r := _rules()
	var n := clampi(int(floorf(float(tier + 1) / float(maxi(1, int(r["key_tier_div"]))))), 1, int(r["key_tier_max"]))
	return "key_t%d" % n


func _best_zone_crate() -> String:
	var cb := ctx.get_system("combat")
	if cb == null:
		return ""
	var best := ""
	var best_order := -1
	for z in ctx.data.table("zones"):
		if int(z.get("order", 0)) > best_order and bool(cb.call("zone_unlocked", str(z.id))):
			best_order = int(z.order)
			best = str(z.get("crate", ""))
	return best


## Cambio gratuito (1 al giorno): sostituisce una commissione senza progressi con un'altra di un modello diverso.
func reroll(contract_id: String) -> bool:
	var e := entry(contract_id)
	if e.is_empty() or int(e.progress) > 0 or free_rerolls_left() <= 0:
		return false
	var period := str(e.period)
	var avoid: Array = []
	for x in state[period]:
		avoid.append(str(x.tpl))
	var fresh := _generate(period, avoid)
	if fresh.is_empty():
		return false
	var idx: int = (state[period] as Array).find(e)
	fresh["born"] = int(e.born)             # il cambio non allunga né accorcia la scadenza
	state[period][idx] = fresh
	if int(state.reroll_day) != int(state.day):
		state["reroll_day"] = int(state.day)
		state["rerolls_used"] = 0
	state["rerolls_used"] = int(state.rerolls_used) + 1
	contracts_changed.emit()
	return true


## Negozio dei Gettoni: voci di contract_rules.token_shop. false se mancano i Gettoni (il Deposito pieno non blocca: il premio va nel Carro di Ritiro).
func buy(item_id: String) -> bool:
	var cost := 0
	for v in _rules().get("token_shop", []):
		if str(v.item) == item_id:
			cost = int(v.tokens)
	var bank := ctx.get_system("bank")
	if cost <= 0 or bank == null or tokens() < cost:
		return false
	if not bool(bank.call("remove", TOKEN, cost)):
		return false
	bank.call("add", item_id, 1, "contract_shop")
	contracts_changed.emit()
	return true
