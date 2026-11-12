class_name SidebarMenu
extends RefCounted
## Menù laterale di MainScreen (docs/16 §2; F0 e F4 del progetto di interfaccia, docs/ui_redesign/06 §3.3): voci da
## ScreenRegistry raggruppate in sezioni richiudibili (due livelli: gruppo → voce), segnali a tre tipi (SidebarBadges.signals:
## numero ambra, puntino, rosso), segni dell'attività in corso (MenuActivity, doc ui_redesign/05) e indicatori ai bordi.
## I dizionari `buttons` e `badges` vivono qui e MainScreen ne conserva l'alias (i test li leggono come `main._buttons`):
## non vanno mai riassegnati, solo svuotati con `clear()`.
##
## Stato che sopravvive: gruppi richiusi in Settings.sidebar_groups_closed (preferenza dell'utente); Recenti, voci già aperte,
## «Tutte» aperta e primo uso del coop in GameState.data.ui (campi additivi: se mancano valgono «vuoto», nessuna migrazione).

## Costanti di INTERFACCIA (non di bilanciamento).
const RECENT_MAX := 5                    # mansioni nelle Recenti (comprese quella in corso e le voci di riempimento)
const EXPLICIT := "*"                    # marcatore in sidebar_groups_closed: l'elenco l'ha scelto il giocatore (niente predefinito)
const SHORT_WINDOW_H := 800.0            # sotto questa altezza logica Città, Caveau e Progresso partono chiusi
const DEFAULT_CLOSED: PackedStringArray = ["city", "vault", "progress"]
const HEADER_COLOR := Color("#d2b574")
const HEADER_FONT := 13
const SIGNAL_GAP := 4
## Misure del rapporto grafica 08 (punto 4): TUTTE le voci hanno la stessa altezza e l'icona nello stesso posto; i gruppi
## sono separati da uno spazio e da un filetto; il segnale di stato è UNA sola pillola (stessa forma e misura per numero,
## novità e pericolo); l'attività in corso è un punto a destra, la voce selezionata è il riempimento dorato.
const ROW_H := 36.0
const HEADER_H := 28.0
const GROUP_GAP := 10.0
const PILL := 18.0
const DOT_PX := 9.0                      # novità senza numero: lo stesso cerchio, più piccolo
const SEL_BG := Color("#4a3b1c")
const SEL_BAR := Color("#e0b95a")
const SEL_TEXT := Color("#ffe9b0")
const HOVER_BG := Color(1, 1, 1, 0.08)
const ROW_PAD_L := 7
const ROW_PAD_R := 4

var buttons: Dictionary = {}        # id voce -> Button
var badges: Dictionary = {}         # id voce -> PanelContainer del segnale (numero, puntino o «!»)
var menu_ids: Array = []            # id delle voci disponibili E visibili, nell'ordine del menù (tasti 1-9)

var _ms: Control
var _menu: VBoxContainer
var _sidebar: PanelContainer
var _group := ButtonGroup.new()
var _base_text: Dictionary = {}    # id voce -> testo senza segnale (solo voci con badge: Talenti e mansioni)
var _badge_vals: Dictionary = {}   # id voce -> ultimo numero mostrato
var _badge_kind: Dictionary = {}   # id voce -> ultimo tipo di segnale ("" = nessuno)
var _marks: Dictionary = {}        # id voce -> MenuMark (attività in corso evidenziata nel menù, resoconto UI 05)
var _mark_data: Dictionary = {}    # ultimo MenuActivity.marks()
var _main_mark_id: String = ""     # voce dell'attività principale ("" = nessuna)
var _menu_scroll: ScrollContainer
var _edge_up: MenuEdgeHint
var _edge_down: MenuEdgeHint
# gruppi (F4)
var _group_ids: Dictionary = {}    # id gruppo -> [id voce] (ordine del menù)
var _group_order: Array = []       # id gruppi con intestazione, in ordine
var _entry_group: Dictionary = {}  # id voce -> id gruppo
var _headers: Dictionary = {}      # id gruppo -> {btn, sum: PanelContainer, dot: PanelContainer}
var _header_marks: Dictionary = {} # id gruppo -> MenuMark sull'intestazione chiusa
var _all_row: Button               # «Tutte (N) ▸» delle mansioni
var _skill_ids: Array = []         # id di tutte le voci mansione, nell'ordine del menù
var _avail_ids: Array = []         # id delle voci disponibili (aprirbili) nel menù
var _sig: Dictionary = {}          # ultimo SidebarBadges.signals()
var _selected_gid: String = ""     # gruppo della voce selezionata: si apre da solo
var _suppressed: Dictionary = {}   # gruppi che il giocatore ha richiuso a mano pur contenendo la voce selezionata
var _tut_step: String = ""
var _tut_ids: Array = []           # voci bersaglio del passo di tutorial attivo (D29)
var _tut_groups: Array = []
var _vis_sig: String = ""
var _key_sig: String = ""
var _extra_dots: Dictionary = {}   # id voce -> punti da spendere mostrati come novità (Talenti: la pillola porta il numero)
static var _styles: Dictionary = {}
static var _bold: FontVariation


