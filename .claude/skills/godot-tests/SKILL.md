---
name: godot-tests
description: Esegue i test GUT del progetto Godot in modalità headless e riassume i risultati. Usare dopo modifiche a src/ o prima di chiudere un compito.
---
# Test del progetto Godot

1. Assicurati che `game/data` sia aggiornato (`python tools/sync_data.py`) e che `game/tests/reference_values.json` esista (`python tools/export_reference_values.py`).
2. Esegui `python tools/run_tests.py` (funziona da Git Bash e da PowerShell; usa la variabile `GODOT_BIN` con l'eseguibile **console** di Godot 4.7.2, importa le risorse e lancia GUT su `res://tests`). Codice 0 = verde, 1 = test falliti, 2 = Godot/GUT/progetto mancanti: in quel caso spiega allo sviluppatore come impostare `GODOT_BIN` (README).
3. Riporta: test totali, falliti (nome, messaggio, file:riga), tempo.
4. Se un test di formula fallisce, confronta con `tools/gamedata/core.py`: il riferimento è il Python.
