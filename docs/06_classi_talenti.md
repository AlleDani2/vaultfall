# 06 — Classi, specializzazioni, talenti

> Dati: `data/classes.json`, `data/abilities.json` (48 abilità), `data/talents.json` (78 nodi), `data/resources.json`.

## 1. Struttura

```
Guerriero (Mischia, FOR, Furia) ──► Paladino (Sacro, difesa e cure) | Berserker (danno e rubavita)
Ramingo  (Distanza, DES, Concentrazione) ──► Cecchino (Fulmine, critici) | Domatore (Veleno, compagno animale)
Arcanista (Arcano, INT, Mana) ──► Piromante (Fuoco, DoT) | Negromante (Ombra, prosciugamento, servitori)
Classi ibride (1 Stella Eroe): Lama Arcana (Mischia+Arcano) · Ombra Cacciatrice (Distanza+Mischia) · Tessitempeste (Arcano+Distanza)
```

- **R-CL-1:** la classe base si sceglie all'inizio (cambiabile gratis fino a Eroe 20, poi 300 oro × livello Eroe; attesa di 10 minuti tra due cambi). **Prova (MURI, BOT-05):** dopo un cambio a pagamento, tornare alla classe lasciata entro 2 ore di gioco è gratis e senza attesa (`class_change.trial_return_s`; stato `class_prev`/`class_prev_s`). Prima la finestra gratuita finiva a Eroe 10 e il cambio costava 5.000 oro × livello (60.000 a Eroe 12): chi provava una classe dopo il 10 restava bloccato per ore. Senza munizioni (rune dell'Arcanista, frecce del Ramingo) l'avvio del combattimento dice dove procurarsele (Sacchetto di Rune del Collegio all'Emporio per 25 oro; frecce dalla Falegnameria).
- **R-CL-2:** la specializzazione si sblocca a **Eroe 30** con la missione di classe (`class_<spec>`); si può possedere entrambe le specializzazioni della propria classe e cambiarle fuori dal combattimento (gratis).
- **R-CL-3:** le **classi ibride** si sbloccano con la prima **Stella dell'Eroe** e la missione `class_<ibrida>`. Hanno il passivo **Postura automatica**: a ogni nuovo nemico scelgono lo stile in vantaggio di triangolo tra i loro due; ~~in cambio tutte le statistiche ×0,95~~ (FIX-COMBATTIMENTO: crescita 1,0 per livello nei due attributi di stile e statistiche ×1,15, misurate a 0,96-0,99× delle classi non ibride; prima 0,5 e ×0,95 le lasciavano al 73-80%). Possono equipaggiare armi e armature di entrambi gli stili. La potenza d'attacco usa l'attributo dello **stile attivo** (FOR per Mischia, DES per Distanza, INT per Arcano): `AP = 1,5 × attributo`; crescita per livello e ripartizione automatica sono scritte in `data/classes.json` (`growth_per_level`, `auto_alloc`, anche per le specializzazioni).
- **R-CL-4:** lo **stile** di combattimento è dato dall'arma impugnata, ma l'attributo primario e le abilità dipendono dalla classe: usare un'arma di stile diverso dalla propria classe è possibile ma senza abilità di classe (solo attacchi base).

## 2. Crescita per livello

| Classe | Primario per livello | VIT per livello | Punti liberi |
|---|---|---|---|
| Guerriero | +1 FOR | +1,0 | +3 |
| Ramingo | +1 DES | +0,5 | +3 |
| Arcanista | +1 INT | +0,5 | +3 |
| Ibride | +0,5 a entrambi i primari | +0,75 | +3 |

Preset di distribuzione automatica (modificabile): 2 al primario, 1 a VIT. Ridistribuzione: gratuita fuori combattimento.

## 3. Abilità

- 6 abilità base per classe (livelli 1, 8, 15, 25, 40, 60), 3 per specializzazione (30, 50, 75), 4 per ibrida (1, 1, 50, 80).
- Fino a **4 abilità equipaggiate** in ordine di priorità (docs/05 §5). Le abilità con `trigger` (es. "Ultima Difesa" sotto il 30% di vita) scattano solo quando la condizione è vera.
- Ogni abilità ha icona `res://assets/icons/abilities/<id>.png` (manifest).

