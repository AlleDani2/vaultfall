extends GutTest
## TimePushSystem (Sabbia del Custode, UI F13): spesa, rigenerazione, offline, tetti, salvataggio, determinismo, regalo di sblocco.
## Partite vere su Game (sistemi reali). I numeri vengono SEMPRE da constants.time_push (nessuna costante qui).

var _old_dir: String
var _old_auto: bool
var _paused_before: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_time_push_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func before_each() -> void:
	_paused_before = Clock.core.paused


func after_each() -> void:
	Clock.core.paused = _paused_before
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _k() -> Dictionary:
	return DataRegistry.constants.time_push


func _new_game(seed_value: int = 31) -> TimePushSystem:
	assert_true(Game.new_game(1, "normal", seed_value))
	return Game.system("time_push") as TimePushSystem


func _unlock(tp: TimePushSystem) -> void:
	(Game.system("unlock") as UnlockSystem).grant(str(_k().unlock_token))
	tp.state["gift_given"] = true            # i test che non parlano del regalo partono da una riserva nota
	tp.state["reserve_s"] = 0.0


func _start_action() -> String:
	var sk := Game.system("skills") as SkillSystem
	for a in DataRegistry.actions_for_skill("woodcutting"):
		if int(a.get("level_req", 1)) <= 1:
			if not GameState.data.unlocks.has("skill:woodcutting"):
				GameState.data.unlocks.append("skill:woodcutting")
			if sk.start(str(a.id)):
				return str(a.id)
	return ""


func _xp() -> float:
	return float(GameState.data.skills.woodcutting.xp)


# ------------------------------------------------------------------ dati e formule

func test_parametri_prudenti_dai_dati() -> void:
	var k := _k()
	assert_almost_eq(float(k.click_s), 0.3, 1e-9)
	assert_eq(int(k.max_cps), 20)
	assert_almost_eq(float(k.reserve_cap_s), 600.0, 1e-9)
	assert_almost_eq(float(k.regen_online_pct), 5.0, 1e-9)
	assert_lte(float(k.regen_offline_pct), 0.5, "non piu' generoso del doc 03")
	assert_eq(k.allowed_activities, ["skill"], "v1: solo mansioni")


func test_formule_push() -> void:
	assert_almost_eq(Formulas.push_regen(3600.0, 5.0), 180.0, 1e-9)
	assert_eq(Formulas.push_regen(-1.0, 5.0), 0.0)
	assert_eq(Formulas.push_regen(10.0, 0.0), 0.0)
	assert_almost_eq(Formulas.push_spend(600.0, 0.3), 0.3, 1e-9)
	assert_almost_eq(Formulas.push_spend(0.2, 0.3), 0.2, 1e-9)
	assert_eq(Formulas.push_spend(0.0, 0.3), 0.0)


# ------------------------------------------------------------------ spesa

func test_spesa_non_supera_la_riserva() -> void:
	var tp := _new_game()
	_unlock(tp)
	assert_false(_start_action().is_empty())
	tp.state["reserve_s"] = 1.0
	var res := Game.debug_push(100)
	assert_true(res.ok)
	assert_almost_eq(float(res.seconds), 1.0, 1e-9, "100 clic ma solo 1,0 s di Sabbia")
	assert_almost_eq(tp.reserve_s(), 1.0, 1e-9, "la riserva si scala quando il passo e' eseguito, non alla richiesta")
	var steps := tp.drain(1000)
	assert_eq(steps, 10, "1,0 s = 10 passi da 0,1 s")
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)
	assert_almost_eq(tp.pushed_total_s(), 1.0, 1e-9)
	assert_almost_eq(tp.today_s(), 1.0, 1e-9)
	assert_almost_eq(tp.pending_s(), 0.0, 1e-9)
	var again := Game.debug_push(5)
	assert_false(again.ok, "riserva vuota")
	assert_eq(again.reason, "UI_PUSH_EMPTY")


func test_spesa_parziale_sotto_un_clic() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 0.2
	var res := Game.debug_push(1)
	assert_almost_eq(float(res.seconds), 0.2, 1e-9, "min(riserva, click_s)")
	assert_eq(tp.drain(10), 2)
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)


