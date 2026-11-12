extends GameScreen
## Talenti (docs/06 §4, F10 = 06 §3.12): albero della classe (ramo Generale + un ramo per specializzazione, o il ramo unico delle ibride),
## punti da spendere, requisiti dei nodi, azzeramento. Solo presentazione: tutto passa da CombatSystem.build (HeroBuild).
## F10: il rango n/N sta DENTRO il nodo (niente pillola a parte), il testo del nodo (effetto, requisito, costo) si legge in UN solo
## riquadro di dettaglio per il nodo sotto il puntatore o col fuoco, il ramo non attivo è ridotto a icone, il banner «Hai speso tutti
## i punti» compare solo la prima volta. Animazioni a tween: rimbalzo del nodo quando sale di rango, respiro luminoso sui nodi acquistabili.

const NODE_SIZE := Vector2(300, 56)         # revisione grafica 1.0 (punto 20): nodi più grandi, in catena con la linea dei livelli
const TIER_W := 46.0                        # colonna dei requisiti (punti nel ramo) a sinistra di ogni nodo
const TIER_ROW_H := 68.0                    # altezza di una riga della catena: nodo + respiro per la linea che collega
const ICON_BTN := Vector2(40, 40)
const RESPEC_CONFIRM_MS := 4000
const SEEN_SPENT := "talents_spent"
## Nodo non ancora acquistabile: attenuato ma leggibile (con 0,38 il testo spariva sullo sfondo scuro).
const LOCKED_COL := Color(1, 1, 1, 0.72)
## Il testo disattivato del tema è troppo scuro sul fondo dei nodi: lo schiariamo (contrasto leggibile anche a nodo bloccato).
const LOCKED_FONT := Color(0.78, 0.8, 0.86)

var _combat: CombatSystem
var _build: HeroBuild
var _points_stat: ScreenKit.KitStat
var _spend_btn: Button
var _tiers: Array = []                   # [{mark: TierMark, branch, need}] per colorare la linea dei livelli sbloccati
var _class_label: Label
var _spec_label: Label
var _hint: Label
var _hint_bar: ScreenKit.KitHint
var _purpose: Label
var _respec_btn: Button
var _respec_reason: Label
var _respec_armed_until: int = 0
var _branches_box: HFlowContainer
var _nodes: Dictionary = {}              # id talento -> {button, state, icon: bool}
var _sig: String = ""
var _last_free: int = -1
var _spent_banner: bool = false          # il banner «punti spesi» è stato mostrato in questa visita
# riquadro di dettaglio condiviso
var _detail_id: String = ""
var _detail_sig: String = ""
var _d_name: Label
var _d_meta: Label
var _d_effect: Label
var _d_reason: Label


## Colonna dei requisiti di una catena di talenti: il numero di punti che servono nel ramo, un punto sulla linea e la linea che
## collega al livello prima e dopo (oro = livello sbloccato, grigio = ancora chiuso). Solo disegno.
class TierMark extends Control:
	var need: int = 0
	var is_first: bool = false
	var is_last: bool = false
	var open_here: bool = false
	var open_next: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(TIER_W, TIER_ROW_H)

	func set_state(here: bool, next: bool) -> void:
		if here != open_here or next != open_next:
			open_here = here
			open_next = next
			queue_redraw()

	func _draw() -> void:
		var x := size.x - 10.0
		var cy := size.y * 0.5
		var on_col := Color(ScreenKit.GOLD)
		var off_col := Color("#4d5365")
		if not is_first:
			draw_line(Vector2(x, 0.0), Vector2(x, cy), on_col if open_here else off_col, 3.0)
		if not is_last:
			draw_line(Vector2(x, cy), Vector2(x, size.y), on_col if open_next else off_col, 3.0)
		draw_circle(Vector2(x, cy), 6.0, on_col if open_here else off_col)
		var font := get_theme_font("font", "Label")
		var txt := str(need)
		var fs := UiType.NOTE
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(x - 14.0 - w, cy + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(ScreenKit.TEXT_DIM) if not open_here else on_col)


