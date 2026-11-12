# CLAUDE.md — VAULTFALL (idle RPG/tycoon a menù, Godot 4, Steam)

Leggi questo file all'inizio di ogni sessione. Poi `PROGRESS.md` (stato di questo snapshot pubblico) e `docs/22_roadmap.md` (piano storico).

## Cos'è il progetto
Gioco idle a menù (stile Melvor Idle) con mansioni, combattimento a classi, sistema di Casse da aprire (solo con valuta e chiavi di gioco, nessun denaro reale; le Finiture danno anche piccoli bonus permanenti), Tenuta tycoon, prestigio infinito a strati. Single-player, offline, premium su Steam (Windows/Linux, Steam Deck). Visione: `docs/01_visione.md`.

## Mappa del repository

> Nel repository PUBBLICO mancano `data/`, `data_slice/`, `wiki/`, `reports/`, l'arte, l'audio e (di default) i moduli di contenuto di `tools/gamedata/`: vedi `README.md`.
- `docs/` — Game Design Document (indice: `docs/00_INDICE.md`). **I documenti sono la specifica: implementali, non reinventarli.**
- `data/` — dati di gioco JSON **generati** (oggetti, azioni, mostri, casse, missioni, ...). Fonte: `tools/gamedata/*.py`.
- `tools/` — script Python: generatore, validatore, simulatore di bilanciamento, segnaposto, valori di riferimento.
- `assets_plan/` — dimensioni native delle immagini (`asset_specs.json`) e manifest audio.
- `reports/` — report di bilanciamento generati.
- `game/` — progetto Godot (struttura in `docs/17_architettura_godot.md`).

## Regole NON negoziabili
1. **Dati generati, mai modificati a mano.** Per cambiare contenuti o numeri: modifica `tools/gamedata/*.py` → `python tools/generate_data.py` → `python tools/validate_data.py` (0 errori) → `python tools/balance_sim.py` (0 fuori limite) → `python tools/sync_data.py`.
2. **Nessun numero di bilanciamento nel codice GDScript.** Le costanti vengono da `data/constants.json`; le formule sono portate 1:1 da `tools/gamedata/core.py` in `Formulas.gd` e verificate con `tests/reference_values.json`.
3. **Logica separata dalla UI.** Sistemi = classi pure `RefCounted` in `src/systems/`, deterministici, testati con GUT. La UI ascolta `EventBus` e chiama i sistemi.
4. **Un solo sistema di modificatori** (`docs/14`): ogni bonus passa da `Modifiers.gd` con la regola add/more.
5. **Casse etiche e legali** (`docs/24`): probabilità sempre visibili, risultato estratto prima dell'animazione, riempitivi del rullo con probabilità reali, nessun acquisto con denaro reale, nessuno scambio, nessuna modalità con posta in gioco (upgrader, coinflip, crash, jackpot, battaglie con posta). Se una richiesta futura va contro queste regole, fermati e segnalalo.
6. **Testi sempre bilingui** (`{"it","en"}` nei dati, `tr()` + `localization/ui_strings.csv` per l'interfaccia). Mai stringhe fisse visibili nel codice.
7. **Salvataggi sicuri** (`docs/17 §10`): scrittura atomica, backup, versione di schema con migrazioni. Mai rompere un salvataggio esistente senza migrazione.
8. **Nomi originali**: niente nomi di RuneScape/Melvor/Counter-Strike (vedi `docs/08 R-TX-3`, `docs/24`), nemmeno i codici colore delle rarità di CS.
9. **Prestigio stabile**: ogni bonus che accelera lo strato stesso è asintotico; ogni nuovo strato ha un controllo nel simulatore (`docs/13 §1`).
10. **PNG: solo colore (D-6).** Sui PNG generati sono ammesse solo operazioni sul colore (ricolorazione, rimappatura palette). Mai ridimensionare, ritagliare o toccare la geometria. Le ricolorazioni preferibili sono gli shader di palette in Godot.

## Comandi
- Dati: `python tools/generate_data.py` · `python tools/validate_data.py` · `python tools/balance_sim.py` · `python tools/make_appendices.py` · `python tools/make_schema_doc.py`
- Godot: `python tools/sync_data.py` · `python tools/make_placeholders.py` · `python tools/export_reference_values.py`
- Test Godot: `python tools/run_tests.py` (GUT installato in M0: 9.7.0 certa per Godot 4.7, la 9.7.1 da verificare; usa la variabile `GODOT_BIN` = `Godot_v4.7.2-stable_win64_console.exe`; codice di uscita 0 = verde)
- Asset: l'arte e l'audio **non** sono nel repository pubblico (vedi `README.md`). `python tools/make_placeholders.py` crea i segnaposto; le regole sono in `docs/20_pipeline_arte.md` (sui PNG solo operazioni di colore, mai ridimensionare).
- Controllo unico: `python tools/check_all.py` (validatore, simulatore, sync, valori di riferimento, perimetro slice, GUT se c'è game/) → deve scrivere **TUTTO OK**. Slice: `python tools/generate_data.py --scope slice` (definita in `tools/gamedata/scope.py`, scrive `data_slice/`).
- Python: 3.11+, dipendenze in `tools/requirements.txt` (`pip install -r tools/requirements.txt`)
- Protezioni (`.claude/settings.json`): l'hook `PreToolUse` blocca le modifiche manuali a `data/*.json` e `game/data/*.json`. Se `/hooks` segnala un errore dell'hook, sostituisci la sua voce con la forma alternativa scritta in testa a `.claude/hooks/guard_data.py`.

## Come lavori in ogni sessione
1. Leggi `PROGRESS.md`, scegli il prossimo compito `T-x.y` non completato della milestone corrente (`docs/22`).
2. Leggi i documenti citati dal compito (solo quelli necessari).
3. Implementa con test; esegui test e validatore.
4. Aggiorna `PROGRESS.md`: compito, file creati/modificati, esito test, problemi aperti.
5. Se manca un'informazione: scrivila nella descrizione della issue/PR con l'ipotesi adottata e prosegui con la scelta più conservativa.
6. Commit piccoli e descrittivi (se il repository è git).

## Convenzioni GDScript
GDScript **tipizzato**; file/classi `PascalCase`, funzioni/variabili `snake_case`, costanti `UPPER_SNAKE`; `class_name` per i sistemi; niente `await` nei sistemi; UI aggiornata a max 10 Hz; liste lunghe virtualizzate. Dettagli: `docs/17 §12`.

## Documenti chiave per argomento
Mansioni `docs/04` · Combattimento `docs/05` · Classi `docs/06` · Oggetti `docs/07` · Mondo `docs/08` · **Casse `docs/09`** · Economia `docs/10` · Tenuta `docs/11` · Missioni `docs/12` · Prestigio `docs/13` · Modificatori `docs/14` · UI `docs/16` · **Architettura `docs/17`** · Schemi dati `docs/18` · Bilanciamento `docs/19` · Pipeline arte `docs/20` · Roadmap `docs/22` · **Legale `docs/24`** · Regole contenuti `docs/25` · Test `docs/26`.