func test_la_coda_aspetta_il_budget_e_non_perde_tempo() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 3.0
	Game.debug_push(10)                       # 3,0 s concessi
	assert_eq(tp.drain(4), 4, "tetto di passi per fotogramma")
	assert_almost_eq(tp.reserve_s(), 2.6, 1e-9, "scalati solo i 4 passi eseguiti")
	assert_almost_eq(tp.pending_s(), 2.6, 1e-9)
	assert_eq(tp.drain(1000), 26)
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)


func test_la_spinta_fa_avanzare_la_sola_azione() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 30.0
	var xp0 := _xp()
	var play0 := float(GameState.data.stats.playtime_s)
	Game.debug_push(100)
	tp.drain(1000)
	assert_gt(_xp(), xp0, "l'azione in corso e' avanzata")
	assert_almost_eq(float(GameState.data.stats.playtime_s), play0, 1e-9, "playtime_s non cambia")


func test_se_l_azione_finisce_la_coda_si_svuota_senza_scalare() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 5.0
	Game.debug_push(100)
	tp.drain(2)
	GameState.data["activity"].clear()
	assert_eq(tp.drain(100), 0)
	assert_almost_eq(tp.pending_s(), 0.0, 1e-9)
	assert_almost_eq(tp.reserve_s(), 4.8, 1e-9, "solo i 2 passi eseguiti sono costati")


# ------------------------------------------------------------------ rigenerazione

func test_rigenera_solo_con_azione_ammessa() -> void:
	var tp := _new_game()
	_unlock(tp)
	GameState.data["activity"].clear()
	tp.tick(10.0)
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9, "nessuna azione: niente ricarica")
	_start_action()
	tp.tick(10.0)
	assert_almost_eq(tp.reserve_s(), Formulas.push_regen(10.0, float(_k().regen_online_pct)), 1e-9)
	GameState.data["activity"].clear()
	GameState.data["activity"].merge({"type": "combat", "mode": "zone"})
	var r := tp.reserve_s()
	tp.tick(10.0)
	assert_almost_eq(tp.reserve_s(), r, 1e-9, "combattimento: non ammesso nella v1")


func test_non_rigenera_se_non_sbloccata() -> void:
	var tp := _new_game()
	_start_action()
	tp.tick(100.0)
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)
	assert_eq(tp.block_reason(), "UI_PUSH_REASON_LOCKED")


func test_in_pausa_il_clock_non_fa_tick_e_il_clic_e_rifiutato() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	Clock.core.paused = true
	var steps := Clock.core.advance(5.0)
	assert_eq(steps, 0, "in pausa nessun passo, quindi nessuna ricarica")
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)
	tp.state["reserve_s"] = 10.0
	var blocked := []
	var cb := func(reason: String) -> void: blocked.append(reason)
	EventBus.push_blocked.connect(cb)
	var res := Game.debug_push(3)
	EventBus.push_blocked.disconnect(cb)
	assert_false(res.ok)
	assert_eq(res.reason, "UI_PUSH_REASON_PAUSE")
	assert_eq(blocked, ["UI_PUSH_REASON_PAUSE"])
	assert_almost_eq(tp.pending_s(), 0.0, 1e-9)


func test_mai_oltre_il_tetto() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	var cap := float(_k().reserve_cap_s)
	tp.state["reserve_s"] = cap - 0.01
	tp.tick(3600.0)
	assert_almost_eq(tp.reserve_s(), cap, 1e-9)
	var rep := tp.simulate_offline(1.0e9)
	assert_almost_eq(tp.reserve_s(), cap, 1e-9, "nemmeno offline")
	assert_true(rep.is_empty(), "niente da dire se non e' entrato nulla")


# ------------------------------------------------------------------ offline

func test_offline_e_rho_off_per_delta_t() -> void:
	var tp := _new_game()
	_unlock(tp)
	var rep := tp.simulate_offline(3600.0)
	assert_almost_eq(tp.reserve_s(), Formulas.push_regen(3600.0, float(_k().regen_offline_pct)), 1e-9)
	assert_eq(rep.rows[0].key, "UI_OFFL_PUSH_ROW")
	var wb := WelcomeBack.build(3600.0, {"time_push": rep}, DataRegistry, Game.offline_cap_s())
	assert_false(bool(wb.empty), "il Bentornato mostra la riga")


