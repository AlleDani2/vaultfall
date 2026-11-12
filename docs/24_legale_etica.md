# 24 — Legale ed etica: casse senza gioco d'azzardo, rating, proprietà intellettuale, IA, licenze

> Sintesi della ricerca del 21/10/2026 (fonti in docs/02 §10 e §5.3). **Non è una consulenza legale**: prima del lancio far verificare la pagina Steam e il sistema delle casse da un professionista se ci sono dubbi, soprattutto per i mercati con regole specifiche.

## 1. Il principio che ci protegge

Tutte le norme e le prassi recenti (PEGI 2026, Australia 2024, Brasile 2026, Belgio, Paesi Bassi, cause contro Valve negli USA) colpiscono due cose: **(a) oggetti casuali pagati con denaro reale** (o con valuta acquistabile con denaro reale) e **(b) oggetti che hanno un valore nel mondo reale** (rivendibili, scambiabili, convertibili). VAULTFALL non ha né l'una né l'altra:

- le Casse si aprono **solo** con chiavi forgiate o guadagnate giocando;
- **nessun acquisto in-game**, nessuna valuta acquistabile, nessun DLC che contenga valuta, chiavi, casse o oggetti casuali;
- **nessuno scambio** tra giocatori, nessun Inventario Steam, nessun Mercato Steam, nessun codice da riscattare;
- gli oggetti **non hanno valore reale** e lo diciamo esplicitamente.

## 2. Regole vincolanti di design (R-LEG)

1. **R-LEG-1:** nessun percorso che porti denaro reale verso casse, chiavi, valute, ricariche, "booster". Anche un pacchetto "sostenitore" non deve contenerne.
2. **R-LEG-2:** nessuna uscita degli oggetti dal gioco (niente Steam Inventory Service/Market, niente scambi, niente regali, niente codici).
3. **R-LEG-3:** **nessuna modalità con posta in gioco** in stile casinò: roulette, crash, coinflip, jackpot, mine, slot, "upgrader" con perdita dell'oggetto, battaglie di casse con posta. Sono le meccaniche che possono portare a PEGI 18 / R18+ in Australia come "gioco d'azzardo simulato". Le alternative adottate sono **senza posta**: Contratti di Conversione (crafting con esito casuale e probabilità mostrate), Affinatura deterministica, Sfida dei Collezionisti (classifica senza puntate).
4. **R-LEG-4:** **probabilità trasparenti e vere**: in ogni cassa le probabilità per rarità e per oggetto, **nominali ed effettive con la pity**, la probabilità Annalista, le **probabilità delle condizioni di ogni finitura** (`condition_odds`: sono esattamente quelle usate dal codice); nei contratti tutti gli esiti con probabilità e float previsto; contatore della pity visibile. Un test automatico (docs/26) confronta le frequenze simulate con i numeri mostrati.
5. **R-LEG-5:** **rullo onesto**: risultato estratto prima (e **non ri-estraibile ricaricando il salvataggio**: estrazione indicizzata da seme, cassa e contatore, docs/09 §6), riempitivi con probabilità reali, niente quasi-vincite costruite, niente testi o suoni che spingono ad "aprirne un'altra", Salta/Rapida/×10 sempre disponibili.
6. **R-LEG-6:** niente serie di accessi con penalità (le commesse si accumulano per 7 giorni): evita i criteri PEGI su "penalità per mancato ritorno".
7. **R-LEG-7:** nessuna offerta a tempo, nessun conto alla rovescia commerciale (non vendiamo nulla).
8. **R-LEG-8:** nessun lessico del gioco d'azzardo nel marketing ("scommetti", "vinci", "jackpot", "slot"); nessuna collaborazione con siti di skin/casse.
9. **R-LEG-9:** se in futuro si abilitano le **Carte Collezionabili di Steam**, devono essere del tutto scollegate dalle casse del gioco.

Testo da inserire nella sezione "Informazioni sul gioco" della pagina Steam (IT/EN):

