class_name TutorialDirector
extends CanvasLayer
## Tutorial guidato: strato sopra l'interfaccia che oscura leggermente lo schermo, mette in risalto il controllo giusto
## (cornice dorata che pulsa + freccia) e mostra una scheda breve con «Avanti», «Più tardi» e «Salta il tutorial».
## Non blocca il gioco: lo schermo è cliccabile ovunque tranne che nei due passi "premi proprio questo" (Pino e Rame), dove
## solo il controllo evidenziato risponde (e «Salta questo passo» sblocca sempre).
##
## Logica dei passi: TutorialSystem (stato nel salvataggio) + TutorialCatalog (i passi). Qui solo presentazione.
## Regole di buona educazione: un passo alla volta; niente mentre è aperta una finestra (benvenuto, Bentornato, schede);
## niente durante combattimenti rischiosi; «Più tardi» lo riporta dopo un po'; se il controllo non esiste il passo si salta.

const POLL_S := 0.25
const GAP_GUIDE_S := 0.6
const GAP_FEATURE_S := 5.0
const LATER_S := 120.0
const MISSING_S := 1.5
const SHOW_AFTER_MISSING_S := 0.35
const BLOCKED_HINT_S := 3.0
const CARD_W := 380.0
const ARROW_GAP := 30.0
const MARGIN := 10.0
const TITLE_PX := 18
const RISK_HP_FRAC := 0.5
const BIG_FRACTION := 0.30                 # un bersaglio più grande di così (es. tutta la schermata) non si circonda di frecce

var _main: Control                          # MainScreen
var _overlay: OverlayHost
var _ts: TutorialSystem
var _step: Dictionary = {}
var _forced: bool = false
var _gap: float = 0.0
var _poll: float = 0.0
var _missing: float = 0.0
var _prepped: bool = false
var _screen_seen: String = ""
var _later_until: Dictionary = {}           # id passo -> secondo (tempo reale) in cui può tornare
var _skipped: Dictionary = {}               # passi saltati in questa sessione perché il controllo mancava
var _hl_key: String = ""                    # chiave del controllo evidenziato ora
var _allow: Array = []                      # zone dove i clic passano anche nei passi «premi proprio questo» (il «Vai» dell'Obiettivo)
var _popup_t: float = 0.0
var _dragging: bool = false                 # la scheda si può trascinare dove non copre: playtest novizio 121 (copriva gli slot dell'Eroe)
var _drag_off: Vector2 = Vector2.ZERO
var _drag_note_done: bool = false         # l'avviso «si può trascinare» compare una volta sola nella sessione (niente tooltip al passaggio del mouse)
var _user_pos: Variant = null               # posizione scelta dal giocatore (Vector2) finché dura il passo
var _popup_open: bool = false
var _blocked_s: float = 0.0                 # secondi in cui mostrare «premi il pulsante evidenziato» dopo un clic fermato

var _spot: TutorialSpotlight
var _blockers: Array[Control] = []
var _card: PanelContainer
var _title: Label
var _body: Label
var _hint: Label
var _prog: Label
var _next: Button
var _later: Button
var _skip_step: Button
var _skip_all: Button


func _init(main: Control = null, overlay: OverlayHost = null) -> void:
	name = "TutorialDirector"
	layer = 40
	_main = main
	_overlay = overlay


func _ready() -> void:
	_ts = Game.system("tutorial") as TutorialSystem
	_build()
	visible = false
	if _ts != null:
		_ts.begin()
	set_process(_ts != null)


# ------------------------------------------------------------------ interfaccia pubblica (anche per i test)

func current_step_id() -> String:
	return str(_step.get("id", ""))


func is_showing() -> bool:
	return not _step.is_empty() and visible


func highlighted_key() -> String:
	return _hl_key


func highlight_rect() -> Rect2:
	return _spot.hole if _spot.has_hole else Rect2()


func is_blocking() -> bool:
	return not _step.is_empty() and _blockers[0].mouse_filter == Control.MOUSE_FILTER_STOP and _blockers[0].visible


