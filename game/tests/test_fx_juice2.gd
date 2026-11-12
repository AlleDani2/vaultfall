extends GutTest
## «Juice» 2: Tenuta animata, Sala delle Casse (cassa che trema, tick del rullo, cornice del risultato), transizioni,
## contatori che scorrono, barre con scia, pulsanti, tooltip, notifiche. Rispetta «Riduci animazioni» e «Effetti ridotti»;
## l'esito delle Casse è sempre estratto prima della scena.

const HALL := preload("res://src/ui/screens/VaultHallScreen.gd")
var _old_reduce: bool = false
var _old_mode: String = "full"
var _old_path: String = ""
var _old_dir: String = ""


func before_each() -> void:
	_old_path = Settings.path
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_mode = str(Settings.get_value("fx_mode"))
	Settings.path = "user://test_settings_fxj2.cfg"
	Settings.set_value("reduce_motion", false)
	Settings.set_value("fx_mode", "full")
	Fx.force_level = -1
	Fx.reset()
	Fx.ensure()
	await get_tree().process_frame
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_fxj2_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Fx.force_level = -1
	Fx.reset()
	if GameState.active:
		Game.stop_game(false)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("reduce_motion", _old_reduce)
	Settings.set_value("fx_mode", _old_mode)
	Settings.path = _old_path
	DirAccess.remove_absolute("user://test_settings_fxj2.cfg")
	HALL.quick_open = false


func _label() -> Label:
	var l := Label.new()
	add_child_autofree(l)
	return l


