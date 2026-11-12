# 08 — Mondo, storia, zone, mostri e PNG

> Dati: `data/zones.json`, `data/monsters.json`, `data/npcs.json`, `data/factions.json`, `data/chapters.json`. Tabelle complete: `docs/appendici/A3_zone_mostri.md`.

## 1. Premessa narrativa

Il mondo di **Orvane** era custodito dal **Caveau Celeste**, la camera del tesoro degli dèi che orbitava sopra le nuvole. Cento anni fa, nella notte chiamata **la Caduta** (*Vaultfall*), il Caveau si è spezzato: i suoi frammenti piovono ancora sulla terra come **Casse sigillate**, piene di finiture, reliquie e meraviglie. Solo chiavi forgiate a mano possono aprirle.

A **Vaelmora**, la capitale, l'**Ordine dei Custodi** addestra chi raccoglie, forgia, combatte e recupera le Casse prima che finiscano nelle mani del **Collezionista**, una figura mascherata che ne accumula a migliaia per riaprire il Caveau e governare le stelle.

**Colpo di scena (Cap. X):** sotto la maschera c'è il primo dei Custodi, che vuole rimettere insieme il Caveau per impedire che i suoi frammenti rendano il mondo dipendente dalla fortuna. Sconfitto lui, si risveglia il **Custode del Caveau**, il guardiano costruito dagli dèi. Batterlo fa **ricomporre il Caveau più forte di prima**: inizia una nuova **Era** — giustificazione narrativa della scala infinita.

## 2. Tono e regole di scrittura

- Tono: **fantasy leggero con ironia** (Terry Pratchett incontra un gestionale). PNG con una caratteristica memorabile ciascuno. Mai cinico verso il giocatore.
- **R-TX-1:** descrizioni di missione ≤ 2 frasi, dialoghi ≤ 3 battute. Il giocatore idle legge poco: ogni frase deve contenere un'informazione o una battuta.
- **R-TX-2:** ogni testo esiste in **IT e EN** nei dati (`{"it": ..., "en": ...}`), mai stringhe fisse nel codice.
- **R-TX-3:** nomi originali. Vietati nomi di RuneScape/Melvor/Counter-Strike (es. Mithril, Adamant, Rune come metallo, Golbin, StatTrak, nomi di skin CS). Nomi di creature del folklore generico (lupo mannaro, yeti, idra, grifone) sono ammessi.
- **R-TX-4:** lessico del gioco coerente (glossario in docs/99): "Cassa", "Chiave", "Finitura", "Reliquia ★", "Annalista", "Condizione", "Mansione", "Stella", "Era", "Tenuta", "Socio".

## 3. Le 10 regioni

| # | Regione | Livelli | Tema | Elemento ricorrente | Boss | Dungeon (boss) | Cassa |
|---|---|---|---|---|---|---|---|
| 1 | Valle del Mulino | 1–10 | campi, mulini, bracconieri | Natura/Veleno | Regina Vespa | Granaio Maledetto (Mietitore di Paglia) | Cassa della Valle |
| 2 | Costa del Sale | 11–20 | scogliere, pirati | Gelo/Fulmine | Capitano Ghignosale | Relitto della Fortuna (Kraken Giovane) | Cassa della Risacca |
| 3 | Miniere di Ferroradice | 21–30 | gallerie, coboldi, golem | Terra/Fuoco | Golem di Ferroradice | Cuore della Forgia (Elementale di Scoria) | Cassa di Ferroradice |
| 4 | Bosco Sussurrante | 31–40 | fate, ragni, treant | Veleno/Sacro | Madre dei Ragni | Corte delle Fate (Regina dei Rovi) | Cassa dei Sussurri |
| 5 | Paludi di Fiele | 41–50 | morbo, lucertoloidi, strega | Veleno | Strega di Fiele | Tempio Annegato (Idra di Palude) | Cassa di Fiele |
| 6 | Deserto di Cenere | 51–60 | tombe, mummie, djinn | Fuoco/Ombra | Faraone Senza Nome | Tomba Sepolta (Scarabeo Colosso) | Cassa di Cenere |
| 7 | Picchi di Brina | 61–70 | yeti, giganti, spettri | Gelo | Jarl di Ghiaccio | Caverna Cristallina (Wyrm Cristallino) | Cassa di Brina |
| 8 | Archivio Sommerso | 71–80 | biblioteca annegata | Ombra/Fulmine | Bibliotecario Annegato | Sala dei Tomi Proibiti (Libro Vivente) | Cassa dell'Archivio |
| 9 | Cime della Tempesta | 81–90 | grifoni, draghi | Fulmine | Drago della Tempesta | Nido del Tuono (Roc Ancestrale) | Cassa della Tempesta |
| 10 | Caveau Celeste | 91–100 | costrutti stellari | Sacro/Ombra | Il Collezionista | Atrio del Caveau (Portinaio Celeste) | Cassa Celeste |

