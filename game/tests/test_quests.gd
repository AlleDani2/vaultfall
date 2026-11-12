extends GutTest
## T-4.4: QuestSystem (tutti i tipi di obiettivo), UnlockSystem, ordine del Prologo, "nessun sistema prima del suo
## sblocco" e simulazione della prima ora con sistemi finti (bank/crates con le firme del contratto 17).

const Fakes := preload("res://tests/helpers/quest_fakes.gd")

var _keep: Array = []


func before_all() -> void:
	# una partita lasciata aperta da un altro test ascolterebbe gli stessi segnali di EventBus (casse, Deposito)
	if GameState.active:
		Game.stop_game(false)


func _quest(id: String, objs: Array, rewards: Dictionary = {"gold": 10}, unlocks: Array = [], requires: Array = []) -> Dictionary:
	return {"id": id, "kind": "main", "chapter": 0, "giver": "ilde", "title": {"it": "T " + id, "en": "T " + id},
		"desc": {"it": "d", "en": "d"}, "objectives": objs, "rewards": rewards, "unlocks": unlocks, "requires": requires}


## Costruisce una simulazione con QuestSystem + UnlockSystem + finti bank/crates sulle missioni date.
func _make(quests: Array) -> Dictionary:
	var data := Fakes.FakeData.new()
	data.quests = quests
	var state := {"unlocks": [], "skills": {}, "equipment": {}, "estate": {"buildings": {}}, "hero": {"class": "warrior"}}
	var ctx := SystemContext.make(data, state, ModifierStack.new(), RngStreams.new(7), EventBus)
	var sim := Simulation.new()
	var q := QuestSystem.new()
	var u := UnlockSystem.new()
	var bank := Fakes.FakeBank.new()
	var crates := Fakes.FakeCrates.new()
	sim.setup(ctx, [bank, crates, q, u])
	sim.bind_state(state)
	sim.tick(0.1)
	_keep.append(sim)
	return {"sim": sim, "q": q, "u": u, "bank": bank, "crates": crates, "state": state, "data": data}


func _step(m: Dictionary, n: int = 2) -> void:
	for i in n:
		m.sim.tick(0.1)


func _progress(m: Dictionary, qid: String = "t") -> Array:
	return m.q.progress_of(qid)


# ------------------------------------------------------------------ tipi di obiettivo

func test_gather_craft_skill_actions() -> void:
	var m := _make([_quest("t", [
		{"type": "gather", "item": "log_pine", "qty": 3},
		{"type": "craft", "item": "bar_copper", "qty": 2},
		{"type": "craft_any", "skill": "smithing", "qty": 2},
		{"type": "skill_actions", "skill": "woodcutting", "qty": 3},
		{"type": "craft_category", "category": "smelting", "qty": 2}])])
	for i in 3:
		EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 1}])
	for i in 2:
		EventBus.action_completed.emit("smelt_copper", [{"item": "bar_copper", "qty": 1}])
	_step(m)
	assert_eq(_progress(m), [3, 2, 2, 3, 2])
	assert_true(m.q.is_ready("t"))


func test_gather_non_conta_la_produzione_e_viceversa() -> void:
	var m := _make([_quest("t", [{"type": "gather", "item": "bar_copper", "qty": 1}])])
	EventBus.action_completed.emit("smelt_copper", [{"item": "bar_copper", "qty": 1}])
	_step(m)
	assert_eq(_progress(m), [0], "un lingotto prodotto non è una raccolta")


func test_kill_family() -> void:
	var m := _make([_quest("t", [
		{"type": "kill", "monster": "mud_slime", "qty": 2},
		{"type": "kill_any", "qty": 3},
		{"type": "kill_zone", "zone": "millbrook", "qty": 3},
		{"type": "kill_any_as_class", "cls": "warrior", "qty": 3}])])
	EventBus.monster_killed.emit("mud_slime", [])
	EventBus.monster_killed.emit("mud_slime", [])
	EventBus.monster_killed.emit("grey_wolf", [])
	_step(m)
	assert_eq(_progress(m), [2, 3, 3, 3])


func test_kill_family_batch_same_as_singles() -> void:
	var m := _make([_quest("t", [
		{"type": "kill", "monster": "mud_slime", "qty": 2},
		{"type": "kill_any", "qty": 3},
		{"type": "kill_zone", "zone": "millbrook", "qty": 3},
		{"type": "kill_any_as_class", "cls": "warrior", "qty": 3}])])
	EventBus.monsters_killed_batch.emit("mud_slime", 2, [])
	EventBus.monsters_killed_batch.emit("grey_wolf", 1, [])
	_step(m)
	assert_eq(_progress(m), [2, 3, 3, 3], "il batch conta come N uccisioni singole")


