# 04 — Mansioni (skill)

> Dati: `data/skills.json`, `data/actions/*.json`, `data/skill_perks.json`, `data/xp_table.json`. Elenco completo delle azioni: `docs/appendici/A1_mansioni_e_azioni.md`.

## 1. Le 17 mansioni

| Gruppo | Mansione (ID) | Cosa fa | Attrezzo | Alimenta |
|---|---|---|---|---|
| Raccolta | Taglialegna (`woodcutting`) | Tronchi da 11 alberi | Ascia | Carpenteria, Tenuta, Fusione chiavi (manici) |
| Raccolta | Miniera (`mining`) | Minerali, carbone, granito, essenze; gemme grezze (1%) | Piccone | Forgiatura, Gioielleria, Incisione, Tenuta |
| Raccolta | Pesca (`fishing`) | 11 pesci; Tesori Sommersi | Canna | Cucina, oli, banchetti |
| Raccolta | Erboristeria (`foraging`) | 11 fibre + 11 erbe; semi | Falcetto | Sartoria, Alchimia, Rune |
| Raccolta | Trappole (`trapping`) | Pelli, carne, piume | Trappola | Sartoria, Cucina, frecce |
| Produzione | Forgiatura (`smithing`) | Lingotti, armature a piastre, spade, scudi, asce/picconi/falcetti | — | Combattimento (Mischia), attrezzi, chiavi |
| Produzione | Carpenteria (`woodworking`) | Assi, archi, bacchette, bastoni, canne, trappole, frecce | — | Distanza/Arcano, attrezzi, Tenuta |
| Produzione | Sartoria (`tailoring`) | Cuoio, tessuti, corde, armature di cuoio e stoffa, mantelli | — | Distanza/Arcano |
| Produzione | Cucina (`cooking`) | Cibo curativo + **Banchetti** (bonus di 20–60 min) | — | Combattimento, coloni della Tenuta |
| Produzione | Alchimia (`alchemy`) | 12 linee di pozioni × 4 ranghi + oli da lama | — | Combattimento e mansioni |
| Produzione | Gioielleria (`jewelcrafting`) | Taglio gemme, anelli e amuleti | — | Combattimento, chiavi |
| Produzione | Incisione Runica (`runecarving`) | Rune (munizioni arcane), **Glifi** (incastri), Tomi | — | Arcano, incastri |
| Speciale | Forgiachiavi (`keysmithing`) | **Chiavi delle Casse**, grimaldelli, lucchetti | — | Casse, Borseggio, Tenuta |
| Speciale | Borseggio (`thievery`) | Oro e drop speciali da 11 bersagli | Grimaldello | Economia, casse della Mano Grigia |
| Speciale | Coltivazione (`farming`) | Orti e frutteti a timer (in parallelo) | — | Cucina, banchetti |
| Combattimento | Eroe (`hero`) | Livello del personaggio (XP dai combattimenti) | — | Attributi, talenti |
| Combattimento | Caccia alle Taglie (`bounty`) | Incarichi di caccia, Marchi, Ricercati | — | Casse delle Taglie |

## 2. Livelli e curva dell'esperienza

- Livello massimo **100** per ogni mansione (si prosegue con le Stelle, docs/13).
- `xp_per_passare(L) = floor(80 × 1,08^L)` → totale per il livello 100: **2.198.634 XP**.

| Livello | XP totali | Livello | XP totali |
|---|---|---|---|
| 10 | 1.074 | 60 | 100.147 |
| 20 | 3.571 | 70 | 217.491 |
| 25 | 5.755 | 80 | 470.835 |
| 30 | 8.967 | 90 | 1.017.791 |
| 40 | 20.625 | 95 | 1.495.995 |
| 50 | 45.796 | 100 | 2.198.634 |

**Ritmo di riferimento** (azione migliore, senza bonus): Lv 50 in ~3 h, Lv 75 in ~12 h, Lv 90 in ~27 h, **Lv 100 in ~45 h** (≈33 h con bonus tipici). Il 90% del tempo sta tra 50 e 100: è voluto.

## 3. I tier di contenuto

Ogni mansione sblocca contenuti a livelli fissi: **1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95** (11 tier).

| Tier | Livello | XP/ora di riferimento | Oro/ora di riferimento |
|---|---|---|---|
| 1 | 1 | 8.000 | 2.000 |
| 2 | 10 | 10.000 | 2.900 |
| 3 | 20 | 12.500 | 4.205 |
| 4 | 30 | 15.625 | 6.097 |
| 5 | 40 | 19.531 | 8.841 |
| 6 | 50 | 24.414 | 12.819 |
| 7 | 60 | 30.518 | 18.588 |
| 8 | 70 | 38.147 | 26.953 |
| 9 | 80 | 47.684 | 39.082 |
| 10 | 90 | 59.605 | 56.669 |
| 11 | 95 | 74.506 | 82.169 |

