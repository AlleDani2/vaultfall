class_name ActivityChip
extends TopCurrency
## L'attività in corso come UN solo controllo cliccabile della barra alta (D7, docs/ui_redesign/06 §3.2, risolve I5):
## icona · «Mansione · Azione» · barra sottile · «Liv N · tra X». Si accorcia prima il nome dell'azione, poi quello della
## mansione; il tempo al livello non si schiaccia mai (etichetta senza ritaglio) e l'icona resta. A riposo:
## «○ A riposo — scegli un'attività ▸» (clic = Riepilogo). In pausa: «❚❚ IN PAUSA» ambra davanti al nome. In combattimento: il
## numero di uccisioni al posto del tempo al livello. I nodi (Activity, ActivityBar, LevelEta) sono nella scena, con i nomi di
## sempre (test_skill_screen, MainScreen, FxDirector). Solo presentazione: legge SkillSystem, CombatSystem, Clock.

enum State { IDLE, RUN, PAUSED, WAITING }

const SEP := " · "
const MIN_ACTION_CHARS := 4
const MIN_SKILL_CHARS := 3
const ELLIPSIS := "…"
const COMBAT_ICON := "hero"
const BAR_W := 200              # rapporto 08 punto 11: l'attività è l'informazione più importante dell'idle, la barra si vede
const BAR_W_COMPACT := 56
const BAR_H := 8
const ICON_PX := 24
const ETA_COLOR := Color("#c9c5b4")      # tempo al livello: chiaro ma sotto il nome (6,9:1 sul fondo della barra)
const AMBER := Color("#e0a43a")

var compact: bool = false
var slim: bool = false                     # barra accorciata (la barra alta ha poco spazio) senza altre conseguenze
var bar_hidden: bool = false               # ultima risorsa: senza barra sottile (resta il tempo al livello)
## Larghezza che la barra alta può occupare per intero (la dà TopBar.fit; 0 = usa quella attuale del contenitore). Serve perché la
## larghezza attuale del contenitore può essere rimasta più grande del dovuto (un minimo largo la tiene aperta) e il nome,
## fidandosi di quella, non si restringerebbe mai: il minimo si autoalimenterebbe.
var width_cap: float = 0.0
var state: int = State.IDLE
var full_text: String = ""

var _icon: TopCurrency.Pic
var _tag: Label
var _name: Label
var _hint: Label
var _bar: SmoothBar
var _eta: Label
var _spacer: Control                       # spazio che si allarga DOPO il tempo al livello: nome, barra e tempo restano vicini
var _skill_txt: String = ""
var _action_txt: String = ""
var _fit_w: float = -1.0
var _is_combat: bool = false


func _ready() -> void:
	super._ready()
	var r := ensure_row()
	_icon = TopCurrency.as_pic(r.get_node("ActIcon") as Control)
	_tag = r.get_node("PausedTag") as Label
	_name = r.get_node("Activity") as Label
	_hint = r.get_node("IdleHint") as Label
	_bar = r.get_node("ActivityBar") as SmoothBar
	_eta = r.get_node("LevelEta") as Label
	clip_contents = true
	_tag.text = "UI_TOP_PAUSED"
	_tag.add_theme_color_override("font_color", AMBER)
	_tag.visible = false
	_hint.text = "UI_TOP_IDLE_HINT"
	_hint.theme_type_variation = &"MutedLabel"
	_hint.visible = false
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.custom_minimum_size.x = 0
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.resized.connect(_on_name_resized)
	row.resized.connect(_on_name_resized)
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_name.theme_type_variation = &"MonoLabel"               # nome nel colore del testo (non più grigio): è il primo dato della barra
	_eta.theme_type_variation = &"MonoLabel"
	_eta.add_theme_color_override("font_color", ETA_COLOR)
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_apply_bar_width()
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer = Control.new()
	_spacer.name = "ActSpacer"
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(_spacer)
	_eta.clip_text = false                                  # I5: il tempo al livello non si schiaccia mai
	_eta.size_flags_horizontal = Control.SIZE_SHRINK_END


