class_name ProfileCard
extends PanelContainer
## Scheda del profilo nel Riepilogo (UI-A G32): Stendardo ed Emblema scelti, titolo e cornice, con il collegamento al
## Compendio dove si cambiano. Solo presentazione: legge CompendiumSystem e CodexSystem.

var _banner: TextureRect
var _emblem: TextureRect
var _line: Label
var _sub: Label
var _sig := ""


func _init() -> void:
	theme_type_variation = &"ContentPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	_banner = _pic(Vector2(72, 72))
	h.add_child(_banner)
	_emblem = _pic(Vector2(48, 48))
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_emblem)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	_line = Label.new()
	_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_line.theme_type_variation = &"SectionLabel"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_line)
	_sub = Label.new()
	_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_sub.theme_type_variation = &"MutedLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sub)
	var btn := Button.new()
	btn.text = "UI_UIA_PROFILE_EDIT"
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: EventBus.screen_requested.emit("compendium", {}))
	h.add_child(btn)


func _pic(sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = sz
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	return t


func refresh() -> void:
	var comp := Game.system("compendium") as CompendiumSystem
	var codex := Game.system("codex") as CodexSystem
	if comp == null or codex == null:
		visible = false
		return
	var sig := "%s|%s|%s|%s|%s|%s" % [Loc.locale(), codex.selected("banner"), codex.selected("emblem"), comp.selected_title(),
		comp.selected_frame(), comp.companion()]
	if sig == _sig:
		return
	_sig = sig
	var b := codex.selected("banner")
	var e := codex.selected("emblem")
	_banner.texture = CrateUi.def_icon(b) if not b.is_empty() else null
	_banner.tooltip_text = Loc.t(DataRegistry.item(b).get("name", {})) if not b.is_empty() else ""
	_banner.visible = not b.is_empty()
	_emblem.texture = CrateUi.def_icon(e) if not e.is_empty() else null
	_emblem.tooltip_text = Loc.t(DataRegistry.item(e).get("name", {})) if not e.is_empty() else ""
	_emblem.visible = not e.is_empty()
	var t := comp.title_line()
	_line.text = ("«%s»" % t) if not t.is_empty() else tr("UI_UIA_PROFILE_NO_TITLE")
	var bits := PackedStringArray()
	if not b.is_empty():
		bits.append(Loc.t(DataRegistry.item(b).get("name", {})))
	if not e.is_empty():
		bits.append(Loc.t(DataRegistry.item(e).get("name", {})))
	var fr := comp.selected_frame()
	if not fr.is_empty():
		bits.append(Loc.t(DataRegistry.get_def("frames", fr).get("name", fr)))
	_sub.text = " · ".join(bits) if not bits.is_empty() else tr("UI_UIA_PROFILE_EMPTY")
