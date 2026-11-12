class_name EndgamePanel
extends VBoxContainer
## Base delle schede di fine gioco della schermata Dungeon (Incursioni, Boss mondiali, Breccia): riferimento a
## CombatSystem, striscione animato, scheda del boss con ritratto e meccaniche, riga di ricompense e negozio a valuta.
## Solo presentazione: legge e comanda CombatSystem / EndgameCombat.

var combat: CombatSystem
var _banner: Label
var _last_log_id: int = 0


func setup(c: CombatSystem) -> void:
	combat = c
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_last_log_id = c.log_last_id()
	_build()
	refresh()


func _build() -> void:
	pass


func refresh() -> void:
	pass


## Suggerimento «cosa fare ora» della scheda: [tipo ScreenKit.Kind, testo, testo del pulsante Vai, bersaglio]. Vuoto = nessuno.
## Le schede lo ridefiniscono; DungeonScreen lo mostra nella barra sotto il titolo.
func hint() -> Array:
	return []


func _eg() -> EndgameCombat:
	return combat.eg


## Striscione centrale (vittoria, fallimento, nuova fase): compare, rimbalza e svanisce.
func make_banner() -> Label:
	_banner = CombatUi.text_label("TitleLabel")
	_banner.modulate.a = 0.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.custom_minimum_size = Vector2(0, 24)
	return _banner


func show_banner(text: String, col: Color, hold: float = 1.6) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate.a = 1.0
	CombatUi.pop(_banner, 1.25, 0.35)
	if CombatUi.reduce() or not is_inside_tree():
		return
	var tw := _banner.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)


## Colonna con ritratto, nome, descrizione e meccaniche di un boss. Ritorna il ritratto (per le scosse).
static func boss_card(parent: Control, boss: Dictionary, mech: Dictionary, extra: String = "") -> TextureRect:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(128, 128)
	portrait.texture = IconLib.portrait("monsters", str(boss.id))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var nm := CombatUi.text_label("SectionLabel")
	nm.text = "%s  (%s %d)" % [Loc.t(boss.name), TranslationServer.translate("UI_COMBAT_LV"), int(boss.level)]
	col.add_child(nm)
	if boss.has("desc"):
		var d := CombatUi.text_label("MutedLabel", true)
		d.text = Loc.t(boss.desc)
		col.add_child(d)
	if not extra.is_empty():
		var ex := CombatUi.text_label("", true)
		ex.text = extra
		col.add_child(ex)
	for mid in boss.get("mechanics", []):
		var m: Dictionary = mech.get(str(mid), {})
		ScreenKit.mech_row(col, Loc.t(m.get("name", "")), Loc.t(m.get("desc", "")))
	return portrait


## Riquadro «Cosa serve per aprirlo»: livello Eroe e missione, con ✓/✗ e il pulsante Vai dove si ottengono.
static func lock_card(c: CombatSystem, parent: Control, unlock: Dictionary) -> void:
	var rq := ScreenKit.card(parent, Color("#a85a5a"), 4)
	rq.add_child(CombatUi.label("UI_RS_DU_REQS", "SectionLabel"))
	var need := int(unlock.get("hero_level", 0))
	if need > 0:
		var now := c.hero_unlock_level()
		ScreenKit.req_row(rq, now >= need, Loc.tf("UI_RS_DU_REQ_LEVEL", {"lv": need, "now": now}),
			ScreenKit.target("combat") if ScreenKit.available("combat") else {}, TranslationServer.translate("UI_RS_GO_COMBAT"))
	var qid := str(unlock.get("quest", ""))
	if qid != "":
		var done := ((GameState.data.get("quests", {}) as Dictionary).get("done", []) as Array).has(qid)
		ScreenKit.req_row(rq, done, Loc.tf("UI_RS_DU_REQ_QUEST", {"quest": Loc.t(DataRegistry.get_def("quests", qid).get("title", qid))}),
			ReqLink.target_for_quest(qid), TranslationServer.translate("UI_RS_GO_QUESTS"))