func test_crates_and_rarity() -> void:
	var m := _make([_quest("t", [
		{"type": "open_crates", "crate": "any", "qty": 3},
		{"type": "open_crates", "crate": "crate_millbrook", "qty": 1},
		{"type": "obtain_rarity", "rarity": "epic", "qty": 1}])])
	EventBus.crate_opened.emit({"crate_id": "crate_millbrook", "rarity": "epic"})
	EventBus.crate_opened.emit({"crate_id": "crate_other", "rarity": "rare", "count": 2})
	_step(m)
	assert_eq(_progress(m), [3, 1, 1])


func test_deliver_consuma_dal_deposito() -> void:
	var m := _make([_quest("t", [{"type": "deliver", "item": "log_pine", "qty": 5}])])
	m.bank.stacks["log_pine"] = 3
	assert_true(m.q.deliver("t", 0))
	assert_eq(m.bank.count("log_pine"), 0)
	assert_eq(_progress(m), [3])
	assert_false(m.q.deliver("t", 0), "niente da consegnare")
	m.bank.stacks["log_pine"] = 9
	assert_true(m.q.deliver("t", 0))
	assert_eq(m.bank.count("log_pine"), 7, "ne servivano 2")
	assert_true(m.q.is_ready("t"))


func test_equip_build_levels_sono_di_stato() -> void:
	var m := _make([_quest("t", [
		{"type": "equip", "item": "sword_copper"},
		{"type": "build", "building": "cottage", "level": 2},
		{"type": "reach_level", "skill": "mining", "level": 5},
		{"type": "reach_total_level", "level": 8},
		{"type": "estate_total_levels", "qty": 3}])])
	m.bank.instances["i_1"] = {"def": "sword_copper"}
	m.state.equipment["weapon"] = "i_1"
	m.state.estate.buildings["cottage"] = {"level": 2}
	m.state.estate.buildings["mill"] = {"level": 1}
	m.state.skills["mining"] = {"level": 5}
	m.state.skills["woodcutting"] = {"level": 3}
	_step(m, 12)         # il controllo di stato avviene ogni secondo simulato
	assert_eq(_progress(m), [1, 2, 5, 8, 3])
	assert_true(m.q.is_ready("t"))
	m.state.skills["mining"]["level"] = 1       # il valore non scende mai
	_step(m, 12)
	assert_eq(_progress(m)[2], 5)


func test_reach_level_gia_soddisfatto_e_immediato() -> void:
	var data := Fakes.FakeData.new()
	data.quests = [_quest("t", [{"type": "reach_level", "skill": "mining", "level": 3}])]
	var state := {"unlocks": [], "skills": {"mining": {"level": 4}}}
	var sim := Simulation.new()
	var q := QuestSystem.new()
	sim.setup(SystemContext.make(data, state, ModifierStack.new(), RngStreams.new(1), EventBus), [Fakes.FakeBank.new(), q, UnlockSystem.new()])
	sim.bind_state(state)
	q.start()
	assert_true(q.is_ready("t"))


func test_eventi_generici() -> void:
	var cases := [
		[{"type": "sell_market", "gold": 500}, "sell_market", {"gold": 300}, 300],
		[{"type": "steal", "target": "steal_x", "qty": 2}, "steal", {"target": "steal_x"}, 1],
		[{"type": "farm_harvest", "crop": "crop_potato", "qty": 2}, "farm_harvest", {"crop": "crop_potato", "qty": 2}, 2],
		[{"type": "complete_dungeon", "dungeon": "any", "qty": 1}, "complete_dungeon", {"dungeon": "cursed_granary"}, 1],
		[{"type": "complete_raid", "raid": "any", "qty": 1}, "complete_raid", {"raid": "r1"}, 1],
		[{"type": "recruit", "qty": 2}, "recruit", {}, 1],
		[{"type": "expedition", "qty": 1}, "expedition", {}, 1],
		[{"type": "bounty_complete", "qty": 1}, "bounty_complete", {}, 1],
		[{"type": "tradeup", "qty": 1}, "tradeup", {}, 1],
		[{"type": "refine_polish", "qty": 1}, "refine_polish", {}, 1],
		[{"type": "socket_glyph", "qty": 1}, "socket_glyph", {}, 1],
		[{"type": "orders_complete", "qty": 1}, "orders_complete", {}, 1],
		[{"type": "estate_prestige", "qty": 1}, "estate_prestige", {}, 1],
		[{"type": "secret_spot", "qty": 1}, "secret_spot", {}, 1],
		[{"type": "secret_spot_all", "qty": 1}, "secret_spot_all", {}, 1],
		[{"type": "world_boss", "tier": "gold", "qty": 1}, "world_boss", {"tier": "gold"}, 1],
		[{"type": "rift_floor", "floor": 5}, "rift_floor", {"floor": 4}, 4],
		[{"type": "talk", "npc": "ilde"}, "talk", {"npc": "ilde"}, 1],
		[{"type": "craft_rank", "rank": 3, "qty": 1}, "craft_rank", {"rank": 3}, 1],
	]
	for c in cases:
		var m := _make([_quest("t", [c[0]])])
		EventBus.objective_event.emit(c[1], c[2])
		_step(m)
		assert_eq(_progress(m)[0], c[3], "tipo " + str(c[1]))
	# filtro: un evento diverso non conta
	var m2 := _make([_quest("t", [{"type": "talk", "npc": "ilde"}])])
	EventBus.objective_event.emit("talk", {"npc": "gunilde"})
	_step(m2)
	assert_eq(_progress(m2), [0])


