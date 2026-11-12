extends SceneTree
## Genera i temi di VAULTFALL (docs/16 §6): res://src/ui/theme/main_theme.tres (tema globale, accento Città/ottone)
## e accent_skills.tres / accent_adventure.tres / accent_progress.tres (sovrapposizioni per sezione).
## Uso:  godot --headless --path game -s res://scripts/build_theme.gd
## I temi sono file generati: per cambiarli si modifica QUESTO script (o i telai con `python tools/make_ui_frames.py`).
## I telai 9-slice stanno in res://assets/ui/frames/ con i margini in frames.json (nessun numero duplicato qui).
## Font (OFL, in res://assets/fonts/, licenze accanto e in LICENSES.md §5): Atkinson Hyperlegible Next per il testo e i dati
## (cifre tabellari `tnum`), Departure Mono per titoli e marchio (pixel font: solo a multipli di 11 px, qui 22), Noto Sans Symbols2
## per i simboli (★ ◆ ▸ ▾ ...: sottoinsieme «Vaultfall Symbols»). Catena di ripiego: testo -> simboli -> Departure Mono -> font di sistema (resta solo come ultima rete).
## Le impostazioni di importazione (hinting, antialiasing, subpixel) stanno nei file .import accanto ai font.
## Variazioni di tipo: TitleLabel (placca del titolo), BrandLabel (marchio nella barra), SectionLabel, MutedLabel, MonoLabel,
## NumberLabel, WindowTitle, SidebarButton, AccentButton, TopBarPanel, ContentPanel, LogPanel, SidebarPanel, CardPanel,
## RaisedPanel, InsetPanel, BackdropPanel, SearchField, CardCommon..CardRelic, SlotCommon..SlotRelic.
## Le sezioni (Mansioni oliva, Avventura ruggine, Progresso viola/azzurro) ridefiniscono le variazioni nei temi accent_*.

const UiTypeScript := preload("res://src/ui/theme/UiType.gd")    ## dimensioni dei caratteri: UNA sola fonte (gerarchia tipografica)
const FRAMES := "res://assets/ui/frames/"
const OUT_DIR := "res://src/ui/theme/"
const SECTIONS := ["city", "skills", "adventure", "progress"]
const RARITIES := ["common", "rare", "epic", "legendary", "mythic", "relic"]

const C_TEXT := Color("#e6e1d6")
const C_MUTED := Color("#aaa69c")
const C_DISABLED := Color("#9a9da6")     ## testo disabilitato: ≥ 4,5:1 sul fondo più chiaro dei telai disabilitati (43,44,52 → 5,1:1)
const C_SIDEBAR_DISABLED := Color("#6b6e76")     ## menù laterale: invariato (fuori dall'ambito della revisione scala/tipografia)
const C_TITLE := Color("#f0d9a0")
const C_OUTLINE := Color("#07080b")
const C_INTRO := Color("#c9c2b0")      ## frase «a cosa serve» (IntroHint): contrasto 10:1 sul pannello
## Colore dei testi di sezione (SectionLabel) per accento: abbastanza chiari da avere contrasto ≥ 4,5:1 sul pannello.
const SECTION_TEXT := {"city": "#d2b574", "skills": "#a9c460", "adventure": "#e08a62", "progress": "#98a6ff"}
const SECTION_BAR := {"city": "brass", "skills": "olive", "adventure": "rust", "progress": "indigo"}

var _man: Dictionary = {}
const FONT_DIR := "res://assets/fonts/"
const TNUM := {"tnum": 1}

var _text_font: Font      ## testo e dati (Atkinson Regular, cifre tabellari)
var _data_font: Font      ## etichette di dati (Atkinson Medium, cifre tabellari)
var _bold_font: Font
var _italic_font: Font
var _bold_italic_font: Font
var _mono_font: Font      ## titoli e marchio (Departure Mono, pixel)


