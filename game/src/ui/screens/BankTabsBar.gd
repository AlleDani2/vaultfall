class_name BankTabsBar
extends HFlowContainer
## Barra delle schede del Deposito (F17, docs/ui_redesign/02 §5.1): [Risultati (n)] [Tutto n] [Armeria n/tetto] [schede del
## giocatore ≤ max_tabs] [+] [⋮]. Solo presentazione: emette segnali, BankScreen chiama BankSystem.
## I nomi delle schede sono DATI DELL'UTENTE: si mostrano con auto_translate spento (mai tradotti, mai markup). Ogni azione
## che si fa trascinando ha un'alternativa senza trascinamento (menù del tasto destro, F2, Alt+←/→, WCAG 2.5.7).

signal tab_chosen(tab_id: String)
signal create_requested
signal edit_requested(tab_id: String, what: String)      # "rename" | "icon" | "delete" | "lock_all"
signal move_requested(tab_id: String, delta: int)
signal keys_dropped(tab_id: String, keys: Array)         # ALL = togli dalla scheda, NEW = nuova scheda con queste voci
signal suggested_requested

const ALL := ""
const ARMORY := "~armory"
const RESULTS := "~results"
const NEW := "~new"
const DRAG_KEYS := "bank_keys"
const DRAG_TAB := "bank_tab"
## Voci del menù del tasto destro di una scheda.
const M_RENAME := 0
const M_ICON := 1
const M_LEFT := 2
const M_RIGHT := 3
const M_LOCK := 4
const M_DELETE := 5
const L_SUGGESTED := 1000

var buttons: Dictionary = {}          # id della scheda -> Button
var add_btn: Button
var list_btn: MenuButton
var current: String = ALL
## Callable(def_id) -> Texture2D per le icone delle schede (lo passa BankScreen: stessa cache di IconLib).
var icon_for: Callable
var _sig := ""
var _group := ButtonGroup.new()
var _order: Array = []                # id nell'ordine della barra (per [⋮] e per [ / ])


func _init() -> void:
	name = "TabsBar"
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)


## Ricostruisce la barra solo se è cambiato qualcosa di visibile. `tabs` = BankSystem.tabs(); `counts` = tab_counts();
## `results_n` < 0 = nessuna ricerca attiva (niente scheda Risultati).
func update_bar(tabs: Array, counts: Dictionary, all_n: int, armory_text: String, armory_tip: String, results_n: int,
		current_id: String, can_add: bool, add_tip: String) -> void:
	current = current_id
	var sig := JSON.stringify([tabs, counts, all_n, armory_text, results_n, current_id, can_add, add_tip, Loc.locale()])
	if sig == _sig:
		return
	_sig = sig
	for c in get_children():
		remove_child(c)
		c.queue_free()
	buttons.clear()
	_order.clear()
	_group = ButtonGroup.new()
	if results_n >= 0:
		_add_fixed(RESULTS, Loc.tf("UI_BANKG_TAB_RESULTS", {"n": NumberFormat.fmt(float(results_n))}), "UI_BANKG_TAB_RESULTS_TIP")
	_add_fixed(ALL, Loc.tf("UI_BANKG_TAB_ALL_N", {"n": NumberFormat.fmt(float(all_n))}), "UI_BANKG_TAB_ALL_TIP")
	_add_fixed(ARMORY, armory_text, armory_tip)
	for t in tabs:
		var b := _make_button(str(t.id))
		b.text = "%s %s" % [str(t.name), NumberFormat.fmt(float(counts.get(str(t.id), 0)))]
		b.tooltip_text = Loc.tf("UI_BANKG_TAB_TIP", {"name": str(t.name)})
		if str(t.get("icon", "")) != "" and icon_for.is_valid():
			b.icon = icon_for.call(str(t.icon))
		b.gui_input.connect(_on_tab_input.bind(str(t.id)))
	add_btn = Button.new()
	add_btn.name = "AddTab"
	add_btn.text = "UI_BANKG_TAB_ADD"
	add_btn.disabled = not can_add
	add_btn.tooltip_text = add_tip
	add_btn.pressed.connect(func() -> void: create_requested.emit())
	add_btn.set_drag_forwarding(Callable(), _can_drop.bind(NEW), _drop.bind(NEW))
	add_child(add_btn)
	list_btn = MenuButton.new()
	list_btn.name = "TabList"
	list_btn.text = "UI_BANKG_TAB_LIST"
	list_btn.tooltip_text = "UI_BANKG_TAB_LIST_TIP"
	list_btn.flat = false
	var pop := list_btn.get_popup()
	pop.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for i in _order.size():
		var bb: Button = buttons[_order[i]]
		pop.add_item(bb.text, i)
	pop.add_separator()
	pop.add_item(tr("UI_BANKG_SUGGEST_BTN"), L_SUGGESTED)
	pop.id_pressed.connect(func(id: int) -> void:
		if id == L_SUGGESTED:
			suggested_requested.emit()
		elif id >= 0 and id < _order.size():
			tab_chosen.emit(str(_order[id])))
	add_child(list_btn)


