extends GameScreen
## Mercato di Vaelmora (docs/10 §3, docs/16): vendi dal Deposito con prezzo e tendenza, vendita di massa con
## anteprima, graficini disegnati con _draw. Nessuna logica di gioco: chiama MarketSystem.

var _mk: MarketSystem
var _ticker: Label
var _gold: Label
var _search: LineEdit
var _list: Tree
var _ids: Array = []
var _selected: String = ""
var _sig: int = 0
var _slow_n: int = 0
var _detail: Label
var _qty: SpinBox
var _preview: Label
var _pick_only: Array = []
var _chart_trend: MarketChart
var _chart_demand: MarketChart
var _mass_cat: OptionButton
var _mass_keep: SpinBox
var _mass_preview: Label
var _mass_btn: Button
var _mass_cats: Array = []
var _sell_btns: Array[Button] = []
var _empty_box: VBoxContainer
var _split: HSplitContainer


func open(_params: Dictionary) -> void:
	_mk = Game.system("market") as MarketSystem
	if _mk == null:
		var title := Label.new()
		ScreenKit.title_style(title)
		title.text = tr("UI_MENU_MARKET")
		add_child(title)
		var l := Label.new()
		l.text = tr("UI_MARKET_NO_SYSTEM")
		add_child(l)
		return
	VaultKit.header(self, "market", "UI_MENU_MARKET", "UI_MARKET_INTRO")
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 10)
	top.add_theme_constant_override("v_separation", 6)
	add_child(top)
	var chip := VaultKit.gold_chip(top)
	_gold = (chip.get_child(0) as Control).get_child(-1) as Label
	_ticker = Label.new()
	_ticker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticker.theme_type_variation = &"MutedLabel"
	_ticker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ticker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ticker.custom_minimum_size = Vector2(240, 0)
	top.add_child(_ticker)
	_empty_box = VBoxContainer.new()
	_empty_box.name = "EmptyBox"
	add_child(_empty_box)
	_empty_box.visible = false

	_split = HSplitContainer.new()
	var split := _split
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	split.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = tr("UI_MARKET_SEARCH")
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	left.add_child(_search)
	_list = Tree.new()                       # TABELLA: nome · quantità · prezzo · tendenza (colonne allineate, niente «…»)
	_list.name = "MarketTable"
	_list.columns = 4
	_list.column_titles_visible = true
	_list.hide_root = true
	_list.select_mode = Tree.SELECT_ROW
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("icon_max_width", 32)
	for c in 4:
		_list.set_column_title(c, tr(["UI_GB_MK_COL_ITEM", "UI_GB_MK_COL_QTY", "UI_GB_MK_COL_PRICE", "UI_GB_MK_COL_TREND"][c]))
		_list.set_column_expand(c, c == 0)
		_list.set_column_custom_minimum_width(c, [180, 64, 96, 52][c])
		_list.set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT if c == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
	_list.item_selected.connect(_on_pick)
	left.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	scroll.add_child(right)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_detail)
	var sec_trend := _section(tr("UI_MARKET_CHART_TREND"))
	right.add_child(sec_trend)
	_chart_trend = MarketChart.new()
	right.add_child(_chart_trend)
	var sec_demand := _section(tr("UI_MARKET_CHART_DEMAND"))
	right.add_child(sec_demand)
	_chart_demand = MarketChart.new()
	_chart_demand.line_color = Color(0.92, 0.72, 0.35)
	right.add_child(_chart_demand)
	var sec_sell := _section(tr("UI_MARKET_SELL"))
	right.add_child(sec_sell)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	right.add_child(row)
	_pick_only = [sec_trend, _chart_trend, sec_demand, _chart_demand, sec_sell, row]
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = 1000000000
	_qty.step = 1
	_qty.value = 1
	_qty.value_changed.connect(func(_v: float) -> void: _update_preview())
	row.add_child(_qty)
	_sell_btns.append(_button(row, tr("UI_MARKET_SELL_QTY"), _sell_qty))
	_sell_btns.append(_button(row, tr("UI_MARKET_SELL_ONE"), func() -> void: _sell(1)))
	_sell_btns.append(_button(row, tr("UI_MARKET_SELL_ALL"), func() -> void: _sell(_owned(_selected))))
	_preview = Label.new()
	_preview.theme_type_variation = &"MutedLabel"
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_preview)
	right.add_child(_section(tr("UI_MARKET_MASS")))
	var mi := Label.new()
	mi.text = tr("UI_MARKET_MASS_INTRO")
	mi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mi.theme_type_variation = &"MutedLabel"
	right.add_child(mi)
	var mrow := HFlowContainer.new()
	mrow.add_theme_constant_override("h_separation", 6)
	mrow.add_theme_constant_override("v_separation", 6)
	right.add_child(mrow)
	_mass_cat = OptionButton.new()
	_mass_cat.item_selected.connect(func(_i: int) -> void: _update_mass())
	mrow.add_child(_mass_cat)
	var kl := Label.new()
	kl.text = tr("UI_MARKET_KEEP")
	mrow.add_child(kl)
	_mass_keep = SpinBox.new()
	_mass_keep.min_value = 0
	_mass_keep.max_value = 1000000000
	_mass_keep.value_changed.connect(func(_v: float) -> void: _update_mass())
	mrow.add_child(_mass_keep)
	_mass_btn = _button(mrow, tr("UI_MARKET_MASS_GO"), _mass_sell)
	_mass_preview = Label.new()
	_mass_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_mass_preview)
	_fill_mass_cats()
	refresh()
	if _selected == "" and not _ids.is_empty():       # mai una schermata vuota: parte dal primo oggetto
		_selected = str(_ids[0])
		var first := _list.get_root().get_first_child()
		if first != null:
			first.select(0)
		_update_detail()


