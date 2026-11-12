class_name MarketSystem
extends GameSystem
## Mercato di Vaelmora, Emporio, Commesse e Fazioni (docs/10, contratto in docs/audit_2026-10-22/17).
## Possiede le sezioni di stato `market` (state_key), `orders` (Array, bacheca delle Commesse) e `factions`
## ({fazione: reputazione}); le ultime due vivono nella radice di stato (ctx.state) e sono create in from_state.
##
## Tutto il tempo è TEMPO DI GIOCO (`market.t`, secondi simulati): avanza in tick() e in simulate_offline(),
## mai col tempo reale di sistema. Gli eventi periodici (nuovo giorno -> tendenze, Gazzetta, rinnovo delle Commesse)
## sono programmati in `market.next_*` e consumati in ordine cronologico da _advance(): offline e online coincidono.
##
## Prezzo di vendita (docs/10 §3):
##   unitario = valore × tendenza(categoria) × Gazzetta × domanda × (1 − tassa) × (1 + market_sell_pct)
##   domanda  = 1 / (1 + venduti_recenti / volume_elastico),  venduti_recenti dimezza ogni `half_life_h` ore.
## Vendere q unità in blocco paga l'integrale della curva: V·ln((V+x+q)/(V+x)) × prezzo_senza_domanda
## (stesso risultato della vendita "una a una" a passi infinitesimi; l'anteprima usa la stessa funzione).
##
## Stato `market`: t, day, next_gazette_t, next_order_t, pending_fill[], order_seq, board_init, sold_recent{id:{n,t}},
## trend{cat:float}, history{cat:[float]}, gazette{active[],log[]}, npc{id:{slot,n}}, shop{id:acquisti},
## shop_daily{id:{day,n}}, seen{id:true}, sold_total, orders_done.

const DAY_S := 86400.0
const HOUR_S := 3600.0
## Categorie "da cassa": tassa maggiore (constants.market.skin_sell_tax).
const CRATE_ITEM_CATEGORIES: PackedStringArray = ["skin", "relic", "cosmetic"]
## Numeri di mercato e Commesse: SOLO dai dati (market_rules / orders_rules / constants.market), mai ripieghi nel codice.
const DEFAULT_FACTION := "merchant_league"       # categorie senza fazione in orders_rules.faction_by_category
const FEATURE_TOKEN := "feature:market"

var _cats: PackedStringArray = PackedStringArray()
var _rate_per_h: Dictionary = {}            # item_id -> unità/ora della migliore azione che lo crea
var _cb_item_gained: Callable
var _catalog_ok: Dictionary = {}


func _init() -> void:
	id = "market"
	state_key = "market"


func default_state() -> Variant:
	return {
		"t": 0.0, "day": 0, "next_gazette_t": 0.0, "next_order_t": 0.0, "pending_fill": [],
		"order_seq": 0, "board_init": false, "sold_recent": {}, "trend": {}, "history": {},
		"gazette": {"active": [], "log": []}, "npc": {}, "shop": {}, "shop_daily": {}, "seen": {},
		"sold_total": 0, "orders_done": 0,
	}


func setup() -> void:
	_cats = PackedStringArray(_market_rules().get("categories", []))
	_rate_per_h.clear()
	for a in ctx.data.all_actions().values():
		var time_s := float(a.get("time_s", 0.0))
		if time_s <= 0.0:
			continue
		for o in a.get("outputs", []):
			var rate := float(o.get("qty", 1)) / time_s * HOUR_S
			var key := str(o.get("item", ""))
			if rate > float(_rate_per_h.get(key, 0.0)):
				_rate_per_h[key] = rate
	_cb_item_gained = _on_item_gained
	if not ctx.events.item_gained.is_connected(_cb_item_gained):
		ctx.events.item_gained.connect(_cb_item_gained)


## Scollega gli ascoltatori (i test che creano molti sistemi lo chiamano alla fine).
func teardown() -> void:
	if ctx != null and ctx.events != null and _cb_item_gained.is_valid() and ctx.events.item_gained.is_connected(_cb_item_gained):
		ctx.events.item_gained.disconnect(_cb_item_gained)


func from_state(section: Variant) -> void:
	state = section
	var base: Dictionary = default_state()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	for k in ["active", "log"]:
		if not (state.gazette.get(k) is Array):
			state.gazette[k] = []
	state.day = int(state.day)
	state.order_seq = int(state.order_seq)
	state.sold_total = int(state.sold_total)
	state.orders_done = int(state.orders_done)
	if not (ctx.state.get("orders") is Array):
		ctx.state["orders"] = []
	if not (ctx.state.get("factions") is Dictionary):
		ctx.state["factions"] = {}
	for o in ctx.state.orders:
		for k in ["qty", "gold", "rep"]:
			o[k] = int(o.get(k, 0))
		_clamp_unique_order(o)
	for f in ctx.state.factions.keys():
		ctx.state.factions[f] = int(ctx.state.factions[f])
	state.pending_fill = (state.pending_fill as Array).map(func(x: Variant) -> float: return float(x))
	for c in _cats:
		if not state.trend.has(c):
			state.trend[c] = _trend_mean()
		if not (state.history.get(c) is Array) or (state.history[c] as Array).is_empty():
			state.history[c] = [float(state.trend[c])]
	if float(state.next_gazette_t) <= 0.0:
		state.next_gazette_t = float(state.t) + _gazette_interval_s()
	if float(state.next_order_t) <= 0.0:
		state.next_order_t = float(state.t) + _refresh_s()
	_apply_faction_mods()
	_apply_shop_mods()


