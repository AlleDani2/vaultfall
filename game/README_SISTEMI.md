# Guida rapida per chi aggiunge sistemi e schermate (VAULTFALL, Godot 4.7.2)

Leggere prima `CLAUDE.md` e `docs/17_architettura_godot.md`. Qui solo il "come si fa", con i punti di aggancio
pensati perché più agenti lavorino in parallelo senza toccare gli stessi file.

## 1. Mappa

| Cosa | Dove | Note |
|---|---|---|
| Autoload | `src/autoload/` | `EventBus` · `DataRegistry` · `Clock` · `Settings` · `Loc` · `GameState` · `Rng` · `Modifiers` · `SaveService` · `Game` (ordine in `project.godot`) |
| Utilità pure | `src/core/` | `Formulas`, `NumberFormat`, `ModifierStack`, `RngStreams`, `FixedStepClock`, `SaveCodec`, `GameSystem`, `SystemContext`, `Simulation` |
| Sistemi di gioco | `src/systems/` | una classe per sistema + **`SystemRegistry.gd`** (unico punto di aggancio) |
| Schermate | `src/ui/screens/` | una scena per schermata + **`src/ui/ScreenRegistry.gd`** (unico punto di aggancio) |
| Testi UI | `localization/ui_strings.csv` (radice) | copiare in `game/localization/` (o `python tools/sync_data.py`) |
| Test | `tests/test_*.gd` | GUT 9.7.0, `python tools/run_tests.py` |

## 2. Aggiungere un sistema (3 passi)

1. Creare `src/systems/MioSystem.gd`:

```gdscript
class_name MioSystem
extends GameSystem

func _init() -> void:
	id = "mio"              # unico
	state_key = "mio"       # sezione di GameState.data posseduta ("" = nessuno stato)

func default_state() -> Variant:
	return {"contatore": 0}

func tick(dt: float) -> void:            # ogni 0,1 s simulati, mai await, mai tempo reale
	state.contatore += 1                  # `state` È GameState.data["mio"] (stesso Dictionary)

func int_paths() -> PackedStringArray:   # campi interi da normalizzare al caricamento (R-SAV-8)
	return PackedStringArray(["contatore"])
```

2. Aggiungere **una riga** in `src/systems/SystemRegistry.gd`, nella posizione dell'ordine fisso
   (Activity → Apprentices → Farming → Estate → Expeditions → Buffs/Timers → Quests/Achievements → Unlocks).
3. Scrivere `tests/test_mio_system.gd` (vedi §6). Esempio completo: `src/systems/BuffSystem.gd` + `tests/test_systems.gd`.

Regole: classe pura `RefCounted` (niente nodi, niente `await`, niente `Time`/`OS`), deterministica; modifica solo
la propria sezione; per sapere qualcosa di un altro sistema `ctx.get_system("altro")`; offline: sovrascrivere
`simulate_offline(seconds)` con una versione analitica (quella di base fa tick a passi fissi, esatta ma lenta).
Salvataggio: nulla da fare, `Game.snapshot()` chiama `to_state()` di ogni sistema. Interi > 2^53 come **stringhe**.
Se si cambia la forma di una sezione già rilasciata: `SaveCodec.SCHEMA_VERSION += 1` + migrazione (vedi `SaveCodec.gd`).

## 3. Cosa usa un sistema (`ctx`, mai gli autoload direttamente)

| | Esempio |
|---|---|
| Dati (sola lettura) | `ctx.data.item("log_pine")` · `ctx.data.action("mine_copper")` · `ctx.data.actions_for_skill("mining")` · `ctx.data.get_def("monsters", id)` · `ctx.data.table("zones")` · `ctx.data.rules("crate_rules")` · `ctx.data.constants` |
| Formule | `Formulas.xp_to_next(lv)`, `Formulas.hit_chance(acc, eva)`… (statiche, costanti già configurate) |
| Bonus | `ctx.modifiers.set_source("equip:weapon", [{"key": "skill_double_pct:mining", "value": 3}])` · `ctx.modifiers.apply(base, "skill_haste_pct", ["mining", "gathering", "all"])` |
| Caso | `ctx.rng.stream("loot").randf()` · `ctx.rng.chance("crates", p)` · `ctx.rng.weighted_index("loot", pesi)` (flussi: loot, crates, combat, market, world) |
| Segnali | `ctx.events.item_gained.emit("log_pine", 1, "mining")` (elenco in `EventBus.gd`; aggiungerne uno = una riga lì) |
| Stato radice | `ctx.state` (= `GameState.data`), solo in lettura fuori dalla propria sezione |