func _init() -> void:
	var f := FileAccess.open(FRAMES + "frames.json", FileAccess.READ)
	if f == null:
		push_error("frames.json mancante: lancia python tools/make_ui_frames.py e godot --import")
		quit(1)
		return
	_man = JSON.parse_string(f.get_as_text())
	_setup_fonts()
	var ok := true
	var main := _build_main()
	ok = _save(main, "main_theme.tres") and ok
	for sec in ["skills", "adventure", "progress"]:
		var a := Theme.new()
		_accent(a, sec)
		ok = _save(a, "accent_%s.tres" % sec) and ok
	quit(0 if ok else 1)


## Carica i FontFile e costruisce le FontVariation con la catena di ripiego (i FontFile importati non si modificano).
func _setup_fonts() -> void:
	var pixel := load(FONT_DIR + "DepartureMono-Regular.otf") as Font
	var symbols := load(FONT_DIR + "VaultfallSymbols-Regular.ttf") as Font
	var sys := SystemFont.new()    # ultima rete: glifi che nessun font incluso ha (es. ⚔)
	sys.font_names = PackedStringArray(["Segoe UI Symbol", "Noto Sans Symbols2", "DejaVu Sans", "Arial", "sans-serif"])
	# i simboli stanno in un sottoinsieme di Noto Symbols2 con metriche verticali basse (tools/make_symbol_font.py): un font con
	# interlinea alta come ripiego gonfierebbe ogni riga (l'altezza di una FontVariation è il massimo della catena)
	var chain: Array[Font] = [symbols, pixel, sys]
	_text_font = _variation("AtkinsonHyperlegibleNext-Regular.ttf", chain, TNUM)
	_data_font = _variation("AtkinsonHyperlegibleNext-Medium.ttf", chain, TNUM)
	_bold_font = _variation("AtkinsonHyperlegibleNext-Bold.ttf", chain, TNUM)
	_italic_font = _variation("AtkinsonHyperlegibleNext-Italic.ttf", chain, TNUM)
	_bold_italic_font = _variation("AtkinsonHyperlegibleNext-BoldItalic.ttf", chain, TNUM)
	var title_chain: Array[Font] = [symbols, sys]
	var v := FontVariation.new()
	v.base_font = pixel
	v.fallbacks = title_chain
	v.opentype_features = TNUM
	_mono_font = v


func _variation(file: String, chain: Array[Font], features: Dictionary) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = load(FONT_DIR + file) as Font
	v.fallbacks = chain
	v.opentype_features = features
	# l'interlinea naturale di Atkinson (1,3 em) è più alta dei font di sistema usati finora: la riportiamo a ~1,19 em a 16 px
	v.spacing_top = -1
	v.spacing_bottom = -2
	return v


func _save(t: Theme, file: String) -> bool:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var err := ResourceSaver.save(t, OUT_DIR + file)
	print("Tema salvato in %s%s: %s" % [OUT_DIR, file, error_string(err)])
	return err == OK


