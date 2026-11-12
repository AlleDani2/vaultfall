extends Control
## Layout principale (docs/16 §2, T-0.4): barra superiore, menù laterale da ScreenRegistry, area contenuto,
## colonna destra con registro e notifiche a comparsa. Solo presentazione: legge GameState, ascolta EventBus.
## Aggiornamento a 10 Hz (2 Hz con la finestra in secondo piano, docs/17 §11).
##
## F0 del progetto di interfaccia (docs/ui_redesign/06 §4.3): MainScreen è l'ORCHESTRATORE. La logica è divisa in pezzi con
## un solo proprietario, creati in `_ready` e raggiunti con le deleghe pubbliche qui sotto (nessun cambio di comportamento):
##   - TopBar       barra alta: oro, attività, «tempo al livello», pausa, salva, impostazioni, aiuto, indicatore di modalità;
##   - SidebarMenu  menù laterale: voci, sezioni, pallini numerici, segni dell'attività, indicatori ai bordi;
##   - RightRail    colonna destra: Obiettivo, Paralleli, Amici, Registro, cassetto, maniglia, posizione dei toast;
##   - UiBands      costanti di interfaccia e bande di larghezza.
## Qui restano: schermata corrente, scorciatoie da tastiera, registro/avvisi, tutorial, benvenuto e navigazione.
##
## UI-B (audit G22-G24, G34, G37, G53): badge sulle voci del menù, riquadro «Paralleli», scorciatoie (ShortcutMap), colonna
## destra nascondibile e ridimensionabile, striscia Città (CityStrip), voci bloccate cliccabili (ReqLink), LevelEta, CozyMode.
##
## «AmiciSlot» (%AmiciSlot) è un VBoxContainer VUOTO riservato al riquadro «Amici» del co-op (COOP-2): basta aggiungerci
## i propri nodi con `add_child`; non va rinominato né spostato.

const START_SCENE := "res://src/ui/start/StartScreen.tscn"
const UI_HZ_FOCUSED := 10.0
const UI_HZ_BACKGROUND := 2.0
const TOAST_SECONDS := 2.6
const TOAST_SECONDS_TUTORIAL := 1.8     # durante il tutorial gli avvisi passano più in fretta
const TOAST_MAX := 3                    # visibili insieme: gli altri aspettano in coda
const TOAST_QUEUE_MAX := 12             # coda oltre il tetto: i più vecchi si scartano (restano nel Registro)
const TOAST_TOP_GAP := 8.0             # sotto la barra alta: mai sui pulsanti d'uso in basso a destra
const SLOW_EVERY := 5                  # i badge, il riquadro Paralleli e il «tempo al livello» si aggiornano a 2 Hz (ogni 5 passi da 10 Hz)

@warning_ignore("unused_private_class_variable")
@onready var _settings_btn: Button = %SettingsButton       # solo per test e bot (get("_settings_btn"))
@warning_ignore("unused_private_class_variable")
@onready var _menu: VBoxContainer = %List
@onready var _host: MarginContainer = %Host
@onready var _screen_scroll: ScrollContainer = %ScreenScroll
@onready var _content: PanelContainer = $Root/Body/Content
@onready var _log: LogView = %Log
@onready var _toasts: VBoxContainer = %Toasts
@warning_ignore("unused_private_class_variable")
@onready var _level_eta: Label = %LevelEta

## Emesso al posto del cambio di scena quando MainScreen non è la scena corrente (es. nei test).
signal navigate(scene_path: String)

var current_id: String = ""
var _current: Control
var _holder: Node                 # nodo dentro Host: la schermata stessa, o il ScrollContainer che la contiene (wants_scroll)
var _timer := Timer.new()
var _digest := LogDigest.new()      # GUILD-2: livelli, Deposito pieno, imprese… in una riga per gruppo
var _digest_timer := Timer.new()
var _overlay: OverlayHost
var _tutorial: TutorialDirector
var _toast_queue: Array = []
var _tick_n: int = 0
var _topbar: TopBar
var _sidebar: SidebarMenu
var _rail: RightRail

