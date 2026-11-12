class_name SystemContext
extends RefCounted
## Tutto ciò che un GameSystem può usare, passato esplicitamente (niente accesso diretto agli autoload nei
## sistemi: così i test possono fornire dati, RNG e modificatori isolati).
##   ctx.data       -> DataRegistry (sola lettura: item(), action(), table(), get_def(), constants)
##   ctx.state      -> Dictionary radice dello stato (GameState.data); scrivere SOLO nella propria sezione
##   ctx.modifiers  -> ModifierStack (Modifiers.stack in gioco)
##   ctx.rng        -> RngStreams (Rng.streams in gioco)
##   ctx.events     -> oggetto con i segnali di EventBus (l'autoload in gioco e nei test)
##   ctx.get_system("bank") -> un altro sistema della stessa Simulation (riferimento debole: niente cicli)

var data: Object
var state: Dictionary = {}
var modifiers: ModifierStack
var rng: RngStreams
var events: Object
var _sim_ref: WeakRef
var _mode_rules: ModeRules


static func make(p_data: Object, p_state: Dictionary, p_modifiers: ModifierStack, p_rng: RngStreams,
		p_events: Object) -> SystemContext:
	var c := SystemContext.new()
	c.data = p_data
	c.state = p_state
	c.modifiers = p_modifiers
	c.rng = p_rng
	c.events = p_events
	return c


## Costanti di gioco (constants.json) già unite da Formulas.
func constants() -> Dictionary:
	return Formulas.k()


func set_simulation(sim: Simulation) -> void:
	_sim_ref = weakref(sim)


func simulation() -> Simulation:
	return _sim_ref.get_ref() if _sim_ref != null else null


func get_system(system_id: String) -> GameSystem:
	var s := simulation()
	return s.get_system(system_id) if s != null else null


## Regole della modalità della partita (Normale/Autarchica/Estrema, docs/05 §7). Le legge dallo stato radice
## (`mode`, scelta alla creazione e immutabile): i sistemi chiedono al ModeRules, mai `if mode ==`.
func mode_rules() -> ModeRules:
	var m := str(state.get("mode", ModeRules.NORMAL))
	if _mode_rules == null or _mode_rules.mode_id != m:
		_mode_rules = ModeRules.make(data, m)
	return _mode_rules
