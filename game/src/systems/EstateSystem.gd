class_name EstateSystem
extends GameSystem
## La Tenuta (docs/11 §1-4, T-6.1/T-6.2): edifici con livello, coloni, Dispensa, Magazzino, Bottega, raccolta,
## Caveau Privato, Rifondazione/Soci, piccoli eventi di colore. id "estate". Tutto a TEMPO DI GIOCO.
##
## Stato (ctx.state.estate):
##   t          secondi di gioco simulati dalla Tenuta
##   buildings  {id: {"level": int, "product": item_id, "grade": int}}        (grade = massimo mai raggiunto, resta alla Rifondazione)
##   settlers   int (coloni arrivati)  ·  settler_s  secondi dall'ultimo arrivo
##   pantry     float, razioni di cibo nella Dispensa
##   storage    {item_id: float}  Magazzino (unità prodotte non ancora raccolte)
##   listed     {item_id: bool}   merci "in vendita" per la Bottega (di base tutte; false = tenere)
##   prosperity float (Punti Prosperità: unità prodotte a vita)  ·  partners, refounds: LEGACY, i Soci stanno in PrestigeSystem (assorbiti al caricamento)
##   sell_gold  float (oro maturato dalla Bottega e non ancora versato)  ·  vault_s  avanzamento del Caveau Privato
##   events     {"next_s": float, "log": [{"id","t"}], "count": int}
##   stats      {"produced","sold_gold","crates","collected"}
##
## SIMULAZIONE: continua e a tratti (_advance). Dentro un tratto tutte le velocità sono costanti; i tratti finiscono
## quando succede qualcosa (Dispensa vuota, Magazzino pieno, scorta esaurita, arrivo di un colono, cassa del Caveau,
## evento). tick(0,1 s) e simulate_offline(N s) usano lo STESSO codice: l'offline è analitico (O(eventi)) e coincide
## col tick fino all'arrotondamento. Bonus: estate_prod_pct, estate_cost_reduction_pct, estate_auto_collect via
## Modifiers; i Soci sono la fonte "prestige:partners" di PrestigeSystem (estate_prod_pct).
## Uscite: oro e oggetti verso il bank, casse verso crates.grant_crate (se c'è) o bank.add.

## Numeri di bilanciamento: data/constants.json -> `estate_tuning` (fonte: tools/gamedata/tuning.py), nessun valore qui (regola 2).
static func tuning() -> Dictionary:
	return Formulas.k().get("estate_tuning", {})


## Soglie puramente TECNICHE (tolleranze numeriche, guardie dei cicli): non sono numeri di bilanciamento.
const TECH := {
	"eps": 1e-9,
	"max_segments": 400,
	"min_segment_s": 1e-3,
}
## Eventi di colore (testi in localization/parts/estate.csv: UI_ESTATE_EV_<id>). effect: none | gold | pantry_plus | pantry_minus.
const EVENTS: Array = [
	{"id": "cat_nap", "w": 10, "effect": "none"},
	{"id": "postman", "w": 6, "effect": "gold"},
	{"id": "settlers_debate", "w": 10, "effect": "none"},
	{"id": "cat_ration", "w": 5, "effect": "pantry_minus"},
	{"id": "forgotten_larder", "w": 4, "effect": "pantry_plus"},
	{"id": "goat_inspection", "w": 8, "effect": "none"},
	{"id": "scarecrow_union", "w": 8, "effect": "none"},
	{"id": "nap_contest", "w": 8, "effect": "none"},
]
const GUILD_TOKEN := "feature:mercenaries"     # token della Gilda (dati + ScreenRegistry)

var _rules: Dictionary = {}
var _b_defs: Dictionary = {}                 # building_id -> definizione
var _b_order: Array = []                     # id in ordine
var _by_sub: Dictionary = {}                 # sottocategoria -> {tier: item_id}
var _skill_of_sub: Dictionary = {}           # sottocategoria -> mansione (dalle azioni)
var _k: Dictionary = {}
var _crate_log: Dictionary = {}          # casse del Caveau dall'ultimo azzeramento (report offline, non salvato)
var _guild_granted: bool = false
var _offline: bool = false             # true durante simulate_offline: niente notifiche per ogni evento
var _auto_foods: Array = []            # cibi ammessi alla Dispensa automatica, dal meno al più caro (id come spareggio)
var _auto_drawn: float = 0.0           # razioni prese dal Deposito dall'ultimo azzeramento (report offline, non salvato)


func _init() -> void:
	id = "estate"
	state_key = "estate"


# ------------------------------------------------------------------ ciclo di vita

