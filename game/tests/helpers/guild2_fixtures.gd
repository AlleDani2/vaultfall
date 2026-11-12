class_name Guild2Fixtures
extends RefCounted
## Banco di prova GUILD-2: Deposito, mansioni, Mercato, Missioni, Prestigio, Compendio, Luoghi Segreti e Sblocchi.
## Bus di segnali PRIVATO (nessun autoload toccato).

var sim: Simulation
var state: Dictionary
var mods: ModifierStack
var events: Node
var bank: BankSystem
var skills: SkillSystem
var market: MarketSystem
var quests: QuestSystem
var prestige: PrestigeSystem
var comp: CompendiumSystem
var secrets: SecretSystem
var unlock: UnlockSystem
var notices: Array = []


static func make(seed_value: int = 7) -> Guild2Fixtures:
	var f := Guild2Fixtures.new()
	f.state = {}
	f.mods = ModifierStack.new()
	f.mods.set_catalog(DataRegistry.table("modifier_catalog"))
	f.events = (load("res://src/autoload/EventBus.gd") as GDScript).new() as Node
	var ctx := SystemContext.make(DataRegistry, f.state, f.mods, RngStreams.new(seed_value), f.events)
	f.sim = Simulation.new()
	f.bank = BankSystem.new()
	f.skills = SkillSystem.new()
	f.market = MarketSystem.new()
	f.quests = QuestSystem.new()
	f.prestige = PrestigeSystem.new()
	f.comp = CompendiumSystem.new()
	f.secrets = SecretSystem.new()
	f.unlock = UnlockSystem.new()
	f.state["unlocks"] = ["skill:woodcutting", "skill:mining", "skill:fishing", "skill:foraging", "skill:trapping", "feature:market",
		"feature:factions"]
	f.state["bank"] = {"gift_done": true}
	f.sim.setup(ctx, [f.bank, f.skills, f.market, f.prestige, f.quests, f.comp, f.secrets, f.unlock])
	f.sim.bind_state(f.state)
	f.events.notice.connect(f._on_notice)
	return f


func _on_notice(kind: String, text: String, data: Dictionary) -> void:
	notices.append({"kind": kind, "text": text, "data": data})


func run(seconds: float, step: float = 0.1) -> void:
	var n := int(round(seconds / step))
	for i in n:
		sim.tick(step)
