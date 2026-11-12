class_name ScreenKit
extends RefCounted
## Mattoncini comuni del restyling UX (resoconto 110): intestazione «a cosa serve» + suggerimento «cosa fare ora»,
## carte con bordo/striscia d'accento, numeri chiave con unità, stati vuoti con pulsante Vai, motivo dei pulsanti disattivi.
## Solo presentazione: nessuna regola di gioco, nessun numero di bilanciamento. I testi sono chiavi del CSV (UI_RS_*) o testi
## già tradotti dal chiamante; i colori vengono dalla palette del progetto (FxPalette) e dalla sezione del Registro (LogCategory).

const BG := Color("#171a22")
const BG_HI := Color("#1d212b")
const EDGE := Color("#3a3f4c")
const TEXT_DIM := Color("#aaa69c")
const GOOD := Color("#a0d8a0")
const BAD := Color("#e07070")
const WARN := Color("#e0c070")
const GOLD := Color("#f0d9a0")

enum Kind { TODO, OK, WARN, INFO }


# ------------------------------------------------------------------ colori di sezione

## Colore d'accento della schermata: quello della sua sezione del Registro (lo stesso del filo lungo il bordo).
static func accent(screen_id: String) -> Color:
	var sec: String = str(LogCategory.SCREEN_SECTION.get(screen_id, ""))
	return Color(LogCategory.COLORS[sec]) if LogCategory.COLORS.has(sec) else Color(GOLD)


# ------------------------------------------------------------------ contenitori

## Stile di una carta: fondo scuro, bordo di 1 px (accento attenuato), striscia d'accento a sinistra di `lw` px.
static func card_style(edge: Color, lw: int = 4, filled: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_HI if filled else BG
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.border_width_left = lw
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## Carta con bordo personalizzato. Ritorna il VBoxContainer interno; il pannello è il suo parent (`panel_of`).
static func card(parent: Control, edge: Color, lw: int = 4, filled: bool = false) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(edge, lw, filled))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


static func panel_of(card_body: Control) -> PanelContainer:
	return card_body.get_parent() as PanelContainer


## Cambia il colore del bordo di una carta già creata (stato: pronta, in corso, bloccata…).
static func set_edge(card_body: Control, edge: Color, lw: int = 4) -> void:
	var p := panel_of(card_body)
	if p != null:
		p.add_theme_stylebox_override("panel", card_style(edge, lw))


## Intestazione di sezione piccola (SectionLabel) con una riga di spiegazione sotto (facoltativa).
static func section(parent: Control, title_key: String, sub_key: String = "") -> void:
	var h := Label.new()
	h.theme_type_variation = &"SectionLabel"
	h.text = title_key
	parent.add_child(h)
	if sub_key != "":
		parent.add_child(muted(sub_key))


## Titolo di PAGINA: un solo stile per tutte le schermate (variazione TitleLabel del tema: corpo `UiType.PAGE`, Departure Mono, targa
## con cornice). Larghezza = quella del testo (mai una barra a tutta larghezza), ancorata a sinistra. Ritorna l'etichetta.
static func title_style(l: Label) -> Label:
	l.theme_type_variation = &"TitleLabel"
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return l