func int_paths() -> PackedStringArray:
	return PackedStringArray(["day", "order_seq", "sold_total", "orders_done", "shop.*", "shop_daily.*.n", "shop_daily.*.day", "npc.*.n", "npc.*.slot"])


# ================================================================== tempo

func game_time() -> float:
	return float(state.t)


func tick(dt: float) -> void:
	_ensure_board()
	_advance(dt)


## Versione analitica: gli eventi vengono consumati in ordine cronologico (nessun passo da 0,1 s).
func simulate_offline(seconds: float) -> Dictionary:
	var before := _counters()
	_ensure_board()
	_advance(seconds)
	var after := _counters()
	var rep := {}
	for k in after:
		var d: int = int(after[k]) - int(before[k])
		if d > 0:
			rep[k] = d
	return rep


## R-OFF-6 (audit 84): oltre il limite offline il Mercato vive lo stesso (giorni dei limiti dell'Emporio, rinnovo della
## bacheca, Gazzetta, recupero della domanda); non produce nulla per il giocatore.
func advance_calendar(seconds: float) -> void:
	_ensure_board()
	_advance(seconds)


func _counters() -> Dictionary:
	return {"days": int(state.day), "orders": int(state.order_seq), "gazette_total": (state.gazette.log as Array).size()}


func _unlocked() -> bool:
	return (ctx.state.get("unlocks", []) as Array).has(FEATURE_TOKEN)


func _ensure_board() -> void:
	if not bool(state.board_init) and _unlocked():
		state.board_init = true
		_fill_board()


func _advance(dt: float) -> void:
	var target: float = float(state.t) + maxf(0.0, dt)
	var guard := 0
	while guard < 6000:
		guard += 1
		var best_t := target
		var kind := ""
		var day_t: float = (int(state.day) + 1) * DAY_S
		if day_t <= best_t:
			best_t = day_t
			kind = "day"
		if float(state.next_gazette_t) < best_t or (kind == "" and float(state.next_gazette_t) <= best_t):
			best_t = float(state.next_gazette_t)
			kind = "gaz"
		if float(state.next_order_t) < best_t or (kind == "" and float(state.next_order_t) <= best_t):
			best_t = float(state.next_order_t)
			kind = "ref"
		for p in state.pending_fill:
			if float(p) < best_t or (kind == "" and float(p) <= best_t):
				best_t = float(p)
				kind = "fill"
		if kind == "":
			state.t = target
			return
		state.t = maxf(float(state.t), best_t)
		match kind:
			"day":
				state.day = int(state.day) + 1
				_on_new_day()
			"gaz":
				if _unlocked():
					_spawn_gazette()
				state.next_gazette_t = float(state.next_gazette_t) + _gazette_interval_s()
			"ref":
				_expire_orders()
				if _unlocked():
					_fill_board()
				state.next_order_t = float(state.next_order_t) + _refresh_s()
			"fill":
				var arr: Array = state.pending_fill
				var best_i := 0
				for i in arr.size():
					if float(arr[i]) < float(arr[best_i]):
						best_i = i
				arr.remove_at(best_i)
				if _unlocked() and ctx.state.orders.size() < order_slots():
					_add_order()
	# salto in blocco (assenza lunghissima): riallinea le scadenze senza simulare ogni evento
	state.t = target
	state.day = int(floor(target / DAY_S))
	state.next_gazette_t = target + _gazette_interval_s()
	state.next_order_t = target + _refresh_s()
	state.pending_fill = []


# ================================================================== dati e parametri

func _market_rules() -> Dictionary:
	return ctx.data.rules("market_rules")


func _orders_rules() -> Dictionary:
	return ctx.data.rules("orders_rules")


func _gazette_interval_s() -> float:
	return float(_market_rules()["gazette_interval_h"]) * HOUR_S


func _refresh_s() -> float:
	return float(_orders_rules()["refresh_h"]) * HOUR_S


func _trend_mean() -> float:
	return float(_market_rules()["trend"]["mean"])


func _bank() -> Variant:
	return ctx.get_system("bank")


func is_tradeable(def_id: String) -> bool:
	var it: Dictionary = ctx.data.item(def_id)
	return not it.is_empty() and bool(it.get("tradeable", true)) and float(it.get("value", 0)) > 0.0


func category_of(def_id: String) -> String:
	var it: Dictionary = ctx.data.item(def_id)
	var sub := str(it.get("subcategory", ""))
	if _cats.has(sub):
		return sub
	var cat := str(it.get("category", ""))
	return cat if _cats.has(cat) else ""


func categories() -> PackedStringArray:
	return _cats


# ================================================================== prezzi di vendita

## Volume elastico (docs/10 §3): ore di produzione della migliore azione che crea l'oggetto, min 20; da drop 300/tier.
## Vale anche per gli oggetti non impilabili (equipaggiamento, attrezzi): prima avevano volume 20 e rendevano 0,02 x gph (QA3).
func volume(def_id: String) -> float:
	var rules := _market_rules()
	var dem: Dictionary = rules.get("demand", {})
	var min_v := float(dem["min_volume"])
	var it: Dictionary = ctx.data.item(def_id)
	var rate := float(_rate_per_h.get(def_id, 0.0))
	if rate > 0.0:
		return maxf(min_v, float(dem["elasticity_hours_of_production"]) * rate)
	return maxf(min_v, float(dem["drop_volume_per_tier"]) / maxf(1.0, float(it.get("tier", 1))))


