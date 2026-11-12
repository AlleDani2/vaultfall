"""
VAULTFALL — costanti e formule di base.
UNICA fonte di verità per i numeri: il gioco (GDScript) deve replicare ESATTAMENTE
queste formule (vedi docs/19_bilanciamento.md). Se cambi un valore qui,
rigenera i dati (python tools/generate_data.py) e rilancia validate + balance_sim.
Arrotondamenti: SEMPRE con rhalf()/rdec() (metà per eccesso, come round() di GDScript), MAI con round() di Python
(che arrotonda le metà al pari: 2.5 -> 2) per avere gli stessi numeri nel gioco e nei valori di riferimento.
"""
import math


# Interi "sicuri" (FIX-COMBATTIMENTO, QA4 #12): GDScript ha interi a 64 bit e float a 53 bit di mantissa, Python interi
# illimitati. Per avere gli stessi numeri in entrambi, ogni intero derivato da un float satura a +-2^62 (NaN -> 0) e le
# potenze che traboccano danno inf (come pow() di GDScript) invece di OverflowError. Fino a 2^62 i due lati coincidono esattamente (int del float); oltre, nessun dato reale.
INT_LIMIT = 2 ** 62


def _sat(v: float) -> int:
    if v != v:
        return 0
    if v >= INT_LIMIT:
        return INT_LIMIT
    if v <= -INT_LIMIT:
        return -INT_LIMIT
    return int(v)


def fpow(a: float, b: float) -> float:
    """a ** b come pow() di GDScript: inf invece di OverflowError."""
    try:
        return float(a) ** b
    except OverflowError:
        return math.inf


def ifloor(x: float) -> int:
    """floor() intero saturato a +-2^62 (NaN -> 0)."""
    if x != x:
        return 0
    if abs(x) >= INT_LIMIT:
        return _sat(x)
    return int(math.floor(x))


def rhalf(x: float) -> int:
    """Arrotonda all'intero con le metà per eccesso (x >= 0), uguale a round() di GDScript per i valori positivi.
    Satura a +-2^62 (inf compreso); NaN -> 0."""
    if x != x:
        return 0
    if abs(x) >= INT_LIMIT:
        return _sat(x)
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def rdec(x: float, nd: int) -> float:
    """Arrotonda a nd decimali con le metà per eccesso (equivale a snappedf(x, 10^-nd) di GDScript)."""
    f = 10 ** nd
    return rhalf(x * f) / f

GAME_CODENAME = "VAULTFALL"          # titolo di lavoro (vedi docs/01)
DATA_VERSION = 1                     # incrementare a ogni cambio di schema

# ----------------------------------------------------------------------------
# LIVELLI E XP
# ----------------------------------------------------------------------------
LEVEL_CAP = 100
XP_BASE = 80.0
XP_GROWTH = 1.08

def xp_to_next(level: int) -> int:
    """XP necessari per passare da `level` a `level+1` (1..99)."""
    return ifloor(XP_BASE * fpow(XP_GROWTH, level))

def xp_table():
    """Lista cumulativa: xp_total[L] = XP totali per ESSERE al livello L (L=1 -> 0)."""
    tot = [0, 0]
    for L in range(1, LEVEL_CAP):
        tot.append(tot[-1] + xp_to_next(L))
    return tot  # indice = livello

# Tier di contenuto: ogni mansione sblocca un tier a questi livelli
TIER_LEVELS = [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95]
N_TIERS = len(TIER_LEVELS)  # 11

def tier_of_level(level: int) -> int:
    t = 1
    for i, l in enumerate(TIER_LEVELS):
        if level >= l:
            t = i + 1
    return t

# XP/ora "di riferimento" dell'azione migliore del tier t (senza bonus)
XPH_BASE = 8000.0
XPH_GROWTH = 1.25

def xph(tier: int) -> float:
    return XPH_BASE * fpow(XPH_GROWTH, tier - 1)

# Oro/ora "di riferimento" al tier t (vendendo grezzi / combattendo)
GPH_BASE = 2000.0
GPH_GROWTH = 1.45

def gph(tier: int) -> float:
    return GPH_BASE * fpow(GPH_GROWTH, tier - 1)

# Valore grezzo: un'azione di raccolta vale gph(t) * tempo / 3600
def raw_value(tier: int, action_time_s: float) -> int:
    return max(1, rhalf(gph(tier) * action_time_s / 3600.0))

# ----------------------------------------------------------------------------
# MAESTRIA (per singola azione)
# ----------------------------------------------------------------------------
MASTERY_CAP = 50
MASTERY_BASE = 60.0    # "secondi" di XP maestria al livello 1
MASTERY_GROWTH = 1.09

def mastery_to_next(m: int) -> int:
    return ifloor(MASTERY_BASE * fpow(MASTERY_GROWTH, m))

# XP maestria guadagnata per azione = durata base dell'azione in secondi (x modificatori)
MASTERY_MILESTONES = {
    10: {"key": "action_haste_pct", "value": 5},
    20: {"key": "action_xp_pct", "value": 5},
    30: {"key": "action_haste_pct", "value": 10},
    40: {"key": "action_secondary_pct", "value": 25},
    50: {"key": "action_mastered", "value": 1},  # 10% risparmio input / +1 resa, sblocca automazione
}
MASTERY_DOUBLE_PER_LEVEL = 0.5   # +0,5% doppio per livello di maestria (max +25%)
# Padronanza (maestria 50, docs/04 §6): 10% di non consumare gli ingredienti (produzione) o +1 resa (raccolta);
# l'azione padroneggiata riparte da sola quando tornano gli ingredienti (automazione).
MASTERED_SAVE_PCT = 10.0
MASTERED_EXTRA_YIELD = 1

# ----------------------------------------------------------------------------
# PRESTIGIO DI MANSIONE (STELLE)
# ----------------------------------------------------------------------------
# Regola di stabilità (docs/02 §4, docs/13 §2): un bonus che accelera la stella successiva con costo costante
# produce una "fuga" (tempo per stella che tende a zero). Per questo l'XP della mansione cresce ad ASINTOTO.
STAR_XP_CAP_PCT = 60           # XP nella mansione (bucket "more"): 60 * (1 - 0.92^stelle) -> asintoto +60% (era 100: D-8, 23/10/2026)
STAR_XP_DECAY = 0.92
STAR_HASTE_CAP_PCT = 25        # velocità: 25 * (1 - 0.9^stelle) -> asintoto +25% (era 30: D-8)
STAR_HASTE_DECAY = 0.9
STAR_CURVE_DECAY = 0.95        # bonus extra "a curva": cap * (1 - 0.95^stelle)
STAR_MIN_HOURS_TARGET = 6.0    # il simulatore verifica che una stella non scenda mai sotto queste ore (mansione tipica)

def star_curve(cap: float, decay: float, stars: int) -> float:
    return cap * (1 - fpow(decay, stars))