## Nodo ridotto: icona (facoltativa) e titolo con il rango («Fendente  2/3»). Un pulsante trasparente sopra riceve clic, mouse e fuoco.
## Stessa interfaccia di ScreenKit.PickRow (ButtonGroup, `pressed`, `disabled`, `set_card`), ma 5 controlli invece di 8-10.
class TalentNode extends ScreenKit.PickRow:
	func build(title: String, accent_col: Color, icon_tex: Texture2D) -> void:
		custom_minimum_size = Vector2(0, NODE_SIZE.y)
		_normal = ScreenKit.card_style(Color(ScreenKit.EDGE), 3)
		_hover_style = ScreenKit.card_style(accent_col.darkened(0.3), 3, true)
		_sel_style = ScreenKit.card_style(accent_col, 5, true)
		var outer := HBoxContainer.new()
		outer.add_theme_constant_override("separation", 8)
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(outer)
		if icon_tex != null and icon_tex.get_width() <= 64:
			icon_l = TextureRect.new()
			icon_l.texture = icon_tex
			icon_l.custom_minimum_size = icon_tex.get_size()
			icon_l.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon_l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			outer.add_child(icon_l)
		title_l = Label.new()
		title_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title_l.text = title
		title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART        # i nomi lunghi vanno a capo, mai tagliati
		title_l.custom_minimum_size = Vector2(40, 0)
		title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(title_l)
		btn = Button.new()
		btn.flat = true
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			btn.add_theme_stylebox_override(st, empty)
		add_child(btn)
		btn.pressed.connect(func() -> void: pressed.emit())
		btn.mouse_entered.connect(func() -> void:
			_hovering = true
			_restyle())
		btn.mouse_exited.connect(func() -> void:
			_hovering = false
			_restyle())
		_restyle()


func open(_params: Dictionary) -> void:
	_combat = Game.system("combat") as CombatSystem
	_build = _combat.build
	_build_ui()
	_sig = ""
	refresh()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	outer.add_child(title_row)
	title_row.add_child(ScreenKit.title_style(CombatUi.label("UI_MENU_TALENTS", "TitleLabel")))
	_purpose = ScreenKit.muted(tr("UI_RS_TA_PURPOSE"))        # «a cosa serve»: alla prima visita, poi nel «?» (D17)
	HeroKit.help_button(title_row, _purpose, "talents", tr("UI_SCR_HERO_HELP_TIP"))
	outer.add_child(_purpose)
	ScreenKit.cap_text(_purpose)
	_hint_bar = ScreenKit.KitHint.new()
	_hint_bar.setup(ScreenKit.accent("talents"))
	outer.add_child(_hint_bar)
	var root := HBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	outer.add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	var card := ScreenKit.card(left, ScreenKit.accent("talents"), 4, true)
	_class_label = CombatUi.text_label("SectionLabel", true)
	card.add_child(_class_label)
	_spec_label = CombatUi.text_label("MutedLabel", true)
	card.add_child(_spec_label)
	_points_stat = ScreenKit.stat(card, "UI_RS_TA_ST_POINTS", "UI_RS_TA_TIP_POINTS")
	_points_stat.value_l.add_theme_font_size_override("font_size", UiType.NUMBER_HERO)      # i punti liberi: il numero più grande della pagina
	_spend_btn = Button.new()
	_spend_btn.name = "SpendBtn"
	_spend_btn.theme_type_variation = &"AccentButton"
	_spend_btn.text = tr("UI_GSA_TAL_SPEND")
	_spend_btn.pressed.connect(_on_spend)
	card.add_child(_spend_btn)
	_hint = CombatUi.text_label("MutedLabel", true)          # la regola dei punti è nel suggerimento in alto e nel riquadro di dettaglio
	_hint.visible = false
	card.add_child(_hint)
	_respec_btn = Button.new()
	_respec_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_respec_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # la colonna sinistra resta stretta: due rami affiancati
	_respec_btn.pressed.connect(_on_respec)
	left.add_child(_respec_btn)
	_respec_reason = ScreenKit.reason_label()
	left.add_child(_respec_reason)
	# UN solo riquadro di dettaglio: il nodo sotto il puntatore o col fuoco (non una riga di testo per nodo)
	var dv := ScreenKit.card(left, Color(ScreenKit.EDGE), 4, true)
	_d_name = CombatUi.text_label("SectionLabel", true)
	dv.add_child(_d_name)
	_d_meta = CombatUi.text_label("MutedLabel", true)
	dv.add_child(_d_meta)
	_d_effect = CombatUi.text_label("", true)
	dv.add_child(_d_effect)
	_d_reason = CombatUi.text_label("MutedLabel", true)
	dv.add_child(_d_reason)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # i rami vanno a capo: niente barra orizzontale nascosta
	root.add_child(scroll)
	_branches_box = HFlowContainer.new()
	_branches_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branches_box.add_theme_constant_override("h_separation", 10)
	_branches_box.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_branches_box)


