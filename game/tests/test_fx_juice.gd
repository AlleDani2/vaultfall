extends GutTest
## «Juice» di combattimento e mansioni: lampo bianco con limite di sicurezza, fendenti per stile, knockback/affondo,
## movimento dell'attrezzo e reazione del bersaglio. Rispetta «riduci animazioni» ed «effetti ridotti».

var _old_reduce: bool = false
var _old_mode: String = "full"
var _old_path: String = ""


func before_each() -> void:
	_old_path = Settings.path
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_mode = str(Settings.get_value("fx_mode"))
	Settings.path = "user://test_settings_fxj.cfg"
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "full")
	Fx.reset()
	Fx.ensure()
	FxJuice.reset_limiter()
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	Fx.reset()
	Settings.set_value("reduce_motion", _old_reduce)
	Settings.set_value("fx_mode", _old_mode)
	Settings.path = _old_path
	DirAccess.remove_absolute("user://test_settings_fxj.cfg")


func _sprite() -> TextureRect:
	var t := TextureRect.new()
	t.texture = PlaceholderTexture2D.new()
	t.custom_minimum_size = Vector2(64, 64)
	add_child_autofree(t)
	return t


func _count_kind(kind: int) -> int:
	return Fx.host().canvas.count_of(kind)


# ------------------------------------------------------------------ lampo bianco

func test_hit_flash_sets_material_then_restores() -> void:
	var n := _sprite()
	assert_true(Fx.hit_flash(n))
	assert_not_null(n.material, "shader di lampo attivo")
	assert_true(n.material is ShaderMaterial)
	assert_almost_eq(float((n.material as ShaderMaterial).get_shader_parameter("flash")), 0.9, 0.001)
	await get_tree().create_timer(0.3).timeout
	assert_null(n.material, "dopo ~0,08 s il materiale è tolto")


func test_hit_flash_limited_to_three_per_second() -> void:
	var started := 0
	for i in 12:
		if Fx.hit_flash(_sprite()):
			started += 1
	assert_eq(started, 3, "sicurezza fotosensibilità: max 3 lampi al secondo")
	assert_eq(FxJuice.flashes_started, 3)


func test_hit_flash_off_with_reduce_motion_and_weaker_when_reduced() -> void:
	Settings.set_value("reduce_motion", true)
	var n := _sprite()
	assert_false(Fx.hit_flash(n))
	assert_null(n.material)
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "reduced")
	assert_true(Fx.hit_flash(n))
	assert_true(float((n.material as ShaderMaterial).get_shader_parameter("flash")) < 0.7, "tenue con effetti ridotti")


func test_hit_flash_does_not_clobber_foreign_material() -> void:
	var n := _sprite()
	var m := ShaderMaterial.new()
	n.material = m
	assert_false(Fx.hit_flash(n))
	assert_eq(n.material, m)


# ------------------------------------------------------------------ fendenti

func test_strike_shape_per_style() -> void:
	Fx.strike("melee", Vector2(500, 200), Vector2(200, 200))
	assert_eq(_count_kind(FxShape.Kind.ARC), 1)
	Fx.strike("ranged", Vector2(500, 200), Vector2(200, 200))
	assert_eq(_count_kind(FxShape.Kind.BOLT), 1)
	Fx.strike("arcane", Vector2(500, 200), Vector2(200, 200))
	assert_eq(_count_kind(FxShape.Kind.RAYS), 1)


func test_heavy_strike_is_bigger() -> void:
	Fx.strike("melee", Vector2(500, 200), Vector2(200, 200), Color.WHITE, true)
	assert_eq(_count_kind(FxShape.Kind.ARC), 2, "critico/tecnica: due fendenti incrociati")
	Fx.clear_all()
	Fx.strike("ranged", Vector2(500, 200), Vector2(200, 200), Color.WHITE, true)
	assert_eq(_count_kind(FxShape.Kind.BOLT), 2)


func test_strike_draws_and_expires() -> void:
	Fx.strike("melee", Vector2(500, 200), Vector2(200, 200))
	var h := Fx.host()
	for i in 6:
		h._process(1.0 / 30.0)
	h.canvas._draw()                      # nessun errore a metà vita
	for i in 30:
		h._process(1.0 / 30.0)
	assert_eq(h.canvas.active_count(), 0, "il fendente si spegne da solo")


func test_strike_pool_stays_capped() -> void:
	for i in 600:
		Fx.strike(["melee", "ranged", "arcane"][i % 3], Vector2(400, 300), Vector2(100, 100), Color.WHITE, i % 2 == 0)
	assert_true(Fx.host().canvas.active_count() <= FxCanvas.MAX_SHAPES)


