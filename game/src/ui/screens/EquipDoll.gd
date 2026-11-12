class_name EquipDoll
extends VBoxContainer
## Equipaggiamento dell'Eroe in stile «paper-doll» (come l'inventario di Minecraft): una griglia di SLOT disegnati, uno per
## ogni slot reale dei dati (elmo, corazza, gambali, stivali, guanti, mantello, arma, mano secondaria, munizioni, due anelli,
## amuleto, insegna) più gli utensili di mansione. Ogni slot mostra il pezzo indossato (icona e nome) oppure la silhouette
## dello slot e quanti pezzi adatti hai nel Deposito. Un clic sullo slot apre l'elenco dei SOLI pezzi compatibili con
## confronto delle statistiche; doppio clic o trascinamento sullo slot per indossare; tasto destro sullo slot per togliere.
## Solo presentazione: legge e comanda CombatSystem (equip/unequip/equip_check). Un solo pezzo per slot: indossarne un altro
## manda quello vecchio (non indossato) nel Deposito.

signal changed

const SLOTS: PackedStringArray = ["weapon", "offhand", "ammo", "helm", "body", "legs", "gloves", "boots",
	"cape", "amulet", "ring", "ring2", "insignia"]
## Posizione (colonna, riga) di ogni slot nella figura: testa in alto, mani ai lati, piedi in basso.
const GRID := {
	"cape": Vector2i(0, 0), "helm": Vector2i(1, 0), "amulet": Vector2i(2, 0),
	"weapon": Vector2i(0, 1), "body": Vector2i(1, 1), "offhand": Vector2i(2, 1),
	"gloves": Vector2i(0, 2), "legs": Vector2i(1, 2), "ring": Vector2i(2, 2),
	"ammo": Vector2i(0, 3), "boots": Vector2i(1, 3), "ring2": Vector2i(2, 3),
	"insignia": Vector2i(1, 4),
}
## Mansione che costruisce i pezzi di uno slot (per il link «Vai a…» quando manca qualcosa).
const CRAFT_SKILL := {"weapon": "smithing", "offhand": "smithing", "helm": "smithing", "body": "smithing", "legs": "smithing",
	"gloves": "smithing", "boots": "smithing", "cape": "tailoring", "amulet": "jewelcrafting", "ring": "jewelcrafting",
	"ring2": "jewelcrafting"}
const REBUILD_MIN_MS := 400
const COL_BAD := Color("d9544d")
const COL_WARN := Color("e0b640")
const COL_OK := Color("7fcf8a")
const COL_ACCENT := Color(0.93, 0.76, 0.42)
const LIST_ROWS := 5
## Scheda dell'Eroe accanto agli slot (revisione grafica 1.0, punto 19): ritratto della classe e le statistiche che gli slot cambiano.
const FIGURE_STATS: PackedStringArray = ["AP", "ACC", "EVA", "ARMOR", "WARD", "CRIT"]
const FIGURE_PORTRAIT_PX := 128         # PNG 128×128 a scala 1× (D-6)

static var _sil_cache: Dictionary = {}
static var _tool_skills: Array = []

var slot_buttons: Dictionary = {}          # id slot -> EquipSlotButton (compresi gli utensili «tool:<mansione>»)
var finish_labels: Dictionary = {}         # slot -> Label con nome e colore della finitura del Guardaroba (meta «row» = se stesso)
var selected_slot: String = "weapon"
var picked_key: String = ""                # riga scelta nell'elenco (uid, o «ammo:<oggetto>»)

var _combat: CombatSystem
var _bank: BankSystem
var _grid: GridContainer
var _row: HBoxContainer
var _right: VBoxContainer                   # colonna destra: scheda dell'Eroe + elenco dei pezzi
var _fig_panel: PanelContainer
var _fig_portrait: TextureRect
var _fig_name: Label
var _fig_level: Label
var _fig_vals: Dictionary = {}              # chiave di riga (AP, ACC, …) -> Label del valore
var _tools_head: Label
var _tools_flow: HFlowContainer
var _help: Label
var _dungeon_lbl: Label
var _pk_title: Label
var _pk_rule: Label
var _cur_icon: TextureRect
var _cur_name: Label
var _cur_info: Label
var _cur_fin: Label
var _cur_remove: Button
var _list_head: Label
var _list_hint: Label
var _list: VirtualList
var _empty_box: VBoxContainer
var _empty_lbl: Label
var _go_row: HBoxContainer
var _why_lbl: Label
var _equip_btn: Button
var _entries: Array[Dictionary] = []
var _counts: Dictionary = {}
var _sig := ""
var _bank_rev := -1
var _last_ms := 0
var _built := false


func _ready() -> void:
	ensure_built()
	refresh(true)


func help_label() -> Label:
	return _help


## Mostra o nasconde la frase d'aiuto sopra gli slot (il «?» dell'Eroe, F10).
func set_help_visible(on: bool) -> void:
	if _help != null:
		_help.visible = on