# alias di sola lettura per test e bot: lo stato vive nei pezzi
@warning_ignore("unused_private_class_variable")
var _buttons: Dictionary:           # id voce -> Button
	get: return _sidebar.buttons
@warning_ignore("unused_private_class_variable")
var _badges: Dictionary:            # id voce -> PanelContainer del badge
	get: return _sidebar.badges
@warning_ignore("unused_private_class_variable")
var _menu_ids: Array:               # id delle voci disponibili, nell'ordine del menù (tasti 1-9)
	get: return _sidebar.menu_ids
@warning_ignore("unused_private_class_variable")
var _menu_scroll: ScrollContainer:
	get: return _sidebar.sidebar().get_node("Scroll") as ScrollContainer
@warning_ignore("unused_private_class_variable")
var _grip: ColumnGrip:
	get: return _rail.grip
@warning_ignore("unused_private_class_variable")
var _city_strip: CityStrip:
	get: return _rail.city_strip


func _ready() -> void:
	add_to_group(FocusAssist.ENTRY_GROUP)
	if not GameState.active:
		# avvio diretto della scena senza partita (debug dall'editor): si torna al menù iniziale
		_go(START_SCENE)
		return
	GameScreen.sliced_builds = get_tree().current_scene == self     # costruzione a fette solo nel gioco vero (non nei test)
	_topbar = TopBar.new(self)
	_sidebar = SidebarMenu.new(self)
	_rail = RightRail.new(self)
	_topbar.setup()
	# tastiera: con Tab il focus può finire fuori vista; ogni ScrollContainer scorre fino al controllo con il focus (QA 95)
	for sc in find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).follow_focus = true
	get_tree().node_added.connect(_on_node_added)
	_rail.build()
	resized.connect(_apply_adaptive)
	$Root/TopBar.resized.connect(_apply_adaptive)
	_content.draw.connect(_draw_section_edge)
	EventBus.settings_changed.connect(_on_setting_changed)
	EventBus.notice.connect(_on_notice)
	# avvisi emessi da Game.load_game prima che questa schermata esistesse (orologio indietro, ripiego sul backup...) - QA120
	_show_load_notices.call_deferred()
	EventBus.level_up.connect(_on_level_up)
	EventBus.save_completed.connect(_on_save_completed)
	EventBus.offline_progress.connect(_on_offline_progress)
	EventBus.unlocked.connect(_on_unlocked_rebuild)
	EventBus.state_loaded.connect(build_menu)
	EventBus.locale_changed.connect(_on_locale_rebuild)
	EventBus.screen_requested.connect(_on_screen_requested)
	EventBus.game_stopped.connect(_on_game_stopped)
	_topbar.build_mode_badge()
	EventBus.app_focus_changed.connect(_on_focus_changed)
	EventBus.clock_paused_changed.connect(_on_pause_refresh)
	var dg: Dictionary = DataRegistry.rules("social_rules").get("log_digest", {})
	_digest.max_listed = int(dg.get("max_items_listed", _digest.max_listed))
	_digest_timer.one_shot = true
	_digest_timer.wait_time = float(dg.get("window_s", 1.5))
	_digest_timer.timeout.connect(_flush_digest)
	add_child(_digest_timer)
	add_child(_timer)
	_timer.wait_time = 1.0 / UI_HZ_FOCUSED
	_timer.timeout.connect(_on_ui_tick)
	_timer.start()
	_sidebar.build_edge_hints()
	_log.set_empty_text(tr("UI_UXA_LOG_EMPTY"))     # il registro non resta una colonna nuda: messaggio smorzato finché non c'è nulla
	build_menu()
	show_screen("summary")
	_refresh_top()
	add_child(FxDirector.new(self))     # effetti globali: level up, missioni, imprese, sblocchi, monete (FX)
	_overlay = OverlayHost.new()
	add_child(_overlay)                # benvenuto, tutorial al primo sblocco, Bentornato, F1 = Manuale (QUESTS)
	_mark_tutorial_targets()
	_tutorial = TutorialDirector.new(self, _overlay)     # tutorial guidato: evidenzia i controlli giusti (TutorialDirector)
	add_child(_tutorial)
	_update_slow()
	if get_tree().current_scene == self:
		add_child(ScreenWarmup.new())      # precarica le schermate in un thread, una per volta (la prima apertura non si blocca)
	FriendsPanel.attach(self)          # COOP-2: riquadro «Amici» ripiegabile in cima alla colonna destra
	_apply_adaptive()
	_open_menu_intent.call_deferred()


