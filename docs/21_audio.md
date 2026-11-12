# 21 — Audio: musica, effetti, interfaccia

> Elenco completo: `assets_plan/audio_manifest.csv` (id, categoria, descrizione/prompt, durata, priorità, cartella).

## 1. Direzione

- Musica **ambient fantasy rilassante**, adatta ad ascolto lungo (il gioco resta aperto per ore): tracce brevi (29–44 s, più varianti per contesto che ruotano per evitare la fatica d'ascolto) in loop morbido senza giunzione, strumenti acustici (liuto, arpa, flauto, archi leggeri, percussioni morbide), nessun picco di volume.
- Effetti **brevi, morbidi, informativi**: ogni suono comunica un evento (livello, drop raro, cassa). Nessun suono ripetitivo fastidioso: le azioni ripetute (colpo d'ascia ogni 3 s) hanno 4–6 varianti, volume basso, e si possono silenziare.
- Il suono del **rullo delle casse** è il più importante: tick crescenti/decrescenti con la velocità, rivelazione con accordo che cambia per rarità (Rara: semplice; ★: fanfara breve). Mai suoni da slot machine (monete che piovono, sirene).

> **Stato reale (23/10/2026): l'audio c'è ed è interamente sintetizzato dal progetto** (`tools/make_audio.py`, nessuna IA, nessun campione di terzi), 104 file OGG Vorbis 22,05 kHz in `game/assets/audio/{music,sfx}/`, 4,6 MB. È **misurato ma non ancora ascoltato da una persona** (vedi `docs/giocatori/CHECKLIST_VERIFICA_UMANA.md`). Le sezioni §2–§4 sono il piano originale; **§5 è la descrizione fedele dell'implementato**. Differenze rispetto al piano: l'autoload si chiama `AudioManager` (non `AudioService`); formato 22,05 kHz e non 44,1 kHz; bersaglio −22 LUFS stimati (non −16/−20); i suoni di combattimento per colpo/elemento/parata e gli ambienti (vento, mare…) non sono stati generati perché il gioco non emette quei segnali; al posto della musica commissionata c'è musica procedurale (decisione D-11 da riconsiderare prima di una versione commerciale).

## 2. Elenco (sintesi; dettaglio nel CSV)

| Gruppo | Quanti | Esempi |
|---|---|---|
| Musica | 26 | 12 contesti (città/menù, mansioni, 3 combattimenti per tier, dungeon, boss/incursione, Breccia, Tenuta, Prestigio/Ere, Sala dei Caveau, eventi) × 2–3 varianti; dettaglio in §5 |
| Mansioni | 17 × 3 varianti | colpo d'ascia, piccone su roccia, lenza, falcetto, scatto di trappola, martello su incudine, sega, forbici, sfrigolio, bollicine, scalpello su gemma, incisione, lima, monete rubate, zappa |
| Combattimento | 20 | colpo mischia/distanza/arcano (×3), critico, schivata, blocco, cura, morte nemico, morte eroe, abilità per elemento (6), livello Eroe |
| Casse | 10 | tick del rullo, rallentamento, rivelazione per 5 rarità, contratto firmato, fusione in Schegge, lucidatura |
| Interfaccia | 15 | clic, hover, apertura/chiusura pannello, notifica, errore, acquisto, vendita, livello, missione completata, impresa, famiglio trovato |
| Ambiente (facoltativo) | 6 | vento, mare, miniera, foresta, palude, tempesta (loop sotto la musica della zona) |

## 3. Come produrre l'audio

1. **Librerie con licenza commerciale** (preferibile per gli effetti): pacchetti CC0 (es. Kenney), Sonniss GDC bundle (licenza royalty-free), Freesound solo CC0/CC-BY con attribuzione nei crediti. Registrare la licenza di ogni file in `game/assets/audio/LICENSES.md`.
2. **Generazione con IA** (facoltativa): strumenti di generazione di effetti sonori o musica. **Obbligo:** dichiararli nella sezione "Contenuti generati con IA" della pagina Steam (docs/24) e verificare la licenza commerciale del piano usato.
3. **Musica su commissione** (consigliata per la 1.0 e per l'eventuale DLC colonna sonora).
4. Formato: `.ogg` (Vorbis, 44,1 kHz) per musica e ambienti, `.wav` 16 bit per effetti brevi; normalizzazione −16 LUFS musica, −20 LUFS ambienti; picchi ≤ −1 dBTP.

## 4. Implementazione (`AudioService.gd`)

- Bus: `Master → Music, SFX, UI, Ambience, Reel`. Volumi separati nelle Impostazioni.
- Musica a crossfade 2 s per contesto (schermata/zona). Silenzio automatico quando la finestra è ridotta a icona (opzione).
- Limite di voci per effetto ripetuto (max 2 contemporanee), variazione di tono ±5% casuale.
- Nessun suono durante la simulazione offline; il riepilogo "Bentornato" ha un suo jingle.

## 5. Crediti e provenienza (implementato)

Tutto l'audio del gioco è **generato proceduralmente dal progetto** con `tools/make_audio.py` (sintesi additiva, rumore filtrato e riverbero per convoluzione con numpy; deterministica: stesso nome, stessi byte; nessun campione di terzi, nessuna licenza da registrare). Uscita in `game/assets/audio/{sfx,music}/` (OGG Vorbis 22,05 kHz: effetti mono, stinger e musica stereo; WAV se `ffmpeg` manca). **Non** è audio generato da modelli di IA: nella pagina Steam va dichiarato come "audio sintetizzato dagli autori" (docs/24). Il riproduttore è l'autoload `AudioManager`.

**Rigenerare e controllare**

- `python tools/make_audio.py --report` rigenera tutto (circa 2,5 minuti), riscrive `assets_plan/audio_manifest.csv`, rimuove i file non più prodotti e stampa le misure. Poi `godot --headless --path game --import`.
- `python tools/make_audio.py --check --no-gen` misura i file esistenti (nessuna rigenerazione) ed esce con 1 se un limite è violato; lo stesso controllo gira in `python tests/test_audio_levels.py` (anche da `tools/check_all.py`).
- Limiti (`LIMITS` in `make_audio.py`): picco ≤ −1 dBFS dopo la codifica, nessun campione clippato, tracce livellate entro 3 dB sulla stessa loudness stimata (K-weighting semplificato, bersaglio −22 LUFS stimati; scarto reale 0,03 dB), durata musica 24–48 s, centroide spettrale ≤ 2,2 kHz, energia sopra 4 kHz ≤ 5 % e sopra 6 kHz ≤ 1 %, salto fra ultimo e primo campione ≤ 3× il 99° percentile delle differenze (nessun click nel loop), nessun silenzio a inizio/fine né finestre di 1 s sotto −55 dB, peso totale ≤ 12 MB (reale: circa 4,6 MB).

**Contenuto**

| Gruppo | File | Note |
|---|---|---|
| Musica | 26 | 12 contesti × 2-3 varianti di 29-44 s: `menu`, `skilling`, `combat_early` (zone 1-4), `combat_mid` (5-7), `combat_late` (8-10), `dungeon`, `boss` (Boss mondiali e Incursioni), `rift` (Breccia), `estate`, `prestige` (Prestigio ed Ere), `vault` (Sala dei Caveau e Rullo), `event` (eventi di mercato). Modi diversi (eolio, dorico, frigio, lidio, misolidio, minore armonico, scala a toni interi), tempi 54-126 bpm, strumenti sintetici morbidi (liuto, arpa, flauto, archi, coro, celesta, vibrafono, tamburi). Loop senza giunzione: il buffer è circolare e il riverbero è una convoluzione circolare; filtri a 38 Hz e 6,2 kHz per un ascolto non stancante. |
| Mansioni | 51 | 17 mansioni × 3 varianti, ognuna con un suono proprio (ascia, piccone, lenza, falcetto, trappola, incudine, sega, forbici, sfrigolio, bollicine, scalpello, incisione, lima, monete, zappa, fendente, timbro); stessa loudness (−25,5 LUFS stimati). |
| Stinger | 17 | level up, missione, vittoria, sconfitta, morte, prestigio, Era, 5 rivelazioni per rarità (Rara = accordo semplice … ★ = fanfara breve), impresa, famiglio, stella, Bentornato, sblocco. Stereo con ambiente breve. |
| Interfaccia e altri | 10 | clic, conferma, errore, notifica, azione completata, apertura Cassa, tick del rullo, colpo, moneta, vendita (pentatonica di Do per i suoni tonali). |

**Comportamento di `AudioManager`**

- Contesto → tracce: `CONTEXT_TRACKS` (stesso elenco del manifest; `tests/test_audio_levels.py` verifica la coincidenza). Il contesto dipende dalla schermata e, per il combattimento, dall'attività in corso: tier della zona (1-4/5-7/8-10), dungeon, boss/incursione, Breccia. Le fiere di mercato (`market_event`) attivano `event` per 120 s sulle schermate "menu".
- Varianti: a ogni ingresso nel contesto parte la variante successiva; ogni 150 s nello stesso contesto si passa a un'altra variante con crossfade di 2 s.
- Ducking: stinger e rivelazioni abbassano la musica di 9 dB (attacco 0,12 s, rilascio 0,9 s) tramite un effetto Amplify sul bus Music.
- Voci: 12 in tutto, 2 per suono, 2 per il gruppo delle mansioni; variazione di tono ±5 % sulle azioni ripetute; la stessa variante di mansione non suona due volte di fila.
- "Riduci animazioni": intervalli minimi doppi e −4 dB sulle azioni ripetute, crossfade musicale di 0,5 s, ducking quasi immediato.
- Silenzio: nessun suono mentre l'offline aggregato consuma il tempo (`Simulation.offline_running`); il jingle "Bentornato" suona a calcolo finito; bus Master muto a finestra ridotta a icona (opzione). Volumi separati in Impostazioni per Master, Musica, Effetti, Interfaccia e Rullo.
- Caricamento pigro con cache: ogni file si carica alla prima riproduzione (gli OGG restano compressi: 2 tracce + 4 effetti si caricano in pochi ms).
- I pulsanti suonano `ui_click` (bus UI) alla pressione; nessun suono all'hover (martellante).

**AUDIO-3 (qualità e copertura)** — matrice evento->suono, misure per categoria e checklist di ascolto in `docs/audit_2026-10-22/88_RESOCONTO_AUDIO.md`. Aggiunti 8 effetti (`hit_crit`, `dodge`, `hurt`, `kill`, `buy`, `crate_found`, `drop_rare`, `coop_link`), i segnali di sola presentazione `EventBus.combat_hit(kind)` e `EventBus.item_bought`, la loudness per categoria (`SFX_TARGET_LUFS` in `make_audio.py`: UI -20,5, combattimento e stinger -22,5, mansioni -25,5, rivelazioni crescenti), la dissolvenza di bordo su ogni effetto e i limiti DC / bordo / categoria in `LIMITS`. `python tools/audio_matrix.py --misura` verifica che ogni evento importante abbia un suono.