def star_xp_pct(stars: int) -> float:
    return star_curve(STAR_XP_CAP_PCT, STAR_XP_DECAY, stars)

def star_haste_pct(stars: int) -> float:
    return star_curve(STAR_HASTE_CAP_PCT, STAR_HASTE_DECAY, stars)

STARDUST_BASE, STARDUST_STEP = 10, 2    # Polvere Stellare della stella n: base + passo * (n - 1)

def stardust_for_star(star_index: int) -> int:
    """Polvere Stellare ottenuta conseguendo la stella numero star_index (1,2,3...)."""
    return STARDUST_BASE + STARDUST_STEP * (star_index - 1)

# Rito (mini-prestigio precoce, audit 03 #2): UNA volta per mansione, a livello >= PRESTIGE_RITE_LEVEL, vale come una Stella
# (stessi bonus e Polvere della stella n) ma si fa molto prima di 100. Non e' una fuga: al massimo una per mansione.
# Livello 50 = 1,3-2,8 h di sola mansione (balance_sim §10), qualche ora di partita: il primo reset arriva nella prima
# giornata (R4 §1). Era 75 (ora 5-20): chi seguiva la storia (mansioni <= 55) non faceva mai un Rito (QA2, FIX-MEDIO).
PRESTIGE_RITE_LEVEL = 50
PRESTIGE_RESPEC_FREE_INTERVAL_S = 7 * 86400   # rimborso totale delle Costellazioni gratuito una volta ogni 7 giorni (docs/13 §3)
PRESTIGE_RESPEC_COST_STARDUST = 50            # poi costa 50 Polvere
PRESTIGE_ADVISOR = {"refound_min_new_partners": 1, "refound_min_ratio": 0.5}   # il Consigliere propone la Rifondazione se i nuovi Soci >= 50% di quelli posseduti
# Grandi Obiettivi (audit 03 #4): premi forti in Polvere tra ora 5 e 20; si riscuotono da soli, una volta.
# Ere (docs/13 §4): la Polvere del Custode ("5 x era") si paga SOLO alla prima uccisione di ogni Era (ripetere il Custode non e' una
# fonte di Polvere: altrimenti piu' danno -> piu' Custodi -> piu' Polvere -> Costellazioni di danno = un anello, regola 9). Percentuale
# della Polvere per le uccisioni successive.
PRESTIGE_WARDEN_REPEAT_DUST_PCT = 0
# Prove del Custode (docs/13 §6): si combattono SEMPRE nell'Era I (le restrizioni, non l'Era, sono la sfida); "armatura" = questi slot.
PRESTIGE_TRIALS = {"era": 1, "armor_slots": ["helm", "body", "gloves", "legs", "boots", "offhand"]}
# Regole per grado che sovrascrivono quelle della Prova (balance_sim §11, superabilita'): il Digiuno concede poche porzioni ai gradi
# alti (boss che fanno piu' danno della vita) e il tempo di "Contro il Tempo" cresce con la durata dei boss. Grado = 1..5.
TRIAL_TIER_RULES = {
    "fasting": {4: {"no_food": False, "max_food": 3}, 5: {"no_food": False, "max_food": 6}},
    "race": {3: {"time_limit_s": 90}, 4: {"time_limit_s": 105}, 5: {"time_limit_s": 125}},
    # FIX-COMBATTIMENTO (QA4 #12): Vetro V (boss della zona 10 con vita x0,25) era impossibile per tutte (P(morte) 0,76-1,0, poi
    # 0,43-0,89 col modello per tipo di colpo): al grado V la vita resta al 35%.
    "glass": {5: {"hp_mult": 0.35}},
}
PRESTIGE_GOALS = [
    {"id": "goal_rite", "type": "rites_done", "qty": 1, "stardust": 20},
    {"id": "goal_first_star", "type": "stars_total", "qty": 1, "stardust": 30},
    {"id": "goal_nodes_10", "type": "constellation_levels", "qty": 10, "stardust": 25},
    {"id": "goal_stars_5", "type": "stars_total", "qty": 5, "stardust": 40},
    {"id": "goal_partner", "type": "partners", "qty": 1, "stardust": 30},
    # audit 42 (buco di contenuto, ore 15-26): premi a metà strada, sugli stessi tipi dei primi cinque
    {"id": "goal_nodes_30", "type": "constellation_levels", "qty": 30, "stardust": 40},
    {"id": "goal_stars_10", "type": "stars_total", "qty": 10, "stardust": 60},
    {"id": "goal_stars_20", "type": "stars_total", "qty": 20, "stardust": 80},
]

# Eco (catch-up) quando livello attuale < record
ECHO_RATIO_BELOW_50 = 0.5      # soglie del rapporto livello/record
ECHO_RATIO_BELOW_90 = 0.9

def echo_multiplier(level: int, record: int) -> float:
    if record <= level:
        return 1.0
    ratio = level / record
    if ratio < ECHO_RATIO_BELOW_50:
        return 3.0
    if ratio < ECHO_RATIO_BELOW_90:
        return 2.0
    return 1.5

# ----------------------------------------------------------------------------
# ERE DEL MONDO (prestigio di combattimento, infinito)
# ----------------------------------------------------------------------------
ERA_MONSTER_MULT = 1.35       # per era: tutte le statistiche dei mostri in ERA_MONSTER_STATS
ERA_MONSTER_STATS = ("hp", "max_hit", "accuracy", "evasion", "armor", "ward")
ERA_REWARD_ADD = 0.30         # +30% XP e oro per era oltre la prima
RANK_STAT_MULT = 1.04         # +4% per Rango dell'oggetto (moltiplicativo) SOLO sulle statistiche in RANK_APPLIES_TO
# Il Rango NON tocca attributi (FOR/DES/INT/VIT), potenza d'attacco, critico e modificatori: scalare sia il danno
# dell'arma sia la potenza d'attacco darebbe una crescita "al quadrato" (1,04^2r) e l'eroe supererebbe le Ere
# senza sforzo (verificato in reports/balance_report.md §9).
RANK_APPLIES_TO = ("damage", "armor", "ward", "hp", "accuracy", "evasion")
RANK_CAP_PER_ERA = 12         # servono ~8 ranghi per Era (1,04^7,65 = 1,35): 12 lascia margine
# Costo per salire AL rango r (docs/07 §5): Essenza d'Era ceil(base + per_rank·r), oro per_tier·tier·(1 + r/rank_div).
# I numeri sono esportati in constants.json (eras.rank_cost) e portati 1:1 in Formulas.rank_essence_cost/rank_gold_cost (G03).
RANK_ESSENCE_BASE = 2
RANK_ESSENCE_PER_RANK = 0.5
RANK_GOLD_PER_TIER = 250
RANK_GOLD_RANK_DIV = 10
RANK_MIN_ERA = 2              # i Ranghi si comprano dall'Era II (docs/07 §5; l'Essenza si accumula già nell'Era I)
RANK_ESSENCE_FORMULA = f"ceil({RANK_ESSENCE_BASE} + {RANK_ESSENCE_PER_RANK} * rango)"
RANK_GOLD_FORMULA = f"{RANK_GOLD_PER_TIER} * tier * (1 + rango / {RANK_GOLD_RANK_DIV})"
ERA_ESSENCE_QTY_FORMULA = "era"   # quantità per drop; si accumula anche nell'Era I (i ranghi si applicano dall'Era II)
ERA_ESSENCE_DROP = {"elite": 0.25, "boss": 1.0, "dungeon_boss": 3.0, "raid_boss": 10.0}