## «Cooperativa (LAN)» dal menù principale: la partita si apre direttamente sulla Lobby (MenuIntent, letto una volta sola).
func _open_menu_intent() -> void:
	var sid := MenuIntent.take()
	if not sid.is_empty() and not show_screen(sid):
		_on_notice("info", tr("UI_M10_COOP_LOCKED"), {})


## Un pulsante dentro una schermata chiede un'altra schermata (es. «Dungeon…» nel Combattimento). Se la destinazione è
## ancora bloccata il clic non deve restare muto (QA 95): come la voce di menù, porta alla missione che la sblocca oppure
## dice come si sblocca.
func _on_screen_requested(id: String, params: Dictionary = {}) -> void:
	if show_screen(id, params):
		return
	var e := ScreenRegistry.get_entry(id)
	var unlocks: Array = GameState.data.get("unlocks", [])
	if e.is_empty() or str(e.get("scene", "")).is_empty() or ScreenRegistry.is_unlocked(e, unlocks):
		return
	var token := str(e.get("hint_unlock", e.get("unlock", "")))
	if ReqLink.go(ReqLink.target_for_token(token)):
		return
	var hint := UnlockSystem.hint_for(token, DataRegistry)
	_on_notice("info", tr(hint if not hint.is_empty() else "UI_INTEG_LOCKED_LATER"), {})


func _on_node_added(n: Node) -> void:
	if n is ScrollContainer:
		(n as ScrollContainer).follow_focus = true


## Ricostruisce il menù laterale da ScreenRegistry (voci bloccate o non ancora realizzate in grigio).
func _on_unlocked_rebuild(_t: String) -> void:
	build_menu()


func _on_locale_rebuild(_l: String) -> void:
	build_menu()


func _on_pause_refresh(_p: bool) -> void:
	_refresh_top()
	refresh_activity_marks()


# ------------------------------------------------------------------ deleghe pubbliche (test, bot, altre schermate)

## Ricostruisce il menù laterale (delega a SidebarMenu).
func build_menu() -> void:
	_sidebar.build_menu()


func badge_count(id: String) -> int:
	return _sidebar.badge_count(id)


func refresh_activity_marks() -> void:
	_sidebar.refresh_activity_marks()


## Dati di un segno per i test: {role, state, frac, tip, breathing} oppure {} se la voce non è evidenziata.
func activity_mark(id: String) -> Dictionary:
	return _sidebar.activity_mark(id)


func main_mark_id() -> String:
	return _sidebar.main_mark_id()


## Indicatori ai bordi del menù (visibili solo se la voce principale è fuori vista): per i test.
func edge_hints() -> Dictionary:
	return _sidebar.edge_hints()


func _tick_marks() -> void:
	_sidebar.tick_marks()


func _set_badge(id: String, n: int, tip_key: String) -> void:
	_sidebar._set_badge(id, n, tip_key)


func column_visible() -> bool:
	return _rail.column_visible()


## Il pulsante «»/tasto L: con la finestra larga apre/chiude la colonna fissa (preferenza salvata); con la finestra
## stretta apre/chiude il cassetto (non cambia la preferenza).
func toggle_column() -> void:
	_rail.toggle_column()


func is_narrow() -> bool:
	return _rail.narrow


func is_compact() -> bool:
	return _topbar.compact


func drawer_open() -> bool:
	return _rail.drawer_open()


func _apply_column() -> void:
	_rail.apply_column()


## La striscia Città (chiacchiera dei PNG + Gazzetta) non sta più nella cornice (F6, D16): è una riga in fondo al Riepilogo
## (`CityStrip.make_row()`). Quindi non è visibile in nessuna schermata.
func city_strip_visible_for(_screen_id: String) -> bool:
	return false