# --------------------------------------------------------------------------- tema principale
func _build_main() -> Theme:
	var t := Theme.new()
	t.default_font = _text_font
	t.default_font_size = UiTypeScript.BODY

	# pannelli
	t.set_stylebox("panel", "Panel", _nine("panel_base"))
	t.set_stylebox("panel", "PanelContainer", _nine("panel_base"))
	t.set_type_variation("SidebarPanel", "PanelContainer")
	t.set_stylebox("panel", "SidebarPanel", _nine("sidebar", [0, 0, 8, 0]))
	t.set_type_variation("LogPanel", "PanelContainer")
	t.set_stylebox("panel", "LogPanel", _nine("panel_log"))
	t.set_type_variation("RaisedPanel", "PanelContainer")
	t.set_stylebox("panel", "RaisedPanel", _nine("panel_raised"))
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", _nine("panel_inset"))
	t.set_type_variation("BackdropPanel", "Panel")
	t.set_stylebox("panel", "BackdropPanel", _tile("bg_tile"))
	for r in RARITIES:
		var cv := "Card" + String(r).capitalize()
		t.set_type_variation(cv, "PanelContainer")
		t.set_stylebox("panel", cv, _nine("card_" + r, [6, 6, 6, 6]))
		var sv := "Slot" + String(r).capitalize()
		t.set_type_variation(sv, "PanelContainer")
		t.set_stylebox("panel", sv, _nine("slot_" + r, [4, 4, 4, 4]))
	t.set_stylebox("panel", "TooltipPanel", _nine("panel_tooltip", [8, 6, 8, 6]))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	t.set_stylebox("panel", "PopupPanel", _nine("panel_tooltip", [8, 8, 8, 8]))
	# finestre modali (sottofinestre incorporate): barra del titolo di default, titolo in ottone; il riquadro interno è la cornice ornata
	t.set_constant("title_outline_size", "Window", 3)
	t.set_color("title_color", "Window", C_TITLE)
	t.set_color("title_outline_modulate", "Window", C_OUTLINE)
	t.set_font("title_font", "Window", _mono_font)
	t.set_font_size("title_font_size", "Window", UiTypeScript.PAGE)
	t.set_stylebox("panel", "AcceptDialog", _nine("panel_window", [18, 18, 18, 18]))
	t.set_stylebox("panel", "PopupMenu", _nine("panel_tooltip", [6, 6, 6, 6]))
	t.set_stylebox("hover", "PopupMenu", _nine("sidebar_btn_hover", [10, 3, 6, 3]))
	t.set_color("font_hover_color", "PopupMenu", C_TITLE)
	t.set_constant("v_separation", "PopupMenu", 4)

	# etichette e tipografia
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_font("normal_font", "RichTextLabel", _text_font)
	t.set_font("bold_font", "RichTextLabel", _bold_font)
	t.set_font("italics_font", "RichTextLabel", _italic_font)
	t.set_font("bold_italics_font", "RichTextLabel", _bold_italic_font)
	t.set_font("mono_font", "RichTextLabel", _data_font)
	# NumberLabel/MonoLabel: etichette di dati (anche frasi lunghe): Atkinson Medium a cifre tabellari, non il pixel font
	t.set_font("font", "NumberLabel", _data_font)
	t.set_type_variation("NumberLabel", "Label")
	t.set_font("font", "MonoLabel", _data_font)
	t.set_type_variation("MonoLabel", "Label")
	t.set_color("font_color", "MonoLabel", C_TEXT)
	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", UiTypeScript.NOTE)
	t.set_color("font_color", "MutedLabel", C_MUTED)
	# IntroHint: frase «a cosa serve» di una schermata, richiudibile (progetto di interfaccia F0; usata dalle fasi F6-F11)
	t.set_type_variation("IntroHint", "Label")
	t.set_font_size("font_size", "IntroHint", UiTypeScript.NOTE)
	t.set_color("font_color", "IntroHint", C_INTRO)
	t.set_type_variation("BrandLabel", "Label")
	t.set_font("font", "BrandLabel", _mono_font)
	t.set_font_size("font_size", "BrandLabel", UiTypeScript.PAGE)
	t.set_color("font_color", "BrandLabel", C_TITLE)
	_outline(t, "BrandLabel", 4)
	t.set_type_variation("WindowTitle", "Label")
	t.set_font("font", "WindowTitle", _mono_font)
	t.set_font_size("font_size", "WindowTitle", UiTypeScript.PAGE)
	t.set_color("font_color", "WindowTitle", C_TITLE)
	t.set_stylebox("normal", "WindowTitle", _nine("banner_title_city", [28, 3, 28, 3]))
	_outline(t, "WindowTitle", 3)
	_accent(t, "city")

	# pulsanti
	for type in ["Button", "OptionButton", "MenuButton"]:
		_button(t, type, "std")
	t.set_type_variation("AccentButton", "Button")
	_button(t, "AccentButton", "accent")
	t.set_color("font_color", "AccentButton", C_TITLE)
	t.set_icon("arrow", "OptionButton", _icon("arrow_down"))
	t.set_constant("arrow_margin", "OptionButton", 8)
	t.set_constant("h_separation", "OptionButton", 6)
	t.set_type_variation("SidebarButton", "Button")
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 12
	none.content_margin_right = 8
	none.content_margin_top = 4
	none.content_margin_bottom = 4
	var sel := _nine("sidebar_btn_pressed", [14, 4, 8, 4])
	t.set_stylebox("normal", "SidebarButton", none)
	t.set_stylebox("hover", "SidebarButton", _nine("sidebar_btn_hover", [14, 4, 8, 4]))
	t.set_stylebox("pressed", "SidebarButton", sel)
	t.set_stylebox("hover_pressed", "SidebarButton", sel)
	t.set_stylebox("disabled", "SidebarButton", none)
	t.set_stylebox("focus", "SidebarButton", _nine("focus", [8, 4, 8, 4]))
	t.set_color("font_disabled_color", "SidebarButton", C_SIDEBAR_DISABLED)
	t.set_color("font_color", "SidebarButton", C_TEXT)
	t.set_color("font_hover_color", "SidebarButton", C_TITLE)
	t.set_color("font_pressed_color", "SidebarButton", C_TITLE)
	t.set_color("font_hover_pressed_color", "SidebarButton", C_TITLE)
	t.set_constant("h_separation", "SidebarButton", 8)

	# interruttori e caselle
	for type in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", type, C_TEXT)
		t.set_color("font_hover_color", type, C_TITLE)
		t.set_color("font_pressed_color", type, C_TEXT)
		t.set_color("font_disabled_color", type, C_DISABLED)
		t.set_stylebox("focus", type, _nine("focus", [6, 4, 6, 4]))
		var plain := StyleBoxEmpty.new()          # la casella non è un pulsante: nessun riquadro dietro la scritta
		plain.content_margin_left = 4
		plain.content_margin_right = 4
		plain.content_margin_top = 3
		plain.content_margin_bottom = 3
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, plain)
		t.set_constant("h_separation", type, 8)
	t.set_icon("checked", "CheckBox", _icon("check_on"))
	t.set_icon("unchecked", "CheckBox", _icon("check_off"))
	t.set_icon("checked_disabled", "CheckBox", _icon("check_on_dis"))
	t.set_icon("unchecked_disabled", "CheckBox", _icon("check_off_dis"))
	t.set_icon("radio_checked", "CheckBox", _icon("radio_on"))
	t.set_icon("radio_unchecked", "CheckBox", _icon("radio_off"))
	t.set_icon("radio_checked_disabled", "CheckBox", _icon("radio_on_dis"))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _icon("radio_off_dis"))
	t.set_icon("checked", "CheckButton", _icon("switch_on"))
	t.set_icon("unchecked", "CheckButton", _icon("switch_off"))
	t.set_icon("checked_disabled", "CheckButton", _icon("switch_on_dis"))
	t.set_icon("unchecked_disabled", "CheckButton", _icon("switch_off_dis"))
	t.set_icon("checked_mirrored", "CheckButton", _icon("switch_on"))
	t.set_icon("unchecked_mirrored", "CheckButton", _icon("switch_off"))
	t.set_icon("checked_disabled_mirrored", "CheckButton", _icon("switch_on_dis"))
	t.set_icon("unchecked_disabled_mirrored", "CheckButton", _icon("switch_off_dis"))

	# campi
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _nine("field_normal", [10, 5, 10, 5]))
		t.set_stylebox("focus", type, _nine("field_focus", [10, 5, 10, 5]))
		t.set_stylebox("read_only", type, _nine("field_readonly", [10, 5, 10, 5]))
		t.set_color("font_color", type, C_TEXT)
		t.set_color("caret_color", type, C_TITLE)
		t.set_color("selection_color", type, Color(0.79, 0.64, 0.36, 0.35))
		t.set_color("font_placeholder_color", type, Color("#7d8090"))
	t.set_type_variation("SearchField", "LineEdit")
	t.set_stylebox("normal", "SearchField", _nine("search_normal", [30, 5, 10, 5]))
	t.set_stylebox("focus", "SearchField", _nine("search_focus", [30, 5, 10, 5]))
	t.set_stylebox("panel", "ItemList", _nine("panel_inset", [4, 4, 4, 4]))
	t.set_stylebox("hovered", "ItemList", _nine("sidebar_btn_hover", [8, 3, 6, 3]))
	t.set_stylebox("selected", "ItemList", _nine("sidebar_btn_pressed", [10, 3, 6, 3]))
	t.set_stylebox("selected_focus", "ItemList", _nine("sidebar_btn_pressed", [10, 3, 6, 3]))
	t.set_color("font_color", "ItemList", C_TEXT)
	t.set_color("font_selected_color", "ItemList", C_TITLE)

	# schede
	t.set_stylebox("tab_selected", "TabContainer", _nine("tab_selected", [12, 5, 12, 4]))
	t.set_stylebox("tab_unselected", "TabContainer", _nine("tab_unselected", [12, 5, 12, 4]))
	t.set_stylebox("tab_hovered", "TabContainer", _nine("tab_hover", [12, 5, 12, 4]))
	t.set_stylebox("tab_disabled", "TabContainer", _nine("tab_disabled", [12, 5, 12, 4]))
	t.set_stylebox("tab_focus", "TabContainer", _nine("focus", [8, 4, 8, 4]))
	t.set_stylebox("panel", "TabContainer", _nine("panel_base"))
	t.set_color("font_selected_color", "TabContainer", C_TITLE)
	t.set_color("font_unselected_color", "TabContainer", C_MUTED)
	t.set_color("font_hovered_color", "TabContainer", C_TEXT)
	t.set_color("font_disabled_color", "TabContainer", C_DISABLED)
	t.set_stylebox("tab_selected", "TabBar", _nine("tab_selected", [12, 5, 12, 4]))
	t.set_stylebox("tab_unselected", "TabBar", _nine("tab_unselected", [12, 5, 12, 4]))
	t.set_stylebox("tab_hovered", "TabBar", _nine("tab_hover", [12, 5, 12, 4]))
	t.set_stylebox("tab_disabled", "TabBar", _nine("tab_disabled", [12, 5, 12, 4]))
	t.set_color("font_selected_color", "TabBar", C_TITLE)
	t.set_color("font_unselected_color", "TabBar", C_MUTED)

	# barre di avanzamento, slider, scrollbar, separatori
	t.set_stylebox("background", "ProgressBar", _nine("progress_bg"))
	t.set_stylebox("fill", "ProgressBar", _nine("progress_fill_brass"))
	t.set_color("font_color", "ProgressBar", C_TEXT)
	_outline(t, "ProgressBar", 3)
	t.set_stylebox("slider", "HSlider", _nine("slider_track"))
	t.set_stylebox("grabber_area", "HSlider", _nine("slider_fill"))
	t.set_stylebox("grabber_area_highlight", "HSlider", _nine("slider_fill_hl"))
	t.set_icon("grabber", "HSlider", _icon("slider_grabber_normal"))
	t.set_icon("grabber_highlight", "HSlider", _icon("slider_grabber_highlight"))
	t.set_icon("grabber_disabled", "HSlider", _icon("slider_grabber_disabled"))
	for type in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", type, _nine("scroll_track"))
		t.set_stylebox("scroll_focus", type, _nine("scroll_track"))
		t.set_stylebox("grabber", type, _nine("scroll_grab"))
		t.set_stylebox("grabber_highlight", type, _nine("scroll_hover"))
		t.set_stylebox("grabber_pressed", type, _nine("scroll_pressed"))
	t.set_stylebox("separator", "HSeparator", _nine("separator_h"))
	t.set_constant("separation", "HSeparator", 9)
	t.set_stylebox("separator", "VSeparator", _nine("separator_v"))
	t.set_constant("separation", "VSeparator", 9)
	return t


