extends GutTest
## Effetti visivi (src/ui/fx): limiti dei pool, «riduci animazioni», «Effetti: ridotti», rarità crescente, cerimonia
## saltabile, striscioni in coda, costo per frame. Solo presentazione: nessun test di bilanciamento.

var _old_path: String = ""
var _old_reduce: bool = false
var _old_mode: String = "full"


func before_each() -> void:
	_old_path = Settings.path
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_mode = str(Settings.get_value("fx_mode"))
	Settings.path = "user://test_settings_fx.cfg"          # non sporca le impostazioni vere
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "full")
	Fx.reset()
	Fx.ensure()
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	Fx.reset()
	Settings.set_value("reduce_motion", _old_reduce)
	Settings.set_value("fx_mode", _old_mode)
	Settings.path = _old_path
	DirAccess.remove_absolute("user://test_settings_fx.cfg")


## Fa avanzare gli effetti di `secs` a passi da 1/30 (deterministico, senza aspettare il tempo vero).
func _advance(secs: float) -> void:
	var h := Fx.host()
	var t := 0.0
	while t < secs:
		h._process(1.0 / 30.0)
		t += 1.0 / 30.0


func test_host_exists_and_is_idle() -> void:
	var h := Fx.host()
	assert_not_null(h)
	assert_false(h.is_busy())
	assert_eq(Fx.level(), 2)


func test_settings_fx_mode_validated() -> void:
	assert_true(Settings.set_value("fx_mode", "reduced"))
	assert_eq(Fx.level(), 1)
	assert_false(Settings.set_value("fx_mode", "bogus"), "valore non valido rifiutato")
	assert_false(Settings.set_value("fx_mode", 3), "tipo sbagliato rifiutato")
	assert_eq(str(Settings.get_value("fx_mode")), "reduced")


func test_reduce_motion_disables_everything_but_static_mark() -> void:
	Settings.set_value("reduce_motion", true)
	assert_eq(Fx.level(), 0)
	assert_false(Fx.number(Vector2(100, 100), "5", Color.WHITE))
	assert_false(Fx.ring(Vector2(100, 100), Color.WHITE))
	assert_false(Fx.burst("spark", Vector2(100, 100)))
	assert_false(Fx.screen_flash(Color.WHITE))
	assert_false(Fx.ceremony("T", "s"))
	Fx.hit(Vector2(50, 50), true)
	Fx.reveal(Rect2(10, 10, 100, 100), "relic")                 # solo un contorno FERMO
	var st := Fx.stats()
	assert_eq(int(st.particles), 0, "nessuna particella")
	assert_eq(int(st.shapes), 1, "un solo contorno statico")
	var found_static := false
	for s in Fx.host().canvas.shapes:
		if s.kind == FxShape.Kind.FRAME:
			found_static = s.vel.x > 0.5
	assert_true(found_static, "il lampo statico non si muove")


func test_reduced_mode_is_lighter_and_without_flash_or_shake() -> void:
	Fx.burst("star", Vector2(300, 300))
	var full_n := Fx.stats().particles as int
	Fx.clear_all()
	Settings.set_value("fx_mode", "reduced")
	Fx.burst("star", Vector2(300, 300))
	var red_n := Fx.stats().particles as int
	assert_true(full_n > 0 and red_n > 0 and red_n < full_n, "meno particelle: %d < %d" % [red_n, full_n])
	assert_false(Fx.screen_flash(Color.WHITE), "niente lampo a schermo intero")
	assert_false(Fx.ring(Vector2(10, 10), Color.WHITE), "niente anelli")
	var n := Control.new()
	add_child_autofree(n)
	n.position = Vector2(20, 30)
	Fx.shake(n, 10.0, 0.3)
	assert_false(n.has_meta(FxShakeBehavior.META), "niente scosse")


func test_number_pool_is_capped() -> void:
	for i in 500:
		Fx.number(Vector2(100, 100), "9", Color.WHITE)
	var c := Fx.host().canvas
	assert_true(c.count_of(FxShape.Kind.NUMBER) <= FxCanvas.MAX_NUMBERS)
	assert_true(c.active_count() <= FxCanvas.MAX_SHAPES)
	assert_eq(c.shapes.size(), FxCanvas.MAX_SHAPES, "il pool non cresce")


func test_shape_pool_never_exceeds_max_and_priority_steals() -> void:
	for i in 400:
		Fx.ring(Vector2(i, i), Color.WHITE, 40.0, 5.0)
	var c := Fx.host().canvas
	assert_eq(c.active_count(), FxCanvas.MAX_SHAPES, "pieno ma non oltre")
	var ok := Fx.number(Vector2(5, 5), "!", Color.GOLD, Fx.NUM_L, 40.0, 1.0, 5)
	assert_true(ok, "priorità alta ruba il posto al più vecchio")
	assert_eq(c.active_count(), FxCanvas.MAX_SHAPES)
	assert_eq(c.shapes.size(), FxCanvas.MAX_SHAPES)


