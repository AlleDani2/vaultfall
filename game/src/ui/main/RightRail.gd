class_name RightRail
extends RefCounted
## Lato destro di MainScreen (F3 del progetto di interfaccia, docs/ui_redesign/06 §3.4, D9–D13, D25):
##   - BINARIO «RightRail» (52 px, sempre presente a destra del contenuto): Registro (con puntino se è arrivato un evento raro
##     non letto), Amici (solo con il coop sbloccato E una lobby aperta almeno una volta) e, in basso, «PushSlot» (il
##     pulsante della Sabbia del Custode, PushButton, F14; con la colonna fissata va in fondo ad essa);
##   - CASSETTO: la vecchia colonna destra («RightColumn»), chiusa di default; si apre sopra il contenuto da destra con un
##     velo al 30%, si chiude con un clic fuori, Esc, L. Contiene il Registro (con i filtri NoticeFilter) e gli Amici
##     (%AmiciSlot). In banda larga (UiBands.band == "wide") il 📌 lo FISSA: diventa colonna (right_col_visible = true);
##   - striscia Obiettivo («GoalStrip» con il «GoalPanel» dentro): una riga da 28 px sopra lo ScreenScroll, nascosta in Riepilogo
##     e Missioni; il pannello Paralleli non è più nel layout (ParallelsPanel.rows()/side_rows() restano come sorgente dati);
##   - maniglia di ridimensionamento (ColumnGrip) della colonna fissata, striscia Città e posizione dei toast.
##
## Percorsi stabili: Root/Body/RightColumn/RightScroll/VBox/{DrawerHead, AmiciSlot, Log}. Con il cassetto chiuso o la colonna
## fissata RightColumn sta in Root/Body; con il cassetto aperto è spostata sotto «Drawer».

const RAIL_W := 52.0
const BTN := 40.0
const CAPTION_PX := 11
const DRAWER_MAX_FRAC := 0.7
const VEIL := Color(0, 0, 0, 0.3)
const SECTION_LOG := "log"
const SECTION_FRIENDS := "friends"
const LAYOUT_REV := 2                              # revisione del layout: la 2 è «colonna destra → cassetto»
const NO_STRIP_SCREENS: PackedStringArray = ["summary", "quests"]
const ACCENT := Color("#e0b95a")
const ICON := Color("#d8d2c0")
const ICON_OFF := Color("#6b6e76")

var goal: GoalPanel                 # striscia «Obiettivo attuale» (QuestGuide)
var grip: ColumnGrip
var city_strip: CityStrip
var narrow: bool = false            # banda stretta (< UiBands.NARROW_W): menù ridotto, cassetto limitato in larghezza
var band: String = UiBands.BAND_NORMAL

var _ms: Control
var _right: PanelContainer          # «RightColumn»: contenuto del cassetto / colonna fissata
var _right_vbox: VBoxContainer
var _body: HBoxContainer
var _toasts: VBoxContainer
var _rail: PanelContainer
var _btn_log: RailButton
var _btn_friends: RailButton
var _push_slot: VBoxContainer
var _push: PushButton
var _head_title: Label
var _filter_btn: MenuButton
var _pin_btn: RailButton
var _close_btn: RailButton
var _log: LogView
var _slot: VBoxContainer
var _drawer: Control                # strato sopra il contenuto che ospita la colonna in modalità cassetto
var _drawer_catcher: Control        # velo al 30%: un clic fuori dal cassetto lo chiude
var _goal_holder: GoalStrip
var _top_h: float = 0.0
var _drawer_open: bool = false
var _dot: bool = false
var _built: bool = false


