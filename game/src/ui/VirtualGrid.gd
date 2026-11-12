class_name VirtualGrid
extends Control
## Griglia virtualizzata (docs/ui_redesign/02 §5.4), gemella di VirtualList: stesso contratto make_cell / bind_cell / set_count /
## rebind. Crea solo le celle visibili (+2 righe di margine) e le riusa mentre si scorre, quindi costa lo stesso con 20 o con
## 20.000 voci. Uso:
##   grid.cell_w = 88; grid.cell_h = 100; grid.make_cell = func() -> Control: ...; grid.bind_cell = func(cell, index): ...
##   grid.set_count(n)        # nuovo numero di voci (mantiene la posizione se possibile)
##   grid.rebind()            # rilegge i dati delle celle visibili (dati cambiati, stesso numero)
## - colonne = max(1, floor((larghezza − barra) / cell_w)), ricalcolate SOLO al resized;
## - rotella: 1 riga per scatto, Maiusc = una pagina; la barra di scorrimento è sempre visibile (niente barre auto-nascoste);
## - il fuoco è un INDICE, non un nodo: le celle sono riusate, quindi dopo ogni riassegnazione il nodo che mostra l'indice con il
##   fuoco lo riceve (grab_focus) SOLO se l'ultimo input è da tastiera o gamepad (col mouse si perderebbe il fuoco a ogni scatto);
## - frecce, Pag su/giù, Inizio/Fine spostano il fuoco di indice e scorrono quanto serve.

signal focus_index_changed(index: int)

## Passo orizzontale e verticale di una cella (la cella disegnata è un poco più piccola: lo spazio fra le celle).
var cell_w: float = 88.0
var cell_h: float = 100.0
var make_cell: Callable
var bind_cell: Callable
## Righe scorse con un colpo di rotella.
var wheel_rows: int = 1
## True se l'ultimo input veniva da tastiera o gamepad (aggiornato da _input; i test lo impostano a mano).
var last_input_keyboard: bool = false

var _count: int = 0
var _cols: int = 1
var _first_row: int = 0
var _pool: Array[Control] = []
var _bar := VScrollBar.new()
var _holder := Control.new()
var _focus_index: int = -1
var _bound_rows: int = 0              # righe di celle effettivamente legate (le visibili)


func _init() -> void:
	clip_contents = true
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_holder)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_bar.value_changed.connect(_on_scroll)
	add_child(_bar)


func _ready() -> void:
	resized.connect(_layout)
	_layout()


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		last_input_keyboard = true
	elif event is InputEventMouseButton or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 0.0):
		last_input_keyboard = false


# ------------------------------------------------------------------ interrogazioni (usate anche dai test)

func count() -> int:
	return _count


func columns() -> int:
	return _cols


## Righe intere di dati (ceil(n / colonne)).
func total_rows() -> int:
	return int(ceil(float(_count) / float(_cols)))


func first_row() -> int:
	return _first_row


func first_visible() -> int:
	return _first_row * _cols


func visible_rows() -> int:
	return maxi(1, int(ceil(size.y / cell_h)))


func pool_size() -> int:
	return _pool.size()


func focus_index() -> int:
	return _focus_index


func bar_width() -> float:
	return maxf(_bar.get_combined_minimum_size().x, 12.0)


## La cella che mostra `index` adesso (null se fuori dalla finestra visibile).
func cell_for_index(index: int) -> Control:
	var k := index - first_visible()
	if index < 0 or index >= _count or k < 0 or k >= _bound_rows * _cols or k >= _pool.size():
		return null
	return _pool[k]


# ------------------------------------------------------------------ comandi

func set_count(n: int) -> void:
	_count = maxi(0, n)
	if _focus_index >= _count:
		_focus_index = _count - 1
	_update()


## Cambia il passo (densità comoda/compatta): ricalcola colonne e righe.
func set_cell_size(w: float, h: float) -> void:
	if is_equal_approx(w, cell_w) and is_equal_approx(h, cell_h):
		return
	cell_w = w
	cell_h = h
	_layout()


func rebind() -> void:
	_fill()


func scroll_to_row(row: int) -> void:
	_bar.value = clampf(row, 0, _max_first_row())


## Porta in vista la riga che contiene `index` (scorrendo il meno possibile).
func ensure_visible(index: int) -> void:
	if index < 0 or index >= _count:
		return
	var row := floori(float(index) / float(_cols))
	var full := maxi(1, int(floor(size.y / cell_h)))
	if row < _first_row:
		scroll_to_row(row)
	elif row >= _first_row + full:
		scroll_to_row(row - full + 1)


