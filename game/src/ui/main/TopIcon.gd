class_name TopIcon
extends Button
## Icona-pulsante della barra alta (D8, docs/ui_redesign/06 §3.2): Pausa/Riprendi, Salva (con stato), Impostazioni. Il simbolo è
## DISEGNATO in codice (nessun glifo del font, nessun PNG): non dipende dai font di sistema e non si taglia a nessuna
## larghezza. Il testo resta vuoto; il significato sta nel tooltip, che porta anche il tasto.

enum Kind { PAUSE, PLAY, SAVE_OK, SAVE_DIRTY, SAVE_BUSY, SETTINGS, HELP }

## Tutte le icone della barra hanno la stessa misura (rapporto 08 punto 11: allineamenti): quadrate, alte come i riquadri di Oro/Deposito.
const SIZE := Vector2(32, 32)
const AMBER := Color("#e0a43a")
const HELP_COLOR := Color("#d8d2c0")

var kind: int = Kind.PAUSE:
	set(v):
		if v != kind:
			kind = v
			queue_redraw()


func _init() -> void:
	custom_minimum_size = SIZE
	flat = true
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var col := HELP_COLOR if kind == Kind.HELP else get_theme_color("font_color")      # il testo del «?» è nascosto: colore fisso
	if is_hovered() or has_focus():
		if kind == Kind.HELP:
			col = col.lightened(0.25)
		else:
			col = get_theme_color("font_hover_color") if has_theme_color("font_hover_color") else col.lightened(0.25)
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.94, 0.85, 0.63, 0.9), false, 2.0)
	var c := size * 0.5
	match kind:
		Kind.PAUSE:
			draw_rect(Rect2(c + Vector2(-6, -7), Vector2(4, 14)), col)
			draw_rect(Rect2(c + Vector2(2, -7), Vector2(4, 14)), col)
		Kind.PLAY:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -8), c + Vector2(7, 0), c + Vector2(-5, 8)]), AMBER)
		Kind.SAVE_OK:
			draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 5), c + Vector2(7, -6)]), col, 2.5, true)
		Kind.SAVE_DIRTY:
			draw_circle(c, 5.0, AMBER)
		Kind.SAVE_BUSY:
			draw_arc(c, 7.0, -0.4, TAU * 0.78, 20, col, 2.5, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(4, -10), c + Vector2(10, -5), c + Vector2(2, -4)]), col)
		Kind.SETTINGS:
			_draw_gear(c, col)
		Kind.HELP:
			_draw_help(c, col)


## Ingranaggio: corona con 8 denti e foro centrale.
func _draw_gear(c: Vector2, col: Color) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * 6.0, c + d * 10.0, col, 3.0)
	draw_arc(c, 6.0, 0.0, TAU, 24, col, 3.0, true)
	draw_circle(c, 2.0, col)


## «?» in un cerchio: DISEGNATO come le altre icone (prima il pulsante era una TopIcon con il tipo «pausa» e il testo «?» sovrapposti:
## l'ultima icona della barra era illeggibile, rapporto 08 punto 11). Il testo del pulsante resta per l'accessibilità, ma non si vede.
func _draw_help(c: Vector2, col: Color) -> void:
	draw_arc(c, 10.0, 0.0, TAU, 28, col, 2.0, true)
	var f := get_theme_font("font")
	var fs := 15
	var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(c.x - w * 0.5, c.y + f.get_ascent(fs) - f.get_height(fs) * 0.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