def era_monster_mult(era: int) -> float:
    return fpow(ERA_MONSTER_MULT, era - 1)

def era_reward_mult(era: int) -> float:
    return 1 + ERA_REWARD_ADD * (era - 1)


def rank_essence_cost(r: int) -> int:
    """Essenza d'Era per salire al rango r (r >= 1)."""
    return math.ceil(RANK_ESSENCE_BASE + RANK_ESSENCE_PER_RANK * r - 1e-9)


def rank_gold_cost(tier: int, r: int) -> int:
    """Oro per salire al rango r un oggetto di tier `tier` (intero: 250·t + 25·t·r)."""
    return int(round(RANK_GOLD_PER_TIER * tier * (1 + r / RANK_GOLD_RANK_DIV)))

# ----------------------------------------------------------------------------
# TENUTA (tycoon) — Soci (prestigio della tenuta)
# ----------------------------------------------------------------------------
ESTATE_COST_GROWTH = 1.11
ESTATE_COST_BASE = 40.0            # oro per il primo livello (x fattore tier della banda)
ESTATE_UNITS_PER_LEVEL = 30.0      # unità/ora per livello di un edificio produttore
ESTATE_MILESTONES = [10, 25, 50, 100, 150, 200, 300, 400, 500, 750, 1000]
ESTATE_PRESTIGE_MIN_UNITS = 30_000 # Punti Prosperità per la prima Rifondazione (FIX-MEDIO: 45.000 -> 30.000, il bot QA2 la faceva dopo ~22 h di Tenuta)
ESTATE_SHOP_INCOME_CAP_GPH = 0.6  # D-8 (23/10/2026): la Bottega paga al massimo 0,6 × gph(tier) ogni ora (era 0,8; QA3 somma delle fonti); il resto produce solo Prosperità
SOCI_COEFF = 15.0
SOCI_DIVISOR = 10_000.0
SOCIO_BONUS_PCT = 2.0

def soci_total(lifetime_units: float) -> int:
    """Soci totali in funzione dei Punti Prosperità (unità prodotte a vita dalla Tenuta)."""
    return ifloor(SOCI_COEFF * math.sqrt(max(0.0, lifetime_units) / SOCI_DIVISOR))

def estate_units_per_hour(level: int) -> float:
    return ESTATE_UNITS_PER_LEVEL * level * estate_milestone_mult(level) if level > 0 else 0.0

def estate_cost_gold(level: int, band_tier: int) -> int:
    return round_nice(ESTATE_COST_BASE * fpow(ESTATE_COST_GROWTH, level) * fpow(GPH_GROWTH, band_tier - 1))

ESTATE_MILESTONE_MULT = 2    # ogni traguardo raddoppia la produzione

def estate_milestone_mult(level: int) -> int:
    return ESTATE_MILESTONE_MULT ** sum(1 for m in ESTATE_MILESTONES if level >= m)

# ----------------------------------------------------------------------------
# COMBATTIMENTO — formule (documentate in docs/05)
# ----------------------------------------------------------------------------
HIT_BASE = 0.75
HIT_MIN, HIT_MAX = 0.05, 0.98
CRIT_BASE = 0.05
CRIT_DMG_BASE = 1.50
CRIT_CAP = 0.75
DR_CAP = 0.85
TRIANGLE_ADV = 1.15
TRIANGLE_DIS = 0.85
TRIANGLE = {"melee": "ranged", "ranged": "arcane", "arcane": "melee"}  # chiave batte valore
RESPAWN_S = 1.5
# Regole di combattimento di docs/05 che il codice NON deve inventare (lette da constants.json -> combat.rules)
COMBAT_RULES = {
    "respawn_min_s": 0.5,                    # la ricomparsa non scende sotto 0,5 s con nessun bonus
    "element_weak_mult": 1.25,               # debolezza del mostro all'elemento
    "element_resist_mult": 0.75,             # resistenza del mostro all'elemento
    "food_slots": 3,
    "manual_eat_below_pct": 20,              # senza Cinturone: si mangia a mano sotto il 20% di vita...
    "emergency_eat_below_pct": 10,           # ...o in automatico al 10%
    "emergency_eat_waste_pct": 50,           # con il 50% di spreco della cura
    "death_restart_delay_s": 10,
    "death_wounded_stat_pct": -10,           # debuff "Ferito": -10% a tutte le statistiche
    "death_wounded_duration_s": 300,
    "death_item_loss": False,                # nessun oggetto perso (modalità Estremo a parte, docs/05 §7)
    # SHARK 1.0 #6 (regola 2): numeri che stavano nel GDScript (CombatSim)
    "revive_once_hp_pct": 30,                # «Seconda possibilita'» (modificatore revive_once): l'eroe torna al 30% della vita massima
    "enemy_hp_floor_pct": 5,                 # la vita di un nemico appena creato non scende sotto il 5% della sua vita base scalata
    # Q97 (QA82, primo combattimento): un eroe senza equipaggiamento moriva ogni ~50 s e ogni morte costava 10 s + 5 minuti di
    # Ferito. Fino a `until_level` (come il cambio classe gratuito) l'attesa e il Ferito sono ridotti: la difficolta' dello
    # scontro non cambia, cambia solo il costo dell'errore mentre si impara.
    "novice": {"until_level": 10, "restart_delay_s": 3, "wounded_duration_s": 60},
    "multihit_cap_pct": 50, "lifesteal_cap_pct": 25,
    "dot_tick_s": 1.0,
    "ammo_arrow_recovery_pct": 20,
    "ammo_recovery_max_pct": 90,             # tetto COMBINATO (recupero base frecce + ammo_save_pct): resta sempre un 10% di consumo (QA82 Q82-2)
    "raid_phase_hp_pct": [66, 33],
    # --- M7 (COMBAT-2): valori che prima stavano in CombatSystem.PENDING o nei testi dei documenti
    "ability_slots": 4,                      # docs/05 §5: fino a 4 abilità equipaggiate in lista di priorità
    # MURI (BOT-05): gratis fino a Eroe 10 e poi 5.000 oro/livello lasciavano chi provava una classe dopo il 10 bloccato per ore.
    # Ora gratis fino a 20, poi 300 oro/livello (Eroe 50: 15.000), ricarica 10 minuti, e il ritorno alla classe lasciata e' gratis
    # entro `trial_return_s` di gioco (prova senza rischio: se la nuova classe non piace si torna indietro senza pagare).
    "class_change": {"free_until_level": 20, "gold_per_level": 300, "cooldown_s": 600, "trial_return_s": 7200},   # docs/06 R-CL-1
    "talents": {"hero_levels_per_point": 2, "max_level_points": 50, "max_star_points": 25,  # docs/06 §4
                "respec_free_until_level": 20, "respec_gold_per_level": 1000},
    "bounty_xp_per_kill_mult": 0.6,          # docs/05 §11: XP Taglie per uccisione = 60% dell'XP del mostro
    "day_s": 86400,                          # giorno di gioco (cambi gratuiti della Bacheca)
    # FIX-COMBATTIMENTO (QA4 #5): XP ridotta sui mostri molto sotto il livello dell'Eroe. Con vita x1,0575 e XP x1,0225 per
    # livello i mostri piu' bassi rendevano sempre di piu' all'ora: per ~9 livelli conveniva restare nella zona vecchia.
    # Oltre `grace_levels` di distacco l'XP cala del `pct_per_level` per livello (minimo `min_pct`); i mostri dal livello
    # `exempt_from_level` (ultima zona, farm delle Ere al livello massimo) non sono toccati.
    "overlevel_xp": {"grace_levels": 3, "pct_per_level": 6, "min_pct": 25, "exempt_from_level": 91},
    # FIX-COMBATTIMENTO (QA4 #5, R2 pacchetto C): Imboscata. Nelle zone, dal livello minimo, un mostro normale compare come
    # elite (vita x3, danno x1,15) con il 2% per comparsa e almeno 3 minuti tra due; XP e oro x2. Non uccide: quando sarebbe
    # letale, o sotto il 25% di vita senza cibo, si ritira (si perde solo il premio). Offline: valore atteso.
    "ambush": {"chance_pct": 2.0, "min_interval_s": 180, "hp_mult": 3.0, "dmg_mult": 1.15, "reward_mult": 2.0,
               "min_hero_level": 10, "retreat_hp_pct": 25},
    # CORSA (resoconto 91, R1 tema 1): tetto della velocità d'attacco. Oltre +`soft_pct`% di combat_haste_pct (somma degli add)
    # ogni punto vale `soft_slope`; l'effetto non supera mai +`hard_pct`% (intervallo minimo = metà di quello dell'arma).
    # Oggi le fonti normali arrivano a +30-50%: il tetto protegge Ere, Corsa e combinazioni di reliquie, non cambia il gioco medio.
    "haste_cap": {"soft_pct": 60, "soft_slope": 0.5, "hard_pct": 100},
}


