class_name PushButton
extends VBoxContainer
## Pulsante «Sabbia del Custode» (F14, docs/ui_redesign/06 §3.5, D24-D26, 03 §7.3-7.4). Vive nel PushSlot del binario destro (o in
## fondo al cassetto fissato). Bersaglio 48x48 con l'anello della riserva (disegnato in codice: niente PNG), sotto il tempo «m:ss».
## Solo presentazione: chiama Game.request_push e ascolta EventBus; nessun numero di bilanciamento (click_s, cap, max_cps: dati).
##
## Stati: A pronta · B in uso (clic negli ultimi 300 ms) · C vuota («fra N s») · D non disponibile (motivo nel tooltip) ·
## E automatica (Clic assistito «auto») · HIDDEN (prima dello sblocco o con push_enabled = false).
## Input: clic sinistro, tasto T (azione «push» di InputBindings), controller X (azione «pad_sand») (tenendo premuto = «tieni premuto»), tocco (un solo evento:
## Godot lo converte in mouse). Gli eventi `echo` si ignorano; la cadenza del Clic assistito è un timer interno (mai oltre max_cps).
## Accessibilità: un solo input basta; tieni premuto / interruttore / automatico; Riduci animazioni via PushFeedback.

const SIDE := 48.0
const RING_R := 21.0
const IN_USE_MS := 300
const REFRESH_S := 0.1                       # anello e numero a 10 Hz al massimo
const ACCENT := Color("#e0b95a")
const DIM := Color("#4a4d55")
const GREY := Color("#8a8d96")
const ICON := Color("#d8d2c0")

const HIDDEN := "hidden"
const A := "A"
const B := "B"
const C := "C"
const D := "D"
const E := "E"

var hit: Hit
var time_label: Label
var cap_label: Label
var feedback: PushFeedback
var state: String = HIDDEN
var reason_key: String = ""                  # per lo stato D: chiave del motivo
var frac: float = 0.0                        # riserva / tetto
var auto_on: bool = false                    # Clic assistito «auto» attivo (▶ nell'icona)
var clicks_done: int = 0                     # clic accettati dal gioco (per i test)

var _down: Dictionary = {}                   # sorgenti che tengono premuto: "mouse" | "key" | "pad"
var _toggle_on: bool = false
var _acc: float = 0.0                        # accumulatore del timer del Clic assistito
var _since_refresh: float = 0.0
var _last_click_msec: int = -1000000


## Il controllo vero: 48x48, anello + clessidra. Il disegno legge lo stato dal PushButton.
class Hit extends Button:
	var owner_btn: PushButton

	func _init() -> void:
		name = "PushHit"
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(PushButton.SIDE, PushButton.SIDE)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	func _get_tooltip(_at: Vector2) -> String:
		return owner_btn.tooltip() if owner_btn != null else ""

	func _gui_input(event: InputEvent) -> void:
		if ClickLimiter.is_echo(event):
			accept_event()                     # il sistema operativo ripete i tasti: non sono clic

	func _draw() -> void:
		if owner_btn == null:
			return
		var c := size * 0.5
		var st := owner_btn.state
		var ring_col := PushButton.ACCENT
		match st:
			PushButton.C:
				ring_col = PushButton.GREY
			PushButton.D:
				ring_col = PushButton.DIM
		# anello di fondo + anello della riserva
		if st == PushButton.D:
			_dotted(c, PushButton.RING_R, ring_col)
		elif st == PushButton.C:
			_dashed(c, PushButton.RING_R, ring_col)
		else:
			draw_arc(c, PushButton.RING_R, 0.0, TAU, 48, PushButton.DIM, 3.0, true)
			if owner_btn.frac > 0.0:
				draw_arc(c, PushButton.RING_R, -PI * 0.5, -PI * 0.5 + TAU * clampf(owner_btn.frac, 0.0, 1.0), 48, ring_col, 3.5, true)
		# clessidra
		var icol := PushButton.ICON if st != PushButton.D else PushButton.DIM
		var top := PackedVector2Array([c + Vector2(-8, -11), c + Vector2(8, -11), c + Vector2(0, -1)])
		var bot := PackedVector2Array([c + Vector2(-8, 11), c + Vector2(8, 11), c + Vector2(0, 1)])
		draw_colored_polygon(top, icol)
		draw_colored_polygon(bot, icol)
		draw_line(c + Vector2(-9, -12), c + Vector2(9, -12), icol, 2.0)
		draw_line(c + Vector2(-9, 12), c + Vector2(9, 12), icol, 2.0)
		if owner_btn.auto_on and st != PushButton.D:             # piccolo ▶: Clic assistito automatico (anche mentre spende)
			draw_colored_polygon(PackedVector2Array([c + Vector2(6, 3), c + Vector2(15, 8), c + Vector2(6, 13)]), PushButton.ACCENT)
		if has_focus():
			draw_arc(c, PushButton.RING_R + 4.0, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 1.5, true)

	func _dotted(c: Vector2, r: float, col: Color) -> void:
		for i in 20:
			var a := TAU * float(i) / 20.0
			draw_circle(c + Vector2(cos(a), sin(a)) * r, 1.4, col)

	func _dashed(c: Vector2, r: float, col: Color) -> void:
		for i in 12:
			var a := TAU * float(i) / 12.0
			draw_arc(c, r, a, a + TAU / 24.0, 6, col, 2.5, true)


func _init() -> void:
	name = "PushButton"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 0)
	feedback = PushFeedback.new()
	add_child(feedback)
	add_child(feedback.gain_label)                       # «+N s» sopra il pulsante, dentro il binario, altezza fissa
	hit = Hit.new()
	hit.owner_btn = self
	add_child(hit)
	time_label = Label.new()
	time_label.name = "PushTime"
	time_label.theme_type_variation = &"MonoLabel"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.custom_minimum_size = Vector2(SIDE, 0)
	add_child(time_label)
	cap_label = RightRail._caption("PushCaption", "UI_GM_RAIL_SAND")      # «Sabbia»: l'icona da sola non si capisce (rapporto 08 punto 12)
	cap_label.custom_minimum_size = Vector2(SIDE, 0)
	add_child(cap_label)
	visible = false
	hit.button_down.connect(press_down.bind("mouse"))
	hit.button_up.connect(press_up.bind("mouse"))


func _ready() -> void:
	EventBus.settings_changed.connect(_on_setting)
	EventBus.push_changed.connect(_on_push_changed)
	EventBus.app_focus_changed.connect(_on_focus_changed)
	refresh()


# ------------------------------------------------------------------ stato

func _tp() -> TimePushSystem:
	return Game.system("time_push") as TimePushSystem if GameState.active else null


## Il pulsante esiste per il giocatore: Sabbia sbloccata e push_enabled.
func is_available() -> bool:
	var tp := _tp()
	return tp != null and tp.is_unlocked() and bool(Settings.get_value("push_enabled"))


## Si può dare un clic adesso (azione ammessa, gioco non in pausa, almeno un clic di Sabbia).
func can_spend() -> bool:
	var tp := _tp()
	if tp == null or not is_available() or Clock.core.paused:
		return false
	return tp.block_reason().is_empty() and tp.seconds_to_next_click() <= 0.0


func compute_state() -> String:
	var tp := _tp()
	if tp == null or not is_available():
		return HIDDEN
	if Clock.core.paused:
		reason_key = "UI_PUSH_REASON_PAUSE"
		return D
	reason_key = tp.block_reason()
	if not reason_key.is_empty():
		return D
	if tp.seconds_to_next_click() > 0.0:
		return C
	if Time.get_ticks_msec() - _last_click_msec <= IN_USE_MS:
		return B
	if str(Settings.get_value("push_assist")) == "auto":
		return E
	return A


func refresh() -> void:
	var tp := _tp()
	state = compute_state()
	var shown := state != HIDDEN
	if visible != shown:
		visible = shown
	if not shown:
		_release_all()
		feedback.clear()
		return
	auto_on = str(Settings.get_value("push_assist")) == "auto"
	frac = clampf(tp.reserve_s() / tp.cap_s(), 0.0, 1.0) if tp.cap_s() > 0.0 else 0.0
	match state:
		D:
			time_label.text = "—"
		C:
			time_label.text = Loc.tf("UI_PUSH_WAIT_SHORT", {"s": int(ceil(tp.seconds_to_next_click()))})
		_:
			time_label.text = mmss(tp.reserve_s())
	hit.queue_redraw()