func setup() -> void:
	_k = ctx.constants().get("estate", {})
	_rules = ctx.data.rules("estate_rules")
	_b_defs.clear()
	_b_order.clear()
	for b in ctx.data.table("estate_buildings"):
		_b_defs[b.id] = b
		_b_order.append(b.id)
	_by_sub.clear()
	for cat in ["material"]:
		for it in ctx.data.items_by_category(cat):
			var sub := str(it.get("subcategory", ""))
			if not _by_sub.has(sub):
				_by_sub[sub] = {}
			_by_sub[sub][int(it.get("tier", 1))] = str(it.id)
	_auto_foods.clear()
	for fd in ctx.data.items_by_category("food"):
		if str(fd.get("subcategory", "")) != "feast":          # i banchetti sono buff dell'Eroe, non razioni
			_auto_foods.append(fd)
	_auto_foods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va := float(a.get("value", 0.0))
		var vb := float(b.get("value", 0.0))
		return str(a.id) < str(b.id) if is_equal_approx(va, vb) else va < vb)
	_skill_of_sub.clear()
	var acts: Dictionary = ctx.data.all_actions()
	for aid in acts:
		var a: Dictionary = acts[aid]
		if not a.has("outputs") or (a.outputs as Array).is_empty() or str(a.get("skill", "")) == "":
			continue
		var it: Dictionary = ctx.data.item(str((a.outputs as Array)[0].item))
		var sub := str(it.get("subcategory", ""))
		if sub != "" and not _skill_of_sub.has(sub) and str(a.get("kind", "")) != "combat":
			_skill_of_sub[sub] = str(a.skill)


func default_state() -> Variant:
	return {"t": 0.0, "buildings": {}, "settlers": 0, "settler_s": 0.0, "pantry": 0.0, "pantry_auto": true, "storage": {}, "listed": {},
		"prosperity": 0.0, "partners": 0, "refounds": 0, "sell_gold": 0.0, "vault_s": 0.0,
		"events": {"next_s": -1.0, "log": [], "count": 0},
		"stats": {"produced": 0.0, "sold_gold": 0.0, "crates": 0, "collected": 0.0}}


func from_state(section: Variant) -> void:
	state = section
	if not (state is Dictionary):         # il GameState di base ha liste vuote al posto delle sezioni
		state = default_state()
		ctx.state[state_key] = state
	var d: Dictionary = default_state()
	for key in d:
		if not state.has(key) or typeof(state[key]) != typeof(d[key]):
			if typeof(d[key]) == TYPE_FLOAT and (typeof(state.get(key)) == TYPE_INT):
				state[key] = float(state[key])
			elif typeof(d[key]) == TYPE_INT and typeof(state.get(key)) == TYPE_FLOAT:
				state[key] = int(state[key])
			else:
				state[key] = d[key]
	for bid in state.buildings.keys():
		if not _b_defs.has(bid) or not (state.buildings[bid] is Dictionary):
			state.buildings.erase(bid)
			continue
		var b: Dictionary = state.buildings[bid]
		b["level"] = int(b.get("level", 0))
		b["grade"] = int(b.get("grade", 0))
		b["product"] = str(b.get("product", ""))
	if float((state.events as Dictionary).get("next_s", -1.0)) < 0.0:
		_schedule_event(true)
	_guild_granted = false


func int_paths() -> PackedStringArray:
	return PackedStringArray(["settlers", "partners", "refounds", "buildings.*.level", "buildings.*.grade", "stats.crates",
		"events.count"])


# ------------------------------------------------------------------ accesso a dati e stato (UI e altri sistemi)

func building_ids() -> Array:
	return _b_order.duplicate()


func def_of(bid: String) -> Dictionary:
	return _b_defs.get(bid, {})


func type_of(bid: String) -> String:
	return str(_b_defs.get(bid, {}).get("type", ""))


func level_of(bid: String) -> int:
	return int(state.buildings.get(bid, {}).get("level", 0))


func level_of_type(btype: String) -> int:
	for bid in _b_order:
		if type_of(bid) == btype:
			return level_of(bid)
	return 0


func total_levels() -> int:
	var n := 0
	for bid in state.buildings:
		n += int(state.buildings[bid].level)
	return n


func game_time() -> float:
	return float(state.t)


func _unlocks() -> Array:
	return ctx.state.get("unlocks", [])


## Edificio disponibile: token `building:<id>` (concesso dalle missioni) o la missione di sblocco completata.
func is_unlocked(bid: String) -> bool:
	if _unlocks().has("building:" + bid):
		return true
	var q := str(_b_defs.get(bid, {}).get("unlock", {}).get("quest", ""))
	return q != "" and (ctx.state.get("quests", {}).get("done", []) as Array).has(q)


func _bank() -> GameSystem:
	return ctx.get_system("bank")


func _entry(bid: String) -> Dictionary:
	if not state.buildings.has(bid):
		state.buildings[bid] = {"level": 0, "product": "", "grade": 0}
	return state.buildings[bid]


# ------------------------------------------------------------------ coloni, Dispensa, capienza

func settler_cap() -> int:
	var l := level_of_type("housing")
	return 0 if l <= 0 else int(tuning().cottage_base) + int(tuning().cottage_per_level) * l


func settlers() -> int:
	return int(state.settlers)


func settlers_assigned() -> int:
	var n := 0
	for bid in state.buildings:
		if bool(_b_defs[bid].get("uses_settlers", false)):
			n += int(state.buildings[bid].level)
	return n


func settlers_free() -> int:
	return settlers() - settlers_assigned()


func settler_arrival_s() -> float:
	return float(_rules.settlers.arrival_min) * 60.0


func pantry() -> float:
	return float(state.pantry)


func ration_use_per_h() -> float:
	return float(tuning().rations_per_settler_h) * settlers()


## Ore di Dispensa rimaste (INF se nessun colono).
func pantry_hours() -> float:
	var u := ration_use_per_h()
	return INF if u <= 0.0 else pantry() / u