func _init(ms: Control) -> void:
	_ms = ms
	_menu = ms.get_node("%List")
	_sidebar = ms.get_node("Root/Body/Sidebar")


func sidebar() -> PanelContainer:
	return _sidebar


# ------------------------------------------------------------------ stato della partita (GameState.data.ui)

static func _ui() -> Dictionary:
	if not GameState.active:
		return {}
	var d: Variant = GameState.data.get("ui")
	if not (d is Dictionary):
		d = {}
		GameState.data["ui"] = d
	return d as Dictionary


## Le ultime mansioni avviate o aperte (id voce, la più recente per prima), al massimo RECENT_MAX.
func recent_skills() -> Array:
	var out: Array = []
	for v in _ui().get("recent_skills", []):
		if str(v).begins_with("skill:") and not out.has(str(v)):
			out.append(str(v))
	return out.slice(0, RECENT_MAX)


func _push_recent(id: String) -> void:
	if not id.begins_with("skill:") or not GameState.active:
		return
	var cur := recent_skills()
	if not cur.is_empty() and cur[0] == id:
		return
	cur.erase(id)
	cur.push_front(id)
	_ui()["recent_skills"] = cur.slice(0, RECENT_MAX)


## Mansioni mostrate a gruppo aperto senza «Tutte»: le Recenti disponibili, completate con le prime sbloccate fino a RECENT_MAX
## (a inizio partita le mansioni sbloccate sono poche e si vedono tutte).
func shown_skills() -> Array:
	var out: Array = recent_skills()             # sono voci che il giocatore ha già aperto o avviato: esistono di sicuro
	for id in _skill_ids:
		if out.size() >= RECENT_MAX:
			break
		if _avail_ids.has(id) and not out.has(id):
			out.append(id)
	return out


func all_skills_open() -> bool:
	return bool(_ui().get("all_skills_open", false))


func set_all_skills_open(open: bool) -> void:
	if GameState.active:
		_ui()["all_skills_open"] = open
	_apply_visibility()


func _seen() -> Array:
	return _ui().get("seen_entries", [])


func coop_used() -> bool:
	return bool(_ui().get("coop_used", false))


## Una voce non dei dati compare nel menù? (Impostazioni mai; Lobby e Gilda d'amici solo dopo il primo uso del coop.)
func _in_menu(e: Dictionary) -> bool:
	match str(e.get("menu", "")):
		"hidden":
			return false
		"coop_used":
			return coop_used()
	return true


# ------------------------------------------------------------------ gruppi richiudibili

## Gruppi chiusi in questo momento secondo la preferenza (senza le aperture automatiche).
func closed_groups() -> Array:
	var arr: Array = (Settings.get_value("sidebar_groups_closed") as Array).duplicate()
	if arr.has(EXPLICIT):
		arr.erase(EXPLICIT)
		return arr
	var h := _ms.get_viewport().get_visible_rect().size.y if _ms.is_inside_tree() else 0.0
	return Array(DEFAULT_CLOSED) if h > 0.0 and h < SHORT_WINDOW_H else []


## Il gruppo si vede aperto: scelto aperto dal giocatore, oppure contiene la voce selezionata o il bersaglio del tutorial (D29).
func is_group_open(gid: String) -> bool:
	if _tut_groups.has(gid) or (gid == _selected_gid and not _suppressed.has(gid)):
		return true
	return not closed_groups().has(gid)


## Apre o chiude un gruppo e ricorda la scelta (l'elenco diventa esplicito: niente più predefinito per l'altezza).
func set_group_closed(gid: String, closed: bool) -> void:
	var arr := closed_groups()
	arr.erase(gid)
	if closed:
		arr.append(gid)
		_suppressed[gid] = true
	else:
		_suppressed.erase(gid)
	arr.append(EXPLICIT)
	Settings.set_value("sidebar_groups_closed", arr)
	update_badges()


func toggle_group(gid: String) -> void:
	set_group_closed(gid, is_group_open(gid))


func group_ids() -> Array:
	return _group_order.duplicate()


func header_button(gid: String) -> Button:
	var h: Dictionary = _headers.get(gid, {})
	return h.get("btn") as Button


## Cosa mostra l'intestazione: {open, text, sum (numero ambra o 0), dot, danger} per i test.
func header_state(gid: String) -> Dictionary:
	var h: Dictionary = _headers.get(gid, {})
	if h.is_empty():
		return {}
	var sum := h.sum as PanelContainer
	var dot := h.dot as PanelContainer
	return {"open": is_group_open(gid), "text": (h.btn as Button).text, "sum_visible": sum.visible,
		"sum_text": str((sum.get_node("N") as Label).text), "sum_danger": bool(sum.get_meta("danger", false)), "dot": dot.visible,
		"mark": _header_marks.has(gid)}


func all_row() -> Button:
	return _all_row


func signals_now() -> Dictionary:
	return _sig


# ------------------------------------------------------------------ costruzione