## Variazioni che cambiano con l'accento della sezione (pannello del contenuto, titoli, sezioni, barre).
func _accent(t: Theme, sec: String) -> void:
	var suffix := "" if sec == "city" else "_" + sec
	t.set_type_variation("ContentPanel", "PanelContainer")
	t.set_stylebox("panel", "ContentPanel", _nine("panel_content" + suffix, [12, 10, 12, 10]))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", _nine("panel_card" + suffix, [10, 8, 10, 8]))
	t.set_type_variation("TopBarPanel", "PanelContainer")
	t.set_stylebox("panel", "TopBarPanel", _nine("topbar_" + sec, [12, 4, 12, 12]))
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", _mono_font)
	t.set_font_size("font_size", "TitleLabel", UiTypeScript.PAGE)
	t.set_color("font_color", "TitleLabel", C_TITLE)
	_outline(t, "TitleLabel", 4)
	t.set_stylebox("normal", "TitleLabel", _nine("banner_title_" + sec, [30, 3, 30, 3]))
	t.set_type_variation("SectionLabel", "Label")
	t.set_font("font", "SectionLabel", _bold_font)
	t.set_font_size("font_size", "SectionLabel", UiTypeScript.SECTION)
	t.set_color("font_color", "SectionLabel", Color(SECTION_TEXT[sec]))
	t.set_stylebox("normal", "SectionLabel", _nine("banner_section_" + sec, [16, 2, 6, 3]))
	t.set_stylebox("fill", "ProgressBar", _nine("progress_fill_" + SECTION_BAR[sec]))


