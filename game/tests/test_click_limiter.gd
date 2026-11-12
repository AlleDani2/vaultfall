extends GutTest
## ClickLimiter (Sabbia del Custode, UI F13): limite duro di clic/s con finestra scorrevole. Solo CPU/effetti, non equità.

const MS := 1000      # microsecondi in un millisecondo


func _lim() -> ClickLimiter:
	return ClickLimiter.from_constants(DataRegistry.constants)


func test_parametri_dai_dati() -> void:
	var l := _lim()
	var k: Dictionary = DataRegistry.constants.time_push
	assert_eq(l.max_cps, int(k.max_cps))
	assert_eq(l.window_usec, int(k.window_ms) * 1000)


func test_venti_in_un_secondo_accettati_il_ventunesimo_no() -> void:
	var l := _lim()
	var t0 := 5_000_000
	for i in 20:
		assert_true(l.accept(t0 + i * 10 * MS), "clic %d" % (i + 1))
	assert_false(l.accept(t0 + 300 * MS), "il 21° nella stessa finestra è ignorato")
	assert_false(l.accept(t0 + 999 * MS), "ancora dentro la finestra del primo")


func test_riaccetta_dopo_la_finestra() -> void:
	var l := _lim()
	var t0 := 1_000_000
	for i in 20:
		l.accept(t0 + i * MS)
	assert_false(l.accept(t0 + 999 * MS))
	assert_true(l.accept(t0 + 1000 * MS), "il primo clic è uscito dalla finestra di 1000 ms")
	assert_false(l.accept(t0 + 1000 * MS), "i clic accettati nella finestra restano 20")
	assert_true(l.accept(t0 + 1001 * MS), "esce anche il secondo")


func test_a_cadenza_lenta_accetta_sempre() -> void:
	var l := _lim()
	for i in 200:
		assert_true(l.accept(i * 100 * MS), "10 clic/s")


func test_istanti_non_monotoni_non_regalano_clic() -> void:
	var l := _lim()
	var t0 := 10_000_000
	for i in 20:
		assert_true(l.accept(t0 + i * MS))
	# l'orologio torna indietro di 5 s: i clic non contano come passati
	assert_false(l.accept(t0 - 5_000_000), "istante nel passato: conta come l'ultimo visto")
	assert_false(l.accept(0))
	assert_false(l.accept(t0 + 500 * MS))
	assert_true(l.accept(t0 + 1019 * MS), "la finestra scorre dall'ultimo istante reale")


func test_eventi_echo_non_sono_clic() -> void:
	var k := InputEventKey.new()
	k.echo = true
	assert_true(ClickLimiter.is_echo(k))
	assert_false(ClickLimiter.is_echo(InputEventKey.new()))
	assert_false(ClickLimiter.is_echo(InputEventMouseButton.new()))


func test_reset() -> void:
	var l := _lim()
	for i in 20:
		l.accept(i)
	assert_false(l.accept(100))
	l.reset()
	assert_true(l.accept(100))
