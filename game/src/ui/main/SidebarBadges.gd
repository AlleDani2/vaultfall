class_name SidebarBadges
extends RefCounted
## Badge numerici della barra laterale (G22, docs/16 §2): quante cose aspettano il giocatore dietro ogni voce del menù.
## Funzione pura di lettura: `counts()` ritorna {id voce: quantità > 0}; MainScreen disegna i pallini a 2 Hz.
##   vault_hall  casse che si possono aprire adesso (con chiave/costo disponibili)
##   quests      missioni completabili (ricompensa da riscattare) + passi di scoperta mai aperti (QuestGuide)
##   skill:farming  raccolti pronti nell'orto/frutteto
##   orders      Commesse che si possono consegnare adesso (oggetti nel Deposito)
##   events      ricompense di Eventi stagionali da riscattare
##   skill:<id>  talenti da scegliere (livelli della mansione con la scelta aperta); Eroe e Taglie: voci «hero» e «bounty»
##   guild       spedizioni concluse non esistono (si chiudono da sole): nessun badge, vedi ParallelsPanel
## Nessun numero di bilanciamento: tutto viene dai sistemi.

const MAX_SHOWN := 9          # tetto del numero nel menù (D14): «9+»


static func counts() -> Dictionary:
	var out: Dictionary = {}
	if not GameState.active:
		return out
	_put(out, "vault_hall", _crates())
	var q := Game.system("quests") as QuestSystem
	if q != null:
		_put(out, "quests", q.ready_count() + QuestGuide.discoveries(q).size())      # da riscattare + passi di scoperta nuovi
	var f := Game.system("farming") as FarmingSystem
	if f != null:
		_put(out, "skill:farming", f.ready_count())
	_put(out, "orders", _orders())
	var ev := Game.system("seasonal") as SeasonalEventSystem
	if ev != null and ev.events_enabled():
		_put(out, "events", ev.claimable().size())
	var perks := perk_counts()
	for id in perks:
		_put(out, id, int(out.get(id, 0)) + int(perks[id]))
	return out


## Talenti di mansione da scegliere, per id di voce di menù ({id voce: n > 0}). Conta SOLO le mansioni la cui schermata si può
## aprire dal menù e che mostra il pannello dei talenti (SkillPerkPanel): niente pallino senza una scelta dietro (rapporto 116).
static func perk_counts() -> Dictionary:
	var out: Dictionary = {}
	var sk := Game.system("skills") as SkillSystem
	if sk == null or not GameState.active:
		return out
	var unlocks: Array = GameState.data.get("unlocks", [])
	for s in DataRegistry.table("skills"):
		var sid := str(s.id)
		var n := sk.pending_perk_tiers(sid).size()
		if n <= 0 or not sk.is_unlocked(sid):
			continue
		var menu_id := ScreenRegistry.menu_id_for_skill(sid)
		if ScreenRegistry.is_available(ScreenRegistry.get_entry(menu_id), unlocks):
			out[menu_id] = int(out.get(menu_id, 0)) + n
	return out


static func _put(out: Dictionary, id: String, n: int) -> void:
	if n > 0:
		out[id] = n
	elif out.has(id) and int(out[id]) <= 0:
		out.erase(id)


static func _crates() -> int:
	var cs := Game.system("crates") as CrateSystem
	if cs == null:
		return 0
	var n := 0
	for it in DataRegistry.items_by_category("crate"):
		if cs.is_crate(str(it.id)):
			n += cs.openable(str(it.id))
	return n


static func _orders() -> int:
	var mk := Game.system("market") as MarketSystem
	var bank := Game.system("bank") as BankSystem
	if mk == null or bank == null or not mk.orders_enabled():
		return 0
	var n := 0
	for o in mk.orders():
		if bank.has(str(o.item), int(o.qty)):
			n += 1
	return n


## Testo del pallino («9+» oltre il massimo).
static func label(n: int) -> String:
	return "%d+" % MAX_SHOWN if n > MAX_SHOWN else str(n)


# ------------------------------------------------------------------ segnali del menù (F4, D14): tre tipi, tetti di interfaccia

## Costanti di INTERFACCIA (non di bilanciamento): quanti numeri e puntini al massimo nel menù, insieme.
const MAX_NUMBERS := 5
const MAX_DOTS := 5

const KIND_COUNT := "count"       # numero ambra: un'azione che si può fare adesso
const KIND_DOT := "dot"           # puntino: novità non urgente
const KIND_DANGER := "danger"     # rosso con «!»: pericolo o perdita in corso

## Priorità dei numeri (la più alta per prima): Missioni > Casse > raccolti > Commesse > Eventi. Chiave tooltip di ogni causa.
const NUMBER_ORDER: PackedStringArray = ["quests", "vault_hall", "skill:farming", "orders", "events"]
const CAUSE_KEYS := {"quests": "UI_UIB_BADGE_QUESTS", "vault_hall": "UI_UIB_BADGE_CRATES", "skill:farming": "UI_UIB_BADGE_FARM",
	"orders": "UI_UIB_BADGE_ORDERS", "events": "UI_UIB_BADGE_EVENTS"}
const CAUSE_PERKS := "UI_UIB_BADGE_PERKS"
const CAUSE_DISCOVERY := "UI_SIDE_DISCOVERY"
const CAUSE_NEW_ENTRY := "UI_SIDE_NEW_ENTRY"
const CAUSE_DANGER_BANK := "UI_SIDE_DANGER_BANK"
const CAUSE_DANGER_PANTRY := "UI_SIDE_DANGER_PANTRY"
const CAUSE_DANGER_FOOD := "UI_SIDE_DANGER_FOOD"


