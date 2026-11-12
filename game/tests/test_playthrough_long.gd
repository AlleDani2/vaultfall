extends GutTest
## Integrazione finale (resoconto 47): partita VERA giocata da BotPlayer in `long_mode` ben oltre il Cap. I, fino ai
## Capitoli centrali (Tenuta, Gilda, mercenari e spedizioni, Taglie, Fazioni, Contratti, prima incursione) e al primo
## Rito. Il bot gioca attivo a passi da 0,1 s e "va via" (offline analitico vero) durante i compiti lunghi, come un
## giocatore idle. Registra i tempi simulati per capitolo, i blocchi, le ricompense (ritmo delle ore 5-20) e i picchi
## di tick/offline. BOT_LOG=1 stampa il diario completo.

const SEED := 20261047
const LAST_QUEST := "main_c6_q2"          # prima incursione (Covo del Collezionista)
const MAX_S := 120.0 * 3600.0

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_playthrough_long_saves"
	SaveService.autosave_enabled = false


func after_all() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in [1, 2, 3]:
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


var _sys_max: Dictionary = {}          # sistema -> picco del tick (ms)
var _slow: Array = []                  # tick di un sistema oltre 15 ms (diagnosi)
var _steps: int = 0
var _over15: int = 0                   # passi oltre 15 ms x fattore di carico (tutti i sistemi insieme)
var _trk := PerfGate.Tracker.new()     # fattore di carico della macchina durante la partita (PerfGate)


## Come Game._on_step, ma misura il tick di ogni sistema (per trovare chi supera i 15 ms).
func _step(dt: float) -> void:
	var stats: Dictionary = GameState.data.stats
	stats["playtime_s"] = float(stats.get("playtime_s", 0.0)) + dt
	var t_step := PerfGate.clock_usec()
	for gs in Game.sim.systems:
		if gs.enabled:
			var t0 := PerfGate.clock_usec()
			gs.tick(dt)
			var ms := float(PerfGate.clock_usec() - t0) / 1000.0
			if ms > float(_sys_max.get(gs.id, 0.0)):
				_sys_max[gs.id] = ms
			if ms > 15.0:
				_slow.append("%s %.1f ms @%.2f h" % [gs.id, ms, float(stats.playtime_s) / 3600.0])
	var step_ms := float(PerfGate.clock_usec() - t_step) / 1000.0
	_steps += 1
	if step_ms > 15.0 * _trk.f_cur:
		_over15 += 1


func _away(seconds: float) -> void:
	Game._on_long_gap(seconds)


