class_name EstateDungeonKit
extends RefCounted
## Piccoli pezzi di interfaccia condivisi da Tenuta, Dungeon (e schede) e Taglie (fase F9 del progetto di interfaccia,
## docs/ui_redesign/06 §2 D17/D23, §3.10, §3.11, §3.15): titolo con «?» (la frase «a cosa serve» si vede alla prima visita e poi si
## richiude), sezione a scomparsa (Disclosure), chip di rischio, scheda a scelta con segnale (! o •). Solo presentazione, nessun numero
## di bilanciamento: i colori e le soglie del rischio vengono da UiKit e dal sistema.

const WARN_MARK := "!"
const DOT_MARK := "•"


## Titolo della schermata con il pulsante «?» sulla stessa riga e, sotto, la frase «a cosa serve». La frase è aperta alla PRIMA visita
## della schermata (Settings.seen_intro) e poi si richiude; il «?» la riapre. Ritorna {"title": Label, "help": Button, "purpose": Label}.
static func title_row(parent: Control, title_key: String, purpose_key: String, screen_id: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var title := Label.new()
	ScreenKit.title_style(title)
	title.text = title_key
	row.add_child(title)
	var help := Button.new()
	help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help.text = "?"
	help.toggle_mode = true
	help.tooltip_text = "UI_F9_INTRO_TIP"
	help.focus_mode = Control.FOCUS_ALL
	help.custom_minimum_size = Vector2(32, 0)
	row.add_child(help)
	var purpose := ScreenKit.muted(purpose_key)
	parent.add_child(purpose)
	var first := not _seen(screen_id)
	purpose.visible = first
	help.set_pressed_no_signal(first)
	help.toggled.connect(func(on: bool) -> void: purpose.visible = on)
	if first:
		_mark_seen(screen_id)
	return {"title": title, "help": help, "purpose": purpose}


static func _seen(screen_id: String) -> bool:
	var seen: Variant = Settings.get_value("seen_intro")
	return seen is Array and (seen as Array).has(screen_id)


static func _mark_seen(screen_id: String) -> void:
	var seen: Array = []
	var cur: Variant = Settings.get_value("seen_intro")
	if cur is Array:
		seen = (cur as Array).duplicate()
	if not seen.has(screen_id):
		seen.append(screen_id)
		Settings.set_value("seen_intro", seen)


## Sezione a scomparsa: pulsante con freccia (▸/▾) e corpo che si mostra/nasconde. `state` (dizionario del chiamante) ricorda
## lo stato aperto/chiuso per `state_key` anche quando il dettaglio viene ricostruito. Ritorna il corpo, dove aggiungere i figli.
static func disclosure(parent: Control, title_key: String, state: Dictionary, state_key: String, open_default: bool = false) -> VBoxContainer:
	var open: bool = bool(state.get(state_key, open_default))
	var btn := Button.new()
	btn.toggle_mode = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.set_pressed_no_signal(open)
	Disclosure.apply(btn, title_key, open)
	parent.add_child(btn)
	var body := VBoxContainer.new()
	body.visible = open
	body.add_theme_constant_override("separation", 6)
	parent.add_child(body)
	btn.toggled.connect(func(on: bool) -> void:
		state[state_key] = on
		body.visible = on
		Disclosure.apply(btn, title_key, on))
	return body


## Chip di rischio (UN solo punto per schermata): testo breve in un riquadro colorato; il dettaglio sta nel tooltip («ⓘ»).
## `level`: "green" | "yellow" | "red".
static func risk_chip(level: String, text: String, tip: String) -> PanelContainer:
	var bg := UiKit.RISK_OK
	var fg := UiKit.RISK_OK_TEXT
	match level:
		"yellow":
			bg = UiKit.RISK_WARN
			fg = UiKit.RISK_WARN_TEXT
		"red":
			bg = UiKit.RISK_BAD
			fg = UiKit.RISK_BAD_TEXT
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_color_override("font_color", fg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## Scheda a scelta (pulsante a bottone con stile d'accento). `mark` = "" | "!" | "•" aggiunto in coda al testo.
static func tab_button(group: ButtonGroup, text: String, tip: String, accent_col: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.tooltip_text = tip
	ScreenKit.style_tab(b, accent_col)
	return b


static func tab_text(base: String, mark: String) -> String:
	return base if mark == "" else "%s %s" % [base, mark]