## Modello dell'attività adesso (puro: serve ai test): {state, skill, action, icon, kills, combat, menu_id}.
static func model() -> Dictionary:
	var out := {"state": State.IDLE, "skill": "", "action": "", "icon": "", "kills": 0, "combat": false, "menu_id": ""}
	var sk := Game.system("skills") as SkillSystem
	var aid := sk.current_action() if sk != null else ""
	if not aid.is_empty():
		var sid := sk.skill_of(aid)
		out.skill = Loc.t(DataRegistry.get_def("skills", sid).get("name", {}))
		out.action = Loc.t(DataRegistry.action(aid).get("name", {}))
		out.icon = sid
		out.state = State.WAITING if sk.is_waiting() else State.RUN
	elif ActivityText.is_active():
		var cb := Game.system("combat") as CombatSystem
		out.skill = TranslationServer.translate("UI_TOP_COMBAT")
		out.action = ActivityText.combat_zone()
		out.icon = COMBAT_ICON
		out.combat = true
		out.kills = int(cb.run_summary().get("kills", 0)) if cb != null else 0
		out.state = State.RUN
	if Clock.paused and int(out.state) != State.IDLE:
		out.state = State.PAUSED
	out.menu_id = str(MenuActivity.main_mark().get("id", ""))
	return out


## Testo «Mansione · Azione» che entra in `avail` pixel: si accorcia PRIMA l'azione (fino a MIN_ACTION_CHARS), POI la mansione.
## Pura: font e dimensione arrivano da fuori. Se non entra comunque, ritorna la versione più corta (l'etichetta ritaglia).
static func fit_text(skill: String, action: String, avail: float, font: Font, font_size: int) -> String:
	var full := skill + SEP + action if not action.is_empty() else skill
	if avail <= 1.0 or font == null or font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= avail:
		return full
	var min_a := mini(action.length(), MIN_ACTION_CHARS)
	var n := action.length() - 1
	while n >= min_a and not action.is_empty():
		var cand := skill + SEP + action.left(n) + ELLIPSIS
		if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= avail:
			return cand
		n -= 1
	var short_action := (action.left(min_a) + ELLIPSIS) if not action.is_empty() else ""
	var m := skill.length() - 1
	var best := skill
	while m >= MIN_SKILL_CHARS:
		best = skill.left(m) + ELLIPSIS + (SEP + short_action if not short_action.is_empty() else "")
		if font.get_string_size(best, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= avail:
			return best
		m -= 1
	return best


## Nomi mostrati (mansione, azione): il testo si adatta alla larghezza disponibile. Pubblica per i test.
func set_names(skill: String, action: String) -> void:
	_skill_txt = skill
	_action_txt = action
	full_text = skill + (SEP + action if not action.is_empty() else "")
	_fit_w = -1.0
	_apply_name()


func set_compact(value: bool) -> void:
	compact = value
	_apply_bar_width()


## Barra sottile corta (BAR_W_COMPACT) quando la barra alta non ha spazio per quella intera.
func set_slim(value: bool) -> void:
	slim = value
	_apply_bar_width()


func set_bar_hidden(value: bool) -> void:
	if value == bar_hidden:
		return
	bar_hidden = value
	if _bar != null and value:
		_bar.visible = false
	elif _bar != null:
		_bar.visible = state != State.IDLE and not _is_combat


func _apply_bar_width() -> void:
	if _bar != null:
		_bar.custom_minimum_size.x = BAR_W_COMPACT if (compact or slim) else BAR_W


## Correzione alla larghezza minima del riquadro per il calcolo di TopBar.fit: il nome è l'unica parte che si restringe
## (ritaglio con «…»), quindi al posto del suo minimo attuale si conta il testo più corto che fit_text sa produrre.
func shrink_adjust() -> float:
	if _name == null or state == State.IDLE:
		return 0.0
	var f := _name.get_theme_font("font")
	var shortest := 0.0
	if f != null:
		var t := fit_text(_skill_txt, _action_txt, 2.0, f, _name.get_theme_font_size("font_size"))
		shortest = ceilf(f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _name.get_theme_font_size("font_size")).x)
	return shortest - _name.custom_minimum_size.x


func _on_name_resized() -> void:
	if absf(_avail_width() - _fit_w) > 0.5:
		_apply_name()


