# 07 — Oggetti ed equipaggiamento

> Dati: `data/items/*.json` (1.233 oggetti), elenco consultabile in `docs/appendici/A2_equipaggiamento.md`.

## 1. Tassonomia (campo `category`)

| Categoria | Esempi | Impilabile | Note |
|---|---|---|---|
| `material` | tronchi, assi, minerali, lingotti, pelli, cuoio, fibre, tessuti, erbe, gemme, materiali dei mostri | sì | input delle ricette |
| `food` | pesci alla brace, spiedini, **banchetti** | sì | `food.heal` o `feast` |
| `potion` | 12 linee × 4 ranghi | sì | `potion.scope/charges/modifiers` |
| `ammo` | frecce, rune, oli | sì | `ammo.style/damage` |
| `glyph` | 8 linee × 5 ranghi | sì | si incastrano nell'equipaggiamento |
| `equipment` | armi, mano secondaria, armature, mantelli, anelli, amuleti, insegne, unici | **no** (istanze) | qualità, incastri, rango, finitura |
| `tool` | asce, picconi, canne, falcetti, trappole, grimaldelli | no | slot attrezzo per mansione |
| `key` | Chiavi T1–T6 | sì | **non vendibili** |
| `crate` | casse e capsule | sì | si aprono (docs/09) |
| `skin` / `relic` | finiture e reliquie ★ | **no** (istanze con float, motivo, Annalista) | docs/09 |
| `seed`, `openable`, `consumable`, `currency`, `quest`, `cosmetic`, `misc` | | | |

**R-IT-1:** gli oggetti `stackable: false` sono **istanze** nel salvataggio: `{uid, def, quality, sockets[], rank, skin_uid?, float?, seed?, annalist?, counter?, phase?, locked?, name_tag?}`.
**R-IT-2:** `tradeable: false` = non vendibile al Mercato (chiavi, valute, tomi, oggetti di missione).

## 2. Slot del personaggio

`weapon`, `offhand`, `ammo`, `helm`, `body`, `legs`, `gloves`, `boots`, `cape`, `amulet`, `ring` ×2, `relic` ×1 (fino a 3), `insignia` ×1, + 1 **attrezzo per mansione** (6 slot attrezzo) + **Guardaroba** (29 slot finitura, docs/09).

