extends Control
## Menù principale (T-0.4 / R-SAV-5, revisione 1.0): illustrazione a tutta pagina, logo grande, Continua · Nuova partita ·
## Cooperativa (LAN) · Impostazioni · Crediti · Esci, con Novità e versione in basso. Tutto si ricompone con la finestra:
## logo e pulsanti seguono l'area logica (UiScale), l'illustrazione copre sempre lo schermo senza toccare il file (nodo con
## stretch, regola D-6). Nuova partita apre gli slot (eroe, classe, capitolo, tempo di gioco, ultimo salvataggio: SlotSummary,
## con cache), con ripristino da copia di sicurezza per quelli danneggiati e conferma prima di sovrascrivere o eliminare.
## Una breve schermata di caricamento copre il passaggio alla partita. Esc dentro un pannello torna al menù.

const MAIN_SCENE := "res://src/ui/main/MainScreen.tscn"
const SETTINGS_SCENE := "res://src/ui/screens/SettingsScreen.tscn"
const KEY_ART: Texture2D = preload("res://assets/ui/title/title_keyart.png")      # copia identica di store/store_keyart_wide.png
const LOGO: Texture2D = preload("res://assets/brand/logo_wordmark.png")   # logo grande (tools/make_logo.py), griglia 1:1: si mostra a scala INTERA
const LOGO_SIZE := Vector2(104, 17)       # misura della griglia del logo (la verifica è nei test: deve coincidere con LOGO)
const TEXT_ON_BAND := Color(0.96, 0.93, 0.82)
const BAND_COLOR := Color(0.03, 0.03, 0.07, 0.84)
const HERO_K := 1.4                       # «Continua» è alto 1,4 volte un pulsante normale (azione primaria)
const LOADING_MIN_S := 0.45             # la schermata di caricamento non lampeggia: resta almeno questo (0 con «Riduci animazioni»)
const COOP_SCREEN := "coop_lobby"

## Precaricamento in un thread della schermata principale (resoconto 100): compilare gli script della UI costa ~0,5 s di
## CPU su un PC lento; mentre il giocatore guarda il menù lo fa un thread, e «Continua» trova la scena già pronta.
static var _main_requested: bool = false

@onready var _continue: Button = %ContinueButton
@onready var _new: Button = %NewGameButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _message: Label = %Message
@onready var _panel: PanelContainer = %Panel
@onready var _slots: VBoxContainer = %Slots
@onready var _confirm: ConfirmationDialog = %Confirm
@onready var _menu: VBoxContainer = $Margin/Stage/Menu
@onready var _title: TextureRect = $Margin/Stage/Menu/Title
var _title_box: Control               # contenitore alto quanto il logo e largo zero: il logo può sporgere dai pulsanti

## Emesso al posto del cambio di scena quando StartScreen non è la scena corrente (es. nei test).
signal navigate(scene_path: String)

var _mode_option: OptionButton
var _mode_desc: Label                 # descrizione della modalità scelta (cosa cambia, cosa non si può rifare)
var _coop: Button
var _credits_btn: Button
var _home: VBoxContainer              # sotto «Continua»: l'ultima partita, oppure l'invito a cominciare
var _home_body: Label
var _footer: HBoxContainer
var _spacer: Control                  # respiro fra la frase sotto il logo e «Continua»
var _row_a: HBoxContainer             # Nuova partita · Cooperativa
var _row_b: HBoxContainer             # Impostazioni · Crediti
var _pending: Callable
var _settings_view: Control
var _credits_view: Control
var _backdrop: StartBackdrop
var _tagline: Label
var _art: TextureRect
var _slot_note: String = ""           # esito dell'ultima azione sugli slot (ripristino, esportazione), mostrato nel pannello
var _loading: Control
var _loading_bar: ProgressBar
var _loading_path: String = ""
var _loading_t: float = 0.0
var _busy: bool = false
var _panel_tall: bool = true          # Impostazioni e Crediti riempiono l'altezza; gli slot occupano solo quanto serve


func _ready() -> void:
	_continue.pressed.connect(_on_continue)
	_new.pressed.connect(show_slots)
	_settings.pressed.connect(show_settings)
	_quit.pressed.connect(SaveService.request_quit)
	_confirm.confirmed.connect(func() -> void:
		if _pending.is_valid():
			_pending.call())
	DialogKit.style_confirm(_confirm, 440)
	_build_art()
	_build_menu_extras()
	_build_backdrop()
	_build_footer()
	_set_panel(false)
	_refresh_continue()
	resized.connect(_apply_layout)
	_apply_layout()
	# senza partite il focus (bordo dorato) va a «Nuova partita»: un pulsante grigio non deve sembrare quello da premere
	_continue_or_new_focus()
	_preload_main.call_deferred()
	set_process(false)


