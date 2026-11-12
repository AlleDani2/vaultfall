class_name CrateMultiReveal
extends VBoxContainer
## Rullo per le aperture multiple ×5 / ×10 (docs/09 §6, docs/24 R-LEG-5). SOLO PRESENTAZIONE: riceve i risultati già
## estratti da CrateSystem.open() e li scopre uno dopo l'altro (rarità crescente, la migliore per ultima, evidenziata).
## Niente tessere finte, niente quasi-vincite: ogni carta è un risultato vero. Filtro per rarità sempre disponibile.
## "Riduci animazioni": tutto subito, senza tween. Salta: scopre subito tutto il resto.

signal tick_sound(volume: float, pitch: float)
signal reveal_sound(rarity: String)
signal selected(index: int)
signal finished

const CARD := Vector2(124, 118)
const TOTAL_S := 2.4           # durata massima della sequenza (la «rapida» usa QUICK_S)
const STEP_MAX_S := 0.30
const QUICK_S := 0.8

var playing: bool = false
var filter: String = ""        # "" = tutte, altrimenti id di rarità

var _results: Array = []
var _order: Array[int] = []    # indici dei risultati nell'ordine di scoperta
var _cards: Array = []         # carta per indice di risultato
var _best: int = -1
var _revealed: int = 0
var _tween: Tween
var _flow: HFlowContainer
var _filters: HFlowContainer
var _banner: Label
var _summary: Label
var _filter_btns: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_banner = Label.new()
	_banner.theme_type_variation = &"SectionLabel"
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.visible = false
	add_child(_banner)
	_summary = Label.new()
	_summary.theme_type_variation = &"MutedLabel"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_filters = HFlowContainer.new()
	add_child(_filters)
	_flow = HFlowContainer.new()
	add_child(_flow)


func best_index() -> int:
	return _best


func results() -> Array:
	return _results


func card(i: int) -> Control:
	return _cards[i] if i >= 0 and i < _cards.size() else null


func revealed_count() -> int:
	return _revealed


## Ordine di scoperta: rarità crescente (a parità, ordine di apertura); la migliore è sempre l'ultima.
static func reveal_order(list: Array) -> Array[int]:
	var idx: Array[int] = []
	for i in list.size():
		idx.append(i)
	var best := CrateSystem.best_result_index(list)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ra := CrateSystem.RARITIES.find(str(list[a].rarity))
		var rb := CrateSystem.RARITIES.find(str(list[b].rarity))
		return ra < rb if ra != rb else a < b)
	if best >= 0:
		idx.erase(best)
		idx.append(best)
	return idx


## Prepara le carte (nascoste) e avvia la sequenza. `quick`: apertura rapida (0,8 s in totale).
func play(list: Array, quick: bool = false) -> void:
	stop()
	_results = list
	_order = reveal_order(list)
	_best = CrateSystem.best_result_index(list)
	_revealed = 0
	filter = ""
	for c in _flow.get_children():
		c.queue_free()
	_cards.clear()
	for r in list:
		var tip := CrateUi.rarity_label(str(r.rarity))
		if r.kind == "skin" or r.kind == "relic":
			tip += "\n" + CrateUi.instance_text(r.instance)
		else:
			tip += "\n" + CrateUi.def_name(str(r.def_id))
		var cell := CrateUi.cell(str(r.def_id), str(r.rarity), CrateUi.rarity_name(str(r.rarity)), tip, CARD)
		cell.visible = false
		var idx := _cards.size()
		cell.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				selected.emit(idx))
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		_flow.add_child(cell)
		_cards.append(cell)
	_banner.visible = false
	_summary.text = ""
	_build_filters()
	playing = true
	if CrateUi.reduce_motion() or list.is_empty():
		_reveal_all(false)
		return
	var total := QUICK_S if quick else TOTAL_S
	var step := minf(STEP_MAX_S, total / float(maxi(1, _order.size())))
	_tween = create_tween()
	for k in _order.size():
		_tween.tween_interval(step)
		_tween.tween_callback(_reveal_next)
	_tween.tween_callback(_done)


func skip() -> void:
	if not playing:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_reveal_all(not CrateUi.reduce_motion())


func stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	playing = false


func _reveal_all(animate: bool) -> void:
	while _revealed < _order.size():
		_reveal_next(animate and _revealed >= _order.size() - 1)
	_done()


