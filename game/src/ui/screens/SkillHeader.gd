class_name SkillHeader
extends VBoxContainer
## Testata unica delle mansioni e della Coltivazione (progetto di interfaccia F7, docs/ui_redesign/06 §3.7).
## Due blocchi: la TESTATA di una riga (icona, nome, livello, barra XP «cur / next», attrezzo; a destra i pulsanti che le
## aggiunge la schermata, p. es. [Talenti •] e [Coda ▾], poi «?») e la STRISCIA «In corso» di una riga (puntino, icona, nome,
## barra del ciclo, informazioni, ultimo guadagno, [Ferma]). Solo costruzione dei nodi: i testi li scrive la schermata.
## La chiave del tutorial `skill_header` sta sul riquadro della testata.

const FX_PAD := 4.0                       # margine del riquadro che contiene le icone animate (più piccolo che in passato: righe basse)
const HEAD_ICON := 32.0
const STRIP_ICON := 24.0

var head_panel: PanelContainer
var icon: TextureRect
var title: Label
var level_l: Label
var xp_bar: ProgressBar
var xp_l: Label
var eta_l: Label                          # «prossimo livello tra…»: non occupa posto, il testo va nel suggerimento della barra
var tool_l: Label
var buttons: HBoxContainer                # a destra: i pulsanti della schermata e «?»
var help_btn: Button

var strip: PanelContainer
var strip_dot: Label
var strip_icon: TextureRect
var strip_name: Label
var strip_bar: SmoothBar
var strip_info: Label
var strip_gain: Label
var strip_btn: Button

var _screen_id: String = ""


## `help_tip` = descrizione comica (già tradotta): compare nel suggerimento del «?», che apre la pagina del Manuale.
func setup(skill_id: String, title_text: String, help_tip: String, screen_id: String, ghost: bool = true) -> void:
	_screen_id = screen_id
	add_theme_constant_override("separation", 6)
	head_panel = PanelContainer.new()
	add_child(head_panel)
	TutorialTargets.mark(head_panel, "skill_header")
	var flow := HFlowContainer.new()               # a capo solo se la finestra è molto stretta
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 4)
	head_panel.add_child(flow)
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	flow.add_child(left)
	icon = TextureRect.new()
	icon.texture = IconLib.icon("skills", skill_id)
	icon.custom_minimum_size = Vector2(HEAD_ICON, HEAD_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(clip_box(icon, HEAD_ICON))
	title = ScreenKit.title_style(_label(title_text, &"TitleLabel"))
	var no_frame := StyleBoxEmpty.new()               # il titolo senza cornice: la testata sta in una riga sola
	no_frame.content_margin_left = 2
	no_frame.content_margin_right = 2
	title.add_theme_stylebox_override("normal", no_frame)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(title)
	level_l = _label("", &"")
	level_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(level_l)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.min_value = 0.0
	xp_bar.max_value = 1.0
	xp_bar.step = 0.0
	xp_bar.custom_minimum_size = Vector2(150, 16)
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(xp_bar)
	if ghost:
		FxBarGhost.attach(xp_bar)                  # lampo chiaro sul tratto di XP appena guadagnato
	xp_l = _label("", &"MonoLabel")
	xp_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_l.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(xp_l)
	eta_l = _label("", &"MutedLabel")
	eta_l.visible = false
	left.add_child(eta_l)
	tool_l = _label("", &"MutedLabel")
	tool_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(tool_l)
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL | Control.SIZE_SHRINK_END
	buttons.alignment = BoxContainer.ALIGNMENT_END
	flow.add_child(buttons)
	help_btn = Button.new()
	help_btn.name = "HelpBtn"
	help_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help_btn.text = "?"
	help_btn.custom_minimum_size = Vector2(34, 0)
	help_btn.tooltip_text = help_tip + ("\n\n" if not help_tip.is_empty() else "") + tr("UI_SKILLS_HELP_HINT")
	help_btn.pressed.connect(func() -> void:
		EventBus.screen_requested.emit("manual", {"page": ManualCatalog.page_for_screen(_screen_id)}))
	buttons.add_child(help_btn)
	_build_strip()


## Inserisce un pulsante a destra, prima del «?».
func add_action_button(b: Button) -> void:
	if b == null:
		return
	buttons.add_child(b)
	buttons.move_child(b, buttons.get_child_count() - 2)


func _build_strip() -> void:
	strip = PanelContainer.new()
	strip.name = "ActiveStrip"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.9)
	sb.set_border_width_all(1)
	sb.border_color = Color("#3a3f4c")
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	strip.add_theme_stylebox_override("panel", sb)
	strip.custom_minimum_size = Vector2(0, 38)
	add_child(strip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	strip.add_child(h)
	strip_dot = _label("○", &"")
	strip_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(strip_dot)
	strip_icon = TextureRect.new()
	strip_icon.custom_minimum_size = Vector2(STRIP_ICON, STRIP_ICON)
	strip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	strip_icon.pivot_offset = Vector2(STRIP_ICON, STRIP_ICON) / 2.0
	h.add_child(clip_box(strip_icon, STRIP_ICON))
	strip_name = _label("", &"")
	strip_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(strip_name)
	strip_bar = SmoothBar.new()
	strip_bar.custom_minimum_size = Vector2(150, 14)
	strip_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(strip_bar)
	strip_info = _label("", &"MutedLabel")
	strip_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_info.clip_text = true
	strip_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	strip_info.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(strip_info)
	strip_gain = _label("", &"MonoLabel")
	strip_gain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(strip_gain)
	strip_btn = Button.new()
	strip_btn.text = "UI_SKILLS_STOP"
	h.add_child(strip_btn)


## Riquadro che CONTIENE un'icona animata: margine di FX_PAD px attorno e `clip_contents`, così ciò che si muove (dondolio
## dell'attrezzo, schiacciamento della risorsa) non esce mai dal proprio posto né tocca il testo vicino (rapporto 104).
static func clip_box(ic: TextureRect, side: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(side + 2.0 * FX_PAD, side + 2.0 * FX_PAD)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(FX_PAD))
	return box


static func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l
