# 09 — Casse, Finiture, Reliquie ★ (il "case simulator" di VAULTFALL)

> Dati: `data/items/crate.json`, `data/items/skin.json` (240 finiture), `data/items/relic.json` (48 reliquie), `data/collections.json`, `data/crate_rules.json`, `data/items/key.json`. Tabelle: `docs/appendici/A4_casse_finiture.md`. Vincoli legali ed etici: **docs/24** (obbligatori).

## 1. Il sistema in breve

```
Fonti di Casse ──► Cassa sigillata ──(Chiave del tier)──► Rullo ──► Finitura / Reliquia ★ (istanza con float, motivo, Annalista)
                                                                     │
          ┌─────────────────────┬────────────────────┬──────────────┼────────────────┬───────────────────┐
     Guardaroba (bonus)   Collezioni (bonus)   Contratto di Conversione   Affinatura     Fusione → Schegge   Mercato (oro)
                                               (10 → 1 superiore)   (lucidare)    (Banco dei Caveau)
```

## 2. Fonti

| Fonte | Cassa | Probabilità |
|---|---|---|
| Azioni di raccolta | Cassa del Raccoglitore | durata/2400 per azione |
| Azioni di produzione | Cassa dell'Artigiano | durata/2400 |
| Forgiachiavi, Borseggio | Cassa della Mano Grigia | durata/2400 · durata/1200 |
| Coltivazione | Cassa del Mercante | 2% (ortaggi) / 5% (alberi) per raccolto |
| Mostri normali / élite / boss | Cassa della zona | 1/150 · 1/40 · 1/4 |
| Fine dungeon | Cassa della zona | garantita |
| Incursioni | Cassa della zona | 2 garantite |
| Taglie (completamento / Ricercati) | Cassa delle Taglie | 25% / garantita |
| Breccia | Cassa della Breccia | 5% + 0,2% per piano (max 50%) |
| Caveau Privato (Tenuta) | casse delle zone sbloccate | 1 ogni 8 h / (1 + 0,05×livello) |
| Ere II+ | Cassa dell'Era N | drop dei boss nell'Era |
| Eventi stagionali | Cassa dell'evento | valuta evento |

`crate_find_pct` aumenta la probabilità (cap +200%). Le casse **non si comprano con denaro reale, mai**. Le casse si possono vendere/comprare al Mercato di gioco a prezzo basso (10% del prezzo della chiave in Emporio).

## 3. Chiavi

| Chiave | Forgiachiavi Lv | Ricetta | Apre | Prezzo Emporio (max 5/giorno) |
|---|---|---|---|---|
| Rame (T1) | 1 | 2 Lingotti di Rame | Valle, Risacca, Raccoglitore, Artigiano | 200 |
| Ferro (T2) | 20 | 2 Lingotti di Ferro + Ametista + 2 Schegge | Ferroradice, Sussurri, Mano Grigia, Mercante | 420 |
| Cobalto (T3) | 40 | 2 Cobalto + Smeraldo + 5 Schegge | Fiele, Cenere, Taglie | 880 |
| Oricalco (T4) | 60 | 2 Oricalco + Zaffiro + 10 Schegge | Brina, Archivio | 1.900 |
| Astrale (T5) | 80 | 2 Astralite + Opale Nera + 20 Schegge | Tempesta, Celeste, Breccia | 3.900 |
| Stellare (T6) | 95 | 2 Acciaio Stellare + Lacrima Stellare + 40 Schegge | Casse dell'Era | 8.200 |

