class_name Simulation
extends RefCounted
## Orchestratore puro dei sistemi (docs/17 §5). Non conosce nodi né tempo reale: riceve dt.
## In gioco lo possiede l'autoload Game (alimentato da Clock); nei test si crea direttamente:
##   var sim := Simulation.new()
##   sim.setup(ctx)                       # crea i sistemi di SystemRegistry (o setup(ctx, [MioSistema.new()]))
##   sim.bind_state(state)                # aggancia le sezioni di stato
##   for i in 100: sim.tick(0.1)

const _GameStateScript := preload("res://src/autoload/GameState.gd")

var ctx: SystemContext
var systems: Array[GameSystem] = []
## Vero mentre `run_offline` consuma il tempo in blocco: l'audio resta in silenzio (docs/21 §4).
var offline_running: bool = false
var _by_id: Dictionary = {}


## Crea e prepara i sistemi. `custom` (facoltativo) sostituisce l'elenco di SystemRegistry (utile nei test).
func setup(p_ctx: SystemContext, custom: Array = []) -> void:
	ctx = p_ctx
	ctx.set_simulation(self)
	systems.clear()
	_by_id.clear()
	var list: Array = custom if not custom.is_empty() else SystemRegistry.create_all()
	for s in list:
		var gs: GameSystem = s
		assert(not gs.id.is_empty(), "un GameSystem deve avere un id")
		assert(not _by_id.has(gs.id), "id di sistema duplicato: " + gs.id)
		gs.ctx = ctx
		systems.append(gs)
		_by_id[gs.id] = gs
	for gs in systems:
		gs.setup()


func get_system(system_id: String) -> GameSystem:
	return _by_id.get(system_id)


## Dopo nuova partita o caricamento: completa le sezioni mancanti e le consegna ai sistemi.
func bind_state(root: Dictionary) -> void:
	ctx.state = root
	for gs in systems:
		if gs.state_key.is_empty():
			gs.from_state(null)
			continue
		# sezione mancante, null o di tipo sbagliato (salvataggio danneggiato): si riparte dallo stato iniziale del sistema (QA 83 C-05)
		if not root.has(gs.state_key) or root[gs.state_key] == null or typeof(root[gs.state_key]) != typeof(gs.default_state()):
			root[gs.state_key] = gs.default_state()
		gs.from_state(root[gs.state_key])


## Prima del salvataggio: ogni sistema riscrive la propria sezione.
func collect_state(root: Dictionary) -> void:
	for gs in systems:
		if not gs.state_key.is_empty():
			root[gs.state_key] = gs.to_state()


func tick(dt: float) -> void:
	for gs in systems:
		if gs.enabled:
			gs.tick(dt)


## Tick dei SOLI sistemi indicati (Sabbia del Custode, UI F13), nell'ordine fisso di SystemRegistry (quindi `bank` prima, come
## Hourglass.SYSTEMS_FOR). Nessun altro sistema avanza; NON tocca `stats.playtime_s`, il calendario, i buff, l'Orto, la Tenuta,
## le spedizioni e il mercato (quella e' Game._on_step). `ids` puo' essere in qualunque ordine: conta l'ordine del registro.
func tick_subset(ids: Array, dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	for gs in systems:
		if gs.enabled and ids.has(gs.id):
			gs.tick(dt)


## Tempo in blocco: ogni sistema lo consuma nell'ordine fisso. Ritorna {id_sistema: resoconto}.
func run_offline(seconds: float) -> Dictionary:
	var report := {}
	if not is_finite(seconds) or seconds <= 0.0:
		return report
	offline_running = true
	for gs in systems:
		if gs.enabled:
			var r := gs.simulate_offline(seconds)
			if not r.is_empty():
				report[gs.id] = r
	offline_running = false
	for gs in systems:
		if gs.enabled:
			var f := gs.finish_offline()
			if not f.is_empty():
				report[gs.id] = _merge_section(report.get(gs.id, {}), f)
	return report


## Unisce due sezioni del resoconto dello stesso sistema (le righe si sommano, le altre chiavi della seconda vincono).
static func _merge_section(a: Variant, b: Dictionary) -> Dictionary:
	var out: Dictionary = (a as Dictionary).duplicate(true) if a is Dictionary else {}
	for k in b:
		if k == "rows" and out.has("rows"):
			out["rows"] = (out["rows"] as Array) + (b["rows"] as Array)
		else:
			out[k] = b[k]
	return out


## R-OFF-6 (audit 84): la parte dell'assenza oltre il limite offline fa avanzare solo gli orologi di calendario.
func run_calendar(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for gs in systems:
		if gs.enabled:
			gs.advance_calendar(seconds)


## Percorsi interi «morbidi» (GameSystem.soft_int_paths) di tutti i sistemi + quelli base di GameState.
func soft_int_paths() -> PackedStringArray:
	var out := PackedStringArray(_GameStateScript.BASE_SOFT_INT_PATHS)
	for gs in systems:
		if gs.state_key.is_empty():
			continue
		for p in gs.soft_int_paths():
			out.append(gs.state_key + "." + p)
	return out


## Tutti i percorsi interi da normalizzare al load: quelli base di GameState + quelli dei sistemi.
func int_paths() -> PackedStringArray:
	var out := PackedStringArray(_GameStateScript.BASE_INT_PATHS)
	for gs in systems:
		if gs.state_key.is_empty():
			continue
		for p in gs.int_paths():
			out.append(gs.state_key + "." + p)
	return out
