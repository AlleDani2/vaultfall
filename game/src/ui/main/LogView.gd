class_name LogView
extends ScrollContainer
## Registro della colonna destra (rapporto 104). Una riga per messaggio, in ordine di tempo (la più recente in fondo):
##   [striscia colorata] ┬ [SIGLA] Sezione ........ 20:31      <- sezione (colore, sigla + nome breve) e orario tenue
##                       ├ Titolo in grassetto
##                       └ dettaglio in secondario (a capo, mai troncato)
## Il colore e la sigla vengono da LogCategory: gli stessi della voce di menù, del filo lungo il bordo della schermata e
## delle notifiche nelle Impostazioni. Nessuna animazione (quindi «Riduci animazioni» è rispettato per costruzione).
## Solo presentazione: nessuna regola di gioco, nessun tempo di gioco.

const MAX_ROWS := 200
const STRIP_W := 4.0
const ROW_GAP := 8
const TIME_COLOR := Color("7d7a72")
const TITLE_COLOR := Color("efe9d8")
const DETAIL_COLOR := Color("aba79a")

var _box: VBoxContainer
var _empty: Label
var _rows: Array[Dictionary] = []       # {"node", "section", "text"}
var _stick := true                      # resta agganciato in fondo finché il giocatore non scorre in alto


## Compatibilità con il vecchio RichTextLabel: tutto il testo delle righe, una per riga.
var text: String:
	get:
		return plain_text()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = false
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", ROW_GAP)
	add_child(_box)
	get_v_scroll_bar().changed.connect(_on_range_changed)
	get_v_scroll_bar().value_changed.connect(_on_user_scroll)


## Messaggio smorzato finché il registro è vuoto.
func set_empty_text(t: String) -> void:
	if _empty == null:
		_empty = Label.new()
		_empty.theme_type_variation = &"MutedLabel"
		_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_empty.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_box.add_child(_empty)
	_empty.text = t


func row_count() -> int:
	return _rows.size()


func row_section(i: int) -> String:
	return str(_rows[i].section)


func last_text() -> String:
	return "" if _rows.is_empty() else str(_rows[_rows.size() - 1].text)


func plain_text() -> String:
	var parts: PackedStringArray = []
	for r in _rows:
		parts.append(str(r.text))
	return "\n".join(parts)


## Porta il registro in fondo e lo riaggancia (il cassetto lo mostra dopo che è rimasto nascosto: F3).
func scroll_to_end() -> void:
	_stick = true
	var bar := get_v_scroll_bar()
	scroll_vertical = int(maxf(0.0, bar.max_value - bar.page))


func clear_rows() -> void:
	for r in _rows:
		(r.node as Node).queue_free()
	_rows.clear()


## Aggiunge una riga. `time_text` vuoto = orario di sistema (HH:MM).
func add_entry(section: String, text_line: String, time_text: String = "") -> void:
	if _box == null:
		return
	if not LogCategory.is_valid(section):
		section = LogCategory.SYSTEM
	if _empty != null:
		_empty.queue_free()
		_empty = null
	var t := time_text if not time_text.is_empty() else Time.get_time_string_from_system().substr(0, 5)
	var node := _build_row(section, text_line, t)
	_box.add_child(node)
	_rows.append({"node": node, "section": section, "text": text_line})
	while _rows.size() > MAX_ROWS:
		var old: Dictionary = _rows.pop_front()
		(old.node as Node).queue_free()


func _build_row(section: String, text_line: String, time_text: String) -> Control:
	var col := LogCategory.color(section)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("section", section)
	var strip := ColorRect.new()
	strip.name = "Strip"
	strip.color = col
	strip.custom_minimum_size = Vector2(STRIP_W, 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(strip)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_top", 1)
	pad.add_theme_constant_override("margin_bottom", 2)
	row.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)
	# riga di intestazione: sigla su fondo colorato + nome breve + orario tenue a destra
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(chip(section, false))
	var nm := Label.new()
	nm.name = "SectionName"
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.text = LogCategory.label(section)
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nm)
	var tl := Label.new()
	tl.name = "Time"
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tl.text = time_text
	tl.add_theme_font_size_override("font_size", 11)
	tl.add_theme_color_override("font_color", TIME_COLOR)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tl)
	# corpo: titolo in grassetto, dettaglio in secondario
	var body := RichTextLabel.new()
	body.name = "Body"
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.selection_enabled = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = body_bbcode(text_line)
	v.add_child(body)
	return row


## «[b]Titolo[/b]» e, se c'è, il dettaglio a capo in colore secondario. Le parentesi quadre del testo sono neutralizzate.
static func body_bbcode(text_line: String) -> String:
	var parts := LogCategory.split_text(text_line)
	var out := "[color=#%s][b]%s[/b][/color]" % [TITLE_COLOR.to_html(false), _esc(parts[0])]
	if not parts[1].is_empty():
		out += "\n[color=#%s]%s[/color]" % [DETAIL_COLOR.to_html(false), _esc(parts[1])]
	return out


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


## Pastiglia con la sigla (2 lettere) scura sul colore della sezione. `with_name`: aggiunge anche il nome breve accanto.
static func chip(section: String, with_name: bool) -> Control:
	var col := LogCategory.color(section)
	var p := PanelContainer.new()
	p.name = "Chip"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.name = "Tag"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = LogCategory.tag(section)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", LogCategory.ON_COLOR)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	if not with_name:
		return p
	# il contenitore si crea solo qui: prima nasceva sempre e, senza nome, restava orfano a ogni riga del Registro (QA 95)
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(p)
	var nm := Label.new()
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.text = LogCategory.label(section)
	nm.add_theme_font_size_override("font_size", UiType.NOTE)
	nm.add_theme_color_override("font_color", col)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(nm)
	return holder


# ------------------------------------------------------------------ scorrimento

func _on_user_scroll(_v: float = 0.0) -> void:
	var bar := get_v_scroll_bar()
	_stick = bar.value + bar.page >= bar.max_value - 6.0


func _on_range_changed() -> void:
	if _stick:
		var bar := get_v_scroll_bar()
		scroll_vertical = int(maxf(0.0, bar.max_value - bar.page))
