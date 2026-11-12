class_name MarketChart
extends Control
## Graficino a linee disegnato con _draw (nessuna texture): serie di valori con minimo/massimo ai lati.
## values: Array di float; baseline: linea tratteggiata facoltativa (es. 1,0 = prezzo di riferimento).

var values: Array = []
var baseline: float = -1.0
var line_color: Color = Color(0.45, 0.78, 0.55)
var fill_under: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(240, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(v: Array, p_baseline: float = -1.0) -> void:
	values = v
	baseline = p_baseline
	custom_minimum_size.y = 100.0 if v.size() >= 2 else 36.0          # senza storia: una riga di testo, non un riquadro vuoto da 100 px
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	if values.size() < 2 or r.size.x <= 0.0:
		# stato vuoto amichevole invece di un riquadro nero muto
		draw_string(ThemeDB.fallback_font, Vector2(10, size.y * 0.5 + 5.0), TranslationServer.translate("UI_MARKET_CHART_NODATA"),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, UiType.NOTE, Color(1, 1, 1, 0.6))
		return
	var lo := INF
	var hi := -INF
	for x in values:
		lo = minf(lo, float(x))
		hi = maxf(hi, float(x))
	if baseline >= 0.0:
		lo = minf(lo, baseline)
		hi = maxf(hi, baseline)
	if hi - lo < 1e-9:
		lo -= 0.5
		hi += 0.5
	var pts := PackedVector2Array()
	for i in values.size():
		var px := r.position.x + r.size.x * float(i) / float(values.size() - 1)
		var py := r.position.y + r.size.y * (1.0 - (float(values[i]) - lo) / (hi - lo))
		pts.append(Vector2(px, py))
	if baseline >= 0.0:
		var by := r.position.y + r.size.y * (1.0 - (baseline - lo) / (hi - lo))
		var x := r.position.x
		while x < r.end.x:
			draw_line(Vector2(x, by), Vector2(minf(x + 4.0, r.end.x), by), Color(1, 1, 1, 0.35), 1.0)
			x += 8.0
	if fill_under:
		var poly := PackedVector2Array(pts)
		poly.append(Vector2(r.end.x, r.end.y))
		poly.append(Vector2(r.position.x, r.end.y))
		draw_colored_polygon(poly, Color(line_color, 0.18))
	draw_polyline(pts, line_color, 2.0, true)
	draw_circle(pts[pts.size() - 1], 3.0, line_color)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(6, 16), "%.2f" % hi, HORIZONTAL_ALIGNMENT_LEFT, -1, UiType.NOTE, Color(1, 1, 1, 0.7))
	draw_string(font, Vector2(6, size.y - 6), "%.2f" % lo, HORIZONTAL_ALIGNMENT_LEFT, -1, UiType.NOTE, Color(1, 1, 1, 0.7))