func _ctl(sz: Vector2 = Vector2(64, 64)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.size = sz
	add_child_autofree(c)
	return c


# ------------------------------------------------------------------ contatori

func test_counter_first_value_is_immediate() -> void:
	var l := _label()
	FxCounter.set_value(l, 1000.0)
	assert_eq(l.text, NumberFormat.fmt(1000.0))
	assert_false(l.get_child(0).is_processing(), "fermo se il numero non si muove")


func test_counter_rolls_then_settles_on_true_value() -> void:
	var l := _label()
	FxCounter.set_value(l, 0.0)
	FxCounter.set_value(l, 100000.0)
	var d := FxCounter.displayed(l)
	assert_gt(d, 0.0, "primo passo immediato (mai «0» rimasto)")
	assert_lt(d, 100000.0, "ma non salta al valore finale")
	await get_tree().create_timer(1.2).timeout
	assert_eq(FxCounter.displayed(l), 100000.0)
	assert_eq(l.text, NumberFormat.fmt(100000.0), "il testo finale è il valore vero")
	assert_false(l.get_child(0).is_processing(), "si spegne a numero arrivato")


func test_counter_follows_new_target_midway_and_goes_down() -> void:
	var l := _label()
	FxCounter.set_value(l, 5000.0)
	FxCounter.set_value(l, 9000.0)
	FxCounter.set_value(l, 100.0)               # cambia idea: scende
	await get_tree().create_timer(1.2).timeout
	assert_eq(l.text, NumberFormat.fmt(100.0))


func test_counter_immediate_with_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	var l := _label()
	FxCounter.set_value(l, 10.0)
	FxCounter.set_value(l, 777.0)
	assert_eq(l.text, NumberFormat.fmt(777.0))
	assert_false(l.get_child(0).is_processing())


func test_counter_pop_is_rate_limited() -> void:
	var l := _label()
	FxCounter.set_value(l, 100.0)
	for i in 10:
		FxCounter.set_value(l, 1000.0 * float(i + 2))
	assert_lte((l.get_child(0) as FxCounter).pops, 1, "un solo rimbalzo ogni 0,45 s")


# ------------------------------------------------------------------ barre

func _bar() -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.value = 1.0
	b.custom_minimum_size = Vector2(200, 16)
	add_child_autofree(b)
	return b


func test_bar_ghost_trails_a_drop_then_drains() -> void:
	var b := _bar()
	var g := FxBarGhost.attach(b)
	assert_same(FxBarGhost.attach(b), g, "un solo nodo per barra")
	b.value = 0.7
	assert_gt(g.ghost, 0.9, "la scia parte dal vecchio livello")
	assert_true(g.is_processing())
	await get_tree().create_timer(1.0).timeout
	assert_lt(g.ghost, 0.0, "la scia si è ritirata")
	assert_false(g.is_processing(), "nessun costo a riposo")


func test_bar_ghost_no_trail_when_bar_restarts() -> void:
	var b := _bar()
	var g := FxBarGhost.attach(b)
	b.value = 0.05                              # nuovo livello / nuova ondata
	assert_lt(g.ghost, 0.0)


func test_bar_ghost_gain_flash_only_in_full_mode() -> void:
	var b := _bar()
	b.value = 0.2
	var g := FxBarGhost.attach(b)
	b.value = 0.205
	assert_lt(g.gain_from, 0.0, "un'inezia (rigenerazione) non lampeggia")
	b.value = 0.4
	assert_gte(g.gain_from, 0.0, "lampo sul tratto guadagnato")
	var b2 := _bar()
	b2.value = 0.2
	Fx.force_level = 1
	var g2 := FxBarGhost.attach(b2)
	b2.value = 0.4
	assert_lt(g2.gain_from, 0.0, "con effetti ridotti niente lampo")
	b2.value = 0.1
	assert_gte(g2.ghost, 0.0, "ma la scia sì")


func test_bar_ghost_off_with_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	var b := _bar()
	var g := FxBarGhost.attach(b)
	b.value = 0.5
	b.value = 0.9
	assert_false(g.is_busy())
	assert_false(g.is_processing())


func test_combat_bars_carry_ghost() -> void:
	var b := CombatUi.bar(Color.RED)
	add_child_autofree(b)
	var has := false
	for c in b.get_children():
		has = has or c is FxBarGhost
	assert_true(has)


# ------------------------------------------------------------------ transizioni, tooltip, pulsanti

func test_screen_transition_is_short_and_lands_on_final_state() -> void:
	var c := _ctl()
	FxUi.screen_in(c)
	assert_lt(c.modulate.a, 0.5, "parte trasparente")
	assert_lte(FxUi.SCREEN_S, 0.15, "transizione <= 0,15 s")
	await get_tree().create_timer(FxUi.SCREEN_S + 0.12).timeout
	assert_eq(c.modulate.a, 1.0)
	assert_eq(c.scale, Vector2.ONE)


func test_screen_transition_nothing_with_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	var c := _ctl()
	FxUi.screen_in(c)
	assert_eq(c.modulate.a, 1.0)
	assert_eq(c.scale, Vector2.ONE)


func test_screen_transition_reduced_mode_fade_only() -> void:
	Fx.force_level = 1
	var c := _ctl()
	FxUi.screen_in(c)
	assert_eq(c.scale, Vector2.ONE, "solo dissolvenza")
	await get_tree().create_timer(0.3).timeout
	assert_eq(c.modulate.a, 1.0)


func test_main_screen_switch_fades_in_and_ends_opaque() -> void:
	assert_true(Game.new_game(1, "normal", 99))
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_true(main.show_screen("settings"))
	var scr: Control = main.current_screen()
	assert_lt(scr.modulate.a, 1.0, "appena aperta sfuma")
	await get_tree().create_timer(0.4).timeout
	assert_eq(main.current_screen().modulate.a, 1.0)
	main._on_ui_tick()
	assert_ne(main.get_node("%GoldValue").text, "")


func test_button_press_squashes_and_returns() -> void:
	var b := Button.new()
	b.text = "x"
	b.custom_minimum_size = Vector2(80, 30)
	add_child_autofree(b)
	await get_tree().process_frame
	FxUi.press(b)
	await get_tree().create_timer(0.06).timeout
	assert_lt(b.scale.x, 1.0, "schiacciato")
	await get_tree().create_timer(0.3).timeout
	assert_eq(b.scale, Vector2.ONE)
	Fx.force_level = 1
	FxUi.press(b)
	assert_eq(b.scale, Vector2.ONE, "effetti ridotti: nessun movimento")


func test_card_hover_lights_border_and_returns() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(100, 50)
	add_child_autofree(p)
	await get_tree().process_frame
	FxUi.card_hover(p)
	FxUi.card_hover(p)                           # idempotente
	p.mouse_entered.emit()
	await get_tree().create_timer(0.25).timeout
	assert_gt(p.self_modulate.r, 1.05)
	p.mouse_exited.emit()
	await get_tree().create_timer(0.25).timeout
	assert_eq(p.self_modulate, Color.WHITE)


func test_tooltip_fades_in() -> void:
	var rt := ItemTooltip.make_control("log_pine")
	assert_not_null(rt, "log_pine esiste: il tooltip si costruisce")
	if rt == null:
		return
	assert_lt(rt.modulate.a, 1.0)
	add_child_autofree(rt)
	await get_tree().create_timer(0.3).timeout
	assert_eq(rt.modulate.a, 1.0)
	Settings.set_value("reduce_motion", true)
	var rt2 := ItemTooltip.make_control("log_pine")
	assert_eq(rt2.modulate.a, 1.0, "nessuna dissolvenza con «riduci animazioni»")
	rt2.free()


func test_toast_leaves_shrinking_or_at_once() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(60, 30)
	add_child(p)
	await get_tree().process_frame
	FxUi.toast_out(p)
	await get_tree().create_timer(0.12).timeout
	assert_true(is_instance_valid(p))
	assert_lt(p.scale.x, 1.0)
	await get_tree().create_timer(0.4).timeout
	assert_false(is_instance_valid(p), "tolta a fine uscita")
	Settings.set_value("reduce_motion", true)
	var q := PanelContainer.new()
	add_child(q)
	FxUi.toast_out(q)
	await get_tree().process_frame
	assert_false(is_instance_valid(q), "subito con «riduci animazioni»")


# ------------------------------------------------------------------ cassa che trema

func test_chest_open_level0_calls_done_at_once() -> void:
	Settings.set_value("reduce_motion", true)
	var c := _ctl()
	var n := [0]
	var tw := FxUi.chest_open(c, 0.4, func() -> void: n[0] += 1)
	assert_null(tw)
	assert_eq(n[0], 1)


func test_chest_open_shakes_then_calls_done_once() -> void:
	var c := _ctl(Vector2(96, 96))
	var n := [0]
	var tw := FxUi.chest_open(c, 0.3, func() -> void: n[0] += 1)
	assert_not_null(tw)
	assert_eq(n[0], 0, "il rullo parte DOPO la scena")
	await get_tree().create_timer(0.15).timeout
	assert_ne(c.rotation, 0.0, "trema")
	await get_tree().create_timer(0.9).timeout
	assert_eq(n[0], 1, "done una volta sola")
	assert_false(c.visible)
	assert_eq(c.rotation, 0.0)
	assert_eq(c.scale, Vector2.ONE)


func test_chest_finish_skips_and_does_not_double_call() -> void:
	var c := _ctl(Vector2(96, 96))
	var n := [0]
	FxUi.chest_open(c, 0.5, func() -> void: n[0] += 1)
	assert_true(FxUi.finish_chest(c, func() -> void: n[0] += 1))
	assert_eq(n[0], 1)
	await get_tree().create_timer(0.8).timeout
	assert_eq(n[0], 1, "il tween fermato non richiama done")
	assert_false(FxUi.finish_chest(c, func() -> void: n[0] += 1), "niente da saltare")


func test_chest_reduced_mode_is_short_pop_without_shake() -> void:
	Fx.force_level = 1
	var c := _ctl(Vector2(96, 96))
	var n := [0]
	FxUi.chest_open(c, 0.4, func() -> void: n[0] += 1)
	await get_tree().create_timer(0.03).timeout
	assert_eq(c.rotation, 0.0)
	await get_tree().create_timer(0.4).timeout
	assert_eq(n[0], 1)


# ------------------------------------------------------------------ Sala delle Casse (integrazione)

const CRATE := "crate_millbrook"


func _hall() -> Array:
	assert_true(Game.new_game(1, "normal", 5))
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 30)
	bank.add("key_t1", 30)
	var scr: GameScreen = (load("res://src/ui/screens/VaultHallScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"crate": CRATE})
	await wait_process_frames(3)
	return [scr, Game.system("crates") as CrateSystem]


func test_hall_result_is_drawn_before_the_chest_scene() -> void:
	HALL.quick_open = true
	var h: Array = await _hall()
	var scr: GameScreen = h[0]
	var crates: CrateSystem = h[1]
	scr._do_open(1)
	assert_eq(crates.state.opened, 1, "estrazione PRIMA della scena")
	assert_true(scr._preroll_on, "la cassa sta tremando")
	assert_false(scr._reel.playing, "il rullo non è ancora partito")
	assert_eq(scr._reel_box.modulate.a, 0.0, "rullo vecchio nascosto durante la scena")
	await get_tree().create_timer(0.6).timeout
	assert_false(scr._preroll_on)
	assert_eq(scr._reel_box.modulate.a, 1.0)
	assert_eq(crates.state.opened, 1, "nessuna estrazione in più")
	scr._on_skip()
	await get_tree().create_timer(0.8).timeout
	assert_ne(scr._result_label.text, "")
	scr._on_close_panel()


func test_hall_skip_during_chest_goes_to_result() -> void:
	var h: Array = await _hall()
	var scr: GameScreen = h[0]
	scr._do_open(1)
	assert_true(scr._preroll_on)
	scr._on_skip()
	await get_tree().create_timer(0.8).timeout
	assert_false(scr._preroll_on)
	assert_ne(scr._result_label.text, "", "un solo Salta porta al risultato")
	scr._on_close_panel()


func test_hall_multi_open_also_has_chest_scene_and_pulsing_frame() -> void:
	HALL.quick_open = true
	var h: Array = await _hall()
	var scr: GameScreen = h[0]
	scr._do_open(5)
	assert_true(scr._preroll_on)
	assert_eq(scr._multi.results().size(), 0 if not scr._multi.visible else scr._multi.results().size())
	scr._on_skip()
	await wait_process_frames(3)
	scr._multi.skip()
	await wait_process_frames(3)
	assert_true(scr._close_btn.visible)
	scr._on_close_panel()


func test_hall_no_scene_with_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	var h: Array = await _hall()
	var scr: GameScreen = h[0]
	scr._do_open(1)
	assert_false(scr._preroll_on, "nessuna scena: risultato subito")
	assert_eq(scr._reel_box.modulate.a, 1.0)
	assert_ne(scr._result_label.text, "")
	scr._on_close_panel()


func test_result_frame_pulses_in_rarity_color_and_returns() -> void:
	var p := _ctl(Vector2(200, 100))
	await get_tree().process_frame
	FxUi.result_frame(p, "epic")
	await get_tree().create_timer(0.25).timeout
	assert_ne(p.self_modulate, Color.WHITE, "la cornice pulsa")
	await get_tree().create_timer(3.0).timeout
	assert_eq(p.self_modulate, Color.WHITE, "e si spegne")


func test_reel_tick_kick_only_while_playing_and_respects_levels() -> void:
	var reel := CrateReel.new()
	reel.custom_minimum_size = Vector2(480, 190)
	add_child_autofree(reel)
	reel.size = Vector2(480, 190)
	var tiles: Array = []
	for i in 60:
		tiles.append({"d": "skin_millbrook_01", "r": "rare"})
	reel.play(tiles, 52, 0.5, true)
	await get_tree().create_timer(0.25).timeout
	var kicked := reel._tick_kick > 0.0 or reel._last_idx > 0
	assert_true(kicked)
	reel.skip()
	await get_tree().create_timer(0.5).timeout
	assert_eq(reel._tick_kick, 0.0, "nessuno scatto a rullo fermo")
	Settings.set_value("reduce_motion", true)
	var reel2 := CrateReel.new()
	add_child_autofree(reel2)
	reel2.size = Vector2(480, 190)
	reel2.play(tiles, 52, 0.5, true)
	assert_eq(reel2._tick_kick, 0.0, "nessun effetto con «riduci animazioni»")


# ------------------------------------------------------------------ Tenuta

func test_every_estate_building_has_its_own_recipe() -> void:
	assert_true(Game.new_game(1, "normal", 4))
	var ids: Array = (Game.system("estate") as EstateSystem).building_ids()
	assert_gt(ids.size(), 5)
	for id in ids:
		assert_true(FxAmbient.RECIPES.has(str(id)), "ricetta ambientale per " + str(id))


func test_ambient_idle_when_inactive_or_no_motion() -> void:
	var icon := _ctl()
	var a := FxAmbient.attach(icon, "sawmill")
	await get_tree().process_frame
	assert_false(a.is_animating(), "edificio non costruito: fermo")
	assert_false(a.is_processing())
	a.active = true
	assert_true(a.is_animating())
	assert_true(a.is_processing())
	Settings.set_value("reduce_motion", true)
	assert_false(a.is_animating(), "riduci animazioni: fermo")
	assert_eq(a.count_elements(), 0)


func test_ambient_stops_when_hidden() -> void:
	var icon := _ctl()
	var a := FxAmbient.attach(icon, "tavern")
	a.active = true
	await get_tree().process_frame
	assert_true(a.is_processing())
	icon.visible = false
	await get_tree().process_frame
	assert_false(a.is_processing(), "icona nascosta: nessun costo")


func test_ambient_element_budget_and_reduced_mode() -> void:
	for id in FxAmbient.RECIPES:
		var icon := _ctl(Vector2(60, 90))
		var a := FxAmbient.attach(icon, str(id))
		a.active = true
		a.t = 3.7
		await get_tree().process_frame
		var full := a.count_elements()
		assert_gt(full, 0, str(id) + " disegna qualcosa")
		assert_lte(full, FxAmbient.MAX_ELEMENTS, str(id))
		Fx.force_level = 1
		var red := a.count_elements()
		assert_lte(red, FxAmbient.MAX_ELEMENTS >> 1, str(id) + " ridotto")
		assert_lte(red, full)
		Fx.force_level = -1


func test_ambient_redraw_throttled_to_20hz() -> void:
	var icon := _ctl()
	var a := FxAmbient.attach(icon, "cottage")
	a.active = true
	await get_tree().process_frame
	var t0 := a.t
	a._process(0.01)
	a._process(0.01)
	assert_gt(a.t, t0, "il tempo avanza")
	assert_lt(a._acc, FxAmbient.STEP_S, "ridisegno solo ogni 0,05 s")


func test_estate_screen_attaches_ambient_and_production_pops() -> void:
	assert_true(Game.new_game(1, "normal", 12))
	for b in EstateFixtures.ALL_BUILDINGS:
		(GameState.data.unlocks as Array).append("building:" + b)
	var e := Game.system("estate") as EstateSystem
	for bid in ["cottage", "sawmill"]:
		e._entry(bid)["level"] = 5
	e.state.settlers = e.settler_cap()
	var scr: Control = (load("res://src/ui/screens/EstateScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	await wait_process_frames(1)
	scr.open({})
	scr.refresh()
	var amb_n := 0
	var active_n := 0
	for bid in scr._cards:
		var a: FxAmbient = scr._cards[bid].amb
		amb_n += 1
		if a.active:
			active_n += 1
	assert_eq(amb_n, e.building_ids().size())
	assert_eq(active_n, 2, "animati solo gli edifici costruiti")
	# produzione: il «+N» sale solo se l'icona è visibile nello scorrimento
	var big := ScrollContainer.new()
	add_child_autofree(big)
	big.position = Vector2(-9000, -9000)
	big.size = Vector2(20000, 20000)
	scr._scroll = big
	var item := e.product_of("sawmill")
	scr.refresh()
	e.state.storage[item] = float(e.state.storage.get(item, 0.0)) + 7.0
	var before := Fx.host().canvas.count_of(FxShape.Kind.NUMBER)
	scr.refresh()
	assert_gt(Fx.host().canvas.count_of(FxShape.Kind.NUMBER), before, "+N sopra l'edificio")
	e.state.storage[item] = float(e.state.storage.get(item, 0.0)) + 7.0
	var n1 := Fx.host().canvas.count_of(FxShape.Kind.NUMBER)
	scr.refresh()
	assert_eq(Fx.host().canvas.count_of(FxShape.Kind.NUMBER), n1, "rate limit: non un altro subito")
	Fx.force_level = 0
	e.state.storage[item] = float(e.state.storage.get(item, 0.0)) + 700.0
	scr._stock_ms.clear()
	var n2 := Fx.host().canvas.count_of(FxShape.Kind.NUMBER)
	scr.refresh()
	assert_eq(Fx.host().canvas.count_of(FxShape.Kind.NUMBER), n2, "nessun numero con riduci animazioni")
	scr.close()


# ------------------------------------------------------------------ level up, pulsanti globali, prestazioni

func test_level_up_director_shows_level_number() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var d := FxDirector.new(null)
	add_child_autofree(d)
	await get_tree().process_frame
	var before := Fx.host().canvas.count_of(FxShape.Kind.NUMBER)
	d._on_level_up("woodcutting", 12)
	assert_gt(Fx.host().canvas.count_of(FxShape.Kind.NUMBER), before, "numero «Livello N» che sale")


func test_ceremony_is_skippable_and_short_in_reduced_mode() -> void:
	Fx.force_level = 1
	var c := FxCeremony.new()
	c.setup("Titolo", "Sotto", FxPalette.GOLD, "rite")
	assert_lte(c.dur, 1.6)
	c.skip()
	assert_true(c.skipped)
	c.free()


func test_flash_rate_limit_holds_with_new_effects_around() -> void:
	FxJuice.reset_limiter()
	var started := 0
	for i in 20:
		var s := TextureRect.new()
		s.texture = PlaceholderTexture2D.new()
		add_child_autofree(s)
		if Fx.hit_flash(s):
			started += 1
	assert_lte(started, 3, "mai più di 3 lampi al secondo")
	var before := Fx.host().canvas.count_of(FxShape.Kind.FLASH)
	for i in 10:
		Fx.screen_flash(Color.WHITE, 0.3, 0.3)
	assert_lte(Fx.host().canvas.count_of(FxShape.Kind.FLASH) - before, 3, "lampi a schermo intero limitati")


func test_per_frame_cost_stays_tiny_with_everything_running() -> void:
	var icons: Array = []
	for id in FxAmbient.RECIPES:
		var icon := _ctl(Vector2(60, 90))
		var a := FxAmbient.attach(icon, str(id))
		a.active = true
		icons.append(a)
	var bars: Array = []
	for i in 6:
		var b := _bar()
		FxBarGhost.attach(b)
		bars.append(b)
		b.value = 0.5
	var l := _label()
	FxCounter.set_value(l, 0.0)
	FxCounter.set_value(l, 99999999.0)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var frames := 20
	for f in frames:
		for a in icons:
			a._process(0.017)
			a.count_elements()
		for b in bars:
			for c in b.get_children():
				if c is FxBarGhost:
					c._process(0.017)
		(l.get_child(0) as FxCounter)._process(0.017)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	gut.p("juice2: %.3f ms per fotogramma (11 edifici + 6 barre + 1 contatore, calcolo forzato a ogni frame; il disegno vero è a 20 Hz)" % per_frame_ms)
	assert_lt(per_frame_ms, 3.0, "costo per fotogramma trascurabile")
