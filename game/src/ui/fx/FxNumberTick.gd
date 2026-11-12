class_name FxNumberTick
extends RefCounted
## NumberTick: conteggio «a scatti» di un numero in un Label (come un contatore a tacche), poi un piccolo rimbalzo.
## `fmt` riceve il valore e ritorna il testo (es. NumberFormat.fmt). «Riduci animazioni»: valore finale subito.

const STEPS := 12
const META := "fx_tick_tw"


static func run(label: Label, from: float, to: float, secs: float = 0.7, fmt: Callable = Callable()) -> void:
	if label == null or not is_instance_valid(label):
		return
	if label.has_meta(META):
		var old: Variant = label.get_meta(META)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var show := func(v: float) -> void:
		if is_instance_valid(label):
			label.text = str(fmt.call(v)) if fmt.is_valid() else str(roundi(v))
	if Fx.level() <= 0 or not label.is_inside_tree() or is_equal_approx(from, to):
		show.call(to)
		return
	var tw := label.create_tween()
	label.set_meta(META, tw)
	tw.tween_method(func(k: float) -> void:
		show.call(lerpf(from, to, floorf(k * float(STEPS)) / float(STEPS))), 0.0, 1.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		show.call(to)
		Fx.pop(label, 1.1, 0.18))