func test_particle_pool_is_capped_and_nodes_do_not_grow() -> void:
	var h := Fx.host()
	for i in 200:
		Fx.burst("confetti", Vector2(400, 300), [], 1.0, 1.0, Vector2(100, 5))
		Fx.burst("star", Vector2(300, 300))
	assert_true(h.burst.live_particles() <= FxBurst.MAX_PARTICLES, "particelle vive %d" % h.burst.live_particles())
	assert_true(h.burst.emitter_count() <= FxBurst.MAX_EMITTERS)
	assert_true(h.burst.dropped > 0, "gli scoppi in eccesso vengono scartati, non accumulati")
	assert_true(h.burst.emitter_count() <= FxBurst.MAX_EMITTERS)
	for rnd in 2:                                             # riscaldamento: il pool si riempie fino al massimo e poi non cresce
		for i in 150:
			Fx.burst("spark", Vector2(200, 200))
			Fx.burst("star", Vector2(300, 200), [], 1.0, 1.0, Vector2.ZERO, 1)
			_advance(0.05)
	var nodes := h.burst.get_child_count()
	assert_true(nodes <= FxBurst.MAX_EMITTERS)
	for i in 200:
		Fx.burst("spark", Vector2(200, 200))
		Fx.burst("star", Vector2(300, 200), [], 1.0, 1.0, Vector2.ZERO, 1)
		_advance(0.05)
	assert_eq(h.burst.get_child_count(), nodes, "i nodi si riusano")


func test_everything_ends() -> void:
	Fx.hit(Vector2(100, 100), true)
	Fx.number(Vector2(100, 100), "1", Color.WHITE)
	Fx.ring(Vector2(100, 100), Color.WHITE)
	Fx.reveal(Rect2(50, 50, 100, 100), "legendary")
	Fx.coins(Vector2(10, 10), Vector2(300, 20), 5)
	assert_true(Fx.host().is_busy())
	_advance(4.0)
	assert_false(Fx.host().is_busy(), "dopo qualche secondo non resta nulla di attivo")
	assert_eq(Fx.stats().particles, 0)


func test_reveal_grows_with_rarity_and_uses_original_palette() -> void:
	var rar: Array = CrateUi.rules().get("rarities", [])
	assert_true(rar.size() >= 4)
	var prev := -1
	var prev_shapes := -1
	for r in rar:
		Fx.clear_all()
		Fx.host().last_flash_ms = -100000                       # il limite di un lampo ogni 0,4 s non falsa il confronto
		Fx.reveal(Rect2(100, 100, 120, 150), str(r.id))
		var parts := Fx.stats().particles as int
		var shapes := Fx.stats().shapes as int
		assert_true(parts >= prev, "particelle non decrescenti con la rarità (%s: %d >= %d)" % [r.id, parts, prev])
		assert_true(shapes >= prev_shapes, "forme non decrescenti (%s)" % r.id)
		prev = parts
		prev_shapes = shapes
	assert_true(prev > 0)
	# colori: solo quelli dei dati (nessun colore inventato per la rarità)
	for r in rar:
		assert_eq(FxPalette.rarity(str(r.id)), Color(str(r.color)))
	assert_almost_eq(FxPalette.rarity_t(str(rar[0].id)), 0.0, 0.001)
	assert_almost_eq(FxPalette.rarity_t(str(rar[rar.size() - 1].id)), 1.0, 0.001)


func test_low_rarity_reveal_is_gentle() -> void:
	var rar: Array = CrateUi.rules().get("rarities", [])
	Fx.reveal(Rect2(100, 100, 120, 150), str(rar[0].id))
	for s in Fx.host().canvas.shapes:
		assert_ne(s.kind, FxShape.Kind.FLASH, "nessun lampo a schermo intero per la rarità più comune")
		assert_ne(s.kind, FxShape.Kind.RING)


func test_screen_flash_is_soft_and_rate_limited() -> void:
	assert_true(Fx.screen_flash(Color.WHITE, 0.9, 0.3))
	assert_false(Fx.screen_flash(Color.WHITE, 0.9, 0.3), "al massimo uno ogni 0,4 s")
	for s in Fx.host().canvas.shapes:
		if s.kind == FxShape.Kind.FLASH:
			assert_true(s.amount <= 0.3 + 0.0001, "opacità massima 0,3")


func test_shake_restores_rest_position() -> void:
	var n := Control.new()
	add_child_autofree(n)
	n.position = Vector2(40, 60)
	Fx.shake(n, 12.0, 0.2)
	var b := FxShakeBehavior.on(n)
	assert_true(b.running)
	for i in 30:
		b._process(1.0 / 30.0)
	assert_false(b.running)
	assert_eq(n.position, Vector2(40, 60), "torna esattamente dov'era")
	Fx.shake(n, 12.0, 0.2)
	Fx.shake(n, 12.0, 0.2)                                      # una scossa nuova non fa derivare il riposo
	for i in 30:
		b._process(1.0 / 30.0)
	assert_eq(n.position, Vector2(40, 60))


