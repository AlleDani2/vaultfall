"""
Catalogo UFFICIALE delle chiavi di modificatore. Ogni modificatore nei dati deve usare una chiave di questo elenco.
Formato chiave: "famiglia" oppure "famiglia:ambito" (es. skill_xp_pct:mining, skill_xp_pct:gathering, skill_xp_pct:all).
Regola di cumulo (docs/16): finale = base * (1 + somma(add)/100) * prodotto(1 + more_i/100).
"""
from .core import L
from .reg import R
from .modifier_names import N as NAMES, SCOPE_ALL

SKILL_SCOPES = ["all", "current", "gathering", "artisan", "special", "combat", "woodcutting", "mining", "fishing", "foraging", "trapping",
                "smithing", "woodworking", "tailoring", "cooking", "alchemy", "jewelcrafting", "runecarving", "keysmithing",
                "thievery", "farming", "hero", "bounty"]
ELEMENT_SCOPES = ["all", "fire", "frost", "lightning", "poison", "holy", "shadow"]
GOLD_SCOPES = ["all", "combat", "thievery", "market", "estate", "quests"]
CRATE_SCOPES = ["all", "combat", "skilling", "current"] + [x for x in SKILL_SCOPES if x not in ("all", "current", "combat")]

C = {
    # famiglia: (unità, ambiti ammessi, cap o None, descrizione IT, descrizione EN)
    "skill_xp_pct": ("pct", SKILL_SCOPES, None, "+% XP nella mansione", "+% XP in the skill"),
    "skill_haste_pct": ("pct", SKILL_SCOPES, None, "+% velocità delle azioni (durata = base / (1 + valore/100))", "+% action speed (duration = base / (1 + value/100))"),
    "skill_double_pct": ("pct", SKILL_SCOPES, None, "probabilità % di prodotto doppio (oltre 100% = garantito + probabilità di triplo)", "% chance of double output (above 100% = guaranteed + chance of triple)"),
    "skill_save_pct": ("pct", SKILL_SCOPES, 50, "probabilità % di non consumare gli ingredienti (max 50%)", "% chance not to consume inputs (max 50%)"),
    "skill_secondary_pct": ("pct", SKILL_SCOPES, None, "+% probabilità dei drop secondari", "+% secondary drop chance"),
    "craft_quality_pct": ("pct", SKILL_SCOPES, None, "+% (relativo) alle probabilità di qualità superiore", "+% (relative) to higher-quality chances"),
    "mastery_xp_pct": ("pct", None, None, "+% XP di maestria", "+% mastery XP"),
    "action_haste_pct": ("pct", None, None, "(maestria) +% velocità della singola azione", "(mastery) +% speed of the single action"),
    "action_xp_pct": ("pct", None, None, "(maestria) +% XP della singola azione", "(mastery) +% XP of the single action"),
    "action_secondary_pct": ("pct", None, None, "(maestria) +% drop secondari della singola azione", "(mastery) +% secondary drops of the single action"),
    "action_mastered": ("flag", None, None, "(maestria 50) 10% risparmio input o +1 resa, automazione dell'azione", "(mastery 50) 10% input saving or +1 yield, action automation"),
    "combat_dmg_pct": ("pct", None, None, "+% danno inflitto", "+% damage dealt"),
    "combat_acc_pct": ("pct", None, None, "+% precisione", "+% accuracy"),
    "combat_eva_pct": ("pct", None, None, "+% evasione", "+% evasion"),
    "combat_arm_pct": ("pct", None, None, "+% armatura", "+% armor"),
    "combat_ward_pct": ("pct", None, None, "+% protezione arcana", "+% ward"),
    "combat_defense_pct": ("pct", None, None, "+% armatura E protezione arcana", "+% armor AND ward"),
    "combat_hp_pct": ("pct", None, None, "+% vita massima", "+% max HP"),
    "combat_crit_chance_pct": ("pct_abs", None, 75, "+ punti % di probabilità critica (cap 75%)", "+ % points of crit chance (cap 75%)"),
    "combat_crit_dmg_pct": ("pct_abs", None, None, "+ punti % di danno critico", "+ % points of crit damage"),
    "combat_haste_pct": ("pct", None, None, "+% velocità d'attacco (intervallo = base / (1 + valore/100)); oltre +60% vale metà, massimo +100%", "+% attack speed (interval = base / (1 + value/100)); above +60% counts half, max +100%"),
    "combat_lifesteal_pct": ("pct_abs", None, 25, "% del danno inflitto recuperato come vita (cap 25%)", "% of damage dealt healed (cap 25%)"),
    "combat_regen_hps_pct": ("pct_abs", None, None, "rigenerazione: % vita max al secondo", "regeneration: % max HP per second"),
    "combat_multihit_pct": ("pct_abs", None, 50, "probabilità % di colpire due volte (cap 50%)", "% chance to hit twice (cap 50%)"),
    "combat_dot_dmg_pct": ("pct", None, None, "+% danno nel tempo (sanguinamento, veleno, bruciatura)", "+% damage over time"),
    "combat_thorns_pct": ("pct_abs", None, None, "% del danno subito rinviato all'attaccante", "% of damage taken reflected"),
    "combat_armor_pen_pct": ("pct_abs", None, 60, "% di difese del bersaglio ignorate (cap 60%)", "% of target defenses ignored (cap 60%)"),
    "combat_status_resist_pct": ("pct_abs", None, 90, "% di resistenza a veleno, stordimento, bruciatura", "% resistance to poison, stun, burn"),
    "combat_heal_received_pct": ("pct", None, None, "+% cure ricevute", "+% healing received"),
    "combat_resource_regen_pct": ("pct", None, None, "+% rigenerazione di Furia/Concentrazione/Mana", "+% Fury/Focus/Mana generation"),
    "combat_dmg_taken_pct": ("pct", None, None, "variazione % del danno subito (negativo = riduzione)", "% change in damage taken (negative = reduction)"),
    "combat_dmg_vs_bounty_pct": ("pct", None, None, "+% danno contro i bersagli della taglia attiva", "+% damage against active bounty targets"),
    "combat_revive_once": ("flag", None, 1, "una volta per combattimento torni al 30% di vita invece di morire", "once per fight return to 30% HP instead of dying"),
    "target_dmg_taken_pct": ("pct", None, None, "(debuff) +% danno subito dal bersaglio", "(debuff) +% damage taken by target"),
    "summon_dmg_pct": ("pct", None, None, "+% danno dei servitori/compagni evocati", "+% damage of summons/companions"),
    "element_dmg_pct": ("pct", ELEMENT_SCOPES, None, "+% danno dell'elemento", "+% elemental damage"),
    "food_heal_pct": ("pct", None, None, "+% cura del cibo", "+% food healing"),
    "potion_charges_pct": ("pct", None, None, "+% cariche delle pozioni", "+% potion charges"),
    "ammo_save_pct": ("pct_abs", None, 80, "% di munizioni recuperate (cap 80%)", "% of ammo saved (cap 80%)"),
    "monster_drop_pct": ("pct", None, None, "+% probabilità dei drop dei mostri (non casse, non famigli)", "+% monster drop chance (not crates, not pets)"),
    "dungeon_loot_pct": ("pct", ["all"], None, "+% bottino del dungeon (ambito: id dungeon o all)", "+% dungeon loot (scope: dungeon id or all)"),
    "dungeon_speed_pct": ("pct", ["all"], None, "+% velocità nel dungeon (ambito: id dungeon)", "+% dungeon speed (scope: dungeon id)"),
    "gold_gain_pct": ("pct", GOLD_SCOPES, None, "+% oro guadagnato dalla fonte", "+% gold from the source"),
    "crate_find_pct": ("pct", CRATE_SCOPES, 200, "+% probabilità di trovare casse (cap +200%)", "+% crate find chance (cap +200%)"),
    "pet_chance_pct": ("pct", None, None, "+% probabilità di famigli", "+% familiar chance"),
    "key_craft_save_pct": ("pct_abs", None, 50, "% di probabilità di non consumare materiali forgiando chiavi (cap 50%)", "% chance not to consume materials when forging keys (cap 50%)"),
    "annalist_chance_abs_pct": ("pct_abs", None, 10, "+ punti % di probabilità Annalista", "+ % points of Annalist chance"),
    "pity_soft_start_reduction": ("abs", None, 100, "anticipa la pity morbida di N aperture", "starts soft pity N openings earlier"),
    "shards_pct": ("pct", None, None, "+% Schegge dalla fusione", "+% Shards from melting"),
    "refine_cost_reduction_pct": ("pct_abs", None, 50, "-% costo di Affinatura (cap 50%)", "-% Refinery cost (cap 50%)"),
    "market_sell_pct": ("pct", None, 50, "+% prezzo di vendita al mercato (cap 50%)", "+% market sell price (cap 50%)"),
    "market_tax_reduction_pct": ("pct_abs", None, 80, "-% della tassa di mercato (cap 80%)", "-% of market tax (cap 80%)"),
    "estate_prod_pct": ("pct", None, None, "+% produzione della Tenuta", "+% Estate production"),
    "estate_cost_reduction_pct": ("pct_abs", None, 50, "-% costo degli edifici (cap 50%)", "-% building cost (cap 50%)"),
    "estate_auto_collect": ("flag", None, 1, "raccolta automatica della Tenuta", "Estate auto-collect"),
    "soci_gain_pct": ("pct", None, None, "+% Soci dalla Rifondazione", "+% Partners from Refounding"),
    "merc_power_pct": ("pct", None, None, "+% potere dei mercenari", "+% mercenary power"),
    "expedition_speed_pct": ("pct", None, 50, "-% durata delle spedizioni (cap 50%)", "-% expedition duration (cap 50%)"),
    "faction_rep_pct": ("pct", None, None, "+% reputazione con le fazioni", "+% faction reputation"),
    "orders_slots": ("abs", None, 4, "+ posti nella bacheca delle Commesse", "+ Orders board slots"),
    "bank_slots": ("abs", None, None, "+ spazi nel Deposito", "+ bank slots"),
    "relic_slots": ("abs", None, 2, "+ reliquiari equipaggiabili", "+ relic slots"),
    "apprentice_slots": ("abs", None, 2, "+ apprendisti (oltre a quelli dell'Accademia, max 5 totali)", "+ apprentices (beyond the Academy, max 5 total)"),
    "action_queue_slots": ("abs", None, None, "+ posti nella coda delle azioni", "+ action queue slots"),
    "auto_sell_unlock": ("flag", None, 1, "sblocca regole di vendita automatica", "unlocks auto-sell rules"),
    "offline_cap_hours": ("abs", None, 12, "+ ore di progresso offline (totale max 24)", "+ offline progress hours (max 24 total)"),
    "offline_efficiency_pct": ("pct", None, 0, "riservato (l'efficienza offline è sempre 100%)", "reserved (offline efficiency is always 100%)"),
    "echo_mult_pct": ("pct", None, None, "+% al moltiplicatore Eco (recupero dopo una Stella)", "+% to the Echo multiplier (catch-up after a Star)"),
    "stardust_gain_pct": ("pct", None, None, "+% Polvere Stellare", "+% Stardust"),
    "xp_tome_pct": ("pct", None, None, "+% XP dai Tomi", "+% XP from Tomes"),
    "rift_shard_pct": ("pct", None, None, "+% Frammenti di Breccia", "+% Rift Shards"),
    "bounty_marks_pct": ("pct", None, None, "+% Marchi di Taglia", "+% Bounty Marks"),
    "bounty_wanted_chance_pct": ("pct", None, None, "+% probabilità di Ricercati", "+% Wanted target chance"),
    "thievery_success_pct": ("pct_abs", None, None, "+ punti % di successo nel Borseggio (cap totale 98%)", "+ % points of Thievery success (total cap 98%)"),
    "thievery_stun_reduction_pct": ("pct_abs", None, 75, "-% durata dello stordimento da borseggio fallito", "-% stun duration on failed Thievery"),
}