## Pulsante quadrato del binario / dell'intestazione: l'icona è disegnata in codice (nessun glifo di font, nessun PNG).
class RailButton extends Button:
	var kind: String = ""
	var dot: bool = false:
		set(v):
			dot = v
			queue_redraw()
	var active: bool = false:
		set(v):
			active = v
			queue_redraw()

	func _init(k: String, side: float) -> void:
		kind = k
		name = "Btn_" + k
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(side, side)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		clip_text = true

	func _draw() -> void:
		var col := RightRail.ACCENT if active else (RightRail.ICON_OFF if disabled else RightRail.ICON)
		var c := size * 0.5
		var s := minf(size.x, size.y) / 40.0
		match kind:
			"log":
				for dy in [-7.0, 0.0, 7.0]:
					draw_line(c + Vector2(-9, dy) * s, c + Vector2(9, dy) * s, col, 2.5 * s)
			"friends":
				draw_circle(c + Vector2(0, -6) * s, 4.5 * s, col)
				draw_arc(c + Vector2(0, 11) * s, 9.0 * s, PI * 1.08, PI * 1.92, 14, col, 3.0 * s)
			"pin":
				draw_circle(c + Vector2(0, -5) * s, 5.0 * s, col)
				draw_line(c + Vector2(-6, 1) * s, c + Vector2(6, 1) * s, col, 2.5 * s)
				draw_line(c + Vector2(0, 1) * s, c + Vector2(0, 10) * s, col, 2.0 * s)
			"close":
				draw_line(c + Vector2(-6, -6) * s, c + Vector2(6, 6) * s, col, 2.5 * s)
				draw_line(c + Vector2(-6, 6) * s, c + Vector2(6, -6) * s, col, 2.5 * s)
		if active and kind != "pin" and kind != "close":
			draw_rect(Rect2(0, 8.0 * s, 3.0, size.y - 16.0 * s), RightRail.ACCENT)
		if dot:
			draw_circle(Vector2(size.x - 9.0 * s, 9.0 * s), 5.5 * s, UiKit.BADGE_AMBER)


## Contenitore della striscia Obiettivo: ogni fotogramma decide se si vede (nascosta in Riepilogo e Missioni).
class GoalStrip extends PanelContainer:
	var rail: RightRail

	func _process(_delta: float) -> void:
		var want := rail != null and rail.strip_wanted()
		if want != visible:
			visible = want


## Prende i tasti Esc prima di MainScreen (è figlio di «Drawer»: l'input non gestito scende dai figli ai genitori).
class EscCatcher extends Node:
	var rail: RightRail

	func _unhandled_key_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo or k.keycode != KEY_ESCAPE:
			return
		if rail != null and rail.drawer_open():
			rail.set_drawer(false)
			get_viewport().set_input_as_handled()


func _init(ms: Control) -> void:
	_ms = ms
	_right = ms.get_node("Root/Body/RightColumn")
	_right_vbox = ms.get_node("Root/Body/RightColumn/RightScroll/VBox")
	_body = ms.get_node("Root/Body")
	_toasts = ms.get_node("%Toasts")
	_log = ms.get_node("%Log") as LogView
	_slot = ms.get_node("%AmiciSlot") as VBoxContainer


func is_built() -> bool:
	return _built


func build() -> void:
	_build_drawer_layer()
	_build_head()
	_build_rail()
	_build_goal_strip()
	grip = ColumnGrip.new()
	_body.add_child(grip)
	_body.move_child(grip, _right.get_index())
	grip.dragged.connect(_on_grip_dragged)
	grip.released.connect(_on_grip_released)
	grip.reset_requested.connect(_on_grip_reset)
	city_strip = CityStrip.new()
	city_strip.visible = false
	_ms.get_node("Root").add_child(city_strip)
	EventBus.crate_opened.connect(_on_rare_event)
	EventBus.achievement_unlocked.connect(_on_rare_event)
	EventBus.quest_completed.connect(_on_rare_event)
	EventBus.level_up.connect(_on_level_up)
	EventBus.unlocked.connect(_on_unlocked)
	_built = true
	_migrate_layout()
	apply_column()


## Strato del cassetto: velo + (in apertura) la colonna; sopra tutto il resto, escluso il binario.
func _build_drawer_layer() -> void:
	_drawer = Control.new()
	_drawer.name = "Drawer"
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ms.add_child(_drawer)
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drawer_catcher = Control.new()
	_drawer_catcher.name = "DrawerCatcher"
	_drawer_catcher.visible = false
	_drawer_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer_catcher.gui_input.connect(_on_catcher_input)
	_drawer.add_child(_drawer_catcher)
	_drawer_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_catcher.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var esc := EscCatcher.new()
	esc.name = "EscCatcher"
	esc.rail = self
	_drawer.add_child(esc)


## Intestazione del cassetto (in cima a VBox): titolo della sezione, filtri del Registro, 📌 Fissa, chiudi.
func _build_head() -> void:
	var head := HBoxContainer.new()
	head.name = "DrawerHead"
	head.add_theme_constant_override("separation", 4)
	_right_vbox.add_child(head)
	_right_vbox.move_child(head, 0)
	_head_title = Label.new()
	_head_title.name = "DrawerTitle"
	_head_title.theme_type_variation = &"SectionLabel"
	_head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head_title.clip_text = true
	_head_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_head_title)
	_filter_btn = MenuButton.new()
	_filter_btn.name = "FilterButton"
	_filter_btn.text = "UI_RAIL_FILTERS"
	_filter_btn.tooltip_text = "UI_RAIL_FILTERS_TIP"
	_filter_btn.flat = true
	_filter_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pop := _filter_btn.get_popup()
	pop.hide_on_checkable_item_selection = false
	pop.about_to_popup.connect(_fill_filters)
	pop.index_pressed.connect(_on_filter_pressed)
	head.add_child(_filter_btn)
	_pin_btn = RailButton.new("pin", 32.0)
	_pin_btn.pressed.connect(_on_pin_pressed)
	head.add_child(_pin_btn)
	_close_btn = RailButton.new("close", 32.0)
	_close_btn.tooltip_text = "UI_RAIL_CLOSE_TIP"
	_close_btn.pressed.connect(set_drawer.bind(false))
	head.add_child(_close_btn)


func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.name = "RightRail"
	_rail.theme_type_variation = &"LogPanel"
	_rail.custom_minimum_size.x = RAIL_W
	var box := VBoxContainer.new()
	box.name = "RailBox"
	box.add_theme_constant_override("separation", 6)
	_rail.add_child(box)
	_btn_log = RailButton.new("log", BTN)
	_btn_log.tooltip_text = "UI_RAIL_LOG_TIP"
	_btn_log.pressed.connect(_on_rail_pressed.bind(SECTION_LOG))
	box.add_child(_btn_log)
	box.add_child(_caption("RailLogCap", "UI_GM_RAIL_LOG"))       # l'icona da sola non dice cosa apre (rapporto 08 punto 12)
	_btn_friends = RailButton.new("friends", BTN)
	_btn_friends.tooltip_text = "UI_RAIL_FRIENDS_TIP"
	_btn_friends.pressed.connect(_on_rail_pressed.bind(SECTION_FRIENDS))
	_btn_friends.visible = false
	box.add_child(_btn_friends)
	_push_slot = VBoxContainer.new()                # posto della Sabbia del Custode (F14): vuoto in F3
	_push_slot.name = "PushSlot"
	_push_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_push_slot.alignment = BoxContainer.ALIGNMENT_END
	_push_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_push_slot)
	_push = PushButton.new()                        # nascosto finché la Sabbia non è sbloccata (o con push_enabled = false)
	_push_slot.add_child(_push)
	_body.add_child(_rail)
	var sb := _rail.get_theme_stylebox("panel").duplicate() as StyleBox          # margini stretti: il pulsante da 48 px sta in 52
	sb.content_margin_left = (RAIL_W - PushButton.SIDE) * 0.5
	sb.content_margin_right = (RAIL_W - PushButton.SIDE) * 0.5
	_rail.add_theme_stylebox_override("panel", sb)


## Didascalia sotto un'icona del binario: stessa misura e colore per tutte (11 px, spenta), centrata, mai tagliata.
static func _caption(node_name: String, key: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = key
	l.theme_type_variation = &"MutedLabel"
	l.add_theme_font_size_override("font_size", CAPTION_PX)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_FILL
	return l


## Striscia Obiettivo: ScreenScroll viene messo in una colonna insieme alla striscia (in codice, per non toccare il resto della scena).
func _build_goal_strip() -> void:
	var content := _ms.get_node("Root/Body/Content")
	var scroll := _ms.get_node("%ScreenScroll") as Control
	var col := VBoxContainer.new()
	col.name = "ContentColumn"
	col.add_theme_constant_override("separation", 4)
	content.add_child(col)
	scroll.reparent(col, false)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_goal_holder = GoalStrip.new()
	_goal_holder.rail = self
	_goal_holder.name = "GoalStrip"
	var strip_sb := StyleBoxFlat.new()                  # una riga da 28 px: fondo tenue, margini solo ai lati
	strip_sb.bg_color = Color(1, 1, 1, 0.05)
	strip_sb.set_corner_radius_all(3)
	strip_sb.content_margin_left = 8
	strip_sb.content_margin_right = 4
	strip_sb.content_margin_top = 0
	strip_sb.content_margin_bottom = 0
	_goal_holder.add_theme_stylebox_override("panel", strip_sb)
	_goal_holder.visible = false
	col.add_child(_goal_holder)
	col.move_child(_goal_holder, 0)
	goal = GoalPanel.new()
	_goal_holder.add_child(goal)
	TutorialTargets.mark(_rail, "rail")


## Chiavi stabili del tutorial: `topbar:column` e `rail:log` indicano il pulsante Registro del binario.
func mark_targets() -> void:
	TutorialTargets.mark(_btn_log, "rail:log")
	TutorialTargets.mark(_push.hit, "rail:push")
	_btn_log.add_to_group(TutorialTargets.GROUP_PREFIX + "topbar:column")


## Revisione 2 del layout: la colonna destra fissa diventa un cassetto. Una sola volta, con un avviso.
func _migrate_layout() -> void:
	if int(Settings.get_value("ui_layout_rev")) >= LAYOUT_REV:
		return
	Settings.set_value("right_col_visible", false)
	Settings.set_value("ui_layout_rev", LAYOUT_REV)
	if _ms.has_method("toast"):
		_ms.call("toast", tr("UI_RAIL_MIGRATION"))


# ------------------------------------------------------------------ aggiornamento

## Parti che cambiano piano (2 Hz): binario (Amici), puntino del Registro.
func refresh_slow() -> void:
	var avail := friends_available()
	if _btn_friends.visible != avail:
		_btn_friends.visible = avail
		_show_section()


## Bordo basso della striscia Obiettivo nelle coordinate della schermata principale (0 se non si vede): sotto, gli avvisi.
func goal_bottom_y() -> float:
	if _goal_holder == null or not is_instance_valid(_goal_holder) or not _goal_holder.is_visible_in_tree():
		return 0.0
	return _goal_holder.global_position.y + _goal_holder.size.y - _ms.global_position.y


## A ogni tick (10 Hz): la striscia Obiettivo e la sua visibilità nella schermata corrente.
func refresh_goal() -> void:
	if goal != null:
		goal.refresh()


## La striscia si vede se c'è un obiettivo e la schermata non è Riepilogo o Missioni (dove l'obiettivo è già nel contenuto).
## Eccezione: durante un passo del tutorial che blocca i clic il «Vai» (goal_go) deve restare raggiungibile, anche in Riepilogo.
func strip_wanted() -> bool:
	if goal == null or not goal.visible:
		return false
	if not NO_STRIP_SCREENS.has(str(_ms.get("current_id"))):
		return true
	var tut: Variant = _ms.call("tutorial") if _ms.has_method("tutorial") else null
	return tut != null and (tut as TutorialDirector).is_blocking()


## Gli Amici compaiono nel binario solo con il coop sbloccato E una lobby aperta almeno una volta (D13): stanza in corso,
## oppure soprannome o gilda già salvati nella sezione personale.
func friends_available() -> bool:
	if not GameState.active or not (GameState.data.get("unlocks", []) as Array).has("feature:coop"):
		return false
	var svc := CoopNetService.instance()
	if svc != null and svc.status != CoopNetService.ST_OFFLINE:
		return true
	var sec: Variant = GameState.data.get("coop_net", {})
	if sec is Dictionary:
		return not str(sec.get("nick", "")).is_empty() or not str(sec.get("guild_id", "")).is_empty()
	return false


# ------------------------------------------------------------------ stato colonna / cassetto

## Colonna fissata: preferenza accesa E banda larga (nelle altre bande la preferenza resta, ma si usa il cassetto).
func is_pinned() -> bool:
	return bool(Settings.get_value("right_col_visible")) and band == UiBands.BAND_WIDE


func pin_available() -> bool:
	return band == UiBands.BAND_WIDE


## true se il Registro o gli Amici si vedono in questo momento (colonna fissata o cassetto aperto).
func column_visible() -> bool:
	return is_pinned() or _drawer_open


func drawer_open() -> bool:
	return _drawer_open


func column_width() -> float:
	return float(Settings.get_value("right_col_width"))


## Sezione mostrata: quella ricordata in Settings, ma «friends» solo se disponibile.
func section() -> String:
	var s := str(Settings.get_value("drawer_section"))
	if s == SECTION_FRIENDS and friends_available():
		return SECTION_FRIENDS
	return SECTION_LOG


func log_dot() -> bool:
	return _dot


## L: con la colonna fissata la toglie (torna cassetto); altrimenti apre/chiude il cassetto sull'ultima sezione aperta.
func toggle_column() -> void:
	if is_pinned():
		Settings.set_value("right_col_visible", false)
	else:
		set_drawer(not _drawer_open)


func set_drawer(open: bool, sec: String = "") -> void:
	if sec == SECTION_LOG or sec == SECTION_FRIENDS:
		Settings.set_value("drawer_section", sec)
	_drawer_open = open and not is_pinned()
	apply_column()


func apply_column() -> void:
	if not _built:
		return
	band = UiBands.band(_ms.size.x)
	narrow = band == UiBands.BAND_NARROW
	var pinned := is_pinned()
	if pinned:
		_drawer_open = false
	var w := column_width()
	if not pinned:
		w = minf(w, maxf(180.0, _ms.size.x * DRAWER_MAX_FRAC))
	_place_column(_drawer_open)
	_place_push(pinned)
	_right.visible = pinned or _drawer_open
	_right.custom_minimum_size.x = w
	grip.visible = pinned
	_drawer_catcher.visible = _drawer_open
	_drawer_catcher.offset_top = _top_h
	_drawer_catcher.offset_right = -RAIL_W
	if _drawer_open:
		_right.offset_left = -(w + RAIL_W)
		_right.offset_right = -RAIL_W
		_right.offset_top = _top_h
		_right.offset_bottom = 0.0
	_show_section()
	_pin_btn.visible = _right.visible
	_pin_btn.disabled = not pin_available()
	_pin_btn.active = pinned
	_pin_btn.tooltip_text = "UI_RAIL_UNPIN_TIP" if pinned else ("UI_RAIL_PIN_TIP" if pin_available() else "UI_RAIL_PIN_WIDE_ONLY")
	_place_toasts(RAIL_W + (w if (pinned or _drawer_open) else 0.0))


## Larghezza logica cambiata (finestra ridimensionata, scala interfaccia, schermo diverso). `top_h` = altezza della barra alta
## (il velo e il cassetto partono sotto di essa). `value` = banda stretta (la banda vera la ricalcola apply_column).
func set_narrow(value: bool, top_h: float) -> void:
	narrow = value
	_top_h = top_h
	apply_column()


## Sposta RightColumn fra Root/Body (chiusa o fissata) e Drawer (cassetto aperto).
func _place_column(in_drawer: bool) -> void:
	if in_drawer:
		if _right.get_parent() != _drawer:
			_right.reparent(_drawer, false)
			_right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	elif _right.get_parent() != _body:
		_right.reparent(_body, false)
		_right.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_right.offset_top = 0.0
		_right.offset_bottom = 0.0
		_body.move_child(_right, _rail.get_index())


## Il pulsante della Sabbia sta in fondo al binario; con la colonna fissata va in fondo alla colonna (stessa chiave rail:push).
func _place_push(pinned: bool) -> void:
	if _push == null:
		return
	var want: Node = _right_vbox if pinned else _push_slot
	if _push.get_parent() != want:
		_push.reparent(want, false)
	if pinned:
		_right_vbox.move_child(_push, -1)


## Mostra Registro o Amici (uno alla volta: il Registro occupa tutta l'altezza e scorre).
func _show_section() -> void:
	var sec := section()
	var is_log := sec == SECTION_LOG
	_log.visible = is_log
	_slot.visible = not is_log
	_filter_btn.visible = is_log
	_head_title.text = "UI_LOG" if is_log else "UI_RAIL_FRIENDS"
	var shown := _right.visible
	_btn_log.active = shown and is_log
	_btn_friends.active = shown and not is_log
	if shown and is_log:
		if _dot:
			_dot = false
		_log.scroll_to_end.call_deferred()
	_btn_log.dot = _dot
	_btn_log.tooltip_text = "UI_RAIL_LOG_NEW_TIP" if _dot else "UI_RAIL_LOG_TIP"


## Gli avvisi a comparsa stanno in alto, al centro dell'area di contenuto (tra menù e colonna destra/binario): mai sui
## pulsanti d'uso in basso né sul Riscatta dell'obiettivo a destra. `col_w` = larghezza di binario + colonna.
func _place_toasts(col_w: float) -> void:
	var width := _toasts.offset_right - _toasts.offset_left
	var sb := _ms.get_node_or_null("Root/Body/Sidebar") as Control
	var side := sb.custom_minimum_size.x if sb != null else 0.0
	var shift := (side - col_w) * 0.5                     # centro dell'area di contenuto rispetto al centro della finestra
	_toasts.offset_left = shift - width * 0.5
	_toasts.offset_right = shift + width * 0.5


# ------------------------------------------------------------------ eventi

func _on_rail_pressed(sec: String) -> void:
	if is_pinned():
		Settings.set_value("drawer_section", sec)
		apply_column()
	elif _drawer_open and section() == sec:
		set_drawer(false)
	else:
		set_drawer(true, sec)


func _on_pin_pressed() -> void:
	if not pin_available():
		return
	if is_pinned():
		Settings.set_value("right_col_visible", false)
	else:
		_drawer_open = false
		Settings.set_value("right_col_visible", true)
	apply_column()


## Evento raro (Cassa aperta, impresa, missione, livello dell'Eroe): puntino sul Registro se non lo si sta guardando.
func _on_rare_event(_a: Variant = null) -> void:
	if _built and not (column_visible() and section() == SECTION_LOG):
		_dot = true
		_btn_log.dot = true
		_btn_log.tooltip_text = "UI_RAIL_LOG_NEW_TIP"


func _on_level_up(skill: String, _level: int) -> void:
	if skill == "hero":
		_on_rare_event()


func _on_unlocked(_token: String) -> void:
	refresh_slow()


func _on_catcher_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		set_drawer(false)
		_drawer_catcher.accept_event()


# ------------------------------------------------------------------ filtri del Registro (NoticeFilter, in Settings)

func _fill_filters() -> void:
	var pop := _filter_btn.get_popup()
	pop.clear()
	for cat in NoticeFilter.CATEGORIES:
		pop.add_check_item(tr("UI_UIA_NOTIFY_" + str(cat).to_upper()))
		pop.set_item_checked(pop.item_count - 1, bool(Settings.get_value(NoticeFilter.key_of(cat))))


func _on_filter_pressed(index: int) -> void:
	if index < 0 or index >= NoticeFilter.CATEGORIES.size():
		return
	var key := NoticeFilter.key_of(NoticeFilter.CATEGORIES[index])
	var pop := _filter_btn.get_popup()
	var on := not bool(Settings.get_value(key))
	Settings.set_value(key, on)
	pop.set_item_checked(index, on)


# ------------------------------------------------------------------ maniglia

func _on_grip_dragged(dx: float) -> void:
	var r: Array = Settings.RANGES["right_col_width"]
	_right.custom_minimum_size.x = clampf(_right.custom_minimum_size.x - dx, float(r[0]), float(r[1]))
	_place_toasts(RAIL_W + _right.custom_minimum_size.x)


func _on_grip_released() -> void:
	Settings.set_value("right_col_width", int(_right.custom_minimum_size.x))


func _on_grip_reset() -> void:
	Settings.set_value("right_col_width", int(Settings.DEFAULTS["right_col_width"]))
	apply_column()
