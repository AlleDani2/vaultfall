class_name FxThemes
extends RefCounted
## Particelle tematiche per mansione (completamento di un'azione) e per tipo di tecnica. Solo presentazione.
## Ogni voce: preset di FxBurst + toni (se diversi dal preset) + direzione. Mansione sconosciuta: polvere.

const JOBS := {
	"woodcutting": {"preset": "chip", "extra": "leaf", "cols": []},
	"mining": {"preset": "spark", "extra": "impact", "cols": [FxPalette.STONE, FxPalette.WHITE, FxPalette.GOLD_D]},
	"fishing": {"preset": "bubble", "extra": "", "cols": []},
	"foraging": {"preset": "leaf", "extra": "", "cols": []},
	"trapping": {"preset": "dust", "extra": "", "cols": []},
	"smithing": {"preset": "forge", "extra": "ember", "cols": []},
	"woodworking": {"preset": "chip", "extra": "", "cols": [Color("e6c898"), FxPalette.BROWN, FxPalette.CREAM]},
	"tailoring": {"preset": "glint", "extra": "", "cols": [Color("e8a0c8"), FxPalette.CREAM, FxPalette.VIOLET]},
	"cooking": {"preset": "steam", "extra": "ember", "cols": []},
	"alchemy": {"preset": "bubble", "extra": "mote", "cols": [FxPalette.VIOLET, FxPalette.GREEN, FxPalette.WHITE]},
	"jewelcrafting": {"preset": "glint", "extra": "", "cols": [FxPalette.WHITE, Color("c8f0ff"), FxPalette.RED_L]},
	"runecarving": {"preset": "mote", "extra": "", "cols": [FxPalette.BLUE, FxPalette.VIOLET, FxPalette.WHITE]},
	"keysmithing": {"preset": "glint", "extra": "forge", "cols": [FxPalette.GOLD, FxPalette.GOLD_D, FxPalette.WHITE]},
	"thievery": {"preset": "smoke", "extra": "", "cols": []},
	"farming": {"preset": "leaf", "extra": "dust", "cols": []},
	"hero": {"preset": "spark", "extra": "", "cols": []},
	"bounty": {"preset": "spark", "extra": "", "cols": []},
}


## Movimento dell'attrezzo per mansione (vedi FxToolAnim.MOTIONS). Sconosciuta: colpo secco.
const MOTION := {
	"woodcutting": "chop", "mining": "mine", "fishing": "rod", "foraging": "dip", "trapping": "sneak",
	"smithing": "hammer", "woodworking": "hammer", "tailoring": "stitch", "cooking": "stir", "alchemy": "stir",
	"jewelcrafting": "gem", "runecarving": "gem", "keysmithing": "hammer", "thievery": "sneak", "farming": "dip",
	"hero": "chop", "bounty": "chop",
}


static func motion(skill_id: String) -> String:
	return str(MOTION.get(skill_id, "chop"))


## Colpetto intermedio del ciclo: poche particelle piccole (nessun extra), si scartano per prime se il pool è pieno.
static func job_tap(host_burst: FxBurst, skill_id: String, pos: Vector2) -> void:
	var t: Dictionary = JOBS.get(skill_id, {"preset": "dust", "cols": []})
	host_burst.spawn(str(t.preset), pos, t.cols, 0.55, 0.5, Vector2(12.0, 10.0))


static func job_preset(skill_id: String) -> String:
	return str(JOBS.get(skill_id, {}).get("preset", "dust"))


## Particelle di completamento azione per la mansione. `scale` > 1 per il livello/la maestria.
static func job(host_burst: FxBurst, skill_id: String, pos: Vector2, scale: float = 1.0) -> void:
	var t: Dictionary = JOBS.get(skill_id, {"preset": "dust", "extra": "", "cols": []})
	host_burst.spawn(str(t.preset), pos, t.cols, scale, 1.4, Vector2(20.0, 16.0))
	if str(t.get("extra", "")) != "" and Fx.level() >= 2:
		host_burst.spawn(str(t.extra), pos, [], scale * 0.8, 0.9, Vector2(16.0, 12.0))
