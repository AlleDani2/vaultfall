extends RefCounted
const _GS_SCRIPT := preload("res://src/autoload/GameState.gd")
## Ambiente di prova per i test di COMBAT-2 (abilità, talenti, dungeon, boss, taglie, offline): CombatSystem e
## BountySystem veri con Deposito, mansioni e missioni finti (stesse firme dei contratti, docs/audit_2026-10-22/17).

const SimFx := preload("res://tests/helpers/sim_fixtures.gd")


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var inst: Dictionary = {}
	var gold_n: int = 0
	var counter: int = 0
	func _init() -> void:
		id = "bank"
	func add(def_id: String, qty: int, _source: String = "") -> int:
		stacks[def_id] = int(stacks.get(def_id, 0)) + qty
		return qty
	func remove(def_id: String, qty: int) -> bool:
		if int(stacks.get(def_id, 0)) < qty:
			return false
		stacks[def_id] = int(stacks[def_id]) - qty
		return true
	func count(def_id: String) -> int:
		return int(stacks.get(def_id, 0))
	func has(def_id: String, qty: int = 1) -> bool:
		return count(def_id) >= qty
	func add_instance(i: Dictionary) -> String:
		counter += 1
		var uid := "i_%06d" % counter
		i["uid"] = uid
		inst[uid] = i
		return uid
	func get_instance(uid: String) -> Dictionary:
		return inst.get(uid, {})
	func remove_instance(uid: String) -> bool:
		return inst.erase(uid)
	func list_instances() -> Array:
		return inst.values()
	func add_gold(n: int) -> void:
		gold_n += n
	func spend_gold(n: int) -> bool:
		if gold_n < n:
			return false
		gold_n -= n
		return true


class FakeSkills extends GameSystem:
	var levels: Dictionary = {"hero": 1}
	var xp: Dictionary = {}
	func _init() -> void:
		id = "skills"
	func level(skill_id: String) -> int:
		return int(levels.get(skill_id, 1))
	func add_xp(skill_id: String, amount: float) -> void:
		xp[skill_id] = float(xp.get(skill_id, 0.0)) + amount
	func stop() -> void:
		pass


class FakeQuests extends GameSystem:
	var done: Dictionary = {}
	func _init() -> void:
		id = "quests"
	func is_done(quest_id: String) -> bool:
		return bool(done.get(quest_id, false))


var sim: Simulation
var state: Dictionary
var bank: FakeBank
var skills: FakeSkills
var quests: FakeQuests
var combat: CombatSystem
var bounty: BountySystem
var mods: ModifierStack
var bus: Node       # copia privata di EventBus: i test non toccano i sistemi dell'autoload Game


## Crea l'ambiente. `with_bounty` aggiunge BountySystem. Il giocatore parte con il set di equipaggiamento del tier.
static func make(seed_v: int = 7, hero_level: int = 5, cls: String = "warrior", with_bounty: bool = false, extra: Array = []) -> Object:
	var env: Object = (load("res://tests/helpers/combat2_env.gd") as GDScript).new()
	env.state = _GS_SCRIPT.default_state()
	env.mods = ModifierStack.new()
	env.mods.set_catalog(DataRegistry.table("modifier_catalog"))
	env.bus = (load("res://src/autoload/EventBus.gd") as GDScript).new()
	var ctx := SystemContext.make(DataRegistry, env.state, env.mods, RngStreams.new(seed_v), env.bus)
	env.bank = FakeBank.new()
	env.skills = FakeSkills.new()
	env.quests = FakeQuests.new()
	env.skills.levels["hero"] = hero_level
	env.combat = CombatSystem.new()
	var list: Array = [env.combat, env.bank, env.skills, env.quests]
	if with_bounty:
		env.bounty = BountySystem.new()
		list.append(env.bounty)
	list.append_array(extra)             # sistemi in più (COMBAT-3: CrateSystem per le reliquie)
	env.sim = Simulation.new()
	env.sim.setup(ctx, list)
	env.sim.bind_state(env.state)
	env.combat.state["class"] = cls
	return env


func give(def_id: String, quality: String = "normal", rank: int = 0) -> String:
	return bank.add_instance({"def": def_id, "quality": quality, "sockets": [], "rank": rank})


## Equipaggia il set del simulatore (tier t) per la classe base indicata, con munizioni abbondanti.
func gear(cls: String, t: int) -> void:
	for gid in SimFx.gear_ids(cls, t):
		combat.equip(give(gid))
	var g: Dictionary = SimFx.CLASS_GEAR[cls]
	if g.ammo != "":
		var ammo_id: String = ("arrow_" + SimFx.WOODS[t - 1]) if g.ammo == "arrow" else ("rune_t%d" % t)
		bank.add(ammo_id, 1000000, "test")
		combat.equip_ammo(ammo_id)


## Cibo abbondante e cintura III: l'eroe non resta mai senza (per i test sul danno e sui tempi).
func food() -> void:
	bank.add("food_bleak", 1000000, "test")
	combat.set_food(0, "food_bleak")
	state.unlocks.append("shop:auto_eat_3")


func tick(n: int) -> void:
	for i in n:
		sim.tick(FixedStepClock.STEP)


func unlock_zone(zone_id: String) -> void:
	state.unlocks.append("zone:" + zone_id)