## Costruisce gli slot (una volta sola). Chi vuole gli slot subito (HeroScreen) la chiama prima di aggiungere il nodo alla scena.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	_combat = Game.system("combat") as CombatSystem
	_bank = Game.system("bank") as BankSystem
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


# ------------------------------------------------------------------ costruzione

func _build() -> void:
	# riga principale: figura degli slot a sinistra, elenco dei pezzi a destra; gli utensili sotto, a tutta larghezza (F10: la colonna
	# sinistra non si allunga più con la fila degli utensili)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 14)
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	_row.add_child(left)
	_help = Label.new()
	_help.text = "UI_EQ_HELP"
	_help.theme_type_variation = &"MutedLabel"
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(EquipSlotButton.SIZE_NORMAL.x * 3 + 16, 0)
	left.add_child(_help)
	_dungeon_lbl = Label.new()
	_dungeon_lbl.text = "UI_EQ_DUNGEON_LOCK"
	_dungeon_lbl.add_theme_color_override("font_color", COL_WARN)
	_dungeon_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dungeon_lbl.custom_minimum_size = _help.custom_minimum_size
	_dungeon_lbl.visible = false
	left.add_child(_dungeon_lbl)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(_grid)
	# le celle vuote della figura (il quinto rigo ha solo l'insegna al centro) si riempiono con segnaposto
	for row in 5:
		for col in 3:
			var slot := _slot_at(Vector2i(col, row))
			if slot.is_empty():
				var gap := Control.new()
				gap.custom_minimum_size = EquipSlotButton.SIZE_NORMAL
				_grid.add_child(gap)
			else:
				_grid.add_child(_make_slot(slot, false))
	_tools_head = Label.new()
	_tools_head.text = "UI_EQ_TOOLS"
	_tools_head.theme_type_variation = &"SectionLabel"
	add_child(_tools_head)
	_tools_flow = HFlowContainer.new()
	_tools_flow.add_theme_constant_override("h_separation", 4)
	_tools_flow.add_theme_constant_override("v_separation", 4)
	add_child(_tools_flow)
	for sk in tool_skills():
		_tools_flow.add_child(_make_slot("tool:" + str(sk), true))
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 10)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_right)
	_build_figure()
	_build_picker()


## Scheda dell'Eroe in cima alla colonna destra: ritratto della classe a sinistra, a destra nome, livello e le statistiche principali
## che cambiano indossando un pezzo. Sta sopra l'elenco dei pezzi: non allarga la pagina (le schede restano nell'area stretta).
func _build_figure() -> void:
	_fig_panel = PanelContainer.new()
	_fig_panel.name = "HeroFigure"
	_fig_panel.theme_type_variation = &"ContentPanel"
	_fig_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(_fig_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_fig_panel.add_child(h)
	_fig_portrait = TextureRect.new()
	_fig_portrait.custom_minimum_size = Vector2(FIGURE_PORTRAIT_PX, FIGURE_PORTRAIT_PX)
	_fig_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fig_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fig_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fig_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_fig_portrait)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_fig_name = Label.new()
	_fig_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fig_name.theme_type_variation = &"SectionLabel"
	_fig_name.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_fig_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fig_name.custom_minimum_size.x = 100
	v.add_child(_fig_name)
	_fig_level = Label.new()
	_fig_level.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fig_level.theme_type_variation = &"MutedLabel"
	v.add_child(_fig_level)
	var g := GridContainer.new()
	g.columns = 2                              # nome a sinistra, valore a destra: stretta, non allarga la pagina
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 2)
	v.add_child(g)
	for i in FIGURE_STATS.size():
		var k := str(FIGURE_STATS[i])
		var nl := Label.new()
		nl.text = "UI_HERO_ST_" + k
		nl.theme_type_variation = &"MutedLabel"
		g.add_child(nl)
		var vl := Label.new()
		vl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		vl.theme_type_variation = &"MonoLabel"
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(vl)
		_fig_vals[k] = vl


func _refresh_figure() -> void:
	if _fig_panel == null:
		return
	var st := _combat.hero_stats()
	var cls_id := str(_combat.state.get("class", "warrior"))
	var cls := Loc.t(_combat.class_def().get("name", {}))
	var spec := str(_combat.state.get("spec", ""))
	if not spec.is_empty():
		cls += " / " + Loc.t(DataRegistry.get_def("classes", spec).get("name", {}))
	_fig_portrait.texture = IconLib.portrait("classes", cls_id)
	_fig_name.text = cls
	_fig_level.text = Loc.tf("UI_GSA_HERO_LEVEL", {"level": int(st.level)})
	var vals := {"AP": NumberFormat.fmt(float(st.ap)), "ACC": NumberFormat.fmt(float(st.acc)), "EVA": NumberFormat.fmt(float(st.eva)),
		"ARMOR": NumberFormat.fmt(float(st.arm)), "WARD": NumberFormat.fmt(float(st.ward)), "CRIT": NumberFormat.fmt_pct(float(st.crit) * 100.0)}
	for k in vals:
		(_fig_vals[k] as Label).text = str(vals[k])


