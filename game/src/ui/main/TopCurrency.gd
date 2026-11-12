class_name TopCurrency
extends PanelContainer
## «Chip» cliccabile della barra alta (F2 del progetto di interfaccia, docs/ui_redesign/06 §3.2): un riquadro con una riga
## (`Row`) di figli, sfondo che cambia al passaggio del mouse e anello di focus per la tastiera. È la base di Oro, Polvere
## Stellare (questa classe), Deposito (BankChip) e Attività (ActivityChip). Solo presentazione, nessuna regola di gioco.
## L'icona è un `TopCurrency.Pic` (Control che disegna la texture), non un TextureRect: un'icona decorativa non è un elemento
## informativo in più nel censimento della barra (test_ui_budget). La scena dichiara un Control semplice e `TopBar.setup`
## gli assegna lo script Pic (`TopCurrency.as_pic`).

signal activated

const PAD_X := 8
const PAD_Y := 2
const RADIUS := 6
const HOVER_BG := Color(1, 1, 1, 0.08)
const FOCUS_RING := Color(0.94, 0.85, 0.63, 0.9)

## Sfondo di stato (trasparente = nessuno). Lo imposta chi estende la classe (ambra / rosso del Deposito).
var tint: Color = Color(0, 0, 0, 0):
	set(v):
		tint = v
		_apply_style()

var row: HBoxContainer
var _hover: bool = false
var _sb := StyleBoxFlat.new()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sb.set_corner_radius_all(RADIUS)
	_sb.content_margin_left = PAD_X
	_sb.content_margin_right = PAD_X
	_sb.content_margin_top = PAD_Y
	_sb.content_margin_bottom = PAD_Y
	add_theme_stylebox_override("panel", _sb)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _ready() -> void:
	ensure_row()
	_apply_style()


## La riga di figli: se la scena non la dichiara (chip creato da codice) la crea qui.
func ensure_row() -> HBoxContainer:
	if row == null:
		row = get_node_or_null("Row") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "Row"
		add_child(row)
	row.add_theme_constant_override("separation", 6)
	_ignore_mouse(row)
	return row


## Tutti i figli lasciano passare il mouse: il chip è UN solo controllo cliccabile (tooltip compreso).
static func _ignore_mouse(n: Node) -> void:
	var c := n as Control
	if c != null:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in c.get_children():
			_ignore_mouse(k)


## Trasforma un Control semplice della scena in icona del chip (script Pic) e lo ritorna.
static func as_pic(c: Control) -> Pic:
	if c == null:
		return null
	if not (c is Pic):
		c.set_script(Pic)
		c.custom_minimum_size = Vector2(20, 20)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c as Pic


func _set_hover(v: bool) -> void:
	_hover = v
	_apply_style()


func _apply_style() -> void:
	if tint.a > 0.0:
		_sb.bg_color = tint.lightened(0.12) if _hover else tint
	else:
		_sb.bg_color = HOVER_BG if _hover else Color(0, 0, 0, 0)
	queue_redraw()


func _draw() -> void:
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), FOCUS_RING, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		activated.emit()
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		activated.emit()


## Icona della barra: disegna una texture quadrata, oppure (senza texture e con `ring`) un cerchio vuoto «a riposo».
class Pic extends Control:
	var texture: Texture2D:
		set(v):
			texture = v
			queue_redraw()
	var ring: bool = false:
		set(v):
			ring = v
			queue_redraw()
	var ring_color: Color = Color(0.78, 0.74, 0.62, 1)

	func _draw() -> void:
		if ring:
			draw_arc(size * 0.5, minf(size.x, size.y) * 0.32, 0.0, TAU, 24, ring_color, 2.0, true)
		elif texture != null:
			var s := minf(size.x, size.y)
			draw_texture_rect(texture, Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s)), false)


## Marchio della barra: il lockup compatto del logo (emblema a portello + parola piatta, `assets/brand/logo_lockup.png`, griglia
## 118×16), disegnato a SCALA INTERA con filtro nearest (stesso marchio del titolo e dei crediti). Quando alla barra manca
## spazio passa alla sola emblema (`assets/brand/emblem.png`, 32×32, scala 1: stessa altezza del lockup a scala 2). È un
## logo, non un'informazione: non conta come elemento informativo nel censimento della barra. `caption` è il nome accessibile.
class Brand extends Control:
	const LOCKUP: Texture2D = preload("res://assets/brand/logo_lockup.png")
	const EMBLEM: Texture2D = preload("res://assets/brand/emblem.png")
	var caption: String = "":
		set(v):
			caption = v
			update_minimum_size()
			queue_redraw()
	## Solo l'emblema (versione compatta del marchio) invece del lockup intero.
	var emblem_only: bool = false:
		set(v):
			if v == emblem_only:
				return
			emblem_only = v
			update_minimum_size()
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## Scala intera del lockup (2 → 236×32 logici); l'emblema sta a scala 1 (32×32).
	func lockup_scale() -> int:
		return 1 if emblem_only else 2

	func _tex() -> Texture2D:
		return EMBLEM if emblem_only else LOCKUP

	func _get_minimum_size() -> Vector2:
		return _tex().get_size() * float(lockup_scale())

	func _draw() -> void:
		var sz := _tex().get_size() * float(lockup_scale())
		draw_texture_rect(_tex(), Rect2(((size - sz) * 0.5).round(), sz), false)


## Trasforma un Control semplice della scena nel marchio (script Brand).
static func as_brand(c: Control, text: String) -> Brand:
	if not (c is Brand):
		c.set_script(Brand)
	var b := c as Brand
	b.caption = text
	return b
