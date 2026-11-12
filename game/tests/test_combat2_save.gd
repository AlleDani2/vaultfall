extends GutTest
## M7 (COMBAT-2): il salvataggio conserva classe, specializzazione, talenti, tecniche, risorse, pozione, dungeon, taglie;
## i salvataggi di M3 (senza i campi nuovi) si caricano senza errori.

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_combat2_save_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func test_partita_completa_salvata_e_ricaricata() -> void:
	assert_true(Game.new_game(1, "normal", 77))
	var combat := Game.system("combat") as CombatSystem
	var bank := Game.system("bank") as BankSystem
	# stelle a 0: il bonus delle Stelle (fonte "star:hero", PrestigeSystem) si registra solo al caricamento e
	# falserebbe il confronto delle statistiche prima/dopo
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 40, "record_level": 40, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.skills["bounty"] = {"xp": 0.0, "level": 5, "record_level": 5, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "dungeon:cursed_granary", "class:beastmaster", "zone:saltreach"])
	GameState.data.currencies.gold = 1000000
	assert_true(combat.set_class("ranger"))
	assert_true(combat.build.set_spec("beastmaster"))
	for i in 3:
		assert_true(combat.build.rank_up("ranger_toughness"))
	assert_true(combat.build.rank_up("bea_pet"))
	assert_true(combat.build.set_slot(0, "call_companion"))
	bank.add("potion_fury_1", 2, "test")
	assert_true(combat.use_potion("potion_fury_1"))
	combat.state.dungeon_clears["cursed_granary"] = 12
	combat._apply_dungeon_milestones()
	var bounty := Game.system("bounty") as BountySystem
	bounty.offers()
	assert_true(bounty.accept(1))
	combat.state.rt["res"] = 55.0
	var before := combat.hero_stats()
	var ab_before: Array = combat.build.abilities_equipped().map(func(x: Dictionary) -> String: return str(x.id))
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	combat = Game.system("combat") as CombatSystem
	bounty = Game.system("bounty") as BountySystem
	assert_eq(combat.state.class, "ranger")
	assert_eq(combat.state.spec, "beastmaster")
	assert_eq(combat.build.rank("ranger_toughness"), 3)
	assert_eq(typeof(combat.state.talents["bea_pet"]), TYPE_INT, "i ranghi tornano interi")
	assert_eq(typeof(combat.state.dungeon_clears["cursed_granary"]), TYPE_INT)
	assert_eq(combat.build.abilities_equipped().map(func(x: Dictionary) -> String: return str(x.id)), ab_before)
	assert_almost_eq(float(combat.state.rt.res), 55.0, 1e-6)
	assert_false(combat.state.potion.is_empty())
	assert_true(Modifiers.stack.has_source("talents"), "i talenti ri-registrano i modificatori")
	assert_true(Modifiers.stack.has_source(CombatSystem.POTION_SOURCE))
	assert_true(Modifiers.stack.has_source("dungeon:cursed_granary"), "traguardo da 10 completamenti")
	var after := combat.hero_stats()
	for key in ["hp", "max_hit", "interval", "crit", "acc", "eva", "arm", "ward"]:
		assert_almost_eq(float(after[key]), float(before[key]), absf(float(before[key])) * 1e-9 + 1e-9, key)
	assert_true(bounty.has_active())
	assert_eq(bounty.offers().size(), 3)
	# si può continuare a giocare dal salvataggio
	assert_true(combat.start_dungeon("cursed_granary"))
	for i in 600:
		Game.sim.tick(FixedStepClock.STEP)
	assert_true(Game.system("combat").in_combat() or int(combat.state.deaths) > 0)


func test_salvataggio_a_meta_scontro() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var combat := Game.system("combat") as CombatSystem
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 30, "record_level": 30, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "dungeon:cursed_granary"])
	assert_true(combat.start_dungeon("cursed_granary"))
	for i in 150:
		Game.sim.tick(FixedStepClock.STEP)
	var wave: int = int(GameState.data.activity.get("wave", 0))
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	combat = Game.system("combat") as CombatSystem
	assert_true(combat.in_dungeon())
	assert_eq(int(GameState.data.activity.get("wave", -1)), wave)
	for i in 300:
		Game.sim.tick(FixedStepClock.STEP)
	assert_gte(int(GameState.data.stats.kills), 1)


func test_salvataggio_vecchio_senza_campi_nuovi() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var combat := Game.system("combat") as CombatSystem
	# sezione `hero` e nemico come li scriveva M3
	GameState.data["hero"] = {"class": "ranger", "spec": "", "attrs": {}, "talents": {}, "abilities": [], "food": ["", "", ""], "hp": 50.0,
		"kills": {"mud_slime": 3}, "wounded_s": 0.0, "auto_alloc": true, "eat_pct": 0, "class_cd_s": 0.0, "deaths": 0}
	GameState.data["activity"] = {"type": "combat", "zone": "millbrook", "monster": "", "respawn_s": 0.0, "hero_cd": 1.0, "mon_cd": 1.0,
		"revive_s": 0.0, "enemy": {"id": "mud_slime", "hp": 10.0, "t": {}, "shield_s": 0.0, "poison_s": 0.0}}
	Game.sim.bind_state(GameState.data)
	combat = Game.system("combat") as CombatSystem
	assert_eq(combat.state.class, "ranger")
	assert_true(combat.state.has("rt") and combat.state.has("dungeon_clears") and combat.state.has("potion"))
	assert_true((GameState.data.activity.enemy as Dictionary).is_empty(), "il nemico vecchio viene scartato e ricompare")
	assert_eq(GameState.data.activity.mode, "zone")
	for i in 200:
		Game.sim.tick(FixedStepClock.STEP)
	assert_true(true)