func _button(t: Theme, type: String, kind: String) -> void:
	t.set_stylebox("normal", type, _nine("button_%s_normal" % kind, [12, 5, 12, 5]))
	t.set_stylebox("hover", type, _nine("button_%s_hover" % kind, [12, 5, 12, 5]))
	t.set_stylebox("pressed", type, _nine("button_%s_pressed" % kind, [12, 6, 12, 4]))
	t.set_stylebox("hover_pressed", type, _nine("button_%s_pressed" % kind, [12, 6, 12, 4]))
	t.set_stylebox("disabled", type, _nine("button_%s_disabled" % kind, [12, 5, 12, 5]))
	t.set_stylebox("focus", type, _nine("focus", [12, 5, 12, 5]))
	t.set_color("font_color", type, C_TEXT)
	t.set_color("font_hover_color", type, C_TITLE)
	t.set_color("font_pressed_color", type, C_TITLE)
	t.set_color("font_hover_pressed_color", type, C_TITLE)
	t.set_color("font_focus_color", type, C_TEXT)
	t.set_color("font_disabled_color", type, C_DISABLED)
	t.set_constant("h_separation", type, 6)


func _outline(t: Theme, type: String, size: int) -> void:
	t.set_color("font_outline_color", type, C_OUTLINE)
	t.set_constant("outline_size", type, size)
	t.set_color("font_shadow_color", type, Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", type, 0)
	t.set_constant("shadow_offset_y", type, 2)


func _icon(name: String) -> Texture2D:
	return load(FRAMES + name + ".png") as Texture2D


## StyleBoxTexture 9-slice dal manifest; `content` = margini del contenuto (sinistra, alto, destra, basso).
func _nine(name: String, content: Array = []) -> StyleBoxTexture:
	var m: Dictionary = _man.get(name, {})
	if m.is_empty():
		push_error("telaio sconosciuto: " + name)
	var sb := StyleBoxTexture.new()
	sb.texture = load(FRAMES + name + ".png") as Texture2D
	var mg: Array = m.get("margin")
	sb.texture_margin_left = mg[0]
	sb.texture_margin_top = mg[1]
	sb.texture_margin_right = mg[2]
	sb.texture_margin_bottom = mg[3]
	var tile: String = str(m.get("tile", ""))
	if tile.contains("x"):
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	if tile.contains("y"):
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	var c: Array = content if not content.is_empty() else mg
	sb.content_margin_left = c[0]
	sb.content_margin_top = c[1]
	sb.content_margin_right = c[2]
	sb.content_margin_bottom = c[3]
	return sb


## Mattonella senza giunte: si ripete su entrambi gli assi.
func _tile(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(FRAMES + name + ".png") as Texture2D
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb
