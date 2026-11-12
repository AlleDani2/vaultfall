extends SceneTree
## Profilo delle prestazioni per PC modesti (resoconto 100). Un solo script, più modi; stampa righe `PERF ...` e scrive
## un JSON in `user://perf_out/<modo>.json`. Serve il salvataggio di prova di `perf_fixture.gd` (slot 1 in
## `user://perf_fixture/`). Rendering software: sotto Xvfb con Mesa (llvmpipe) il costo grafico NON è quello di una GPU
## integrata, ma draw call, nodi e CPU di logica sì; i tempi di CPU sono del thread principale (PerfGate.clock_usec).
##
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##       -s res://scripts/perf_profile.gd -- <modo> [opzioni]
## Modi:
##   startup            tempi: autoload, menù iniziale, Continua (carica + MainScreen)
##   screens            ogni schermata: costruzione, refresh (logica UI a 10 Hz), nodi, draw call, tempo di fotogramma
##   leak [giri]        visita tutte le schermate N volte: nodi/oggetti/risorse/memoria tra un giro e l'altro
##   save               snapshot + scrittura (durata, byte) dello stato del fixture
##   idle               CPU con finestra in primo piano e in secondo piano (focus perso)
## Non tocca i salvataggi veri.

const FIXTURE_DIR := "user://perf_fixture"
const MAIN := "res://src/ui/main/MainScreen.tscn"
const START := "res://src/ui/start/StartScreen.tscn"

var _mode := ""
var _args: PackedStringArray
var _out := {}
var _boot_wall_ms := 0
var _boot_cpu_ms := 0.0


func _initialize() -> void:
	_boot_wall_ms = Time.get_ticks_msec()
	_boot_cpu_ms = float(PerfGate.clock_usec()) / 1000.0
	_args = OS.get_cmdline_user_args()
	_mode = _args[0] if _args.size() > 0 else "screens"
	_run.call_deferred()


func _n(name: String) -> Node:
	return root.get_node(name)