def effective_haste_pct(add_pct: float) -> float:
    """combat_haste_pct effettivo (punti %) dalla somma degli add: lineare fino a soft_pct, poi soft_slope, tetto hard_pct.
    I valori negativi (rallentamenti) passano invariati. NaN -> 0."""
    if add_pct != add_pct:
        return 0.0
    h = COMBAT_RULES["haste_cap"]
    if add_pct <= h["soft_pct"]:
        return float(add_pct)
    return float(min(h["hard_pct"], h["soft_pct"] + (add_pct - h["soft_pct"]) * h["soft_slope"]))


def overlevel_xp_mult(hero_level: int, monster_level: int) -> float:
    """Moltiplicatore dell'XP di un mostro di livello `monster_level` per un Eroe di livello `hero_level` (1.0 = pieno)."""
    o = COMBAT_RULES["overlevel_xp"]
    if monster_level >= o["exempt_from_level"]:
        return 1.0
    gap = hero_level - monster_level - o["grace_levels"]
    if gap <= 0:
        return 1.0
    return max(o["min_pct"] / 100.0, 1.0 - gap * o["pct_per_level"] / 100.0)
# Ipotesi del simulatore di bilanciamento (NON regole di gioco): servono a tools/balance_sim.py
SIM_ASSUMPTIONS = {
    "ability_dps_factor": 1.25,              # le abilità aggiungono ~25% al DPS degli attacchi base (obiettivo di design)
    "monster_avg_hit_ratio": 0.70,           # colpo medio del mostro = 70% del colpo massimo
}

def hit_chance(acc: float, eva: float) -> float:
    # guardie (QA4 #12): NaN o precisione <= 0 -> minimo; evasione <= 0 -> massimo; inf/inf -> minimo
    if acc != acc or eva != eva:
        return HIT_MIN
    if eva <= 0:
        return HIT_MAX
    if acc <= 0:
        return HIT_MIN
    r = acc / eva
    if r != r:
        return HIT_MIN
    return max(HIT_MIN, min(HIT_MAX, HIT_BASE * math.sqrt(r)))

def dr_k(monster_level: float) -> float:
    """Costante K della riduzione danni: DR = ARM / (ARM + K(livello attaccante))."""
    return 30.0 * fpow(1.0375, monster_level)

def damage_reduction(armor: float, attacker_level: float) -> float:
    if armor != armor or armor <= 0:
        return 0.0
    if armor == math.inf:
        return DR_CAP
    return min(DR_CAP, armor / (armor + dr_k(attacker_level)))

def triangle_mult(att_style: str, def_style: str) -> float:
    if not att_style or not def_style:
        return 1.0
    if TRIANGLE.get(att_style) == def_style:
        return TRIANGLE_ADV
    if TRIANGLE.get(def_style) == att_style:
        return TRIANGLE_DIS
    return 1.0

# Attributi del personaggio per livello (con allocazione automatica "standard")
ATTR_BASE = 5
ATTR_POINTS_PER_LEVEL = 3
CLASS_PRIMARY_PER_LEVEL = 1.0
VIT_PER_LEVEL_ALL = 0.5

HERO_COEF = {
    "hp": {"base": 60, "vit": 10, "level": 5},
    "ap": {"primary": 1.5},
    "acc": {"base": 20, "level": 3, "primary": 1.0},
    "eva": {"base": 10, "level": 2, "dex": 0.8},
    "regen_pct_per_s": 0.2,
}

def hero_hp(vit: float, level: int, gear_hp: float, hp_pct: float = 0.0) -> float:
    c = HERO_COEF["hp"]
    return (c["base"] + c["vit"] * vit + c["level"] * level + gear_hp) * (1 + hp_pct / 100)

def hero_ap(primary: float, gear_ap: float) -> float:
    return HERO_COEF["ap"]["primary"] * primary + gear_ap

def hero_acc(level: int, primary: float, gear_acc: float) -> float:
    c = HERO_COEF["acc"]
    return c["base"] + c["level"] * level + c["primary"] * primary + gear_acc

def hero_eva(level: int, des: float, gear_eva: float) -> float:
    c = HERO_COEF["eva"]
    return c["base"] + c["level"] * level + c["dex"] * des + gear_eva

def max_hit(weapon_dmg: float, ap: float, dmg_pct: float = 0.0) -> float:
    return weapon_dmg * (1 + ap / 100) * (1 + dmg_pct / 100)

