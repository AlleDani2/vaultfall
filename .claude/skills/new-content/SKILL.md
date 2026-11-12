---
name: new-content
description: Aggiunge nuovi contenuti (mansione, oggetti, mostri, zona, cassa, missioni, imprese, modificatori, eventi) seguendo il regolamento di docs/25. Usare quando l'utente chiede di aggiungere o espandere contenuti.
---
# Aggiungere contenuti

1. Leggi `docs/25_regole_contenuti.md` e la checklist della categoria richiesta.
2. Leggi i moduli coinvolti in `tools/gamedata/` (vocabolario in `vocab.py`, formule in `core.py`).
3. Proponi all'utente un elenco sintetico dei contenuti (nomi IT/EN, livelli, ruolo nell'economia) se la richiesta è vaga; altrimenti procedi.
4. Aggiungi i contenuti nel generatore usando le formule esistenti (niente numeri arbitrari; se servono, commenta il motivo).
5. Esegui `/data-pipeline` e correggi finché validatore e simulatore sono puliti.
6. Aggiorna i documenti interessati (capitolo del GDD, glossario) e il manifest degli asset.
7. Riassumi cosa è stato aggiunto e cosa resta da fare (icone, testi, test).