func _add_fixed(tab_id: String, text: String, tip: String) -> void:
	var b := _make_button(tab_id)
	b.text = text
	b.tooltip_text = tr(tip)         # il bottone non si traduce da solo (auto_translate spento): la chiave del suggerimento sì, a mano


func _make_button(tab_id: String) -> Button:
	var b := Button.new()
	b.name = "Tab_" + (tab_id.trim_prefix("~") if tab_id != ALL else "all")
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # nomi del giocatore e numeri: mai tradotti
	b.toggle_mode = true
	b.button_group = _group
	b.button_pressed = tab_id == current
	b.expand_icon = false
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST                # icona 32 px a fattore 1: nitida, file non toccato
	b.pressed.connect(func() -> void: tab_chosen.emit(tab_id))
	var user := not tab_id.begins_with("~") and tab_id != ALL
	b.set_drag_forwarding(_tab_drag.bind(tab_id) if user else Callable(), _can_drop.bind(tab_id), _drop.bind(tab_id))
	add_child(b)
	buttons[tab_id] = b
	_order.append(tab_id)
	return b


## Ordine delle schede nella barra (Risultati, Tutto, Armeria, schede del giocatore).
func order() -> Array:
	return _order.duplicate()


## Tasto destro / doppio clic / F2 / Alt+←→ su una scheda del giocatore.
func _on_tab_input(event: InputEvent, tab_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			open_tab_menu(tab_id, get_global_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			edit_requested.emit(tab_id, "rename")
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F2:
			edit_requested.emit(tab_id, "rename")
			accept_event()
		elif k.alt_pressed and (k.keycode == KEY_LEFT or k.keycode == KEY_RIGHT):
			move_requested.emit(tab_id, -1 if k.keycode == KEY_LEFT else 1)
			accept_event()
		elif k.keycode == KEY_MENU or (k.keycode == KEY_F10 and k.shift_pressed):
			open_tab_menu(tab_id, (buttons[tab_id] as Control).get_global_rect().get_center())
			accept_event()


func open_tab_menu(tab_id: String, at: Vector2) -> PopupMenu:
	var pm := PopupMenu.new()
	pm.name = "TabMenu"
	pm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pm.add_item(tr("UI_BANKG_TAB_RENAME"), M_RENAME)
	pm.add_item(tr("UI_BANKG_TAB_ICON"), M_ICON)
	var i := _order.find(tab_id)
	pm.add_item(tr("UI_BANKG_TAB_LEFT"), M_LEFT)
	pm.set_item_disabled(pm.get_item_index(M_LEFT), i <= _order.find(ARMORY) + 1)
	pm.add_item(tr("UI_BANKG_TAB_RIGHT"), M_RIGHT)
	pm.set_item_disabled(pm.get_item_index(M_RIGHT), i < 0 or i >= _order.size() - 1)
	pm.add_item(tr("UI_BANKG_TAB_LOCK_ALL"), M_LOCK)
	pm.add_separator()
	pm.add_item(tr("UI_BANKG_TAB_DELETE"), M_DELETE)
	pm.id_pressed.connect(_on_tab_menu.bind(tab_id))
	pm.popup_hide.connect(pm.queue_free)
	add_child(pm)
	pm.position = Vector2i(at)
	pm.popup()
	return pm


func _on_tab_menu(id: int, tab_id: String) -> void:
	if id == M_RENAME:
		edit_requested.emit(tab_id, "rename")
	elif id == M_ICON:
		edit_requested.emit(tab_id, "icon")
	elif id == M_LEFT or id == M_RIGHT:
		move_requested.emit(tab_id, -1 if id == M_LEFT else 1)
	elif id == M_LOCK:
		edit_requested.emit(tab_id, "lock_all")
	elif id == M_DELETE:
		edit_requested.emit(tab_id, "delete")


# ------------------------------------------------------------------ trascinamento (con alternativa sempre presente)

func _tab_drag(_at: Vector2, tab_id: String) -> Variant:
	var b: Button = buttons.get(tab_id)
	if b == null:
		return null
	var pv := Label.new()
	pv.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pv.text = b.text
	if b.get_viewport() != null and b.get_viewport().gui_is_dragging():
		b.set_drag_preview(pv)
	else:
		pv.free()
	return {"type": DRAG_TAB, "id": tab_id}


func _can_drop(_at: Vector2, data: Variant, target: String) -> bool:
	if not (data is Dictionary):
		return false
	var t := str((data as Dictionary).get("type", ""))
	if t == DRAG_KEYS:
		return target != ARMORY and target != RESULTS and not ((data as Dictionary).get("keys", []) as Array).is_empty() \
			and (target != NEW or (add_btn != null and not add_btn.disabled))
	if t == DRAG_TAB:
		return not target.begins_with("~") and target != ALL and target != str(data.id)
	return false


func _drop(_at: Vector2, data: Variant, target: String) -> void:
	var d: Dictionary = data
	if str(d.type) == DRAG_KEYS:
		keys_dropped.emit(target, (d.keys as Array).duplicate())
	elif str(d.type) == DRAG_TAB:
		var from := _order.find(str(d.id))
		var to := _order.find(target)
		if from >= 0 and to >= 0:
			move_requested.emit(str(d.id), to - from)
