# 16 — Interfaccia (UI/UX): schermate, navigazione, accessibilità

> Un gioco a menù vive o muore per la sua interfaccia. Regola principale: **ogni informazione necessaria alla decisione in corso
> è visibile; il resto è a un clic, e nessun requisito è un vicolo cieco.** Ogni fatto ha un solo posto (`docs/ui_redesign/06 §2.4`).
>
> *Aggiornato il 28/10/2026 (fase F18, chiusura del progetto di interfaccia `docs/ui_redesign/06_PROGETTO_INTERFACCE.md`): layout e wireframe*
> *descrivono lo stato reale dopo le fasi F1–F17; i numeri misurati prima/dopo sono in `docs/ui_redesign/08_RISULTATI.md`.*

## 1. Principi

1. **Chiarezza prima dell'estetica:** testo leggibile a 1280×800 (Steam Deck), contrasto alto, numeri allineati; tre corpi
   (22/16/14) e un solo pulsante primario per vista.
2. **Nessun vicolo cieco:** ogni requisito mancante è cliccabile e porta a dove si ottiene (es. "Serve: 20 Lingotti di Ferro" → apre Forgiatura filtrata).
3. **Feedback immediato:** ogni azione mostra un numero che sale (XP, oggetti) con animazioni brevi (≤ 300 ms), disattivabili.
4. **Densità controllata:** la cornice fissa (barra alta, menù, binario) ha un budget (≤ 45 elementi, ≤ 26% dell'area);
   liste lunghe virtualizzate e a righe compatte; filtri e ricerca ovunque ci siano > 20 elementi; spiegazioni alla prima visita
   e poi dietro «?».
5. **Tutto con il mouse**, scorciatoie da tastiera, navigazione completa con controller (Steam Deck).
6. **Segnali azionabili:** numero ambra = azione possibile ora (≤ 5 contemporanei, tetto 9+); puntino = novità; rosso = solo
   pericolo in corso.
7. **Compare quando serve:** nessun riquadro vuoto («Niente di piantato», «Non collegato»); funzioni e valute compaiono dal loro
   sblocco.
8. **Due livelli di navigazione:** menù a gruppi → schede interne; mai sotto-schede di sotto-schede.
9. **Misurare:** la densità si controlla con `game/tests/test_ui_budget.gd` (soglie in testa al file, `reports/ui_budget.json`).

## 2. Layout principale (area logica minima 1280×720, scala automatica fino a 1536×864)

Il layout è progettato per l'**area logica minima 1280×720** (Steam Deck 1280×800). Lo stretch resta `canvas_items` + `expand`;
una **scala automatica** porta l'area logica a **1536×864** quando lo schermo lo permette (1600×900 e oltre: a 1920×1080 la
scala fisica è 1,25, a 2560×1440 è 1,67) senza mai scendere sotto la scala fisica 1,0. «Dimensione interfaccia» (80–125%) è
relativa all'automatica; l'area logica non scende mai sotto 1024×576. Tre bande di larghezza logica: stretta < 1100 (cassetto
non fissabile, menù stretto, barra compatta sotto 1000), normale 1100–1439, larga ≥ 1440 (cassetto fissabile come colonna).
Formula e costanti: `docs/ui_redesign/06 §3.17` e `game/src/ui/main/UiBands.gd`.
*(Stato reale dopo F5: la scala automatica è attiva — 1920×1080 → area logica 1536×864, 1280×720 → 1280×720 — e le tre bande sono
usate da barra, menù, cassetto e dalle schermate con colonne.)*