# Mostri: statistiche da livello (tipo: normal/elite/boss/dungeon_boss/raid_boss/world_boss)
MONSTER_TYPES = {
    #               hp     dmg   acc   eva   arm   xp    gold  interval
    "normal":      (1.0,  1.00, 1.00, 1.00, 1.00, 1.0,  1.0,  2.8),
    "elite":       (3.0,  1.25, 1.10, 1.10, 1.20, 3.2,  3.0,  2.6),
    "boss":        (10.0, 1.60, 1.15, 1.10, 1.40, 12.0, 12.0, 3.0),
    "dungeon_boss": (14.0, 1.75, 1.20, 1.15, 1.50, 18.0, 18.0, 3.0),
    "raid_boss":   (45.0, 2.10, 1.30, 1.20, 1.70, 60.0, 60.0, 3.2),
    "world_boss":  (400.0, 1.50, 1.20, 1.00, 1.50, 80.0, 80.0, 3.5),
}
MONSTER_HP_A, MONSTER_HP_R = 23.5, 1.0575
MONSTER_MH_A, MONSTER_MH_R = 13.5, 1.0364
MONSTER_ACC_A, MONSTER_ACC_B = 20.0, 7.5
MONSTER_EVA_A, MONSTER_EVA_B = 15.0, 6.66
MONSTER_ARM_A, MONSTER_ARM_R = 4.0, 1.036   # armatura/ward dei mostri (riduce il danno del giocatore)
TTK_TARGET_S = 8.0

# Derivazione di XP e oro dei mostri dal livello (10 livelli = 1 tier; l'oro è una quota del reddito, il resto arriva dai drop)
MONSTER_LEVELS_PER_TIER = 10.0
MONSTER_GOLD_SHARE = 0.65
MONSTER_GOLD_MIN_MULT, MONSTER_GOLD_MAX_MULT = 0.7, 1.3
MONSTER_XP_FLOOR, MONSTER_GOLD_MIN_FLOOR, MONSTER_GOLD_MAX_FLOOR = 1, 1, 2

def monster_stats(level: int, mtype: str = "normal"):
    hp_m, dmg_m, acc_m, eva_m, arm_m, xp_m, gold_m, interval = MONSTER_TYPES[mtype]
    hp = MONSTER_HP_A * fpow(MONSTER_HP_R, level) * hp_m
    mh = MONSTER_MH_A * fpow(MONSTER_MH_R, level) * dmg_m
    acc = (MONSTER_ACC_A + MONSTER_ACC_B * level) * acc_m
    eva = (MONSTER_EVA_A + MONSTER_EVA_B * level) * eva_m
    arm = MONSTER_ARM_A * fpow(MONSTER_ARM_R, level) * arm_m
    # curve continue nel livello (stessa crescita dei tier: 10 livelli = 1 tier)
    lv_t = 1 + (max(1, level) - 1) / MONSTER_LEVELS_PER_TIER
    xp = XPH_BASE * fpow(XPH_GROWTH, lv_t - 1) * (TTK_TARGET_S + RESPAWN_S) / 3600.0 * xp_m
    gold = GPH_BASE * fpow(GPH_GROWTH, lv_t - 1) * (TTK_TARGET_S + RESPAWN_S) / 3600.0 * MONSTER_GOLD_SHARE * gold_m  # il resto arriva dai drop
    return {
        "hp": rhalf(hp), "max_hit": rhalf(mh), "accuracy": rhalf(acc), "evasion": rhalf(eva),
        "armor": rhalf(arm), "ward": rhalf(arm), "attack_interval_s": interval,
        "xp": max(MONSTER_XP_FLOOR, rhalf(xp)), "gold_min": max(MONSTER_GOLD_MIN_FLOOR, rhalf(gold * MONSTER_GOLD_MIN_MULT)),
        "gold_max": max(MONSTER_GOLD_MAX_FLOOR, rhalf(gold * MONSTER_GOLD_MAX_MULT)),
    }

# Cibo
FOOD_HEAL_A, FOOD_HEAL_R = 25.0, 1.40
def food_heal(tier: int) -> int:
    return rhalf(FOOD_HEAL_A * fpow(FOOD_HEAL_R, tier - 1))

# ----------------------------------------------------------------------------
# EQUIPAGGIAMENTO — budget statistiche per tier
# ----------------------------------------------------------------------------
GEAR_R = 1.40   # crescita per tier delle statistiche principali
WEAPONS = {
    # id: (stile, mani, velocità s, molt. danno, min_ratio, acc_bonus_mult, crit_bonus)
    "sword":      ("melee", 1, 2.4, 1.24, 0.60, 1.00, 0.00),
    "greatsword": ("melee", 2, 3.4, 1.65, 0.55, 0.90, 0.02),
    "shortbow":   ("ranged", 2, 2.0, 0.89, 0.60, 1.10, 0.03),
    "longbow":    ("ranged", 2, 3.0, 1.35, 0.55, 1.00, 0.06),
    "wand":       ("arcane", 1, 2.6, 1.00, 0.65, 1.00, 0.00),
    "staff":      ("arcane", 2, 3.4, 1.50, 0.60, 0.95, 0.02),
}
WEAPON_DMG_A = 6.0
def weapon_damage(tier: int, mult: float) -> int:
    return rhalf(WEAPON_DMG_A * fpow(GEAR_R, tier - 1) * mult)

ARMOR_SLOTS = {"helm": 0.18, "body": 0.32, "legs": 0.24, "gloves": 0.12, "boots": 0.14}
ARMOR_TYPES = {
    #        arm   ward  hp    eva   primary attr   ap_pct  acc
    "plate":   (1.00, 0.30, 1.00, -0.10, "str", 0.00, 0.00),
    "leather": (0.55, 0.50, 0.70, 0.45, "dex", 0.00, 0.40),
    "cloth":   (0.75, 1.00, 0.55, 0.45, "int", 0.06, 0.00),
}
ARMOR_SET_A = 40.0   # armatura totale set piastre al tier 1
HP_SET_A = 30.0
EVA_SET_A = 30.0
ACC_SET_A = 25.0
ATTR_SET_A = 4.0

def set_value(base: float, tier: int) -> float:
    return base * GEAR_R ** (tier - 1)

# Qualità di creazione (artigianato)
QUALITIES = [
    {"id": "normal", "mult": 1.00, "sockets": 0},
    {"id": "fine", "mult": 1.08, "sockets": 1},
    {"id": "excellent", "mult": 1.16, "sockets": 2},
    {"id": "masterwork", "mult": 1.28, "sockets": 3},
]

# base + per_level * (livelli sopra il requisito) + per_mastery * (padronanza), con tetto
QUALITY_CHANCES = {
    "masterwork": {"base": 0.0, "per_level": 0.0015, "per_mastery": 0.0010, "cap": 0.10},
    "excellent": {"base": 0.01, "per_level": 0.004, "per_mastery": 0.002, "cap": 0.25},
    "fine": {"base": 0.10, "per_level": 0.01, "per_mastery": 0.004, "cap": 0.45},
    "decimals": 4,
}