func _slot_at(cell: Vector2i) -> String:
	for s in GRID:
		if GRID[s] == cell:
			return str(s)
	return ""


func _make_slot(slot: String, small: bool) -> EquipSlotButton:
	var b := EquipSlotButton.new(slot, small)
	b.can_drop = _can_drop
	b.pressed.connect(_select_slot.bind(slot))
	b.dropped.connect(_on_dropped)
	b.context_requested.connect(_on_slot_right_click.bind(slot))
	slot_buttons[slot] = b
	var fin := b.finish_label()
	fin.set_meta("row", fin)
	finish_labels[slot] = fin
	return b


func _build_picker() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContentPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_pk_title = Label.new()
	_pk_title.theme_type_variation = &"SectionLabel"
	_pk_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_pk_title)
	_pk_rule = _wrap_label(&"MutedLabel")
	v.add_child(_pk_rule)
	# scheda del pezzo indossato
	var cur := HBoxContainer.new()
	cur.add_theme_constant_override("separation", 10)
	v.add_child(cur)
	_cur_icon = TextureRect.new()
	_cur_icon.custom_minimum_size = Vector2(EquipSlotButton.ICON_PX, EquipSlotButton.ICON_PX)
	_cur_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cur_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cur_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cur_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cur.add_child(_cur_icon)
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 2)
	cur.add_child(cv)
	_cur_name = _wrap_label(&"")
	cv.add_child(_cur_name)
	_cur_info = _wrap_label(&"MutedLabel")
	cv.add_child(_cur_info)
	_cur_fin = _wrap_label(&"MutedLabel")
	cv.add_child(_cur_fin)
	_cur_remove = Button.new()
	_cur_remove.text = "UI_EQ_REMOVE"
	_cur_remove.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cur_remove.pressed.connect(_unequip_selected)
	cv.add_child(_cur_remove)
	v.add_child(HSeparator.new())
	# «Nel Deposito, adatti a questo slot: N» e, se N è 0, i «Vai» sulla stessa riga (F10)
	var head_row := HFlowContainer.new()
	head_row.add_theme_constant_override("h_separation", 10)
	head_row.add_theme_constant_override("v_separation", 4)
	v.add_child(head_row)
	_list_head = Label.new()
	_list_head.theme_type_variation = &"SectionLabel"
	_list_head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head_row.add_child(_list_head)
	_go_row = HBoxContainer.new()
	_go_row.add_theme_constant_override("separation", 8)
	head_row.add_child(_go_row)
	_list_hint = _wrap_label(&"MutedLabel")
	_list_hint.text = tr("UI_EQ_LIST_HINT")
	v.add_child(_list_hint)
	var act := HBoxContainer.new()             # azione sul pezzo scelto, subito sopra l'elenco (non in fondo alla pagina)
	act.add_theme_constant_override("separation", 10)
	v.add_child(act)
	_equip_btn = Button.new()
	_equip_btn.text = "UI_EQ_EQUIP"
	_equip_btn.theme_type_variation = &"AccentButton"
	_equip_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_equip_btn.pressed.connect(func() -> void: _do_equip(picked_key))
	act.add_child(_equip_btn)
	_why_lbl = _wrap_label(&"")
	_why_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(_why_lbl)
	_list = VirtualList.new()
	_list.row_height = EquipPickRow.ROW_H + 2.0
	_list.custom_minimum_size = Vector2(0, (EquipPickRow.ROW_H + 2.0) * LIST_ROWS)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.make_row = _make_row
	_list.bind_row = _bind_row
	v.add_child(_list)
	_empty_box = VBoxContainer.new()             # il vecchio blocco «non c'è niente» non serve più: la riga di testata dice già «0»
	_empty_box.visible = false
	v.add_child(_empty_box)
	_empty_lbl = _wrap_label(&"MutedLabel")
	_empty_box.add_child(_empty_lbl)