## Ricostruisce il menù laterale da ScreenRegistry (voci bloccate o non ancora realizzate in grigio).
func build_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()
	buttons.clear()
	badges.clear()
	_badge_vals.clear()
	_badge_kind.clear()
	_base_text.clear()
	_marks.clear()          # i segni erano figli dei vecchi pulsanti: vanno ricreati
	_header_marks.clear()
	_headers.clear()
	_group_ids.clear()
	_group_order.clear()
	_entry_group.clear()
	_skill_ids = []
	_avail_ids = []
	_all_row = null
	_sig = {}
	_mark_data = {}
	_main_mark_id = ""
	_vis_sig = ""
	_key_sig = ""
	var unlocks: Array = GameState.data.get("unlocks", [])
	var last_section := ""
	var entries := ScreenRegistry.entries()
	var shown: Array[Dictionary] = []
	for e in entries:
		if _in_menu(e):
			shown.append(e)
			if ScreenRegistry.is_available(e, unlocks):
				_avail_ids.append(str(e.id))
	_seed_seen()
	for e in shown:
		var gid := str(e.section)
		if gid != last_section:
			last_section = gid
			var title := _section_title(gid)
			if not title.is_empty():
				_add_header(gid, title)
		_entry_group[str(e.id)] = gid
		if not _group_ids.has(gid):
			_group_ids[gid] = []
		(_group_ids[gid] as Array).append(str(e.id))
		if gid == "skills":
			_skill_ids.append(str(e.id))
		var b := Button.new()
		b.theme_type_variation = &"SidebarButton"
		b.toggle_mode = true
		b.button_group = _group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_ALL
		if e.has("title_data"):
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = Loc.t(e.title_data)
		else:
			b.text = e.title
		if e.id == "talents":
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # il testo cambia col badge dei punti non spesi
			b.text = _ms.tr(e.title)
		if e.id == "talents" or str(e.id).begins_with("skill:"):
			_base_text[e.id] = b.text
		var icon: Texture2D = MenuIcons.texture(str(e.id), str(e.get("icon", "")))
		b.icon = icon if icon != null else MenuIcons.blank()      # tutte le righe hanno lo spazio dell'icona: testi allineati
		b.expand_icon = false
		_style_row(b)
		var available := ScreenRegistry.is_available(e, unlocks)
		b.disabled = not available
		var locked_target := {}
		var core := ""
		if not ScreenRegistry.is_unlocked(e, unlocks):
			var token := str(e.get("hint_unlock", e.get("unlock", "")))
			var hint := UnlockSystem.hint_for(token, DataRegistry)     # "Si sblocca con: missione X"
			# nessuna missione dei dati lo concede ancora (sistemi in arrivo): si dice comunque come/quando
			core = _ms.tr(hint if not hint.is_empty() else "UI_INTEG_LOCKED_LATER")
			if not str(e.get("scene", "")).is_empty():
				locked_target = ReqLink.target_for_token(token)      # «nessun vicolo cieco»: il clic apre la missione che la sblocca
		elif str(e.get("scene", "")).is_empty():
			core = _ms.tr("UI_COMING_SOON")
		if not locked_target.is_empty():
			b.disabled = false
			b.toggle_mode = false
			b.button_group = null
			b.modulate = Color(1, 1, 1, 0.62)
			b.set_meta("req_target", locked_target)
			core += "\n" + _ms.tr("UI_UIB_LOCKED_CLICK")
			b.pressed.connect(ReqLink.go.bind(locked_target))
		else:
			b.pressed.connect(_ms.show_screen.bind(e.id, e.get("params", {})))
		b.set_meta("tip_core", core)
		b.set_meta("available", available)
		_add_section_bar(b, str(e.id), available)
		_add_badge(b, str(e.id))
		_menu.add_child(b)
		buttons[e.id] = b
		TutorialTargets.mark(b, "menu:" + str(e.id))
	_add_all_row()
	_selected_gid = str(_entry_group.get(_ms.current_id, ""))
	if buttons.has(_ms.current_id):
		buttons[_ms.current_id].button_pressed = true
	refresh_activity_marks()
	update_badges()


## Stili condivisi delle righe (una sola istanza per tipo): normale trasparente, passaggio del mouse tenue, selezione =
## riempimento dorato scuro con barra piena a sinistra. Nessun PNG: sono StyleBoxFlat (la selezione non dipende dal tema).
static func _style(kind: String) -> StyleBoxFlat:
	if _styles.has(kind):
		return _styles[kind]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = ROW_PAD_L
	sb.content_margin_right = ROW_PAD_R
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	match kind:
		"hover":
			sb.bg_color = HOVER_BG
		"selected":
			sb.bg_color = SEL_BG
			sb.border_width_left = 4
			sb.border_color = SEL_BAR
			sb.content_margin_left = ROW_PAD_L - 2
		"header":
			sb.border_width_top = 1
			sb.border_color = Color(HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, 0.35)
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
		"header_hover":
			sb.border_width_top = 1
			sb.border_color = Color(HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, 0.35)
			sb.bg_color = HOVER_BG
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
	_styles[kind] = sb
	return sb


static func _bold_font(base: Font) -> Font:
	if _bold == null or _bold.base_font != base:
		_bold = FontVariation.new()
		_bold.base_font = base
		_bold.variation_embolden = 0.45
	return _bold