## «Spendi»: porta il fuoco sul primo nodo acquistabile (e lo mostra nel riquadro di dettaglio).
func _on_spend() -> void:
	var id := _default_detail()
	if id.is_empty() or not _nodes.has(id):
		return
	_show_detail(id)
	var row: Variant = _nodes[id].button
	if row is ScreenKit.PickRow and (row as ScreenKit.PickRow).btn != null:
		((row as ScreenKit.PickRow).btn as Control).grab_focus()
	elif row is Control:
		(row as Control).grab_focus()


func _branch_ids() -> Array:
	var out: Array = []
	for t in _build.talent_nodes():
		if not out.has(str(t.branch)):
			out.append(str(t.branch))
	return out


func _branch_title(branch: String) -> String:
	match branch:
		"general":
			return tr("UI_C2_BRANCH_GENERAL")
		"hybrid":
			return tr("UI_C2_BRANCH_HYBRID")
	return Loc.t(DataRegistry.get_def("classes", branch).get("name", branch))


func _rebuild() -> void:
	CombatUi.clear_children(_branches_box)
	_nodes.clear()
	_tiers.clear()
	for branch in _branch_ids():
		var active := _build.branch_active(str(branch))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.custom_minimum_size = Vector2(TIER_W + NODE_SIZE.x if active else NODE_SIZE.x, 0)
		_branches_box.add_child(col)
		var head := CombatUi.text_label("SectionLabel")
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.text = _branch_title(str(branch)) if active else Loc.tf("UI_SCR_HERO_TAL_BRANCH_OFF", {"branch": _branch_title(str(branch))})
		head.mouse_filter = Control.MOUSE_FILTER_STOP
		head.tooltip_text = tr("UI_RS_TA_TIP_BRANCH_ON") if active else Loc.tf("UI_C2_TALENT_WHY_INACTIVE", {"spec": _branch_title(str(branch))})
		col.add_child(head)
		var nodes: Array = []
		for t in _build.talent_nodes():
			if str(t.branch) == branch:
				nodes.append(t)
		nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index))
		var flow: HFlowContainer = null
		if not active:                       # ramo non attivo: solo icone (il dettaglio compare al passaggio del mouse)
			flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 4)
			flow.add_theme_constant_override("v_separation", 4)
			col.add_child(flow)
		for i in nodes.size():
			var t: Dictionary = nodes[i]
			var id := str(t.id)
			if active:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 0)
				col.add_child(line)
				var mark := TierMark.new()
				mark.need = int(t.requires_points_in_branch)
				mark.is_first = i == 0
				mark.is_last = i == nodes.size() - 1
				line.add_child(mark)
				var row := TalentNode.new()
				row.build(Loc.t(t.name), ScreenKit.accent("talents"), IconLib.icon("talents", id))
				row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.custom_minimum_size = Vector2(NODE_SIZE.x, NODE_SIZE.y)
				row.pressed.connect(_on_node.bind(id))
				row.btn.mouse_entered.connect(_show_detail.bind(id))
				row.btn.focus_entered.connect(_show_detail.bind(id))
				line.add_child(row)
				_nodes[id] = {"button": row, "state": "", "icon": false}
				_tiers.append({"mark": mark, "branch": str(branch), "need": int(t.requires_points_in_branch),
					"next": int((nodes[i + 1] as Dictionary).requires_points_in_branch) if i + 1 < nodes.size() else -1})
			else:
				var b := Button.new()
				b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				b.icon = IconLib.icon("talents", id)
				b.custom_minimum_size = ICON_BTN
				b.text = "" if b.icon != null else Loc.t(t.name).left(2)
				b.expand_icon = false
				b.pressed.connect(_on_node.bind(id))
				b.mouse_entered.connect(_show_detail.bind(id))
				b.focus_entered.connect(_show_detail.bind(id))
				flow.add_child(b)
				_nodes[id] = {"button": b, "state": "", "icon": true}
	if not _nodes.has(_detail_id):
		_detail_id = _default_detail()
	_detail_sig = ""


