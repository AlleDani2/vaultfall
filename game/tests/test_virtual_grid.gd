extends GutTest
## VirtualGrid (F16, docs/ui_redesign/02 §5.4): colonne, pool costante, rebind, rotella, fuoco per indice.

var _binds := 0


func _grid(w: float = 880.0, h: float = 400.0) -> VirtualGrid:
	var g := VirtualGrid.new()
	g.cell_w = 88.0
	g.cell_h = 100.0
	g.make_cell = func() -> Control:
		var c := Control.new()
		c.focus_mode = Control.FOCUS_ALL
		c.size = Vector2(84, 96)
		return c
	g.bind_cell = func(c: Control, i: int) -> void:
		_binds += 1
		c.set_meta("shown", i)
	g.size = Vector2(w, h)
	add_child_autofree(g)
	g.size = Vector2(w, h)
	return g


func test_colonne_dalla_larghezza_meno_la_barra() -> void:
	var g := _grid(880.0)
	var bw := g.bar_width()
	assert_eq(g.columns(), maxi(1, int(floor((880.0 - bw) / 88.0))))
	g.size = Vector2(300.0, 400.0)
	await wait_process_frames(2)
	assert_eq(g.columns(), maxi(1, int(floor((300.0 - bw) / 88.0))), "ricalcolo al resized")
	g.size = Vector2(10.0, 400.0)
	await wait_process_frames(2)
	assert_eq(g.columns(), 1, "mai meno di una colonna")


func test_pool_costante_con_20_e_20000_voci() -> void:
	var g := _grid()
	g.set_count(20000)
	var big := g.pool_size()
	assert_eq(big, (g.visible_rows() + 2) * g.columns(), "(righe visibili + 2) × colonne")
	g.set_count(2000)
	assert_eq(g.pool_size(), big, "il costo non dipende da n")
	g.set_count(20)
	var shown := 0
	for c in g._pool:
		if c.visible:
			shown += 1
	assert_eq(shown, 20, "con 20 voci 20 celle in vista (il pool non si restringe: le altre sono nascoste)")
	assert_eq(g.pool_size(), big, "e nessun nodo in più")
	g.set_count(20000)
	g.scroll_to_row(5000)
	assert_eq(g.pool_size(), big, "scorrere non crea nodi")


func test_rebind_solo_delle_celle_visibili() -> void:
	var g := _grid()
	g.set_count(20000)
	_binds = 0
	g.rebind()
	assert_eq(_binds, g.visible_rows() * g.columns(), "legate solo le righe visibili, non il margine del pool")
	assert_lt(_binds, g.pool_size())


func test_scorrimento_e_indici() -> void:
	var g := _grid()
	g.set_count(1000)
	g.scroll_to_row(10)
	assert_eq(g.first_row(), 10)
	assert_eq(g.first_visible(), 10 * g.columns())
	assert_eq(int(g.cell_for_index(10 * g.columns() + 3).get_meta("shown")), 10 * g.columns() + 3)
	assert_null(g.cell_for_index(0), "fuori dalla finestra")
	g.scroll_to_row(999999)
	assert_eq(g.first_row(), g.total_rows() - int(floor(400.0 / 100.0)), "l'ultima riga resta in vista")


func test_rotella_una_riga_e_maiusc_una_pagina() -> void:
	var g := _grid()
	g.set_count(1000)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	g._gui_input(ev)
	assert_eq(g.first_row(), 1, "uno scatto = una riga")
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev2.pressed = true
	ev2.shift_pressed = true
	g._gui_input(ev2)
	assert_eq(g.first_row(), 1 + 3, "Maiusc = una pagina (righe intere − 1)")


func test_barra_sempre_visibile() -> void:
	var g := _grid()
	g.set_count(3)
	assert_true(g._bar.visible, "anche con tre voci la barra c'è")


func test_fuoco_per_indice_durante_lo_scorrimento() -> void:
	var g := _grid()
	g.set_count(1000)
	g.last_input_keyboard = true
	g.set_focus_index(5)
	await wait_process_frames(1)
	assert_eq(g.focus_index(), 5)
	var c := g.cell_for_index(5)
	assert_not_null(c)
	assert_true(c.has_focus(), "con la tastiera il nodo dell'indice ha il fuoco")
	# si scorre di una riga: il nodo che mostrava l'indice 5 ora mostra altro, ma il fuoco segue l'INDICE
	g.scroll_to_row(1)
	await wait_process_frames(1)
	assert_eq(g.focus_index(), 5, "l'indice del fuoco resta")
	var c2 := g.cell_for_index(5)
	if c2 != null:
		assert_true(c2.has_focus(), "il nodo che ora mostra l'indice 5 ha il fuoco")
	# fuori finestra e ritorno
	g.scroll_to_row(50)
	await wait_process_frames(1)
	assert_null(g.cell_for_index(5))
	g.scroll_to_row(0)
	await wait_process_frames(1)
	assert_true(g.cell_for_index(5).has_focus(), "tornato in vista, il fuoco è sull'indice 5")


func test_col_mouse_il_fuoco_non_si_sposta_da_solo() -> void:
	var g := _grid()
	g.set_count(1000)
	g.last_input_keyboard = true
	g.set_focus_index(5)
	await wait_process_frames(1)
	g.last_input_keyboard = false
	g.scroll_to_row(1)
	await wait_process_frames(1)
	var owners := 0
	for c in g._pool:
		if c.has_focus():
			owners += 1
	assert_lte(owners, 1)
	assert_eq(g.focus_index(), 5)


func test_frecce_spostano_il_fuoco_e_scorrono() -> void:
	var g := _grid()
	g.set_count(1000)
	g.last_input_keyboard = true
	g.set_focus_index(0)
	await wait_process_frames(1)
	var cols := g.columns()
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	for i in 6:
		g._on_key(down)
	assert_eq(g.focus_index(), 6 * cols, "giù = una riga di indici")
	assert_gt(g.first_row(), 0, "si è scorso per tenerlo in vista")
	assert_not_null(g.cell_for_index(g.focus_index()))
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	g._on_key(right)
	assert_eq(g.focus_index(), 6 * cols + 1)
	var end := InputEventKey.new()
	end.keycode = KEY_END
	end.pressed = true
	g._on_key(end)
	assert_eq(g.focus_index(), 999)
	assert_not_null(g.cell_for_index(999))


func test_cambio_numero_di_voci_tiene_la_posizione() -> void:
	var g := _grid()
	g.set_count(1000)
	g.scroll_to_row(20)
	g.set_count(900)
	assert_eq(g.first_row(), 20)
	g.set_count(10)
	assert_eq(g.first_row(), 0, "con poche voci si torna all'inizio")
