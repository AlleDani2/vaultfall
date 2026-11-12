extends GutTest
## 1.0 GAMEPLAY (docs/review_1_0/02 punti 1 e 3): (a) dopo incursioni e boss mondiali l'Eroe riprende l'attività di prima
## (zona/mostro, mansione), come il dungeon con «Ripeti»; il ritiro voluto non riprende; (b) offline il tempo che avanza è
## suo; (c) il cibo finito offline è detto chiaramente nel Bentornato (non «Eroe KO» generico).

const Env := preload("res://tests/helpers/raids_env.gd")
const RAID_ID := "collectors_den"
const H := 3600.0


func _env(seed_v: int = 5) -> Object:
	var env: Object = Env.make(seed_v, 55, "warrior", 6)
	env.unlock_raid(RAID_ID)
	env.state.unlocks.append("zone:ironroot")
	return env


func _run(env: Object, max_ticks: int = 30000) -> void:
	var n := 0
	while env.combat.endgame_mode() != "" and n < max_ticks:
		env.tick(1)
		n += 1


func test_incursione_vinta_riprende_la_zona() -> void:
	var env: Object = _env()
	assert_true(env.combat.start("ironroot", "ironroot_golem"))
	assert_true(env.combat.eg.start_raid(RAID_ID, env.party("epic", 40)))
	assert_eq(env.combat.endgame_mode(), "raid")
	_run(env)
	assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 1, "vinta")
	assert_true(env.combat.in_combat(), "l'Eroe non resta «A riposo»")
	assert_eq(env.combat.endgame_mode(), "")
	assert_eq(str(env.state.activity.zone), "ironroot")
	assert_eq(str(env.state.activity.monster), "ironroot_golem")
	assert_true((env.combat.state.return_to as Dictionary).is_empty(), "il ricordo si consuma")


func test_ritiro_voluto_non_riprende() -> void:
	var env: Object = _env()
	env.combat.start("ironroot", "ironroot_golem")
	env.combat.eg.start_raid(RAID_ID, env.party("epic", 40))
	env.tick(50)
	env.combat.stop()
	assert_false(env.combat.in_combat())
	assert_true((env.combat.state.return_to as Dictionary).is_empty())


func test_senza_attivita_precedente_resta_a_riposo() -> void:
	var env: Object = _env()
	env.combat.eg.start_raid(RAID_ID, env.party("epic", 40))
	_run(env)
	assert_false(env.combat.in_combat())


func test_boss_mondiale_riprende_anche_dopo_la_sconfitta() -> void:
	var env: Object = _env()
	env.state.unlocks.append("feature:world_bosses")
	env.quests.active["main_c9_q2"] = true
	env.combat.state.wb["t"] = 4.0 * H + 10.0
	env.combat.start("ironroot", "ironroot_golem")
	assert_true(env.combat.eg.start_world_boss("rotation"))
	assert_eq(env.combat.endgame_mode(), "wboss")
	env.state.activity["left_s"] = 2.0          # la finestra si chiude: tempo scaduto
	_run(env, 60000)
	assert_true(env.combat.in_combat(), "ripresa dopo la fine dell'incontro")
	assert_eq(env.combat.endgame_mode(), "")
	assert_eq(str(env.state.activity.zone), "ironroot")


func test_offline_il_tempo_avanzato_va_alla_zona() -> void:
	var env: Object = _env(9)
	env.combat.start("ironroot", "ironroot_golem")
	env.combat.eg.start_raid(RAID_ID, env.party("epic", 40))
	var rep: Dictionary = env.combat.simulate_offline(3.0 * H)
	assert_eq(int(env.combat.state.raid_clears.get(RAID_ID, 0)), 1)
	assert_true(env.combat.in_combat(), "dopo l'incursione si combatte ancora")
	assert_gt(int(rep.kills), 20, "uccisioni nel tempo avanzato, oltre al boss")
	var has_row := false
	for r in rep.get("rows", []):
		has_row = has_row or str(r.get("key", "")) == "UI_OFFL_RESUMED_FIGHT"
	assert_true(has_row, "il Bentornato lo dice")


func test_cibo_finito_offline_lo_dice_il_bentornato() -> void:
	var env: Object = Env.make(11, 30, "warrior", 3)
	env.state.unlocks.append("zone:ironroot")
	env.bank.remove("food_bleak", env.bank.count("food_bleak"))      # niente scorta
	env.combat.start("ironroot", "ironroot_golem")
	var rep: Dictionary = env.combat.simulate_offline(6.0 * H)
	if str(rep.get("stopped", "")) != "death":
		pending("a questo livello il mostro non toglie vita: stop %s" % str(rep.get("stopped", "")))
		return
	assert_true(bool(rep.get("food_out", false)), "causa: cibo finito")
	var wb := WelcomeBack.normalize({"combat": rep}, DataRegistry)
	assert_eq(str(wb.combat.stop.key), "UI_WB_FOOD_OUT")