## Moltiplicatore con la Dispensa vuota (dai dati: estate_rules.settlers.starving_mult).
func starving_mult() -> float:
	return float(_rules.settlers.starving_mult)


func food_factor() -> float:
	return 1.0 if pantry() > TECH.eps or settlers() <= 0 else float(_rules.settlers.starving_mult)


func base_capacity() -> float:
	var l := maxi(1, level_of_type("storage"))
	return float(tuning().storage_base) * pow(float(l), float(tuning().storage_exp))


func auto_collect() -> bool:
	return ctx.modifiers.total_add("estate_auto_collect") >= 1.0


## Capienza effettiva: con la raccolta automatica la produzione va direttamente al Deposito (nessun limite).
func capacity() -> float:
	return INF if auto_collect() else base_capacity()


func stored_total() -> float:
	var s := 0.0
	for it in state.storage:
		s += float(state.storage[it])
	return s


func stored(item_id: String) -> float:
	return float(state.storage.get(item_id, 0.0))


## Dispensa automatica (QA81 M1, docs/11 §3): con la Dispensa vuota e coloni da sfamare, prende dal Deposito fino a
## `pantry_auto_target_h` ore di razioni. Cibi dal meno al più caro; mai quelli bloccati, né i banchetti. REGOLA DEGLI SLOT
## (resoconto 117): un cibo messo in uno slot cibo dell'Eroe riserva al combattimento solo `pantry_slot_reserve` porzioni
## (dati); il resto della pila è utilizzabile dalla Dispensa. Con meno porzioni della riserva la Dispensa non lo tocca.
## Interruttore: state.pantry_auto. Ritorna le razioni prese.
func pantry_auto() -> bool:
	return bool(state.pantry_auto)


func set_pantry_auto(on: bool) -> void:
	state["pantry_auto"] = on
	ctx.events.estate_changed.emit()


func _auto_stock() -> float:
	if not pantry_auto() or settlers() <= 0 or pantry() > TECH.eps:
		return 0.0
	var b := _bank()
	if b == null:
		return 0.0
	var want := ration_use_per_h() * float(tuning().pantry_auto_target_h)
	if want <= 0.0:
		return 0.0
	var slots: Array = []
	var cb := ctx.get_system("combat")
	if cb != null:
		slots = (cb.state.get("food", []) as Array)
	var taken := 0.0
	for fd in _auto_foods:
		var fid := str(fd.id)
		if bool(b.call("is_def_locked", fid)):
			continue
		var have := int(b.call("count", fid))
		if slots.has(fid):
			have -= int(tuning().pantry_slot_reserve)         # lo slot dell'Eroe tiene solo la riserva, il resto è usabile
		if have <= 0:
			continue
		var n := mini(have, int(ceil(want - taken)))
		if n > 0 and bool(b.call("remove", fid, n)):
			taken += n
		if taken >= want - 1e-9:
			break
	if taken > 0.0:
		state.pantry = float(state.pantry) + taken
		_auto_drawn += taken
		ctx.events.estate_changed.emit()
	return taken


## Rifornisce la Dispensa con cibo del Deposito (1 unità di qualsiasi cibo = 1 razione). Ritorna le razioni aggiunte.
func stock_pantry(def_id: String, qty: int) -> int:
	var def: Dictionary = ctx.data.item(def_id)
	if def.is_empty() or str(def.get("category", "")) != "food" or qty <= 0:
		return 0
	var b := _bank()
	if b == null:
		return 0
	qty = mini(qty, int(b.count(def_id)))
	if qty <= 0 or not b.remove(def_id, qty):
		return 0
	state.pantry = float(state.pantry) + qty
	ctx.events.estate_changed.emit()
	return qty


# ------------------------------------------------------------------ produzione: tier, grado, prodotto

## Mansione collegata a una sottocategoria di prodotto ("" se sconosciuta).
func skill_for_sub(sub: String) -> String:
	return str(_skill_of_sub.get(sub, ""))


func _skill_tier(skill_id: String) -> int:
	var s := ctx.get_system("skills")
	if s == null or skill_id == "":
		return int(tuning().band_max)       # senza SkillSystem (test) nessun limite dalla mansione
	return Formulas.tier_of_level(int(s.level(skill_id)))


## Massimo tier che la mansione collegata permette per questo edificio (il migliore tra le sue sottocategorie).
func skill_tier_for(bid: String) -> int:
	var best := 0
	for sub in _subs_of(bid):
		best = maxi(best, _skill_tier(skill_for_sub(sub)))
	return best


func _subs_of(bid: String) -> Array:
	return _b_defs.get(bid, {}).get("production", {}).get("output_subcategories", [])


## Grado dell'edificio: il più alto con livello richiesto raggiunto e tier di mansione sufficiente (non cala mai).
func grade_of(bid: String) -> int:
	var d: Dictionary = _b_defs.get(bid, {})
	if not d.has("production"):
		return 0
	var lv := level_of(bid)
	var st := skill_tier_for(bid)
	var g := int(state.buildings.get(bid, {}).get("grade", 0))
	for u in d.production.get("grade_upgrades", []):
		if lv >= int(u.requires_level) and st >= int(u.requires_skill_tier):
			g = maxi(g, int(u.grade))
	return g


