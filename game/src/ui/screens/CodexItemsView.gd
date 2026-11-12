class_name CodexItemsView
extends VBoxContainer
## Schede «Oggetti» e «Unici» del Compendio (docs/15 §2, UI-A G16): ogni oggetto del gioco, in colore se già ottenuto e
## in grigio se manca, con filtro per categoria e «solo mancanti». Lista virtualizzata (oltre mille voci).

const ROW_H := 30.0
const ICON_PX := 24

var mode := "items"                  # "items" | "uniques"
var _codex: CodexSystem
var _ids: Array = []
var _cat := ""
var _only_missing := false
var _head: Label
var _bar: ProgressBar
var _filter: OptionButton
var _list: VirtualList
var _sig := ""


func setup(codex: CodexSystem, view_mode: String) -> void:
	_codex = codex
	mode = view_mode
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_head = Label.new()
	_head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_head.theme_type_variation = &"SectionLabel"
	add_child(_head)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	add_child(_bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	if mode == "items":
		var lb := Label.new()
		lb.text = "UI_GUILD2_ACH_FILTER"
		top.add_child(lb)
		_filter = OptionButton.new()
		_filter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_filter.add_item(tr("UI_GUILD2_CAT_ALL"))
		_filter.set_item_metadata(0, "")
		for c in _codex.categories():
			_filter.add_item(tr("UI_UIA_CAT_" + str(c).to_upper()))
			_filter.set_item_metadata(_filter.item_count - 1, str(c))
		_filter.item_selected.connect(func(i: int) -> void:
			_cat = str(_filter.get_item_metadata(i))
			_rebuild())
		top.add_child(_filter)
	var chk := CheckBox.new()
	chk.text = "UI_UIA_CODEX_ONLY_MISSING"
	chk.toggled.connect(func(on: bool) -> void:
		_only_missing = on
		_rebuild())
	top.add_child(chk)
	var hint := Label.new()
	hint.text = "UI_UIA_CODEX_ITEMS_HELP" if mode == "items" else "UI_UIA_CODEX_UNIQUES_HELP"
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_list = VirtualList.new()
	_list.row_height = ROW_H
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 160)
	_list.make_row = _make_row
	_list.bind_row = _bind_row
	add_child(_list)
	_rebuild()


## Aggiorna solo se il registro è cambiato (firma = oggetti visti, lingua).
func refresh() -> void:
	var s := "%s|%d|%d" % [Loc.locale(), (_codex.state.seen as Dictionary).size(), int(_codex.item_progress().have)]
	if s != _sig:
		_rebuild()


func _rebuild() -> void:
	_sig = "%s|%d|%d" % [Loc.locale(), (_codex.state.seen as Dictionary).size(), int(_codex.item_progress().have)]
	var src: Array = _codex.collectible_ids() if mode == "items" else _codex.unique_ids()
	_ids = []
	for i in src:
		var d := DataRegistry.item(str(i))
		if mode == "items" and not _cat.is_empty() and str(d.get("category", "")) != _cat:
			continue
		if _only_missing and _codex.item_seen(str(i)):
			continue
		_ids.append(str(i))
	var p: Dictionary = _codex.item_progress(_cat) if mode == "items" else _codex.unique_progress()
	_head.text = Loc.tf("UI_UIA_CODEX_PROGRESS", {"have": NumberFormat.fmt(int(p.have)), "total": NumberFormat.fmt(int(p.total)),
		"pct": CodexSystem.pct_text(int(p.have), int(p.total))})
	_bar.max_value = maxf(1.0, float(p.total))
	_bar.value = float(p.have)
	_list.set_count(_ids.size())
	_list.rebind()


func _make_row() -> Control:
	var b := ItemTipButton.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var h := HBoxContainer.new()
	h.name = "H"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", 10)
	b.add_child(h)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var nm := Label.new()
	nm.name = "Name"
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	var cnt := Label.new()
	cnt.name = "Count"
	cnt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cnt.theme_type_variation = &"MonoLabel"
	cnt.custom_minimum_size.x = 90
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cnt)
	return b


func _bind_row(row: Control, index: int) -> void:
	var id := str(_ids[index])
	var d := DataRegistry.item(id)
	var seen := _codex.item_seen(id)
	(row as ItemTipButton).set_item(id)
	var h: Node = row.get_node("H")
	var kind := str(d.get("icon", "")).get_base_dir().get_file()
	h.get_node("Icon").texture = IconLib.icon(kind if not kind.is_empty() else "items", id)
	h.get_node("Name").text = Loc.t(d.get("name", id))
	h.get_node("Count").text = ("×" + NumberFormat.fmt(_codex.item_count_seen(id))) if seen else tr("UI_UIA_CODEX_MISSING")
	row.modulate = Color(1, 1, 1, 1) if seen else Color(1, 1, 1, 0.42)
