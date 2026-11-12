# 14 — Modificatori e boost (sistema unico)

> Dati: `data/modifier_catalog.json` (catalogo ufficiale: 75 famiglie). Elenco consultabile: `docs/appendici/A6_imprese_famigli_costellazioni.md`.

## 1. Un solo sistema per tutti i bonus

Ogni bonus del gioco (attrezzi, maestria, talenti di mansione, Stelle, Costellazioni, equipaggiamento, glifi, finiture, reliquie, collezioni, famigli, pozioni, banchetti, fazioni, Prove, eventi, Ere) è un **modificatore**:

```json
{"key": "skill_double_pct:mining", "value": 3, "mode": "add"}
```

- `key` = `famiglia` oppure `famiglia:ambito` (ambito = mansione, gruppo `gathering/artisan/special/combat`, `all`, `current`, elemento, fonte d'oro, id dungeon).
- `mode` = `add` (default) o `more`.
- **R-MOD-1:** ogni chiave usata nei dati DEVE esistere nel catalogo (il validatore lo verifica).

## 2. Regola di cumulo (identica ovunque)

```
valore_finale = base × (1 + Σ add / 100) × Π (1 + more_i / 100)
```

- Gli **add** dello stesso tipo si sommano tra loro (tutte le fonti normali).
- I **more** si moltiplicano tra loro e con la somma degli add. Sono riservati agli strati di prestigio (Stelle: XP della mansione `60% × (1 − 0,92^stelle)` more, asintotico; Costellazioni: alcuni nodi, **tutti con livello massimo** — «Passo Esperto» 14 livelli, «Mani Svelte» 20; Ere) per mantenere il loro valore anche quando gli add sono alti. Un bonus *more* che accelera lo strato stesso deve essere asintotico (docs/13 §1).
- **Ambiti:** per un'azione di Miniera valgono `skill_xp_pct:mining` + `skill_xp_pct:gathering` + `skill_xp_pct:all` + `skill_xp_pct:current` (se attivo su quella mansione).

## 3. Interpretazioni speciali

| Famiglia | Come si applica |
|---|---|
| `skill_haste_pct`, `action_haste_pct` | durata = base / (1 + totale/100) (nessun limite, rendimento decrescente naturale) |
| `combat_haste_pct` | intervallo = base / (1 + effettivo/100); effettivo = somma degli add fino a +60%, oltre vale metà, **massimo +100%** (`combat.rules.haste_cap`, `Formulas.effective_haste_pct`, resoconto 91); i «more» moltiplicano dopo |
| `skill_double_pct` | probabilità di doppio; oltre 100%: doppio garantito + (totale−100)% di triplo, ecc. |
| `skill_save_pct` | cap 50% |
| `combat_crit_chance_pct` | punti percentuali assoluti, cap 75% |
| `combat_defense_pct` | si applica sia ad armatura sia a protezione arcana |
| `crate_find_pct` | relativo; cap +200% |
| `market_tax_reduction_pct` | riduce la tassa in percentuale della tassa stessa; cap 80% |
| `offline_cap_hours` | ore aggiuntive al limite offline (max totale 24 h) |
| `*_slots`, `bank_slots` | interi additivi |
| `estate_auto_collect`, `auto_sell_unlock`, `combat_revive_once` | flag (≥1 = attivo) |

I cap sono nel catalogo (`cap`): l'interfaccia mostra "(limite raggiunto)" quando un totale lo supera.

## 4. Implementazione (`Modifiers.gd`)

- Ogni fonte registra i propri modificatori con un **id fonte** (`"equip:weapon"`, `"pet:pet_skill_mining"`, `"star:mining"`, `"potion:combat"` …). Quando la fonte cambia si sostituisce l'intero blocco della fonte.
- Cache per chiave invalidata a ogni cambio; lettura O(1) durante le azioni.
- API minima:
  - `set_source(source_id: String, mods: Array)` / `clear_source(source_id)`
  - `total_add(key: String, scopes: Array) -> float` (somma su chiave base + ambiti)
  - `total_more(key, scopes) -> float` (prodotto)
  - `apply(base: float, key: String, scopes: Array) -> float`
- **Pannello "Bonus attivi"** (`BonusSummary` + `BonusDialog`, rapporto 112): solo presentazione, non cambia nessun bonus. Mai chiavi tecniche né id grezzi: ogni famiglia del catalogo ha `name`, `blurb` (una frase senza numeri), `cat` (categoria del pannello) e, se ha ambiti, `scope_all` (testo di «tutto»), tutti generati da `tools/gamedata/modifier_names.py`. L'ambito si legge dopo i due punti («Qualità: Cucina»): mansioni e dungeon dai loro dati, gli altri ambiti da `UI_BONUS_SCOPE_*`. Le fonti hanno il nome vero (evento, famiglio, Stella, Prova, collezione…; tipi in `UI_UIA_SRC_*` e `UI_BONUS_SRC_*`). Categorie con colore e sigla di `LogCategory`. Il tetto del catalogo compare come «Tetto +200%: stai usando il 100%» con barra e, se superato, «Ne hai +250%: il resto non conta». I bonus «more» sono contrassegnati «moltiplicatore» (×1,28) e distinti dagli additivi (+17,5%). Per aggiungere una famiglia: nome e descrizione in `modifier_names.py` (il test `test_bonus_panel` lo pretende).

## 5. Budget dei bonus (regole per i progettisti)

Valori tipici massimi a fine gioco **senza** Stelle/Costellazioni (per tenere sotto controllo l'inflazione):

| Famiglia | Fonti principali | Totale tipico endgame |
|---|---|---|
| `skill_double_pct:<raccolta>` | attrezzo 10, maestria 25, talenti ~25, finitura ~6, famiglio 3, reliquia 6–10 | ~70–80% |
| `skill_haste_pct:<raccolta>` | attrezzo 40, maestria 10, talenti ~20, finitura ~5 | ~75% (durata ×0,57) |
| `skill_xp_pct:all` | banchetto 8, reliquie 6–8, famigli, imprese | ~20–30% |
| `combat_dmg_pct` | amuleto ~6,5, glifi 5×3, talenti ~25, finitura ~6, pozione 16 | ~60–70% |
| `crate_find_pct:all` | reliquie, collezioni, famigli, Costellazioni (max 100) | ~50–100% |

Regola: un singolo oggetto o famiglio non deve dare più del **10%** su una chiave "generale" (`all`).

## 6. Sabbia del Custode (UI F13): NON è un modificatore

La Sabbia del Custode (`constants.time_push`, `TimePushSystem`) regala tempo all'azione in corso come la Clessidra: non passa da `Modifiers`, non ha famiglie e non entra nel budget di §5. Nella v1 nessun nodo, oggetto o Costellazione la potenzia. Se un giorno servirà potenziarla, **solo** famiglie additive (`push_reserve_cap_s`, `push_regen_pct`) con livello massimo e tetto, mai dalle Stelle né dalle Ere (regola 9); il controllo (7) di `balance_sim.py::time_push_report` fallisce se esiste un nodo infinito che la tocca.