func test_strike_nothing_when_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	Fx.strike("melee", Vector2(500, 200), Vector2(200, 200))
	assert_eq(Fx.stats().shapes, 0)


# ------------------------------------------------------------------ knockback / affondo

func test_impact_pushes_then_restores() -> void:
	var n := Node2D.new()
	add_child_autofree(n)
	n.position = Vector2(100, 100)
	Fx.impact(n, Vector2.RIGHT, 12.0, 0.0, 0.2)
	var b := FxShakeBehavior.on(n)
	assert_true(b.running)
	var peak := 0.0
	for i in 12:
		b._process(1.0 / 60.0)
		peak = maxf(peak, n.position.x - 100.0)
	assert_true(peak > 3.0, "spinta visibile: %f" % peak)
	assert_true(peak <= Fx.IMPACT_PUSH_MAX + 0.5, "spinta contenuta (rapporto 104): %f" % peak)
	for i in 30:
		b._process(1.0 / 60.0)
	assert_eq(n.position, Vector2(100, 100), "torna al punto di riposo")
	assert_false(b.running)


func test_impact_none_in_reduced_modes() -> void:
	var n := Node2D.new()
	add_child_autofree(n)
	Settings.set_value("fx_mode", "reduced")
	Fx.impact(n, Vector2.RIGHT, 12.0)
	assert_false(n.has_meta(FxShakeBehavior.META), "effetti ridotti: nessun movimento")
	Settings.set_value("fx_mode", "full")
	Settings.set_value("reduce_motion", true)
	Fx.impact(n, Vector2.RIGHT, 12.0)
	assert_false(n.has_meta(FxShakeBehavior.META))


func test_impact_in_container_tilts_instead_of_moving() -> void:
	var box := VBoxContainer.new()
	add_child_autofree(box)
	var c := Control.new()
	c.custom_minimum_size = Vector2(50, 50)
	box.add_child(c)
	await get_tree().process_frame
	var pos := c.position
	Fx.impact(c, Vector2.RIGHT, 16.0, 0.0, 0.2)
	var b := FxShakeBehavior.on(c)
	for i in 6:
		b._process(1.0 / 60.0)
	assert_eq(c.position, pos, "il container comanda la posizione")
	assert_ne(c.rotation, 0.0)
	for i in 40:
		b._process(1.0 / 60.0)
	assert_eq(c.rotation, 0.0)


# ------------------------------------------------------------------ mansioni

func test_every_skill_has_a_known_motion() -> void:
	for sid in DataRegistry.skill_ids():
		assert_true(FxThemes.MOTION.has(sid), "movimento esplicito per %s" % sid)
	for k in FxThemes.MOTION.values():
		assert_true(FxToolAnim.MOTIONS.has(k), "movimento noto: %s" % k)
	assert_true(FxToolAnim.MOTIONS.has(FxThemes.motion("mansione_inventata")))


func _pair() -> Array:
	var row := HBoxContainer.new()
	add_child_autofree(row)
	var tool := TextureRect.new()
	tool.custom_minimum_size = Vector2(48, 48)
	tool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tool.texture = PlaceholderTexture2D.new()
	row.add_child(tool)
	var target := TextureRect.new()
	target.custom_minimum_size = Vector2(48, 48)
	target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target.texture = PlaceholderTexture2D.new()
	row.add_child(target)
	return [tool, target]


func test_tool_cycle_runs_and_stop_restores() -> void:
	var p := _pair()
	await get_tree().process_frame
	var tool: Control = p[0]
	var target: Control = p[1]
	Fx.tool_start(tool, target, "woodcutting", 1.0, 0.0)
	assert_true(FxToolAnim.is_running(tool))
	await get_tree().create_timer(0.85).timeout          # nella carica: l'attrezzo è piegato indietro
	assert_ne(tool.rotation, 0.0, "carica a fine ciclo")
	Fx.tool_stop(tool, target)
	assert_false(FxToolAnim.is_running(tool))
	assert_eq(tool.rotation, 0.0)
	assert_eq(tool.scale, Vector2.ONE)


func test_tool_strike_moves_target_and_returns() -> void:
	var p := _pair()
	await get_tree().process_frame
	var tool: Control = p[0]
	var target: Control = p[1]
	Fx.tool_strike(tool, target, "mining")
	await get_tree().create_timer(0.1).timeout
	assert_true(tool.rotation != 0.0 or target.scale != Vector2.ONE, "movimento in corso")
	await get_tree().create_timer(0.7).timeout
	assert_true(absf(tool.rotation) < 0.001, "l'attrezzo torna a riposo")
	assert_true(target.scale.is_equal_approx(Vector2.ONE), "il bersaglio torna a scala 1")
	assert_true(absf(target.rotation) < 0.001, "il bersaglio non resta storto")


