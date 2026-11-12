extends GutTest
## Simulation.tick_subset (Sabbia del Custode, UI F13): ordine fisso del registro, bank prima, nessun tick agli altri sistemi,
## playtime e calendario invariati.

class Spy extends GameSystem:
	static var log: Array = []
	func _init(p_id: String = "") -> void:
		id = p_id
	func tick(dt: float) -> void:
		Spy.log.append([id, dt])


func _make(ids: Array) -> Simulation:
	var state := {}
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(1), EventBus)
	var sim := Simulation.new()
	var list: Array = []
	for i in ids:
		list.append(Spy.new(str(i)))
	sim.setup(ctx, list)
	sim.bind_state(state)
	Spy.log.clear()
	return sim


func test_ordine_del_registro_non_quello_della_richiesta() -> void:
	var sim := _make(["bank", "skills", "combat", "queue", "farming"])
	sim.tick_subset(["queue", "skills", "bank"], 0.1)
	assert_eq(Spy.log.map(func(e: Array) -> String: return str(e[0])), ["bank", "skills", "queue"], "bank prima, ordine fisso")
	for e in Spy.log:
		assert_almost_eq(float(e[1]), 0.1, 1e-12)


func test_nessun_tick_agli_altri_sistemi() -> void:
	var sim := _make(["bank", "skills", "combat", "queue", "farming", "estate"])
	sim.tick_subset(["skills", "queue"], 0.1)
	var seen := Spy.log.map(func(e: Array) -> String: return str(e[0]))
	assert_false(seen.has("combat") or seen.has("farming") or seen.has("estate") or seen.has("bank"))
	sim.tick_subset([], 0.1)
	sim.tick_subset(["skills"], 0.0)
	sim.tick_subset(["skills"], -1.0)
	sim.tick_subset(["skills"], NAN)
	assert_eq(Spy.log.size(), 2, "elenco vuoto o dt non valido: nulla")


func test_sistema_spento_non_avanza() -> void:
	var sim := _make(["bank", "skills"])
	sim.get_system("skills").enabled = false
	sim.tick_subset(["bank", "skills"], 0.1)
	assert_eq(Spy.log.size(), 1)


func test_partita_vera_calendario_e_mondo_invariati() -> void:
	assert_true(Game.new_game(1, "normal", 12))
	var ids: Array = DataRegistry.constants.time_push.systems_for.skill
	assert_eq(ids[0], "bank", "bank per primo, come Hourglass.SYSTEMS_FOR")
	var sk := Game.system("skills") as SkillSystem
	for a in DataRegistry.actions_for_skill("woodcutting"):
		if int(a.get("level_req", 1)) <= 1:
			GameState.data.unlocks.append("skill:woodcutting")
			if sk.start(str(a.id)):
				break
	var keep := ["estate", "farming", "expeditions", "buffs"]
	var before := {}
	for k in keep:
		before[k] = GameState.data[k].duplicate(true) if GameState.data.has(k) else null
	var mk0: Dictionary = {}
	for f in ["t", "day", "next_gazette_t", "next_order_t"]:
		mk0[f] = GameState.data.market[f]        # il Mercato reagisce agli oggetti ottenuti (evento), ma il SUO orologio non avanza
	var play0 := float(GameState.data.stats.playtime_s)
	var clock0 := float(GameState.data.prestige.clock_s)
	var xp0 := float(GameState.data.skills.woodcutting.xp)
	for i in 600:
		Game.sim.tick_subset(ids, 0.1)
	assert_gt(float(GameState.data.skills.woodcutting.xp), xp0, "l'azione e' avanzata di 60 s")
	for k in keep:
		var now: Variant = GameState.data[k].duplicate(true) if GameState.data.has(k) else null
		assert_eq(now, before[k], "sezione intatta: " + k)
	for f in mk0:
		assert_eq(GameState.data.market[f], mk0[f], "orologio del Mercato: " + f)
	assert_almost_eq(float(GameState.data.stats.playtime_s), play0, 1e-9, "playtime_s invariato")
	assert_almost_eq(float(GameState.data.prestige.clock_s), clock0, 1e-9, "calendario/orologio della Tenuta invariato")
	Game.stop_game(false)
