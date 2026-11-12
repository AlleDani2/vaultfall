extends RefCounted
## Fixture del simulatore di bilanciamento (tools/balance_sim.py: CLASS_GEAR, gear_set, allocazione "standard"
## degli attributi). NON sono regole di gioco: servono solo a ricostruire gli stessi eroi di riferimento dei
## casi "hero_stats" e "fight" di reference_values.json, usando gli oggetti VERI di data/items.

const CLASS_GEAR := {
	"warrior": {"armor": "plate", "weapon": "sword", "offhand": "shield", "ring": "might", "primary": "str", "style": "melee", "ammo": ""},
	"warrior2h": {"armor": "plate", "weapon": "greatsword", "offhand": "", "ring": "might", "primary": "str", "style": "melee", "ammo": ""},
	"ranger": {"armor": "leather", "weapon": "shortbow", "offhand": "", "ring": "aim", "primary": "dex", "style": "ranged", "ammo": "arrow"},
	"arcanist": {"armor": "cloth", "weapon": "wand", "offhand": "tome", "ring": "arcana", "primary": "int", "style": "arcane", "ammo": "rune"},
}
const METALS := ["copper", "bronze", "iron", "steel", "cobalt", "moonsilver", "orichalcum", "bloodiron", "astralite", "starsteel", "vaultsteel"]
const WOODS := ["pine", "birch", "chestnut", "cedar", "ebony", "ironwood", "raventhorn", "silverbark", "vesperwood", "starwood", "vaultroot"]
const BEASTS := ["rabbit", "fox", "deer", "lynx", "bear", "basilisk", "gryphon", "wyvern", "panther", "stormdrake", "starbeast"]
const FIBERS := ["flax", "hemp", "cotton", "nettle", "silk", "moonthistle", "byssus", "ember", "shadowsilk", "starthread", "vaultthread"]
const SLOTS := ["helm", "body", "legs", "gloves", "boots"]


static func gear_ids(cls: String, t: int) -> Array:
	var g: Dictionary = CLASS_GEAR[cls]
	var ids: Array = []
	var mat: String = {"plate": METALS, "leather": BEASTS, "cloth": FIBERS}[g.armor][t - 1]
	for s in SLOTS:
		ids.append("%s_%s_%s" % [g.armor, s, mat])
	var w: String = g.weapon
	ids.append("%s_%s" % [w, METALS[t - 1] if w in ["sword", "greatsword"] else WOODS[t - 1]])
	if g.offhand == "shield":
		ids.append("shield_" + METALS[t - 1])
	elif g.offhand == "tome":
		ids.append("tome_t%d" % t)
	ids += ["cape_t%d" % t, "ring_%s_t%d" % [g.ring, t], "ring_%s_t%d" % [g.ring, t], "amulet_wrath_t%d" % t]
	return ids


static func ammo_damage(data: Node, cls: String, t: int) -> float:
	var g: Dictionary = CLASS_GEAR[cls]
	if g.ammo == "arrow":
		return float(data.item("arrow_" + WOODS[t - 1]).ammo.damage)
	if g.ammo == "rune":
		return float(data.item("rune_t%d" % t).ammo.damage)
	return 0.0


## Allocazione "standard" del simulatore: base + 3/livello al primario, 1,5/livello alla VIT (+0,5 per i guerrieri).
static func attrs(data: Node, cls: String, level: int) -> Dictionary:
	var h: Dictionary = data.constants.combat.hero
	var base := float(h.attr_base)
	var a := {"str": base, "dex": base, "int": base, "vit": base}
	var prim: String = CLASS_GEAR[cls].primary
	a[prim] += level * (float(h.class_primary_per_level) + float(h.attr_points_per_level) - 1.0)
	a["vit"] += level * (float(h.vit_per_level_all) + 1.0) + (0.5 * level if cls.begins_with("warrior") else 0.0)
	return a


static func hero(data: Node, cls: String, level: int, t: int) -> Dictionary:
	var gear: Array = []
	for id in gear_ids(cls, t):
		var it: Dictionary = data.item(id)
		assert(not it.is_empty(), "oggetto della fixture mancante: " + id)
		gear.append(it.equipment)
	var g: Dictionary = CLASS_GEAR[cls]
	var rank_stats: Array = data.rules("era_rules").item_rank.applies_to_stats
	return Formulas.hero_stats(level, attrs(data, cls, level), g.primary, g.style, gear, ammo_damage(data, cls, t),
		1.0, 1.0, rank_stats)