## Crea il titolo di pagina (testo già tradotto o chiave del CSV) e lo aggiunge a `parent`.
static func page_title(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.name = "Title"
	l.text = text
	title_style(l)
	parent.add_child(l)
	return l


## Limita la larghezza di una frase introduttiva a ~`max_px` (≈ 90 caratteri a corpo NOTE): una riga di 190 caratteri su 1300 px non si
## legge (revisione grafica 1.0, punto 21). Mai più larga del contenitore: il minimo segue la larghezza del genitore.
const CAP_TEXT_PX := 680.0


static func cap_text(l: Label, max_px: float = CAP_TEXT_PX) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size.x = max_px
	var apply := func() -> void:
		var par := l.get_parent() as Control
		if par == null:
			return
		var w := minf(max_px, maxf(60.0, par.size.x))
		if absf(l.custom_minimum_size.x - w) > 0.5:
			l.custom_minimum_size.x = w
	l.tree_entered.connect(func() -> void:
		var par := l.get_parent() as Control
		if par != null and not par.resized.is_connected(apply):
			par.resized.connect(apply)
		apply.call())


static func muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func label(text: String, variation: String = "", color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = StringName(variation)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


# ------------------------------------------------------------------ intestazione e suggerimento

## «A cosa serve»: una frase sotto il titolo. Ritorna la barra del suggerimento («Cosa fare ora»), da aggiornare in refresh().
static func intro(parent: Control, purpose_key: String, screen_id: String) -> KitHint:
	if purpose_key != "":
		parent.add_child(muted(purpose_key))
	var h := KitHint.new()
	h.setup(accent(screen_id))
	parent.add_child(h)
	return h


## Barra «Cosa fare ora»: icona + frase + (facoltativo) pulsante Vai che apre un'altra schermata.
class KitHint extends PanelContainer:
	var _mark: Label
	var _text: Label
	var _go: Button
	var _accent: Color = Color(GOLD)
	var _sig: String = ""
	var _target: Dictionary = {}

	func setup(accent_col: Color) -> void:
		_accent = accent_col
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		add_child(h)
		_mark = Label.new()
		_mark.text = "▸"
		h.add_child(_mark)
		_text = Label.new()
		_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(_text)
		_go = Button.new()
		_go.theme_type_variation = &"AccentButton"
		_go.visible = false
		_go.pressed.connect(func() -> void: ScreenKit.go(_target))
		h.add_child(_go)
		_paint(ScreenKit.Kind.INFO)

	func _paint(kind: ScreenKit.Kind) -> void:
		var col := _accent
		match kind:
			ScreenKit.Kind.OK: col = Color(ScreenKit.GOOD)
			ScreenKit.Kind.WARN: col = Color(ScreenKit.WARN)
			ScreenKit.Kind.TODO: col = _accent.lerp(Color.WHITE, 0.45)
			ScreenKit.Kind.INFO: col = Color(ScreenKit.TEXT_DIM)
		var sb := ScreenKit.card_style(col.darkened(0.25), 4)
		sb.bg_color = Color(col.r * 0.10 + 0.08, col.g * 0.10 + 0.08, col.b * 0.10 + 0.09)
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		add_theme_stylebox_override("panel", sb)
		_mark.add_theme_color_override("font_color", col)
		_mark.text = "✓" if kind == ScreenKit.Kind.OK else ("!" if kind == ScreenKit.Kind.WARN else "▸")

	## Aggiorna il suggerimento. `text` già tradotto. `go_text` e `target` ({screen, params}) per il pulsante Vai (opzionali).
	func show_hint(kind: ScreenKit.Kind, text: String, go_text: String = "", tgt: Dictionary = {}) -> void:
		var sig := "%d|%s|%s|%s" % [kind, text, go_text, str(tgt)]
		if sig == _sig:
			return
		_sig = sig
		_paint(kind)
		_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_text.text = text
		_target = tgt
		_go.visible = go_text != "" and not tgt.is_empty()
		_go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_go.text = go_text


## Apre una schermata (stesso canale di ReqLink): {screen, params}.
static func go(tgt: Dictionary) -> void:
	if not tgt.is_empty():
		EventBus.screen_requested.emit(str(tgt.screen), tgt.get("params", {}))


static func target(screen: String, params: Dictionary = {}) -> Dictionary:
	return {"screen": screen, "params": params}


## La schermata è aperta/sbloccata adesso? (per non proporre un «Vai» che non porta da nessuna parte)
static func available(screen_id: String) -> bool:
	var e := ScreenRegistry.get_entry(screen_id)
	return not e.is_empty() and ScreenRegistry.is_available(e, GameState.data.get("unlocks", []))


# ------------------------------------------------------------------ numeri chiave

## Numero chiave in evidenza (grande) con unità e didascalia piccola. Tooltip sul tutto.
class KitStat extends VBoxContainer:
	var value_l: Label
	var unit_l: Label
	var cap_l: Label

	func setup(caption: String, tip: String, color: Color) -> void:
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = tip
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		value_l = Label.new()
		value_l.theme_type_variation = &"NumberLabel"
		value_l.add_theme_font_size_override("font_size", UiType.NUMBER_BIG)
		value_l.add_theme_color_override("font_color", color)
		value_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value_l)
		unit_l = Label.new()
		unit_l.theme_type_variation = &"MutedLabel"
		unit_l.size_flags_vertical = Control.SIZE_SHRINK_END
		unit_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(unit_l)
		cap_l = Label.new()
		cap_l.theme_type_variation = &"MutedLabel"
		cap_l.text = caption
		cap_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cap_l)

	func set_value(value: String, unit: String = "") -> void:
		value_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		unit_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value_l.text = value
		unit_l.text = unit

	func set_color(c: Color) -> void:
		value_l.add_theme_color_override("font_color", c)

	func set_caption(text: String) -> void:
		cap_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cap_l.text = text


