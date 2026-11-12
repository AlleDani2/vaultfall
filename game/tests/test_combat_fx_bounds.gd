extends GutTest
## Difetto I2: i numeri di danno fluttuanti non escono dall'arena. Fx.number accetta un rettangolo globale di confine
## facoltativo; senza rettangolo il comportamento è quello di sempre.

const ARENA := Rect2(Vector2(300, 120), Vector2(420, 160))

var _old_reduce: bool = false
var _old_mode: String = "full"
var _old_path: String = ""


func before_each() -> void:
	_old_path = Settings.path
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_mode = str(Settings.get_value("fx_mode"))
	Settings.path = "user://test_settings_fxb.cfg"
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "full")
	Fx.reset()
	Fx.force_level = 2
	Fx.ensure()
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	Fx.force_level = -1
	Fx.reset()
	Settings.set_value("reduce_motion", _old_reduce)
	Settings.set_value("fx_mode", _old_mode)
	Settings.path = _old_path
	DirAccess.remove_absolute("user://test_settings_fxb.cfg")


func _numbers() -> Array[FxShape]:
	var out: Array[FxShape] = []
	for s in Fx.host().canvas.shapes:
		if s.kind == FxShape.Kind.NUMBER:
			out.append(s)
	return out


func test_50_numeri_al_bordo_alto_restano_nel_rettangolo() -> void:
	var made := 0
	var sizes := [Fx.NUM_S, Fx.NUM_M, Fx.NUM_L, Fx.NUM_XL]
	for i in 50:
		Fx.host().canvas.clear_all()
		# centro del nemico al bordo alto (e a volte oltre i lati): l'offset di -50 lo porterebbe sopra l'arena
		var cx := ARENA.position.x + (float(i) / 49.0) * ARENA.size.x + randf_range(-60.0, 60.0)
		var c := Vector2(cx, ARENA.position.y)
		var sz: int = sizes[i % 4]
		var ok := Fx.number(c + Vector2(randf_range(-30.0, 30.0), -50.0), "12345!", Color.WHITE, sz, 58.0, 1.0, i % 2, 0.0, ARENA)
		assert_true(ok)
		made += 1
		for s in _numbers():
			var top_y := s.pos.y - s.amount - float(sz)        # cima del testo alla fine della salita
			assert_true(s.pos.x >= ARENA.position.x and s.pos.x <= ARENA.end.x, "x dentro: %s" % s.pos)
			assert_true(s.pos.y <= ARENA.end.y and s.pos.y >= ARENA.position.y, "y di nascita dentro: %s" % s.pos)
			assert_true(top_y >= ARENA.position.y - 0.01, "la salita non esce in alto: %f" % top_y)
	assert_eq(made, 50)


func test_durante_l_animazione_i_nodi_restano_dentro() -> void:
	Fx.number(Vector2(ARENA.position.x, ARENA.position.y - 40.0), "999", Color.RED, Fx.NUM_XL, 80.0, 0.3, 1, 0.0, ARENA)
	for k in 6:
		await get_tree().create_timer(0.06).timeout
		for s in _numbers():
			var p := s.t()
			var rise := s.amount * (1.0 - pow(1.0 - p, 2.0))
			assert_true(s.pos.y - rise - float(Fx.NUM_XL) >= ARENA.position.y - 0.01, "in salita resta dentro")
			assert_true(s.pos.x >= ARENA.position.x)


func test_senza_rettangolo_comportamento_invariato() -> void:
	var p := Vector2(10, -30)
	assert_true(Fx.number(p, "5", Color.WHITE, Fx.NUM_M, 44.0, 0.9))
	var found := false
	for s in _numbers():
		found = true
		assert_eq(s.pos, p, "posizione invariata")
		assert_eq(s.amount, 44.0, "salita invariata")
	assert_true(found)
	Fx.host().canvas.clear_all()
	assert_true(Fx.number(p, "5", Color.WHITE, Fx.NUM_M, 44.0, 0.9, 0, 0.0, Rect2()), "rettangolo vuoto = nessun confine")
	for s in _numbers():
		assert_eq(s.pos, p)


func test_riduci_animazioni_nessun_numero() -> void:
	Fx.force_level = 0
	assert_false(Fx.number(ARENA.get_center(), "1", Color.WHITE, Fx.NUM_M, 44.0, 0.9, 0, 0.0, ARENA))
