class_name EstateFixtures
extends RefCounted
## Banco di prova di Tenuta/Gilda: simulazione con Deposito vero, mansioni, Tenuta, Apprendisti, Mercenari e Spedizioni.
## Ogni chiamata crea uno stato nuovo e indipendente (nessun autoload toccato).

var sim: Simulation
var state: Dictionary
var mods: ModifierStack
var bank: BankSystem
var skills: SkillSystem
var estate: EstateSystem
var apprentices: ApprenticeSystem
var mercs: MercenarySystem
var exps: ExpeditionSystem
var unlock: UnlockSystem
var prestige: PrestigeSystem       # unico proprietario di Soci e Rifondazione (audit 42)
## Bus di segnali PRIVATO (copia dello script di EventBus): evita che i sistemi dell'autoload Game (non avviato) ricevano i segnali.
var events: Node

const ALL_BUILDINGS := ["cottage", "sawmill", "mine_shaft", "fishery", "fields", "ranch", "shopfront", "warehouse",
	"private_vault", "academy", "tavern"]


static func make(seed_value: int = 11) -> EstateFixtures:
	var f := EstateFixtures.new()
	f.state = {}
	f.mods = ModifierStack.new()
	f.mods.set_catalog(DataRegistry.table("modifier_catalog"))
	f.events = (load("res://src/autoload/EventBus.gd") as GDScript).new() as Node
	var ctx := SystemContext.make(DataRegistry, f.state, f.mods, RngStreams.new(seed_value), f.events)
	f.sim = Simulation.new()
	f.bank = BankSystem.new()
	f.skills = SkillSystem.new()
	f.estate = EstateSystem.new()
	f.apprentices = ApprenticeSystem.new()
	f.mercs = MercenarySystem.new()
	f.exps = ExpeditionSystem.new()
	f.unlock = UnlockSystem.new()
	f.prestige = PrestigeSystem.new()
	f.state["unlocks"] = ["skill:woodcutting", "skill:mining", "skill:fishing"]
	for b in ALL_BUILDINGS:
		(f.state["unlocks"] as Array).append("building:" + b)
	# Deposito vuoto: i test di Tenuta/Gilda contano oro e oggetti dal nulla. Il regalo di nuova partita
	# (constants.new_game_gift: 25 oro + 10 Alborelle, aggiunto dall'integrazione) si salta segnandolo già dato.
	f.state["bank"] = {"gift_done": true}
	f.sim.setup(ctx, [f.bank, f.skills, f.apprentices, f.estate, f.mercs, f.exps, f.unlock, f.prestige])
	f.sim.bind_state(f.state)
	return f


## Imposta direttamente i livelli degli edifici (salta costi e coloni) e riempie coloni e Dispensa.
func set_levels(levels: Dictionary, settlers: int = -1, pantry: float = 100000.0) -> void:
	for bid in levels:
		var e: Dictionary = estate._entry(bid)
		e["level"] = int(levels[bid])
	estate.state.settlers = settlers if settlers >= 0 else estate.settler_cap()
	estate.state.pantry = pantry


func run(seconds: float, step: float = 0.1) -> void:
	var n := int(round(seconds / step))
	for i in n:
		sim.tick(step)