func trend(cat: String) -> float:
	return float(state.trend.get(cat, _trend_mean())) if cat != "" else 1.0


func gazette_mult(cat: String) -> float:
	var m := 1.0
	if cat == "":
		return m
	for e in state.gazette.active:
		if str(e.category) == cat and float(e.ends_t) > float(state.t):
			m *= float(e.mult)
	return m


## Tasse effettive: tassa base (risorse o oggetti da cassa) ridotta da Licenze/fazione/Costellazioni (cap 80%).
func tax_rate(def_id: String) -> float:
	var it: Dictionary = ctx.data.item(def_id)
	var is_crate_item := CRATE_ITEM_CATEGORIES.has(str(it.get("category", "")))
	var base: float
	if is_crate_item:
		base = float(ctx.data.constants["market"]["skin_sell_tax"])
	else:
		base = float(_market_rules()["sell_tax"])
	var red: float = ctx.modifiers.total_add_capped("market_tax_reduction_pct")
	return base * (1.0 - clampf(red, 0.0, 100.0) / 100.0)


## Venduti recenti dopo il decadimento (emivita demand.half_life_h, in tempo di gioco).
func recent_sold(def_id: String, at_t: float = -1.0) -> float:
	var r: Variant = state.sold_recent.get(def_id)
	if r == null:
		return 0.0
	var now := float(state.t) if at_t < 0.0 else at_t
	var half_s := float(_market_rules()["demand"]["half_life_h"]) * HOUR_S
	return float(r.n) * pow(0.5, maxf(0.0, now - float(r.t)) / half_s)


func demand(def_id: String, at_t: float = -1.0) -> float:
	return 1.0 / (1.0 + recent_sold(def_id, at_t) / volume(def_id))


## Prezzo senza il fattore domanda (valore × tendenza × Gazzetta × (1−tassa) × bonus).
## `with_bonuses` = false toglie `market_sell_pct` e `gold_gain_pct` (usato per le Finiture, QA3 E2: con i bonus di
## mercato il ritorno delle Casse superava il 130% della chiave; resta la tassa ridotta dalle Licenze).
func base_price(def_id: String, with_bonuses: bool = true) -> float:
	if not is_tradeable(def_id):
		return 0.0
	var cat := category_of(def_id)
	var p := float(ctx.data.item(def_id).value) * trend(cat) * gazette_mult(cat) * (1.0 - tax_rate(def_id))
	if not with_bonuses:
		return p
	p *= 1.0 + minf(ctx.modifiers.total_add("market_sell_pct"), ctx.modifiers.cap_of("market_sell_pct")) / 100.0
	return p * _gold_gain_mult()


func _gold_gain_mult() -> float:
	return 1.0 + ctx.modifiers.total_add("gold_gain_pct", ["all", "market"]) / 100.0


## Prezzo marginale di una unità oggi (contratto: price_sell).
func price_sell(def_id: String) -> float:
	return base_price(def_id) * demand(def_id)


## Oro per vendere `qty` unità adesso, senza vendere (anteprima).
func quote_sell(def_id: String, qty: int) -> int:
	if qty <= 0 or not is_tradeable(def_id):
		return 0
	var v := volume(def_id)
	var x := recent_sold(def_id)
	return roundi(base_price(def_id) * v * log((v + x + float(qty)) / (v + x)))


## Vende `qty` unità dal Deposito. Ritorna l'oro ottenuto (0 se non vendibile o non posseduto).
func sell(def_id: String, qty: int) -> int:
	var bank: Variant = _bank()
	if bank == null or qty <= 0 or not is_tradeable(def_id):
		return 0
	# solo i pezzi vendibili: niente bloccati né equipaggiati (bank.sellable_count chiede a combat.is_equipped)
	qty = mini(qty, int(bank.sellable_count(def_id)) if bank.has_method("sellable_count") else int(bank.count(def_id)))
	if qty <= 0:
		return 0
	var gold := quote_sell(def_id, qty)
	if not bank.remove(def_id, qty):
		return 0
	return _record_sale(bank, def_id, qty, gold)


## Vende istanze precise del Deposito (vendita multipla e regole automatiche, UI-A G14): salta da sola le istanze
## bloccate, in uso, non vendibili o inesistenti. Ritorna l'oro ottenuto. Le pile si vendono con sell().
func sell_instances(uids: Array) -> int:
	var bank: Variant = _bank()
	if bank == null:
		return 0
	var by_def: Dictionary = {}
	for u in uids:
		var inst: Dictionary = bank.get_instance(str(u))
		if inst.is_empty() or bool(inst.get("locked", false)) or bool(bank.is_in_use(str(u))) or not is_tradeable(str(inst.def)):
			continue
		if not by_def.has(inst.def):
			by_def[inst.def] = []
		by_def[inst.def].append(str(u))
	var total := 0
	for def_id in by_def:
		var list: Array = by_def[def_id]
		var gold := quote_sell(str(def_id), list.size())
		var removed := 0
		for u in list:
			if bank.remove_instance(str(u)):
				removed += 1
		if removed > 0:
			total += _record_sale(bank, str(def_id), removed, gold if removed == list.size() else quote_sell(str(def_id), removed))
	return total


