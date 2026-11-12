class_name FxCeremony
extends Control
## Cerimonia breve (2-3 s) per Stella, Rito e Rifondazione: pixel che convergono, scoppio, anello, raggi, titolo che
## «pompa» a gradini. SALTABILE con Spazio / Invio / Esc / clic (e l'input usato per saltare non arriva al pulsante
## che ha il focus). Non blocca il mouse. Con effetti «ridotti» dura meno e senza lampo né raggi.

signal done

var title: String = ""
var subtitle: String = ""
var accent: Color = FxPalette.GOLD
var kind: String = "star"            # star | rite | refound
var dur: float = 2.6
var age: float = 0.0
var skipped: bool = false
var _boom: bool = false
var _confetti: bool = false
var _rays: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_title: String, p_sub: String, p_accent: Color, p_kind: String = "star") -> void:
	title = p_title
	subtitle = p_sub
	accent = p_accent
	kind = p_kind
	var lv := Fx.level()
	_rays = lv >= 2
	dur = 2.8 if p_kind == "refound" else (2.6 if lv >= 2 else 1.6)
	if lv < 2:
		dur = minf(dur, 1.6)


func skip() -> void:
	if not skipped:
		skipped = true
		age = maxf(age, dur - 0.25)


func _input(e: InputEvent) -> void:
	if age >= dur - 0.25:
		return
	if e is InputEventKey and e.pressed and not e.echo and \
			(e.keycode == KEY_SPACE or e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_ESCAPE):
		skip()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed:
		skip()


func _center() -> Vector2:
	return (size * 0.5 - Vector2(0, 30.0)).round()


func _process(dt: float) -> void:
	age += dt
	if not _boom and age >= 0.45 and not skipped:
		_boom = true
		var c := _center()
		Fx.screen_flash(FxPalette.lighten(accent, 0.6), 0.3, 0.45)
		Fx.ring(c, accent, 150.0, 0.8, FxPalette.WHITE, 3)
		Fx.ring(c, FxPalette.lighten(accent, 0.4), 90.0, 0.55, FxPalette.WHITE, 3)
		Fx.burst("star", c, [], 1.5, 1.4, Vector2.ZERO, 3)
	if not _confetti and age >= 0.7 and not skipped and kind != "star":
		_confetti = true
		Fx.confetti(Rect2(Vector2(size.x * 0.25, 40.0), Vector2(size.x * 0.5, 4.0)), 2)
	if age >= dur:
		done.emit()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var env := minf(age / 0.3, 1.0) * minf((dur - age) / 0.35, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.015, 0.03, 0.55 * clampf(env, 0.0, 1.0)))
	var c := _center()
	# 1) pixel che convergono verso il centro
	if age < 0.5:
		var u := age / 0.5
		var r := lerpf(260.0, 6.0, u * u)
		for i in 24:
			var a := TAU * float(i) / 24.0 + u * 1.4
			var q := c + Vector2(cos(a), sin(a)) * r
			draw_rect(Rect2(q.round() - Vector2(2, 2), Vector2(4, 4)), Color(accent.r, accent.g, accent.b, 0.4 + 0.6 * u))
	# 2) raggi a quadratini che ruotano piano
	if _rays and age > 0.45:
		var u2 := clampf((age - 0.45) / 0.5, 0.0, 1.0)
		var fade := minf(1.0, (dur - age) / 0.5)
		for k in 16:
			var a2 := TAU * float(k) / 16.0 + age * 0.25
			var dir := Vector2(cos(a2), sin(a2))
			for j in 8:
				var d := (50.0 + float(j) * 28.0) * u2
				var q2 := c + dir * d
				var sq := 7.0 - float(j) * 0.6
				draw_rect(Rect2(q2.round() - Vector2(sq, sq) * 0.5, Vector2(sq, sq)),
					Color(accent.r, accent.g, accent.b, (0.75 - float(j) * 0.08) * fade))
	# 3) titolo (pop a gradini) e sottotitolo
	if age > 0.5:
		var f := get_theme_default_font()
		if age < dur - 0.4:
			draw_string(f, Vector2(0, size.y - 36.0), tr("UI_FX_SKIP_HINT"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 1, 1, 0.45))
		var fs := 56 if age < 0.58 else (50 if age < 0.66 else 44)
		var a3 := minf(1.0, (dur - age) / 0.35)
		var tc := FxPalette.lighten(accent, 0.45)
		tc.a = a3
		var ty := c.y + 14.0
		draw_string_outline(f, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 8, Color(0, 0, 0, 0.85 * a3))
		draw_string(f, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, tc)
		if age > 0.85 and not subtitle.is_empty():
			var sc := FxPalette.CREAM
			sc.a = a3 * minf(1.0, (age - 0.85) / 0.2)
			draw_string_outline(f, Vector2(0, ty + 40.0), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 5, Color(0, 0, 0, 0.8 * sc.a))
			draw_string(f, Vector2(0, ty + 40.0), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, sc)
