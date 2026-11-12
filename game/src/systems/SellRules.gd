class_name SellRules
extends RefCounted
## Filtri di vendita del Deposito (UI-A, G14): la stessa descrizione serve alla vendita multipla a mano (con anteprima)
## e alle regole di vendita automatica (AssistSystem, sbloccate dal nodo di Costellazione «auto_sell_unlock»).
## Classe pura: nessun nodo, nessuno stato. Non vende MAI oggetti bloccati, in uso (indossati / nel Guardaroba /
## nel Reliquiario), unici, oggetti-missione o non commerciabili: sono esclusi già in raccolta e contati a parte.
##
## Filtro: {"cat": categoria dei dati, "max_tier": int (0 = qualsiasi), "max_quality": id qualità o "" (qualsiasi),
##          "max_rarity": id rarità o "" (qualsiasi), "keep_special": bool (opzionale: non prende le Finiture Annalista)}. «max» = fino a quel livello compreso: gli oggetti senza
## rarità contano come «comune».

## Categorie offerte dalla UI (scelta di interfaccia, non un numero di bilanciamento).
const CATEGORIES: PackedStringArray = ["equipment", "tool", "material", "food", "potion", "ammo", "seed", "glyph", "skin"]
const RARITIES: PackedStringArray = ["common", "rare", "epic", "legendary", "mythic", "relic"]


static func new_filter(cat: String = "equipment") -> Dictionary:
	return {"cat": cat, "max_tier": 0, "max_quality": "", "max_rarity": ""}


## Filtro ripulito (tipi giusti, categoria ammessa). Un filtro con categoria non ammessa diventa quello di equipaggiamento.
static func clean(f: Dictionary) -> Dictionary:
	var cat := str(f.get("cat", ""))
	if not CATEGORIES.has(cat):
		cat = "equipment"
	var q := str(f.get("max_quality", ""))
	var r := str(f.get("max_rarity", ""))
	var out := {"cat": cat, "max_tier": maxi(0, int(f.get("max_tier", 0))), "max_quality": q,
		"max_rarity": r if RARITIES.has(r) else ""}
	if bool(f.get("keep_special", false)):
		out["keep_special"] = true
	return out


static func quality_ids() -> Array:
	var out: Array = []
	for q in DataRegistry.constants.get("quality", []):
		out.append(str(q.id))
	return out


## Gli oggetti che la categoria ha in comune con questo filtro hanno qualità/rarità? (per nascondere i campi inutili)
static func cat_has_quality(cat: String) -> bool:
	return cat == "equipment"


static func cat_has_rarity(cat: String) -> bool:
	return cat == "skin"


static func matches(def: Dictionary, inst: Dictionary, f: Dictionary) -> bool:
	if def.is_empty() or str(def.get("category", "")) != str(f.get("cat", "")):
		return false
	if bool(def.get("unique", false)) or not bool(def.get("tradeable", true)) or float(def.get("value", 0)) <= 0.0:
		return false
	if bool(f.get("keep_special", false)) and bool(inst.get("annalist", false)):
		return false               # Finitura Annalista: resta al giocatore (regola consigliata del Carro, resoconto 117)
	var mt := int(f.get("max_tier", 0))
	if mt > 0 and int(def.get("tier", 0)) > mt:
		return false
	var mq := str(f.get("max_quality", ""))
	if mq != "" and not inst.is_empty():
		var qs := quality_ids()
		var have := qs.find(str(inst.get("quality", "normal")))
		var lim := qs.find(mq)
		if lim >= 0 and have > lim:
			return false
	var mr := str(f.get("max_rarity", ""))
	if mr != "":
		var rar := str(inst.get("rarity", def.get("rarity", "common"))) if not inst.is_empty() else str(def.get("rarity", "common"))
		if RARITIES.find(rar if RARITIES.has(rar) else "common") > RARITIES.find(mr):
			return false
	return true


