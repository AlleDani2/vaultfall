# 12 — Missioni: storia lineare, incarichi, classi, percorsi di mansione, commesse, taglie

> Dati: `data/quests.json` (270 missioni), `data/chapters.json`, `data/npcs.json`, `data/contract_templates.json`, `data/contract_rules.json`, `data/bounty_board.json`. Elenco: `docs/appendici/A5_missioni.md`.

## 1. Tipi di missione

| Tipo (`kind`) | Quante | Struttura | Scopo |
|---|---|---|---|
| `main` — **Cronache del Caveau** | 71 (Prologo + 10 capitoli × 6 + Epilogo × 5) | **lineare**, una alla volta | storia, sblocchi di sistemi e zone |
| `side` — Incarichi di fazione | 30 (5 fazioni × 6) | lineare per fazione | reputazione, titoli, obiettivi di sistema |
| `class` — Missioni di classe | 9 | singole | specializzazioni e classi ibride |
| `skill_path` — Percorsi di mansione | 160 (16 mansioni × 10) | lineare per mansione | obiettivi a lungo termine, Tomi XP, cornici, titoli, Insegne |
| Commesse giornaliere/settimanali | 3 + 5 attive | generate da modelli | ritorno quotidiano senza FOMO |
| Taglie | 1 attiva (3 offerte) | generate | mansione Caccia alle Taglie |

## 2. Struttura dati di una missione

```json
{ "id": "main_c2_q4", "kind": "main", "chapter": 2, "giver": "mirta",
  "title": {"it": "...", "en": "..."}, "desc": {"it": "...", "en": "..."},
  "objectives": [ {"type": "kill", "monster": "tidecutter_pirate", "qty": 20},
                  {"type": "craft", "item": "potion_vigor_1", "qty": 3},
                  {"type": "build", "building": "fishery", "level": 1} ],
  "rewards": {"gold": 1200, "xp_tome": {"skill": "hero", "size": "medium"}, "items": [...], "title": "...", "reputation": {...}, "bank_slots": 10},
  "unlocks": ["skill:alchemy", "building:fishery"], "requires": ["main_c2_q3"] }
```

## 3. Tipi di obiettivo (implementare TUTTI in `QuestSystem.gd`)

