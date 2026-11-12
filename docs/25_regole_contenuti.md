# 25 — Regolamento per creare nuovi contenuti (guida continuativa)

> Questo documento è la **guida da seguire per sempre**: ogni nuova mansione, oggetto, mostro, zona, cassa, missione, impresa o sistema deve rispettarla. Le checklist sono pensate per essere eseguite da Claude Code.

## 0. Regole generali

1. **Generatore, non mano.** Ogni contenuto nasce in `tools/gamedata/*.py` (vocabolario + formule). I JSON si rigenerano. Eccezione ammessa: testi narrativi (vanno comunque nei moduli Python).
2. **Formule, non numeri.** Statistiche, valori, XP, probabilità derivano dalle formule (docs/19). Un numero "a mano" richiede un commento con la motivazione.
3. **Bilingue sempre.** Ogni testo visibile: `{"it", "en"}`. Nomi originali (docs/08 R-TX-3).
4. **Ogni cosa ha una fonte e un uso.** Il validatore rifiuta oggetti senza fonte; avvisa per materiali senza uso.
5. **Ogni cosa ha un'icona** nel manifest (docs/20) e un segnaposto finché l'arte non c'è.
6. **Verifica.** Dopo ogni aggiunta: `generate → validate (0 errori) → balance_sim (0 fuori limite) → appendici`.

## 1. Nuova mansione

- [ ] Ruolo chiaro nel grafo dell'economia: **cosa consuma** e **chi consuma ciò che produce** (almeno 2 consumatori).
- [ ] 11 tier di azioni ai livelli 1/10/…/90/95 (le mansioni con due linee, come Erboristeria, possono sfalsarle di 3–5 livelli).
- [ ] XP/ora del tier = `xph(t)` (±5%); durate coerenti con il gruppo (docs/04 §3).
- [ ] Drop secondario a tema (0,4–2%), cassa di gruppo (`durata/2400`), famiglio (`durata/150.000`).
- [ ] 10 tappe di talenti (`skill_perks`), Percorso di mansione (10 missioni), imprese Lv 50/100, famiglio, Insegna, traguardi delle Stelle.
- [ ] Sblocco tramite una missione della storia (`unlocks: ["skill:<id>"]`).
- [ ] Icone: mansione (32×32), azioni (ogni prodotto/risorsa), attrezzo se previsto; se il prodotto è un nuovo materiale ricolorabile, aggiungere la sua rampa in `assets_plan/palettes.json` (docs/20 §7).

## 2. Nuovo oggetto / linea di equipaggiamento

- [ ] Categoria e sottocategoria esistenti (o aggiornare validatore + docs/07).
- [ ] Statistiche da `weapon_stats` / `armor_stats` o con un moltiplicatore documentato (unici ×1,12).
- [ ] Ricetta con ingredienti del tier giusto; livello = tier + scostamento del pezzo (eccezione 1.0: la Spada di Rame è Forgiatura 2, perché la richiede `main_c0_q4`, prima uccisione e prima Cassa).
- [ ] Valore da `proc_value`; `tradeable` corretto.
- [ ] Un singolo modificatore "generale" (`:all`) ≤ 10%.

## 3. Nuovo mostro / zona

- [ ] Struttura 4 normali + 1 élite + 1 boss (+ dungeon con boss a +12) — docs/08 R-MO-1..5.
- [ ] Stili variati, debolezze/resistenze coerenti con il tema, meccaniche del boss dall'elenco `BOSS_MECHANICS` (o nuova meccanica implementata nel `CombatEngine` + test).
- [ ] Tabelle di drop secondo R-MO-5; materiale comune e raro della zona **usati** da almeno una ricetta (alchimia, rune, glifi) o dalla Tenuta.
- [ ] Cassa di zona con 15 finiture + 3–4 ★ (+ eventuale famiglio ★), collezione con bonus.
- [ ] 6 missioni di capitolo, imprese del boss, famiglio del boss, 2 unici del boss + 2 del dungeon.
- [ ] Il simulatore deve restare entro i limiti (TTK 6–9 s, danno/uccisione ≤ 35%, cibo ≤ 450/h) per tutte e tre le classi.

## 4. Nuova cassa

- [ ] 6 Rare / 4 Epiche / 3 Leggendarie / 2 Mitiche + pool ★ (3–4 reliquie, 0–1 famiglio).
- [ ] Slot delle finiture vari (`CRATE_SLOTS`), bonus dallo slot (`SKIN_SLOTS`), intervalli di float dalla lista standard.
- [ ] Chiave del tier corretto; valore dei contenuti con `skin_value` (ritorno atteso 55–80%).
- [ ] Probabilità di rarità **identiche** a quelle standard (promessa pubblica). Varianti speciali solo nelle casse evento, dichiarate.
- [ ] Nomi originali, bilingui, coerenti con il tema; nessun nome di skin reale.
- [ ] Icone: cassa chiusa/aperta, 15 finiture (ricolorazioni dei modelli di slot), ★ uniche (generazione dedicata).

## 5. Nuova missione

- [ ] Rispetta R-QU-5..9 (docs/12): ritmo, varietà, ricompense, testi brevi, sblocchi.
- [ ] Ogni obiettivo usa un `type` esistente (o nuovo tipo implementato + documentato in docs/12 §3 + test).
- [ ] La catena resta raggiungibile (il validatore verifica la storia principale).

## 6. Nuova impresa (Steam)

- [ ] `steam_api_name` MAIUSCOLO, stabile per sempre (mai rinominare dopo l'uscita).
- [ ] Condizione verificabile da evento o statistica esistente.
- [ ] Ricompensa in Polvere proporzionata (1 facile → 30 estrema); icona 64×64 e versione bloccata **derivate in automatico** (`tools/compose_derived.py`, base scelta da `build_asset_manifest.py`); `steam_phase` 1 solo se le imprese di fase 1 restano ≤ 100 (il validatore lo controlla).
- [ ] Inserire anche nella configurazione Steamworks (docs/23 §7) **prima** della build che la usa.

## 7. Nuovo modificatore

- [ ] Aggiungere la famiglia a `modifiers.py` (unità, ambiti, cap, descrizioni IT/EN).
- [ ] Implementarne l'effetto nel sistema giusto + test.
- [ ] Mostrarlo nel pannello "Bonus attivi" con testo comprensibile.

## 8. Nuovo sistema

- [ ] Serve almeno un pilastro (docs/01 §3) e non introduce meccaniche di gioco d'azzardo (docs/24).
- [ ] Ha: dati in `data/`, sistema puro in `src/systems/`, schermata, sblocco da missione, salvataggio con migrazione, offline definito, test, voce in docs (nuovo capitolo o sezione), voci nel glossario.

## 9. Nuova Era / evento / stagione

- Era: nessun contenuto a mano (tutto da formule) tranne il nome e la cassa dell'Era (template).
- Evento: valuta, cassa evento (contenuti cosmetici o bonus temporanei), 3–5 missioni, ricompense che **tornano ogni anno** (niente esclusive permanenti).
- Stagione: modificatore globale + regole di conversione a fine stagione dichiarate all'inizio.

## 10. Checklist finale di ogni contenuto

```
[ ] generate_data.py   [ ] validate_data.py (0 errori)   [ ] balance_sim.py (0 fuori limite)
[ ] appendici + schemi aggiornati   [ ] manifest aggiornato (python tools/build_asset_manifest.py)
[ ] testi IT/EN   [ ] test GUT verdi   [ ] note di versione
```