## «Avanti»: il passo si dà per visto.
func press_next() -> void:
	if _step.is_empty():
		return
	_finish(true)


## «Più tardi»: il passo torna dopo un po' (o alla prossima sessione).
func press_later() -> void:
	if _step.is_empty():
		return
	_later_until[current_step_id()] = Time.get_ticks_msec() / 1000.0 + LATER_S
	_clear()


## «Salta il tutorial»: nessun suggerimento automatico finché non si riattiva dalla Guida.
func press_skip_all() -> void:
	if _ts != null:
		_ts.set_off(true)
	Settings.set_value("tutorials", false)      # anche le vecchie schede «Novità» di 3 righe: chi salta non vuole finestre di tutorial (playtest novizio 121)
	_clear()
	EventBus.notice.emit("info", tr("UI_TUT_SKIPPED"), {})


## «Salta questo passo» (passi "premi proprio questo"): lo dà per visto e si va avanti.
func press_skip_step() -> void:
	if _step.is_empty():
		return
	_finish(true)


## «Mostrami» dalla Guida: ripropone un passo già sbloccato (anche se visto). false se non è ancora disponibile.
func show_step(step_id: String) -> bool:
	if _ts == null or not _ts.available(step_id):
		return false
	_begin(TutorialCatalog.get_step(step_id), true)
	return true


## Riparte da capo (dalla Guida o dalle Impostazioni).
func restart() -> void:
	if _ts == null:
		return
	_ts.reset()
	Settings.set_value("tutorials", true)
	_later_until.clear()
	_skipped.clear()
	_clear()
	_gap = 0.0


func dismiss() -> void:
	_clear()


# ------------------------------------------------------------------ costruzione

func _build() -> void:
	_spot = TutorialSpotlight.new()
	add_child(_spot)
	for i in 4:
		var b := TutorialBlocker.new()
		b.name = "TutorialBlocker%d" % i
		b.visible = false
		b.allow = _allow
		b.blocked.connect(_on_blocked_click)
		add_child(b)
		_blockers.append(b)
	_card = PanelContainer.new()
	_card.name = "TutorialCard"
	_card.theme_type_variation = &"ContentPanel"
	_card.custom_minimum_size.x = CARD_W
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_on_card_input)
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_card.add_child(v)
	_title = _label(v, &"TitleLabel")
	_title.name = "TutorialTitle"
	_title.add_theme_font_size_override("font_size", TITLE_PX)
	_body = _label(v, &"")
	_body.name = "TutorialBody"
	_hint = _label(v, &"SectionLabel")
	_hint.name = "TutorialHint"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_next = _button(row, "UI_TUT_NEXT", true, press_next)
	_next.name = "TutorialNext"
	_skip_step = _button(row, "UI_TUT_SKIP_STEP", false, press_skip_step)
	_skip_step.name = "TutorialSkipStep"
	_later = _button(row, "UI_TUT_LATER", false, press_later)
	_later.name = "TutorialLater"
	_prog = _label(v, &"MutedLabel")
	_prog.name = "TutorialProgress"
	_skip_all = Button.new()
	_skip_all.name = "TutorialSkipAll"
	_skip_all.text = "UI_TUT_SKIP_ALL"
	_skip_all.flat = true
	_skip_all.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_skip_all.pressed.connect(press_skip_all)
	v.add_child(_skip_all)


