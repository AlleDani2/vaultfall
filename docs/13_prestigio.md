# 13 — Prestigio infinito a strati

> Dati: `data/skill_prestige.json`, `data/constellations.json`, `data/era_rules.json`, `data/estate_rules.json` (Rifondazione), `data/trials.json`.

## 1. Perché "a strati" e non un reset totale

Un idle RPG in stile Melvor vive di progressi permanenti: azzerare tutto il personaggio allontana proprio il pubblico principale. VAULTFALL offre **prestigi illimitati ma locali**, ognuno scelto dal giocatore e con un tempo di recupero breve:

| Strato | Cosa si azzera | Cosa si ottiene | Ciclo tipico |
|---|---|---|---|
| **Stella di Mansione** | il livello di UNA mansione (100 → 1) | bonus permanenti alla mansione + Polvere Stellare | 23 h la 2ª, poi in calo fino a ~12,4 h costanti (profilo base) |
| **Rifondazione** | i livelli degli edifici della Tenuta | Soci (+2% produzione ciascuno) | 6–24 h di Tenuta |
| **Era del Mondo** | niente (si sale di difficoltà) | ricompense ×(1+0,3·(N−1)), Casse dell'Era, ranghi | 9–52 h per Era, poi ~25 h costanti |
| **Costellazioni** | niente (si spende Polvere) | nodi con livelli infiniti | continuo |
| **Prove del Custode** | niente (sfide con restrizioni) | bonus permanenti, titoli | 8 prove × 5 gradi |
| *(post-lancio)* **Stagioni** | un salvataggio stagionale separato | cosmetici e Polvere al personaggio principale | 8–12 settimane |

Regole d'oro (dalla ricerca, docs/02): mostrare sempre **cosa si guadagna prima di confermare**, consigliare il momento ("+X% rispetto ad ora"), automatizzare lo strato inferiore come ricompensa, mai obbligare a cliccare.

