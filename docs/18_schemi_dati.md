# 18 — Schemi dei dati (generato da `tools/make_schema_doc.py`)

Ogni file in `data/` è JSON UTF-8. Quasi tutti sono **array di oggetti con `id` univoco**. I testi visibili sono sempre oggetti `{"it": ..., "en": ...}` (tipo `loc{it,en}`). I percorsi delle immagini (`icon`, `portrait`, `banner`) sono già in formato `res://` del progetto Godot.

Colonna *Presenza*: in quanti oggetti del file compare il campo (campi opzionali < 100%).

Regole generali:

- **id**: `snake_case` ASCII, univoco nel proprio file; gli oggetti hanno id univoci in tutto `items/`.
- **Riferimenti**: per id (mai per indice). Il validatore `tools/validate_data.py` controlla tutti i riferimenti.
- **Modificatori**: `{"key": "famiglia[:ambito]", "value": numero, "mode": "add"|"more"}` (docs/14).
- **Quantità**: intero oppure `[min, max]` (estrazione uniforme inclusiva).
- **Probabilità**: `chance` in [0,1] (frazione), `weight` relativo, `*_pct` in percentuale.

## `abilities.json`

Array di **48** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"cleave"` |
| `class` | string | 100% | `"warrior"` |
| `name` | loc{it,en} | 100% | `{"it": "Fendente", "en": "Cleave"}` |
| `level_req` | int | 100% | `1` |
| `cooldown_s` | int | 100% | `12` |
| `cost` | int | 100% | `25` |
| `effect` | object | 100% | `{"type": "damage", "weapon_mult": 1.8, "element": null, "hits": 1}` |
| `desc` | loc{it,en} | 100% | `{"it": "Un colpo ampio: 180% danno arma. Dario lo chiama «il mio co…` |
| `icon` | string | 100% | `"res://assets/icons/abilities/cleave.png"` |

Sotto-oggetto `effect`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `effect.type` | string | 100% | `"damage"` |
| `effect.weapon_mult` | float | 52% | `1.8` |
| `effect.element` | null, string | 62% | `"holy"` |
| `effect.hits` | int | 52% | `1` |
| `effect.modifiers` | array | 31% | `[{"key": "combat_dmg_taken_pct", "value": -30}, {"key": "combat_dmg…` |
| `effect.duration_s` | int | 37% | `9` |
| `effect.weapon_mult_per_tick` | float | 6% | `0.8` |
| `effect.ticks` | int | 6% | `6` |
| `effect.stun_s` | float | 2% | `1.5` |
| `effect.pct_max_hp` | int | 6% | `30` |
| `effect.trigger` | string | 6% | `"hp_below_pct:30"` |
| `effect.heal_pct_of_damage` | int | 8% | `25` |
| `effect.crit_bonus` | float | 2% | `0.15` |
| `effect.armor_pen_pct` | int | 2% | `50` |
| `effect.execute_below_pct` | int | 2% | `20` |
| `effect.execute_mult` | float | 2% | `2.0` |
| `effect.dps_weapon_mult` | float | 4% | `0.5` |
| `effect.slow_pct` | int | 2% | `30` |
| `effect.slow_s` | int | 2% | `5` |
| `effect.dot_weapon_mult_per_tick` | float | 2% | `0.2` |
| `effect.dot_ticks` | int | 2% | `4` |

## `achievements.json`

Array di **118** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"ach_woodcutting_50"` |
| `steam_api_name` | string | 100% | `"ACH_WOODCUTTING_50"` |
| `category` | string | 100% | `"skills"` |
| `name` | loc{it,en} | 100% | `{"it": "Accetta della Domenica", "en": "Sunday Lumberjack"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Raggiungi il livello 50 in Taglialegna. Gli alberi hanno in…` |
| `condition` | object | 100% | `{"type": "skill_level", "skill": "woodcutting", "level": 50}` |
| `reward` | object | 100% | `{"stardust": 2}` |
| `hidden` | bool | 100% | `false` |
| `icon` | string | 100% | `"res://assets/icons/achievements/ach_woodcutting_50.png"` |
| `icon_locked` | string | 100% | `"res://assets/icons/achievements/ach_woodcutting_50_locked.png"` |
| `steam_phase` | int | 100% | `1` |

Sotto-oggetto `condition`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `condition.type` | string | 100% | `"skill_level"` |
| `condition.skill` | string | 29% | `"woodcutting"` |
| `condition.level` | int | 33% | `50` |
| `condition.qty` | int | 49% | `1` |
| `condition.monster` | string | 8% | `"hornet_queen"` |
| `condition.raid` | string | 2% | `"collectors_den"` |
| `condition.floor` | int | 3% | `25` |
| `condition.era` | int | 2% | `2` |
| `condition.rarity` | string | 5% | `"epic"` |
| `condition.annalist` | bool | 0% | `true` |
| `condition.float_below` | float | 0% | `0.01` |
| `condition.chapter` | int | 10% | `0` |
| `condition.quality` | string | 0% | `"masterwork"` |

Sotto-oggetto `reward`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `reward.stardust` | int | 100% | `2` |
| `reward.title` | string | 17% | `"title_master_woodcutting"` |

## `actions/alchemy.json`

Array di **62** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"alch_vigor_1"` |
| `skill` | string | 100% | `"alchemy"` |
| `name` | loc{it,en} | 100% | `{"it": "Pozione di Vigore I", "en": "Vigor Potion I"}` |
| `category` | string | 100% | `"potions"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `3.2` |
| `xp` | int | 100% | `7` |
| `mastery_xp` | float | 100% | `3.2` |
| `inputs` | array | 100% | `[{"item": "herb_sage", "qty": 1}, {"item": "mm_rough_fang", "qty": …` |
| `outputs` | array | 100% | `[{"item": "potion_vigor_1", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.001333}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.001333` |

## `actions/cooking.json`

Array di **31** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"cook_bleak"` |
| `skill` | string | 100% | `"cooking"` |
| `name` | loc{it,en} | 100% | `{"it": "Alborella alla Brace", "en": "Grilled Bleak"}` |
| `category` | string | 100% | `"fish"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `2.5` |
| `xp` | int | 100% | `6` |
| `mastery_xp` | float | 100% | `2.5` |
| `inputs` | array | 100% | `[{"item": "fish_raw_bleak", "qty": 1}]` |
| `outputs` | array | 100% | `[{"item": "food_bleak", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.001042}` |
| `burn` | object | 70% | `{"base": 0.3, "per_level": 0.01, "per_mastery": 0.005, "min": 0.0}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.001042` |

Sotto-oggetto `burn`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `burn.base` | float | 100% | `0.3` |
| `burn.per_level` | float | 100% | `0.01` |
| `burn.per_mastery` | float | 100% | `0.005` |
| `burn.min` | float | 100% | `0.0` |

## `actions/farming.json`

Array di **15** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"farm_potato"` |
| `skill` | string | 100% | `"farming"` |
| `kind` | string | 100% | `"crop"` |
| `name` | loc{it,en} | 100% | `{"it": "Patata", "en": "Potato"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `seed` | string | 100% | `"seed_potato"` |
| `seeds_per_plant` | int | 100% | `1` |
| `grow_time_min` | int | 100% | `10` |
| `xp_plant` | int | 100% | `133` |
| `xp_harvest` | int | 100% | `533` |
| `outputs` | array | 100% | `[{"item": "crop_potato", "qty": [5, 9]}]` |
| `harvest_bonus_per_10_levels` | int | 100% | `1` |
| `crate` | object | 100% | `{"id": "crate_merchant", "chance": 0.02}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_merchant"` |
| `crate.chance` | float | 100% | `0.02` |

## `actions/fishing.json`

Array di **11** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"fish_bleak"` |
| `skill` | string | 100% | `"fishing"` |
| `name` | loc{it,en} | 100% | `{"it": "Ruscello del Mulino", "en": "Millbrook Stream"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `4.0` |
| `time_variance` | float | 100% | `0.25` |
| `xp` | int | 100% | `9` |
| `mastery_xp` | float | 100% | `4.0` |
| `outputs` | array | 100% | `[{"item": "fish_raw_bleak", "qty": 1}]` |
| `secondary` | array | 100% | `[{"item": "sunken_treasure", "qty": 1, "chance": 0.004}]` |
| `crate` | object | 100% | `{"id": "crate_gatherer", "chance": 0.001667}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_gatherer"` |
| `crate.chance` | float | 100% | `0.001667` |

## `actions/foraging.json`

Array di **22** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"forage_fiber_flax"` |
| `skill` | string | 100% | `"foraging"` |
| `name` | loc{it,en} | 100% | `{"it": "Lino", "en": "Flax"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `2.6` |
| `xp` | int | 100% | `6` |
| `mastery_xp` | float | 100% | `2.6` |
| `outputs` | array | 100% | `[{"item": "fiber_flax", "qty": 1}]` |
| `secondary` | array | 100% | `[{"item": "seed_potato", "qty": 1, "chance": 0.02}]` |
| `crate` | object | 100% | `{"id": "crate_gatherer", "chance": 0.001083}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_gatherer"` |
| `crate.chance` | float | 100% | `0.001083` |

## `actions/jewelcrafting.json`

Array di **99** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"jc_cut_quartz"` |
| `skill` | string | 100% | `"jewelcrafting"` |
| `name` | loc{it,en} | 100% | `{"it": "Quarzo Tagliato", "en": "Cut Quartz"}` |
| `category` | string | 100% | `"cutting"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `2.0` |
| `xp` | int | 100% | `4` |
| `mastery_xp` | float | 100% | `2.0` |
| `inputs` | array | 100% | `[{"item": "gem_raw_quartz", "qty": 1}]` |
| `outputs` | array | 100% | `[{"item": "gem_quartz", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.000833}` |
| `single_craft` | bool | 88% | `true` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.000833` |

## `actions/keysmithing.json`

Array di **22** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"key_key_t1"` |
| `skill` | string | 100% | `"keysmithing"` |
| `name` | loc{it,en} | 100% | `{"it": "Chiave di Rame", "en": "Copper Key"}` |
| `category` | string | 100% | `"keys"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `6.0` |
| `xp` | int | 100% | `33` |
| `mastery_xp` | float | 100% | `6.0` |
| `inputs` | array | 100% | `[{"item": "bar_copper", "qty": 50}]` |
| `outputs` | array | 100% | `[{"item": "key_t1", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_rogue", "chance": 0.0025}` |
| `single_craft` | bool | 50% | `true` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_rogue"` |
| `crate.chance` | float | 100% | `0.0025` |

## `actions/mining.json`

Array di **13** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"mine_copper"` |
| `skill` | string | 100% | `"mining"` |
| `name` | loc{it,en} | 100% | `{"it": "Vena di Rame", "en": "Copper Vein"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `3.0` |
| `xp` | int | 100% | `7` |
| `mastery_xp` | float | 100% | `3.0` |
| `outputs` | array | 100% | `[{"item": "ore_copper", "qty": 1}]` |
| `secondary` | array | 100% | `[{"pick": [{"item": "gem_raw_quartz", "weight": 20}, {"item": "gem_…` |
| `crate` | object | 100% | `{"id": "crate_gatherer", "chance": 0.00125}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_gatherer"` |
| `crate.chance` | float | 100% | `0.00125` |

## `actions/runecarving.json`

Array di **62** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"rc_rune_t1"` |
| `skill` | string | 100% | `"runecarving"` |
| `name` | loc{it,en} | 100% | `{"it": "Runa di Pietra", "en": "Stone Rune"}` |
| `category` | string | 100% | `"runes"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `2.0` |
| `xp` | int | 100% | `4` |
| `mastery_xp` | float | 100% | `2.0` |
| `inputs` | array | 100% | `[{"item": "essence_stone", "qty": 1}, {"item": "herb_sage", "qty": 1}]` |
| `outputs` | array | 100% | `[{"item": "rune_t1", "qty": 25}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.000833}` |
| `single_craft` | bool | 17% | `true` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.000833` |

## `actions/smithing.json`

Array di **132** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"smelt_copper"` |
| `skill` | string | 100% | `"smithing"` |
| `name` | loc{it,en} | 100% | `{"it": "Lingotto di Rame", "en": "Copper Bar"}` |
| `category` | string | 100% | `"smelting"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `2.0` |
| `xp` | int | 100% | `4` |
| `mastery_xp` | float | 100% | `2.0` |
| `inputs` | array | 100% | `[{"item": "ore_copper", "qty": 1}]` |
| `outputs` | array | 100% | `[{"item": "bar_copper", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.000833}` |
| `single_craft` | bool | 91% | `true` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.000833` |

## `actions/tailoring.json`

Array di **154** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"tail_tan_rabbit"` |
| `skill` | string | 100% | `"tailoring"` |
| `name` | loc{it,en} | 100% | `{"it": "Cuoio di Coniglio", "en": "Rabbit Leather"}` |
| `category` | string | 100% | `"tanning"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `1.5` |
| `xp` | int | 100% | `3` |
| `mastery_xp` | float | 100% | `1.5` |
| `inputs` | array | 100% | `[{"item": "hide_rabbit", "qty": 1}]` |
| `outputs` | array | 100% | `[{"item": "leather_rabbit", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.000625}` |
| `single_craft` | bool | 78% | `true` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.000625` |

## `actions/thievery.json`

Array di **11** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"thief_farmer"` |
| `skill` | string | 100% | `"thievery"` |
| `name` | loc{it,en} | 100% | `{"it": "Contadino", "en": "Farmer"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `3.0` |
| `xp` | int | 100% | `10` |
| `mastery_xp` | float | 100% | `3.0` |
| `success` | object | 100% | `{"base": 0.7, "per_level_above": 0.01, "per_mastery": 0.003, "max":…` |
| `stun_s` | float | 100% | `3.0` |
| `gold` | array | 100% | `[1, 3]` |
| `drops` | array | 100% | `[{"item": "seed_potato", "chance": 0.1, "qty": [1, 3]}, {"item": "s…` |
| `crate` | object | 100% | `{"id": "crate_rogue", "chance": 0.0025}` |

Sotto-oggetto `success`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `success.base` | float | 100% | `0.7` |
| `success.per_level_above` | float | 100% | `0.01` |
| `success.per_mastery` | float | 100% | `0.003` |
| `success.max` | float | 100% | `0.95` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_rogue"` |
| `crate.chance` | float | 100% | `0.0025` |

## `actions/trapping.json`

Array di **11** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"trap_rabbit"` |
| `skill` | string | 100% | `"trapping"` |
| `name` | loc{it,en} | 100% | `{"it": "Coniglio", "en": "Rabbit"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `5.0` |
| `xp` | int | 100% | `11` |
| `mastery_xp` | float | 100% | `5.0` |
| `outputs` | array | 100% | `[{"item": "hide_rabbit", "qty": 1}, {"item": "meat_raw_rabbit", "qt…` |
| `secondary` | array | 100% | `[{"item": "feather", "qty": [1, 3], "chance": 0.4}]` |
| `crate` | object | 100% | `{"id": "crate_gatherer", "chance": 0.002083}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_gatherer"` |
| `crate.chance` | float | 100% | `0.002083` |

## `actions/woodcutting.json`

Array di **11** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"wc_pine"` |
| `skill` | string | 100% | `"woodcutting"` |
| `name` | loc{it,en} | 100% | `{"it": "Pino", "en": "Pine Tree"}` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `3.0` |
| `xp` | int | 100% | `7` |
| `mastery_xp` | float | 100% | `3.0` |
| `outputs` | array | 100% | `[{"item": "log_pine", "qty": 1}]` |
| `secondary` | array | 100% | `[{"item": "bird_nest", "qty": 1, "chance": 0.005}]` |
| `crate` | object | 100% | `{"id": "crate_gatherer", "chance": 0.00125}` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_gatherer"` |
| `crate.chance` | float | 100% | `0.00125` |

## `actions/woodworking.json`

Array di **88** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"ww_plank_pine"` |
| `skill` | string | 100% | `"woodworking"` |
| `name` | loc{it,en} | 100% | `{"it": "Asse di Pino", "en": "Pine Plank"}` |
| `category` | string | 100% | `"planks"` |
| `level_req` | int | 100% | `1` |
| `tier` | int | 100% | `1` |
| `time_s` | float | 100% | `1.5` |
| `xp` | int | 100% | `3` |
| `mastery_xp` | float | 100% | `1.5` |
| `inputs` | array | 100% | `[{"item": "log_pine", "qty": 1}]` |
| `outputs` | array | 100% | `[{"item": "plank_pine", "qty": 1}]` |
| `quality` | bool | 100% | `false` |
| `crate` | object | 100% | `{"id": "crate_artisan", "chance": 0.000625}` |
| `single_craft` | bool | 75% | `true` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_artisan"` |
| `crate.chance` | float | 100% | `0.000625` |

## `boss_mechanics.json`

Array di **7** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"enrage"` |
| `name` | loc{it,en} | 100% | `{"it": "Furia", "en": "Enrage"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Sotto il 30% di vita: +40% danno, +20% velocità. Quando si …` |
| `trigger` | object | 100% | `{"hp_below_pct": 30}` |
| `effect` | object | 100% | `{"dmg_pct": 40, "haste_pct": 20}` |
| `answer` | object | 71% | `{"kind": "guard", "hit_mult": 0.5, "buff_keys": ["combat_dmg_taken_…` |

Sotto-oggetto `trigger`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `trigger.hp_below_pct` | int | 28% | `30` |
| `trigger.every_s` | int | 57% | `15` |
| `trigger.once` | bool | 14% | `true` |
| `trigger.passive` | bool | 14% | `true` |

Sotto-oggetto `effect`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `effect.dmg_pct` | int | 14% | `40` |
| `effect.haste_pct` | int | 14% | `20` |
| `effect.hit_mult` | float | 14% | `2.5` |
| `effect.dot_pct_max_hp` | int | 14% | `3` |
| `effect.duration_s` | int | 28% | `6` |
| `effect.element` | string | 14% | `"poison"` |
| `effect.summon` | int | 14% | `2` |
| `effect.hp_pct_of_boss` | int | 14% | `5` |
| `effect.dmg_pct_of_boss` | int | 14% | `20` |
| `effect.dmg_taken_pct` | int | 14% | `-80` |
| `effect.stun_s` | int | 14% | `2` |
| `effect.lifesteal_pct` | int | 14% | `30` |

Sotto-oggetto `answer`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `answer.kind` | string | 100% | `"guard"` |
| `answer.hit_mult` | float | 20% | `0.5` |
| `answer.buff_keys` | array | 20% | `["combat_dmg_taken_pct", "combat_defense_pct", "combat_arm_pct", "c…` |
| `answer.ready_pct` | int | 40% | `30` |
| `answer.min_hits` | int | 20% | `3` |
| `answer.min_armor_pen_pct` | int | 20% | `20` |
| `answer.or_dot` | bool | 20% | `true` |
| `answer.keep_pct` | int | 20% | `50` |

## `bounty_board.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"bounty_board"` |
| `name` | loc{it,en} | 100% | `{"it": "Bacheca delle Taglie", "en": "Bounty Board"}` |
| `offers` | int | 100% | `3` |
| `reroll_cost_gold_formula` | string | 100% | `"500 * tier"` |
| `reroll_cost_gold_per_tier` | int | 100% | `500` |
| `free_rerolls_per_day` | int | 100% | `3` |
| `tiers` | array | 100% | `[{"id": "easy", "name": {"it": "Facile (Per Dario)", "en": "Easy (D…` |
| `xp_per_kill_formula` | string | 100% | `"monster.xp * 0.6"` |
| `completion_bonus` | object | 100% | `{"xp_mult_of_task": 0.5, "crate_bounty_chance": 0.25, "crate": "cra…` |
| `wanted_variant` | object | 100% | `{"chance_per_kill": 0.02, "hp_mult": 3.0, "dmg_mult": 1.5, "drops":…` |
| `target_selection` | string | 100% | `"mostri delle zone sbloccate con livello <= livello Eroe + 5"` |

Sotto-oggetto `completion_bonus`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `completion_bonus.xp_mult_of_task` | float | 100% | `0.5` |
| `completion_bonus.crate_bounty_chance` | float | 100% | `0.25` |
| `completion_bonus.crate` | string | 100% | `"crate_bounty"` |

Sotto-oggetto `wanted_variant`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `wanted_variant.chance_per_kill` | float | 100% | `0.02` |
| `wanted_variant.hp_mult` | float | 100% | `3.0` |
| `wanted_variant.dmg_mult` | float | 100% | `1.5` |
| `wanted_variant.drops` | array | 100% | `[{"item": "crate_bounty", "qty": 1}]` |
| `wanted_variant.marks` | int | 100% | `10` |

## `chapters.json`

Array di **12** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | int | 100% | `0` |
| `name` | loc{it,en} | 100% | `{"it": "Prologo — La Pioggia di Stelle (Nessuno Aveva Avvisato)", "…` |

## `classes.json`

Array di **12** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"warrior"` |
| `name` | loc{it,en} | 100% | `{"it": "Guerriero", "en": "Warrior"}` |
| `style` | string | 75% | `"melee"` |
| `primary_attr` | string | 100% | `"str"` |
| `resource` | string | 100% | `"fury"` |
| `desc` | loc{it,en} | 100% | `{"it": "Combatte in prima linea con armature pesanti; la Furia cres…` |
| `base` | bool | 25% | `true` |
| `growth_per_level` | object | 100% | `{"str": 1.0, "vit": 1.0}` |
| `auto_alloc` | object | 100% | `{"str": 2, "vit": 1}` |
| `specializations` | array | 25% | `["paladin", "berserker"]` |
| `portrait` | string | 100% | `"res://assets/portraits/classes/warrior.png"` |
| `parent` | string | 50% | `"warrior"` |
| `element` | null, string | 50% | `"holy"` |
| `unlock` | object | 75% | `{"hero_level": 30, "quest": "class_paladin"}` |
| `styles` | array | 25% | `["melee", "arcane"]` |
| `primary_attrs` | array | 25% | `["str", "int"]` |
| `hybrid` | bool | 25% | `true` |
| `ap_formula` | string | 25% | `"1.5 * attributo dello stile attivo (str = mischia, dex = distanza,…` |
| `passive` | object | 25% | `{"auto_stance": true, "stat_mult": 1.2}` |

Sotto-oggetto `growth_per_level`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `growth_per_level.str` | float | 41% | `1.0` |
| `growth_per_level.vit` | float | 100% | `1.0` |
| `growth_per_level.dex` | float | 41% | `1.0` |
| `growth_per_level.int` | float | 41% | `1.0` |

Sotto-oggetto `auto_alloc`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `auto_alloc.str` | int | 41% | `2` |
| `auto_alloc.vit` | int | 100% | `1` |
| `auto_alloc.dex` | int | 41% | `2` |
| `auto_alloc.int` | int | 41% | `2` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.hero_level` | int | 66% | `30` |
| `unlock.quest` | string | 100% | `"class_paladin"` |
| `unlock.hero_stars` | int | 33% | `1` |

Sotto-oggetto `passive`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `passive.auto_stance` | bool | 100% | `true` |
| `passive.stat_mult` | float | 100% | `1.2` |

## `collections.json`

Array di **16** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"collection_millbrook"` |
| `crate` | string | 100% | `"crate_millbrook"` |
| `name` | loc{it,en} | 100% | `{"it": "Collezione della Valle", "en": "Vale Collection"}` |
| `complete_bonus` | object | 100% | `{"requires": "all_skins", "modifiers": [{"key": "skill_xp_pct:gathe…` |
| `golden_bonus` | object | 100% | `{"requires": "all_skins_and_relics", "modifiers": [{"key": "skill_x…` |

Sotto-oggetto `complete_bonus`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `complete_bonus.requires` | string | 100% | `"all_skins"` |
| `complete_bonus.modifiers` | array | 100% | `[{"key": "skill_xp_pct:gathering", "value": 2, "mode": "add"}]` |

Sotto-oggetto `golden_bonus`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `golden_bonus.requires` | string | 100% | `"all_skins_and_relics"` |
| `golden_bonus.modifiers` | array | 100% | `[{"key": "skill_xp_pct:gathering", "value": 2, "mode": "add"}]` |
| `golden_bonus.title` | string | 100% | `"title_collector_millbrook"` |

## `constants.json`

Oggetto con chiavi: `game_codename`, `data_version`, `level_cap`, `xp`, `tier_levels`, `xph`, `gph`, `mastery`, `automation`, `queue`, `farming`, `consumables`, `stars`, `prestige`, `eras`, `estate`, `combat`, `quality`, `quality_formula`, `quality_chances`, `crates`, `market`, `offline`, `time_push`, `cozy`, `new_game_gift`, `bank`, `estate_tuning`, `expedition_tuning`, `mercenary_tuning`, `apprentice_tuning`, `modifier_stacking`

## `constellations.json`

Array di **35** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"c_vi_xp"` |
| `constellation` | string | 100% | `"wayfarer"` |
| `constellation_name` | loc{it,en} | 100% | `{"it": "Il Viandante Distratto", "en": "The Absent-Minded Wayfarer"}` |
| `index` | int | 100% | `0` |
| `name` | loc{it,en} | 100% | `{"it": "Passo Che Sa Dove Va", "en": "Stride With a Destination"}` |
| `modifier_per_level` | object | 100% | `{"key": "skill_xp_pct:all", "value": 2, "mode": "more"}` |
| `max_level` | int, null | 100% | `14` |
| `cost_formula` | string | 100% | `"ceil(5 * 1.35^livello)"` |
| `cost_base` | int | 100% | `5` |
| `cost_growth` | float | 100% | `1.35` |
| `requires` | array, null | 100% | `["c_vi_xp", 1]` |

Sotto-oggetto `modifier_per_level`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `modifier_per_level.key` | string | 100% | `"skill_xp_pct:all"` |
| `modifier_per_level.value` | float, int | 100% | `2` |
| `modifier_per_level.mode` | string | 100% | `"more"` |

## `contract_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"contract_rules"` |
| `daily_slots` | int | 100% | `3` |
| `weekly_slots` | int | 100% | `5` |
| `free_rerolls_daily` | int | 100% | `1` |
| `rollover_days` | int | 100% | `7` |
| `reset_time` | string | 100% | `"00:00 ora locale"` |
| `unlock_token` | string | 100% | `"feature:market"` |
| `day_s` | int | 100% | `86400` |
| `week_days` | int | 100% | `7` |
| `weekly_keep_days` | int | 100% | `14` |
| `key_tier_div` | int | 100% | `2` |
| `key_tier_max` | int | 100% | `5` |
| `rewards` | object | 100% | `{"daily": {"commission_token": 3, "gold_formula": "gph(tier) * 0.15…` |
| `token_shop` | array | 100% | `[{"item": "key_t1", "tokens": 6}, {"item": "key_t2", "tokens": 12},…` |
| `no_fomo_rule` | string | 100% | `"le commissioni non completate restano fino a 7 giorni; nessuna ric…` |

## `contract_templates.json`

Array di **11** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"c_gather"` |
| `period` | string | 100% | `"daily"` |
| `text` | loc{it,en} | 100% | `{"it": "Raccogli {qty} {item}. «Oggi non ho sbatti», dice Livia, «f…` |
| `objective` | string | 100% | `"gather"` |
| `pick` | string | 27% | `"materiale grezzo del tier migliore sbloccato -1"` |
| `qty_formula` | string | 100% | `"round(1200 / tempo_azione)"` |
| `pick_rule` | string | 27% | `"gather_best_minus_1"` |
| `qty_secs` | int | 18% | `1200` |
| `requires` | array | 100% | `["feature:combat"]` |
| `qty` | int | 72% | `60` |
| `gold_gph_mult` | float | 9% | `0.5` |
| `skill` | string | 9% | `"thievery"` |

## `coop_net_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"coop_net_rules"` |
| `protocol_version` | int | 100% | `1` |
| `default_port` | int | 100% | `24680` |
| `max_members` | int | 100% | `8` |
| `presence` | object | 100% | `{"interval_s": 3.0, "stale_s": 10.0, "timeout_s": 20.0, "crate_show…` |
| `net` | object | 100% | `{"max_packet_bytes": 1400, "max_snapshot_bytes": 65536, "rate_per_s…` |
| `name` | object | 100% | `{"min_len": 1, "max_len": 16}` |
| `log_max` | int | 100% | `80` |
| `deposit` | object | 100% | `{"items": ["log_pine", "log_birch", "log_chestnut", "log_cedar", "l…` |
| `member_scale_milli` | array | 100% | `[0, 1000, 1682, 2280, 2828, 3344, 3834, 4304, 4757]` |
| `bonus_cap_pct` | int | 100% | `10` |
| `projects` | array | 100% | `[{"id": "banner_scholars", "cap_pct": 4, "mods": [{"key": "skill_xp…` |
| `vote` | object | 100% | `{"proposal_timeout_s": 86400}` |
| `boss` | object | 100% | `{"week_s": 604800, "attempt_s": 120.0, "points_per_kill": 1000, "hp…` |

Sotto-oggetto `presence`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `presence.interval_s` | float | 100% | `3.0` |
| `presence.stale_s` | float | 100% | `10.0` |
| `presence.timeout_s` | float | 100% | `20.0` |
| `presence.crate_show_s` | float | 100% | `5.0` |
| `presence.max_friends_shown` | int | 100% | `7` |

Sotto-oggetto `net`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `net.max_packet_bytes` | int | 100% | `1400` |
| `net.max_snapshot_bytes` | int | 100% | `65536` |
| `net.rate_per_s` | float | 100% | `8.0` |
| `net.rate_burst` | int | 100% | `24` |
| `net.strikes_kick` | int | 100% | `40` |
| `net.ping_interval_s` | float | 100% | `2.0` |
| `net.hash_interval_s` | float | 100% | `5.0` |
| `net.resend_s` | float | 100% | `3.0` |
| `net.reconnect_min_s` | float | 100% | `2.0` |
| `net.reconnect_max_s` | float | 100% | `30.0` |
| `net.hello_timeout_s` | float | 100% | `10.0` |
| `net.save_debounce_s` | float | 100% | `0.0` |
| `net.copy_save_debounce_s` | float | 100% | `2.0` |
| `net.max_outbox` | int | 100% | `64` |
| `net.max_string` | int | 100% | `64` |
| `net.max_code_len` | int | 100% | `900` |

Sotto-oggetto `name`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `name.min_len` | int | 100% | `1` |
| `name.max_len` | int | 100% | `16` |

Sotto-oggetto `deposit`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `deposit.items` | array | 100% | `["log_pine", "log_birch", "log_chestnut", "log_cedar", "log_ebony",…` |
| `deposit.gold_points_per_coin` | int | 100% | `1` |
| `deposit.daily_cap_mult_milli` | int | 100% | `2000` |
| `deposit.drawer_days` | int | 100% | `7` |
| `deposit.max_qty_per_cmd` | int | 100% | `1000000` |

Sotto-oggetto `vote`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `vote.proposal_timeout_s` | int | 100% | `86400` |

Sotto-oggetto `boss`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `boss.week_s` | int | 100% | `604800` |
| `boss.attempt_s` | float | 100% | `120.0` |
| `boss.points_per_kill` | int | 100% | `1000` |
| `boss.hp_points_base` | int | 100% | `6000` |
| `boss.member_week_cap_mult_milli` | int | 100% | `1500` |
| `boss.attempts_per_day` | int | 100% | `3` |
| `boss.drawer_days` | int | 100% | `7` |
| `boss.monster_type` | string | 100% | `"boss"` |
| `boss.max_points_per_attempt` | int | 100% | `4000` |
| `boss.boss_min_hit_ratio` | float | 100% | `0.3` |
| `boss.reward_fund_points_base` | int | 100% | `5000` |
| `boss.bosses` | array | 100% | `[{"id": "wb_tax_golem", "name": {"it": "Il Golem delle Tasse", "en"…` |

## `coop_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"coop_rules"` |
| `format` | object | 100% | `{"version": 1, "protocol_version": 1, "prefix": "VF", "kind_hero": …` |
| `code` | object | 100% | `{"max_chars": 6000, "max_json_bytes": 12000, "name_max": 24, "max_a…` |
| `companions` | object | 100% | `{"max": 3, "valid_days": 30, "future_slack_s": 172800}` |
| `roles` | object | 100% | `{"warrior": "defender", "paladin": "healer", "berserker": "striker"…` |
| `sim` | object | 100% | `{"window_s": 600.0, "rift_window_s": 120.0, "min_score": 1e-09}` |
| `world_boss` | object | 100% | `{"weight": 0.5, "cap_mult": 1.0}` |
| `limits` | object | 100% | `{"headroom": 3.0, "min_interval_ratio": 0.35, "dmg_taken_min": 0.1,…` |
| `weekly` | object | 100% | `{"affix_count": [3, 5], "affix_from_floor": [3, 40], "mult_per_floo…` |
| `unlock` | object | 100% | `{"token": "feature:coop", "poll_s": 1.0}` |
| `title` | string | 100% | `"title_companion_in_arms"` |

Sotto-oggetto `format`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `format.version` | int | 100% | `1` |
| `format.protocol_version` | int | 100% | `1` |
| `format.prefix` | string | 100% | `"VF"` |
| `format.kind_hero` | string | 100% | `"H"` |
| `format.kind_result` | string | 100% | `"R"` |

Sotto-oggetto `code`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `code.max_chars` | int | 100% | `6000` |
| `code.max_json_bytes` | int | 100% | `12000` |
| `code.name_max` | int | 100% | `24` |
| `code.max_abilities` | int | 100% | `4` |
| `code.default_name` | loc{it,en} | 100% | `{"it": "Eroe", "en": "Hero"}` |
| `code.max_stances` | int | 100% | `3` |

Sotto-oggetto `companions`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `companions.max` | int | 100% | `3` |
| `companions.valid_days` | int | 100% | `30` |
| `companions.future_slack_s` | int | 100% | `172800` |

Sotto-oggetto `roles`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `roles.warrior` | string | 100% | `"defender"` |
| `roles.paladin` | string | 100% | `"healer"` |
| `roles.berserker` | string | 100% | `"striker"` |
| `roles.ranger` | string | 100% | `"striker"` |
| `roles.sharpshooter` | string | 100% | `"striker"` |
| `roles.beastmaster` | string | 100% | `"defender"` |
| `roles.arcanist` | string | 100% | `"striker"` |
| `roles.pyromancer` | string | 100% | `"striker"` |
| `roles.necromancer` | string | 100% | `"healer"` |
| `roles.spellblade` | string | 100% | `"striker"` |
| `roles.shadowstalker` | string | 100% | `"striker"` |
| `roles.stormweaver` | string | 100% | `"healer"` |

Sotto-oggetto `sim`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `sim.window_s` | float | 100% | `600.0` |
| `sim.rift_window_s` | float | 100% | `120.0` |
| `sim.min_score` | float | 100% | `1e-09` |

Sotto-oggetto `world_boss`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `world_boss.weight` | float | 100% | `0.5` |
| `world_boss.cap_mult` | float | 100% | `1.0` |

Sotto-oggetto `limits`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `limits.headroom` | float | 100% | `3.0` |
| `limits.min_interval_ratio` | float | 100% | `0.35` |
| `limits.dmg_taken_min` | float | 100% | `0.1` |
| `limits.dmg_taken_max` | float | 100% | `3.0` |
| `limits.regen_pct_max` | float | 100% | `25.0` |
| `limits.tot_abs_max` | float | 100% | `1000.0` |
| `limits.elem_more_max` | float | 100% | `5.0` |
| `limits.res_max_cap` | float | 100% | `1000.0` |
| `limits.pct_stats_max` | float | 100% | `100.0` |

Sotto-oggetto `weekly`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `weekly.affix_count` | array | 100% | `[3, 5]` |
| `weekly.affix_from_floor` | array | 100% | `[3, 40]` |
| `weekly.mult_per_floor_jitter` | float | 100% | `0.012` |
| `weekly.guardian_extra` | array | 100% | `[0, 2]` |
| `weekly.guardian_pool` | array | 100% | `["shield_phase", "poison_cloud", "summon_adds", "stun", "lifedrain"]` |
| `weekly.name_pool` | array | 100% | `[{"it": "Settimana dei Moduli Smarriti", "en": "Week of the Lost Fo…` |
| `weekly.max_floors` | int | 100% | `400` |
| `weekly.old_result_days` | int | 100% | `400` |
| `weekly.history_weeks` | int | 100% | `12` |
| `weekly.max_entries_per_week` | int | 100% | `64` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.token` | string | 100% | `"feature:coop"` |
| `unlock.poll_s` | float | 100% | `1.0` |

## `crate_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"crate_rules"` |
| `rarities` | array | 100% | `[{"id": "rare", "weight_pct": 79.2, "color": "#8DA2B8", "symbol": "…` |
| `conditions` | array | 100% | `[{"id": "pristine", "float_min": 0.0, "float_max": 0.1, "weight_pct…` |
| `float_algorithm` | string | 100% | `"1) condizioni possibili = quelle la cui fascia interseca [float_mi…` |
| `annalist` | object | 100% | `{"chance": 0.1, "value_mult": 2.2, "milestones": [100, 1000, 10000,…` |
| `pity` | object | 100% | `{"soft_start": 180, "soft_step": 0.0003, "hard": 300, "scope": "un …` |
| `reel` | object | 100% | `{"length_items": 60, "winner_index": 52, "duration_s": 5.5, "easing…` |
| `relic_phases` | array | 100% | `[{"id": "phase_1", "name": {"it": "Fase Alba", "en": "Dawn Phase"},…` |
| `dismantle_shards` | object | 100% | `{"rare": 1, "epic": 5, "legendary": 25, "mythic": 125, "relic": 500}` |
| `tradeup` | object | 100% | `{"inputs": 10, "same_rarity": true, "same_variant": true, "output_r…` |
| `golden_contract` | object | 100% | `{"inputs": 5, "input_rarity": "mythic", "output": "relic_pool delle…` |
| `refinery` | object | 100% | `{"name": {"it": "Banco di Affinatura", "en": "Refinery Bench"}, "un…` |
| `collectors_challenge` | object | 100% | `{"name": {"it": "Sfida dei Collezionisti", "en": "Collectors' Chall…` |
| `market` | object | 100% | `{"sell_tax": 0.1, "price_model": "random walk con ritorno alla medi…` |
| `vault_bank` | array | 100% | `[{"item": "key_t1", "shards": 30}, {"item": "key_t2", "shards": 60}…` |
| `era_crate_template` | object | 100% | `{"id_pattern": "crate_era_{n}", "name_pattern": {"it": "Cassa dell'…` |

Sotto-oggetto `annalist`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `annalist.chance` | float | 100% | `0.1` |
| `annalist.value_mult` | float | 100% | `2.2` |
| `annalist.milestones` | array | 100% | `[100, 1000, 10000, 100000, 1000000]` |
| `annalist.bonus_per_milestone_abs` | float | 100% | `0.2` |
| `annalist.name` | loc{it,en} | 100% | `{"it": "Annalista", "en": "Annalist"}` |
| `annalist.desc` | loc{it,en} | 100% | `{"it": "Conta azioni o uccisioni fatte con la finitura equipaggiata…` |

Sotto-oggetto `pity`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `pity.soft_start` | int | 100% | `180` |
| `pity.soft_step` | float | 100% | `0.0003` |
| `pity.hard` | int | 100% | `300` |
| `pity.scope` | string | 100% | `"un contatore per ogni valore di crate.pity_family (null = nessuna …` |
| `pity.visible` | bool | 100% | `true` |
| `pity.nominal_relic_pct` | float | 100% | `0.3` |
| `pity.effective_relic_pct` | float | 100% | `0.571` |
| `pity.mean_openings_per_relic` | float | 100% | `175.0` |
| `pity.effective_rarity_pct` | object | 100% | `{"rare": 78.984, "epic": 15.757, "legendary": 3.79, "mythic": 0.898…` |
| `pity.display` | string | 100% | `"mostrare sempre nominale ed effettiva: 'Reliquia ★ 0,30% (con la p…` |

Sotto-oggetto `reel`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `reel.length_items` | int | 100% | `60` |
| `reel.winner_index` | int | 100% | `52` |
| `reel.duration_s` | float | 100% | `5.5` |
| `reel.easing` | string | 100% | `"cubic_out"` |
| `reel.filler` | string | 100% | `"real_odds"` |
| `reel.skippable` | bool | 100% | `true` |
| `reel.multi_open` | array | 100% | `[1, 5, 10]` |
| `reel.fake_near_miss` | bool | 100% | `false` |

Sotto-oggetto `dismantle_shards`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `dismantle_shards.rare` | int | 100% | `1` |
| `dismantle_shards.epic` | int | 100% | `5` |
| `dismantle_shards.legendary` | int | 100% | `25` |
| `dismantle_shards.mythic` | int | 100% | `125` |
| `dismantle_shards.relic` | int | 100% | `500` |

Sotto-oggetto `tradeup`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `tradeup.inputs` | int | 100% | `10` |
| `tradeup.same_rarity` | bool | 100% | `true` |
| `tradeup.same_variant` | bool | 100% | `true` |
| `tradeup.output_rarity` | string | 100% | `"next"` |
| `tradeup.rarities_in` | array | 100% | `["rare", "epic", "legendary"]` |
| `tradeup.unlock` | object | 100% | `{"token": "feature:tradeup"}` |
| `tradeup.collection_weighting` | string | 100% | `"proporzionale al numero di input per collezione"` |
| `tradeup.float_formula` | string | 100% | `"out = out_min + (out_max - out_min) * media(norm_i), norm_i = (f_i…` |

Sotto-oggetto `golden_contract`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `golden_contract.inputs` | int | 100% | `5` |
| `golden_contract.input_rarity` | string | 100% | `"mythic"` |
| `golden_contract.output` | string | 100% | `"relic_pool delle collezioni in ingresso"` |
| `golden_contract.unlock` | object | 100% | `{"quest": "main_c6_q5", "token": "feature:golden_contract"}` |

Sotto-oggetto `refinery`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `refinery.name` | loc{it,en} | 100% | `{"it": "Banco di Affinatura", "en": "Refinery Bench"}` |
| `refinery.unlock` | object | 100% | `{"quest": "main_c6_q5", "token": "feature:refinery"}` |
| `refinery.note` | string | 100% | `"NESSUNA posta in gioco: si spendono Schegge e l'oggetto resta semp…` |
| `refinery.polish` | object | 100% | `{"name": {"it": "Lucidatura", "en": "Polish"}, "float_step": 0.1, "…` |
| `refinery.engrave_annalist` | object | 100% | `{"name": {"it": "Incisione Annalista", "en": "Annalist Engraving"},…` |
| `refinery.rename` | object | 100% | `{"name": {"it": "Targhetta", "en": "Name Tag"}, "cost_gold": 10000,…` |

Sotto-oggetto `collectors_challenge`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `collectors_challenge.name` | loc{it,en} | 100% | `{"it": "Sfida dei Collezionisti", "en": "Collectors' Challenge"}` |
| `collectors_challenge.unlock` | object | 100% | `{"quest": "main_c7_q5", "token": "feature:collectors_challenge"}` |
| `collectors_challenge.week_days` | int | 100% | `7` |
| `collectors_challenge.points` | object | 100% | `{"rare": 1, "epic": 5, "legendary": 25, "mythic": 125, "relic": 250}` |
| `collectors_challenge.rival_tier_source` | string | 100% | `"tier più alto di chiave tra le casse aperte (minimo 1)"` |
| `collectors_challenge.note` | string | 100% | `"Classifica settimanale contro rivali PNG: nessuna scommessa, nessu…` |
| `collectors_challenge.score` | string | 100% | `"somma dei punti rarità degli oggetti trovati nella settimana (rare…` |
| `collectors_challenge.rivals` | array | 100% | `[{"id": "rival_bruno", "name": {"it": "Bruno il Fortunato", "en": "…` |
| `collectors_challenge.rewards_by_place` | object | 100% | `{"1": [{"item": "vault_shard", "qty": 200}, {"item": "key_t3", "qty…` |

Sotto-oggetto `market`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `market.sell_tax` | float | 100% | `0.1` |
| `market.price_model` | string | 100% | `"random walk con ritorno alla media (Ornstein-Uhlenbeck)"` |
| `market.theta` | float | 100% | `0.15` |
| `market.sigma_daily` | float | 100% | `0.06` |
| `market.retired_crate_drift_pct_per_week` | float | 100% | `1.5` |
| `market.retired_week_days` | int | 100% | `7` |

Sotto-oggetto `era_crate_template`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `era_crate_template.id_pattern` | string | 100% | `"crate_era_{n}"` |
| `era_crate_template.name_pattern` | loc{it,en} | 100% | `{"it": "Cassa dell'Era {roman}", "en": "Era {roman} Crate"}` |
| `era_crate_template.key` | null | 100% | `null` |
| `era_crate_template.key_note` | string | 100% | `"docs/13 diceva Chiave Stellare: senza chiave (E47-1)"` |
| `era_crate_template.bonus_mult_formula` | string | 100% | `"1 + 0.25 * (era - 1)"` |
| `era_crate_template.bonus_applies_to` | string | 100% | `"Schegge della fusione dei pezzi usciti dalla cassa"` |
| `era_crate_template.names_source` | string | 100% | `"rift (riusa nomi con suffisso Era)"` |
| `era_crate_template.min_era` | int | 100% | `2` |
| `era_crate_template.max_era` | int | 100% | `12` |
| `era_crate_template.per_warden_kill` | int | 100% | `1` |
| `era_crate_template.pity_family` | string | 100% | `"crate_era"` |
| `era_crate_template.slots` | string | 100% | `"rift"` |

## `currency_shops.json`

Array di **3** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"bounty_shop"` |
| `name` | loc{it,en} | 100% | `{"it": "Banco delle Taglie (Pagamento in Marchi)", "en": "Bounty Co…` |
| `currency` | string | 100% | `"bounty_mark"` |
| `items` | array | 100% | `[{"item": "crate_bounty", "cost": 30}, {"item": "key_t3", "cost": 4…` |

## `drop_tables.json`

Array di **77** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"drops_mud_slime"` |
| `rolls` | int | 100% | `1` |
| `always` | array | 100% | `null` |
| `entries` | array | 100% | `[{"item": "mm_rough_fang", "chance": 0.3, "qty": [1, 2]}, {"item": …` |
| `crate` | null, object | 100% | `{"id": "crate_millbrook", "chance": 0.006667}` |
| `rare_table_chance` | float | 100% | `0.001953` |
| `gold` | null | 100% | `null` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.id` | string | 100% | `"crate_millbrook"` |
| `crate.chance` | float | 100% | `0.006667` |

## `dungeons.json`

Array di **10** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"cursed_granary"` |
| `order` | int | 100% | `1` |
| `name` | loc{it,en} | 100% | `{"it": "Granaio Maledetto", "en": "Cursed Granary"}` |
| `desc` | loc{it,en} | 100% | `{"it": "11 ondate e un boss finale. Dentro non puoi cambiare equipa…` |
| `zone` | string | 100% | `"millbrook"` |
| `boss` | string | 100% | `"straw_reaper"` |
| `waves` | array | 100% | `[{"monster": "mud_slime", "level_bonus": 2}, {"monster": "thornback…` |
| `rules` | object | 100% | `{"can_change_equipment": false, "can_eat": true, "death": "fail_kee…` |
| `completion_reward` | object | 100% | `{"gold": 725, "crates": [{"id": "crate_millbrook", "qty": 1}], "ite…` |
| `unlock` | object | 100% | `{"quest": "main_c1_q6", "hero_level": 8}` |
| `mastery_milestones` | array | 100% | `[{"completions": 10, "modifiers": [{"key": "dungeon_speed_pct:curse…` |
| `banner` | string | 100% | `"res://assets/banners/dungeons/cursed_granary.png"` |

Sotto-oggetto `rules`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `rules.can_change_equipment` | bool | 100% | `false` |
| `rules.can_eat` | bool | 100% | `true` |
| `rules.death` | string | 100% | `"fail_keep_loot_until_wave"` |

Sotto-oggetto `completion_reward`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `completion_reward.gold` | int | 100% | `725` |
| `completion_reward.crates` | array | 100% | `[{"id": "crate_millbrook", "qty": 1}]` |
| `completion_reward.items` | array | 100% | `[{"item": "mm_hornet_stinger", "qty": [2, 4]}]` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.quest` | string | 100% | `"main_c1_q6"` |
| `unlock.hero_level` | int | 100% | `8` |

## `era_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"era_rules"` |
| `monster_stat_mult` | float | 100% | `1.35` |
| `reward_add_per_era` | float | 100% | `0.3` |
| `unlock_next` | string | 100% | `"sconfiggere il Custode del Caveau (Cuore del Caveau) nell'Era corr…` |
| `selectable` | bool | 100% | `true` |
| `infinite` | bool | 100% | `true` |
| `era_essence` | object | 100% | `{"item": "era_essence", "drop": {"elite": 0.25, "boss": 1.0, "dunge…` |
| `monster_stats_scaled` | array | 100% | `["hp", "max_hit", "accuracy", "evasion", "armor", "ward"]` |
| `item_rank` | object | 100% | `{"stat_mult_per_rank": 1.04, "cap_per_era": 12, "cap_formula": "12 …` |
| `stardust_per_warden_kill` | string | 100% | `"5 * era"` |
| `stardust_repeat_pct` | int | 100% | `0` |
| `names` | array | 100% | `[{"it": "Era I — La Quiete Sospetta", "en": "Era I — The Suspicious…` |

Sotto-oggetto `era_essence`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `era_essence.item` | string | 100% | `"era_essence"` |
| `era_essence.drop` | object | 100% | `{"elite": 0.25, "boss": 1.0, "dungeon_boss": 3.0, "raid_boss": 10.0}` |
| `era_essence.qty_formula` | string | 100% | `"era"` |

Sotto-oggetto `item_rank`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `item_rank.stat_mult_per_rank` | float | 100% | `1.04` |
| `item_rank.cap_per_era` | int | 100% | `12` |
| `item_rank.cap_formula` | string | 100% | `"12 * era_massima_sbloccata"` |
| `item_rank.applies_to_stats` | array | 100% | `["damage", "armor", "ward", "hp", "accuracy", "evasion"]` |
| `item_rank.not_applied_to` | string | 100% | `"attributi (str/dex/int/vit), ap, crit_chance, modificatori"` |
| `item_rank.cost_formula` | object | 100% | `{"era_essence": "ceil(2 + 0.5 * rango)", "gold": "250 * tier * (1 +…` |

## `estate_buildings.json`

Array di **11** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"cottage"` |
| `order` | int | 100% | `0` |
| `name` | loc{it,en} | 100% | `{"it": "Casolare", "en": "Cottage"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Ospita i coloni: +3 posti per livello. Il Generale Baffo lo…` |
| `type` | string | 100% | `"housing"` |
| `unlock` | object | 100% | `{"quest": "main_c2_q2"}` |
| `max_level` | null | 100% | `null` |
| `uses_settlers` | bool | 100% | `false` |
| `cost` | object | 100% | `{"gold_base": 30, "gold_growth": 1.11, "gold_formula": "round_nice(…` |
| `icon` | string | 100% | `"res://assets/icons/estate/cottage.png"` |
| `effect` | object | 54% | `{"settler_cap_formula": "5 + 3 * L"}` |
| `production` | object | 45% | `{"output_subcategories": ["log"], "units_per_hour_formula": "30 * L…` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.quest` | string | 100% | `"main_c2_q2"` |

Sotto-oggetto `cost`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `cost.gold_base` | float, int | 100% | `30` |
| `cost.gold_growth` | float | 100% | `1.11` |
| `cost.gold_formula` | string | 100% | `"round_nice(gold_base * crescita^L * 1.45^(banda-1)), banda = min(1…` |
| `cost.materials_formula` | string | 100% | `"banda b = min(11, 1 + L//10): assi(b) x ceil(2 + 0.5L), lingotti(b…` |

Sotto-oggetto `effect`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `effect.settler_cap_formula` | string | 16% | `"5 + 3 * L"` |
| `effect.sell_value_pct` | int | 16% | `80` |
| `effect.throughput_units_per_hour_formula` | string | 16% | `"200 * L * 2^(traguardi)"` |
| `effect.capacity_formula` | string | 16% | `"500 * L^1.2 (unità totali)"` |
| `effect.interval_h_formula` | string | 16% | `"8 / (1 + 0.05 * L)"` |
| `effect.crate_pool` | string | 16% | `"casse delle zone sbloccate (pesi uguali)"` |
| `effect.key_chance_per_crate` | float | 16% | `0.05` |
| `effect.slots_by_level` | object | 16% | `{"1": 1, "15": 2, "40": 3}` |
| `effect.extra_slots_from` | string | 16% | `"Costellazioni (max 5 totali)"` |
| `effect.efficiency_formula` | string | 16% | `"min(0.35, 0.15 + 0.01 * L)  (numeri: constants.apprentice_tuning)"` |
| `effect.rules` | string | 16% | `"un apprendista svolge un'azione di raccolta o produzione (non comb…` |
| `effect.roster_formula` | string | 16% | `"4 + L // 5 (max 16)"` |
| `effect.concurrent_expeditions_formula` | string | 16% | `"1 + L // 15 (max 4)"` |
| `effect.board_missions_formula` | string | 16% | `"3 + L // 10 (max 6)"` |
| `effect.recruit_rarity_bonus_per_level_pct` | float | 16% | `0.5` |

Sotto-oggetto `production`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `production.output_subcategories` | array | 100% | `["log"]` |
| `production.units_per_hour_formula` | string | 100% | `"30 * L * 2^(traguardi) * (1 + soci*0.02) * (1 + estate_prod_pct/10…` |
| `production.tier_limit` | string | 100% | `"min(tier sbloccato nella mansione collegata, grado edificio)"` |
| `production.grade_upgrades` | array | 100% | `[{"grade": 1, "requires_level": 0, "requires_skill_tier": 1}, {"gra…` |

## `estate_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"estate_rules"` |
| `milestones` | array | 100% | `[10, 25, 50, 100, 150, 200, 300, 400, 500, 750, 1000]` |
| `milestone_mult` | int | 100% | `2` |
| `settlers` | object | 100% | `{"arrival_min": 2, "upkeep": "1 razione di cibo/ora per colono dall…` |
| `collection` | object | 100% | `{"manual": true, "auto_collect_unlock": {"constellation": "c_custod…` |
| `prestige` | object | 100% | `{"name": {"it": "Rifondazione", "en": "Refounding"}, "partner_name"…` |

Sotto-oggetto `settlers`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `settlers.arrival_min` | int | 100% | `2` |
| `settlers.upkeep` | string | 100% | `"1 razione di cibo/ora per colono dalla Dispensa (vuota: si riforni…` |
| `settlers.starving_mult` | float | 100% | `0.75` |
| `settlers.rule` | string | 100% | `"ogni livello di un edificio (tranne Casolare, Taverna e Accademia)…` |

Sotto-oggetto `collection`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `collection.manual` | bool | 100% | `true` |
| `collection.auto_collect_unlock` | object | 100% | `{"constellation": "c_custode_autocollect"}` |

Sotto-oggetto `prestige`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `prestige.name` | loc{it,en} | 100% | `{"it": "Rifondazione", "en": "Refounding"}` |
| `prestige.partner_name` | loc{it,en} | 100% | `{"it": "Socio", "en": "Partner"}` |
| `prestige.prosperity_points` | string | 100% | `"unità prodotte a vita dalla Tenuta (indipendenti dal tier)"` |
| `prestige.requires_lifetime_units` | int | 100% | `30000` |
| `prestige.partners_formula` | string | 100% | `"floor(15.0 * sqrt(punti_prosperità / 10000)) - soci_già_ottenuti"` |
| `prestige.bonus_per_partner_pct` | float | 100% | `2.0` |
| `prestige.resets` | array | 100% | `["livelli edifici (Casolare torna a 1)", "Magazzino", "coloni"]` |
| `prestige.keeps` | array | 100% | `["soci", "gradi sbloccati", "statistiche a vita"]` |

## `event_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"event_rules"` |
| `currency_drop` | string | 100% | `"1 ogni 300 secondi di qualsiasi attività (online o offline)"` |
| `event_crates_open_with` | string | 100% | `"25 unità di valuta evento (nessuna chiave)"` |
| `past_event_rewards` | string | 100% | `"tornano ogni anno (nessuna esclusiva permanente)"` |
| `skill_of_the_week` | object | 100% | `{"rule": "mansione = elenco mansioni senza hero/bounty [numero_sett…` |
| `seasonal` | object | 100% | `{"drop_every_s": 300, "echo_every_s": 600, "max_drops_per_occurrenc…` |

Sotto-oggetto `skill_of_the_week`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `skill_of_the_week.rule` | string | 100% | `"mansione = elenco mansioni senza hero/bounty [numero_settimana_ISO…` |
| `skill_of_the_week.modifier` | string | 100% | `"+25% XP"` |

Sotto-oggetto `seasonal`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `seasonal.drop_every_s` | int | 100% | `300` |
| `seasonal.echo_every_s` | int | 100% | `600` |
| `seasonal.max_drops_per_occurrence` | int | 100% | `400` |
| `seasonal.max_drops_echo` | int | 100% | `400` |
| `seasonal.crate_cost` | int | 100% | `25` |
| `seasonal.clock_tolerance_s` | int | 100% | `3600` |
| `seasonal.min_valid_date` | string | 100% | `"2026-01-01"` |
| `seasonal.min_valid_unix` | int | 100% | `1767225600` |
| `seasonal.unlock_token` | string | 100% | `"feature:crates"` |
| `seasonal.calendar` | string | 100% | `"data locale del sistema; se l'orologio torna indietro o la data no…` |
| `seasonal.recovery` | string | 100% | `"ogni cosmetico: riproposta annuale, Eco fuori dalle date (metà rit…` |
| `seasonal.cosmetic_only` | bool | 100% | `true` |
| `seasonal.shop_prices` | object | 100% | `{"cosmetic_1": 25, "cosmetic_2": 50, "cosmetic_3": 80, "banner": 12…` |
| `seasonal.limits` | object | 100% | `{"max_crates_per_hour": 0.6, "max_relative_gain_pct": 15, "max_sing…` |

## `events.json`

Array di **4** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"lantern_night"` |
| `name` | loc{it,en} | 100% | `{"it": "Notte delle Lanterne", "en": "Lantern Night"}` |
| `dates` | object | 100% | `{"start": "10-20", "end": "11-05"}` |
| `currency` | string | 100% | `"event_wax"` |
| `crate` | string | 100% | `"crate_event_lantern_night"` |
| `modifiers` | array | 100% | `[{"key": "crate_find_pct:all", "value": 10, "mode": "add"}]` |
| `rewards` | array | 100% | `["pet_event_lantern_cat", "cosmetic_banner_lantern_night", "title_l…` |
| `title` | object | 100% | `{"id": "title_lantern_keeper", "name": {"it": "Custode delle Lanter…` |
| `quests` | int | 100% | `4` |
| `currency_drop_every_s` | int | 100% | `300` |
| `missions` | array | 100% | `[{"id": "evq_lantern_night_1", "kind": "actions", "qty": 200, "skil…` |
| `host` | string | 100% | `"dario"` |
| `intro` | loc{it,en} | 100% | `{"it": "Dario: «Notte delle Lanterne! Si accendono lanterne di cart…` |
| `shop` | array | 100% | `[{"kind": "item", "id": "cosmetic_event_lantern_night_1", "price": …` |
| `title_from` | string | 100% | `"missions"` |

Sotto-oggetto `dates`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `dates.start` | string | 100% | `"10-20"` |
| `dates.end` | string | 100% | `"11-05"` |

Sotto-oggetto `title`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `title.id` | string | 100% | `"title_lantern_keeper"` |
| `title.name` | loc{it,en} | 100% | `{"it": "Custode delle Lanterne di Carta", "en": "Keeper of Paper La…` |

## `expedition_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"expedition_rules"` |
| `types` | array | 100% | `[{"id": "recon", "name": {"it": "Ricognizione", "en": "Reconnaissan…` |
| `durations_h` | array | 100% | `[0.5, 1, 2, 4, 8, 12, 0.25]` |
| `duration_reward_mult` | array | 100% | `[1.0, 1.0, 1.05, 1.1, 1.18, 1.25, 1.0]` |
| `required_power_formula` | string | 100% | `"30 * 1.35^(zona-1) * dimensione_squadra_consigliata(2..4)"` |
| `success_formula` | string | 100% | `"clamp(1.6 * P/(P+Req) - 0.15, 0.05, 0.98)"` |
| `reward_value_per_hour_formula` | string | 100% | `"0.6 * gph(tier_zona) * dimensione_squadra/4"` |
| `passive_income_gph_estimate` | float | 100% | `0.4` |
| `salvage_crates_per_4h` | int | 100% | `1` |
| `salvage_key_chance` | float | 100% | `0.1` |
| `fail_reward_pct` | int | 100% | `25` |
| `merc_xp_per_hour` | int | 100% | `40` |
| `map_fragment_chance` | object | 100% | `{"survey": 0.35, "other": 0.05}` |

Sotto-oggetto `map_fragment_chance`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `map_fragment_chance.survey` | float | 100% | `0.35` |
| `map_fragment_chance.other` | float | 100% | `0.05` |

## `factions.json`

Array di **5** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"merchant_league"` |
| `name` | loc{it,en} | 100% | `{"it": "Lega dei Mercanti", "en": "Merchant League"}` |
| `npc` | string | 100% | `"bertoldo"` |
| `desc` | loc{it,en} | 100% | `{"it": "Economia, mercato, tenuta. Entrata consigliata con sorriso …` |
| `ranks` | array | 100% | `[{"id": "neutral", "name": {"it": "Passante", "en": "Passerby"}, "r…` |
| `rank_rewards` | array | 100% | `[{"rank": "friendly", "modifiers": [{"key": "market_tax_reduction_p…` |
| `emblem` | string | 100% | `"res://assets/icons/factions/merchant_league.png"` |

## `farming_plots.json`

Array di **2** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"garden"` |
| `name` | loc{it,en} | 100% | `{"it": "Orto", "en": "Garden"}` |
| `accepts` | array | 100% | `["crop"]` |
| `base_plots` | int | 100% | `4` |
| `max_plots` | int | 100% | `8` |
| `unlock_costs_gold` | array | 100% | `[5000, 25000, 120000, 600000]` |

## `frames.json`

Array di **104** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"cosmetic_frame_woodcutting_bronze"` |
| `name` | loc{it,en} | 100% | `{"it": "Cornice di Bronzo: Taglialegna", "en": "Bronze Frame: Woodc…` |

## `gazette_events.json`

Array di **10** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"smiths_strike"` |
| `text` | loc{it,en} | 100% | `{"it": "Sciopero dei fabbri: i lingotti valgono di più! Gunilde non…` |
| `category` | string | 100% | `"bar"` |
| `mult` | float | 100% | `1.35` |
| `duration_h` | int | 100% | `3` |
| `weight` | int | 100% | `10` |

## `guides.json`

Array di **6** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"guide_manual"` |
| `requires` | array | 100% | `["feature:secrets"]` |
| `screen` | string | 100% | `"manual"` |
| `title` | loc{it,en} | 100% | `{"it": "Sfoglia il Manuale", "en": "Browse the Manual"}` |
| `text` | loc{it,en} | 100% | `{"it": "Apri «Manuale» dal menù laterale (o premi F1). Ogni pagina …` |
| `why` | loc{it,en} | 100% | `{"it": "Così trovi la risposta senza cercarla in giro.", "en": "So …` |
| `goto` | object | 100% | `{"screen": "manual", "params": {}}` |

Sotto-oggetto `goto`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `goto.screen` | string | 100% | `"manual"` |
| `goto.params` | object | 100% | `null` |

## `items/ammo.json`

Array di **33** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"oil_t1"` |
| `name` | loc{it,en} | 100% | `{"it": "Olio da Lama I", "en": "Blade Oil I"}` |
| `category` | string | 100% | `"ammo"` |
| `subcategory` | string | 100% | `"oil"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `1` |
| `ammo` | object | 100% | `{"style": "melee", "damage": 1, "per": "hit", "optional": true}` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/oil_t1.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Un olio per lame: più affilato dove serve, più unto dove no…` |

Sotto-oggetto `ammo`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `ammo.style` | string | 100% | `"melee"` |
| `ammo.damage` | int | 100% | `1` |
| `ammo.per` | string | 100% | `"hit"` |
| `ammo.optional` | bool | 100% | `true` |
| `ammo.base_recovery_pct` | int | 33% | `20` |

## `items/consumable.json`

Array di **5** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"tome_xp_small"` |
| `name` | loc{it,en} | 100% | `{"it": "Tomo dell'Esperienza Minore", "en": "Lesser Tome of Experie…` |
| `category` | string | 100% | `"consumable"` |
| `subcategory` | string | 100% | `"xp_tome"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `0` |
| `tradeable` | bool | 100% | `false` |
| `tome` | object | 60% | `{"xp_formula": "1 * xph(tier_del_livello_attuale) * 0.25; sull'Eroe…` |
| `stackable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/tome_xp_small.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Un tomo con un po' di sapere. Non basta per diventare saggi…` |
| `hourglass` | object | 20% | `{"hours": 1, "effect": "simula 1 ora dell'azione attiva come progre…` |

Sotto-oggetto `tome`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `tome.xp_formula` | string | 100% | `"1 * xph(tier_del_livello_attuale) * 0.25; sull'Eroe al massimo 2 l…` |
| `tome.mult` | int | 100% | `1` |
| `tome.xph_frac` | float | 100% | `0.25` |
| `tome.hero_max_levels` | int | 100% | `2` |
| `tome.skill` | string | 100% | `"scelta del giocatore (o fissata dalla ricompensa)"` |

Sotto-oggetto `hourglass`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `hourglass.hours` | int | 100% | `1` |
| `hourglass.effect` | string | 100% | `"simula 1 ora dell'azione attiva come progresso offline"` |
| `hourglass.activities` | array | 100% | `["skill", "zone"]` |

## `items/cosmetic.json`

Array di **40** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"cosmetic_banner_01"` |
| `name` | loc{it,en} | 100% | `{"it": "Stendardo del Lupo", "en": "Wolf Banner"}` |
| `category` | string | 100% | `"cosmetic"` |
| `subcategory` | string | 100% | `"banner"` |
| `tier` | int | 100% | `1` |
| `stackable` | bool | 100% | `false` |
| `rarity` | string | 100% | `"rare"` |
| `value` | int | 100% | `10` |
| `icon` | string | 100% | `"res://assets/icons/cosmetics/cosmetic_banner_01.png"` |
| `tradeable` | bool | 100% | `true` |
| `desc` | loc{it,en} | 100% | `{"it": "Un lupo che ulula alla luna. Dario precisa: «Era un cucciol…` |

## `items/crate.json`

Array di **33** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"crate_millbrook"` |
| `name` | loc{it,en} | 100% | `{"it": "Cassa della Valle", "en": "Vale Crate"}` |
| `category` | string | 100% | `"crate"` |
| `subcategory` | string | 100% | `"crate"` |
| `tier` | int | 100% | `2` |
| `value` | int | 100% | `20` |
| `key` | null, string | 100% | `"key_t1"` |
| `icon` | string | 100% | `"res://assets/icons/crates/crate_millbrook.png"` |
| `crate` | object | 100% | `{"kind": "zone", "key": "key_t1", "skins": ["skin_millbrook_01", "s…` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `desc` | loc{it,en} | 100% | `{"it": "Una Cassa piovuta dal cielo con garbo, cioè senza fracassar…` |

Sotto-oggetto `crate`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate.kind` | string | 100% | `"zone"` |
| `crate.key` | null, string | 100% | `"key_t1"` |
| `crate.skins` | array | 100% | `["skin_millbrook_01", "skin_millbrook_02", "skin_millbrook_03", "sk…` |
| `crate.relic_pool` | array | 100% | `["relic_millbrook_1", "relic_millbrook_2", "relic_millbrook_3", "pe…` |
| `crate.odds` | object | 100% | `{"rare": 79.2, "epic": 15.8, "legendary": 3.8, "mythic": 0.9, "reli…` |
| `crate.pity_family` | null, string | 100% | `"crate_millbrook"` |
| `crate.collection` | null, string | 100% | `"collection_millbrook"` |
| `crate.era` | int | 33% | `2` |
| `crate.bonus_mult` | float | 33% | `1.25` |
| `crate.open_cost` | object | 12% | `{"item": "event_wax", "qty": 25}` |

## `items/currency.json`

Array di **10** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"raid_seal"` |
| `name` | loc{it,en} | 100% | `{"it": "Sigillo d'Incursione", "en": "Raid Seal"}` |
| `category` | string | 100% | `"currency"` |
| `subcategory` | string | 100% | `"token"` |
| `tier` | int | 100% | `6` |
| `value` | int | 100% | `0` |
| `tradeable` | bool | 100% | `false` |
| `desc` | loc{it,en} | 100% | `{"it": "Valuta delle Incursioni: si spende alla Sala dei Trofei.", …` |
| `stackable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/raid_seal.png"` |

## `items/equipment.json`

Array di **423** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"plate_helm_copper"` |
| `name` | loc{it,en} | 100% | `{"it": "Elmo di Rame", "en": "Copper Helm"}` |
| `category` | string | 100% | `"equipment"` |
| `subcategory` | string | 100% | `"armor"` |
| `tier` | int | 100% | `1` |
| `stackable` | bool | 100% | `false` |
| `value` | int | 100% | `8` |
| `equipment` | object | 100% | `{"slot": "helm", "armor_type": "plate", "style": "melee", "level_re…` |
| `quality_applies` | bool | 96% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/plate_helm_copper.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Ha una fessura per vedere. Col tempo impari a usarla anche …` |
| `unique` | bool | 13% | `true` |
| `source` | string | 13% | `"hornet_queen"` |

Sotto-oggetto `equipment`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `equipment.slot` | string | 100% | `"helm"` |
| `equipment.armor_type` | string | 41% | `"plate"` |
| `equipment.style` | null, string | 100% | `"melee"` |
| `equipment.level_req` | int | 100% | `1` |
| `equipment.stats` | object | 100% | `{"armor": 7, "ward": 2, "hp": 5, "str": 1, "evasion": -1}` |
| `equipment.two_handed` | bool | 22% | `false` |
| `equipment.weapon_type` | string | 22% | `"sword"` |
| `equipment.attack_interval_s` | float | 22% | `2.4` |
| `equipment.damage` | int | 22% | `7` |
| `equipment.min_ratio` | float | 22% | `0.6` |
| `equipment.offhand_type` | string | 5% | `"shield"` |
| `equipment.modifiers` | array | 29% | `[{"key": "combat_resource_regen_pct", "value": 6, "mode": "add"}]` |
| `equipment.element` | string | 5% | `"poison"` |

## `items/food.json`

Array di **31** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"food_bleak"` |
| `name` | loc{it,en} | 100% | `{"it": "Alborella alla Brace", "en": "Grilled Bleak"}` |
| `category` | string | 100% | `"food"` |
| `subcategory` | string | 100% | `"food"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `3` |
| `food` | object | 70% | `{"heal": 25}` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/food_bleak.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Un'alborella alla brace: croccante fuori, ancora sorpresa d…` |
| `feast` | object | 29% | `{"duration_min": 20, "modifiers": [{"key": "skill_xp_pct:gathering"…` |

Sotto-oggetto `food`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `food.heal` | int | 100% | `25` |
| `food.estate_ration` | bool | 50% | `true` |

Sotto-oggetto `feast`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `feast.duration_min` | int | 100% | `20` |
| `feast.modifiers` | array | 100% | `[{"key": "skill_xp_pct:gathering", "value": 3, "mode": "add"}]` |

## `items/glyph.json`

Array di **40** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"glyph_fury_1"` |
| `name` | loc{it,en} | 100% | `{"it": "Glifo della Furia I", "en": "Glyph of Fury I"}` |
| `category` | string | 100% | `"glyph"` |
| `subcategory` | string | 100% | `"glyph"` |
| `tier` | int | 100% | `2` |
| `value` | int | 100% | `240` |
| `glyph` | object | 100% | `{"modifiers": [{"key": "combat_dmg_pct", "value": 1, "mode": "add"}…` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/glyph_fury_1.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Glifo da incastro: più danno. Si incide con una scintilla d…` |

Sotto-oggetto `glyph`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `glyph.modifiers` | array | 100% | `[{"key": "combat_dmg_pct", "value": 1, "mode": "add"}]` |
| `glyph.line` | string | 100% | `"fury"` |
| `glyph.rank` | int | 100% | `1` |

## `items/key.json`

Array di **6** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"key_t1"` |
| `name` | loc{it,en} | 100% | `{"it": "Chiave di Rame", "en": "Copper Key"}` |
| `category` | string | 100% | `"key"` |
| `subcategory` | string | 100% | `"key"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `80` |
| `key_tier` | int | 100% | `1` |
| `tradeable` | bool | 100% | `false` |
| `desc` | loc{it,en} | 100% | `{"it": "Apre le Casse del suo tier. Non si vende al mercato. Gunild…` |
| `stackable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/key_t1.png"` |

## `items/material.json`

Array di **202** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"log_pine"` |
| `name` | loc{it,en} | 100% | `{"it": "Tronco di Pino", "en": "Pine Log"}` |
| `category` | string | 100% | `"material"` |
| `subcategory` | string | 100% | `"log"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `2` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/log_pine.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Un tronco di pino onesto. Brucia, regge, e non fa domande."…` |

## `items/misc.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"burnt_food"` |
| `name` | loc{it,en} | 100% | `{"it": "Cibo Bruciato", "en": "Burnt Food"}` |
| `category` | string | 100% | `"misc"` |
| `subcategory` | string | 100% | `"junk"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `1` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/burnt_food.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Cibo bruciato: nero, fumante e orgogliosamente inutilizzabi…` |

## `items/openable.json`

Array di **3** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"bird_nest"` |
| `name` | loc{it,en} | 100% | `{"it": "Nido d'Uccello", "en": "Bird's Nest"}` |
| `category` | string | 100% | `"openable"` |
| `subcategory` | string | 100% | `"nest"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `30` |
| `desc` | loc{it,en} | 100% | `{"it": "Contiene semi, piume o una gemma. Dentro potrebbe esserci u…` |
| `open_table` | string | 100% | `"table_bird_nest"` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/bird_nest.png"` |

## `items/potion.json`

Array di **51** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"potion_vigor_1"` |
| `name` | loc{it,en} | 100% | `{"it": "Pozione di Vigore I", "en": "Vigor Potion I"}` |
| `category` | string | 100% | `"potion"` |
| `subcategory` | string | 100% | `"potion"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `15` |
| `potion` | object | 100% | `{"scope": "combat", "charges": 100, "modifiers": [{"key": "combat_r…` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/potion_vigor_1.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Una pozione di vigore. Mirta giura che sia «quasi la ricett…` |

Sotto-oggetto `potion`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `potion.scope` | string | 100% | `"combat"` |
| `potion.charges` | int | 100% | `100` |
| `potion.modifiers` | array | 100% | `[{"key": "combat_regen_hps_pct", "value": 0.4, "mode": "add"}]` |

## `items/quest.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"celestial_key"` |
| `name` | loc{it,en} | 100% | `{"it": "Chiave Celeste", "en": "Celestial Key"}` |
| `category` | string | 100% | `"quest"` |
| `subcategory` | string | 100% | `"quest"` |
| `tier` | int | 100% | `10` |
| `value` | int | 100% | `0` |
| `tradeable` | bool | 100% | `false` |
| `desc` | loc{it,en} | 100% | `{"it": "Forgiata da Gunilde con il nucleo della tempesta. Pina, il …` |
| `stackable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/celestial_key.png"` |

## `items/relic.json`

Array di **48** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"relic_millbrook_1"` |
| `name` | loc{it,en} | 100% | `{"it": "Falcetto della Prima Mietitura", "en": "Sickle of the First…` |
| `category` | string | 100% | `"relic"` |
| `subcategory` | string | 100% | `"relic"` |
| `tier` | int | 100% | `2` |
| `stackable` | bool | 100% | `false` |
| `value` | int | 100% | `10000` |
| `rarity` | string | 100% | `"relic"` |
| `crate` | string | 100% | `"millbrook"` |
| `relic` | object | 100% | `{"slot": "relic", "float_min": 0.0, "float_max": 1.0, "condition_od…` |
| `icon` | string | 100% | `"res://assets/icons/relics/relic_millbrook_1.png"` |
| `tradeable` | bool | 100% | `true` |
| `desc` | loc{it,en} | 100% | `{"it": "Ha mietuto il primo grano della Valle. Nonna Berta giura di…` |

Sotto-oggetto `relic`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `relic.slot` | string | 100% | `"relic"` |
| `relic.float_min` | float | 100% | `0.0` |
| `relic.float_max` | float | 100% | `1.0` |
| `relic.condition_odds` | object | 100% | `{"pristine": 5.0, "polished": 25.0, "marked": 34.0, "worn": 21.0, "…` |
| `relic.phases` | array | 100% | `["phase_1", "phase_2", "phase_3", "phase_4", "gem_ruby", "gem_sapph…` |
| `relic.modifiers` | array | 100% | `[{"key": "skill_double_pct:gathering", "value": 6, "mode": "add"}, …` |

## `items/seed.json`

Array di **15** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"seed_potato"` |
| `name` | loc{it,en} | 100% | `{"it": "Semi di Patata", "en": "Potato Seeds"}` |
| `category` | string | 100% | `"seed"` |
| `subcategory` | string | 100% | `"seed"` |
| `tier` | int | 100% | `1` |
| `value` | int | 100% | `2` |
| `stackable` | bool | 100% | `true` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/seed_potato.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Un sacchetto di semi. Pianta, innaffia e aspetta con aria s…` |

## `items/skin.json`

Array di **240** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"skin_millbrook_01"` |
| `name` | loc{it,en} | 100% | `{"it": "Spiga Dorata", "en": "Golden Ear"}` |
| `category` | string | 100% | `"skin"` |
| `subcategory` | string | 100% | `"weapon"` |
| `tier` | int | 100% | `2` |
| `stackable` | bool | 100% | `false` |
| `value` | int | 100% | `20` |
| `rarity` | string | 100% | `"rare"` |
| `crate` | string | 100% | `"millbrook"` |
| `skin` | object | 100% | `{"slot": "weapon", "slot_group": "combat", "float_min": 0.0, "float…` |
| `icon` | string | 100% | `"res://assets/icons/skins/skin_millbrook_01.png"` |
| `tradeable` | bool | 100% | `true` |
| `desc` | loc{it,en} | 100% | `{"it": "«Spiga Dorata»: finitura rara per l'arma. I nemici vengono …` |

Sotto-oggetto `skin`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `skin.slot` | string | 100% | `"weapon"` |
| `skin.slot_group` | string | 100% | `"combat"` |
| `skin.float_min` | float | 100% | `0.0` |
| `skin.float_max` | float | 100% | `1.0` |
| `skin.condition_odds` | object | 100% | `{"pristine": 5.0, "polished": 25.0, "marked": 34.0, "worn": 21.0, "…` |
| `skin.modifier` | object | 100% | `{"key": "combat_dmg_pct", "value": 1.0, "mode": "add"}` |
| `skin.pattern_seeds` | int | 100% | `1000` |
| `skin.special_patterns` | array | 100% | `[{"seeds": [7, 77, 777], "name": {"it": "Motivo Leggendario", "en":…` |

## `items/tool.json`

Array di **66** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"axe_copper"` |
| `name` | loc{it,en} | 100% | `{"it": "Ascia di Rame", "en": "Copper Axe"}` |
| `category` | string | 100% | `"tool"` |
| `subcategory` | string | 100% | `"axe"` |
| `tier` | int | 100% | `1` |
| `stackable` | bool | 100% | `false` |
| `value` | int | 100% | `12` |
| `tool` | object | 100% | `{"skill": "woodcutting", "level_req": 1, "haste_pct": 0, "double_pc…` |
| `tradeable` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/items/axe_copper.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Un'ascia: serve ad abbattere alberi. Con gli alberi non si …` |

Sotto-oggetto `tool`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `tool.skill` | string | 100% | `"woodcutting"` |
| `tool.level_req` | int | 100% | `1` |
| `tool.haste_pct` | int | 100% | `0` |
| `tool.double_pct` | int | 83% | `0` |
| `tool.success_pct` | float | 16% | `1.5` |

## `loot_tables.json`

Array di **3** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"table_rune_pouch"` |
| `rolls` | int | 100% | `1` |
| `entries` | array | 100% | `[{"item": "rune_t1", "weight": 1, "qty": 250}]` |
| `gold` | array | 33% | `[50, 400]` |

## `market_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"market_rules"` |
| `sell_tax` | float | 100% | `0.05` |
| `buy_markup` | float | 100% | `1.8` |
| `buy_markup_equipment` | float | 100% | `6.5` |
| `demand` | object | 100% | `{"half_life_h": 6.0, "elasticity_hours_of_production": 8.0, "formul…` |
| `trend` | object | 100% | `{"model": "Ornstein-Uhlenbeck giornaliero per categoria", "theta": …` |
| `gazette_interval_h` | float | 100% | `3.0` |
| `npc_stock` | object | 100% | `{"refresh_min": 60, "qty_formula": "volume_elastico / 4", "price": …` |
| `categories` | array | 100% | `["log", "plank", "ore", "bar", "gem_raw", "gem", "fish_raw", "food"…` |
| `price_history_days` | int | 100% | `30` |

Sotto-oggetto `demand`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `demand.half_life_h` | float | 100% | `6.0` |
| `demand.elasticity_hours_of_production` | float | 100% | `8.0` |
| `demand.formula` | string | 100% | `"prezzo_vendita = valore * trend_categoria * 1/(1 + venduti_recenti…` |
| `demand.volume_elastico_formula` | string | 100% | `"8 ore di produzione dell'azione migliore che crea l'oggetto, equip…` |
| `demand.min_volume` | int | 100% | `20` |
| `demand.drop_volume_per_tier` | int | 100% | `300` |

Sotto-oggetto `trend`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `trend.model` | string | 100% | `"Ornstein-Uhlenbeck giornaliero per categoria"` |
| `trend.theta` | float | 100% | `0.2` |
| `trend.sigma` | float | 100% | `0.07` |
| `trend.min` | float | 100% | `0.7` |
| `trend.max` | float | 100% | `1.4` |
| `trend.mean` | float | 100% | `1.0` |

Sotto-oggetto `npc_stock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `npc_stock.refresh_min` | int | 100% | `60` |
| `npc_stock.qty_formula` | string | 100% | `"volume_elastico / 4"` |
| `npc_stock.price` | string | 100% | `"valore * 1.8 * trend (equipaggiamento: valore * buy_markup_equipme…` |

## `mercenary_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"mercenary_rules"` |
| `roles` | array | 100% | `[{"id": "defender", "name": {"it": "Difensore", "en": "Defender"}},…` |
| `rarities` | array | 100% | `[{"id": "common", "base_power": 10, "max_level": 30, "weight": 600,…` |
| `power_formula` | string | 100% | `"base_power * (1 + 0.1*(livello-1)) * (1 + merc_power_pct/100) * (1…` |
| `xp_to_next_formula` | string | 100% | `"100 * 1.12^livello"` |
| `hire_cost_formula` | string | 100% | `"1000 * hire_mult * (1 + tavern_level*0.02)"` |
| `recruit_board` | object | 100% | `{"candidates": 3, "refresh_h": 6, "reroll_cost_gold": 2000}` |
| `injury` | object | 100% | `{"chance_on_fail": 0.3, "duration_h": 2}` |
| `traits` | array | 100% | `[{"id": "lucky", "name": {"it": "Fortunato", "en": "Lucky"}, "effec…` |
| `traits_per_merc` | object | 100% | `{"common": 1, "uncommon": 1, "rare": 2, "epic": 2, "legendary": 3}` |
| `names_pool_it_en` | array | 100% | `["Aldo", "Bianca", "Corrado", "Delia", "Ettore", "Fosca", "Gino", "…` |
| `raid_role_effects` | object | 100% | `{"defender": "riduzione danni subiti = 30% * min(1.5, potere/potere…` |
| `raid_roles` | object | 100% | `{"power_base": 30, "power_growth": 1.35, "power_party_size": 4, "ra…` |

Sotto-oggetto `recruit_board`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `recruit_board.candidates` | int | 100% | `3` |
| `recruit_board.refresh_h` | int | 100% | `6` |
| `recruit_board.reroll_cost_gold` | int | 100% | `2000` |

Sotto-oggetto `injury`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `injury.chance_on_fail` | float | 100% | `0.3` |
| `injury.duration_h` | int | 100% | `2` |

Sotto-oggetto `traits_per_merc`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `traits_per_merc.common` | int | 100% | `1` |
| `traits_per_merc.uncommon` | int | 100% | `1` |
| `traits_per_merc.rare` | int | 100% | `2` |
| `traits_per_merc.epic` | int | 100% | `2` |
| `traits_per_merc.legendary` | int | 100% | `3` |

Sotto-oggetto `raid_role_effects`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `raid_role_effects.defender` | string | 100% | `"riduzione danni subiti = 30% * min(1.5, potere/potere_richiesto)"` |
| `raid_role_effects.healer` | string | 100% | `"cura = 1.5% vita max/s * min(1.5, potere/potere_richiesto)"` |
| `raid_role_effects.striker` | string | 100% | `"danno giocatore +40% * min(1.5, potere/potere_richiesto)"` |
| `raid_role_effects.required_power_formula` | string | 100% | `"30 * 1.35^(zona-1) * 4"` |

Sotto-oggetto `raid_roles`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `raid_roles.power_base` | int | 100% | `30` |
| `raid_roles.power_growth` | float | 100% | `1.35` |
| `raid_roles.power_party_size` | int | 100% | `4` |
| `raid_roles.ratio_cap` | float | 100% | `1.5` |
| `raid_roles.hero_share` | float | 100% | `0.6` |
| `raid_roles.hero_level_cap` | float | 100% | `1.3` |
| `raid_roles.hero_role_share` | float | 100% | `0.5` |
| `raid_roles.defender` | object | 100% | `{"dmg_taken_pct": -30}` |
| `raid_roles.healer` | object | 100% | `{"regen_pct_per_s": 1.5}` |
| `raid_roles.striker` | object | 100% | `{"dmg_pct": 40}` |

## `mode_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"mode_rules"` |
| `default` | string | 100% | `"normal"` |
| `modes` | object | 100% | `{"normal": {"title": null, "star_title": null, "frame": null}, "aut…` |

Sotto-oggetto `modes`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `modes.normal` | object | 100% | `{"title": null, "star_title": null, "frame": null}` |
| `modes.autarchic` | object | 100% | `{"market_buy": {"allow_items": ["vial", "seed_potato", "seed_wheat"…` |
| `modes.extreme` | object | 100% | `{"permadeath": {"reset_skills": ["hero"], "lose_equipment": true, "…` |

## `modifier_catalog.json`

Array di **75** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `family` | string | 100% | `"skill_xp_pct"` |
| `unit` | string | 100% | `"pct"` |
| `scopes` | array, null | 100% | `["all", "current", "gathering", "artisan", "special", "combat", "wo…` |
| `cap` | int, null | 100% | `50` |
| `desc` | loc{it,en} | 100% | `{"it": "+% XP nella mansione", "en": "+% XP in the skill"}` |
| `cat` | string | 100% | `"skills"` |
| `name` | loc{it,en} | 100% | `{"it": "Esperienza", "en": "Experience"}` |
| `blurb` | loc{it,en} | 100% | `{"it": "Più esperienza guadagnata ogni volta che completi un'azione…` |
| `scope_all` | loc{it,en}, null | 100% | `{"it": "tutte le mansioni", "en": "all skills"}` |

## `monsters.json`

Array di **76** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"mud_slime"` |
| `name` | loc{it,en} | 100% | `{"it": "Melma di Fango", "en": "Mud Slime"}` |
| `zone` | null, string | 100% | `"millbrook"` |
| `level` | int | 100% | `2` |
| `type` | string | 100% | `"normal"` |
| `style` | string | 100% | `"melee"` |
| `damage_type` | string | 100% | `"physical"` |
| `weakness` | string | 100% | `"fire"` |
| `resistance` | null, string | 100% | `"poison"` |
| `stats` | object | 100% | `{"hp": 26, "max_hit": 15, "accuracy": 35, "evasion": 28, "armor": 4…` |
| `xp` | int | 100% | `22` |
| `gold` | array | 100% | `[2, 5]` |
| `drop_table` | string | 100% | `"drops_mud_slime"` |
| `portrait` | string | 100% | `"res://assets/portraits/monsters/mud_slime.png"` |
| `desc` | loc{it,en} | 100% | `{"it": "Una pozzanghera con delle opinioni. Odia tutti, soprattutto…` |
| `mechanics` | array | 34% | `["heavy_blow"]` |
| `unique_drops` | array | 34% | `["queens_stinger", "wasp_wings"]` |
| `pet` | null, string | 30% | `"pet_boss_millbrook"` |
| `phases` | array | 3% | `[{"hp_pct": 100, "style": "ranged"}, {"hp_pct": 66, "style": "melee…` |

Sotto-oggetto `stats`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `stats.hp` | int | 100% | `26` |
| `stats.max_hit` | int | 100% | `15` |
| `stats.accuracy` | int | 100% | `35` |
| `stats.evasion` | int | 100% | `28` |
| `stats.armor` | int | 100% | `4` |
| `stats.ward` | int | 100% | `4` |
| `stats.attack_interval_s` | float | 100% | `2.8` |

## `npcs.json`

Array di **12** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"ilde"` |
| `name` | loc{it,en} | 100% | `{"it": "Maestra Ilde", "en": "Mistress Ilde"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Capo dell'Ordine dei Custodi. Ama tre cose: i regolamenti, …` |
| `portrait` | string | 100% | `"res://assets/portraits/npcs/ilde.png"` |
| `chat` | array | 100% | `[{"it": "«Il modulo per lamentarsi dei moduli esiste. Richiede un m…` |

## `orders_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"orders_rules"` |
| `name` | loc{it,en} | 100% | `{"it": "Commesse", "en": "Orders"}` |
| `board_slots` | int | 100% | `4` |
| `refresh_h` | int | 100% | `4` |
| `deadline_h` | int | 100% | `168` |
| `lifetime_days` | int | 100% | `7` |
| `reject_cooldown_min` | int | 100% | `30` |
| `item_pool` | string | 100% | `"oggetti tradeable con tier <= tier massimo sbloccato dal giocatore…` |
| `max_production_hours` | int | 100% | `24` |
| `unique_qty_max` | int | 100% | `3` |
| `item_pool_excluded` | object | 100% | `{"categories": ["skin", "relic", "rune"], "unique_items": true, "it…` |
| `qty_range` | array | 100% | `[0.1, 0.3]` |
| `reward_mult_range` | array | 100% | `[1.0, 1.2]` |
| `qty_formula` | string | 100% | `"volume_elastico * random(0.1, 0.3)"` |
| `reward_formula` | string | 100% | `"qty * valore * random(1.0, 1.2)"` |
| `reputation_formula` | string | 100% | `"10 + 5 * tier"` |
| `faction_by_category` | object | 100% | `{"bar": "merchant_league", "equipment": "order_of_wardens", "potion…` |
| `crate_chance` | float | 100% | `0.1` |

Sotto-oggetto `item_pool_excluded`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `item_pool_excluded.categories` | array | 100% | `["skin", "relic", "rune"]` |
| `item_pool_excluded.unique_items` | bool | 100% | `true` |
| `item_pool_excluded.items` | array | 100% | `["tome_t1", "tome_t2", "tome_t3", "amulet_bulwark_t1", "amulet_bulw…` |

Sotto-oggetto `faction_by_category`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `faction_by_category.bar` | string | 100% | `"merchant_league"` |
| `faction_by_category.equipment` | string | 100% | `"order_of_wardens"` |
| `faction_by_category.potion` | string | 100% | `"arcane_college"` |
| `faction_by_category.rune` | string | 100% | `"arcane_college"` |
| `faction_by_category.hide` | string | 100% | `"rangers_company"` |
| `faction_by_category.leather` | string | 100% | `"rangers_company"` |
| `faction_by_category.food` | string | 100% | `"merchant_league"` |
| `faction_by_category.gem` | string | 100% | `"grey_hand"` |
| `faction_by_category.skin` | string | 100% | `"grey_hand"` |

## `pets.json`

Array di **40** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"pet_skill_woodcutting"` |
| `name` | loc{it,en} | 100% | `{"it": "Scoiattolo Boscaiolo", "en": "Lumberjack Squirrel"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Lancia ghiande e ordini. Gli ordini sono i più pericolosi."…` |
| `source` | object | 100% | `{"type": "skill_action", "skill": "woodcutting", "chance_formula": …` |
| `modifiers` | array | 100% | `[{"key": "skill_double_pct:woodcutting", "value": 3, "mode": "add"}]` |
| `portrait` | string | 100% | `"res://assets/portraits/pets/pet_skill_woodcutting.png"` |

Sotto-oggetto `source`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `source.type` | string | 100% | `"skill_action"` |
| `source.skill` | string | 42% | `"woodcutting"` |
| `source.chance_formula` | string | 42% | `"tempo_azione_s / 150000 * (1 + livello/100)"` |
| `source.monster` | string | 25% | `"hornet_queen"` |
| `source.chance` | float | 32% | `0.000667` |
| `source.raid` | string | 7% | `"collectors_den"` |
| `source.crate` | string | 25% | `"crate_millbrook"` |
| `source.event` | string | 10% | `"lantern_night"` |

## `quests.json`

Array di **270** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"main_c0_q1"` |
| `kind` | string | 100% | `"main"` |
| `chapter` | int, null | 100% | `0` |
| `giver` | null, string | 100% | `"ilde"` |
| `title` | loc{it,en} | 100% | `{"it": "Piove Roba dal Cielo", "en": "Stuff Falls from the Sky"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Dal cielo piovono Casse sul tetto di Orvane, e la Maestra I…` |
| `objectives` | array | 100% | `[{"type": "gather", "item": "log_pine", "qty": 25}]` |
| `rewards` | object | 100% | `{"gold": 50}` |
| `unlocks` | array | 100% | `["skill:woodcutting", "skill:mining"]` |
| `requires` | array | 100% | `["main_c0_q1"]` |

## `raids.json`

Array di **3** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"collectors_den"` |
| `order` | int | 100% | `1` |
| `name` | loc{it,en} | 100% | `{"it": "Covo del Collezionista", "en": "Collector's Den"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Incursione per una squadra di 3 mercenari (difensore, guari…` |
| `zone` | string | 100% | `"gallmire"` |
| `boss` | string | 100% | `"master_fence"` |
| `level` | int | 100% | `55` |
| `party` | object | 100% | `{"size": 3, "roles": ["defender", "healer", "striker"], "source": "…` |
| `attempts_per_day` | null | 100% | `null` |
| `cooldown_h` | int | 100% | `4` |
| `merc_xp` | int | 100% | `120` |
| `completion_reward` | object | 100% | `{"gold": 12819, "crates": [{"id": "crate_gallmire", "qty": 2}], "it…` |
| `unlock` | object | 100% | `{"quest": "main_c5_q6", "hero_level": 50}` |
| `banner` | string | 100% | `"res://assets/banners/raids/collectors_den.png"` |

Sotto-oggetto `party`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `party.size` | int | 100% | `3` |
| `party.roles` | array | 100% | `["defender", "healer", "striker"]` |
| `party.source` | string | 100% | `"mercenaries"` |

Sotto-oggetto `completion_reward`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `completion_reward.gold` | int | 100% | `12819` |
| `completion_reward.crates` | array | 100% | `[{"id": "crate_gallmire", "qty": 2}]` |
| `completion_reward.items` | array | 100% | `[{"item": "raid_seal", "qty": [3, 5]}]` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.quest` | string | 100% | `"main_c5_q6"` |
| `unlock.hero_level` | int | 100% | `50` |

## `resources.json`

Array di **3** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"fury"` |
| `name` | loc{it,en} | 100% | `{"it": "Furia", "en": "Fury"}` |
| `max` | int | 66% | `100` |
| `on_hit_dealt` | int | 33% | `16` |
| `on_hit_taken` | int | 33% | `8` |
| `regen_per_s` | int | 66% | `0` |
| `decay_out_of_combat_per_s` | int | 33% | `5` |
| `on_crit` | int | 33% | `10` |
| `max_formula` | string | 33% | `"50 + 2*INT"` |
| `regen_pct_per_s` | float | 33% | `2.5` |

## `rift.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"the_rift"` |
| `name` | loc{it,en} | 100% | `{"it": "La Breccia", "en": "The Rift"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Piani infiniti generati proceduralmente. Ogni 10 piani un G…` |
| `unlock` | object | 100% | `{"quest": "main_c10_q6"}` |
| `floor_level` | string | 100% | `"100 + floor"` |
| `stat_mult_per_floor` | float | 100% | `0.99` |
| `dmg_mult_per_floor` | float | 100% | `0.985` |
| `monsters_per_floor` | int | 100% | `5` |
| `guardian_every` | int | 100% | `10` |
| `styles_cycle` | array | 100% | `["melee", "ranged", "arcane"]` |
| `affixes` | array | 100% | `[{"id": "fortified", "name": {"it": "Fortificati (Fanno Palestra)",…` |
| `rewards_per_floor` | object | 100% | `{"rift_shard": "1 + floor // 10", "crate_rift_chance": "min(0.5, 0.…` |
| `crate` | string | 100% | `"crate_rift"` |
| `guardian_rewards` | array | 100% | `[{"item": "crate_rift", "qty": 1}, {"item": "era_essence", "qty": 1}]` |
| `leaderboard` | string | 100% | `"steam:rift_best_floor"` |
| `floor_level_base` | int | 100% | `100` |
| `shards` | object | 100% | `{"base": 1, "per_floors": 10}` |
| `crate_chance` | object | 100% | `{"base": 0.05, "per_floor": 0.002, "max": 0.5}` |
| `monster_type` | string | 100% | `"normal"` |
| `guardian_type` | string | 100% | `"boss"` |
| `guardian_mechanics` | array | 100% | `["enrage", "heavy_blow"]` |
| `monster_names` | array | 100% | `[{"it": "Impiegato del Nulla", "en": "Void Clerk"}, {"it": "Eco Sco…` |
| `guardian_names` | array | 100% | `[{"it": "Guardiano delle Pratiche Arretrate", "en": "Guardian of th…` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.quest` | string | 100% | `"main_c10_q6"` |

Sotto-oggetto `rewards_per_floor`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `rewards_per_floor.rift_shard` | string | 100% | `"1 + floor // 10"` |
| `rewards_per_floor.crate_rift_chance` | string | 100% | `"min(0.5, 0.05 + floor * 0.002)"` |

Sotto-oggetto `shards`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `shards.base` | int | 100% | `1` |
| `shards.per_floors` | int | 100% | `10` |

Sotto-oggetto `crate_chance`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `crate_chance.base` | float | 100% | `0.05` |
| `crate_chance.per_floor` | float | 100% | `0.002` |
| `crate_chance.max` | float | 100% | `0.5` |

## `run_perks.json`

Array di **24** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"off_edge"` |
| `family` | string | 100% | `"offense"` |
| `name` | loc{it,en} | 100% | `{"it": "Filo Affilato", "en": "Honed Edge"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Si taglia meglio, anche le dita.", "en": "Cuts better, fing…` |
| `modifiers` | array | 100% | `[{"key": "combat_dmg_pct", "value": 7, "mode": "add"}, {"key": "com…` |

## `run_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"run_rules"` |
| `unlock_hero_level` | int | 100% | `15` |
| `unlock_token` | string | 100% | `"feature:run"` |
| `kills_per_choice` | int | 100% | `30` |
| `max_choices` | int | 100% | `12` |
| `offers` | int | 100% | `3` |
| `max_stacks` | int | 100% | `3` |
| `rerolls_per_run` | int | 100% | `1` |
| `banishes_per_run` | int | 100% | `1` |
| `ask_timeout_s` | int | 100% | `90` |
| `default_mode` | string | 100% | `"ask"` |
| `modes` | array | 100% | `["ask", "auto"]` |
| `safety_defense_first` | bool | 100% | `true` |
| `rng_stream` | string | 100% | `"world"` |
| `modifier_source` | string | 100% | `"run:perks"` |
| `worse_if_higher` | array | 100% | `["combat_dmg_taken_pct"]` |
| `history_max` | int | 100% | `5` |
| `champion` | object | 100% | `{"hp_mult": 5.0, "dmg_mult": 1.2, "reward_mult": 5.0, "loot_rolls":…` |
| `offline` | string | 100% | `"paused"` |
| `families` | array | 100% | `[{"id": "offense", "name": {"it": "Offesa", "en": "Offense"}}, {"id…` |
| `forbidden_keys` | array | 100% | `["stardust_gain_pct", "soci_gain_pct", "echo_mult_pct", "offline_ca…` |

Sotto-oggetto `champion`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `champion.hp_mult` | float | 100% | `5.0` |
| `champion.dmg_mult` | float | 100% | `1.2` |
| `champion.reward_mult` | float | 100% | `5.0` |
| `champion.loot_rolls` | int | 100% | `2` |
| `champion.crate_chance` | float | 100% | `0.25` |
| `champion.retreat_hp_pct` | int | 100% | `25` |
| `champion.max_attempts` | int | 100% | `2` |

## `secret_spots.json`

Array di **5** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"hidden_grove"` |
| `name` | loc{it,en} | 100% | `{"it": "Bosco Nascosto (Si Vede Benissimo)", "en": "Hidden Grove (C…` |
| `skill` | string | 100% | `"woodcutting"` |
| `bonus_item` | string | 100% | `"log_vaultroot"` |
| `level_req` | int | 100% | `60` |
| `map_fragments_required` | int | 100% | `10` |
| `effect` | string | 100% | `"azione speciale: +50% XP del tier migliore sbloccato e 2% di otten…` |
| `duration_h_per_unlock` | int | 100% | `24` |

## `shop.json`

Array di **29** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `section` | string | 100% | `"upgrades"` |
| `id` | string | 100% | `"auto_eat_1"` |
| `name` | loc{it,en} | 34% | `{"it": "Cinturone del Viandante Affamato", "en": "Hungry Wayfarer's…` |
| `price` | int | 93% | `2000` |
| `effect` | object | 31% | `{"auto_eat": {"threshold_pct": 25, "target_pct": 55, "efficiency_pc…` |
| `requires` | null, object, string | 51% | `"auto_eat_1"` |
| `price_formula` | string | 6% | `"50000 * 3^n (n = slot già comprati)"` |
| `max` | int | 3% | `5` |
| `base_slots` | int | 3% | `100` |
| `max_purchases` | int | 3% | `340` |
| `item` | string | 65% | `"vial"` |
| `daily_limit` | int | 20% | `5` |

Sotto-oggetto `effect`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `effect.auto_eat` | object | 33% | `{"threshold_pct": 25, "target_pct": 55, "efficiency_pct": 90}` |
| `effect.action_queue_slots` | int | 22% | `3` |
| `effect.loadouts` | int | 11% | `1` |
| `effect.relic_slots` | int | 11% | `1` |
| `effect.market_tax_reduction_pct` | int | 22% | `20` |

Sotto-oggetto `requires`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `requires.hero_level` | int | 87% | `50` |
| `requires.faction` | string | 12% | `"merchant_league"` |
| `requires.rank` | string | 12% | `"friendly"` |

## `skill_perks.json`

Array di **170** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `skill` | string | 100% | `"woodcutting"` |
| `tier` | int | 100% | `1` |
| `level` | int | 100% | `10` |
| `signature` | bool | 100% | `false` |
| `options` | array | 100% | `[{"id": "perk_woodcutting_1_a", "modifiers": [{"key": "skill_haste_…` |
| `respec_cost_gold_formula` | string | 100% | `"1000 * livello_mansione"` |

## `skill_prestige.json`

Array di **17** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `skill` | string | 100% | `"woodcutting"` |
| `requires_level` | int | 100% | `100` |
| `kind` | string | 100% | `"gathering"` |
| `per_star_linear` | array | 100% | `[{"key": "combat_dmg_pct", "value": 1, "mode": "add"}, {"key": "com…` |
| `curves` | array | 100% | `[{"key": "skill_xp_pct:woodcutting", "mode": "more", "cap": 60, "de…` |
| `stardust_formula` | string | 100% | `"10 + 2 * (n - 1) per la stella n"` |
| `milestones` | array | 100% | `[{"stars": 1, "unlock": "automation:woodcutting", "desc": {"it": "A…` |
| `hero_extra` | null, object | 100% | `{"milestones": [{"stars": 1, "unlock": "hybrid_classes"}, {"stars":…` |

Sotto-oggetto `hero_extra`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `hero_extra.milestones` | array | 100% | `[{"stars": 1, "unlock": "hybrid_classes"}, {"stars": 3, "unlock": "…` |

## `skills.json`

Array di **17** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"woodcutting"` |
| `group` | string | 100% | `"gathering"` |
| `order` | int | 100% | `0` |
| `name` | loc{it,en} | 100% | `{"it": "Taglialegna", "en": "Woodcutting"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Abbatti alberi per ottenere tronchi. Dario dice di parlare …` |
| `tool_type` | null, string | 100% | `"axe"` |
| `level_cap` | int | 100% | `100` |
| `prestige` | bool | 100% | `true` |
| `icon` | string | 100% | `"res://assets/icons/skills/woodcutting.png"` |
| `crate` | null, string | 100% | `"crate_gatherer"` |

## `social_rules.json`

Array di **1** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"social_rules"` |
| `pets` | object | 100% | `{"duplicate_stardust": 3, "crate_duplicate_stardust": 8, "event_dup…` |
| `achievements` | object | 100% | `{"poll_s": 2.0}` |
| `secrets` | object | 100% | `{"explore_minutes": 20, "runs_per_reveal": 3, "xp_mult": 1.5, "bonu…` |
| `log_digest` | object | 100% | `{"window_s": 1.5, "max_items_listed": 3}` |

Sotto-oggetto `pets`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `pets.duplicate_stardust` | int | 100% | `3` |
| `pets.crate_duplicate_stardust` | int | 100% | `8` |
| `pets.event_duplicate_stardust` | int | 100% | `0` |

Sotto-oggetto `achievements`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `achievements.poll_s` | float | 100% | `2.0` |

Sotto-oggetto `secrets`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `secrets.explore_minutes` | int | 100% | `20` |
| `secrets.runs_per_reveal` | int | 100% | `3` |
| `secrets.xp_mult` | float | 100% | `1.5` |
| `secrets.bonus_chance` | float | 100% | `0.02` |
| `secrets.discovery_stardust` | int | 100% | `3` |
| `secrets.unlock_token` | string | 100% | `"feature:secrets"` |

Sotto-oggetto `log_digest`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `log_digest.window_s` | float | 100% | `1.5` |
| `log_digest.max_items_listed` | int | 100% | `3` |

## `steam_achievements.json`

Array di **118** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"ach_woodcutting_50"` |
| `steam_api_name` | string | 100% | `"ACH_WOODCUTTING_50"` |
| `phase` | int | 100% | `1` |
| `category` | string | 100% | `"skills"` |
| `hidden` | bool | 100% | `false` |
| `name` | loc{it,en} | 100% | `{"it": "Taglialegna 50", "en": "Woodcutting 50"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Raggiungi il livello 50 in Taglialegna.", "en": "Reach leve…` |
| `icon_achieved` | string | 100% | `"ACH_WOODCUTTING_50_ACHIEVED.png"` |
| `icon_unachieved` | string | 100% | `"ACH_WOODCUTTING_50_UNACHIEVED.png"` |

## `talents.json`

Array di **78** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"warrior_toughness"` |
| `class` | string | 100% | `"warrior"` |
| `branch` | string | 100% | `"general"` |
| `index` | int | 100% | `0` |
| `name` | loc{it,en} | 100% | `{"it": "Pelle Dura", "en": "Thick Skin"}` |
| `max_rank` | int | 100% | `5` |
| `modifiers_per_rank` | array | 100% | `[{"key": "combat_hp_pct", "value": 2, "mode": "add"}]` |
| `requires_points_in_branch` | int | 100% | `0` |
| `icon` | string | 100% | `"res://assets/icons/talents/warrior_toughness.png"` |

## `titles.json`

Array di **84** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"title_arcane_college_champion"` |
| `name` | loc{it,en} | 100% | `{"it": "Mente con Occhiali in Testa", "en": "Scholar, Glasses on He…` |

## `trials.json`

Array di **8** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"trial_fasting"` |
| `name` | loc{it,en} | 100% | `{"it": "Digiuno", "en": "Fasting"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Nessun cibo: sconfiggi il boss di zona indicato senza mangi…` |
| `rules` | object | 100% | `{"no_food": true}` |
| `tiers` | array | 100% | `[{"tier": "I", "zone_index": 2, "reward": {"modifiers": [{"key": "f…` |
| `unlock` | object | 100% | `{"quest": "main_c5_q5"}` |

Sotto-oggetto `rules`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `rules.no_food` | bool | 12% | `true` |
| `rules.max_gear_tier` | string | 12% | `"tier_zona - 1"` |
| `rules.time_limit_s` | int | 12% | `60` |
| `rules.no_abilities` | bool | 12% | `true` |
| `rules.hp_mult` | float | 12% | `0.25` |
| `rules.forced_disadvantage` | bool | 12% | `true` |
| `rules.no_armor` | bool | 12% | `true` |
| `rules.dungeon` | bool | 12% | `true` |
| `rules.monster_hp_mult` | float | 12% | `1.5` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.quest` | string | 100% | `"main_c5_q5"` |

## `world_bosses.json`

Array di **3** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"wandering_colossus"` |
| `order` | int | 100% | `1` |
| `name` | loc{it,en} | 100% | `{"it": "Colosso Errante", "en": "Wandering Colossus"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Boss mondiale di livello 40: compare ogni 4 ore e resta 30 …` |
| `level` | int | 100% | `40` |
| `boss` | string | 100% | `"wandering_colossus"` |
| `spawn_every_h` | int | 100% | `4` |
| `window_min` | int | 100% | `30` |
| `contribution_tiers` | array | 100% | `[{"id": "bronze", "damage_pct": 15}, {"id": "silver", "damage_pct":…` |
| `rewards` | object | 100% | `{"bronze": [{"item": "crate_bounty", "qty": 1}], "silver": [{"item"…` |
| `simulated_allies_dps_pct_of_hp_per_min` | float | 100% | `2.5` |
| `summon_item` | string | 100% | `"rally_horn"` |

## `xp_table.json`

Oggetto con chiavi: `formula`, `total_xp_for_level`, `mastery_total_for_level`

## `zones.json`

Array di **10** oggetti.

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `id` | string | 100% | `"millbrook"` |
| `order` | int | 100% | `1` |
| `name` | loc{it,en} | 100% | `{"it": "Valle del Mulino", "en": "Millbrook Vale"}` |
| `desc` | loc{it,en} | 100% | `{"it": "Campi dorati e mulini, minacciati da bestie, predoni e da u…` |
| `level_min` | int | 100% | `1` |
| `level_max` | int | 100% | `10` |
| `tier` | int | 100% | `1` |
| `monsters` | array | 100% | `["mud_slime", "thornback_boar", "grey_wolf", "poacher", "animated_s…` |
| `crate` | string | 100% | `"crate_millbrook"` |
| `common_material` | string | 100% | `"mm_rough_fang"` |
| `rare_material` | string | 100% | `"mm_hornet_stinger"` |
| `unlock` | object | 100% | `{"quest": null, "hero_level": 1}` |
| `banner` | string | 100% | `"res://assets/banners/zones/millbrook.png"` |

Sotto-oggetto `unlock`:

| Campo | Tipo | Presenza | Esempio |
|---|---|---|---|
| `unlock.quest` | null, string | 100% | `"main_c2_q1"` |
| `unlock.hero_level` | int | 100% | `1` |