func _record_sale(bank: Variant, def_id: String, qty: int, gold: int) -> int:
	var x := recent_sold(def_id)
	state.sold_recent[def_id] = {"n": x + float(qty), "t": float(state.t)}
	state.sold_total = int(state.sold_total) + qty
	state.seen[def_id] = true
	if gold > 0:
		bank.add_gold(gold)
	ctx.events.item_sold.emit(def_id, qty, gold)
	if gold > 0:
		ctx.events.objective_event.emit("sell_market", {"gold": gold})     # missioni "incassa N oro" (docs/12 §3)
	return gold


## Vendita di massa: entries = [{"id": String, "qty": int}] -> oro totale (anteprima: quote_many).
func sell_many(entries: Array) -> int:
	var tot := 0
	for e in entries:
		tot += sell(str(e.id), int(e.qty))
	return tot


func quote_many(entries: Array) -> int:
	var tot := 0
	for e in entries:
		tot += quote_sell(str(e.id), int(e.qty))
	return tot


## Ore perché la domanda risalga al livello `target` (0..1) dopo le vendite attuali.
func hours_to_recover(def_id: String, target: float = 0.9) -> float:
	var x := recent_sold(def_id)
	var need := volume(def_id) * (1.0 / target - 1.0)
	if x <= need:
		return 0.0
	var half_h := float(_market_rules()["demand"]["half_life_h"])
	return half_h * log(x / need) / log(2.0)


## Domanda prevista tra `hours` ore (per il grafico del recupero).
func demand_in(def_id: String, hours: float) -> float:
	return demand(def_id, float(state.t) + hours * HOUR_S)


## Storico giornaliero della tendenza della categoria (ultimi price_history_days giorni).
func trend_history(cat: String) -> Array:
	return state.history.get(cat, [])


## Storico del prezzo unitario di un oggetto (valore × tendenza × (1−tassa), senza domanda).
func price_history(def_id: String) -> Array:
	var cat := category_of(def_id)
	var out: Array = []
	if cat == "" or not is_tradeable(def_id):
		return out
	var k := float(ctx.data.item(def_id).value) * (1.0 - tax_rate(def_id))
	for tr_v in trend_history(cat):
		out.append(k * float(tr_v))
	return out


# ================================================================== tendenze e Gazzetta

func _on_new_day() -> void:
	var tr_rules: Dictionary = _market_rules()["trend"]
	var theta := float(tr_rules["theta"])
	var sigma := float(tr_rules["sigma"])
	var lo := float(tr_rules["min"])
	var hi := float(tr_rules["max"])
	var mean := _trend_mean()
	var keep := int(_market_rules()["price_history_days"])
	var rng: RandomNumberGenerator = ctx.rng.stream("market")
	for c in _cats:
		var x := float(state.trend.get(c, mean))
		x = clampf(x + theta * (mean - x) + sigma * rng.randfn(), lo, hi)
		state.trend[c] = x
		var h: Array = state.history.get(c, [])
		h.append(x)
		while h.size() > keep:
			h.pop_front()
		state.history[c] = h
	# pulizia: venduti recenti ormai trascurabili ed eventi scaduti
	for k in state.sold_recent.keys():
		if recent_sold(str(k)) < 0.01:
			state.sold_recent.erase(k)
	_prune_gazette()


func _prune_gazette() -> void:
	var keep: Array = []
	for e in state.gazette.active:
		if float(e.ends_t) > float(state.t):
			keep.append(e)
	state.gazette.active = keep


func _spawn_gazette() -> void:
	var events: Array = ctx.data.table("gazette_events")
	if events.is_empty():
		return
	var weights: Array = events.map(func(e: Dictionary) -> float: return float(e.get("weight", 1)))
	var idx: int = ctx.rng.weighted_index("market", weights)
	if idx < 0:
		return
	var ev: Dictionary = events[idx]
	_prune_gazette()
	state.gazette.active.append({"id": ev.id, "category": ev.category, "mult": float(ev.mult),
		"ends_t": float(state.t) + float(ev.duration_h) * HOUR_S})
	state.gazette.log.append({"id": ev.id, "t": float(state.t)})
	while state.gazette.log.size() > 12:
		state.gazette.log.pop_front()
	ctx.events.market_event.emit(str(ev.id))


## Eventi della Gazzetta ancora in corso: [{id, category, mult, ends_t, text}].
func active_gazette() -> Array:
	var out: Array = []
	for e in state.gazette.active:
		if float(e.ends_t) > float(state.t):
			var d: Dictionary = (e as Dictionary).duplicate()
			d["text"] = ctx.data.get_def("gazette_events", str(e.id)).get("text", {})
			out.append(d)
	return out


# ================================================================== acquisti dai PNG (scorte)

func buy_price_npc(def_id: String) -> int:
	if not is_tradeable(def_id) or category_of(def_id) == "" or not ctx.mode_rules().market_buy_allowed(def_id):
		return 0                      # Autarchica: solo fiale e semi base (docs/05 §7); prezzo 0 = non in vendita
	var cat := category_of(def_id)
	var markup := float(_market_rules()["buy_markup_equipment"]) if cat == "equipment" \
		else float(_market_rules()["buy_markup"])
	return ceili(float(ctx.data.item(def_id).value) * markup * trend(cat))


func npc_stock_cap(def_id: String) -> int:
	return maxi(1, int(volume(def_id) / 4.0))