func _label(parent: Control, variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _button(parent: Control, key: String, accent: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	if accent:
		b.theme_type_variation = &"AccentButton"
	b.pressed.connect(action)
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ scelta del passo

func _process(dt: float) -> void:
	# anche il banner «Missione completata» (2 s, sopra il tutorial) ha la precedenza: prima copriva il titolo della scheda
	_popup_t -= dt
	if _popup_t <= 0.0:
		_popup_t = POLL_S
		_popup_open = _any_dialog_open()
	var busy := (_overlay != null and _overlay.is_busy()) or Fx.banner_active() or _popup_open
	if _step.is_empty():
		visible = false
		_gap -= dt
		_poll -= dt
		if _poll <= 0.0 and _gap <= 0.0 and not busy:
			_poll = POLL_S
			_try_pick()
		return
	visible = not busy
	if busy:
		return
	_update_step(dt)


## Una finestra di dialogo (es. «Non sei pronto a combattere») è aperta: è esclusiva, i clic sulla scheda non le arriverebbero
## mai (R6c del rapporto 95), quindi la scheda aspetta che si risponda.
func _any_dialog_open() -> bool:
	for w in get_tree().root.find_children("*", "AcceptDialog", true, false):
		if (w as Window).visible:
			return true
	return false


func _auto_enabled() -> bool:
	return _ts != null and _ts.active() and bool(Settings.get_value("tutorials"))


func _excluded() -> Dictionary:
	var ex := _skipped.duplicate()
	var now := Time.get_ticks_msec() / 1000.0
	for k in _later_until.keys():
		if float(_later_until[k]) > now:
			ex[k] = true
	return ex


func _try_pick() -> void:
	if not _auto_enabled():
		return
	var s := _ts.next_step(_excluded())
	if s.is_empty():
		return
	if str(s.cat) != "guide" and _risky():
		return
	if _ts.should_skip(s):
		_ts.mark_seen(str(s.id))
		_poll = 0.0
		return
	_begin(s, false)


## Mai un suggerimento mentre si rischia: dungeon, incursioni, boss, o vita bassa in combattimento.
func _risky() -> bool:
	var c := Game.system("combat") as CombatSystem
	if c == null or not c.in_combat():
		return false
	if c.in_dungeon() or not c.endgame_mode().is_empty():
		return true
	return c.hp() < c.max_hp() * RISK_HP_FRAC


func _begin(step: Dictionary, forced: bool) -> void:
	_step = step
	_forced = forced
	_user_pos = null
	_dragging = false
	_missing = 0.0
	_prepped = false
	_screen_seen = ""
	_hl_key = ""
	_hint.visible = false
	var sid := str(step.id)
	var data: Object = DataRegistry
	_title.text = tr(TutorialCatalog.title_key(sid))
	_body.text = Loc.tf(TutorialCatalog.body_key(sid), TutorialSystem.text_params(sid, data))
	var c := _ts.counts()
	_prog.text = Loc.tf("UI_TUT_PROGRESS", {"seen": c.seen, "total": c.total})
	if not _drag_note_done:
		_drag_note_done = true
		_prog.text += "  ·  " + tr("UI_TUT_DRAG_TIP")
	var act := _is_act()
	_next.visible = not act
	_skip_step.visible = act
	_card.modulate.a = 1.0
	_card.visible = false
	if bool(step.get("goto", false)):
		var scr := str(step.get("screen", ""))
		if not scr.is_empty() and _main.get("current_id") != scr:
			_main.call("show_screen", scr)
	_spot.calm = bool(Settings.get_value("reduce_motion"))
	if not _spot.calm:
		_card.modulate.a = 0.0
		_card.create_tween().tween_property(_card, "modulate:a", 1.0, 0.2)
	visible = true


func _is_act() -> bool:
	return str(_step.get("mode", "ack")) == "act" and not _forced


func _clear() -> void:
	var was_guide := str(_step.get("cat", "")) == "guide"
	_step = {}
	_hl_key = ""
	_spot.has_hole = false
	_spot.arrow_side = ""
	for b in _blockers:
		b.visible = false
	_card.visible = false
	visible = false
	_gap = GAP_GUIDE_S if was_guide else GAP_FEATURE_S


func _finish(seen: bool) -> void:
	var sid := current_step_id()
	if seen and _ts != null and not sid.is_empty():
		_ts.mark_seen(sid)
	_clear()
	_poll = 0.0


# ------------------------------------------------------------------ passo in corso

func _current_screen_id() -> String:
	return str(_main.get("current_id")) if _main != null and _main.get("current_id") != null else ""


func _is_done() -> bool:
	var d: Dictionary = _step.get("done", {})
	if d.has("screen"):
		return _current_screen_id() == str(d.screen)
	if d.has("action"):
		var sk := Game.system("skills") as SkillSystem
		return sk != null and sk.current_action() == str(d.action)
	return false


## Chiavi del controllo da evidenziare adesso: quelle del passo se si è sulla sua schermata, altrimenti il menù per arrivarci.
func _keys_now() -> Array:
	var screen := str(_step.get("screen", ""))
	var keys := TutorialCatalog.targets_of(_step)
	if screen.is_empty() or _current_screen_id() == screen:
		return keys
	var out: Array = []
	for k in keys:
		var ks := str(k)
		if ks == "sidebar" or ks.begins_with("topbar:") or ks.begins_with("menu:"):
			out.append(ks)
	var menu := "menu:" + screen
	if not out.has(menu):
		out.append(menu)
	return out


func _update_step(dt: float) -> void:
	if _is_act() and _is_done():
		_finish(true)
		return
	if not _forced and _ts.should_skip(_step):
		_finish(true)
		return
	var cur := _current_screen_id()
	if cur != _screen_seen:
		_screen_seen = cur
		_prepped = false
	var screen := str(_step.get("screen", ""))
	if not _prepped and (screen.is_empty() or cur == screen):
		_prepped = true
		_prepare()
	var keys := _keys_now()
	var hit := TutorialTargets.find_any(get_tree(), keys)
	var vs := _spot.size
	if keys.is_empty():                     # passo senza bersaglio: scheda al centro
		_hint.visible = false
		_apply_hole(Rect2(), false, "")
		_place_card(Rect2(), false, vs)
		return
	if hit.is_empty():
		_missing += dt
		_card.visible = _missing > SHOW_AFTER_MISSING_S and _forced
		if _missing > MISSING_S:
			_on_missing(vs)
		return
	_missing = 0.0
	var node: Control = hit.node
	_hl_key = str(hit.key)
	TutorialTargets.reveal(node)
	var r := node.get_global_rect().grow(5.0)
	_apply_hole(r, true, "")
	_hint.text = Loc.tf("UI_TUT_HINT_MENU", {"menu": TutorialSystem.menu_name(screen, DataRegistry)}) if _hl_key.begins_with("menu:") and _hl_key != _first_key() else ""
	if _blocked_s > 0.0:
		_blocked_s -= dt
		_hint.text = tr("UI_TUT_BLOCKED")
	_hint.visible = not _hint.text.is_empty()
	_place_card(r, true, vs)


func _first_key() -> String:
	var ks := TutorialCatalog.targets_of(_step)
	return str(ks[0]) if not ks.is_empty() else ""


func _prepare() -> void:
	var prep := str(_step.get("prep", ""))
	if prep.is_empty() or _main == null:
		return
	var scr: Variant = _main.call("current_screen")
	if scr != null and (scr as Object).has_method("tut_prepare"):
		(scr as Object).call("tut_prepare", prep)


## Il controllo non c'è: un passo "forzato" mostra la scheda senza evidenziazione; gli altri vengono saltati.
func _on_missing(vs: Vector2) -> void:
	if _forced:
		_apply_hole(Rect2(), false, "")
		_place_card(Rect2(), false, vs)
		return
	var sid := current_step_id()
	if str(_step.get("cat", "")) == "guide":
		_ts.mark_seen(sid)
	else:
		_skipped[sid] = true
	_clear()
	_poll = 0.0


## Un clic fermato dal bloccante: la scheda ricorda cosa premere (il gioco non resta muto).
func _on_blocked_click() -> void:
	_blocked_s = BLOCKED_HINT_S


func _apply_hole(r: Rect2, has: bool, side: String) -> void:
	_spot.has_hole = has
	_spot.hole = r
	_spot.arrow_side = side
	var strict := has and _is_act()
	var vs := _spot.size
	_allow.clear()
	if strict:
		# i «Vai» (Obiettivo attuale e schermata Missioni) portano nello stesso posto del passo: restano cliccabili
		for key in ["goal_go", "quest_go"]:
			for n in get_tree().get_nodes_in_group(TutorialTargets.GROUP_PREFIX + key):
				var vai := n as Button
				if vai != null and vai.is_visible_in_tree() and not vai.disabled and vai.size.x > 1.0:
					_allow.append(vai.get_global_rect())
		var rects := [Rect2(0, 0, vs.x, maxf(0.0, r.position.y)), Rect2(0, r.end.y, vs.x, maxf(0.0, vs.y - r.end.y)),
			Rect2(0, r.position.y, maxf(0.0, r.position.x), r.size.y), Rect2(r.end.x, r.position.y, maxf(0.0, vs.x - r.end.x), r.size.y)]
		for i in 4:
			var b := _blockers[i]
			b.visible = true
			b.position = (rects[i] as Rect2).position
			b.size = (rects[i] as Rect2).size
	else:
		for b in _blockers:
			b.visible = false


## Mette la scheda accanto al bersaglio dove c'è posto (a destra, a sinistra, sotto, sopra) e orienta la freccia.
## Trascinare la scheda (clic sinistro tenuto sul suo sfondo): la posizione scelta resta fino alla fine del passo.
func _on_card_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			_drag_off = -mb.position                 # dove si è afferrata la scheda (coordinate locali)
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _dragging:
		var vs := _spot.size
		var bounds := Rect2(Vector2(MARGIN, MARGIN), vs - Vector2(MARGIN, MARGIN) * 2.0)
		_user_pos = _clamp_pos(_card.position + mm.position + _drag_off, _card.size, bounds)
		_card.position = _user_pos


func _place_card(hole: Rect2, has: bool, vs: Vector2) -> void:
	_card.visible = true
	_card.size = Vector2(CARD_W, 0.0)
	var cs := _card.get_combined_minimum_size()
	cs.x = maxf(cs.x, CARD_W)
	_card.size = cs
	var bounds := Rect2(Vector2(MARGIN, MARGIN), vs - Vector2(MARGIN, MARGIN) * 2.0)
	if _user_pos is Vector2:                     # l'ha spostata il giocatore: niente riposizionamento automatico (e niente freccia vicina)
		_card.position = _clamp_pos(_user_pos, cs, bounds)
		return
	var pos := (vs - cs) * 0.5
	var side := ""
	if has:
		var big := hole.size.x * hole.size.y > BIG_FRACTION * vs.x * vs.y
		if big:
			pos = Vector2(hole.end.x - cs.x - 18.0, hole.end.y - cs.y - 18.0)         # in basso a destra, dentro il bersaglio
		else:
			var wide := hole.size.x > hole.size.y * 1.5
			var order: Array = ["below", "above", "right", "left"] if wide else ["right", "left", "below", "above"]
			var found := false
			for s in order:
				var p := _candidate(str(s), hole, cs)
				if bounds.encloses(Rect2(p, cs)):
					pos = p
					side = str(s)
					found = true
					break
			if not found:                 # nessun posto pulito: il lato dove la scheda copre meno il bersaglio
				var best := INF
				for s in order:
					var p := _clamp_pos(_candidate(str(s), hole, cs), cs, bounds)
					var covered := Rect2(p, cs).intersection(hole).get_area()
					if covered < best:
						best = covered
						side = str(s)
						pos = p
	_card.position = _clamp_pos(pos, cs, bounds)
	if has and not side.is_empty():
		_spot.arrow_side = side


func _clamp_pos(pos: Vector2, cs: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - cs.x)),
		clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - cs.y)))


func _candidate(side: String, hole: Rect2, cs: Vector2) -> Vector2:
	match side:
		"right":
			return Vector2(hole.end.x + ARROW_GAP, hole.get_center().y - cs.y * 0.5)
		"left":
			return Vector2(hole.position.x - ARROW_GAP - cs.x, hole.get_center().y - cs.y * 0.5)
		"below":
			return Vector2(hole.get_center().x - cs.x * 0.5, hole.end.y + ARROW_GAP)
	return Vector2(hole.get_center().x - cs.x * 0.5, hole.position.y - ARROW_GAP - cs.y)