**R-SK-1:** l'XP di un'azione di raccolta del tier *t* è `xph(t) × durata / 3600` (arrotondata). Ogni tier rende **+25% XP/ora** rispetto al precedente.
**R-SK-2:** il valore di un materiale grezzo del tier *t* è `gph(t) × durata / 3600` (min 1).
**R-SK-3:** durata di raccolta = base + incremento × (t−1): Taglialegna/Miniera 3,0 + 0,25 · Pesca 4,0 + 0,30 (±25% casuale) · Erboristeria 2,6 + 0,20 · Trappole 5,0 + 0,40 · Borseggio 3,0 fisso.

## 4. Azioni di produzione (REGOLE)

- **R-PR-1 — XP:** `xp = xph(t) × durata / 3600 × (1 + 0,25 × (quantità_ingrediente_principale − 1)) × fattore_ricetta`. Le ricette "grandi" (corazza da 4 lingotti) danno più XP per azione ma **meno XP per lingotto**: scelta tra velocità e risparmio.
- **R-PR-2 — Valore:** `valore = (Σ valore ingredienti × 1,15 + manodopera) / quantità_prodotta`, manodopera = `gph(t) × durata / 3600 × 0,5`. Equipaggiamento: moltiplicatore 1,25.
- **R-PR-3 — Livello richiesto:** tier del materiale + scostamento del pezzo (guanti +1, stivali +2, elmo +3, spada +3, scudo +4, gambali +5, spadone +6, corazza +7, ecc.), massimo 99.
- **R-PR-4 — Qualità** (solo equipaggiamento con `quality: true`): Normale ×1,00 · Fine ×1,08 (1 incastro) · Eccellente ×1,16 (2) · Capolavoro ×1,28 (3). Probabilità con *d* = livelli oltre il requisito e *m* = maestria:
  - Capolavoro = min(10%, 0,15%·d + 0,10%·m)
  - Eccellente = min(25%, 1% + 0,4%·d + 0,2%·m)
  - Fine = min(45%, 10% + 1%·d + 0,4%·m)
  - Normale = resto. Il modificatore `craft_quality_pct` moltiplica le tre probabilità superiori.
- **R-PR-5 — Bruciatura (Cucina):** `prob = max(0, 30% − 1%·d − 0,5%·m)`; il cibo bruciato diventa *Cibo Bruciato* (valore 1).
- **R-PR-6 — Lotti:** frecce ×40, rune ×25, oli ×25 per azione.
- **R-PR-7 — Risparmio e doppio:** `skill_save_pct` (max 50%) evita il consumo di tutti gli ingredienti dell'azione; `skill_double_pct` raddoppia i prodotti (oltre il 100%: garantito + probabilità di triplo).

## 5. Raccolta: drop secondari

| Mansione | Drop secondario | Probabilità base |
|---|---|---|
| Taglialegna | Nido d'Uccello (semi, piume, gemme) | 0,5% |
| Miniera | Gemma grezza (tier t−2/t−1/t con pesi 20/30/50) | 1% |
| Pesca | Tesoro Sommerso (oro, gemme, a volte casse/chiavi) | 0,4% |
| Erboristeria | Semi di ortaggi | 2% |
| Trappole | Piume (1–3) | 40% |

Modificatore: `skill_secondary_pct` (relativo) e milestone di maestria 40 (+25%).

## 6. Maestria (per singola azione)

- Livelli **1–50** per ogni azione (es. "Pino", "Spada di Ferro").
- XP maestria per azione = **durata base in secondi** (×`mastery_xp_pct`). Totale per la maestria 50: 48.822 → circa **13,5 h** della stessa azione.
- `maestria_per_passare(m) = floor(60 × 1,09^m)`.
- Bonus continui: **+0,5% doppio per livello** (max +25%).
- Traguardi: 10 → +5% velocità azione · 20 → +5% XP azione · 30 → +10% velocità · 40 → +25% drop secondari · 50 → **Padronanza**: 10% di non consumare ingredienti (produzione) o +1 resa (raccolta) e automazione dell'azione.

## 7. Talenti di mansione

- Ogni 10 livelli (10, 20, …, 100) si sceglie **1 talento su 3** (`data/skill_perks.json`): A = velocità, B = resa, C = specialità (alternata tra XP/casse, risparmio/qualità, ecc.). Ai livelli 50 e 100 i valori sono **doppi** ("firma").
- Con **3 Stelle** nella mansione se ne scelgono **2 su 3**.
- Respec: 1.000 oro × livello della mansione.

## 8. Attrezzi

| Tier | Velocità | Doppio | Note |
|---|---|---|---|
| 1 | +0% | +0% | Rame / Pino |
| 6 | +20% | +5% | Argento Lunare / Legnoferro |
| 11 | +40% | +10% | Caveau |

Grimaldelli (Borseggio): velocità ½ e +1,5% successo per tier. Requisito: livello della mansione = livello del tier.

### 8.1 Come si equipaggia un attrezzo
Un attrezzo conta solo se è **in uso**: Deposito → dettaglio → «Usa come attrezzo» (o trascinarlo nello slot attrezzo della scheda Eroe). Un solo attrezzo per mansione. Gli esemplari uguali in più non servono a niente: «Vendi i doppioni» (docs/07 §7.1). Il dettaglio di ogni attrezzo dice mansione, bonus (letti dai dati) e se è migliore di quello in uso (`ItemUse`).

