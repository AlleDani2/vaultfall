class_name AccessibilityPanel
extends VBoxContainer
## Scheda «Accessibilità» delle Impostazioni (1.0): testo grande, alto contrasto, palette per daltonici, riduzione di animazioni
## ed effetti, percentuali sulle barre. Solo colore e dimensione del testo (D-6): nessun PNG viene toccato.
## L'anteprima mostra campioni di colore con il nome scritto accanto (mai solo colore) e cambia subito con il filtro.

const PREVIEW: Array[Dictionary] = [
	{"color": Color("#4caf50"), "text": "UI_I10_A11Y_SWATCH_OK", "mark": "✓"},
	{"color": Color("#e5484d"), "text": "UI_I10_A11Y_SWATCH_DANGER", "mark": "!"},
	{"color": Color("#4f8fe8"), "text": "UI_I10_A11Y_SWATCH_RARE", "mark": "R"},
	{"color": Color("#e8b84f"), "text": "UI_I10_A11Y_SWATCH_GOLD", "mark": "★"},
]

var text_opt: OptionButton
var colorblind_opt: OptionButton
var contrast_check: CheckBox
var percent_check: CheckBox


func _ready() -> void:
	name = "AccessibilityPanel"
	add_theme_constant_override("separation", 10)
	SettingsKit.section(self, "UI_I10_A11Y_TITLE")
	SettingsKit.note(self, "UI_I10_A11Y_INTRO")
	text_opt = SettingsKit.option(self, "UI_I10_A11Y_TEXT", ["100%", "125%", "150%"], Accessibility.TEXT_SCALES, "text_scale")
	text_opt.name = "TextScaleOption"
	text_opt.tooltip_text = "UI_I10_A11Y_TEXT_TIP"
	SettingsKit.note(self, "UI_I10_A11Y_TEXT_NOTE")
	contrast_check = SettingsKit.check(self, "UI_I10_A11Y_CONTRAST", "high_contrast")
	contrast_check.name = "HighContrastCheck"
	SettingsKit.note(self, "UI_I10_A11Y_CONTRAST_NOTE")
	colorblind_opt = SettingsKit.option(self, "UI_I10_A11Y_COLORBLIND",
		["UI_I10_A11Y_CB_OFF", "UI_I10_A11Y_CB_PROTAN", "UI_I10_A11Y_CB_DEUTAN", "UI_I10_A11Y_CB_TRITAN"], Array(Accessibility.COLORBLIND_MODES), "colorblind")
	colorblind_opt.name = "ColorblindOption"
	SettingsKit.note(self, "UI_I10_A11Y_CB_NOTE")
	_preview()
	SettingsKit.section(self, "UI_I10_A11Y_MOTION")
	SettingsKit.check(self, "UI_REDUCE_MOTION", "reduce_motion")
	SettingsKit.note(self, "UI_I10_A11Y_MOTION_NOTE")
	SettingsKit.option(self, "UI_FX_MODE", ["UI_FX_MODE_FULL", "UI_FX_MODE_REDUCED"], ["full", "reduced"], "fx_mode")
	SettingsKit.note(self, "UI_I10_A11Y_FX_NOTE")
	SettingsKit.section(self, "UI_I10_A11Y_NOCOLOR")
	percent_check = SettingsKit.check(self, "UI_I10_A11Y_PERCENT", "bar_percent")
	percent_check.name = "BarPercentCheck"
	SettingsKit.note(self, "UI_I10_A11Y_NOCOLOR_NOTE")


func _preview() -> void:
	SettingsKit.section(self, "UI_I10_A11Y_PREVIEW")
	var r := HBoxContainer.new()
	r.name = "Preview"
	r.add_theme_constant_override("separation", 12)
	for p in PREVIEW:
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = p.color
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		box.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = "%s %s" % [p.mark, TranslationServer.translate(str(p.text))]
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.07))
		box.add_child(l)
		r.add_child(box)
	add_child(r)
