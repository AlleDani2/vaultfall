class_name FxGlowPulse
extends RefCounted
## Impulsi di luce sul self_modulate di un nodo (non tocca `modulate`, che usano altri effetti della UI).
## - pulse(): N respiri di colore, poi torna normale;
## - breathe(): respiro lento continuo (edifici al lavoro, abilità pronta), si spegne con breathe(node, false);
## - con «riduci animazioni»: nessun movimento, solo un tono fisso per un attimo (lampo statico).

const META_TW := "fx_glow_tw"


static func _kill(n: CanvasItem) -> void:
	if n.has_meta(META_TW):
		var old: Variant = n.get_meta(META_TW)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		n.remove_meta(META_TW)


static func pulse(n: CanvasItem, color: Color, pulses: int = 2, secs: float = 0.5, strength: float = 0.5) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return
	var lv := Fx.level()
	_kill(n)
	var tint := Color.WHITE.lerp(color, strength)
	tint = Color(minf(1.6, tint.r + 0.25 * strength), minf(1.6, tint.g + 0.25 * strength), minf(1.6, tint.b + 0.25 * strength), 1.0)
	if lv <= 0:
		n.self_modulate = tint
		var tw0 := n.create_tween()                 # legato al nodo: se sparisce, sparisce anche lui (niente lambda orfane)
		n.set_meta(META_TW, tw0)
		tw0.tween_interval(secs)
		tw0.tween_callback(_restore.bind(n))
		return
	var tw := n.create_tween()
	n.set_meta(META_TW, tw)
	var each := secs / float(maxi(1, pulses))
	for i in maxi(1, pulses):
		tw.tween_property(n, "self_modulate", tint, each * 0.4).set_trans(Tween.TRANS_SINE)
		tw.tween_property(n, "self_modulate", Color.WHITE, each * 0.6).set_trans(Tween.TRANS_SINE)


static func _restore(n: CanvasItem) -> void:
	if is_instance_valid(n):
		n.self_modulate = Color.WHITE
		n.remove_meta(META_TW)


static func breathe(n: CanvasItem, on: bool, color: Color = Color(1.0, 0.95, 0.75), period: float = 1.6, strength: float = 0.25) -> void:
	if n == null or not is_instance_valid(n):
		return
	_kill(n)
	n.self_modulate = Color.WHITE
	if not on or Fx.level() <= 0 or not n.is_inside_tree():
		return
	var tint := Color.WHITE.lerp(color, 0.5)
	tint = Color(1.0 + strength * (tint.r - 0.5), 1.0 + strength * (tint.g - 0.5), 1.0 + strength * (tint.b - 0.5), 1.0)
	var tw := UiAnim.color_loop(n, &"self_modulate", Color.WHITE, tint, period * 0.5, Tween.TRANS_SINE)     # a gradini (resoconto 100)
	n.set_meta(META_TW, tw)


static func is_active(n: CanvasItem) -> bool:
	return n.has_meta(META_TW)
