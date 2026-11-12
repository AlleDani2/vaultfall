class_name ItemActions
extends RefCounted
## Menù contestuale degli oggetti (tasto destro, docs/16 §8, UI-A G25): equipaggia / togli, blocca / sblocca, vendi, fondi.
## `available()` decide le voci (pura, testabile); `perform()` le esegue sui sistemi veri; `popup()` costruisce il PopupMenu.
## Mai una scorciatoia: le regole di vendita e fusione sono quelle dei sistemi (bloccati e indossati restano al sicuro).

const MARKET_TOKEN := "feature:market"
## Voci in ordine di comparsa. Ogni id ha il testo UI_UIA_ACT_<ID>.
const ORDER: PackedStringArray = ["equip", "unequip", "lock", "unlock", "sell", "fuse"]


## Voci disponibili per l'oggetto: [{"id", "enabled", "why": chiave del motivo se disabilitata}].
## `uid` = "" per le pile (si possono solo bloccare/sbloccare e vendere).
static func available(def_id: String, uid: String) -> Array:
	var out: Array = []
	if not GameState.active:
		return out
	var bank := Game.system("bank") as BankSystem
	var cb := Game.system("combat") as CombatSystem
	var market := Game.system("market") as MarketSystem
	var cr := Game.system("crates") as CrateSystem
	if bank == null:
		return out
	var def := DataRegistry.item(def_id)
	var is_inst := not uid.is_empty()
	var locked := bank.is_instance_locked(uid) if is_inst else bank.is_def_locked(def_id)
	var equipped := is_inst and cb != null and cb.is_equipped(uid)
	var wearable := is_inst and (def.has("equipment") or def.has("tool"))
	if wearable and not equipped:
		out.append({"id": "equip", "enabled": cb != null and not cb.in_combat_blocking(), "why": "UI_UIA_ACT_WHY_DUNGEON"})
	if equipped:
		out.append({"id": "unequip", "enabled": cb != null and not def.has("tool") and not cb.in_combat_blocking(), "why": "UI_UIA_ACT_WHY_DUNGEON"})
	if is_inst or bank.state.stacks.has(def_id):
		out.append({"id": "unlock" if locked else "lock", "enabled": true, "why": ""})
	if market != null and market.is_tradeable(def_id):
		var can_sell := GameState.has_unlock(MARKET_TOKEN) and not locked and not equipped \
			and (bank.sellable_count(def_id) > 0 if not is_inst else not bank.is_in_use(uid))
		out.append({"id": "sell", "enabled": can_sell, "why": "UI_UIA_ACT_WHY_SELL"})
	if is_inst and cr != null and cr.instance(uid) != {} and cr.fuse_value(uid) > 0:
		out.append({"id": "fuse", "enabled": cr.consume_block(uid).is_empty(), "why": "UI_UIA_ACT_WHY_FUSE"})
	return out


## Esegue una voce. Ritorna true se qualcosa è cambiato.
static func perform(action: String, def_id: String, uid: String) -> bool:
	var bank := Game.system("bank") as BankSystem
	var cb := Game.system("combat") as CombatSystem
	var market := Game.system("market") as MarketSystem
	var cr := Game.system("crates") as CrateSystem
	if bank == null:
		return false
	var is_inst := not uid.is_empty()
	match action:
		"equip":
			return cb != null and cb.equip(uid)
		"unequip":
			if cb == null:
				return false
			var slot := ""
			for s in CombatSystem.EQUIP_SLOTS:
				if s != "ammo" and cb.equipped(s) == uid:
					slot = s
			if slot.is_empty():
				return false
			cb.unequip(slot)
			return true
		"lock", "unlock":
			if is_inst:
				bank.set_instance_locked(uid, action == "lock")
			else:
				bank.set_def_locked(def_id, action == "lock")
			return true
		"sell":
			if market == null:
				return false
			var gold := market.sell_instances([uid]) if is_inst else market.sell(def_id, bank.sellable_count(def_id))
			if gold > 0:
				EventBus.notice.emit("success", Loc.tf("UI_BANK_SOLD_NOTICE", {"gold": NumberFormat.fmt(gold)}), {"category": "loot"})
			return gold > 0
		"fuse":
			if cr == null:
				return false
			var got := cr.fuse(uid)
			if got > 0:
				EventBus.notice.emit("success", Loc.tf("UI_UIA_ACT_FUSED", {"n": got}), {"category": "loot"})
			return got > 0
	return false


## Mostra il menù. `extras` = [{"text": testo già tradotto, "call": Callable}] per le voci della singola schermata
## (Confronta, Scarta…). `on_done` si chiama dopo una voce standard eseguita.
static func popup(host: Node, global_pos: Vector2, def_id: String, uid: String, on_done: Callable, extras: Array = []) -> PopupMenu:
	var pm := PopupMenu.new()
	pm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var acts := available(def_id, uid)
	for i in acts.size():
		var a: Dictionary = acts[i]
		pm.add_item(TranslationServer.translate("UI_UIA_ACT_" + str(a.id).to_upper()), i)
		pm.set_item_disabled(pm.item_count - 1, not bool(a.enabled))
		if not bool(a.enabled) and str(a.why) != "":
			pm.set_item_tooltip(pm.item_count - 1, TranslationServer.translate(str(a.why)))
	if not extras.is_empty() and not acts.is_empty():
		pm.add_separator()
	for j in extras.size():
		pm.add_item(str(extras[j].text), 100 + j)
	pm.id_pressed.connect(func(id: int) -> void:
		if id >= 100:
			(extras[id - 100].call as Callable).call()
		elif id < acts.size() and perform(str(acts[id].id), def_id, uid) and on_done.is_valid():
			on_done.call()
		pm.queue_free())
	pm.popup_hide.connect(pm.queue_free)
	host.add_child(pm)
	pm.position = Vector2i(global_pos)
	pm.popup()
	return pm
