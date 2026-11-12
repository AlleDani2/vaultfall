class_name AssistSystem
extends GameSystem
## Comodità di gioco (UI-A): regole di vendita automatica del Deposito (G14) e avviso «boss mondiale tra 5 minuti» (G19).
## Offline, nessuna rete. Stato `assist`: {"rules": [filtro SellRules + "on"], "auto_on": bool, "wb_slot": int}.
##
## Vendita automatica: sbloccata dal nodo di Costellazione «Vendita Automatica» (modificatore `auto_sell_unlock`) e dal
## Mercato. Ogni SCAN_S secondi di gioco (e una volta al rientro offline) applica le regole attive con SellRules: mai
## oggetti bloccati, indossati, unici o non commerciabili. Avviso del boss: legge EndgameCombat (`combat.eg.wb_next()`)
## senza modificarlo e manda UNA notifica per finestra quando mancano WB_WARN_S secondi (sono scelte di presentazione).

const SCAN_S := 10.0
const WB_WARN_S := 300.0
const MAX_RULES := 6
const MARKET_TOKEN := "feature:market"

var _acc: float = 0.0
var _wb_acc: float = 0.0


func _init() -> void:
	id = "assist"
	state_key = "assist"


func default_state() -> Variant:
	return _fresh()


static func _fresh() -> Dictionary:
	return {"rules": [], "auto_on": true, "wb_slot": -1, "auto_dupes": false}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["wb_slot"])


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	var clean_rules: Array = []
	for r in state.rules:
		if r is Dictionary:
			var c := SellRules.clean(r)
			c["on"] = bool(r.get("on", true))
			clean_rules.append(c)
	state.rules = clean_rules.slice(0, MAX_RULES)
	_acc = 0.0
	_wb_acc = 0.0


# ------------------------------------------------------------------ vendita automatica

func auto_sell_unlocked() -> bool:
	return ctx.modifiers.total_add("auto_sell_unlock") >= 1.0 and (ctx.state.get("unlocks", []) as Array).has(MARKET_TOKEN)


func rules() -> Array:
	return state.rules


func is_auto_on() -> bool:
	return bool(state.auto_on)


func set_auto_on(on: bool) -> void:
	state.auto_on = on


## Vendita automatica dei doppioni (equipaggiamento e attrezzi uguali oltre il primo): un interruttore, non una regola.
func is_auto_dupes() -> bool:
	return bool(state.get("auto_dupes", false))


func set_auto_dupes(on: bool) -> void:
	state["auto_dupes"] = on


## La regola consigliata dal Carro di Ritiro (Finiture in eccesso, dati: bank.recommended_sell_rule) è già attiva?
func recommended_active() -> bool:
	var bank := ctx.get_system("bank") as BankSystem
	if bank == null or not bool(state.auto_on):
		return false
	var f := bank.recommended_sell_rule()
	if f.is_empty():
		return false
	var want := SellRules.describe(f)
	for r in state.rules:
		if bool(r.get("on", true)) and SellRules.describe(r) == want:
			return true
	return false


## «Vendita automatica» a un clic (Carro di Ritiro, resoconto 117): accende l'interruttore generale e i doppioni e aggiunge la
## regola consigliata delle Finiture in eccesso (mai bloccate, indossate, uniche, Reliquie né Annaliste). false se la funzione
## non è sbloccata (nodo di Costellazione + Mercato) o non c'è posto per la regola.
func enable_recommended() -> bool:
	if not auto_sell_unlocked():
		return false
	var bank := ctx.get_system("bank") as BankSystem
	var f: Dictionary = bank.recommended_sell_rule() if bank != null else {}
	if f.is_empty():
		return false
	state.auto_on = true
	set_auto_dupes(true)
	if not recommended_active():
		add_rule(f)
	if not recommended_active():
		return false
	run_auto_sell()
	return true


## Aggiunge una regola (filtro SellRules). false se i posti sono finiti, se la funzione non è sbloccata o se esiste già.
func add_rule(f: Dictionary) -> bool:
	if not auto_sell_unlocked() or (state.rules as Array).size() >= MAX_RULES:
		return false
	var c := SellRules.clean(f)
	for r in state.rules:
		if SellRules.describe(r) == SellRules.describe(c):
			return false
	c["on"] = true
	(state.rules as Array).append(c)
	return true


func remove_rule(index: int) -> void:
	if index >= 0 and index < (state.rules as Array).size():
		(state.rules as Array).remove_at(index)


func set_rule_on(index: int, on: bool) -> void:
	if index >= 0 and index < (state.rules as Array).size():
		state.rules[index]["on"] = on


## Applica ora tutte le regole attive. Ritorna l'oro incassato.
func run_auto_sell() -> int:
	if not auto_sell_unlocked() or not bool(state.auto_on) or ((state.rules as Array).is_empty() and not is_auto_dupes()):
		return 0
	var bank := ctx.get_system("bank") as BankSystem
	var market := ctx.get_system("market") as MarketSystem
	if bank == null or market == null:
		return 0
	var gold := 0
	var pieces := 0
	if is_auto_dupes():
		var dp := SellRules.collect_dupes(bank, market, true)
		if int(dp.pieces) > 0:
			gold += SellRules.execute_dupes(bank, market, dp)
			pieces += int(dp.pieces)
	for r in state.rules:
		if not bool(r.get("on", true)):
			continue
		var plan := SellRules.collect(bank, market, r)
		if int(plan.pieces) <= 0:
			continue
		var g := SellRules.execute(market, plan)
		gold += g
		pieces += int(plan.pieces)
	if pieces > 0:
		ctx.events.notice.emit("success", Loc.tf("UI_UIA_AUTOSOLD", {"n": pieces, "gold": NumberFormat.fmt(gold)}), {"category": "loot"})
	return gold


# ------------------------------------------------------------------ boss mondiale

## true se la finestra del prossimo boss si apre entro WB_WARN_S e non è già stata annunciata. Segna lo slot come annunciato.
func check_world_boss_soon() -> bool:
	var cb: Variant = ctx.get_system("combat")
	if cb == null or cb.get("eg") == null:
		return false
	var eg: Variant = cb.get("eg")
	if not bool(eg.call("wb_unlocked")):
		return false
	var nxt: Dictionary = eg.call("wb_next")
	if nxt.is_empty() or float(nxt.in_s) > WB_WARN_S or int(nxt.slot) == int(state.wb_slot):
		return false
	state["wb_slot"] = int(nxt.slot)
	ctx.events.notice.emit("info", Loc.tf("UI_WORLD_BOSS_SOON", {}), {"category": "boss", "digest": "boss_soon"})
	return true


# ------------------------------------------------------------------ ciclo

func tick(dt: float) -> void:
	if state == null:
		return
	_acc += dt
	if _acc >= SCAN_S:
		_acc = 0.0
		run_auto_sell()
	_wb_acc += dt
	if _wb_acc >= 5.0:
		_wb_acc = 0.0
		check_world_boss_soon()


## Offline: una sola passata di vendita al rientro (le regole valgono per ciò che è arrivato nel Deposito).
func simulate_offline(_seconds: float) -> Dictionary:
	if state == null:
		return {}
	run_auto_sell()
	return {}