## Disegna il filo di sezione sul bordo sinistro del pannello dei contenuti (nessuna animazione).
func _draw_section_edge() -> void:
	var sec := LogCategory.of_screen(current_id)
	if sec.is_empty() or _content == null:
		return
	_content.draw_rect(Rect2(2.0, 14.0, 3.0, maxf(0.0, _content.size.y - 28.0)), LogCategory.color(sec))


func open_help() -> void:
	show_screen("manual", {"page": ManualCatalog.page_for_screen(current_id) if current_id != "manual" else "start"})


## Mostra una schermata registrata. Ritorna false se non esiste, è bloccata o non è ancora realizzata.
func show_screen(id: String, params: Dictionary = {}) -> bool:
	var e := ScreenRegistry.get_entry(id)
	if e.is_empty() or not ScreenRegistry.is_available(e, GameState.data.get("unlocks", [])):
		return false
	var packed: PackedScene = load(e.scene)
	if packed == null:
		push_warning("MainScreen: scena mancante " + str(e.scene))
		return false
	if _current != null:
		if _current.has_method("close"):
			_current.close()
		if _holder != null:
			_holder.queue_free()
		else:
			_current.queue_free()
	_current = packed.instantiate()
	_holder = _current
	# ogni schermata sta in ScreenScroll (scena): se è più alta o più larga dell'area utile scorre, non esce dalla finestra
	_current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.add_child(_current)
	_screen_scroll.scroll_vertical = 0
	_screen_scroll.scroll_horizontal = 0
	FxUi.screen_in(_holder)                  # dissolvenza breve (<= 0,15 s; nessuna con «riduci animazioni»)
	var p: Dictionary = e.get("params", {}).duplicate()
	p.merge(params, true)
	if _current.has_method("open"):
		_current.open(p)
	current_id = id
	var qs := Game.system("quests") as QuestSystem
	if qs != null:
		qs.note_screen(id)                  # passi di scoperta (QuestGuide.discoveries): schermata già vista
	_content.queue_redraw()                  # filo colorato della sezione lungo il bordo sinistro (stesso colore del Registro)
	_content.theme = UiKit.accent_theme(str(e.get("section", "")))     # accento di sezione: oliva / ruggine / viola
	_sidebar.select(id)
	if _rail.city_strip != null:
		_rail.city_strip.visible = city_strip_visible_for(id)
	return true


func current_screen() -> Control:
	return _current


## Tutorial guidato (TutorialDirector) di questa schermata principale.
func tutorial() -> TutorialDirector:
	return _tutorial


## Chiavi stabili dei controlli che il tutorial può evidenziare (TutorialTargets): mai il testo tradotto.
func _mark_tutorial_targets() -> void:
	TutorialTargets.mark(_sidebar.sidebar(), "sidebar")
	TutorialTargets.mark(_content, "content")
	_topbar.mark_targets()
	_rail.mark_targets()


# ------------------------------------------------------------------ aggiornamento (10 Hz)

func _on_ui_tick() -> void:
	_place_toasts_top()
	_pump_toasts()
	_refresh_top()
	_tick_marks()
	_tick_n += 1
	if _tick_n % SLOW_EVERY == 0:
		_update_slow()
	_sidebar.refresh_talent_badge()
	_rail.refresh_goal()
	if _current != null and _current.has_method("refresh"):
		_current.refresh()


## Parti che cambiano piano (2 Hz): badge del menù, riquadro Paralleli, «tempo al livello».
func _update_slow() -> void:
	_sidebar.update_badges()
	refresh_activity_marks()
	_rail.refresh_slow()
	_topbar.update_eta()


func _refresh_top() -> void:
	_topbar.refresh_top()


## Larghezza logica cambiata (finestra ridimensionata, scala interfaccia, schermo diverso): ricalcola le modalità.
func _apply_adaptive() -> void:
	_place_toasts_top()
	if _rail == null or not _rail.is_built():
		return
	var narrow := UiBands.band(size.x) == UiBands.BAND_NARROW
	_rail.set_narrow(narrow, $Root/TopBar.size.y)
	$Root/Body/Sidebar.custom_minimum_size.x = UiBands.SIDEBAR_W_NARROW if narrow else UiBands.SIDEBAR_W
	_rail.apply_column()
	_topbar.set_compact(size.x < UiBands.COMPACT_W)


