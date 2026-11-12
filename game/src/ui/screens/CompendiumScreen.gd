extends GameScreen
## Compendio (docs/15, GUILD-2): Imprese, Titoli e cornici, Famigli, Collezioni. Solo presentazione: legge
## CompendiumSystem (Game.system("compendium")) e CrateSystem; le scelte (titolo, cornice, compagno) chiamano il sistema.
## Ogni scheda si ricostruisce solo quando cambia la sua firma; le barre delle imprese si aggiornano sul posto.

const TAB_ACH := 0
const TAB_TITLES := 1
const TAB_PETS := 2
const TAB_COLL := 3
const TAB_ITEMS := 4                     # UI-A G16: registro dei contenuti (viste dedicate, vedi Codex*View)
const TAB_MONSTERS := 5
const TAB_UNIQUES := 6
const TAB_TOTALS := 7
const TAB_COUNT := 8
const BAR_EVERY := 5                    # le barre delle imprese si ricalcolano ogni 5 refresh (≈ 2 Hz)
const ICON_PX := 36
const SIDE_PX := 150
const DONE_COLOR := Color(0.62, 0.85, 0.52)
const LOCKED_ALPHA := 0.62

var _comp: CompendiumSystem
var _codex: CodexSystem
var _views: Dictionary = {}              # indice scheda -> vista con refresh()
var _tabs: TabContainer
var _hint: ScreenKit.KitHint
var _st_title: ScreenKit.KitStat
var _st_pct: ScreenKit.KitStat
var _st_ach: ScreenKit.KitStat
var _st_pets: ScreenKit.KitStat
var _st_titles: ScreenKit.KitStat
var _ach_near: String = ""               # suggerimento «la più vicina», calcolato quando si ricostruisce la scheda Imprese
var _only_pending: bool = false
var _bodies: Array[VBoxContainer] = []
var _sigs: Array[String] = ["", "", "", "", "", "", "", ""]
var _filter: OptionButton
var _filter_cat: String = ""
var _bars: Array[Dictionary] = []        # {id, bar, label}
var _tick: int = 0
var _ach_gen: int = 0                    # annulla la costruzione a fette delle Imprese se la scheda viene ricostruita


func open(_params: Dictionary) -> void:
	_comp = Game.system("compendium") as CompendiumSystem
	_codex = Game.system("codex") as CodexSystem
	IntroOnce.title_row(self, tr("UI_MENU_COMPENDIUM"), "UI_RS_CO_PURPOSE" if _comp != null else "", "compendium")   # «a cosa serve»: solo alla prima visita (D17)
	if _comp == null:
		return
	_hint = ScreenKit.intro(self, "", "compendium")
	var stats := ScreenKit.stat_row(self)
	_st_title = ScreenKit.stat(stats, "UI_RS_CO_ST_TITLE", "UI_RS_CO_TIP_TITLE")
	_st_pct = ScreenKit.stat(stats, "UI_RS_CO_ST_PCT", "UI_RS_CO_TIP_PCT")
	_st_ach = ScreenKit.stat(stats, "UI_RS_CO_ST_ACH", "UI_RS_CO_TIP_ACH")
	_st_pets = ScreenKit.stat(stats, "UI_RS_CO_ST_PETS", "UI_RS_CO_TIP_PETS")
	_st_titles = ScreenKit.stat(stats, "UI_RS_CO_ST_TITLES", "UI_RS_CO_TIP_TITLES")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	for i in 4:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tabs.add_child(scroll)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 6)
		scroll.add_child(body)
		_bodies.append(body)
	_tabs.set_tab_title(TAB_ACH, tr("UI_GUILD2_TAB_ACH"))
	_tabs.set_tab_title(TAB_TITLES, tr("UI_GUILD2_TAB_TITLES"))
	_tabs.set_tab_title(TAB_PETS, tr("UI_GUILD2_TAB_PETS"))
	_tabs.set_tab_title(TAB_COLL, tr("UI_GUILD2_TAB_COLL"))
	if _codex != null:
		var iv := CodexItemsView.new()
		iv.setup(_codex, "items")
		_add_view(TAB_ITEMS, iv, "UI_UIA_TAB_ITEMS")
		var mv := CodexMonstersView.new()
		mv.setup(_codex)
		_add_view(TAB_MONSTERS, mv, "UI_UIA_TAB_MONSTERS")
		var uv := CodexItemsView.new()
		uv.setup(_codex, "uniques")
		_add_view(TAB_UNIQUES, uv, "UI_UIA_TAB_UNIQUES")
		var tv := CodexTotalsView.new()
		tv.setup(_codex)
		var tscroll := ScrollContainer.new()
		tscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tscroll.add_child(tv)
		_tabs.add_child(tscroll)
		_tabs.set_tab_title(TAB_TOTALS, tr("UI_UIA_TAB_TOTALS"))
		_views[TAB_TOTALS] = tv
	refresh()