## Scorte disponibili adesso (rifornite ogni refresh_min minuti di tempo di gioco).
func npc_stock(def_id: String) -> int:
	if buy_price_npc(def_id) <= 0:
		return 0
	var slot := int(floor(float(state.t) / (float(_market_rules()["npc_stock"]["refresh_min"]) * 60.0)))
	var rec: Dictionary = state.npc.get(def_id, {})
	var bought := int(rec.get("n", 0)) if int(rec.get("slot", -1)) == slot else 0
	return maxi(0, npc_stock_cap(def_id) - bought)


func buy_npc(def_id: String, qty: int) -> bool:
	var bank: Variant = _bank()
	var price := buy_price_npc(def_id)
	if bank == null or qty <= 0 or price <= 0 or qty > npc_stock(def_id):
		return false
	if not bank.spend_gold(price * qty):
		return false
	var added: int = int(bank.add(def_id, qty, "market"))
	if added < qty:
		bank.add_gold(price * (qty - added))
	if added <= 0:
		return false
	var slot := int(floor(float(state.t) / (float(_market_rules()["npc_stock"]["refresh_min"]) * 60.0)))
	var rec: Dictionary = state.npc.get(def_id, {})
	var bought := (int(rec.get("n", 0)) if int(rec.get("slot", -1)) == slot else 0) + added
	state.npc[def_id] = {"slot": slot, "n": bought}
	state.seen[def_id] = true
	ctx.events.item_bought.emit(def_id, added)
	return true


# ================================================================== Commesse

func order_slots() -> int:
	if not orders_enabled():
		return 0
	return int(_orders_rules()["board_slots"]) + int(ctx.modifiers.total_add_capped("orders_slots"))


## false in Autarchica: la bacheca resta vuota e nessuna Commessa nasce (docs/05 §7).
func orders_enabled() -> bool:
	return ctx.mode_rules().orders_enabled()


## Commesse attive (non scadute).
func orders() -> Array:
	var out: Array = []
	for o in ctx.state.orders:
		if float(o.expires_t) > float(state.t):
			out.append(o)
	return out


func get_order(order_id: String) -> Dictionary:
	for o in ctx.state.orders:
		if str(o.id) == order_id:
			return o
	return {}


func next_refresh_in() -> float:
	return maxf(0.0, float(state.next_order_t) - float(state.t))


func _expire_orders() -> void:
	var keep: Array = []
	for o in ctx.state.orders:
		if float(o.expires_t) > float(state.t):
			keep.append(o)
	ctx.state.orders.clear()
	ctx.state.orders.append_array(keep)


## QA119: le Commesse già in bacheca (vecchi salvataggi) di pezzi non impilabili con quantità enorme si riducono al tetto
## dei dati; la ricompensa scala in proporzione (resta qty * valore * moltiplicatore).
func _clamp_unique_order(o: Dictionary) -> void:
	var cap := int(_orders_rules()["unique_qty_max"])
	var it: Dictionary = ctx.data.item(str(o.get("item", "")))
	if cap <= 0 or it.is_empty() or bool(it.get("stackable", true)) or int(o.qty) <= cap:
		return
	o.gold = roundi(float(o.gold) * float(cap) / float(maxi(1, int(o.qty))))
	o.qty = cap


func _fill_board() -> void:
	while ctx.state.orders.size() < order_slots():
		if not _add_order():
			break


func _add_order() -> bool:
	if not orders_enabled():
		return false
	var o := _make_order()
	if o.is_empty():
		return false
	ctx.state.orders.append(o)
	return true


## Oggetti che la Commessa può chiedere: già visti dal giocatore (raccolti/prodotti/venduti/comprati),
## scambiabili, appartenenti a una categoria di mercato, non già in bacheca.
func order_candidates() -> Array:
	var seen: Dictionary = (state.seen as Dictionary).duplicate()
	var stacks: Variant = ctx.state.get("bank", {}).get("stacks")
	if stacks is Dictionary:
		for k in stacks:
			seen[k] = true
	var on_board := {}
	for o in ctx.state.orders:
		on_board[str(o.item)] = true
	var out: Array = []
	var keys: Array = seen.keys()
	keys.sort()
	for k in keys:
		var kid := str(k)
		if is_tradeable(kid) and category_of(kid) != "" and not on_board.has(kid) and not _order_excluded(kid):
			out.append(kid)
	return out


## Oggetti che non possono essere richiesti da una Commessa (orders_rules.item_pool_excluded): categorie escluse
## (Finiture, Reliquie) e oggetti unici da drop. Tengono le Commesse entro R-EC-3 (max 1,5 x gph orari).
func _order_excluded(def_id: String) -> bool:
	var ex: Dictionary = _orders_rules().get("item_pool_excluded", {})
	var it: Dictionary = ctx.data.item(def_id)
	var excluded_cats: Array = ex.get("categories", [])
	if excluded_cats.has(str(it.get("category", ""))) or excluded_cats.has(category_of(def_id)):
		return true
	if (ex.get("items", []) as Array).has(def_id):
		return true
	return bool(ex.get("unique_items", false)) and bool(it.get("unique", false))


## Intervallo [min, max] letto da orders_rules (qty_range, reward_mult_range): nessun numero di bilanciamento nel codice.
func _order_range(key: String, rng: RandomNumberGenerator) -> float:
	var r: Array = _orders_rules().get(key, [])
	if r.size() < 2:
		return 1.0
	return rng.randf_range(float(r[0]), float(r[1]))


func faction_of_category(cat: String) -> String:
	return str(_orders_rules().get("faction_by_category", {}).get(cat, DEFAULT_FACTION))