static func stat(parent: Control, caption_key: String, tip_key: String = "", color: Color = Color(GOLD)) -> KitStat:
	var s := KitStat.new()
	s.setup(caption_key, tip_key, color)
	parent.add_child(s)
	return s


## Riga di numeri chiave che va a capo se manca spazio.
static func stat_row(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 22)
	f.add_theme_constant_override("v_separation", 6)
	parent.add_child(f)
	return f


## Barra con riempimento tinto (stessa grafica del resto del gioco) e altezza fissa.
static func bar(parent: Control, color: Color, height: int = 10) -> SmoothBar:
	var b := SmoothBar.new()
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("fill", UiKit.tinted_fill(color))
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ pulsanti

## Pulsante disattivo CON motivo: tooltip (anche sul pulsante spento) e, se `rlabel` è dato, riga di testo.
## `reason` vuoto = pulsante attivo. Ritorna true se attivo.
static func gate(btn: Button, reason: String, rlabel: Label = null) -> bool:
	var ok := reason == ""
	btn.disabled = not ok
	btn.tooltip_text = "" if ok else reason
	if rlabel != null:
		rlabel.visible = not ok
		rlabel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		rlabel.text = reason
	return ok


## Riga del motivo (rossa, piccola) da mettere sotto un pulsante.
static func reason_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"MutedLabel"
	l.add_theme_color_override("font_color", Color(BAD))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible = false
	return l


## Pulsante «Vai a …» verso un'altra schermata.
static func go_button(text: String, tgt: Dictionary, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if primary:
		b.theme_type_variation = &"AccentButton"
	b.pressed.connect(go.bind(tgt))
	return b


# ------------------------------------------------------------------ stati vuoti

## Stato vuoto utile: cosa manca (`what`), dove ottenerlo (`where`, facoltativo) e pulsanti Vai (liste di [testo, bersaglio]).
## Il pannello ha bordo tratteggiato leggero, non un buco nero.
static func empty(parent: Control, what: String, where: String = "", actions: Array = [], kind: String = "") -> Control:
	var v := card(parent, Color(EDGE), 4)
	if kind != "":
		var pic := TextureRect.new()
		pic.texture = UiKit.texture("empty_" + kind)
		pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pic)
	var w := label(what, "MonoLabel")
	v.add_child(w)
	if where != "":
		v.add_child(muted(where))
	if not actions.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		v.add_child(row)
		for a in actions:
			row.add_child(go_button(str(a[0]), a[1], row.get_child_count() == 0))
	return panel_of(v)


# ------------------------------------------------------------------ varie

## Piccola etichetta a «pillola» (stato, rarità, ruolo): testo colorato su fondo scuro con bordo dello stesso colore.
static func pill(text: String, color: Color, tip: String = "") -> Control:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", UiType.NOTE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	p.tooltip_text = tip
	set_pill(p, text, color)
	return p


