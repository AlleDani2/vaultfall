---
name: next-task
description: Riprende lo sviluppo di VAULTFALL dal prossimo compito della roadmap. Usare all'inizio di ogni sessione o quando l'utente dice "continua", "prossimo passo", "vai avanti".
---
# Prossimo compito della roadmap

1. Leggi `PROGRESS.md` e individua la milestone corrente e il primo compito con stato ⬜ o 🟨.
2. Apri `docs/22_roadmap.md` alla milestone corrente e rileggi il testo del compito e i **criteri** della milestone.
3. Leggi solo i documenti citati dal compito (es. `docs/05` per il combattimento) e i file di `data/` coinvolti.
4. Prima di scrivere codice, elenca in 5-10 righe il piano (file da creare/modificare, test da scrivere).
5. Implementa. Rispetta le regole di `CLAUDE.md` (dati generati, niente numeri nel codice, logica separata dalla UI, testi bilingui).
6. Esegui i test (`python tools/run_tests.py`) e, se hai toccato i dati, la pipeline (`/data-pipeline`).
7. Aggiorna `PROGRESS.md` (stato, data, file, test, note) e aggiungi una riga al "Registro sessioni".
8. Chiudi con un riepilogo per lo sviluppatore in italiano: cosa è stato fatto, come verificarlo a mano (passi numerati), prossimo compito.