## Cosa si venderebbe ora con il filtro `f`:
## {"stacks": [{id, qty}], "uids": [uid], "pieces": n, "gold": anteprima, "locked": n, "in_use": n, "groups": [{id, qty}]}
## `locked` e `in_use` sono i pezzi che il filtro avrebbe preso ma restano al sicuro.
static func collect(bank: BankSystem, market: MarketSystem, f: Dictionary) -> Dictionary:
	var plan := {"stacks": [], "uids": [], "pieces": 0, "gold": 0, "locked": 0, "in_use": 0, "groups": []}
	if bank == null:
		return plan
	var flt := clean(f)
	for def_id in bank.state.stacks:
		var def: Dictionary = DataRegistry.item(str(def_id))
		if not matches(def, {}, flt):
			continue
		if bank.is_def_locked(str(def_id)):
			plan.locked += int(bank.state.stacks[def_id])
			continue
		var q := int(bank.state.stacks[def_id])
		if bank.is_def_in_use(str(def_id)):          # cibo negli slot dell'eroe: salvo, come le istanze indossate
			plan.in_use += q
			continue
		plan.stacks.append({"id": str(def_id), "qty": q})
		plan.pieces += q
	var per_def: Dictionary = {}
	for inst in bank.state.instances:
		var def2: Dictionary = DataRegistry.item(str(inst.def))
		if not matches(def2, inst, flt):
			continue
		if bool(inst.get("locked", false)):
			plan.locked += 1
			continue
		if bank.is_in_use(str(inst.uid)):
			plan.in_use += 1
			continue
		plan.uids.append(str(inst.uid))
		plan.pieces += 1
		per_def[str(inst.def)] = int(per_def.get(str(inst.def), 0)) + 1
	var groups: Array = (plan.stacks as Array).duplicate(true)
	for d in per_def:
		groups.append({"id": d, "qty": per_def[d]})
	plan.groups = groups
	plan.gold = market.quote_many(groups) if market != null else 0
	return plan


## UNICO punto di verità di «questa voce si può vendere a mano?» (F17: selezione e modalità vendita del Deposito, «Vendita
## rapida» del dettaglio). Ritorna "" se sì, altrimenti la chiave del motivo (bilingue). `uid` = "" per le pile.
## Mai vendibili: valute, oggetti-missione, non commerciabili o senza valore, unici, Reliquie, Finiture Annalista, bloccati,
## indossati / nel Guardaroba / nel Reliquiario, il cibo negli slot dell'Eroe; e nulla senza il Mercato sbloccato.
static func block_reason(bank: BankSystem, market: MarketSystem, def_id: String, uid: String, market_open: bool) -> String:
	if bank == null:
		return "UI_BANK_SELL_NEEDS_MARKET"
	var def: Dictionary = DataRegistry.item(def_id)
	var cat := str(def.get("category", ""))
	if def.is_empty() or bank.is_currency(def_id) or cat == "quest" or not bool(def.get("tradeable", true)) \
			or float(def.get("value", 0)) <= 0.0:
		return "UI_GUILD2_BANK_NOT_TRADEABLE"
	if bool(def.get("unique", false)) or cat == "relic":
		return "UI_BANKG_SELL_SPECIAL"
	var inst: Dictionary = bank.get_instance(uid) if uid != "" else {}
	if uid != "" and inst.is_empty():
		return "UI_GUILD2_BANK_NOT_TRADEABLE"
	if bool(inst.get("annalist", false)):
		return "UI_BANKG_SELL_SPECIAL"
	if not market_open or market == null:
		return "UI_BANK_SELL_NEEDS_MARKET_USE" if bank.is_recyclable(def_id) else "UI_BANK_SELL_NEEDS_MARKET"
	if (uid != "" and bool(inst.get("locked", false))) or (uid == "" and bank.is_def_locked(def_id)):
		return "UI_BANK_SELL_LOCKED_ITEM"
	if (uid != "" and bank.is_in_use(uid)) or (uid == "" and bank.is_def_in_use(def_id)):
		return "UI_BANK_SELL_IN_USE"
	if uid == "" and bank.sellable_count(def_id) <= 0:
		return "UI_GUILD2_BANK_NOT_TRADEABLE"
	return ""