### 8.2 «Una costruzione per volta» (`single_craft`)
Feedback giocatore (23/10/2026): la Forgiatura ripetuta riempì il Deposito di 60 Grimaldelli di Rame. Regola **sui dati**, non per elenco: ogni azione di produzione con almeno un'uscita **non impilabile** (equipaggiamento, attrezzi) riceve `single_craft: true` dal generatore (`tools/gamedata/skills.py::recipe`). Sono **418 azioni**: Forgiatura (armature a piastre 55, armi 33, attrezzi 33), Carpenteria (armi 44, attrezzi 22), Sartoria (armature di cuoio 55 e di stoffa 55, mantelli 11), Gioielleria (anelli 44, amuleti 44), Incisione Runica (tomi 11), Forgiachiavi (grimaldelli 11). Restano ripetibili lingotti, assi, cuoio, chiavi, cibo, pozioni, munizioni, rune, lucchetti.
- **Online**: dopo UNA costruzione riuscita l'attività si ferma da sola, anche con l'Automazione (nessuna attesa/riavvio) e con la coda; il Registro dice «Costruzione completata: … Premi di nuovo per farne un'altra.». La riga dell'azione porta l'etichetta «Una per volta» e il pulsante è «Costruisci» / «Costruisci un altro» (se ne hai già uno).
- **Coda**: una voce di una costruzione singola vale sempre 1 passo (`qty 1`, qualunque modo si scelga); per N copie si aggiungono N voci (il tetto sono gli slot di coda).
- **Offline**: al massimo una costruzione per azione (limite «single» in `SkillSystem._offline_action`); la coda offline conta una per voce.
- **Simulatore**: `balance_sim` §2b controlla la copertura (tutte e sole le azioni con uscita non impilabile) e non cambia le medie: i ritmi sostenuti non usano queste azioni (non si ripetono), il volume del Mercato resta quello elastico del modello.

## 9. Casse e famigli dalle mansioni

- **Cassa per azione:** `prob = durata / 2400` (≈ 1 cassa ogni 40 minuti) — Raccolta → *Cassa del Raccoglitore*, Produzione → *Cassa dell'Artigiano*, Forgiachiavi → *Cassa della Mano Grigia*; Borseggio `durata / 1200` (Mano Grigia), Coltivazione 2–5% per raccolto (*Cassa del Mercante*). Modificatore `crate_find_pct`.
- **Famiglio di mansione:** `prob = durata / 150.000 × (1 + livello/100)` (≈ 1 ogni 25–40 h); Coltivazione 1/400 raccolti; Borseggio 1/30.000 successi; Eroe 1/25.000 uccisioni; Taglie 1/300 incarichi.
- **Regola del tempo:** in entrambe le formule `durata` è la durata **effettiva** dell'azione (dopo velocità, maestria, Stelle). Così casse e famigli dipendono dal **tempo** passato sulla mansione, non dal numero di azioni: la velocità aumenta XP e materiali, non le casse all'ora (lo fanno solo `crate_find_pct` e `pet_chance_pct`). È la regola dei famigli di Melvor (~69 h a 99, docs/02 §2.6) applicata anche alle casse.

## 10. Borseggio

- Successo: `min(95%, 70% + 1% × (livello − requisito) + 0,3% × maestria + bonus)`; fallimento → **stordimento 3 s** (riducibile).
- Oro per successo calibrato a **1,3 × gph(t)** all'ora (all'80% di successo): rende più oro della raccolta ma nessun materiale.
- Ogni bersaglio ha drop speciali (semi, gemme, rune, chiavi, casse, alberelli) — vedi A1.

## 11. Coltivazione

- **Orto** (ortaggi): 4 appezzamenti iniziali → 8 (5k/25k/120k/600k oro). **Frutteto**: 2 → 4 (50k/400k).
- Crescita da 10 min (Patata) a 150 min (Grano Celeste); frutteti 2–8 h. Resa 5–9 (+1 ogni 10 livelli); alberi 3–6.
- XP: 20% alla semina, 80% al raccolto; tarata a **~metà dell'XP/ora** delle altre mansioni con 6 appezzamenti (è parallela).
- I raccolti pronti restano in attesa (nessuna perdita).

## 12. Apprendisti (Accademia della Tenuta)

- Slot: 1 (Accademia Lv 1), 2 (Lv 15), 3 (Lv 40); +2 dalle Costellazioni (**max 5**).
- Un apprendista svolge **un'azione di raccolta o produzione** (no combattimento, no borseggio) in parallelo, con efficienza `min(75%, 35% + 1% × livello Accademia)` sulla velocità; l'XP va alla mansione; casse e famigli possono cadere; consuma dal Deposito.
- Limite: un apprendista non può fare la stessa azione dell'azione attiva del giocatore.

## 13. Prestigio di mansione (sintesi)

Al livello 100 si può **ottenere una Stella**: la mansione torna al livello 1 (con **Eco**: XP ×3 fino al 50% del record, ×2 fino al 90%, ×1,5 fino al record), si guadagna Polvere Stellare e bonus permanenti. Dettagli in docs/13.