func _reveal_next(animate: bool = true) -> void:
	if _revealed >= _order.size():
		return
	var i := _order[_revealed]
	_revealed += 1
	var c: Control = _cards[i]
	c.visible = _passes(i)
	var rarity := str(_results[i].rarity)
	var prog := float(_revealed) / float(maxi(1, _order.size()))
	tick_sound.emit(lerpf(0.5, 1.0, prog), lerpf(0.9, 1.4, prog))
	if i == _best or CrateSystem.RARITIES.find(rarity) >= CrateSystem.RARITIES.find("legendary"):
		reveal_sound.emit(rarity)
	if c.visible and (animate or i == _best):
		_fx_card.call_deferred(c, rarity, i == _best)           # dopo il riordino del contenitore: posizione vera
	if animate and not CrateUi.reduce_motion() and c.visible:
		c.pivot_offset = CARD * 0.5
		c.scale = Vector2(0.7, 0.7)
		create_tween().tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rivelazione di una carta (risultato già estratto): solo epiche o migliori e la migliore, per non fare rumore.
func _fx_card(c: Control, rarity: String, is_best: bool) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or not c.visible:
		return
	if is_best or FxPalette.rarity_t(rarity) >= 0.25:
		Fx.reveal(c.get_global_rect(), rarity)


func _done() -> void:
	if not playing:
		return
	playing = false
	_show_best()
	_summary.text = _summary_text()
	finished.emit()


func _show_best() -> void:
	if _best < 0:
		return
	var r: Dictionary = _results[_best]
	_banner.text = Loc.tf("UI_CRATES2_BEST", {"name": CrateUi.def_name(str(r.def_id)), "rarity": CrateUi.rarity_label(str(r.rarity))})
	_banner.add_theme_color_override("font_color", CrateUi.rarity_color(str(r.rarity)))
	_banner.visible = true
	var c: PanelContainer = _cards[_best]
	c.theme_type_variation = UiKit.rarity_variation(str(r.rarity), true)     # la migliore ha la cornice grande (anche con «riduci animazioni»)
	c.tooltip_text = TranslationServer.translate("UI_CRATES2_BEST_TAG") + "\n" + c.tooltip_text
	if not CrateUi.reduce_motion() and is_inside_tree():
		c.pivot_offset = CARD * 0.5
		c.scale = Vector2(1.18, 1.18)
		create_tween().tween_property(c, "scale", Vector2(1.06, 1.06), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func counts() -> Dictionary:
	var out := {}
	for r in _results:
		out[str(r.rarity)] = int(out.get(str(r.rarity), 0)) + 1
	return out


func _summary_text() -> String:
	var parts := PackedStringArray()
	var cn := counts()
	for rar in CrateSystem.RARITIES:
		if cn.has(rar):
			parts.append("%s %d" % [CrateUi.rarity_symbol(rar), int(cn[rar])])
	return Loc.tf("UI_CRATES_FOUND_N", {"n": _results.size()}) + " · " + " · ".join(parts)


func _passes(i: int) -> bool:
	return filter.is_empty() or str(_results[i].rarity) == filter


func set_filter(rarity: String) -> void:
	filter = rarity
	for i in _cards.size():
		var revealed := _order.find(i) < _revealed
		(_cards[i] as Control).visible = revealed and _passes(i)
	for k in _filter_btns:
		(_filter_btns[k] as Button).button_pressed = (k == filter)


func visible_count() -> int:
	var n := 0
	for c in _cards:
		if (c as Control).visible:
			n += 1
	return n


func _build_filters() -> void:
	for c in _filters.get_children():
		c.queue_free()
	_filter_btns.clear()
	var cn := counts()
	var all := Button.new()
	all.text = TranslationServer.translate("UI_CRATES2_FILTER_ALL")
	all.toggle_mode = true
	all.button_pressed = true
	all.pressed.connect(func() -> void: set_filter(""))
	_filters.add_child(all)
	_filter_btns[""] = all
	for rar in CrateSystem.RARITIES:
		if not cn.has(rar):
			continue
		var b := Button.new()
		b.text = "%s %d" % [CrateUi.rarity_label(rar), int(cn[rar])]
		b.toggle_mode = true
		b.add_theme_color_override("font_color", CrateUi.rarity_color(rar))
		var rr: String = rar
		b.pressed.connect(func() -> void: set_filter(rr))
		_filters.add_child(b)
		_filter_btns[rar] = b
