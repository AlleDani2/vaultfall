class_name TestFakeBank
extends GameSystem
## Finto Deposito con le firme del contratto "bank" (docs/audit_2026-10-22/17): serve ai test delle Casse
## finché il sistema vero non è integrato.

var stacks: Dictionary = {}
var inst: Dictionary = {}
var n: int = 0


func _init() -> void:
	id = "bank"


func add(def_id: String, qty: int, _source: String = "") -> int:
	stacks[def_id] = int(stacks.get(def_id, 0)) + qty
	return qty


func remove(def_id: String, qty: int) -> bool:
	if int(stacks.get(def_id, 0)) < qty:
		return false
	stacks[def_id] = int(stacks[def_id]) - qty
	return true


func count(def_id: String) -> int:
	return int(stacks.get(def_id, 0))


func has(def_id: String, qty: int = 1) -> bool:
	return count(def_id) >= qty


func add_instance(i: Dictionary) -> String:
	n += 1
	var uid := "i_%06d" % n
	i["uid"] = uid
	inst[uid] = i
	return uid


func get_instance(uid: String) -> Dictionary:
	return inst.get(uid, {})


func remove_instance(uid: String) -> bool:
	return inst.erase(uid)


func list_instances() -> Array:
	return inst.values()


## Spazi liberi (contratto "bank"): illimitati, salvo che un test imposti `free_limit`.
var free_limit: int = 1 << 40


func free_slots() -> int:
	return maxi(0, free_limit - inst.size())