func _add_view(index: int, view: Control, title_key: String) -> void:
	_tabs.add_child(view)
	_tabs.set_tab_title(index, tr(title_key))
	_views[index] = view


func refresh() -> void:
	if _comp == null or _tabs == null:
		return
	_tick += 1
	if _tick % BAR_EVERY == 1:             # la testata calcola il completamento su tutti gli oggetti: 2 Hz bastano (resoconto 100)
		_refresh_head()
	var cur := _tabs.current_tab
	_refresh_hint(cur)
	if _views.has(cur):
		_views[cur].refresh()
		return
	var sig := _signature(cur)
	if sig != _sigs[cur]:
		_sigs[cur] = sig
		match cur:
			TAB_ACH: _build_ach()
			TAB_TITLES: _build_titles()
			TAB_PETS: _build_pets()
			TAB_COLL: _build_coll()
	elif cur == TAB_ACH and _tick % BAR_EVERY == 0:
		_update_bars()


func _refresh_head() -> void:
	var t := _comp.title_line()
	_st_title.set_value(t if not t.is_empty() else tr("UI_GUILD2_NONE"), "")
	_st_title.value_l.add_theme_font_size_override("font_size", UiType.BODY)
	_st_pct.set_value(str(_codex.completion().pct_text) if _codex != null else "-", "")
	_st_ach.set_value("%d / %d" % [_comp.unlocked_count(), _comp.total_count()], "")
	_st_pets.set_value("%d / %d" % [_comp.pets_owned().size(), DataRegistry.table("pets").size()], "")
	_st_titles.set_value("%d / %d" % [_comp.owned_titles().size(), DataRegistry.table("titles").size()], "")


## «Cosa fare ora» in base alla scheda aperta.
func _refresh_hint(tab: int) -> void:
	match tab:
		TAB_ACH:
			if _ach_near != "":
				_hint.show_hint(ScreenKit.Kind.TODO, _ach_near)
			else:
				_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_CO_H_ACH"))
		TAB_TITLES:
			if _comp.owned_titles().is_empty():
				_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_CO_H_TITLES_NONE"))
			elif _comp.selected_title() == "":
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_CO_H_TITLES_WEAR"))
			else:
				_hint.show_hint(ScreenKit.Kind.OK, tr("UI_RS_CO_H_TITLES_OK"))
		TAB_PETS:
			if _comp.pets_owned().is_empty():
				_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_CO_H_PETS_NONE"))
			elif _comp.companion() == "":
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_CO_H_PETS_PICK"))
			else:
				_hint.show_hint(ScreenKit.Kind.OK, tr("UI_RS_CO_H_PETS_OK"))
		TAB_COLL:
			_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_CO_H_COLL"), tr("UI_GUILD2_COLL_OPEN_ALBUM") if ScreenKit.available("album") else "", ScreenKit.target("album"))
		_:
			_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_CO_H_CODEX"))


func _signature(tab: int) -> String:
	var base := "%s|%s" % [Loc.locale(), tab]
	match tab:
		TAB_ACH:
			return "%s|%d|%s|%s" % [base, _comp.unlocked_count(), _filter_cat, str(_only_pending)]
		TAB_TITLES:
			var cosm := ""
			if _codex != null:
				cosm = "%d|%s|%s" % [_codex.owned_cosmetics("banner").size() + _codex.owned_cosmetics("emblem").size(), _codex.selected("banner"), _codex.selected("emblem")]
			return "%s|%d|%s|%d|%s|%s" % [base, _comp.owned_titles().size(), _comp.selected_title(), (_comp.state.frames as Array).size(), _comp.selected_frame(), cosm]
		TAB_PETS:
			var d := 0
			for k in _comp.state.dupes:
				d += int(_comp.state.dupes[k])
			return "%s|%d|%d|%s" % [base, _comp.pets_owned().size(), d, _comp.companion()]
		TAB_COLL:
			var cr := Game.system("crates") as CrateSystem
			var n := 0
			if cr != null:
				for cid in cr.collection_ids():
					var p := cr.collection_progress(str(cid))
					n += int(p.owned) * 100 + int(p.relics_owned)
			return "%s|%d" % [base, n]
	return base


