class_name NewsView
extends ScrollContainer
## Elenco delle novità (AppInfo.changelog) nella lingua attiva, dalla versione più recente.
## Si usa nella schermata «Novità» (menù Progressi) e nella finestra del menù iniziale.


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build()


func build() -> void:
	for c in get_children():
		c.free()
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var lang := Loc.locale()
	var entries := AppInfo.changelog()
	if entries.is_empty():
		box.add_child(_text(tr("UI_FB_NEWS_EMPTY"), &"MutedLabel"))
		return
	for e in entries:
		box.add_child(_text(Loc.tf("UI_FB_NEWS_VERSION_LINE", {"v": str(e.version), "date": str(e.get("date", ""))}), &"SectionLabel"))
		for line in AppInfo.entries_of(e, lang):
			box.add_child(_text("•  " + line, &""))


func _text(t: String, variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(300, 0)
	if variation != &"":
		l.theme_type_variation = variation
	return l


## Finestra con le novità (per il menù iniziale e le Impostazioni).
static func show_dialog(host: Node) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.title = "UI_FB_NEWS_TITLE"
	d.ok_button_text = "UI_FB_REPORT_CLOSE"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 340)
	var intro := Label.new()
	intro.text = "UI_FB_NEWS_INTRO"
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	box.add_child(NewsView.new())
	d.add_child(box)
	d.canceled.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	host.get_tree().root.add_child(d)
	d.popup_centered(Vector2i(620, 460))
	return d
