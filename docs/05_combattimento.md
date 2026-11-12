# 05 — Combattimento

> Dati: `data/constants.json` (sezione `combat`), `data/monsters.json`, `data/drop_tables.json`, `data/zones.json`, `data/dungeons.json`, `data/raids.json`, `data/world_bosses.json`, `data/rift.json`, `data/abilities.json`, `data/classes.json`, `data/bounty_board.json`. Riferimento numerico: `reports/balance_report.md` §3–4.

## 1. Principi

- Combattimento **automatico** a tempo: il giocatore sceglie *dove* (zona e mostro, dungeon, incursione, Breccia, taglia) e *come* (classe, equipaggiamento, abilità e loro priorità, cibo, pozioni, soglia di auto-mangiare).
- **Simulazione a passo fisso di 0,1 s** (10 tick/s), identica online e nel simulatore offline. Nessuna fisica, nessuna posizione.
- Il tempo per uccidere (TTK) bersaglio è **6–9 s** su un mostro normale della propria zona con equipaggiamento creato del tier (qualità Normale). I boss di zona durano 40–100 s, i boss di dungeon 50–110 s, le incursioni 3–6 minuti.

## 2. Statistiche del personaggio

| Statistica | Formula (costanti in `constants.json → combat.hero.coef`) |
|---|---|
| Attributi | Forza (FOR), Destrezza (DES), Intelletto (INT), Vitalità (VIT). Base 5. Per livello Eroe: +1 all'attributo primario della classe, +0,5 VIT (+1 per il Guerriero) **+3 punti liberi** (preset automatico: 2 primario, 1 VIT) |
| Vita max | `(60 + 10·VIT + 5·L + vita_equip) × (1 + combat_hp_pct/100)` |
| Potenza (AP) | `1,5 × attributo_primario + AP_equip` |
| Precisione | `20 + 3·L + attributo_primario + prec_equip` × (1 + combat_acc_pct) |
| Evasione | `10 + 2·L + 0,8·DES + evas_equip` × (1 + combat_eva_pct) |
| Armatura / Protezione arcana | somma dell'equipaggiamento × (1 + combat_arm_pct / combat_ward_pct / combat_defense_pct) |
| Colpo massimo | `(danno_arma + danno_munizione) × (1 + AP/100) × (1 + combat_dmg_pct/100)`; colpo minimo = massimo × `min_ratio` dell'arma |
| Critico | 5% + arma + modificatori (cap 75%); danno critico 150% + modificatori |
| Velocità d'attacco | intervallo = `intervallo_arma / (1 + effettivo/100)`, effettivo = `combat_haste_pct` fino a +60%, poi metà, massimo +100% (CORSA, resoconto 91) |
| Rigenerazione | 0,2% della vita max al secondo + `combat_regen_hps_pct` |

Attributo primario: Guerriero FOR · Ramingo DES · Arcanista INT · Ibride: il maggiore tra i due stili.

## 3. Formule del colpo

```
probabilità_colpo = clamp(0,75 × sqrt(precisione_attaccante / evasione_difensore), 0,05, 0,98)
danno_grezzo      = uniforme(colpo_min, colpo_max) × (critico ? danno_critico : 1)
riduzione         = min(0,85, difesa / (difesa + K)),  K = 30 × 1,0375^(livello_attaccante)
                    difesa = Armatura se il danno è fisico (Mischia, Distanza), Protezione arcana se magico (Arcano)
                    difesa effettiva = difesa × (1 − penetrazione)
danno_finale      = danno_grezzo × (1 − riduzione) × triangolo × elemento × (1 + bonus_vari) × (1 + target_dmg_taken_pct)
```

- **Triangolo:** Mischia batte Distanza, Distanza batte Arcano, Arcano batte Mischia. Vantaggio ×1,15 sul danno inflitto, svantaggio ×0,85. Vale per giocatore e mostri.
- **Elementi:** Fuoco, Gelo, Fulmine, Veleno, Sacro, Ombra. Ogni mostro ha 0–1 debolezza (**+25%**) e 0–1 resistenza (**−25%**) verso il danno di quell'elemento. Le abilità e alcune armi uniche hanno un elemento; `element_dmg_pct:<el>` lo potenzia.
- **Colpo multiplo** (`combat_multihit_pct`, cap 50%): l'attacco base colpisce due volte.
- **Rubavita** (cap 25%), **Spine** (danno riflesso), **DoT** (sanguinamento/veleno/bruciatura a tick di 1 s, potenziati da `combat_dot_dmg_pct`), **Stordimento** (il bersaglio salta gli attacchi per la durata; ridotto da `combat_status_resist_pct`).