# ------------------------------------------------------------------ utilità di riga

func close() -> void:
	_ach_gen += 1


func _clear(i: int) -> void:
	for c in _bodies[i].get_children():
		c.queue_free()


## Spiegazione della scheda: una sezione richiudibile («Come funziona», chiusa di default, scelta ricordata), non prosa fissa.
func _help(body: Control, fold_id: String, text_key: String) -> void:
	var b := IntroOnce.fold(body, "compendium_" + fold_id, tr("UI_SCR_SUMMARY_HOW"))
	_label(b, tr(text_key), &"MutedLabel", false)


func _label(parent: Control, text: String, variation: StringName = &"", dynamic: bool = true) -> Label:
	var l := Label.new()
	if dynamic:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	parent.add_child(l)
	return l


## Riga a riquadro con bordo (verde = ottenuto, spento = da ottenere), icona 1:1 a sinistra, testo al centro e controlli a destra.
## Ritorna la colonna di testo e quella dei controlli.
func _row(body: Control, icon: Texture2D, dim: bool) -> Dictionary:
	var card := ScreenKit.card(body, Color(ScreenKit.EDGE) if dim else Color("#5f8f5f"), 4)
	var panel := ScreenKit.panel_of(card)
	if dim:
		panel.modulate.a = LOCKED_ALPHA
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var tr_icon := TextureRect.new()
	if icon != null:
		var w := icon.get_width()
		tr_icon.custom_minimum_size = Vector2(minf(w, 64.0), minf(w, 64.0)) if w <= 128 else Vector2(ICON_PX, ICON_PX)
	tr_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr_icon.texture = icon
	h.add_child(tr_icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_PX, 0)        # senza larghezza minima il testo a capo va lettera per lettera
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(side)
	return {"text": v, "side": side}


func _tex(path: String, kind: String, id: String) -> Texture2D:
	var t := IconLib.texture_at(path)
	return t if t != null else IconLib.icon(kind, id)


# ------------------------------------------------------------------ Imprese

func _build_ach() -> void:
	_ach_gen += 1
	var gen := _ach_gen
	_clear(TAB_ACH)
	_bars.clear()
	var body := _bodies[TAB_ACH]
	var top := HBoxContainer.new()
	body.add_child(top)
	var lb := _label(top, tr("UI_GUILD2_ACH_FILTER"), &"", false)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	_filter = OptionButton.new()
	_filter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_filter.add_item(tr("UI_GUILD2_CAT_ALL"))
	_filter.set_item_metadata(0, "")
	var sel := 0
	for cat in _comp.categories():
		_filter.add_item(tr("UI_GUILD2_CAT_" + str(cat).to_upper()))
		_filter.set_item_metadata(_filter.item_count - 1, str(cat))
		if str(cat) == _filter_cat:
			sel = _filter.item_count - 1
	_filter.select(sel)
	_filter.item_selected.connect(_on_filter)
	top.add_child(_filter)
	var pend := CheckBox.new()
	pend.text = "UI_RS_CO_ONLY_PENDING"
	pend.button_pressed = _only_pending
	pend.toggled.connect(func(on: bool) -> void:
		_only_pending = on
		_sigs[TAB_ACH] = "")
	top.add_child(pend)
	_help(body, "ach", "UI_GUILD2_ACH_HELP")
	var grid := GridContainer.new()                  # imprese a DUE colonne (una se stretto): righe da 1300 px con 800 px di vuoto
	grid.name = "AchGrid"
	grid.columns = 2 if _tabs.size.x >= 900.0 else 1
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	_tabs.resized.connect(func() -> void:
		if is_instance_valid(grid):
			grid.columns = 2 if _tabs.size.x >= 900.0 else 1)
	var rows: Array = []
	var near_ratio := -1.0
	_ach_near = ""
	for a in DataRegistry.table("achievements"):
		if not _filter_cat.is_empty() and str(a.category) != _filter_cat:
			continue
		var is_done := _comp.is_unlocked(str(a.id))
		if _only_pending and is_done:
			continue
		if not is_done and not bool(a.get("hidden", false)):
			var pr := _comp.ach_progress(str(a.id))
			var ratio := float(pr.cur) / maxf(1.0, float(pr.target))
			if ratio > near_ratio and ratio < 1.0:
				near_ratio = ratio
				_ach_near = Loc.tf("UI_RS_CO_H_ACH_NEAR", {"name": Loc.t(a.name), "cur": NumberFormat.fmt(int(pr.cur)), "target": NumberFormat.fmt(int(pr.target))})
		rows.append(a)
	var i := 0
	while i < rows.size():
		var stop := mini(rows.size(), i + GameScreen.ROWS_PER_SLICE) if GameScreen.sliced_builds else rows.size()
		while i < stop:
			_add_ach_row(grid, rows[i])
			i += 1
		if i < rows.size():                  # costruzione a fette (solo nel gioco vero): il resto al fotogramma dopo
			await get_tree().process_frame
			if not is_instance_valid(self) or not is_inside_tree() or gen != _ach_gen:
				return
	_update_bars()          # una volta sola dopo tutte le righe (prima era dentro ogni riga: costo quadratico, resoconto 100)