func test_partita_lunga_fino_alla_prima_incursione() -> void:
	assert_true(Game.new_game(1, "normal", SEED))
	var bot := BotPlayer.new(Game.sim, _step)
	bot.long_mode = true
	bot.step_long = _away
	bot.verbose = OS.get_environment("BOT_VERBOSE") != ""
	bot.wall_limit_ms = 450000          # tempo di CPU (bot.clock): immune al carico della macchina; normalmente ~170 s
	_trk.start()
	bot.between_steps = _trk.step
	bot.clock = PerfGate.clock_usec
	var t0 := Time.get_ticks_msec()
	var res := bot.run_until_quest(LAST_QUEST, MAX_S)
	# dopo la prima incursione: il primo Rito (Taglialegna fino al livello del Rito, giocando da idle)
	var t_raid := float(res.t)
	var rr := bot.run_until_rite("woodcutting", MAX_S)
	res = rr
	var wall_s := float(Time.get_ticks_msec() - t0) / 1000.0
	# tabella per missione e per capitolo
	var lines := PackedStringArray()
	var prev := 0.0
	for e in res.quests:
		lines.append("%-12s fine %6.2f h (durata %5.1f min, attivo %5.2f h, via %6.2f h, eroe %2d)" % [e.id, float(e.t) / 3600.0,
			(float(e.t) - prev) / 60.0, float(e.played) / 3600.0, float(e.away) / 3600.0, int(e.hero)])
		prev = float(e.t)
	gut.p("Partita lunga (seme %d), %.0f s reali:\n%s" % [SEED, wall_s, "\n".join(lines)])
	var ch := PackedStringArray()
	var pc := 0.0
	var pp := 0.0
	for e in res.quests:
		if str(e.id).ends_with("_q6"):
			ch.append("Cap. %s: fine %.2f h (durata %.2f h, di cui attiva %.2f h)" % [str(e.id).substr(6, 1), float(e.t) / 3600.0,
				(float(e.t) - pc) / 3600.0, (float(e.played) - pp) / 3600.0])
			pc = float(e.t)
			pp = float(e.played)
	gut.p("Capitoli:\n" + "\n".join(ch))
	gut.p("Totale %.2f h simulate (attivo %.2f h, via %.2f h) · morti %d · picco tick %.2f ms · picco offline %.0f ms" % [
		float(res.t) / 3600.0, float(res.played_s) / 3600.0, float(res.away_s) / 3600.0, int(res.deaths),
		float(res.max_tick_ms), float(res.offline_max_ms)])
	var sm := PackedStringArray()
	for k in _sys_max:
		if float(_sys_max[k]) >= 1.0:
			sm.append("%s %.1f" % [k, float(_sys_max[k])])
	gut.p("Picchi per sistema (ms): " + ", ".join(sm))
	if not _slow.is_empty():
		gut.p("Tick lenti: " + ", ".join(PackedStringArray(_slow.slice(0, 30))))
	var gaps := _reward_gaps(res.rewards, 5.0 * 3600.0, 20.0 * 3600.0)
	gut.p("Ricompense ore 5-20: %d (missioni %d), intervallo massimo %.1f min (da %.2f h), medio %.1f min" % [int(gaps.n), int(gaps.quests),
		float(gaps.max_gap) / 60.0, float(gaps.gap_at) / 3600.0, float(gaps.mean_gap) / 60.0])
	var unl := PackedStringArray()
	for tok in res.unlock_t:
		unl.append("%s@%.1fh" % [tok, float(res.unlock_t[tok]) / 3600.0])
	gut.p("Sblocchi: " + ", ".join(unl))
	if OS.get_environment("BOT_LOG") != "" or not bool(res.ok):
		gut.p("\n".join(bot.log_lines.slice(maxi(0, bot.log_lines.size() - 400))))
	assert_eq(res.blocks, [], "nessun blocco di progressione")
	assert_true((Game.system("quests") as QuestSystem).is_done(LAST_QUEST), "prima incursione completata")
	assert_true(bool(res.ok), "primo Rito fatto")
	gut.p("Prima incursione a %.2f h · primo Rito (Taglialegna) a %.2f h" % [t_raid / 3600.0, float(bot.goal_done_t) / 3600.0])
	assert_eq(res.violations, [], "nessun sistema usato prima dello sblocco")
	# picco: sulle macchine virtuali un passo isolato può essere sospeso dal sistema operativo (sistemi diversi a ogni
	# esecuzione, non riproducibile); il limite vale per il 99,99% dei passi e i rari picchi sono stampati sopra.
	gut.p("Decisioni (ms): " + str(bot.prof))
	gut.p("Passi: %d, oltre 15 ms: %d · tempo reale: decisioni %.0f s, passi %.0f s" % [_steps, _over15, bot.decide_ms / 1000.0, bot.step_ms / 1000.0])
	# limiti di progetto x fattore di carico misurato durante la partita (PerfGate: solo una regressione vera fallisce)
	var f_run := _trk.finish()
	gut.p("Fattore di carico della macchina durante la partita: ultimo %.2f, massimo %.2f" % [_trk.f_cur, f_run])
	assert_lte(_over15, maxi(1, floori(_steps / 10000.0)), "tick ≤ 15 ms x carico (99,99% dei passi) con tutti i sistemi")
	PerfGate.assert_time(self, "ogni blocco offline (obiettivo docs/17 §11, normalmente ~0,3 s)", float(res.offline_max_ms), 1000.0, f_run)
	assert_lt(float(gaps.max_gap), 75.0 * 60.0, "ore 5-20: mai più di 75 minuti senza una ricompensa")
	# offline di 24 ore a metà partita con TUTTI i sistemi in gioco (Tenuta, Gilda, spedizioni, orti, mercato, combattimento)
	var cb := Game.system("combat") as CombatSystem
	var zone := ""
	for z in cb.zones():
		if bool(z.unlocked):
			zone = str(z.id)
	cb.start(zone, "")
	var t1 := PerfGate.clock_usec()
	var per := PackedStringArray()
	var report := {}
	for gs in Game.sim.systems:          # come Simulation.run_offline, misurando ogni sistema
		if gs.enabled:
			var ts := PerfGate.clock_usec()
			var r := gs.simulate_offline(86400.0)
			var ms_s := float(PerfGate.clock_usec() - ts) / 1000.0
			if not r.is_empty():
				report[gs.id] = r
			if ms_s >= 5.0:
				per.append("%s %.0f" % [gs.id, ms_s])
	EventBus.offline_progress.emit(86400.0, report)
	var ms24 := float(PerfGate.clock_usec() - t1) / 1000.0
	gut.p("Offline 24 h a metà partita (zona %s, tutti i sistemi): %.0f ms (%s)" % [zone, ms24, ", ".join(per)])
	PerfGate.assert_time(self, "offline di 24 ore con tutti i sistemi (obiettivo docs/17 §11, normalmente ~0,3 s)", ms24, 1000.0, PerfGate.factor_around(f_run))


## Intervalli tra ricompense (missioni, livelli, casse, costruzioni, sblocchi) nella finestra [a, b] di tempo simulato.
func _reward_gaps(rewards: Array, a: float, b: float) -> Dictionary:
	var ts: Array = []
	var nq := 0
	for r in rewards:
		if float(r.t) >= a and float(r.t) <= b:
			ts.append(float(r.t))
			if str(r.kind) == "quest":
				nq += 1
	ts.sort()
	var mx := 0.0
	var at := a
	var prev := a
	for x in ts:
		if float(x) - prev > mx:
			mx = float(x) - prev
			at = prev
		prev = float(x)
	return {"n": ts.size(), "quests": nq, "max_gap": mx, "gap_at": at, "mean_gap": (b - a) / maxf(1.0, float(ts.size()))}