## Piano di vendita di una SELEZIONE a mano (F17): `picks` = [{def, uid, qty}] (qty per le pile; le istanze valgono 1).
## Stessa forma di collect() (stacks, uids, pieces, gold, groups) più `skipped` (voci tolte perché block_reason non è vuoto)
## e `warn` (avvisi: "quality" Capolavoro/Eccellente, "ranked" pezzi con grado o incastri). L'oro è quello del Mercato
## (quote_many), quindi l'anteprima coincide con l'esito di execute().
static func collect_picks(bank: BankSystem, market: MarketSystem, picks: Array, market_open: bool) -> Dictionary:
	var plan := {"stacks": [], "uids": [], "pieces": 0, "gold": 0, "locked": 0, "in_use": 0, "groups": [], "skipped": 0,
		"warn": {}}
	if bank == null:
		return plan
	var per_def: Dictionary = {}
	var qs := quality_ids()
	var hi_q := qs.size() - 2                          # le ultime due qualità (Eccellente, Capolavoro) meritano un avviso
	for p in picks:
		var def_id := str(p.get("def", ""))
		var uid := str(p.get("uid", ""))
		if block_reason(bank, market, def_id, uid, market_open) != "":
			plan.skipped += 1
			continue
		if uid == "":
			var q := clampi(int(p.get("qty", 0)), 0, bank.sellable_count(def_id))
			if q <= 0:
				continue
			plan.stacks.append({"id": def_id, "qty": q})
			plan.pieces += q
		else:
			var inst := bank.get_instance(uid)
			plan.uids.append(uid)
			plan.pieces += 1
			per_def[def_id] = int(per_def.get(def_id, 0)) + 1
			if hi_q >= 1 and qs.find(str(inst.get("quality", ""))) >= hi_q:
				plan.warn["quality"] = int(plan.warn.get("quality", 0)) + 1
			var socketed := false
			for sk in inst.get("sockets", []):
				socketed = socketed or (sk != null and str(sk) != "")
			if int(inst.get("rank", 0)) > 0 or socketed:
				plan.warn["ranked"] = int(plan.warn.get("ranked", 0)) + 1
	var groups: Array = (plan.stacks as Array).duplicate(true)
	for d in per_def:
		groups.append({"id": d, "qty": per_def[d]})
	plan.groups = groups
	plan.gold = market.quote_many(groups) if market != null else 0
	return plan


## Esegue il piano calcolato da collect(). Ritorna l'oro ottenuto.
static func execute(market: MarketSystem, plan: Dictionary) -> int:
	if market == null:
		return 0
	var gold := 0
	if not (plan.stacks as Array).is_empty():
		gold += market.sell_many(plan.stacks)
	if not (plan.uids as Array).is_empty():
		gold += market.sell_instances(plan.uids)
	return gold


## Testo breve di un filtro per la lista delle regole («Equipaggiamento · fino al tier 2 · fino a Fine»).
static func describe(f: Dictionary) -> String:
	var flt := clean(f)
	var parts := PackedStringArray([TranslationServer.translate("UI_UIA_CAT_" + str(flt.cat).to_upper())])
	if int(flt.max_tier) > 0:
		parts.append(Loc.tf("UI_UIA_RULE_TIER", {"t": int(flt.max_tier)}))
	if str(flt.max_quality) != "":
		parts.append(Loc.tf("UI_UIA_RULE_QUALITY", {"q": TranslationServer.translate("UI_BANK_Q_" + str(flt.max_quality).to_upper())}))
	if str(flt.max_rarity) != "":
		parts.append(Loc.tf("UI_UIA_RULE_RARITY", {"r": TranslationServer.translate("UI_UIA_RAR_" + str(flt.max_rarity).to_upper())}))
	return " · ".join(parts)


## «Vendi i doppioni» (feedback giocatore 23/10/2026): i pezzi di equipaggiamento e gli attrezzi uguali oltre il primo
## (il primo è quello in uso, bloccato o di qualità migliore). Gli attrezzi si riciclano in oro (non serve il Mercato);
## l'equipaggiamento si vende al Mercato (se è sbloccato e lo compra).
## Piano: {"recycle": [uid], "sell": [uid], "pieces": n, "gold": anteprima, "skipped": n (pezzi senza Mercato o non vendibili)}
static func collect_dupes(bank: BankSystem, market: MarketSystem, market_open: bool) -> Dictionary:
	var plan := {"recycle": [], "sell": [], "pieces": 0, "gold": 0, "skipped": 0}
	if bank == null:
		return plan
	var per_def: Dictionary = {}
	for u in bank.duplicate_uids():
		var inst: Dictionary = bank.get_instance(str(u))
		var def_id := str(inst.get("def", ""))
		if bank.is_recyclable(def_id):
			(plan.recycle as Array).append(str(u))
			plan.gold += bank.recycle_value(def_id)
			plan.pieces += 1
		elif market != null and market_open and market.is_tradeable(def_id):
			(plan.sell as Array).append(str(u))
			per_def[def_id] = int(per_def.get(def_id, 0)) + 1
			plan.pieces += 1
		else:
			plan.skipped += 1
	var groups: Array = []
	for d in per_def:
		groups.append({"id": d, "qty": per_def[d]})
	if market != null and not groups.is_empty():
		plan.gold += market.quote_many(groups)
	return plan


## Esegue il piano di collect_dupes(). Ritorna l'oro ottenuto.
static func execute_dupes(bank: BankSystem, market: MarketSystem, plan: Dictionary) -> int:
	var gold := 0
	if bank != null and not (plan.recycle as Array).is_empty():
		gold += bank.recycle_instances(plan.recycle)
	if market != null and not (plan.sell as Array).is_empty():
		gold += market.sell_instances(plan.sell)
	return gold