Wireframe a 1280×720 (stato reale; quello a 1536×864 è in `docs/ui_redesign/06 §3.1`):

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ VAULTFALL  ● 2.973  ✦ 134  ▣ 150 liberi │ ▶ Taglialegna · Pino ▰▰▰▰▰▰▱▱▱ Liv 33 · 4 min                       │ ⏸  ✓  ⚙  ? │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
┌───────────────────┐┌───────────────────────────────────────────────────────────────────────────────────────────────────┐┌────┐
│Riepilogo          ││◎ Piove Roba dal Cielo · Raccogli Tronco di Pino ▰▰▰▰▱▱▱▱ 12/25                             [Vai]  ││ ☰  │
│Missioni          2│├───────────────────────────────────────────────────────────────────────────────────────────────────┤│ •  │
│▾ MANSIONI         ││[ico] TAGLIALEGNA  Liv 33  ▰▰▰▰▰▰▰▱▱ 735/1.095 XP · Ascia di Ferro      [Talenti •] [Coda ▾]  ?    ││    │
│▶Taglialegna       ││● In corso: Pino ▰▰▰▰▰▱▱▱▱ 2,1 s                                                   [Ferma]         ││ ☺  │
│ ▁▁▁▁▁▁▁▁▁         │├───────────────────────────────────────────────────────────────────────────────────────────────────┤│    │
│  Miniera          ││[Tutte ▾] [Cerca…                ]  ☑ Solo ciò che posso fare          Ordina: [Fattibili ▾]       ││    │
│  Pesca           •││Pino      Liv 1   3,0 s · 7 XP    ~1.206/h  Maestria 50★ ▰▰▰▰                      [■ Ferma]       ││    │
│  Forgiatura       ││Betulla   Liv 10  3,3 s · 9 XP    ~1.113/h  Maestria 31  ▰▰▱▱                      [ Avvia ]       ││    │
│  Cucina          3││Castagno  Liv 20  3,5 s · 12 XP   ~1.034/h  Maestria 12  ▰▱▱▱                      [ Avvia ]       ││    │
│  Tutte (17) ▸     ││Cedro     Liv 30  3,8 s · 16 XP     ~947/h  Maestria 3   ▱▱▱▱                      [ Avvia ]       ││    │
│▾ AVVENTURA        ││▸ Bloccate (4) — la prossima: Ebano al Liv 40                                                      ││    │
│  Combattimento    ││                                                                                                   ││    │
│  Eroe             ││                                                                                                   ││    │
│  Talenti         •││                                                                                                   ││    │
│  Dungeon          ││                                                                                                   ││ ⌛ │
│▸ CITTÀ         4  ││                                                                                                   ││7:42│
│▸ CAVEAU        2  ││                                                                                                   ││    │
│▸ PROGRESSO        ││                                                                                                   ││    │
└───────────────────┘└───────────────────────────────────────────────────────────────────────────────────────────────────┘└────┘
```

- Barra superiore: marchio, Oro (clic: valute), Polvere Stellare (dal Prestigio; clic: Costellazioni), Deposito con gli spazi
  liberi (ambra da `warn_pct`, rosso a pieno), attività in corso (un solo controllo), icone Pausa/Salva/Impostazioni/Aiuto.
- Striscia Obiettivo (una riga) sotto la barra, tranne in Riepilogo e Missioni.
- Menù laterale a gruppi richiudibili (Mansioni con «Recenti» e «Tutte», Avventura, Città, Caveau, Progresso); voce in corso
  evidenziata (doc ui_redesign/05); voci bloccate in grigio con lucchetto e clic verso la missione che le sblocca; segnali secondo §1.6.
- Binario destro (52 px): Registro, Amici (se il coop è stato usato), Sabbia del Custode. Il cassetto si apre sopra il
  contenuto (tasto L) e nella banda larga si può fissare come colonna.
- **Robustezza alla finestra** (invariata nella sostanza; QA overflow, `docs/audit_2026-10-22/107_RESOCONTO_OVERFLOW.md`): ogni
  schermata sta nello scorrimento `ScreenScroll`, mai oltre la finestra; `WindowFit` (minimo 960×540, adattata allo schermo
  all'avvio); dialoghi dentro l'area; nessuna larghezza minima fissa oltre ~600 px (`HFlowContainer`/`clip_text`); lanciare
  `layout_audit.gd`, `test_layout_resolutions.gd` e `test_ui_budget.gd`.
- **Struttura del codice (F0):** `MainScreen.gd` orchestra; barra alta in `TopBar.gd`, menù in `SidebarMenu.gd`, colonna destra in
  `RightRail.gd`, costanti e bande in `UiBands.gd` (tutti in `game/src/ui/main/`).

## 3. Schermate chiave (wireframe definitivi, stato dopo F18)

> Questi schemi descrivono ciò che il gioco mostra **davvero** dopo le fasi F1–F17 (sostituiscono i wireframe di progetto di F0).
> Le specifiche di dettaglio e le decisioni sono in `docs/ui_redesign/06 §3.6–3.15`; i numeri misurati prima/dopo in
> `docs/ui_redesign/08_RISULTATI.md`; la storia fase per fase nei resoconti `08`–`26`.
> Regola comune: ogni schermata ha **una frase «a cosa serve»** aperta alla prima visita e poi dietro il «?» accanto al titolo
> (`Settings.seen_intro`, D17); le spiegazioni lunghe stanno in `Disclosure` chiuse; ogni fatto compare in un solo posto (D18).

### 3.0 Riepilogo (cruscotto, F6)

```
RIEPILOGO ?                                          Livello totale 412 · Giocato 61 h · Deposito 87/226 · ✦ 134
┌ Adesso ───────────────────────────┐ ┌ Prossimo passo ───────────────────────┐ ┌ Da fare ────────────────────────┐
│ ▶ Taglialegna · Pino ▰▰▰▱ 2,1 s   │ │ Capitolo 7: uccidi 40 Scorpioni       │ │ ▪ 2 talenti da scegliere   [Vai] │
│ Liv. 34 tra 18 min                │ │ ▰▰▰▰▰▱▱▱ 23/40               [Vai]    │ │ ▪ Dispensa vuota           [Vai] │
└───────────────────────────────────┘ └───────────────────────────────────────┘ └─────────────────────────────────┘
▸ Titolo e profilo        ▾ Prossimi traguardi (3)        [Bonus attivi (12)]
Città: «battuta del PNG a una riga»  ·  Gazzetta a scorrimento
```
«Da fare» legge gli stessi segnali del menù (`SidebarBadges.signals()`): stesso elenco, stessi numeri. In banda larga (≥ 1440) le tre carte
stanno su una riga.

### 3.1 Mansione di raccolta e di produzione (F7)

```
TAGLIALEGNA ?  Liv 33 ▰▰▰▰▰▰▰▱▱ 735/1.095 XP · Ascia di Ferro                  [Talenti •] [Coda ▾]
● In corso: Pino ▰▰▰▰▰▱▱▱▱ 2,1 s                                                              [Ferma]
[Tutte ▾] [Cerca…            ] ☑ Solo ciò che posso fare                      Ordina: [Fattibili ▾]
 Pino     Liv 1   3,0 s · 7 XP    ~1.206/h  Maestria 50★ ▰▰▰▰                        [■ Ferma]
 Betulla  Liv 10  3,3 s · 9 XP    ~1.113/h  Maestria 31  ▰▰▱▱                        [ Avvia ]
 ...                                                  (righe da 56 px, virtualizzate)
