# 11 — La Tenuta (tycoon), Coloni, Mercenari, Spedizioni, Luoghi Segreti

> Dati: `data/estate_buildings.json`, `data/estate_rules.json`, `data/mercenary_rules.json`, `data/expedition_rules.json`, `data/secret_spots.json`. Simulazione: `reports/balance_report.md` §7.

## 1. La Tenuta in breve

Una **gestionale idle** in stile AdVenture Capitalist che produce risorse 24/7 (anche offline, entro il limite offline), con traguardi che raddoppiano la produzione e un prestigio proprio: la **Rifondazione**, che dà **Soci** (+2% produzione ciascuno, permanenti).

## 2. Edifici

| Edificio | Tipo | Effetto | Sblocco |
|---|---|---|---|
| Casolare | abitazioni | +3 posti coloni per livello (5 + 3·L) | Cap. II |
| Segheria | produttore | tronchi del tier scelto | Cap. II |
| Pozzo Minerario | produttore | minerali, carbone, granito | Cap. II |
| Peschiera | produttore | pesce crudo | Cap. II |
| Campi | produttore | fibre e ortaggi | Cap. III |
| Allevamento | produttore | pelli, carne, piume | Cap. III |
| Bottega | venditore | vende le merci del Magazzino all'80% del valore (200·L·2^traguardi unità/h), **fino a 0,6 × gph(tier) all'ora** (D-8): oltre il tetto la produzione conta solo come Punti Prosperità | Cap. II |
| Magazzino | deposito | capienza 500·L^1,2 unità | Cap. II |
| Caveau Privato | generatore di casse | 1 cassa ogni 8/(1+0,05·L) h, 5% chiave | Cap. III |
| Accademia | apprendisti | 1/2/3 slot a Lv 1/15/40, efficienza min(35%, 15%+L%) (dati; era min(75%, 35%+L%): audit 53, somma delle fonti) | Cap. III | **Solo raccolta e produzione ripetibili:** gli apprendisti non costruiscono pezzi singoli (`single_craft`: equipaggiamento e attrezzi, una costruzione per volta, audit 119); prima ne producevano ~320 l'ora.
| Taverna | gilda | mercenari 4 + L/5 (max 16), spedizioni 1 + L/15 (max 4) | Cap. IV |

## 3. Formule (REGOLE)

```
unità/ora (produttore)  = 30 × L × 2^(traguardi) × (1 + 0,02 × soci) × (1 + estate_prod_pct/100) × fattore_cibo
traguardi               = numero di soglie raggiunte tra [10, 25, 50, 100, 150, 200, 300, 400, 500, 750, 1000]
costo livello L→L+1     = round_nice(base × 1,11^L × 1,45^(banda−1)) oro + materiali della banda
banda                   = min(11, 1 + L // 10)
materiali               = assi(banda) × ceil(2 + 0,5L), lingotti(banda) × ceil(1 + 0,3L), granito × L//5 (da L 15), lucchetti (Magazzino, Caveau Privato) 1 ogni 10 livelli
tier prodotto           = scelto dal giocatore ≤ min(tier sbloccato nella mansione collegata, grado dell'edificio)
grado                   = upgrade dell'edificio ogni 10 livelli (richiede il tier nella mansione)
```

