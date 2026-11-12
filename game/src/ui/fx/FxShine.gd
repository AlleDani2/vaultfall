class_name FxShine
extends RefCounted
## ShineSweep: una banda di luce a gradini attraversa un'icona o una tessera (shader shine.gdshader).
## Si applica a un nodo senza materiale proprio e lo toglie alla fine. Con «riduci animazioni» non fa nulla.

const SHADER: Shader = preload("res://src/ui/fx/shine.gdshader")


static func sweep(n: CanvasItem, color: Color = Color(1, 1, 1), secs: float = 0.6, strength: float = 0.75, delay: float = 0.0) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or Fx.level() <= 0:
		return false
	if n.material != null:
		return false                      # non si sovrascrive il materiale di qualcun altro
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("progress", -0.5)
	m.set_shader_parameter("shine_color", color)
	m.set_shader_parameter("strength", strength)
	n.material = m
	var tw := n.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("progress", v), -0.5, 1.5, secs) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(n) and n.material == m:
			n.material = null)
	return true
