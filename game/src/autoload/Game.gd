extends Node
## Game (autoload) — orchestratore della partita (docs/17 §5: "Game = orchestratore").
## Collega Clock -> Simulation, crea/carica/chiude le partite, prepara lo snapshot per SaveService.
## La UI chiama: Game.new_game(slot, mode) · Game.load_game(slot) · Game.stop_game() · Game.system("buffs").

var sim := Simulation.new()
var ctx: SystemContext
var snapshot_cache := SnapshotCache.new()      # copie riusabili delle liste grandi per l'autosalvataggio (E47-6)
## Avvisi emessi da load_game PRIMA che esista la schermata principale (StartScreen carica e solo dopo cambia scena): senza questa
## coda andrebbero persi (orologio indietro, salvataggio senza data, ripiego sul backup). MainScreen li mostra in _ready (QA120).
var load_notices: Array = []
## Limite duro di clic/s della Sabbia del Custode (solo CPU: l'equita' la da' la riserva, UI F13).
var click_limiter: ClickLimiter


func _ready() -> void:
	ctx = SystemContext.make(DataRegistry, GameState.data, Modifiers.stack, Rng.streams, EventBus)
	sim.setup(ctx)
	_set_systems_enabled(false)        # nessuna partita: i sistemi si accendono con new_game/load_game
	Clock.core.stepped.connect(_on_step)
	Clock.core.long_gap.connect(_on_long_gap)


func is_active() -> bool:
	return GameState.active


func system(system_id: String) -> GameSystem:
	return sim.get_system(system_id)


## Nuova partita nello slot (1..3). Sovrascrive lo slot: la conferma è compito della UI.
func new_game(slot: int, mode: String = "normal", seed_value: int = -1) -> bool:
	if not GameState.ENABLED_MODES.has(mode):
		return false
	load_notices.clear()
	if GameState.active:
		stop_game(true)                   # i progressi non salvati della partita in corso non si buttano via
	GameState.reset_new(mode, Clock.now_unix())
	snapshot_cache.reset()
	Modifiers.clear_all()
	Rng.seed_all(seed_value if seed_value >= 0 else RngStreams.fresh_seed())
	GameState.data["rng"] = Rng.to_state()
	_set_systems_enabled(true)
	sim.bind_state(GameState.data)
	var ms := system("modes") as ModeSystem
	if ms != null:                        # la nuova partita nasce Cozy se la preferenza del PC lo chiede; da lì lo ricorda lei
		ms.set_cozy(bool(Settings.get_value("cozy_mode")))
	GameState.slot = slot
	GameState.active = true
	EventBus.state_loaded.emit()
	EventBus.game_started.emit(slot, true)
	SaveService.save_now(true)            # la partita che occupava lo slot (se c'era) passa sempre a .bak1
	return true


## Carica lo slot. Ritorna il risultato di SaveService.load_slot ({ok, error, source, offline_s}).
func load_game(slot: int) -> Dictionary:
	load_notices.clear()
	var res := SaveService.load_slot(slot, sim.int_paths())
	if not res.ok:
		return res
	if GameState.active:
		# Un'altra partita in corso si salva prima di sostituirla; ricaricare lo STESSO slot e' un «torna all'ultimo salvataggio»
		# esplicito e scarta lo stato in memoria.
		stop_game(GameState.slot != slot)
	GameState.replace(res.data)
	snapshot_cache.reset()
	Modifiers.clear_all()
	var rng_state: Variant = GameState.data.get("rng", {})
	if not (rng_state is Dictionary) or not Rng.from_state(rng_state):
		push_warning("Game: stato RNG assente o non valido, nuovo seed")
		Rng.seed_all(RngStreams.fresh_seed())
	_set_systems_enabled(true)
	sim.bind_state(GameState.data)
	GameState.slot = slot
	GameState.active = true
	SaveService.mark_saved(int(GameState.data.get("saved_at_unix", 0)))     # «salvato N min fa» conta dal file, non dall'apertura
	EventBus.state_loaded.emit()
	if str(res.get("source", "main")) != "main":
		# QA120: il file principale non si apriva (o la scrittura era a meta'): detto in chiaro, con l'eta' della copia
		var age := maxi(1, Clock.now_unix() - int(GameState.data.get("saved_at_unix", 0)))
		_load_notice("warning", Loc.tf("UI_QA120_BACKUP_LOADED", {"time": NumberFormat.fmt_time(float(age))}))
	# progressi offline (il limite cresce con i modificatori offline_cap_hours, max constants.offline.cap_max_h)
	var gap := offline_gap(Clock.now_unix(), int(GameState.data.get("saved_at_unix", 0)))
	if bool(gap.get("no_reference", false)):
		# QA81 M4: salvataggio senza data valida (0 o negativa): nessun riferimento, quindi nessun tempo regalato
		GameState.data["saved_at_unix"] = int(gap.now)
		res["no_time_reference"] = true
		_load_notice("warning", tr("UI_OFFL_NOREF"))
	if bool(gap.rewound):
		# R-OFF-1 (G52): orologio di sistema tornato indietro -> Δt = 0 e il riferimento si riallinea ADESSO, così il
		# prossimo calcolo non conta né regala il tratto "nel futuro" (anche se la partita si chiude prima di un salvataggio)
		GameState.data["saved_at_unix"] = int(gap.now)
		res["clock_rewound_s"] = int(gap.rewound_s)
		_load_notice("warning", Loc.tf("UI_GAPM_CLOCK_REWOUND", {"time": NumberFormat.fmt_time(float(gap.rewound_s))}))
	res["offline_s"] = apply_absence(float(gap.elapsed))
	EventBus.game_started.emit(slot, false)
	return res


## Avviso di caricamento: va al registro subito (se la schermata principale c'e' gia') e resta in coda per quella che nasce dopo.
func _load_notice(kind: String, text: String) -> void:
	load_notices.append({"kind": kind, "text": text})
	EventBus.notice.emit(kind, text, {"section": "system"})


## Consegna (una sola volta) gli avvisi di caricamento a chi nasce dopo il caricamento: MainScreen in _ready.
func take_load_notices() -> Array:
	var out := load_notices.duplicate()
	load_notices.clear()
	return out


## Assenza di `elapsed` secondi: prima il calendario per la parte oltre il limite offline (R-OFF-6: Commesse, limiti
## giornalieri, rinnovi; nessuna produzione), poi l'offline vero fino al limite (R-OFF-1). Ritorna i secondi di offline.
func apply_absence(elapsed: float) -> float:
	var cap_s := offline_cap_s()
	var offline_s := minf(maxf(0.0, elapsed), cap_s)
	var uncounted := maxf(0.0, elapsed) - offline_s
	sim.run_calendar(uncounted)
	# QA81 M4: sotto la soglia minima (dati: offline.min_apply_s) il simulatore non parte: il tempo si accumula in
	# `offline_carry_s` e si applica alla prossima sessione (chi sospende e riprende di continuo non perde nulla né paga ogni volta).
	var off: Dictionary = DataRegistry.constants.get("offline", {})
	var carry := maxf(0.0, float(GameState.data.get("offline_carry_s", 0.0)))
	var total := minf(offline_s + carry, cap_s)
	if total < float(off.get("min_apply_s", 0.0)):
		GameState.data["offline_carry_s"] = total if total >= FixedStepClock.STEP else 0.0
		return offline_s
	GameState.data["offline_carry_s"] = 0.0
	if total >= FixedStepClock.STEP:
		var report := sim.run_offline(total)
		if uncounted >= 1.0:
			# R-OFF-4 (QA81 B4): dire quanto dell'assenza NON è stato contato (oltre il limite): solo il calendario è avanzato
			report["absence"] = {"rows": [{"key": "UI_OFFL_UNCOUNTED", "params": {"time": NumberFormat.fmt_time(uncounted),
				"limit": NumberFormat.fmt_time(cap_s)}}]}
		EventBus.offline_progress.emit(total, report)
	return offline_s


## Chiude la partita in corso (salvando, di base) e torna allo stato "nessuna partita".
func stop_game(save: bool = true) -> void:
	if not GameState.active:
		return
	if save:
		SaveService.save_now()
	load_notices.clear()
	GameState.clear()
	snapshot_cache.reset()
	Modifiers.clear_all()
	_set_systems_enabled(false)
	EventBus.game_stopped.emit()


## Sistemi accesi solo a partita in corso (a partita chiusa non devono reagire ai segnali di EventBus).
func _set_systems_enabled(on: bool) -> void:
	for gs in sim.systems:
		gs.enabled = on


## R-OFF-1: tempo trascorso dall'ultimo salvataggio. Se l'orologio è tornato indietro (`now` < `saved_at`) il tempo è 0
## e `rewound` dice di quanto, perché il chiamante riallinei il riferimento. Pura: {elapsed, rewound, rewound_s, now}.
func offline_gap(now: int, saved_at: int) -> Dictionary:
	if saved_at <= 0:
		# nessun riferimento valido (campo mancante o negativo): Δt = 0, non il limite pieno (QA81 M4)
		return {"elapsed": 0, "rewound": false, "rewound_s": 0, "now": now, "no_reference": true}
	if now < saved_at:
		return {"elapsed": 0, "rewound": true, "rewound_s": saved_at - now, "now": now}
	return {"elapsed": maxi(0, now - saved_at), "rewound": false, "rewound_s": 0, "now": now}


