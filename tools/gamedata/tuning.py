"""Numeri di bilanciamento dei sistemi Tenuta, Spedizioni, Mercenari e Apprendisti (CLAUDE.md regola 2).

Prima stavano nei blocchi `PENDING` di EstateSystem / ExpeditionSystem / MercenarySystem / ApprenticeSystem (GDScript) perché i dati
non li esportavano. Ora la fonte è QUI e finiscono in data/constants.json (chiavi `estate_tuning`, `expedition_tuning`,
`mercenary_tuning`, `apprentice_tuning`); il codice li legge da lì. I valori sono gli stessi di prima (nessun cambio di comportamento).
Le soglie puramente tecniche (epsilon, guardie dei cicli) restano nel codice come `TECH`: non sono numeri di bilanciamento.
"""

ESTATE_TUNING = {
    "rations_per_settler_h": 1.0,      # docs/11 §3 (anche estate_rules.settlers.upkeep, testo)
    "pantry_auto_target_h": 24.0,      # QA81 M1: la Dispensa vuota si rifornisce dal Deposito fino a 24 h di razioni (= tetto offline)
    # Resoconto 117 (P5 del 111): un cibo messo in uno slot dell'Eroe riserva SOLO questa quantità di porzioni (basta per più di un
    # boss: docs/19 <= 40 cibi per uccisione); il resto della pila è utilizzabile dalla Dispensa automatica. Prima l'intera pila
    # era esclusa e la Dispensa restava vuota in 51-83 Bentornato su 89.
    "pantry_slot_reserve": 60,
    "cottage_base": 5, "cottage_per_level": 3,        # docs/11 §2: 5 + 3·L posti
    "storage_base": 500.0, "storage_exp": 1.2,        # docs/11 §2: 500 · L^1,2
    "shop_units_per_level_h": 200.0,   # docs/11 §2: 200 · L · 2^traguardi unità/h
    "vault_interval_h": 8.0, "vault_speed_per_level": 0.05, "vault_key_chance": 0.05,   # docs/11 §2
    "band_levels": 10, "band_max": 11,                # banda = min(11, 1 + L // 10)
    "planks_base": 2.0, "planks_per_level": 0.5, "bars_base": 1.0, "bars_per_level": 0.3,
    "granite_from_level": 15, "granite_every": 5, "padlock_every": 10,
    "granite_item": "granite",
    "event_interval_min": 90.0, "event_interval_var": 0.5,     # Eventi di colore: ogni ~90 min di gioco (±50%)
    "event_gold_minutes": 10.0,        # il postino porta una mancia pari a 10 min di reddito della Bottega
    "event_pantry_hours": 0.5,         # gatto/colono: ± mezz'ora di razioni
    "event_log_max": 12,
    # QA120: se il Magazzino pieno ha rifiutato la produzione per almeno questi secondi di offline, il Bentornato lo dice
    "warehouse_full_report_s": 600.0,
}

EXPEDITION_TUNING = {
    "req_base": 30.0, "req_growth": 1.35,                 # expedition_rules.required_power_formula
    "success_gain": 1.6, "success_bias": 0.15, "success_min": 0.05, "success_max": 0.98,     # success_formula
    "value_per_hour": 0.6,                                # reward_value_per_hour_formula
    "size_min": 2, "size_max": 4, "team_max": 4,
    "board_base": 3, "board_per_levels": 10, "board_max": 6,          # docs/11 §2 (board_missions_formula)
    "conc_base": 1, "conc_per_levels": 15, "conc_max": 4,             # docs/11 §2 (concurrent_expeditions_formula)
    "recon_rolls": 3,                                     # materiali grezzi diversi per Ricognizione
    "hunt_common_share": 0.8,                             # Caccia: quota di valore in materiale comune (il resto raro)
    "survey_xp_mult": 2.0,                                # Cartografia: XP mercenari doppi (docs/11 §6)
    "recon_subs": ["log", "ore", "fish_raw", "fiber", "crop", "hide", "meat_raw", "herb"],
    "map_fragment_item": "map_fragment",
    "log_max": 12,
}

MERCENARY_TUNING = {
    "roster_base": 4, "roster_per_levels": 5, "roster_max": 16,       # docs/11 §2: 4 + L//5 (max 16)
    "level_power_step": 0.1, "equip_power_step": 0.05,                # docs/11 §5
    "equip_tier_max": 11,
    "xp_base": 100.0, "xp_growth": 1.12,                              # mercenary_rules.xp_to_next_formula
    "rarity_bonus_per_tavern_level": 0.005,                           # docs/11 §2: +0,5% relativo per livello
    "hire_base": 1000.0, "hire_per_tavern_level": 0.02,                # mercenary_rules.hire_cost_formula
}

APPRENTICE_TUNING = {
    "eff_base": 0.15, "eff_per_level": 0.01, "eff_cap": 0.35,      # docs/11 §2: min(35%, 15% + L%) (era 75%/35%: audit 53, somma delle fonti)
    "max_slots": 5,                                                # docs/11 §2 / modificatore apprentice_slots
    "groups": ["gathering", "artisan"],
    "chunk_s": 600.0,       # blocco massimo dell'offline (i livelli cambiano i valori attesi)
}
