class_name DevMenu
extends CanvasLayer
## Menù F10 per lo sviluppatore (build di debug o VAULTFALL_DEBUG=1). Mai creato in rilascio: lo istanzia solo
## Feedback.toggle_dev_menu() dopo aver controllato DevTools.is_enabled(). Presentazione pura: le azioni sono in DevTools.

var tools := DevTools.new()

var _status: Label
var _gold: LineEdit
var _item_id: LineEdit
var _item_qty: LineEdit
var _skill: OptionButton
var _level: SpinBox
var _chapter: OptionButton
var _date: LineEdit
var _path: LineEdit
var _slot: OptionButton
var _file_dialog: FileDialog
var _need_game: Array[Control] = []


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContentPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -480.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.clip_contents = true
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	_head(v, "UI_FB_DEV_TITLE", &"TitleLabel")
	_head(v, "UI_FB_DEV_WARNING", &"MutedLabel")

	_head(v, "UI_FB_DEV_TIME", &"SectionLabel")
	var r := HBoxContainer.new()
	v.add_child(r)
	for h in [1, 8, 24, 168]:
		_add_need(r, _btn("+%d h" % h, _on_skip.bind(h * 3600.0)))

	_head(v, "UI_FB_DEV_GOLD", &"SectionLabel")
	r = HBoxContainer.new()
	v.add_child(r)
	_gold = _edit(r, "100000", 120)
	_add_need(r, _key_btn("UI_FB_DEV_GIVE", _on_gold))

	_head(v, "UI_FB_DEV_ITEM", &"SectionLabel")
	r = HBoxContainer.new()
	v.add_child(r)
	_item_id = _edit(r, "log_pine", 200)
	_item_qty = _edit(r, "100", 70)
	_add_need(r, _key_btn("UI_FB_DEV_GIVE", _on_item))

	_head(v, "UI_FB_DEV_LEVELS", &"SectionLabel")
	r = HBoxContainer.new()
	v.add_child(r)
	_skill = OptionButton.new()
	_skill.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for id in DataRegistry.skill_ids():
		_skill.add_item(str(id))
	r.add_child(_skill)
	_level = SpinBox.new()
	_level.min_value = 1
	_level.max_value = 999
	_level.value = 50
	r.add_child(_level)
	_add_need(r, _key_btn("UI_FB_DEV_SET", _on_level))
	_add_need(v, _key_btn("UI_FB_DEV_ALL_SKILLS", _on_all_levels))

	_head(v, "UI_FB_DEV_CHAPTER", &"SectionLabel")
	r = HBoxContainer.new()
	v.add_child(r)
	_chapter = OptionButton.new()
	_chapter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for c in DataRegistry.table("chapters"):
		_chapter.add_item(Loc.t(c.name), int(c.id))
	_chapter.fit_to_longest_item = false
	_chapter.clip_text = true
	_chapter.custom_minimum_size = Vector2(260, 0)
	r.add_child(_chapter)
	_add_need(r, _key_btn("UI_FB_DEV_UNLOCK", _on_chapter))

	_head(v, "UI_FB_DEV_DATE", &"SectionLabel")
	r = HBoxContainer.new()
	v.add_child(r)
	_date = _edit(r, "2026-12-24", 120)
	_add_need(r, _key_btn("UI_FB_DEV_SET", _on_date))
	_add_need(r, _key_btn("UI_FB_DEV_REAL_CLOCK", _on_real_clock))

	_head(v, "UI_FB_DEV_SAVE", &"SectionLabel")
	_add_need(v, _key_btn("UI_FB_DEV_FORCE_SAVE", _on_save))

	_head(v, "UI_FB_DEV_FRIEND", &"SectionLabel")
	_head(v, "UI_FB_DEV_FRIEND_HINT", &"MutedLabel")
	r = HBoxContainer.new()
	v.add_child(r)
	_path = _edit(r, "", 240)
	_path.placeholder_text = "*.sav / *.zip"
	r.add_child(_key_btn("UI_FB_DEV_BROWSE", _on_browse))
	r = HBoxContainer.new()
	v.add_child(r)
	_slot = OptionButton.new()
	_slot.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for s in range(1, SaveService.SLOTS + 1):
		_slot.add_item(Loc.tf("UI_SLOT_N", {"n": s}), s)
	_slot.selected = SaveService.SLOTS - 1
	r.add_child(_slot)
	r.add_child(_key_btn("UI_FB_DEV_LOAD", _on_load_friend))

	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.theme_type_variation = &"MonoLabel"
	v.add_child(_status)
	v.add_child(_key_btn("UI_FB_DEV_CLOSE", Feedback.toggle_dev_menu))

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.sav, *.zip ; VAULTFALL"])
	_file_dialog.file_selected.connect(func(p: String) -> void: _path.text = p)
	add_child(_file_dialog)
	_refresh_enabled()