func _on_filter(idx: int) -> void:
	_filter_cat = str(_filter.get_item_metadata(idx))
	_sigs[TAB_ACH] = ""


func _add_ach_row(body: Control, a: Dictionary) -> void:
	var done := _comp.is_unlocked(str(a.id))
	var secret := bool(a.get("hidden", false)) and not done
	var icon := _tex(str(a.get("icon", "")) if done else str(a.get("icon_locked", "")), "achievements", str(a.id))
	var r := _row(body, icon, not done)
	var v: VBoxContainer = r.text
	var name_l := _label(v, tr("UI_GUILD2_ACH_HIDDEN_NAME") if secret else Loc.t(a.name), &"SectionLabel")
	if done:
		name_l.add_theme_color_override("font_color", DONE_COLOR)
	_label(v, tr("UI_GUILD2_ACH_HIDDEN_DESC") if secret else Loc.t(a.desc), &"MutedLabel")
	var rw := PackedStringArray()
	var reward: Dictionary = a.get("reward", {})
	if int(reward.get("stardust", 0)) > 0:
		rw.append(Loc.tf("UI_GUILD2_ACH_REWARD_DUST", {"n": int(reward.stardust)}))
	if str(reward.get("title", "")) != "":
		rw.append(Loc.tf("UI_GUILD2_ACH_REWARD_TITLE", {"name": Loc.t(DataRegistry.get_def("titles", str(reward.title)).get("name", reward.title))}))
	if not rw.is_empty() and not secret:
		_label(v, ", ".join(rw), &"MonoLabel")
	var side: VBoxContainer = r.side
	if done:
		_label(side, tr("UI_GUILD2_ACH_DONE"), &"", false).add_theme_color_override("font_color", DONE_COLOR)
	elif not secret:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 12)
		bar.add_theme_stylebox_override("fill", UiKit.tinted_fill(Color("#98a6ff")))
		side.add_child(bar)
		var lab := _label(side, "", &"MonoLabel")
		_bars.append({"id": str(a.id), "bar": bar, "label": lab})


func _update_bars() -> void:
	for b in _bars:
		var p := _comp.ach_progress(str(b.id))
		(b.bar as ProgressBar).max_value = maxf(1.0, float(p.target))
		(b.bar as ProgressBar).value = float(p.cur)
		(b.label as Label).text = "%s / %s" % [NumberFormat.fmt(int(p.cur)), NumberFormat.fmt(int(p.target))]


# ------------------------------------------------------------------ Titoli e cornici

