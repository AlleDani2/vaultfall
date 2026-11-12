class_name BankTabDialog
extends ConfirmationDialog
## Finestra «Nuova scheda» / «Modifica scheda» del Deposito (F17, docs/ui_redesign/02 §5.1): nome (obbligatorio, al più
## constants.bank.ui.tab_name_max caratteri, ripulito come BankSystem.sanitize_tab_name) e icona scelta tra gli oggetti già
## SCOPERTI (Compendio): nessuna arte nuova, le icone sono quelle degli oggetti (32 px a fattore intero, regola 10).
## Solo presentazione: emette `done(name, icon)`; BankScreen chiama BankSystem.

signal done(tab_name: String, icon_def: String)

const ICON_CELL := 40.0

var name_edit: LineEdit
var icon_search: LineEdit
var grid: VirtualGrid
var icon_def: String = ""
var max_len: int = 1
var _all_ids: Array = []
var _ids: Array = []
var _preview: TextureRect
var _icon_for: Callable
var _names: Dictionary = {}          # def_id -> nome normalizzato (per la ricerca)


## mode: "create" | "edit". `discovered` = def_id degli oggetti scoperti, nell'ordine del Compendio.
func setup(dlg_mode: String, name0: String, icon0: String, max_chars: int, discovered: Array, icon_for: Callable) -> void:
	max_len = maxi(1, max_chars)
	icon_def = icon0
	_icon_for = icon_for
	_all_ids = discovered.duplicate()
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title = tr("UI_BANKG_TABDLG_NEW") if dlg_mode == "create" else tr("UI_BANKG_TABDLG_EDIT")
	ok_button_text = tr("UI_BANKG_TABDLG_CREATE") if dlg_mode == "create" else tr("UI_BANKG_TABDLG_SAVE")
	cancel_button_text = tr("UI_BANKG_TABDLG_CANCEL")
	min_size = Vector2i(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var nl := Label.new()
	nl.text = Loc.tf("UI_BANKG_TABDLG_NAME", {"n": max_len})
	box.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.max_length = max_len
	name_edit.text = name0.substr(0, max_len)
	name_edit.placeholder_text = tr("UI_BANKG_TABDLG_NAME_PH")
	name_edit.text_changed.connect(func(_t: String) -> void: _validate())
	box.add_child(name_edit)
	register_text_enter(name_edit)
	var il := HBoxContainer.new()
	var lab := Label.new()
	lab.text = tr("UI_BANKG_TABDLG_ICON")
	il.add_child(lab)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(32, 32)
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	il.add_child(_preview)
	box.add_child(il)
	icon_search = LineEdit.new()
	icon_search.name = "IconSearch"
	icon_search.placeholder_text = tr("UI_BANKG_TABDLG_ICON_SEARCH")
	icon_search.clear_button_enabled = true
	icon_search.text_changed.connect(_filter_icons)
	box.add_child(icon_search)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(440, 200)
	box.add_child(holder)
	grid = VirtualGrid.new()
	grid.name = "IconGrid"
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.set_cell_size(ICON_CELL, ICON_CELL)
	grid.make_cell = _make_icon_cell
	grid.bind_cell = _bind_icon_cell
	holder.add_child(grid)
	if _all_ids.is_empty():
		var none := Label.new()
		none.text = tr("UI_BANKG_TABDLG_NO_ICONS")
		none.theme_type_variation = &"MutedLabel"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(none)
	for d in _all_ids:
		_names[str(d)] = BankSystem.search_norm(Loc.t(DataRegistry.item(str(d)).get("name", {})))
	_filter_icons("")
	_set_icon(icon0)
	_validate()
	confirmed.connect(func() -> void:
		var nm := BankSystem.sanitize_tab_name(name_edit.text, max_len)
		if not nm.is_empty():
			done.emit(nm, icon_def))


func _validate() -> void:
	get_ok_button().disabled = BankSystem.sanitize_tab_name(name_edit.text, max_len).is_empty()


func _filter_icons(text: String) -> void:
	var q := BankSystem.search_norm(text)
	_ids.clear()
	for d in _all_ids:
		if q.is_empty() or str(_names.get(str(d), "")).contains(q):
			_ids.append(d)
	grid.set_count(_ids.size())
	grid.rebind()


func _make_icon_cell() -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(ICON_CELL - 4.0, ICON_CELL - 4.0)
	b.size = b.custom_minimum_size
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.toggle_mode = true
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.pressed.connect(func() -> void: _set_icon(str(b.get_meta("def", ""))))
	return b


func _bind_icon_cell(cell: Control, index: int) -> void:
	var d := str(_ids[index])
	var b := cell as Button
	b.set_meta("def", d)
	b.icon = _icon_for.call(d) if _icon_for.is_valid() else null
	b.tooltip_text = Loc.t(DataRegistry.item(d).get("name", {}))
	b.set_pressed_no_signal(d == icon_def)


func _set_icon(def_id: String) -> void:
	icon_def = def_id
	_preview.texture = _icon_for.call(def_id) if (def_id != "" and _icon_for.is_valid()) else null
	if grid != null:
		grid.rebind()


# ------------------------------------------------------------------ finestre e menù delle schede (chiamate da BankScreen)
## Funzioni statiche: `scr` è la BankScreen che le apre (le finestre sono sue figlie). Stanno qui perché il Deposito si apre
## dentro il budget di costruzione (doc 02 §7.1): questo file si compila solo al primo uso.

static func discovered_icons(bank: BankSystem) -> Array:
	var cx := Game.system("codex") as CodexSystem
	var out: Array = []
	if cx == null:
		return out
	for d in cx.collectible_ids():
		if cx.item_seen(str(d)) or bank.count(str(d)) > 0:
			out.append(str(d))
	return out


## [+] / «Nuova scheda…»: nome predefinito «Scheda N», icona = il primo oggetto spostato. `keys` = voci da metterci subito.
static func create_flow(scr, keys: Array = []) -> Window:
	if not scr._bank.can_add_tab():
		EventBus.notice.emit("warning", Loc.tf("UI_BANKG_TAB_MAX", {"n": scr._bank.max_tabs()}), {})
		return null
	var icon0 := ""
	for k in keys:
		if str(k).begins_with("s:"):
			icon0 = str(k).substr(2)
		elif str(k).begins_with("u:"):
			icon0 = str(scr._bank.get_instance(str(k).substr(2)).get("def", ""))
		if icon0 != "":
			break
	var dlg := BankTabDialog.new()
	dlg.setup("create", Loc.tf("UI_BANKG_TAB_DEFAULT_N", {"n": scr._bank.tab_count() + 1}), icon0, scr._bank.tab_name_max(),
		discovered_icons(scr._bank as BankSystem), Callable(scr, "_icon_for"))
	var moved := keys.duplicate()
	dlg.done.connect(func(nm: String, icon: String) -> void:
		var tid: String = scr._bank.create_tab(nm, icon)
		if tid != "" and not moved.is_empty():
			scr._announce_move(scr._bank.assign_to_tab(moved, tid), tid)
			scr.clear_selection()
		if tid != "":
			scr._select_tab(tid))
	scr._popup_dialog(dlg)
	scr.last_tab_dialog = dlg
	return dlg


static func edit_flow(scr, tab_id: String) -> Window:
	var t: Dictionary = scr._bank.get_tab(tab_id)
	if t.is_empty():
		return null
	var dlg := BankTabDialog.new()
	dlg.setup("edit", str(t.name), str(t.get("icon", "")), scr._bank.tab_name_max(), discovered_icons(scr._bank as BankSystem), Callable(scr, "_icon_for"))
	dlg.done.connect(func(nm: String, icon: String) -> void:
		scr._bank.rename_tab(tab_id, nm)
		scr._bank.set_tab_icon(tab_id, icon)
		scr._mark_dirty())
	scr._popup_dialog(dlg)
	scr.last_tab_dialog = dlg
	return dlg


## Elimina con conferma se la scheda non è vuota: le caselle tornano in Tutto, nessun oggetto si perde.
static func delete_flow(scr, tab_id: String) -> ConfirmationDialog:
	var t: Dictionary = scr._bank.get_tab(tab_id)
	if t.is_empty():
		return null
	var n := int(scr._bank.tab_counts().get(tab_id, 0))
	if n <= 0:
		scr._do_delete_tab(tab_id)
		return null
	var dlg := ConfirmationDialog.new()
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dlg.title = scr.tr("UI_BANKG_TAB_DELETE")
	dlg.dialog_text = Loc.tf("UI_BANKG_TAB_DELETE_ASK", {"name": str(t.name), "n": n})
	dlg.dialog_autowrap = true
	dlg.ok_button_text = scr.tr("UI_BANKG_TAB_DELETE_OK")
	dlg.cancel_button_text = scr.tr("UI_BANKG_TABDLG_CANCEL")
	dlg.confirmed.connect(scr._do_delete_tab.bind(tab_id))
	scr._popup_dialog(dlg)
	dlg.get_cancel_button().call_deferred("grab_focus")
	return dlg


## «Blocca tutta la scheda», con conferma.
static func lock_flow(scr, tab_id: String) -> ConfirmationDialog:
	var t: Dictionary = scr._bank.get_tab(tab_id)
	if t.is_empty():
		return null
	var dlg := ConfirmationDialog.new()
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dlg.title = scr.tr("UI_BANKG_TAB_LOCK_ALL")
	dlg.dialog_text = Loc.tf("UI_BANKG_TAB_LOCK_ASK", {"name": str(t.name), "n": int(scr._bank.tab_counts().get(tab_id, 0))})
	dlg.dialog_autowrap = true
	dlg.confirmed.connect(scr.lock_tab.bind(tab_id))
	scr._popup_dialog(dlg)
	return dlg


static func lock_all(scr, tab_id: String) -> int:
	var n := 0
	for k in (scr._bank.state.tab_of as Dictionary).keys():
		if str(scr._bank.state.tab_of[k]) != tab_id:
			continue
		var key := str(k)
		if key.begins_with("s:") and scr._bank.state.stacks.has(key.substr(2)) and not scr._bank.is_def_locked(key.substr(2)):
			scr._bank.set_def_locked(key.substr(2), true)
			n += 1
		elif key.begins_with("u:") and not scr._bank.get_instance(key.substr(2)).is_empty() and not scr._bank.is_instance_locked(key.substr(2)):
			scr._bank.set_instance_locked(key.substr(2), true)
			n += 1
	scr._mark_dirty()
	return n


## Menù «Sposta in…» (tasto Maiusc+M, pulsante della selezione, tasto destro): le schede, «Nuova scheda…», «Togli dalla scheda».
static func move_menu(scr, keys: Array, at: Vector2) -> PopupMenu:
	var ok_keys: Array = []
	for k in keys:
		if scr._bank.can_assign(str(k)):
			ok_keys.append(str(k))
	if ok_keys.is_empty():
		EventBus.notice.emit("info", scr.tr("UI_BANKG_MOVE_NONE"), {})
		return null
	var pm := PopupMenu.new()
	pm.name = "MoveMenu"
	pm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var ids: Array = []
	for t in scr._bank.tabs():
		pm.add_item(str(t.name), ids.size())
		ids.append(str(t.id))
	if not ids.is_empty():
		pm.add_separator()
	pm.add_item(scr.tr("UI_BANKG_MOVE_NEW"), 1000)
	pm.set_item_disabled(pm.get_item_index(1000), not scr._bank.can_add_tab())
	var in_tab := false
	for k in ok_keys:
		in_tab = in_tab or scr._bank.tab_of(str(k)) != ""
	if in_tab:
		pm.add_item(scr.tr("UI_BANKG_MOVE_OUT"), 1001)
	pm.id_pressed.connect(func(id: int) -> void:
		if id == 1000:
			scr.open_create_tab(ok_keys)
		elif id == 1001:
			scr._announce_move(scr._bank.assign_to_tab(ok_keys, ""), "")
			scr._mark_dirty()
		elif id >= 0 and id < ids.size():
			scr._announce_move(scr._bank.assign_to_tab(ok_keys, str(ids[id])), str(ids[id]))
			if scr._mode != "":
				scr.clear_selection()
			scr._mark_dirty())
	pm.popup_hide.connect(pm.queue_free)
	scr.add_child(pm)
	pm.position = Vector2i(at)
	pm.popup()
	scr.last_popup = pm
	return pm


static func suggested_flow(scr) -> ConfirmationDialog:
	var plan: Array = scr.suggested_plan()
	var dlg := ConfirmationDialog.new()
	dlg.name = "SuggestedDialog"
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dlg.title = scr.tr("UI_BANKG_SUGGEST_BTN")
	dlg.dialog_autowrap = true
	dlg.ok_button_text = scr.tr("UI_BANKG_TABDLG_CREATE")
	dlg.cancel_button_text = scr.tr("UI_BANKG_TABDLG_CANCEL")
	var lines := PackedStringArray([scr.tr("UI_BANKG_SUGGEST_HELP")])
	for p in plan:
		lines.append("• " + Loc.tf("UI_BANKG_SUGGEST_ROW", {"name": str(p.name), "n": (p.keys as Array).size()}))
	if plan.is_empty():
		lines.append(scr.tr("UI_BANKG_SUGGEST_NONE"))
	dlg.dialog_text = "\n".join(lines)
	dlg.get_ok_button().disabled = plan.is_empty()
	dlg.confirmed.connect(func() -> void: scr.apply_suggested(plan))
	scr._popup_dialog(dlg)
	dlg.min_size = Vector2i(420, 0)
	return dlg


# ------------------------------------------------------------------ azioni del Deposito eseguite di rado (tasti, selezione, vendita,
# trascinamento, schede suggerite, ricerca): stesse funzioni di BankScreen, qui per non pesare sull'apertura della schermata.

## Costante della BankScreen (GROUPS, SUGGESTED_GROUPS): una sola definizione, letta dallo script della schermata.
static func _screen_const(scr, cname: String) -> Array:
	return Array((scr.get_script() as GDScript).get_script_constant_map().get(cname, []))

## Esegue un'azione dei tasti locali (ShortcutMap.BANK_TABLE). Ritorna true se il tasto è stato usato.
static func key_action(scr, act: String) -> bool:
	match act:
		"search":
			scr._search.grab_focus()
		"lock":
			if scr._mode != "" and not scr._selection.is_empty():
				scr.lock_selection()
			elif not scr._selected_entry().is_empty():
				scr._on_toggle_lock()                  # F16: «L» da sola è il cassetto (scorciatoia globale), per questo serve Maiusc
		"move":
			var keys: Array = scr._move_keys()
			if keys.is_empty():
				return true
			scr.open_move_menu(keys, scr.get_global_mouse_position())
		"sort":
			scr._sort_opt.show_popup()
		"select":
			scr.toggle_mode("select")
		"sell_mode":
			scr.toggle_mode("sell")
		"select_all":
			if scr._mode == "":
				return false
			scr.select_all_visible()
		"tab_prev", "tab_next":
			scr.cycle_tab(-1 if act == "tab_prev" else 1)
		"rename":
			if not scr._is_user_tab(scr._tab):
				return false
			scr.open_edit_tab(scr._tab)
		"tab_left", "tab_right":
			if not scr._is_user_tab(scr._tab):
				return false
			scr._on_tab_move(scr._tab, -1 if act == "tab_left" else 1)
		"escape":
			return scr.escape_chain()
		_:
			return false
	return true


static func empty_action(scr) -> void:
	match str(scr._empty_btn.get_meta("act", "")):
		"exit":
			scr.exit_mode()
		"clear_search":
			scr._search.text = ""
			scr._on_query("")
		"clear_filters":
			scr._only_locked = false
			scr._only_worn = false
			scr._group = "all"
			scr._sync_group_ui()
			scr._update_menu_labels()
			scr._mark_dirty()
		"select_move":
			scr._select_tab("")
			scr.enter_mode("select")
		"go_smithing":
			scr._go_screen("skill:smithing", {"skill": "smithing"})
		"go_skills":
			var t := ShortcutMap.queue_target()
			if not t.is_empty():
				scr._go_screen(str(t.id), t.params)


static func go_screen(scr, id: String, params: Dictionary) -> void:
	var n: Node = scr.get_parent()
	while n != null and not n.has_method("show_screen"):
		n = n.get_parent()
	if n != null:
		n.call("show_screen", id, params)


static func cycle_tab(scr, dir: int) -> void:
	var order: Array = scr._tabs_bar.order() if scr._tabs_bar != null else ["", BankTabsBar.ARMORY]
	order.erase(BankTabsBar.RESULTS)
	if order.is_empty():
		return
	var i := order.find(scr._tab)
	scr._select_tab(str(order[posmod(i + dir, order.size())]))


## Trascinamento di una casella (o della selezione) verso la barra delle schede. Il gear non si assegna: non si trascina.
static func cell_drag(scr, _at: Vector2, cell: Control) -> Variant:
	var key := str(cell.get_meta("key", ""))
	var e: Dictionary = scr._entry_by_key(key)
	if e.is_empty():
		return null
	var keys: Array = []
	if scr._mode != "" and scr._selection.has(key):
		keys = scr._move_keys()
	elif scr._bank.can_assign(str(e.akey)):
		keys = [str(e.akey)]
	if keys.is_empty():
		return null
	var pv := HBoxContainer.new()
	var ic := TextureRect.new()
	ic.texture = scr._icon_for(str(e.def))
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv.add_child(ic)
	if keys.size() > 1:
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = "×%d" % keys.size()
		pv.add_child(l)
	if cell.get_viewport() != null and cell.get_viewport().gui_is_dragging():
		cell.set_drag_preview(pv)          # solo durante un trascinamento vero (si chiama da _get_drag_data)
	else:
		pv.free()
	return {"type": BankTabsBar.DRAG_KEYS, "keys": keys}


## «Crea schede suggerite» (doc 02 §5.1): Materiali / Provviste / Casse / Collezione dai gruppi esistenti, con le voci NON
## ancora in una scheda. Mai automatico: anteprima con i conteggi e conferma. Ritorna il piano [{group, name, icon, keys}].
static func suggested_plan(scr) -> Array:
	var plan: Array = []
	var room: int = scr._bank.max_tabs() - scr._bank.tab_count()
	for gid in _screen_const(scr, "SUGGESTED_GROUPS"):
		if plan.size() >= room:
			break
		var keys: Array = []
		var icon := ""
		for def_id in scr._bank.state.stacks:
			var ak := BankSystem.tab_key(str(def_id), "")
			if scr._info(str(def_id)).group == gid and scr._bank.tab_of(ak) == "" and scr._bank.can_assign(ak):
				keys.append(ak)
				if icon == "":
					icon = str(def_id)
		for inst in scr._bank.state.instances:
			var uk := BankSystem.tab_key("", str(inst.uid))
			if scr._info(str(inst.def)).group == gid and scr._bank.tab_of(uk) == "" and scr._bank.can_assign(uk):
				keys.append(uk)
				if icon == "":
					icon = str(inst.def)
		if keys.is_empty():
			continue
		var key := ""
		for g in _screen_const(scr, "GROUPS"):
			if g.id == gid:
				key = str(g.key)
		plan.append({"group": gid, "name": scr.tr(key), "icon": icon, "keys": keys})
	return plan


static func apply_suggested(scr, plan: Array) -> int:
	var made := 0
	for p in plan:
		var tid: String = scr._bank.create_tab(str(p.name), str(p.icon))
		if tid == "":
			break
		scr._bank.assign_to_tab(p.keys, tid)
		made += 1
	scr.dismiss_welcome()
	scr._mark_dirty()
	return made


## Blocca la selezione (o la sblocca se è già tutta bloccata): un clic, nessuna conferma (il blocco protegge, non distrugge).
static func lock_selection(scr) -> void:
	if scr._selection.is_empty():
		return
	var all_locked := true
	for k in scr._selection:
		var s: Dictionary = scr._selection[k]
		var locked: bool = scr._bank.is_instance_locked(str(s.uid)) if str(s.uid) != "" else scr._bank.is_def_locked(str(s.def))
		all_locked = all_locked and locked
	for k in scr._selection:
		var s: Dictionary = scr._selection[k]
		if str(s.uid) != "":
			scr._bank.set_instance_locked(str(s.uid), not all_locked)
		elif scr._bank.state.stacks.has(str(s.def)):
			scr._bank.set_def_locked(str(s.def), not all_locked)
	if scr._mode == "sell":
		scr._selection.clear()                         # in vendita i bloccati non sono più selezionabili
	scr._mark_dirty()


## Voci per l'anteprima: [{def, uid, qty}] (per le pile l'intera quantità vendibile: si cambia nell'anteprima).
static func selection_picks(scr) -> Array:
	var out: Array = []
	for k in scr._selection:
		var s: Dictionary = scr._selection[k]
		out.append({"def": str(s.def), "uid": str(s.uid), "qty": scr._bank.sellable_count(str(s.def)) if str(s.uid) == "" else 1})
	return out


## «Vendi…»: PASSAGGIO 2 (anteprima con «Torna indietro» predefinito). Nessuna vendita senza questa finestra.
static func sell_flow(scr) -> Window:
	var picks: Array = scr.selection_picks()
	if picks.is_empty():
		return null
	var dlg = (load("res://src/ui/screens/SellDialog.gd") as GDScript).new()
	dlg.setup_selection(picks, int(scr._bank.ui_rules().get("sell_confirm_guard_ms", 0)))
	dlg.sold.connect(func(_g: int, _n: int) -> void:
		scr.clear_selection()
		scr._mark_dirty())
	dlg.canceled.connect(dlg.queue_free)
	dlg.visibility_changed.connect(func() -> void:
		if not dlg.visible and is_instance_valid(dlg):
			dlg.queue_free())
	scr.add_child(dlg)
	dlg.popup_centered()
	scr.last_sell_dialog = dlg
	return dlg


## Tabelle dei nomi per gli operatori della ricerca (cat: q: rar:), normalizzate, una volta per lingua.
static func search_names(scr) -> Dictionary:
	var loc := Loc.locale()
	if str(scr._names_cache.get("loc", "")) == loc:
		return scr._names_cache.names
	var cats: Dictionary = {}
	var groups: Dictionary = {}
	for g in _screen_const(scr, "GROUPS"):
		for c in g.cats:
			if not groups.has(c):
				groups[c] = []
			(groups[c] as Array).append(BankSystem.search_norm(scr.tr(str(g.key))))
	for c in SellRules.CATEGORIES:
		var k := "UI_UIA_CAT_" + str(c).to_upper()
		var t: String = scr.tr(k)
		if t != k:
			if not cats.has(c):
				cats[c] = []
			(cats[c] as Array).append(BankSystem.search_norm(t))
	var qn: Dictionary = {}
	for q in SellRules.quality_ids():
		qn[q] = [BankSystem.search_norm(scr._quality_label(str(q)))]
	var rn: Dictionary = {}
	for r in SellRules.RARITIES:
		var k2 := "UI_UIA_RAR_" + str(r).to_upper()
		rn[r] = [BankSystem.search_norm(scr.tr(k2))] if scr.tr(k2) != k2 else []
	var names := {"cat": cats, "cat_group": groups, "q": qn, "rar": rn}
	scr._names_cache = {"loc": loc, "names": names}
	return names


## Barre della modalità selezione / vendita (doc 02 §7.5): costruite alla prima entrata in modalità.
static func build_mode_bars(scr, root: Control) -> void:
	scr._mode_bar = PanelContainer.new()                 # barra della modalità: ambra in vendita (doc 02 §7.5), neutra in selezione
	scr._mode_bar.name = "ModeBar"
	scr._mode_bar.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.36, 0.25, 0.05, 0.95)
	sb.border_color = Color(1.0, 0.76, 0.28)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	scr._mode_bar.add_theme_stylebox_override("panel", sb)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 12)
	scr._mode_bar.add_child(mh)
	scr._mode_label = scr._dyn_label()
	scr._mode_label.name = "ModeLabel"
	scr._mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scr._mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr._mode_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	mh.add_child(scr._mode_label)
	scr._mode_exit = Button.new()
	scr._mode_exit.name = "ModeExit"
	scr._mode_exit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	scr._mode_exit.pressed.connect(Callable(scr, "exit_mode"))
	mh.add_child(scr._mode_exit)
	root.add_child(scr._mode_bar)
	scr._action_bar = HFlowContainer.new()               # «☑ 12 selezionati · circa 3.420 oro» e le azioni sulla selezione
	scr._action_bar.name = "ActionBar"
	scr._action_bar.visible = false
	scr._action_bar.add_theme_constant_override("h_separation", 8)
	scr._action_bar.add_theme_constant_override("v_separation", 4)
	scr._sel_label = scr._dyn_label(&"MonoLabel")
	scr._sel_label.name = "SelLabel"
	scr._action_bar.add_child(scr._sel_label)
	var all_b := Button.new()
	all_b.name = "SelectAll"
	all_b.text = "UI_BANKG_SEL_ALL"
	all_b.tooltip_text = "UI_BANKG_SEL_ALL_TIP"
	all_b.pressed.connect(Callable(scr, "select_all_visible"))
	scr._action_bar.add_child(all_b)
	var none_b := Button.new()
	none_b.name = "SelectNone"
	none_b.text = "UI_BANKG_SEL_NONE"
	none_b.pressed.connect(Callable(scr, "clear_selection"))
	scr._action_bar.add_child(none_b)
	scr._move_btn = Button.new()
	scr._move_btn.name = "MoveSel"
	scr._move_btn.text = "UI_BANKG_MOVE_TO"
	scr._move_btn.tooltip_text = "UI_BANKG_MOVE_TIP"
	scr._move_btn.pressed.connect(func() -> void: scr.open_move_menu(scr._move_keys(), (scr._move_btn as Control).get_global_rect().end))
	scr._action_bar.add_child(scr._move_btn)
	scr._lock_sel_btn = Button.new()
	scr._lock_sel_btn.name = "LockSel"
	scr._lock_sel_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	scr._lock_sel_btn.pressed.connect(Callable(scr, "lock_selection"))
	scr._action_bar.add_child(scr._lock_sel_btn)
	scr._sell_sel_btn = Button.new()
	scr._sell_sel_btn.name = "SellSel"
	scr._sell_sel_btn.text = "UI_BANKG_SELL_SEL"
	scr._sell_sel_btn.pressed.connect(Callable(scr, "open_selection_sell"))
	scr._action_bar.add_child(scr._sell_sel_btn)
	root.add_child(scr._action_bar)