Numeri di bilanciamento: **solo** da `data/constants.json` o dai file di dati. Mai costanti nel codice.

## 4. Aggiungere una schermata (3 passi)

1. Scena `src/ui/screens/MiaScreen.tscn`, radice con script che `extends GameScreen`
   (`open(params)`, `refresh()` chiamato a ≤10 Hz, `close()`).
2. **Una riga** in `SCREENS` di `src/ui/ScreenRegistry.gd` (`id`, `section`, `title`, `icon`, `scene`, `unlock`, `order`);
   per una voce già presente basta compilare `scene`. Le mansioni usano `SKILL_SCENE` (riceve `{"skill": id}`).
3. Chiave del titolo e di ogni testo visibile in `localization/ui_strings.csv` (`keys,en,it`).

Testi: nei nodi si scrive direttamente la chiave (`text = "UI_BANK_TITLE"`, traduzione automatica); nel codice
`tr("UI_…")` o `Loc.tf("UI_…", {"n": 3})`; testi dei dati `Loc.t(item.name)`. Numeri: `NumberFormat.fmt(n)`,
`fmt_time(s)`, `fmt_pct(p)`. Il test `test_ui.gd` fallisce se una chiave manca o se c'è una stringa visibile fissa.
Navigazione da codice: `EventBus.screen_requested.emit("bank", {})`. Notifiche: `EventBus.notice.emit("info", testo_tradotto, {})`.
Tema: `src/ui/theme/main_theme.tres` è GENERATO da `scripts/build_theme.gd` (variazioni: TitleLabel, SectionLabel,
MutedLabel, MonoLabel, SidebarButton, AccentButton, TopBarPanel, ContentPanel, LogPanel).

## 5. Ciclo di vita

