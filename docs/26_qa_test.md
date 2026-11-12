# 26 — Piano di test e qualità

## 1. Livelli di test

| Livello | Strumento | Quando | Cosa |
|---|---|---|---|
| Dati | `python tools/validate_data.py` | a ogni modifica dei dati | riferimenti, nomi, modificatori, fonti/usi |
| Bilanciamento | `python tools/balance_sim.py` | a ogni modifica di formule | limiti di design (docs/19 §2) |
| Formule | GUT `tests/test_formulas.gd` | a ogni build | confronto con `tests/reference_values.json` (generato da `tools/export_reference_values.py`) |
| Sistemi | GUT `tests/test_<sistema>.gd` | a ogni build | logica pura con stato finto |
| Salvataggi | GUT `tests/test_save.gd` | a ogni modifica dello schema | round-trip, migrazioni, file corrotto, backup |
| Integrazione | scena `tests/IntegrationRunner.tscn` headless | prima di ogni milestone | 24 h simulate in accelerato senza errori |
| Manuale | checklist §4 | prima di ogni build pubblica | UI, input, Steam Deck |

Comando headless (Windows, PowerShell; adattare il percorso dell'eseguibile console di Godot):
```
python tools/run_tests.py            # usa GODOT_BIN, importa le risorse e lancia GUT (codice 0 = verde)
# equivalente a mano (PowerShell):
& $env:GODOT_BIN --headless --path game --import
& $env:GODOT_BIN --headless -d -s --path game addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=res://test_results.xml
```

### 1.1 Stato reale della QA (23/10/2026)

- **Suite GUT**: 66 file in `game/tests/`, circa 830 funzioni di test; ultimo giro completo 805/806 verdi (il rosso è sempre `test_playthrough_long`, soglie di tempo sotto carico della macchina: rumore d'ambiente, non funzionale). `python tools/run_tests.py` esce 0 solo con «All tests passed».
- **Test Python** in `tests/`: `test_coherence.py` (12 controlli di coerenza globale dati/testi/sistemi, nati dal rapporto QA5), `test_en_quality.py` (inglese), `test_wiki.py` (wiki), `test_audio_levels.py` (livelli, loop, manifest). Tutti in `tools/check_all.py`, insieme a validatore, simulatore, sync, valori di riferimento (341 casi), perimetro slice e controllo dei telai UI (`make_ui_frames.py --check`).
- **Bot giocatore** (`game/scripts/bot_player.gd`, `test_playthrough.gd`, `test_playthrough_long`): gioca la partita VERA con i sistemi veri a passi da 0,1 s. Completa Prologo e Cap. I in 60–90 min simulati, arriva alla prima incursione (16,8 h) e al primo Rito (20,7 h); prima Cassa a ~13 min. Ha trovato 20 bug di colla nella prima integrazione.
- **Analisi di supervisione** (`docs/audit_2026-10-22/qa/`, script in `tools/analysis/`): QA1 inizio gioco (3 profili), QA3 economia/Casse (Monte Carlo 1.000.000 aperture × 16 casse), QA4 combattimento (12 classi, zone 1–10), QA5 coerenza (tabelle CSV su dati inerti, missioni bloccate, chiavi di testo, raggiungibilità), AUDIT-ROADMAP (matrice di 446 requisiti della VAlfa1.0, 53 gap).
- **Fuzzing**: non esiste un fuzzer vero. Le cose più vicine: salvataggio da 20.000 istanze e round-trip (spike S2), 100.000 aperture di Casse in `test_crates.gd`, `test_save_endgame`, import di salvataggi corrotti; **lacuna dichiarata**: nessuna fuzzatura di input casuali sulle schermate né sui salvataggi malformati in massa.
- **QA visiva**: catture IT/EN a 1280×720 e 1920×1080 (`docs/audit_2026-10-22/catture/`, resoconti 40, 41, 62, 66) con Xvfb. Non sostituiscono la verifica umana su Windows.
- **Prototipo coop**: `tools/analysis/coop_proto/run_proto.py`, 2 processi Godot, hash dello stato ogni 5 s.
- **Non verificato da persone**: audio, resa su Windows, scala frazionaria a 1080p, bilanciamento oltre il Cap. VI (il bot arriva fin lì). Checklist per un non tecnico: `docs/giocatori/CHECKLIST_VERIFICA_UMANA.md`.

## 2. Test obbligatori per sistema (minimo)

- **Formulas:** xp_to_next (L = 1, 10, 50, 99), hit_chance (5 coppie), damage_reduction (5), monster_stats (L = 1, 50, 100 per 3 tipi), food_heal, weapon_damage, soci_total, estate_units_per_hour, echo_multiplier, star_haste_pct, star_xp_pct, star_curve.
- **Modifiers:** cumulo add/more, ambiti (skill + gruppo + all + current), cap, sostituzione di una fonte.
- **SkillSystem:** azione completa → XP, prodotti, consumo; risparmio e doppio (con RNG fisso); stop a fine materiali; banca piena.
- **CraftingSystem:** distribuzione delle qualità su 10.000 estrazioni entro ±1,5 punti dalle probabilità teoriche; bruciatura.
- **CombatEngine:** TTK medio di 1.000 combattimenti per 3 combinazioni del report entro ±10% dal simulatore Python; morte; auto-mangiare; munizioni finite; triangolo; elementi.
- **CrateSystem:** 1.000.000 aperture simulate → frequenze di rarità entro ±0,1 punti dalle probabilità **effettive** (`crate_rules.pity.effective_rarity_pct`); ★ effettiva entro ±0,02 punti da `effective_relic_pct`; pity (mai oltre 500 senza ★, un contatore per `pity_family`); per 5 finiture con intervalli diversi le frequenze delle condizioni entro ±0,5 punti da `condition_odds`; float sempre nell'intervallo della finitura **e** della condizione estratta; Annalista ~10%; rullo con vincitore alla posizione 52 e riempitivi con frequenze reali.
- **TradeUpSystem:** probabilità per collezione proporzionali; formula del float normalizzato; rifiuto di input misti.
- **MarketSystem:** domanda che scende con le vendite e torna con emivita 6 h; tassa; tendenze limitate.
- **EstateSystem:** produzione con traguardi, costi, vincolo dei coloni, Rifondazione e Soci.
- **PrestigeSystem:** curve asintotiche delle Stelle (`star_xp_pct`, `star_curve`) uguali ai valori di riferimento; Eco; il Rango applica ×1,04 solo alle statistiche di `applies_to_stats` (`data/era_rules.json`).
- **QuestSystem:** ogni tipo di obiettivo; sblocchi; catena principale completa in un salvataggio di test ("giocatore onnipotente").
- **Sabbia del Custode (UI F13):** `test_click_limiter` (20 eventi in 1000 ms accettati, 21° rifiutato, riaccetta dopo la finestra, istanti non monotoni, eventi echo); `test_time_push` (spesa ≤ riserva, spesa parziale, rigenerazione solo con azione ammessa e non in pausa, offline = ρ_off × Δt con il tetto di R-OFF-1, mai oltre il tetto, salva/carica, determinismo, regalo di sblocco una volta); `test_simulation_subset` (ordine fisso, bank incluso, nessun tick agli altri sistemi, playtime e calendario invariati); `test_time_push_crates` (stessa sequenza di aperture con e senza Sabbia: stessi oggetti, seme e `draw_n`); `test_time_push_blocked` (dungeon, incursioni, Breccia, boss mondiali, Prova, Estremo, coop, combattimento in zona); `test_time_push_perf` (20 clic/s per 60 s: budget di CPU e nessun `long_gap`); migrazione v3→v4 in `test_save_service`; `push_regen`/`push_spend` in `test_formulas`.
- **Deposito: regola di spazio e Armeria (UI F15):** `test_bank_space_rule` (R-SP-1…9: pile e Finiture contano, equipaggiamento e attrezzi no, oro no; indossato resta nell'Armeria; oltre il tetto il pezzo va nel Carro e lo Spazio resta libero; Spazio pieno con Armeria libera; Carro scaricato per classe; avviso dell'Armeria una sola volta; «Tutto» = `used_slots()` e «Armeria» = `gear_used()` nella schermata; salvataggio vecchio con 340 pezzi che si apre con lo Spazio sceso senza perdere nulla; Carro vecchio scaricato una volta e senza ripetere la riga; estrazioni delle Casse identiche con l'Armeria piena; fuzz corto sugli invarianti); `test_fuzz_bank` (invarianti di classe ogni 100 passi); `test_carro_totale` e `test_probe_deposito_pieno` riempiono lo Spazio con pile, non con equipaggiamento.
- **Deposito: schede, migrazione, selezione e vendita, ricerca (UI F17):** `test_bank_tabs` (limiti dai dati, nomi ripuliti e unici, id mai riusati, eliminazione senza perdite, una scheda per voce e gear non assegnabile, appiccicosità, tetto delle assegnazioni, round-trip; barra e conteggi, ordinamento salvato per scheda, trascinamento e alternativa, conferma di eliminazione, benvenuto e schede suggerite, passo `f_bank_tabs`); `test_save_v_bank_tabs` (schema 5, v4 → v5 con oggetti identici e idempotente, migrazione tollerante, v4 con 340 pezzi, schede corrotte ripulite con una riga, campi nuovi innocui, import Base64 di un v4 e salva/ricarica); `test_bank_selection` (esclusioni = `SellRules`, Ctrl+A, motore unico per Sposta/Blocca/Vendi, tasti locali, Canc/Invio non vendono, Esc a catena); `test_bank_sell_safety` (protetti mai venduti, anteprima = esito, guardia sul primo Invio, quantità per pila, modalità spenta cambiando schermata, senza Mercato non si entra); `test_bank_search` (accenti, AND, operatori con ripiego sui gruppi, scheda Risultati ed Esc con la posizione, attesa); `test_bank_i18n` (chiavi bilingui, nessuna chiave a vista in IT/EN, nomi del giocatore mai tradotti né in RichTextLabel, nome predefinito).
- **Progetto di interfaccia (UI F0–F18, `docs/ui_redesign/`):** a fine progetto la suite conta **157 file e ~1.840 funzioni di test**. I file nati con le fasi, uno per tema: `test_ui_budget` + `helpers/ui_census` (F0: censimento dei controlli e **soglie di densità** per cornice e per schermata, `reports/ui_budget.json`; le soglie finali sono riviste in F18), `test_activity_text` e `test_combat_fx_bounds` (F1: testo dell'attività senza zona, numeri di danno dentro l'arena), `test_topbar` (F2), `test_right_rail` (F3: binario, cassetto, striscia Obiettivo), `test_sidebar_groups` (F4: gruppi e segnali a tre tipi), `test_ui_scale_auto` (F5: scala automatica, vincolo 1024×576, conversione dei vecchi valori), `test_summary_dashboard` (F6), `test_skill_rows_compact` (F7), `test_combat_layout` (F8), `test_estate_dungeon_layout` (F9), `test_hero_tabs` (F10), `test_vault_odds_visible` (F11: **regola 5, probabilità sempre visibili senza clic**), `test_bank_toolbar` (F12), `test_click_limiter`, `test_simulation_subset`, `test_time_push`, `test_time_push_blocked`, `test_time_push_crates` (le Casse non cambiano con la Sabbia), `test_time_push_perf` (F13), `test_push_button` (F14), `test_bank_space_rule` (F15), `test_number_cell_format`, `test_virtual_grid`, `test_bank_grid_view` (F16), `test_bank_tabs`, `test_save_v_bank_tabs`, `test_bank_selection`, `test_bank_sell_safety`, `test_bank_search`, `test_bank_i18n` (F17). Prestazioni: `test_perf_ui` misura la costruzione a freddo del Deposito (limite di progetto 450 ms; dopo F18 stabilmente sotto ~350 ms: il dettaglio sta in `BankDetail.gd`, caricato alla prima selezione, e le classi usate solo da lista, tooltip e finestre si caricano al primo uso).
- **Misura finale della densità (F18):** `docs/ui_redesign/strumenti/ux_density_dump.gd` + `analizza_densita.py` + `mediane_densita.py` sugli stessi checkpoint del bot attivo (seme 20261101, 12/31/60 h) a 1280×720 e 1920×1080 con scala automatica; risultati in `docs/ui_redesign/08_RISULTATI.md`. Si rilancia a ogni cambio importante di interfaccia (procedura in `04 §7.1`).
- **Bot novizio** (`python tools/run_bot_novizio.py`): il percorso del tutorial e dell'inizio gioco con clic e tasti veri, IT/EN × 720p/1080p; si rilancia dopo ogni fase di interfaccia (esito F18 in `docs/ui_redesign/26_RESOCONTO_F18.md`).
- **OfflineSimulator:** 12 h di mansione = stessi risultati (±2%) della simulazione tick per tick; 12 h di combattimento entro ±5%; Δt negativo → 0.
- **SaveService:** salva/carica identico; migrazione v1→v2 di esempio; file troncato → si usa il backup.

## 3. Test di regressione del bilanciamento

`tools/balance_sim.py` è anche un test: se la sezione "Controllo automatico" trova combinazioni fuori limite, la build non è valida.

## 4. Checklist manuale prima di ogni build pubblica

- [ ] Nuova partita: primi 60 minuti come da docs/01 §6 (cronometrare).
- [ ] Ogni schermata a 1920×1080, 2560×1440, **1280×800** (Steam Deck) e 1366×768: niente testo tagliato.
- [ ] Navigazione completa con controller; tastiera virtuale su Deck nei campi di testo.
- [ ] Lingua IT ed EN: nessuna chiave non tradotta (`UI_...` visibile = errore).
- [ ] Offline di 8 h reali: riepilogo corretto.
- [ ] Apertura di 100 casse: nessun rallentamento; salta/rapida/×10 funzionano; probabilità visibili.
- [ ] Imprese Steam che scattano (con `steam_appid.txt` in sviluppo), Cloud che sincronizza tra due PC.
- [ ] Chiusura forzata durante il salvataggio → al riavvio nessuna perdita oltre l'ultimo salvataggio.
- [ ] Uso di CPU con finestra in secondo piano o ridotta a icona: ≤ 3% (10 FPS in background, `low_processor_usage_mode`, docs/17 §11).

## 5. Telemetria

Nessuna telemetria online nella 1.0 (niente dati personali, niente GDPR). Opzionale in futuro solo con consenso esplicito e informativa. Per il debug: log locale `user://logs/` (registro errori ruotato `vaultfall*.log`, ultimi 5 avvii) e pulsante "Esporta diagnostica" (salvataggio + log in uno zip) nelle Impostazioni (dall'Alfa 0.1.0: «Segnala un problema», ZIP locale in Desktop o `user://reports/`; statistiche locali opt-in; menù F10 solo debug o `VAULTFALL_DEBUG=1`).
