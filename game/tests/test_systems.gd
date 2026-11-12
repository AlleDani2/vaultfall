extends GutTest
## Interfaccia GameSystem + Simulation + SystemRegistry + BuffSystem (docs/17 §5).
## Mostra anche come si testa un sistema in isolamento (vedi game/README_SISTEMI.md).


## Sistema finto: conta i tick e i secondi nella propria sezione di stato.
class CounterSystem extends GameSystem:
	var log_ref: Array
	func _init(p_id: String, p_log: Array) -> void:
		id = p_id
		state_key = p_id
		log_ref = p_log
	func default_state() -> Variant:
		return {"ticks": 0, "seconds": 0.0}
	func tick(dt: float) -> void:
		state.ticks += 1
		state.seconds += dt
		log_ref.append(id)
	func int_paths() -> PackedStringArray:
		return PackedStringArray(["ticks"])


func _ctx(state: Dictionary = {}) -> SystemContext:
	return SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(1), EventBus)


func test_ordine_stato_e_tick() -> void:
	var order: Array = []
	var sim := Simulation.new()
	var state := {}
	sim.setup(_ctx(state), [CounterSystem.new("first", order), CounterSystem.new("second", order)])
	sim.bind_state(state)
	assert_eq(state.first, {"ticks": 0, "seconds": 0.0}, "sezione creata da default_state")
	for i in 10:
		sim.tick(FixedStepClock.STEP)
	assert_eq(order.slice(0, 4), ["first", "second", "first", "second"], "ordine fisso di registrazione")
	assert_eq(state.first.ticks, 10, "il sistema scrive nella sezione VIVA di GameState")
	assert_almost_eq(state.second.seconds, 1.0, 1e-9)
	assert_eq(sim.get_system("second").ctx.get_system("first"), sim.get_system("first"), "accesso tra sistemi")
	assert_true(sim.int_paths().has("first.ticks"), "percorsi interi con prefisso della sezione")


func test_sistema_disabilitato_e_offline_di_base() -> void:
	var order: Array = []
	var sim := Simulation.new()
	var state := {}
	sim.setup(_ctx(state), [CounterSystem.new("a", order)])
	sim.bind_state(state)
	sim.get_system("a").enabled = false
	sim.tick(0.1)
	assert_eq(state.a.ticks, 0)
	sim.get_system("a").enabled = true
	sim.run_offline(5.0)
	assert_eq(state.a.ticks, 50, "simulate_offline di base: tick a passi fissi")


func test_registro_dei_sistemi() -> void:
	var list := SystemRegistry.create_all()
	assert_gt(list.size(), 0)
	var ids := {}
	for s in list:
		assert_true(s is GameSystem)
		assert_false(s.id.is_empty(), "id obbligatorio")
		assert_false(ids.has(s.id), "id unico")
		ids[s.id] = true
	assert_not_null(Game.system("buffs"), "Game aggancia i sistemi del registro")


func test_buff_system() -> void:
	var state := {}
	var ctx := _ctx(state)
	var sim := Simulation.new()
	sim.setup(ctx, [BuffSystem.new()])
	sim.bind_state(state)
	var b: BuffSystem = sim.get_system("buffs")
	b.add_buff("potion_haste", 1.0, [{"key": "skill_haste_pct:all", "value": 10}])
	assert_almost_eq(ctx.modifiers.total_add("skill_haste_pct", ["all"]), 10.0, 1e-9)
	b.add_buff("potion_haste", 0.5, [{"key": "skill_haste_pct:all", "value": 10}])
	assert_almost_eq(b.remaining("potion_haste"), 1.0, 1e-9, "il rinnovo tiene la durata maggiore")
	for i in 9:
		sim.tick(0.1)
	assert_true(state.buffs.active.has("potion_haste"))
	sim.tick(0.1)
	assert_false(state.buffs.active.has("potion_haste"), "scaduto dopo 1 s simulato")
	assert_almost_eq(ctx.modifiers.total_add("skill_haste_pct", ["all"]), 0.0, 1e-9, "modificatori rimossi")
	# ripresa da salvataggio: i modificatori si ri-registrano
	b.add_buff("feast", 3600.0, [{"key": "skill_xp_pct:all", "value": 8}])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state))
	var ctx2 := _ctx(saved)
	var sim2 := Simulation.new()
	sim2.setup(ctx2, [BuffSystem.new()])
	sim2.bind_state(saved)
	assert_almost_eq(ctx2.modifiers.total_add("skill_xp_pct", ["all"]), 8.0, 1e-9)
	var rep := sim2.run_offline(4000.0)
	assert_eq(rep.get("buffs", {}).get("expired", []), ["feast"], "offline analitico")
	assert_almost_eq(ctx2.modifiers.total_add("skill_xp_pct", ["all"]), 0.0, 1e-9)
