extends GutTest
## M7 (COMBAT-2): le schermate Combattimento, Eroe, Talenti, Dungeon e Taglie si aprono, si aggiornano mentre la
## simulazione gira (anche con "riduci animazioni") e comandano i sistemi giusti.

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_combat2_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("reduce_motion", false)


func _screen(path: String) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _new_hero(level: int) -> CombatSystem:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": level, "record_level": level, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.skills["bounty"] = {"xp": 0.0, "level": 5, "record_level": 5, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "dungeon:cursed_granary", "zone:saltreach", "feature:talents", "feature:bounties", "skill:hero"])
	return Game.system("combat") as CombatSystem


func test_registro_delle_nuove_schermate() -> void:
	var tok := {"talents": "feature:talents", "dungeon": "dungeon:cursed_granary", "bounty": "feature:bounties"}      # token propri (QA1)
	for id in ["talents", "dungeon", "bounty"]:
		var e := ScreenRegistry.get_entry(id)
		assert_false(e.is_empty(), id)
		assert_true(ScreenRegistry.is_available(e, [tok[id]]), id)
		assert_false(ScreenRegistry.is_available(e, ["feature:combat"]), id + " non si apre col solo Combattimento")
		assert_false(ScreenRegistry.is_available(e, []), id + " bloccata senza combattimento")


func test_tutte_le_schermate_girano_con_e_senza_animazioni() -> void:
	var combat := _new_hero(30)
	var cs := _screen("res://src/ui/screens/CombatScreen.tscn")
	var hs := _screen("res://src/ui/screens/HeroScreen.tscn")
	var ts := _screen("res://src/ui/screens/TalentScreen.tscn")
	var ds := _screen("res://src/ui/screens/DungeonScreen.tscn")
	var bs := _screen("res://src/ui/screens/BountyScreen.tscn")
	for s in [cs, hs, ts, ds, bs]:
		s.open({})
	await wait_process_frames(2)
	# talenti: spendere punti dalla schermata
	assert_true(combat.build.points_free() > 0)
	ts._on_node("warrior_toughness")
	assert_eq(combat.build.rank("warrior_toughness"), 1)
	# taglie: accettare dalla bacheca
	var bounty := Game.system("bounty") as BountySystem
	assert_eq(bounty.offers().size(), 3)
	assert_true(bounty.accept(0))
	bs.refresh()
	# dungeon: entrare e combattere
	ds._selected = "cursed_granary"
	ds._on_enter()
	assert_true(combat.in_dungeon())
	for reduce in [false, true]:
		Settings.set_value("reduce_motion", reduce)
		for i in 500:
			Game.sim.tick(FixedStepClock.STEP)
			if i % 3 == 0:
				for s in [cs, hs, ts, ds, bs]:
					s.refresh()
		await wait_process_frames(2)
	assert_gt(int(GameState.data.stats.kills), 0, "qualche uccisione nel dungeon")
	combat.stop()
	for s in [cs, hs, ts, ds, bs]:
		s.refresh()
	assert_false(combat.in_combat())


func test_eroe_cambia_classe_specializzazione_e_tecniche_dalla_schermata() -> void:
	var combat := _new_hero(8)
	var hs := _screen("res://src/ui/screens/HeroScreen.tscn")
	hs.open({})
	await wait_process_frames(2)
	assert_eq(hs._class_ids.size(), 6, "3 classi base + 3 ibride nel selettore")
	hs._on_class_selected(hs._class_ids.find("ranger"))
	assert_eq(combat.state.class, "ranger")
	assert_eq(hs._spec_opt.item_count, 3, "nessuna + 2 specializzazioni")
	assert_true(hs._spec_opt.is_item_disabled(1), "specializzazione bloccata a livello 8")
	GameState.data.skills["hero"].level = 10
	hs._on_slot_selected(1, 0)       # prima tecnica disponibile nello slot 0 (passa alla scelta manuale)
	assert_false(combat.state.auto_abilities)
	assert_eq(combat.build.abilities_equipped().size(), 0, "senza arco niente tecniche di classe")
	hs._auto_abil.set_pressed(true)
	assert_true(combat.state.auto_abilities)


func test_dungeon_screen_mostra_blocco_e_rischio() -> void:
	var combat := _new_hero(5)
	var ds := _screen("res://src/ui/screens/DungeonScreen.tscn")
	ds.open({"dungeon": "cursed_granary"})
	await wait_process_frames(2)
	assert_false(combat.dungeon_unlocked("cursed_granary"), "livello troppo basso")
	assert_true(ds._enter_btn.disabled)
	GameState.data.skills["hero"].level = 20
	ds.refresh()
	assert_false(ds._enter_btn.disabled)
	assert_true(["green", "yellow", "red"].has(combat.dungeon_risk("cursed_granary").level))
