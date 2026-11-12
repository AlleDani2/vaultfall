class_name PerfGate
extends RefCounted
## Test di prestazione robusti al carico della macchina (resoconto 67, docs/17 §11).
##
## PROBLEMA: un limite fisso in millisecondi ("24 h offline <= 1 s", "tick <= 15 ms") fallisce a caso quando altri
## processi occupano la CPU, anche se il codice non è peggiorato. SOLUZIONE (due difese insieme):
##  1. CALIBRAZIONE: una routine di riferimento (`_work`, GDScript puro con array, dizionari e ordinamento, come il
##     codice dei sistemi) viene cronometrata nello stesso processo; `load_factor()` = tempo misurato / REF_MS, mai
##     sotto 1 e mai sopra MAX_FACTOR. Il limite effettivo è `limite_di_progetto * load_factor`. A macchina libera il
##     fattore è 1 e il limite di progetto resta quello scritto nel test. Con la macchina carica il limite si allarga
##     in proporzione, quindi fallisce solo una regressione che costa molto più del rumore.
##  0. OROLOGIO: su Linux le misure usano il tempo di CPU del thread (`clock_usec`), che non dipende dagli altri processi.
##  2. MIGLIORE DI K: dove la misura è ripetibile a basso costo si usa il minimo di K esecuzioni (`best_of`), che
##     scarta le sospensioni occasionali dello scheduler.
## La calibrazione è presa PRIMA e DOPO la misura e si usa il valore più alto (`factor_around`).
## MAX_FACTOR limita lo "sconto": con carico oltre 6 volte il normale il test non diventa più permissivo di così.
##
## Gruppo `perf`: le funzioni di prova che SOLO misurano tempi si chiamano `test_perf_*`. `tools/run_tests.py` le
## esclude dai processi paralleli (variabile VAULTFALL_PERF=off, vedi `deferred`) e le esegue alla fine, da sole,
## in serie (`--perf-only` le lancia soltanto). Misure dentro test funzionali lunghi (partita del bot) usano solo il
## fattore di carico.

## Tempo (ms) della routine di riferimento su una macchina libera (minimo di molte esecuzioni, vedi
## docs/audit_2026-10-22/67_RESOCONTO_TEST_INFRA.md). Se la CPU di sviluppo è più lenta il fattore sale (>1) e i
## limiti si allargano, il che è voluto: i limiti di progetto sono per un PC medio.
const REF_MS := 3.0
const MAX_FACTOR := 6.0
const CALIB_RUNS := 7

static var _sink: int = 0
static var _sched: int = -1            # -1 non provato, 1 /proc/thread-self/schedstat disponibile, 0 no


## OROLOGIO DELLE MISURE, in microsecondi. Su Linux è il tempo di CPU del thread principale
## (/proc/thread-self/schedstat, 1° campo = ns passati sulla CPU): NON conta l'attesa quando altri processi occupano la
## macchina, quindi un test non fallisce perché il processo è stato sospeso dallo scheduler. Dove non c'è (Windows,
## macOS) ripiega sul tempo reale (Time.get_ticks_usec) e si affida al fattore di carico. Costo ~20 µs a chiamata.
@warning_ignore("integer_division")
static func clock_usec() -> int:
	if _sched != 0:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f != null:
			var parts := f.get_line().split(" ")
			if parts.size() >= 1 and parts[0].is_valid_int():
				_sched = 1
				return int(float(parts[0]) / 1000.0)
		_sched = 0
	return Time.get_ticks_usec()


## True se `clock_usec` misura il tempo di CPU (immune al carico), false se è tempo reale.
static func clock_is_cpu() -> bool:
	clock_usec()
	return _sched == 1


## Routine di riferimento: ~3 ms su macchina libera (misurato 2,9 ms con la macchina già occupata).
static func _work() -> int:
	var d := {}
	var a: Array = []
	var s := 0
	for i in 12000:
		s += (i * 7) % 13
		d[i % 97] = s
		a.append((i * 31) & 1023)
	a.sort()
	for k in d:
		s += int(d[k]) & 7
	return s + a.size()


