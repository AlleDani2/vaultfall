extends RefCounted
const _GS_SCRIPT := preload("res://src/autoload/GameState.gd")
## Ambiente di prova per Incursioni, Boss mondiali e Breccia (agente RAIDS): CombatSystem e MercenarySystem veri,
## Deposito/mansioni/missioni/Prestigio finti con le stesse firme dei contratti (docs/audit_2026-10-22/17).
## Bus di eventi privato: i test non toccano i sistemi dell'autoload Game.

const SimFx := preload("res://tests/helpers/sim_fixtures.gd")
const Base := preload("res://tests/helpers/combat2_env.gd")


class FakePrestige extends GameSystem:
	var calls: Array = []
	var rules: Dictionary = {}
	var active: Dictionary = {}              # Prova in corso (COMBAT-3: porzioni mangiate del Digiuno)
	func _init() -> void:
		id = "prestige"
	func trial_active() -> Dictionary:
		return active
	func on_warden_defeated(era: int) -> int:
		calls.append(era)
		return 5 * era
	func trial_rules_active() -> Dictionary:
		return rules


class FakeQuests extends GameSystem:
	var done: Dictionary = {}
	var active: Dictionary = {}
	func _init() -> void:
		id = "quests"
	func is_done(quest_id: String) -> bool:
		return bool(done.get(quest_id, false))
	func is_active(quest_id: String) -> bool:
		return bool(active.get(quest_id, false))


var sim: Simulation
var state: Dictionary
var bank: Object
var skills: Object
var quests: FakeQuests
var prestige: FakePrestige
var combat: CombatSystem
var mercs: MercenarySystem
var mods: ModifierStack
var bus: Node


static func make(seed_v: int = 7, hero_level: int = 55, cls: String = "warrior", tier: int = 6) -> Object:
	var env: Object = (load("res://tests/helpers/raids_env.gd") as GDScript).new()
	env.state = _GS_SCRIPT.default_state()
	env.mods = ModifierStack.new()
	env.mods.set_catalog(DataRegistry.table("modifier_catalog"))
	env.bus = (load("res://src/autoload/EventBus.gd") as GDScript).new()
	var ctx := SystemContext.make(DataRegistry, env.state, env.mods, RngStreams.new(seed_v), env.bus)
	env.bank = Base.FakeBank.new()
	env.skills = Base.FakeSkills.new()
	env.skills.levels["hero"] = hero_level
	env.quests = FakeQuests.new()
	env.prestige = FakePrestige.new()
	env.combat = CombatSystem.new()
	env.mercs = MercenarySystem.new()
	env.sim = Simulation.new()
	env.sim.setup(ctx, [env.combat, env.bank, env.skills, env.quests, env.prestige, env.mercs])
	env.sim.bind_state(env.state)
	env.combat.state["class"] = cls
	if tier > 0:
		env.gear(cls, tier)
	env.food()
	return env


func give(def_id: String) -> String:
	return bank.add_instance({"def": def_id, "quality": "normal", "sockets": [], "rank": 0})


func gear(cls: String, t: int) -> void:
	for gid in SimFx.gear_ids(cls, t):
		combat.equip(give(gid))
	var g: Dictionary = SimFx.CLASS_GEAR[cls]
	if g.ammo != "":
		var ammo_id: String = ("arrow_" + SimFx.WOODS[t - 1]) if g.ammo == "arrow" else ("rune_t%d" % t)
		bank.add(ammo_id, 1000000, "test")
		combat.equip_ammo(ammo_id)


func food() -> void:
	bank.add("food_bleak", 1000000, "test")
	combat.set_food(0, "food_bleak")
	state.unlocks.append("shop:auto_eat_3")


func tick(n: int) -> void:
	for i in n:
		sim.tick(FixedStepClock.STEP)


## Aggiunge un mercenario alla Taverna (stato diretto) e ne restituisce l'uid.
func merc(role: String, rarity: String = "epic", level: int = 40, traits: Array = [], equip_tier: int = 0) -> String:
	var st: Dictionary = mercs.state
	st["seq"] = int(st.seq) + 1
	var uid := "m_%06d" % int(st.seq)
	(st.roster as Array).append({"uid": uid, "name": "Prova %d" % int(st.seq), "role": role, "rarity": rarity, "level": level, "xp": 0.0,
		"traits": traits, "equip_tier": equip_tier, "injured_until": 0.0, "busy": ""})
	return uid


## Squadra completa (difensore, guaritore, assaltatore) di pari rarità e livello.
func party(rarity: String = "epic", level: int = 40) -> Array:
	return [merc("defender", rarity, level), merc("healer", rarity, level), merc("striker", rarity, level)]


func unlock_raid(raid_id: String) -> void:
	state.unlocks.append("raid:" + raid_id)