## Una sola richiesta per processo; ignorata se la scena è già in cache. Il vero caricamento resta `change_scene_to_file`
## (che trova la risorsa già pronta o attende il thread).
func _preload_main() -> void:
	# solo quando il menù è la scena principale vera (non nei test né dentro altre schermate)
	if _main_requested or not is_inside_tree() or get_tree().current_scene != self:
		return
	_main_requested = true
	if ResourceLoader.has_cached(MAIN_SCENE):
		return
	ResourceLoader.load_threaded_request(MAIN_SCENE, "PackedScene", true)


## Se si esce (o si cambia scena) mentre il thread lavora ancora si attende la fine: niente caricamento interrotto
## a metà (che finirebbe nel registro errori).
func _exit_tree() -> void:
	if _main_requested and ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		ResourceLoader.load_threaded_get(MAIN_SCENE)


# ------------------------------------------------------------------ costruzione

## Illustrazione di sfondo (stessa immagine dello store, copiata senza modifiche): riempie lo schermo con stretch, pixel nitidi,
## più un velo scuro perché logo e testi si leggano sopra il disco luminoso.
func _build_art() -> void:
	_art = TextureRect.new()
	_art.name = "KeyArt"
	_art.texture = KEY_ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art)
	move_child(_art, 1)
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(0.03, 0.03, 0.07, 0.42)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	move_child(veil, 2)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.78)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	var shade := TextureRect.new()
	shade.name = "Shade"
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	move_child(shade, 3)


## Frase sotto il logo, riga dell'ultima partita sotto «Continua», voci Cooperativa e Crediti.
func _build_menu_extras() -> void:
	_title_box = Control.new()
	_title_box.name = "TitleBox"
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(_title_box)
	_menu.move_child(_title_box, _title.get_index())
	_title.reparent(_title_box)
	_title.custom_minimum_size = Vector2.ZERO
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tagline = Label.new()
	_tagline.name = "Tagline"
	_tagline.text = "UI_START_TAGLINE"
	_tagline.theme_type_variation = &"MutedLabel"
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_art(_tagline)
	_menu.add_child(_tagline)
	_menu.move_child(_tagline, _title_box.get_index() + 1)

	_home = VBoxContainer.new()
	_home.name = "Home"
	_home_body = Label.new()
	_home_body.name = "HomeBody"
	_home_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_home_body.theme_type_variation = &"MutedLabel"
	_home_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_home_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_art(_home_body)
	_home.add_child(_home_body)
	_menu.add_child(_home)
	_menu.move_child(_home, _continue.get_index() + 1)

	_coop = Button.new()
	_coop.name = "CoopButton"
	_coop.text = "UI_M10_COOP"
	_coop.tooltip_text = "UI_M10_COOP_TIP"
	_coop.pressed.connect(_on_coop)

	_credits_btn = Button.new()
	_credits_btn.name = "CreditsButton"
	_credits_btn.text = "UI_CRED_BUTTON"
	_credits_btn.pressed.connect(show_credits)

	# gerarchia a tre livelli: Continua (primario, grande) · quattro azioni a coppie · Esci (separato, rosso spento)
	_spacer = Control.new()
	_spacer.name = "TaglineGap"
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(_spacer)
	_menu.move_child(_spacer, _tagline.get_index() + 1)
	_row_a = _make_row("RowA", [_new, _coop])
	_row_b = _make_row("RowB", [_settings, _credits_btn])
	_menu.move_child(_row_a, _home.get_index() + 1)
	_menu.move_child(_row_b, _row_a.get_index() + 1)
	_quit.add_theme_color_override("font_color", Color(0.93, 0.62, 0.58))
	_quit.add_theme_color_override("font_hover_color", Color(1.0, 0.76, 0.72))
	_menu.move_child(_quit, _row_b.get_index() + 1)

	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	_menu.move_child(_message, _menu.get_child_count() - 1)


## Riga di pulsanti affiancati della stessa larghezza (stesso tema dei pulsanti in partita).
func _make_row(row_name: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 10)
	_menu.add_child(row)
	for b in buttons:
		if (b as Node).get_parent() != null:
			(b as Node).reparent(row)
		else:
			row.add_child(b as Node)
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


## Testo direttamente sull'illustrazione: avorio chiaro su una banda scura quasi opaca (contrasto ≥ 4,5:1 anche sul disco
## luminoso), niente contorno «adesivo» attorno alle lettere.
func _over_art(l: Label) -> void:
	l.add_theme_color_override("font_color", TEXT_ON_BAND)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BAND_COLOR
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	l.add_theme_stylebox_override("normal", sb)