## "Nome ×qty" di un elenco di oggetti dei dati ({item|id, qty|[a,b]}).
static func items_text(list: Array, with_chance: bool = true) -> String:
	var parts: PackedStringArray = []
	for it in list:
		var iid := str(it.get("item", it.get("id", "")))
		var q: Variant = it.get("qty", 1)
		var qt := "%d–%d" % [int(q[0]), int(q[1])] if q is Array else str(int(q))
		var txt := "%s ×%s" % [Loc.t(DataRegistry.item(iid).get("name", iid)), qt]
		if with_chance and it.has("chance"):
			txt += " (%s)" % NumberFormat.fmt_pct(float(it.chance) * 100.0)
		parts.append(txt)
	return ", ".join(parts)


## Etichetta del livello di rischio colorata (verde/giallo/rosso) con il testo di CombatUi / dungeon.
static func paint_risk(l: Label, level: String, text: String) -> void:
	l.text = text
	l.add_theme_color_override("font_color", CombatUi.COL_SAFE.get(level, Color.WHITE))


## Negozio a valuta (Sala dei Trofei, Bazar della Breccia): elenco con costo e pulsante Compra.
func build_shop(parent: Control, shop_id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	box.set_meta("shop", shop_id)
	return box


func fill_shop(box: VBoxContainer) -> void:
	EndgamePanel.shop_fill(combat, box)


## Negozio a valuta come elenco di carte: icona, nome, prezzo, Compra con il motivo se non si può.
## Statico: lo usano anche le Taglie (Banco delle Taglie). `box` porta il meta "shop" (id del negozio).
static func shop_fill(c: CombatSystem, box: VBoxContainer) -> void:
	var shop_id := str(box.get_meta("shop"))
	CombatUi.clear_children(box)
	var egc: EndgameCombat = c.eg
	var d := egc.shop_def(shop_id)
	if d.is_empty():
		return
	var bank: Variant = c.ctx.get_system("bank")
	var cur := str(d.currency)
	var have: int = int(bank.count(cur)) if bank != null else 0
	var head := ScreenKit.stat(box, Loc.t(DataRegistry.item(cur).get("name", cur)), "UI_RS_DU_TIP_SHOP_CUR", Color(ScreenKit.GOLD))
	head.set_value(NumberFormat.fmt(float(have)), "")
	for it in egc.shop_items(shop_id):
		var iid := str(it.item)
		var def := DataRegistry.item(iid)
		var ok := bool(it.can_buy)
		var body := ScreenKit.card(box, Color("#d2b574") if ok else Color(ScreenKit.EDGE), 3)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.texture = ScreenKit.item_icon(iid)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var nm := VBoxContainer.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_constant_override("separation", 0)
		row.add_child(nm)
		var l := CombatUi.text_label("", true)
		l.text = Loc.t(def.get("name", iid))
		nm.add_child(l)
		if not str(it.note).is_empty():
			nm.add_child(ScreenKit.muted(TranslationServer.translate("UI_RAID_SHOP_PITY")))
		var price := ScreenKit.stat(row, "", "UI_RS_DU_TIP_SHOP_PRICE", Color(ScreenKit.GOLD) if ok else Color(ScreenKit.TEXT_DIM))
		price.set_value(NumberFormat.fmt(float(it.cost)), "")
		price.set_caption(TranslationServer.translate("UI_RS_DU_SHOP_COST"))
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bcol := VBoxContainer.new()
		bcol.add_theme_constant_override("separation", 2)
		bcol.custom_minimum_size = Vector2(150, 0)
		row.add_child(bcol)
		var b := Button.new()
		b.text = "UI_RAID_SHOP_BUY"
		if ok:
			b.theme_type_variation = &"AccentButton"
		var rl := ScreenKit.reason_label()
		ScreenKit.gate(b, "" if ok else Loc.tf("UI_RS_DU_SHOP_WHY", {"need": NumberFormat.fmt(float(it.cost)), "have": NumberFormat.fmt(float(have))}), rl)
		b.pressed.connect(func() -> void:
			if egc.shop_buy(shop_id, iid):
				CombatUi.pop(b)
				EndgamePanel.shop_fill(c, box))
		bcol.add_child(b)
		bcol.add_child(rl)
