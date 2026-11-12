class_name MenuMark
extends Control
## Segno dell'«attività in corso» sopra una voce del menù laterale (resoconto UI 05, rivisto dal rapporto grafica 08 punto 4).
## NON è più una riga colorata: la riga verde si confondeva con la voce selezionata (riempimento dorato). Ora è un PUNTO a destra:
##   - principale in corso: punto pieno verde che «respira»; in pausa o in attesa: due barrette;
##   - parallela: anello verde chiaro (in pausa: barrette vuote);
##   - sotto la voce, una linea sottile di avanzamento del ciclo (solo se il dato esiste).
## La principale «respira» piano (self_modulate a gradini, UiAnim: nessun ridisegno a 60 Hz); con «Riduci animazioni», in
## pausa o con la finestra in secondo piano resta ferma ma ben visibile. Non cattura il mouse.
## Non contiene numeri di gioco: solo misure grafiche.

const ICON_W := 16.0                       # spazio riservato a destra (il segnale numerico si sposta di tanto)
const DOT_R := 4.5
const LIVE := Color("#5fd38a")             # attività: verde, MAI il colore della selezione (oro)
const LIVE_SIDE := Color("#9be0b4")
const TRACK_COLOR := Color(1, 1, 1, 0.12)
const BREATH_LOW := 0.45
const BREATH_HALF_S := 1.1

var role: String = ""
var state: String = ""
var frac: float = -1.0
var tint: Color = Color.WHITE

var _tween: Tween
var _fill_px: int = -1
var _pulse: Control                        # il punto: l'unica parte che «respira»


func _init() -> void:
	name = "ActivityMark"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pulse = Control.new()
	_pulse.name = "Pulse"
	_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pulse)
	_pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pulse.draw.connect(_draw_pulse)


func _ready() -> void:
	EventBus.settings_changed.connect(_on_setting)
	resized.connect(queue_redraw)
	resized.connect(_pulse.queue_redraw)
	_apply_motion()


## Imposta lo stato; ritorna true se qualcosa di visibile è cambiato.
func set_state(new_role: String, new_state: String, new_frac: float, new_tint: Color) -> bool:
	var changed := new_role != role or new_state != state or new_tint != tint or (new_frac < 0.0) != (frac < 0.0)
	role = new_role
	state = new_state
	tint = new_tint
	if changed:
		frac = new_frac
		_fill_px = -1
		_apply_motion()
		queue_redraw()
		_pulse.queue_redraw()
	else:
		set_frac(new_frac)
	return changed


## Avanzamento (chiamato a 10 Hz): si ridisegna solo se cambia il numero di pixel riempiti.
func set_frac(f: float) -> void:
	if f < 0.0 or frac < 0.0:
		frac = f
		return
	frac = clampf(f, 0.0, 1.0)
	var px := int(frac * maxf(0.0, size.x - 2.0))
	if px != _fill_px:
		_fill_px = px
		queue_redraw()


func is_breathing() -> bool:
	return _tween != null and _tween.is_valid()


func _on_setting(key: String, _v: Variant) -> void:
	if key == "reduce_motion":
		_apply_motion()


## Respiro lento solo per la principale in corso, senza «Riduci animazioni».
func _apply_motion() -> void:
	if not is_inside_tree():
		return
	var want := role == MenuActivity.ROLE_MAIN and state == MenuActivity.STATE_RUN and not bool(Settings.get_value("reduce_motion"))
	if want and not is_breathing():
		_tween = UiAnim.color_loop(_pulse, &"self_modulate", Color.WHITE, Color(1, 1, 1, BREATH_LOW), BREATH_HALF_S, Tween.TRANS_SINE)
	elif not want:
		if _tween != null:
			_tween.kill()
			_tween = null
		_pulse.self_modulate = Color.WHITE


func pulse_layer() -> Control:
	return _pulse


## Linea di avanzamento in fondo alla voce (2 px, dentro i margini del testo).
func _draw() -> void:
	if role.is_empty() or frac < 0.0:
		return
	var main := role == MenuActivity.ROLE_MAIN
	var y := size.y - 3.0
	var inner := size.x - 16.0
	draw_rect(Rect2(8.0, y, inner, 2.0), TRACK_COLOR)
	var fill := LIVE if main else LIVE_SIDE
	fill.a = 0.9 if main else 0.55
	draw_rect(Rect2(8.0, y, inner * frac, 2.0), fill)


func _draw_pulse() -> void:
	if role.is_empty():
		return
	var main := role == MenuActivity.ROLE_MAIN
	_draw_icon(Vector2(size.x - 8.0 - ICON_W * 0.5, size.y * 0.5), main)


func _draw_icon(c: Vector2, main: bool) -> void:
	var col := LIVE if main else LIVE_SIDE
	if state != MenuActivity.STATE_RUN:                # pausa / attesa: due barre
		for dx in [-2.2, 2.2]:
			var r := Rect2(c.x + dx - 1.2, c.y - 4.5, 2.4, 9.0)
			if main:
				_pulse.draw_rect(r, col)
			else:
				_pulse.draw_rect(r, col, false, 1.0)
		return
	if main:
		_pulse.draw_circle(c, DOT_R, col)
	else:
		_pulse.draw_arc(c, DOT_R - 0.75, 0.0, TAU, 20, col, 1.5, true)