> *Le Casse si aprono solo con chiavi ottenute o forgiate giocando. Nessun acquisto con denaro reale, nessuno scambio: gli oggetti non hanno alcun valore nel mondo reale. Le probabilità di ogni Cassa sono sempre visibili nel gioco.*
> *Crates open only with keys earned or crafted in game. No real-money purchases, no trading: items have no real-world value. The odds of every Crate are always shown in game.*

## 3. Classificazione per età (aspettative)

| Sistema | Situazione | Attesa |
|---|---|---|
| **PEGI** (criteri aggiornati, in vigore per i giochi presentati dal 1/6/2026) | "Oggetti casuali a pagamento" → minimo PEGI 16: **non si applica** (nessun pagamento). Missioni giornaliere → minimo PEGI 7 (12 se penalizzano chi non torna: noi no) | PEGI 7–12 |
| **Germania (USK)** | Rating obbligatorio su Steam dal 15/11/2024: lo genera Steam dal **questionario dei contenuti** | rispondere con precisione |
| **ESRB/IARC** (se un giorno si va su altri store) | possibile descrittore "Simulated Gambling" | Teen plausibile |
| **Australia** | "Simulated gambling" → R18+ obbligatorio se la meccanica *somiglia a un servizio di scommesse*: per questo niente modalità con posta | M o inferiore |
| **Brasile** (Legge 15.211/2025, in vigore dal 17/3/2026) | vieta le loot box **a pagamento** nei giochi accessibili ai minori: non si applica | ok |
| **Belgio / Paesi Bassi** | contestano le loot box **a pagamento** / con valore di mercato | ok |
| **Italia** | nessuna legge in vigore; proposta di legge A.C. 2798 (giugno 2026) sulle loot box con esborso per i minori di 16 anni; indagine AGCM (ottobre 2026) su spese in-game di minori | ok, monitorare |
| **UE** | Digital Fairness Act in preparazione (proposta attesa fine 2026): probabile stretta su loot box a pagamento e valute virtuali | monitorare |

## 4. Proprietà intellettuale

- **Vietato usare:** "Counter-Strike", "CS:GO/CS2", "StatTrak™" (marchio di Valve), "Souvenir" come termine dedicato, nomi di casse o skin di CS, nomi delle fasce di rarità di CS ("Mil-Spec", "Covert"…), nomi delle condizioni di CS ("Factory New", "Battle-Scarred"…), loghi e arte di Valve. VAULTFALL usa nomi propri: Annalista, Intatto/Lucido/Segnato/Logoro/Sfregiato, Rara/Epica/Leggendaria/Mitica/Reliquia ★.
- **Vietato usare:** nomi e contenuti propri di Melvor Idle (es. Golbin, nomi dei suoi oggetti/espansioni) e di RuneScape (Mithril, Adamant, Rune come metallo, Dragon gear, "Slayer", "skillcape"…). Sono ammessi concetti generici (mansioni, livelli 1–100, maestria) e nomi del folklore comune.
- **Ispirazione ≠ copia:** meccaniche generiche (rarità, float, contratti) non sono proteggibili come tali, ma testi, nomi, interfaccia e arte devono essere originali.
- **Verifica del nome** del gioco su Steam, itch.io ed EUIPO prima della pagina Steam (docs/01 §8).

## 5. Contenuti generati con IA (Steam)

- Il questionario dei contenuti di Steam ha la sezione **"Contenuti generati con IA"**. Regole in vigore (riscritte a gennaio 2026): si dichiarano i contenuti **visibili** nel gioco, nella pagina dello store e nel marketing creati con l'IA (arte, suoni, testi, traduzioni); gli **strumenti di sviluppo** (es. assistenti di programmazione come Claude Code) **non** vanno dichiarati.
- VAULTFALL dichiara come **pre-generati**: icone, ritratti, banner e capsule realizzati con uno strumento di IA per la pixel art; i **testi del gioco e le traduzioni** scritti con l'assistente IA (Claude) e rivisti dallo sviluppatore; il materiale promozionale che usa quell'arte. L'audio è sintetizzato dal progetto (non IA). Nessun contenuto **generato durante il gioco** (nessuna IA a runtime). Testo pronto IT/EN: `docs/store/DICHIARAZIONE_IA.md` (aggiornato dalla revisione SHARK 1.0, punto 8: la bozza precedente citava solo l'arte).
- Alcune fonti non ufficiali parlano di obblighi più estesi dal 2026: **ricontrollare il modulo al momento dell'invio**.
- Attenzione al mercato: nel 2026 Steam riceve moltissimi idle game "fotocopia" con IA. Qualità, coerenza di stile e originalità del design sono la difesa (docs/02 §7).

