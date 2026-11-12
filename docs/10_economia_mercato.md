# 10 — Economia: valute, fonti e pozzi, Mercato dinamico, Commesse, Fazioni

> Dati: `data/shop.json`, `data/market_rules.json`, `data/gazette_events.json`, `data/orders_rules.json`, `data/factions.json`, `data/currency_shops.json`, `data/contract_rules.json`. Numeri: `reports/balance_report.md` §5–6.

## 1. Valute

| Valuta | Fonte principale | Si spende in | Vendibile |
|---|---|---|---|
| **Oro** | vendite al Mercato, Borseggio, mostri, Commesse, Bottega della Tenuta, missioni | Emporio, Mercato (acquisti), edifici, Deposito, ranghi, respec, chiavi in Emporio, capsule | — |
| **Schegge del Caveau** | fusione di oggetti da cassa | chiavi, Affinatura, Banco dei Caveau | no |
| **Marchi di Taglia** | taglie | Banco delle Taglie | no |
| **Sigilli d'Incursione** | incursioni | Sala dei Trofei (inclusi gli unici: protezione dalla sfortuna) | no |
| **Frammenti di Breccia** | Breccia | Bazar della Breccia | no |
| **Gettoni di Commissione** | commesse giornaliere/settimanali | negozio dei gettoni | no |
| **Polvere Stellare** | Stelle di Mansione, imprese, Custode nelle Ere, capitoli | Costellazioni | no |
| **Essenza d'Era** | élite, boss, dungeon, incursioni (da Era I, ×era) | Rango degli oggetti | no |
| **Valuta evento** | attività durante gli eventi | casse e premi dell'evento | no |

**R-EC-1:** nessuna valuta si compra con denaro reale. **R-EC-2:** ogni valuta ha almeno un pozzo infinito o ripetibile (nessuna valuta "morta").

## 2. Curve di riferimento

- **Oro/ora di riferimento** `gph(t) = 2.000 × 1,45^(t−1)`: T1 2.000 · T5 8.841 · T8 26.953 · T10 56.669 · T11 82.169.
- Fonti a parità di tier (senza bonus): raccolta e vendita dei grezzi ≈ 1,0×gph; **Borseggio ≈ 1,0×gph a successo 80% e ≤ 1,5×gph al successo reale 95%** (niente materiali; era 1,3 → 1,6–1,9 a regime, audit 53 E5); combattimento ≈ 0,6×gph in oro diretto + drop + casse; Tenuta 0,3–0,8×gph a regime (passiva).
- Valori degli oggetti: grezzi = gph × durata; prodotti = Σ ingredienti × 1,15 + manodopera; equipaggiamento ×1,25 (docs/04 §4).

## 3. Mercato di Vaelmora (dinamico)

```
prezzo_vendita = valore × tendenza(categoria) × domanda(oggetto) × (1 − tassa)
domanda        = 1 / (1 + venduti_recenti / volume_elastico)
venduti_recenti decade con emivita 6 h
volume_elastico = 8 ore di produzione dell'azione migliore che crea l'oggetto, equipaggiamento compreso (min 20; oggetti da drop 300/tier)
prezzo_acquisto (dai PNG) = valore × 1,8 × tendenza   (scorte limitate, rifornite ogni 60 min)
                           (equipaggiamento: valore × 6,5 × tendenza — un set intero = 1,0–3,2 ore di gph(tier), audit 50 / E47-8)
tassa: 5% (risorse) / 10% (oggetti da cassa); ridotta da Licenze (−20%/−20%), Costellazioni, fazione (cap 80%)
```

- **Tendenza** per categoria: processo di Ornstein-Uhlenbeck giornaliero (θ 0,20, σ 0,07) limitato a [0,70; 1,40]. Grafico a linee degli ultimi 30 giorni per ogni oggetto.
- **Gazzetta di Vaelmora:** ogni 3 h un evento casuale (`gazette_events.json`) modifica una categoria (×0,70–×1,40 per 3–6 h): sciopero dei fabbri, fiera dei collezionisti, paura del morbo... Mostrata come "ticker" nel menù Città.
- **Resa a regime (audit 53, QA3):** con 8 h di elasticità un flusso di grezzi venduto ogni ora rende 0,46–0,55×gph, quattro flussi alternati ~0,9×gph (con 4 h: 0,30 e 0,62). Le Finiture si vendono a valore × tendenza × (1 − tassa) **senza** `market_sell_pct` né `gold_gain_pct` (ritorno atteso delle Casse 63–73% della chiave, non 133–154%). Le Capsule cosmetiche e le Frecce di tier 1-4 non si rivendono.
- Effetto voluto: **vendere tanto della stessa cosa abbassa il prezzo** → conviene diversificare, trasformare, aspettare le notizie, usare le Commesse. È il cuore "tycoon" del commercio.

## 4. Commesse (ordini dei PNG)

