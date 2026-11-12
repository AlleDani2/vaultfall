class_name ColumnGrip
extends Control
## Maniglia sottile tra l'area contenuto e la colonna destra (G24): trascinandola a sinistra/destra la colonna si
## allarga/si restringe. Emette `dragged(dx)` (dx > 0 = verso destra) durante il trascinamento e `released` al rilascio.
## Si muove anche con la tastiera (frecce sinistra/destra a maniglia attiva) e al doppio clic torna alla larghezza di base.

signal dragged(dx: float)
signal released
signal reset_requested

const STEP_KEY_PX := 24.0

var _dragging: bool = false


func _init() -> void:
	name = "ColumnGrip"
	custom_minimum_size = Vector2(6, 0)
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "UI_UIB_GRIP_TIP"


func _draw() -> void:
	var col := Color(0.62, 0.55, 0.38, 0.9 if (_dragging or has_focus()) else 0.35)
	draw_rect(Rect2(size.x * 0.5 - 1.0, 4.0, 2.0, maxf(0.0, size.y - 8.0)), col)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click:
			reset_requested.emit()
		_dragging = mb.pressed
		if not mb.pressed:
			released.emit()
		queue_redraw()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		dragged.emit(mm.relative.x)
		accept_event()
		return
	var k := event as InputEventKey
	if k != null and k.pressed and (k.keycode == KEY_LEFT or k.keycode == KEY_RIGHT):
		dragged.emit(STEP_KEY_PX if k.keycode == KEY_RIGHT else -STEP_KEY_PX)
		released.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()