## I segnali del menù: {id voce: {"kind": count|dot|danger, "n": int, "causes": [[chiave tooltip, n], …]}}. Funzione pura di lettura.
## `opts`: "recent" = id delle voci mansione mostrate nelle Recenti (solo per loro si segnalano i talenti da scegliere; le voci
## che non sono mansioni, come Eroe e Taglie, segnalano sempre) · "new_ids" = id delle voci sbloccate e mai aperte (già filtrate
## dal menù). `counts()` resta com'era (somma grezza per voce) per i test e per chi la usa.
static func signals(opts: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	if not GameState.active:
		return out
	var recent: Array = opts.get("recent", [])
	# 1) numeri ambra, in ordine di priorità; oltre il quinto diventano puntino
	var picked := pick_numbers(_number_sources())
	for id in picked.numbers:
		out[id] = {"kind": KIND_COUNT, "n": int(picked.numbers[id]), "causes": [[CAUSE_KEYS[id], int(picked.numbers[id])]]}
	# 2) puntini
	var dots := 0
	for id in picked.overflow:
		if dots < MAX_DOTS:
			out[id] = {"kind": KIND_DOT, "n": 0, "causes": [[CAUSE_KEYS[id], int(picked.overflow[id])]]}
			dots += 1
	var q := Game.system("quests") as QuestSystem
	var disc := QuestGuide.discoveries(q).size() if q != null else 0
	if disc > 0:
		dots = _add_dot(out, "quests", [CAUSE_DISCOVERY, disc], dots)
	var perks := perk_counts()
	for id in perks:
		if str(id).begins_with("skill:") and not recent.has(id):
			continue                   # talenti: puntino solo per le mansioni nelle Recenti
		dots = _add_dot(out, str(id), [CAUSE_PERKS, int(perks[id])], dots)
	for id in opts.get("new_ids", []):
		dots = _add_dot(out, str(id), [CAUSE_NEW_ENTRY, 1], dots)
	# 3) pericolo (sostituisce ogni altro segnale della stessa voce: il rosso è l'unico che non si deve perdere)
	for d in _dangers():
		var causes: Array = [d.cause]
		causes.append_array((out.get(d.id, {}) as Dictionary).get("causes", []))
		out[d.id] = {"kind": KIND_DANGER, "n": 0, "causes": causes}
	return out


## Sceglie quali voci mostrano il numero: al massimo `max_numbers`, per priorità (`order`, la più alta per prima); le altre
## passano a puntino. Ritorna {"numbers": {id: n}, "overflow": {id: n}}. Pura (i test la chiamano con fonti inventate).
static func pick_numbers(raw: Dictionary, order: Array = NUMBER_ORDER, max_numbers: int = MAX_NUMBERS) -> Dictionary:
	var numbers: Dictionary = {}
	var overflow: Dictionary = {}
	for id in order:
		var n := int(raw.get(id, 0))
		if n <= 0:
			continue
		if numbers.size() < max_numbers:
			numbers[id] = n
		else:
			overflow[id] = n
	return {"numbers": numbers, "overflow": overflow}


## Aggiunge un puntino (o una causa in più a un segnale già presente). Ritorna il numero di puntini usati.
static func _add_dot(out: Dictionary, id: String, cause: Array, dots: int) -> int:
	if out.has(id):
		(out[id].causes as Array).append(cause)
		return dots
	if dots >= MAX_DOTS:
		return dots
	out[id] = {"kind": KIND_DOT, "n": 0, "causes": [cause]}
	return dots + 1


## Quantità «da fare adesso» per voce (solo i cinque numeri della D14).
static func _number_sources() -> Dictionary:
	var out: Dictionary = {}
	var q := Game.system("quests") as QuestSystem
	if q != null:
		out["quests"] = q.ready_count()
	out["vault_hall"] = _crates()
	var f := Game.system("farming") as FarmingSystem
	if f != null:
		out["skill:farming"] = f.ready_count()
	out["orders"] = _orders()
	var ev := Game.system("seasonal") as SeasonalEventSystem
	if ev != null and ev.events_enabled():
		out["events"] = ev.claimable().size()
	return out


## Pericoli in corso: [{id, cause}]. Deposito pieno · Dispensa vuota (con coloni) · cibo finito in un combattimento a rischio.
static func _dangers() -> Array:
	var out: Array = []
	var bank := Game.system("bank") as BankSystem
	if bank != null and bank.is_full():
		out.append({"id": "bank", "cause": [CAUSE_DANGER_BANK, 1]})
	var es := Game.system("estate") as EstateSystem
	if es != null and (GameState.data.get("unlocks", []) as Array).has("feature:estate") and es.settlers() > 0 and es.pantry() <= 0.0:
		out.append({"id": "estate", "cause": [CAUSE_DANGER_PANTRY, 1]})
	var cb := Game.system("combat") as CombatSystem
	if cb != null and cb.in_combat() and not cb.in_dungeon() and cb.food_available() <= 0 and not cb.trial_food_blocked():
		if str(CloseGuard.combat_status().get("level", "")) == "red":
			out.append({"id": "combat", "cause": [CAUSE_DANGER_FOOD, 1]})
	return out
