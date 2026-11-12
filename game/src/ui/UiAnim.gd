class_name UiAnim
extends RefCounted
## Animazioni di colore «a gradini» (resoconto 100). Un respiro luminoso lento animato a 60 Hz costringe il motore a
## ridisegnare tutto il canvas a ogni fotogramma (anche per una sola icona) anche se l'occhio non vede la differenza:
## su un PC lento è il costo maggiore di una schermata ferma. Qui il valore interpolato è quantizzato in STEPS gradini:
## `CanvasItem.modulate/self_modulate` ignora un valore uguale al precedente, quindi il ridisegno avviene solo quando
## il gradino cambia (~8-10 volte al secondo per un respiro di 1,4 s) e il tween resta una chiamata quasi gratuita.

const STEPS := 6


## Valore quantizzato in `steps` gradini (0..1).
static func quantize(v: float, steps: int = STEPS) -> float:
	return roundf(clampf(v, 0.0, 1.0) * float(steps)) / float(steps)


## Respiro continuo di `prop` (modulate o self_modulate) tra `a` e `b`: `half_secs` per andare e altrettanti per tornare.
## Ritorna il Tween (legato al nodo). Il chiamante lo ferma con kill().
static func color_loop(n: CanvasItem, prop: StringName, a: Color, b: Color, half_secs: float, trans: Tween.TransitionType = Tween.TRANS_LINEAR,
		steps: int = STEPS) -> Tween:
	var tw := n.create_tween().set_loops()
	tw.tween_method(_apply.bind(n, prop, a, b, steps), 0.0, 1.0, half_secs).set_trans(trans)
	tw.tween_method(_apply.bind(n, prop, a, b, steps), 1.0, 0.0, half_secs).set_trans(trans)
	return tw


static func _apply(v: float, n: CanvasItem, prop: StringName, a: Color, b: Color, steps: int) -> void:
	if is_instance_valid(n) and Clock.focused:        # in secondo piano il respiro si ferma: niente ridisegni
		n.set(prop, a.lerp(b, quantize(v, steps)))