## Aspetto di una voce: altezza uniforme, stili propri, testo semigrassetto e senza barretta di sezione quando è selezionata.
func _style_row(b: Button) -> void:
	b.custom_minimum_size.y = ROW_H
	b.add_theme_stylebox_override("normal", _style("normal"))
	b.add_theme_stylebox_override("disabled", _style("normal"))
	b.add_theme_stylebox_override("hover", _style("hover"))
	b.add_theme_stylebox_override("pressed", _style("selected"))
	b.add_theme_stylebox_override("hover_pressed", _style("selected"))
	b.add_theme_color_override("font_pressed_color", SEL_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", SEL_TEXT)
	b.add_theme_constant_override("h_separation", 4)
	b.toggled.connect(_on_row_toggled.bind(b))


func _on_row_toggled(on: bool, b: Button) -> void:
	if on:
		b.add_theme_font_override("font", _bold_font(b.get_theme_font("font")))
	else:
		b.remove_theme_font_override("font")
	var bar := b.get_node_or_null("SectionBar") as CanvasItem
	if bar != null:
		bar.visible = not on                  # la barra piena della selezione prende il posto di quella di sezione
	var m := _marks.get(str(_id_of(b))) as MenuMark
	if m != null and is_instance_valid(m):
		m.queue_redraw()
		m.pulse_layer().queue_redraw()


func _id_of(b: Button) -> String:
	for id in buttons:
		if buttons[id] == b:
			return str(id)
	return ""


func _add_header(gid: String, title_key: String) -> void:
	var gap := Control.new()                                  # respiro fra i gruppi
	gap.name = "Gap_" + gid
	gap.set_meta("gap_of", gid)                               # il nome può cambiare se il vecchio menù non è ancora stato liberato
	gap.custom_minimum_size.y = GROUP_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(gap)
	var b := Button.new()
	b.name = "Header_" + gid
	b.theme_type_variation = &"SidebarButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size.y = HEADER_H
	for st in ["normal", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, _style("header"))
	b.add_theme_stylebox_override("hover", _style("header_hover"))
	b.add_theme_font_size_override("font_size", HEADER_FONT)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, HEADER_COLOR)
	b.set_meta("title_key", title_key)
	b.set_meta("tip_core", _ms.tr("UI_SIDE_HEADER_TIP"))
	b.pressed.connect(toggle_group.bind(gid))
	var row := HBoxContainer.new()
	row.name = "Signals"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", SIGNAL_GAP)
	row.alignment = BoxContainer.ALIGNMENT_END
	b.add_child(row)
	_anchor_right_centered(row, 8.0 + MenuMark.ICON_W)
	var dot := _new_pill()
	dot.name = "Dot"
	_style_pill(dot, SidebarBadges.KIND_DOT, "")
	row.add_child(dot)
	var sum := _new_pill()
	sum.name = "Sum"
	row.add_child(sum)
	_menu.add_child(b)
	_headers[gid] = {"btn": b, "sum": sum, "dot": dot}
	_group_order.append(gid)
	_refresh_header_text(gid)


func _add_all_row() -> void:
	if _skill_ids.is_empty():
		return
	var last: Button = buttons.get(_skill_ids[_skill_ids.size() - 1])
	_all_row = Button.new()
	_all_row.name = "AllSkills"
	_all_row.theme_type_variation = &"SidebarButton"
	_all_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_all_row.focus_mode = Control.FOCUS_ALL
	_all_row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_all_row.add_theme_font_size_override("font_size", HEADER_FONT)
	_all_row.add_theme_color_override("font_color", HEADER_COLOR)
	_all_row.custom_minimum_size.y = HEADER_H
	for st in ["normal", "pressed", "disabled", "hover_pressed"]:
		_all_row.add_theme_stylebox_override(st, _style("normal"))
	_all_row.add_theme_stylebox_override("hover", _style("hover"))
	_all_row.tooltip_text = _ms.tr("UI_SIDE_ALL_TIP")
	_all_row.pressed.connect(func() -> void: set_all_skills_open(not all_skills_open()))
	_menu.add_child(_all_row)
	_menu.move_child(_all_row, last.get_index() + 1)


## Barretta colorata sul bordo sinistro della voce: il colore della sezione, lo stesso delle righe del Registro.
func _add_section_bar(b: Button, id: String, available: bool) -> void:
	var sec := LogCategory.of_screen(id)
	if sec.is_empty():
		return
	var bar := ColorRect.new()
	bar.name = "SectionBar"
	bar.color = LogCategory.color(sec)
	bar.modulate.a = 1.0 if available else 0.4
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar.offset_left = 1.0
	bar.offset_right = 4.0
	bar.offset_top = 5.0
	bar.offset_bottom = -5.0
	b.set_meta("log_section", sec)


func _section_title(section_id: String) -> String:
	for s in ScreenRegistry.SECTIONS:
		if s.id == section_id:
			return s.title
	return ""


func _refresh_header_text(gid: String) -> void:
	var h: Dictionary = _headers.get(gid, {})
	if h.is_empty():
		return
	var b := h.btn as Button
	b.text = ("▾ " if is_group_open(gid) else "▸ ") + _ms.tr(str(b.get_meta("title_key"))).to_upper()


# ------------------------------------------------------------------ voce selezionata, recenti, voci già aperte

