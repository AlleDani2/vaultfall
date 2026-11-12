"""Scrive i dati generati in data/ (JSON UTF-8, ordinati e stabili) + costanti + tabella XP."""
import json, os, csv
from collections import OrderedDict, Counter
from . import core, tuning
from .reg import R


def _dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
        f.write("\n")


def constants():
    return OrderedDict(
        game_codename=core.GAME_CODENAME, data_version=core.DATA_VERSION,
        level_cap=core.LEVEL_CAP, xp={"base": core.XP_BASE, "growth": core.XP_GROWTH, "formula": "floor(base * growth^L)"},
        tier_levels=core.TIER_LEVELS, xph={"base": core.XPH_BASE, "growth": core.XPH_GROWTH}, gph={"base": core.GPH_BASE, "growth": core.GPH_GROWTH},
        mastery={"cap": core.MASTERY_CAP, "base": core.MASTERY_BASE, "growth": core.MASTERY_GROWTH,
                 "double_per_level_pct": core.MASTERY_DOUBLE_PER_LEVEL, "milestones": core.MASTERY_MILESTONES,
                 "mastered_save_pct": core.MASTERED_SAVE_PCT, "mastered_extra_yield": core.MASTERED_EXTRA_YIELD},
        automation={"stars": core.AUTOMATION_STARS, "perk_double_pick_stars": core.PERK_DOUBLE_PICK_STARS},
        queue={"base_slots": core.QUEUE_BASE_SLOTS, "max_slots": core.QUEUE_MAX_SLOTS, "modes": core.QUEUE_MODES},
        farming={"pet_one_in": core.FARM_PET_ONE_IN, "auto_stars": core.FARM_AUTO_STARS},
        consumables={"feast_slots": core.FEAST_SLOTS, "potion_slots": core.POTION_SLOTS},
        stars={"xp_cap_pct": core.STAR_XP_CAP_PCT, "xp_decay": core.STAR_XP_DECAY, "haste_cap_pct": core.STAR_HASTE_CAP_PCT,
               "haste_decay": core.STAR_HASTE_DECAY, "curve_decay": core.STAR_CURVE_DECAY, "curve_formula": "cap * (1 - decay^stelle)",
               "min_hours_target": core.STAR_MIN_HOURS_TARGET,
               "echo": {"below_50pct_of_record": 3.0, "below_90pct": 2.0, "below_record": 1.5},
               "echo_ratio": {"below_50pct_of_record": core.ECHO_RATIO_BELOW_50, "below_90pct": core.ECHO_RATIO_BELOW_90},
               "stardust_base": core.STARDUST_BASE, "stardust_step": core.STARDUST_STEP},
        prestige={"rite_level": core.PRESTIGE_RITE_LEVEL,
                  # integrazione finale (resoconto 47): il Rito dell'Eroe a livello 75 (Cap. V) lo riportava a 1 e chiudeva
                  # le zone della storia; il Consigliere lo proponeva per primo (livello più alto). L'Eroe resta escluso.
                  "rite_excluded_skills": ["hero"],
                  "respec_free_interval_s": core.PRESTIGE_RESPEC_FREE_INTERVAL_S,
                  "respec_cost_stardust": core.PRESTIGE_RESPEC_COST_STARDUST, "advisor": core.PRESTIGE_ADVISOR, "goals": core.PRESTIGE_GOALS,
                  "trials": core.PRESTIGE_TRIALS},
        eras={"monster_mult": core.ERA_MONSTER_MULT, "reward_add": core.ERA_REWARD_ADD, "rank_stat_mult": core.RANK_STAT_MULT,
              "rank_cap_per_era": core.RANK_CAP_PER_ERA, "rank_min_era": core.RANK_MIN_ERA,
              # G03: costo del Rango in numeri (le formule testuali restano in era_rules.item_rank.cost_formula)
              "rank_cost": {"essence_base": core.RANK_ESSENCE_BASE, "essence_per_rank": core.RANK_ESSENCE_PER_RANK,
                            "gold_per_tier": core.RANK_GOLD_PER_TIER, "gold_rank_div": core.RANK_GOLD_RANK_DIV}},
        estate={"cost_growth": core.ESTATE_COST_GROWTH, "cost_base": core.ESTATE_COST_BASE, "units_per_level": core.ESTATE_UNITS_PER_LEVEL,
                "milestones": core.ESTATE_MILESTONES, "prestige_min_units": core.ESTATE_PRESTIGE_MIN_UNITS, "soci_coeff": core.SOCI_COEFF,
                "soci_divisor": core.SOCI_DIVISOR, "shop_income_cap_gph": core.ESTATE_SHOP_INCOME_CAP_GPH, "socio_bonus_pct": core.SOCIO_BONUS_PCT, "band_cost_growth": core.GPH_GROWTH,
                "milestone_mult": core.ESTATE_MILESTONE_MULT},
        combat={"hit_base": core.HIT_BASE, "hit_min": core.HIT_MIN, "hit_max": core.HIT_MAX, "crit_base": core.CRIT_BASE,
                "crit_dmg_base": core.CRIT_DMG_BASE, "crit_cap": core.CRIT_CAP, "dr_cap": core.DR_CAP,
                "dr_k": {"a": 30.0, "r": 1.0375, "formula": "a * r^livello_attaccante"},
                "triangle": {"beats": core.TRIANGLE, "advantage": core.TRIANGLE_ADV, "disadvantage": core.TRIANGLE_DIS},
                "respawn_s": core.RESPAWN_S, "ttk_target_s": core.TTK_TARGET_S, "rules": core.COMBAT_RULES,
                "sim_assumptions": core.SIM_ASSUMPTIONS,
                "hero": {"attr_base": core.ATTR_BASE, "attr_points_per_level": core.ATTR_POINTS_PER_LEVEL,
                         "class_primary_per_level": core.CLASS_PRIMARY_PER_LEVEL, "vit_per_level_all": core.VIT_PER_LEVEL_ALL,
                         "coef": core.HERO_COEF,
                         "hp_formula": "(hp.base + hp.vit*VIT + hp.level*L + gear_hp) * (1 + hp_pct/100)", "ap_formula": "ap.primary*primario + gear_ap",
                         "acc_formula": "acc.base + acc.level*L + acc.primary*primario + gear_acc", "eva_formula": "eva.base + eva.level*L + eva.dex*DES + gear_eva",
                         "max_hit_formula": "(danno_arma + danno_munizione) * (1 + AP/100) * (1 + dmg_pct/100)",
                         "regen_base_pct_per_s": core.HERO_COEF["regen_pct_per_s"]},
                "monster_types": {k: dict(zip(["hp", "dmg", "acc", "eva", "arm", "xp", "gold", "interval_s"], v)) for k, v in core.MONSTER_TYPES.items()},
                "monster_curves": {"hp": [core.MONSTER_HP_A, core.MONSTER_HP_R], "max_hit": [core.MONSTER_MH_A, core.MONSTER_MH_R],
                                   "acc": [core.MONSTER_ACC_A, core.MONSTER_ACC_B], "eva": [core.MONSTER_EVA_A, core.MONSTER_EVA_B],
                                   "arm": [core.MONSTER_ARM_A, core.MONSTER_ARM_R]},
                "food_heal": [core.FOOD_HEAL_A, core.FOOD_HEAL_R], "gear_growth": core.GEAR_R,
                "weapon_damage_base": core.WEAPON_DMG_A,
                "monster_derivation": {"levels_per_tier": core.MONSTER_LEVELS_PER_TIER, "gold_share": core.MONSTER_GOLD_SHARE,
                                       "gold_min_mult": core.MONSTER_GOLD_MIN_MULT, "gold_max_mult": core.MONSTER_GOLD_MAX_MULT,
                                       "xp_floor": core.MONSTER_XP_FLOOR, "gold_min_floor": core.MONSTER_GOLD_MIN_FLOOR,
                                       "gold_max_floor": core.MONSTER_GOLD_MAX_FLOOR}},
        quality=core.QUALITIES,
        quality_formula="vedi tools/gamedata/core.py::quality_chances",
        quality_chances=core.QUALITY_CHANCES,
        crates={"rarities": core.CRATE_RARITIES, "conditions": core.CONDITIONS, "annalist_chance": core.ANNALIST_CHANCE,
                "pity": {"soft_start": core.PITY_SOFT_START, "soft_step": core.PITY_SOFT_STEP, "hard": core.PITY_HARD},
                "skin_value_fraction_of_gph": core.SKIN_VALUE_FRACTION_OF_GPH, "key_shop_fraction_of_gph": core.KEY_SHOP_FRACTION_OF_GPH,
                "rarity_value_mult": core.RARITY_VALUE_MULT, "key_econ_tier": {str(k): v for k, v in core.KEY_TIER.items()}},
        market={"sell_tax": core.MARKET_SELL_TAX, "skin_sell_tax": core.SKIN_SELL_TAX, "buy_markup": core.MARKET_BUY_MARKUP,
                "demand_half_life_h": core.DEMAND_HALF_LIFE_H, "elasticity_hours": core.DEMAND_ELASTICITY_HOURS},
        offline={"cap_base_h": core.OFFLINE_CAP_BASE_H, "cap_max_h": core.OFFLINE_CAP_MAX_H, "efficiency_pct": 100,
                 "overflow_max_instances": core.OFFLINE_OVERFLOW_MAX_INSTANCES, "min_apply_s": core.OFFLINE_MIN_APPLY_S,
                 "resume_min_gap_s": core.OFFLINE_RESUME_MIN_GAP_S,
                 "safe_fallback_default": core.OFFLINE_SAFE_FALLBACK_DEFAULT},
        time_push=core.TIME_PUSH,
        cozy={"xp_pct": core.COZY_XP_PCT},
        new_game_gift=core.NEW_GAME_GIFT, bank=core.BANK_RULES,
        # numeri di bilanciamento di Tenuta, Spedizioni, Mercenari, Apprendisti (prima nei blocchi PENDING del codice)
        estate_tuning=tuning.ESTATE_TUNING, expedition_tuning=tuning.EXPEDITION_TUNING,
        mercenary_tuning=tuning.MERCENARY_TUNING, apprentice_tuning=tuning.APPRENTICE_TUNING,
        modifier_stacking="valore_finale = base * (1 + somma(add)/100) * prodotto(1 + more_i/100)",
    )