▸ Bloccate (4) — la prossima: Ebano al Liv 40
```
Una riga per ricetta (non più una carta da ~118 px): nome, tempo/XP, resa all'ora, Maestria, un solo pulsante. Le ricette di produzione
mostrano gli ingredienti mancanti come riga cliccabile (nessun vicolo cieco). Pagine di scorrimento mediane: 7,6 → 1,1 (max 4,8 a 60 h).
Coltivazione ha lo stesso telaio con le parcelle.

### 3.2 Combattimento (F8)

```
COMBATTIMENTO ?  [Zona ▾ Valle]  [Smetti di combattere]  [Dungeon…]   ✓ Sicuro in idle
┌ Nemici ───────────┐ ┌ Arena ──────────────────────────────────────┐ ┌ Eroe ─────────────────────────┐
│ Ratto della Peste │ │ Nome zona · meccaniche                       │ │ Vita ▰▰▰▰▰▱ 1.840/2.210 ▏soglia│
│ ▸ Sciamano (élite)│ │ [ritratto nemico]  numeri di danno           │ │ Risorsa · Colpo / max / DPS    │
│ Strega (boss) 🔒  │ │ Vita ▰▰▱▱ 412/1.034 · avvisi del boss        │ │ Effetti · ferite · uccisioni   │
└───────────────────┘ └─────────────────────────────────────────────┘ └────────────────────────────────┘
Cibo  [slot][slot][slot]  soglia ▏ [Mangia ora] ⓘ          Tecniche  1 Fendente PRONTA · 2 Grido 16 · … ▸
▾ La Corsa   ▸ Bottino recente   ▸ Registro di battaglia           (fisarmonica: una sola sezione aperta)
```
Un solo chip di rischio nella testata (verde/ambra/rosso, `UiKit.RISK_*`); le regole del Cibo stanno dietro «ⓘ». Colpo/max/DPS sono
misurati dal registro, nessuna formula nuova.

### 3.3 Sala dei Caveau, Album, Guardaroba (F11)

```
SALA DEI CAVEAU ?   [Casse] [Contratti] [Affinatura] [Banco] [Sfida 🔒→Vai]
┌ Le tue casse (righe da 32 px) ─┐ ┌ Cassa di Fiele   Casse: 14 · Chiave: 3 ─────────────────────────┐
│ Cassa della Valle   pronta ×31 │ │ PROBABILITÀ  ◆ 79,2% · ◆◆ 15,8% · ✦ 3,8% · ✦✦ 0,9% · ★ 0,3%     │
│ Cassa di Fiele      pronta ×14 │ │ Senza ★ da 143 aperture (pity da 200)                           │
│ Cassa del Raccogl.  manca chiave│ │ [APRI] [APRI ×5] [APRI ×10]  ☐ Apertura rapida                  │
└────────────────────────────────┘ │ (se manca la chiave: un solo motivo + un solo «Vai»)             │
                                   │ ▸ Contenuto completo                                            │