## Nodo mostrato quando il mouse non è su nessun nodo: il primo acquistabile, altrimenti il primo del ramo attivo.
func _default_detail() -> String:
	var first := ""
	for t in _build.talent_nodes():
		var id := str(t.id)
		if not _nodes.has(id) or bool(_nodes[id].icon):
			continue
		if first.is_empty():
			first = id
		if _build.why_not(id).is_empty():
			return id
	return first


## Cosa dà il talento, in una riga («Vita massima +5 per rango»): il numero conta, non il nome.
func _effect_line(t: Dictionary) -> String:
	var parts := PackedStringArray()
	for m in t.modifiers_per_rank:
		parts.append(BonusSummary.effect_text(m))
	return ", ".join(parts) + " " + tr("UI_RS_TA_PER_RANK")


func refresh() -> void:
	if _combat == null:
		return
	var sig := "%s|%s" % [str(_combat.state.class), str(_combat.state.spec)]
	if sig != _sig:
		_sig = sig
		_rebuild()
	var cd := _combat.class_def()
	_class_label.text = Loc.t(cd.get("name", ""))
	var spec := str(_combat.state.spec)
	_spec_label.text = tr("UI_C2_SPEC_NONE_SHORT") if spec.is_empty() else Loc.t(DataRegistry.get_def("classes", spec).get("name", spec))
	var free := _build.points_free()
	_points_stat.set_value(str(free), "/ %d" % _build.points_total())
	_points_stat.set_color(Color(ScreenKit.GOLD) if free > 0 else Color(ScreenKit.TEXT_DIM))
	if _last_free >= 0 and free != _last_free:
		CombatUi.pop(_points_stat, 1.12)
	_last_free = free
	_spend_btn.visible = free > 0
	_hint.text = tr("UI_C2_TALENT_HINT") if _build.points_total() > 0 else tr("UI_C2_TALENT_NO_POINTS_YET")
	var cost := _build.respec_cost()
	var armed := Time.get_ticks_msec() < _respec_armed_until
	if armed:
		_respec_btn.text = tr("UI_C2_RESPEC_CONFIRM")
	elif cost == 0:
		_respec_btn.text = tr("UI_C2_RESPEC_FREE")
	else:
		_respec_btn.text = Loc.tf("UI_C2_RESPEC_COST", {"gold": NumberFormat.fmt(cost)})
	var why_respec := ""
	if _combat.in_combat():
		why_respec = tr("UI_C2_SPEC_NOT_IN_COMBAT")
	elif _combat.state.talents.is_empty():
		why_respec = tr("UI_RS_TA_WHY_NO_TALENTS")
	ScreenKit.gate(_respec_btn, why_respec, _respec_reason)
	# «non hai speso nessun punto» non è un errore: nota neutra, non rossa (revisione grafica 1.0, punto 20)
	_respec_reason.add_theme_color_override("font_color", Color(ScreenKit.TEXT_DIM) if _combat.state.talents.is_empty() else Color(ScreenKit.BAD))
	if why_respec == "":
		_respec_btn.tooltip_text = tr("UI_C2_RESPEC_TIP")
	_refresh_hint(free)
	for t in _build.talent_nodes():
		_refresh_node(t, free)
	for e in _tiers:                          # linea dei livelli: oro finché i punti spesi nel ramo bastano al requisito
		var spent := _build.points_spent(str(e.branch))
		(e.mark as TierMark).set_state(spent >= int(e.need), int(e.next) >= 0 and spent >= int(e.next))
	_refresh_detail()


