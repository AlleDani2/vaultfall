class_name FxBanner
extends Control
## Striscione che scende dall'alto con un luccichio che lo attraversa (missione completata, impresa sbloccata,
## nuovo sblocco). Disegnato a codice con pixel quadrati e colori propri (non dipende dal tema dei pannelli).
## Non blocca il mouse. Durata ~3 s; «riduci animazioni»: compare fermo e sparisce senza scorrere né luccichio.

signal done

const H := 76.0
const SLIDE_IN := 0.28
const SLIDE_OUT := 0.3
const Y_REST := 56.0

var title: String = ""
var subtitle: String = ""
var accent: Color = FxPalette.GOLD
var icon: Texture2D = null
var hold: float = 2.0
var age: float = 0.0
var _sparked: int = 0
var _static: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_title: String, p_sub: String, p_accent: Color, p_icon: Texture2D = null, p_hold: float = 2.0) -> void:
	title = p_title
	subtitle = p_sub
	accent = p_accent
	icon = p_icon
	hold = p_hold
	_static = Fx.level() <= 0


func total() -> float:
	return SLIDE_IN + hold + SLIDE_OUT


func _process(dt: float) -> void:
	age += dt
	if not _static:
		if _sparked == 0 and age > 0.3:
			_sparked = 1
			_sparkle()
		elif _sparked == 1 and age > 0.75:
			_sparked = 2
			_sparkle()
	if age >= total():
		done.emit()
		queue_free()
		return
	queue_redraw()


func _sparkle() -> void:
	var w := _w()
	var x := _x()
	for k in 2:
		var p := Vector2(x + randf_range(0.1, 0.9) * w, Y_REST + randf_range(8.0, H - 8.0))
		Fx.burst("glint", p, [FxPalette.lighten(accent, 0.5), FxPalette.WHITE], 1.0, 1.0)


func _w() -> float:
	return minf(480.0, size.x - 32.0)


## In alto A DESTRA, sotto la barra (revisione grafica 1.0, problema 9): non copre più titolo e schede della pagina.
## 64 px di margine a destra = binario destro (52) + respiro.
func _x() -> float:
	return roundf(maxf(16.0, size.x - _w() - 64.0))


func _y() -> float:
	if _static:
		return Y_REST
	if age < SLIDE_IN:
		var u := age / SLIDE_IN
		var e := 1.0 + 2.70158 * pow(u - 1.0, 3.0) + 1.70158 * pow(u - 1.0, 2.0)
		return lerpf(-H, Y_REST, e)
	var left := total() - age
	if left < SLIDE_OUT:
		var v := 1.0 - left / SLIDE_OUT
		return lerpf(Y_REST, -H - 4.0, v * v)
	return Y_REST


func _draw() -> void:
	var w := _w()
	var x := _x()
	var y := roundf(_y())
	var dark := Color(0.07, 0.06, 0.09, 0.98)
	draw_rect(Rect2(x, y, w, H), dark)
	draw_rect(Rect2(x, y, w, 3), accent)
	draw_rect(Rect2(x, y + H - 3, w, 3), FxPalette.darken(accent, 0.45))
	draw_rect(Rect2(x, y, 3, H), FxPalette.darken(accent, 0.2))
	draw_rect(Rect2(x + w - 3, y, 3, H), FxPalette.darken(accent, 0.2))
	for cx in [x - 3.0, x + w - 5.0]:
		draw_rect(Rect2(cx, y + H * 0.5 - 6.0, 8, 12), accent)
	# luccichio: banda diagonale a gradini che attraversa il pannello
	if not _static and age > 0.3 and age < 1.15:
		var u := (age - 0.3) / 0.85
		var bx := x - 40.0 + u * (w + 80.0)
		var rows := int(H / 4.0)
		for r in rows:
			var rx := bx + float(r) * 3.0 - 20.0
			var x0 := clampf(rx, x + 3.0, x + w - 3.0)
			var x1 := clampf(rx + 16.0, x + 3.0, x + w - 3.0)
			if x1 > x0:
				draw_rect(Rect2(x0, y + 3.0 + float(r) * 4.0, x1 - x0, 4.0), Color(1, 1, 1, 0.07))
				var m0 := clampf(rx + 5.0, x + 3.0, x + w - 3.0)
				var m1 := clampf(rx + 11.0, x + 3.0, x + w - 3.0)
				if m1 > m0:
					draw_rect(Rect2(m0, y + 3.0 + float(r) * 4.0, m1 - m0, 4.0), Color(1, 1, 1, 0.16))
	var f := get_theme_default_font()
	var tx := x
	var tw_ := w
	if icon != null:
		draw_texture_rect(icon, Rect2(x + 16.0, y + 18.0, 40, 40), false)
		tx = x + 56.0
		tw_ = w - 56.0
	var cy := y + H * 0.5
	draw_string_outline(f, Vector2(tx, cy - 2.0), title, HORIZONTAL_ALIGNMENT_CENTER, tw_, 24, 4, Color(0, 0, 0, 0.8))
	draw_string(f, Vector2(tx, cy - 2.0), title, HORIZONTAL_ALIGNMENT_CENTER, tw_, 24, FxPalette.lighten(accent, 0.45))
	if not subtitle.is_empty():
		draw_string(f, Vector2(tx, cy + 22.0), subtitle, HORIZONTAL_ALIGNMENT_CENTER, tw_, 14, FxPalette.CREAM)