func test_number_tick_ends_on_exact_value_and_reduced_is_instant() -> void:
	var l := Label.new()
	add_child_autofree(l)
	Settings.set_value("reduce_motion", true)
	Fx.number_tick(l, 0.0, 1234.0, 0.5, func(v: float) -> String: return str(int(v)))
	assert_eq(l.text, "1234", "con riduci animazioni il valore è subito quello finale")
	Settings.set_value("reduce_motion", false)
	Fx.number_tick(l, 0.0, 99.0, 0.3, func(v: float) -> String: return str(int(v)))
	await get_tree().create_timer(0.7).timeout
	assert_eq(l.text, "99")


func test_banner_queue_dedupes_and_is_bounded() -> void:
	assert_true(Fx.banner("A", "x"))
	assert_false(Fx.banner("A", "x"), "doppione scartato")
	for i in 10:
		Fx.banner("T%d" % i, "s")
	assert_true(Fx._banner_queue.size() <= 3, "coda limitata")
	assert_true(Fx.banner_active())


func test_ceremony_can_be_skipped() -> void:
	assert_true(Fx.ceremony("Stella", "+3", FxPalette.GOLD, "star"))
	assert_true(Fx.ceremony_active())
	var c := Fx._ceremony_cur
	assert_true(c.dur <= 3.0, "dura 2-3 s al massimo")
	c.skip()
	assert_true(c.skipped)
	var t := 0.0
	while t < 0.5 and is_instance_valid(c):
		c._process(0.05)
		t += 0.05
	assert_false(Fx.ceremony_active() and is_instance_valid(c) and not c.is_queued_for_deletion(), "dopo il salto sparisce in pochi decimi")


func test_ceremony_space_key_skips_and_is_consumed() -> void:
	Fx.ceremony("Rito", "", FxPalette.GOLD, "rite")
	var c := Fx._ceremony_cur
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	c._input(ev)
	assert_true(c.skipped)


func test_dissolve_and_fly_do_not_leave_orphans() -> void:
	var tr_ := TextureRect.new()
	tr_.texture = IconLib.portrait("monsters", "mud_slime")
	tr_.size = Vector2(128, 128)
	add_child_autofree(tr_)
	await get_tree().process_frame
	var before := Fx.host().get_child_count()
	Fx.dissolve(tr_)
	Fx.fly(tr_.texture, Vector2(10, 10), Vector2(300, 300), 0.3)
	assert_eq(Fx.host().get_child_count(), before + 1, "solo la copia del ritratto, rimossa a fine effetto")
	await get_tree().create_timer(0.8).timeout
	assert_eq(Fx.host().get_child_count(), before)


func test_job_themes_cover_all_skills() -> void:
	for s in DataRegistry.table("skills"):
		var sid := str(s.id)
		if str(s.get("group", "")) == "combat":
			continue
		assert_true(FxThemes.JOBS.has(sid), "tema particelle per la mansione " + sid)
		assert_true(FxBurst.PRESETS.has(FxThemes.job_preset(sid)))


func test_ability_colors_cover_all_effect_types() -> void:
	var seen := {}
	for a in DataRegistry.table("abilities"):
		seen[str(a.effect.type)] = true
	for t in seen:
		assert_ne(FxPalette.ability(str(t)), FxPalette.BLUE if str(t) != "shield" else Color.BLACK, "colore dedicato a " + str(t))


func test_cost_per_frame_with_five_effects_is_small() -> void:
	var h := Fx.host()
	var f0 := PerfGate.load_factor()
	var total := 0
	var frames := 0
	for k in 60:
		if k % 6 == 0:
			var o := Vector2(200.0 + float(k) * 7.0, 300.0)
			Fx.hit(o, true, FxPalette.GOLD)
			Fx.number(o, "999", FxPalette.GOLD, Fx.NUM_L, 40.0, 0.9, 1)
			Fx.reveal(Rect2(o - Vector2(60, 70), Vector2(120, 140)), "legendary")
			Fx.ring(o, FxPalette.GOLD, 90.0, 0.6)
			Fx.coins(o, Vector2(1100, 20), 5)
		var t0 := PerfGate.clock_usec()
		h._process(1.0 / 60.0)
		total += PerfGate.clock_usec() - t0
		frames += 1
	var avg_ms := float(total) / float(frames) / 1000.0
	gut.p("costo medio aggiornamento Fx con 5 effetti: %.3f ms" % avg_ms)
	PerfGate.assert_time(self, "aggiornamento Fx con 5 effetti (media per frame)", avg_ms, 2.0, PerfGate.factor_around(f0))
	assert_true(h.burst.live_particles() <= FxBurst.MAX_PARTICLES)


func test_director_survives_events_without_errors() -> void:
	var main := Control.new()
	add_child_autofree(main)
	var d := FxDirector.new(main)
	main.add_child(d)
	await get_tree().process_frame
	EventBus.level_up.emit("woodcutting", 5)
	EventBus.item_sold.emit("log_pine", 3, 10)
	EventBus.crate_found.emit("crate_millbrook", "test")
	EventBus.pet_found.emit("nonexistent")
	EventBus.quest_completed.emit("nonexistent")
	EventBus.achievement_unlocked.emit("nonexistent")
	EventBus.unlocked.emit("feature:nonexistent")
	assert_true(true)