| `type` | Parametri | Si conta quando |
|---|---|---|
| `gather` | item, qty | l'oggetto entra nel Deposito da un'azione di raccolta (dall'accettazione) |
| `craft` | item, qty | l'oggetto viene prodotto |
| `craft_any` / `craft_category` / `craft_rank` | skill / category / rank, qty | prodotto qualsiasi della mansione/categoria/rango |
| `kill` | monster, qty | uccisione (anche offline) |
| `kill_any` / `kill_zone` / `kill_any_as_class` | (era) / zone / cls, qty | uccisioni con filtro |
| `complete_dungeon` / `complete_raid` | dungeon / raid (`any`), (era), qty | completamento |
| `open_crates` | crate (`any`), qty | apertura |
| `deliver` | item, qty | **consuma** gli oggetti alla consegna (pulsante) |
| `equip` | item | oggetto equipaggiato |
| `build` | building, level | livello raggiunto |
| `reach_level` / `reach_total_level` | skill, level / level | livello raggiunto (immediato se già soddisfatto) |
| `sell_market` | gold | oro incassato al Mercato |
| `steal` | target (id azione), qty | borseggio riuscito |
| `farm_harvest` | crop, qty | raccolto |
| `skill_actions` | skill, qty | azioni completate |
| `recruit` | (rarity), qty | mercenario assunto |
| `expedition` | qty | spedizione completata (successo o no) |
| `bounty_complete` | qty | taglia completata |
| `tradeup` / `refine_polish` / `socket_glyph` | qty | azioni della Sala dei Caveau / incastri |
| `obtain_rarity` | rarity, qty | oggetto da cassa ottenuto |
| `orders_complete` / `estate_total_levels` / `estate_prestige` | qty | Tenuta e commesse |
| `secret_spot` / `secret_spot_all` | qty | luoghi segreti rivelati |
| `world_boss` | tier, qty | fascia di contributo raggiunta |
| `rift_floor` | floor | piano raggiunto |
| `star` | skill (`any`), qty | stelle ottenute |
| `talk` | npc | apertura del dialogo |

**R-QU-1:** i contatori partono da zero all'accettazione (tranne `reach_*`, `build`, `equip` che si verificano sullo stato attuale).
**R-QU-2:** la storia principale è **sempre** una sola missione attiva alla volta, accettata automaticamente; le altre categorie hanno un limite di missioni attive (fazione: 1 per fazione; percorsi: tutte).
**R-QU-3:** le missioni completate restano completate per sempre (anche dopo Stelle, Rifondazioni, Ere).
**R-QU-3b (resoconto 114):** `rewards.bank_slots` regala spazi permanenti del Deposito (+10 alla fine dei Capitoli I, III, V, VI, VII, IX, X; `core.BANK_QUEST_SLOTS`). Non c'è stato nuovo nel salvataggio: `QuestSystem` ricostruisce la fonte Modifiers `quest:bank_slots` dalle missioni in `done` a ogni caricamento e riscatto, quindi chi le aveva già riscattate li riceve subito. La scheda della missione mostra «+10 spazi del Deposito».
**R-QU-4:** le ricompense `xp_tome` danno un **Tomo** (oggetto) la cui XP si calcola all'uso sul livello attuale: `molt × xph(tier del livello) × 0,25` (piccolo ×1, medio ×3, grande ×10); **sull'Eroe** un Tomo dà al massimo 2 / 4 / 8 livelli (`tome.hero_max_levels`: 4 Tomi accumulati portavano l'Eroe da Lv 26 a 47, ora a ~38).

## 4. La storia principale (sintesi dei capitoli)

| Capitolo | Arco narrativo | Fine capitolo |
|---|---|---|
| Prologo | La Pioggia di Stelle: primi mestieri, prima Cassa | Erboristeria |
| I — Valle del Mulino | lupi, archi per i Ramingi, l'orto di Nonna Berta, il Mercato | Regina Vespa |
| II — Costa del Sale | nasce la Tenuta, pirati e pozioni, la Gazza e la Mano Grigia | Capitano Ghignosale |
| III — Ferroradice | gemme, rune antiche, la Chiave di Ferro | Golem di Ferroradice |
| IV — Bosco Sussurrante | la Taverna, le spedizioni, le taglie, il sigillo del Collezionista | Madre dei Ragni |
| V — Paludi di Fiele | il morbo, i contratti di conversione, le tracce del Collezionista | Strega di Fiele → Covo |
| VI — Deserto di Cenere | il Ricettatore, la Sfinge, l'Affinatura | Faraone Senza Nome |
| VII — Picchi di Brina | provviste per l'inverno, la Sfida dei Collezionisti | Jarl di Ghiaccio |
| VIII — Archivio Sommerso | la Cittadella, **il segreto delle Stelle** | Bibliotecario Annegato |
| IX — Cime della Tempesta | il Colosso Errante, la **Chiave Celeste** | Drago della Tempesta |
| X — Caveau Celeste | sentinelle, Custode delle Chiavi, **il Collezionista smascherato** | Cuore del Caveau |
| Epilogo | il Caveau si ricompone: Era II, Breccia, prima Stella, Custode Eterno | — |

## 5. Regole per scrivere nuove missioni

- **R-QU-5 (ritmo):** nella storia principale i requisiti di mansione non superano il **60% del livello Eroe** del capitolo (es. Cap. VII, Eroe 61–70 → mansioni ≤ 40). La storia non deve obbligare a grind di mansioni. Gli obiettivi di **livello totale** (Cap. VI–X: 450/550/600/650/700, FIX-MEDIO; contano i livelli record, quindi Riti e Stelle non li fanno arretrare) restano entro Eroe atteso + 16 × 60% (VII ≤ 640, VIII ≤ 743, IX ≤ 849, X ≤ 955): avanzano tutte le mansioni insieme con un livello ogni pochi minuti, senza chiederne una alta. Dal Cap. VI ogni capitolo dà le chiavi del proprio tier e i passi dei Percorsi di Mansione danno k Schegge al passo k (fonte regolare per la Forgiachiavi).
- **R-QU-6 (varietà):** ogni capitolo alterna 6 missioni: arrivo + livello → raccolta/produzione → combattimento → sistema nuovo → élite/consegna → boss.
- **R-QU-7 (ricompense):** oro ≈ 15–30 minuti di gph del capitolo; Tomo XP alle missioni di boss; mai oggetti esclusivi di potere che non si possano ottenere altrimenti (eccezione: oggetti di missione).
- **R-QU-8 (testi):** titolo ≤ 5 parole, descrizione ≤ 2 frasi, IT + EN.
- **R-QU-9:** ogni nuova funzionalità del gioco va sbloccata da una missione (`unlocks: ["feature:..."]`).

## 6. Commesse giornaliere e settimanali (anti-FOMO)

- 3 giornaliere + 5 settimanali generate dai modelli (`contract_templates.json`) sul **tier attuale** del giocatore; 1 cambio gratuito al giorno.
- **Restano disponibili fino a 7 giorni** (si accumulano), **nessuna serie di accessi**, nessuna penalità per l'assenza, nessuna ricompensa esclusiva: premiano chi torna, non puniscono chi non torna (evita i criteri PEGI su "penalità per mancato ritorno").
- Ricompense: Gettoni di Commissione (3 / 15), oro (0,15 / 1,0 × gph), chiavi o casse. Negozio dei gettoni: chiavi T1–T3, Clessidre, Tomi, Frammenti di Mappa.
- **Implementazione (`ContractSystem`, sezione Commesse nella schermata Missioni):** il «giorno» è di gioco (`contract_rules.day_s` secondi, giocati o di assenza), mai la data del sistema; si aprono con `feature:market`; giornaliere 7 giorni, settimanali 14; le completate non scadono finché non si riscattano; i modelli non disponibili (funzione non ancora sbloccata) vengono saltati; cambio gratuito 1/giorno per le giornaliere senza progressi. Gli eventi sono gli stessi degli obiettivi di missione (inoltrati da `QuestSystem`).

## 7. Percorsi di mansione

Per ogni mansione 10 tappe (livelli 10…100 + N azioni). Ricompense crescenti: oro, Tomi XP, cornice di bronzo (tappa 5), **titolo di Maestro + Insegna** della mansione (tappa 10: +5% doppio o risparmio + 5% XP nella mansione, slot `insignia`).

## 8. Guida alle missioni: «Come fare», «Vai», «Da scoprire» (feedback dei giocatori)
Il giocatore deve sempre sapere COSA fare e DOVE. Tutta la logica sta in `game/src/ui/screens/QuestGuide.gd` (solo presentazione, nessun numero di bilanciamento); i testi sono in `localization/parts/quest_guide.csv` (`UI_QG_*`).
- **Istruzione per obiettivo** (`QuestGuide.howto`): per ogni tipo di obiettivo un testo esplicito («Apri Taglialegna, scegli «Pino» e premi Avvia») e un bersaglio «Vai» ({schermata, parametri}, lo stesso formato di `ReqLink`). Nomi di azioni, zone e mostri vengono dai dati: nessun testo scritto a mano per singola missione. Ogni tipo di obiettivo nuovo DEVE avere il suo ramo in `howto` (il test `test_quest_guide.gd` lo impone su tutte le 270 missioni, in IT ed EN).
- **Dove si ottiene un oggetto** (`QuestGuide.where_item`): mansione che lo produce (dalle azioni), altrimenti il mostro che lo lascia cadere con la sua zona (tabelle di drop), altrimenti la missione che lo dà come ricompensa, altrimenti il Mercato; se i dati non indicano una fonte lo dice onestamente.
- **Perché** (`QuestGuide.why`): «Sblocca: …» dai `unlocks` della missione; per le missioni non ancora disponibili «Si apre dopo: …» (`lock_reason`) con link alla missione che manca.
- **Passi di scoperta**: tabella dati `guides` (generata da `tools/gamedata/quests.py::build_guides`): sistemi che nessuna missione principale introduce (Manuale, Deposito, Compendio, Luoghi Segreti, Prestigio, Amici). Compaiono quando i `requires` sono soddisfatti e finché la schermata non è stata aperta (`QuestSystem.state.seen_screens`, riempito da `MainScreen.show_screen`). Regola per i contenuti futuri: ogni voce di `ScreenRegistry` con sblocco deve essere concessa da una missione principale OPPURE avere una guida (test di copertura).
- **UI**: voce «Missioni» subito dopo il Riepilogo (tasto M, pallino = missioni da riscattare + novità da scoprire); schermata a sezioni (Da riscattare con «Riscatta tutto», Da fare ora, Da scoprire, Altre in corso, Prossime, Commesse, rimandi a Compendio/Commesse, Completate); riquadro «Obiettivo attuale» (`GoalPanel`) in cima alla colonna destra e nel Riepilogo.