def quality_chances(levels_above_req: int, mastery: int):
    """Probabilità [normale, fine, eccellente, capolavoro] di una creazione."""
    d = max(0, levels_above_req)
    m = max(0, mastery)
    q = QUALITY_CHANCES
    def chance(k):
        return min(q[k]["cap"], q[k]["base"] + q[k]["per_level"] * d + q[k]["per_mastery"] * m)
    master, exc, fine = chance("masterwork"), chance("excellent"), chance("fine")
    normal = max(0.0, 1 - master - exc - fine)
    nd = q["decimals"]
    return [rdec(normal, nd), rdec(fine, nd), rdec(exc, nd), rdec(master, nd)]

# ----------------------------------------------------------------------------
# CASSE — rarità e condizione (vedi docs/09)
# ----------------------------------------------------------------------------
CRATE_RARITIES = [
    # id, peso %, colore hex, simbolo accessibile, bonus finitura %
    ("rare", 79.20, "#8DA2B8", "◆", 1.0),
    ("epic", 15.80, "#6F7BE6", "◆◆", 2.0),
    ("legendary", 3.80, "#C65AA8", "✦", 3.5),
    ("mythic", 0.90, "#E8702A", "✦✦", 5.5),
    ("relic", 0.30, "#F5CF4F", "★", 0.0),
]
CONDITIONS = [
    # id, float_min, float_max, peso %, molt. bonus, molt. valore
    ("pristine", 0.00, 0.10, 5.0, 1.20, 1.80),
    ("polished", 0.10, 0.25, 25.0, 1.10, 1.30),
    ("marked", 0.25, 0.50, 34.0, 1.00, 1.00),
    ("worn", 0.50, 0.72, 21.0, 0.92, 0.85),
    ("scarred", 0.72, 1.00, 15.0, 0.85, 0.70),
]
ANNALIST_CHANCE = 0.10      # variante "Annalista" (contatore)
ANNALIST_VALUE_MULT = 2.2
# QA3 §3: con 200/+0,05%/500 la garanzia a 500 non scattava mai (P(gap>=400)=0,001%, massimo osservato 367) e chi apre poche casse
# per tipo vedeva 1 ★ ogni ~330. Ora 180/+0,03%/300: la garanzia e' raggiungibile (4,6% delle serie), 1 ★ ogni 175,0 aperture
# (155,8 con Destino Paziente al massimo: resta nel bersaglio 150-220).
PITY_SOFT_START = 180       # aperture senza ★ prima che parta la pity morbida
PITY_SOFT_STEP = 0.0003     # +0,03% a ogni apertura oltre la soglia
PITY_HARD = 300             # ★ garantita alla 300ª apertura senza ★
TRADEUP_INPUTS = 10
GOLDEN_CONTRACT_INPUTS = 5  # 5 Mitici -> 1 ★
# ★ garantita a 300: con la pity la ★ esce in media 1 volta ogni ~175 aperture (0,57% invece dello 0,30% nominale);
# con 1000 il ritorno atteso delle casse supererebbe il 95% del prezzo della chiave (verifica in reports §6).
DISMANTLE_SHARDS = {"rare": 1, "epic": 5, "legendary": 25, "mythic": 125, "relic": 500}
RARITY_VALUE_MULT = {"rare": 1, "epic": 5, "legendary": 25, "mythic": 125, "relic": 500}
SKIN_VALUE_FRACTION_OF_GPH = 0.010   # valore di una finitura Rara = 1% dell'oro/ora del tier della chiave
KEY_TIER = {1: 1, 2: 3, 3: 5, 4: 7, 5: 9, 6: 11}   # chiave -> tier economico
KEY_SHOP_FRACTION_OF_GPH = 0.10       # prezzo all'Emporio = 6 minuti di oro/ora del tier

def skin_value(key_tier: int, rarity: str) -> int:
    return round_nice(gph(KEY_TIER[key_tier]) * SKIN_VALUE_FRACTION_OF_GPH * RARITY_VALUE_MULT[rarity])

def relic_pity_stats(base_pct: float = None, soft_start: int = PITY_SOFT_START, soft_step: float = PITY_SOFT_STEP,
                     hard: int = PITY_HARD):
    """Calcolo ESATTO della pity: ritorna (aperture medie tra due ★, probabilità effettiva della ★).
    'since' = aperture già fatte senza ★; probabilità di questa apertura:
      base                                  se since < soft_start
      base + soft_step * (since - soft_start + 1)   se since >= soft_start
      1                                     se since + 1 >= hard  (★ garantita)"""
    base = (base_pct if base_pct is not None else [r[1] for r in CRATE_RARITIES if r[0] == "relic"][0]) / 100
    surv, mean = 1.0, 0.0
    for since in range(hard):
        p = 1.0 if since + 1 >= hard else min(1.0, base + (soft_step * (since - soft_start + 1) if since >= soft_start else 0.0))
        mean += surv
        surv *= (1 - p)
    return mean, 1 / mean


def effective_rarity_pct():
    """Probabilità effettive delle rarità sul lungo periodo (pity inclusa): la massa in più della ★ si toglie
    in proporzione alle altre rarità. Sono i numeri da mostrare accanto a quelli nominali (docs/09 §4)."""
    nominal = {r[0]: r[1] / 100 for r in CRATE_RARITIES}
    eff_relic = relic_pity_stats()[1]
    k = (1 - eff_relic) / (1 - nominal["relic"])
    return {rid: rdec(100 * (eff_relic if rid == "relic" else w * k), 3) for rid, w in nominal.items()}


def condition_odds(float_min: float, float_max: float):
    """Probabilità (%) di ogni condizione per una finitura con intervallo [float_min, float_max].
    Regola (docs/09 §5): sono possibili solo le condizioni la cui fascia interseca l'intervallo; i pesi nominali si
    rinormalizzano su quelle; il float si estrae uniforme nell'intersezione fascia ∩ intervallo.
    Così le probabilità mostrate al giocatore sono ESATTAMENTE quelle usate dal gioco."""
    reach = [(c[0], c[3]) for c in CONDITIONS if min(c[2], float_max) - max(c[1], float_min) > 1e-9]
    tot = sum(w for _, w in reach)
    return {cid: rdec(100 * w / tot, 2) for cid, w in reach}


def key_shop_price(key_tier: int) -> int:
    return round_nice(gph(KEY_TIER[key_tier]) * KEY_SHOP_FRACTION_OF_GPH)

