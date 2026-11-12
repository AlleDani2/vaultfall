extends RefCounted
const _GS_SCRIPT := preload("res://src/autoload/GameState.gd")
## Ambiente di prova per la modalità Amici (COOP-1): come raids_env (CombatSystem e MercenarySystem veri, resto finto)
## più CoopSystem, UnlockSystem vero e un Compendio finto che registra i titoli. Bus di eventi privato.

const SimFx := preload("res://tests/helpers/sim_fixtures.gd")
const Base := preload("res://tests/helpers/combat2_env.gd")
const Raids := preload("res://tests/helpers/raids_env.gd")


class FakeCompendium extends GameSystem:
	var titles: Array = []
	func _init() -> void:
		id = "compendium"
	func grant_title(title_id: String) -> bool:
		if titles.has(title_id):
			return false
		titles.append(title_id)
		return true
	func selected_title() -> String:
		return "title_vaultbreaker"


var sim: Simulation
var state: Dictionary
var bank: Object
var skills: Object
var quests: Raids.FakeQuests
var prestige: Raids.FakePrestige
var combat: CombatSystem
var mercs: MercenarySystem
var coop: CoopSystem
var modes: ModeSystem
var comp: FakeCompendium
var unlock: UnlockSystem
var mods: ModifierStack
var bus: Node
static var _created: Array = []


static func make(seed_v: int = 7, hero_level: int = 55, cls: String = "warrior", tier: int = 6, created_at: int = 1700000000) -> Object:
	var env: Object = (load("res://tests/helpers/coop_env.gd") as GDScript).new()
	env.state = _GS_SCRIPT.default_state()
	env.state["created_at_unix"] = created_at
	env.mods = ModifierStack.new()
	env.mods.set_catalog(DataRegistry.table("modifier_catalog"))
	env.bus = (load("res://src/autoload/EventBus.gd") as GDScript).new()
	_created.append(env.bus)
	var ctx := SystemContext.make(DataRegistry, env.state, env.mods, RngStreams.new(seed_v), env.bus)
	env.bank = Base.FakeBank.new()
	env.skills = Base.FakeSkills.new()
	env.skills.levels["hero"] = hero_level
	env.quests = Raids.FakeQuests.new()
	env.prestige = Raids.FakePrestige.new()
	env.comp = FakeCompendium.new()
	env.unlock = UnlockSystem.new()
	env.combat = CombatSystem.new()
	env.mercs = MercenarySystem.new()
	env.coop = CoopSystem.new()
	env.modes = ModeSystem.new()
	env.sim = Simulation.new()
	env.sim.setup(ctx, [env.combat, env.bank, env.skills, env.quests, env.prestige, env.mercs, env.comp, env.unlock, env.coop, env.modes])
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


func merc(role: String, rarity: String = "epic", level: int = 40, traits: Array = [], equip_tier: int = 0) -> String:
	var st: Dictionary = mercs.state
	st["seq"] = int(st.seq) + 1
	var uid := "m_%06d" % int(st.seq)
	(st.roster as Array).append({"uid": uid, "name": "Prova %d" % int(st.seq), "role": role, "rarity": rarity, "level": level, "xp": 0.0,
		"traits": traits, "equip_tier": equip_tier, "injured_until": 0.0, "busy": ""})
	return uid


func party(rarity: String = "epic", level: int = 40) -> Array:
	return [merc("defender", rarity, level), merc("healer", rarity, level), merc("striker", rarity, level)]


func unlock_raid(raid_id: String) -> void:
	state.unlocks.append("raid:" + raid_id)


## Codice-eroe di questo ambiente importato in `other` (un altro ambiente): ritorna l'esito dell'importazione.
func share_to(other: Object, now_unix: int = 1760000000) -> Dictionary:
	return other.coop.import_code(coop.export_hero_code(now_unix), now_unix)


## Libera i bus di eventi privati creati dagli ambienti (evita nodi orfani): da chiamare in after_each.
static func free_all() -> void:
	for b in _created:
		if is_instance_valid(b):
			(b as Node).free()
	_created.clear()
