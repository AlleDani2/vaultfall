extends GameScreen
## Manuale in gioco (docs/16 §3.8, voce "manual", tasto F1 o icona «?»): indice per gruppi con ricerca; le pagine sono
## generate dai dati da ManualPages (testi in manual2.csv, numeri da ManualFacts). params {"page": id}.

@onready var _pages: VBoxContainer = %Pages
@onready var _body: RichTextLabel = %Body
@onready var _search: LineEdit = %Search

var _group := ButtonGroup.new()
var _current: String = "start"
var _unlock_count: int = -1
var _group_labels: Dictionary = {}      # indice del gruppo -> Label
var _plain: Dictionary = {}             # pagina -> testo semplice minuscolo (per la ricerca)
var _plain_locale: String = ""
var _strip := RegEx.new()


func open(params: Dictionary) -> void:
	ScreenKit.title_style(get_node("Title") as Label)          # titolo di pagina unico: a larghezza del testo, non a barra intera
	_strip.compile("\\[[^\\]]*\\]")
	var gi := 0
	for g in ManualCatalog.GROUPS:
		var l := Label.new()
		l.theme_type_variation = &"SectionLabel"
		l.text = str(g.title)
		l.name = "Group_%d" % gi
		_pages.add_child(l)
		_group_labels[gi] = l
		for p in g.pages:
			var b := Button.new()
			b.theme_type_variation = &"SidebarButton"
			b.toggle_mode = true
			b.button_group = _group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = ManualPages.page_title_key(p)
			b.pressed.connect(show_page.bind(p))
			b.name = "Page_" + p
			b.set_meta("group", gi)
			_pages.add_child(b)
		gi += 1
	_search.text_changed.connect(_on_search)
	_search.text_submitted.connect(_on_search_submit)
	show_page(str(params.get("page", "start")))


func current_page() -> String:
	return _current


func show_page(page: String) -> void:
	if not ManualPages.PAGES.has(page):
		page = "start"
	_current = page
	_unlock_count = (GameState.data.get("unlocks", []) as Array).size()
	_body.text = ManualPages.build(page, DataRegistry, GameState.data.get("unlocks", []))
	_body.scroll_to_line(0)
	var btn := _pages.get_node_or_null("Page_" + page) as Button
	if btn != null:
		btn.button_pressed = true


func refresh() -> void:
	# la pagina "Come si sblocca" e quella dei mostri dipendono dagli sblocchi
	var n := (GameState.data.get("unlocks", []) as Array).size()
	if n != _unlock_count and (_current == "unlocks" or _current == "drops"):
		var scroll := _body.get_v_scroll_bar().value
		show_page(_current)
		_body.get_v_scroll_bar().value = scroll


# ------------------------------------------------------------------ ricerca

## Pagine che contengono il testo cercato (titolo o contenuto), nell'ordine dell'indice.
func matching_pages(query: String) -> PackedStringArray:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return PackedStringArray(ManualPages.PAGES)
	var out := PackedStringArray()
	_ensure_plain()
	for p in ManualPages.PAGES:
		if str(_plain.get(p, "")).contains(q):
			out.append(p)
	return out


func _ensure_plain() -> void:
	var loc := Loc.locale()
	if loc == _plain_locale and not _plain.is_empty():
		return
	_plain_locale = loc
	_plain.clear()
	var unlocks: Array = GameState.data.get("unlocks", [])
	for p in ManualPages.PAGES:
		var t := tr(ManualPages.page_title_key(p)) + "\n" + _strip.sub(ManualPages.build(p, DataRegistry, unlocks), "", true)
		_plain[p] = t.to_lower()


func _on_search(text: String) -> void:
	var hits := matching_pages(text)
	for c in _pages.get_children():
		if c is Button:
			c.visible = hits.has(c.name.trim_prefix("Page_"))
	for gi in _group_labels:
		var any := false
		for c in _pages.get_children():
			if c is Button and int(c.get_meta("group", -1)) == gi and c.visible:
				any = true
				break
		(_group_labels[gi] as Label).visible = any
	if hits.is_empty():
		_body.text = tr("UI_MAN2_SEARCH_EMPTY")
	elif not hits.has(_current):
		show_page(hits[0])


func _on_search_submit(text: String) -> void:
	var hits := matching_pages(text)
	if not hits.is_empty():
		show_page(hits[0])