func _wrap_label(variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


func _make_row() -> Control:
	var r := EquipPickRow.new()
	r.pressed.connect(_on_row_pressed.bind(r))
	r.activated.connect(func() -> void: _do_equip(r.uid))
	return r


func _bind_row(row: Control, index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var e: Dictionary = _entries[index]
	var r := row as EquipPickRow
	r.set_item(str(e.def), e.inst)
	var ok := bool(e.chk.ok)
	r.fill(str(e.key), e.icon, str(e.title), Color(0.95, 0.93, 0.86) if ok else Color(0.7, 0.68, 0.62), str(e.tag), str(e.info))
	r.modulate = Color(1.0, 0.92, 0.6) if str(e.key) == picked_key else (Color.WHITE if ok else Color(1, 1, 1, 0.78))


# ------------------------------------------------------------------ dati

## Mansioni che hanno attrezzi (dai dati), nell'ordine delle mansioni.
static func tool_skills() -> Array:
	if _tool_skills.is_empty():
		var seen := {}
		for it in DataRegistry.items_by_category("tool"):
			seen[str(it.get("tool", {}).get("skill", ""))] = true
		for s in DataRegistry.table("skills"):
			if seen.has(str(s.id)):
				_tool_skills.append(str(s.id))
	return _tool_skills


## Icona dello slot vuoto: un pezzo base dello slot (tier più basso), che lo slot mostra scurito.
static func silhouette(slot: String) -> Texture2D:
	if _sil_cache.has(slot):
		return _sil_cache[slot]
	var best := ""
	var best_tier := 999
	if slot == "ammo":
		for it in DataRegistry.items_by_category("ammo"):
			if int(it.get("tier", 99)) < best_tier:
				best_tier = int(it.get("tier", 99))
				best = str(it.id)
	elif slot.begins_with("tool:"):
		for it in DataRegistry.items_by_category("tool"):
			if str(it.get("tool", {}).get("skill", "")) == slot.substr(5) and int(it.get("tier", 99)) < best_tier:
				best_tier = int(it.get("tier", 99))
				best = str(it.id)
	else:
		var want := "ring" if slot == "ring2" else slot
		for it in DataRegistry.items_by_category("equipment"):
			if str(it.get("equipment", {}).get("slot", "")) == want and int(it.get("tier", 99)) < best_tier:
				best_tier = int(it.get("tier", 99))
				best = str(it.id)
	var tex: Texture2D = null
	if not best.is_empty():
		var kind := str(DataRegistry.item(best).get("icon", "")).get_base_dir().get_file()
		tex = IconLib.icon(kind if not kind.is_empty() else "items", best)
	_sil_cache[slot] = tex
	return tex


static func item_icon(def_id: String) -> Texture2D:
	var kind := str(DataRegistry.item(def_id).get("icon", "")).get_base_dir().get_file()
	return IconLib.icon(kind if not kind.is_empty() else "items", def_id)


## Identificatore dell'istanza indossata nello slot ("" se vuoto). Per le munizioni l'id dell'oggetto.
func worn_in(slot: String) -> String:
	if _combat == null:
		return ""
	if slot.begins_with("tool:"):
		var tools: Variant = GameState.data.get("equipment", {}).get("tools", {})
		return str((tools as Dictionary).get(slot.substr(5), "")) if tools is Dictionary else ""
	return _combat.equipped(slot)


## Nome dello slot tradotto («Elmo», «Secondo anello», «Utensile: Taglialegna»).
static func slot_title(slot: String) -> String:
	return ItemLabel.slot_name(slot)


## Nome corto per l'etichetta del riquadro («Secondaria», «Anello 2»): il riquadro è largo 96 pixel.
static func short_title(slot: String) -> String:
	if slot.begins_with("tool:"):
		return _skill_name(slot.substr(5))
	return TranslationServer.translate("UI_EQ_SLOT_" + slot.to_upper())


# ------------------------------------------------------------------ aggiornamento

func _signature() -> String:
	var lvl := _combat.hero_level()
	var crates := Game.system("crates") as CrateSystem
	return "%s|%s|%s|%d|%s|%s|%d" % [JSON.stringify(GameState.data.get("equipment", {})), selected_slot, picked_key, lvl, Loc.locale(),
		JSON.stringify(crates.state.get("wardrobe", {})) if crates != null else "", 1 if _combat.in_combat_blocking() else 0]


func refresh(force: bool = false) -> void:
	if _combat == null or _bank == null or not is_inside_tree():
		return
	var sig := _signature()
	var rev := _bank.revision
	var now := Time.get_ticks_msec()
	if not force and sig == _sig and rev == _bank_rev:
		return
	if not force and sig == _sig and now - _last_ms < REBUILD_MIN_MS:
		return                                         # solo il Deposito è cambiato (bottino): non ricostruire a ogni colpo
	_sig = sig
	_bank_rev = rev
	_last_ms = now
	_count_available()
	_refresh_slots()
	_refresh_figure()
	_refresh_picker()


## Quanti pezzi adatti, non indossati e già utilizzabili, ci sono nel Deposito per ogni slot (una sola passata).
func _count_available() -> void:
	_counts.clear()
	var lvl := _combat.hero_level()
	for inst in _bank.state.instances:
		var d: Dictionary = DataRegistry.item(str(inst.get("def", "")))
		var uid := str(inst.get("uid", ""))
		if d.has("tool"):
			if _combat.worn_slot(uid).is_empty():
				var k := "tool:" + str(d.tool.get("skill", ""))
				_counts[k] = int(_counts.get(k, 0)) + 1
			continue
		var eq: Dictionary = d.get("equipment", {})
		if eq.is_empty() or lvl < int(eq.get("level_req", 1)) or not _combat.worn_slot(uid).is_empty():
			continue
		var s := str(eq.slot)
		if s == "ring":
			_counts["ring"] = int(_counts.get("ring", 0)) + 1
			_counts["ring2"] = int(_counts.get("ring2", 0)) + 1
		else:
			_counts[s] = int(_counts.get(s, 0)) + 1
	_counts["ammo"] = _ammo_defs().size()


func _ammo_defs() -> Array:
	var out: Array = []
	var wstyle := str(_combat.hero_stats().weapon_style)
	if wstyle.is_empty():
		wstyle = "melee"
	for it in DataRegistry.items_by_category("ammo"):
		if _bank.count(str(it.id)) > 0 and str(it.ammo.get("style", "")) == wstyle:
			out.append(str(it.id))
	return out


func _refresh_slots() -> void:
	var sk := Game.system("skills") as SkillSystem
	var blocked := _combat.in_combat_blocking()
	_dungeon_lbl.visible = blocked
	var any_tool := false
	for slot in slot_buttons:
		var b: EquipSlotButton = slot_buttons[slot]
		if slot.begins_with("tool:"):
			var shown := sk == null or sk.is_unlocked(slot.substr(5))
			b.visible = shown
			any_tool = any_tool or shown
		b.set_slot_name(short_title(slot))
		b.set_selected(slot == selected_slot)
		var cur := worn_in(slot)
		var fin := b.finish_label()
		fin.visible = false
		b.set_state_text("")
		if cur.is_empty():
			var n := int(_counts.get(slot, 0))
			b.set_frame("slot_common" if n <= 0 else "slot_relic", Color(1, 1, 1, 0.6) if n <= 0 else Color(1, 1, 1, 0.9))
			b.show_empty(silhouette(slot), (Loc.tf("UI_EQ_AVAILABLE", {"n": n}) if n != 1 else tr("UI_EQ_AVAILABLE_ONE")) if n > 0 else tr("UI_EQ_EMPTY"), n > 0)
			b.set_item("")
			b.tooltip_text = Loc.tf("UI_EQ_EMPTY_TIP", {"slot": slot_title(slot)})
			if slot == "offhand" and _two_handed_weapon():
				b.set_state_text(tr("UI_EQ_LOCKED_2H"))
				b.show_empty(silhouette(slot), tr("UI_EQ_EMPTY"), false)
			if slot == "weapon":                   # la finitura del Guardaroba vale anche a mani nude
				_refresh_finish(slot, fin)
		else:
			b.set_frame("slot_rare" if not slot.begins_with("tool:") else "slot_common", Color.WHITE)
			if slot == "ammo":
				b.show_item(item_icon(cur), "%s ×%d" % [_item_name(cur), _combat.ammo_qty()])
				b.set_item(cur)
				b.tooltip_text = " "
			else:
				var inst: Dictionary = _bank.get_instance(cur)
				b.show_item(item_icon(str(inst.get("def", ""))), _item_name(str(inst.get("def", ""))))
				b.set_item(str(inst.get("def", "")), inst)
				b.tooltip_text = " "
				_refresh_finish(slot, fin)
	_tools_head.visible = any_tool
	_tools_flow.visible = any_tool


func _two_handed_weapon() -> bool:
	var w := _combat.equipped("weapon")
	var inst: Dictionary = _bank.get_instance(w) if not w.is_empty() else {}
	return bool(DataRegistry.item(str(inst.get("def", ""))).get("equipment", {}).get("two_handed", false))


static func _skill_name(skill_id: String) -> String:
	return Loc.t(DataRegistry.get_def("skills", skill_id).get("name", skill_id))


static func _item_name(def_id: String) -> String:
	return Loc.t(DataRegistry.item(def_id).get("name", def_id))


## Nome e colore della finitura che il Guardaroba mette sullo slot (docs/09 §5).
func _refresh_finish(slot: String, fin: Label) -> void:
	var crates := Game.system("crates") as CrateSystem
	var uid := crates.equipped(slot) if crates != null else ""
	var inst: Dictionary = crates.instance(uid) if (crates != null and not uid.is_empty()) else {}
	if inst.is_empty():
		fin.visible = false
		return
	var rarity := str(inst.get("rarity", "rare"))
	fin.visible = true
	fin.text = "%s %s" % [CrateUi.rarity_symbol(rarity), CrateUi.def_name(str(inst.get("def_id", "")))]
	fin.add_theme_color_override("font_color", CrateUi.rarity_color(rarity))
	fin.tooltip_text = "%s · %s" % [CrateUi.rarity_label(rarity), CrateUi.condition_name(str(inst.get("condition", "")))]
	fin.mouse_filter = Control.MOUSE_FILTER_PASS


# ------------------------------------------------------------------ pannello dello slot scelto

func _refresh_picker() -> void:
	var slot := selected_slot
	_pk_title.text = slot_title(slot)
	var rule_key := "UI_EQ_RULE_" + slot.to_upper() if not slot.begins_with("tool:") else "UI_EQ_RULE_TOOL"
	var rule := tr(rule_key)
	_pk_rule.text = rule if rule != rule_key else tr("UI_EQ_RULE_DEFAULT")
	# pezzo indossato
	var cur := worn_in(slot)
	var blocked := _combat.in_combat_blocking()
	if cur.is_empty():
		_cur_icon.texture = silhouette(slot)
		_cur_icon.modulate = EquipSlotButton.COL_SILHOUETTE
		_cur_name.text = tr("UI_EQ_NOTHING_WORN")
		_cur_name.remove_theme_color_override("font_color")
		_cur_info.text = tr("UI_EQ_NOTHING_WORN_HINT") if not (slot == "offhand" and _two_handed_weapon()) else tr("UI_HERO_TWO_HANDED")
		_cur_fin.visible = false
		_cur_remove.visible = false
	else:
		_cur_icon.modulate = Color.WHITE
		var def_id := cur
		var inst: Dictionary = {}
		if slot != "ammo":
			inst = _bank.get_instance(cur)
			def_id = str(inst.get("def", ""))
			_cur_name.text = ItemLabel.label(inst) + "  " + ItemLabel.short_id(cur)
		else:
			_cur_name.text = "%s ×%d" % [_item_name(cur), _combat.ammo_qty()]
		_cur_icon.texture = item_icon(def_id)
		_cur_name.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78))
		_cur_info.text = tr("UI_EQ_WORN_NOW") + " · " + _stats_line(def_id, inst)
		var fin := finish_labels.get(slot) as Label
		_cur_fin.visible = fin != null and fin.visible
		if _cur_fin.visible:
			_cur_fin.text = fin.text
			_cur_fin.add_theme_color_override("font_color", fin.get_theme_color("font_color"))
		_cur_remove.visible = true
		_cur_remove.disabled = blocked
	_build_entries(slot, cur)
	_list_head.text = Loc.tf("UI_EQ_LIST_HEAD", {"n": _entries.size()})
	_list.set_count(_entries.size())
	_list.rebind()
	_list.visible = not _entries.is_empty()
	_list_hint.visible = not _entries.is_empty()
	_refresh_empty(slot)
	_refresh_action()