func _build_titles() -> void:
	_clear(TAB_TITLES)
	var body := _bodies[TAB_TITLES]
	_help(body, "titles", "UI_GUILD2_TITLES_HELP")
	_label(body, tr("UI_GUILD2_TITLES_SECTION"), &"SectionLabel", false)
	var rows: Array = []
	var src := _title_sources()
	for t in DataRegistry.table("titles"):
		rows.append({"id": str(t.id), "name": Loc.t(t.name), "own": _comp.has_title(str(t.id))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.own != b.own:
			return a.own
		return str(a.name) < str(b.name))
	var locked_flow: HFlowContainer = null
	var n_owned := 0
	for t in rows:
		if t.own:
			n_owned += 1
	_label(body, Loc.tf("UI_RS_CO_TITLES_OWNED", {"n": n_owned}), &"MonoLabel")
	if n_owned == 0:
		ScreenKit.empty(body, tr("UI_RS_CO_TITLES_EMPTY"), tr("UI_RS_CO_TITLES_EMPTY_WHY"))
	for t in rows:
		if t.own:
			var r := _row(body, IconLib.icon("titles", str(t.id)), false)
			var v: VBoxContainer = r.text
			_label(v, str(t.name), &"SectionLabel")
			var wearing := _comp.selected_title() == str(t.id)
			if wearing:
				v.add_child(ScreenKit.pill(tr("UI_RS_CO_WORN"), Color(ScreenKit.GOLD)))
			var btn := Button.new()
			btn.text = "UI_GUILD2_TITLE_REMOVE" if wearing else "UI_GUILD2_TITLE_WEAR"
			if not wearing:
				btn.theme_type_variation = &"AccentButton"
			btn.pressed.connect(_on_wear.bind("" if wearing else str(t.id)))
			r.side.add_child(btn)
		else:
			if locked_flow == null:
				# «Da scoprire»: i titoli ancora da ottenere stanno in una sezione richiudibile (chiusa di default); il «come» è nel tooltip
				var lbody := IntroOnce.fold(body, "compendium_titles_locked", Loc.tf("UI_RS_CO_TITLES_LOCKED", {"n": rows.size() - n_owned}))
				(lbody.get_meta("fold_button") as Button).tooltip_text = tr("UI_RS_CO_TITLES_LOCKED_SUB")
				locked_flow = HFlowContainer.new()
				locked_flow.add_theme_constant_override("h_separation", 6)
				locked_flow.add_theme_constant_override("v_separation", 6)
				lbody.add_child(locked_flow)
			var how := str(src.get(str(t.id), ""))
			ScreenKit.chip(locked_flow, str(t.name), IconLib.icon("titles", str(t.id)), how if how != "" else tr("UI_RS_CO_TITLE_HOW_UNKNOWN"))
	_label(body, tr("UI_GUILD2_FRAMES_SECTION"), &"SectionLabel", false)
	_label(body, Loc.tf("UI_GUILD2_FRAMES_COUNT", {"n": (_comp.state.frames as Array).size(), "total": DataRegistry.table("frames").size()}), &"MutedLabel")
	for fid in _comp.state.frames:
		var fd := DataRegistry.get_def("frames", str(fid))
		var r2 := _row(body, IconLib.icon("frames", str(fid)), false)
		_label(r2.text, Loc.t(fd.get("name", fid)), &"SectionLabel")
		var using := _comp.selected_frame() == str(fid)
		var b2 := Button.new()
		b2.text = "UI_GUILD2_FRAME_REMOVE" if using else "UI_GUILD2_FRAME_USE"
		b2.pressed.connect(_on_frame.bind("" if using else str(fid)))
		r2.side.add_child(b2)
	_build_cosmetics(body)


## Stendardi ed Emblemi del profilo (UI-A G32): quelli ottenuti dalle Capsule si scelgono qui; la scelta compare nel Riepilogo.
func _build_cosmetics(body: Control) -> void:
	if _codex == null:
		return
	for kind in ["banner", "emblem"]:
		_label(body, tr("UI_UIA_COS_SECTION_" + kind.to_upper()), &"SectionLabel", false)
		var all := _codex.all_cosmetics(kind)
		var own := _codex.owned_cosmetics(kind)
		_label(body, Loc.tf("UI_UIA_COS_COUNT", {"n": own.size(), "total": all.size()}), &"MutedLabel")
		if own.is_empty():
			_label(body, tr("UI_UIA_COS_NONE_" + kind.to_upper()), &"MutedLabel", false)
			continue
		var cur := _codex.selected(kind)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		body.add_child(flow)
		for cid in own:
			var using := cur == str(cid)
			var b := Button.new()
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.custom_minimum_size = Vector2(150, 96)
			b.icon = CrateUi.def_icon(str(cid))
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.text = Loc.t(DataRegistry.item(str(cid)).get("name", cid)) + ("  ✓" if using else "")
			b.tooltip_text = tr("UI_UIA_COS_REMOVE") if using else tr("UI_UIA_COS_USE")
			b.toggle_mode = true
			b.set_pressed_no_signal(using)
			b.pressed.connect(_on_cosmetic.bind(kind, "" if using else str(cid)))
			flow.add_child(b)


func _on_cosmetic(kind: String, def_id: String) -> void:
	_codex.select(kind, def_id)
	_sigs[TAB_TITLES] = ""


func _on_wear(title_id: String) -> void:
	_comp.set_title(title_id)
	_sigs[TAB_TITLES] = ""


func _on_frame(frame_id: String) -> void:
	_comp.set_frame(frame_id)
	_sigs[TAB_TITLES] = ""


## Dove si ottiene ogni titolo, quando lo dicono i dati (impresa che lo concede). Vuoto = fonte non nei dati (missione, fazione…).
func _title_sources() -> Dictionary:
	var out := {}
	for a in DataRegistry.table("achievements"):
		var tid := str(a.get("reward", {}).get("title", ""))
		if tid != "":
			out[tid] = Loc.tf("UI_RS_CO_TITLE_HOW_ACH", {"name": Loc.t(a.name), "desc": Loc.t(a.desc)}) if not bool(a.get("hidden", false)) else tr("UI_RS_CO_TITLE_HOW_HIDDEN")
	return out


# ------------------------------------------------------------------ Famigli

func _build_pets() -> void:
	_clear(TAB_PETS)
	var body := _bodies[TAB_PETS]
	_help(body, "pets", "UI_GUILD2_PETS_HELP")
	var rows: Array = []
	for p in DataRegistry.table("pets"):
		rows.append(p)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := _comp.has_pet(str(a.id))
		var ob := _comp.has_pet(str(b.id))
		if oa != ob:
			return oa
		return str(Loc.t(a.name)) < str(Loc.t(b.name)))
	var n_own := 0
	for p in rows:
		if _comp.has_pet(str(p.id)):
			n_own += 1
	_label(body, Loc.tf("UI_RS_CO_PETS_OWNED", {"n": n_own}), &"MonoLabel")
	if n_own == 0:
		ScreenKit.empty(body, tr("UI_RS_CO_PETS_EMPTY"), tr("UI_RS_CO_PETS_EMPTY_WHY"))
	var shown_unknown := false
	var pets_locked_n := 0
	var locked_src: Dictionary = {}
	var locked_order: Array = []
	for p in rows:
		var own := _comp.has_pet(str(p.id))
		if own:
			var r := _row(body, IconLib.portrait("pets", str(p.id)), false)
			var v: VBoxContainer = r.text
			_label(v, Loc.t(p.name), &"SectionLabel")
			_label(v, Loc.t(p.get("desc", {})), &"MutedLabel")
			_label(v, CrateUi.mods_text(p.get("modifiers", [])), &"MonoLabel")
			var dupes := _comp.pet_dupes(str(p.id))
			if dupes > 0:
				_label(v, Loc.tf("UI_GUILD2_PET_DUPES", {"n": dupes}), &"MutedLabel")
			var cur := _comp.companion() == str(p.id)
			var btn := Button.new()
			btn.text = "UI_GUILD2_PET_COMPANION_ON" if cur else "UI_GUILD2_PET_COMPANION"
			btn.disabled = cur
			btn.tooltip_text = tr("UI_RS_CO_WHY_ALREADY_COMPANION") if cur else tr("UI_RS_CO_TIP_COMPANION")
			if not cur:
				btn.theme_type_variation = &"AccentButton"
			btn.pressed.connect(_on_companion.bind(str(p.id)))
			r.side.add_child(btn)
		else:
			if not shown_unknown:
				shown_unknown = true
				pets_locked_n = rows.size() - n_own
			var stext := _pet_source(p)
			if not locked_src.has(stext):
				locked_src[stext] = 0
				locked_order.append(stext)
			locked_src[stext] = int(locked_src[stext]) + 1
	# i famigli ancora da trovare con la stessa fonte si raggruppano: una riga con «×N», non N righe uguali.
	# «Da scoprire»: stanno in una sezione richiudibile (chiusa di default); ogni riga dice dove si trova il famiglio.
	var lock_body: Control = body
	if pets_locked_n > 0:
		lock_body = IntroOnce.fold(body, "compendium_pets_locked", Loc.tf("UI_RS_CO_PETS_LOCKED", {"n": pets_locked_n}))
		(lock_body.get_meta("fold_button") as Button).tooltip_text = tr("UI_RS_CO_PETS_LOCKED_SUB")
	for stext in locked_order:
		var c := ScreenKit.card(lock_body, Color(ScreenKit.EDGE), 3)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		c.add_child(ch)
		var q := Label.new()
		q.text = "?"
		q.add_theme_color_override("font_color", Color(ScreenKit.TEXT_DIM))
		ch.add_child(q)
		var sl := _label(ch, str(stext), &"MutedLabel")
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(locked_src[stext]) > 1:
			ch.add_child(ScreenKit.pill("×%d" % int(locked_src[stext]), Color(ScreenKit.WARN), tr("UI_RS_CO_TIP_SAME_SRC")))


