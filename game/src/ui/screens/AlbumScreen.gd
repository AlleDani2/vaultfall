extends GameScreen
## Album delle collezioni (docs/09 §8): una collezione per cassa, sagome per gli oggetti mancanti, contatore
## "posseduti/totale", miglior float posseduto, numero di Annalisti, stato del bonus (completa / Aurea).
## Anche con l'Album ancora bianco la schermata mostra le sagome da completare, a cosa serve e come si riempie.

const SLOT_CARD := Vector2(148, 150)
const TILE := Vector2(190, 0)

var _crates: CrateSystem
var _selected: String = ""
var _signature: String = ""

static var _open_done: bool = false          # sezioni dell'elenco: ricordate per la sessione
static var _open_unstarted: bool = false

var _st_done: ScreenKit.KitStat
var _st_found: ScreenKit.KitStat
var _st_bonus: ScreenKit.KitStat
var _tiles: VBoxContainer
var _body: VBoxContainer


func open(params: Dictionary) -> void:
	_crates = CrateUi.crates()
	_selected = str(params.get("collection", _selected))
	_build()
	_rebuild(true)


func refresh() -> void:
	if _crates != null:
		_rebuild(false)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	VaultHead.header(self, "album", "UI_CRATES_TAB_ALBUM", "UI_CRATES_ALBUM_SUB")
	var stats := ScreenKit.stat_row(self)              # tre numeri grandi invece di una riga di testo in grassetto
	_st_done = ScreenKit.stat(stats, "UI_GB_ALB_DONE")
	_st_found = ScreenKit.stat(stats, "UI_GB_ALB_FOUND")
	_st_bonus = ScreenKit.stat(stats, "UI_GB_ALB_BONUS")
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(TILE.x + 22.0, 0)
	left.size_flags_stretch_ratio = 1.0
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	_tiles = VBoxContainer.new()
	_tiles.name = "CollectionTiles"
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tiles.add_theme_constant_override("separation", 4)
	left.add_child(_tiles)
	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 3.0
	right.custom_minimum_size = Vector2(300, 0)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	right.add_child(_body)


func _rebuild(force: bool) -> void:
	var ids := _crates.collection_ids()
	if ids.is_empty():
		return
	var progress := {}
	var groups := {"active": [], "done": [], "unstarted": []}
	var done := 0
	var owned := 0
	var total := 0
	var bonus_on := 0
	for cid in ids:
		var p := _crates.collection_progress(str(cid))
		progress[cid] = p
		if bool(p.complete):
			done += 1
		if bool(p.complete) or bool(p.golden):
			bonus_on += 1
			groups.done.append(cid)
		elif int(p.owned) + int(p.relics_owned) > 0:
			groups.active.append(cid)
		else:
			groups.unstarted.append(cid)
		owned += int(p.owned)
		total += int(p.total)
	if _selected.is_empty() or not ids.has(_selected):
		_selected = str(groups.active[0]) if not groups.active.is_empty() else str(ids[0])
	var sig := "%s|%s|%d" % [_selected, str(_crates.state.collections.hash()), int(_crates.state.opened)]
	if sig == _signature and not force:
		return
	_signature = sig
	for c in _tiles.get_children():
		c.queue_free()
	# «In corso» sempre aperta; «Finite» e «Non iniziate» chiuse (si aprono da sole se contengono la scelta,
	# o se non c'è nulla in corso: un Album bianco mostra comunque le collezioni da cominciare)
	_section(Loc.tf("UI_F11_ALBUM_ACTIVE", {"n": groups.active.size()}), groups.active, progress, true, "Active")
	var no_active: bool = groups.active.is_empty()
	_section(Loc.tf("UI_F11_ALBUM_DONE", {"n": groups.done.size()}), groups.done, progress,
		_open_done or groups.done.has(_selected), "Done")
	_section(Loc.tf("UI_F11_ALBUM_UNSTARTED", {"n": groups.unstarted.size()}), groups.unstarted, progress,
		_open_unstarted or groups.unstarted.has(_selected) or (no_active and groups.done.is_empty()), "Unstarted")
	_st_done.set_value("%d/%d" % [done, ids.size()])
	_st_found.set_value("%d/%d" % [owned, total])
	_st_bonus.set_value("%d/%d" % [bonus_on, ids.size()])
	_build_body(owned)


