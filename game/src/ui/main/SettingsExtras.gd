class_name SettingsExtras
extends VBoxContainer
## Blocco di Impostazioni della UI principale (UI-B): colonna destra (G24), tutorial (G38), Modalità Cozy (G53) e pannello
## «Scorciatoie» (G23). Vive in un file a parte perché SettingsScreen (UI-A) lo aggancia con UNA riga:
##     _box.add_child(SettingsExtras.new())
## Ogni controllo scrive in Settings (nessuna logica qui); MainScreen ascolta EventBus.settings_changed.

const LABEL_W := 240.0

## Con false manca il pannello «Scorciatoie» (nelle Impostazioni a schede vive nella scheda Comandi).
var shortcuts: bool = true


func _init() -> void:
	name = "SettingsExtras"
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	_title("UI_UIB_SET_INTERFACE")
	_check("UI_UIB_SET_RIGHT_COL", "right_col_visible", "UI_UIB_SET_RIGHT_COL_TIP")
	_check("UI_UIB_SET_TUTORIALS", "tutorials", "UI_UIB_SET_TUTORIALS_TIP")
	var guide := Button.new()                  # tutorial guidato: la Guida elenca le dinamiche e riporta qualsiasi scheda
	guide.name = "OpenGuide"
	guide.text = "UI_TUT_OPEN_GUIDE"
	guide.tooltip_text = "UI_TUT_SETTINGS_NOTE"
	guide.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	guide.pressed.connect(func() -> void: EventBus.screen_requested.emit("guide", {}))
	add_child(guide)
	_title("UI_UIB_SET_COZY_TITLE")
	var cb := _check("UI_UIB_SET_COZY", "cozy_mode", "UI_UIB_SET_COZY_TIP")
	cb.name = "CozyCheck"
	var note := Label.new()
	note.name = "CozyNote"
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = Loc.tf("UI_UIB_SET_COZY_NOTE", {"n": NumberFormat.fmt(CozyMode.xp_pct())})
	add_child(note)
	if shortcuts:
		_title("UI_UIB_SET_SHORTCUTS")
		add_child(shortcuts_panel())


## Tabella delle scorciatoie (tasti a sinistra, azione a destra). Usata anche dai test.
static func shortcuts_panel() -> GridContainer:
	var g := GridContainer.new()
	g.name = "ShortcutsGrid"
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 4)
	for e in ShortcutMap.TABLE:
		var k := Label.new()
		k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		k.theme_type_variation = &"MonoLabel"
		k.text = ShortcutMap.keys_label(str(e.id))
		k.custom_minimum_size = Vector2(110, 0)
		g.add_child(k)
		var t := Label.new()
		t.text = str(e.text)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(t)
	return g


func _title(key: String) -> void:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = &"SectionLabel"
	add_child(l)


func _check(key: String, setting: String, tip_key: String) -> CheckBox:
	var cb := SettingsKit.check_row(self, key, tip_key)
	cb.button_pressed = bool(Settings.get_value(setting))
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(setting, on))
	return cb

