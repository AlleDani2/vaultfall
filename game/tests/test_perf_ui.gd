extends GutTest
## Prestazioni della UI per PC modesti (resoconto docs/audit_2026-10-22/100_RESOCONTO_PRESTAZIONI.md):
## animazioni a gradini (niente ridisegni a 60 Hz per una barra o un respiro), limite di fotogrammi, finestra in secondo
## piano che non anima, nessuna perdita di nodi/connessioni visitando le schermate. I `test_perf_*` usano PerfGate.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old_fps: int


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_fps = int(Settings.get_value("fps_cap"))
	SaveService.save_dir = "user://test_perf_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Clock.focused = true


func after_each() -> void:
	Clock.focused = true
	Settings.set_value("fps_cap", _old_fps)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


# ------------------------------------------------------------------ animazioni a gradini

func test_quantize_a_gradini() -> void:
	assert_eq(UiAnim.quantize(0.0), 0.0)
	assert_eq(UiAnim.quantize(1.0), 1.0)
	assert_eq(UiAnim.quantize(-3.0), 0.0, "fuori intervallo: tagliato")
	assert_eq(UiAnim.quantize(0.49, 2), 0.5)
	var levels := {}
	for i in 101:
		levels[UiAnim.quantize(float(i) / 100.0)] = true
	assert_eq(levels.size(), UiAnim.STEPS + 1, "solo STEPS+1 valori distinti su tutta la corsa")


func test_color_loop_ridisegna_solo_quando_cambia_il_gradino() -> void:
	var r := ColorRect.new()
	add_child_autofree(r)
	var seen := {}
	for i in 201:
		UiAnim._apply(float(i) / 200.0, r, &"modulate", Color.WHITE, Color(1.5, 1.0, 1.0), UiAnim.STEPS)
		seen[r.modulate] = true
	assert_eq(seen.size(), UiAnim.STEPS + 1, "una corsa di 200 fotogrammi produce solo %d colori diversi" % (UiAnim.STEPS + 1))
	var tw := UiAnim.color_loop(r, &"modulate", Color.WHITE, Color(1.2, 1.2, 1.2), 0.5)
	assert_true(tw.is_valid() and tw.is_running())
	tw.kill()


func test_in_secondo_piano_il_respiro_sta_fermo() -> void:
	var r := ColorRect.new()
	add_child_autofree(r)
	Clock.focused = false
	UiAnim._apply(1.0, r, &"modulate", Color.WHITE, Color(2, 2, 2), 6)
	assert_eq(r.modulate, Color.WHITE, "finestra senza focus: nessun cambio di colore (nessun ridisegno)")
	Clock.focused = true
	UiAnim._apply(1.0, r, &"modulate", Color.WHITE, Color(2, 2, 2), 6)
	assert_eq(r.modulate, Color(2, 2, 2))


func test_barra_fluida_a_30_hz() -> void:
	var b := SmoothBar.new()
	add_child_autofree(b)
	b.set_target(0.10, 0.5)
	b.set_process(false)        # i passi li dà il test: l'engine non deve consumare _acc tra una chiamata e l'altra
	var v0 := b.value
	b._process(1.0 / 60.0)
	assert_eq(b.value, v0, "metà passo: nessun aggiornamento (nessun ridisegno)")
	b._process(1.0 / 60.0)
	assert_gt(b.value, v0, "a 1/30 s la barra avanza")
	assert_almost_eq(b.value, v0 + 0.5 / 30.0, 0.0005, "avanza della velocità x tempo accumulato: nessun tempo perso")
	var v1 := b.value
	Clock.focused = false
	b._process(1.0)
	assert_eq(b.value, v1, "in secondo piano segue solo i refresh, non anima")


func test_ticker_a_20_hz_e_fermo_in_secondo_piano() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var strip := CityStrip.new()
	add_child_autofree(strip)
	await wait_process_frames(1)
	var x0 := strip._news.position.x
	strip._process(0.01)
	assert_eq(strip._news.position.x, x0, "sotto il passo di 50 ms non si muove")
	strip._process(0.05)
	if Fx.enabled():
		assert_lt(strip._news.position.x, x0, "al passo scorre")
	var x1 := strip._news.position.x
	Clock.focused = false
	strip._process(1.0)
	assert_eq(strip._news.position.x, x1, "in secondo piano sta fermo")


