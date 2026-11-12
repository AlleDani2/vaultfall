# 15 — Famigli, Compendio, Imprese (achievement), Titoli, Cosmetici

> Dati: `data/pets.json` (40), `data/achievements.json` (118), `data/titles.json`, `data/collections.json`, `data/items/cosmetic.json`.

## 1. Famigli

- 40 famigli: 17 di mansione, 10 dei boss di zona, 3 delle incursioni, 6 ★ delle casse (pool delle reliquie), 4 degli eventi stagionali (docs/27).
- **Tutti i famigli posseduti danno il loro bonus passivo** (collezione stile "serraglio"), non serve equipaggiarli. Uno può essere scelto come **compagno visibile** nel pannello Eroe (solo estetica).
- Probabilità (docs/04 §9 e A6): mansioni ≈ 1 ogni 25–40 h, boss 1/1500, incursioni 1/250, casse ★.
- Notifica speciale e voce nel registro quando si trova un famiglio (momento "wow": banner dorato 3 s).
- Modificatore `pet_chance_pct` (Costellazioni, reliquie).

## 2. Compendio (collection log)

Schermata con schede: **Oggetti** (ogni oggetto mai ottenuto), **Mostri** (uccisioni per mostro, drop ottenuti dalla sua tabella con caselle grigie per i mancanti), **Casse** (Album delle collezioni, docs/09 §8), **Famigli**, **Unici**. Percentuale di completamento totale e per categoria. Contatori a vita: uccisioni, azioni per mansione, casse aperte, ★ trovate, oro guadagnato, tempo giocato/offline.

## 3. Imprese (achievement)

- 118 imprese in 9 categorie: mansioni (Lv 50/100 per ognuna), livello totale, prestigio, combattimento (boss, dungeon, incursioni, uccisioni, Breccia, Ere), casse, economia, Tenuta, storia (ogni capitolo), famigli, varie (anche nascoste e simpatiche: "Chef Distratto").
- Ricompensa: 1–30 **Polvere Stellare** e talvolta un **titolo**.
- **Steam:** ogni impresa ha `steam_api_name` (MAIUSCOLO, mai rinominato dopo l'uscita) e `steam_phase`. Steam consente **100 imprese** finché l'app non sblocca le *Profile Features*: **100 di fase 1** si configurano per l'Accesso Anticipato, **18 di fase 2** si aggiungono appena il limite cade (nel gioco esistono tutte da subito). Icone: 64×64 in gioco; per Steamworks PNG **256×256** sbloccata + bloccata, create da `tools/compose_derived.py` con i nomi del caricamento in blocco (docs/23 §7.1). Le imprese "grind" estreme vanno marcate `hidden` solo se sono sorprese, non per nascondere la fatica.
- Regole di design: ogni capitolo, ogni sistema principale e ogni mansione hanno almeno un'impresa raggiungibile entro le prime 10 ore di quel sistema; massimo 10% di imprese che richiedono > 200 h.

## 4. Titoli

79 titoli (missioni, imprese, collezioni auree, fazioni Esaltato, dungeon ×250, 25 Stelle, eventi). Un titolo selezionato appare accanto al nome dell'Eroe e nelle classifiche Steam (testo locale). I nomi sono già bilingui nei dati (`data/titles.json`, campo `name` con `it`/`en`): nessuna chiave da aggiungere a `localization/ui_strings.csv`.

## 5. Cosmetici

- **Stendardi** e **Emblemi** del profilo (capsule cosmetiche), **cornici delle Stelle** (bronzo/argento/oro/platino/diamante/celeste per mansione), cornici degli eventi.
- Nessun cosmetico dà statistiche. Nessuno si compra con denaro reale (eventuale DLC "Sostenitore" = colonna sonora + 3 stendardi fissi, **mai casuale**).