## Reputazione base della Commessa: dalla formula testuale dei dati ("10 + 5 * tier").
func order_rep(tier: int) -> int:
	var m := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s*\\+\\s*(\\d+(?:\\.\\d+)?)\\s*\\*\\s*tier").search(
		str(_orders_rules().get("reputation_formula", "")))
	if m == null:
		return 10 + 5 * tier
	return roundi(float(m.get_string(1)) + float(m.get_string(2)) * tier)


func _make_order() -> Dictionary:
	var cands := order_candidates()
	if cands.is_empty():
		return {}
	var rules := _orders_rules()
	var rng: RandomNumberGenerator = ctx.rng.stream("market")
	var item_id: String = cands[rng.randi_range(0, cands.size() - 1)]
	var it: Dictionary = ctx.data.item(item_id)
	var tier := int(it.get("tier", 1))
	var qty := maxi(1, roundi(volume(item_id) * _order_range("qty_range", rng)))
	var uniq_max := int(rules["unique_qty_max"])      # QA119: pezzi non impilabili = uno per volta, mai centinaia
	if uniq_max > 0 and not bool(it.get("stackable", true)):
		qty = mini(qty, uniq_max)
	var gold := roundi(float(qty) * float(it.value) * _order_range("reward_mult_range", rng))
	var cat := category_of(item_id)
	var fid := faction_of_category(cat)
	var crate_id := ""
	if rng.randf() < float(rules["crate_chance"]):
		crate_id = _pick_crate(tier, rng)
	state.order_seq = int(state.order_seq) + 1
	var fdef: Dictionary = ctx.data.get_def("factions", fid)
	return {"id": "o_%06d" % int(state.order_seq), "item": item_id, "qty": qty, "gold": gold, "rep": order_rep(tier),
		"faction": fid, "npc": str(fdef.get("npc", "bertoldo")), "crate": crate_id,
		"created_t": float(state.t), "expires_t": float(state.t) + _order_lifetime_s()}


func _order_lifetime_s() -> float:
	return float(_orders_rules()["lifetime_days"]) * DAY_S