**Regola di stabilità (vincolante per ogni nuovo strato):** un bonus che rende più veloce il prestigio successivo, con un costo che non cresce, crea una **fuga** (tempo per ciclo che tende a zero: stelle o ere "infinite" in poche centinaia di ore). Quindi:
1. i bonus **auto-rinforzanti** (XP della stessa mansione, velocità, probabilità) sono **asintotici**: `cap × (1 − decadimento^n)`;
2. i bonus lineari senza limite sono ammessi solo se **non** accelerano lo strato stesso (danno dell'Eroe, oro del Borseggio, Marchi);
3. ogni strato ha un controllo automatico nel simulatore (`reports/balance_report.md` §8 Stelle, §9 Ere, §7 Tenuta): il tempo per ciclo deve **convergere** (né muro né fuga).

## 2. Stelle di Mansione

- Requisito: **livello 100**. Conferma con riepilogo (livello perso, Stella guadagnata, Polvere, tempo stimato per tornare a 100 con l'Eco).
- La mansione torna al **livello 1** (i talenti di mansione si azzerano ma il gioco ricorda le scelte per riapplicarle con un clic; maestrie, oggetti, missioni restano).
- **Eco** (recupero): XP ×3 finché il livello è < 50% del record, ×2 fino al 90%, ×1,5 fino al record (`echo_mult_pct` lo aumenta).
- Bonus delle stelle (`data/skill_prestige.json`: `curves` = asintotici, `per_star_linear` = lineari):
  - **XP nella mansione** `60% × (1 − 0,92^stelle)` (modalità **more**): 1★ +4,8% · 5★ +20,5% · 10★ +33,9% · 25★ +52,5% · asintoto +60% (era 100%: ritarato il 23/10/2026, D-8);
  - **velocità** `25% × (1 − 0,9^stelle)` (asintoto 25%, era 30%) per le mansioni ad azione;
  - extra a curva `cap × (1 − 0,95^stelle)`: raccolta/produzione doppio (cap 40%) · Coltivazione doppio (cap 60%) · Forgiachiavi risparmio chiavi (cap 20%) · Borseggio successo (cap 15 punti);
  - extra lineari senza limite (non accelerano la stella successiva): Borseggio +2% oro · Eroe +1% danno e +1% vita · Taglie +3% Marchi.
- Traguardi: 1★ **automazione** della mansione · 3★ **secondo talento** a ogni scelta · 5★ cornice d'argento + bonus · 10★ cornice d'oro + bonus · 25★ titolo · 50★ e 100★ cornici. Eroe: 1★ **classi ibride**, 3★ terzo Reliquiario.
- **Polvere Stellare** per la stella *n*: `10 + 2·(n−1)` (+`stardust_gain_pct`).
- Ritmo (simulato, Taglialegna profilo base): 1ª stella 44,5 h · 2ª 23 h (Eco) · 10ª 16 h · dalla 30ª 12,9 h, a regime **~12,4 h costanti** → le stelle crescono in modo lineare nel tempo (100 stelle ≈ 1.365 h su una mansione). Con i bonus del budget di docs/14 il minimo è 6,2 h; con le Costellazioni al massimo (XP 14 livelli, Mani Svelte 20) 4,3 h, pavimento anti-fuga fissato a 4 h. Con un ingenuo +10% moltiplicativo per stella la 51ª richiederebbe 10 minuti e la 101ª 5 secondi: per questo l'XP è asintotica.

## 3. Costellazioni (albero globale)

5 costellazioni × 7 nodi (`constellations.json`): **Il Viandante** (mansioni), **Il Mercante** (economia, Tenuta), **Il Guerriero** (combattimento, mercenari), **La Sorte** (casse, drop, famigli, pity), **Il Custode** (offline fino a 24 h, raccolta/vendita automatica, coda azioni, Reliquiario, Polvere, Tomi).

- Costo livello: `ceil(base × crescita^livello)` Polvere; molti nodi **senza livello massimo** con effetto lineare e costo esponenziale (crescita logaritmica del potere: niente esplosioni numeriche).
- Nodo *i* richiede il nodo *i−1* della stessa costellazione a livello ≥ 1.
- Fonti di Polvere: Stelle, imprese (1–30), capitoli della storia, Custode nelle Ere (5 × era, **solo alla prima uccisione di ogni Era**), Prove, piani della Breccia (2 ogni 10 piani).
- Rimborso totale gratuito una volta ogni 7 giorni (poi 50 Polvere).

## 4. Ere del Mondo

- Dopo il Cap. X: battere il Custode del Caveau nell'Era N sblocca l'Era N+1. **Infinite.**
- Mostri ×1,35^(N−1) su vita, danno, precisione, evasione, armatura e barriera; XP/oro ×(1 + 0,3·(N−1)); **Cassa dell'Era N** (dal Custode, si apre senza chiave: E47-1; bonus ×(1 + 0,25·(N−1)) sulle Schegge della fusione).
- **Essenza d'Era** (non vendibile): probabilità per uccisione élite 25%, boss 100%, boss di dungeon 300%, boss d'incursione 1000% (cioè 3 e 10 drop garantiti); quantità per drop = **N** (si accumula già nell'Era I).
- Equilibrio: il giocatore segue con il **Rango** degli oggetti (+4%/rango **solo** su danno dell'arma, armatura, barriera, vita, precisione, evasione; cap 12·N), le Stelle dell'Eroe e le Costellazioni. Servono ~8 ranghi per Era (1,04^7,65 = 1,35).
- Perché il Rango non tocca attributi e potenza d'attacco: scalando sia il danno dell'arma sia la potenza d'attacco la crescita diventa "al quadrato" (×1,08 per rango) e dall'Era 20 si uccide in meno di 1 secondo (verificato nel simulatore).
- Ritmo simulato (§9 del report): Era III in ~9 h, Era X in ~45 h (zona di transizione), poi **~25 h per Era costanti**; il costo cresce linearmente con l'Era come le entrate, quindi il ciclo è stabile e infinito.
- Si può giocare in qualsiasi Era sbloccata (selettore nella schermata Combattimento e scheda **Ere** del Prestigio, con anteprima: mostri ×, ricompense ×, Essenza, Ranghi consigliati; cambiare Era non toglie nulla).
- **Polvere del Custode (audit 43):** `5 × era` alla PRIMA uccisione del Custode di ogni Era; ripetere il Custode paga `stardust_repeat_pct` % (0 nei dati) perché altrimenti più danno → più Custodi → più Polvere → più danno sarebbe un anello (regola 9). Controllo: `balance_sim.py` §11 (la Polvere dei Custodi, spesa tutta in danno/vita/difesa, vale ≤ 11% dei Ranghi richiesti e la quota scende dall'Era 20).
- **Integrazione col combattimento:** `PrestigeSystem.on_warden_defeated(era)` va chiamata quando cade il Custode del Caveau (vedi `docs/audit_2026-10-22/43_RESOCONTO_ERE_PROVE.md`).

## 5. Rifondazione della Tenuta

Vedi docs/11 §4. Soci = `floor(15 × √(punti_prosperità / 10.000))`; +2% produzione per Socio; nodo "Rete di Soci" +5%/livello sui Soci guadagnati.

## 6. Prove del Custode

8 prove con restrizioni (Digiuno, Lama Spuntata, Contro il Tempo, Silenzio, Vetro, Stile Sbagliato, Senza Armatura, Maratona) × 5 gradi (boss delle zone 2/4/6/8/10; la Maratona è il dungeon della zona). Premio per grado, **una volta sola**: +1% permanente a un modificatore legato alla prova + 3/6/9/12/15 Polvere. Sblocco: Cap. V (missione «La Strega di Fiele»; scheda **Prove** del Prestigio, token `feature:trials`).

- **Come funziona (audit 43):** anteprima obbligatoria (regole, cosa lasci, cosa conservi, premio) → «Inizia la Prova» con conferma a due passaggi → si combatte nell'**Era I** (l'Era scelta torna a fine Prova) → vinci uccidendo il boss (o completando il dungeon) rispettando le regole. Fallire, morire, scadere o abbandonare non costa nulla.
- **Regole applicate dal sistema stesso** (ascolta gli eventi del gioco): `no_food`/`max_food` (cibo mangiato), `time_limit_s` (cronometro dal clic su Inizia; scade anche offline), `max_gear_tier` e `no_armor` (equipaggiamento controllato all'avvio e alla vittoria), `hp_mult` (modificatore temporaneo `combat_hp_pct`), `dungeon` (si vince con `complete_dungeon`), morte. Le regole che solo il combattimento può far rispettare (`no_abilities`, `forced_disadvantage`, `monster_hp_mult`) sono esposte da `PrestigeSystem.trial_rules_active()`.
- **Regole per grado** (`tiers[].rules`, tarate con `balance_sim.py` §11): Digiuno IV/V concedono 3/6 porzioni (`max_food`), Contro il Tempo 60/60/90/105/125 s, Lama Spuntata = tier della zona − 1 (con −3 i gradi II–V erano infattibili).
- **Stabilità:** 40 premi in tutto, ciascuno riscosso una volta: +5% al massimo per famiglia (≈ 7,5 Ranghi equivalenti, meno di un'Era), 360 Polvere. Nessun anello.

## 7. Stagioni (post-lancio, docs/27)

Un **salvataggio stagionale** che riparte da zero con un modificatore globale (es. "Casse ×2, cibo ×0,5"), durata 8–12 settimane; a fine stagione il progresso si converte in cosmetici e Polvere per il personaggio principale. Dà la fantasia del "reset totale" senza toccare il personaggio principale.

## 8. UI del prestigio (requisiti)

- Schermata **Stelle**: griglia delle 17 mansioni con stelle, prossimo traguardo, pulsante "Ottieni Stella" attivo a 100, anteprima calcolata dai dati: "Polvere +N · XP della mansione +A% → +B% · velocità +C% → +D% · tempo stimato per tornare a 100: X h" (chiave `UI_STARS_NEXT_PREVIEW`).
- Schermata **Costellazioni**: mappa stellare a 5 rami, costo/effetto del prossimo livello, "massimo acquistabile".
- Tenuta: indicatore "Soci se rifondi ora: +N (+X% produzione)" con consiglio.