func test_offline_rispetta_il_tetto_di_r_off_1() -> void:
	var tp := _new_game()
	_unlock(tp)
	GameState.data["activity"].clear()
	var cap_h := Game.offline_cap_s()
	Game.apply_absence(cap_h * 4.0)                  # l'assenza oltre il limite non conta
	assert_almost_eq(tp.reserve_s(), Formulas.push_regen(cap_h, float(_k().regen_offline_pct)), 1e-6)


func test_offline_non_sbloccata_non_fa_nulla() -> void:
	var tp := _new_game()
	assert_true(tp.simulate_offline(3600.0).is_empty())
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)


# ------------------------------------------------------------------ regalo di sblocco

func test_regalo_di_sblocco_una_volta_sola() -> void:
	var tp := _new_game()
	assert_false(bool(tp.state.gift_given))
	(Game.system("unlock") as UnlockSystem).grant(str(_k().unlock_token))
	tp.tick(0.1)
	assert_almost_eq(tp.reserve_s(), float(_k().unlock_gift_s), 1e-9)
	assert_true(bool(tp.state.gift_given))
	tp.state["reserve_s"] = 0.0
	tp.tick(0.1)
	tp.simulate_offline(10.0)
	assert_lt(tp.reserve_s(), 1.0, "nessun secondo regalo")
	assert_true(SaveService.save_now())
	assert_true(Game.load_game(1).ok)
	var tp2 := Game.system("time_push") as TimePushSystem
	var r := tp2.reserve_s()
	tp2.tick(0.1)
	assert_almost_eq(tp2.reserve_s(), r, 1e-9, "dopo il caricamento il regalo non si ripete")


# ------------------------------------------------------------------ salvataggio e determinismo

func test_salva_e_ricarica_e_idempotente() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 123.4
	Game.debug_push(10)
	tp.drain(5)
	var before: Dictionary = tp.to_state().duplicate(true)
	assert_true(SaveService.save_now())
	assert_true(Game.load_game(1).ok)
	var tp2 := Game.system("time_push") as TimePushSystem
	var after: Dictionary = tp2.to_state()
	for key in ["reserve_s", "pushed_total_s", "today_s", "gift_given"]:
		assert_eq(after[key], before[key], key)
	var snap := Game.snapshot(true)
	assert_true(snap.has("time_push"))
	assert_eq(int(snap.schema_version), SaveCodec.SCHEMA_VERSION)


func test_sezione_danneggiata_non_rompe() -> void:
	var tp := _new_game()
	tp.from_state({"reserve_s": "abc", "pending_s": 99999.0, "pushed_total_s": -5.0, "today_s": INF, "day_age_s": NAN})
	assert_almost_eq(tp.reserve_s(), 0.0, 1e-9)
	assert_almost_eq(tp.pending_s(), 0.0, 1e-9)
	assert_almost_eq(tp.today_s(), 0.0, 1e-9)
	tp.from_state(null)
	assert_almost_eq(tp.reserve_s(), float(_k().start_reserve_s), 1e-9)
	tp.from_state({"reserve_s": 1.0e9})
	assert_almost_eq(tp.reserve_s(), float(_k().reserve_cap_s), 1e-9, "mai oltre il tetto nemmeno da un salvataggio manomesso")


func _run(seed_value: int) -> Array:
	var tp := _new_game(seed_value)
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 40.0
	for i in 40:
		Game._on_step(0.1)
		Game.debug_push(2)
		tp.drain(int(_k().max_steps_per_frame))
	var bank := Game.system("bank") as BankSystem
	return [snappedf(tp.reserve_s(), 1e-9), snappedf(tp.pushed_total_s(), 1e-9), snappedf(_xp(), 1e-9), bank.count("log_pine"),
		snappedf(float(GameState.data.stats.playtime_s), 1e-9)]


func test_determinismo() -> void:
	var a := _run(555)
	Game.stop_game(false)
	var b := _run(555)
	assert_eq(a, b, "stessa sequenza di eventi, stesso stato")
	assert_gt(float(a[1]), 0.0)


func test_giorno_si_azzera_dopo_ventiquattro_ore_contate() -> void:
	var tp := _new_game()
	_unlock(tp)
	_start_action()
	tp.state["reserve_s"] = 5.0
	Game.debug_push(5)
	tp.drain(100)
	assert_gt(tp.today_s(), 0.0)
	tp.advance_calendar(86400.0)
	assert_almost_eq(tp.today_s(), 0.0, 1e-9)
	assert_gt(tp.pushed_total_s(), 0.0, "il totale di partita resta")