## Riepilogo breve delle statistiche principali di un pezzo («Armatura 12 · Vita 5»).
static func _stats_line(def_id: String, inst: Dictionary) -> String:
	var def := DataRegistry.item(def_id)
	if def.has("ammo"):
		return Loc.tf("UI_EQ_AMMO_DMG", {"d": NumberFormat.fmt(float(def.ammo.get("damage", 0)))})
	var st := ItemTooltip.effective_stats(def, inst)
	var parts := PackedStringArray()
	for key in ItemTooltip.STAT_ORDER:
		if not st.has(key) or parts.size() >= 4:
			continue
		var v := float(st[key])
		var shown := NumberFormat.fmt_pct(v * 100.0) if key == "crit_chance" else NumberFormat.decimal(v, 1, Loc.locale())
		parts.append("%s %s" % [TranslationServer.translate(ItemTooltip.STAT_KEYS[key]).capitalize(), shown])
	return " · ".join(parts)


func _build_entries(slot: String, cur: String) -> void:
	_entries.clear()
	var cur_inst: Dictionary = _bank.get_instance(cur) if (not cur.is_empty() and slot != "ammo") else {}
	if slot == "ammo":
		for did in _ammo_defs():
			if did == cur:
				continue
			var def := DataRegistry.item(did)
			_entries.append({"key": "ammo:" + did, "def": did, "inst": {}, "icon": item_icon(did),
				"title": "%s ×%d" % [_item_name(did), _bank.count(did)], "tag": "T%d" % int(def.get("tier", 0)),
				"info": "[color=#%s]%s[/color]" % [ItemTooltip.COL_MUTED, Loc.tf("UI_EQ_AMMO_DMG", {"d": NumberFormat.fmt(float(def.ammo.get("damage", 0)))})],
				"chk": {"ok": true, "why": "", "args": {}}, "sort": [0, -int(def.get("tier", 0)), did]})
		_sort_entries()
		return
	var is_tool := slot.begins_with("tool:")
	var want := "ring" if slot == "ring2" else slot
	var raw: Array[Dictionary] = []
	for inst in _bank.state.instances:
		var d: Dictionary = DataRegistry.item(str(inst.get("def", "")))
		if is_tool:
			if str(d.get("tool", {}).get("skill", "")) != slot.substr(5):
				continue
		else:
			if str(d.get("equipment", {}).get("slot", "")) != want:
				continue
		var uid := str(inst.get("uid", ""))
		if uid == cur:
			continue
		raw.append({"inst": inst, "def": d, "uid": uid})
	# nomi uguali -> codice breve «#14» accanto (due «Manopole di Rame» non si confondono)
	var seen: Dictionary = {}
	for r in raw:
		var lab := ItemLabel.label(r.inst)
		r["label"] = lab
		seen[lab] = int(seen.get(lab, 0)) + 1
	var wstyle_cls := _class_style()
	for r in raw:
		var inst: Dictionary = r.inst
		var d: Dictionary = r.def
		var uid := str(r.uid)
		var chk := _combat.equip_check(uid, slot)
		var eq: Dictionary = d.get("equipment", {})
		var tag := ItemLabel.short_id(uid)
		var info := PackedStringArray()
		if not bool(chk.ok):
			info.append("[color=#%s]%s[/color]" % [COL_BAD.to_html(false), _short_why(chk)])
		if slot == "weapon" and not str(eq.get("style", "")).is_empty() and not wstyle_cls.is_empty() and not wstyle_cls.has(str(eq.style)):
			info.append("[color=#%s]%s[/color]" % [COL_WARN.to_html(false), Loc.tf("UI_EQ_STYLE_SHORT", {"style": tr("UI_RAID_STYLE_" + str(eq.style).to_upper())})])
		if bool(eq.get("two_handed", false)):
			info.append("[color=#%s]%s[/color]" % [ItemTooltip.COL_MUTED, tr("UI_EQ_LOCKED_2H").to_lower()])
		var cmp := ItemTooltip.compare(d, inst, cur_inst) if not cur_inst.is_empty() else []
		if not cur_inst.is_empty():
			if cmp.is_empty():
				info.append("[color=#%s]%s[/color]" % [ItemTooltip.COL_MUTED, tr("UI_UIA_TIP_SAME")])
			var n := 0
			for c in cmp:
				if n >= 4:
					break
				n += 1
				info.append("[color=#%s]%s[/color]" % [ItemTooltip.COL_UP if float(c.diff) > 0.0 else ItemTooltip.COL_DOWN, c.text])
		else:
			info.append("[color=#%s]%s[/color]" % [ItemTooltip.COL_MUTED, _stats_line(str(inst.def), inst)])
		var lv := int(eq.get("level_req", int(d.get("tool", {}).get("level_req", 0))))
		var lv_txt := Loc.tf("UI_EQ_LEVEL_TAG", {"n": lv}) if lv > 1 else ""
		_entries.append({"key": uid, "def": str(inst.def), "inst": inst, "icon": item_icon(str(inst.def)),
			"title": r.label, "tag": (tag + "  " + lv_txt).strip_edges(), "info": "  ".join(info), "chk": chk,
			"sort": [0 if bool(chk.ok) else 1, -int(d.get("tier", 0)), str(r.label), int(uid.trim_prefix("i_"))]})
	_sort_entries()


