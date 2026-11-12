class_name FxCounter
extends Node
## Contatore che SCORRE: il numero mostrato in un Label raggiunge il valore vero con un'andatura morbida (esponenziale,
## ~0,3 s) invece di saltare; un piccolo rimbalzo quando sale di molto. Il valore vero resta sempre `target`: la UI non
## decide niente. Un solo nodo figlio per etichetta, `_process` acceso SOLO mentre il numero si muove.
## - il primo valore e ogni cambio con «Riduci animazioni» (Fx.level() 0) sono immediati;
## - al primo frame di un cambio il numero fa già il 35% della strada (nessun ritardo percepito, nessun «0» rimasto).

const META := "fx_counter"
const RATE := 11.0                    # velocità di avvicinamento (1/s)
const FIRST_STEP := 0.35
const POP_MIN_GAP_MS := 450

var label: Label
var fmt: Callable
var target: float = 0.0
var shown: float = 0.0
var pops: int = 0
var _last_pop_ms: int = -100000


## Mostra `value` in `label` (da chiamare a ogni refresh a 10 Hz: è economico se il valore non cambia).
static func set_value(l: Label, value: float, formatter: Callable = Callable(), pop_on_rise: bool = true) -> void:
	if l == null or not is_instance_valid(l):
		return
	var c: FxCounter = null
	if l.has_meta(META):
		var m: Variant = l.get_meta(META)
		if m is FxCounter and is_instance_valid(m):
			c = m
	if c == null:
		c = FxCounter.new()
		c.label = l
		c.shown = value
		c.target = value
		c.fmt = formatter
		l.set_meta(META, c)
		l.add_child(c)
		c.set_process(false)
		c._show()
		return
	if formatter.is_valid():
		c.fmt = formatter
	if is_equal_approx(value, c.target):
		return
	var old := c.target
	c.target = value
	if Fx.level() <= 0 or not l.is_inside_tree():
		c.shown = value
		c.set_process(false)
		c._show()
		return
	c.shown = lerpf(c.shown, value, FIRST_STEP)
	c._show()
	c.set_process(true)
	if pop_on_rise and value > old and (value - old) >= maxf(2.0, absf(old) * 0.01):
		c._pop()


## Valore mostrato adesso (per i test).
static func displayed(l: Label) -> float:
	if l != null and l.has_meta(META):
		var m: Variant = l.get_meta(META)
		if m is FxCounter and is_instance_valid(m):
			return (m as FxCounter).shown
	return NAN


func _init() -> void:
	name = "FxCounter"


func _process(dt: float) -> void:
	if label == null or not is_instance_valid(label):
		queue_free()
		return
	var k := minf(1.0, dt * RATE)
	shown = lerpf(shown, target, k)
	if absf(target - shown) < 1.0:
		shown = target
		set_process(false)
	_show()


func _show() -> void:
	if label == null:
		return
	label.text = str(fmt.call(floorf(shown))) if fmt.is_valid() else NumberFormat.fmt(floorf(shown))


func _pop() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_pop_ms < POP_MIN_GAP_MS:
		return
	_last_pop_ms = now
	pops += 1
	Fx.pop(label, 1.07, 0.16)
