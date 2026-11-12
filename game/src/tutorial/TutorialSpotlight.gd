class_name TutorialSpotlight
extends Control
## Strato di evidenziazione del tutorial: oscura leggermente lo schermo, lascia un "buco" sul controllo da premere,
## gli disegna intorno una cornice dorata che pulsa (ferma con «Riduci animazioni») e una freccia che indica verso di lui.
## Solo disegno: non intercetta mai il mouse (i quattro bloccanti per i passi "premi proprio questo" li crea il Director).

const GOLD := Color("#f0c24f")
const DIM := Color(0.02, 0.02, 0.04, 0.46)
const DIM_FULL := Color(0.02, 0.02, 0.04, 0.30)
const PULSE_HZ := 2.2
const BOB_PX := 5.0
const ARROW_LEN := 22.0
const ARROW_W := 26.0

var has_hole: bool = false
var hole: Rect2 = Rect2()
var arrow_side: String = ""        # lato del buco da cui parte la freccia: left | right | above | below | ""
var calm: bool = false              # true = niente movimento
var time: float = 0.0


func _init() -> void:
	name = "TutorialSpotlight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	time += dt
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if not has_hole:
		draw_rect(Rect2(0, 0, w, h), DIM_FULL)
		return
	var r := hole
	draw_rect(Rect2(0, 0, w, maxf(0.0, r.position.y)), DIM)
	draw_rect(Rect2(0, r.end.y, w, maxf(0.0, h - r.end.y)), DIM)
	draw_rect(Rect2(0, r.position.y, maxf(0.0, r.position.x), r.size.y), DIM)
	draw_rect(Rect2(r.end.x, r.position.y, maxf(0.0, w - r.end.x), r.size.y), DIM)
	var pulse := 1.0 if calm else 0.5 + 0.5 * sin(time * TAU * PULSE_HZ * 0.5)
	for i in 3:
		draw_rect(r.grow(float(i + 1) * 3.0), Color(GOLD.r, GOLD.g, GOLD.b, (0.22 - 0.06 * i) * (0.6 + 0.4 * pulse)), false, 2.0)
	draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.75 + 0.25 * pulse), false, 3.0 + (0.0 if calm else 1.5 * pulse))
	if not arrow_side.is_empty():
		_draw_arrow(r)


func _draw_arrow(r: Rect2) -> void:
	var bob := 0.0 if calm else sin(time * TAU * 1.1) * BOB_PX
	var gap := 8.0 + bob
	var tip: Vector2
	var dir: Vector2                    # verso il bersaglio
	match arrow_side:
		"left":
			tip = Vector2(r.position.x - gap, r.get_center().y)
			dir = Vector2.RIGHT
		"right":
			tip = Vector2(r.end.x + gap, r.get_center().y)
			dir = Vector2.LEFT
		"above":
			tip = Vector2(r.get_center().x, r.position.y - gap)
			dir = Vector2.DOWN
		_:
			tip = Vector2(r.get_center().x, r.end.y + gap)
			dir = Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	var base := tip - dir * ARROW_LEN
	var pts := PackedVector2Array([tip, base + side * ARROW_W * 0.5, base - side * ARROW_W * 0.5])
	if not arrow_valid(pts):
		return
	draw_colored_polygon(pts, GOLD)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.25, 0.16, 0.02), 2.0)


## Triangolo disegnabile: punti finiti e area non nulla. Con un bersaglio che sparisce a metà cambio di schermata il rettangolo
## può avere valori non finiti e il motore scriveva «Invalid polygon data, triangulation failed» (rapporto 95 R7).
static func arrow_valid(pts: PackedVector2Array) -> bool:
	if pts.size() != 3:
		return false
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y)):
			return false
	return absf((pts[1] - pts[0]).cross(pts[2] - pts[0])) > 1.0
