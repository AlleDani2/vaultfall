extends GutTest
## T-1.3: Modifiers / ModifierStack (docs/14): regola add/more, ambiti, fonti, cache, catalogo e cap.

var m: ModifierStack


func before_each() -> void:
	m = ModifierStack.new()


func test_regola_add_more() -> void:
	m.set_source("a", [{"key": "skill_xp_pct", "value": 20}])
	m.set_source("b", [{"key": "skill_xp_pct", "value": 30}])
	m.set_source("c", [{"key": "skill_xp_pct", "value": 10, "mode": "more"}])
	m.set_source("d", [{"key": "skill_xp_pct", "value": 20, "mode": "more"}])
	assert_almost_eq(m.total_add("skill_xp_pct"), 50.0, 1e-9)
	assert_almost_eq(m.total_more("skill_xp_pct"), 1.1 * 1.2, 1e-12)
	# 10 × (1 + 50/100) × 1,1 × 1,2 = 19,8
	assert_almost_eq(m.apply(10.0, "skill_xp_pct"), 19.8, 1e-9)
	assert_almost_eq(m.multiplier("skill_xp_pct"), 1.98, 1e-9)


func test_ambiti() -> void:
	m.set_source("tool", [{"key": "skill_xp_pct:mining", "value": 5}])
	m.set_source("pet", [{"key": "skill_xp_pct:gathering", "value": 3}])
	m.set_source("feast", [{"key": "skill_xp_pct:all", "value": 8}])
	m.set_source("other", [{"key": "skill_xp_pct:fishing", "value": 100}])
	m.set_source("global", [{"key": "skill_xp_pct", "value": 1}])
	var scopes := ["mining", "gathering", "all"]
	assert_almost_eq(m.total_add("skill_xp_pct", scopes), 17.0, 1e-9, "famiglia nuda + ambiti richiesti, non fishing")
	assert_almost_eq(m.total_add("skill_xp_pct"), 1.0, 1e-9, "senza ambiti solo la famiglia nuda")
	assert_almost_eq(m.total_add("skill_xp_pct:mining"), 6.0, 1e-9, "chiave con ambito + famiglia nuda")
	assert_eq(m.contributions("skill_xp_pct", scopes).size(), 4)


func test_set_source_sostituisce_e_rimozione() -> void:
	m.set_source("equip:weapon", [{"key": "combat_dmg_pct", "value": 6}])
	assert_almost_eq(m.total_add("combat_dmg_pct"), 6.0, 1e-9)
	m.set_source("equip:weapon", [{"key": "combat_dmg_pct", "value": 9}])
	assert_almost_eq(m.total_add("combat_dmg_pct"), 9.0, 1e-9, "il blocco della fonte si sostituisce, non si somma")
	m.set_source("equip:ring1", [{"key": "combat_dmg_pct", "value": 2}])
	m.set_source("pet:x", [{"key": "combat_dmg_pct", "value": 1}])
	m.clear_prefix("equip:")
	assert_almost_eq(m.total_add("combat_dmg_pct"), 1.0, 1e-9, "clear_prefix rimuove tutte le fonti equip:")
	m.clear_source("pet:x")
	assert_almost_eq(m.total_add("combat_dmg_pct"), 0.0, 1e-9)
	assert_almost_eq(m.total_more("combat_dmg_pct"), 1.0, 1e-9)
	assert_eq(m.source_ids().size(), 0)


func test_cache_invalidata() -> void:
	m.set_source("a", [{"key": "skill_haste_pct", "value": 10}])
	assert_almost_eq(m.total_add("skill_haste_pct", ["mining"]), 10.0, 1e-9)
	m.set_source("b", [{"key": "skill_haste_pct:mining", "value": 5}])
	assert_almost_eq(m.total_add("skill_haste_pct", ["mining"]), 15.0, 1e-9, "la cache si invalida al cambio")
	watch_signals(m)
	m.clear_all()
	assert_signal_emitted(m, "changed")
	assert_almost_eq(m.total_add("skill_haste_pct", ["mining"]), 0.0, 1e-9)


func test_catalogo_e_cap() -> void:
	m.set_catalog(DataRegistry.table("modifier_catalog"))
	assert_false(m.set_source("x", [{"key": "chiave_inventata", "value": 1}]), "R-MOD-1: famiglia non in catalogo")
	assert_false(m.has_source("x"))
	assert_false(m.set_source("y", [{"key": "skill_xp_pct", "value": 1, "mode": "boh"}]), "modo non valido")
	m.set_source("s1", [{"key": "skill_save_pct:all", "value": 40}])
	m.set_source("s2", [{"key": "skill_save_pct:mining", "value": 30}])
	assert_eq(m.cap_of("skill_save_pct"), 50.0)
	assert_almost_eq(m.total_add_capped("skill_save_pct", ["mining", "all"]), 50.0, 1e-9)
	assert_true(m.is_capped("skill_save_pct", ["mining", "all"]))
	assert_eq(m.cap_of("skill_xp_pct"), INF, "nessun cap")


func test_autoload_modifiers() -> void:
	watch_signals(EventBus)
	Modifiers.set_source("test:auto", [{"key": "skill_xp_pct:mining", "value": 4}])
	assert_almost_eq(Modifiers.apply(100.0, "skill_xp_pct", ["mining"]), 104.0, 1e-9)
	assert_signal_emitted(EventBus, "modifiers_changed")
	Modifiers.clear_source("test:auto")
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["mining"]), 0.0, 1e-9)