## Sposta il fuoco su un indice (ricordato anche se la cella non è visibile). Con la tastiera il nodo lo riceve subito.
func set_focus_index(index: int, grab: bool = true) -> void:
	if _count == 0:
		_focus_index = -1
		return
	var i := clampi(index, 0, _count - 1)
	var changed := i != _focus_index
	_focus_index = i
	ensure_visible(i)
	if grab:
		_grab_focus_cell()
	if changed:
		focus_index_changed.emit(i)


# ------------------------------------------------------------------ interni

func _max_first_row() -> int:
	return maxi(0, total_rows() - maxi(1, int(floor(size.y / cell_h))))


func _layout() -> void:
	_cols = maxi(1, int(floor((size.x - bar_width()) / cell_w)))
	_update()


func _update() -> void:
	var rows := total_rows()
	var page := size.y / cell_h
	_bar.max_value = maxf(rows, 1)
	_bar.page = minf(page, float(rows)) if rows > 0 else 1.0
	_bar.step = 1.0
	_bar.visible = true                                 # sempre visibile (accessibilità), anche se non c'è nulla da scorrere
	var need := mini(_count, (visible_rows() + 2) * _cols)
	while _pool.size() < need and make_cell.is_valid():
		var c: Control = make_cell.call()
		var k := _pool.size()
		c.focus_entered.connect(_on_cell_focus.bind(c))
		_holder.add_child(c)
		_pool.append(c)
		c.set_meta("slot", k)
	_fill()


func _on_scroll(_v: float) -> void:
	_fill()


func _on_cell_focus(c: Control) -> void:
	var idx := int(c.get_meta("index", -1))
	if idx >= 0 and idx != _focus_index:
		_focus_index = idx
		focus_index_changed.emit(idx)


func _fill() -> void:
	_first_row = clampi(int(_bar.value), 0, _max_first_row())
	var vrows := visible_rows()
	_bound_rows = mini(vrows, maxi(0, total_rows() - _first_row))
	var base := _first_row * _cols
	for k in _pool.size():
		var c := _pool[k]
		var idx := base + k
		var row := floori(float(k) / float(_cols))
		if row >= vrows or idx >= _count:
			c.visible = false                            # margine del pool o oltre l'ultima voce: nascosta e non legata
			c.set_meta("index", -1)
			continue
		c.visible = true
		c.position = Vector2((k % _cols) * cell_w, row * cell_h)
		c.set_meta("index", idx)
		if bind_cell.is_valid():
			bind_cell.call(c, idx)
	if last_input_keyboard and _focus_index >= 0 and _focus_in_grid():
		_grab_focus_cell()


func _focus_in_grid() -> bool:
	if not is_inside_tree():
		return false
	var f := get_viewport().gui_get_focus_owner()
	return f != null and _holder.is_ancestor_of(f)


## Il nodo che mostra `_focus_index` prende il fuoco, se la tastiera è l'ultima fonte di input (col mouse il fuoco non si sposta
## mai da solo). Dopo uno scorrimento lo si chiama solo se il fuoco era già in una cella: mai si ruba il fuoco alla ricerca.
func _grab_focus_cell() -> void:
	var c := cell_for_index(_focus_index)
	if c == null or c.has_focus() or not c.is_inside_tree() or not c.visible:
		return
	if not last_input_keyboard:
		return
	c.grab_focus()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var step := wheel_rows
		if event.shift_pressed:
			step = maxi(1, int(floor(size.y / cell_h)) - 1)         # una pagina
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_bar.value -= step
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_bar.value += step
			accept_event()
	elif event is InputEventKey and event.pressed and _count > 0:
		_on_key(event as InputEventKey)


func _on_key(event: InputEventKey) -> void:
	var cur := _focus_index if _focus_index >= 0 else first_visible()
	var target := cur
	var page := maxi(1, int(floor(size.y / cell_h))) * _cols
	if event.is_action_pressed("ui_left"):
		target = cur - 1
	elif event.is_action_pressed("ui_right"):
		target = cur + 1
	elif event.is_action_pressed("ui_up"):
		target = cur - _cols
	elif event.is_action_pressed("ui_down"):
		target = cur + _cols
	elif event.is_action_pressed("ui_page_up"):
		target = cur - page
	elif event.is_action_pressed("ui_page_down"):
		target = cur + page
	elif event.is_action_pressed("ui_home"):
		target = 0
	elif event.is_action_pressed("ui_end"):
		target = _count - 1
	else:
		return
	if target < 0 or target >= _count:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_right"):
			return                                       # ai bordi la navigazione normale esce dalla griglia (verso la barra degli strumenti)
		target = clampi(target, 0, _count - 1)
	last_input_keyboard = true
	set_focus_index(target)
	accept_event()
