# 01 — Visione, pilastri e perimetro

> Documento di riferimento per ogni decisione. Se una funzionalità non serve almeno uno dei 5 pilastri, non entra nel gioco.

## 1. In una frase

**VAULTFALL** *(titolo di lavoro)* è un **idle RPG/tycoon a menù** per PC (Steam) in cui raccogli, produci, combatti e gestisci una tenuta in un mondo fantasy dove il Caveau degli dèi è andato in frantumi e i suoi tesori piovono sulla terra sotto forma di **Casse sigillate** da aprire con chiavi forgiate a mano.

- IT: *"Raccogli, forgia, combatti. Apri le Casse cadute dal cielo."*
- EN: *"Gather, forge, fight. Crack open the Crates that fell from the sky."*

## 2. Scheda

| Voce | Scelta |
|---|---|
| Genere | Idle RPG + tycoon + "MMORPG a menù" (single-player, offline) |
| Ispirazioni | Melvor Idle / RuneScape (mansioni), simulatori di casse CS (apertura, rarità, usura, contratti), AdVenture Capitalist (tenuta e soci), Legends of IdleOn / Shakes & Fidget (classi, spedizioni), Antimatter Dimensions / Trimps (prestigio a strati, prove) |
| Piattaforme | Windows x64, Linux x64 (Steam Deck nativo); macOS opzionale dopo la 1.0 |
| Motore | Godot 4.x (GDScript tipizzato) |
| Grafica | Pixel art generata con uno strumento di IA per la pixel art (icone, ritratti, banner) + interfaccia vettoriale/tema Godot. Nessuna mappa 2D: tutto a menù |
| Lingue al lancio | Inglese + Italiano (struttura pronta per altre lingue) |
| Età attesa | PEGI 7–12 (vedi docs/24) |
| Sessioni | check-in da 2–5 minuti, sessioni attive da 30–90 minuti, progresso offline fino a 12 h (24 h con le Costellazioni) |
| Durata | ~40–50 h per portare una mansione a 100 senza bonus; **storia completa (Capitoli 0–11) ~55 h di gioco attivo** (misura del bot che gioca di continuo, 24/10/2026); in calendario dipende dalla cadenza: ~136 h con sessioni da 10 minuti ogni 8 h per il bot che cucina bene (Era II a 108 h, Era III a 136 h; ~160 h se la prima Stella si spende sull'Eroe), mentre il bot che non cucina il cibo migliore stima oltre 800 h sui due scontri più duri (Q120-2): un giocatore reale sta tra i due, nessuna cifra di orologio da promettere; poi contenuto infinito con Stelle, Ere, Breccia e Tenuta. Motivi e confronto con la stima iniziale (150–250 h): `docs/OPEN_QUESTIONS.md` Q1.0-2 |

## 3. I 5 pilastri

1. **Il progresso non si ferma mai.** Un'azione attiva alla volta + sistemi paralleli (Coltivazione, Tenuta, Spedizioni, Apprendisti). Offline al 100% di efficienza fino al limite. Ogni sessione deve chiudersi con almeno un obiettivo vicino visibile.
2. **Mansioni profonde e intrecciate.** 17 mansioni: tutto ciò che raccogli serve a qualcosa, tutto ciò che produci ha un consumatore (combattimento, chiavi, tenuta, missioni, mercato). Nessuna mansione "inutile".
3. **L'emozione della Cassa, onesta.** Rarità, usura (float), varianti Annalista, motivi rari, fasi colore, collezioni, contratti di conversione. **Probabilità sempre visibili**, nessuna "quasi-vincita" truccata, nessun denaro reale. Le Casse danno bonus di gioco veri (Finiture e Reliquie), non solo valore di rivendita.
4. **Prestigio infinito, mai inutile.** Stelle per ogni mansione, Ere del Mondo infinite, Rifondazione della Tenuta, Costellazioni con nodi infiniti, Prove del Custode. Ogni reset è *locale* e scelto dal giocatore: il personaggio non perde mai tutto.
5. **Un mondo vivo a menù.** Classi e specializzazioni, abilità automatiche, dungeon, incursioni con squadra di mercenari, boss mondiali a orario, mercato dinamico con notizie, fazioni con reputazione, rivali collezionisti. Sensazione MMO senza server.

## 4. Cosa ci rende diversi da Melvor Idle

| Melvor Idle | VAULTFALL |
|---|---|
| Combattimento a stili e abilità passive | Classi (3 + 6 specializzazioni + 3 ibride), talenti, **abilità a rotazione automatica**, risorse di classe |
| Nessun prestigio | **Stelle di Mansione** (prestigio per singola mansione), **Ere** infinite, **Rifondazione** della Tenuta, Costellazioni |
| Drop casuali tradizionali | **Sistema Casse** completo (rarità, float, Annalista, motivi, fasi, collezioni, contratti, pity) |
| Township (gestionale) | **Tenuta** in stile tycoon (livelli, traguardi ×2, coloni, Soci) |
| Mercato fisso | **Mercato dinamico** (domanda, tendenze, Gazzetta, Commesse delle fazioni) |
| — | **Spedizioni e mercenari**, **incursioni in squadra**, **boss mondiali** a orario, **Breccia** infinita |
| Maestria con pool | Maestria per azione **+ talenti di mansione a scelta ogni 10 livelli** + Apprendisti paralleli |

## 5. Pubblico

- **Primario:** giocatori di Melvor Idle, RuneScape/OSRS, IdleOn, Idle Clans (amano numeri, ottimizzazione, completismo).
- **Secondario:** fan dei simulatori di casse (collezionismo, rarità, "il colpo"), fan dei tycoon idle (AdCap, Egg Inc).
- **Non** è per: chi cerca azione in tempo reale o grafica in movimento.

## 6. Esperienza dei primi 60 minuti (obiettivo)

| Minuto | Cosa succede | Sistema introdotto |
|---|---|---|
| 0–1 | Prima azione (taglio del Pino) parte entro 20 secondi dall'avvio | Mansioni, coda XP |
| 1–5 | Primo livello, primo minerale, primo lingotto | Raccolta → Produzione |
| 5–10 | Pesca e cucina; spada di rame (Forgiatura 2); prima uccisione | Combattimento |
| 10–15 | **Prima Cassa** e prima Chiave forgiata, apertura con rullo (bot 1.0: 9,5 min; prima 27,7 min) | Casse |
| 15–30 | Erbe e fibre, Capitolo I: lupi, archi, orto | Tutte le raccolte base |
| 30–60 | Mercato, primo boss, prima finitura equipaggiata, primo talento di mansione (Lv 10) | Economia, Guardaroba, Talenti |

La regola: **mai più di 1 nuovo sistema ogni 5–10 minuti** nella prima ora; gli altri restano visibili ma bloccati con l'indicazione di come sbloccarli.

## 7. Perimetro per versione

| Versione | Contenuto | Uscita indicativa |
|---|---|---|
| **Vertical slice (M4)** | Prologo + Cap. I, 8 mansioni, 1 zona + dungeon, 3 casse, mercato base, salvataggio/offline | Interno |
| **Demo (Next Fest)** | Prologo + Cap. I–II completi, Tenuta base, 4 casse; salvataggio trasferibile al gioco completo | 2–3 mesi prima dell'EA |
| **Accesso Anticipato (M8)** | Capitoli 0–6, tutte le 17 mansioni, 6 zone, 6 dungeon, 1 incursione, 10 casse, Tenuta completa, Spedizioni, Stelle di Mansione, Steam (imprese, cloud) | ~6 mesi |
| **1.0 (M12)** | Capitoli 0–11, 10 zone, 10 dungeon, 3 incursioni, Ere, Breccia, boss mondiali, Prove, tutte le casse, eventi stagionali | ~10–12 mesi |
| **VAlfa1.0 (decisa il 23/10/2026)** | Gioco completo (Capitoli 0–11, Ere, Prove, Breccia, boss mondiali, eventi stagionali, modalità Autarchico/Estremo) **+ coop** (Compagni d'armi, seme settimanale, presenza degli amici, Gilda di amici via VPN). **Senza** Steam, controller/Deck, accessibilità. Tecnicamente giocabile, bug ammessi; la «1.0 vera» la decide il proprietario dopo gamethrough reali | Alfa per gli amici (0.1.0-alfa) |
| **Post-lancio** | Stagioni (leghe a ripartenza), nuove regioni (Zona 11+), nuove mansioni, mod di traduzione | ogni 2–3 mesi |

## 9. Non-obiettivi (cose che NON facciamo nella 1.0)

- Multigiocatore in tempo reale con **mondo condiviso** (una sola Tenuta e più eroi: sconsigliato, studio 60 §3.3), chat nel gioco, scambi o regali tra giocatori, server propri, account.
- **Aggiornamento del 23/10/2026:** il coop **non è più un non-obiettivo**. La **VAlfa1.0** (gioco completo + coop, senza Steam, controller/Deck e accessibilità) include un coop **asincrono e di presenza**, tra amici, via LAN/VPN (Hamachi, ZeroTier, Tailscale). Forma scelta (studio `docs/audit_2026-10-22/qa/60_STUDIO_COOP.md` e ricerca R5): ognuno gioca il proprio salvataggio, anche offline; il coop non cambia mai la partita personale. Fasi:
  - **Fase 0 (single-player)**: salvataggi a piena precisione, nessuno stato nascosto fuori dal salvataggio, `profile.player_uid`.
  - **Fase 1 (senza rete)**: «Compagni d'armi» (la scheda dell'eroe di un amico, come codice, al posto di un mercenario nelle incursioni) e «Seme della settimana» della Breccia.
  - **Fase 2 (LAN/VPN, ENet)**: «Gilda di amici» con fondo comune **a solo versamento** (nessun prelievo, nessun regalo), progetti, ruoli e voti, bonus **uguali per tutti** con tetto basso e asintotico, più la **presenza degli amici** (personaggini); la R5 aggiunge il «Boss della settimana» a danno cumulativo e un tetto di versamento anche settimanale.
  - **Fase 3**: incursioni e boss in diretta con eroi reali (bottino personale). **Fase 4 (Steam)**: lobby, inviti, relè: fuori dalla VAlfa.
  Restano esclusi scambi, regali, prestiti, Deposito comune con prelievo, PvP, casse con posta, anti-cheat invasivo. **Stato (23/10/2026): esiste solo il prototipo `tools/analysis/coop_proto/`; il coop nel gioco non è ancora implementato.**
- Inventario Steam / Mercato Steam / oggetti con valore reale.
- Acquisti in-game di qualsiasi tipo che diano valuta, chiavi, casse o vantaggi.
- Modalità da casinò (roulette, crash, coinflip, jackpot, scommesse, "upgrader" con posta).
- Mappe esplorabili 2D/3D o animazioni di combattimento complesse.
