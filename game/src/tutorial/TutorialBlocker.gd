class_name TutorialBlocker
extends Control
## Bloccante di un passo «premi proprio questo» (TutorialDirector): ferma i clic fuori dal controllo evidenziato, ma lascia
## passare quelli sulle zone in `allow` (il «Vai» dell'Obiettivo attuale porta nello stesso posto: non va mai ignorato in
## silenzio) e avvisa con `blocked` quando ferma un clic, così la scheda può dire «premi il pulsante evidenziato».

signal blocked

## Zone dello schermo (coordinate dello schermo) dove i clic passano. Lista condivisa dai quattro bloccanti.
var allow: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):      # l'override sostituisce il controllo di base: il rettangolo va controllato qui
		return false
	var g := point + position
	for r in allow:
		if (r as Rect2).has_point(g):
			return false
	return true


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		blocked.emit()
