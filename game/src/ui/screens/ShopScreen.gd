extends GameScreen
## Emporio (docs/10 §5): negozio fisso dai dati shop.json, acquisti con oro. Le righe si costruiscono una volta
## in open(); refresh() aggiorna solo testi e pulsanti.

const SECTIONS: Array[Dictionary] = [
	{"id": "upgrades", "title": "UI_SHOP_SEC_UPGRADES"},
	{"id": "bank", "title": "UI_SHOP_SEC_BANK"},
	{"id": "goods", "title": "UI_SHOP_SEC_GOODS"},
	{"id": "keys", "title": "UI_SHOP_SEC_KEYS"},
]

const INFO_MIN_W := 180.0          # larghezza minima dei testi di una carta (layout, non bilanciamento)
const GRID_TWO_COLS_W := 900.0     # sotto questa larghezza utile le carte vanno in una colonna sola
const SHOP_ICON := 2               # icona a scala intera: 2× il PNG da 32 px = 64 px

var _mk: MarketSystem
var _gold: Label
var _rows: Array[Dictionary] = []
var _grids: Array[GridContainer] = []
var _scroll: ScrollContainer


func open(_params: Dictionary) -> void:
	_mk = Game.system("market") as MarketSystem
	if _mk == null:
		var title := Label.new()
		ScreenKit.title_style(title)
		title.text = tr("UI_MENU_SHOP")
		add_child(title)
		return
	VaultKit.header(self, "shop", "UI_MENU_SHOP", "UI_SHOP_INTRO")
	if ModeRules.make(DataRegistry, GameState.mode()).market_buy_restricted():
		var note := Label.new()                       # Autarchica: perché quasi tutto è grigio
		note.text = tr("UI_MODES_SHOP_NOTE")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.theme_type_variation = &"SectionLabel"
		add_child(note)
	var chip := VaultKit.gold_chip(self)
	_gold = (chip.get_child(0) as Control).get_child(-1) as Label
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll
	scroll.resized.connect(_fit_grids)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	for sec in SECTIONS:
		var head := Label.new()
		head.theme_type_variation = &"SectionLabel"
		head.text = tr(sec.title)
		col.add_child(head)
		var grid := GridContainer.new()                    # carte a DUE colonne: icona 64 px, stato a pillola, prezzo e «Compra» in fondo
		grid.name = "ShopGrid_" + str(sec.id)
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(grid)
		_grids.append(grid)
		for e in _mk.shop_entries():
			if str(e.section) == sec.id:
				_add_row(grid, e)
	_fit_grids()
	refresh()


func _fit_grids() -> void:
	if _scroll == null:
		return
	var cols := 2 if _scroll.size.x >= GRID_TWO_COLS_W else 1
	for g in _grids:
		if g.columns != cols:
			g.columns = cols


func _add_row(parent: Container, e: Dictionary) -> void:
	var panel := VaultKit.card(FxPalette.GOLD_D)
	panel.name = "ShopRow_" + str(e.id)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var icon := VaultKit.pix(IconLib.icon("items", str(e.item)) if e.has("item") else IconLib.ui("shop_" + str(e.id)), SHOP_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(INFO_MIN_W, 0)
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)
	var name_l := Label.new()
	name_l.theme_type_variation = &"SectionLabel"
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.text = Loc.t(e.name) if e.has("name") else Loc.t(DataRegistry.item(str(e.item)).get("name", {}))
	info.add_child(name_l)
	var desc := Label.new()
	desc.theme_type_variation = &"MutedLabel"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = _desc_for(e)
	info.add_child(desc)
	var status := ScreenKit.pill("", FxPalette.STONE)       # stato come PILLOLA: Comprabile · Mancano N · Bloccato: serve X · Posseduto
	status.name = "StatusPill"
	status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var st_l := (status as PanelContainer).get_child(0) as Label                   # va a capo se serve (min 200 px: mai lettera per lettera)
	st_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st_l.custom_minimum_size.x = 200
	v.add_child(status)
	var actions := HFlowContainer.new()               # prezzo e pulsanti vanno a capo se la carta è stretta (nessuna larghezza minima grande)
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	v.add_child(actions)
	var price := Label.new()
	price.theme_type_variation = &"MonoLabel"
	price.add_theme_color_override("font_color", FxPalette.GOLD)
	price.custom_minimum_size = Vector2(110, 40)
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(price)
	var b1 := Button.new()
	b1.text = tr("UI_SHOP_BUY")
	b1.custom_minimum_size = Vector2(110, 40)
	b1.pressed.connect(_buy.bind(str(e.id), 1))
	actions.add_child(b1)
	var b10: Button = null
	if e.has("item"):
		b10 = Button.new()
		b10.text = tr("UI_SHOP_BUY_10")
		b10.custom_minimum_size = Vector2(0, 40)
		b10.pressed.connect(_buy.bind(str(e.id), 10))
		actions.add_child(b10)
	var go := Button.new()
	go.visible = false
	go.custom_minimum_size = Vector2(0, 40)
	go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	actions.add_child(go)
	_rows.append({"id": str(e.id), "status": status, "price": price, "b1": b1, "b10": b10, "go": go})