func _section(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"SectionLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _stacks() -> Dictionary:
	return GameState.data.get("bank", {}).get("stacks", {})


func _owned(def_id: String) -> int:
	return int(_stacks().get(def_id, 0))


func _fill_mass_cats() -> void:
	_mass_cats = [""]
	_mass_cat.clear()
	_mass_cat.add_item(tr("UI_MARKET_MASS_SAFE"))
	for c in _mk.categories():
		_mass_cats.append(c)
		_mass_cat.add_item(tr("UI_MARKET_CAT_" + str(c).to_upper()))


func refresh() -> void:
	if _mk == null or _list == null:
		return
	_gold.text = NumberFormat.fmt(GameState.gold())
	_ticker.text = _ticker_text()
	var h := hash([_stacks().hash(), int(_mk.game_time() / 60.0)])
	var changed := h != _sig
	if changed:
		_sig = h
		_rebuild_list()
	# anteprime (dettaglio con i grafici, vendita di massa su tutti gli stack): costose con un Deposito grande e cambiano solo
	# quando cambiano scorte o minuto di mercato; per sicurezza anche a 2 Hz (resoconto 100)
	_slow_n += 1
	if changed or _slow_n % 5 == 0:
		_update_detail()
		_update_mass()


func _ticker_text() -> String:
	var ev := _mk.active_gazette()
	if ev.is_empty():
		return tr("UI_MARKET_GAZETTE_QUIET")
	var parts := PackedStringArray()
	for e in ev:
		parts.append(Loc.t(e.text))
	return tr("UI_MARKET_GAZETTE") + " " + "  |  ".join(parts)


func _arrow(cat: String) -> String:
	var h: Array = _mk.trend_history(cat)
	if h.size() < 2:
		return "•"
	var d := float(h[-1]) - float(h[-2])
	return "▲" if d > 0.005 else ("▼" if d < -0.005 else "•")


func _rebuild_list() -> void:
	if _list == null:
		return
	var q := _search.text.strip_edges().to_lower()
	_list.clear()
	var troot := _list.create_item()
	_ids.clear()
	var entries: Array = []
	for k in _stacks():
		var qty := int(_stacks()[k])
		if qty <= 0 or not _mk.is_tradeable(str(k)):
			continue
		var nm := Loc.t(DataRegistry.item(str(k)).get("name", {}))
		if q != "" and not nm.to_lower().contains(q):
			continue
		entries.append([nm, str(k), qty])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e in entries:
		var cat := _mk.category_of(e[1])
		var ti := _list.create_item(troot)
		ti.set_icon(0, CrateUi.def_icon(e[1]))
		ti.set_text(0, str(e[0]))
		ti.set_text(1, "×" + NumberFormat.fmt(e[2]))
		ti.set_text(2, NumberFormat.fmt_unit(_mk.price_sell(e[1])))
		ti.set_text(3, _arrow(cat))
		ti.set_tooltip_text(2, tr("UI_GOLD"))
		for c in [1, 2, 3]:
			ti.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
		ti.set_metadata(0, _ids.size())
		_ids.append(e[1])
		if e[1] == _selected:
			ti.select(0)
	_show_empty(entries.is_empty() and q == "")


## Niente da vendere: invece di una lista vuota, spiega a cosa serve il Mercato e come si riempie il Deposito.
func _show_empty(on: bool) -> void:
	if _empty_box == null:
		return
	_split.visible = not on
	_empty_box.visible = on
	if on and _empty_box.get_child_count() == 0:
		var gos: Array = []
		var bank_e := ScreenRegistry.get_entry("bank")
		if not bank_e.is_empty():
			gos.append({"text": tr("UI_MENU_BANK"), "target": {"screen": "bank", "params": {}, "hint": ""}, "primary": false})
		var q := ScreenRegistry.get_entry("quests")
		if not q.is_empty():
			gos.append({"text": tr("UI_MENU_QUESTS"), "target": {"screen": "quests", "params": {}, "hint": ""}, "primary": true})
		VaultKit.empty_card(_empty_box, IconLib.ui("ui_currency_gold"), tr("UI_VUX_MK_EMPTY_TITLE"), tr("UI_VUX_MK_EMPTY_WHAT"),
			PackedStringArray([tr("UI_VUX_MK_STEP_1"), tr("UI_VUX_MK_STEP_2")]), gos)


func _on_pick() -> void:
	var it := _list.get_selected()
	if it == null:
		return
	_selected = str(_ids[int(it.get_metadata(0))])
	_update_detail()


func _update_detail() -> void:
	var has := _selected != "" and _mk.is_tradeable(_selected)
	for b in _sell_btns:
		b.disabled = not has or _owned(_selected) <= 0
	for c in _pick_only:
		(c as Control).visible = has
	if not has:
		_detail.text = tr("UI_MARKET_PICK")
		_chart_trend.set_values([])
		_chart_demand.set_values([])
		_preview.text = ""
		return
	var cat := _mk.category_of(_selected)
	var it: Dictionary = DataRegistry.item(_selected)
	var wait_h := _mk.hours_to_recover(_selected, 0.9)
	_detail.text = Loc.tf("UI_MARKET_DETAIL" if wait_h >= 0.5 else "UI_MARKET_DETAIL_FRESH", {
		"name": Loc.t(it.get("name", {})), "own": NumberFormat.fmt(_owned(_selected)),
		"price": NumberFormat.fmt_unit(_mk.price_sell(_selected)), "base": NumberFormat.fmt(float(it.value)),
		"trend": NumberFormat.fmt_pct((_mk.trend(cat) - 1.0) * 100.0),
		"demand": NumberFormat.fmt_pct(_mk.demand(_selected) * 100.0),
		"tax": NumberFormat.fmt_pct(_mk.tax_rate(_selected) * 100.0),
		"wait": NumberFormat.fmt(wait_h)})
	_chart_trend.set_values(_mk.trend_history(cat), 1.0)
	var pts: Array = []
	for hh in 25:
		pts.append(_mk.demand_in(_selected, float(hh)))
	_chart_demand.set_values(pts, 1.0)
	_update_preview()


func _update_preview() -> void:
	if _mk == null or _selected == "":
		return
	var q := mini(int(_qty.value), _owned(_selected))
	var g := _mk.quote_sell(_selected, q)
	_preview.text = Loc.tf("UI_MARKET_PREVIEW", {"qty": NumberFormat.fmt(q), "gold": NumberFormat.fmt(g),
		"avg": NumberFormat.fmt(float(g) / maxf(1.0, float(q)))})


func _sell_qty() -> void:
	_sell(int(_qty.value))


func _sell(qty: int) -> void:
	if _selected == "" or qty <= 0:
		return
	var n := mini(qty, _owned(_selected))
	var g := _mk.sell(_selected, n)
	EventBus.notice.emit("success", Loc.tf("UI_MARKET_SOLD", {"qty": NumberFormat.fmt(n),
		"name": Loc.t(DataRegistry.item(_selected).get("name", {})), "gold": NumberFormat.fmt(g)}), {})
	_sig = 0
	refresh()


func _mass_entries() -> Array:
	var cat: String = _mass_cats[_mass_cat.selected] if _mass_cat.selected >= 0 else ""
	var keep := int(_mass_keep.value)
	var out: Array = []
	for k in _stacks():
		var id := str(k)
		var qty := int(_stacks()[k]) - keep
		if qty <= 0 or not _mk.is_tradeable(id) or _mk.category_of(id) == "":
			continue
		var icat := str(DataRegistry.item(id).get("category", ""))
		if cat == "" and (MarketSystem.CRATE_ITEM_CATEGORIES.has(icat) or icat == "equipment"):
			continue      # "Tutto il sicuro" lascia stare equipaggiamento e oggetti da cassa
		if cat != "" and _mk.category_of(id) != cat:
			continue
		out.append({"id": id, "qty": qty})
	return out


func _update_mass() -> void:
	if _mass_preview == null:
		return
	var es := _mass_entries()
	var pieces := 0
	for e in es:
		pieces += int(e.qty)
	_mass_btn.disabled = es.is_empty()
	if es.is_empty():
		_mass_preview.text = tr("UI_MARKET_MASS_NONE")
	else:
		_mass_preview.text = Loc.tf("UI_MARKET_MASS_PREVIEW", {"kinds": es.size(), "pieces": NumberFormat.fmt(pieces),
			"gold": NumberFormat.fmt(_mk.quote_many(es))})


func _mass_sell() -> void:
	var es := _mass_entries()
	var g := _mk.sell_many(es)
	EventBus.notice.emit("success", Loc.tf("UI_MARKET_MASS_DONE", {"kinds": es.size(), "gold": NumberFormat.fmt(g)}), {})
	_sig = 0
	refresh()