## ScreenRegistry senza nome di classe nello script: un -s che nomina classi dei sistemi le compila PRIMA degli autoload
## ("Identifier not found: Loc") e le lascia rotte per tutto il processo.
func _sr() -> GDScript:
	return load("res://src/ui/ScreenRegistry.gd") as GDScript


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var l := f.get_line()
		if l.begins_with("VmRSS:"):
			return float(l.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0
	return -1.0


func _hwm_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var l := f.get_line()
		if l.begins_with("VmHWM:"):
			return float(l.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0
	return -1.0


func _mem() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mb": snappedf(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, 0.01),
		"tex_mb": snappedf(float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0, 0.01),
		"rss_mb": snappedf(_rss_mb(), 0.1),
	}


func _p(key: String, v: Variant) -> void:
	_out[key] = v
	print("PERF ", key, " = ", v)


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute("user://perf_out")
	var f := FileAccess.open("user://perf_out/%s.json" % _mode, FileAccess.WRITE)
	f.store_string(JSON.stringify(_out, "\t"))
	f.close()
	print("PERF_JSON ", ProjectSettings.globalize_path("user://perf_out/%s.json" % _mode))
	quit(0)


func _setup_saves() -> void:
	var ss := _n("SaveService")
	ss.set("save_dir", FIXTURE_DIR)
	ss.set("autosave_enabled", false)


## Deposito di stress: posti comprati in abbondanza e ogni oggetto dei dati (x3: l'equipaggiamento diventa istanze).
func _stress_bank() -> void:
	var bk: Object = _n("Game").call("system", "bank")
	bk.state.slots_bought = int(bk.state.slots_bought) + 4000
	var n := 0
	for it in _n("DataRegistry").call("all_items").values():
		if int(bk.call("free_slots")) <= 0:
			break
		bk.call("add", str(it.id), 3, "perf")
		n += 1
	_p("bank_stress", {"items_added": n, "used": bk.call("used_slots"), "stacks": bk.state.stacks.size(), "instances": bk.state.instances.size()})


func _unlock_all() -> void:
	var u: Array = _n("GameState").data.get("unlocks", [])
	for e in _sr().entries():
		var tok := str(e.get("unlock", ""))
		if not tok.is_empty() and not u.has(tok):
			u.append(tok)
	_n("GameState").data["unlocks"] = u


func _run() -> void:
	_setup_saves()
	match _mode:
		"startup":
			await _startup()
		"screens":
			await _screens()
		"leak":
			await _leak()
		"save":
			await _save()
		"idle":
			await _idle()
		"who":
			await _who()
		_:
			print("modo sconosciuto ", _mode)
	_finish()


# ------------------------------------------------------------------ startup

func _startup() -> void:
	_p("t_autoload_done_wall_ms", _boot_wall_ms)
	_p("t_autoload_done_cpu_ms", snappedf(_boot_cpu_ms, 0.1))
	_p("datareg_load_ms", snappedf(float(_n("DataRegistry").load_ms), 0.1))
	_p("items_count", _n("DataRegistry").call("all_items").size())
	_p("mem_after_autoloads", _mem())
	# costo isolato dei pezzi più sospetti (cache fredda del sistema operativo già calda: sono misure di CPU)
	var t := PerfGate.clock_usec()
	var theme := load("res://src/ui/theme/main_theme.tres")
	_p("theme_load_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	t = PerfGate.clock_usec()
	_n("DataRegistry").call("load_all")
	_p("datareg_reload_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	_p("theme", theme != null)
	var w0 := Time.get_ticks_msec()
	var c0 := PerfGate.clock_usec()
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	current_scene = start          # come nell'avvio vero: il menù è la scena principale (avvia il precaricamento a thread)
	await process_frame
	await process_frame
	_p("start_menu_wall_ms", Time.get_ticks_msec() - w0)
	_p("start_menu_cpu_ms", snappedf(float(PerfGate.clock_usec() - c0) / 1000.0, 0.1))
	_p("t_menu_ready_wall_ms", Time.get_ticks_msec())
	_p("mem_at_menu", _mem())
	if _args.has("wait"):       # il giocatore guarda il menù 4 s prima di premere Continua (il precaricamento lavora nel frattempo)
		var tw := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tw < 4000:
			await process_frame
		_p("menu_wait_ms", 4000)
	# Continua: carica lo slot, passa a MainScreen
	w0 = Time.get_ticks_msec()
	c0 = PerfGate.clock_usec()
	var res: Dictionary = _n("Game").call("load_game", 1)
	_p("load_ok", str(res.get("ok")) + " " + str(res.get("error", "")))
	_p("load_game_wall_ms", Time.get_ticks_msec() - w0)
	_p("load_game_cpu_ms", snappedf(float(PerfGate.clock_usec() - c0) / 1000.0, 0.1))
	_p("offline_s_applied", res.get("offline_s", 0))
	start.queue_free()
	w0 = Time.get_ticks_msec()
	c0 = PerfGate.clock_usec()
	var packed := load(MAIN) as PackedScene
	_p("main_scene_load_cpu_ms", snappedf(float(PerfGate.clock_usec() - c0) / 1000.0, 0.1))
	var c1 := PerfGate.clock_usec()
	var main: Control = packed.instantiate()
	_p("main_scene_instantiate_cpu_ms", snappedf(float(PerfGate.clock_usec() - c1) / 1000.0, 0.1))
	c1 = PerfGate.clock_usec()
	root.add_child(main)
	_p("main_screen_ready_cpu_ms", snappedf(float(PerfGate.clock_usec() - c1) / 1000.0, 0.1))
	c1 = PerfGate.clock_usec()
	await process_frame
	await process_frame
	_p("main_screen_first_frames_cpu_ms", snappedf(float(PerfGate.clock_usec() - c1) / 1000.0, 0.1))
	_p("main_screen_wall_ms", Time.get_ticks_msec() - w0)
	_p("main_screen_cpu_ms", snappedf(float(PerfGate.clock_usec() - c0) / 1000.0, 0.1))
	_p("t_continue_ready_wall_ms", Time.get_ticks_msec())
	_p("mem_at_main", _mem())
	_p("rss_hwm_mb", snappedf(_hwm_mb(), 0.1))


# ------------------------------------------------------------------ schermate

func _open_main() -> Control:
	var res: Dictionary = _n("Game").call("load_game", 1)
	if not bool(res.get("ok", false)):
		push_error("fixture mancante: lanciare perf_fixture.gd")
		quit(2)
	_unlock_all()
	if _args.has("stress"):
		_stress_bank()
	_n("Settings").call("set_value", "reduce_motion", false)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	if _args.has("sliced"):
		(load("res://src/ui/GameScreen.gd") as GDScript).set("sliced_builds", true)
	return main


func _screen_ids() -> Array:
	var ids: Array = []
	var only := ""
	for a in _args:
		if a.begins_with("only="):
			only = a.get_slice("=", 1)
	for e in _sr().entries():
		var id := str(e.id)
		if not only.is_empty() and not only.split(",").has(id):
			continue
		if id.begins_with("skill:") and not ["skill:woodcutting", "skill:cooking", "skill:farming", "skill:smithing"].has(id):
			continue
		if str(e.get("scene", "")).is_empty():
			continue
		ids.append(id)
	return ids


## Misura una schermata: costruzione, refresh, N fotogrammi (CPU del thread principale e tempo reale).
func _measure_screen(main: Control, id: String, frames: int = 60) -> Dictionary:
	var n0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var c0 := PerfGate.clock_usec()
	var ok: bool = main.call("show_screen", id)
	var build_ms := float(PerfGate.clock_usec() - c0) / 1000.0
	await process_frame
	await process_frame
	var cur: Control = main.call("current_screen")
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - n0
	var refresh_ms := 0.0
	if cur != null and cur.has_method("refresh"):
		var best := INF
		for i in 8:
			var r0 := PerfGate.clock_usec()
			cur.call("refresh")
			best = minf(best, float(PerfGate.clock_usec() - r0) / 1000.0)
		refresh_ms = best
	var ui_tick := INF
	for i in 6:
		var u0 := PerfGate.clock_usec()
		main.call("_on_ui_tick")
		ui_tick = minf(ui_tick, float(PerfGate.clock_usec() - u0) / 1000.0)
	await _frames(70)          # a regime: le animazioni d'ingresso (pop dei badge, comparsa) sono finite (~1,2 s di gioco a 60 Hz fissi)
	var w0 := Time.get_ticks_usec()
	var cpu0 := PerfGate.clock_usec()
	var worst_cpu := 0.0
	var draw_max := 0
	var prims_max := 0
	var drawn0 := Engine.get_frames_drawn()
	for i in frames:
		var f0 := PerfGate.clock_usec()
		await process_frame
		worst_cpu = maxf(worst_cpu, float(PerfGate.clock_usec() - f0) / 1000.0)
		draw_max = maxi(draw_max, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims_max = maxi(prims_max, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	var drawn := Engine.get_frames_drawn() - drawn0
	var wall_per := float(Time.get_ticks_usec() - w0) / 1000.0 / float(frames)
	var cpu_per := float(PerfGate.clock_usec() - cpu0) / 1000.0 / float(frames)
	var total_nodes := 0
	if cur != null:
		total_nodes = 1 + cur.find_children("*", "", true, false).size()
	# seconda apertura (scena e script già compilati): costo di sola costruzione
	main.call("show_screen", "news")
	await process_frame
	var cw := PerfGate.clock_usec()
	main.call("show_screen", id)
	var warm_ms := float(PerfGate.clock_usec() - cw) / 1000.0
	await process_frame
	return {"ok": ok, "build_cpu_ms": snappedf(build_ms, 0.1), "build_warm_cpu_ms": snappedf(warm_ms, 0.1), "refresh_cpu_ms": snappedf(refresh_ms, 0.02),
		"ui_tick_cpu_ms": snappedf(ui_tick, 0.02), "screen_nodes": total_nodes, "new_nodes": nodes,
		"frame_cpu_ms": snappedf(cpu_per, 0.1), "frame_cpu_worst_ms": snappedf(worst_cpu, 0.1),
		"frame_wall_ms": snappedf(wall_per, 0.1), "redraw_pct": snappedf(100.0 * drawn / float(frames), 1.0), "draw_calls": draw_max, "primitives": prims_max}


func _screens() -> void:
	var main := _open_main()
	await _frames(10)
	# combattimento con effetti pieni: zona più avanzata sbloccata
	# come un giocatore idle vero: una mansione SEMPRE in corso (la barra dell'attività in alto si muove di continuo)
	var sk: Object = _n("Game").call("system", "skills")
	sk.call("start", "wc_pine")
	if _args.has("warm"):          # precaricamento in background come nel gioco vero: si attende che finisca (max 90 s)
		var wu: Node = (load("res://src/ui/main/ScreenWarmup.gd") as GDScript).new()
		main.add_child(wu)
		var tw := Time.get_ticks_msec()
		while int(wu.call("pending")) > 0 and Time.get_ticks_msec() - tw < 90000:
			await process_frame
		_p("warmup_wall_s", snappedf(float(Time.get_ticks_msec() - tw) / 1000.0, 0.1))
		_p("warmup_held", wu.call("held_count"))
	var rows := {}
	var combat_zone := ""
	var cb: Object = _n("Game").call("system", "combat")
	for z in cb.zones():
		if bool(z.unlocked):
			combat_zone = str(z.id)
	for id in _screen_ids():
		if id == "combat" and not combat_zone.is_empty():
			cb.call("start", combat_zone, "")      # combattimento vero, effetti pieni
		var r: Dictionary = await _measure_screen(main, id)
		rows[id] = r
		print("PERF screen %-20s build %6.1f ms (2a apertura %6.1f) | refresh %5.2f ms | tick %5.2f ms | nodi %5d | draw %4d | redraw %3d%% | frame cpu %5.1f wall %6.1f ms" % [
			id, r.build_cpu_ms, r.build_warm_cpu_ms, r.refresh_cpu_ms, r.ui_tick_cpu_ms, r.screen_nodes, r.draw_calls, r.redraw_pct, r.frame_cpu_ms, r.frame_wall_ms])
	_out["screens"] = rows
	_p("mem_after_screens", _mem())
	_p("rss_hwm_mb", snappedf(_hwm_mb(), 0.1))


# ------------------------------------------------------------------ perdite

func _leak() -> void:
	var rounds := 4
	for a in _args:
		if a.begins_with("rounds="):
			rounds = int(a.get_slice("=", 1))
	var main := _open_main()
	await _frames(10)
	var ids := _screen_ids()
	var series: Array = []
	for r in rounds:
		for id in ids:
			main.call("show_screen", id)
			await _frames(3)
			main.call("_on_ui_tick")
		main.call("show_screen", "summary")
		await _frames(6)
		var m := _mem()
		m["connections"] = _signal_connections(main)
		series.append(m)
		print("PERF giro %d: %s" % [r, m])
	_out["series"] = series
	_p("rss_hwm_mb", snappedf(_hwm_mb(), 0.1))
	# crescita tra l'ultimo e il penultimo giro
	if series.size() >= 2:
		var a: Dictionary = series[series.size() - 2]
		var b: Dictionary = series[series.size() - 1]
		_p("delta_ultimo_giro", {"nodes": b.nodes - a.nodes, "objects": b.objects - a.objects, "resources": b.resources - a.resources,
			"orphans": b.orphans - a.orphans, "static_mb": snappedf(b.static_mb - a.static_mb, 0.01), "connections": b.connections - a.connections})


## Conta le connessioni di segnale sul bus (se crescono a ogni giro, una schermata non si disconnette).
func _signal_connections(_main: Node) -> int:
	var eb := _n("EventBus")
	var n := 0
	for s in eb.get_signal_list():
		n += eb.get_signal_connection_list(s.name).size()
	return n


# ------------------------------------------------------------------ salvataggio

func _save() -> void:
	# lavora su una COPIA del salvataggio di prova: il fixture non deve cambiare tra una misura e l'altra
	var work := "user://perf_work"
	DirAccess.make_dir_recursive_absolute(work)
	for f in ["slot_1.sav"]:
		var bytes := FileAccess.get_file_as_bytes(FIXTURE_DIR + "/" + f)
		var out := FileAccess.open(work + "/" + f, FileAccess.WRITE)
		out.store_buffer(bytes)
		out.close()
	_n("SaveService").set("save_dir", work)
	var game := _n("Game")
	var res: Dictionary = game.call("load_game", 1)
	_p("load_ok", res.get("ok"))
	var ss := _n("SaveService")
	var path := work + "/slot_1.sav"
	# "hours=N": N ore di gioco in più (offline analitico a blocchi di mezz'ora con una mansione in corso)
	for a in _args:
		if a.begins_with("hours="):
			game.call("system", "skills").call("start", "wc_pine")
			var extra := int(float(a.get_slice("=", 1)) * 2.0)
			for i in extra:
				game.call("_on_long_gap", 1800.0)
			_p("hours_added", a.get_slice("=", 1))
	if _args.has("stress"):
		_stress_bank()
	_p("save_file_bytes", FileAccess.get_file_as_bytes(path).size())
	_p("instances", _n("Game").call("system", "bank").call("used_slots"))
	var t := PerfGate.clock_usec()
	var snap: Dictionary = game.call("snapshot", true)
	_p("snapshot_full_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	for i in 3:
		t = PerfGate.clock_usec()
		snap = game.call("snapshot", false)
		_p("snapshot_incremental_cpu_ms_%d" % i, snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	t = PerfGate.clock_usec()
	var js := JSON.stringify(snap)
	_p("json_stringify_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	_p("json_bytes", js.length())
	t = PerfGate.clock_usec()
	var gz := js.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	_p("gzip_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	_p("gzip_bytes", gz.size())
	# percorso vero: save_now (sincrono) e request_save (thread)
	t = PerfGate.clock_usec()
	var w := Time.get_ticks_usec()
	ss.call("save_now")
	_p("save_now_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	_p("save_now_wall_ms", snappedf(float(Time.get_ticks_usec() - w) / 1000.0, 0.1))
	var worst := 0.0
	for k in 3:
		t = PerfGate.clock_usec()
		ss.call("request_save")
		var blocking := float(PerfGate.clock_usec() - t) / 1000.0
		worst = maxf(worst, blocking)
		await _frames(30)
	_p("request_save_main_thread_cpu_ms_max", snappedf(worst, 0.1))
	t = PerfGate.clock_usec()
	var loaded: Dictionary = ss.call("load_slot", 1, game.get("sim").int_paths())
	_p("load_slot_cpu_ms", snappedf(float(PerfGate.clock_usec() - t) / 1000.0, 0.1))
	_p("load_slot_ok", loaded.get("ok"))
	_p("save_file_bytes_after", FileAccess.get_file_as_bytes(path).size())


# ------------------------------------------------------------------ idle

func _idle() -> void:
	var main := _open_main()
	await _frames(20)
	var sk: Object = _n("Game").call("system", "skills")
	var cb: Object = _n("Game").call("system", "combat")
	var combat_zone := ""
	for z in cb.zones():
		if bool(z.unlocked):
			combat_zone = str(z.id)
	var cases := [["skill:woodcutting", "skill"], ["bank", "skill"], ["quests", "skill"], ["combat", "combat"]]
	for c in cases:
		if c[1] == "combat" and not combat_zone.is_empty():
			cb.call("start", combat_zone, "")
		else:
			sk.call("start", "wc_pine")
		main.call("show_screen", c[0])
		await _frames(30)
		var secs := 8.0
		var fg := await _cpu_window(secs)
		_n("Clock").call("_notification", NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _frames(5)
		var bg := await _cpu_window(secs)
		_n("Clock").call("_notification", NOTIFICATION_APPLICATION_FOCUS_IN)
		await _frames(5)
		var key := str(c[0]).replace(":", "_")
		_p("idle_%s_foreground" % key, fg)
		_p("idle_%s_background" % key, bg)
	_p("fps_cap_setting", _n("Settings").call("get_value", "fps_cap"))


func _proc_cpu_ms() -> float:
	# CPU di TUTTO il processo (tutti i thread: motore, audio, rasterizzatore software), da /proc/self/stat (utime+stime, 1/100 s)
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0.0
	var line := f.get_line()
	var parts := line.substr(line.rfind(")") + 2).split(" ")
	return (float(parts[11]) + float(parts[12])) * 10.0


## Finestra di misura di `secs` secondi REALI: fotogrammi, CPU del thread principale e di tutto il processo.
func _cpu_window(secs: float) -> Dictionary:
	var c0 := PerfGate.clock_usec()
	var p0 := _proc_cpu_ms()
	var w0 := Time.get_ticks_usec()
	var drawn0 := Engine.get_frames_drawn()
	var frames := 0
	while float(Time.get_ticks_usec() - w0) < secs * 1e6:
		await process_frame
		frames += 1
	var wall := float(Time.get_ticks_usec() - w0) / 1000.0
	var cpu := float(PerfGate.clock_usec() - c0) / 1000.0
	var proc := _proc_cpu_ms() - p0
	return {"wall_s": snappedf(wall / 1000.0, 0.1), "process_frames": frames, "drawn_frames": Engine.get_frames_drawn() - drawn0,
		"fps": snappedf(1000.0 * frames / maxf(wall, 1.0), 0.1), "main_thread_cpu_pct": snappedf(100.0 * cpu / maxf(wall, 1.0), 1.0),
		"process_cpu_pct": snappedf(100.0 * proc / maxf(wall, 1.0), 1.0)}


# ------------------------------------------------------------------ chi tiene vivo il ridisegno

## Elenca i nodi con _process attivo e i tween in corso su una schermata (con mansione in corso), per trovare
## chi causa i ridisegni continui.
func _who() -> void:
	var main := _open_main()
	await _frames(10)
	_n("Game").call("system", "skills").call("start", "wc_pine")
	var scr := _args[1] if _args.size() > 1 else "summary"
	main.call("show_screen", scr)
	await _frames(30)
	var procs := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.is_processing() and n.is_inside_tree():
			var key := "%s (%s)" % [n.get_script().resource_path.get_file() if n.get_script() != null else n.get_class(), n.get_class()]
			procs[key] = int(procs.get(key, 0)) + 1
	_p("who_processing", procs)
	_p("who_tweens", get_processed_tweens().size())
	for t in get_processed_tweens():
		print("PERF tween: ", t)