func _sort_entries() -> void:
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Array = a.sort
		var sb: Array = b.sort
		for i in mini(sa.size(), sb.size()):
			if sa[i] == sb[i]:
				continue
			return sa[i] < sb[i]
		return false)


## Gli stili che la classe corrente sfrutta (per avvisare quando un'arma ne ha un altro).
func _class_style() -> PackedStringArray:
	var cd := _combat.class_def()
	var out := PackedStringArray()
	if bool(cd.get("hybrid", false)):
		for s in cd.get("styles", []):
			out.append(str(s))
	elif not str(cd.get("style", "")).is_empty():
		out.append(str(cd.style))
	return out


func _short_why(chk: Dictionary) -> String:
	var why := str(chk.why)
	if why == "UI_HERO_LEVEL_REQ":
		return Loc.tf("UI_EQ_NEED_LEVEL", chk.args)
	if why == "UI_EQ_WHY_WORN":
		return Loc.tf("UI_EQ_WHY_WORN", {"slot": ItemLabel.slot_name(str((chk.args as Dictionary).get("slot", "")))})
	return Loc.tf(why, chk.args)


func _refresh_empty(slot: String) -> void:
	var none := _entries.is_empty()
	for c in _go_row.get_children():
		_go_row.remove_child(c)
		c.queue_free()
	_list_head.tooltip_text = ""
	if not none:
		return
	_empty_lbl.text = tr("UI_EQ_LIST_EMPTY_AMMO") if slot == "ammo" else tr("UI_EQ_LIST_EMPTY")
	_list_head.tooltip_text = _empty_lbl.text
	var market := _link("market", {})
	if not market.is_empty():
		_go_row.add_child(_go_button(tr("UI_EQ_GO_MARKET"), market))
	var craft := str(CRAFT_SKILL.get(slot, ""))
	if slot.begins_with("tool:"):
		craft = slot.substr(5)
	if not craft.is_empty():
		var target := ReqLink.target_for_level(craft)
		if not target.is_empty():
			_go_row.add_child(_go_button(Loc.tf("UI_EQ_GO_CRAFT", {"skill": _skill_name(craft)}), target))


