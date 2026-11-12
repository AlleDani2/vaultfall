extends GutTest
## RAIDS: la schermata Dungeon con le schede Incursioni, Boss mondiali e La Breccia (partita vera): si aprono, si
## aggiornano mentre la simulazione gira (anche con "riduci animazioni"), comandano i sistemi e mostrano ricompense.

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_raids_ui_%d" % Time.get_ticks_usec()
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


func _hero(level: int) -> CombatSystem:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": level, "record_level": level, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "raid:collectors_den", "feature:world_bosses", "feature:rift"])
	return Game.system("combat") as CombatSystem


func _screen() -> GameScreen:
	var s: GameScreen = (load("res://src/ui/screens/DungeonScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func test_le_quattro_schede_si_aprono() -> void:
	_hero(60)
	var ds := _screen()
	ds.open({})
	await wait_process_frames(2)
	for tab in ["raids", "worldboss", "rift", "dungeon"]:
		ds._set_tab(tab)
		ds.refresh()
		await wait_process_frames(1)
	assert_true(ds._panels.has("raids") and ds._panels.has("worldboss") and ds._panels.has("rift"))
	ds.open({"tab": "rift"})
	assert_eq(ds._tab, "rift", "il parametro tab apre la scheda indicata")


func test_scheda_incursioni_squadra_rischio_e_avvio() -> void:
	var combat := _hero(60)
	var ds := _screen()
	ds.open({"tab": "raids"})
	await wait_process_frames(2)
	var panel: RaidPanel = ds._panels["raids"]
	# un po' di mercenari nella Taverna
	var m := Game.system("mercenaries") as MercenarySystem
	assert_not_null(m)
	for role in ["defender", "healer", "striker"]:
		m.state.seq = int(m.state.seq) + 1
		(m.state.roster as Array).append({"uid": "m_t%d" % int(m.state.seq), "name": "Prova", "role": role, "rarity": "epic", "level": 40,
			"xp": 0.0, "traits": [], "equip_tier": 0, "injured_until": 0.0, "busy": ""})
	panel._party_sig = ""
	panel._sig = ""
	panel.refresh()
	panel._on_auto()
	assert_eq(panel._party_choice().size(), 3, "scelta automatica della squadra")
	assert_true(panel._risk.text.length() > 0, "indicatore di rischio visibile")
	assert_true(panel._power_label.text.length() > 0)
	panel._on_start()
	assert_eq(combat.endgame_mode(), "raid")
	for reduce in [false, true]:
		Settings.set_value("reduce_motion", reduce)
		for i in 40:
			Game.sim.tick(FixedStepClock.STEP)
		ds.refresh()
		await wait_process_frames(1)
	assert_true(panel._run_box.visible)
	panel._stop_btn.pressed.emit()
	assert_false(combat.in_combat())


func test_scheda_boss_mondiali_finestra_e_corno() -> void:
	var combat := _hero(70)
	var ds := _screen()
	ds.open({"tab": "worldboss"})
	await wait_process_frames(2)
	var panel: WorldBossPanel = ds._panels["worldboss"]
	assert_string_contains(panel._status.text, "4", "mostra quando arriva il prossimo")
	combat.state.wb["t"] = 4.0 * 3600.0 + 5.0
	panel.refresh()
	assert_false(panel._go_rot.disabled, "finestra aperta: si può attaccare")
	panel._enter("rotation")
	assert_eq(combat.endgame_mode(), "wboss")
	for i in 100:
		Game.sim.tick(FixedStepClock.STEP)
	panel.refresh()
	assert_true(panel._run_box.visible)
	assert_true(panel._run_contrib.text.length() > 0)
	panel._stop_btn.pressed.emit()
	assert_false(combat.in_combat())
	var bank := Game.system("bank") as BankSystem
	bank.add("rally_horn", 1, "test")
	panel._selected = "star_titan"
	panel._on_summon()
	assert_eq(str(combat.eg.wb_horn().boss), "star_titan")


func test_scheda_breccia_ripartenze_e_negozio() -> void:
	var combat := _hero(100)
	var ds := _screen()
	ds.open({"tab": "rift"})
	await wait_process_frames(2)
	var panel: RiftPanel = ds._panels["rift"]
	assert_eq(panel._start_ids, [1])
	panel._on_enter()
	assert_eq(combat.endgame_mode(), "rift")
	for i in 30:
		Game.sim.tick(FixedStepClock.STEP)
	panel.refresh()
	assert_true(panel._run_box.visible)
	assert_true(panel._shop.get_child_count() > 1, "negozio del Bazar della Breccia")
	panel._stop_btn.pressed.emit()
	assert_false(combat.in_combat())


func test_registro_del_dungeon_e_testi_bilingui() -> void:
	for key in ["UI_RAID_TAB_RAIDS", "UI_RAID_TITLE", "UI_RAID_WB_TITLE", "UI_RAID_RIFT_TITLE", "UI_RAID_RISK_RED", "UI_RAID_TIER_PLATINUM"]:
		for loc in ["it", "en"]:
			TranslationServer.set_locale(loc)
			assert_ne(TranslationServer.translate(key), key, "%s manca in %s" % [key, loc])
	TranslationServer.set_locale("it")