## Barra in basso: versione a sinistra; Novità e copyright a destra.
func _build_footer() -> void:
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_theme_constant_override("separation", 14)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_left = 24.0
	_footer.offset_right = -24.0
	_footer.offset_top = -44.0
	_footer.offset_bottom = -10.0
	add_child(_footer)
	var ver := Label.new()
	ver.name = "VersionLabel"
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ver.theme_type_variation = &"MutedLabel"
	ver.text = Loc.tf("UI_M10_VERSION", {"v": AppInfo.version()})
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_over_art(ver)
	_footer.add_child(ver)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(spacer)
	var news := Button.new()
	news.name = "NewsButton"
	news.text = "UI_FB_NEWS_TITLE"
	news.flat = true
	news.pressed.connect(func() -> void: NewsView.show_dialog(self))
	_footer.add_child(news)
	var copy := Label.new()
	copy.name = "CopyrightLabel"
	copy.text = "UI_M10_COPYRIGHT"
	copy.theme_type_variation = &"MutedLabel"
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_over_art(copy)
	_footer.add_child(copy)


## Sfondo animato: scintille dorate sopra l'illustrazione (nessun portello separato: c'è già nell'immagine).
func _build_backdrop() -> void:
	_backdrop = StartBackdrop.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	move_child(_backdrop, 4)
	_backdrop.setup(null)


## Dimensioni che seguono l'area logica: logo e pulsanti crescono con lo schermo (a 1080p e 4K la scala automatica dà circa
## 1536×864 logici), ma non oltre quello che l'altezza permette; il pannello degli slot occupa una colonna centrale.
func _apply_layout() -> void:
	if _title == null:
		return
	var view := size
	var compact := view.y < 700.0
	var sep := 6 if compact else 10
	var bh := 40.0 if compact else (46.0 if view.y < 1000.0 else 52.0)
	var hero := roundf(bh * HERO_K)
	_menu.add_theme_constant_override("separation", sep)
	_spacer.custom_minimum_size = Vector2(0.0, 6.0 if compact else 18.0)
	var bw := clampf(view.x * 0.34, 380.0, 540.0)
	_continue.custom_minimum_size = Vector2(bw, hero)
	_continue.add_theme_font_size_override("font_size", _continue.get_theme_font_size("font_size", "Button") + 4)
	_row_a.custom_minimum_size = Vector2(bw, 0.0)
	_row_b.custom_minimum_size = Vector2(bw, 0.0)
	for b in [_new, _coop, _settings, _credits_btn]:
		(b as Button).custom_minimum_size = Vector2(0.0, bh)
	_quit.custom_minimum_size = Vector2(bw, roundf(bh * 0.85))
	_home_body.custom_minimum_size = Vector2(bw, 0)
	_home_body.add_theme_font_size_override("font_size", _home_body.get_theme_font_size("font_size", "MutedLabel") + 2)
	_tagline.custom_minimum_size = Vector2(bw, 0)
	_message.custom_minimum_size = Vector2(bw, 0)
	# logo a scala INTERA (k celle di griglia per pixel logico): ~46% della larghezza, ma non oltre quello che l'altezza permette
	var rest := hero + 3.0 * bh + 80.0 + _spacer.custom_minimum_size.y + 9.0 * float(sep)    # tasti, frase e riga dell'ultima partita
	var k_h := floorf((view.y - 72.0 - rest) / LOGO_SIZE.y)
	var k_w := floorf(view.x * 0.46 / LOGO_SIZE.x)
	var k := clampf(minf(k_h, k_w), 2.0, 8.0)
	var logo := LOGO_SIZE * k
	_title_box.custom_minimum_size = Vector2(0.0, logo.y)
	_title.anchor_left = 0.5
	_title.anchor_right = 0.5
	_title.anchor_top = 0.0
	_title.anchor_bottom = 0.0
	_title.offset_left = -logo.x * 0.5
	_title.offset_right = logo.x * 0.5
	_title.offset_top = 0.0
	_title.offset_bottom = logo.y
	_apply_panel_size()


func _apply_panel_size() -> void:
	var view := size
	var w := clampf(view.x * 0.74, 600.0, 1040.0)
	_panel.custom_minimum_size = Vector2(w, maxf(view.y - 150.0, 300.0) if _panel_tall else 0.0)
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if _panel_tall else Control.SIZE_SHRINK_CENTER
	var scroll := _slots.get_node_or_null("SlotScroll") as ScrollContainer
	if scroll != null:
		var list := scroll.get_child(0) as Control
		if list is GridContainer:
			(list as GridContainer).columns = 3 if w >= 900.0 else 1
		scroll.custom_minimum_size.y = minf(list.get_combined_minimum_size().y, maxf(view.y - 330.0, 200.0))


