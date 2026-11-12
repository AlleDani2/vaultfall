extends GutTest
## COMBAT-3: la schermata Combattimento mostra postura, cibo, pericolo, avvisi del boss, reliquie, Prova e riepilogo,
## con e senza «riduci animazioni».

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_combat3_ui_%d" % Time.get_ticks_usec()
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


func _screen() -> GameScreen:
	var s: GameScreen = (load("res://src/ui/screens/CombatScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _new_hero(level: int) -> CombatSystem:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": level, "record_level": level, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "zone:saltreach", "zone:ironroot", "shop:auto_eat_3"])
	return Game.system("combat") as CombatSystem


func _feed(combat: CombatSystem) -> void:
	var bank := Game.system("bank") as BankSystem
	bank.add("food_bleak", 500, "test")
	combat.set_food(0, "food_bleak")


func test_cibo_pericolo_e_abilita_pronte() -> void:
	var combat := _new_hero(30)
	var cs := _screen()
	cs.open({})
	_feed(combat)
	assert_true(combat.start("saltreach", ""))
	for i in 80:
		Game.sim.tick(FixedStepClock.STEP)
	cs.refresh()
	assert_true(cs._food_lbl.text.contains("500") or cs._food_lbl.text.length() > 10, cs._food_lbl.text)
	assert_true(cs._thr_mark.visible, "segno bianco della soglia sulla barra della vita")
	assert_false(cs._danger_lbl.visible, "vita piena: nessun allarme")
	# vita bassa con cibo: allarme giallo; senza cibo: rosso
	combat.state["hp"] = combat.max_hp() * 0.1
	cs.refresh()
	assert_true(cs._danger_lbl.visible)
	assert_eq(cs._danger_state, "low")
	var bank0 := Game.system("bank") as BankSystem
	bank0.remove("food_bleak", bank0.count("food_bleak"))
	combat.state["hp"] = combat.max_hp() * 0.1
	cs.refresh()
	assert_eq(cs._danger_state, "critical")
	assert_true(cs._food_lbl.text.length() > 5)
	# tecniche: numero di priorità nel nome, «PRONTA» sul tempo di ricarica
	var equipped := combat.build.abilities_equipped()
	if not equipped.is_empty():
		var found_ready := false
		for ab in equipped:
			var slot: Dictionary = cs._slots.get(str(ab.id), {})
			assert_false(slot.is_empty())
			if (slot.cd_label as Label).text == tr("UI_C3_READY"):
				found_ready = true
		assert_true(found_ready or cs._abil_hint.text.length() > 0, "una tecnica pronta oppure il suggerimento «niente di pronto»")


func test_avvisi_del_boss_e_riepilogo_di_fine_scontro() -> void:
	var combat := _new_hero(60)
	var cs := _screen()
	cs.open({})
	_feed(combat)
	assert_true(combat.start("ironroot", "ironroot_golem"))
	for i in 30:
		Game.sim.tick(FixedStepClock.STEP)
	var e: Dictionary = GameState.data.activity.enemy
	assert_false(e.is_empty())
	cs.refresh()
	assert_false(cs._threat_lbl.visible, "il Colpo Devastante è ancora lontano")
	(e.t as Dictionary)["heavy_blow"] = 11.0          # mancano 4 s
	cs.refresh()
	assert_true(cs._threat_lbl.visible)
	assert_true(cs._threat_lbl.text.length() > 3, cs._threat_lbl.text)
	(e.t as Dictionary)["heavy_blow"] = 14.2          # manca meno di 1,5 s: allarme
	cs.refresh()
	assert_eq(cs._threat_pop, "heavy_blow")
	# uccidere il boss: riepilogo e striscione
	e["hp"] = 1.0
	for i in 400:
		Game.sim.tick(FixedStepClock.STEP)
		if int(GameState.data.stats.kills) > 0:
			break
	cs.refresh()
	assert_gt(int(GameState.data.stats.kills), 0)
	assert_ne(cs._summary_lbl.text, tr("UI_C3_SUMMARY_NONE"), "riepilogo dopo l'uccisione")
	assert_true(cs._banner.text.length() > 3, "striscione del boss a terra")
	assert_false(combat.last_fight().is_empty())