func tier_limit(bid: String) -> int:
	return mini(skill_tier_for(bid), grade_of(bid))


## Prodotti scelgibili (id oggetto) per un edificio produttore, dal tier più alto al più basso.
func product_options(bid: String) -> Array:
	var out: Array = []
	var lim := tier_limit(bid)
	for sub in _subs_of(bid):
		var by_t: Dictionary = _by_sub.get(sub, {})
		for t in by_t:
			if int(t) <= lim:
				out.append(by_t[t])
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ta := int(ctx.data.item(str(a)).tier)
		var tb := int(ctx.data.item(str(b)).tier)
		return ta > tb if ta != tb else str(a) < str(b))
	return out


## Prodotto effettivo: quello scelto se ancora valido, altrimenti il migliore disponibile.
func product_of(bid: String) -> String:
	var opts := product_options(bid)
	if opts.is_empty():
		return ""
	var chosen := str(state.buildings.get(bid, {}).get("product", ""))
	return chosen if opts.has(chosen) else str(opts[0])


func set_product(bid: String, item_id: String) -> bool:
	if not product_options(bid).has(item_id) or level_of(bid) <= 0:
		return false
	_entry(bid)["product"] = item_id
	ctx.events.estate_changed.emit()
	return true


func set_listed(item_id: String, on: bool) -> void:
	state.listed[item_id] = on


func is_listed(item_id: String) -> bool:
	return bool(state.listed.get(item_id, true))


# ------------------------------------------------------------------ velocità e moltiplicatori

func partners() -> int:
	var ps: Variant = _prestige()
	return int(ps.call("partners")) if ps != null else 0


## Moltiplicatore complessivo di produzione (Soci × bonus), senza il fattore cibo.
func prod_multiplier() -> float:
	return ctx.modifiers.multiplier("estate_prod_pct", [])


func milestone_next(level: int) -> int:
	for m in _k.milestones:
		if level < int(m):
			return int(m)
	return 0


func milestones_reached(level: int) -> int:
	var n := 0
	for m in _k.milestones:
		if level >= int(m):
			n += 1
	return n


## Unità/ora di un produttore con lo stato attuale (compreso il fattore cibo).
func units_per_hour(bid: String) -> float:
	if str(_b_defs.get(bid, {}).get("type", "")) != "producer":
		return 0.0
	var lv := level_of(bid)
	if lv <= 0 or product_of(bid) == "":
		return 0.0
	return Formulas.estate_units_per_hour(lv) * prod_multiplier() * food_factor()


func shop_units_per_hour() -> float:
	var l := level_of_type("seller")
	return 0.0 if l <= 0 else float(tuning().shop_units_per_level_h) * l * Formulas.estate_milestone_mult(l)


func shop_sell_pct() -> float:
	for bid in _b_order:
		if type_of(bid) == "seller":
			return float(_b_defs[bid].effect.sell_value_pct)
	return 0.0


## Tier di riferimento del giocatore per il tetto orario della Bottega (il tier più alto che un produttore consente).
func reference_tier() -> int:
	var t := 1
	for bid in _b_order:
		if type_of(bid) == "producer" and level_of(bid) > 0:
			t = maxi(t, tier_limit(bid))
	return t


## Oro/ora massimo che la Bottega può pagare: shop_income_cap_gph × gph(tier).
func shop_gold_cap_per_h() -> float:
	return float(_k.shop_income_cap_gph) * Formulas.gph(reference_tier())


func vault_interval_s() -> float:
	var l := level_of_type("crate_gen")
	if l <= 0:
		return INF
	return float(tuning().vault_interval_h) * 3600.0 / (1.0 + float(tuning().vault_speed_per_level) * l)


## Riepilogo per l'interfaccia: unità/ora totali dei produttori.
func total_units_per_hour() -> float:
	var s := 0.0
	for bid in _b_order:
		s += units_per_hour(bid)
	return s


# ------------------------------------------------------------------ costi e acquisto

func _band(level: int) -> int:
	return mini(int(tuning().band_max), 1 + int(floor(float(level) / float(tuning().band_levels))))


func _tier_item(sub: String, tier: int, at_most: bool = true) -> String:
	var by_t: Dictionary = _by_sub.get(sub, {})
	var best := -1
	for t in by_t:
		if (int(t) <= tier if at_most else int(t) == tier) and int(t) > best:
			best = int(t)
	if best < 0 and not at_most:
		return ""
	if best < 0:          # nessun oggetto fino a quel tier (es. lucchetti da tier 2): il più basso disponibile
		for t in by_t:
			best = int(t) if best < 0 else mini(best, int(t))
	return str(by_t[best]) if best >= 0 else ""


func gold_reduction_mult() -> float:
	return 1.0 - minf(ctx.modifiers.total_add("estate_cost_reduction_pct"), ctx.modifiers.cap_of("estate_cost_reduction_pct")) / 100.0