```
Le probabilità sono **sempre visibili senza clic** (regola 5, `docs/24`): mai dietro una `Disclosure`. Album (voce di menù propria):
totali in testata, sezioni «In corso» (aperta), «Finite» e «Non iniziate» (chiuse); patina e Analisti nel tooltip del pezzo.
Guardaroba (voce propria): schede Indossati · Bonus attivi · Reliquiari, slot per gruppo su 4 colonne.

### 3.4 Tenuta, Dungeon, Taglie (F9)

```
TENUTA ?   ⚠ Dispensa vuota · [Rifornisci]                coloni 41/44 · produzione · Magazzino ▰▰▰▱ [Raccogli tutto]
[Edifici] [Dispensa !] [Rifondazione •] [Merci in vendita]
┌ [64px] Segheria  Liv 12 ┐ ┌ ... ┐ ┌ ... ┐       1 colonna in banda stretta, 2 normale, 3 larga
│ 38 unità/h · ▰▰▰▱ 23/25 │
│ [▲ 1.200 oro ▾ +1/+10/Max]  Mancano: Asse di Pino ×5 (riga cliccabile)
```
Dungeon: elenco a sinistra (una riga = un pulsante), dettaglio a destra con un chip di rischio, premi sempre visibili, Boss/Stanze/Record
in `Disclosure` chiuse. Taglie: l'istruzione «Scegli un incarico… Accetta» compare una sola volta.

### 3.5 Eroe, Talenti, Prestigio (F10)

```
EROE ?  Liv 96 · Guerriero / Berserker        Vita 2.210 · Precisione 812 · Armatura 340   (tooltip di calcolo)
[Equipaggiamento] [Abilità] [Statistiche] [Cibo e pozioni] [Glifi]          (una pagina alla volta)
```
Talenti: rango «n/N» dentro il nodo, **un solo riquadro di dettaglio** (nodo sotto il puntatore o col fuoco), ramo non attivo ridotto a
icone. Prestigio: schede Consigliere · Grande Obiettivo · strati (Stelle, Costellazioni, Ere, Prove) · Rifondazione (solo se disponibile).

### 3.6 Deposito (F12, F15–F17)

```
DEPOSITO ?   Spazio ▰▰▰▱▱ 87/226  [Espandi Deposito · 1.200]  Valore 48.210  [?]
[Risultati (n)] [Tutto 87] [Armeria 12/300] [Armi ⚔ 9] [Scorte ▣ 14] [+] [Schede ▾]       ← schede (fino a 12, gratis)
[Tutte le categorie] [Risorse] [Cibo] [Attrezzi] ...                                       ← filtri per categoria
[Cerca…  (cat: t: lock: q: rar:)] Ordina [Nome ▾] [Filtri ▾ (1)] [Vendita ▾] [Selezione] [Modalità vendita] [Griglia|Lista] [Compatta]
┌ griglia virtualizzata di caselle 84×96 (icona 64 px 1:1, quantità su fondo opaco, lucchetto, «E», tier/grado) ┐ ┌ Dettaglio ┐
│ [ico][ico][ico][ico][ico][ico][ico][ico][ico][ico]                                                           │ │ (solo con  │
│ ...                                                                                                         │ │ una scelta)│
```
Regola di spazio (F15): conta lo Spazio (pile e Finiture), l'**Armeria** (equipaggiamento) ha un limite proprio; l'eccedenza va nel Carro di
Ritiro. Modalità Selezione (S) e Vendita (V): barra con conteggio e azioni (Sposta in…, Blocca, Vendi con anteprima e guardia sul primo
Invio); protetti (bloccati, indossati, in uso) mai venduti. Salvataggio schema 5 (schede).

### 3.7 Barra superiore, menù, binario e cassetto (F2–F5, F14)

Vedi §2. La Sabbia del Custode (F13–F14) ha il pulsante nel binario (tasto T), il Clic assistito nelle Impostazioni e la riserva visibile
nel tooltip; non esiste alcuna azione che richieda clic rapidi ripetuti.

### 3.8 Bentornato (finestra modale)

```
BENTORNATO! Sei stato via 9 h 41 min (limite 12 h).
Azione: Pesca — Celacanto   +2.311 azioni · +98.420 XP (Lv 71 → 73) · +2.874 Celacanto Crudo
Parallelo: Tenuta +31.200 unità · Orto: 4 raccolti pronti · Spedizioni: 2 completate (1 Cassa di Brina!)
Trovati: ◆ Cassa del Raccoglitore ×14 · Famiglio: Lontra Pescatrice ★
[ RACCOGLI TUTTO ]  [ VAI ALLE CASSE ]
```

### 3.9 Manuale (codex in gioco)

Voce di menu sempre disponibile (tasto `F1`). Ogni pagina è **generata dai dati** (`constants.json`, tabelle), quindi non va mai fuori sincronia:
- **Formule**: XP per livello, colpo, riduzione del danno, triangolo, cibo, maestria, Eco, Stelle, Ere, Soci (con l'esempio sui valori attuali del giocatore: "il tuo colpo contro questo mostro: 86%");
- **Probabilità**: ogni Cassa (rarità, oggetto, Annalista, condizioni, pity), contratti, drop dei mostri, famigli;
- **Glossario** IT/EN e "Come si sblocca" per ogni sistema ancora bloccato.
**Struttura attuale (audit 74):** indice per gruppi con **ricerca** (titolo e contenuto) e una pagina per OGNI sistema (mansioni e maestria, coda, Coltivazione, Alchimia, Apprendisti, combattimento, classi, Taglie, Incursioni, Boss mondiali, Breccia, Deposito, Casse, Bottega dei Caveau, Album, Mercato/Emporio, Commesse, Fazioni, Tenuta, Gilda, Mercenari, Spedizioni, Luoghi Segreti, Prestigio, Costellazioni, Rifondazione, Ere e Prove, Compendio, Eventi, Modalità, Impostazioni, Segnala un problema, Amici/Coop; dalla fase F14 anche la pagina «Sabbia del Custode»). Ogni pagina: a cosa serve (2 righe), come si usa passo-passo, **«I numeri» generati dai dati**, consigli, da non fare, una battuta in fondo (tono di `26_BIBBIA_COMICA.md`). L'icona **«?»** nella barra in alto (e `F1`) apre la pagina della schermata corrente (`ManualCatalog.SCREEN_PAGES`). Dettagli per chi aggiunge pagine: `game/README_SISTEMI.md` §10.
Motivo: i giocatori del genere amano capire i numeri (wiki di Melvor, Codex di Melvor Idle 2, docs/02) e la trasparenza è anche un requisito legale delle casse (docs/24 R-LEG-4).

## 4. Componenti riutilizzabili (scene Godot in `ui/components/`)

`ItemSlot` (icona, quantità, cornice di rarità con simbolo, blocco, tooltip) · `ItemTooltip` (nome, categoria, statistiche, confronto con equipaggiato, fonti, usi) · `ProgressBarLabeled` · `ActionCard` · `RecipeRow` · `CurrencyLabel` (formattazione numeri) · `ResourceCostRow` (verde/rosso) · `ModalDialog` · `Toast` · `TabBar` · `VirtualList` (lista virtualizzata) · `CrateReel` · `StatRow` (con spiegazione) · `TimerLabel`.

## 5. Formattazione dei numeri

- Sotto 100.000: separatore delle migliaia della lingua (IT `12.450`, EN `12,450`).
- Da 100.000: abbreviazioni `K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc` con 3 cifre significative (`1,25 M` / `1.25M`); oltre `Dc` notazione scientifica `1,25e36`.
- Opzione nelle Impostazioni: Abbreviata (default) / Completa / Scientifica.
- Tempi: `3,2 s`, `18 min`, `4 h 12 min`, `3 g 2 h`.
- Percentuali: 1 decimale sotto il 10% (`0,3%`), interi sopra.

## 6. Tema grafico

- Interfaccia scura con accenti oro/ottone (tema "caveau"), pannelli con cornice pixel art 9-slice (generata con uno strumento di IA per la pixel art, docs/20) o `StyleBoxFlat` di Godot come ripiego.
- Colori di rarità (palette propria: **non** usare i codici dei colori di CS:GO/CS2): Rara `#8DA2B8`, Epica `#6F7BE6`, Leggendaria `#C65AA8`, Mitica `#E8702A`, ★ `#F5CF4F` (con riflesso animato); sempre accompagnati da simbolo e nome (daltonismo); qualità: Normale bianco, Fine verde `#5EBD5E`, Eccellente turchese `#3FC1B0`, Capolavoro rame `#D86F45`.
- Font: **Departure Mono** per numeri e titoli (22 px; cifre a larghezza fissa), **Atkinson Hyperlegible Next** per il testo (16 px di base, minimo 14), licenze OFL (docs/20 §9). Requisito Steam Deck: testo ≥ 9 px reali a 1280×800, obiettivo 12 px → con la base 16 px siamo sopra.