`Clock` (tempo reale misurato) → passi fissi 0,1 s (max 50 per frame; ritardi > 60 s ceduti in blocco come offline)
→ `Game._on_step` → `Simulation.tick` → sistemi in ordine. Partita: `Game.new_game(slot, "normal")`,
`Game.load_game(slot)` (migrazione + normalizzazione + offline fino al limite), `Game.stop_game()`.
Salvataggi: `SaveService` (3 slot, atomico, `.bak1..3`, autosave 30 s, all'uscita, su `EventBus.important_event`).

## 6. Test GUT

```gdscript
extends GutTest

func test_qualcosa() -> void:
	var state := {}
	var ctx := SystemContext.make(DataRegistry, state, ModifierStack.new(), RngStreams.new(42), EventBus)
	var sim := Simulation.new()
	sim.setup(ctx, [MioSystem.new()])     # solo il sistema in prova
	sim.bind_state(state)
	for i in 10:
		sim.tick(0.1)
	assert_eq(state.mio.contatore, 10)
```

- Gli autoload sono disponibili nei test (DataRegistry già carico). Non sporcare lo stato globale: se si usa
  `Game`/`SaveService`, cambiare `SaveService.save_dir` in una cartella temporanea e ripristinarla (vedi `test_save_service.gd`).
- Errori del motore attesi (es. file corrotti) vanno marcati come gestiti (`get_errors()` → `e.handled = true`), altrimenti GUT fallisce.
- Comando: `GODOT_BIN=… python tools/run_tests.py` (verde solo con "All tests passed", ≥1 test e nessuno SCRIPT ERROR);
  iterazione veloce: `python tools/run_tests.py --no-import --select test_mio` (o direttamente `$GODOT_BIN --headless -d -s --path game addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gselect=test_mio`).
  Dopo aver creato nuove `class_name` lanciare una volta `$GODOT_BIN --headless --path game --import`.
- **Esecuzione in parallelo e gruppi** (resoconto 67). `python tools/run_tests.py` divide i file di test in N processi Godot
  (N = min(4, CPU), ripartizione per pesi in `tools/test_weights.json`, aggiornabile con `--update-weights`), ognuno con una
  propria cartella `user://` temporanea (nessuna collisione sui salvataggi). Verde solo se TUTTI i processi dicono
  "All tests passed", con ≥1 test e senza SCRIPT ERROR. Opzioni: `--fast` (senza il gruppo lento: i playthrough lunghi del
  bot in `SLOW_FILES`, dentro `run_tests.py`; è l'uso quotidiano, ~1-2 min), `--slow-only`, `--perf-only`, `--jobs N`
  (1 = seriale), `--select nome` (solo i file che contengono il nome), `--no-import`, `--no-perf`, `--verbose`.
  `python tools/check_all.py --veloce` = controllo unico con `--fast`; prima di chiudere un compito: la suite completa.
  A fine corsa stampa i 10 file più lenti; il report JUnit unito è in `game/test_results.xml` (un `testsuite` per file).
  Un test nuovo molto lungo (> ~30 s) va aggiunto a `SLOW_FILES`.
- **Test di prestazione (gruppo `perf`)**: usare `tests/helpers/perf_gate.gd` (`PerfGate`), mai un limite fisso in ms.
  Il limite di progetto (docs/17 §11: 24 h offline <= 1 s, tick <= 15 ms) si moltiplica per un fattore di carico =
  tempo di una routine di riferimento nello stesso processo / `REF_MS`, mai < 1 e <= 6; dove la misura è ripetibile si
  prende il minimo di 3 (`best_of`). Le funzioni che SOLO misurano si chiamano `test_perf_*` e iniziano con
  `if PerfGate.skip_if_deferred(self): return`: nei processi paralleli sono rimandate e girano alla fine da sole, in serie
  (`--perf-only` per lanciare solo quelle). Nelle partite lunghe del bot il fattore è seguito durante la partita
  (`PerfGate.Tracker`, agganciato a `BotPlayer.between_steps`). Ogni misura stampa una riga `PERF …` con il fattore usato.
  Interpretazione di un fallimento: se la riga PERF mostra un fattore alto (>2) il problema è il carico, rilanciare con la
  macchina libera; se il fattore è ~1 e il tempo è molto sopra il limite è una regressione vera. Non allentare i limiti di
  progetto per far passare un test: se serve, ricalibrare `REF_MS` (CPU molto diversa) con la nota nel resoconto 67.
- I sistemi di `Game` sono spenti (`enabled = false`) finché non c'è una partita: un test che usa `Game` chiama
  `Game.new_game(...)` e alla fine `Game.stop_game(false)`; non sostituire mai i sistemi di `Game.sim` con finti.

## 7. Partita intera e controllo a occhio (integrazione, resoconto 29)

- `scripts/bot_player.gd` (`BotPlayer`): giocatore automatico sui sistemi VERI, tempo simulato a passi diretti.
  `tests/test_playthrough.gd` lo usa per i criteri M4 (Cap. I in 60-90 min, prima Cassa ≤ 15 min, nessun sistema prima
  dello sblocco, tick < 50 ms, offline 24 h < 1 s) e stampa i tempi di ogni missione (`BOT_LOG=1` per il diario).
  Se cambi quantità o ricompense delle missioni, rilancialo.
- `scripts/capture_tour.gd`: giro fotografico della prima esperienza (PNG + testi delle voci grigie). Linux:
  `xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path game --rendering-driver opengl3 -s res://scripts/capture_tour.gd -- <cartella> it`;
  su Windows lo stesso comando senza `xvfb-run …` (si apre una finestra).
- `scripts/capture_qa_b.gd`: catture QA delle schermate del gruppo B in stati realistici (bot + aiuti di prova), it/en, 1280×720 e 1920×1080, Rullo a metà corsa/rivelazione; stampa `OVERFLOW`/`MINW` per i controlli fuori dall'area utile. Argomenti: `-- <cartella> <it|en> <all|id,id> [reuse]` (`reuse` ricarica lo slot salvato dalla prima esecuzione, ~1 min in meno). Resoconto 41.
- `tests/test_integration.gd`: la colla tra i sistemi veri (attrezzi, chiavi, Deposito/Mercato, Tomi, regalo iniziale…).
- **Partita lunga** (resoconto 47): `BotPlayer.long_mode = true` + `step_long = Game._on_long_gap` gioca oltre il Cap. I (Tenuta, Gilda,
  mercenari/spedizioni, Taglie, Fazioni, Contratti, incursioni, Rito) e durante i compiti lunghi "va via" a blocchi di offline vero.
  `tests/test_playthrough_long.gd` stampa tempi per capitolo, ricompense delle ore 5-20, picchi di tick per sistema e offline
  (`BOT_VERBOSE=1` per il diario in tempo reale). `wall_limit_ms` ferma il test se il tempo reale si allunga.
- **Salvataggio dorato**: `tests/golden/save_v0_1_fine_cap1.sav` è stato scritto dalla versione 0.1 (commit a4556ab, bot a fine
  Cap. I). `tests/test_save_endgame.gd` verifica che si carichi e si continui a giocare, più il round-trip di un salvataggio
  di fine partita da 20.000 istanze scritto sul thread. Se cambi la forma di uno stato: migrazione in `SaveCodec` e questo test resta verde.
- `tests/test_integration_final.gd`: eventi senza fonte collegati (Contratti, Affinatura, incursioni, piatti bruciati,
  Capolavoro, classi, Sfida, Prove), Cassa dell'Era, Essenza d'Era, «Contro il Tempo» offline.

## 8. Modalità di gioco (Autarchico, Estremo)

Il gioco ha tre modalità scelte alla creazione e immutabili (`GameState.data.mode`: `normal|autarchic|extreme`). Le regole sono **dati** (`data/mode_rules.json`, generato da `tools/gamedata/meta.py`) e un solo oggetto le legge: `ModeRules` (`src/core/ModeRules.gd`).

- **Chiedi, non confrontare.** Un sistema fa `ctx.mode_rules().market_buy_allowed(id)`, `.orders_enabled()`, `.permadeath()`, `.offline_stops_before_death()`; la UI usa `GameState.mode_rules()`. Mai `if mode == "extreme"` (`tests/test_modes.gd` cerca il confronto nei sistemi). Una regola nuova = un campo nel record della modalità in `meta.py` + un metodo in `ModeRules` + il controllo nel sistema interessato (una riga) + un test.
- **Conseguenze trasversali** (cosa accade alla morte Estrema, titolo e cornice alla creazione): `ModeSystem` (`src/systems/ModeSystem.gd`, sezione di stato `modes`). Chiama metodi pubblici minimi degli altri sistemi (`SkillSystem.reset_level`, `CombatSystem.lose_worn_gear/reset_hero_build`).
- **Salvataggi.** Sezione `modes` nuova: i salvataggi precedenti la ricevono da `default_state` (nessuna migrazione, `SCHEMA_VERSION` invariato); un `mode` sconosciuto torna `normal` al caricamento (`GameState.replace`).
- **Simulatore.** `tools/balance_sim.py` §12 controlla Rito/prima Stella/Rifondazione in Autarchico e il costo di una morte Estrema (30-70% della prima salita). Testi: `localization/parts/modes.csv`.
## 8. Tema UI e telai (resoconto 62)
- **Telai** (`assets/ui/frames/*.png` + `frames.json`): generati da `python tools/make_ui_frames.py` (Pillow, deterministico, pixel esatti;
  `--check` lo verifica ed è in `check_all.py`). Sono disegni nuovi, non PNG d'arte. Dopo averli cambiati:
  `godot --headless --path game --import` e poi `godot --headless --path game -s res://scripts/build_theme.gd`.
- **Temi** (`src/ui/theme/`): `main_theme.tres` (globale, accento ottone = Città) e `accent_skills|adventure|progress.tres`
  (solo le variazioni che cambiano con la sezione). Sono file generati da `scripts/build_theme.gd`: non si modificano a mano.
  `MainScreen.show_screen` assegna `UiKit.accent_theme(sezione)` al pannello del contenuto, quindi titoli, sezioni, card e barre
  prendono oliva / ruggine / viola senza override locali.
- **Variazioni**: TitleLabel (placca), BrandLabel, SectionLabel, MutedLabel, MonoLabel, NumberLabel, WindowTitle, AccentButton, SidebarButton,
  TopBarPanel, ContentPanel, LogPanel, SidebarPanel, CardPanel, RaisedPanel, InsetPanel, BackdropPanel, SearchField, Card<Rarità>, Slot<Rarità>.
  Rarità riquadri: `UiKit.rarity_variation(rarity, big)`; barre tinte: `UiKit.tinted_fill(color)`; stati vuoti: `UiKit.empty_state(kind, key)`.
- **Catture**: `scripts/capture_ui.gd` (menù iniziale, slot, galleria dei controlli, sezioni/rarità/finestra) e `scripts/capture_qa_b.gd`.
## 8. Effetti visivi (`src/ui/fx/`, resoconto 61)

Solo presentazione. Si usa la facciata statica `Fx` (posizioni globali): `Fx.number`, `Fx.hit`, `Fx.burst(preset, …)`, `Fx.ring`, `Fx.reveal(rect, rarità)` (SOLO dopo che l'esito è noto), `Fx.fly`/`Fx.coins`, `Fx.shake`, `Fx.glow_pulse`/`Fx.breathe`, `Fx.shine`, `Fx.number_tick`, `Fx.banner`, `Fx.ceremony`. Tutto rispetta `Fx.level()` (2 pieni · 1 «Effetti: ridotti» · 0 «riduci animazioni») e i limiti dei pool. Galleria: `res://scripts/fx_gallery.tscn`; dal vivo: `capture_fx_live.tscn`; test `tests/test_fx.gd`.

## 9. Modalità Amici (coop senza rete) e stato fuori dal salvataggio (COOP-1)

Tutto il codice sta in `src/coop/` (modulo isolato: `CoopSystem`, `CoopSheet`, `CoopCodec`, `CoopSim`, `CoopWeekly`, `link/`), la schermata
in `src/ui/screens/CoopScreen.*`, i testi in `localization/parts/coop.csv`, i numeri in `data/coop_rules.json` (generato da
`tools/gamedata/coop.py`). Formati e protocollo: `docs/audit_2026-10-22/69_PROTOCOLLO_COOP.md`. Agganci nel resto del gioco (tutti minimi):
una riga in `SystemRegistry`, una in `ScreenRegistry`, e in `EndgameCombat` i ganci «COOP-1» (squadra delle Incursioni, effetti alla Breccia,
alleati dei Boss mondiali, vittoria) che non fanno nulla se il sistema `coop` non c'è.

- **Stato coop separato e additivo**: sezione `coop` del salvataggio personale, nessun bump di `SCHEMA_VERSION`; mai oggetti, valute o
  Deposito dentro. Niente scambi, regali o Casse in comune (regola 5): lo controlla `tests/test_coop_ethics.gd`.
- **REGOLA «contatori fuori dallo stato»**: una variabile privata di un sistema (accumulatore, cache, contatore) **non deve influire
  sull'evoluzione dello stato**; se influisce, va nello stato e quindi nel salvataggio. I contatori e le cache che restano fuori
  (per esempio `CoopSim._cache`, `_self_cache`) devono poter essere azzerati in qualsiasi momento senza cambiare nessun risultato, e
  **non vanno mai nei salvataggi condivisi** (quelli di gilda della fase 2): lì viaggiano solo comandi, istantanee e identificativi
  idempotenti. Prova: `tests/test_coop_save.gd::test_nulla_fuori_dallo_stato_influenza_il_risultato`.
- **Niente tempo reale nei sistemi**: l'istante UNIX (UTC) entra dall'interfaccia come argomento (`import_code(text, now)`,
  `weekly_run(now)`, `refresh(now)`); i sistemi non chiamano `Time`/`OS`.
- **Rete**: nessuna in questa fase. `CoopLink` (astratto) e `LocalFileLink` (cartella condivisa, per le prove) sono la
  predisposizione per `EnetTransport`/`SteamTransport`; nessun `await` nei sistemi, si interroga con `poll()`.
- Per provarlo: `-gtest=res://tests/test_coop_codes.gd` (e `_companions`, `_weekly`, `_save`, `_transport`, `_ethics`, `_ui`).
## 9. Feedback per l'Alfa (resoconto 68)
Tutto in `src/feedback/` + autoload `Feedback`; nessuna rete, nessun sistema di gioco toccato. `AppInfo` (versione da `version.json`, novità da `changelog.json`; `make_release.py` li tiene allineati a `project.godot`), `ErrorLog` (user://logs/vaultfall*.log, ultimi 5 avvii, 256 KB ciascuno), `ReportBuilder`/`ReportDialog` (ZIP «Segnala un problema»), `SessionStats` (opt-in `stats_opt_in`, spento di default), `DevTools`/`DevMenu` (F10: solo build di debug o `VAULTFALL_DEBUG=1`), `PauseMenu` (Esc). Per fornire al ZIP le ultime righe del registro, `MainScreen.add_log` chiama `Feedback.record_game_line`. Test: `tests/test_feedback.gd`. Testi: `localization/parts/feedback.csv` (prefisso `UI_FB_`).

## 10. Manuale in gioco e icona «?» (resoconto 74)
- **Pagine**: `src/ui/screens/ManualCatalog.gd` (elenco, gruppi, mappa schermata -> pagina), `ManualPages.gd` (costruzione del testo), `ManualFacts.gd` (le righe «I numeri», riempite SOLO da dati e `Formulas`), `ManualScreen.gd/.tscn` (indice, ricerca, pagina). Testi: `localization/parts/manual2.csv` (prefisso `UI_MAN2_<PAGINA>_`: `T` titolo, `WHAT`, `HOW_n`, `F_n`, `TIPS`, `DONT`, `JOKE`). Una pagina strutturata ha sempre queste parti, nell'ordine; la battuta sta in fondo e non sostituisce l'istruzione (`docs/audit_2026-10-22/26_BIBBIA_COMICA.md`).
- **Aggiungere una pagina** (es. per un sistema nuovo): una riga in `ManualCatalog.GROUPS` e in `PAGES`; le chiavi nel CSV; se ha numeri, un caso in `ManualFacts.params` che restituisce un `Dictionary` per riga `F_n` con i segnaposto del CSV (mai numeri scritti a mano); se ha una schermata, la riga in `SCREEN_PAGES`. `tests/test_manual2.gd` fallisce se manca una parte, una riga di numeri o la traduzione IT/EN.
- **Icona «?»**: `MainScreen._build_help_button` la aggiunge alla barra in alto (dopo «Impostazioni»), quindi c'è in OGNI schermata; apre `ManualCatalog.page_for_screen(current_id)`. F1 (`OverlayHost`) fa lo stesso. Una schermata nuova NON deve fare nulla: basta la riga in `SCREEN_PAGES` (altrimenti si apre «Come si gioca»). Le mansioni `skill:<id>` aprono «Mansioni», tranne `farming` e `alchemy`.
- **Wiki e guide**: `tools/wiki_pages4.py` rigenera la pagina «Il Manuale di gioco» e le pagine Modalità, Compendio, Amici e Coop e Guida rapida dagli stessi CSV e da `docs/giocatori/`.