def export_all(root):
    d = os.path.join(root, "data")
    _dump(os.path.join(d, "constants.json"), constants())
    tbl = core.xp_table()
    _dump(os.path.join(d, "xp_table.json"), {"formula": "floor(80 * 1.08^L)", "total_xp_for_level": tbl,
                                             "mastery_total_for_level": [0, 0] + [sum(core.mastery_to_next(m) for m in range(1, k)) for k in range(2, core.MASTERY_CAP + 1)]})
    # oggetti per categoria
    by_cat = OrderedDict()
    for it in R.items.values():
        by_cat.setdefault(it["category"], []).append(it)
    for cat, lst in by_cat.items():
        _dump(os.path.join(d, "items", f"{cat}.json"), lst)
    # azioni per mansione
    by_skill = OrderedDict()
    for a in R.actions.values():
        by_skill.setdefault(a["skill"], []).append(a)
    for sk, lst in by_skill.items():
        _dump(os.path.join(d, "actions", f"{sk}.json"), lst)
    for name, lst in R.tables.items():
        _dump(os.path.join(d, f"{name}.json"), lst)
    counts = OrderedDict(items=len(R.items), actions=len(R.actions))
    counts.update({k: len(v) for k, v in R.tables.items()})
    counts["items_by_category"] = dict(Counter(i["category"] for i in R.items.values()))
    counts["actions_by_skill"] = {k: len(v) for k, v in by_skill.items()}
    _dump(os.path.join(d, "manifest.json"), {"data_version": core.DATA_VERSION, "codename": core.GAME_CODENAME,
                                             "files": sorted(os.path.relpath(os.path.join(dp, f), d).replace("\\", "/")
                                                             for dp, _, fs in os.walk(d) for f in fs if f.endswith(".json") and f != "manifest.json"),
                                             "counts": counts})
    return counts