func _link(screen: String, params: Dictionary) -> Dictionary:
	var e := ScreenRegistry.get_entry(screen)
	if e.is_empty() or not ScreenRegistry.is_available(e, GameState.data.get("unlocks", [])):
		return {}
	return {"screen": screen, "params": params, "hint": ""}


func _go_button(text: String, target: Dictionary) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.pressed.connect(ReqLink.go.bind(target))
	return b


func _entry_by_key(key: String) -> Dictionary:
	for e in _entries:
		if str(e.key) == key:
			return e
	return {}


func _refresh_action() -> void:
	var e := _entry_by_key(picked_key)
	if e.is_empty():
		picked_key = ""
		_equip_btn.visible = not _entries.is_empty()
		_equip_btn.disabled = true
		_why_lbl.visible = not _entries.is_empty()
		_why_lbl.text = tr("UI_EQ_PICK_FIRST")
		_why_lbl.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
		return
	_equip_btn.visible = true
	var chk: Dictionary = e.chk
	_equip_btn.disabled = not bool(chk.ok)
	_why_lbl.visible = not bool(chk.ok)
	if not bool(chk.ok):
		_why_lbl.text = Loc.tf(str(chk.why), chk.args) if str(chk.why) != "UI_EQ_WHY_WORN" else \
			Loc.tf("UI_EQ_WHY_WORN", {"slot": ItemLabel.slot_name(str((chk.args as Dictionary).get("slot", "")))})
		_why_lbl.add_theme_color_override("font_color", COL_BAD)
	else:
		_why_lbl.visible = false


