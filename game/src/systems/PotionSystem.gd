class_name PotionSystem
extends GameSystem
## Alchimia in uso: pozioni a cariche e Banchetti a tempo (docs/05 §6, docs/07, docs/14). id "potions".
##
## Pozioni: 1 per slot (constants.consumables.potion_slots: combat · gathering · artisan · thievery). Una pozione
## ha `charges` (nei dati) e perde una carica per azione RIUSCITA del suo gruppo (SkillSystem.on_skill_action);
## quelle di combattimento perdono cariche per attacco: chi attacca chiama consume("combat", n).
## I bonus sono modificatori normali con id fonte "potion:<slot>" e durano finché restano cariche.
## Le pozioni con scope "any" (Fortuna, Saggezza) si bevono in uno slot di mansione e valgono per quel gruppo.
## Banchetti: 1 solo attivo (constants.consumables.feast_slots); il timer è un effetto di BuffSystem ("feast"),
## quindi scorre anche offline e SkillSystem spezza i segmenti alla scadenza.
##
## Stato (GameState.data.potions): {"active": {slot: {"item": id, "charges": int}}, "feast": item_id | ""}

const SOURCE_PREFIX := "potion:"
const FEAST_BUFF := "feast"

signal changed()


func has_tick() -> bool:
	return false


func _init() -> void:
	id = "potions"
	state_key = "potions"


func default_state() -> Variant:
	return {"active": {}, "feast": ""}


func from_state(section: Variant) -> void:
	state = section
	if not (state.get("active") is Dictionary):
		state["active"] = {}
	if not state.has("feast"):
		state["feast"] = ""
	ctx.modifiers.clear_prefix(SOURCE_PREFIX)
	for slot in state.active.keys():
		var rec: Dictionary = state.active[slot]
		var def: Dictionary = ctx.data.item(str(rec.get("item", "")))
		if def.is_empty() or int(rec.get("charges", 0)) <= 0 or not (slot in slots()):
			state.active.erase(slot)
			continue
		rec["charges"] = int(rec.charges)
		_apply(slot)


func int_paths() -> PackedStringArray:
	return PackedStringArray(["active.*.charges"])


func slots() -> Array:
	return ctx.constants().consumables.potion_slots


# ------------------------------------------------------------------ letture

func charges(slot: String) -> int:
	return int(state.active.get(slot, {}).get("charges", 0))


func item_in(slot: String) -> String:
	return str(state.active.get(slot, {}).get("item", ""))


## Slot delle pozioni che influenza una mansione ("" se nessuno: es. Coltivazione, Forgiachiavi).
func slot_for_skill(skill_id: String) -> String:
	if skill_id == "thievery":
		return "thievery"
	var grp := ""
	for s in ctx.data.table("skills"):
		if str(s.id) == skill_id:
			grp = str(s.get("group", ""))
	return grp if grp in ["gathering", "artisan"] else ""


## Slot in cui una pozione può essere bevuta ({} per scope non valido).
func slots_for(item_id: String) -> Array:
	var scope := str(ctx.data.item(item_id).get("potion", {}).get("scope", ""))
	if scope == "combat":
		return ["combat"]
	if scope == "skill:thievery":
		return ["thievery"]
	if scope.begins_with("skill_group:"):
		return [scope.substr(12)]
	if scope == "any":
		return ["gathering", "artisan", "thievery"]
	return []


# ------------------------------------------------------------------ pozioni

## Beve una pozione dal Deposito. Stessa pozione: le cariche si sommano; un'altra: sostituisce quella dello slot.
func drink(item_id: String, slot: String = "") -> bool:
	var def: Dictionary = ctx.data.item(item_id)
	var pot: Dictionary = def.get("potion", {})
	if pot.is_empty():
		return false
	var allowed := slots_for(item_id)
	var sl := slot if not slot.is_empty() else (str(allowed[0]) if not allowed.is_empty() else "")
	if sl.is_empty() or not (sl in allowed):
		return false
	var b := ctx.get_system("bank")
	if b != null and not b.remove(item_id, 1):
		return false
	var cur: Dictionary = state.active.get(sl, {})
	var ch := int(pot.charges)
	if str(cur.get("item", "")) == item_id:
		ch += int(cur.get("charges", 0))
	state.active[sl] = {"item": item_id, "charges": ch}
	_apply(sl)
	changed.emit()
	return true


## Toglie `n` cariche dallo slot (fine pozione = bonus rimossi).
func consume(slot: String, n: int = 1) -> void:
	if n <= 0 or not state.active.has(slot):
		return
	var rec: Dictionary = state.active[slot]
	rec["charges"] = int(rec.charges) - n
	if int(rec.charges) <= 0:
		discard(slot)
		ctx.events.notice.emit("info", tr("UI_POTION_FINISHED"), {"slot": slot})


func on_skill_action(skill_id: String) -> void:
	var slot := slot_for_skill(skill_id)
	if not slot.is_empty():
		consume(slot, 1)


func discard(slot: String) -> void:
	if state.active.has(slot):
		state.active.erase(slot)
		ctx.modifiers.clear_source(SOURCE_PREFIX + slot)
		changed.emit()


func _apply(slot: String) -> void:
	var rec: Dictionary = state.active[slot]
	var pot: Dictionary = ctx.data.item(str(rec.item)).get("potion", {})
	var target := "thievery" if slot == "thievery" else slot
	var mods: Array = []
	for m in pot.get("modifiers", []):
		var mm: Dictionary = (m as Dictionary).duplicate()
		mm["key"] = str(mm.key).replace(":current", ":" + target)
		mods.append(mm)
	ctx.modifiers.set_source(SOURCE_PREFIX + slot, mods)


# ------------------------------------------------------------------ banchetti

## Mangia un banchetto dal Deposito: sostituisce quello in corso. La durata è in minuti di gioco (anche offline).
func eat_feast(item_id: String) -> bool:
	var def: Dictionary = ctx.data.item(item_id)
	var f: Dictionary = def.get("feast", {})
	var buffs := ctx.get_system("buffs")
	if f.is_empty() or buffs == null:
		return false
	var b := ctx.get_system("bank")
	if b != null and not b.remove(item_id, 1):
		return false
	buffs.remove_buff(FEAST_BUFF)
	buffs.add_buff(FEAST_BUFF, float(f.duration_min) * 60.0, (f.modifiers as Array).duplicate(true))
	state["feast"] = item_id
	changed.emit()
	return true


## Banchetto attivo ("" se nessuno) e secondi rimasti.
func feast_item() -> String:
	var buffs := ctx.get_system("buffs")
	if buffs == null or buffs.remaining(FEAST_BUFF) <= 0.0:
		return ""
	return str(state.get("feast", ""))


func feast_remaining() -> float:
	var buffs := ctx.get_system("buffs")
	return float(buffs.remaining(FEAST_BUFF)) if buffs != null else 0.0