## Gli avvisi partono subito sotto la barra alta (che cambia altezza con scala e testo), SOTTO la striscia dell'Obiettivo
## quando c'e' (non la coprono) e sotto lo striscione («Impresa sbloccata», ecc.) finche' e' in scena (non si accavallano).
func _place_toasts_top() -> void:
	var h := (get_node("Root/TopBar") as Control).size.y + TOAST_TOP_GAP
	if _rail != null:
		h = maxf(h, _rail.goal_bottom_y() + TOAST_TOP_GAP)
	if Fx.banner_active():
		h = maxf(h, FxBanner.Y_REST + FxBanner.H + TOAST_TOP_GAP)
	_toasts.offset_top = h
	_toasts.offset_bottom = h


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "right_col_visible" or key == "right_col_width":
		_rail.apply_column()
	elif key == "cozy_mode":
		on_cozy_changed()          # il bonus lo applica ModeSystem (stato della partita): qui solo l'avviso


func on_cozy_changed() -> void:
	if CozyMode.is_on():
		_on_notice("info", Loc.tf("UI_UIB_COZY_ON", {"n": NumberFormat.fmt(CozyMode.xp_pct())}), {})


# ------------------------------------------------------------------ scorciatoie da tastiera (G23)

func _unhandled_key_input(event: InputEvent) -> void:
	if Feedback.is_pause_menu_open():
		# il menù di pausa è in primo piano: Esc lo chiude (come «Riprendi»), gli altri tasti non arrivano alla schermata sotto
		var k := event as InputEventKey
		if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			Feedback.close_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _overlay != null and _overlay.is_busy():
		return                                  # una finestra è aperta: i tasti sono suoi (Esc la chiude)
	var act := ShortcutMap.resolve(event, _sidebar.menu_ids)
	if act.is_empty():
		return
	if run_shortcut(act):
		get_viewport().set_input_as_handled()


## Controller (1.0): Start = menù di pausa, B = indietro (alla schermata Riepilogo; chiude le finestre), Select/View = Deposito,
## LB/RB = scheda precedente/successiva. Le schermate con tasti propri (Deposito, Impostazioni) li prendono prima: qui arrivano
## solo quelli non consumati. I tasti sono azioni di InputBindings (rimappabili).
func _unhandled_input(event: InputEvent) -> void:
	var j := event as InputEventJoypadButton
	if j == null or not j.pressed:
		return
	if run_pad(j):
		get_viewport().set_input_as_handled()


## Esegue il pulsante del controller come comando della schermata principale. true se l'ha usato (pubblica: la usano i test).
func run_pad(j: InputEventJoypadButton) -> bool:
	if Feedback.is_pause_menu_open():
		if InputBindings.matches(j, "pad_menu") or InputBindings.matches(j, "pad_back"):
			Feedback.close_pause_menu()
		return true                              # il menù di pausa è in primo piano: gli altri pulsanti non passano oltre
	if _overlay != null and _overlay.is_busy():
		if InputBindings.matches(j, "pad_back"):
			return _overlay.dismiss_active()
		return false
	var f := get_viewport().gui_get_focus_owner()
	if InputBindings.matches(j, "pad_menu"):
		return Feedback.toggle_pause_menu(true)
	if InputBindings.matches(j, "pad_back"):
		if f is LineEdit or f is TextEdit:
			f.release_focus()
			return true
		if current_id != "" and current_id != "summary":
			return show_screen("summary")
		return false
	if InputBindings.matches(j, "pad_bank"):
		return _sidebar.open_entry("bank")
	if InputBindings.matches(j, "pad_tab_prev"):
		return pad_tab(-1)
	if InputBindings.matches(j, "pad_tab_next"):
		return pad_tab(1)
	return false