# ------------------------------------------------------------------ azioni

func _select_slot(slot: String) -> void:
	selected_slot = slot
	picked_key = ""
	refresh(true)


func _on_row_pressed(row: EquipPickRow) -> void:
	picked_key = row.uid
	_list.rebind()
	_refresh_action()


func _can_drop(key: String, slot: String) -> bool:
	if _combat == null or _combat.in_combat_blocking():
		return false
	if key.begins_with("ammo:"):
		return slot == "ammo"
	if slot == "ammo":
		return false
	var chk := _combat.equip_check(key, slot)
	if slot.begins_with("tool:"):
		return bool(chk.ok) and str(chk.slot) == slot
	return bool(chk.ok) and str(chk.slot) == slot


func _on_dropped(key: String, slot: String) -> void:
	selected_slot = slot
	_do_equip(key)


## Indossa il pezzo `key` (uid, o «ammo:<oggetto>») nello slot scelto, con avviso a schermo.
func _do_equip(key: String) -> bool:
	if key.is_empty() or _combat == null:
		return false
	var slot := selected_slot
	var old := worn_in(slot)
	var old_name := ""
	var ok := false
	var new_name := ""
	if key.begins_with("ammo:"):
		new_name = _item_name(key.substr(5))
		ok = _combat.equip_ammo(key.substr(5))
	else:
		var inst: Dictionary = _bank.get_instance(key)
		new_name = ItemLabel.label(inst)
		if not old.is_empty() and slot != "ammo":
			old_name = ItemLabel.label(_bank.get_instance(old))
		if slot.begins_with("tool:"):
			ok = _combat.equip(key, slot)
		else:
			ok = _combat.equip(key, slot)
	if ok:
		var msg := Loc.tf("UI_EQ_EQUIPPED_NOTICE", {"name": new_name, "slot": slot_title(slot)})
		if not old_name.is_empty() and old != key:
			msg += " " + Loc.tf("UI_EQ_REPLACED_NOTICE", {"old": old_name})
		EventBus.notice.emit("info", msg, {})
		picked_key = ""
		changed.emit()
		refresh(true)
	return ok


func _unequip_selected() -> void:
	_unequip(selected_slot)


func _unequip(slot: String) -> void:
	if _combat == null:
		return
	if _combat.in_combat_blocking():
		EventBus.notice.emit("warning", tr("UI_EQ_DUNGEON_LOCK"), {})
		return
	var cur := worn_in(slot)
	if cur.is_empty():
		return
	var nm := _item_name(cur) if slot == "ammo" else ItemLabel.label(_bank.get_instance(cur))
	if slot.begins_with("tool:"):
		_combat.unequip_tool(slot.substr(5))
	else:
		_combat.unequip(slot)
	EventBus.notice.emit("info", Loc.tf("UI_EQ_REMOVED_NOTICE", {"name": nm}), {})
	changed.emit()
	refresh(true)


func _on_slot_right_click(_pos: Vector2, slot: String) -> void:
	selected_slot = slot
	_unequip(slot)
