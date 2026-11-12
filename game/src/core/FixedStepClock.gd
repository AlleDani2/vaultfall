class_name FixedStepClock
extends RefCounted
## Accumulatore a passo fisso (docs/17 §5). Classe pura e testabile: l'autoload Clock la alimenta con il
## tempo REALE misurato (non con il numero di frame), così la simulazione non rallenta con la finestra in
## secondo piano a 10 fps (docs/17 §11).
## - passo fisso STEP = 0,1 s simulati;
## - al massimo MAX_STEPS_PER_FRAME passi per chiamata (protezione dai salti lunghi);
## - il ritardo rimasto si recupera nelle chiamate successive; se supera MAX_CATCHUP_S viene ceduto in blocco
##   con il segnale long_gap(seconds) (lo gestisce Game come tempo offline, docs/17 §5).

signal stepped(dt: float)
signal long_gap(seconds: float)

const STEP := 0.1
const MAX_STEPS_PER_FRAME := 50
const MAX_CATCHUP_S := 60.0
## Tetto di un singolo avanzamento (1 anno): un delta assurdo (finito) non manda in overflow il conteggio dei passi.
const MAX_ADVANCE_S := 31536000.0

var speed: float = 1.0
var paused: bool = false
var sim_time: float = 0.0          # secondi simulati totali
var total_steps: int = 0
var _acc: float = 0.0


## Avanza di real_delta secondi reali; ritorna il numero di passi eseguiti.
func advance(real_delta: float) -> int:
	if paused or not is_finite(real_delta) or real_delta <= 0.0:
		return 0
	var inc := real_delta * speed
	if not is_finite(inc):             # velocita' NaN/inf (debug): nessun avanzamento, l'accumulatore resta sano
		return 0
	_acc += minf(inc, MAX_ADVANCE_S)
	var steps := 0
	while _acc >= STEP - 1e-9 and steps < MAX_STEPS_PER_FRAME:
		_acc -= STEP
		steps += 1
		total_steps += 1
		sim_time += STEP
		stepped.emit(STEP)
	if _acc < 0.0:
		_acc = 0.0
	if _acc > MAX_CATCHUP_S:
		var n := int(floor(_acc / STEP))
		var gap := n * STEP
		_acc -= gap
		sim_time += gap
		long_gap.emit(gap)
	return steps


## Sospensione con il gioco aperto (QA120): `wall_delta` = secondi di orologio di sistema trascorsi dal fotogramma precedente,
## `real_delta` = secondi misurati dal motore (monotonico: su Linux/Steam Deck NON conta il sonno). L'eccesso, se arriva alla
## soglia `min_gap` (dati: constants.offline.resume_min_gap_s), e' tempo di assenza da accreditare; altrimenti 0. Un orologio
## tornato indietro (wall < real) non produce nulla. Pura.
static func suspend_gap(wall_delta: float, real_delta: float, min_gap: float) -> float:
	if not is_finite(wall_delta) or not is_finite(real_delta):
		return 0.0
	var excess := wall_delta - maxf(real_delta, 0.0)
	if excess < maxf(min_gap, 1.0):
		return 0.0
	return minf(excess, MAX_ADVANCE_S)


func pending_s() -> float:
	return _acc


func reset() -> void:
	_acc = 0.0
	sim_time = 0.0
	total_steps = 0
