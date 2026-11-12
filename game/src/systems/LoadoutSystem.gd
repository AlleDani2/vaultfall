class_name LoadoutSystem
extends GameSystem
## Set di equipaggiamento (docs/10 §5 «Set di equipaggiamento», docs/16 §3.6 scheda «Set», audit 71 G15).
## I posti si comprano all'Emporio (`loadout_slot`, effetto "loadouts": MarketSystem.shop_effect_total); senza posti
## comprati non c'è nessun set. Un set ricorda gli uid indossati negli slot dell'Eroe e le munizioni (id oggetto).
## Applicare un set passa SOLO dai metodi pubblici di CombatSystem (equip/unequip/equip_ammo): requisiti di livello,
## armi a due mani e blocco nei dungeon restano quelli del combattimento. I pezzi venduti o scartati si saltano
## (elencati in `missing`), il resto si indossa comunque.
##
## Stato (GameState.data.loadouts): {"sets": [{"name": String, "gear": {slot: uid}, "ammo": def_id}]}. Sezione nuova:
## i salvataggi precedenti la ricevono da default_state (nessuna migrazione, SCHEMA_VERSION invariato).

const NAME_MAX := 24


func _init() -> void:
	id = "loadouts"
	state_key = "loadouts"


func default_state() -> Variant:
	return {"sets": []}


func from_state(section: Variant) -> void:
	state = section if section is Dictionary else default_state()
	if not (state.get("sets") is Array):
		state["sets"] = []
	var clean: Array = []
	for s in state.sets:
		if s is Dictionary:
			clean.append({"name": str(s.get("name", "")).left(NAME_MAX),
				"gear": (s.get("gear", {}) as Dictionary).duplicate() if s.get("gear") is Dictionary else {},
				"ammo": str(s.get("ammo", ""))})
		else:
			clean.append({})
	state["sets"] = clean


## Il Loadout è a soli comandi (nessun tick): l'offline non deve fare 864.000 chiamate a vuoto (QA81 M4).
func has_tick() -> bool:
	return false


func _combat() -> GameSystem:
	return ctx.get_system("combat")


func _bank() -> GameSystem:
	return ctx.get_system("bank")


## Posti comprati all'Emporio.
func slot_count() -> int:
	var mk := ctx.get_system("market")
	if mk == null or not mk.has_method("shop_effect_total"):
		return 0
	return int(mk.call("shop_effect_total", "loadouts"))


## Set del posto `index` ({} se vuoto o fuori dai posti comprati).
func get_set(index: int) -> Dictionary:
	if index < 0 or index >= slot_count() or index >= state.sets.size():
		return {}
	var s: Variant = state.sets[index]
	return (s as Dictionary).duplicate(true) if s is Dictionary and not (s as Dictionary).is_empty() else {}


func is_empty_slot(index: int) -> bool:
	return get_set(index).is_empty()


## Salva ciò che l'Eroe indossa ora nel posto `index`. `name` vuoto = nome automatico della UI. false se il posto non c'è.
func save_set(index: int, set_name: String = "") -> bool:
	if index < 0 or index >= slot_count():
		return false
	var eqs: Variant = ctx.state.get("equipment", {})
	var gear := {}
	var ammo := ""
	if eqs is Dictionary:
		for slot in CombatSystem.EQUIP_SLOTS:
			var v: Variant = (eqs as Dictionary).get(slot, "")
			if slot == "ammo":
				ammo = str(v.get("def", "")) if v is Dictionary else ""
			elif not str(v).is_empty():
				gear[slot] = str(v)
	while state.sets.size() <= index:
		state.sets.append({})
	var old: Variant = state.sets[index]
	var keep := str(old.get("name", "")) if old is Dictionary else ""
	state.sets[index] = {"name": (set_name if not set_name.is_empty() else keep).left(NAME_MAX), "gear": gear, "ammo": ammo}
	ctx.events.important_event.emit("loadout")
	return true


func rename_set(index: int, set_name: String) -> bool:
	if is_empty_slot(index):
		return false
	state.sets[index]["name"] = set_name.strip_edges().left(NAME_MAX)
	return true


func clear_set(index: int) -> bool:
	if is_empty_slot(index):
		return false
	state.sets[index] = {}
	return true


## "" se il set si può indossare ora, altrimenti la chiave del motivo.
func can_apply(index: int) -> String:
	if is_empty_slot(index):
		return "UI_GAPM_SET_REASON_EMPTY"
	var cb := _combat()
	if cb == null:
		return "UI_GAPM_SET_REASON_EMPTY"
	if bool(cb.call("in_combat_blocking")):
		return "UI_GAPM_SET_REASON_DUNGEON"
	return ""


## Pezzi del set che non ci sono più nel Deposito (venduti, scartati, persi): [slot].
func missing_slots(index: int) -> Array:
	var s := get_set(index)
	var out: Array = []
	var b := _bank()
	for slot in s.get("gear", {}):
		if b == null or (b.call("get_instance", str(s.gear[slot])) as Dictionary).is_empty():
			out.append(str(slot))
	return out


## Indossa il set: prima toglie tutto (munizioni escluse), poi indossa nell'ordine degli slot dell'Eroe (arma prima
## della mano secondaria, primo anello prima del secondo). Ritorna {ok, reason, worn, missing: [slot], failed: [slot]}.
func apply_set(index: int) -> Dictionary:
	var reason := can_apply(index)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "worn": 0, "missing": [], "failed": []}
	var s := get_set(index)
	var cb := _combat()
	var b := _bank()
	var missing := missing_slots(index)
	for slot in CombatSystem.EQUIP_SLOTS:
		if slot != "ammo" and not str(cb.call("equipped", slot)).is_empty():
			cb.call("unequip", slot)
	var worn := 0
	var failed: Array = []
	for slot in CombatSystem.EQUIP_SLOTS:
		if slot == "ammo" or not s.gear.has(slot) or missing.has(slot):
			continue
		if bool(cb.call("equip", str(s.gear[slot]))):
			worn += 1
		else:
			failed.append(slot)
	var ammo := str(s.get("ammo", ""))
	if not ammo.is_empty() and b != null and int(b.call("count", ammo)) > 0:
		cb.call("equip_ammo", ammo)
	ctx.events.important_event.emit("loadout")
	return {"ok": true, "reason": "", "worn": worn, "missing": missing, "failed": failed}