- **Coloni:** arrivano 1 ogni 2 minuti (`estate_rules.settlers.arrival_min` = 2, valore attuale dei dati; era 6, audit 51; l'ipotesi iniziale di 10 minuti in OPEN_QUESTIONS E-1 è superata) fino al limite del Casolare (5 + 3 per livello); **ogni livello di edificio (tranne il Casolare) richiede 1 colono assegnato**. Consumano **1 razione di cibo/ora** dalla Dispensa (qualsiasi cibo; la carne cotta è segnata come razione ideale). Dispensa vuota → produzione ×0,75 (`estate_rules.settlers.starving_mult`; era ×0,5, QA81 M1). **Dispensa automatica** (interruttore sulla scheda della Tenuta, attivo di base): con la Dispensa vuota e coloni da sfamare, prende da sola dal Deposito fino a `estate_tuning.pantry_auto_target_h` (24 h) di razioni, dal cibo più economico; mai cibo bloccato, mai i cibi negli slot cibo dell'Eroe, mai i banchetti. Stesso codice online e offline; il Bentornato dice quante razioni sono state prese o, se il Deposito non aveva cibo adatto, di quanto è calata la produzione.
- **Raccolta:** manuale ("Raccogli tutto" → al Deposito) o automatica (nodo Costellazione). La Bottega vende solo ciò che il giocatore marca come "in vendita".

## 4. Rifondazione (prestigio della Tenuta, infinito)

- Requisito: **30.000 Punti Prosperità** (FIX-MEDIO, era 45.000: col sistema vero il bot QA2 la raggiungeva dopo ~22 h di Tenuta) (= unità prodotte a vita dalla Tenuta, **indipendenti dal tier**).
- **Soci totali = floor(15 × √(punti_prosperità / 10.000))**; alla Rifondazione si ottengono i Soci non ancora riscossi.
- Si azzerano: livelli degli edifici (Casolare a 1), Magazzino, coloni. Restano: Soci, gradi sbloccati, statistiche.
- Simulazione: prima Rifondazione a **~10 h** di Tenuta con ~25 Soci (+50%); la corsa successiva raggiunge la stessa soglia in ~6–7 h. Consiglio mostrato in UI: "Rifonda quando i nuovi Soci sono almeno il 50% di quelli posseduti".

## 5. Mercenari (Taverna)

- Ruoli: **Difensore, Guaritore, Assaltatore, Esploratore**. Rarità: Comune 60% · Non comune 28% · Raro 9% · Epico 2,5% · Leggendario 0,5% (migliora di +0,5% relativo per livello di Taverna).
- Potere = `potere_base × (1 + 0,1 × (livello − 1)) × (1 + merc_power_pct) × (1 + 0,05 × tier_equipaggiamento)`. Livelli fino a 30–50 secondo rarità; XP = 40/ora di spedizione.
- 1–3 **tratti** (Fortunato, Instancabile, Coraggioso, Avido, Erudito, Robusto, Raccoglitore, Cartografo, Veterano, Condottiero, Maldestro, Predone).
- Reclutamento: 3 candidati ogni 6 h, costo `1.000 × molt_rarità × (1 + 0,02 × livello Taverna)`.
- Equipaggiamento dei mercenari: uno "kit" per tier (consuma 1 arma + 1 corazza qualsiasi del tier) → +5% potere per tier.

## 6. Spedizioni

- Tipi: **Ricognizione** (grezzi della zona), **Scorta** (oro), **Recupero** (casse e chiavi), **Caccia** (materiali dei mostri), **Cartografia** (frammenti di mappa, XP mercenari).
- Durate 0,5 / 1 / 2 / 4 / 8 / 12 h (ricompense ×1,00 → ×1,25). Squadra 1–4.
- Potere richiesto `30 × 1,35^(zona−1) × dimensione_consigliata`; **successo = clamp(1,6 × P/(P + Req) − 0,15, 5%, 98%)**. Fallimento: 25% delle ricompense, 30% di infortunio (2 h).
- Valore ricompense/ora ≈ `0,6 × gph(tier_zona) × dimensione/4`; Recupero: 1 cassa ogni 4 h + 10% chiave.

## 7. Luoghi Segreti

10 **Frammenti di Mappa** rivelano per 24 h un luogo segreto di una mansione di raccolta (Bosco Nascosto, Vena Cava, Pozza al Chiaro di Luna, Prato delle Fate, Tana Stellare): un'azione speciale con **+50% XP** del tier migliore sbloccato e 2% di oggetti del tier 11.

**Realizzazione (GUILD-2, `SecretSystem`).** Rivelare un luogo costa 10 Frammenti di Mappa e richiede il livello della mansione; per 24 h di gioco si possono fare fino a 3 *esplorazioni a tempo* da 20 minuti, una alla volta, in parallelo all'attività in corso: ciascuna dà l'XP dell'azione di maggior livello sbloccata ×1,5 per la sua durata e, per ogni ciclo, il 2% dell'oggetto di tier 11 del luogo. La prima scoperta di ogni luogo paga Polvere Stellare e alimenta gli incarichi dei Ranger. Numeri in `data/social_rules.json` (`secrets`).

## 8. Incursioni con la squadra

La squadra di 3 mercenari (Difensore, Guaritore, Assaltatore) applica effetti di ruolo scalati su `potere / potere_richiesto` (max ×1,5): −30% danni subiti, cura 1,5% vita/s, +40% danno del giocatore. Squadra incompleta = incursione molto più dura (consentito).
