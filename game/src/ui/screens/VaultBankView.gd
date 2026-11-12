class_name VaultBankView
extends WorkshopView
## Scheda Banco dei Caveau (docs/09 §11): le Schegge del Caveau (si ottengono fondendo i pezzi delle Casse) si
## spendono in chiavi, clessidre e capsule a prezzo fisso. Qui c'è anche la Fusione in blocco per rarità
## (esclusi i pezzi bloccati e quelli in uso). Prezzi e Schegge sono dati: nessuna sorpresa.

var fuse_rarity: String = "rare"
var _msg: String = ""


func signature() -> String:
	return "%d|%d|%s|%s" % [bank_revision(), crates.shards(), fuse_rarity, _msg]


func build() -> void:
	if crates.shards() <= 0 and _instances_of(["skin", "relic", "cosmetic"]).is_empty():
		var gos: Array = []
		var hall := ScreenRegistry.get_entry("vault_hall")
		if not hall.is_empty() and ScreenRegistry.is_available(hall, GameState.data.get("unlocks", [])):
			gos.append({"text": tr("UI_MENU_VAULT_HALL"), "primary": true, "target": {"screen": "vault_hall", "params": {}, "hint": ""}})
		VaultKit.empty_card(self, IconLib.icon("items", "vault_shard"), tr("UI_VUX_BK_EMPTY_TITLE"), tr("UI_VUX_BK_EMPTY_WHAT"),
			PackedStringArray([tr("UI_VUX_BK_STEP_1")]), gos)
	var head := Label.new()
	head.text = Loc.tf("UI_CRATES2_VB_BALANCE", {"s": NumberFormat.fmt(crates.shards())})
	ScreenKit.title_style(head)
	add_child(head)
	if not _msg.is_empty():
		_label(_msg, false)

	_section(tr("UI_CRATES2_VB_STOCK"))
	for e in crates.vault_stock():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var icon := TextureRect.new()
		icon.texture = CrateUi.def_icon(str(e.item))
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name_l := Label.new()
		name_l.text = "%s  (%s)" % [CrateUi.def_name(str(e.item)), Loc.tf("UI_CRATES2_VB_OWNED", {"n": NumberFormat.fmt(int(e.owned))})]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		row.add_child(name_l)
		var b := Button.new()
		b.text = Loc.tf("UI_CRATES2_VB_BUY", {"n": NumberFormat.fmt(int(e.shards))})
		var why := crates.vault_buy_check(str(e.item), 1)
		b.disabled = not why.is_empty()
		if b.disabled:
			b.tooltip_text = CrateUi.why(why)
		var item_id: String = e.item
		b.pressed.connect(func() -> void: buy(item_id))
		row.add_child(b)

	_section(tr("UI_CRATES2_VB_FUSE"))
	_label(tr("UI_CRATES2_VB_FUSE_INFO"))
	var ob := _rarity_option(false, CrateSystem.RARITIES, fuse_rarity)
	ob.item_selected.connect(func(i: int) -> void:
		fuse_rarity = str(ob.get_item_metadata(i))
		rebuild(true))
	add_child(ob)
	var uids := fuse_candidates(fuse_rarity)
	if uids.is_empty():
		_label(tr("UI_VUX_BK_NO_FUSE"))
	var total := 0
	for u in uids:
		total += crates.fuse_value(str(u))
	var fb := Button.new()
	fb.text = Loc.tf("UI_CRATES2_VB_FUSE_BTN", {"c": uids.size(), "r": CrateUi.rarity_label(fuse_rarity), "n": NumberFormat.fmt(total)})
	fb.disabled = uids.is_empty()
	fb.pressed.connect(func() -> void:
		CrateUi.confirm(self, Loc.tf("UI_CRATES2_CONFIRM_BULK", {"c": uids.size()}), fuse_all))
	add_child(fb)


## Pezzi della rarità fondibili in blocco: non bloccati e non in uso.
func fuse_candidates(rarity: String) -> Array:
	var out: Array = []
	for inst in _instances_of(["skin", "relic", "cosmetic"]):
		if str(inst.rarity) == rarity and crates.consume_block(str(inst.uid)).is_empty():
			out.append(str(inst.uid))
	return out


func buy(item_id: String) -> void:
	if crates.vault_buy(item_id, 1):
		_msg = Loc.tf("UI_CRATES2_VB_BOUGHT", {"name": CrateUi.def_name(item_id)})
	rebuild(true)


func fuse_all() -> void:
	var res := crates.fuse_many(fuse_candidates(fuse_rarity))
	_msg = Loc.tf("UI_CRATES2_BULK_DONE", {"c": res.n, "n": NumberFormat.fmt(res.shards)})
	rebuild(true)
