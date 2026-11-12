extends Node
## Modifiers (autoload) — unico punto d'accesso ai bonus del gioco (docs/14, CLAUDE.md regola 4).
## Delega a una ModifierStack (classe pura in src/core/). I sistemi ricevono `stack` tramite SystemContext.
##   Modifiers.set_source("equip:weapon", [{"key": "skill_double_pct:mining", "value": 3}])
##   Modifiers.apply(3.0, "skill_haste_pct", ["mining", "gathering", "all"])
##   Modifiers.clear_source("equip:weapon")

var stack := ModifierStack.new()


func _ready() -> void:
	if DataRegistry.is_loaded():
		stack.set_catalog(DataRegistry.table("modifier_catalog"))
	stack.changed.connect(func() -> void: EventBus.modifiers_changed.emit())


func set_source(source_id: String, mods: Array) -> bool:
	return stack.set_source(source_id, mods)


func clear_source(source_id: String) -> void:
	stack.clear_source(source_id)


func clear_prefix(prefix: String) -> void:
	stack.clear_prefix(prefix)


func clear_all() -> void:
	stack.clear_all()


func total_add(key: String, scopes: Array = []) -> float:
	return stack.total_add(key, scopes)


func total_more(key: String, scopes: Array = []) -> float:
	return stack.total_more(key, scopes)


func apply(base: float, key: String, scopes: Array = []) -> float:
	return stack.apply(base, key, scopes)


func multiplier(key: String, scopes: Array = []) -> float:
	return stack.multiplier(key, scopes)


func total_add_capped(key: String, scopes: Array = []) -> float:
	return stack.total_add_capped(key, scopes)


func contributions(key: String, scopes: Array = []) -> Array:
	return stack.contributions(key, scopes)