func _refresh_hint(free: int) -> void:
	_hint_bar.visible = true
	if _build.points_total() <= 0:
		_hint_bar.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_TA_H_NONE_YET"), tr("UI_RS_GO_COMBAT") if ScreenKit.available("combat") else "", ScreenKit.target("combat"))
	elif free > 0:
		_hint_bar.show_hint(ScreenKit.Kind.TODO, Loc.tf("UI_RS_TA_H_FREE", {"n": free}))
	elif _spent_banner or not HeroKit.seen(SEEN_SPENT):
		# «Hai speso tutti i punti»: solo la prima volta (poi resta in vista finché la schermata è aperta, ma non nelle visite dopo)
		_spent_banner = true
		HeroKit.mark_seen(SEEN_SPENT)
		_hint_bar.show_hint(ScreenKit.Kind.OK, tr("UI_RS_TA_H_SPENT"))
	else:
		_hint_bar.visible = false


func _refresh_node(t: Dictionary, free: int) -> void:
	var id := str(t.id)
	var entry: Dictionary = _nodes.get(id, {})
	if entry.is_empty():
		return
	var rank := _build.rank(id)
	var why := _build.why_not(id)
	var maxr := int(t.max_rank)
	var can := why.is_empty()
	var state_now := "%d|%s|%d|%s" % [rank, why, free, Loc.locale()]
	var shown_col := Color.WHITE if (can or rank > 0) and _build.branch_active(str(t.branch)) else LOCKED_COL
	if bool(entry.icon):                       # ramo non attivo: icona con il rango nel tooltip breve
		var ib: Button = entry.button
		ib.disabled = false
		ib.modulate = LOCKED_COL if rank == 0 else Color.WHITE
		if state_now != str(entry.state):
			entry["state"] = state_now
			ib.tooltip_text = "%s  %d/%d" % [Loc.t(t.name), rank, maxr]
		return
	var b: ScreenKit.PickRow = entry.button
	b.disabled = rank == 0 and not why.is_empty()
	b.modulate = shown_col
	if state_now != str(entry.state):
		var was_rank := int(str(entry.state).split("|")[0]) if not str(entry.state).is_empty() else rank
		entry["state"] = state_now
		CombatUi.glow(b, can)
		if rank > was_rank:
			CombatUi.pop(b, 1.1)
		# stato visibile a colpo d'occhio: bordo dorato = acquistabile, verde = al massimo, accento = con ranghi, grigio = bloccato
		var edge := Color(ScreenKit.EDGE)
		if rank >= maxr:
			edge = Color("#5f8f5f")
		elif can:
			edge = Color("#d2b574")
		elif rank > 0:
			edge = ScreenKit.accent("talents").darkened(0.2)
		b.set_card(edge, can)
		# il rango n/N è dentro il nodo, nel titolo
		b.title_l.text = Loc.tf("UI_SCR_HERO_TAL_NODE", {"name": Loc.t(t.name), "rank": rank, "max": maxr})
		var col := Color(ScreenKit.GOOD) if rank >= maxr else (Color(ScreenKit.GOLD) if rank > 0 else Color(LOCKED_FONT))
		b.title_l.add_theme_color_override("font_color", col)


# ------------------------------------------------------------------ riquadro di dettaglio condiviso

func _show_detail(id: String) -> void:
	if _detail_id == id:
		return
	_detail_id = id
	_refresh_detail()


