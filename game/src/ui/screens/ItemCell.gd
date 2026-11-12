class_name ItemCell
extends Control
## Cella della griglia del Deposito (docs/ui_redesign/02 §5.3): UN SOLO nodo disegnato con _draw (nessun figlio), così 165 celle
## costano 165 nodi. Mostra icona a fattore intero (2× = 64 px comoda, 1× = 32 px compatta, sempre TEXTURE_FILTER_NEAREST: i file
## non si ridimensionano, regola 10), quantità con contorno su fondo opaco, lucchetto, «E» (indossato), tier e grado, e per le
## voci non vendibili in modalità vendita un velo con motivo (F17). Ogni stato ha anche una forma, non solo il colore.
## Tooltip: ItemTooltip (lo stesso di ItemTipButton), costruito solo quando serve.

signal pressed
signal activated                      # doppio clic o Invio: azione predefinita SICURA (mai vendere né scartare)
signal context_requested(global_pos: Vector2)

## Misure della cella disegnata (passo = cella + 4 px).
const COMFORT := Vector2(84, 96)
const COMPACT := Vector2(52, 62)
const COMFORT_ICON := 64
const COMPACT_ICON := 32
const BG := Color(0.10, 0.09, 0.08, 1.0)
const BG_SELECTED := Color(0.20, 0.16, 0.08, 1.0)
const STRIP := Color(0.04, 0.035, 0.03, 1.0)          # fondo opaco della quantità: il testo non sta mai sull'icona
const TEXT := Color(0.96, 0.94, 0.88)
const MUTED := Color(0.78, 0.74, 0.66)
const BORDER := Color(0.30, 0.27, 0.22)
const SELECT := Color(1.0, 0.86, 0.45)
const WORN := Color(0.93, 0.76, 0.42)
const WORN_TEXT := Color(0.12, 0.09, 0.03)
const VEIL := Color(0.08, 0.08, 0.08, 0.62)

var def_id: String = ""
var inst: Dictionary = {}
var icon: Texture2D
var qty_text: String = ""
var tier: int = 0
var rank: int = 0
var locked: bool = false
var worn: bool = false
var selected: bool = false
var veil: bool = false                 # non selezionabile / non vendibile (F17): velo grigio con motivo a righe
var compact: bool = false
var rarity_color: Color = BORDER
var qty_exact: String = ""             # «Quantità: 203.480»: il valore esatto sta nel tooltip, la cella lo abbrevia


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST      # icone nitide a fattore intero
	tooltip_text = " "                                      # il testo vero lo costruisce _make_custom_tooltip


## Un solo ridisegno per bind: il dato cambia raramente, quindi si confronta una firma prima di ridisegnare.
func setup(new_def: String, new_inst: Dictionary, new_icon: Texture2D, new_qty: String, new_tier: int, new_rank: int,
		new_locked: bool, new_worn: bool, new_selected: bool, new_rarity: Color, new_veil: bool, new_compact: bool) -> void:
	def_id = new_def
	inst = new_inst
	icon = new_icon
	qty_text = new_qty
	tier = new_tier
	rank = new_rank
	locked = new_locked
	worn = new_worn
	selected = new_selected
	rarity_color = new_rarity
	veil = new_veil
	compact = new_compact
	custom_minimum_size = cell_size()
	size = cell_size()
	queue_redraw()


func cell_size() -> Vector2:
	return COMPACT if compact else COMFORT


func icon_px() -> int:
	return COMPACT_ICON if compact else COMFORT_ICON