4 posti (+1 dalla Lega Amico, +2 dalle Costellazioni), rinnovo ogni 4 h, vita di 7 giorni anche per le commesse dei PNG (`orders_rules.lifetime_days`, `deadline_h` = 168: il codice usava già 7 giorni, i dati dicevano 24 h; allineati nell'audit 84). Dal pool sono esclusi gli oggetti la cui commessa più piccola chiederebbe più di `max_production_hours` (24) di produzione propria (gemme tagliate e tutto ciò che le usa: anelli, amuleti, bastoni, bacchette; la gemma grezza esce dall'1% delle azioni di Miniera), controllo «commesse: fattibilità» del simulatore. Le **Commesse giornaliere (3) e settimanali (5)** a gettoni (`ContractSystem`, `contract_rules.json`) seguono invece la **regola dei 7 giorni** anti-FOMO: le non completate restano fino a 7 giorni (le settimanali 14), si ripristinano a mezzanotte locale, 1 rinnovo gratuito al giorno, nessuna ricompensa esclusiva a tempo. Ai fini del giocatore vale la regola dei 7 giorni. I giorni sono di calendario anche oltre il limite offline (R-OFF-6, audit 84): chi torna dopo una settimana trova le giornaliere degli ultimi giorni. Ogni commessa chiede N unità di un oggetto **già sbloccato** dal giocatore e paga `qty × valore × (1,0–1,2)` (quantità = 0,1–0,3 volte il volume elastico, cioè 0,8–2,4 ore di produzione) + reputazione della fazione legata alla categoria + 10% di cassa. **Pezzi singoli (audit 119):** equipaggiamento e attrezzi non si ripetono (`single_craft`: una costruzione per volta), quindi una Commessa di un oggetto non impilabile chiede al massimo `orders_rules.unique_qty_max` (3) pezzi (la ricompensa scala di conseguenza; prima c'erano 1.912 Spade di Rame da costruire a mano); le Commesse già in bacheca nei vecchi salvataggi si riducono al tetto al caricamento, e le giornaliere «Produci N» non scelgono azioni a costruzione singola. Rifiutare una commessa la sostituisce dopo 30 minuti.

## 5. Emporio (pozzi principali)

| Voce | Prezzo |
|---|---|
| Auto-mangiare I / II / III | 2.000 / 150.000 / 12.000.000 |
| Coda azioni I / II | 4.000 / 3.000.000 |
| Set di equipaggiamento (5) | 50.000 × 3^n |
| Secondo Reliquiario (Eroe 50) | 8.000.000 |
| Licenza di Mercato / di Gilda | 100.000 / 20.000.000 |
| Spazi del Deposito | min(5.000.000; 200 × 1,03^n) — era 800 × 1,07^n (23/10/2026, resoconto 114: il vecchio prezzo costava più dell'oro dell'intera fase già al 26° spazio) |
| Appezzamenti dell'Orto / Frutteto | 5k–600k / 50k–400k |
| Chiavi T1–T6 (max 5/giorno) | 200 / 420 / 880 / 1.900 / 3.900 / 8.200 |
| Capsule cosmetiche (non rivendibili) | 2.500 |
| Fiale, semi base, attrezzi di rame/pino | pochi oro |

Altri pozzi: edifici della Tenuta (esponenziali), mercenari (assunzione), ranghi degli oggetti, respec, Targhette, rerolls di Taglie e Taverna, tassa di mercato.

## 6. Fazioni e reputazione

5 fazioni con 5 gradi (0 / 1.000 / 5.000 / 15.000 / 40.000). Bonus per grado (`factions.json → rank_rewards`), es. Lega dei Mercanti: −10% tassa → +1 commessa → −5% costo edifici → +10% Tenuta (Esaltato + titolo). Fonti: Commesse, incarichi di fazione (6 per fazione), eventi.

## 7. Controlli anti-inflazione (REGOLE)

- **R-EC-3b (D-8, 23/10/2026):** la Bottega della Tenuta paga al massimo **0,8 × gph(tier)** all'ora (`constants.json: estate.shop_income_cap_gph`); prima il reddito saliva fino a 90× gph. Dopo il tetto la produzione genera solo Prosperità.
- **R-EC-3c (audit 53 QA3):** oltre al singolo tetto, la **somma** della fonte attiva migliore (Borseggio, raccolta venduta a 4 flussi, miglior catena) più le passive (Apprendisti, Bottega, Spedizioni) non supera **3,6×gph** senza bonus (controllo `somma_fonti` in `balance_sim`; prima ≈ 4,5×). Parametri: Bottega tetto 0,6×gph, Apprendisti efficienza `min(0,35; 0,15 + 0,01·L)` (dati `estate_buildings.academy.effect.efficiency`), Spedizioni stimate 0,4×gph.
- **R-EC-3d:** un oggetto comprabile all'Emporio e rivendibile non deve dare utile nemmeno con i bonus massimi (validatore: valore × 0,99 × 1,5 × 1,4 ≤ prezzo).
- **R-EC-3e (23/10/2026):** il riciclo dei doppioni (`constants.bank.recycle_pct`, solo attrezzi) rende al massimo il valore dell'oggetto, che per R-EC-3d è inferiore al prezzo d'acquisto e alla somma dei materiali: non è una fonte di profitto. Le costruzioni di equipaggiamento sono «una per volta» (`single_craft`, docs/04 §8.2): la produzione in serie di non impilabili per rivenderli non è più automatica, e il Mercato li compra comunque con domanda elastica.
- **R-EC-3:** nessuna attività deve rendere più di **1,5×gph(t)** in oro diretto senza bonus (verifica del simulatore).
- **R-EC-4:** ogni nuova fonte d'oro va accompagnata da un pozzo che cresce allo stesso ritmo.
- **R-EC-5:** prezzi dell'Emporio in oro fissi, ma i costi a crescita esponenziale (Deposito, Tenuta, set) assorbono l'eccesso nel lungo periodo.
- **R-EC-6:** le chiavi non si vendono; le casse valgono poco; il ritorno atteso delle casse resta tra il 55% e l'80% del prezzo di una chiave comprata.
- **R-EC-7:** le Ere moltiplicano l'oro in modo **lineare** (+30% per era), i costi dei ranghi crescono in modo **polinomiale**: niente esplosioni numeriche.