## Costo del passaggio dal livello `level` a level+1: {"gold": int, "items": {item_id: qty}}.
func cost_at(bid: String, level: int) -> Dictionary:
	var d: Dictionary = _b_defs.get(bid, {})
	if d.is_empty():
		return {"gold": 0, "items": {}}
	var band := _band(level)
	var gold_f := float(d.cost.gold_base) * pow(float(d.cost.gold_growth), level) * pow(float(_k.band_cost_growth), band - 1)
	var gold := int(maxf(1.0, ceil(float(Formulas.round_nice(gold_f)) * gold_reduction_mult())))
	var items := {}
	var plank := _tier_item("plank", band)
	var bar := _tier_item("bar", band)
	if plank != "":
		items[plank] = int(ceil(float(tuning().planks_base) + float(tuning().planks_per_level) * level))
	if bar != "":
		items[bar] = int(ceil(float(tuning().bars_base) + float(tuning().bars_per_level) * level))
	var granite := int(floor(float(level) / float(tuning().granite_every)))
	if level >= int(tuning().granite_from_level) and granite > 0:
		items[str(tuning().granite_item)] = granite
	if (str(d.type) == "storage" or str(d.type) == "crate_gen") and (level + 1) % int(tuning().padlock_every) == 0:
		var lock := _tier_item("padlock", band)
		if lock != "":
			items[lock] = 1
	return {"gold": gold, "items": items}


func cost_of(bid: String) -> Dictionary:
	return cost_at(bid, level_of(bid))


## "" se si può salire di un livello, altrimenti la chiave UI della ragione.
func can_upgrade(bid: String) -> String:
	var d: Dictionary = _b_defs.get(bid, {})
	if d.is_empty():
		return "UI_ESTATE_REASON_UNKNOWN"
	if not is_unlocked(bid):
		return "UI_ESTATE_REASON_LOCKED"
	if bool(d.uses_settlers) and settlers_free() < 1:
		return "UI_ESTATE_REASON_SETTLERS"
	var b := _bank()
	if b == null:
		return "UI_ESTATE_REASON_NOBANK"
	var c := cost_of(bid)
	if int(b.gold()) < int(c.gold):
		return "UI_ESTATE_REASON_GOLD"
	for it in c.items:
		if int(b.count(str(it))) < int(c.items[it]):
			return "UI_ESTATE_REASON_MATERIALS"
	return ""


## Sale di un livello (paga oro e materiali). Ritorna true se riuscito.
func upgrade(bid: String) -> bool:
	if can_upgrade(bid) != "":
		return false
	var b := _bank()
	var c := cost_of(bid)
	if not b.spend_gold(int(c.gold)):
		return false
	for it in c.items:
		b.remove(str(it), int(c.items[it]))
	var e := _entry(bid)
	e["level"] = int(e.level) + 1
	e["grade"] = grade_of(bid)
	if str(e.get("product", "")) == "" and _b_defs[bid].has("production"):
		e["product"] = product_of(bid)
	_sync_features()
	ctx.events.estate_changed.emit()
	return true


## Sale di `n` livelli (+1/+10); si ferma al primo ostacolo. Ritorna i livelli saliti.
func upgrade_many(bid: String, n: int) -> int:
	var done := 0
	for i in n:
		if not upgrade(bid):
			break
		done += 1
	return done


## "Max": sale finché si può (con un tetto di sicurezza). Ritorna i livelli saliti.
func upgrade_max(bid: String, safety: int = 2000) -> int:
	return upgrade_many(bid, safety)


## Costruita la Taverna si apre la Gilda. Il token è quello dei dati (ricompensa di main_c4_q2, docs/appendici/A5)
## e della voce di menù in ScreenRegistry: feature:mercenaries. Lo diamo già alla costruzione perché la missione
## chiede anche di reclutare un mercenario, cosa possibile solo a Gilda aperta.
## Controllato nel tick, non al caricamento: UnlockSystem ha il proprio stato agganciato dopo il nostro.
func _sync_features() -> void:
	if _guild_granted or level_of_type("guild") <= 0:
		return
	var u := ctx.get_system("unlock")
	if u != null and u.state is Array:
		u.grant(GUILD_TOKEN)
		_guild_granted = true


# ------------------------------------------------------------------ raccolta

## "Raccogli tutto": porta le unità intere del Magazzino al Deposito. Ritorna {item_id: qty}.
func collect_all() -> Dictionary:
	var out := {}
	var b := _bank()
	if b == null:
		return out
	for it in state.storage.keys():
		var n := int(floor(float(state.storage[it]) + 1e-7))
		if n <= 0:
			continue
		var added := int(b.add(str(it), n, "estate"))
		if added > 0:
			state.storage[it] = maxf(0.0, float(state.storage[it]) - added)
			out[it] = added
			state.stats["collected"] = float(state.stats.collected) + added
	_prune_storage()
	if not out.is_empty():
		ctx.events.estate_changed.emit()
	return out


## Il Deposito può rifiutare (pieno): con la raccolta automatica il Magazzino non supera comunque la sua capienza.
func _trim_storage() -> void:
	var cap := base_capacity()
	var tot := stored_total()
	if tot > cap and tot > 0.0:
		var f := cap / tot
		for it in state.storage.keys():
			state.storage[it] = float(state.storage[it]) * f
		_prune_storage()


func _prune_storage() -> void:
	for it in state.storage.keys():
		if float(state.storage[it]) <= TECH.eps:
			state.storage.erase(it)


# ------------------------------------------------------------------ Rifondazione