## Aggiorna testo e colore di una pillola creata con `pill()`.
static func set_pill(p: Control, text: String, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.2, color.g * 0.2, color.b * 0.2, 0.9)
	sb.border_color = color.darkened(0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := p.get_child(0) as Label
	l.text = text
	l.add_theme_color_override("font_color", color.lightened(0.25))


## Pulsante-scheda a scelta: la scheda attiva ha il bordo d'accento e il fondo acceso (si vede quale è aperta).
static func style_tab(b: Button, accent_col: Color) -> void:
	var sb_n := card_style(Color(EDGE), 1)
	sb_n.border_width_left = 1
	b.add_theme_stylebox_override("normal", sb_n)
	var sb_h := card_style(accent_col.darkened(0.3), 1, true)
	sb_h.border_width_left = 1
	b.add_theme_stylebox_override("hover", sb_h)
	var sb_p := card_style(accent_col, 2, true)
	sb_p.set_border_width_all(2)
	sb_p.border_width_bottom = 4
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb_p)
	b.add_theme_color_override("font_pressed_color", Color(GOLD))
	b.add_theme_color_override("font_hover_pressed_color", Color(GOLD))


## Riga selezionabile di un elenco (dungeon, incursioni, boss, talenti…): titolo, sottotitolo e pillola di stato dentro un riquadro con
## bordo che si accende quando è scelta. È un contenitore (l'altezza segue il testo a capo, niente testi tagliati) con un pulsante
## trasparente sopra: stesso comportamento di un pulsante a scelta (ButtonGroup, `pressed`, `disabled`), ma leggibile a colpo d'occhio.
class PickRow extends PanelContainer:
	signal pressed
	var btn: Button
	var title_l: Label
	var sub_l: Label
	var pill: Control
	var icon_l: TextureRect
	var _normal: StyleBoxFlat
	var _hover_style: StyleBoxFlat
	var _sel_style: StyleBoxFlat
	var _hovering: bool = false
	var toggle_mode: bool:
		get:
			return btn.toggle_mode
		set(v):
			btn.toggle_mode = v
	var button_group: ButtonGroup:
		get:
			return btn.button_group
		set(v):
			btn.button_group = v
	var disabled: bool:
		get:
			return btn.disabled
		set(v):
			btn.disabled = v
	var button_pressed: bool:
		get:
			return btn.button_pressed
		set(v):
			btn.button_pressed = v
			_restyle()

	func set_pressed_no_signal(v: bool) -> void:
		btn.set_pressed_no_signal(v)
		_restyle()

	## Il tooltip sta sul pulsante trasparente (è lui che riceve il mouse).
	func set_tip(text: String) -> void:
		btn.tooltip_text = text

	## Cambia il bordo di riposo (stato: acquistabile, al massimo, bloccato…).
	func set_card(edge: Color, filled: bool = false) -> void:
		_normal = ScreenKit.card_style(edge, 4, filled)
		_restyle()

	func _restyle() -> void:
		var st: StyleBoxFlat = _normal
		if btn.button_pressed and btn.toggle_mode:
			st = _sel_style
		elif _hovering and not btn.disabled:
			st = _hover_style
		add_theme_stylebox_override("panel", st)

	func setup(title: String, sub: String, pill_text: String, pill_col: Color, locked: bool, accent_col: Color, tip: String = "",
			icon_tex: Texture2D = null) -> void:
		custom_minimum_size = Vector2(0, 40)
		_normal = ScreenKit.card_style(Color(ScreenKit.EDGE), 3)
		_hover_style = ScreenKit.card_style(accent_col.darkened(0.3), 3, true)
		_sel_style = ScreenKit.card_style(accent_col, 5, true)
		_sel_style.set_border_width_all(2)
		_sel_style.border_width_left = 5
		var outer := HBoxContainer.new()
		outer.add_theme_constant_override("separation", 8)
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(outer)
		if icon_tex != null and icon_tex.get_width() <= 64:
			var ic := TextureRect.new()
			ic.texture = icon_tex
			ic.custom_minimum_size = icon_tex.get_size()
			ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			outer.add_child(ic)
			icon_l = ic
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(box)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(top)
		title_l = Label.new()
		title_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title_l.text = title
		title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART        # i nomi lunghi vanno a capo, mai tagliati
		title_l.custom_minimum_size = Vector2(40, 0)
		title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			title_l.add_theme_color_override("font_color", Color(ScreenKit.TEXT_DIM))
		top.add_child(title_l)
		if pill_text != "":
			pill = ScreenKit.pill(pill_text, pill_col)
			pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(pill)
		if sub != "":
			sub_l = ScreenKit.muted("")
			sub_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			sub_l.custom_minimum_size = Vector2(40, 0)
			sub_l.text = sub
			sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(sub_l)
		# pulsante trasparente sopra a tutto: riceve clic, hover e tooltip
		btn = Button.new()
		btn.flat = true
		btn.toggle_mode = true
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.tooltip_text = tip
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			btn.add_theme_stylebox_override(st, empty)
		add_child(btn)
		btn.pressed.connect(func() -> void:
			_restyle()
			pressed.emit())
		btn.mouse_entered.connect(func() -> void:
			_hovering = true
			_restyle())
		btn.mouse_exited.connect(func() -> void:
			_hovering = false
			_restyle())
		_restyle()


