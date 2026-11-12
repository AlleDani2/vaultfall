class_name VirtualList
extends Control
## Lista virtualizzata (docs/17 §12): crea solo le righe visibili (+1) e le riusa mentre si scorre, quindi
## costa lo stesso con 20 o con 20.000 voci. Uso:
##   list.row_height = 40; list.make_row = func() -> Control: ...; list.bind_row = func(row, index): ...
##   list.set_count(n)      # nuovo numero di voci (mantiene la posizione se possibile)
##   list.rebind()          # rilegge i dati delle righe visibili (dati cambiati, stesso numero)

var row_height: float = 40.0
var make_row: Callable
var bind_row: Callable
## Righe scorse con un colpo di rotella.
var wheel_rows: int = 3

var _count: int = 0
var _first: int = 0
var _pool: Array[Control] = []
var _bar := VScrollBar.new()
var _holder := Control.new()


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


func count() -> int:
	return _count


func first_visible() -> int:
	return _first


func visible_rows() -> int:
	return int(ceil(size.y / row_height)) + 1


func pool_size() -> int:
	return _pool.size()


func set_count(n: int) -> void:
	_count = maxi(0, n)
	_layout()


func rebind() -> void:
	_fill()


func scroll_to(index: int) -> void:
	_bar.value = clampf(index, 0, maxf(0.0, _count - size.y / row_height))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_bar.value -= wheel_rows
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_bar.value += wheel_rows
			accept_event()


func _on_scroll(_v: float) -> void:
	_fill()


func _layout() -> void:
	var page := size.y / row_height
	_bar.max_value = maxf(_count, 1)
	_bar.page = minf(page, _count) if _count > 0 else 1.0
	_bar.step = 1.0
	_bar.visible = _count > page
	var need := mini(_count, visible_rows())
	while _pool.size() < need and make_row.is_valid():
		var r: Control = make_row.call()
		_holder.add_child(r)
		_pool.append(r)
	_fill()


func _fill() -> void:
	var max_first := maxi(0, _count - int(floor(size.y / row_height)))
	_first = clampi(int(_bar.value), 0, max_first)
	var w := size.x - (_bar.size.x if _bar.visible else 0.0)
	for i in _pool.size():
		var idx := _first + i
		var r := _pool[i]
		if idx >= _count:
			r.visible = false
			continue
		r.visible = true
		r.position = Vector2(0, i * row_height)
		r.size = Vector2(w, row_height)
		if bind_row.is_valid():
			bind_row.call(r, idx)