func _head(parent: Control, key: String, variation: StringName) -> void:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _btn(label: String, action: Callable) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = label
	b.pressed.connect(action)
	return b


func _key_btn(key: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	b.pressed.connect(action)
	return b


func _edit(parent: Control, initial: String, width: int) -> LineEdit:
	var e := LineEdit.new()
	e.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	e.text = initial
	e.custom_minimum_size = Vector2(width, 0)
	parent.add_child(e)
	return e


func _add_need(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_need_game.append(c)


func _refresh_enabled() -> void:
	for c in _need_game:
		if c is BaseButton:
			(c as BaseButton).disabled = not GameState.active


func _say(text: String) -> void:
	_status.text = text


# ------------------------------------------------------------------ azioni

func _on_skip(seconds: float) -> void:
	tools.skip_time(seconds)
	_say(Loc.tf("UI_FB_DEV_DONE_TIME", {"h": int(seconds / 3600.0)}))


func _on_gold() -> void:
	_say(tr("UI_FB_DEV_OK") if tools.give_gold(int(_gold.text)) else tr("UI_FB_DEV_FAIL"))


func _on_item() -> void:
	var n := tools.give_item(_item_id.text.strip_edges(), int(_item_qty.text))
	_say(Loc.tf("UI_FB_DEV_DONE_ITEM", {"n": n}) if n > 0 else tr("UI_FB_DEV_FAIL"))


func _on_level() -> void:
	var lv := tools.set_skill_level(_skill.get_item_text(_skill.selected), int(_level.value))
	_say(Loc.tf("UI_FB_DEV_DONE_LEVEL", {"n": lv}))


func _on_all_levels() -> void:
	_say(Loc.tf("UI_FB_DEV_DONE_ALL", {"n": tools.all_skills_to(int(_level.value))}))


func _on_chapter() -> void:
	var n := tools.unlock_chapter(_chapter.get_selected_id())
	_say(Loc.tf("UI_FB_DEV_DONE_CHAPTER", {"n": n}))


func _on_date() -> void:
	var p := _date.text.strip_edges().split("-")
	var ok := p.size() == 3 and p[0].is_valid_int() and p[1].is_valid_int() and p[2].is_valid_int() \
		and tools.set_event_date(int(p[0]), int(p[1]), int(p[2]))
	_say(tr("UI_FB_DEV_OK") if ok else tr("UI_FB_DEV_FAIL"))


func _on_real_clock() -> void:
	tools.clear_event_date()
	_say(tr("UI_FB_DEV_OK"))


func _on_save() -> void:
	_say(tr("UI_FB_DEV_OK") if tools.force_save() else tr("UI_FB_DEV_FAIL"))


func _on_browse() -> void:
	_file_dialog.popup_centered(Vector2i(800, 520))


func _on_load_friend() -> void:
	var res := tools.load_friend_save(_path.text.strip_edges(), _slot.get_selected_id())
	if res.ok:
		Feedback.toggle_dev_menu()
		get_tree().change_scene_to_file.call_deferred("res://src/ui/main/MainScreen.tscn")
	else:
		_say(Loc.tf("UI_FB_DEV_LOAD_FAILED", {"err": str(res.error)}))
