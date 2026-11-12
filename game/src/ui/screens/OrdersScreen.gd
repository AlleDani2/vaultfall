extends GameScreen
## Commesse dei PNG e Fazioni (docs/10 §4 e §6): bacheca con consegna/rifiuto, reputazione e gradi.
## La bacheca si ricostruisce solo quando cambia (firma degli id); i numeri si aggiornano a ogni refresh().

var _mk: MarketSystem
var _gold: Label
var _next: Label
var _board: VBoxContainer
var _factions: GridContainer
var _scroll: ScrollContainer
var _sig: String = ""
var _cards: Dictionary = {}       # order_id -> {have: Label, deliver: Button, left: Label}
var _frows: Dictionary = {}       # faction_id -> {rank: Label, bar: ProgressBar, next: Label}


func open(_params: Dictionary) -> void:
	_mk = Game.system("market") as MarketSystem
	if _mk == null:
		var title := Label.new()
		ScreenKit.title_style(title)
		title.text = tr("UI_MENU_ORDERS")
		add_child(title)
		return
	VaultKit.header(self, "orders", "UI_MENU_ORDERS", "UI_ORDERS_INTRO")
	if not _mk.orders_enabled():                      # Autarchica: bacheca spenta, Fazioni e reputazione restano
		var off := Label.new()
		off.text = tr("UI_MODES_ORDERS_OFF")
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		off.theme_type_variation = &"SectionLabel"
		add_child(off)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 10)
	top.add_theme_constant_override("v_separation", 6)
	add_child(top)
	var chip := VaultKit.gold_chip(top)
	_gold = (chip.get_child(0) as Control).get_child(-1) as Label
	_next = Label.new()
	_next.theme_type_variation = &"MutedLabel"
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next.custom_minimum_size = Vector2(240, 0)
	top.add_child(_next)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll
	scroll.resized.connect(_fit_cols)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	var h1 := Label.new()
	h1.theme_type_variation = &"SectionLabel"
	h1.text = tr("UI_ORDERS_BOARD")
	col.add_child(h1)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 6)
	col.add_child(_board)
	var h2 := Label.new()
	h2.theme_type_variation = &"SectionLabel"
	h2.text = tr("UI_ORDERS_FACTIONS")
	col.add_child(h2)
	_factions = GridContainer.new()                    # fazioni a DUE colonne (una se stretto): niente barre larghe come la pagina
	_factions.name = "FactionGrid"
	_factions.columns = 2
	_factions.add_theme_constant_override("h_separation", 8)
	_factions.add_theme_constant_override("v_separation", 8)
	_factions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_factions)
	for fid in _mk.faction_ids():
		_add_faction_row(str(fid))
	_fit_cols()
	refresh()


func _fit_cols() -> void:
	if _scroll == null:
		return
	var cols := 2 if _scroll.size.x >= 900.0 else 1
	if _factions != null and _factions.columns != cols:
		_factions.columns = cols
	for g in _board.find_children("OrderGrid", "GridContainer", true, false):
		(g as GridContainer).columns = cols


func _add_faction_row(fid: String) -> void:
	var f: Dictionary = DataRegistry.get_def("factions", fid)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_factions.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var icon := VaultKit.pix(IconLib.icon("factions", fid), 1)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_l := Label.new()
	name_l.text = Loc.t(f.get("name", {}))
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.x = 120
	v.add_child(name_l)
	var d := Label.new()
	d.theme_type_variation = &"MutedLabel"
	d.text = Loc.t(f.get("desc", {}))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 120
	v.add_child(d)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	var next := Label.new()
	next.theme_type_variation = &"MutedLabel"
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(next)
	var rank := Label.new()
	rank.theme_type_variation = &"MonoLabel"
	rank.custom_minimum_size = Vector2(140, 0)
	h.add_child(rank)
	_frows[fid] = {"rank": rank, "bar": bar, "next": next}


func refresh() -> void:
	if _mk == null or _board == null:
		return
	_gold.text = NumberFormat.fmt(GameState.gold())
	_next.text = Loc.tf("UI_ORDERS_NEXT", {"t": NumberFormat.fmt_time(_mk.next_refresh_in()),
		"slots": _mk.order_slots()})
	var ids := PackedStringArray()
	for o in _mk.orders():
		ids.append(str(o.id))
	var sig := ",".join(ids)
	if sig != _sig:
		_sig = sig
		_rebuild_board()
	var stacks: Dictionary = GameState.data.get("bank", {}).get("stacks", {})
	for o in _mk.orders():
		var c: Dictionary = _cards.get(str(o.id), {})
		if c.is_empty():
			continue
		var have := int(stacks.get(str(o.item), 0))
		var short := have < int(o.qty)
		(c.have as Label).text = Loc.tf("UI_MSK_ORDER_SHORT" if short else "UI_ORDERS_HAVE", {"have": NumberFormat.fmt(have), "qty": NumberFormat.fmt(int(o.qty)),
			"miss": NumberFormat.fmt(maxi(0, int(o.qty) - have))})
		(c.deliver as Button).disabled = have < int(o.qty)
		(c.have as Label).add_theme_color_override("font_color", FxPalette.AMBER if have < int(o.qty) else FxPalette.GREEN)
		(c.deliver as Button).tooltip_text = ReqText.missing_sentence(str(o.item), int(o.qty), have) if have < int(o.qty) else ""
		(c.left as Label).text = Loc.tf("UI_ORDERS_EXPIRES", {"t": NumberFormat.fmt_time(maxf(0.0, float(o.expires_t) - _mk.game_time()))})
	for fid in _frows:
		_update_faction(str(fid))