static func pick_row(parent: Control, group: ButtonGroup, title: String, sub: String, pill_text: String, pill_col: Color, locked: bool,
		accent_col: Color, tip: String = "", icon_tex: Texture2D = null) -> PickRow:
	var r := PickRow.new()
	parent.add_child(r)
	r.setup(title, sub, pill_text, pill_col, locked, accent_col, tip, icon_tex)
	if group != null:
		r.button_group = group
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## Etichetta piccola con bordo (ricompensa, mostro, affisso): icona facoltativa (32/64 px, 1:1) + testo.
static func chip(parent: Control, text: String, icon: Texture2D = null, tip: String = "", color: Color = Color(EDGE)) -> Control:
	var p := PanelContainer.new()
	var sb := card_style(color, 1)
	sb.border_width_left = 1
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if icon != null and icon.get_width() <= 64:               # icone 32/64 px mostrate 1:1 (mai ridimensionate); i ritratti grandi non vanno nei chip
		var t := TextureRect.new()
		t.texture = icon
		t.custom_minimum_size = icon.get_size()
		t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	parent.add_child(p)
	return p


## Icona di un oggetto (le casse stanno in una cartella a parte). Segnaposto colorato se il PNG manca (IconLib).
static func item_icon(item_id: String) -> Texture2D:
	if ResourceLoader.exists("res://assets/icons/crates/%s.png" % item_id):
		return IconLib.icon("crates", item_id)
	return IconLib.icon("items", item_id)


## Riga di requisito spuntabile: «✓ Livello Eroe 8 (ora 12)» in verde o «✗ …» in rosso, con pulsante Vai se c'è una strada.
static func req_row(parent: Control, ok: bool, text: String, tgt: Dictionary = {}, go_text: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var m := Label.new()
	m.text = "✓" if ok else "✗"
	m.add_theme_color_override("font_color", Color(GOOD) if ok else Color(BAD))
	row.add_child(m)
	var l := label(text, "", Color(GOOD) if ok else Color(TEXT_DIM))
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if not ok and not tgt.is_empty() and go_text != "":
		row.add_child(go_button(go_text, tgt))


## Meccanica di un boss: nome in evidenza e spiegazione sotto (una riga ciascuna, niente elenco di frasi lunghe).
static func mech_row(parent: Control, mech_name: String, desc: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var d := Label.new()
	d.text = "◆"
	d.add_theme_color_override("font_color", Color("#e0b640"))
	d.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(d)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var n := label(mech_name, "MonoLabel", Color("#e0c070"))
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(n)
	var t := muted(desc)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(t)


## Motivo per cui la Rifondazione non è disponibile, già tradotto e con i numeri al posto dei segnaposto ("" = disponibile).
static func refound_reason(sys: PrestigeSystem) -> String:
	if sys == null:
		return ""
	var key := str(sys.can_refound())
	if key == "":
		return ""
	return TranslationServer.translate(key).format({"units": NumberFormat.fmt(floorf(sys.lifetime_units())), "min": NumberFormat.fmt(sys.refound_min_units())})