- Armi a due mani occupano anche `offhand`.
- Requisiti: `level_req` (livello Eroe per l'equipaggiamento di combattimento, livello mansione per gli attrezzi).

## 3. Tier dei materiali (11)

| Tier | Lv | Metallo (Mischia) | Legno (Distanza/Arcano) | Cuoio (Distanza) | Stoffa (Arcano) | Gemma |
|---|---|---|---|---|---|---|
| 1 | 1 | Rame | Pino | Coniglio | Lino | Quarzo |
| 2 | 10 | Bronzo | Betulla | Volpe | Canapa | Agata |
| 3 | 20 | Ferro | Castagno | Cervo | Cotone | Ametista |
| 4 | 30 | Acciaio | Cedro | Lince | Ortica | Topazio |
| 5 | 40 | Cobalto | Ebano | Orso | Seta | Smeraldo |
| 6 | 50 | Argento Lunare | Legnoferro | Basilisco | Velluto Lunare | Rubino |
| 7 | 60 | Oricalco | Spinacorvo | Grifone | Bisso | Zaffiro |
| 8 | 70 | Sangueferro | Argentalba | Viverna | Brace | Diamante |
| 9 | 80 | Astralite | Legnovespro | Pantera d'Ombra | Seta d'Ombra | Opale Nera |
| 10 | 90 | Acciaio Stellare | Legnostella | Draco di Tempesta | Tessuto Stellare | Lacrima Stellare |
| 11 | 95 | Caveau | Radice del Caveau | Bestia Stellare | Tessuto del Caveau | Gemma del Caveau |

## 4. Budget delle statistiche (formule — `core.py`)

Crescita per tier: **×1,40** (`GEAR_R`).

- **Armi:** `danno = 6 × 1,40^(t−1) × molt_arma`; precisione = `10 × 1,40^(t−1) × molt`; AP = `5 × t^1,3`.

| Arma | Stile | Mani | Intervallo | Molt. danno | Min | Note |
|---|---|---|---|---|---|---|
| Spada | Mischia | 1 | 2,4 s | 1,24 | 60% | + Scudo |
| Spadone | Mischia | 2 | 3,4 s | 1,65 | 55% | +2% critico |
| Arco Corto | Distanza | 2 | 2,0 s | 0,89 | 60% | +3% critico, precisione ×1,1 |
| Arco Lungo | Distanza | 2 | 3,0 s | 1,35 | 55% | +6% critico |
| Bacchetta | Arcano | 1 | 2,6 s | 1,00 | 65% | + Tomo |
| Bastone | Arcano | 2 | 3,4 s | 1,50 | 60% | +2% critico |

- **Armature** (totale set di 5 pezzi; pesi per slot: elmo 18%, corazza 32%, gambali 24%, guanti 12%, stivali 14%):

| Tipo | Armatura | Protezione arcana | Vita | Evasione | Extra |
|---|---|---|---|---|---|
| Piastre | 40 × 1,4^(t−1) | ×0,30 | 30 × 1,4^(t−1) | −10% | FOR `4 × t^1,3` |
| Cuoio | ×0,55 | ×0,50 | ×0,70 | 30 × 1,4^(t−1) × 0,45 | DES, precisione `25 × 1,4^(t−1) × 0,4` |
| Stoffa | ×0,75 | ×1,00 | ×0,55 | ×0,45 | INT, AP `2 × t^1,3` |

- **Scudo:** 22% dell'armatura del set piastre, 8% protezione, 20% vita. **Tomo:** AP `4 × t^1,3`, INT, +(5+t)% rigenerazione risorsa.
- **Mantello:** evasione 10% del set, protezione 6%. **Anelli:** Potenza (FOR+AP), Mira (DES+precisione), Arcano (INT+AP), Vitalità (VIT+vita). **Amuleti:** Furia (+danno %), Baluardo (+difese %), Precisione (+critico), Vita (+vita %, rigenerazione).
- **Munizioni:** frecce e rune `12% × 6 × 1,4^(t−1)` danno aggiunto all'arma; oli 12% (per colpo, facoltativi).

## 5. Qualità, incastri, rango

- **Qualità** (solo creati): Normale/Fine/Eccellente/Capolavoro = ×1,00/1,08/1,16/1,28 sulle statistiche, 0/1/2/3 **incastri** per Glifi (docs/04 §4).
- **Glifi** (Incisione Runica, 8 linee × ranghi I–V): si incastrano consumandoli; rimuoverli li distrugge (o costa 25% del valore per recuperarli con l'Estrattore, sblocco Collegio Arcano Onorato).
- **Rango** (dall'Era II): +4% per rango (moltiplicativo) **solo** su danno dell'arma, armatura, barriera, vita, precisione ed evasione dell'oggetto (non su attributi, potenza d'attacco, critico, modificatori: docs/13 §4); massimo 12 × era sbloccata; costo per salire al rango *r*: `Essenza d'Era = ceil(2 + 0,5·r)`, oro `250 × tier × (1 + r/10)`.

## 6. Oggetti unici

- 55 unici: 2 per boss di zona (1/64), 2 per boss di dungeon (1/50), 4 per incursione (1/20 + acquistabili con 150 Sigilli), 1 per boss mondiale.
- Statistiche = equivalente creato ×1,12 + 1–2 modificatori speciali + eventuale **elemento**. Non hanno qualità (non sono creati) e **non hanno incastri** (sono già speciali); possono invece salire di **Rango** come ogni altro equipaggiamento.

## 7. Deposito e inventario

- Deposito condiviso (non c'è inventario separato): **100 spazi** iniziali (erano 60, resoconto 114), +1 per acquisto (`min(5.000.000, round(200 × 1,03^n))`, massimo 340 acquisti), +bonus permanenti: **7 missioni principali** (+10 ciascuna: fine dei Capitoli I, III, V, VI, VII, IX, X, ricompensa `bank_slots`), Costellazione «Caveau di Famiglia» (+10 per livello, 20 livelli = +200) e reliquia «Forziere Senza Fondo» (+40 nel Reliquiario). Tutto passa da Modifiers (`bank_slots`). Ogni oggetto impilabile occupa 1 spazio; ogni istanza non impilabile occupa 1 spazio, **tranne l'equipaggiamento e gli attrezzi** (UI F15, `constants.bank.space.free_categories = [equipment, tool]`): hanno la loro **Armeria**, che non occupa Spazio. Spazio usato = pile + istanze di categoria non libera (Finiture, Reliquie, cosmetici contano); Armeria = istanze di categoria libera (indossate comprese), con un tetto tecnico `gear_cap` (300, non si compra, non è economia) e un avviso una volta a `gear_warn_pct` (95%). Oltre il tetto il pezzo aspetta nel Carro di Ritiro, che ragiona per classe (un pezzo di equipaggiamento aspetta solo se l'Armeria è piena, una pila o una Finitura solo se lo Spazio è pieno); nessun pezzo si perde. Invarianti: celle di «Tutto» senza filtri = `used_slots()`; celle di «Armeria» = `gear_used()`; `used + gear = pile + istanze`; `free_slots()` mai negativo. I vecchi salvataggi con più pezzi del tetto restano intatti (nessun pezzo tolto); il loro Carro si scarica una volta verso l'Armeria con una riga nel Registro. Nessun cambio di schema. `need_base` del simulatore da 30 a 12 (sono usciti equipaggiamento e attrezzi).
- **Schede del giocatore (UI F17, docs/ui_redesign/02 §4.3, §5):** fino a `constants.bank.ui.max_tabs` (12) schede gratuite create dal giocatore, oltre a «Tutto» (tutto ciò che occupa Spazio) e «Armeria» (fisse). Le schede **organizzano soltanto**: non danno capacità, non costano oro, non cambiano quantità, Spazio o esito delle Casse. Nome scritto dal giocatore (1–`tab_name_max` = 16 caratteri, ripulito, senza markup, mai tradotto; doppioni senza distinzione di maiuscole ricevono « 2»), icona = un oggetto già scoperto. Ogni pila o istanza da collezione sta in **una** scheda; l'equipaggiamento non si assegna (si organizza nell'Armeria). Assegnazione «appiccicosa»: una pila esaurita resta nella sua scheda e ci torna quando rientra; un'istanza sparita esce dalla scheda. Eliminare una scheda cancella solo le assegnazioni (nessun oggetto si perde). «Crea schede suggerite» propone Materiali / Provviste / Casse e chiavi / Collezione con anteprima. Ricerca in tutte le schede e nell'Armeria (scheda virtuale «Risultati (n)», parole in AND, senza accenti, operatori `cat:` `t:` `lock:` `q:` `rar:`). **Vendita a selezione** (modalità vendita, tasto V): solo vendibili selezionabili (stessa regola di `SellRules.block_reason`: mai bloccati, indossati/in uso, unici, Reliquie, Annalisti, oggetti-missione, non commerciabili), anteprima a due passaggi con «Torna indietro» predefinito, quantità per pila, prezzo del Mercato (nessuna casualità), primo Invio ignorato per `sell_confirm_guard_ms`, nessun tasto che vende, nessun annulla dopo la vendita. Schema di salvataggio 4 → 5 (`bank.tabs`, `bank.tab_of`, `bank.next_tab`, additivi).
- **«Espandi Deposito»** (resoconto 114): pulsante in alto nel Deposito (e nell'avviso «quasi pieno») con il prezzo del prossimo spazio; apre una finestra con +1/+5/+10 (`constants.bank.buy_batches`), costo, spazi dopo l'acquisto, il motivo se non si può comprare e il riepilogo di tutte le fonti di spazi. Compra senza passare dall'Emporio (stesso contatore `shop.bank_slot`: nessuna migrazione, i posti già comprati restano). Il passo del tutorial `f_bank_expand` compare al 90% e lo evidenzia. Lo studio di capacità è in `reports/balance_report.md` §5e.
- Funzioni: schede (filtri per categoria), ricerca testuale, ordinamento (valore, tier, nome, recenti), **blocco** oggetto (non vendibile/fondibile), vendita multipla, **regole di vendita automatica** (sblocco Costellazione) per categoria/rarità/qualità.
- Riepilogo valore totale del Deposito (stile "inventory value").

### 7.1 Doppioni, «A cosa serve» e Deposito quasi pieno (feedback giocatore 23/10/2026)
Caso reale: Deposito 60/60 di «Grimaldello di Rame», righe identiche, nessuna spiegazione, «Vendita rapida» spenta. Cause: (1) Forgiachiavi ripetuta all'infinito su un'uscita non impilabile (ora `single_craft`, docs/04 §8.2); (2) gli attrezzi sono istanze (uid) perché possono essere bloccati, indossati e portare qualità; (3) la Vendita rapida si spegneva per tre motivi diversi (Mercato non sbloccato, pezzo in uso, bloccato) senza dirlo.
- **Niente impilamento** degli attrezzi (restano istanze: l'equipaggiamento per uid è usato da Eroe, slot attrezzo, blocco): la soluzione è non produrne più in serie + smaltire i doppioni con un clic.
- **«Vendi i doppioni»** (pulsante del Deposito, anteprima con pezzi e oro): per ogni definizione di equipaggiamento/attrezzo con 2+ istanze se ne tiene UNA (bloccata o in uso; altrimenti la qualità migliore) e le altre, se non bloccate/uniche/con grado/con incastri, si smaltiscono. Gli **attrezzi si riciclano in oro anche senza Mercato** (`constants.bank.recycle_pct` × valore, `recycle_dupe_categories`); l'equipaggiamento si vende al Mercato (domanda elastica, R-EC-3 invariata: il riciclo senza decadimento vale solo per gli attrezzi, che non si possono più produrre in serie). Interruttore «Vendi anche i doppioni in automatico» nella Vendita automatica. La categoria «Attrezzi» è ora filtrabile nella vendita multipla e nelle regole automatiche.
- **Migrazione**: al caricamento di un vecchio salvataggio gli attrezzi doppioni si riciclano in oro (resta quello in uso/bloccato/migliore), con avviso nel Registro. Nessun cambio di schema.
- **Motivi dei pulsanti spenti**: la Vendita rapida spenta mostra il perché nel tooltip E scritto sotto il pulsante (Mercato non sbloccato · bloccato · in uso · il Mercato non lo compra).
- **«A cosa serve»**: ogni oggetto mostra nel dettaglio una riga generata dai dati (`ItemUse.purpose`: categoria + effetto + dove si usa), una riga «Come si usa» (`ItemUse.howto`) e se il Mercato lo compra; per gli attrezzi, bonus concreti e confronto con quello in uso. `test_attrezzi.gd` verifica che TUTTI gli oggetti dei dati abbiano la riga in IT e EN.
- **Avviso 90%** (`constants.bank.warn_pct`): una volta sola nel Registro e banner nel Deposito, con i rimedi. A Deposito pieno NIENTE si ferma e niente si perde (resoconto 117): premi, acquisti e produzione aspettano nel **Carro di Ritiro** (`bank.overflow_*`, online e offline) e si scaricano da soli appena c'è posto. Il pannello del Carro (Deposito e Sala dei Caveau) offre «Vendi i doppioni», «Vendi Finiture comuni e rare», «Vendita automatica» (un clic: doppioni + regola consigliata `constants.bank.carro.sell_rule`, mai bloccati, indossati, unici, Annalisti né Reliquie) ed «Espandi Deposito».