## Clessidra del Custode (R-OFF-5, G05): 1 h di progresso all'azione attiva, mostrata nel Bentornato come l'offline vero.
## Ritorna il risultato di Hourglass.use ({ok, seconds, report} o {ok: false, reason}).
func use_hourglass() -> Dictionary:
	if not GameState.active:
		return {"ok": false, "reason": "UI_GAPM_HG_REASON_IDLE"}
	var res := Hourglass.use(ctx)
	if bool(res.ok):
		EventBus.offline_progress.emit(float(res.seconds), res.report)
		SaveService.save_now()
	else:
		EventBus.notice.emit("warning", tr(str(res.reason)), {"section": "system"})
	return res


## Limite offline in secondi (docs/14 §3: offline_cap_hours si somma, totale massimo cap_max_h).
func offline_cap_s() -> float:
	var off: Dictionary = DataRegistry.constants.get("offline", {})
	var base_h := float(off.get("cap_base_h", 0))
	var max_h := float(off.get("cap_max_h", base_h))
	return minf(max_h, base_h + Modifiers.total_add("offline_cap_hours")) * 3600.0


## Copia dello stato pronta da salvare (sul thread principale; la scrittura avviene su un thread). Le liste grandi
## (Deposito con migliaia di istanze) si copiano a pezzi riusando quelli invariati (`SnapshotCache`); `full = true`
## (uscita, salvataggio sincrono, esportazione) rifà la copia profonda completa. Il risultato è SOLA LETTURA.
func snapshot(full: bool = false) -> Dictionary:
	sim.collect_state(GameState.data)
	GameState.data["rng"] = Rng.to_state()
	GameState.data["saved_at_unix"] = Clock.now_unix()
	GameState.data["schema_version"] = SaveCodec.SCHEMA_VERSION
	return snapshot_cache.snapshot(GameState.data, full)


func _on_step(dt: float) -> void:
	if not GameState.active:
		return
	var stats: Dictionary = GameState.data.stats
	stats["playtime_s"] = float(stats.get("playtime_s", 0.0)) + dt
	sim.tick(dt)


## Coda della Sabbia del Custode: a ogni fotogramma esegue i passi concessi dai clic (max_steps_per_frame passi e
## max_cpu_ms_per_frame ms di CPU, dai dati). Mai FixedStepClock ne' Clock.set_speed: il Clock non sa nulla della Sabbia.
func _process(_delta: float) -> void:
	if not GameState.active or Clock.core.paused:
		return
	var tp := system("time_push") as TimePushSystem
	if tp == null or tp.pending_s() <= 0.0:
		return
	var k: Dictionary = DataRegistry.constants.get("time_push", {})
	tp.drain(int(k.get("max_steps_per_frame", 1)), int(k.get("max_cpu_ms_per_frame", 0)) * 1000)


## Sabbia del Custode: `n_clicks` clic dell'interfaccia (ogni evento accettato dal limitatore vale al massimo click_s di tempo
## all'azione in corso). Ritorna {ok, accepted, seconds, reason}; se non va: EventBus.push_blocked(reason). Il clic oltre
## max_cps al secondo si ignora in silenzio (nessuna accusa, nessuna rilevazione). Gli eventi `echo` vanno scartati a monte.
func request_push(n_clicks: int = 1) -> Dictionary:
	return _request_push(n_clicks, true)


## Comando di debug (solo build di debug, come il ×N di Clock.set_speed): spende N clic senza il limitatore, utile ai test e al bot.
func debug_push(n_clicks: int) -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "accepted": 0, "seconds": 0.0, "reason": ""}
	return _request_push(n_clicks, false)


func _request_push(n_clicks: int, limited: bool) -> Dictionary:
	var tp := system("time_push") as TimePushSystem
	var reason := "UI_PUSH_REASON_NONE"
	if not GameState.active or tp == null:
		return {"ok": false, "accepted": 0, "seconds": 0.0, "reason": reason}
	if Clock.core.paused:
		reason = "UI_PUSH_REASON_PAUSE"
	else:
		var accepted := maxi(0, n_clicks)
		if limited:
			if click_limiter == null:
				click_limiter = ClickLimiter.from_constants(DataRegistry.constants)
			accepted = 0
			var now := Time.get_ticks_usec()
			for i in maxi(0, n_clicks):
				if not click_limiter.accept(now):
					break
				accepted += 1
			if accepted == 0 and n_clicks > 0:
				return {"ok": false, "accepted": 0, "seconds": 0.0, "reason": ""}     # oltre il limite: ignorato in silenzio
		var res := tp.request(accepted)
		if bool(res.ok):
			return {"ok": true, "accepted": accepted, "seconds": float(res.seconds), "reason": ""}
		reason = str(res.reason)
	EventBus.push_blocked.emit(reason)
	return {"ok": false, "accepted": 0, "seconds": 0.0, "reason": reason}


func _on_long_gap(seconds: float) -> void:
	if not GameState.active or not is_finite(seconds) or seconds <= 0.0:
		return
	# QA82 Q82-4: stesso limite del caricamento (R-OFF-1). Oltre il tetto passa solo il calendario (R-OFF-6), nessuna produzione.
	apply_absence(seconds)
