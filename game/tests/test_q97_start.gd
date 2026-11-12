extends GutTest
## Q97 - primo combattimento (QA82: l'eroe nudo moriva 10-11 volte in 10 minuti):
##  N1  protezione del novizio: attesa e Ferito ridotti fino al livello `novice.until_level`, normali dopo
##  N2  `readiness()`: dice cosa manca (arma, armatura, cibo) e non blocca il combattimento
##  N3  la divisa di rame arriva con la missione che precede il Combattimento (dati)

const Fx := preload("res://tests/helpers/sim_fixtures.gd")

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_q97_saves"
	SaveService.autosave_enabled = false


func after_all() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in [1, 2, 3]:
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _new(seed_v: int) -> CombatSystem:
	assert_true(Game.new_game(1, "normal", seed_v), "nuova partita")
	return Game.system("combat") as CombatSystem


func test_n1_novizio_morte_a_basso_livello_costa_poco() -> void:
	var cb := _new(9701)
	var nov: Dictionary = Formulas.k().combat.rules.novice
	var rules: Dictionary = Formulas.k().combat.rules
	assert_eq(cb.death_delay_s(), float(nov.restart_delay_s), "livello 1: attesa ridotta")
	assert_eq(cb.wounded_duration_s(), float(nov.wounded_duration_s), "livello 1: Ferito ridotto")
	assert_lt(float(nov.wounded_duration_s), float(rules.death_wounded_duration_s), "il Ferito del novizio e' piu' breve")
	(Game.system("skills") as SkillSystem).state["hero"]["level"] = int(nov.until_level) + 1
	assert_eq(cb.death_delay_s(), float(rules.death_restart_delay_s), "oltre il livello: attesa normale")
	assert_eq(cb.wounded_duration_s(), float(rules.death_wounded_duration_s), "oltre il livello: Ferito normale")


func test_n1_eroe_nudo_muore_ma_si_rialza_presto() -> void:
	var cb := _new(9702)
	cb.set_class("warrior")
	assert_true(cb.start("millbrook", ""), "il combattimento parte (nessun blocco)")
	var nov: Dictionary = Formulas.k().combat.rules.novice
	var d0 := int(cb.state.deaths)
	var i := 0
	while int(cb.state.deaths) == d0 and i < 6000:
		Game._on_step(0.1)
		i += 1
	assert_gt(int(cb.state.deaths), d0, "senza equipaggiamento prima o poi cade")
	var act: Dictionary = GameState.data.get("activity", {})
	assert_true(float(act.get("revive_s", 99.0)) <= float(nov.restart_delay_s), "si rialza entro l'attesa del novizio")
	for k in int(float(nov.restart_delay_s) * 10.0) + 5:
		Game._on_step(0.1)
	assert_true(float(cb.state.wounded_s) <= float(nov.wounded_duration_s), "Ferito non oltre la durata del novizio")


func test_n2_readiness_dice_cosa_manca() -> void:
	var cb := _new(9703)
	var r: Dictionary = cb.readiness()
	assert_true(bool(r.unprepared), "appena creato: impreparato")
	assert_true((r.missing as Array).has("weapon") and (r.missing as Array).has("armor") and (r.missing as Array).has("food"),
		"manca tutto: %s" % str(r.missing))
	var bank := Game.system("bank") as BankSystem
	for gid in Fx.gear_ids("warrior", 1):
		var uid: String = bank.add_instance({"def": gid, "quality": "normal", "sockets": [], "rank": 0})
		cb.equip(uid)
	r = cb.readiness()
	assert_true(bool(r.weapon) and int(r.armor_n) >= 4, "arma e armatura indossate")
	assert_eq(r.missing, ["food"], "resta solo il cibo")
	bank.add("food_bleak", 5, "test")
	cb.set_food(0, "food_bleak")
	r = cb.readiness()
	assert_false(bool(r.unprepared), "equipaggiato e con cibo: pronto")


func test_n3_divisa_di_rame_nella_missione_prima_del_combattimento() -> void:
	var q3: Dictionary = DataRegistry.get_def("quests", "main_c0_q3")
	var ids := []
	for it in q3.rewards.get("items", []):
		ids.append(str(it.item))
	for slot in ["helm", "body", "legs", "gloves", "boots"]:
		assert_true(ids.has("plate_%s_copper" % slot), "ricompensa: " + slot)
	var q4: Dictionary = DataRegistry.get_def("quests", "main_c0_q4")
	assert_true((q4.unlocks as Array).has("feature:combat"), "il Combattimento si apre con la missione 4")
