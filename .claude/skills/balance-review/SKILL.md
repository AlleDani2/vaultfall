---
name: balance-review
description: Analizza il bilanciamento con il simulatore e propone modifiche motivate alle formule. Usare quando l'utente segnala che qualcosa è troppo facile, lento, forte o redditizio.
---
# Revisione del bilanciamento

1. Esegui `python tools/balance_sim.py` e leggi `reports/balance_report.md`.
2. Confronta con gli obiettivi di `docs/19_bilanciamento.md §2`.
3. Individua la leva giusta secondo `docs/19 §5` (mai cambiare le probabilità di rarità delle casse: sono una promessa pubblica).
4. Proponi la modifica con numeri prima/dopo e l'effetto atteso; applicala solo dopo conferma dell'utente se tocca la progressione già pubblicata.
5. Rigenera (`/data-pipeline`) e riporta il nuovo report.
