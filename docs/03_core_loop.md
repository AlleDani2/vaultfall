# 03 — Core loop, modello delle azioni, sblocchi e offline

## 1. I cicli di gioco

| Scala | Ciclo | Esempio |
|---|---|---|
| **Secondi** | Azione → XP → oggetto | Taglia un Pino (3 s) → +11 XP, +1 Tronco |
| **Minuti** | Raccogli → produci → equipaggia/vendi | 30 Tronchi → 30 Assi → Arco Corto |
| **Ore** | Livello → sblocco tier → nuova zona/missione | Lv 20 Miniera → Ferro → Acciaio → Cap. III |
| **Giorni** | Commesse, spedizioni, Tenuta, casse accumulate, boss mondiali | Ritorno al mattino: riepilogo offline, aperture, raccolta Tenuta |
| **Settimane** | Stelle di Mansione, Rifondazioni, collezioni, Sfida dei Collezionisti | Prima Stella in Taglialegna, collezione Valle completa |
| **Mesi** | Ere del Mondo, Breccia, Prove, eventi stagionali | Era IV, piano 120 della Breccia |

## 2. Modello delle azioni (REGOLE)

- **R-AZ-1 — Un'azione attiva.** Il giocatore svolge **una sola azione attiva** alla volta: un'azione di mansione (raccolta, produzione, borseggio) **oppure** il combattimento (zona, dungeon, incursione, Breccia, taglia).
- **R-AZ-2 — Sistemi paralleli sempre attivi:** Coltivazione (timer degli orti), Tenuta (produzione continua), Spedizioni (timer dei mercenari), Apprendisti (fino a 5 azioni di raccolta/produzione parallele a efficienza ridotta), Pozioni/Banchetti (timer).
- **R-AZ-3 — Ciclo dell'azione:** ogni azione ha una durata base; al termine si risolvono in quest'ordine: (1) consumo ingredienti (con risparmio), (2) prodotti (con doppio), (3) drop secondari, (4) cassa, (5) famiglio, (6) XP mansione, (7) XP maestria, (8) aggiornamento obiettivi di missioni/imprese, (9) riavvio automatico.
- **R-AZ-4 — Fine materiali:** se mancano ingredienti l'azione si ferma e passa alla **coda azioni** (se acquistata) oppure resta in pausa con notifica. Con 1 Stella nella mansione: **automazione** (riprende da sola quando gli ingredienti tornano disponibili, es. dagli Apprendisti o dalla Tenuta).
- **R-AZ-5 — Coda delle azioni:** fino a 3 (poi 6, poi +4 dalle Costellazioni) azioni in sequenza con condizione di fine (quantità, livello, tempo, "fino a esaurimento").
- **R-AZ-6 — Cambio azione istantaneo**, senza penalità, tranne nei dungeon (non si cambia equipaggiamento) e nelle incursioni.
- **R-AZ-7 — Banca piena:** se un prodotto non entra nel Deposito l'azione si ferma (notifica), tranne per gli oggetti con regola di vendita automatica.

## 3. Ordine degli sblocchi (gating dei sistemi)

Gli sblocchi avvengono **tramite missioni della storia** (vedi docs/12 e `data/quests.json`, campo `unlocks`). Tabella riassuntiva:

