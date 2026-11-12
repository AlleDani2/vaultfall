# 19 — Bilanciamento: formule, obiettivi, strumenti

> Fonte di verità numerica: `tools/gamedata/core.py` (+ moduli in `tools/gamedata/`). Report: `reports/balance_report.md`. Il gioco legge i parametri da `data/constants.json` e porta le formule in `Formulas.gd`.

## 1. Flusso di lavoro (obbligatorio per ogni modifica di numeri)

```
1. modifica tools/gamedata/*.py          (mai i JSON a mano)
2. python tools/generate_data.py         → data/*.json
3. python tools/validate_data.py         → 0 errori
4. python tools/balance_sim.py           → reports/balance_report.md (controllare i "Controllo automatico")
5. python tools/make_appendices.py
   python tools/make_schema_doc.py
6. python tools/export_reference_values.py → game/tests/reference_values.json (test GUT delle formule)
7. python tools/sync_data.py             → copia data/ in game/data/
```

## 2. Obiettivi di design (verificati dal simulatore)

`python tools/balance_sim.py` termina con **codice 1** se un controllo automatico fallisce (riepilogo in fondo al report). I valori qui sotto sono quelli del report del 23/10/2026 (audit 42).

| Grandezza | Obiettivo | Valore attuale (report) | Controllo automatico |
|---|---|---|---|
| Mansione Lv 50 (senza bonus) | ~3 h | 2,8–2,9 h | — |
| Mansione Lv 100 (senza bonus) | 40–50 h | 44,3–44,6 h | — |
| Mansione Lv 100 (bonus tipici) | 25–35 h | 32,7–34,6 h | — |
| Mansione Lv 100 (budget completo di docs/14: haste 75%, XP +25%) | 18–25 h (D-8, 23/10/2026) | 20,4 h (Taglialegna) | sì |
| TTK mostro normale della zona | 5–10 s | 5,3–8,7 s | sì (limiti larghi 3–16 s) |
| Differenza tra classi (TTK dalla media) | ≤ ±20% | ±9% (Archivio Sommerso) | sì |
| Differenza tra classi sui boss di dungeon (TTK dalla media) | ≤ ±20% | ±18,6% (Portinaio Celeste) | sì (audit 42) |
| Cibo/ora di ogni classe rispetto al Guerriero (stessa zona) | ≤ 1,6× | 1,55× (Ramingo, Valle del Mulino) | sì (audit 42) |
| Danno subito per uccisione | ≤ 35% della vita | 3,5–16% | sì |
| Cibo/ora in combattimento | ≤ 450 | 122–333 | sì |
| Boss di zona | 25–110 s, ≤ 20 cibi | 41–83 s, ≤ 16 cibi | sì |
| Boss di dungeon | 40–160 s, ≤ 40 cibi | 65–141 s, ≤ 21 cibi | sì |
| Boss d'incursione (con la squadra, fasi pesate) | 2–7,5 min, ≤ 60 cibi, classi entro ±20% | 199–356 s, ≤ 26 cibi, ±12% | sì |
| Boss mondiali: fasce (Bronzo/Argento/Oro/Platino = 15/35/55/70% della vita, FIX-COMBATTIMENTO) | al livello del boss ogni classe ≥ Bronzo, la migliore ≥ Argento, non tutte Platino; ≤ 150 cibi per l'Argento | quota 45–61% (prima Platino al 10%: tutte Platino) | sì |
| Breccia: piano 1 e numeri fino al piano 200 | TTK 3–16 s; nessun valore > 2^53 | 6–9 s; ok | sì |
| Breccia: Guardiani graduali (FIX-COMBATTIMENTO) | TTK del Guardiano ≤ ×3 per decina di piani | ×1,70 (prima ×5-6) | sì |
| Potenziamenti attivi una parte sensata del tempo | durata/ricarica ≥ 20% | 15 su 15 | sì |
| Ibride: crescita × moltiplicatore vs classi base | 1,00–1,25 | 1,15 | sì |
| Zone: XP della zona precedente a sblocco+3 | ≤ 90% | ≤ 82% | sì |
| Borseggio (successo reale 95%) vs raccolta (oro) | 0,9–1,6× (oro intero: ai tier bassi pesa l'arrotondamento) | 0,95–1,59× (prima, a p=0,8: 1,23–1,46× ma 1,6–1,9×gph al p reale) | sì (audit 53 E5) |
| Somma delle fonti: attiva migliore (≤ 1,5×) + Apprendisti + Bottega (tetto 0,6) + Spedizioni (0,4) | ≤ 3,6×gph senza bonus | 3,43–3,59× (prima ≈ 4,5×) | sì (audit 53) |
| Ritorno atteso casse (chiave comprata, pity inclusa) | 55–80% | 62–72% | sì |
| Eventi stagionali: Casse evento/ora dalle cadute · Casse per edizione · bonus temporaneo (guadagno relativo sul tipico docs/14) | ≤ 0,6/ora · ≤ 20 · ≤ 15% (una fonte ≤ 10% su «all»; Lv 100 col budget ≥ 18 h) | 0,48/ora (Eco 0,24) · 18 · 5–13,9% · 18,9 h | sì (T-11.3) |
| ★ effettive con pity (morbida da 180, +0,03% a apertura, garantita alla 300ª: raggiunta nel 4,6% delle serie) | 1 ogni 150–220 aperture | 1 ogni 175,0 (0,571%, calcolo esatto); con «Destino Paziente» al massimo (−4 aperture per livello, max 40) 1 ogni 155,8 | sì (audit 53; prima 200/+0,05%/500: garanzia mai raggiunta) |
| Commesse (rendimento orario, materiali intermedi compresi, secondari come le piume inclusi) | ≤ 1,5 × gph del tier (R-EC-3) | max 1,50× (mediana 1,11×); Bottega in parallelo a parte (max 0,6×) | sì (audit 42/53) |
| Commesse: fattibilità (Commessa più piccola, produzione propria con ingredienti, Orto e beni dell'Emporio compresi) | ≤ 24 h (`orders_rules.max_production_hours`) | max 23,9 h; 131 oggetti fuori dal pool (gemme e ciò che le usa; prima 128 oggetti oltre, fino a 252 h) | sì (audit 84) |
| Sfida dei Collezionisti | ★ ≤ 40% del punteggio atteso; 1° posto con 35 aperture/settimana 10–35%, crescente | ★ 28% (era 61% con 1000 punti); 20% (era 19%); 3% → 99% da 10 a 150 aperture | sì (audit 84) |
| Vendita diretta al Mercato (con elasticità 8 h) | ≤ 1,5 × gph | max 1,25× (Frecce T1-4 non vendibili) | sì (audit 53 E3) |
| Set di equipaggiamento comprato dai mercanti (valore × 6,5) | 1,0–4,0 ore di gph(tier) (la forgia resta la via principale) | 1,0–3,2 ore (prima: 0,3–0,9) | sì (audit 50) |
| Prima Rifondazione Tenuta | 8–15 h di Tenuta | 14,0 h nel simulatore (Bottega 0,6×gph) · coloni ogni 2 min (era 6; soglia 45.000 Punti; test_estate_pacing) | sì |
| Tempo per Stella di Mansione (a regime) | ≥ 6 h (≥ 4 h con le Costellazioni al massimo), convergente | 12,4 h base · 9,1 h tipico · 6,2 h budget · 4,3 h Costellazioni | sì |
| Ore per Era del Mondo | ≤ 60 h, stabile | 3–50 h, poi ~25 h | sì |
| Rito (Stella di prova, una per mansione, dal Lv 75) | 5–25 h senza bonus di attrezzo | 11,6 h (Autarchico) | sì (§10, §12) |
| Polvere Stellare e Costellazioni: tempo minimo per Stella con Polvere reinvestita | ≥ 4 h (pavimento), convergente | 4,3 h (4,26 h a regime); prime 10 Stelle −8,9% con la Polvere delle imprese (limite 15%) | sì (§10) |
| Soci della Rifondazione | crescita lineare nel tempo, nessun anello né muro | 400 Soci / 200 Soci = ×2,42 di ore | sì (§10) |
| Costellazioni: nodi infiniti | nessun nodo infinito su acceleratori (XP, velocità, doppio, Eco) né sulla valuta di uno strato (Polvere, Soci) | infiniti solo danno, vita, difesa, oro, drop, Maestria, mercenari; «Polvere Stellare» 20 livelli (era infinito, audit 84) | sì (§10) |
| Ere: moltiplicatori e Polvere del Custode | mostri ×1,35^(N−1), ricompense ×(1+0,3(N−1)); ripetere il Custode paga 0% | Ranghi per Era ≈ 7,65; Polvere dei Custodi ≤ 11% dei Ranghi richiesti (limite 50%) | sì (§11) |
| Prove del Custode | bonus finiti, Polvere finita (non coltivabile) | 360 Polvere in tutto (≈ 36 Stelle); 7,5 Ranghi in tutto, meno di un'Era | sì (§11) |
| Modalità Autarchico | Stella ≤ 2× il tipico; Rifondazione ≤ ×2 | 44,5 h contro 30,7 h; 16 h contro 13 h (×1,20) | sì (§12) |
| Modalità Estremo: costo di una morte | 30–70% della prima salita | 47–55%; offline l'Eroe si ferma prima del rischio | sì (§12) |
| Eco profonda (nodo dormiente) | applicata per intero porterebbe la Stella a 1,6 h: resta DORMIENTE finché non ritarata | non acquistabile (`max_level` 0) | sì (§10) |

> Il report corrente (`reports/balance_report.md`) elenca **tutti** i controlli automatici nel «Riepilogo» (oltre 60 righe, compresi i 4 eventi stagionali) e dice «Obiettivi violati: nessuno». Le ritarature D-8/D-9 (23/10/2026) sono già dentro i valori sopra.

### 2b. Combattimento misurato col motore vero (FIX-COMBATTIMENTO, 23/10/2026, resoconto 65)

Il simulatore Python è analitico; questi numeri vengono dal vero `CombatSystem`/`CombatSim` headless (`tools/analysis/q4_sweep.gd`,
riassunti con `q4_classes.py`, `q4_endgame_rep.py`). Si rifanno dopo ogni ritaratura del combattimento.

| Grandezza | Obiettivo | Prima (QA4) | Ora |
|---|---|---|---|
| XP/h delle 12 classi (zone 4-10, scenario metà zona) | ±20% dalla media | 0,73–1,22 (max/min 1,67) | 0,91–1,16 (max/min 1,27) |
| Ibride rispetto alle classi non ibride | 0,95–1,05 | 0,73–0,80 | 0,96–0,99 |
| Offline contro tick (zone e boss non letali) | ≤ 4% | −3,1…+2,2% | −2,2…+2,5% |
| Offline contro tick su un boss letale (Drago della Tempesta, Guerriero Lv 85) | ≤ 4% uccisioni e morti | 0 morti contro 26, XP +34% | uccisioni −4%, morti +18% (rumore del tick ±11%) |
| Zona nuova contro la precedente a sblocco+3 (XP/h) | conviene entro 2-3 livelli | 0,83–0,91 (mai conveniente fino a +10) | 1,02–1,11 (pari a +2) |
| Cuore del Caveau, Eroe al livello di sblocco (95), Cinturone II, senza squadra | ogni build ≥ 0,5 di vittoria, ≤ 60 cibi | 3 classi su 12 (0,00 per le altre) | tutte ≥ 0,67, ≤ 61 cibi |
| Breccia: limite dei piani (rango 0 / 24 / 24 Eccellente / 60 Eccellente) | progredire coi Ranghi | 10 / 20 / 30 / 30 | 20-30 / 30-50 / 40-60 / 80-90 |
| Nido del Tuono a Lv 88 (corse vere) | difficoltà monotona | 6 fallimenti su 15 | 0 su 8 (Atrio 0 su 8) |
| Prova Vetro V a Lv 100 (P(morte)) | superabile da ≥ 2 classi su 3 | 0,76–1,0 | 0,00–0,30 |
| Potenziamenti (buff/debuff/scudi) | valore ≥ 0 | 6 su 8 negativi | tutti ≥ 0 (offensivi +2-8% uccisioni/h) |
| Formule GDScript contro Python (105 casi limite) | 0 differenze | 31 | 0 |
| Corsa (CORSA, resoconto 91; `balance_sim` §4e, modello analitico) | guadagno medio sul ciclo +5…+15% XP/h, picco ≤ +40%, una scelta ogni ≤ 10 min | — | +12,2…+14,8%, picco +30,2%, ciclo 47-58 min, una scelta ogni ≤ 5,1 min; casse del Campione +11% |
| Vigore (3 punti) sul danno netto subito (motore, Lv 60) | il cibo non si azzera con 3 punti | −64…−92% | −25…−52% |
| Rami di talento: classe base con entrambi i rami | come un ramo solo | +9…+17% uccisioni/h | +3…+4% (= un ramo) |
| Brutalità / Punto Debole (uccisioni/h) | in linea con gli altri nodi | +0,5% / +1,2-2,3% | +3,0% / +4,5% |
| Preparazione dei boss: danno subito con la risposta (78 scontri, `q4_sweep mode=mech` con e senza `noans=1`) | aiuta chi si prepara, non banalizza | — | 0…−14% (media −2%), nessuna vittoria/sconfitta cambiata |
| Q97 · XP/h delle classi (zone 4-10, metà zona, stile migliore delle ibride; `q97_classes.py`) | max/min ≤ 1,2 | 1,25 (1,37 con l'equipaggiamento ibrido sbagliato) | 1,14 (1,24 con tutti gli stili): Berserker 1,07, Guerriero 0,95, Ramingo 0,94 |
| Q97 · Talenti di specializzazione (Lv 60, tutti i punti) | nessun ramo oltre +15% uccisioni/h | Berserker +22%, Paladino +7%, Domatore +4% | Berserker ~+18% (Impeto, Rabbia, Titano ritarati), Paladino +8%, il compagno del Domatore ora usato |
| Q97 · Muro di Scudi (uccisioni/h, in prima posizione e da sola) | ≥ 0 | −3,7…−4,9% (perdita di vita −10…−15%) | −2,5…+2,3% in prima posizione, +4…+6% da sola (`mode=abil`, prima 0%); perdita di vita −21…−40% (da sola −32…−39%): costo 30 → 10, 9 s, +15% danno (il residuo del Paladino viene dallo scambio con l’abilità spostata, non dal costo) |
| Q97 · Primo combattimento senza equipaggiamento (10 min, `q97_newhero.gd`) | costo dell'errore basso | 10-11 morti, ogni morte 10 s + 5 min Ferito, XP 417 | 11 morti, ogni morte 3 s + 60 s Ferito, XP 508; con divisa di rame, spada e cibo: 0 morti, XP 1075 in 10 min |

### 2.y Deposito: Armeria e regola di spazio (UI F15, `balance_sim.py` §5e)

L'equipaggiamento e gli attrezzi non contano come Spazio (`constants.bank.space`: `free_categories`, `gear_cap` 300, `gear_warn_pct` 95). Per questo `study.need_base` scende da 30 a 12 (restano le pile uniche: chiavi, Casse, glifi). Prezzo, tetto (340 acquisti), base 100 e fonti gratuite non cambiano. Due controlli nuovi: **Armeria** (`gear_cap` ≥ 2 × bisogno a 150 h, con `study.gear_need` = (5 slot × 11 set + 6 attrezzi × 2 scorte) × 1,15 = 77 pezzi, quindi ≥ 154) e **classi dello spazio** (le categorie libere esistono nei dati e non sono mai impilabili). Restano il costo di fase ≤ 35% (ora al massimo 8,9%, prima 22,2%) e la capacità massima ≥ 2× bisogno a 150 h (750 contro 344). Costo cumulativo degli spazi da comprare fino a 150 h: 353.857 → 187.132 oro (−47%); spazi da comprare 135 → 114. Gli spazi non danno oro né accelerano alcuno strato (regola 9 invariata). La ritaratura di `need_base` con il bot è nel resoconto `docs/ui_redesign/23_RESOCONTO_F15.md`.

### 2.x Sabbia del Custode (UI F13, `balance_sim.py::time_push_report`)

La Sabbia è un fondo finito di tempo (600 s, ricarica 5% online e **0,3%** offline), quindi il guadagno giornaliero dipende solo dalle ore presenti e mai dal numero di clic. Sette controlli automatici: (1) guadagno massimo ≤ 8% delle ore presenti (4 h e 16 h con notte di 12 h offline); (2) ≤ 1 Clessidra (3.600 s) al giorno; (3) pavimenti delle Stelle con la Sabbia al massimo (≥ 6 h a regime, ≥ 4 h con le Costellazioni al massimo); (4) fine Cap. I ≥ 55 min (α = 0,6); (5) prima Rifondazione in 8–15 h (α = 0,35); (6) tempi per Era entro il 6% (α = 0,35); (7) nessun potenziamento infinito. Il doc 03 proponeva lo 0,5% offline: con quel valore il pavimento delle Costellazioni scendeva a 3,995 h, per questo è 0,3% (4,018 h). Misura reale con il bot: `reports/time_push_bot.md`.

## 3. Formule principali (riassunto)

| Sistema | Formula |
|---|---|
| XP per livello | `floor(80 × 1,08^L)` |
| XP/ora tier *t* | `8.000 × 1,25^(t−1)` |
| Oro/ora tier *t* | `2.000 × 1,45^(t−1)` |
| XP azione di raccolta | `xph(t) × durata/3600` |
| XP azione di produzione | `xph(t) × durata/3600 × (1 + 0,25·(n_input_principale−1)) × fattore` |
| Valore grezzo | `gph(t) × durata/3600` |
| Valore prodotto | `(Σ ingredienti × 1,15 + gph(t)·durata/3600·0,5) / quantità` (equip. ×1,25) |
| Maestria | `floor(60 × 1,09^m)`, XP = durata dell'azione |
| Statistiche armi | danno `6 × 1,4^(t−1) × molt`, precisione `10 × 1,4^(t−1)`, AP `5·t^1,3` |
| Set armatura | armatura `40 × 1,4^(t−1)` (piastre), vita `30 × 1,4^(t−1)` |
| Mostri | vita `23,5 × 1,0575^L`, colpo max `13,5 × 1,0364^L`, precisione `20 + 7,5L`, evasione `15 + 6,66L` |
| XP sui mostri bassi | ×`max(25%, 1 − 6% × (L_eroe − L_mostro − 3))`, mostri dal livello 91 esclusi (`overlevel_xp`) |
| Interi dalle formule | saturati a ±2^62, NaN → 0; potenze che traboccano → inf (uguali in Python e GDScript) |
| Colpo | `clamp(0,75·√(prec/evas), 5%, 98%)` |
| Riduzione | `difesa / (difesa + 30·1,0375^L_att)`, max 85% |
| Cibo | cura `25 × 1,4^(t−1)` (carne ×0,85) |
| Casse | Rara = 1% gph(tier chiave), ×5/×25/×125/×500 (★); chiave in Emporio = 10% gph; pity esatta `core.relic_pity_stats`; condizioni `core.condition_odds` |
| Tenuta | unità/h `30·L·2^traguardi`, costo `base·1,11^L·1,45^(banda−1)`, Soci `floor(15·√(PP/10.000))` |
| Stelle | XP `60%·(1−0,92^s)` more, velocità `25%·(1−0,9^s)`, extra `cap·(1−0,95^s)`, Polvere `10 + 2(n−1)`; tempo per stella ≥ 6 h |
| Ere | mostri ×1,35^(N−1), ricompense ×(1+0,3(N−1)); Rango ×1,04 sulle statistiche base (cap 12·N); Essenza ×N per drop |
| Polvere del Custode e Prove | Custode `5 × Era` solo alla 1ª uccisione di ogni Era (poi `stardust_repeat_pct` = 0); 40 premi delle Prove una volta ciascuno (+5% per famiglia, 360 Polvere). Controlli e superabilità dei gradi: `balance_sim.py` §11 |
| Costellazioni | costo `ceil(base × crescita^livello)` |

## 4. Numeri grandi

- Tutte le grandezze di combattimento e l'oro sono `float` (double, fino a ~1,8e308); quantità e contatori `int` (64 bit).
- Il design **impedisce esplosioni**: prestigi con effetti lineari e costi esponenziali (crescita logaritmica), Ere con ricompense lineari e mostri esponenziali compensati dai ranghi. Nell'Era 500 i mostri hanno ~1e65 di vita: ancora gestibile; oltre l'Era ~2.000 servirebbe una rappresentazione logaritmica (scenario irrealistico; documentato come limite noto).
- La formattazione (docs/16 §5) passa alla notazione scientifica oltre `Dc` (1e33).

## 5. Come ribilanciare (ricette)

| Problema | Leva consigliata |
|---|---|
| Una mansione troppo lenta | `GATHER_TIME` o fattore XP della ricetta (non la curva XP globale) |
| Combattimento troppo facile in tutte le zone | `MONSTER_HP_A` (vita) o `ABILITY_FACTOR` atteso |
| Una classe troppo forte | moltiplicatori dell'arma (`WEAPONS`) o del tipo di armatura (`ARMOR_TYPES`), mai i mostri |
| Troppo oro | `GPH_GROWTH` / tassa / pozzi; mai abbassare i prezzi già visti dai giocatori senza annuncio |
| Casse troppo generose | `SKIN_VALUE_FRACTION_OF_GPH` o probabilità di drop delle casse (non le probabilità di rarità: sono una promessa pubblica) |
| Tenuta troppo lenta/veloce | `ESTATE_UNITS_PER_LEVEL`, `ESTATE_COST_GROWTH`, soglia Prosperità |
| Stelle troppo lente/veloci | `STAR_XP_CAP_PCT` / `STAR_XP_DECAY` (mai un bonus lineare auto-rinforzante: docs/13 §1) |
| Ere troppo lente/veloci | `ERA_ESSENCE_DROP`, `RANK_ESSENCE_FORMULA`, `RANK_GOLD_FORMULA`; `ERA_MONSTER_MULT` solo con nuova verifica del §9 |

**R-BAL-1:** le probabilità di rarità delle casse mostrate ai giocatori **non si cambiano** dopo l'uscita senza annuncio esplicito nelle note di patch.
**R-BAL-2:** ogni modifica di bilanciamento va nelle note di versione con i numeri vecchi e nuovi.
**R-BAL-3:** dopo l'uscita, una modifica che peggiora i progressi già acquisiti (nerf) richiede una compensazione (es. rimborso della Polvere spesa nel nodo modificato).
