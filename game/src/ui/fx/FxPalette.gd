class_name FxPalette
extends RefCounted
## Palette LIMITATA degli effetti (pixel art): pochi colori caldi/freddi, nessun colore di altri giochi.
## Le rarità usano SOLO i colori originali del progetto (crate_rules.rarities, via CrateUi): qui non se ne inventano.

const WHITE := Color("f2efe4")
const CREAM := Color("e6dfcf")
const GOLD := Color("ffd24a")
const GOLD_D := Color("c8a24a")
const AMBER := Color("ffb14a")
const ORANGE := Color("e8702a")
const RED := Color("d9544d")
const RED_L := Color("ff7b72")
const GREEN := Color("7fcf8a")
const GREEN_D := Color("4f9d5d")
const BLUE := Color("7fc8ff")
const BLUE_D := Color("5b8def")
const VIOLET := Color("b58cff")
const TEAL := Color("7fe0d0")
const BROWN := Color("a77c31")
const BROWN_D := Color("6f3f1a")
const STONE := Color("aab0bb")
const SMOKE := Color("8a8f9a")


## Colore della rarità (palette originale dei dati). Id sconosciuto: grigio-azzurro della rarità più bassa.
static func rarity(rarity_id: String) -> Color:
	return CrateUi.rarity_color(rarity_id)


## Posizione 0..1 della rarità nella scala dei dati (0 = la più comune, 1 = la più rara).
static func rarity_t(rarity_id: String) -> float:
	var list: Array = CrateUi.rules().get("rarities", [])
	if list.size() < 2:
		return 0.0
	for i in list.size():
		if str(list[i].get("id", "")) == rarity_id:
			return float(i) / float(list.size() - 1)
	return 0.0


static func lighten(c: Color, t: float = 0.35) -> Color:
	return c.lerp(Color.WHITE, clampf(t, 0.0, 1.0))


static func darken(c: Color, t: float = 0.35) -> Color:
	return c.lerp(Color.BLACK, clampf(t, 0.0, 1.0))


## Colore dell'aura di una tecnica per tipo di effetto (abilities.json effect.type).
static func ability(effect_type: String) -> Color:
	match effect_type:
		"damage": return AMBER
		"buff": return GOLD
		"debuff": return VIOLET
		"dot": return Color("8fd47a")
		"heal": return GREEN
		"shield": return BLUE
		"summon": return TEAL
	return BLUE
