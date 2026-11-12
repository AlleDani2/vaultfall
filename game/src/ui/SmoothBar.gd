class_name SmoothBar
extends ProgressBar
## Barra di avanzamento fluida (docs/16): la simulazione avanza a 10 Hz, la barra si muove a ogni frame
## interpolando con la velocità nota. Con "riduci animazioni" salta direttamente al valore ricevuto.
## Uso: set_target(frazione_0_1, frazioni_al_secondo) a ogni refresh() della schermata (≤10 Hz).

const SNAP_THRESHOLD := 0.2
## La barra si ridisegna a 30 Hz al massimo (resoconto 100): ogni ridisegno rifà tutto il canvas, e con una mansione
## sempre in corso la barra era la causa del 100% di fotogrammi ridisegnati a 60 Hz anche in schermate ferme.
const STEP_S := 1.0 / 30.0

var _disp: float = 0.0
var _rate: float = 0.0
var _last: float = 0.0
var _acc: float = 0.0


func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.0
	show_percentage = false


func set_target(fraction: float, rate_per_s: float) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	var reduce: bool = Settings.get_value("reduce_motion")
	if not reduce and f < _last - 0.4 and _last > 0.7:
		Fx.bar_flash(self)                      # ciclo completato: la barra brilla un attimo
	_rate = 0.0 if (reduce or Clock.paused) else rate_per_s * Clock.speed
	# fine ciclo (la frazione è tornata indietro) o scarto grande: si riallinea subito
	if reduce or f < _last - 1e-6 or absf(f - _disp) > SNAP_THRESHOLD or _rate <= 0.0:
		_disp = f
	else:
		_disp = maxf(_disp, f)
	_last = f
	value = _disp
	set_process(_rate > 0.0)


func _process(delta: float) -> void:
	if _rate <= 0.0 or not Clock.focused:       # finestra in secondo piano: nessuno guarda, la barra segue i refresh a 2 Hz
		return
	_acc += delta
	if _acc < STEP_S:
		return
	_disp = minf(1.0, _disp + _rate * _acc)
	_acc = 0.0
	value = _disp