## Sezione dell'elenco: titolo-pulsante con freccia (le chiuse non occupano spazio) e le tessere sotto.
func _section(title: String, cids: Array, progress: Dictionary, expanded: bool, key: String) -> void:
	if cids.is_empty():
		return
	var box := VBoxContainer.new()
	box.name = "Group" + key
	box.add_theme_constant_override("separation", 4)
	box.visible = expanded
	for cid in cids:
		box.add_child(_tile(str(cid), progress[cid]))
	if key == "Active":
		var h := Label.new()
		h.text = title
		h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		h.theme_type_variation = &"SectionLabel"
		_tiles.add_child(h)
	else:
		var btn := Button.new()
		btn.name = "Toggle" + key
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.text = (Disclosure.OPEN if expanded else Disclosure.CLOSED) + title
		_tiles.add_child(btn)
		btn.pressed.connect(func() -> void:
			box.visible = not box.visible
			if key == "Done":
				_open_done = box.visible
			else:
				_open_unstarted = box.visible
			btn.text = (Disclosure.OPEN if box.visible else Disclosure.CLOSED) + title)
	_tiles.add_child(box)


## Tessera di una collezione: icona della cassa, nome, x/N e barra; la scelta attuale ha il bordo d'oro.
func _tile(cid: String, p: Dictionary) -> Control:
	var cdef := DataRegistry.get_def("collections", cid)
	var crate_id := str(cdef.get("crate", ""))
	var done := bool(p.complete)
	var card := VaultKit.card(VaultKit.crate_accent(crate_id), cid == _selected)
	card.name = "Collection_" + cid
	card.custom_minimum_size = Vector2(TILE.x, 64)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	h.add_child(VaultKit.pix(CrateUi.def_icon(crate_id), 1, false))
	var n := Label.new()
	n.text = Loc.t(cdef.name)
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_size_override("font_size", UiType.NOTE)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(n)
	var cnt := Label.new()
	cnt.text = "%d/%d%s" % [int(p.owned), int(p.total), "  ✓" if done else ""]
	cnt.theme_type_variation = &"NumberLabel"
	cnt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cnt.add_theme_color_override("font_color", FxPalette.GREEN if done else (FxPalette.GOLD if int(p.owned) > 0 else FxPalette.SMOKE))
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cnt)
	var pb := VaultKit.progress(float(p.owned), float(p.total), FxPalette.GREEN_D if done else FxPalette.GOLD_D)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pb)
	VaultKit.make_clickable(card, func() -> void:
		_selected = cid
		_rebuild(true), Loc.t(cdef.name))
	return card