func prestige_min_units() -> float:
	return float(_k.prestige_min_units)


## Soci totali spettanti ai Punti Prosperità attuali.
## Soci, Rifondazione e Rete di Soci (`soci_gain_pct`) vivono SOLO in PrestigeSystem (audit 42, punto 4): qui ci sono
## letture e un inoltro, così la Tenuta e la Gilda non hanno un secondo contatore né una seconda fonte di bonus.
func _prestige() -> Variant:
	return ctx.get_system("prestige") if ctx != null else null


## Soci totali spettanti ai Punti Prosperità attuali (senza Rete di Soci).
func partners_total() -> int:
	return Formulas.soci_total(float(state.prosperity))


## Soci che darebbe una Rifondazione adesso (Rete di Soci compresa).
func partners_pending() -> int:
	var ps: Variant = _prestige()
	return int(ps.call("refound_gain")) if ps != null else 0


func can_refound() -> bool:
	var ps: Variant = _prestige()
	return ps != null and str(ps.call("can_refound")).is_empty()


## Suggerimento di docs/11 §4: conviene quando i Soci nuovi sono almeno il 50% di quelli posseduti.
func refound_advised() -> bool:
	return can_refound() and float(partners_pending()) >= 0.5 * float(maxi(1, partners()))


## Punto di ingresso unico: la Rifondazione è PrestigeSystem.do_refound() (Soci, bonus, eventi); la Tenuta azzera
## i propri edifici in reset_for_refounding(), che quello richiama.
func refound() -> bool:
	var ps: Variant = _prestige()
	return ps != null and not (ps.call("do_refound") as Dictionary).is_empty()


## Punti Prosperità a vita (letto da PrestigeSystem per il requisito della Rifondazione).
func lifetime_units() -> float:
	return float(state.prosperity)


## Azzeramento della Rifondazione: edifici a livello 0 (il Casolare a 1), gradi conservati, coloni e Magazzino vuoti.
## Non tocca Soci, Punti Prosperità né statistiche a vita.
func reset_for_refounding() -> void:
	for bid in state.buildings.keys():
		var e: Dictionary = state.buildings[bid]
		var keep_grade := int(e.get("grade", 0))
		e["level"] = 1 if type_of(bid) == "housing" else 0
		e["grade"] = keep_grade
	state.storage = {}
	state.settlers = 0
	state.settler_s = 0.0
	state.vault_s = 0.0
	state.sell_gold = 0.0
	ctx.events.estate_changed.emit()


# ------------------------------------------------------------------ simulazione

func tick(dt: float) -> void:
	_advance(dt)
	_finish_advance()
	_sync_features()


## Secondi dell'ultimo offline in cui il Magazzino pieno ha rifiutato la produzione (QA120: il Bentornato lo dice).
var _full_s: float = 0.0


func simulate_offline(seconds: float) -> Dictionary:
	if seconds <= 0.0 or total_levels() <= 0:
		return {}
	_full_s = 0.0
	var s0: Dictionary = {"prod": float(state.prosperity), "gold": float(state.stats.sold_gold),
		"crates": int(state.stats.crates), "events": int((state.events as Dictionary).count), "settlers": settlers()}
	_crate_log = {}
	_auto_drawn = 0.0
	_offline = true
	_advance(seconds)
	_finish_advance()
	_offline = false
	var rep := {}
	var rows: Array = []
	var produced := float(state.prosperity) - float(s0.prod)
	if produced >= 1.0:
		rows.append({"key": "UI_ESTATE_WB_PRODUCED", "params": {"n": NumberFormat.fmt(produced)}})
	var gold := float(state.stats.sold_gold) - float(s0.gold)
	if gold >= 1.0:
		rows.append({"key": "UI_ESTATE_WB_GOLD", "params": {"n": NumberFormat.fmt(gold)}})
	if settlers() > int(s0.settlers):
		rows.append({"key": "UI_ESTATE_WB_SETTLERS", "params": {"n": settlers() - int(s0.settlers)}})
	var evn := int((state.events as Dictionary).count) - int(s0.events)
	if evn > 0:
		rows.append({"key": "UI_ESTATE_WB_EVENTS", "params": {"n": evn}})
	if _full_s >= float(tuning().warehouse_full_report_s):
		# QA120: il Magazzino si e' riempito e la produzione si e' fermata: senza questa riga il giocatore AFK non sa perche' «solo» 4.000 unita'
		rows.append({"key": "UI_QA120_ESTATE_FULL", "params": {"time": NumberFormat.fmt_time(_full_s)}})
	if not rows.is_empty():
		rep["rows"] = rows
	if not _crate_log.is_empty():
		rep["crates"] = _crate_log.duplicate()
	if _auto_drawn >= 1.0:
		rows.append({"key": "UI_OFFL_ESTATE_AUTO", "params": {"n": NumberFormat.fmt(_auto_drawn)}})
		rep["rows"] = rows
	if settlers() > 0 and pantry() <= TECH.eps:
		var starve_pct := int(round((1.0 - float(_rules.settlers.starving_mult)) * 100.0))
		rep["stop"] = {"key": "UI_ESTATE_WB_PANTRY", "params": {"pct": starve_pct}}
	return rep