func test_effetti_spenti_in_secondo_piano() -> void:
	Settings.set_value("reduce_motion", false)
	Fx.force_level = -1
	assert_gt(Fx.level(), 0)
	Clock.focused = false
	assert_eq(Fx.level(), 0, "nessun effetto visivo se nessuno guarda")
	Clock.focused = true


# ------------------------------------------------------------------ limite di fotogrammi

func test_limite_fps_applicato_e_validato() -> void:
	assert_true(Settings.set_value("fps_cap", 30))
	assert_eq(Clock.focus_fps, 30)
	assert_eq(Engine.max_fps, 30, "in primo piano il limite è quello scelto")
	assert_false(Settings.set_value("fps_cap", 45), "solo 30 o 60")
	assert_false(Settings.set_value("fps_cap", "30"))
	assert_true(Settings.set_value("fps_cap", 60))
	assert_eq(Engine.max_fps, 60)
	Clock._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(Engine.max_fps, Clock.BACKGROUND_FPS, "in secondo piano 10 fps")
	Clock._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(Engine.max_fps, 60)


# ------------------------------------------------------------------ nessuna perdita

func _screens_to_visit() -> Array:
	var ids: Array = []
	for e in ScreenRegistry.entries():
		var id := str(e.id)
		if str(e.get("scene", "")).is_empty():
			continue
		if id.begins_with("skill:") and id != "skill:woodcutting" and id != "skill:cooking":
			continue
		ids.append(id)
	return ids


func _bus_connections() -> int:
	var n := 0
	for s in EventBus.get_signal_list():
		n += EventBus.get_signal_connection_list(s.name).size()
	return n


func test_visitare_le_schermate_non_perde_nodi_ne_connessioni() -> void:
	assert_true(Game.new_game(1, "normal", 21))
	var u: Array = GameState.data.get("unlocks", [])
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if not tok.is_empty() and not u.has(tok):
			u.append(tok)
	GameState.data["unlocks"] = u
	Settings.set_value("reduce_motion", true)        # niente tween: i conteggi sono stabili
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var snaps: Array = []
	for _rnd in 3:
		for id in _screens_to_visit():
			main.show_screen(id)
			await wait_process_frames(2)
			main._on_ui_tick()
		main.show_screen("summary")
		await wait_process_frames(4)
		snaps.append({"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"conn": _bus_connections(), "res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))})
	gut.p("giri di schermate: %s" % str(snaps))
	assert_eq(snaps[2].conn, snaps[1].conn, "connessioni al bus: stabili tra un giro e l'altro")
	assert_lte(int(snaps[2].nodes) - int(snaps[1].nodes), 4, "nodi: nessuna crescita a ogni giro")
	assert_lte(int(snaps[2].res) - int(snaps[1].res), 8, "risorse: nessuna crescita a ogni giro")
	Settings.set_value("reduce_motion", false)


# ------------------------------------------------------------------ costruzione a fette e precaricamento