def _scope_kind(fam, scopes):
    """Tipo di ambiti di una famiglia (per il testo di «tutto»): skill, crate, gold, element, dungeon o None."""
    if fam in ("dungeon_loot_pct", "dungeon_speed_pct"):
        return "dungeon"
    if scopes is None:
        return None
    if scopes is CRATE_SCOPES:
        return "crate"
    if scopes is GOLD_SCOPES:
        return "gold"
    if scopes is ELEMENT_SCOPES:
        return "element"
    return "skill"


def build_catalog():
    out = []
    for fam, (unit, scopes, cap, it, en) in C.items():
        cat, n_it, n_en, b_it, b_en = NAMES[fam]
        kind = _scope_kind(fam, scopes)
        out.append({"family": fam, "unit": unit, "scopes": scopes, "cap": cap, "desc": L(it, en),
                    "cat": cat, "name": L(n_it, n_en), "blurb": L(b_it, b_en),
                    "scope_all": L(*SCOPE_ALL[kind]) if kind else None})
    R.tables["modifier_catalog"] = out


def is_valid(key: str, dungeon_ids=()) -> bool:
    fam, _, scope = key.partition(":")
    if fam not in C:
        return False
    scopes = C[fam][1]
    if not scope:
        return True
    if fam in ("dungeon_loot_pct", "dungeon_speed_pct"):
        return scope == "all" or scope in dungeon_ids
    return scopes is not None and scope in scopes
