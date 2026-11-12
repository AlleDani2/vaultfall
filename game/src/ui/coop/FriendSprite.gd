class_name FriendSprite
extends Control
## Personaggino di un amico (COOP-2, livello A): omino pixel-art 16x24 disegnato in codice con `_draw` (nessun PNG,
## nessuna operazione sulla geometria di immagini generate), ingrandito x2 a pixel netti. Colore = classe, animazione
## = attività ricevuta nella presenza: colpisce (strike), taglia (chop), picconata (pick), batte il martello (hammer),
## sega/cuce (saw), pesca con la canna (fish), cucina (cook), distilla (brew), raccoglie (gather), sgattaiola (sneak),
## cammina (walk), apre una Cassa con scintille (crate), dorme con «zZz» (sleep).
## Solo presentazione: lo stato arriva da CoopNetService.friends(); il tempo dell'animazione è un contatore locale.

signal clicked()

const PX := 2                      # ingrandimento: 1 pixel logico = 2 pixel sullo schermo
const W := 16
const H := 24
## Colore per stile di classe (classi figlie ereditano dal padre; sconosciuta = grigio).
const STYLE_COLORS := {"melee": Color(0.78, 0.30, 0.25), "ranged": Color(0.33, 0.62, 0.30),
	"magic": Color(0.36, 0.45, 0.85), "hybrid": Color(0.62, 0.38, 0.78)}
const SKIN := Color(0.93, 0.78, 0.62)
const DARK := Color(0.15, 0.13, 0.12)
const TOOL := Color(0.62, 0.55, 0.45)
const METAL := Color(0.80, 0.82, 0.86)