Incursioni: **Covo del Collezionista** (55, Paludi), **Cittadella di Brina** (75, Picchi), **Cuore del Caveau** (105, Caveau). Boss mondiali: Colosso Errante (40), Leviatano delle Sabbie (65), Titano Stellare (95). Infinito: **La Breccia**.

## 4. Regole per i mostri (per crearne di nuovi)

- **R-MO-1:** ogni regione ha **4 normali** (livelli zona+1, +3, +5, +7), **1 élite** (+8), **1 boss** (+10, già oltre la zona). Il dungeon ha un boss a +12.
- **R-MO-2:** almeno un mostro per stile (Mischia, Distanza, Arcano) in ogni regione; il boss usa lo stile che "punisce" la classe più comoda della regione precedente.
- **R-MO-3:** ogni mostro ha 1 debolezza e al massimo 1 resistenza; l'elemento ricorrente della regione è resistito da ≥2 mostri.
- **R-MO-4:** le statistiche si generano **solo** dalle formule (docs/05 §4). Le eccezioni si fanno con il moltiplicatore di tipo o con le meccaniche, mai con numeri a mano.
  Eccezioni dichiarate (FIX-COMBATTIMENTO, nel generatore come tabelle con motivo): `RAID_BOSS_DMG_MULT` (Custode del Caveau ×0,5,
  livello 100 invece di 105: il passaggio all'Era II deve essere battibile da ogni build a Eroe 100) e `DUNGEON_BOSS_DMG_MULT`
  (Roc Ancestrale ×0,85: Nido del Tuono più duro dell'Atrio successivo). Le fasi dei boss d'incursione usano i **tre stili**, uno
  per fase (ogni classe è in svantaggio in una fase sola).
- **R-MO-6 (FIX-COMBATTIMENTO, QA4 #5):** XP ridotta sui mostri molto sotto l'Eroe: oltre 3 livelli di distacco −6% per livello
  (minimo 25%; mostri dal livello 91 esclusi: ultima zona e farm delle Ere). Con vita ×1,0575 e XP ×1,0225 per livello i mostri bassi
  rendevano sempre di più all'ora e per ~9 livelli conveniva restare nella zona vecchia; ora la zona nuova rende di più da sblocco+2/+3
  (0,96-1,11× a +2/+3, 1,1-1,2× a +4; `q4_sweep.gd mode=stay`). Formula `core.overlevel_xp_mult` = `Formulas.overlevel_xp_mult`.
- **R-MO-5:** drop: normali → materiale comune 30%, grezzo a tema 15%, materiale raro 2%, cassa 1/150, tavola rara 1/512; élite → comune 80%, raro 10%, pezzo di equipaggiamento del tier 3%, cassa 1/40, tavola rara 1/128; boss → comune 100%, raro 40%, unici 1/64 cad., famiglio 1/1500, cassa 1/4, tavola rara 1/32.

## 5. Vaelmora (hub, menù "Città")

Luoghi del menù Città: **Emporio** (negozio), **Mercato** (borsa dinamica), **Bacheca delle Commesse**, **Bacheca delle Taglie**, **Sala dei Caveau** (casse, contratti, Affinatura, Banco dei Caveau), **Taverna** (mercenari; richiede la Tenuta), **Collegio Arcano**, **Gilde/Fazioni**, **Sala dei Trofei**, **Osservatorio** (Costellazioni).

## 6. PNG principali

| ID | Nome | Ruolo |
|---|---|---|
| `ilde` | Maestra Ilde | capo dei Custodi, storia principale, Guerriero |
| `bertoldo` | Bertoldo il Mercante | economia, Tenuta, Lega dei Mercanti |
| `gunilde` | Gunilde la Fabbra | Forgiatura, Forgiachiavi |
| `sefora` | Archivista Sefora | Collegio Arcano, Arcanista, lore del Caveau |
| `dario` | Capo-Ramingo Dario | Compagnia dei Ramingi, Ramingo, Taglie |
| `magpie` | La Gazza | Mano Grigia: Borseggio, Casse, Contratti, Affinatura |
| `ottavio` | Cuoco Ottavio | Cucina |
| `mirta` | Erborista Mirta | Erboristeria, Alchimia |
| `berta` | Nonna Berta | Coltivazione |
| `livia` | Cartografa Livia | Spedizioni, Incursioni, Luoghi Segreti |
| `aurelio` | Reggente Aurelio | governo di Vaelmora (eventi) |
| `collector` | Il Collezionista | antagonista |

Ogni PNG ha un ritratto 64×64 (manifest) e 3–5 battute di "chiacchiera" casuale nel menù Città (da scrivere in fase M6, docs/22).

## 7. Fazioni e reputazione

5 fazioni (`data/factions.json`): Lega dei Mercanti, Ordine dei Custodi, Collegio Arcano, Compagnia dei Ramingi, Mano Grigia. Gradi: Neutrale 0 · Amico 1.000 · Onorato 5.000 · Riverito 15.000 · Esaltato 40.000. Ogni grado dà un bonus permanente; Esaltato dà un titolo. Fonti di reputazione: Commesse (10 + 5×tier), incarichi di fazione, eventi.