## Evidenzia la voce della schermata aperta (aggiorna anche il ButtonGroup: `button_pressed` emette solo toggled).
func select(id: String) -> void:
	if buttons.has(id):
		buttons[id].button_pressed = true
	else:
		var pressed := _group.get_pressed_button()
		if pressed != null:
			pressed.button_pressed = false          # schermata fuori dal menù (Impostazioni): nessuna voce evidenziata
	_selected_gid = str(_entry_group.get(id, ""))
	_suppressed.clear()
	_push_recent(id)
	if GameState.active:
		var seen := _seen().duplicate()
		if not seen.has(id):
			seen.append(id)
			_ui()["seen_entries"] = seen
		if (id == "coop" or id == "coop_lobby" or id == "coop_guild") and not coop_used():
			_ui()["coop_used"] = true
			build_menu.call_deferred()              # Lobby e Gilda d'amici compaiono dopo il primo uso
	if not buttons.is_empty():
		update_badges()


## Prima costruzione di una partita (anche caricata): le voci già disponibili contano come viste, i puntini «nuova voce»
## arrivano solo con gli sblocchi successivi.
func _seed_seen() -> void:
	if not GameState.active or _ui().has("seen_entries"):
		return
	var seen: Array = _avail_ids.duplicate()
	if _ms.current_id != "" and not seen.has(_ms.current_id):
		seen.append(_ms.current_id)
	_ui()["seen_entries"] = seen


func _new_ids() -> Array:
	var out: Array = []
	if not GameState.active:
		return out
	var seen := _seen()
	var shown := shown_skills()
	for id in _avail_ids:
		if seen.has(id) or id == _ms.current_id:
			continue
		if str(id).begins_with("skill:") and not shown.has(id):
			continue
		out.append(id)
	return out


## Voce del menù da tastiera: se è bloccata ma cliccabile porta alla missione, se non esiste (ancora) non fa nulla.
func open_entry(id: String) -> bool:
	if not buttons.has(id):
		return false
	var b: Button = buttons[id]
	if b.has_meta("req_target"):
		return ReqLink.go(b.get_meta("req_target"))
	return _ms.show_screen(id, ScreenRegistry.get_entry(id).get("params", {}))


# ------------------------------------------------------------------ segnali del menù (G22, D14)

func _new_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(PILL, PILL)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER           # il cerchio piccolo non si allunga alla pillola vicina
	var l := Label.new()
	l.name = "N"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	p.add_child(l)
	return p


## UN solo stile di segnale (rapporto 08 punto 4): pillola tonda alta PILL px, stessa forma per tutti. Il colore dice il
## significato: ambra con numero = azione possibile adesso; contorno chiaro («•» o il numero) = novità non urgente; rosso con «!» =
## pericolo in corso. Mai testo sotto i 4,5:1 (le tinte e i testi sono in UiKit).
func _style_pill(p: PanelContainer, kind: String, text: String) -> void:
	var sb := StyleBoxFlat.new()
	var l := p.get_node("N") as Label
	p.custom_minimum_size = Vector2(PILL, PILL)
	sb.set_corner_radius_all(int(PILL * 0.5))
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	l.visible = true
	match kind:
		SidebarBadges.KIND_DOT:
			sb.bg_color = UiKit.DOT                      # novità: cerchio pieno oro chiaro; piccolo senza numero, pillola con il numero
			l.add_theme_color_override("font_color", UiKit.BADGE_AMBER_TEXT)
			if text.is_empty():
				l.visible = false
				p.custom_minimum_size = Vector2(DOT_PX, DOT_PX)
				sb.set_corner_radius_all(int(DOT_PX * 0.5))
				sb.content_margin_left = 0
				sb.content_margin_right = 0
				p.add_theme_stylebox_override("panel", sb)
				p.set_meta("danger", false)
				l.text = ""
				return
		SidebarBadges.KIND_DANGER:
			sb.bg_color = UiKit.DANGER
			l.add_theme_color_override("font_color", UiKit.DANGER_TEXT)
		_:
			sb.bg_color = UiKit.BADGE_AMBER
			l.add_theme_color_override("font_color", UiKit.BADGE_AMBER_TEXT)
	p.add_theme_stylebox_override("panel", sb)
	p.set_meta("danger", kind == SidebarBadges.KIND_DANGER)
	l.text = text