## Messaggio sotto il menù (errori, Cooperativa non disponibile): compare solo quando c'è qualcosa da dire.
func _say(text: String) -> void:
	_message.text = text
	_message.visible = not text.is_empty()


# ------------------------------------------------------------------ slot: lettura (con cache)

## Slot più recente caricabile (0 se nessuno).
func best_slot() -> int:
	var last := int(Settings.get_value("last_slot"))
	if SaveService.is_valid_slot(last) and SlotSummary.get_info(last).get("ok", false):
		return last
	var best := 0
	var best_t := -1
	for s in range(1, SaveService.SLOTS + 1):
		var info := SlotSummary.get_info(s)
		if info.get("ok", false) and int(info.saved_at_unix) > best_t:
			best = s
			best_t = int(info.saved_at_unix)
	return best


func _refresh_continue() -> void:
	_continue.disabled = best_slot() == 0
	# senza partite l'azione primaria è «Nuova partita»: prende lo stile in ottone (Continua resta spento)
	_new.theme_type_variation = &"AccentButton" if _continue.disabled else &""
	_refresh_home()


## Riga sotto «Continua»: slot, classe, tempo di gioco. Senza partite, un invito (chi comincia sa subito cosa premere).
func _refresh_home() -> void:
	if _home == null:
		return
	var s := best_slot()
	if s > 0:
		var info := SlotSummary.get_info(s)
		var cls := SlotSummary.class_label(info)
		var parts := PackedStringArray([Loc.tf("UI_SLOT_N", {"n": s})])
		if not cls.is_empty():
			parts.append(cls)
		parts.append(Loc.tf("UI_M10_TOTAL_LEVEL_SHORT", {"n": NumberFormat.fmt(int(info.get("total_level", 0)))}))
		parts.append(SlotSummary.play_time(float(info.get("playtime_s", 0.0))))
		_home_body.text = " · ".join(parts)
	else:
		_home_body.text = tr("UI_UXA_START_FIRST_BODY")


func _set_panel(on: bool, tall: bool = true) -> void:
	_panel_tall = tall
	_apply_panel_size()
	_panel.visible = on
	_menu.visible = not on
	if _footer != null:
		_footer.visible = not on
	if _backdrop != null:
		_backdrop.refresh()


func _continue_or_new_focus() -> void:
	(_new if _continue.disabled else _continue).grab_focus.call_deferred()


func _on_continue() -> void:
	var s := best_slot()
	if s > 0:
		_with_loading(load_slot.bind(s))


## Cooperativa (LAN): carica l'ultima partita e apre la Lobby. Il coop vive dentro la partita e si sblocca con la prima
## Incursione: se la partita non lo ha ancora sbloccato, lo si dice qui senza caricare nulla.
func _on_coop() -> void:
	var s := best_slot()
	if s == 0:
		_say(tr("UI_M10_COOP_NEEDS_GAME"))
		return
	if not bool(SlotSummary.get_info(s).get("coop", false)):
		_say(tr("UI_M10_COOP_LOCKED"))
		return
	_say("")
	MenuIntent.screen = COOP_SCREEN
	_with_loading(load_slot.bind(s))


# ------------------------------------------------------------------ slot: carte

func show_slots() -> void:
	_close_settings()
	_close_credits()
	_set_panel(true, false)
	for c in _slots.get_children():
		c.free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_slots.add_child(head)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "UI_BACK"
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(_back_to_menu)
	head.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "UI_SELECT_SLOT"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var mode_row := HBoxContainer.new()
	var ml := Label.new()
	ml.text = "UI_SELECT_MODE"
	mode_row.add_child(ml)
	_mode_option = OptionButton.new()
	for i in GameState.MODES.size():
		var m: String = GameState.MODES[i]
		_mode_option.add_item("UI_MODE_" + m.to_upper(), i)
		if not GameState.ENABLED_MODES.has(m):
			_mode_option.set_item_disabled(i, true)
			_mode_option.set_item_tooltip(i, "UI_MODE_LOCKED_HINT")
	_mode_option.selected = 0
	mode_row.add_child(_mode_option)
	_slots.add_child(mode_row)
	_mode_desc = Label.new()
	_mode_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_mode_desc.theme_type_variation = &"MutedLabel"
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.custom_minimum_size = Vector2(420, 0)
	_slots.add_child(_mode_desc)
	_mode_option.item_selected.connect(func(_i: int) -> void: _refresh_mode_desc())
	_refresh_mode_desc()
	var scroll := ScrollContainer.new()
	scroll.name = "SlotScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_slots.add_child(scroll)
	var list := GridContainer.new()                  # tre carte AFFIANCATE (una per riga se il pannello è stretto)
	list.name = "SlotList"
	list.columns = 3
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation", 10)
	list.add_theme_constant_override("v_separation", 10)
	scroll.add_child(list)
	for s in range(1, SaveService.SLOTS + 1):
		list.add_child(_slot_card(s))
	if not _slot_note.is_empty():
		var note := Label.new()
		note.name = "SlotNote"
		note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = _slot_note
		_slots.add_child(note)
	var focus_target := _first_focusable(list)
	if focus_target != null:
		focus_target.grab_focus.call_deferred()
	_apply_panel_size.call_deferred()
	scroll.set_deferred("scroll_vertical", 0)