## Larghezza che resta al nome: la riga meno gli altri figli visibili (con i loro minimi) e le separazioni. Non dipende
## dalla larghezza attuale dell'etichetta, quindi è giusta già nello stesso fotogramma in cui cambia lo stato.
func _avail_width() -> float:
	var hb := get_parent() as HBoxContainer
	var hb_w := width_cap if width_cap > 1.0 else (hb.size.x if hb != null else 0.0)
	if hb == null or hb_w <= 1.0:
		return row.size.x
	# larghezza che la barra può dare a questo riquadro: NON dipende dal minimo del nome (che segue il testo), quindi non gira in tondo
	var others := 0.0
	var m := 0
	for c in hb.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		m += 1
		if ctl != self:
			others += ctl.get_combined_minimum_size().x
	var inner := hb_w - others - float(hb.get_theme_constant("separation")) * float(maxi(0, m - 1))
	var sb := get_theme_stylebox("panel")
	if sb != null:
		inner -= sb.get_minimum_size().x
	var used := 0.0
	var n := 0
	for c in row.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		n += 1
		if ctl != _name and ctl != _spacer:
			used += ctl.get_combined_minimum_size().x
	return inner - used - float(row.get_theme_constant("separation")) * float(maxi(0, n - 1))


## Rifà subito l'adattamento del nome (dopo che la barra ha cambiato gradino o larghezza).
func refit() -> void:
	_fit_w = -1.0
	_apply_name()


func _apply_name() -> void:
	_fit_w = _avail_width()
	if state == State.IDLE:
		_name.text = full_text                # a riposo il nome è corto e non si ritaglia mai
		_name.custom_minimum_size.x = 0
		return
	var txt := fit_text(_skill_txt, _action_txt, _fit_w, _name.get_theme_font("font"), _name.get_theme_font_size("font_size"))
	if _name.text != txt:
		_name.text = txt
	var f := _name.get_theme_font("font")
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _name.get_theme_font_size("font_size")).x if f != null else 0.0
	_name.custom_minimum_size.x = minf(ceilf(tw) + 2.0, maxf(0.0, _fit_w))       # mai oltre lo spazio possibile: il minimo non può spingere fuori la barra


## 10 Hz: stato, nomi, barra, tooltip. `menu_key` = tasto dell'attività (vuoto se non ne ha).
func refresh() -> void:
	if _name == null:
		return
	var m := model()
	state = int(m.state)
	var idle := state == State.IDLE
	_is_combat = bool(m.combat)
	_icon.ring = idle
	_icon.texture = null if idle else IconLib.icon("skills", str(m.icon))
	_hint.visible = idle and not compact
	# a riposo il nome è corto e il suggerimento gli sta accanto; in attività il nome occupa lo spazio e si ritaglia
	_name.clip_text = not idle
	_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if idle else TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_FILL                  # in attività la larghezza è quella del testo (ActSpacer assorbe il resto)
	_spacer.visible = not idle
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	_tag.visible = state == State.PAUSED
	_bar.visible = not idle and not bool(m.combat) and not bar_hidden
	if state == State.WAITING:
		_eta.text = TranslationServer.translate("UI_TOP_WAITING")
		_eta.visible = true
	elif bool(m.combat):
		var k := int(m.kills)
		_eta.text = Loc.tf("UI_TOP_KILLS_ONE" if k == 1 else "UI_TOP_KILLS", {"n": NumberFormat.fmt(k)})
		_eta.visible = true
	elif idle:
		_eta.text = ""
		_eta.visible = false
	set_names(str(TranslationServer.translate("UI_SKILLS_TOPBAR_IDLE")) if idle else str(m.skill), "" if idle else str(m.action))
	var sk := Game.system("skills") as SkillSystem
	var aid := sk.current_action() if sk != null else ""
	if not aid.is_empty() and not bool(m.combat):
		_bar.set_target(sk.cycle_fraction(), 1.0 / maxf(0.05, float(sk.profile_of(aid).cycle_s)))
	tooltip_text = _tooltip(idle, state == State.WAITING)


func _tooltip(idle: bool, waiting: bool) -> String:
	if idle:
		return TranslationServer.translate("UI_TOP_IDLE_TIP")
	var t := full_text + "\n" + TranslationServer.translate("UI_TOP_ACT_TIP")
	if waiting:
		t += "\n" + TranslationServer.translate("UI_SKILLS_WAITING_MATERIALS")
	return t


## 2 Hz: «Liv N · tra X» (solo per una mansione che rende XP, non in attesa né in combattimento).
func update_eta() -> void:
	if _eta == null:
		return
	if state == State.IDLE or state == State.WAITING:
		return
	if _is_combat:
		return
	var txt := LevelEta.short_text(LevelEta.info())
	_eta.text = txt
	_eta.visible = not txt.is_empty()
	_eta.tooltip_text = TranslationServer.translate("UI_UIB_ETA_TIP")
