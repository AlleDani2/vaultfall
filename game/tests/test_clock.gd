extends GutTest
## T-1.4: Clock a passo fisso (0,1 s), tetto di 50 passi per chiamata, velocità, pausa, salti lunghi.

var c: FixedStepClock
var steps_seen: int
var gaps: Array


func before_each() -> void:
	c = FixedStepClock.new()
	steps_seen = 0
	gaps = []
	c.stepped.connect(func(dt: float) -> void:
		assert_eq(dt, FixedStepClock.STEP)
		steps_seen += 1)
	c.long_gap.connect(func(s: float) -> void: gaps.append(s))


func test_passo_fisso_e_accumulatore() -> void:
	assert_eq(c.advance(0.35), 3)
	assert_almost_eq(c.pending_s(), 0.05, 1e-9)
	assert_eq(c.advance(0.05), 1, "il resto si accumula")
	assert_eq(steps_seen, 4)
	assert_almost_eq(c.sim_time, 0.4, 1e-9)


func test_tempo_misurato_non_frame() -> void:
	# 60 fps per 10 s e 10 fps per 10 s: stesso tempo simulato (docs/17 §11)
	for i in 600:
		c.advance(1.0 / 60.0)
	var a := c.total_steps
	for i in 100:
		c.advance(0.1)
	assert_almost_eq(float(a), 100.0, 1.0)
	assert_almost_eq(float(c.total_steps - a), 100.0, 1.0)


func test_tetto_di_50_passi_e_recupero() -> void:
	assert_eq(c.advance(10.0), FixedStepClock.MAX_STEPS_PER_FRAME)
	assert_almost_eq(c.pending_s(), 5.0, 1e-6, "il ritardo resta da recuperare")
	assert_eq(c.advance(0.0001), 50, "recupero nelle chiamate successive")
	assert_eq(gaps.size(), 0, "sotto MAX_CATCHUP_S nessun salto")


func test_salto_lungo_ceduto_in_blocco() -> void:
	assert_eq(c.advance(3600.0), 50)
	assert_eq(gaps.size(), 1)
	assert_almost_eq(gaps[0], 3595.0, 0.2)
	assert_lt(c.pending_s(), FixedStepClock.STEP)
	assert_almost_eq(c.sim_time, 3600.0, 0.2, "il tempo simulato totale torna")


func test_velocita_e_pausa() -> void:
	c.speed = 10.0
	assert_eq(c.advance(0.1), 10)
	c.paused = true
	assert_eq(c.advance(1.0), 0)
	assert_almost_eq(c.pending_s(), 0.0, 1e-9, "in pausa il tempo non si accumula")


func test_autoload_clock() -> void:
	assert_not_null(Clock.core)
	assert_gt(Clock.now_unix(), 1700000000)
	watch_signals(EventBus)
	Clock.set_paused(true)
	assert_true(Clock.paused)
	assert_signal_emitted(EventBus, "clock_paused_changed")
	Clock.set_paused(false)