func test_stella() -> void:
	var m := _make([_quest("t", [{"type": "star", "skill": "any", "qty": 1}])])
	EventBus.star_gained.emit("mining")
	_step(m)
	assert_true(m.q.is_ready("t"))


func test_conteggio_parte_da_zero_all_accettazione() -> void:
	# R-QU-1: gli eventi prima dell'accettazione non contano
	var m := _make([_quest("a", [{"type": "kill_any", "qty": 1}]), _quest("b", [{"type": "kill_any", "qty": 1}], {"gold": 1}, [], ["a"])])
	EventBus.monster_killed.emit("mud_slime", [])
	_step(m)
	assert_true(m.q.claim("a"))
	assert_true(m.q.is_active("b"))
	assert_eq(m.q.progress_of("b"), [0])


# ------------------------------------------------------------------ ricompense e sblocchi

func test_claim_ricompense() -> void:
	var m := _make([_quest("t", [{"type": "kill_any", "qty": 1}],
		{"gold": 50, "items": [{"item": "crate_millbrook", "qty": 1}, {"item": "key_t1", "qty": 2}], "xp_tome": {"skill": "hero", "size": "medium"}},
		["skill:hero", "feature:wardrobe"])])
	assert_false(m.q.claim("t"), "non è pronta")
	EventBus.monster_killed.emit("mud_slime", [])
	_step(m)
	var events: Array = []
	var cb := func(qid: String) -> void: events.append(qid)
	EventBus.quest_completed.connect(cb)
	assert_true(m.q.claim("t"))
	EventBus.quest_completed.disconnect(cb)
	assert_eq(events, ["t"])
	assert_eq(m.bank.gold_total, 50)
	assert_eq(m.crates.granted.get("crate_millbrook", 0), 1, "le casse vanno a crates.grant_crate")
	assert_eq(m.bank.count("key_t1"), 2)
	assert_eq(m.bank.count("tome_xp_medium"), 1)
	assert_true(m.u.has("skill:hero") and m.u.has("feature:wardrobe"))
	assert_true(m.q.is_done("t"))
	assert_false(m.q.claim("t"), "una sola volta")


func test_sblocchi_a_tempo_servono_subito_il_resto_alla_consegna() -> void:
	var m := _make([_quest("t", [{"type": "gather", "item": "log_pine", "qty": 1}], {"gold": 1}, ["skill:woodcutting", "skill:mining"])])
	assert_true(m.u.has("skill:woodcutting"), "serve subito per svolgere la missione")
	assert_false(m.u.has("skill:mining"), "un sistema alla volta: arriva alla consegna")
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 1}])
	_step(m)
	m.q.claim("t")
	assert_true(m.u.has("skill:mining"))


func test_oggetto_dell_equip_dato_all_accettazione() -> void:
	var m := _make([_quest("t", [{"type": "equip", "item": "sword_copper"}], {"gold": 1, "items": [{"item": "sword_copper", "qty": 1}, {"item": "key_t1", "qty": 1}]}, ["feature:combat"])])
	assert_eq(m.bank.count("sword_copper"), 1, "senza spada la missione sarebbe impossibile")
	m.bank.instances["i_1"] = {"def": "sword_copper"}
	m.state.equipment["weapon"] = "i_1"
	_step(m, 12)
	m.q.claim("t")
	assert_eq(m.bank.count("sword_copper"), 1, "non raddoppia alla consegna")
	assert_eq(m.bank.count("key_t1"), 1)