func test_tool_strike_flashes_target_within_limiter() -> void:
	var p := _pair()
	await get_tree().process_frame
	for i in 6:
		Fx.tool_strike(p[0], p[1], "woodcutting")
	assert_true(FxJuice.flashes_started <= 3)


func test_tool_nothing_when_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	var p := _pair()
	await get_tree().process_frame
	Fx.tool_start(p[0], p[1], "woodcutting", 2.0, 0.0)
	assert_false(FxToolAnim.is_running(p[0]))
	Fx.tool_strike(p[0], p[1], "woodcutting")
	await get_tree().create_timer(0.15).timeout
	assert_eq((p[0] as Control).rotation, 0.0)
	assert_eq((p[1] as Control).scale, Vector2.ONE)
	assert_null((p[1] as Control).material)


func test_tool_reduced_mode_has_no_taps_or_shake() -> void:
	Settings.set_value("fx_mode", "reduced")
	var p := _pair()
	await get_tree().process_frame
	Fx.tool_strike(p[0], p[1], "woodcutting")
	assert_false((p[1] as Control).has_meta(FxShakeBehavior.META), "nessuna scossa")
	await get_tree().create_timer(0.7).timeout
	assert_eq((p[1] as Control).scale, Vector2.ONE)


func test_tool_motions_are_contained() -> void:
	# rapporto 104: nessun movimento dell'attrezzo supera ±6° né ±6% di scala (l'icona resta nel suo riquadro)
	for k in FxToolAnim.MOTIONS:
		var m: Dictionary = FxToolAnim.MOTIONS[k]
		for key in ["wind", "hit", "wobble"]:
			if m.has(key):
				assert_true(absf(float(m[key])) <= FxToolAnim.MAX_ROT + 0.0001, "%s.%s oltre il tetto" % [k, key])
		if m.has("squash"):
			var sq: Vector2 = m.squash
			assert_true(absf(sq.x - 1.0) <= FxToolAnim.MAX_SCALE + 0.0001 and absf(sq.y - 1.0) <= FxToolAnim.MAX_SCALE + 0.0001, "%s: scala oltre il tetto" % k)
	assert_true(FxToolAnim.TARGET_SQUASH <= FxToolAnim.MAX_SCALE)
	assert_true(FxToolAnim.TARGET_SHAKE_PX <= 3.0)


func test_tool_cycle_has_no_intermediate_taps() -> void:
	# un solo colpetto per ciclo (al completamento): a metà di un ciclo lungo l'attrezzo è fermo e il bersaglio non reagisce
	var p := _pair()
	await get_tree().process_frame
	Fx.tool_start(p[0], p[1], "mining", 4.0, 0.0)
	await get_tree().create_timer(1.5).timeout
	assert_eq((p[0] as Control).rotation, 0.0, "nessun colpetto intermedio")
	assert_false((p[1] as Control).has_meta(FxToolAnim.META_REST), "il bersaglio non ha reagito")
	Fx.tool_stop(p[0], p[1])


func test_tool_strike_stays_within_caps() -> void:
	var p := _pair()
	await get_tree().process_frame
	var tool: Control = p[0]
	var target: Control = p[1]
	Fx.tool_strike(tool, target, "mining")
	var max_rot := 0.0
	var max_scale := 0.0
	for i in 40:
		await get_tree().process_frame
		max_rot = maxf(max_rot, absf(tool.rotation))
		max_scale = maxf(max_scale, maxf(absf(target.scale.x - 1.0), absf(target.scale.y - 1.0)))
	assert_true(max_rot <= FxToolAnim.MAX_ROT + 0.01, "rotazione %f" % max_rot)
	assert_true(max_scale <= FxToolAnim.MAX_SCALE + 0.03, "scala %f" % max_scale)


func test_shake_stop_restores_immediately() -> void:
	var n := Node2D.new()
	add_child_autofree(n)
	n.position = Vector2(40, 40)
	Fx.impact(n, Vector2.LEFT, 14.0, 6.0, 0.3)
	var b := FxShakeBehavior.on(n)
	for i in 5:
		b._process(1.0 / 60.0)
	b.stop()
	assert_eq(n.position, Vector2(40, 40))
	assert_false(b.running)
