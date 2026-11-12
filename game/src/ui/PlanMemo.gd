class_name PlanMemo
extends RefCounted
## Anteprime di vendita del Deposito (doppioni, Finiture in eccesso) con memoria breve.
##
## Costruirle scorre tutto il Deposito (istanze e pile), e il Deposito, il pannello del Carro e la Sala dei Caveau le chiedevano
## a ogni aggiornamento a 10 Hz o 2 Hz (resoconto docs/audit_2026-10-22/122): ora si ricalcolano solo se il Deposito
## (`revision`), ciò che è indossato/assegnato, lo sblocco del Mercato o la regola consigliata sono cambiati, oppure ogni
## MAX_AGE_MS (il prezzo di anteprima segue la domanda del Mercato, che cambia col tempo). Il clic su «Vendi» ricalcola sempre
## il piano da capo (`fresh = true`): la memoria serve solo all'anteprima. Chiave per istanza di Deposito: una nuova partita
## ha un Deposito nuovo e quindi una memoria nuova.

const MAX_AGE_MS := 4000

static var _memo: Dictionary = {}


static func dupes(bank: BankSystem, market: MarketSystem, market_open: bool, fresh: bool = false) -> Dictionary:
	if bank == null:
		return SellRules.collect_dupes(bank, market, market_open)
	return _memoized(bank, "dupes", "%s" % market_open, fresh,
		func() -> Dictionary: return SellRules.collect_dupes(bank, market, market_open))


static func rule(bank: BankSystem, market: MarketSystem, market_open: bool, filter: Dictionary, fresh: bool = false) -> Dictionary:
	if bank == null:
		return SellRules.collect(bank, market, filter)
	return _memoized(bank, "rule", "%s|%s" % [market_open, JSON.stringify(filter)], fresh,
		func() -> Dictionary: return SellRules.collect(bank, market, filter))


static func _memoized(bank: BankSystem, kind: String, extra: String, fresh: bool, make: Callable) -> Dictionary:
	var id := bank.get_instance_id()
	var key := "%s|%d|%s|%s" % [kind, bank.revision, extra, str(bank.in_use_set().keys())]
	var now := Time.get_ticks_msec()
	var slot: Dictionary = _memo.get(id, {})
	var hit: Variant = slot.get(kind)
	if not fresh and hit != null and hit.key == key and now - int(hit.t) < MAX_AGE_MS:
		return hit.plan
	var plan: Dictionary = make.call()
	slot[kind] = {"key": key, "t": now, "plan": plan}
	_memo[id] = slot
	if _memo.size() > 8:                                  # partite aperte e chiuse nei test: non cresce senza fine
		for k in _memo.keys():
			if k != id:
				_memo.erase(k)
				break
	return plan