> **M7:** le ricariche della tabella qui sotto sono i valori "base"; in `data/abilities.json` sono raddoppiate (calibrazione, OPEN_QUESTIONS C2-1) **tranne quelle dei potenziamenti** (buff, debuff, scudi senza condizione: FIX-COMBATTIMENTO, valore della tabella). Cambio classe: azzera specializzazione e talenti della vecchia classe (le abilità tornano automatiche). Le specializzazioni si sbloccano a Eroe 30 con la missione di classe (gettone `class:<id>` o missione `class_<id>` completata); le ibride con una Stella dell'Eroe e la missione. La "Postura automatica" è scelta a ogni nuovo nemico (stile in vantaggio di triangolo) **e a ogni fase del boss** (COMBAT-3, `CombatSim.st_alt`); statistiche ×1,15 (FIX-COMBATTIMENTO).

### Regole di design delle abilità (per aggiungerne di nuove)

| Tipo | Ricarica | Costo | Potenza (danno arma) |
|---|---|---|---|
| Colpo base potenziato | 5–8 s | 20–35 | 170–230% |
| Multi-colpo | 12–25 s | 40–70 | 4–5 colpi da 70–130% (totale 280–650%) |
| DoT | 10–15 s | 30–45 | 35–60%/s per 6–8 s |
| Buff/debuff | 20–40 s | 20–40 | +15–30% per 6–15 s |
| "Finale" (Lv 75+) | 30–45 s | 60–90 | 300–500% |
| Difensiva con condizione | 50–60 s | 0 | cura 25–30% / scudo 20% |

Somma attesa dei contributi delle abilità con rotazione ottimale: **+20–30% DPS** rispetto ai soli attacchi base. Il simulatore usa +25%.

## 4. Talenti

- 1 punto talento ogni 2 livelli Eroe (max 50) + 1 punto per ogni Stella dell'Eroe (max +25).
- Albero per classe: ramo **Generale** (6 nodi) + un ramo per **ogni specializzazione** (6 nodi). Le ibride hanno un ramo unico da 8 nodi.
- Nodo *i* del ramo richiede `2 × i` punti già spesi in quel ramo; i nodi finali (indice 5) sono da 1 rango e valgono molto (es. +10% danno).
- Respec: gratuito fino a Eroe 20, poi 1.000 oro × livello Eroe.
- **Rami esclusivi** (CORSA, QA4 #9): valgono solo Generale/Ibrido e il ramo della specializzazione **attiva**; i punti nel
  ramo dell'altra specializzazione restano salvati e tornano a valere cambiandola. Non si possono aggiungere ranghi a un ramo
  inattivo (motivo «inactive» nella schermata Talenti).
- **Ritaratura** (CORSA, resoconto 91, misure `q4_sweep mode=talents`): Vigore 0,15 → 0,05 %/s di rigenerazione per rango;
  Brutalità +10 → +25 punti di danno critico e +2 punti di critico per rango; Punto Debole +8 → +15; Impeto +4 → +3% velocità per rango; Imposizione
  da cure ricevute a **cura del cibo** +10%/rango; Risolutezza +2% vita per rango oltre alla resistenza agli stati.

## 5. Bilanciamento delle classi (obiettivi)

| Classe | Ruolo | Punto forte | Punto debole |
|---|---|---|---|
| Guerriero (piastre) | Tank | Armatura alta, vita alta, nessun costo di munizioni | Viene colpito quasi sempre; debole contro l'Arcano |
| Ramingo (cuoio) | Elusivo | Evasione, critici, il meno costoso in cibo | Consuma frecce; debole contro la Mischia |
| Arcanista (stoffa) | Cannone di vetro | DPS più alto, protezione arcana alta | Armatura bassa, più cibo; consuma rune; debole contro la Distanza |

Vincolo verificato dal simulatore: a parità di livello/tier i TTK delle tre classi restano entro **±15%** e il danno subito per uccisione entro il 35% della vita.