# ----------------------------------------------------------------------------
# MERCATO
# ----------------------------------------------------------------------------
MARKET_SELL_TAX = 0.05          # tassa sulle vendite al mercato (risorse)
SKIN_SELL_TAX = 0.10            # tassa sulle vendite di oggetti da cassa
MARKET_BUY_MARKUP = 1.8         # prezzo d'acquisto dai PNG = valore * 1.8 * trend
# Equipaggiamento (audit 50, E47-8): a ×1,8 un set intero costava 0,3-0,9 ore di gph(tier): il bot lo ricomprava a ogni tier
# prima di poterlo forgiare e la forgia perdeva senso. A ×6,5 un set costa ~1-3 ore di gph(tier) (controllo `acquisto_set`).
MARKET_BUY_MARKUP_EQUIPMENT = 6.5
DEMAND_HALF_LIFE_H = 6.0
# QA3 (23/10/2026): con 4 h un flusso di grezzi venduto a regime rendeva 0,30-0,36 x gph (docs/10 prometteva ~1,0) e il tetto
# dei prezzi di equipaggiamento (volume 20) 0,02. Con 8 h: 1 flusso 0,46-0,55 x gph, 4 flussi alternati ~0,9. Le Commesse
# chiedono lo stesso numero di ORE di produzione di prima (ORDER_QTY_RANGE in economy.py scala con questo valore).
DEMAND_ELASTICITY_HOURS = 8.0   # ~8 ore di produzione dimezzano il prezzo

# ----------------------------------------------------------------------------
# AUTOMAZIONE, TALENTI, CODA AZIONI, COLTIVAZIONE, POZIONI (docs/03 R-AZ-4/5, docs/04 §7/§11, docs/05 §6)
# ----------------------------------------------------------------------------
AUTOMATION_STARS = 1             # con 1 Stella nella mansione l'azione riprende da sola quando tornano gli ingredienti
PERK_DOUBLE_PICK_STARS = 3       # con 3 Stelle si scelgono 2 talenti su 3
QUEUE_BASE_SLOTS = 0             # senza Emporio/Costellazioni la coda non c'e'
QUEUE_MAX_SLOTS = 10             # 6 dell'Emporio + 4 delle Costellazioni
QUEUE_MODES = ["qty", "level", "time", "exhaust"]
FARM_PET_ONE_IN = 400            # famiglio: 1 raccolto su 400
FARM_AUTO_STARS = 1              # appezzamento automatico (raccolta + risemina) con 1 Stella di Coltivazione
FEAST_SLOTS = 1                  # un solo banchetto attivo
POTION_SLOTS = ["combat", "gathering", "artisan", "thievery"]   # 1 pozione per gruppo (docs/05 §6)

# ----------------------------------------------------------------------------
# OFFLINE
# ----------------------------------------------------------------------------
OFFLINE_CAP_BASE_H = 12
OFFLINE_CAP_MAX_H = 24
# QA81 (M3, M4, M5): tetti e soglie dell'offline. Il Carro di Ritiro raccoglie quanto non entra nel Deposito durante l'offline
# (pile nuove e istanze); oltre il tetto di istanze il pezzo si VENDE al prezzo del Mercato (mai perso in silenzio).
# Sotto la soglia minima l'assenza non lancia il simulatore: il tempo si accumula e si applica alla prossima sessione.
OFFLINE_OVERFLOW_MAX_INSTANCES = 400
OFFLINE_MIN_APPLY_S = 30
# QA120: sospensione/ibernazione del PC (o della Steam Deck) con il gioco APERTO. Il tempo del motore (CLOCK_MONOTONIC su Linux)
# non conta il sonno, quindi l'orologio di sistema avanza piu' di quello misurato: l'eccesso oltre questa soglia (secondi) conta
# come assenza (stesso limite offline, stesso Bentornato). Sotto la soglia nessun intervento (aggiustamenti NTP, scatti).
OFFLINE_RESUME_MIN_GAP_S = 120
OFFLINE_SAFE_FALLBACK_DEFAULT = True   # se il combattimento offline si ferma, il tempo avanzato va alla mansione precedente

# ----------------------------------------------------------------------------
# SABBIA DEL CUSTODE (UI F13, docs/ui_redesign/03 Design A prudente, 06 D24-D26): riserva di tempo che un clic spende per far
# avanzare SOLO l'azione in corso (come la Clessidra). Fondo finito => regola 9 (tetto indipendente dai clic, non cresce con
# Stelle/Ere). click_s = secondi per clic; max_cps/window_ms = limite duro anti-spam (CPU, non equita'); la riserva si
# rigenera di regen_online_pct % del tempo di gioco (solo con azione ammessa e gioco non in pausa) e di regen_offline_pct %
# dell'assenza contata (R-OFF-1). start_reserve_s = riserva di una nuova partita; unlock_gift_s = regalo una tantum allo sblocco
# (token feature:time_push). max_steps_per_frame / max_cpu_ms_per_frame = budget della coda di passi da 0,1 s.
# systems_for: sistemi che avanzano per tipo di attivita' (stesso ordine di SystemRegistry; bank prima). allowed_activities e
# blocked_when: dove la Sabbia NON si puo' usare. Nessun effetto su Casse, estrazioni, coop, Prove (docs/24).
# regen_offline_pct = 0.3 (non 0.5 del doc 03): con 0.5 il pavimento di 4 h delle Stelle con le Costellazioni al massimo scendeva a 3,995 h
# (balance_sim time_push_report, controllo 3); con 0.3 e' 4,018 h. Non toccati gli altri strati.
# ----------------------------------------------------------------------------
TIME_PUSH = {
    "click_s": 0.3, "max_cps": 20, "window_ms": 1000, "reserve_cap_s": 600,
    "regen_online_pct": 5.0, "regen_offline_pct": 0.3, "start_reserve_s": 0, "unlock_gift_s": 60,
    "max_steps_per_frame": 4, "max_cpu_ms_per_frame": 4,
    "systems_for": {"skill": ["bank", "skills", "queue"]},
    "allowed_activities": ["skill"],
    "blocked_when": ["trial", "extreme_risk"],
    "unlock_token": "feature:time_push",
}


def push_regen(dt: float, pct: float) -> float:
    """Sabbia rigenerata in `dt` secondi di tempo contato, a `pct` % (online: regen_online_pct; offline: regen_offline_pct)."""
    if not (dt > 0.0) or not (pct > 0.0):
        return 0.0
    return dt * pct / 100.0


def push_spend(reserve_s: float, click_s: float) -> float:
    """Tempo speso da un clic: min(riserva, click_s), mai negativo."""
    if not (reserve_s > 0.0) or not (click_s > 0.0):
        return 0.0
    return min(reserve_s, click_s)


# Modalità Cozy (opzionale, nelle Impostazioni; G53): +% XP di tutte le mansioni, sorgente modificatori «mode:cozy».
# Non conta per le classifiche. Fuori dal simulatore di bilanciamento: è una scelta del giocatore, non un percorso.
COZY_XP_PCT = 50

