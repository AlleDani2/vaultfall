class_name FxBarGhost
extends Control
## Effetto sulle barre (salute, nemico, risorsa, XP): quando la barra SCENDE resta per un attimo la «scia» del vecchio
## livello, che poi si ritira (si vede quanto si è perso); quando SALE, un lampo chiaro sul tratto appena guadagnato.
## Si mette come figlio di un ProgressBar (`FxBarGhost.attach`). Disegna solo mentre c'è qualcosa da mostrare e
## `_process` è spento altrimenti. Una caduta enorme (la barra riparte: nuovo livello, nuova ondata) non lascia scia.
## Fx.level(): 0 = niente (nessun nodo animato); 1 = solo scia; 2 = scia + lampo del guadagno.

const HOLD_S := 0.22                  # la scia resta ferma questo tempo
const DRAIN_PER_S := 1.6              # poi si ritira a questa velocità (frazione di barra al secondo)
const GAIN_S := 0.35                  # durata del lampo di guadagno
const GAIN_MIN := 0.02               # incrementi più piccoli non lampeggiano
const RESET_DROP := 0.5               # caduta oltre questa frazione: la barra è ripartita, nessuna scia

var bar: ProgressBar
var ghost: float = -1.0               # frazione della scia (>= valore); < 0 = assente
var gain_from: float = -1.0
var gain_t: float = 0.0
var _hold: float = 0.0
var _last: float = -1.0
var trail_color: Color = Color(0.96, 0.9, 0.78, 0.8)
var gain_color: Color = Color(1.0, 1.0, 0.92, 0.5)


static func attach(b: ProgressBar) -> FxBarGhost:
	for c in b.get_children():
		if c is FxBarGhost:
			return c
	var g := FxBarGhost.new()
	g.bar = b
	b.add_child(g)
	b.value_changed.connect(g._on_value)
	g._last = g._frac()
	return g


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "FxBarGhost"
	set_process(false)


func _ready() -> void:
	set_process(false)                    # (il motore riaccende _process alla READY: lo spegniamo qui)


func _frac() -> float:
	var span := bar.max_value - bar.min_value
	return clampf((bar.value - bar.min_value) / span, 0.0, 1.0) if span > 0.0 else 0.0


func is_busy() -> bool:
	return ghost >= 0.0 or gain_from >= 0.0


func _on_value(_v: float) -> void:
	var f := _frac()
	var lv := Fx.level()
	if lv <= 0 or not is_inside_tree():
		ghost = -1.0
		gain_from = -1.0
		_last = f
		return
	if f < _last - 1e-4:
		if _last - f <= RESET_DROP:
			ghost = maxf(ghost, _last)
			_hold = HOLD_S
			gain_from = -1.0
			set_process(true)
		else:
			ghost = -1.0
	elif f > _last + GAIN_MIN and lv >= 2 and f - _last <= RESET_DROP:
		if gain_from < 0.0:
			gain_from = _last              # un guadagno vero inizia il lampo (la rigenerazione lenta, sotto soglia, no)
		gain_t = GAIN_S
		ghost = -1.0
		set_process(true)
	_last = f
	queue_redraw()


func _process(dt: float) -> void:
	var f := _frac()
	if ghost >= 0.0:
		if _hold > 0.0:
			_hold -= dt
		else:
			ghost -= DRAIN_PER_S * dt
		if ghost <= f + 0.002:
			ghost = -1.0
	if gain_from >= 0.0:
		gain_t -= dt
		if gain_t <= 0.0:
			gain_from = -1.0
	if not is_busy():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if not is_busy() or bar == null:
		return
	var f := _frac()
	var w := size.x
	if ghost > f:
		draw_rect(Rect2(Vector2(roundf(f * w), 0.0), Vector2(roundf((ghost - f) * w), size.y)), trail_color)
	if gain_from >= 0.0 and f > gain_from:
		var a := clampf(gain_t / GAIN_S, 0.0, 1.0)
		var c := Color(gain_color.r, gain_color.g, gain_color.b, gain_color.a * a)
		draw_rect(Rect2(Vector2(roundf(gain_from * w), 0.0), Vector2(roundf((f - gain_from) * w), size.y)), c)