func test_costruzione_a_fette_delle_imprese() -> void:
	assert_true(Game.new_game(1, "normal", 23))
	var total := DataRegistry.table("achievements").size()
	assert_gt(total, GameScreen.ROWS_PER_SLICE * 2, "servono più fette")
	GameScreen.sliced_builds = true
	var scr = (load("res://src/ui/screens/CompendiumScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	# le righe stanno nella griglia a due colonne «AchGrid» (revisione grafica 1.0): il corpo ha 3 nodi fissi (filtro, aiuto, griglia)
	var grid := scr._bodies[0].find_child("AchGrid", true, false) as Control
	var first: int = grid.get_child_count()
	assert_lt(first, total, "all'apertura solo la prima fetta: %d righe su %d" % [first, total])
	scr.refresh()             # un refresh a metà costruzione non deve rompere nulla
	var guard := 0
	while grid.get_child_count() < total and guard < 60:
		await wait_process_frames(1)
		guard += 1
	GameScreen.sliced_builds = false
	assert_lt(guard, 60, "la costruzione termina")
	assert_eq(grid.get_child_count(), total, "tutte le righe nella griglia")
	assert_eq(scr._bodies[0].get_child_count(), 3, "più filtro, testo d'aiuto e griglia (3 fisse)")
	scr.close()


func test_costruzione_a_fette_delle_mansioni_e_riga_mancante() -> void:
	assert_true(Game.new_game(1, "normal", 24))
	var sm: Array = DataRegistry.actions_for_skill("smithing")
	assert_gt(sm.size(), GameScreen.ROWS_PER_SLICE * 2)
	GameScreen.sliced_builds = true
	var scr = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"skill": "smithing"})
	assert_lt(scr._rows.size(), sm.size(), "all'apertura solo la prima fetta")
	scr.refresh()
	scr.refresh()
	var guard := 0
	while scr._rows.size() < sm.size() and guard < 60:
		await wait_process_frames(1)
		guard += 1
	GameScreen.sliced_builds = false
	assert_eq(scr._rows.size(), sm.size(), "alla fine tutte le righe")
	scr.refresh()
	scr.close()


func test_costruzione_sincrona_nei_test() -> void:
	assert_false(GameScreen.sliced_builds, "nei test l'apertura resta completa e sincrona")
	assert_true(Game.new_game(1, "normal", 25))
	var scr = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"skill": "smithing"})
	assert_eq(scr._rows.size(), DataRegistry.actions_for_skill("smithing").size())


func test_precaricamento_schermate_in_background() -> void:
	assert_true(Game.new_game(1, "normal", 26))
	var wu := ScreenWarmup.new()
	add_child_autofree(wu)
	await wait_process_frames(1)
	assert_gt(wu.pending(), 0, "ci sono schermate da precaricare")
	wu._step()               # un passo a mano (il timer fa lo stesso ogni STEP_S)
	var guard := 0
	while wu.held_count() == 0 and guard < 400:
		await wait_seconds(0.05)
		wu._step()
		guard += 1
	assert_gt(wu.held_count(), 0, "la prima scena viene caricata dal thread e tenuta")
	Clock.focused = false
	var before := wu.held_count() + wu.pending()
	wu._step()
	assert_eq(wu.held_count() + wu.pending(), before, "in secondo piano non parte nulla")
	Clock.focused = true


# ------------------------------------------------------------------ misure di tempo (PerfGate)

func test_perf_costruzione_schermate_pesanti() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	assert_true(Game.new_game(1, "normal", 22))
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = int(bank.state.slots_bought) + 3000
	for it in DataRegistry.all_items().values():
		if bank.free_slots() <= 0:
			break
		bank.add(str(it.id), 3, "perf")
	var u: Array = GameState.data.get("unlocks", [])
	for tok in ["feature:market", "feature:estate", "feature:mercenaries", "feature:crates"]:
		if not u.has(tok):
			u.append(tok)
	GameState.data["unlocks"] = u
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var f0 := PerfGate.load_factor()
	# limiti di progetto in ms di CPU del thread (PC medio); costruzione = una volta all'apertura, refresh = a 10 Hz
	var design := {"bank": [450.0, 12.0], "market": [300.0, 8.0], "estate": [300.0, 8.0], "guild": [250.0, 6.0], "compendium": [700.0, 8.0]}
	for id in design:
		var t0 := PerfGate.clock_usec()
		main.show_screen(id)
		var build_ms := float(PerfGate.clock_usec() - t0) / 1000.0
		await wait_process_frames(2)
		var best := PerfGate.best_of(func() -> void: main.current_screen().refresh(), 5)
		var f := PerfGate.factor_around(f0)
		PerfGate.assert_time(self, "costruzione di %s" % id, build_ms, design[id][0], f)
		PerfGate.assert_time(self, "refresh di %s (10 Hz)" % id, best, design[id][1], f)