func _on_companion(pet_id: String) -> void:
	_comp.set_companion(pet_id)
	_sigs[TAB_PETS] = ""


func _pet_source(p: Dictionary) -> String:
	var src: Dictionary = p.get("source", {})
	match str(src.get("type", "")):
		"skill_action":
			return Loc.tf("UI_GUILD2_PET_SRC_SKILL", {"skill": Loc.t(DataRegistry.get_def("skills", str(src.skill)).get("name", src.skill))})
		"monster":
			return Loc.tf("UI_GUILD2_PET_SRC_BOSS", {"name": Loc.t(DataRegistry.get_def("monsters", str(src.monster)).get("name", src.monster))})
		"raid":
			return Loc.tf("UI_GUILD2_PET_SRC_RAID", {"name": Loc.t(DataRegistry.get_def("raids", str(src.raid)).get("name", src.raid))})
		"crate_relic_pool":
			return Loc.tf("UI_GUILD2_PET_SRC_CRATE", {"name": Loc.t(DataRegistry.item(str(src.crate)).get("name", src.crate))})
		"event":
			return tr("UI_GUILD2_PET_SRC_EVENT")
	return ""


# ------------------------------------------------------------------ Collezioni

func _on_open_album() -> void:
	EventBus.screen_requested.emit("album", {})