## LB/RB: se la schermata ha un gruppo di schede standard (TabContainer/TabBar) passa a quella accanto; altrimenti passa alla voce
## accanto del menù laterale.
func pad_tab(step: int) -> bool:
	if _current != null:
		for n in _current.find_children("*", "TabContainer", true, false):
			var tc := n as TabContainer
			if tc.is_visible_in_tree() and tc.get_tab_count() > 1:
				tc.current_tab = posmod(tc.current_tab + step, tc.get_tab_count())
				return true
	var ids: Array = _sidebar.menu_ids
	if ids.is_empty():
		return false
	var i := ids.find(current_id)
	var n := ids.size()
	return _sidebar.open_entry(str(ids[posmod((i if i >= 0 else 0) + step, n)]))


## Punto d'ingresso del fuoco per il controller: il primo controllo utile della schermata aperta, altrimenti del menù laterale.
func focus_entry_point() -> bool:
	if _overlay != null and _overlay.is_busy():
		var top := FocusAssist.first_focusable(_overlay)       # una finestra è aperta: il fuoco resta dentro di lei, mai sotto
		if top != null:
			top.grab_focus()
		return true
	for root in [_current, _sidebar.sidebar() if _sidebar != null else null]:
		var c := FocusAssist.first_focusable(root as Node)
		if c != null:
			c.grab_focus()
			return true
	return false


## Esegue un'azione risolta da ShortcutMap. true se l'ha consumata (pubblico: lo usano anche i test).
func run_shortcut(act: Dictionary) -> bool:
	match str(act.get("type", "")):
		"screen":
			return _sidebar.open_entry(str(act.id))
		"search":
			return _focus_search()
		"escape":
			var f := get_viewport().gui_get_focus_owner()
			if f is LineEdit or f is TextEdit:
				f.release_focus()
				return true
			return Feedback.toggle_pause_menu(true)          # Esc apre il menù di pausa (Riprendi, Salva, Impostazioni, Menù principale, Esci)
		"queue":
			var t := ShortcutMap.queue_target()
			if t.is_empty():
				_on_notice("info", tr("UI_UIB_SC_NO_QUEUE"), {})
				return true
			return show_screen(str(t.id), t.params)
		"column":
			toggle_column()
			return true
	return false


## Ctrl+F: porta il cursore nel primo campo di ricerca visibile della schermata aperta.
func _focus_search() -> bool:
	if _current == null:
		return false
	for n in _current.find_children("*", "LineEdit", true, false):
		var le := n as LineEdit
		if le.is_visible_in_tree() and le.editable:
			le.grab_focus()
			return true
	return false


func _on_focus_changed(focused: bool) -> void:
	_timer.wait_time = 1.0 / (UI_HZ_FOCUSED if focused else UI_HZ_BACKGROUND)
	# in secondo piano la schermata corrente non anima più nulla (tween, _process): niente ridisegni inutili (resoconto 100);
	# i refresh a 2 Hz continuano (metodi chiamati da qui) e al ritorno tutto riparte
	_host.process_mode = Node.PROCESS_MODE_INHERIT if focused else Node.PROCESS_MODE_DISABLED


# ------------------------------------------------------------------ registro e notifiche

## Una riga di Registro. `section` (LogCategory.*) ne decide colore, sigla e nome; vuota = sistema.
func add_log(text: String, section: String = "") -> void:
	Feedback.record_game_line(text)       # ultime righe per «Segnala un problema»
	_log.add_entry(section if not section.is_empty() else LogCategory.SYSTEM, text)


## Avviso a comparsa. Sta in alto sotto la barra (mai sui pulsanti d'uso), al massimo TOAST_MAX insieme: gli altri
## aspettano in coda. Lo stesso testo di seguito non crea un nuovo avviso: aggiorna il contatore «×N» e il tempo.
func toast(text: String) -> void:
	var last := _toasts.get_child(_toasts.get_child_count() - 1) if _toasts.get_child_count() > 0 else null
	if last != null and str(last.get_meta("base", "")) == text:
		_bump_toast(last as PanelContainer)
		return
	if not _toast_queue.is_empty() and str(_toast_queue[-1]) == text:
		return                         # già in coda come ultimo: si somma al precedente
	if _toasts.get_child_count() >= TOAST_MAX or not _toast_queue.is_empty():
		_toast_queue.append(text)
		while _toast_queue.size() > TOAST_QUEUE_MAX:
			_toast_queue.remove_at(0)
		return
	_show_toast(text)


