class_name NoticeFilter
extends RefCounted
## Notifiche disattivabili per categoria (docs/16 §7, UI-A G19). Classe pura: decide se un messaggio dell'EventBus va
## mostrato in base alle impostazioni `notify_<categoria>`. Gli avvisi importanti (warning, errori, Deposito pieno)
## non si spengono mai. Usata da LogDigest.absorb (che MainScreen interroga per primo) e dai livelli di mansione.

## Categorie spegnibili, nell'ordine in cui compaiono nelle Impostazioni.
const CATEGORIES: PackedStringArray = ["loot", "progress", "achievements", "levels", "events", "boss", "info"]


static func key_of(category: String) -> String:
	return "notify_" + category


## Categoria di un messaggio, "" se è importante (non si spegne).
static func category_of(kind: String, data: Dictionary) -> String:
	if kind == "warning" or kind == "error" or str(data.get("reason", "")) == "bank_full":
		return ""
	var explicit := str(data.get("category", ""))
	if CATEGORIES.has(explicit):
		return explicit
	match str(data.get("digest", "")):
		"ach", "title", "frame", "pet", "pet_dupe":
			return "achievements"
		"event", "event_buy", "secret", "rank":
			return "events"
		"boss_soon":
			return "boss"
	match kind:
		"loot":
			return "loot"
		"success":
			return "progress"
		"info":
			return "info"
	return ""


## true se il messaggio va mostrato. `values` permette ai test di passare le impostazioni a mano.
static func allows(kind: String, data: Dictionary, values: Dictionary = {}) -> bool:
	return category_allowed(category_of(kind, data), values)


static func category_allowed(category: String, values: Dictionary = {}) -> bool:
	if category.is_empty():
		return true
	var k := key_of(category)
	if values.has(k):
		return bool(values[k])
	return bool(Settings.get_value(k))