## 4. Mostri

- Statistiche da livello e tipo (`constants.json → combat.monster_curves` e `monster_types`):
  - Vita = 23,5 × 1,0575^L × molt. tipo (normale 1 · élite 3 · boss 10 · boss dungeon 14 · boss incursione 45 · boss mondiale 400)
  - Colpo max = 13,5 × 1,0364^L × molt. tipo; colpo medio = 70% del massimo
  - Precisione = (20 + 7,5·L) × molt.; Evasione = (15 + 6,66·L) × molt.; Armatura = Protezione = 4 × 1,036^L × molt.
  - XP e oro: curve continue nel livello, tarate su un ciclo di 9,5 s (8 s + 1,5 s di ricomparsa).
- Ogni mostro ha **stile** (determina tipo di danno e triangolo), **debolezza**, **resistenza**, **tabella drop**.
- I boss hanno **meccaniche** (`data/boss_mechanics.json`, generate da `combat.py → BOSS_MECHANICS`; il codice non ha più valori fissi): Furia sotto il 30%, Colpo Devastante ogni 15 s, Nube Tossica, Richiamo di servitori, Barriera, Stordimento, Prosciugamento. Le incursioni hanno **3 fasi** con cambio di stile al 66% e al 33%.
- **Ricomparsa:** 1,5 s tra un mostro e il successivo (non riducibile sotto 0,5 s).

## 5. Abilità e risorse