## Nome, rango e costo, effetto per rango, requisito mancante del nodo sotto il puntatore (uno solo per tutta la schermata).
func _refresh_detail() -> void:
	var t := _build.talent_def(_detail_id) if not _detail_id.is_empty() else {}
	if t.is_empty():
		_d_name.text = tr("UI_SCR_HERO_TAL_DETAIL_HINT")
		_d_meta.text = ""
		_d_effect.text = ""
		_d_reason.text = ""
		_d_meta.visible = false
		_d_effect.visible = false
		_d_reason.visible = false
		return
	var rank := _build.rank(_detail_id)
	var why := _build.why_not(_detail_id)
	var sig := "%s|%d|%s|%d|%s" % [_detail_id, rank, why, _build.points_free(), Loc.locale()]
	if sig == _detail_sig:
		return
	_detail_sig = sig
	_d_name.text = Loc.t(t.name)
	_d_meta.visible = true
	_d_meta.text = Loc.tf("UI_SCR_HERO_TAL_META", {"rank": rank, "max": int(t.max_rank)})
	var lines := PackedStringArray()
	for m in t.modifiers_per_rank:
		lines.append(BonusSummary.effect_text(m))
	_d_effect.visible = true
	_d_effect.text = tr("UI_C2_TALENT_PER_RANK") + "\n" + "\n".join(lines)
	var reason := ""
	if why.is_empty():
		reason = tr("UI_SCR_HERO_TAL_CLICK_BUY")
	else:
		reason = _why_text(t, why)
	if why != "inactive" and not _build.branch_active(str(t.branch)):
		reason = Loc.tf("UI_C2_TALENT_WHY_INACTIVE", {"spec": _branch_title(str(t.branch))}) + ("\n" + reason if not why.is_empty() else "")
	_d_reason.visible = true
	_d_reason.text = reason


func _why_text(t: Dictionary, why: String) -> String:
	return Loc.tf("UI_C2_TALENT_WHY_" + why.to_upper(), {"need": int(t.requires_points_in_branch),
		"spent": _build.points_spent(str(t.branch)), "spec": _branch_title(str(t.branch))})


## Testo completo di un nodo (per i test e per chi lo vuole in un solo pezzo).
func _node_tip(t: Dictionary, rank: int, why: String) -> String:
	var lines: PackedStringArray = []
	for m in t.modifiers_per_rank:
		lines.append(BonusSummary.effect_text(m))
	var tip := tr("UI_C2_TALENT_PER_RANK") + "\n" + "\n".join(lines)
	if rank > 0:
		tip += "\n" + Loc.tf("UI_C2_TALENT_NOW", {"n": rank})
	if why != "inactive" and not _build.branch_active(str(t.branch)):
		tip += "\n" + Loc.tf("UI_C2_TALENT_WHY_INACTIVE", {"spec": _branch_title(str(t.branch))})
	if not why.is_empty():
		tip += "\n" + _why_text(t, why)
	return tip


func _signed(v: float) -> String:
	return NumberFormat.fmt_signed(v)


func _on_node(id: String) -> void:
	_detail_id = id
	if _build.rank_up(id):
		refresh()
	else:
		var why := _build.why_not(id)
		if not why.is_empty():
			EventBus.notice.emit("info", Loc.tf("UI_C2_TALENT_WHY_" + why.to_upper(), {"need": int(_build.talent_def(id).get("requires_points_in_branch", 0)),
				"spent": _build.points_spent(str(_build.talent_def(id).get("branch", ""))), "spec": ""}), {})
		_refresh_detail()


func _on_respec() -> void:
	if _build.respec_cost() == 0:
		_build.respec()
		refresh()
		return
	if Time.get_ticks_msec() < _respec_armed_until:
		_respec_armed_until = 0
		if not _build.respec():
			EventBus.notice.emit("warning", tr("UI_C2_RESPEC_DENIED"), {})
	else:
		_respec_armed_until = Time.get_ticks_msec() + RESPEC_CONFIRM_MS
	refresh()