func test_postura_delle_ibride_e_testi_senza_segnaposto() -> void:
	var combat := _new_hero(60)
	var cs := _screen()
	cs.open({})
	cs.refresh()
	assert_false(cs._stance_lbl.visible, "un guerriero non ha postura")
	GameState.data.skills["hero"]["stars"] = 1
	(Game.system("bank") as BankSystem).add_gold(999999)
	var quests := Game.system("quests") as QuestSystem
	(quests.state.done as Array).append("class_spellblade")
	assert_true(combat.set_class("spellblade"), "Lama Arcana disponibile")
	cs.refresh()
	assert_true(cs._stance_lbl.visible)
	assert_false(cs._stance_lbl.text.contains("{"), cs._stance_lbl.text)
	for key in ["UI_C3_STANCE", "UI_C3_FOOD", "UI_C3_DANGER_LOW", "UI_C3_DANGER_CRITICAL", "UI_C3_THREAT_TIMER", "UI_C3_READY",
			"UI_C3_FIGHT_WON", "UI_C3_FIGHT_LOST", "UI_C3_RUN", "UI_C3_BOSS_DOWN", "UI_C3_TRIAL", "UI_C3_RELICS"]:
		assert_ne(tr(key), key, "stringa tradotta: " + key)


func test_prova_in_corso_e_reliquie_nella_schermata() -> void:
	var combat := _new_hero(30)
	var cs := _screen()
	cs.open({})
	cs.refresh()
	assert_false(cs._trial_lbl.visible)
	assert_false(cs._relic_lbl.visible)
	var pr := Game.system("prestige") as PrestigeSystem
	assert_not_null(pr)
	pr.state["trial_active"] = {"id": "trial_race", "tier": 1, "started_s": float(pr.state.clock_s), "era_restore": 1}
	cs.refresh()
	assert_true(cs._trial_lbl.visible)
	assert_true(cs._trial_lbl.text.length() > 10, cs._trial_lbl.text)
	var ts := combat.trial_status()
	assert_gt(float(ts.time_left_s), 0.0)
	assert_lte(float(ts.time_left_s), 60.0)
	pr.state["trial_active"] = {"id": "trial_fasting", "tier": 1, "started_s": float(pr.state.clock_s), "era_restore": 1}
	cs.refresh()
	assert_true(combat.trial_status().no_food)
	assert_true(combat.trial_food_blocked())
	pr.state["trial_active"] = {}
	cs.refresh()
	assert_false(cs._trial_lbl.visible)
	# reliquia equipaggiata
	var bank := Game.system("bank") as BankSystem
	var crates := Game.system("crates") as CrateSystem
	var uid := bank.add_instance({"def_id": "relic_frostspire_1", "kind": "relic", "rarity": "relic", "condition": "marked", "float": 0.4})
	assert_true(crates.equip_relic(uid))
	cs.refresh()
	assert_true(cs._relic_lbl.visible)
	assert_true(cs._relic_lbl.tooltip_text.length() > 20)
	crates.unequip_relic(uid)
	cs.refresh()
	assert_false(cs._relic_lbl.visible)


func test_gira_con_e_senza_animazioni_per_dungeon_e_riepilogo_corsa() -> void:
	var combat := _new_hero(40)
	GameState.data.unlocks.append("dungeon:cursed_granary")
	var cs := _screen()
	cs.open({})
	_feed(combat)
	assert_true(combat.start_dungeon("cursed_granary"))
	for reduce in [false, true]:
		Settings.set_value("reduce_motion", reduce)
		for i in 900:
			Game.sim.tick(FixedStepClock.STEP)
			if i % 3 == 0:
				cs.refresh()
		await wait_process_frames(2)
	var run := combat.run_summary()
	assert_false(run.is_empty())
	assert_gt(int(run.kills), 0)
	assert_gt(float(run.dealt), 0.0)
	var txt := CombatUi.run_text(run, "Prova")
	assert_false(txt.contains("{"), txt)
	combat.stop()
	cs.refresh()