func _make_custom_tooltip(_for_text: String) -> Object:
	var tip: Control = (load("res://src/ui/ItemTooltip.gd") as GDScript).call("make_control", def_id, inst) if not def_id.is_empty() else null     # caricato al primo tooltip: non pesa sull'apertura del Deposito
	if tip is RichTextLabel and not qty_exact.is_empty():
		(tip as RichTextLabel).text += "\n" + qty_exact
	return tip


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				activated.emit()
			else:
				pressed.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(get_global_mouse_position())
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10 and event.shift_pressed or event.keycode == KEY_MENU:
			context_requested.emit(get_global_rect().get_center())         # tasto menù / Maiusc+F10 = tasto destro
			accept_event()
			return
		if event.is_action_pressed("ui_select"):         # Spazio: seleziona
			pressed.emit()
			accept_event()
		elif event.is_action_pressed("ui_accept"):       # Invio: seleziona; se è già scelta, azione predefinita sicura
			if selected:
				activated.emit()
			else:
				pressed.emit()
			accept_event()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		context_requested.emit(get_global_rect().get_center())
		accept_event()


func _draw() -> void:
	var sz := size
	var font := get_theme_default_font()
	var fs := 11 if compact else 13
	draw_rect(Rect2(Vector2.ZERO, sz), BG_SELECTED if selected else BG)
	var bw := 3.0 if selected else 2.0
	draw_rect(Rect2(Vector2.ZERO, sz), SELECT if selected else rarity_color, false, bw)
	# icona centrata nella parte alta
	var ip := icon_px()
	var strip_h := 18.0 if not compact else 15.0
	var top := (sz.y - strip_h - ip) * 0.5
	if icon != null:
		draw_texture_rect(icon, Rect2(Vector2((sz.x - ip) * 0.5, top), Vector2(ip, ip)), false)
	# quantità: striscia opaca in basso, testo con contorno
	draw_rect(Rect2(Vector2(bw, sz.y - strip_h - bw), Vector2(sz.x - 2.0 * bw, strip_h)), STRIP)
	if not qty_text.is_empty():
		var tw := font.get_string_size(qty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(maxf(bw + 2.0, (sz.x - tw) * 0.5), sz.y - bw - 4.0)
		draw_string_outline(font, pos, qty_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 2.0 * bw, fs, 3, STRIP)
		draw_string(font, pos, qty_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 2.0 * bw, fs, TEXT)
	# tier in alto a sinistra (solo cella comoda: in compatta non c'è posto), grado «+N» a destra dell'icona
	if tier > 0 and not compact:
		_tag("T%d" % tier, Vector2(bw + 3.0, bw + 12.0), font, 11, MUTED)
	if rank > 0:
		var rt := "+%d" % rank
		var rw := font.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_tag(rt, Vector2(sz.x - bw - 3.0 - rw, sz.y - strip_h - bw - 4.0), font, 11, SELECT)
	# indossato: riquadro con «E»; bloccato: lucchetto disegnato (forma, non solo colore)
	var bx := sz.x - bw - 3.0
	if worn:
		var s := 13.0 if not compact else 11.0
		bx -= s
		draw_rect(Rect2(Vector2(bx, bw + 3.0), Vector2(s, s)), WORN)
		draw_string(font, Vector2(bx + (s - 8.0) * 0.5, bw + 3.0 + s - 2.5), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WORN_TEXT)
		bx -= 3.0
	if locked:
		_padlock(Vector2(bx - 9.0, bw + 3.0))
	# velo di «non selezionabile»: grigio con righe oblique e una croce, mai solo un cambio di colore
	if veil:
		draw_rect(Rect2(Vector2.ZERO, sz), VEIL)
		var step := 8.0
		var x := -sz.y
		while x < sz.x:
			draw_line(Vector2(x, sz.y), Vector2(x + sz.y, 0.0), Color(0, 0, 0, 0.35), 1.0)
			x += step
		draw_string(font, Vector2(sz.x * 0.5 - 4.0, top + ip * 0.5 + 6.0), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT)
	if has_focus():
		draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color.WHITE, false, 2.0)


func _tag(text: String, at: Vector2, font: Font, fs: int, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, STRIP)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _padlock(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(-1, -1), Vector2(11, 12)), STRIP)                      # fondo opaco dietro la forma
	draw_rect(Rect2(at + Vector2(0, 4), Vector2(9, 7)), SELECT)                         # corpo
	draw_arc(at + Vector2(4.5, 4.0), 3.0, PI, TAU, 8, SELECT, 1.5)                      # archetto