## 6. Licenze da tenere in ordine

| Elemento | Cosa verificare | Dove annotarlo |
|---|---|---|
| Font | licenza OFL/CC0 o commerciale; includere il testo della licenza OFL nella build | `game/assets/fonts/` + crediti |
| Audio | licenza di ogni file (CC0, royalty-free, commissionato) | `LICENSES.md` §5 (audio sintetizzato dal progetto: nessuna licenza di terzi) |
| Godot | licenza MIT: includere il testo nei crediti/cartella licenze | schermata Crediti |
| GodotSteam | licenza MIT | Crediti |
| GUT | solo sviluppo (non nella build) | — |

## 7. Privacy

Nessun dato personale raccolto; nessuna telemetria nella 1.0; ID Steam usato solo dalle API di Steam (imprese, Cloud, classifiche). Se in futuro si aggiunge telemetria: consenso esplicito, informativa privacy, possibilità di disattivarla (GDPR).
Dall'Alfa 0.1.0 esistono **statistiche di sessione solo locali** (`SessionStats`): spente di default, attivabili dalle Impostazioni, salvate in `user://stats/`, solo numeri aggregati con ID casuale locale, esportabili (CSV/JSON) e cancellabili. Nessun invio in rete: l'utente manda il file a mano, come lo ZIP di «Segnala un problema» (`ReportBuilder`). Un test (`test_feedback.gd`) vieta nel codice di feedback ogni classe di rete.

### 7.1 Coop tra amici (VAlfa1.0): IP dell'host, dati personali, GDPR

- **Nessun server nostro, nessun account, nessuna chat**: non trattiamo dati personali degli utenti.
- **L'IP dell'host è un dato personale** (GDPR, considerando 30 e giurisprudenza UE). Con la connessione diretta (ENet) o via VPN (Hamachi, ZeroTier, Tailscale) chi entra in una Gilda di amici **vede l'indirizzo IP dell'host** (in VPN è l'indirizzo virtuale della rete privata, ma resta un identificativo). Il gioco deve: (1) dirlo in chiaro **prima** di ospitare e prima di entrare («Ospitando, gli amici che entrano potranno vedere il tuo indirizzo IP. Ospita solo con persone di cui ti fidi, meglio dentro una VPN privata»); (2) richiedere una conferma esplicita la prima volta (fatto: finestra bilingue una tantum nella Lobby prima di «Crea stanza» e «Entra», ricordata nelle impostazioni dalla chiave `coop_ip_ack`); (3) non salvare l'IP altrove che nel computer locale e non includerlo mai in ZIP di «Segnala un problema» né nei log senza maschera (fatto: l'ultimo host sta solo nelle impostazioni locali, chiave `coop_last_host`, che lo ZIP non copia; non è più nel salvataggio, i salvataggi vecchi vengono ripuliti al caricamento e la copia dello slot nello ZIP ne è comunque priva; `ReportBuilder.scrub` maschera gli indirizzi IP nei testi; test `test_coop_ip_privacy.gd`); (4) non mostrare l'IP degli altri ai membri.
- **Nome visibile**: soprannome scelto dal giocatore (filtro minimo di lunghezza e caratteri), mostrato solo agli amici della gilda; nessun dato anagrafico.
- **Codici «Compagni d'armi»**: contengono solo statistiche della scheda dell'eroe; nessun dato personale.
- **Salvataggio di gilda** (`user://coop/`): resta sul computer dell'host e dei membri; nessun invio a terzi.
- **Steam (fase 4, fuori VAlfa)**: il relè di Valve nasconde gli IP; aggiornare questa sezione prima di attivarlo.
- **Statistiche di sessione** (§7): restano locali; il coop non le invia.