## «m:ss» (cifre, uguale in ogni lingua).
static func mmss(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## Testo del tooltip dello stato corrente (bilingue: chiavi UI_PUSH_*).
func tooltip() -> String:
	var tp := _tp()
	if tp == null or state == HIDDEN:
		return ""
	var head := tr("UI_PUSH_SAND")
	match state:
		D:
			return head + "\n" + tr(reason_key)
		C:
			return head + "\n" + Loc.tf("UI_PUSH_EMPTY", {"s": int(ceil(tp.seconds_to_next_click()))}) + "\n" + _numbers(tp)
	var out := head + "\n" + Loc.tf("UI_PUSH_TIP", {"click": NumberFormat.decimal(tp.click_s(), 1, Loc.locale())}) + "\n" + _numbers(tp)
	if state == E:
		out += "\n" + tr("UI_PUSH_TIP_AUTO")
	return out + "\n" + tr("UI_PUSH_TIP_KEYS")


func _numbers(tp: TimePushSystem) -> String:
	return Loc.tf("UI_PUSH_RESERVE", {"cur": NumberFormat.fmt_time(tp.reserve_s()), "cap": NumberFormat.fmt_time(tp.cap_s())}) \
		+ "\n" + Loc.tf("UI_PUSH_TODAY", {"time": NumberFormat.fmt_time(tp.today_s())})


# ------------------------------------------------------------------ clic

## Un clic. Ritorna il risultato di Game.request_push ({} se il pulsante non è disponibile).
func click() -> Dictionary:
	if not is_available():
		return {}
	var res := Game.request_push(1)
	if bool(res.ok):
		clicks_done += int(res.accepted)
		_last_click_msec = Time.get_ticks_msec()
		feedback.on_push(float(res.seconds))
	refresh()
	return res


## Inizio di una pressione (mouse, tasto T, controller X): un clic subito; poi, con «tieni premuto», il timer interno.
## Con l'interruttore ogni pressione accende/spegne la ripetizione.
func press_down(source: String) -> void:
	if not is_available() or _down.has(source):
		return
	_down[source] = true
	_acc = 0.0
	if str(Settings.get_value("push_assist")) == "toggle":
		_toggle_on = not _toggle_on
	click()


func press_up(source: String) -> void:
	_down.erase(source)


func is_held() -> bool:
	return not _down.is_empty()


func toggle_on() -> bool:
	return _toggle_on


## Clic/s equivalenti del Clic assistito: push_assist_rate, mai oltre max_cps dei dati.
func assist_rate() -> float:
	var cap := float(DataRegistry.constants.get("time_push", {}).get("max_cps", 1))
	return minf(float(Settings.get_value("push_assist_rate")), cap)


## Avanza il timer del Clic assistito di `delta` secondi. Ritorna i clic dati. «hold»: finché si tiene premuto;
## «toggle»: finché l'interruttore è acceso; «auto»: sempre, ma solo quando c'è Sabbia per un clic (spende man mano che si ricarica).
func assist_step(delta: float) -> int:
	var mode := str(Settings.get_value("push_assist"))
	var want := false
	match mode:
		"hold":
			want = is_held()
		"toggle":
			want = _toggle_on
		"auto":
			want = true
	if not want or not can_spend():
		_acc = 0.0
		return 0
	_acc += delta * assist_rate()
	var n := mini(int(_acc), int(DataRegistry.constants.get("time_push", {}).get("max_cps", 1)))
	_acc -= float(int(_acc))
	var done := 0
	for i in n:
		if not can_spend():
			break
		var res := click()
		if not bool(res.get("ok", false)):
			break
		done += 1
	return done


func _process(delta: float) -> void:
	if not visible and not is_available():
		return
	assist_step(delta)
	_since_refresh += delta
	if _since_refresh >= REFRESH_S:
		_since_refresh = 0.0
		refresh()


# ------------------------------------------------------------------ tastiera e controller

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.echo or not InputBindings.matches(k, "push") or not is_available():
		return
	if k.pressed:
		if ShortcutMap.resolve(event, []).get("type", "") != "push" or _text_focus() or _overlay_busy():
			return
		press_down("key")
		get_viewport().set_input_as_handled()
	else:
		press_up("key")


func _input(event: InputEvent) -> void:
	var j := event as InputEventJoypadButton
	if j == null or not InputBindings.matches(j, "pad_sand") or not is_available():
		return
	if j.pressed:
		if not _overlay_busy():
			press_down("pad")
	else:
		press_up("pad")


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f is LineEdit or f is TextEdit


## Una finestra della schermata principale è aperta (MainScreen non passa i tasti alle scorciatoie).
func _overlay_busy() -> bool:
	var n: Node = self
	while n != null:
		var ov: Variant = n.get("_overlay")
		if ov is OverlayHost:
			return (ov as OverlayHost).is_busy()
		n = n.get_parent()
	return false


# ------------------------------------------------------------------ eventi

func _release_all() -> void:
	_down.clear()
	_toggle_on = false
	_acc = 0.0


func _on_setting(key: String, _v: Variant) -> void:
	if not key.begins_with("push_"):
		return
	if key == "push_assist":
		_toggle_on = false
		_acc = 0.0
	refresh()


func _on_push_changed(_cur: float, _cap: float) -> void:
	_since_refresh = REFRESH_S                  # l'aggiornamento vero lo fa _process a max 10 Hz


func _on_focus_changed(focused: bool) -> void:
	if not focused:
		_down.clear()                           # un tasto rilasciato fuori dalla finestra non resta «premuto»