- Ogni classe ha 6 abilità base + 3 per specializzazione (+4 per le ibride): `data/abilities.json`.
- Il giocatore equipaggia **fino a 4 abilità** in una **lista di priorità**. Quando l'attacco base è dovuto si lancia la prima abilità pronta (tempo di ricarica terminato, risorsa sufficiente, condizione soddisfatta): **la tecnica offensiva prende il posto dell'attacco base** (stessa pausa, stessa munizione). Le abilità con condizione (`hp_below_pct:30`, difese d'emergenza) scattano invece a ogni tick, senza costare l'attacco. **I potenziamenti** (buff, debuff, scudi senza condizione) **accompagnano l'attacco**: si lanciano insieme all'attacco dovuto, costano solo la risorsa (FIX-COMBATTIMENTO, QA4 #7: prima 6 su 8 avevano valore netto negativo; ora ognuno vale ≥ 0 per costruzione, +2-8% di uccisioni/ora quelli offensivi, meno danno subito quelli difensivi: `q4_sweep.gd mode=abil`). Se non scelte a mano ("scegli per me"), la lista automatica è: una difesa d'emergenza + le due tecniche offensive più avanzate + i potenziamenti negli slot rimasti. (M7, FIX-COMBATTIMENTO)
- Risorse:
  - **Furia** (Guerriero): max 100, +16 per colpo inflitto, +8 per colpo subito, cala di 5/s fuori dal combattimento (valori raddoppiati in M7, vedi sotto).
  - **Concentrazione** (Ramingo e ibride): max 100, +6/s, +10 per critico.
  - **Mana** (Arcanista): max `50 + 2·INT`, +2,5% del max al secondo.
- Tipi di effetto: `damage` (moltiplicatore del danno arma, elemento, colpi), `dot`, `buff`, `debuff`, `heal`, `shield`, `summon` (compagno con DPS = % del danno arma, durata), `stun`.
- Obiettivo di bilanciamento: le abilità aggiungono **~25% di DPS** rispetto ai soli attacchi base (il simulatore usa questo fattore).
- **Calibrazione M7 (OPEN_QUESTIONS C2-1):** con le ricariche "base" della tabella di docs/06 §3 e la tecnica che prende il posto dell'attacco il guadagno misurato nel motore era +45-90%. Le ricariche in `data/abilities.json` sono quindi **doppie** (`ABILITY_CD_SCALE = 2` in `tools/gamedata/combat.py`) e la Furia per colpo è raddoppiata: la rotazione automatica rende +14-36% (media ~25%) per le tre classi tra Lv 5 e Lv 85, misurato da `game/tests/test_abilities.gd`.
- Effetti implementati (CombatSim): danno (colpi, elemento, critico, penetrazione, esecuzione, stordimento, rallentamento), DoT (tick di 1 s, `combat_dot_dmg_pct`), potenziamenti e malus (regola add dei Modificatori sui rapporti), cure (anche in % del danno), scudi, evocazioni (DPS = % del danno arma), colpo multiplo, spine, rubavita, resistenza agli stati.

## 6. Cibo, auto-mangiare, pozioni, munizioni

- Slot cibo: 3, ognuno con un tipo di cibo diverso (lo stesso cibo in un altro slot si sposta; la scorta è la somma dei tipi assegnati, mai contata due volte); si consuma dal primo slot che ha porzioni. La soglia di auto-mangiare si regola da 1% al massimo della cintura (quello di base, 10%, o 25/35/45%): il massimo non scende quando si abbassa la soglia, il valore predefinito (il massimo) è salvato come 0. **Auto-mangiare** (Emporio): I 25%→55% (efficienza 90%) · II 35%→70% (95%) · III 45%→85% (100%). Senza auto-mangiare il giocatore mangia solo se è sotto il 20% (manuale con tasto o automatico al 10% con spreco 50%).
- Mangiare non interrompe gli attacchi. Cura = `cura_cibo × (1 + food_heal_pct)`.
- **Indicatore "Sicuro in idle"** (lezione da Melvor, docs/02 §7): accanto al cibo, un'etichetta calcolata dal simulatore offline (§12) sul mostro scelto:
  - **Verde — Sicuro:** soglia di auto-mangiare × vita massima ≥ colpo massimo del mostro dopo le riduzioni **e** cibo sufficiente per il limite offline;
  - **Giallo — Attenzione:** sicuro ma il cibo finisce prima del limite offline (mostra "cibo per ~X h");
  - **Rosso — Rischio:** un colpo massimo (o una combo del boss) può uccidere prima che l'auto-mangiare intervenga.
  Tooltip con i numeri (colpo massimo, soglia, ore di cibo). Lo stesso calcolo compare nella finestra di conferma prima di chiudere il gioco con un combattimento attivo.
- **Pozioni:** 1 di combattimento attiva (cariche = attacchi) + 1 per gruppo di mansioni. **Banchetti:** 1 attivo, durata in minuti reali di gioco (anche offline).
- **Munizioni:** Distanza = frecce (1 per attacco, 20% recuperate di base), Arcano = rune (1 per attacco); senza munizioni l'Arcano e la Distanza **non attaccano** (notifica e stop). Mischia: oli da lama facoltativi (+danno, 1 per colpo andato a segno).

## 7. Morte

- Alla morte: il combattimento si ferma, **nessun oggetto perso**, si riparte dopo 10 s con *Ferito* (−10% statistiche per 5 minuti) e, nelle zone, lo scontro riprende da solo (anche offline, §12). Nei dungeon si perde l'avanzamento delle ondate ma si tiene il bottino già ottenuto.
- **Protezione del novizio (Q97, QA82).** Fino al livello Eroe `combat.rules.novice.until_level` (10, come il cambio classe gratuito) l'attesa dopo la morte è `restart_delay_s` (3 s) e *Ferito* dura `wounded_duration_s` (60 s) invece di 10 s / 5 min: lo scontro non diventa più facile, costa meno sbagliare mentre si impara (`CombatSystem.death_delay_s`, `wounded_duration_s`; anche offline). Un eroe nudo (nessuna arma, nessuna armatura, nessun cibo) subisce ~5 volte il danno di uno equipaggiato (dati: `q97_newhero.gd`): `CombatSystem.readiness()` elenca cosa manca e la scheda Combattimento mostra un avviso rosso e una conferma «Combatti lo stesso / Mi preparo» prima di partire. La divisa di rame (5 pezzi) è premio della missione del Prologo che precede il Combattimento (`main_c0_q3`).
- **Modalità di gioco** (scelte alla creazione del salvataggio):
  - **Normale**.
  - **Autarchico** (stile "ironman"): niente acquisti dal Mercato tranne fiale e semi base; Commesse disattivate. Titolo e cornice dedicati.
  - **Estremo**: una sola vita per l'Eroe (alla morte il livello Eroe e l'equipaggiamento indossato vanno persi; le mansioni restano). Titolo dedicato.

**Come sono realizzate (MODALITA', audit 57).** Le regole sono dati (`mode_rules.json`, da `tools/gamedata/meta.py`) letti da `ModeRules` (`src/core/ModeRules.gd`); i sistemi li interrogano con `ctx.mode_rules()` e non confrontano mai l'id della modalità (un test lo verifica). La modalità si sceglie alla creazione (`Game.new_game(slot, mode)`), vive in `GameState.data.mode` e non ha alcuna funzione che la cambi. Sono disponibili dall'inizio, con descrizione, avviso e conferma nel menù (OPEN_QUESTIONS M-1).
- *Autarchico.* `MarketSystem`: le merci dell'Emporio con un oggetto (attrezzi di rame, chiavi, capsule…) e le scorte dei PNG si comprano solo se l'oggetto è in `market_buy.allow_items` (Fiala Vuota e semi di patata/grano/cipolla); motivo `mode` nella scheda dell'Emporio. I potenziamenti permanenti (Auto-mangiare, Coda, slot) restano in vendita. Commesse: `orders_enabled()` falso → `order_slots()` = 0, bacheca vuota, consegna rifiutata; le Fazioni restano. Vendere resta permesso. Titolo `Autarchico Convinto` e cornice dedicata alla creazione; `Autarchico Stellato` alla prima Stella.
- *Estremo.* `ModeSystem` ascolta `player_died` (ogni causa: zona, dungeon, incursioni, Breccia, offline): `SkillSystem.reset_level("hero")` (livello 1, XP 0; **Stelle e record restano**), `CombatSystem.lose_worn_gear` (distrugge le istanze indossate; restano munizioni e attrezzi di mansione), `reset_hero_build` (attributi manuali, talenti e specializzazione si azzerano con il livello). Mansioni, Stelle, Polvere, Costellazioni, Ere, Tenuta, Deposito e cosmetici restano: la morte è un'involontaria «Stella senza bonus». Offline l'Eroe non muore: dove prima moriva si ritira (`stopped = "death_risk"`, riga nel Bentornato). Titolo `Vita Unica` e cornice alla creazione; `Sopravvissuto Stellare` alla prima Stella. Stato: `modes` (`deaths_lost`, `levels_lost`, `items_lost`, `last`).
- *Prestigio.* Le regole di conservazione del reset sono le stesse in ogni modalità (Stelle, Polvere, Costellazioni, Ere non si perdono con la morte Estrema); `balance_sim §12` controlla i tempi di Rito, prima Stella e Rifondazione in Autarchico e il costo di una morte Estrema.

## 8. Zone, dungeon, incursioni, boss mondiali

- **10 zone** (Lv 1–100), 6 mostri ciascuna (4 normali, 1 élite, 1 boss). Tabelle: A3.
- **Dungeon** (10): 8 normali + 2 élite + boss in sequenza (11 ondate); **niente cambio equipaggiamento** dentro, si può mangiare; ricompensa a fine dungeon: cassa della zona + materiali rari + oro; unici 1/50; traguardi di completamento (10/50/250).
- **Incursioni** (3: Lv 55, 75, 105): boss a 3 fasi con **squadra di 3 mercenari** (Difensore, Guaritore, Assaltatore) scelti dalla Taverna. Effetti di ruolo in `mercenary_rules.raid_role_effects`. Ricarica 4 h. Ricompense: 2 casse, Sigilli d'Incursione (negozio dei trofei), unici 1/20, famiglio 1/250.
- **Boss mondiali** (3, a rotazione): compaiono **ogni 4 ore** per 30 minuti mentre il gioco è aperto; in alternativa si evocano quando si vuole con un **Corno dell'Adunata** (Sala dei Trofei / Banco delle Taglie): nessuna ricompensa è esclusiva della finestra a tempo. Il giocatore contribuisce danni; "altri avventurieri" simulati infliggono il 2,5% della vita al minuto. Fasce di contributo Bronzo/Argento/Oro/Platino (1/3/6/10% della vita) con ricompense crescenti.

**Come sono realizzate (RAIDS, `EndgameCombat.gd`):**
- *Incursioni.* Accesso: gettone `raid:<id>` (missione) e livello Eroe dei dati. Si parte da Dungeon → scheda **Incursioni**, con 0-3 mercenari liberi della Taverna (uno per ruolo; «scegli per me» prende il più forte di ogni ruolo). Gli effetti di ruolo (`mercenary_rules.raid_roles`) valgono `f = min(1,5; potere squadra / potere richiesto)`: Difensore −30% danni subiti × f, Guaritore +1,5% vita max/s × f, Assaltatore +40% danno × f; il tratto *Predone* aumenta del 15% l'effetto del ruolo del suo possessore. Potere richiesto = 30 × 1,35^(ordine zona − 1) × 4. **L'Eroe conta nel potere di squadra (MURI, BOT-02/03):** potere squadra = potere dei mercenari + potere dell'Eroe, e il potere dell'Eroe = richiesto × `hero_share` (0,6) × min(`hero_level_cap` (1,3); livello Eroe / livello incursione). Un Eroe al livello dell'incursione vale quindi già f = 0,6; tre mercenari realistici (rari di livello 15 ≈ 144 di potere) aggiungono 0,08 (Cuore) – 0,36 (Covo) e squadre forti portano al tetto di 1,5. Prima contava solo il gruppo di mercenari (3 Leggendari al massimo ≈ 0,4 del richiesto al Cuore): la Cittadella e il Cuore avevano vittoria stimata 0–10% anche a Eroe 80–100 (BOT-02/03, audit 80). Un ruolo senza mercenario non è più «vuoto»: l'Eroe lo copre per `hero_role_share` (50%) dell'effetto di f; un mercenario di quel ruolo lo porta al 100% (+ Predone). Obiettivo di progressione (controllo «incursioni vincibili al livello del capitolo» in `balance_sim`): una squadra tipica all'altezza del capitolo ha circa il 65–80% di vittoria stimata (misure in `115_RESOCONTO_MURI.md`); la sconfitta non è punitiva (nessuna ricarica; ogni mercenario si ferisce con il 30% per 2 h). Il boss cambia stile al 66% e al 33% (`monsters.json → phases`): cambiano difesa colpita, tipo di danno e triangolo. Vittoria: oro, 2 casse della zona, 3-5 Sigilli, Essenza d'Era (10 porzioni × Era), drop rari del boss (unici 1/20, famiglio 1/250), XP ai mercenari; ricarica 4 h. Sconfitta: nessuna ricarica, ogni mercenario si ferisce con il 30% (−50% con *Robusto*) per 2 h. Quando cade il Custode del Caveau si chiama `prestige.on_warden_defeated(Era corrente)`.
- *Boss mondiali.* L'orologio delle finestre corre solo a gioco aperto: dopo 4 h, 8 h… compare il boss successivo (rotazione Colosso → Leviatano → Titano) per 30 minuti; la finestra si usa una volta. Il **Corno dell'Adunata** (10 Sigilli alla Sala dei Trofei) evoca a scelta un boss con una finestra propria di 30 minuti. Il contributo è il danno dell'Eroe (non quello degli alleati simulati) in % della vita del boss: Bronzo 1 · Argento 3 · Oro 6 · Platino 10. Il premio del livello raggiunto si riscuote alla fine anche se l'Eroe cade o si ritira.
- *Offline.* Un solo passaggio rapido (`EndgameCombat.boss_pass`, stesso CombatSim in modalità attesa, passo 0,1 s) risolve l'incontro: la vittoria/morte è estratta con la probabilità del colpo fortunato (stesso modello di §12). Scarto misurato dal tick: durata dell'incursione +1,2%, vita residua del boss dopo 100 s ±0,02 (assoluto), contributo ai boss mondiali ±0,1%.

## 9. La Breccia (infinita)

- Piani infiniti generati: livello = 100 + piano, statistiche ×1,06 per piano, 5 mostri per piano, **Guardiano ogni 10 piani**; affissi dal piano 5 (Fortificati, Furiosi, Sfuggenti, Vampirici, Protetti).
- Ricompense: Frammenti di Breccia (1 + piano/10), Casse della Breccia (5% + 0,2%/piano, max 50%), Essenza d'Era dai Guardiani. Classifica Steam: piano massimo.
- *Realizzazione (RAIDS).* Scheda **La Breccia** del Dungeon. Ogni mostro è generato da `rift.json` (`floor_level_base`, `stat_mult_per_floor`, `monster_type`, `guardian_type`, nomi bilingui, stile a rotazione); gli affissi si sommano dal piano indicato (Vampirici = rubavita del mostro, `lifesteal_pct`). Piano superato: Frammenti (con `rift_shard_pct`) e probabilità di Cassa; piano del Guardiano: anche Cassa e Essenza d'Era (× Era). Se l'Eroe cade la corsa finisce; si riparte dal piano 1 o dal piano dopo l'ultimo Guardiano battuto. Offline: i piani si valutano in sequenza (motore in modalità attesa) finché bastano tempo, cibo e la somma dei rischi di morte resta sotto 1. L'evento `rift_floor` (missioni) segue il piano raggiunto. Classifica Steam: non fatta (resta il piano massimo `rift.best` in salvataggio).
- *Reliquie.* Non sono parte del combattimento: sono istanze del Reliquiario di CrateSystem; il combattimento legge i loro bonus solo tramite Modifiers (fonte `relic:<uid>`, valore × bonus della condizione). **COMBAT-3:** verificato per tutte le 48 reliquie (`test_combat3`): ogni famiglia di combattimento (`combat_*`, `element_dmg_pct:*`, `ammo_save_pct`, `combat_revive_once`…) cambia davvero le statistiche dell'Eroe; `monster_drop_pct` (reliquie, glifi, cappe, talenti, Costellazioni) ora moltiplica la probabilità dei drop dei mostri (non casse, non famigli, tetto 100% per voce). `CombatSystem.relic_effects()` descrive le reliquie attive nella schermata Combattimento.
- *Postura delle ibride per fase (COMBAT-3, R44-9).* Negli scontri a fasi (incursioni) l'ibrida rivaluta la postura a ogni cambio di fase del boss: `CombatSim.st_alt` tiene le statistiche di ogni postura, `CombatSim.pick_stance` sceglie lo stile in vantaggio di triangolo contro lo stile della fase (poi quello alla pari, poi il primo). Cambio istantaneo, evento `stance` nel registro, stesso codice per il tick e per il passaggio offline (`boss_pass`).

## 10. Ere del Mondo (scala infinita)

- Era N: statistiche dei mostri ×**1,35^(N−1)**, XP e oro ×(1 + 0,30·(N−1)), Essenza d'Era (élite 25%, boss 1, boss di dungeon 3, incursione 10 drop; ×N ciascuno), **Cassa dell'Era N**.
- Si sblocca l'Era successiva sconfiggendo il Custode del Caveau nell'Era corrente. Si può sempre tornare a un'Era inferiore.
- Il potere del giocatore segue tramite **Rango** degli oggetti (+4% sulle statistiche base per rango, cap 12 × era massima), Stelle dell'Eroe, Costellazioni. Ritmo: docs/13 §4.

## 11. Taglie (mansione Caccia alle Taglie)

- Bacheca con 3 offerte (3 cambi gratuiti al giorno). Fasce: Facile (Lv 1), Media (30), Difficile (60), Leggendaria (90). Obiettivo: N uccisioni di un mostro bersaglio.
- XP Taglie per uccisione = 60% dell'XP del mostro + bonus al completamento (50% dell'XP totale dell'incarico); Marchi per uccisione 1/2/5/15; 25% di Cassa delle Taglie al completamento.
- **Ricercati:** 2% per uccisione durante un incarico: variante con vita ×3 e danno ×1,5, garantisce una Cassa delle Taglie e 10 Marchi.

## 12. Simulazione offline del combattimento

1. Misura con lo **stesso motore del tick** (`CombatSim`): un passaggio rapido a "valori attesi" per la durata, poi 48-400 scontri+ricomparse con numeri casuali **stratificati** (Latin hypercube, deterministici; **COMBAT-3:** una sequenza per tipo di estrazione — colpo, danno, critico, colpo del mostro… — così il k-esimo danno è sempre quello del k-esimo colpo: rumore sul boss da ~0,8% a ~0,35%, scarto massimo tra semi ±1%; i passi senza eventi si fondono in uno solo, con risultato identico e 2-3x meno costo). Scarto misurato rispetto al tick vero: ≤ 2% sulle uccisioni (`game/tests/test_combat2_offline.gd`). La stima rapida (solo valori attesi, ±5%) alimenta l'indicatore "Sicuro in idle".
2. Misura: tempo medio per uccisione, cibo/pozioni/munizioni consumati per uccisione, probabilità di morte per uccisione.
3. Estrapola sul tempo offline: uccisioni = Δt / tempo_medio, limitate da cibo/munizioni disponibili e dalla prima morte attesa.
   **FIX-COMBATTIMENTO (QA4 #1, resoconto 65).** La misura conta anche le morti: a ogni colpo del mostro somma la probabilità
   esatta che quel colpo uccida (vita attuale, distribuzione del danno) e continua estraendo il colpo condizionato alla
   sopravvivenza («pesi di sopravvivenza», `CombatSim.surv_mode`: stessa media dell'esito binario, molta meno varianza). Se il
   rischio atteso supera 1/4 di morte nel periodo, l'offline delle **zone** rifà la misura per posizione nella catena di scontri
   dopo una rinascita (catene da 4 che partono a vita piena, statistiche piene e da *Ferito*) e simula il processo come il tick:
   morte → 10 s → *Ferito* 5 min → si continua (`_offline_renewal`, valori attesi su ~20.000 scontri, RNG deterministico). Il
   Bentornato dice quante volte l'Eroe è caduto. Nei **dungeon** la prima corsa fallita ferma l'attività (come il tick); in
   **Estrema** l'Eroe si ritira prima della prima morte attesa. Cibo: porzioni misurate dallo stesso motore (non più la perdita
   media). Scarto misurato (Drago della Tempesta, 12 semi × 4.000 s): uccisioni e XP −4%, morti +18% (rumore del tick ±11%); prima
   0 morti offline contro 26 e XP +34%.
   **Imboscata** (QA4 #5): dal livello 10, nelle zone, un mostro normale può comparire come élite (`combat.rules.ambush`: 2% per
   comparsa, almeno 3 min tra due, vita ×3, danno ×1,15, XP e oro ×2). Non uccide mai: quando sarebbe letale, o sotto il 25% di
   vita senza cibo, si ritira (niente premio, niente *Ferito*). Offline in valore atteso (frazione delle uccisioni, scontri più
   lunghi, premio), con una riga nel Bentornato.
4. Per ogni uccisione stimata estrai **realmente** i drop (tabelle, casse, famigli) con il RNG: niente valori attesi per gli oggetti rari.
5. Applica XP, oro, oggetti; registra nel riepilogo il motivo di eventuale stop.

5b. **Cibo finito (1.0, revisione gameplay punto 1).** Se lo stop dell'offline è dovuto al cibo (la scorta negli slot non basta per i colpi che l'Eroe subirebbe), il resoconto porta `food_out = true` e il Bentornato lo dice col suo nome («Il cibo è finito, quindi l'Eroe è caduto…», non più un generico «Eroe KO»; in Estrema: «si è ritirato prima di cadere»). Nessun cibo viene regalato e nessun acquisto è automatico: l'economia del cibo (Cucina, Mercato, `food_per_h`) resta quella misurata dal simulatore. Il rimedio automatico già previsto è la **mansione di riserva** (punto 6, acceso di base): il tempo che avanza non va perso. Prima di uscire l'indicatore «Sicuro in idle» e la conferma di chiusura (`CloseGuard`) avvisano in rosso/giallo quando il cibo non basta per il limite offline.
6. **Mansione di riserva (QA81 M5).** Se il combattimento si ferma prima del tempo (Eroe caduto, cibo o munizioni finiti, ritiro in Estrema) in una zona o in un dungeon, il tempo che avanza va all'ultima mansione svolta prima del combattimento (R-OFF-4b). Non vale per incursioni, Breccia e boss mondiali (ma vedi «Ripresa» sotto: finito l'incontro, l'Eroe riprende l'attività di prima).

7. **Ripresa dopo incursioni, boss mondiali e Breccia (1.0, Q118-1).** Prima di entrare in uno di questi incontri `CombatSystem` ricorda l'attività precedente nella chiave additiva `state.return_to` (vuota di base, nessuna migrazione): zona e mostro, dungeon o mansione. A fine incontro (vittoria, sconfitta, tempo scaduto, ritiro automatico dell'Estrema) l'Eroe la riprende, come il dungeon con «Ripeti» (`_end_endgame`); il ritiro voluto (pulsante) non riprende. Offline il tempo che avanza dopo l'incontro va all'attività ripresa (zona/dungeon: stessa simulazione analitica, resoconti uniti; mansione: come il ripiego) e il Bentornato lo dice. Senza attività precedente l'Eroe resta «A riposo». Test: `test_return_to.gd`.

Vincolo di prestazioni: < 1 s per 24 h di offline su un PC medio.

## 13. Registro di combattimento

Ultime 200 righe: colpi, critici, abilità, cure, drop. Filtri: solo drop rari / solo eventi del boss. Disattivabile per prestazioni.

## 14. La Corsa a scelte (CORSA, resoconto 91)

Progetto e motivazioni: `docs/audit_2026-10-22/91_PROGETTO_CORSA.md`. Dati: `data/run_perks.json` (24 voci in 4 famiglie:
Offesa, Difesa, Bottino, Tecnica, ognuna con un compromesso) e `data/run_rules.json` (da `tools/gamedata/run.py`). Sistema:
`RunSystem.gd` (sezione di stato `run`, additiva); riquadro `RunPanel.gd` nella schermata Combattimento.

- Dal livello Eroe 15 (token `feature:run`, scheda tutorial), solo combattendo in una **zona**: ogni 30 uccisioni una Scelta
  di 3 voci (flusso RNG `world`, probabilità uniformi tra le voci disponibili, scritte nel pannello). Massimo 3 accumuli per
  voce, 12 scelte per Corsa, 1 Rilancia e 1 Escludi per Corsa.
- Le voci passano da Modifiers con la fonte `run:perks` (solo add) e valgono solo mentre si combatte nella zona della Corsa.
  Fermarsi, fare mansioni, dungeon, incursioni o Prove mette la Corsa in pausa; cambiare zona la chiude; la morte no.
- «Chiedi» (predefinito): la Scelta aspetta 90 s di gioco, poi segue la priorità delle famiglie (modificabile; con «Sicuro in
  idle» rosso la Difesa passa davanti). «Scegli per me»: subito.
- Dopo la 12ª scelta la comparsa successiva è il **Campione della Corsa** (mostro della zona, vita ×5, danno ×1,2; premio XP e
  oro ×5, 2 tiri della sua tabella, 25% di Cassa della zona). Non uccide: si ritira come l'Imboscata; riprova dopo 30 uccisioni,
  al massimo 2 tentativi. Vinto o no, la Corsa si chiude e riparte vuota.
- **Offline la Corsa è in pausa**: `CombatSystem.simulate_offline` toglie la fonte prima della misura e il contatore non
  avanza (l'offline resta identico al valore base). Il gioco aperto in sottofondo la fa girare.
- Controlli in `balance_sim` §4e: guadagno medio sul ciclo +12…+15% XP/h, picco ≤ +30%, ciclo 47-58 min, una scelta ogni
  ≤ 5,1 min nella zona più lenta, valore netto di ogni voce, casse del Campione +11%, nessuna chiave di strato (regola 9).

## 15. Preparazione dei boss (CORSA, resoconto 91)

Ogni meccanica può dichiarare una **risposta** (`boss_mechanics.json → answer`, da `combat.py → BOSS_ANSWERS`), applicata dal
motore unico (stesso risultato offline):
- *Colpo Devastante* (`guard`): se al colpo c'è uno scudo assorbente o un potenziamento difensivo attivo (danni subiti −,
  difese +, evasione +), il colpo fa metà danno.
- *Barriera* (`pierce`): con penetrazione ≥ 20% o un danno nel tempo sul boss la riduzione dei danni passa da −80% a −40%.
- *Nube Tossica*, *Stordimento* (`resist`): la resistenza agli stati li riduce già; la scheda consiglia il 30%.
- *Richiamo* (`multi`): tecniche a 3+ colpi o evocazioni per i servitori (solo indicazione).
La scheda del boss (tooltip del pulsante del mostro e dell'avversario) mostra per ogni meccanica la risposta e se l'Eroe
ce l'ha adesso («Preparazione n/t», `CombatSystem.boss_answers`). È una decisione presa prima dello scontro, senza tempo reale.