func _desc_for(e: Dictionary) -> String:
	if str(e.section) == "upgrades" or str(e.section) == "bank":
		return tr("UI_SHOP_DESC_" + str(e.id).to_upper())
	if str(e.section) == "keys":
		return tr("UI_SHOP_DESC_KEY")
	return Loc.t(DataRegistry.item(str(e.item)).get("desc", {}))


func _buy(shop_id: String, qty: int) -> void:
	if _mk.buy(shop_id, qty):
		var e := _mk.shop_entry(shop_id)
		var nm := Loc.t(e.name) if e.has("name") else Loc.t(DataRegistry.item(str(e.item)).get("name", {}))
		EventBus.notice.emit("success", Loc.tf("UI_SHOP_BOUGHT", {"name": nm, "qty": qty}), {})
	refresh()


func refresh() -> void:
	if _mk == null or _gold == null:
		return
	_gold.text = NumberFormat.fmt(GameState.gold())
	for r in _rows:
		var e := _mk.shop_entry(r.id)
		var st := _mk.shop_status(r.id, 1)
		var unit := _mk.shop_unit_price(e, _mk.owned(r.id))
		var maxed: bool = st.reason == "max"
		(r.price as Label).text = "" if maxed else tr("UI_SHOP_PRICE").format({"p": NumberFormat.fmt(unit)})
		var stxt := _status_text(e, st)
		var why_off: bool = not bool(st.ok) and not maxed and str(st.reason) != ""
		# palette di significato: verde = fatto/comprabile, ambra = manca qualcosa, grigio = informazione. Rosso SOLO per il pericolo.
		var scol: Color = FxPalette.GREEN if (maxed or bool(st.ok)) else (FxPalette.AMBER if why_off else FxPalette.STONE)
		if stxt.is_empty() and bool(st.ok):
			stxt = tr("UI_GB_SHOP_READY")
		ScreenKit.set_pill(r.status as Control, stxt, scol)
		(r.status as Control).tooltip_text = ReqText.gold_sentence(unit, GameState.gold()) if str(st.reason) == "gold" else ""      # frase intera: quanto serve, quanto hai
		(r.status as Control).visible = not stxt.is_empty()
		_update_go(r.go as Button, st)
		(r.b1 as Button).disabled = not st.ok
		(r.b1 as Button).theme_type_variation = &"AccentButton" if bool(st.ok) else &""
		(r.b1 as Button).visible = not maxed
		if r.b10 != null:
			var st10 := _mk.shop_status(r.id, 10)
			(r.b10 as Button).disabled = not st10.ok


## «Vai» accanto al motivo del blocco: dove si rimedia (Mercato per l'oro, Commesse per la reputazione, Eroe per il livello).
func _update_go(b: Button, st: Dictionary) -> void:
	var screen := ""
	var title := ""
	match str(st.reason):
		"gold":
			screen = "market"
			title = "UI_MENU_MARKET"
		"requires_faction":
			screen = "orders"
			title = "UI_MENU_ORDERS"
		"requires_level":
			screen = "hero"
			title = "UI_MENU_HERO"
	var entry := ScreenRegistry.get_entry(screen) if screen != "" else {}
	b.visible = not entry.is_empty() and ScreenRegistry.is_available(entry, GameState.data.get("unlocks", []))
	if b.visible:
		b.text = Loc.tf("UI_VUX_GO", {"to": tr(title)})
		for c in b.pressed.get_connections():
			b.pressed.disconnect(c.callable)
		b.pressed.connect(ReqLink.go.bind({"screen": screen, "params": {}, "hint": ""}))


func _status_text(e: Dictionary, st: Dictionary) -> String:
	match st.reason:
		"max":
			return tr("UI_SHOP_OWNED")
		"requires_item":
			var req := _mk.shop_entry(str(e.requires))
			return Loc.tf("UI_SHOP_NEEDS_ITEM", {"name": Loc.t(req.get("name", {}))})
		"requires_level":
			return Loc.tf("UI_SHOP_NEEDS_LEVEL", {"lv": int(e.requires.hero_level)})
		"requires_faction":
			var f: Dictionary = DataRegistry.get_def("factions", str(e.requires.faction))
			var rank_name := ""
			for rk in f.get("ranks", []):
				if str(rk.id) == str(e.requires.rank):
					rank_name = Loc.t(rk.name)
			return Loc.tf("UI_SHOP_NEEDS_FACTION", {"faction": Loc.t(f.get("name", {})), "rank": rank_name})
		"mode":
			return tr("UI_MODES_SHOP_BLOCKED")
		"limit":
			return tr("UI_SHOP_LIMIT_REACHED")
		"gold":
			var price := int(_mk.shop_unit_price(e, _mk.owned(str(e.id))))
			return Loc.tf("UI_MSK_SHOP_GOLD", {"n": NumberFormat.fmt(maxi(1, price - GameState.gold())), "have": NumberFormat.fmt(GameState.gold())})
	if int(st.limit_left) >= 0:
		return Loc.tf("UI_SHOP_DAILY_LEFT", {"n": int(st.limit_left), "max": int(e.daily_limit)})
	if int(st.max) > 1:
		return Loc.tf("UI_SHOP_COUNT", {"n": int(st.owned), "max": int(st.max)})
	return ""
