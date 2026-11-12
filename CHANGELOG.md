# Changelog

Tutte le modifiche importanti a VAULTFALL sono annotate qui. Il formato segue [Keep a Changelog](https://keepachangelog.com/it-IT/1.1.0/); le versioni seguono il numero in `game/version.json`. Le novità mostrate ai giocatori sono in `game/changelog.json` (IT/EN) e devono restare coerenti con questo file.

## [Non rilasciato]

## [1.0.0] - 2026-10-29

Prima versione pubblica (Windows e Linux). Gioco completo a menù, per un giocatore e senza connessione, con cooperativa facoltativa in LAN/VPN.

### Per i giocatori
- Vedi la voce 1.0.0 di `game/changelog.json`: è il testo mostrato nella schermata «Novità» e nel LEGGIMI del pacchetto.

### Aggiunto
- Menù principale con illustrazione a tutta pagina, schermata di caricamento, slot con classe, capitolo, tempo e data, ripristino dalle copie di sicurezza, menù di pausa (Esc), Crediti e licenze di terze parti.
- Impostazioni a sei schede (Gioco, Schermo, Audio, Accessibilità, Comandi, Salvataggi e dati), con VSync, schermo intero, comandi rimappabili, alto contrasto, modalità per la visione dei colori e testo grande.
- Integrazione Steam facoltativa: 118 imprese, Rich Presence e Cloud dei salvataggi. Senza Steam il gioco resta identico e completamente offline.
- Sabbia del Custode (Spinta del Tempo) e nuovo Deposito a griglia con schede, Armeria e modalità vendita.
- Conferma una tantum sull'indirizzo IP prima di ospitare o entrare in una stanza cooperativa.
- Pacchetto di rilascio minimo (eseguibile, LEGGIMI, avviso sulle licenze, testi delle licenze) con controlli automatici bloccanti.
- Icona dell'eseguibile e della finestra dall'emblema del gioco.

### Cambiato
- L'Eroe riprende l'attività dopo Incursioni, boss mondiali e Breccia; la finestra «Rieccoti» spiega il cibo finito; la prima Cassa arriva dopo circa 10 minuti; le gemme trovate a gioco chiuso contano per le missioni; battute meno ripetitive.
- Salvataggi più sicuri: copie giornaliere e per versione, importazione con conferma, valori fuori limite riportati nei limiti, conferma di uscita se il salvataggio finale non riesce.
- Gli strumenti per sviluppatori sono disattivati in tutte le versioni di rilascio.
- I testi delle Casse dicono con precisione cosa contengono: Finiture con piccoli bonus permanenti, Reliquie e Famigli, aperte solo con valuta e chiavi di gioco. Il termine inglese per le Finiture è ora sempre «Finish».
- `LICENSES.md` e `NOTICE.txt` in forma pubblica; LEGGIMI, guide rapide e wiki scritti per i giocatori.

## [0.1.0] - 2026-10-23

Anteprima del gioco completo a menù, per un giocatore e senza connessione, senza Steam, controller e accessibilità (aggiunti nella 1.0).

### Aggiunto
- 17 mansioni (raccolta, produzione, Coltivazione, Alchimia, Borseggio, Banchetti), maestria, talenti di mansione, coda azioni, apprendisti, progresso a gioco chiuso con finestra di riepilogo.
- Combattimento a classi (3 base, 6 specializzazioni, 3 ibride), abilità con risorse, talenti, dungeon, Incursioni con squadra di mercenari, boss mondiali, la Breccia, Taglie, Reliquie, posture per fase.
- Casse con probabilità sempre visibili, risultato estratto prima dell'animazione, garanzia (pity), Rullo (Rapida, ×5, ×10), Guardaroba, Album, Rimpasti, Affinatura e Banco dei Caveau. Si aprono solo con chiavi guadagnate o forgiate giocando.
- Economia: Mercato dinamico con Gazzetta, Emporio, Commesse dei PNG e Commesse giornaliere e settimanali (regola dei 7 giorni), Fazioni e incarichi di fazione.
- Tenuta (edifici, coloni, Dispensa, Rifondazione e Soci), Mercenari, Spedizioni, Luoghi Segreti, Compendio (118 Imprese, Titoli, Famigli).
- Prestigio a strati: Stelle di Mansione, Rito, Polvere Stellare, 35 Costellazioni, Rifondazione, Ere del Mondo, Prove del Custode.
- Missioni: Prologo e Capitoli I–XI (270 missioni), sblocchi progressivi, Manuale in gioco.
- Modalità Autarchico ed Estremo (morte permanente) con titolo e cornice dedicati.
- Eventi stagionali (Notte delle Lanterne, Festa del Gelo, Fioritura, Regata del Sole) con valuta, Casse solo cosmetiche, Eco e Negozio a prezzo fisso, senza obblighi di ritorno.
- Testi in italiano e inglese, audio sintetizzato, effetti visivi e tema grafico con telai originali.
- «Segnala un problema» in Impostazioni e nel menù di pausa: crea un file ZIP sul Desktop, senza inviare nulla da solo. Statistiche locali spente di default.
- Salvataggi con scrittura atomica, copie di sicurezza e tre slot.