func _toast_seconds() -> float:
	if _tutorial != null and is_instance_valid(_tutorial) and _tutorial.is_showing():
		return TOAST_SECONDS_TUTORIAL
	return TOAST_SECONDS


func _show_toast(text: String) -> void:
	_place_toasts_top()
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("base", text)
	panel.set_meta("count", 1)
	panel.add_child(l)
	_toasts.add_child(panel)
	Fx.pop_in(panel)                  # ingresso con rimbalzo (nessun effetto con «riduci animazioni»)
	_arm_toast(panel)


## Tween legato al pannello: se il toast viene tolto prima (cambio scena) il tween muore con lui.
func _arm_toast(panel: PanelContainer) -> void:
	if panel.has_meta("tween"):
		var old := panel.get_meta("tween") as Tween
		if old != null and old.is_valid():
			old.kill()
	var tw := panel.create_tween()
	panel.set_meta("tween", tw)
	tw.tween_interval(_toast_seconds())
	tw.tween_callback(_fade_toast.bind(panel))


func _bump_toast(panel: PanelContainer) -> void:
	var n := int(panel.get_meta("count", 1)) + 1
	panel.set_meta("count", n)
	var l := panel.get_child(0) as Label
	l.text = "%s (×%d)" % [str(panel.get_meta("base", "")), n]
	panel.modulate.a = 1.0
	_arm_toast(panel)


## Avvisi in coda: ne entra uno ogni volta che c'è posto (chiamata dal ritmo dell'interfaccia).
func _pump_toasts() -> void:
	while not _toast_queue.is_empty() and _toasts.get_child_count() < TOAST_MAX:
		_show_toast(str(_toast_queue.pop_front()))


func _fade_toast(p: PanelContainer) -> void:
	if p == null or not is_instance_valid(p):
		return
	FxUi.toast_out(p)                   # sparisce subito con «riduci animazioni», altrimenti svanisce rimpicciolendo


func _show_load_notices() -> void:
	for n in Game.take_load_notices():
		_on_notice(str(n.kind), str(n.text), {"section": LogCategory.SYSTEM})


func _on_notice(kind: String, text: String, data: Dictionary) -> void:
	if _digest.absorb(kind, text, data):        # messaggio ripetitivo: va nel riassunto della finestra
		_arm_digest()
		return
	add_log(text, LogCategory.of_notice(kind, data, current_id))
	toast(text)


func _on_level_up(skill: String, level: int) -> void:
	var name_text := Loc.t(DataRegistry.get_def("skills", skill).get("name", {}))
	_digest.add_level(name_text, level)
	_arm_digest()


func _arm_digest() -> void:
	if _digest_timer.is_inside_tree() and _digest_timer.is_stopped():
		_digest_timer.start()


## Chiude la finestra: una riga di registro (e un solo avviso a comparsa) per gruppo.
func _flush_digest() -> void:
	for line in _digest.flush():
		add_log(str(line.text), str(line.get("section", LogCategory.SYSTEM)))
		toast(str(line.text))


func _on_save_completed(ok: bool) -> void:
	if not ok:
		# QA120: «il piccione ha lasciato cadere il rotolo» non dice cosa fare (disco pieno, cartella non scrivibile): si aggiunge il perche' e il rimedio
		_on_notice("error", tr("UI_SAVE_FAILED") + " " + tr("UI_QA120_SAVE_FAILED_HINT"), {"section": LogCategory.SYSTEM})


func _on_offline_progress(seconds: float, _report: Dictionary) -> void:
	_on_notice("info", Loc.tf("UI_OFFLINE_PROGRESS", {"time": NumberFormat.fmt_time(seconds)}), {"section": LogCategory.SYSTEM})


func _on_game_stopped() -> void:
	if is_inside_tree():
		_go(START_SCENE)


func _go(scene_path: String) -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(scene_path)
	else:
		navigate.emit(scene_path)