func _rebuild_board() -> void:
	for ch in _board.get_children():
		ch.queue_free()
	_cards.clear()
	var list := _mk.orders()
	if list.is_empty():
		VaultKit.empty_card(_board, IconLib.ui("ui_currency_commission_token"), tr("UI_VUX_OR_EMPTY_TITLE"), tr("UI_VUX_OR_EMPTY_WHAT"),
			PackedStringArray([tr("UI_VUX_OR_EMPTY_STEP")]), [])
		return
	var grid := GridContainer.new()
	grid.name = "OrderGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_child(grid)
	for o in list:
		grid.add_child(_make_card(o))
	_fit_cols()


func _make_card(o: Dictionary) -> Control:
	var it: Dictionary = DataRegistry.item(str(o.item))
	var fdef: Dictionary = DataRegistry.get_def("factions", str(o.faction))
	var npc: Dictionary = DataRegistry.get_def("npcs", str(o.npc))
	var panel := VaultKit.card(FxPalette.GOLD_D)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var icon := VaultKit.pix(CrateUi.def_icon(str(o.item)), 2)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var ask := Label.new()
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask.text = Loc.tf("UI_ORDERS_ASK", {"npc": Loc.t(npc.get("name", {})), "qty": NumberFormat.fmt(int(o.qty)),
		"item": Loc.t(it.get("name", {}))})
	v.add_child(ask)
	var rew := Label.new()
	rew.theme_type_variation = &"MutedLabel"
	rew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var crate_txt := ""
	if str(o.get("crate", "")) != "":
		crate_txt = Loc.tf("UI_ORDERS_CRATE", {"crate": Loc.t(DataRegistry.item(str(o.crate)).get("name", {}))})
	rew.text = Loc.tf("UI_ORDERS_REWARD", {"gold": NumberFormat.fmt(int(o.gold)), "rep": int(o.rep),
		"faction": Loc.t(fdef.get("name", {})), "crate": crate_txt})
	v.add_child(rew)
	var have := Label.new()
	have.theme_type_variation = &"MonoLabel"
	v.add_child(have)
	var left := Label.new()
	left.theme_type_variation = &"MutedLabel"
	v.add_child(left)
	var src := ReqLink.target_for_item(str(o.item))
	if not src.is_empty():
		v.add_child(ReqLink.link(tr("UI_VUX_WHERE_ITEM"), src))
	var btns := VBoxContainer.new()               # «Consegna» (primaria) sopra «Rifiuta» (secondaria)
	btns.add_theme_constant_override("separation", 6)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(btns)
	var deliver := Button.new()
	deliver.text = tr("UI_ORDERS_DELIVER")
	deliver.theme_type_variation = &"AccentButton"
	deliver.custom_minimum_size = Vector2(120, 40)
	deliver.pressed.connect(_deliver.bind(str(o.id)))
	btns.add_child(deliver)
	var reject := Button.new()
	reject.text = tr("UI_ORDERS_REJECT")
	reject.custom_minimum_size = Vector2(120, 36)
	reject.tooltip_text = tr("UI_ORDERS_REJECT_TIP")
	reject.pressed.connect(_reject.bind(str(o.id)))
	btns.add_child(reject)
	_cards[str(o.id)] = {"have": have, "deliver": deliver, "left": left}
	return panel


func _deliver(order_id: String) -> void:
	if _mk.complete_order(order_id):
		EventBus.notice.emit("success", tr("UI_ORDERS_DONE"), {})
	refresh()


func _reject(order_id: String) -> void:
	_mk.reject_order(order_id)
	refresh()


func _update_faction(fid: String) -> void:
	var f: Dictionary = DataRegistry.get_def("factions", fid)
	var ranks: Array = f.get("ranks", [])
	var rep := _mk.reputation(fid)
	var idx := _mk.rank_index(fid)
	var r: Dictionary = _frows[fid]
	(r.rank as Label).text = Loc.t(ranks[idx].name)
	var bar := r.bar as ProgressBar
	var next_label := r.next as Label
	if idx + 1 < ranks.size():
		var lo := float(ranks[idx].rep)
		var hi := float(ranks[idx + 1].rep)
		bar.min_value = lo
		bar.max_value = hi
		bar.value = rep
		next_label.text = Loc.tf("UI_ORDERS_NEXT_RANK", {"rep": NumberFormat.fmt(rep), "need": NumberFormat.fmt(hi),
			"rank": Loc.t(ranks[idx + 1].name), "reward": _reward_text(f, str(ranks[idx + 1].id))})
	else:
		bar.min_value = 0
		bar.max_value = 1
		bar.value = 1
		next_label.text = Loc.tf("UI_ORDERS_MAX_RANK", {"rep": NumberFormat.fmt(rep)})


func _reward_text(f: Dictionary, rank_id: String) -> String:
	for rw in f.get("rank_rewards", []):
		if str(rw.rank) == rank_id:
			var parts := PackedStringArray()
			for m in rw.get("modifiers", []):
				parts.append(CrateUi.mod_text(m))      # "descrizione [ambito]: +N", come nel Guardaroba (prima: "-% della tassa (10)")
			return ", ".join(parts)
	return ""
