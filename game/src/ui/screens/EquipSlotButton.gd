class_name EquipSlotButton
extends ItemTipButton
## Uno SLOT del paper-doll dell'Eroe (schermata Equipaggiamento): un riquadro con bordo che mostra il nome dello slot,
## l'icona dell'oggetto indossato (a scala intera 2x, mai ridimensionata a frazioni) oppure la silhouette dello slot
## quando è vuoto. Accetta il trascinamento di un pezzo dall'elenco (`dropped`). Solo presentazione: nessuna regola di gioco.

signal dropped(uid: String, slot: String)

const ICON_PX := 64             # le icone sono 32x32: scala 2x esatta
const SIZE_NORMAL := Vector2(96, 116)
const SIZE_SMALL := Vector2(80, 104)
## Slot del cibo (scheda «Cibo e pozioni» dell'Eroe, F10): il nome intero va a capo su più righe invece di essere tagliato.
const SIZE_FOOD := Vector2(80, 148)
const FOOD_NAME_LINES := 3
const COL_SILHOUETTE := Color(0.20, 0.19, 0.17, 0.85)       # solo colore: l'icona di un pezzo base, scurita
const COL_ACCENT := Color(0.93, 0.76, 0.42)

var slot: String = ""
## Verifica se un pezzo (uid) può essere rilasciato qui: la imposta il paper-doll (usa CombatSystem.equip_check).
var can_drop: Callable

var _name_l: Label
var _icon: TextureRect
var _item_l: Label
var _fin_l: Label
var _state_l: Label
var _frame := "slot_common"
var _tint := Color.WHITE
var _selected := false
var _hint := false


func _init(slot_id: String = "", small: bool = false) -> void:
	super._init()
	slot = slot_id
	custom_minimum_size = SIZE_SMALL if small else SIZE_NORMAL
	var full_names := slot_id.begins_with("food:")
	if full_names:
		custom_minimum_size = SIZE_FOOD
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_right = -4
	box.offset_top = 3
	box.offset_bottom = -3
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_name_l = _small_label(&"MutedLabel")
	box.add_child(_name_l)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_icon)
	_item_l = _small_label(&"")
	if full_names:
		_item_l.clip_text = false
		_item_l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_item_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_item_l.max_lines_visible = FOOD_NAME_LINES
	box.add_child(_item_l)
	_fin_l = _small_label(&"MutedLabel")
	_fin_l.visible = false
	box.add_child(_fin_l)
	_state_l = _small_label(&"MutedLabel")
	_state_l.visible = false
	box.add_child(_state_l)
	set_frame("slot_common", Color.WHITE)


func _small_label(variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", UiType.NOTE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = 0
	return l


## Il Label con nome e colore della finitura del Guardaroba (la schermata Eroe lo legge come «riga della finitura»).
func finish_label() -> Label:
	return _fin_l


func set_slot_name(label_text: String) -> void:
	_name_l.text = label_text


## Cornice: telaio dei riquadri (`slot_common`, `slot_rare`…) con un colore di tinta.
func set_frame(frame: String, tint: Color) -> void:
	_frame = frame
	_tint = tint
	_apply_styles()


func set_selected(on: bool) -> void:
	_selected = on
	_apply_styles()


func _apply_styles() -> void:
	var frame := "slot_mythic" if _selected else ("slot_relic" if _hint else _frame)      # scelto = arancio, «qui puoi rilasciare» = oro
	var tex := UiKit.texture(frame)
	var m: Array = UiKit.manifest().get(frame, {}).get("margin", [6, 6, 6, 6])
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = m[0]
		sb.texture_margin_top = m[1]
		sb.texture_margin_right = m[2]
		sb.texture_margin_bottom = m[3]
		var c := _tint
		match st:
			"hover":
				c = c.lightened(0.18)
			"pressed":
				c = c.darkened(0.12)
			"disabled":
				c = Color(c.r, c.g, c.b, 0.6)
		if _selected or _hint:
			c = Color.WHITE if st != "hover" else Color(1.15, 1.15, 1.15)
		sb.modulate_color = c
		add_theme_stylebox_override(st, sb)


## Slot con un oggetto: icona a colori, nome (colore della rarità/qualità se c'è) e, se c'è, la riga di stato.
func show_item(tex: Texture2D, item_name: String, name_color: Color = Color.WHITE) -> void:
	_icon.texture = tex
	_icon.modulate = Color.WHITE
	_item_l.text = item_name
	_item_l.add_theme_color_override("font_color", name_color)
	_item_l.theme_type_variation = &""


## Slot vuoto: silhouette (l'icona di un pezzo base, scurita: solo colore) e la scritta «Vuoto»/«N disponibili».
func show_empty(silhouette: Texture2D, note: String, highlight: bool) -> void:
	_icon.texture = silhouette
	_icon.modulate = COL_SILHOUETTE
	_item_l.text = note
	_item_l.remove_theme_color_override("font_color")
	if highlight:
		_item_l.add_theme_color_override("font_color", COL_ACCENT)
	else:
		_item_l.theme_type_variation = &"MutedLabel"
		_item_l.add_theme_font_size_override("font_size", UiType.NOTE)


## Riga piccola in fondo (es. «Bloccato: arma a due mani»), vuota = nascosta.
func set_state_text(msg: String, color: Color = Color(0.85, 0.5, 0.35)) -> void:
	_state_l.visible = not msg.is_empty()
	_state_l.text = msg
	_state_l.add_theme_color_override("font_color", color)


func item_text() -> String:
	return _item_l.text


func state_text() -> String:
	return _state_l.text if _state_l.visible else ""


func is_selected() -> bool:
	return _selected


# ------------------------------------------------------------------ trascinamento

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		_hint = data is Dictionary and (data as Dictionary).has("equip_uid") and can_drop.is_valid() \
			and bool(can_drop.call(str((data as Dictionary).equip_uid), slot))
		_apply_styles()
	elif what == NOTIFICATION_DRAG_END and _hint:
		_hint = false
		_apply_styles()


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("equip_uid"):
		return false
	return can_drop.is_valid() and bool(can_drop.call(str((data as Dictionary).equip_uid), slot))


func _drop_data(_at: Vector2, data: Variant) -> void:
	if data is Dictionary and (data as Dictionary).has("equip_uid"):
		dropped.emit(str((data as Dictionary).equip_uid), slot)
