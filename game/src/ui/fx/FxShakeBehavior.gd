class_name FxShakeBehavior
extends Node
## Scossa di un nodo (Control o Node2D) a gradini di pixel, che decade. Un solo comportamento per nodo (si riusa:
## una scossa nuova rimpiazza la vecchia e il punto di riposo NON deriva). Dentro un Container (che comanda la
## posizione) trema con una piccola rotazione al posto dello spostamento. Si ferma da solo e rimette tutto a posto.

const HZ := 30.0
const META := "fx_shake"

var _target: CanvasItem
var _rest_pos: Vector2 = Vector2.ZERO
var _rest_rot: float = 0.0
var _amp: float = 0.0
var _kick: Vector2 = Vector2.ZERO     # spinta fluida (knockback / affondo): sale e rientra durante la durata
var _shake_o: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _dur: float = 0.2
var _acc: float = 0.0
var _use_rot: bool = false
var running: bool = false


static func on(target: CanvasItem) -> FxShakeBehavior:
	if target.has_meta(META):
		var old: Variant = target.get_meta(META)
		if is_instance_valid(old) and old is FxShakeBehavior:
			return old
	var b := FxShakeBehavior.new()
	b.name = "FxShake"
	b._target = target
	target.add_child(b)
	target.set_meta(META, b)
	b.set_process(false)
	return b


func start(px: float, secs: float, kick: Vector2 = Vector2.ZERO) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if running:
		_restore()
	_use_rot = _target is Control and _target.get_parent() is Container
	if _use_rot:
		var c := _target as Control
		_rest_rot = c.rotation
		c.pivot_offset = c.size * 0.5
	elif _target is Control:
		_rest_pos = (_target as Control).position
	else:
		_rest_pos = (_target as Node2D).position
	_amp = px
	_kick = kick
	_shake_o = Vector2.ZERO
	_dur = maxf(0.05, secs)
	_t = 0.0
	_acc = 1.0 / HZ
	running = true
	set_process(true)


## Ferma subito e rimette il nodo al punto di riposo (es. prima di copiarne l'immagine per la dissolvenza).
func stop() -> void:
	if running:
		_restore()


func _process(dt: float) -> void:
	if not running:
		set_process(false)
		return
	_t += dt
	_acc += dt
	if _t >= _dur or _target == null or not is_instance_valid(_target):
		_restore()
		return
	if _acc >= 1.0 / HZ:
		_acc = 0.0
		var k := pow(1.0 - _t / _dur, 2.0)
		_shake_o = Vector2(roundf(randf_range(-1.0, 1.0) * _amp * k), roundf(randf_range(-1.0, 1.0) * _amp * k * 0.6))
	var o := _shake_o
	if _kick != Vector2.ZERO:
		var u := clampf(_t / _dur, 0.0, 1.0)
		o += (_kick * pow(sin(PI * pow(u, 0.6)), 1.0)).round()      # picco anticipato, rientro più lento
	_apply(o)


func _apply(o: Vector2) -> void:
	if _use_rot:
		(_target as Control).rotation = _rest_rot + o.x * 0.004
	elif _target is Control:
		(_target as Control).position = _rest_pos + o
	else:
		(_target as Node2D).position = _rest_pos + o


func _restore() -> void:
	running = false
	set_process(false)
	if _target == null or not is_instance_valid(_target):
		return
	if _use_rot:
		(_target as Control).rotation = _rest_rot
	elif _target is Control:
		(_target as Control).position = _rest_pos
	else:
		(_target as Node2D).position = _rest_pos