var anim := "sleep"
var body_color := Color(0.55, 0.55, 0.55)
var online := true
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(W * PX + 8, H * PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	set_process(true)


func setup(class_id: String, p_anim: String, p_online: bool) -> void:
	anim = p_anim
	online = p_online
	body_color = color_for_class(class_id)
	modulate.a = 1.0 if online else 0.45
	queue_redraw()


## Colore della classe dai dati (stile della classe o della classe padre).
static func color_for_class(class_id: String) -> Color:
	var tree := Engine.get_main_loop() as SceneTree
	var dr: Node = tree.root.get_node_or_null("/root/DataRegistry") if tree != null else null
	if dr == null or class_id.is_empty():
		return Color(0.55, 0.55, 0.55)
	var cd: Dictionary = dr.get_def("classes", class_id)
	if cd.has("parent"):
		cd = dr.get_def("classes", str(cd.parent))
	var style := str(cd.get("style", "hybrid" if cd.has("styles") else ""))
	return STYLE_COLORS.get(style, Color(0.55, 0.55, 0.55))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var before := int(_t * 6.0)
	_t += delta
	if int(_t * 6.0) != before:        # 6 fotogrammi al secondo: basta e non pesa sulla UI
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


func _px(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(Vector2(x * PX + 4, y * PX), Vector2(w * PX, h * PX)), c)


func frame() -> int:
	return int(_t * 6.0) % 4


func _draw() -> void:
	var f := frame()
	var bob := 1 if (anim == "walk" and f % 2 == 1) else 0
	var lying := anim == "sleep"
	if lying:
		_draw_sleeping(f)
		return
	# corpo: testa, busto (colore della classe), gambe
	_px(6, 3 + bob, 4, 4, SKIN)
	_px(6, 3 + bob, 4, 1, DARK)                      # capelli
	_px(7, 5 + bob, 1, 1, DARK)                      # occhio
	_px(5, 7 + bob, 6, 7, body_color)
	_px(5, 13 + bob, 6, 1, body_color.darkened(0.35)) # cintura
	var step := (f % 2) if anim == "walk" else 0
	_px(6, 14, 2, 6 - step, DARK)
	_px(8, 14, 2, 6 - (1 - step if anim == "walk" else 0), DARK)
	_draw_action(f, bob)


func _draw_sleeping(f: int) -> void:
	# sdraiato: testa a sinistra, coperta del colore della classe; «zZz» che sale
	_px(1, 16, 4, 4, SKIN)
	_px(1, 16, 4, 1, DARK)
	_px(5, 17, 10, 3, body_color)
	_px(5, 20, 10, 1, body_color.darkened(0.4))
	var font := get_theme_default_font()
	var txt := tr("UI_COOPNET_ZZZ")
	var y := 12 - f * 2
	draw_string(font, Vector2(9 * PX + 4, y * PX + 8), txt.left(1 + f % 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.85, 0.85, 1.0, 0.9))


func _draw_action(f: int, bob: int) -> void:
	var up := f < 2                                   # metà del ciclo braccio su, metà giù
	match anim:
		"strike":
			# spada: alzata e poi giù in diagonale
			if up:
				_px(11, 2 + bob, 1, 7, METAL)
				_px(10, 8 + bob, 3, 1, TOOL)
			else:
				_px(11, 9 + bob, 4, 1, METAL)
				_px(15, 8 + bob, 1, 1, METAL)
		"chop", "pick":
			var head := METAL if anim == "pick" else TOOL.darkened(0.2)
			if up:
				_px(11, 4 + bob, 1, 6, TOOL)
				_px(10, 3 + bob, 3, 2, head)
			else:
				_px(11, 9 + bob, 4, 1, TOOL)
				_px(14, 9 + bob, 2, 3, head)
		"hammer":
			_px(3, 15, 4, 2, DARK.lightened(0.2))      # incudine
			if up:
				_px(11, 5 + bob, 1, 5, TOOL)
				_px(10, 4 + bob, 3, 2, METAL)
			else:
				_px(11, 10 + bob, 3, 1, TOOL)
				_px(13, 9 + bob, 2, 3, METAL)
				_px(12, 8, 1, 1, Color(1.0, 0.8, 0.3))   # scintilla
		"saw":
			var dx := 1 if up else 0
			_px(10 + dx, 10 + bob, 5, 1, METAL)
		"fish":
			# canna e lenza che oscilla, galleggiante sull'acqua
			_px(11, 6 + bob, 1, 5, TOOL)
			_px(12, 5 + bob, 3, 1, TOOL)
			var dy := 1 if up else 0
			_px(15, 6 + bob, 1, 12 + dy, Color(0.9, 0.9, 0.9, 0.7))
			_px(12, 21, 4, 1, Color(0.3, 0.5, 0.9))
			_px(15, 18 + dy, 1, 1, Color(0.9, 0.2, 0.2))
		"cook":
			_px(10, 16, 5, 3, DARK.lightened(0.15))    # pentola
			_px(11, 19, 3, 1, Color(1.0, 0.45, 0.1))    # fuoco
			_px(11 + (f % 2), 13 - (f % 3), 1, 2, Color(0.9, 0.9, 0.9, 0.6))   # vapore
			_px(11, 9 + bob, 1, 6, TOOL)                # mestolo
		"brew":
			_px(11, 10 + bob, 2, 3, Color(0.5, 0.9, 0.6))
			_px(11 + (f % 2), 8 - (f % 3), 1, 1, Color(0.7, 1.0, 0.8))
		"gather":
			var dy2 := 2 if up else 0
			_px(11, 12 + dy2, 2, 2, Color(0.4, 0.75, 0.3))
		"sneak":
			_px(4, 7 + bob, 1, 6, body_color.darkened(0.5))   # mantello
			_px(11, 11 + bob, 2, 2, Color(0.95, 0.8, 0.3) if up else DARK)
		"crate":
			# cassa davanti e scintille che girano
			_px(9, 15, 6, 5, Color(0.55, 0.35, 0.18))
			_px(9, 17, 6, 1, Color(0.85, 0.7, 0.3))
			var sp := [[8, 12], [15, 11], [12, 9], [16, 14]]
			for i in sp.size():
				if (i + f) % 2 == 0:
					_px(int(sp[i][0]), int(sp[i][1]), 1, 1, Color(1.0, 0.95, 0.5))
		_:
			pass
