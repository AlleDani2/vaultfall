class_name EquipPickRow
extends ItemTipButton
## Riga dell'elenco «adatti a questo slot» del paper-doll: icona, nome, differenze di statistiche rispetto all'indossato e
## motivo se non si può indossare. Un clic la sceglie, il doppio clic la indossa (`activated`), si può trascinare su uno slot.

signal activated

const ICON_PX := 32
const ROW_H := 62.0

var uid: String = ""
var icon_tex: Texture2D
var _icon: TextureRect
var _name_l: Label
var _tag_l: Label
var _info: RichTextLabel


func _init() -> void:
	super._init()
	toggle_mode = false
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0, ROW_H)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", 8)
	add_child(h)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_icon)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	_name_l = Label.new()
	_name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_l.clip_text = true
	_name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_name_l)
	_tag_l = Label.new()
	_tag_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_tag_l.theme_type_variation = &"MutedLabel"
	_tag_l.add_theme_font_size_override("font_size", UiType.NOTE)
	_tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_tag_l)
	_info = RichTextLabel.new()
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info.clip_contents = true
	_info.custom_minimum_size = Vector2(0, 18)
	_info.add_theme_font_size_override("normal_font_size", UiType.NOTE)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_info)


## Riempie la riga. `info_bb` = BBCode (differenze, motivi); `tag` = «#14», «Lv 30»…
func fill(new_uid: String, tex: Texture2D, title: String, title_color: Color, tag: String, info_bb: String) -> void:
	uid = new_uid
	icon_tex = tex
	_icon.texture = tex
	_name_l.text = title
	_name_l.add_theme_color_override("font_color", title_color)
	_tag_l.text = tag
	_info.text = info_bb


func name_text() -> String:
	return _name_l.text


func info_text() -> String:
	return _info.get_parsed_text()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		activated.emit()
		accept_event()
		return
	super._gui_input(event)


func _get_drag_data(_at: Vector2) -> Variant:
	if uid.is_empty():
		return null
	var pv := TextureRect.new()
	pv.texture = icon_tex
	pv.custom_minimum_size = Vector2(ICON_PX * 2, ICON_PX * 2)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(pv)
	return {"equip_uid": uid}