func _finish_advance() -> void:
	var g := float(state.sell_gold)
	if g >= 1.0:
		var b := _bank()
		if b != null:
			var whole := int(floor(g))
			b.add_gold(whole)
			state.sell_gold = g - whole
	if auto_collect() and not state.storage.is_empty():
		collect_all()
		_trim_storage()


## Piano di flusso con lo stato corrente: tutte le velocità sono in unità (o oro) all'ora.
func _plan() -> Dictionary:
	var eps := float(TECH.eps)
	var prod := {}                      # item -> unità/ora grezze
	for bid in _b_order:
		var u := units_per_hour(bid)
		if u > 0.0:
			var it := product_of(bid)
			prod[it] = float(prod.get(it, 0.0)) + u
	var cap := capacity()
	var total := stored_total()
	# Bottega: vende le merci "in vendita" dalla più preziosa; dal Magazzino finché c'è scorta, poi solo il prodotto che arriva
	var sell := {}
	var gold_rate := 0.0
	var b_units := shop_units_per_hour()
	var g_cap := shop_gold_cap_per_h()
	var sell_f := shop_sell_pct() / 100.0
	if b_units > 0.0:
		var items: Array = []
		for it in state.storage:
			if float(state.storage[it]) > eps and not items.has(it):
				items.append(it)
		for it in prod:
			if not items.has(it):
				items.append(it)
		items = items.filter(func(i: Variant) -> bool: return is_listed(str(i)))
		items.sort_custom(func(a: Variant, b: Variant) -> bool:
			var va := float(ctx.data.item(str(a)).get("value", 0))
			var vb := float(ctx.data.item(str(b)).get("value", 0))
			return va > vb if va != vb else str(a) < str(b))
		var b_left := b_units
		var g_left := g_cap
		for it in items:
			var v := maxf(0.01, float(ctx.data.item(str(it)).get("value", 1)) * sell_f)
			var room := minf(b_left, g_left / v)
			if room <= 0.0:
				break
			var from_stock := float(state.storage.get(it, 0.0)) > eps
			var s := room if from_stock else minf(room, float(prod.get(it, 0.0)))
			sell[it] = s
			b_left -= s
			g_left -= s * v
			gold_rate += s * v
	# produzione accettata: se il Magazzino è pieno entra solo quanto esce
	var accept := 1.0
	var sum_prod := 0.0
	for it in prod:
		sum_prod += float(prod[it])
	var full := total >= cap - 1e-6
	if full and sum_prod > 0.0:
		var sum_sell := 0.0
		for it in sell:
			sum_sell += float(sell[it])
		accept = clampf(sum_sell / sum_prod, 0.0, 1.0)
	var net := {}
	var net_total := 0.0
	for it in prod:
		net[it] = float(prod[it]) * accept
	for it in sell:
		net[it] = float(net.get(it, 0.0)) - float(sell[it])
	for it in net:
		net_total += float(net[it])
	return {"prod": prod, "accept": accept, "sell": sell, "net": net, "net_total": net_total, "gold_rate": gold_rate,
		"cap": cap, "total": total, "full": full, "sum_prod": sum_prod}


func _advance(dt: float) -> void:
	var left := dt
	var guard := 0
	while left > 1e-12:
		guard += 1
		_auto_stock()                       # no-op salvo Dispensa vuota con coloni (stesso codice per tick e offline)
		var plan := _plan()
		var seg := left
		if guard < int(TECH.max_segments):
			seg = minf(seg, _next_event_s(plan))
			seg = maxf(seg, float(TECH.min_segment_s))      # eventi entro 1 ms uniti: niente centinaia di segmenti minuscoli
			seg = minf(seg, left)
		_apply_segment(plan, seg)
		left -= seg
	_prune_storage()


## Secondi al prossimo evento che cambia le velocità (INF se nessuno).
func _next_event_s(plan: Dictionary) -> float:
	var eps := float(TECH.eps)
	var best := INF
	var use := ration_use_per_h()
	if use > 0.0 and pantry() > eps:
		best = minf(best, pantry() / use * 3600.0)
	if settlers() < settler_cap():
		best = minf(best, maxf(0.0, settler_arrival_s() - float(state.settler_s)))
	for it in plan.sell:
		if float(plan.sell[it]) > 0.0 and float(state.storage.get(it, 0.0)) > eps and float(plan.net.get(it, 0.0)) < 0.0:
			best = minf(best, float(state.storage[it]) / -float(plan.net[it]) * 3600.0)
	if not plan.full and float(plan.net_total) > 0.0 and plan.cap < INF:
		best = minf(best, (float(plan.cap) - float(plan.total)) / float(plan.net_total) * 3600.0)
	var vi := vault_interval_s()
	if vi < INF:
		best = minf(best, maxf(0.0, vi - float(state.vault_s)))
	best = minf(best, maxf(0.0, float((state.events as Dictionary).next_s)))
	return best


