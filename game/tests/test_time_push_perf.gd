extends GutTest
## Sabbia del Custode, prestazioni (UI F13): 20 clic/s per 60 s di gioco a 60 fotogrammi/s. La coda non supera il budget di CPU
## per fotogramma (constants.time_push.max_cpu_ms_per_frame) e il Clock non vede mai un `long_gap` (che sarebbe scambiato per assenza).
## Gruppo perf: la funzione `test_perf_*` gira in serie, a macchina meno carica (PerfGate).

const FPS := 60
const SECONDS := 60

var _old_dir: String
var _old_auto: bool
var _gaps: Array = []


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_time_push_perf_%d" % Time.get_ticks_usec()
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


func _on_gap(s: float) -> void:
	_gaps.append(s)


func test_perf_venti_clic_al_secondo_per_un_minuto() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	var k: Dictionary = DataRegistry.constants.time_push
	assert_true(Game.new_game(1, "normal", 99))
	var tp := Game.system("time_push") as TimePushSystem
	(Game.system("unlock") as UnlockSystem).grant(str(k.unlock_token))
	tp.state["gift_given"] = true
	tp.state["reserve_s"] = float(k.reserve_cap_s)
	GameState.data.unlocks.append("skill:woodcutting")
	var sk := Game.system("skills") as SkillSystem
	for a in DataRegistry.actions_for_skill("woodcutting"):
		if int(a.get("level_req", 1)) <= 1 and sk.start(str(a.id)):
			break
	_gaps.clear()
	Clock.core.long_gap.connect(_on_gap)
	var load_before := PerfGate.load_factor()
	var frames := FPS * SECONDS
	var per_click := FPS / int(k.max_cps)               # un clic ogni 3 fotogrammi = 20 clic/s
	var worst_us := 0
	var over := 0
	var over_us := int(k.max_cpu_ms_per_frame) * 1000
	var total_us := 0
	var max_steps := 0
	var clicks := 0
	for f in frames:
		if f % per_click == 0:
			Game.debug_push(1)
			clicks += 1
		if f % (FPS / 10) == 0:
			Game._on_step(0.1)                           # il tempo normale continua a 10 passi/s
		var t0 := PerfGate.clock_usec()
		var before := tp.pushed_total_s()
		tp.drain(int(k.max_steps_per_frame), int(k.max_cpu_ms_per_frame) * 1000)
		var dt_us := PerfGate.clock_usec() - t0
		worst_us = maxi(worst_us, dt_us)
		if dt_us > over_us:
			over += 1
		total_us += dt_us
		max_steps = maxi(max_steps, int(round((tp.pushed_total_s() - before) / FixedStepClock.STEP)))
	Clock.core.long_gap.disconnect(_on_gap)
	# svuota ciò che resta in coda (al più pochi fotogrammi)
	var guard := 0
	while tp.pending_s() > 0.0 and guard < 600:
		tp.drain(int(k.max_steps_per_frame), 0)
		guard += 1
	var factor := PerfGate.factor_around(load_before)
	var budget_ms := float(k.max_cpu_ms_per_frame)
	# il budget e' morbido: il passo in corso finisce (un picco isolato di un passo, es. il primo uso di un'azione, puo' sfiorarlo)
	PerfGate.assert_time(self, "coda della Sabbia: fotogramma peggiore (<= 2 x budget)", float(worst_us) / 1000.0, 2.0 * budget_ms, factor)
	assert_lte(over, frames / 100, "al massimo l'1%% dei fotogrammi oltre il budget di CPU (%d su %d)" % [over, frames])
	PerfGate.note(self, "coda della Sabbia: media per fotogramma", float(total_us) / 1000.0 / frames, budget_ms, factor)
	assert_eq(_gaps, [], "nessun long_gap: il Clock non e' toccato")
	assert_lte(max_steps, int(k.max_steps_per_frame), "mai oltre max_steps_per_frame passi per fotogramma")
	var wanted := float(clicks) * float(k.click_s)
	assert_almost_eq(tp.pushed_total_s(), wanted, 0.05, "tutto il tempo concesso e' stato eseguito (360 s in 60 s)")
	var regen_max := Formulas.push_regen(float(SECONDS) + 1.0, float(k.regen_online_pct))      # la ricarica online del minuto
	assert_between(tp.reserve_s(), float(k.reserve_cap_s) - wanted - 0.05, float(k.reserve_cap_s) - wanted + regen_max + 0.05)
