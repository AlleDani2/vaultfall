class_name GamepadGlyphs
extends Control
## Glifi dei pulsanti del controller, disegnati in codice (nessun PNG, nessun marchio): cerchio colorato con la lettera (stile
## «xbox» e «deck»), simboli geometrici (stile «playstation»), targhetta arrotondata per spalle, Start e Back.
## Parte statica: nomi dei pulsanti per stile e riconoscimento dello stile dal nome del controller. Parte nodo: `PadGlyph`.
##   var g := GamepadGlyphs.make(JOY_BUTTON_A, "xbox")      un Control pronto da mettere in un contenitore

const STYLES: PackedStringArray = ["xbox", "playstation", "deck"]
const FACE_COLORS := {
	JOY_BUTTON_A: Color("5aa85a"), JOY_BUTTON_B: Color("c9534f"), JOY_BUTTON_X: Color("4f7fc9"), JOY_BUTTON_Y: Color("d2a93a"),
}
const PS_SHAPES := {JOY_BUTTON_A: "cross", JOY_BUTTON_B: "circle", JOY_BUTTON_X: "square", JOY_BUTTON_Y: "triangle"}

var button: int = JOY_BUTTON_A
var style: String = "xbox"
var _label: String = ""


## Stile dei glifi dal nome del controller (Input.get_joy_name): PlayStation, Steam Deck o, in mancanza, Xbox/generico.
static func style_for_name(joy_name: String) -> String:
	var n := joy_name.to_lower()
	if n.contains("playstation") or n.contains("dualsense") or n.contains("dualshock") or n.contains("ps4") or n.contains("ps5") \
			or n.contains("sony"):
		return "playstation"
	if n.contains("steam") or n.contains("deck"):
		return "deck"
	return "xbox"


## Stile da usare: la scelta del giocatore («auto» = quello del controller collegato).
static func resolve_style(choice: String, joy_name: String = "") -> String:
	if STYLES.has(choice):
		return choice
	return style_for_name(joy_name)


## Stile in uso adesso: la scelta delle Impostazioni, oppure (auto) quello del primo controller collegato.
static func current_style() -> String:
	var pads := Input.get_connected_joypads()
	return resolve_style(str(Settings.get_value("pad_glyphs")), Input.get_joy_name(pads[0]) if not pads.is_empty() else "")


## Nome corto del pulsante nello stile dato («A», «LB», «L1», «Menu»...). Per lo stile PlayStation le facce hanno il nome del simbolo.
static func button_label(btn: int, st: String = "xbox") -> String:
	var ps := st == "playstation"
	match btn:
		JOY_BUTTON_A:
			return TranslationServer.translate("UI_I10_PS_CROSS") if ps else "A"
		JOY_BUTTON_B:
			return TranslationServer.translate("UI_I10_PS_CIRCLE") if ps else "B"
		JOY_BUTTON_X:
			return TranslationServer.translate("UI_I10_PS_SQUARE") if ps else "X"
		JOY_BUTTON_Y:
			return TranslationServer.translate("UI_I10_PS_TRIANGLE") if ps else "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "L1" if st != "xbox" else "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "R1" if st != "xbox" else "RB"
		JOY_BUTTON_START:
			return "Options" if ps else "Menu"
		JOY_BUTTON_BACK:
			return "Create" if ps else "View"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_DPAD_UP:
			return "↑"
		JOY_BUTTON_DPAD_DOWN:
			return "↓"
		JOY_BUTTON_DPAD_LEFT:
			return "←"
		JOY_BUTTON_DPAD_RIGHT:
			return "→"
		JOY_BUTTON_GUIDE:
			return "Guide"
	return "#%d" % btn


## Un glifo pronto: il pulsante `btn` nello stile `st`.
static func make(btn: int, st: String = "xbox") -> GamepadGlyphs:
	var g := GamepadGlyphs.new()
	g.button = btn
	g.style = st
	g.name = "Glyph_%d" % btn
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.refresh_size()
	return g


func set_glyph(btn: int, st: String) -> void:
	button = btn
	style = st
	refresh_size()
	queue_redraw()


func _is_face() -> bool:
	return FACE_COLORS.has(button)


func refresh_size() -> void:
	_label = button_label(button, style)
	if _is_face():
		custom_minimum_size = Vector2(26, 26)
	else:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x if font != null else 24.0
		custom_minimum_size = Vector2(maxf(30.0, w + 14.0), 24)
	size = custom_minimum_size


func _draw() -> void:
	var font := get_theme_default_font() if is_inside_tree() else ThemeDB.fallback_font
	var s := size
	if _is_face():
		var c: Color = FACE_COLORS[button]
		var ctr := s * 0.5
		var r := minf(s.x, s.y) * 0.5 - 1.0
		draw_circle(ctr, r, Color(0.07, 0.07, 0.09, 0.95))
		draw_arc(ctr, r, 0.0, TAU, 28, c, 2.0, true)
		if style == "playstation":
			_draw_shape(ctr, r * 0.5, str(PS_SHAPES[button]), c)
		elif font != null:
			var ts := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			draw_string(font, Vector2(ctr.x - ts.x * 0.5, ctr.y + 5.5), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c.lightened(0.25))
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.1, 0.13, 0.95)
	box.border_color = Color(0.78, 0.78, 0.82)
	box.set_border_width_all(2)
	box.set_corner_radius_all(7)
	draw_style_box(box, Rect2(Vector2.ZERO, s))
	if font != null:
		var tw := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(font, Vector2((s.x - tw.x) * 0.5, s.y * 0.5 + 4.5), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.92, 0.95))


func _draw_shape(ctr: Vector2, r: float, shape: String, c: Color) -> void:
	var lw := 2.0
	match shape:
		"cross":
			draw_line(ctr + Vector2(-r, -r), ctr + Vector2(r, r), c, lw, true)
			draw_line(ctr + Vector2(-r, r), ctr + Vector2(r, -r), c, lw, true)
		"circle":
			draw_arc(ctr, r, 0.0, TAU, 20, c, lw, true)
		"square":
			draw_rect(Rect2(ctr - Vector2(r, r), Vector2(r, r) * 2.0), c, false, lw)
		"triangle":
			var pts := PackedVector2Array([ctr + Vector2(0, -r), ctr + Vector2(r, r * 0.8), ctr + Vector2(-r, r * 0.8), ctr + Vector2(0, -r)])
			draw_polyline(pts, c, lw, true)