func _build_coll() -> void:
	_clear(TAB_COLL)
	var body := _bodies[TAB_COLL]
	var cr := Game.system("crates") as CrateSystem
	_help(body, "coll", "UI_GUILD2_COLL_HELP")
	if cr == null:
		return
	var open_btn := Button.new()
	open_btn.text = "UI_GUILD2_COLL_OPEN_ALBUM"
	open_btn.pressed.connect(_on_open_album)
	body.add_child(open_btn)
	for cid in cr.collection_ids():
		var cdef := DataRegistry.get_def("collections", str(cid))
		var p := cr.collection_progress(str(cid))
		var r := _row(body, IconLib.icon("crates", str(cdef.get("crate", cid))), not bool(p.complete))
		var v: VBoxContainer = r.text
		var nm := _label(v, Loc.t(cdef.name), &"SectionLabel")
		if bool(p.golden):
			nm.add_theme_color_override("font_color", DONE_COLOR)
		_label(v, Loc.tf("UI_GUILD2_COLL_PROGRESS", {"owned": p.owned, "total": p.total, "relics": p.relics_owned, "relics_total": p.relics_total}), &"MonoLabel")
		_label(v, CrateUi.mods_text(cdef.complete_bonus.modifiers), &"MutedLabel")
		var state_key := "UI_GUILD2_COLL_GOLDEN" if bool(p.golden) else ("UI_GUILD2_COLL_COMPLETE" if bool(p.complete) else "UI_GUILD2_COLL_OPEN")
		_label(r.side, tr(state_key), &"", false)