## Tempo minimo (ms) della routine di riferimento su CALIB_RUNS esecuzioni.
static func calibration_ms() -> float:
	var best := INF
	for _i in CALIB_RUNS:
		var t0 := clock_usec()
		_sink += _work()
		best = minf(best, float(clock_usec() - t0) / 1000.0)
	return best


## Come `calibration_ms` ma sul tempo REALE: per le misure che includono attese di disco (caricamenti).
static func wall_calibration_ms() -> float:
	var best := INF
	for _i in CALIB_RUNS:
		var t0 := Time.get_ticks_usec()
		_sink += _work()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
	return best


## Fattore di carico sul tempo reale (per misure con attese di disco, cronometrate con Time.get_ticks_*).
static func wall_factor() -> float:
	return clampf(wall_calibration_ms() / REF_MS, 1.0, MAX_FACTOR)


## Fattore di carico attuale: 1.0 a macchina libera, fino a MAX_FACTOR.
static func load_factor() -> float:
	return clampf(calibration_ms() / REF_MS, 1.0, MAX_FACTOR)


## Fattore prudente per una misura appena fatta: il più alto tra quello prima (`before`, da `load_factor()`) e dopo.
static func factor_around(before: float) -> float:
	return maxf(before, load_factor())


## Limite effettivo in ms: limite di progetto per il fattore di carico.
static func limit(design_ms: float, factor: float) -> float:
	return design_ms * factor


## Minimo di `k` esecuzioni di `fn` (ms). `fn` deve preparare da sé uno stato nuovo se la misura lo consuma.
static func best_of(fn: Callable, k: int = 3) -> float:
	var best := INF
	for _i in k:
		var t0 := clock_usec()
		fn.call()
		best = minf(best, float(clock_usec() - t0) / 1000.0)
	return best


## True nei processi paralleli di run_tests.py: i `test_perf_*` vengono rimandati alla fase seriale finale.
static func deferred() -> bool:
	return OS.get_environment("VAULTFALL_PERF") == "off"


## Scrive nel log di GUT l'esito della misura con il fattore di carico (diagnosi dei rari falsi allarmi).
static func note(t: GutTest, what: String, ms: float, design_ms: float, factor: float) -> void:
	t.gut.p("PERF %s: %.1f ms (limite di progetto %.0f ms x fattore di carico %.2f = %.0f ms)" % [what, ms, design_ms, factor, design_ms * factor])


## Rilevatore del carico durante una partita lunga del bot: ricalibra ogni `every` passi (FUORI dal tempo del tick,
## via `BotPlayer.between_steps`). `f_cur` = ultimo fattore, `f_max` = il più alto visto nella partita.
class Tracker extends RefCounted:
	var every: int = 500
	var n: int = 0
	var f_cur: float = 1.0
	var f_max: float = 1.0

	func start() -> void:
		f_cur = PerfGate.load_factor()
		f_max = f_cur

	func step() -> void:
		n += 1
		if n % every == 0:
			f_cur = PerfGate.load_factor()
			f_max = maxf(f_max, f_cur)

	func finish() -> float:
		f_max = maxf(f_max, PerfGate.load_factor())
		return f_max


## Per i `test_perf_*`: nei processi paralleli (VAULTFALL_PERF=off) registra un esito neutro e dice di uscire subito.
## Uso:  if PerfGate.skip_if_deferred(self): return
static func skip_if_deferred(t: GutTest) -> bool:
	if deferred():
		t.pass_test("rimandato alla fase perf seriale di tools/run_tests.py")
		return true
	return false


## Asserzione di tempo con soglia scalata dal carico: ok se `ms < design_ms * factor`.
## `factor` = PerfGate.factor_around(f_prima). Stampa sempre la riga PERF (utile per scoprire falsi allarmi).
static func assert_time(t: GutTest, what: String, ms: float, design_ms: float, factor: float) -> void:
	note(t, what, ms, design_ms, factor)
	t.assert_lt(ms, design_ms * factor, "%s: %.1f ms oltre il limite %.0f ms x carico %.2f" % [what, ms, design_ms, factor])