# ----------------------------------------------------------------------------
# REGALO DI NUOVA PARTITA (OPEN_QUESTIONS B-1, resoconto 29): inizio dolce, pochi oggetti.
# 10 porzioni di cibo per i primi combattimenti del Prologo (prima che la Cucina ne produca) e un po' d'oro
# da vedere nel Deposito fin dal primo minuto. Lo consegna BankSystem una sola volta.
# ----------------------------------------------------------------------------
# Deposito (feedback giocatore, 23/10/2026, docs/07 §7.1): avviso quando i posti usati raggiungono `warn_pct` %; gli attrezzi
# doppioni di una vecchia partita (categoria in `recycle_dupe_categories`) si riciclano al caricamento in oro pari a
# `recycle_pct` % del valore (nessuna perdita di valore: sono pezzi uguali, senza stato proprio).
# CAPACITÀ DEL DEPOSITO (feedback giocatore 23/10/2026, docs/audit_2026-10-22/114_RESOCONTO_DEPOSITO.md): spazi permanenti
# regalati dall'ultima missione principale di certi capitoli (capitolo -> spazi). Sono finiti (7 x 10) e passano da
# Modifiers («bank_slots», fonte `quest:bank_slots`, ricostruita dalle missioni riscattate: nessuno stato nuovo nel salvataggio).
BANK_QUEST_SLOTS = {1: 10, 3: 10, 5: 10, 6: 10, 7: 10, 9: 10, 10: 10}

# F15 (docs/ui_redesign/02 §4.1): le categorie in `space.free_categories` NON occupano Spazio: vivono nell'Armeria, con un tetto
# tecnico `gear_cap` (salvataggio, prestazioni; non si compra e non è economia) e un avviso una volta a `gear_warn_pct` %.
BANK_SPACE = {"free_categories": ["equipment", "tool"], "gear_cap": 300, "gear_warn_pct": 95}

# F17 (docs/ui_redesign/02 §4.3, §5.1, §5.5, §5.7): schede del Deposito create dal giocatore (gratis, nessun pozzo d'oro: non
# danno capacità) e protezioni della vendita a selezione. max_tabs = schede personalizzate (oltre a Tutto e Armeria);
# tab_name_max = caratteri del nome; tab_of_cap = tetto di sicurezza delle assegnazioni salvate (si scartano prima le pile
# esaurite); search_debounce_ms = attesa dopo l'ultimo tasto della ricerca; sell_confirm_guard_ms = per quanto il primo Invio
# nell'anteprima di vendita è ignorato; tabs_hint_used = Spazio usato oltre il quale il tutorial propone le schede.
BANK_UI = {"max_tabs": 12, "tab_name_max": 16, "tab_of_cap": 4000, "search_debounce_ms": 150,
           "sell_confirm_guard_ms": 400, "tabs_hint_used": 40}

BANK_RULES = {
    "space": BANK_SPACE,
    "ui": BANK_UI,
    "warn_pct": 90, "recycle_pct": 100, "recycle_dupe_categories": ["tool"],
    # acquisti multipli nel pulsante «Espandi Deposito» (la UI non ha numeri suoi)
    "buy_batches": [1, 5, 10],
    # Carro di Ritiro per TUTTE le fonti (resoconto 117): il Deposito pieno non blocca mai nulla. Il tetto di istanze è
    # `offline.overflow_max_instances`. notice_s = ogni quanti secondi di gioco il Registro riassume cosa è entrato nel Carro;
    # sell_rule = filtro SellRules «consigliato» per le Finiture in eccesso (solo Finiture: mai bloccate, indossate, uniche
    # né Reliquie né Annaliste), offerto con un clic nel pannello del Carro.
    "carro": {"notice_s": 20, "sell_rule": {"cat": "skin", "max_tier": 0, "max_quality": "", "max_rarity": "rare", "keep_special": True}},
    # Ipotesi dello studio di capacità (solo simulatore: tools/balance_sim.py §5e). Spazi necessari a un giocatore ordinato
    # (vende i doppioni): need = (need_base + need_per_tier * tier + need_per_hour * ore) * (1 + headroom_pct/100).
    # need_base (F15: era 30 con equipaggiamento e attrezzi, che ora stanno nell'Armeria) = pile uniche (chiavi, Casse, glifi); need_per_tier = tipi impilabili che si
    # accumulano per tier (materiali ~18, munizioni 3, pozioni ~5, cibo ~3, semi ~1,5, glifi/Casse/chiavi ~4 = ~35 definizioni
    # per tier nei dati; se ne tiene circa il 60%: il resto si vende o si consuma subito); need_per_hour =
    # collezione di finiture e reliquie. Tarate sul bot QA81 (124 posti usati a ~24 h con vendita aggressiva).
    "study": {
        "need_base": 12, "need_per_tier": 22, "need_per_hour": 0.3, "headroom_pct": 15,
        "tier_by_hour": [[0, 1], [2, 2], [5, 3], [10, 4], [18, 5], [30, 6], [45, 7], [60, 8], [85, 9], [115, 10], [150, 11]],
        "checkpoints_h": [2, 5, 10, 18, 30, 50, 85, 115, 150],
        # ore a cui si chiude ciascun capitolo (bot QA81 tycoon; il C10 è una stima) e Costellazione «Caveau di Famiglia»:
        # livelli ipotizzati alle ore indicate (costano Polvere, che compete con gli acceleratori)
        "chapter_hours": {"1": 2.0, "3": 7.9, "5": 11.9, "6": 24.0, "7": 38.8, "9": 53.0, "10": 80.0},
        "vault_levels_by_hour": [[50, 2], [85, 4], [115, 6]],
        "active_gold_mult": 1.0,           # oro/ora attivo = 1,0 x gph(tier): prudente (docs/19 §5d: 1,09-1,42)
        # Armeria (F15): bisogno a 150 h = (slot_per_set x set posseduti + slot attrezzo x scorte) x (1 + scorte%); gear_cap >= 2 x bisogno
        "gear_need": {"slots_per_set": 5, "sets_owned": 11, "tool_slots": 6, "tool_stock": 2, "stock_pct": 15, "min_cap_factor": 2},
        "max_phase_cost_pct": 35,          # tetto: il costo degli spazi necessari in una fase <= 35% dell'oro attivo della fase
    },
}

NEW_GAME_GIFT = {"gold": 25, "items": [{"item": "food_bleak", "qty": 10}]}

# ----------------------------------------------------------------------------
# UTILITÀ
# ----------------------------------------------------------------------------
def L(it: str, en: str) -> dict:
    """Coppia di localizzazione."""
    return {"it": it, "en": en}

def slug(s: str) -> str:
    import re, unicodedata
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower()
    return s

def round_nice(x: float) -> int:
    """Arrotonda a valori "puliti" (2-3 cifre significative) per prezzi e costi."""
    if not x >= 100:              # anche NaN
        return max(1, rhalf(x))
    if x >= INT_LIMIT:
        return INT_LIMIT
    mag = 10 ** (len(str(int(x))) - 2)
    return int(rhalf(x / mag) * mag)