func _build_body(owned_all: int) -> void:
	for c in _body.get_children():
		c.queue_free()
	VaultKit.fade_in(_body)
	var cdef := DataRegistry.get_def("collections", _selected)
	var crate_id := str(cdef.crate)
	var crate: Dictionary = DataRegistry.item(crate_id).get("crate", {})
	var p := _crates.collection_progress(_selected)
	var head := Label.new()
	head.text = Loc.t(cdef.name)
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.theme_type_variation = &"SectionLabel"
	_body.add_child(head)

	if int(p.owned) + int(p.relics_owned) == 0:
		# nessun pezzo di questa collezione: spiega e rimanda alla cassa che la riempie (le sagome restano sotto)
		var gos: Array = []
		var hall := ScreenRegistry.get_entry("vault_hall")
		if not hall.is_empty() and ScreenRegistry.is_available(hall, GameState.data.get("unlocks", [])):
			gos.append({"text": "%s · %s" % [tr("UI_MENU_VAULT_HALL"), CrateUi.def_name(crate_id)], "primary": true,
				"target": {"screen": "vault_hall", "params": {"crate": crate_id}, "hint": ""}})
		var steps := PackedStringArray([Loc.tf("UI_VUX_ALBUM_FIND_IN", {"crate": CrateUi.def_name(crate_id)}),
			tr("UI_VUX_ALBUM_STEP_2"), tr("UI_VUX_ALBUM_STEP_3")])
		VaultKit.empty_card(_body, CrateUi.def_icon(crate_id), tr("UI_VUX_ALBUM_EMPTY_TITLE") if owned_all == 0 else Loc.t(cdef.name),
			tr("UI_VUX_ALBUM_EMPTY_WHAT"), steps, gos)
	else:
		var st := Label.new()
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Reliquie solo se ne esiste almeno una: «Reliquie 0/4» su ogni collezione è rumore
		var txt := Loc.tf("UI_CRATES_ALBUM_COUNT", {"o": p.owned, "t": p.total, "ro": p.relics_owned, "rt": p.relics_total}) \
			if int(p.relics_owned) > 0 else Loc.tf("UI_F11_ALBUM_SKINS", {"o": p.owned, "t": p.total})
		st.text = txt
		_body.add_child(st)

	var bonus := CrateUi.mods_text(cdef.complete_bonus.modifiers).replace("\n", "; ")
	var on := bool(p.complete) or bool(p.golden)
	var bl := Label.new()
	bl.name = "BonusLine"
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.text = Loc.tf("UI_VUX_ALBUM_BONUS_ON" if on else "UI_VUX_ALBUM_BONUS_OFF", {"b": bonus})
	bl.add_theme_color_override("font_color", FxPalette.GREEN if on else FxPalette.STONE)
	_body.add_child(bl)
	if bool(p.golden):
		VaultKit.label(_body, tr("UI_CRATES_ALBUM_GOLDEN"), false, 0, FxPalette.GOLD)
	elif bool(p.complete):
		VaultKit.label(_body, tr("UI_CRATES_ALBUM_COMPLETE"), false, 0, FxPalette.GREEN)

	var grid := HFlowContainer.new()
	grid.name = "SlotGrid"
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var entries: Dictionary = p.entries
	for sid in crate.get("skins", []):
		grid.add_child(_cell(str(sid), entries.get(sid, {}), false, crate_id))
	for rid in crate.get("relic_pool", []):
		grid.add_child(_cell(str(rid), entries.get(rid, {}), true, crate_id))


func _cell(def_id: String, e: Dictionary, is_relic: bool, crate_id: String) -> Control:
	var have := not e.is_empty()
	var d := DataRegistry.item(def_id)
	var rarity: String = "relic" if is_relic else str(d.get("rarity", "rare"))
	var pnl := PanelContainer.new()
	pnl.custom_minimum_size = SLOT_CARD
	pnl.theme_type_variation = UiKit.rarity_variation(rarity if have else "common", false)     # non posseduto = cornice neutra
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	pnl.add_child(v)
	v.add_child(VaultKit.pix(CrateUi.def_icon(def_id), 2, not have))        # sagoma a scala intera
	var n := Label.new()
	n.text = CrateUi.def_name(def_id) if have else tr("UI_CRATES_ALBUM_MISSING")
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_size_override("font_size", UiType.NOTE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	var s := Label.new()
	s.add_theme_font_size_override("font_size", UiType.NOTE)
	s.theme_type_variation = &"MutedLabel"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.text = CrateUi.rarity_symbol(rarity)            # solo il simbolo (mai solo colore); il nome della rarità sta nel tooltip, non su ogni carta
	if have:
		s.add_theme_color_override("font_color", CrateUi.rarity_color(rarity))
	v.add_child(s)
	if have:
		# patina migliore e Analisti NON si ripetono su ogni carta: stanno nel tooltip (06 §3.13)
		var tip := Loc.tf("UI_CRATES_ALBUM_TIP", {"n": int(e.n), "a": int(e.ann)})
		if d.has("skin") or d.has("relic"):
			tip = Loc.tf("UI_CRATES_ALBUM_BEST", {"f": NumberFormat.decimal(float(e.best), 3, TranslationServer.get_locale().substr(0, 2)),
				"a": int(e.ann)}) + "\n" + tip
		pnl.tooltip_text = CrateUi.rarity_label(rarity) + "\n" + tip
	else:
		pnl.tooltip_text = CrateUi.rarity_label(rarity) + "\n" + Loc.tf("UI_VUX_ALBUM_MISSING_TIP", {"crate": CrateUi.def_name(crate_id)})
	return pnl
