extends GutTest
## Sabbia del Custode (UI F13): dove NON si può usare. Nessun avanzamento, motivo giusto, riserva intatta.
## v1: solo mansioni (e coda). Combattimento in zona, dungeon, incursioni, Breccia, boss mondiali, Prove, coop, modalità Estrema: no.

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_time_push_blocked_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _game(mode: String = "normal") -> TimePushSystem:
	assert_true(Game.new_game(1, mode, 77))
	var tp := Game.system("time_push") as TimePushSystem
	(Game.system("unlock") as UnlockSystem).grant(str(DataRegistry.constants.time_push.unlock_token))
	tp.state["gift_given"] = true
	tp.state["reserve_s"] = 50.0
	return tp


func _skill() -> void:
	GameState.data.unlocks.append("skill:woodcutting")
	var sk := Game.system("skills") as SkillSystem
	for a in DataRegistry.actions_for_skill("woodcutting"):
		if int(a.get("level_req", 1)) <= 1 and sk.start(str(a.id)):
			return


func _expect_blocked(tp: TimePushSystem, reason: String, what: String) -> void:
	var heard := []
	var cb := func(r: String) -> void: heard.append(r)
	EventBus.push_blocked.connect(cb)
	var xp0 := float(GameState.data.skills.woodcutting.xp)
	var res := Game.debug_push(5)
	var steps := tp.drain(100)
	EventBus.push_blocked.disconnect(cb)
	assert_false(bool(res.ok), what)
	assert_eq(str(res.reason), reason, what)
	assert_eq(heard, [reason], what + ": segnale push_blocked")
	assert_eq(steps, 0, what + ": nessun passo")
	assert_almost_eq(tp.reserve_s(), 50.0, 1e-9, what + ": riserva intatta")
	assert_almost_eq(float(GameState.data.skills.woodcutting.xp), xp0, 1e-9, what)


func test_nessuna_azione() -> void:
	var tp := _game()
	GameState.data["activity"].clear()
	_expect_blocked(tp, "UI_PUSH_REASON_NONE", "nessuna azione")


func test_attivita_non_ammesse() -> void:
	var tp := _game()
	var cases := {
		"zone": "combattimento in zona (v1)", "dungeon": "dungeon", "raid": "incursione", "rift": "Breccia", "wboss": "boss mondiale",
		"coop_week": "coop"}
	for mode in cases:
		GameState.data["activity"].clear()
		GameState.data["activity"].merge({"type": "combat", "mode": mode})
		_expect_blocked(tp, "UI_PUSH_REASON_ACT", str(cases[mode]))


func test_prova_del_custode() -> void:
	var tp := _game()
	_skill()
	(Game.system("prestige") as PrestigeSystem).state["trial_active"] = {"id": "trial_race", "tier": 1, "started_s": 0.0, "era_restore": 1, "engaged": false}
	_expect_blocked(tp, "UI_PUSH_REASON_TRIAL", "Prova")
	(Game.system("prestige") as PrestigeSystem).state["trial_active"] = {}
	assert_eq(tp.block_reason(), "", "finita la Prova la Sabbia torna disponibile")


func test_modalita_estrema() -> void:
	var tp := _game("extreme")
	_skill()
	_expect_blocked(tp, "UI_PUSH_REASON_EXTREME", "modalita' Estrema")


func test_non_sbloccata() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var tp := Game.system("time_push") as TimePushSystem
	_skill()
	tp.state["reserve_s"] = 50.0
	var res := Game.debug_push(5)
	assert_false(bool(res.ok))
	assert_eq(str(res.reason), "UI_PUSH_REASON_LOCKED")


func test_la_mansione_e_ammessa() -> void:
	var tp := _game()
	_skill()
	assert_eq(tp.block_reason(), "")
	assert_true(bool(Game.debug_push(1).ok))


func test_limite_di_clic_al_secondo_ignora_in_silenzio() -> void:
	var tp := _game()
	_skill()
	Game.click_limiter = ClickLimiter.new(3, 1000)
	var heard := []
	var cb := func(r: String) -> void: heard.append(r)
	EventBus.push_blocked.connect(cb)
	var accepted := 0
	for i in 10:
		var r := Game.request_push(1)
		if bool(r.ok):
			accepted += 1
		else:
			assert_eq(str(r.reason), "", "oltre il limite: nessun motivo, nessun avviso")
	EventBus.push_blocked.disconnect(cb)
	Game.click_limiter = null
	assert_lte(accepted, 3, "al massimo 3 nella finestra (anche se il test e' molto veloce)")
	assert_eq(heard, [], "nessun messaggio ne' accusa")
