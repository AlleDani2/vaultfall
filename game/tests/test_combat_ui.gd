extends GutTest
## Le schermate Combattimento ed Eroe si aprono, si aggiornano mentre la simulazione gira e reggono "riduci animazioni".

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_combat_ui_%d" % Time.get_ticks_usec()
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


func test_registro_e_schermate() -> void:
	assert_true(ScreenRegistry.is_available(ScreenRegistry.get_entry("combat"), ["feature:combat"]))
	assert_true(ScreenRegistry.is_available(ScreenRegistry.get_entry("hero"), ["skill:hero"]))
	assert_not_null(Game.system("combat") if Game.sim.get_system("combat") != null else null, "sistema registrato")


func test_combattimento_e_eroe_in_esecuzione() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var combat := Game.system("combat") as CombatSystem
	var cs := _screen("res://src/ui/screens/CombatScreen.tscn")
	var hs := _screen("res://src/ui/screens/HeroScreen.tscn")
	cs.open({})
	hs.open({})
	await wait_process_frames(2)
	assert_true(combat.start("millbrook", "mud_slime"))
	for reduce in [false, true]:
		Settings.set_value("reduce_motion", reduce)
		for i in 400:
			Game.sim.tick(FixedStepClock.STEP)
			if i % 3 == 0:
				cs.refresh()
				hs.refresh()
		await wait_process_frames(2)
	assert_gt(combat.kills_of("mud_slime"), 0, "qualche uccisione avvenuta")
	combat.stop()
	cs.refresh()
	assert_false(combat.in_combat())