func _apply_segment(plan: Dictionary, seg: float) -> void:
	var h := seg / 3600.0
	state.t = float(state.t) + seg
	if _offline and bool(plan.full) and float(plan.sum_prod) > 0.0 and float(plan.accept) < 0.999:
		_full_s += seg
	var produced := 0.0
	for it in plan.net:
		var v := float(state.storage.get(it, 0.0)) + float(plan.net[it]) * h
		if v <= 1e-7:
			state.storage.erase(it)
		else:
			state.storage[it] = v
	for it in plan.prod:
		produced += float(plan.prod[it]) * float(plan.accept) * h
	if plan.cap < INF:
		# non superare la capienza per errori di arrotondamento
		var tot := stored_total()
		if tot > float(plan.cap) and tot - float(plan.cap) < 1e-3:
			var ex := tot - float(plan.cap)
			for it in state.storage:
				state.storage[it] = maxf(0.0, float(state.storage[it]) - ex)
				produced -= ex
				break
	state.prosperity = float(state.prosperity) + produced
	state.stats["produced"] = float(state.stats.produced) + produced
	var g := float(plan.gold_rate) * h
	if g > 0.0:
		state.sell_gold = float(state.sell_gold) + g
		state.stats["sold_gold"] = float(state.stats.sold_gold) + g
	var use := ration_use_per_h() * h
	state.pantry = maxf(0.0, float(state.pantry) - use)
	if float(state.pantry) < 1e-7:
		state.pantry = 0.0
	# coloni
	if settlers() < settler_cap():
		state.settler_s = float(state.settler_s) + seg
		while float(state.settler_s) >= settler_arrival_s() - 1e-6 and settlers() < settler_cap():
			state.settler_s = float(state.settler_s) - settler_arrival_s()
			state.settlers = settlers() + 1
	else:
		state.settler_s = 0.0
		if settlers() > settler_cap():
			state.settlers = settler_cap()
	# Caveau Privato
	var vi := vault_interval_s()
	if vi < INF:
		state.vault_s = float(state.vault_s) + seg
		while float(state.vault_s) >= vi - 1e-6:
			state.vault_s = float(state.vault_s) - vi
			_vault_crate()
	# eventi di colore
	var ev: Dictionary = state.events
	ev["next_s"] = float(ev.next_s) - seg
	if float(ev.next_s) <= 1e-6:
		_run_event(plan)
		_schedule_event()


# ------------------------------------------------------------------ Caveau Privato

func _zone_unlocked(zone_id: String) -> bool:
	var c := ctx.get_system("combat")
	if c != null and c.has_method("zone_unlocked"):
		return bool(c.zone_unlocked(zone_id))
	var z: Dictionary = ctx.data.get_def("zones", zone_id)
	return _unlocks().has("zone:" + zone_id) or z.get("unlock", {}).get("quest", "x") == null


func unlocked_crates() -> Array:
	var out: Array = []
	for z in ctx.data.table("zones"):
		if _zone_unlocked(str(z.id)) and str(z.get("crate", "")) != "":
			out.append(str(z.crate))
	return out


func _vault_crate() -> void:
	var pool := unlocked_crates()
	if pool.is_empty():
		return
	var crate_id := str(pool[ctx.rng.randi_range("crates", 0, pool.size() - 1)])
	var cs := ctx.get_system("crates")
	var b := _bank()
	if cs != null:
		cs.grant_crate(crate_id, 1)
	elif b != null:
		b.add(crate_id, 1, "estate")
	state.stats["crates"] = int(state.stats.crates) + 1
	_crate_log[crate_id] = int(_crate_log.get(crate_id, 0)) + 1
	if b != null and ctx.rng.chance("crates", float(tuning().vault_key_chance)):
		var key := str(ctx.data.item(crate_id).get("crate", {}).get("key", ""))
		if key != "":
			b.add(key, 1, "estate")


# ------------------------------------------------------------------ eventi di colore

## Il primo evento arriva dopo l'intervallo medio (senza estrarre: caricare una partita non sposta i flussi RNG condivisi);
## i successivi hanno ±variazione, estratta dal flusso "world".
func _schedule_event(first: bool = false) -> void:
	var base := float(tuning().event_interval_min) * 60.0
	var v := float(tuning().event_interval_var)
	(state.events as Dictionary)["next_s"] = base if first else base * ctx.rng.randf_range("world", 1.0 - v, 1.0 + v)


func _run_event(plan: Dictionary) -> void:
	if total_levels() <= 0:
		return
	var w: Array = []
	for e in EVENTS:
		w.append(e.w)
	var e: Dictionary = EVENTS[maxi(0, ctx.rng.weighted_index("world", w))]
	match str(e.effect):
		"gold":
			var g := float(plan.gold_rate) / 60.0 * float(tuning().event_gold_minutes)
			if g >= 1.0:
				state.sell_gold = float(state.sell_gold) + g
		"pantry_plus":
			state.pantry = float(state.pantry) + ration_use_per_h() * float(tuning().event_pantry_hours)
		"pantry_minus":
			state.pantry = maxf(0.0, float(state.pantry) - ration_use_per_h() * float(tuning().event_pantry_hours))
	var ev: Dictionary = state.events
	ev["count"] = int(ev.count) + 1
	var lg: Array = ev.log
	lg.append({"id": str(e.id), "t": float(state.t)})
	while lg.size() > int(tuning().event_log_max):
		lg.remove_at(0)
	if not _offline:
		ctx.events.notice.emit("info", tr("UI_ESTATE_EV_" + str(e.id).to_upper()), {"estate_event": str(e.id)})


func event_log() -> Array:
	return (state.events as Dictionary).log