| Missione | Sblocca |
|---|---|
| Prologo 1–6 | Taglialegna, Miniera, Forgiatura, Pesca, Cucina, Combattimento (Valle), Eroe, **Forgiachiavi, Casse, Guardaroba**, Erboristeria |
| Cap. I | Trappole, Carpenteria, Sartoria, Coltivazione, **Mercato**, dungeon Granaio Maledetto |
| Cap. II | Costa del Sale, **Tenuta** (Casolare, Segheria, Magazzino, Pozzo, Peschiera, Bottega), Alchimia, Borseggio, **Commesse e Fazioni** |
| Cap. III | Miniere di Ferroradice, Gioielleria, Campi, Allevamento, Incisione Runica, Caveau Privato, **Accademia (Apprendisti)** |
| Cap. IV | Bosco Sussurrante, **Taverna (mercenari) e Spedizioni**, **Taglie** |
| Cap. V | Paludi di Fiele, **Contratti di Conversione**, **Incursione I** |
| Cap. VI | Deserto di Cenere, **Banco di Affinatura**, **Contratto Aureo** |
| Cap. VII | Picchi di Brina, **Sfida dei Collezionisti**, Incursione II |
| Cap. VIII | Archivio Sommerso, **Costellazioni e Stelle di Mansione** presentate dalla storia (requisito: livello totale 600) |
| Fuori dalla storia | **Rito** (Stella di prova, una per mansione) dal livello 50 di una mansione: compare la scheda Prestigio (`feature:prestige`); la Stella vera (livello 100) e le Costellazioni (appena c'è Polvere) sono già usabili da lì, la missione del Cap. VIII le racconta e dà i token `feature:skill_prestige`/`feature:constellations`, che non bloccano nulla (FIX-MEDIO, QA2: chi seguiva la storia non vedeva un reset prima di 170 h) |
| Cap. IX | Cime della Tempesta, **Boss Mondiali** |
| Cap. X | Caveau Celeste, Incursione III, **Ere** e **Breccia** |
| Missioni di classe | Specializzazioni (Eroe 30), Classi Ibride (1 Stella Eroe) |

**R-UNL-1:** ogni sistema bloccato resta visibile in grigio con il testo "Si sblocca con: *missione X*".
**R-UNL-2:** lo sblocco mostra una scheda tutorial di 3 righe al primo accesso (disattivabile).

## 4. Offline (REGOLE)

- **R-OFF-1 — Durata:** `Δt = clamp(ora_attuale − ultimo_salvataggio, 0, limite)`; limite base **12 h**, +1 h per livello del nodo "Pazienza del Custode" (max **24 h**). Se l'orologio di sistema va indietro, Δt = 0 e il riferimento viene riallineato.
- **R-OFF-2 — Efficienza 100%** per tutto (mansioni, combattimento, tenuta, coltivazione, spedizioni, apprendisti). Nessun malus offline (scelta di design: è un gioco premium, non c'è nulla da vendere).
- **R-OFF-3 — Simulazione:** mansioni e produzione si calcolano **analiticamente** (azioni = Δt / durata media, con consumo ingredienti e stop a esaurimento); il combattimento con il **simulatore statistico** (docs/05 §12); casse e drop rari con estrazioni reali (non valori attesi) usando il RNG salvato.
- **R-OFF-4 — Riepilogo "Bentornato"**: tempo trascorso, XP e livelli guadagnati, oggetti ottenuti (raggruppati), casse trovate, eventi (spedizioni concluse, raccolti pronti), motivo di eventuale interruzione (cibo finito, banca piena, morte).
- **R-OFF-4b — Nessuna perdita, nessuna punizione (QA81, `docs/audit_2026-10-22/98_RESOCONTO_OFFLINE.md`):**
  1. *Deposito pieno.* La produzione offline prosegue. Ciò che non entra (pile nuove, istanze) aspetta nel **Carro di Ritiro** (`bank.overflow_*`) e si scarica da solo appena c'è posto; le pile già presenti entrano sempre. Il Carro tiene al massimo `constants.offline.overflow_max_instances` istanze: oltre, il pezzo si vende al prezzo del Mercato e il Bentornato dice quanti pezzi e quanto oro. Mai perso in silenzio, nessun azzardo, esito deterministico. Online (giocatore presente) vale ancora l'avviso «Deposito pieno».
  1b. *Il Carro vale per TUTTE le fonti* (resoconto 117, `docs/audit_2026-10-22/117_RESOCONTO_DEPOSITO_PIENO.md`): anche online, con il giocatore presente, l'esito di un'apertura di Cassa, di un acquisto (Emporio, Banco dei Caveau, Gettoni), di una ricompensa di missione o di una Taglia che non trova posto va nel Carro, mai rifiutato e mai perso. Le unità impilabili del Carro contano in `bank.count()` e si consumano (chiavi, ingredienti): il posto mancante non ferma più nulla. Oltre il tetto di istanze si vendono solo le Finiture comuni e rare non bloccate (mai Reliquie, Annaliste, uniche, bloccate); il Registro riassume cosa è entrato nel Carro (`constants.bank.carro.notice_s`).
  2. *Combattimento che si ferma* (Eroe caduto, cibo o munizioni finiti, ritiro in Estrema): il tempo che avanza va all'ULTIMA mansione svolta prima del combattimento (mansione di riserva, interruttore nel Combattimento, `safe_fallback_default` nei dati), con la stessa simulazione analitica. Non vale per incursioni, Breccia e boss mondiali. Senza mansione di riserva il Bentornato spiega quanto tempo è andato inutilizzato.
  3. *Assenze brevissime* (sotto `constants.offline.min_apply_s`): il simulatore non parte; il tempo si accumula in `offline_carry_s` e si applica alla prossima sessione (chi sospende e riprende spesso non perde nulla e non paga ogni volta il costo del calcolo).
  4. *Riferimento di tempo non valido* (`saved_at_unix` ≤ 0): Δt = 0 e nessun regalo del limite pieno; avviso nel gioco.
  5. *Oltre il limite* (R-OFF-6): il Bentornato dice quanto tempo dell'assenza non è stato contato.
  6. *Sospensione con il gioco aperto* (QA120, Steam Deck e portatili): il tempo del motore non conta il sonno del PC (su Linux è monotonico), quindi `Clock.check_suspend` confronta l'orologio di sistema con il tempo misurato; l'eccesso oltre `constants.offline.resume_min_gap_s` (120 s) conta come assenza (stesso limite R-OFF-1, stesso Bentornato). In pausa, senza partita o con orologio tornato indietro non si accredita nulla.
  7. *Avvisi di caricamento*: gli avvisi di `Game.load_game` (orologio indietro, salvataggio senza data, ripiego sul backup) restano in `Game.load_notices` e li mostra la schermata principale appena nasce (prima si perdevano: StartScreen carica e solo dopo cambia scena).
- **R-OFF-5 — Clessidre:** la *Clessidra del Custode* (oggetto, non acquistabile con denaro) applica 1 h di progresso offline istantaneo all'azione attiva.
- **R-OFF-6:** il gioco non usa orari server; il tempo reale serve solo per offline, eventi stagionali, commesse giornaliere e boss mondiali. La parte dell'assenza **oltre** il limite di R-OFF-1 fa avanzare solo gli orologi di calendario (`GameSystem.advance_calendar`, chiamato da `Game.apply_absence` prima dell'offline: giorni delle Commesse, limiti giornalieri dell'Emporio, bacheca e Gazzetta del Mercato, rinnovi delle Taglie), mai la produzione (audit 84). Manipolare l'orologio è tollerato (gioco single-player), ma le **classifiche Steam** accettano solo valori plausibili (vedi docs/17 §9).

## 5. Struttura di una sessione tipo

1. **Bentornato** (riepilogo offline) → 2. **Raccolta** (Tenuta, orti, spedizioni) → 3. **Casse** (apertura in blocco) → 4. **Missioni/Commesse** (consegne rapide) → 5. **Pianificazione** (coda azioni, apprendisti, nuove spedizioni) → 6. gioco attivo o uscita.

## 6. Obiettivi sempre visibili

- Barra superiore: azione attiva con barra di avanzamento e "tempo al prossimo livello".
- Pannello **Prossimi traguardi** (3 righe): prossimo sblocco di tier, missione attiva, obiettivo più vicino tra imprese/collezioni.
- Ogni schermata mostra cosa serve per il passo successivo (ingredienti mancanti in rosso, livelli richiesti, tempo stimato).

## 7. Notifiche (in-game, non di sistema)

Livello raggiunto · tier sbloccato · drop raro (≥ Epico, famiglio, unico) · cassa trovata (raggruppate) · banca quasi piena · cibo in esaurimento (combattimento) · spedizione completata · raccolto pronto · boss mondiale in arrivo (5 min prima). Tutte disattivabili per categoria nelle Impostazioni.