func test_unlock_system() -> void:
	var m := _make([])
	var got: Array = []
	var cb := func(t: String) -> void: got.append(t)
	EventBus.unlocked.connect(cb)
	assert_true(m.u.grant("skill:fishing"))
	assert_false(m.u.grant("skill:fishing"), "idempotente")
	EventBus.unlocked.disconnect(cb)
	assert_eq(got, ["skill:fishing"])
	assert_true(m.u.has("skill:fishing"))
	assert_false(m.u.has("skill:mining"))
	assert_true(m.u.has(""), "token vuoto = sempre sbloccato")
	assert_true(m.state.unlocks.has("skill:fishing"), "stato = Array di token")
	assert_eq(m.q.take_tutorial(), "skill:fishing", "il primo sblocco accoda il tutorial")
	assert_eq(m.q.take_tutorial(), "")


func test_tutorial_di_tre_righe() -> void:
	for tok in ["skill:woodcutting", "skill:smithing", "feature:combat", "feature:crates", "feature:wardrobe", "feature:market", "feature:estate"]:
		var lines := UnlockSystem.tutorial_lines(tok, DataRegistry)
		assert_eq(lines.size(), 3, tok)
		for l in lines:
			assert_false(l.is_empty() or l.begins_with("UI_"), "riga tradotta per " + tok)
	assert_false(UnlockSystem.has_tutorial("zone:millbrook"))


func test_suggerimento_si_sblocca_con() -> void:
	var h := UnlockSystem.hint_for("skill:mining", DataRegistry)
	assert_false(h.is_empty() or h.begins_with("UI_"))
	assert_eq(UnlockSystem.quest_for_token("feature:crates", DataRegistry), "main_c0_q5")
	assert_eq(UnlockSystem.hint_for("feature:inesistente", DataRegistry), "")


# ------------------------------------------------------------------ persistenza e offline

func test_salvataggio_roundtrip() -> void:
	var qs := [_quest("t", [{"type": "kill_any", "qty": 5}])]
	var m := _make(qs)
	for i in 3:
		EventBus.monster_killed.emit("mud_slime", [])
	m.sim.collect_state(m.state)       # svuota la coda prima di salvare
	var json := JSON.stringify(m.state)
	var loaded: Dictionary = JSON.parse_string(json)
	var data := Fakes.FakeData.new()
	data.quests = qs
	var sim := Simulation.new()
	var q2 := QuestSystem.new()
	sim.setup(SystemContext.make(data, loaded, ModifierStack.new(), RngStreams.new(1), EventBus), [Fakes.FakeBank.new(), q2, UnlockSystem.new()])
	sim.bind_state(loaded)
	assert_eq(q2.progress_of("t"), [3])
	assert_true(q2.is_active("t"))


func test_offline_report() -> void:
	var m := _make([_quest("t", [{"type": "kill_any", "qty": 4}])])
	for i in 5:
		EventBus.monster_killed.emit("mud_slime", [])
	EventBus.item_gained.emit("log_pine", 7, "woodcutting")
	EventBus.xp_gained.emit("woodcutting", 120.0)
	EventBus.crate_found.emit("crate_millbrook", "mud_slime")
	EventBus.level_up.emit("woodcutting", 3)
	var rep: Dictionary = m.sim.run_offline(3600.0)
	assert_true(rep.has("quests"))
	assert_eq(rep.quests.progressed, ["t"])
	assert_eq(rep.quests.ready, ["t"])
	# (altri test lasciano il Deposito di Game.sim collegato al bus globale: la cassa di crate_found può comparire come oggetto)
	assert_eq(rep.quests["items"].get("log_pine"), 7)
	assert_eq(rep.quests["crates"], {"crate_millbrook": 1})
	assert_eq(rep.quests["levels"], {"woodcutting": [2, 3]})
	assert_almost_eq(float(rep.quests["xp"]["woodcutting"]), 120.0, 0.01)


func test_ordine_degli_eventi_con_altri_sistemi_offline() -> void:
	# gli eventi accodati prima (altri sistemi) sono applicati all'offline del sistema missioni
	var m := _make([_quest("t", [{"type": "gather", "item": "log_pine", "qty": 100}])])
	for i in 40:
		EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": 2}])
	m.sim.run_offline(600.0)
	assert_eq(_progress(m), [80])
