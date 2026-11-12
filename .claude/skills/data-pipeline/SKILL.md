---
name: data-pipeline
description: Rigenera e verifica i dati di gioco dopo ogni modifica a tools/gamedata (generatore, validatore, simulatore di bilanciamento, appendici, schemi, copia nel progetto Godot).
---
# Pipeline dei dati

Esegui in ordine e fermati al primo errore:

1. `python tools/generate_data.py`
2. `python tools/validate_data.py` → deve finire con **0 errori**. Correggi la fonte in `tools/gamedata/*.py`, mai i JSON.
3. `python tools/balance_sim.py` → deve terminare con **codice 0** (tutti i controlli automatici OK: tabella "Riepilogo dei controlli automatici" in fondo a `reports/balance_report.md`). Se un controllo fallisce, correggi la causa in `tools/gamedata/` (ricette in docs/19 §5) e rilancia. Se cambia qualcosa di rilevante, riassumi le differenze.
4. `python tools/make_appendices.py` e `python tools/make_schema_doc.py`
5. `python tools/export_reference_values.py` (se hai toccato `core.py`)
6. `python tools/sync_data.py` (se esiste `game/`)
7. `python tools/build_asset_manifest.py` (se hai aggiunto oggetti/mostri/icone: deve dire "Copertura: tutte le … immagini"; codice 1 se un'immagine dei dati non è nel manifest)
8. Riporta: conteggi principali (oggetti, azioni, mostri, missioni), errori/avvisi, effetti sul bilanciamento.
