class_name ChestPedestal
extends Control
## Piedistallo della cassa grande (Sala dei Caveau, scena di apertura): alone a gradini nel colore della cassa, base scura
## e, se serve, la cassa a SCALA INTERA (5× il PNG da 32 px = 160 px, mai frazioni: regola 10). Solo presentazione.
## L'alone è il colore del GENERE di cassa (non della rarità che uscirà): non anticipa nessun esito.

const CHEST_SCALE := 5
const PEDESTAL_SIZE := Vector2(224, 208)

var accent: Color = FxPalette.GOLD_D
var chest: TextureRect


func _init() -> void:
	custom_minimum_size = PEDESTAL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## `tex` nullo = solo alone (la scena di apertura mette la propria cassa sopra).
func setup(tex: Texture2D, accent_col: Color) -> ChestPedestal:
	accent = accent_col
	if chest != null:
		chest.queue_free()
		chest = null
	if tex != null:
		chest = VaultKit.pix(tex, CHEST_SCALE)
		chest.name = "ChestBig"
		chest.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		var half := chest.custom_minimum_size * 0.5
		chest.offset_left = -half.x
		chest.offset_right = half.x
		chest.offset_top = -half.y - 8.0
		chest.offset_bottom = half.y - 8.0
		add_child(chest)
	queue_redraw()
	return self


func _draw() -> void:
	var c := size * 0.5 + Vector2(0, -8)
	for i in 7:                                      # alone continuo a gradini (stile pixel): più fitto verso il centro
		var r := 104.0 - 11.0 * float(i)
		draw_circle(c, r, Color(accent, 0.035 + 0.02 * float(i)))
	var base_y := size.y * 0.5 + 76.0
	draw_rect(Rect2(c.x - 78.0, base_y, 156.0, 6.0), Color(0.05, 0.05, 0.08, 0.9))
	draw_rect(Rect2(c.x - 62.0, base_y + 6.0, 124.0, 4.0), Color(0.05, 0.05, 0.08, 0.7))
