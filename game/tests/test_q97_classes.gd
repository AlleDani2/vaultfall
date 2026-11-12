extends GutTest
## Q97 - classi e talenti (QA82 §2: Berserker dominante, shield_wall negativa, talenti difensivi a effetto nullo):
##  C1  Muro di Scudi: costa poco e ha anche un beneficio offensivo (non e' piu' una perdita netta)
##  C2  ogni talento ha almeno un effetto; i nodi difensivi che valevano 0 hanno un secondo effetto misurabile
##  C3  scelta automatica delle abilita': le evocazioni (Compagno del Domatore, Scheletro) entrano nella lista
##  C4  spread delle classi: XP/h stimato a meta' zona entro 1,25 (misura completa: tools/analysis/q97_classes.py)

const Raids := preload("res://tests/helpers/raids_env.gd")
const Fx := preload("res://tests/helpers/sim_fixtures.gd")


func _mods_of(ab: Dictionary) -> Dictionary:
	var out := {}
	for m in ab.effect.get("modifiers", []):
		out[str(m.key)] = float(m.value)
	return out


func test_c1_muro_di_scudi_utile() -> void:
	var ab: Dictionary = DataRegistry.get_def("abilities", "shield_wall")
	var m := _mods_of(ab)
	assert_eq(m.get("combat_dmg_taken_pct", 0.0), -30.0, "riduce ancora i danni subiti del 30%")
	assert_gt(m.get("combat_dmg_pct", 0.0), 0.0, "e aggiunge danno")
	assert_lt(float(ab.cost), 25.0, "costo basso: non toglie Furia alle tecniche offensive")
	assert_gt(float(ab.effect.duration_s) / float(ab.cooldown_s), 0.4, "attivo per almeno il 40% del tempo")


func test_c2_nessun_talento_senza_effetto() -> void:
	for t in DataRegistry.table("talents"):
		assert_false((t.modifiers_per_rank as Array).is_empty(), "%s ha un effetto" % str(t.id))
		assert_gt(int(t.max_rank), 0, "%s ha almeno un rango" % str(t.id))
	for tid in ["pal_resolve", "pyr_mana", "nec_dot"]:
		var keys := []
		for t in DataRegistry.table("talents"):
			if str(t.id) == tid:
				for mm in t.modifiers_per_rank:
					keys.append(str(mm.key))
		assert_gte(keys.size(), 2, "%s: secondo effetto oltre a quello che valeva zero" % tid)


func test_c3_auto_include_le_evocazioni() -> void:
	var env: Object = Raids.make(9731, 60, "ranger", 0)
	for gid in Fx.gear_ids("ranger", Formulas.tier_of_level(60)):
		env.combat.equip(env.bank.add_instance({"def": gid, "quality": "normal", "sockets": [], "rank": 0}))
	env.quests.done["class_beastmaster"] = true
	assert_true(env.combat.build.set_spec("beastmaster"), "Domatore")
	var ids := []
	for ab in env.combat.build.abilities_equipped():
		ids.append(str(ab.id))
	assert_true(ids.has("call_companion"), "il compagno e' nella lista automatica: %s" % str(ids))


func _mid_xp_h(cls: String) -> float:
	var lvl := 55
	var env: Object = Raids.make(9740, lvl, cls if ["warrior", "ranger", "arcanist"].has(cls) else {"berserker": "warrior", "sharpshooter": "ranger", "pyromancer": "arcanist"}[cls], 0)
	var base: String = cls if ["warrior", "ranger", "arcanist"].has(cls) else {"berserker": "warrior", "sharpshooter": "ranger", "pyromancer": "arcanist"}[cls]
	var gear: Array = Fx.gear_ids(base, Formulas.tier_of_level(lvl))
	for gid in gear:
		env.combat.equip(env.bank.add_instance({"def": gid, "quality": "normal", "sockets": [], "rank": 0}))
	var tier := Formulas.tier_of_level(lvl)
	var g: Dictionary = Fx.CLASS_GEAR[base]
	if g.ammo != "":
		var ammo_id: String = ("arrow_" + Fx.WOODS[tier - 1]) if g.ammo == "arrow" else ("rune_t%d" % tier)
		env.bank.add(ammo_id, 100000000, "q97")
		env.combat.equip_ammo(ammo_id)
	env.bank.add("food_embermoray", 100000, "q97")
	env.combat.set_food(0, "food_embermoray")
	env.state.unlocks.append("shop:auto_eat_3")
	if cls != base:
		env.quests.done["class_" + cls] = true
		env.combat.build.set_spec(cls)
	var b: Object = env.combat.build
	var progress := true
	var guard := 0
	while progress and b.points_free() > 0 and guard < 300:
		guard += 1
		progress = false
		for br in [cls, "general"]:
			for t in b.talent_nodes():
				if str(t.branch) == br and b.why_not(str(t.id)).is_empty() and b.rank_up(str(t.id)):
					progress = true
	var total := 0.0
	var n := 0
	for mid in ["ash_scorpion", "dune_raider", "restless_mummy", "ember_djinn"]:
		var e: Dictionary = env.combat.estimate(mid, true)
		total += float(e.kills_per_h) * float(e.xp)
		n += 1
	return total / float(n)


func test_c4_spread_delle_classi_entro_1_25() -> void:
	var vals := {}
	for cls in ["warrior", "ranger", "arcanist", "berserker", "sharpshooter", "pyromancer"]:
		vals[cls] = _mid_xp_h(cls)
	var lo := 1e30
	var hi := 0.0
	for k in vals:
		lo = minf(lo, float(vals[k]))
		hi = maxf(hi, float(vals[k]))
	assert_gt(lo, 0.0, "tutte le classi producono XP")
	assert_lt(hi / lo, 1.25, "spread XP/h %.2f (%s)" % [hi / lo, str(vals)])
