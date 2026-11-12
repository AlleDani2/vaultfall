extends RefCounted
## Finti sistemi con le firme di docs/audit_2026-10-22/17_CONTRATTI_TRA_SISTEMI.md, per provare QuestSystem e
## UnlockSystem senza dipendere dagli altri agenti. Più un finto DataRegistry con l'elenco missioni sostituibile.


class FakeData extends RefCounted:
	var quests: Array = []

	func table(n: String) -> Array:
		return quests if n == "quests" else DataRegistry.table(n)

	func action(id: String) -> Dictionary:
		return DataRegistry.action(id)

	func item(id: String) -> Dictionary:
		return DataRegistry.item(id)

	func has_item(id: String) -> bool:
		return DataRegistry.has_item(id)

	func all_actions() -> Dictionary:
		return DataRegistry.all_actions()

	func get_def(t: String, id: String) -> Dictionary:
		if t == "quests":
			for q in quests:
				if q.id == id:
					return q
			return {}
		return DataRegistry.get_def(t, id)

	var constants: Dictionary:
		get:
			return DataRegistry.constants


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var gold_total: int = 0
	var instances: Dictionary = {}

	func _init() -> void:
		id = "bank"

	func add(def_id: String, qty: int, _source: String = "") -> int:
		stacks[def_id] = int(stacks.get(def_id, 0)) + qty
		return qty

	func remove(def_id: String, qty: int) -> bool:
		if int(stacks.get(def_id, 0)) < qty:
			return false
		stacks[def_id] -= qty
		return true

	func count(def_id: String) -> int:
		return int(stacks.get(def_id, 0))

	func add_gold(n: int) -> void:
		gold_total += n

	func get_instance(uid: String) -> Dictionary:
		return instances.get(uid, {})


class FakeCrates extends GameSystem:
	var granted: Dictionary = {}

	func _init() -> void:
		id = "crates"

	func grant_crate(crate_id: String, qty: int = 1) -> void:
		granted[crate_id] = int(granted.get(crate_id, 0)) + qty