## 7. Accessibilità (obbligatoria)

- Scala del testo 80–150%; «Dimensione interfaccia» 80–125%, relativa alla scala automatica (F5).
- «Clic assistito» per la Sabbia del Custode (tieni premuto, interruttore, automatico, F14) e regola: **nessuna azione richiede clic rapidi ripetuti**.
- Rarità e qualità sempre con **simbolo + colore**; modalità daltonismo (palette alternative per deuteranopia/protanopia/tritanopia).
- "Riduci animazioni" (rullo istantaneo, niente lampi).
- Tutte le notifiche disattivabili per categoria; volume separato per musica, effetti, interfaccia, rullo.
- Navigazione completa con tastiera e controller; focus sempre visibile.

## 7 bis. Tutorial guidato (2026-10-23)

Strato `TutorialDirector` (CanvasLayer) sopra l'interfaccia: oscura leggermente lo schermo, lascia un buco sul controllo giusto con
cornice dorata che pulsa e una freccia (ferme con «Riduci animazioni»), e mostra una scheda breve (titolo, 2-4 righe, «Avanti» /
«Più tardi» / «Salta il tutorial»). Un passo alla volta, mai con una finestra aperta né durante combattimenti rischiosi. Solo nei due
passi «premi proprio questo» (Pino, Rame) il resto dello schermo non risponde; «Salta questo passo» sblocca sempre. I controlli si
trovano per chiave stabile (`TutorialTargets.mark`, gruppo `tut:<chiave>`), mai per testo tradotto; se mancano il passo si salta.
Percorso: benvenuto → barra laterale → Taglialegna → «Avvia» su Pino → Missioni → Miniera → «Avvia» su Rame → come muoversi → Livello e
Maestria; poi una scheda al primo sblocco reale di ogni sistema. La voce **Guida** (menù Progresso) è la checklist «Dinamiche
scoperte x su N» con «Mostrami» per ogni voce sbloccata e «Riparti dal primo passo»; si apre anche da Impostazioni. Il tutorial si
spegne da solo a catalogo completo.

## 8. Input

- Mouse: clic sinistro azione, destro menù contestuale (equipaggia, blocca, vendi, fondi, confronta), rotellina per liste e quantità.
- Tastiera: `1–9` voci della barra laterale, `Spazio` salta il rullo, `Ctrl+F` cerca, `Esc` chiude, `Q` coda azioni, `B` Deposito, `C` Eroe; nuovi: `P` pausa, `T` Sabbia del Custode, `Maiusc+L`/`Maiusc+M` nel Deposito (fasi F2, F14, F17).
- Controller (Steam Deck): D-pad/levetta per il focus, A conferma, B indietro, LB/RB schede, Y menù contestuale, X Sabbia del Custode (F14), Start Impostazioni. Steam Input con configurazione predefinita "Gamepad".
- **Steam Deck:** risoluzione nativa 1280×800 (16:10), interfaccia testata a quella risoluzione, tastiera virtuale per i campi di testo (ricerca, Targhetta).