Le chiavi **non si vendono** al Mercato (evita di trasformare la Forgiachiavi in una stampante d'oro). Altre fonti: Banco dei Caveau (Schegge), negozio dei Gettoni, Tavola Rara, Borseggio, ricompense.

## 4. Rarità e probabilità (mostrate SEMPRE nella schermata della cassa)

| Rarità | Simbolo | Colore | Probabilità | Contenuto per cassa | Bonus finitura |
|---|---|---|---|---|---|
| Rara | ◆ | grigio acciaio `#8DA2B8` | **79,20%** | 6 finiture | +1,0% |
| Epica | ◆◆ | indaco `#6F7BE6` | **15,80%** | 4 | +2,0% |
| Leggendaria | ✦ | orchidea `#C65AA8` | **3,80%** | 3 | +3,5% |
| Mitica | ✦✦ | arancio brace `#E8702A` | **0,90%** | 2 | +5,5% |
| Reliquia ★ | ★ | oro `#F5CF4F` | **0,30%** | 3–4 reliquie (+ eventuale famiglio ★) | effetto unico |

- Dentro una rarità ogni oggetto ha **la stessa probabilità** (mostrata per oggetto: es. Rara 79,2% / 6 = 13,2% ciascuna).
- **Pity** (contatore visibile "aperture senza ★"): un contatore per ogni valore di `pity_family` della cassa (ogni cassa ha il suo; tutte le Casse dell'Era ne condividono uno, `crate_era`; capsule ed eventi non hanno pity). Dopo **180** aperture senza ★ la probabilità di ★ cresce di **+0,03%** a ogni apertura; alla **300ª** è garantita (audit 53: con 200/+0,05%/500 la garanzia non scattava mai, P(gap≥400)=0,001%; ora è raggiunta nel 4,6% delle serie). Calcolo **esatto** (`core.relic_pity_stats`, salvato in `crate_rules.pity`): **1 ★ ogni 175,0 aperture = 0,571%** (nominale 0,30% = 1/333; 155,8 con «Destino Paziente» al massimo). I riempitivi del rullo usano le probabilità **effettive** (pity inclusa). La schermata mostra **sempre entrambe**: *"★ 0,30% (con la pity in media 0,57%: 1 ogni ~175 aperture)"* e le probabilità effettive delle altre rarità (`effective_rarity_pct`). Il nodo "Destino Paziente" anticipa la soglia (e il gioco ricalcola i numeri mostrati).
- Colori + simboli: la rarità non è mai comunicata solo dal colore (daltonismo).

## 5. Proprietà di ogni istanza (generate all'apertura)

1. **Condizione (float)**: ogni finitura ha un intervallo `[float_min, float_max]`. Sono possibili solo le condizioni la cui fascia **interseca** l'intervallo; la condizione si estrae con i pesi nominali **rinormalizzati** su quelle possibili; il float si estrae uniforme nell'**intersezione** tra fascia e intervallo. Le probabilità risultanti sono scritte in ogni finitura (`condition_odds`) e sono **quelle mostrate al giocatore**: nessuna differenza tra numeri mostrati e numeri usati.

| Condizione | Fascia | Peso | Bonus | Valore |
|---|---|---|---|---|
| Intatto | 0,00–0,10 | 5% | ×1,20 | ×1,80 |
| Lucido | 0,10–0,25 | 25% | ×1,10 | ×1,30 |
| Segnato | 0,25–0,50 | 34% | ×1,00 | ×1,00 |
| Logoro | 0,50–0,72 | 21% | ×0,92 | ×0,85 |
| Sfregiato | 0,72–1,00 | 15% | ×0,85 | ×0,70 |

   Esempi (da `core.condition_odds`): intervallo 0,00–1,00 → 4/22/36/22/16% (i pesi nominali); 0,10–0,90 → Intatto impossibile, Lucido 22,9%, Segnato 37,5%, Logoro 22,9%, Sfregiato 16,7%; 0,00–0,08 → Intatto 15,4%, Lucido 84,6%. Le finiture con intervallo stretto creano rarità naturale, ma sempre dichiarata.
2. **Annalista** (10%): conta azioni o uccisioni fatte con la finitura equipaggiata; ai traguardi 100 / 1.000 / 10.000 / 100.000 / 1.000.000 aggiunge **+0,2 punti** al bonus (max +1,0). Valore ×2,2.
3. **Motivo** (seme 0–999, uniforme): solo estetico + valore; le Mitiche hanno semi speciali `7, 77, 777` = "Motivo Leggendario" (valore ×4).
4. **Fase colore** (solo Reliquie ★): Alba 30%, Meriggio 30%, Vespro 25% (×1,15), Notte 13% (×1,35), Gemma Rubino 1% (×6), Gemma Zaffiro 1% (×6). Implementazione: **palette swap** via shader (nessuna immagine extra).
5. **Bonus finale** di una finitura = `bonus_rarità × moltiplicatore_slot × bonus_condizione + bonus_Annalista`. Reliquie: modificatori fissi × bonus_condizione.

## 6. Il rullo (specifica dell'animazione)

- **Il risultato si estrae PRIMA dell'animazione.** Il rullo lo mostra soltanto.
- **Estrazione indicizzata (anti save-scum, QA82 Q82-1).** L'esito della N-esima apertura di una cassa è una funzione pura di **(seme di estrazione del salvataggio, id della cassa, N)**: non si pesca dal flusso casuale condiviso del gioco. Il contatore N di ogni cassa sta nel salvataggio (`crates.draw_n`) e avanza PRIMA dell'estrazione; il seme (`crates.draw_seed`) si deriva una volta dal seme della partita e non cambia più. Conseguenze volute: ricaricare un salvataggio riporta anche il contatore, quindi si ottiene lo **stesso** esito; aprire altre casse, aprire con o senza rullo, o riavviare non spostano l'esito della prossima apertura di quella cassa; l'unico modo di "cambiare" i numeri è consumare chiavi, cioè giocare. Il rullo ha un generatore a parte (derivato allo stesso modo) e non può influire sul risultato; il Contratto di Conversione ha il proprio contatore. Nessun salvataggio sincrono è necessario per l'equità: non salvare non dà vantaggio, perché il risultato non dipende dall'orologio né da altro. La probabilità di ogni apertura resta quella mostrata (pity inclusa): cambia solo da dove si prende il numero casuale.
- Striscia orizzontale di **60 tessere**; vincitore alla posizione **52**; le altre 59 tessere estratte con **le stesse probabilità reali** (nessuna "quasi-vincita" piazzata vicino al vincitore: `fake_near_miss: false` è un vincolo, non un'opzione).
- Durata 5,5 s, easing `cubic_out`, punto di arresto casuale **dentro** la tessera vincente; suono di "tick" a ogni tessera che passa l'indicatore (volume e frequenza decrescenti); rivelazione con bagliore del colore della rarità.
- Opzioni sempre disponibili: **Salta** (clic/tasto), **Apertura rapida** (0,8 s), **×5** e **×10** (griglia di risultati con le rarità in ordine), "riduci animazioni" nelle Impostazioni.
- Dopo l'apertura: pulsanti **Equipaggia nel Guardaroba**, **Blocca**, **Fondi**, **Vendi**, **Contratto**.
- Testi neutri ("Hai trovato: …"). Vietato: "Per un pelo!", "Riprova!", conti alla rovescia, effetti che spingono ad aprire ancora.

## 7. Guardaroba (bonus delle finiture)

29 slot raggruppati: **Combattimento** (arma, mano secondaria, testa, torso, gambe, mani, piedi, mantello), **Attrezzi** (ascia, piccone, canna, falcetto, trappola, grimaldello), **Bottega** (martello, sega, ago, padella, alambicco, scalpello, stilo, lima), **Mercante** (stendardo, libro mastro, borsa, sacca dei semi), **Mano Grigia** (maschera, portachiavi), **Taglie** (distintivo).

- Una finitura per slot; il bonus vale sempre (non serve un oggetto specifico equipaggiato). Lo slot "arma" mostra la finitura come **nome e colore** dell'arma nel pannello Eroe ("Spada d'Acciaio «Brace Ardente»").
- Le **Reliquie ★** vanno nei **Reliquiari** (1 slot; 2° dall'Emporio a Eroe 50 o dalle Costellazioni; 3° con 3 Stelle Eroe).

## 8. Collezioni

- Ogni cassa = una collezione. **Collezione completa** (tutte le 15 finiture, qualsiasi condizione) → bonus permanente (es. Valle: +2% XP raccolta). **Collezione Aurea** (anche tutte le ★) → bonus raddoppiato + titolo.
- Schermata **Album**: griglia con sagome per gli oggetti mancanti, contatore "posseduti/totale", miglior float posseduto per finitura, numero di Annalisti.

## 9. Contratto di Conversione (trade-up)

1. Si scelgono **10 finiture della stessa rarità** (Rara, Epica, Leggendaria), tutte normali **oppure** tutte Annaliste.
2. Prima di firmare, il gioco **mostra ogni possibile risultato con la sua probabilità e il float previsto**.
3. Risultato: rarità successiva. Collezione estratta in proporzione al numero di input per collezione; dentro la collezione, uniforme tra le finiture della rarità successiva.
4. Float in uscita: `out = out_min + (out_max − out_min) × media(norm_i)`, con `norm_i = (f_i − min_i) / (max_i − min_i)`.
5. **Contratto Aureo** (sblocco Cap. VI): **5 Mitiche → 1 Reliquia ★** del pool delle collezioni in ingresso.

## 10. Affinatura (Banco di Affinatura — sblocco Cap. VI)

Nessuna posta in gioco: si spendono Schegge, l'oggetto resta sempre al giocatore.
- **Lucidatura:** `float_nuovo = float − 0,10 × (float − float_min)`; costo `ceil(schegge_rarità × 0,5 × (1 + lucidature_fatte))`, max 10 per oggetto.
- **Incisione Annalista:** rende Annalista una finitura normale (non ★); costo `schegge_rarità × 8`.
- **Targhetta:** rinomina un oggetto (10.000 oro).

## 11. Fusione e Banco dei Caveau

- Fondere: Rara 1 · Epica 5 · Leggendaria 25 · Mitica 125 · ★ 500 **Schegge del Caveau** (+`shards_pct`). Media per apertura fondendo tutto, pity inclusa: ~6,5. (★ a 500 e non a 1.000: con la pity la ★ esce quasi il doppio delle volte rispetto al nominale; vedi `reports/balance_report.md` §6.)
- Banco dei Caveau: Chiavi T1–T6 (30/60/120/240/480/960 Schegge), Clessidra (150), Capsule (40).

## 12. Sfida dei Collezionisti (settimanale, sblocco Cap. VII)

Classifica contro 3 rivali PNG (Bruno il Fortunato, Greta Occhiolungo, Mastro Zecchino). Punteggio = somma dei punti rarità degli oggetti **trovati** nella settimana (1/5/25/125/250: la ★ vale il 28% del punteggio atteso; era 1000 = 61%, audit 84). Rivali: media 40/60/95 punti × tier di chiave, deviazione 20%. **Nessuna scommessa, nessun oggetto messo in palio.** Premi per posizione in Schegge e chiavi.

## 13. Mercato delle finiture

- Prezzo = valore base × condizione × Annalista × motivo × fase × tendenza (Ornstein-Uhlenbeck, σ giornaliero 6%) × domanda; tassa di vendita **10%**.
- Le casse "ritirate" (quando esce una nuova Era) aumentano di valore dell'1,5% a settimana (sapore "investimento", nessun valore reale).
- Valore della Rara di una cassa = 1% dell'oro/ora del tier della sua chiave; Epica ×5, Leggendaria ×25, Mitica ×125, ★ ×500. **Ritorno atteso 59–69%** del prezzo di una chiave comprata, calcolato con le probabilità **effettive** (pity inclusa) e le condizioni di ogni finitura (la cassa è un pozzo; il valore vero sono i bonus). Verificato in `reports/balance_report.md` §6 (controllo automatico 55–80%).

## 14. Capsule cosmetiche

Capsula degli Stendardi e degli Emblemi: 12 cosmetici ciascuna (stendardi del profilo, emblemi), **senza statistiche**, senza chiave, 2.500 oro o 40 Schegge, **non rivendibili** (audit 53 E1: con i bonus di mercato la rivendita dava fino a 20.000 oro/ora).

## 15. Algoritmo di apertura (riferimento per `CrateSystem.gd`)

```
func open_crate(crate_id):
    assert has_item(crate_id) and (crate.key == null or has_item(crate.key))
    consume(crate_id, 1); if crate.key: consume(crate.key, 1)
    fam     = crate.pity_family                             # null = nessuna pity
    p_relic = odds.relic + (pity_bonus(pity[fam]) if fam else 0)   # 1.0 alla 300ª
    rarity  = roll_rarity(odds with relic = p_relic)       # le altre rarità si riducono in proporzione
    if fam: pity[fam] = 0 if rarity == "relic" else pity[fam] + 1
    def_id  = uniform_choice(contents[rarity])            # relic_pool se ★ (famiglio compreso)
    inst    = new_instance(def_id)
    inst.condition = weighted_choice(def.condition_odds)   # §5.1: probabilità già rinormalizzate
    inst.float  = uniform(max(cond.min, def.float_min), min(cond.max, def.float_max))
    inst.annalist = rng.randf() < 0.10 + annalist_bonus
    inst.seed   = rng.randi_range(0, 999)
    inst.phase  = roll_phase() if rarity == "relic"
    reel = build_reel(winner=inst, length=60, index=52, filler=real_odds)
    stats.crates_opened += 1; collections.update(def_id); achievements.check(...)
    return {instance: inst, reel: reel}
```

## Deposito pieno e apertura (resoconto 117)

Il Deposito pieno **non blocca mai l'apertura**. Il QA82 F3 rifiutava l'apertura senza posto per non perdere la Finitura; dal resoconto 117 l'esito si estrae e si applica come sempre (indicizzato per cassa e contatore, `docs/24`: l'esito non dipende dal posto) e la Finitura che non entra va nel **Carro di Ritiro** (`BankSystem.add_instance` → `OVERFLOW_UID`; nel risultato `carro = true`, `uid = ""`). La Sala dei Caveau scrive «Deposito pieno: il premio è nel Carro di Ritiro (N pezzi)». Le chiavi si comprano e si usano anche a Deposito pieno (la pila del Carro conta). Il Carro tiene al massimo `constants.offline.overflow_max_instances` pezzi; oltre, si vendono al Mercato solo Finiture non bloccate che non siano Annaliste né Reliquie (dichiarato nel Registro). Nessun azzardo, nessuna probabilità nascosta: il Carro non cambia né i pesi né l'ordine delle estrazioni.