func _first_focusable(root: Node) -> Button:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b != null and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			return b
	return null


## Carta di uno slot (revisione grafica 1.0, problema 14): ritratto della classe, livello totale grande, riga di dettagli e le azioni
## SOTTO: «Continua» primaria a tutta larghezza, «Nuova partita» e «Elimina…» (rosso spento) affiancati. Tre carte in colonna.
func _slot_card(slot: int) -> Control:
	var info := SlotSummary.get_info(slot)
	var ok := bool(info.get("ok", false))
	var exists := bool(info.get("exists", false))
	var card := PanelContainer.new()
	card.name = "Slot%d" % slot
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var name_l := Label.new()
	name_l.name = "SlotName"
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.text = Loc.tf("UI_SLOT_N", {"n": slot})
	if ok and slot == best_slot():
		name_l.text += "  ·  " + tr("UI_START_LAST_BADGE")
	elif exists and not ok:
		name_l.text += "  ·  " + tr("UI_M10_SLOT_DAMAGED_BADGE")
	name_l.theme_type_variation = &"SectionLabel"
	v.add_child(name_l)
	if ok:
		var mid := HBoxContainer.new()
		mid.add_theme_constant_override("separation", 12)
		v.add_child(mid)
		var cls_tex: Texture2D = IconLib.portrait("classes", str(info.get("class_id", ""))) if str(info.get("class_id", "")) != "" else null
		if cls_tex != null and cls_tex.get_width() <= 128:
			mid.add_child(VaultKit.pix(cls_tex, 1))                   # ritratto a scala intera (128 px), mai ridimensionato
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 2)
		mid.add_child(col)
		var big := Label.new()
		big.name = "SlotLevel"
		big.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		big.text = NumberFormat.fmt(int(info.get("total_level", 0)))
		big.add_theme_font_size_override("font_size", UiType.NUMBER_BIG + 6)
		big.add_theme_color_override("font_color", FxPalette.GOLD)
		col.add_child(big)
		var cap := Label.new()
		cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cap.theme_type_variation = &"MutedLabel"
		cap.text = tr("UI_TOTAL_LEVEL")
		col.add_child(cap)
		var head := Label.new()
		head.name = "SlotHeadline"
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.text = SlotSummary.headline(info)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(head)
		var det := Label.new()
		det.name = "SlotDetails"
		det.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		det.theme_type_variation = &"MutedLabel"
		det.text = SlotSummary.details(info)
		det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(det)
	else:
		var sp := Control.new()                                          # le carte hanno la stessa altezza: il vuoto spinge le azioni in basso
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(_note_label(describe_slot(info), false))
		v.add_child(sp)
	var recovery := _recovery_text(slot, info)
	if not recovery.is_empty():
		v.add_child(_note_label("⚠ " + recovery, true))
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.size_flags_vertical = Control.SIZE_SHRINK_END
	v.add_child(actions)
	if ok:
		var load_b := Button.new()
		load_b.name = "LoadButton"
		load_b.text = "UI_CONTINUE"
		load_b.theme_type_variation = &"AccentButton"
		load_b.custom_minimum_size = Vector2(0, 44)
		load_b.pressed.connect(func() -> void: _with_loading(load_slot.bind(slot)))
		actions.add_child(load_b)
	for r in _restore_buttons(slot, info):
		(r as Button).custom_minimum_size = Vector2(0, 40)
		actions.add_child(r)
	if exists and not ok:
		var exp_b := Button.new()
		exp_b.name = "SupportExportButton"
		exp_b.text = "UI_M10_SLOT_EXPORT"
		exp_b.tooltip_text = "UI_M10_SLOT_EXPORT_TIP"
		exp_b.custom_minimum_size = Vector2(0, 40)
		exp_b.pressed.connect(_export_for_support.bind(slot))
		actions.add_child(exp_b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	actions.add_child(row)
	var new_b := Button.new()
	new_b.name = "NewButton"
	new_b.text = "UI_NEW_GAME"
	new_b.custom_minimum_size = Vector2(0, 40)
	new_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not exists:
		new_b.theme_type_variation = &"AccentButton"                      # slot libero: l'unica azione è anche quella primaria
	new_b.pressed.connect(_on_new_in_slot.bind(slot, exists))
	row.add_child(new_b)
	if exists:
		var del_b := Button.new()
		del_b.name = "DeleteButton"
		del_b.text = "UI_M10_DELETE_DOTS"
		del_b.custom_minimum_size = Vector2(0, 40)
		del_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		del_b.add_theme_color_override("font_color", UiKit.DANGER.lightened(0.45))      # distruttiva: rosso spento
		del_b.pressed.connect(_ask_delete.bind(slot))
		row.add_child(del_b)
	return card


func _note_label(text: String, warning: bool) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	if warning:
		l.add_theme_color_override("font_color", UiKit.BADGE_AMBER)
	else:
		l.theme_type_variation = &"MutedLabel"
	return l


## Spiega a chi guarda cosa è successo, lo stato dei dati e cosa si può fare (causa + stato + azione).
func _recovery_text(slot: int, info: Dictionary) -> String:
	if bool(info.get("ok", false)):
		if bool(info.get("recovered", false)):
			return Loc.tf("UI_M10_SLOT_RECOVERED", {"date": SlotSummary.format_date(int(info.saved_at_unix)),
				"level": NumberFormat.fmt(int(info.get("total_level", 0)))})
		return ""
	if str(info.get("error", "")) == "newer":
		return ""
	var baks := SlotSummary.backups(slot)
	if baks.is_empty():
		return tr("UI_M10_SLOT_NO_BACKUP")
	return Loc.tf("UI_M10_SLOT_HAS_BACKUP", {"date": SlotSummary.format_date(int(baks[0].saved_at_unix)),
		"level": NumberFormat.fmt(int(baks[0].get("total_level", 0)))})


## «Ripristina la copia»: per uno slot letto da un backup (il principale è danneggiato) o illeggibile ma con backup validi.
func _restore_buttons(slot: int, info: Dictionary) -> Array:
	var out: Array = []
	var n := 0
	if bool(info.get("ok", false)):
		if bool(info.get("recovered", false)):
			n = int(str(info.get("source", "bak0")).substr(3))
	elif str(info.get("error", "")) != "newer":
		var baks := SlotSummary.backups(slot)
		if not baks.is_empty():
			n = int(baks[0].n)
	if n > 0:
		var b := Button.new()
		b.name = "RestoreButton"
		b.text = "UI_M10_SLOT_RESTORE"
		b.theme_type_variation = &"AccentButton"
		b.pressed.connect(_ask_restore.bind(slot, n))
		out.append(b)
	return out


## Testo descrittivo dello slot (già tradotto).
func describe_slot(info: Dictionary) -> String:
	if not info.get("exists", false):
		return tr("UI_SLOT_EMPTY")
	if not info.get("ok", false):
		return tr("UI_SLOT_NEWER") if info.get("error", "") == "newer" else tr("UI_SLOT_CORRUPT")
	return "%s · %s" % [SlotSummary.headline(info), SlotSummary.details(info)]


## Testo della modalità scelta: in che cosa cambia il gioco, più l'avviso (la scelta non si cambia dopo).
func mode_text(p_mode: String) -> String:
	var up := p_mode.to_upper()
	var t := tr("UI_MODES_DESC_" + up)
	if p_mode != ModeRules.NORMAL:
		t += "\n\n" + tr("UI_MODES_WARN_" + up) + "\n" + tr("UI_MODES_PERMANENT")
	return t


func _refresh_mode_desc() -> void:
	if _mode_desc != null:
		_mode_desc.text = mode_text(selected_mode())


func selected_mode() -> String:
	if _mode_option == null:
		return "normal"
	return GameState.MODES[_mode_option.get_selected_id()]


# ------------------------------------------------------------------ slot: azioni

func _on_new_in_slot(slot: int, exists: bool) -> void:
	var m := selected_mode()
	var text := ""
	var ok_key := "UI_CONFIRM"
	var title_key := "UI_START_OVERWRITE_TITLE"
	if exists:
		text = tr("UI_OVERWRITE_CONFIRM") + "\n\n" + describe_slot(SlotSummary.get_info(slot))
		ok_key = "UI_START_OVERWRITE"
	if m != ModeRules.NORMAL:                       # Autarchica/Estrema: conferma esplicita, non si cambia dopo
		text += ("\n\n" if not text.is_empty() else "") + tr("UI_MODES_CONFIRM_" + m.to_upper())
	if text.is_empty():
		_with_loading(start_new.bind(slot))
	else:
		_open_confirm(title_key, ok_key, text, _with_loading.bind(start_new.bind(slot)), exists)


func _ask_delete(slot: int) -> void:
	_open_confirm("UI_START_DELETE_TITLE", "UI_DELETE", Loc.tf("UI_M10_DELETE_BODY", {"n": slot}) + "\n\n" +
		describe_slot(SlotSummary.get_info(slot)), _delete_slot.bind(slot), true)


func _ask_restore(slot: int, n: int) -> void:
	var inf := SlotSummary.get_info(slot)
	if not bool(inf.get("recovered", false)):
		for b in SlotSummary.backups(slot):
			if int(b.n) == n:
				inf = b
	_open_confirm("UI_M10_RESTORE_TITLE", "UI_M10_SLOT_RESTORE", Loc.tf("UI_M10_RESTORE_BODY", {
		"date": SlotSummary.format_date(int(inf.get("saved_at_unix", 0))), "level": NumberFormat.fmt(int(inf.get("total_level", 0)))}),
		_restore_slot.bind(slot, n), false)


## Finestra di conferma: il pulsante che distrugge dati è rosso e il focus parte su «Annulla».
func _open_confirm(title_key: String, ok_key: String, text: String, action: Callable, danger: bool) -> void:
	_pending = action
	_confirm.title = tr(title_key)
	_confirm.get_ok_button().text = tr(ok_key)
	_confirm.get_cancel_button().text = tr("UI_CANCEL")
	_style_ok_button(danger)
	_confirm.dialog_text = text
	_confirm.reset_size()
	_confirm.popup_centered(Vector2i(480, 10))
	_confirm.get_cancel_button().grab_focus.call_deferred()


func _style_ok_button(danger: bool) -> void:
	var ok := _confirm.get_ok_button()
	for s in ["normal", "hover", "pressed", "focus"]:
		ok.remove_theme_stylebox_override(s)
	ok.remove_theme_color_override("font_color")
	ok.remove_theme_color_override("font_hover_color")
	ok.remove_theme_color_override("font_pressed_color")
	ok.remove_theme_color_override("font_focus_color")
	if not danger:
		return
	for pair in [["normal", 0.0], ["hover", 0.12], ["pressed", -0.1], ["focus", 0.0]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiKit.DANGER.lightened(float(pair[1])) if float(pair[1]) >= 0.0 else UiKit.DANGER.darkened(-float(pair[1]))
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
		if pair[0] == "focus":
			sb.bg_color = UiKit.DANGER
			sb.set_border_width_all(2)
			sb.border_color = UiKit.DANGER_TEXT
		ok.add_theme_stylebox_override(pair[0], sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(c, UiKit.DANGER_TEXT)


func start_new(slot: int) -> void:
	if Game.new_game(slot, selected_mode()):
		SlotSummary.invalidate(slot)
		Settings.set_value("last_slot", slot)
		_go(MAIN_SCENE)


func load_slot(slot: int) -> void:
	var res := Game.load_game(slot)
	if res.ok:
		Settings.set_value("last_slot", slot)
		_go(MAIN_SCENE)
	else:
		MenuIntent.screen = ""
		_busy = false
		_hide_loading()
		_say(tr("UI_SLOT_NEWER") if res.error == "newer" else tr("UI_LOAD_FAILED"))
		if _panel.visible:
			_slot_note = _message.text
			show_slots()


func _delete_slot(slot: int) -> void:
	SaveService.delete_slot(slot)
	for p in [SaveService.slot_path(slot) + SlotSummary.CORRUPT_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	SlotSummary.invalidate(slot)
	_slot_note = ""
	_refresh_continue()
	show_slots()


func _restore_slot(slot: int, n: int) -> void:
	var ok := SlotSummary.restore_backup(slot, n)
	_slot_note = tr("UI_M10_RESTORE_DONE") if ok else tr("UI_M10_RESTORE_FAILED")
	_refresh_continue()
	show_slots()


## Copia il file dello slot sul Desktop, per mandarlo all'assistenza (non parte nulla da solo).
func _export_for_support(slot: int) -> void:
	var dest := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dest.is_empty():
		dest = OS.get_user_data_dir()
	var path := SlotSummary.export_for_support(slot, dest)
	_slot_note = Loc.tf("UI_M10_EXPORT_DONE", {"path": path}) if not path.is_empty() else tr("UI_M10_EXPORT_FAILED")
	show_slots()


# ------------------------------------------------------------------ caricamento

## Mostra la schermata di caricamento, lascia due fotogrammi per disegnarla e poi esegue l'azione (che può essere lunga:
## decodifica del salvataggio). Evita doppi clic mentre si lavora.
func _with_loading(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	if get_tree().current_scene == self:
		_show_loading()
		await get_tree().process_frame
		await get_tree().process_frame
	action.call()
	if _loading_path.is_empty():          # l'azione non ha avviato il cambio di scena (errore): si torna al menù
		_busy = false
		_hide_loading()


func _show_loading() -> void:
	if _loading == null:
		_loading = ColorRect.new()
		(_loading as ColorRect).color = Color(0.02, 0.02, 0.05, 0.94)
		_loading.name = "Loading"
		_loading.mouse_filter = Control.MOUSE_FILTER_STOP
		_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_loading.add_child(center)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 14)
		center.add_child(box)
		var logo := TextureRect.new()
		logo.texture = _title.texture
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		logo.custom_minimum_size = LOGO_SIZE * 4.0       # scala intera
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(logo)
		var l := Label.new()
		l.text = "UI_M10_LOADING"
		l.theme_type_variation = &"MutedLabel"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		_loading_bar = ProgressBar.new()
		_loading_bar.min_value = 0.0
		_loading_bar.max_value = 1.0
		_loading_bar.show_percentage = false
		_loading_bar.custom_minimum_size = Vector2(300, 8)
		_loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(_loading_bar)
		add_child(_loading)
	_loading.visible = true
	_loading_bar.value = 0.0
	_confirm.hide()


func _hide_loading() -> void:
	if _loading != null:
		_loading.visible = false
	set_process(false)
	_loading_path = ""


func is_loading() -> bool:
	return _loading != null and _loading.visible


func _go(scene_path: String) -> void:
	if get_tree().current_scene != self:
		navigate.emit(scene_path)
		return
	if _loading == null or not _loading.visible:
		_show_loading()
	_loading_path = scene_path
	_loading_t = 0.0
	if not ResourceLoader.has_cached(scene_path):
		ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	set_process(true)


## Attende il caricamento della scena (thread) e la durata minima, poi cambia scena. Se il thread fallisce, ripiego classico.
func _process(delta: float) -> void:
	if _loading_path.is_empty():
		return
	_loading_t += delta
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
	var min_s := 0.0 if bool(Settings.get_value("reduce_motion")) else LOADING_MIN_S
	var frac := 1.0 if status == ResourceLoader.THREAD_LOAD_LOADED else (float(progress[0]) if not progress.is_empty() else 0.0)
	_loading_bar.value = minf(frac, minf(1.0, _loading_t / maxf(min_s, 0.001)))
	if status == ResourceLoader.THREAD_LOAD_LOADED and _loading_t >= min_s:
		var path := _loading_path
		_loading_path = ""
		set_process(false)
		var packed := ResourceLoader.load_threaded_get(path) as PackedScene
		get_tree().change_scene_to_packed(packed)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var path := _loading_path
		_loading_path = ""
		set_process(false)
		get_tree().change_scene_to_file(path)


# ------------------------------------------------------------------ impostazioni

func show_settings() -> void:
	_close_settings()
	_close_credits()
	for c in _slots.get_children():
		c.free()
	_set_panel(true)
	_settings_view = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	_settings_view.in_menu = true
	_slots.add_child(_settings_view)
	_settings_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_view.open({"in_menu": true})
	_settings_view.closed.connect(func() -> void:
		_close_settings()
		_set_panel(false)
		_continue_or_new_focus())


func _close_settings() -> void:
	if _settings_view != null and is_instance_valid(_settings_view):
		_settings_view.queue_free()
	_settings_view = null


# ------------------------------------------------------------------ crediti

func show_credits() -> void:
	_close_settings()
	_close_credits()
	for c in _slots.get_children():
		c.free()
	_set_panel(true)
	var v := CreditsView.new()
	v.with_back = true
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.closed.connect(func() -> void:
		_close_credits()
		_set_panel(false)
		_continue_or_new_focus())
	_credits_view = v
	_slots.add_child(v)


func _close_credits() -> void:
	if _credits_view != null and is_instance_valid(_credits_view):
		_credits_view.queue_free()
	_credits_view = null


func _back_to_menu() -> void:
	_close_settings()
	_close_credits()
	for c in _slots.get_children():
		c.queue_free()
	_slot_note = ""
	_set_panel(false)
	_refresh_continue()
	_continue_or_new_focus()


## Esc dentro un pannello (slot, Impostazioni, Crediti) torna al menù principale.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel != null and _panel.visible and not is_loading():
		_back_to_menu()
		get_viewport().set_input_as_handled()
