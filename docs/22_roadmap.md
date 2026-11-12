# 22 — Roadmap di sviluppo per Claude Code (milestone, compiti, criteri di accettazione)

> Ogni compito `T-x.y` è pensato per **una sessione di Claude Code** (1–3 ore di lavoro dell'agente). Ordine vincolante: non iniziare una milestone se la precedente non soddisfa tutti i criteri. Lo stato si aggiorna in `PROGRESS.md`.

## Panoramica

| Milestone | Obiettivo | Esito giocabile |
|---|---|---|
| **M0** | Progetto Godot, strumenti, segnaposto | Il gioco si avvia con il layout vuoto |
| **M1** | Nucleo: dati, stato, tempo, salvataggi, modificatori, formule | Test delle formule verdi |
| **M2** | Mansioni di raccolta e produzione + Deposito + offline | Ciclo taglia → forgia giocabile |
| **M3** | Combattimento base (Valle), equipaggiamento, cibo | Si combatte nella Zona 1 |
| **M4** | **Vertical slice**: Casse, Forgiachiavi, Guardaroba, Missioni (Prologo + Cap. I), Bentornato | Prima ora di gioco completa |
| **M5** | Economia: Mercato, Emporio, Commesse, Fazioni, Coltivazione, Borseggio, Alchimia, Banchetti | Cap. I–II |
| **M6** | Tenuta, Apprendisti, Mercenari, Spedizioni, Luoghi Segreti, audio base | Cap. II–IV · **Demo** |
| **M7** | Combattimento avanzato: classi, abilità, talenti, dungeon, taglie, qualità/glifi, contratti, Affinatura | Cap. V–VI |
| **M8** | **Accesso Anticipato**: Steam, accessibilità, controller/Deck, arte lotti 1–4, IT/EN | Build EA |
| **M9** | Prestigio: Stelle, Costellazioni; Incursioni; zone 7–8; Sfida dei Collezionisti | Cap. VII–VIII |
| **M10** | Endgame: zone 9–10, Incursione III, Ere, Breccia, Prove, boss mondiali, classifiche | Cap. IX–XI |
| **M11** | Rifinitura: arte e audio completi, eventi, bilanciamento finale, prestazioni | Release candidate |
| **M12** | **1.0** | Lancio |

## Stato reale al 23/10/2026 (spunte per milestone)

> Legenda: [x] fatto e testato · [~] parziale · [ ] non fatto · [—] fuori dalla VAlfa1.0 (Steam, controller/Deck, accessibilità). Le milestone sono state fatte in parallelo e in ordine diverso; il dettaglio è in `PROGRESS.md` e nei resoconti `docs/audit_2026-10-22/`.

| Milestone | Stato | Note |
|---|---|---|
| M0 | [x] | T-0.3: segnaposto PNG non generati (l'arte vera li ha sostituiti) |
| M1 | [x] | Formulas 341/341 casi; SCHEMA_VERSION 2 |
| M2 | [x] | InventorySystem = `BankSystem`; Crafting dentro `SkillSystem`; offline analitico |
| M3 | [x] | `CombatSystem` + `CombatSim` |
| M4 | [x] | Casse, Rullo, Guardaroba, Album, Missioni, Bentornato, Manuale; prima ora ~65 min (bot) |
| M5 | [x] | Mercato, Emporio, Commesse (anche giornaliere/settimanali), Fazioni, Coltivazione, Alchimia, Banchetti |
| M6 | [~] | Tenuta, Apprendisti, Mercenari, Spedizioni, Luoghi Segreti, audio: [x]. T-6.0 (nome, Steamworks, B13 store) e T-6.6 (demo): [—] |
| M7 | [x] | classi, abilità, talenti, dungeon, Taglie, qualità/Glifi, Contratti, Affinatura, Banco; Reliquie e posture (COMBAT-3) |
| M8 | [—] | Steam, accessibilità e controller fuori dalla VAlfa. Fatti dentro: localizzazione IT/EN, arte B01–B12, strumenti dell'Alfa (versione, Novità, «Segnala un problema») |
| M9 | [x] | Stelle, Rito, Polvere, Costellazioni, Incursioni, Sfida dei Collezionisti, Prove |
| M10 | [~] | Zone 9–10, Ere, Breccia, boss mondiali: [x]. Classifiche Steam: [—] |
| M11 | [~] | Eventi stagionali [x], audio procedurale [x] (non ascoltato), bilanciamento [x], effetti (Fx) e tema UI [x]; arte: audit visivo in corso; T-11.5 (48 h a ×100) e T-11.6 (Steam): non fatti |
| M12 | [ ] | Sostituita dalla **VAlfa1.0** (docs/01 §7); la 1.0 vera la decide il proprietario |
| **Coop (VAlfa1.0)** | [ ] | Fase 0 e 1–2 da fare (studio 60): `CompanionSystem`, `CoopSession`/`NetService`, schermata «Gilda di amici», presenza degli amici. Esiste solo il prototipo |

Fuori roadmap ma fatti: modalità Autarchico ed Estremo (`ModeSystem`), wiki statica (`tools/make_wiki.py`), bibbia comica e 3 giri di testi, revisione EN, strumenti di feedback, test di coerenza (`tests/test_coherence.py`).

---

## M0 — Fondamenta del progetto

- **T-0.1** Creare `game/` con **Godot 4.7.2**: `project.godot` con nome dal codename, impostazioni di docs/17 §1 (base 1280×720, finestra di sviluppo 1600×900, `canvas_items` + `expand` + `scale_mode=integer`, filtro `Nearest`, `snap_2d_transforms_to_pixel`, cartella utente personalizzata `VAULTFALL`, `low_processor_usage_mode`), icona segnaposto. Struttura cartelle di docs/17 §2.
- **T-0.2** Installare **GUT** (9.7.0 certa per Godot 4.7; provare la 9.7.1, se non c'è ripiego sulla 9.7.0) in `game/addons/gut/` (zip della release su GitHub, ramo `godot_4_7`), cartella dei test `game/tests/`, test "hello" che passa con `python tools/run_tests.py` (lo script esiste già: importa le risorse e lancia GUT in headless con l'eseguibile di `GODOT_BIN`; codice di uscita 0 = tutto verde).
- **T-0.3** `python tools/sync_data.py`, `python tools/make_placeholders.py`, `python tools/export_reference_values.py`; verificare che `game/data`, `game/assets` (segnaposto) e `game/tests/reference_values.json` esistano.
- **T-0.4** Scena `MainScreen.tscn` con layout di docs/16 §2 (barra superiore, barra laterale con tutte le voci in grigio, pannello centrale, colonna destra), tema base, font provvisorio.
- **Criteri:** avvio senza errori; test headless verdi; layout visibile e ridimensionabile; nessun errore nel log.

## M1 — Nucleo

- **T-1.1** `GameData.gd`: caricamento di tutti i JSON di `res://data/`, indici per id, accesso tipizzato, controllo dei riferimenti in debug (stesse regole principali di `validate_data.py`).
- **T-1.2** `Formulas.gd` + `NumberFormat.gd` + test GUT su **tutti** i casi di `reference_values.json` (oggi 208: il test li legge tutti dal file, quindi il numero può crescere senza toccare il codice).
- **T-1.3** `Modifiers.gd` (docs/14) + test.
- **T-1.4** `GameState.gd` (forma di docs/17 §4), `Rng.gd` (flussi con stato salvabile), `Clock.gd` (passo 0,1 s, velocità di debug ×1/×10/×100 con scorciatoia F9).
- **T-1.5** `SaveService.gd`: 3 slot, salvataggio automatico, scrittura atomica, backup, versione di schema, export/import Base64 + test round-trip e file corrotto.
- **T-1.6** `Loc.gd` + `ui_strings.csv` importato; selettore lingua IT/EN.
- **Criteri:** tutti i casi di `reference_values.json` verdi; salvataggio e caricamento identici; cambio lingua istantaneo.

## M2 — Mansioni e Deposito

- **T-2.1** `InventorySystem` (impilabili + istanze, spazi, blocco, vendita base) + schermata Deposito con lista virtualizzata, filtri, ricerca, tooltip.
- **T-2.2** `SkillSystem` per la raccolta: azioni, XP, livelli, tier, maestria, drop secondari, casse (solo conteggio per ora), famigli (registrazione), attrezzi.
- **T-2.3** `CraftingSystem`: ricette, consumo, risparmio/doppio, lotti, qualità, bruciatura; schermata Produzione (docs/16 §3.2) con quantità e "Max".
- **T-2.4** Schermata Mansione (docs/16 §3.1), barra superiore con azione attiva e tempo al livello, registro a destra, notifiche di livello.
- **T-2.5** `OfflineSimulator` per mansioni (analitico) + finestra **Bentornato** (versione base) + limite 12 h.
- **T-2.6** Coda delle azioni (sbloccabile: per ora attiva in debug).
- **Criteri:** Taglialegna 1→10 in ~8 min reali a ×1 (±15%); un'ora di offline dà gli stessi risultati della simulazione tick per tick (±2%); Deposito con 500 oggetti fluido.

## M3 — Combattimento base

- **T-3.1** `StatsSystem` (attributi, statistiche derivate con spiegazione), `EquipmentSystem` (slot, requisiti, due mani, munizioni), schermata Eroe (griglia slot + statistiche).
- **T-3.2** `CombatEngine` a tick (docs/05 §3): colpo, danno, riduzione, critico, triangolo, elementi, rigenerazione, ricomparsa, morte; cibo e auto-mangiare (I/II/III); munizioni.
- **T-3.3** Tabelle di drop + Tavola Rara + oro; schermata Combattimento (docs/16 §3.3) con registro e bottino.
- **T-3.4** Zona 1 completa (5 mostri + boss con meccanica "Colpo Devastante"); simulazione offline del combattimento (docs/05 §12) e indicatore **Sicuro in idle** (docs/05 §6).
- **T-3.5** Test: TTK medio su 1.000 combattimenti entro ±10% dal report per Guerriero/Ramingo/Arcanista nella Valle.
- **Criteri:** si combatte, si muore, si mangia, si raccoglie il bottino; offline di combattimento coerente.

## M4 — Vertical slice (prima ora)

- **T-4.1** `CrateSystem` (docs/09 §15): apertura, probabilità, pity, float/condizione, Annalista, motivo; schermata Sala dei Caveau con contenuto e probabilità visibili.
- **T-4.2** **Rullo** (`CrateReel`): 60 tessere, vincitore in 52, riempitivi con probabilità reali, easing, suoni segnaposto, Salta, Rapida, ×5, ×10; "riduci animazioni".
- **T-4.3** Forgiachiavi (chiavi T1–T2), Guardaroba (29 slot) con bonus via `Modifiers`, Album delle collezioni.
- **T-4.4** `QuestSystem` con tutti i tipi di obiettivo usati da Prologo e Cap. I; `UnlockSystem` (voci bloccate in grigio con indicazione); tutorial di 3 righe al primo sblocco.
- **T-4.5** Bentornato completo (casse, missioni, motivi di stop); pannello "Prossimi traguardi".
- **T-4.6** **Manuale** in gioco (docs/16 §3.8): pagine generate dai dati con formule e probabilità di tutte le casse disponibili.
- **T-4.7** Playtest guidato: cronometrare la prima ora (docs/01 §6) e correggere i punti lenti.
- **Criteri:** nuova partita → fine Cap. I in 60–90 minuti; prima Cassa entro 15 minuti; nessun sistema introdotto prima del suo sblocco.

## M5 — Economia e mansioni speciali

- **T-5.1** `MarketSystem` (domanda, tendenze OU, tassa, scorte, storico 30 giorni con grafico), Gazzetta.
- **T-5.2** Emporio (tutte le voci di `shop.json`), Deposito a pagamento, auto-mangiare, coda azioni, set.
- **T-5.3** Commesse + Fazioni (reputazione e bonus dei gradi) + incarichi di fazione.
- **T-5.4** Coltivazione (orti, frutteti, timer paralleli, offline), Borseggio (successo, stordimento, drop), Alchimia (pozioni con cariche), Banchetti (timer), oli.
- **T-5.5** Commesse giornaliere/settimanali con negozio dei gettoni (regola dei 7 giorni).
- **T-5.6** Storia Cap. II (fino al Capitano Ghignosale) — la Tenuta è sbloccata ma vuota fino a M6.
- **Criteri:** vendere 1.000 tronchi di fila abbassa il prezzo come da formula; le commesse si rinnovano; coltivazione corretta anche dopo 10 h offline.

## M6 — Tenuta, Gilda e Demo

- **T-6.1** `EstateSystem`: edifici, livelli +1/+10/Max, traguardi, coloni, Dispensa, Magazzino, Bottega, raccolta, Rifondazione/Soci, offline.
- **T-6.2** Caveau Privato, Accademia + `ApprenticeSystem` (slot paralleli).
- **T-6.3** Taverna: `MercenarySystem` (reclutamento, tratti, livelli, infortuni) + `ExpeditionSystem` (tabellone, durate, successo, ricompense) + Luoghi Segreti.
- **T-6.4** Storia Cap. III–IV; taglie (bacheca, Ricercati) con mansione Caccia alle Taglie.
- **T-6.5** Audio base (bus, musica città/lavoro/combattimento, effetti UI e casse) con file segnaposto o definitivi.
- **T-6.6** **Build demo**: Prologo + Cap. I–II, Tenuta base, 4 casse; limite di contenuto con avviso "nel gioco completo"; salvataggio compatibile; pulsante lista dei desideri (link alla pagina Steam).
- **Criteri:** simulazione della Tenuta coerente con il report (prima Rifondazione ~11 h a ×1 in accelerato); demo giocabile 60–120 min.

## M7 — Combattimento avanzato

- **T-7.1** Classi, specializzazioni (missioni di classe), attributi liberi, abilità con lista di priorità e risorse (Furia/Concentrazione/Mana), effetti (danno, DoT, buff, debuff, cure, scudi, evocazioni, stordimento).
- **T-7.2** Talenti (alberi per classe), respec.
- **T-7.3** Dungeon (ondate, regole, ricompense, traguardi), meccaniche dei boss (tutte quelle in `BOSS_MECHANICS`).
- **T-7.4** Qualità degli oggetti creati, incastri e Glifi, Insegne, unici.
- **T-7.5** Contratti di Conversione (anteprima risultati e float), Contratto Aureo, Affinatura, Fusione, Banco dei Caveau.
- **T-7.6** Zone 2–6 + Cap. V–VI; Incursione I (squadra di mercenari).
- **Criteri:** report di bilanciamento riprodotto in gioco (±10%) per le zone 1–6 e le tre classi.

## M8 — Accesso Anticipato

- **T-8.1** `SteamService` con GodotSteam (GDExtension per Godot 4.7.x, OPEN_QUESTIONS #6): le **100 imprese di fase 1** (`steam_phase = 1`) configurate in Steamworks con le icone 256×256, statistiche, Cloud (Auto-Cloud, docs/23 §7.2), rich presence; build di test con `steam_appid.txt` (mai nella build).
- **T-8.2** Impostazioni complete, accessibilità (docs/16 §7), controller e Steam Deck (1280×800), risparmio risorse in secondo piano (docs/17 §11: ≤ 3% CPU).
- **T-8.3** Arte: completare tutti i lotti con milestone ≤ M8 nel manifest (B01–B08 e B12; B13 è già fatto in T-6.0) con la procedura d'arte; nessun segnaposto nelle schermate dell'EA; shader di palette per le fasi delle ★.
- **T-8.4** Localizzazione IT/EN completa fino al Cap. VI; verifica testi tagliati.
- **T-8.5** Esportazione Windows/Linux, depot Steam, ramo `beta`; checklist di docs/26 §4.
- **T-8.6** Materiali della pagina Steam (docs/23): capsule, screenshot, trailer, descrizione, dichiarazione IA.
- **Criteri:** build EA approvata dalla revisione Steam; nessun blocco su Deck; salvataggi in Cloud tra due PC.

## M9 — Prestigio e incursioni

- **T-9.1** Stelle di Mansione (Eco, automazione, talenti doppi, cornici, Polvere), schermata Stelle.
- **T-9.2** Costellazioni (5 rami, costi, rimborso settimanale), schermata.
- **T-9.3** Incursione II, zone 7–8, Cap. VII–VIII, Sfida dei Collezionisti, Prove del Custode.
- **Criteri:** una Stella dimezza circa i tempi del ciclo successivo come da docs/13; nessun nodo rompe i limiti del simulatore.

## M10 — Endgame infinito

- **T-10.1** Zone 9–10, dungeon 9–10, Incursione III (3 fasi), Cap. IX–XI.
- **T-10.2** Ere (selettore, scalatura, Essenza, Ranghi, Casse dell'Era generate dal modello).
- **T-10.3** La Breccia (piani, affissi, Guardiani, negozio, classifica Steam con validazione).
- **T-10.4** Boss mondiali (finestre, contributo simulato, Corno dell'Adunata).
- **Criteri:** Era 10 e piano 200 della Breccia simulabili senza numeri anomali; classifiche funzionanti.

## M11 — Rifinitura

- **T-11.1** Arte: lotti rimasti (B09–B11, se non già fatti in M9–M10), rigenerazione delle immagini peggiori, ricolorazioni e derivate rifatte, foglio di confronto dello stile per ogni lotto (nessuna icona "fuori stile").
- **T-11.2** Audio definitivo (docs/21): sostituzione dei segnaposto, mix e volumi per bus.
- **T-11.3** Eventi stagionali (docs/27): calendario, valute e Casse evento, cosmetici.
- **T-11.4** Bilanciamento finale: confronto tra `reports/balance_report.md` e i tempi reali dei playtest (salvataggi esportati dai tester), correzioni **solo** dal generatore.
- **T-11.5** Prestazioni (docs/17 §11): sessione di 48 h simulata a ×100 senza perdite di memoria; avvio ≤ 3 s.
- **T-11.6** Steamworks: imprese di fase 1 (100) già configurate in M8 + le 18 di fase 2 se le *Profile Features* sono sbloccate, icone PNG 256×256 da `build/steam_achievements/` (docs/23 §7.1), statistiche, classifiche, Cloud verificato su due PC.
- **T-11.7** Localizzazione completa IT/EN e revisione dei testi inglesi da un madrelingua.
- **Criteri:** nessun segnaposto visibile; tutti i test verdi; tutti i "Controllo automatico" del report OK; checklist di docs/26 completa.

## M12 — 1.0

- **T-12.1** Build finale Windows/Linux, verifica Steam Deck, depot e ramo `default`; il ramo `beta` resta per le patch.
- **T-12.3** Comunicazione: trailer 1.0, aggiornamento della pagina e delle capsule, annuncio nella community Steam e sui social.
- **Criteri:** build approvata da Valve; nessun bug bloccante aperto; salvataggi EA caricati senza perdite.

---

## Regole di lavoro per ogni sessione di Claude Code

1. Leggere `CLAUDE.md`, `PROGRESS.md` e il documento della milestone corrente.
2. Scegliere il prossimo compito non completato; se manca un'informazione, registrarla in `docs/OPEN_QUESTIONS.md` e proseguire con l'ipotesi più conservativa.
3. Scrivere i test insieme al codice; eseguire i test headless e `validate_data.py`.
4. Aggiornare `PROGRESS.md` (compito, file toccati, test, problemi aperti).
5. Mai modificare i JSON a mano; mai inserire numeri di bilanciamento nel codice.