## Ancora un controllo al bordo destro, centrato in verticale: ha la sua dimensione minima e cresce verso sinistra.
func _anchor_right_centered(c: Control, margin: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_right = -margin
	c.offset_left = -margin
	c.offset_top = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


func _add_badge(b: Button, id: String) -> void:
	var badge := _new_pill()
	badge.name = "Badge"
	_style_pill(badge, SidebarBadges.KIND_COUNT, "")
	b.add_child(badge)
	_anchor_right_centered(badge, 8.0)
	badges[id] = badge


## Segnale su ogni voce (numero ambra, puntino o «!» rosso; niente = nascosto), riga per causa nel tooltip, intestazioni dei
## gruppi e visibilità delle voci. Un segnale che cresce fa un piccolo «pop». Gira a 2 Hz.
func update_badges() -> void:
	if buttons.is_empty():
		return
	_sig = SidebarBadges.signals(_signal_opts())
	for id in badges:
		var badge: PanelContainer = badges[id]
		var s: Dictionary = _sig.get(id, {})
		var kind := str(s.get("kind", ""))
		var n := int(s.get("n", 0))
		var extra := 0
		if s.is_empty() and int(_extra_dots.get(id, 0)) > 0:        # Talenti: punti da spendere = novità con il numero dentro
			kind = SidebarBadges.KIND_DOT
			extra = int(_extra_dots[id])
			n = extra
		var b: Button = buttons[id]
		var was := int(_badge_vals.get(id, 0))
		var changed := kind != str(_badge_kind.get(id, "")) or n != was
		if changed:
			_badge_vals[id] = n
			_badge_kind[id] = kind
			badge.visible = not kind.is_empty()
			if not kind.is_empty():
				var txt := ""
				match kind:
					SidebarBadges.KIND_COUNT:
						txt = SidebarBadges.label(n)
					SidebarBadges.KIND_DANGER:
						txt = "!"
					_:
						txt = SidebarBadges.label(extra) if extra > 0 else ""
				_style_pill(badge, kind, txt)
			if n > was and n > 0:
				Fx.pop(badge)
		var tip := _cause_lines(s.get("causes", []))
		if str(b.get_meta("cause_tip", "")) != tip:
			b.set_meta("cause_tip", tip)
			_apply_tip(b)
	_update_headers()
	_update_header_marks()
	_apply_visibility()


## Parametri di SidebarBadges.signals(): Recenti mostrate e voci sbloccate mai aperte.
func _signal_opts() -> Dictionary:
	return {"recent": shown_skills(), "new_ids": _new_ids()}


func _cause_lines(causes: Array) -> String:
	var lines := PackedStringArray()
	for c in causes:
		lines.append(Loc.tf(str(c[0]), {"n": int(c[1])}))
	return "\n".join(lines)


func badge_count(id: String) -> int:
	return int(_badge_vals.get(id, 0))


## Tipo di segnale mostrato su una voce: "count" · "dot" · "danger" · "" (per i test).
func badge_kind(id: String) -> String:
	return str(_badge_kind.get(id, ""))


## Intestazioni: a gruppo chiuso la somma dei numeri, un puntino se ce n'è, il rosso se c'è un pericolo.
func _update_headers() -> void:
	for gid in _group_order:
		var h: Dictionary = _headers[gid]
		var closed := not is_group_open(gid)
		var sum_n := 0
		var any_dot := false
		var any_danger := false
		var lines := PackedStringArray()
		for id in _group_ids.get(gid, []):
			var s: Dictionary = _sig.get(id, {})
			match str(s.get("kind", "")):
				SidebarBadges.KIND_COUNT:
					sum_n += int(s.n)
				SidebarBadges.KIND_DOT:
					any_dot = true
				SidebarBadges.KIND_DANGER:
					any_danger = true
			if closed and not s.is_empty():
				lines.append("%s: %s" % [_ms.tr((buttons[id] as Button).text.strip_edges()), _cause_lines(s.causes).replace("\n", " · ")])
		var sum := h.sum as PanelContainer
		var dot := h.dot as PanelContainer
		sum.visible = closed and (any_danger or sum_n > 0)
		if sum.visible:
			_style_pill(sum, SidebarBadges.KIND_DANGER if any_danger else SidebarBadges.KIND_COUNT,
				"!" if any_danger else SidebarBadges.label(sum_n))
		dot.visible = closed and any_dot
		var btn := h.btn as Button
		var tip := str(btn.get_meta("tip_core", ""))
		if not lines.is_empty():
			tip += "\n" + "\n".join(lines)
		if btn.tooltip_text != tip:
			btn.tooltip_text = tip
		_refresh_header_text(gid)


## Visibilità delle voci: gruppo chiuso = nascoste, salvo l'attività principale (riga fissa); nelle Mansioni a «Tutte» chiusa
## solo le Recenti, più le voci con un numero o un pericolo, la voce selezionata e i bersagli del tutorial.
func _apply_visibility() -> void:
	if buttons.is_empty():
		return
	var shown := shown_skills()
	var all_open := all_skills_open()
	var sel_id := str(_ms.current_id)
	for gid in _group_ids:
		var open := is_group_open(str(gid)) if _headers.has(gid) else true     # Riepilogo e Missioni: in cima, senza titolo
		for id in _group_ids[gid]:
			var b: Button = buttons[id]
			var vis := open
			if open and gid == "skills":
				vis = all_open or shown.has(id) or _tut_ids.has(id) or id == sel_id
				var kind := str((_sig.get(id, {}) as Dictionary).get("kind", ""))
				if kind == SidebarBadges.KIND_COUNT or kind == SidebarBadges.KIND_DANGER:
					vis = true
			if id == _main_mark_id:
				vis = true
			b.visible = vis
	if _all_row != null:
		var hidden := _skill_ids.size() > shown.size()
		_all_row.visible = is_group_open("skills") and hidden
		_all_row.text = Loc.tf("UI_SIDE_ALL_SKILLS", {"n": _skill_ids.size()}) + (" ▾" if all_open else " ▸")
	var ids: Array = []
	for e in ScreenRegistry.entries():
		var id := str(e.id)
		if buttons.has(id) and _avail_ids.has(id) and (buttons[id] as Button).visible:
			ids.append(id)
	menu_ids = ids
	var new_sig := ",".join(PackedStringArray(ids))
	if new_sig != _vis_sig:
		_vis_sig = new_sig
		_update_edge_hints.call_deferred()
	var keys_sig := ",".join(PackedStringArray(ids.slice(0, ShortcutMap.MENU_KEYS)))
	if keys_sig != _key_sig:
		_key_sig = keys_sig
		for id in buttons:
			var b: Button = buttons[id]
			var key := ShortcutMap.key_label_for(str(id), menu_ids) if _avail_ids.has(id) else ""
			b.set_meta("key_line", Loc.tf("UI_UIB_KEY_HINT", {"key": key}) if not key.is_empty() else "")
			_apply_tip(b)


## Il bersaglio del passo di tutorial attivo (D29): il suo gruppo si apre da solo, altrimenti TutorialTargets non lo trova.
func _sync_tutorial() -> void:
	var d: Variant = _ms.tutorial()
	var sid := str(d.current_step_id()) if d != null else ""
	if sid == _tut_step:
		return
	_tut_step = sid
	_tut_ids = []
	_tut_groups = []
	if not sid.is_empty():
		var step := TutorialCatalog.get_step(sid)
		var keys: Array = TutorialCatalog.targets_of(step).duplicate()
		if not str(step.get("screen", "")).is_empty():
			keys.append("menu:" + str(step.screen))
		for k in keys:
			var ks := str(k)
			if ks.begins_with("menu:") and _entry_group.has(ks.substr(5)):
				var id := ks.substr(5)
				_tut_ids.append(id)
				var g := str(_entry_group[id])
				if not _tut_groups.has(g):
					_tut_groups.append(g)
	update_badges()


## Numero ambra/puntino/rosso della voce e riga del tooltip: stato visibile per i test.
func signal_of(id: String) -> Dictionary:
	return _sig.get(id, {})


## Punti talento non spesi: pillola di novità con il numero dentro (stesso stile degli altri segnali), non più testo accanto al nome.
func refresh_talent_badge() -> void:
	var combat := Game.system("combat") as CombatSystem
	var free := 0
	if combat != null and combat.build != null:
		free = combat.build.points_free()
	_set_badge("talents", free, "UI_BADGE_TALENTS")


func _set_badge(id: String, n: int, tip_key: String) -> void:
	var b: Button = buttons.get(id)
	if b == null or not _base_text.has(id):
		return
	if int(_extra_dots.get(id, 0)) != maxi(n, 0):
		if n > 0:
			_extra_dots[id] = n
		else:
			_extra_dots.erase(id)
		update_badges()                              # la pillola (stesso stile degli altri segnali) porta il numero: niente testo in più
	var tip: String = "" if n <= 0 else _ms.tr(tip_key)    # il pulsante non si traduce da solo (testo variabile): il tooltip sì, a mano
	if str(b.get_meta("tip_core", "")) != tip:
		b.set_meta("tip_core", tip)
		_apply_tip(b)


# ------------------------------------------------------------------ attività in corso nel menù (resoconto UI 05)

## Evidenzia le voci del menù che corrispondono a un'attività in corso (MenuActivity): principale e parallele. Gira a 2 Hz,
## a ogni cambio di pausa e a ogni ricostruzione del menù; l'avanzamento del ciclo si aggiorna a 10 Hz in `tick_marks`.
## Un gruppo chiuso mostra il segno sulla propria intestazione; l'attività principale resta anche visibile come riga fissa.
func refresh_activity_marks() -> void:
	var data := MenuActivity.marks() if GameState.active else {}
	_mark_data = data
	_main_mark_id = ""
	for id in _marks.keys():
		if not data.has(id) or not buttons.has(id):
			_remove_mark(str(id))
	for id in data:
		if not buttons.has(id):
			continue
		_set_mark(str(id), data[id])
		if str(data[id].role) == MenuActivity.ROLE_MAIN:
			_main_mark_id = str(id)
	if _main_mark_id.begins_with("skill:"):
		_push_recent(_main_mark_id)                 # la mansione in corso è sempre fra le Recenti
	_update_header_marks()
	_apply_visibility()
	_update_edge_hints()


func _update_header_marks() -> void:
	for gid in _group_order:
		var role := ""
		var d: Dictionary = {}
		var mark_id := ""
		for id in _group_ids.get(gid, []):
			if _mark_data.has(id) and (role.is_empty() or str(_mark_data[id].role) == MenuActivity.ROLE_MAIN):
				role = str(_mark_data[id].role)
				d = _mark_data[id]
				mark_id = str(id)
		var btn: Button = (_headers[gid] as Dictionary).btn
		var m: MenuMark = _header_marks.get(gid)
		if role.is_empty() or is_group_open(gid):
			if m != null and is_instance_valid(m):
				m.queue_free()
			_header_marks.erase(gid)
			continue
		if m == null or not is_instance_valid(m):
			m = MenuMark.new()
			btn.add_child(m)
			btn.move_child(m, 0)
			_header_marks[gid] = m
		m.set_state(role, str(d.state), -1.0, LogCategory.color(LogCategory.of_screen(mark_id)))


func _set_mark(id: String, d: Dictionary) -> void:
	var b: Button = buttons[id]
	var m: MenuMark = _marks.get(id)
	if m == null or not is_instance_valid(m):
		m = MenuMark.new()
		b.add_child(m)
		b.move_child(m, 0)                            # sotto barretta di sezione e pallino
		_marks[id] = m
		_shift_badge(id, -MenuMark.ICON_W)            # il pallino numerico lascia il posto all'icona di stato
	m.set_state(str(d.role), str(d.state), float(d.frac), LogCategory.color(LogCategory.of_screen(id)))
	var tip := str(d.tip)
	if str(b.get_meta("mark_tip", "")) != tip:
		b.set_meta("mark_tip", tip)
		_apply_tip(b)


func _remove_mark(id: String) -> void:
	var m: MenuMark = _marks.get(id)
	_marks.erase(id)
	if m != null and is_instance_valid(m):
		m.queue_free()
		_shift_badge(id, MenuMark.ICON_W)
	var b: Button = buttons.get(id)
	if b != null:
		b.set_meta("mark_tip", "")
		_apply_tip(b)


func _shift_badge(id: String, dx: float) -> void:
	var badge: PanelContainer = badges.get(id)
	if badge != null:
		badge.offset_left += dx
		badge.offset_right += dx


## Tooltip della voce = testo base + tasto + una riga per causa del segnale + riga «In corso: …».
func _apply_tip(b: Button) -> void:
	var parts := PackedStringArray()
	for k in ["tip_core", "key_line", "cause_tip", "mark_tip"]:
		var s := str(b.get_meta(k, ""))
		if not s.is_empty():
			parts.append(s)
	b.tooltip_text = "\n".join(parts)


func tick_marks() -> void:
	_sync_tutorial()
	var m: MenuMark = _marks.get(_main_mark_id)
	if m != null and is_instance_valid(m):
		m.set_frac(MenuActivity.main_frac())


## Dati di un segno per i test: {role, state, frac, tip, breathing} oppure {} se la voce non è evidenziata.
func activity_mark(id: String) -> Dictionary:
	var m: MenuMark = _marks.get(id)
	if m == null or not is_instance_valid(m):
		return {}
	return {"role": m.role, "state": m.state, "frac": m.frac, "tip": str((buttons[id] as Button).get_meta("mark_tip", "")),
		"breathing": m.is_breathing()}


func main_mark_id() -> String:
	return _main_mark_id


## Indicatori ai bordi del menù (visibili solo se la voce principale è fuori vista): per i test.
func edge_hints() -> Dictionary:
	return {"up": _edge_up.visible, "down": _edge_down.visible}


func build_edge_hints() -> void:
	_menu_scroll = _sidebar.get_node("Scroll") as ScrollContainer
	var layer := Control.new()
	layer.name = "EdgeLayer"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.add_child(layer)
	_edge_up = MenuEdgeHint.new(true)
	_edge_down = MenuEdgeHint.new(false)
	for h in [_edge_up, _edge_down]:
		layer.add_child(h)
		(h as Button).anchor_left = 0.0
		(h as Button).anchor_right = 1.0
		(h as Button).pressed.connect(_scroll_to_main)
	_edge_up.anchor_top = 0.0
	_edge_up.anchor_bottom = 0.0
	_edge_up.offset_top = 0.0
	_edge_up.offset_bottom = MenuEdgeHint.H
	_edge_down.anchor_top = 1.0
	_edge_down.anchor_bottom = 1.0
	_edge_down.offset_top = -MenuEdgeHint.H
	_edge_down.offset_bottom = 0.0
	_menu_scroll.get_v_scroll_bar().value_changed.connect(_on_menu_scrolled)
	_menu_scroll.resized.connect(_update_edge_hints)


func _on_menu_scrolled(_v: float) -> void:
	_update_edge_hints()


## Se la voce dell'attività principale è fuori dalla parte visibile del menù compare l'indicatore in alto o in basso.
func _update_edge_hints() -> void:
	if _edge_up == null:
		return
	var b: Button = buttons.get(_main_mark_id)
	if b == null or not is_instance_valid(b) or _menu_scroll == null or not b.is_inside_tree() or not b.visible:
		_edge_up.visible = false
		_edge_down.visible = false
		return
	var top := b.global_position.y - _menu_scroll.global_position.y
	var above := top < 0.0
	var below := top + b.size.y > _menu_scroll.size.y
	var text := Loc.tf("UI_MENUACT_EDGE", {"name": _ms.tr(b.text)})     # il testo di alcune voci è ancora una chiave del CSV
	for h in [_edge_up, _edge_down]:
		(h as Button).text = text
		(h as Button).tooltip_text = _ms.tr("UI_MENUACT_EDGE_TIP")
	_edge_up.visible = above
	_edge_down.visible = below and not above


func _scroll_to_main() -> void:
	var b: Button = buttons.get(_main_mark_id)
	if b != null and _menu_scroll != null:
		_menu_scroll.ensure_control_visible(b)
		_update_edge_hints.call_deferred()
