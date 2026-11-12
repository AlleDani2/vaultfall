extends GutTest
## Giardino (FarmScreen) e pannello coda/pozioni dentro SkillScreen (SkillExtras).

const FARM := "res://src/ui/screens/FarmScreen.tscn"
const SKILL := "res://src/ui/screens/SkillScreen.tscn"

var _old_dir: String
var _old_reduce: bool


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_skills2_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_reduce = Settings.get_value("reduce_motion")
	Settings.set_value("reduce_motion", false)
	# test_crates_ui lascia il Deposito vero fuori dall'indice dei sistemi (Game.sim._by_id.erase("bank")): lo rimetto
	if Game.sim.get_system("bank") == null:
		for sys in Game.sim.systems:
			if sys.id == "bank":
				Game.sim._by_id["bank"] = sys
	assert_true(Game.new_game(1, "normal", 9))


func after_each() -> void:
	Settings.set_value("reduce_motion", _old_reduce)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String, params: Dictionary) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open(params)
	return s


func _cards(s: Node, kind: String) -> int:
	var n := 0
	for c in s.find_children("*", "PanelContainer", true, false):
		n += 1 if (c as Control).get_parent() is HFlowContainer else 0     # a capo (QA overflow 107)
	return n if kind == "" else n


func test_registro_coltivazione_usa_il_giardino() -> void:
	var e := ScreenRegistry.get_entry("skill:farming")
	assert_eq(e.scene, FARM)
	assert_eq(ScreenRegistry.get_entry("skill:mining").scene, ScreenRegistry.SKILL_SCENE, "le altre mansioni restano sulla scena unica")
	assert_true(ScreenRegistry.is_available(e, ["skill:farming"]))


func test_giardino_mostra_orto_e_frutteto() -> void:
	var s := _open(FARM, {"skill": "farming"})
	await wait_process_frames(1)
	assert_eq(_cards(s, ""), 6, "4 appezzamenti dell'orto + 2 del frutteto")
	s.refresh()


func test_giardino_semina_e_raccolta_rapida() -> void:
	var bank: Object = Game.system("bank")
	bank.add("seed_potato", 6, "test")
	var farm := Game.system("farming") as FarmingSystem
	var s := _open(FARM, {"skill": "farming"})
	await wait_process_frames(1)
	s.refresh()
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text == "UI_FARM_PLANT_ALL":
			(b as Button).pressed.emit()
	assert_eq(farm.ready_count(), 0)
	for i in 4:
		assert_eq(str(farm.plot("garden", i).crop), "farm_potato", "semina ovunque")
	Game.system("farming").tick(700.0)
	s.refresh()
	assert_eq(farm.ready_count(), 4)
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text == "UI_FARM_HARVEST_ALL":
			assert_false((b as Button).disabled)
			(b as Button).pressed.emit()
	assert_eq(farm.ready_count(), 0)
	assert_gte(int(bank.count("crop_potato")), 20)


func test_giardino_acquisto_appezzamento() -> void:
	var bank: Object = Game.system("bank")
	bank.add_gold(6000)
	var farm := Game.system("farming") as FarmingSystem
	var s := _open(FARM, {"skill": "farming"})
	await wait_process_frames(1)
	s.refresh()
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Compra un altro") or (b as Button).text.begins_with("Buy another"):
			if not (b as Button).disabled:
				(b as Button).pressed.emit()
				break
	assert_eq(farm.plot_count("garden"), 5)


func test_pannello_coda_dentro_la_mansione() -> void:
	var s := _open(SKILL, {"skill": "smithing"})
	await wait_process_frames(1)
	var ex: SkillExtras = s.get("_extras")
	assert_not_null(ex, "il pannello c'e'")
	ex._toggle.button_pressed = true
	s.refresh()
	ex.refresh()
	assert_true(ex._locked_l.visible, "senza Emporio nessuna coda")


func test_pannello_aggiunge_voce_e_beve_pozione() -> void:
	var bank: Object = Game.system("bank")
	GameState.data.get("unlocks", []).append("skill:woodcutting")
	Modifiers.set_source("shop:test_ui", [{"key": "action_queue_slots", "value": 3, "mode": "add"}])
	var s := _open(SKILL, {"skill": "woodcutting"})
	await wait_process_frames(1)
	var ex: SkillExtras = s.get("_extras")
	ex._toggle.button_pressed = true
	ex.refresh()
	assert_false(ex._locked_l.visible)
	ex._on_add()
	assert_eq((Game.system("queue") as QueueSystem).size(), 1)
	bank.add("potion_gatherer_1", 1, "test")
	ex._counter = 0
	ex.refresh()
	assert_true(ex._drink_btn.visible)
	ex._on_drink()
	assert_eq((Game.system("potions") as PotionSystem).charges("gathering"), 250)
	Modifiers.clear_source("shop:test_ui")