func _pick_crate(tier: int, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for c in ctx.data.items_by_category("crate"):
		if str(c.get("subcategory", "")) == "crate" and bool(c.get("tradeable", true)) and int(c.get("tier", 1)) <= tier + 1:
			pool.append(str(c.id))
	pool.sort()
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else ""


## Consegna una Commessa: toglie gli oggetti dal Deposito, paga oro, reputazione e (forse) una Cassa.
func complete_order(order_id: String) -> bool:
	var bank: Variant = _bank()
	var o := get_order(order_id)
	if bank == null or o.is_empty() or not orders_enabled() or float(o.expires_t) <= float(state.t):
		return false
	if not bank.has(str(o.item), int(o.qty)) or not bank.remove(str(o.item), int(o.qty)):
		return false
	var gold := roundi(float(o.gold) * _gold_gain_mult())
	if gold > 0:
		bank.add_gold(gold)
	add_reputation(str(o.faction), int(o.rep))
	var crate_id := str(o.get("crate", ""))
	if crate_id != "":
		var crates: Variant = ctx.get_system("crates")
		if crates != null and crates.has_method("grant_crate"):
			crates.grant_crate(crate_id, 1)
		else:
			bank.add(crate_id, 1, "order")
	ctx.state.orders.erase(o)
	state.orders_done = int(state.orders_done) + 1
	state.seen[str(o.item)] = true
	ctx.events.order_completed.emit(order_id)
	ctx.events.objective_event.emit("orders_complete", {"qty": 1})       # incarichi di fazione (GUILD-2)
	return true


## Rifiuta una Commessa: il posto si riempie di nuovo dopo il tempo di attesa (30 min di gioco).
func reject_order(order_id: String) -> bool:
	var o := get_order(order_id)
	if o.is_empty():
		return false
	ctx.state.orders.erase(o)
	state.pending_fill.append(float(state.t) + float(_orders_rules()["reject_cooldown_min"]) * 60.0)
	return true


# ================================================================== fazioni

func faction_ids() -> Array:
	return ctx.data.table("factions").map(func(f: Dictionary) -> String: return str(f.id))


func reputation(faction_id: String) -> int:
	return int(ctx.state.factions.get(faction_id, 0))


## Indice del grado (0 = Neutrale) per la reputazione attuale.
func rank_index(faction_id: String) -> int:
	return rank_index_for(faction_id, reputation(faction_id))


func rank_index_for(faction_id: String, rep: int) -> int:
	var ranks: Array = ctx.data.get_def("factions", faction_id).get("ranks", [])
	var idx := 0
	for i in ranks.size():
		if rep >= int(ranks[i].rep):
			idx = i
	return idx


func rank_id(faction_id: String) -> String:
	var ranks: Array = ctx.data.get_def("factions", faction_id).get("ranks", [])
	var i := rank_index(faction_id)
	return str(ranks[i].id) if i < ranks.size() else ""


## Tetto TECNICO della reputazione (2^50): oltre, la somma a int64 andrebbe in overflow e il salvataggio verrebbe rifiutato (QA 83).
const REP_CAP := 1 << 50


## Aggiunge reputazione (moltiplicata da faction_rep_pct). Ritorna la quantità realmente guadagnata.
func add_reputation(faction_id: String, amount: int) -> int:
	if amount <= 0 or ctx.data.get_def("factions", faction_id).is_empty():
		return 0
	var gained := roundi(ctx.modifiers.apply(float(mini(amount, REP_CAP)), "faction_rep_pct"))
	var old_rank := rank_index(faction_id)
	ctx.state.factions[faction_id] = mini(reputation(faction_id) + gained, REP_CAP)      # saturazione: niente overflow a int64
	if rank_index(faction_id) != old_rank:
		_apply_faction_mods()
		ctx.events.faction_rank_up.emit(faction_id, rank_id(faction_id))
		ctx.events.important_event.emit("faction_rank")
	return gained


func _apply_faction_mods() -> void:
	for f in ctx.data.table("factions"):
		var ranks: Array = f.get("ranks", [])
		var cur := rank_index(str(f.id))
		var cur_rank_id := str(ranks[cur].id) if cur < ranks.size() else ""
		var mods: Array = []
		var reached := true
		for r in ranks:
			for rw in f.get("rank_rewards", []):
				if str(rw.rank) == str(r.id) and reached:
					mods.append_array(_known_mods(rw.get("modifiers", [])))
			if str(r.id) == cur_rank_id:
				reached = false
		ctx.modifiers.set_source("faction:" + str(f.id), mods)


func _known_mods(mods: Array) -> Array:
	var out: Array = []
	for m in mods:
		if _family_known(str(m.key).split(":")[0]):
			out.append({"key": m.key, "value": float(m.value), "mode": str(m.get("mode", "add"))})
	return out


func _family_known(family: String) -> bool:
	if not _catalog_ok.has(family):
		_catalog_ok[family] = not ctx.data.modifier_family(family).is_empty()
	return _catalog_ok[family]


# ================================================================== Emporio

func shop_entry(shop_id: String) -> Dictionary:
	for e in ctx.data.table("shop"):
		if str(e.id) == shop_id:
			return e
	return {}


func shop_entries() -> Array:
	return ctx.data.table("shop")


func owned(shop_id: String) -> int:
	return int(state.shop.get(shop_id, 0))


## Prezzo di un acquisto: fisso (`price`) o dalla formula dei dati ("base * crescita^n", con tetto "min(tetto, ...)").
func shop_unit_price(e: Dictionary, n_owned: int) -> int:
	if e.has("price"):
		return int(e.price)
	var f := str(e.get("price_formula", ""))
	var m := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s*\\*\\s*(\\d+(?:\\.\\d+)?)\\^n").search(f)
	if m == null:
		return 0
	var p := float(m.get_string(1)) * pow(float(m.get_string(2)), n_owned)
	var cap := RegEx.create_from_string("min\\(\\s*(\\d+(?:\\.\\d+)?)").search(f)
	if cap != null:
		p = minf(p, float(cap.get_string(1)))
	return roundi(p)


## Quantita' massima per una singola richiesta di acquisto all'Emporio (protegge il ciclo dei prezzi).
const MAX_SHOP_BATCH := 100000


func shop_max(e: Dictionary) -> int:
	if e.has("max"):
		return int(e.max)
	if e.has("max_purchases"):
		return int(e.max_purchases)
	return 1 if str(e.section) == "upgrades" else -1


func hero_level() -> int:
	return int(ctx.state.get("skills", {}).get("hero", {}).get("level", 1))


func daily_used(shop_id: String) -> int:
	var r: Dictionary = state.shop_daily.get(shop_id, {})
	return int(r.get("n", 0)) if int(r.get("day", -1)) == int(state.day) else 0


## Tetto TECNICO di una quantità d'acquisto (la UI usa 1 e 10): oltre, `shop_status` risponde "max" senza calcolare i prezzi.
const BULK_MAX := 100000


## Stato di un acquisto: {"ok", "reason", "cost", "owned", "max", "limit_left"}.
## reason: "" | unknown | max | requires_item | requires_level | requires_faction | limit | gold
func shop_status(shop_id: String, qty: int = 1) -> Dictionary:
	var e := shop_entry(shop_id)
	var res := {"ok": false, "reason": "unknown", "cost": 0, "owned": 0, "max": -1, "limit_left": -1}
	if e.is_empty() or qty <= 0:
		return res
	var n_owned := owned(shop_id)
	if qty > MAX_SHOP_BATCH:          # F4: quantita' assurda, niente ciclo di prezzi
		res.reason = "max"
		res.owned = n_owned
		res.max = shop_max(e)
		return res
	var mx := shop_max(e)
	res.owned = n_owned
	res.max = mx
	if e.has("item") and not ctx.mode_rules().market_buy_allowed(str(e.item)):
		res.reason = "mode"           # Autarchica: tutto il resto si produce da soli
		return res
	if qty > BULK_MAX:
		res.reason = "max"            # quantità assurda: rifiutata prima del ciclo dei prezzi (un qty enorme lo bloccava, QA 83 C-04)
		return res
	var cost := 0
	for i in qty:
		cost += shop_unit_price(e, n_owned + i)
	res.cost = cost
	if e.has("daily_limit"):
		res.limit_left = int(e.daily_limit) - daily_used(shop_id)
	var req: Variant = e.get("requires")
	if req is String and owned(str(req)) <= 0:
		res.reason = "requires_item"
	elif req is Dictionary and (req as Dictionary).has("hero_level") and hero_level() < int(req.hero_level):
		res.reason = "requires_level"
	elif req is Dictionary and (req as Dictionary).has("faction") and rank_index(str(req.faction)) < _rank_pos(str(req.faction), str(req.rank)):
		res.reason = "requires_faction"
	elif mx >= 0 and n_owned + qty > mx:
		res.reason = "max"
	elif int(res.limit_left) >= 0 and qty > int(res.limit_left):
		res.reason = "limit"
	else:
		var bank: Variant = _bank()
		res.reason = "" if (bank != null and int(bank.gold()) >= cost) else "gold"
		res.ok = res.reason == ""
	return res


func _rank_pos(faction_id: String, rank_id_str: String) -> int:
	var ranks: Array = ctx.data.get_def("factions", faction_id).get("ranks", [])
	for i in ranks.size():
		if str(ranks[i].id) == rank_id_str:
			return i
	return 0


## Compra dall'Emporio (contratto: buy). Oro dal Deposito; potenziamenti permanenti o oggetti.
func buy(shop_item_id: String, qty: int = 1) -> bool:
	var st := shop_status(shop_item_id, qty)
	if not st.ok:
		return false
	var e := shop_entry(shop_item_id)
	var bank: Variant = _bank()
	var cost: int = st.cost
	if not bank.spend_gold(cost):
		return false
	if e.has("item"):
		var added: int = int(bank.add(str(e.item), qty, "shop"))
		if added < qty:
			bank.add_gold(shop_unit_price(e, 0) * (qty - added))
		if added <= 0:
			return false
		qty = added
		state.seen[str(e.item)] = true
	else:
		state.shop[shop_item_id] = owned(shop_item_id) + qty
		_apply_shop_mods()
		ctx.events.important_event.emit("shop_upgrade")
	if e.has("daily_limit"):
		state.shop_daily[shop_item_id] = {"day": int(state.day), "n": daily_used(shop_item_id) + qty}
	ctx.events.item_bought.emit(str(e.get("item", shop_item_id)), qty)
	return true


## «Espandi Deposito» (resoconto 114): anteprima e acquisto di `qty` spazi senza passare dall'Emporio. Stesso prezzo, stesso
## contatore (`shop.bank_slot`) e stessi controlli di `buy` (che resta l'unico punto in cui si paga). Chiavi: ok, reason
## ("" | gold | max | unknown…), cost, added, cap_now, cap_after, owned, max, left (acquisti rimasti), missing (oro che manca),
## next_price (prezzo del prossimo spazio), gold.
func bank_expansion(qty: int = 1) -> Dictionary:
	var entry_id := BankSystem.SHOP_BANK_ENTRY
	var e := shop_entry(entry_id)
	var bank: Variant = _bank()
	var st := shop_status(entry_id, qty)
	var cap := int(bank.capacity()) if bank != null else 0
	var gold := int(bank.gold()) if bank != null else 0
	var mx := int(st.max)
	var out := {"ok": bool(st.ok), "reason": str(st.reason), "cost": int(st.cost), "added": qty, "cap_now": cap, "cap_after": cap + qty,
		"owned": int(st.owned), "max": mx, "left": (mx - int(st.owned)) if mx >= 0 else -1, "gold": gold,
		"missing": maxi(0, int(st.cost) - gold), "next_price": shop_unit_price(e, int(st.owned)) if not e.is_empty() else 0}
	return out


## Compra `qty` spazi del Deposito (vedi `bank_expansion`). true se l'acquisto è riuscito.
func buy_bank_slots(qty: int = 1) -> bool:
	if not buy(BankSystem.SHOP_BANK_ENTRY, qty):
		return false
	ctx.events.notice.emit("success", Loc.tf("UI_BANKX_BOUGHT", {"n": qty, "cap": int(_bank().capacity())}), {"reason": "bank_expanded"})
	return true


## Somma numerica degli effetti dei potenziamenti posseduti per una chiave (es. "loadouts").
func shop_effect_total(key: String) -> float:
	var tot := 0.0
	for e in ctx.data.table("shop"):
		var n := owned(str(e.id))
		if n > 0 and e.get("effect") is Dictionary and _is_num((e.effect as Dictionary).get(key)):
			tot += float(e.effect[key]) * n
	return tot


## Parametri dell'Auto-mangiare del grado più alto posseduto ({} se nessuno). Letto dal combattimento.
func auto_eat() -> Dictionary:
	var best: Dictionary = {}
	for e in ctx.data.table("shop"):
		if owned(str(e.id)) > 0 and e.get("effect") is Dictionary and (e.effect as Dictionary).has("auto_eat"):
			best = e.effect.auto_eat
	return best


func _is_num(v: Variant) -> bool:
	return v is float or v is int


func _apply_shop_mods() -> void:
	for e in ctx.data.table("shop"):
		var n := owned(str(e.id))
		var src := "shop:" + str(e.id)
		var mods: Array = []
		if n > 0:
			if str(e.id) == "bank_slot":
				mods.append({"key": "bank_slots", "value": float(n), "mode": "add"})
			elif e.get("effect") is Dictionary:
				for k in e.effect:
					if (e.effect[k] is float or e.effect[k] is int) and _family_known(str(k)):
						mods.append({"key": k, "value": float(e.effect[k]) * n, "mode": "add"})
		ctx.modifiers.set_source(src, mods)


# ================================================================== eventi

func _on_item_gained(def_id: String, _qty: int, _source: String) -> void:
	if ctx == null or ctx.simulation() == null:
		teardown()          # simulazione distrutta (nuova partita): smetto di ascoltare
		return
	if state != null:
		state.seen[def_id] = true
