# 17 — Architettura tecnica (Godot 4, GDScript)

> Documento vincolante per Claude Code. Le scelte qui sono **decise**: non cambiarle senza aggiornare questo file e `CLAUDE.md`.

## 1. Scelte di base

| Tema | Scelta |
|---|---|
| Motore | **Godot 4.7.2 stabile** (18/8/2026; edizione standard, non .NET). Passare a 4.8 solo quando è stabile **e** GUT e GodotSteam la supportano. Se in M8 non esiste GodotSteam per 4.7.x, ripiego: Godot 4.6.2 + GodotSteam 4.18.1 (docs/23 §6) |
| Linguaggio | **GDScript tipizzato** (`var x: int`, funzioni con tipi di ritorno). Niente C# (semplifica export e build) |
| Paradigma | **Logica separata dalla UI.** I sistemi di gioco sono classi pure (`RefCounted`) che operano su uno stato serializzabile; la UI osserva tramite segnali |
| Dati | JSON in `res://data/` (copiati da `data/` del pacchetto), caricati all'avvio in dizionari indicizzati per id. **Nessun numero di bilanciamento scritto nel codice** |
| Tempo | Passo fisso di simulazione **0,1 s** con accumulatore; l'offline usa lo stesso codice in modalità rapida |
| Salvataggio | JSON compresso (gzip) in `user://saves/`, versione di schema, migrazioni, 3 backup a rotazione, esportazione/importazione testo |
| Test | **GUT 9.7.0** (certa per Godot 4.7; la 9.7.1 non è confermata: verificare in T-0.2; ramo `godot_4_7`, dallo zip di GitHub: la Libreria degli Asset ha solo la 9.6.1 per Godot 4.6) in modalità headless + script Python di dati/bilanciamento |
| Steam | GodotSteam (GDExtension) dietro un **wrapper** che non fa nulla se Steam non è presente |
| Risoluzione | Base logica **1280×720** (`display/window/size/viewport_width/height`), finestra di sviluppo 1600×900, `stretch/mode = canvas_items`, `stretch/aspect = expand`, **`stretch/scale_mode = fractional`** (scala automatica, F5; il documento originale diceva `integer`): 1080p → ×1 con più spazio, 1440p → ×2, 4K → ×3, Steam Deck 1280×800 → ×1; così la pixel art resta nitida ovunque (docs/20 §5). Filtro predefinito `Nearest`, `snap_2d_transforms_to_pixel` attivo. Scala dell'interfaccia regolabile dall'utente (75–150%) per chi gioca a 1080p su schermi grandi |
| Cartella utente | `application/config/use_custom_user_dir = true`, `custom_user_dir_name = "VAULTFALL"` → salvataggi in `%APPDATA%\VAULTFALL\saves\` (Windows) e `~/.local/share/VAULTFALL/saves/` (Linux): percorsi stabili per Steam Cloud (docs/23 §7.2) |

## 2. Struttura delle cartelle (progetto Godot in `game/`)

```
game/
  project.godot
  addons/                 # gut/, godotsteam/ (GDExtension)
  data/                   # COPIA di ../data (script tools/sync_data.py o copia manuale)
  assets/
    icons/{items,skins,relics,crates,skills,abilities,talents,achievements,estate,factions,cosmetics}/
    portraits/{monsters,npcs,classes,pets}/
    banners/{zones,dungeons,raids}/
    ui/                   # cornici 9-slice, pulsanti, barre
    fonts/  audio/{music,sfx,ui}/  shaders/palette_swap.gdshader
    _templates/           # modelli grigi per le ricolorazioni (con un file vuoto .gdignore: Godot non li importa)
    _style/               # foglio di stile di riferimento (docs/20 §6 e §0), anche qui .gdignore
                          # NB: i segnaposto (tools/make_placeholders.py) stanno negli STESSI percorsi dell'arte vera
                          #     e vengono sostituiti dai lotti; make_placeholders non sovrascrive mai un file esistente
  src/
    autoload/             # singleton registrati in project.godot (stato M1: vedi §3)
      EventBus.gd  DataRegistry.gd  Clock.gd  Settings.gd  Loc.gd  GameState.gd  Rng.gd  Modifiers.gd
      SaveService.gd  Game.gd   (+ SteamService.gd  AudioService.gd in M8)
    core/                 # utilità pure (RefCounted, testabili senza scena)
      Formulas.gd  NumberFormat.gd  ModifierStack.gd  RngStreams.gd  FixedStepClock.gd  SaveCodec.gd
      GameSystem.gd  SystemContext.gd  Simulation.gd
    systems/              # logica di gioco pura (RefCounted), nessun nodo. Aggancio: SystemRegistry.gd (una riga)
      SkillSystem.gd  CraftingSystem.gd  FarmingSystem.gd  ThieverySystem.gd
      CombatEngine.gd  CombatSystem.gd  DungeonSystem.gd  RaidSystem.gd  RiftSystem.gd  WorldBossSystem.gd
      CrateSystem.gd  TradeUpSystem.gd  RefinerySystem.gd  CollectionSystem.gd
      MarketSystem.gd  ShopSystem.gd  OrdersSystem.gd  FactionSystem.gd
      EstateSystem.gd  MercenarySystem.gd  ExpeditionSystem.gd  ApprenticeSystem.gd
      QuestSystem.gd  ContractSystem.gd  BountySystem.gd  AchievementSystem.gd
      PrestigeSystem.gd  ConstellationSystem.gd  EraSystem.gd  PetSystem.gd  EventSystem.gd
      OfflineSimulator.gd  UnlockSystem.gd  InventorySystem.gd  EquipmentSystem.gd  StatsSystem.gd
    ui/
      start/StartScreen.tscn (menù iniziale, scena principale)   GameScreen.gd (base)   ScreenRegistry.gd (registro voci)
      main/MainScreen.tscn (layout §2 di docs/16)
      screens/  (una scena per schermata: SkillScreen, CraftingScreen, CombatScreen, HeroScreen, BankScreen,
                 CrateHallScreen, MarketScreen, EstateScreen, GuildScreen, QuestScreen, PrestigeScreen,
                 CompendiumScreen, SettingsScreen, WelcomeBackDialog, NewGameScreen)
      components/ (docs/16 §4)
      theme/main_theme.tres
  tests/                  # test GUT: test_formulas.gd, test_modifiers.gd, test_crates.gd, test_save.gd, ...
```

## 3. Autoload (singleton) e responsabilità

| Autoload | Responsabilità |
|---|---|
| `DataRegistry` (era "GameData") | carica tutti i JSON, costruisce indici (`items`, `actions_by_skill`, `monsters`, …), valida i riferimenti in debug, espone getter tipizzati. Sola lettura |
| `GameState` | **unico** stato mutabile del giocatore (dizionari/array serializzabili); niente logica |
| `EventBus` | segnali globali (§6) |
| `Clock` | accumulatore a passo fisso, velocità di debug (×1/×10/×100), ora reale (`Time.get_unix_time_from_system()`) |
| `SaveService` | salvataggio automatico (30 s + uscita + eventi importanti), slot, backup, migrazioni, export/import |
| `Modifiers` | registro delle fonti di modificatori e calcolo dei totali (docs/14 §4) |
| `Rng` | flussi RNG separati e salvati: `loot`, `crates`, `combat`, `market`, `world` (`RandomNumberGenerator` con seed/state) |
| `Loc` | `Loc.t(dict)` per i testi `{it,en}` dei dati + `tr()` per le stringhe di interfaccia (CSV) |
| `SteamService` | inizializzazione Steam, imprese, statistiche, classifiche, rich presence, overlay; *no-op* senza Steam |
| `Settings` | impostazioni utente (`user://settings.cfg`) |
| `AudioManager` | riproduttore audio (bus, musica a contesti con crossfade, effetti, ducking, silenzio offline); legge i file generati da `tools/make_audio.py` (docs/21 §5) |
| `Feedback` | strumenti dell'Alfa (`game/src/feedback/`): versione e Novità (`AppInfo`, `version.json`, `changelog.json`), registro errori ruotato (`ErrorLog`, `user://logs/vaultfall*.log`), «Segnala un problema» (`ReportBuilder`/`ReportDialog`, ZIP locale), statistiche locali opt-in (`SessionStats`), menù di pausa (Esc), strumenti F10 (`DevTools`/`DevMenu`, solo debug o `VAULTFALL_DEBUG=1`). Nessuna classe di rete (lo vieta `test_feedback.gd`) |
| `Game` | orchestratore: possiede la `Simulation` (sistemi di `SystemRegistry`), la collega a `Clock`, crea/carica/chiude le partite, prepara lo snapshot per `SaveService` |

Ordine degli autoload (`project.godot`, 23/10/2026): EventBus, DataRegistry, Clock, Settings, Loc, GameState, Rng, Modifiers, SaveService, Game, AudioManager, Feedback. `PlatformService` (Steam opzionale, no-op senza estensione) è l'ultimo autoload dalla 1.0. **`Fx` non è un autoload**: è la facciata statica del modulo effetti `game/src/ui/fx/` (FxHost su un CanvasLayer 90, pool fisso di forme e particelle, nessun numero di bilanciamento, inattivo se non c'è nulla; con «riduci animazioni» gli effetti si spengono). Non esiste un `DiagLog`: la diagnostica è `ErrorLog` + `ReportBuilder` dentro `Feedback`.

**Sistemi registrati in `SystemRegistry`** (ordine di tick, 23/10/2026): `BankSystem`, `SkillSystem`, `CombatSystem` (con gli aiutanti `CombatSim`, `HeroBuild`, `EndgameCombat`: Incursioni, boss mondiali, Breccia), `BountySystem`, `CrateSystem`, `QueueSystem`, `ApprenticeSystem`, `FarmingSystem`, `EstateSystem`, `MarketSystem`, `MercenarySystem`, `ExpeditionSystem`, `SecretSystem`, `BuffSystem`, `PotionSystem`, `PrestigeSystem` (Stelle, Rito, Polvere, Costellazioni, Rifondazione, Ere, Prove), `QuestSystem`, **`ContractSystem`** (Commesse giornaliere/settimanali a gettoni, regola dei 7 giorni), `CompendiumSystem` (Imprese, Titoli, Famigli, cornici), **`ModeSystem`** (Autarchico ed Estremo; regole come dati in `mode_rules.json`, lette da `ModeRules`; i sistemi chiedono `ctx.mode_rules()`, mai `if mode ==`), **`SeasonalEventSystem`** (eventi stagionali, T-11.3), `UnlockSystem`. **Non ancora esistenti:** `CompanionSystem`, `CoopSession`/`NetService` e i sistemi di gilda (coop: docs/01 §9, studio 60 §3.2; nomi e cartelle previsti `src/coop/`, `src/net/`, `src/autoload/NetService.gd`; chiave di stato `coop` e prefisso di modificatori `guild:` riservati).

**Versione di schema attuale: `SaveCodec.SCHEMA_VERSION = 5`.** Migrazioni registrate: `4 → 5` (`migrate_v4_to_v5`, UI F17): la sezione `bank` riceve `tabs = []`, `tab_of = {}`, `next_tab = 1` se mancano o hanno il tipo sbagliato (additiva e idempotente; nessuna quantità né istanza cambia; `BankSystem.from_state` ripulisce schede oltre `constants.bank.ui.max_tabs`, id doppi, nomi non validi, icone sconosciute, assegnazioni orfane o verso l'Armeria, con una riga nel Registro; `bank.tabs_intro_done` lo completa `default_state`); `3 → 4` (`migrate_v3_to_v4`, UI F13): sezione additiva `time_push`; `2 → 3` (`migrate_v2_to_v3`, QA82 Q82-1): `crates.draw_seed` (derivato da `rng.master`) e `crates.draw_n` (contatori di estrazione per cassa, estrazione indicizzata anti save-scum, docs/09 §6); `1 → 2` (`migrate_v1_to_v2`, FIX-PROGRESSIONE): la sezione `contracts` riceve `daily`, `weekly`, `tokens`; le sezioni morte `relics` e `settings_snapshot` escono dallo stato. Idempotente, non tocca nessun progresso. Le sezioni nuove aggiunte dopo (`bounty`, `mode`, `seasonal`, campi di `hero` per Incursioni/boss/Breccia) non hanno richiesto salto di schema: i sistemi completano i campi mancanti da `default_state`/`from_state`. Il salvataggio JSON dovrà passare a piena precisione (`JSON.stringify(data, "", false, true)`) come fase 0 del coop. Salvataggio dorato di riferimento: v0.1.
I sistemi NON usano gli autoload: ricevono un `SystemContext` (`ctx.data`, `ctx.modifiers`, `ctx.rng`, `ctx.events`,
`ctx.state`, `ctx.get_system(id)`). Guida pratica per aggiungere sistemi e schermate: `game/README_SISTEMI.md`.

## 4. Stato del gioco (forma del salvataggio)

```gdscript
# GameState.data (salvato così com'è, + "schema_version" e "saved_at_unix")
# NB (R-SAV-7/8): seed e state RNG sono STRINGHE (uint64); dopo il load i tipi si normalizzano.
{
  "schema_version": 1, "saved_at_unix": 0, "created_at_unix": 0, "mode": "normal",   # normal|autarchic|extreme   # scelta alla creazione, immutabile; regole in data/mode_rules.json (ModeRules, docs/05 §7)
  "rng": {"loot": {"seed": "0", "state": "0"}, "crates": {...}, "combat": {...}, "market": {...}, "world": {...}},
  "skills": {"mining": {"xp": 0, "level": 1, "record_level": 1, "stars": 0, "perks": {"10": "a"}, "unlocked": true}},
  "mastery": {"mine_copper": {"xp": 0, "level": 1}},
  "bank": {"stacks": {"log_pine": 120}, "instances": [{"uid": "i_000123", "def": "sword_iron", "quality": "fine", "sockets": ["glyph_fury_1"], "rank": 0, "locked": false}], "slots_bought": 0, "overflow_stacks": {}, "overflow_instances": [],
           "tabs": [{"id": "t_0001", "name": "Forgia", "icon": "ore_copper", "sort": {"id": "recent", "desc": true}}],   # UI F17, schema 5
           "tab_of": {"s:ore_copper": "t_0001", "u:i_000124": "t_0001"}, "next_tab": 2, "tabs_intro_done": true},
  "equipment": {"weapon": "i_000123", "offhand": null, "ammo": {"def": "arrow_pine", "qty": 400}, "...": null, "tools": {"woodcutting": "i_000044"}},
  "wardrobe": {"weapon": "i_000300"}, "relics": ["i_000301"],
  "hero": {"class": "warrior", "spec": "berserker", "attrs": {"str": 40, "dex": 5, "int": 5, "vit": 20}, "talents": {"warrior_toughness": 3}, "abilities": ["cleave","battle_cry"], "food": ["food_bleak"], "hp": 0},
  "activity": {"type": "skill", "action": "wc_pine", "progress_s": 1.2} ,      # oppure {"type":"combat","zone":..,"monster":..} ecc.
  "queue": [], "apprentices": [{"action": "mine_iron", "progress_s": 0.0}],
  "farming": {"garden": [{"crop": "farm_potato", "planted_at": 0, "ready_at": 0}], "orchard": []},
  "crates": {"pity": {"zone": 0, "skill": 0}, "opened": 0, "collections": {"collection_millbrook": ["skin_millbrook_01"]}},
  "market": {"sold_recent": {"log_pine": 120.5}, "trend": {"log": 1.03}, "history": {}, "gazette": {"event": "fish_glut", "until": 0}},
  "orders": [], "factions": {"merchant_league": 1200},
  "estate": {"buildings": {"sawmill": {"level": 12, "product": "log_cedar", "settlers": 12}}, "settlers": 41, "pantry": 2310, "storage": {}, "prosperity": 0, "partners": 0},
  "mercenaries": [], "expeditions": [],
  "quests": {"active": ["main_c2_q4"], "progress": {"main_c2_q4": [12, 3, 0]}, "done": ["main_c0_q1"]},
  "contracts": {"daily": [], "weekly": [], "tokens": 0},
  "prestige": {"stardust": 0, "constellations": {"c_vi_xp": 3}, "era_max": 1, "era_current": 1, "trials": {}},
  "pets": ["pet_skill_mining"], "achievements": ["ach_first_star"], "titles": [], "stats": {"kills": 0, "actions": {}, "gold_earned": 0},
  "unlocks": ["skill:woodcutting", "feature:crates"], "settings_snapshot": {}
}
```

Aggiunte di M1 (2026-10-22): `"currencies": {"gold": 0}` (oro; le altre valute sono oggetti in `bank.stacks`),
`"stats.playtime_s"` (secondi simulati giocati, per il menù degli slot), `"rng.<flusso>"` + `"rng.master"`,
`"buffs": {"active": {id: {"remaining_s", "mods"}}}` (BuffSystem). Ogni sistema possiede una sezione (`state_key`)
e ne dichiara i campi interi (`int_paths`) per la normalizzazione R-SAV-8 (`SaveCodec.normalize`).

Aggiunta TUTORIAL (2026-10-23): `"tutorial": {"v": 1, "started": false, "off": false, "seen": [id passo]}` (TutorialSystem). Sezione
additiva: un salvataggio senza `tutorial` riceve il valore iniziale e `begin()` dà per visti i passi base e quelli dei sistemi già
sbloccati; nessuna migrazione di schema. I passi stanno in `src/tutorial/TutorialCatalog.gd`, la parte visiva in `TutorialDirector`.

**R-ARC-1:** nessun riferimento a nodi o risorse Godot nello stato (solo tipi JSON). **R-ARC-2:** id stabili; mai salvare indici di array dei dati.

## 5. Ciclo di simulazione

```gdscript
# Clock.gd (autoload)
const STEP := 0.1
var _acc := 0.0
func _process(delta: float) -> void:
    _acc += delta * speed
    var steps := 0
    while _acc >= STEP and steps < 50:       # protezione da salti lunghi (lag): oltre si usa l'OfflineSimulator
        _acc -= STEP
        Game.tick(STEP)                       # Game = orchestratore: chiama i sistemi in ordine fisso
        steps += 1
```

Ordine fisso dei sistemi per tick: `Activity (skill|combat) → Apprentices → Farming → Estate → Expeditions → Buffs/Timers → Quests/Achievements (eventi accodati) → Unlocks`. La UI si aggiorna a **10 Hz** al massimo (non ogni frame).

## 6. Segnali principali (`EventBus`)

`action_completed(action_id, outputs)` · `xp_gained(skill, amount)` · `level_up(skill, level)` · `item_gained(def_id, qty, source)` · `item_removed(def_id, qty)` · `crate_found(crate_id, source)` · `crate_opened(result)` · `monster_killed(monster_id, drops)` · `player_died(cause)` · `quest_progress(quest_id, objective_index, value)` · `quest_completed(quest_id)` · `unlocked(token)` · `pet_found(pet_id)` · `achievement_unlocked(id)` · `star_gained(skill)` · `estate_changed()` · `expedition_finished(id, result)` · `market_event(event_id)` · `notification(kind, text, data)` · `save_completed(ok)`.
Nel codice il segnale `notification` si chiama **`notice`** (Node ha già il metodo `notification()`); altri segnali
di servizio (ciclo di vita, tempo, impostazioni, navigazione) sono elencati in `src/autoload/EventBus.gd`.

Le missioni e le imprese ascoltano questi segnali (mai il contrario).

## 7. Formule (`Formulas.gd`)

Porta **1:1** le funzioni di `tools/gamedata/core.py` e di `tools/balance_sim.py` (combattimento). Ogni funzione ha un test GUT con i valori di riferimento calcolati dagli script Python (`tools/export_reference_values.py` → `tests/reference_values.json`, docs/26). Esempi:

```gdscript
static func xp_to_next(level: int) -> int:
    return int(floor(C.xp.base * pow(C.xp.growth, level)))
static func hit_chance(acc: float, eva: float) -> float:
    if eva <= 0.0: return C.combat.hit_max
    return clampf(C.combat.hit_base * sqrt(acc / eva), C.combat.hit_min, C.combat.hit_max)
static func damage_reduction(armor: float, attacker_level: float) -> float:
    if armor <= 0.0: return 0.0
    var k := C.combat.dr_k.a * pow(C.combat.dr_k.r, attacker_level)
    return minf(C.combat.dr_cap, armor / (armor + k))
```

(`C` = `DataRegistry.constants`.) Implementazione reale: `Formulas.configure(constants, extras)` all'avvio, poi
funzioni con le stesse firme di core.py (`Formulas.xp_to_next(level)`); i coefficienti che core.py usa ma che
constants.json non esporta ancora stanno in `Formulas.PENDING_CONSTANTS` (OPEN_QUESTIONS F-1).

## 8. Localizzazione

- Testi dei contenuti: nei JSON come `{"it": "...", "en": "..."}` → `Loc.t(item.name)` sceglie la lingua attiva (fallback EN).
- Testi d'interfaccia: `game/localization/ui_strings.csv` (colonne `keys,en,it`) importato da Godot come traduzione; nel codice solo `tr("UI_BANK_TITLE")`.
- Nuove lingue: aggiungere una colonna al CSV; per i testi dei dati `python tools/export_strings.py` (già pronto) crea `build/strings_for_translation.csv` per i traduttori.
- `python tools/sync_data.py` copia anche `localization/ui_strings.csv` in `game/localization/`.

## 9. Steam (wrapper)

> **Stato 29/10/2026 (1.0):** il wrapper esiste come **`PlatformService`** (autoload in `game/src/platform/`, ultimo della lista) con backend nullo di default e `SteamBackend` (GodotSteam, opzionale). Implementati: imprese (tabella `steam_achievements`), Rich Presence testuale, Cloud come copia dei file `slot_N.sav` (`CloudSync`), configurazione in `game/app_config.json`. NON implementati: statistiche, classifiche. Il cloud è via API, non Auto-Cloud. Dettagli: `docs/review_1_0/14_STEAMWORKS_INTEGRAZIONE.md`. Il nome `SteamService` qui sotto è quello della specifica originale.

- `SteamService.init()` all'avvio: se `Engine.has_singleton("Steam")` e `Steam.steamInitEx()` va a buon fine → attivo; altrimenti *no-op* (il gioco funziona identico fuori da Steam).
- **Imprese:** `unlock(api_name)` con coda e `storeStats()` raggruppato (max 1 al minuto).
- **Statistiche:** `TOTAL_LEVEL`, `STARS_TOTAL`, `CRATES_OPENED`, `ERA_MAX`, `RIFT_BEST_FLOOR`, `PLAYTIME_H`.
- **Classifiche:** `RIFT_BEST_FLOOR`, `TOTAL_LEVEL`, `STARS_TOTAL` (punteggi plausibili: si inviano solo se coerenti con le statistiche locali, es. piano ≤ piano massimo registrato nel salvataggio).
- **Steam Cloud:** Auto-Cloud sulla cartella `user://saves/` (configurazione in Steamworks, docs/23). In caso di conflitto è Steam a chiedere quale copia tenere: per aiutare la scelta ogni slot mostra nel menu *data dell'ultimo salvataggio, ore giocate e livello totale*; i backup `bak1..3` restano locali.
- **Rich presence:** "Taglialegna Lv 54", "Combatte nell'Archivio Sommerso".

## 10. Salvataggi (REGOLE)

- **R-SAV-1:** file `user://saves/slot_N.sav` (JSON compresso gzip). Scrittura atomica: si scrive `slot_N.sav.tmp`, si verifica la rilettura, poi si rinomina; si mantengono `slot_N.sav.bak1..3` (solo locali: Steam Cloud sincronizza solo `slot_*.sav`), ruotati al massimo ogni 10 minuti reali; in più `slot_N.sav.pre_vN` (copia del file prima della migrazione, una per versione di schema, mai sovrascritta) e `slot_N.sav.day_AAAA-MM-GG` (ultime 7 copie giornaliere). Decisioni: `docs/OPEN_QUESTIONS.md` F-3, S-1…S-4.
- **R-SAV-1b (QA120):** `load_slot` prova nell'ordine `slot_N.sav`, `slot_N.sav.tmp` (scrittura completa non ancora rinominata: chiusura brusca durante la rotazione; un .tmp parziale non si decodifica e si salta; solo se esiste almeno un backup: un .tmp orfano senza storia non è un salvataggio), `.bak1..3`; `slot_exists` è vero anche se manca il principale ma resta un backup. Se non si carica il principale, il giocatore lo legge in un avviso con l'età della copia.
- **R-SAV-2:** `schema_version` + funzioni `migrate_v1_to_v2(data)` ecc. in `SaveCodec.gd` (registrate in `SaveCodec.migrations()`; `SaveService.gd` le applica al caricamento); un salvataggio più nuovo del gioco non si apre (messaggio).
- **R-SAV-3:** salvataggio automatico ogni 30 s, all'uscita, dopo eventi importanti (apertura ★, Stella, Rifondazione, missione).
- **R-SAV-4:** export/import come stringa Base64 (gzip+JSON) dalle Impostazioni.
- **R-SAV-5:** 3 slot; modalità scelta alla creazione.
- **R-SAV-6:** salvataggi della **demo** compatibili con il gioco completo (stesso schema).
- **R-SAV-7 (numeri nel JSON, T-P3):** Godot legge ogni numero JSON come `float` (double): sopra 2^53 gli interi perdono precisione. Quindi **`seed` e `state` di ogni flusso RNG (uint64) si salvano come STRINGHE decimali** (`"seed": "12345678901234567890"`) e si riconvertono con `String.to_int()` / una funzione `Rng.parse_u64()` che gestisce anche i valori oltre int64. Lo stesso vale per qualunque intero che possa superare 2^53 (monete di Tenuta oltre il livello ~300, contatori cumulativi): o stringa, o `float` dichiarato come tale.
- **R-SAV-8 (tipi dopo il load, T-P3):** dopo `JSON.parse` il `SaveService` esegue una passata di normalizzazione sui campi dichiarati interi (livelli, quantità, tempi, indici): `int(valore)` solo se `valore == floor(valore)`; altrimenti il salvataggio è segnalato come corrotto. Mai usare un `float` letto dal file come indice o come chiave di dizionario. Test previsto in S2 (round-trip con 20.000 istanze, seed uint64 e interi grandi).

## 11. Prestazioni (obiettivi)

- ≤ 2 ms/frame di logica a velocità ×1; offline 24 h in ≤ 1 s; avvio ≤ 3 s (caricamento JSON ≤ 300 ms: valutare la conversione dei JSON in `.res` binari in fase di build se servisse).
- Liste lunghe (Deposito con 600+ voci, Album) virtualizzate; icone in un atlante o caricate in modo pigro con cache.
- **Gioco in secondo piano** (lo si tiene aperto per ore: è la prima causa di lamentele tecniche nei giochi del genere, docs/02): `OS.low_processor_usage_mode = true` sempre; quando la finestra perde il focus (`NOTIFICATION_APPLICATION_FOCUS_OUT`) `Engine.max_fps = 10` e aggiornamento della UI a 2 Hz, al ritorno 60 fps e 10 Hz. La simulazione a tick **non** rallenta (il tempo è misurato, non contato in frame). Obiettivo: ≤ 3% di CPU con la finestra in secondo piano o ridotta a icona.
- **Regole di prestazione per la UI (resoconto 100):** (1) ogni ridisegno rifà tutto il canvas, quindi nessuna animazione continua a 60 Hz per un solo elemento: barre a 30 Hz (`SmoothBar`), ticker a 20 Hz (`CityStrip`), respiri e lampeggi a gradini con `UiAnim.color_loop` (il motore ignora un `modulate` uguale al precedente); (2) in secondo piano (`Clock.focused == false`) barra, ticker, respiri ed effetti stanno fermi (`Fx.level() == 0`) e la schermata corrente non ha `_process`/tween (`MainScreen._host.process_mode = DISABLED`); (3) Impostazioni «Fotogrammi al secondo» (`fps_cap` 60/30, `Clock.set_focus_fps`); (4) le schermate con molte righe si costruiscono a fette (`GameScreen.sliced_builds`, `ROWS_PER_SLICE`; solo nel gioco vero, nei test l'apertura resta sincrona) e ogni `refresh` tollera le righe non ancora costruite; (5) `ScreenWarmup` carica da un thread le scene delle schermate sbloccate, una ogni 0,4 s, per togliere la compilazione degli script dalla prima apertura; `StartScreen` precarica `MainScreen` mentre il giocatore guarda il menù; (6) niente classi nominate negli autoload se servono solo raramente: `Feedback` carica DevTools/DevMenu/PauseMenu/ReportBuilder con `load()` alla prima apertura. Misure ripetibili: `python tools/run_perf.py all` (fixture di 50 h in `game/scripts/perf_fixture.gd`, profilo in `game/scripts/perf_profile.gd`), test in `game/tests/test_perf_ui.gd`.

## 12. Convenzioni di codice

- File e classi `PascalCase`, funzioni e variabili `snake_case`, costanti `UPPER_SNAKE`. `class_name` per i sistemi.
- Nessuna logica nei nodi UI oltre la presentazione; i pulsanti chiamano metodi dei sistemi.
- Ogni sistema ha test unitari; ogni bug corretto aggiunge un test.
- Mai `await` dentro i sistemi (sincroni e deterministici).
- Commenti in italiano o inglese, coerenti per file.

## 13. Sabbia del Custode (UI F13)

Sistema `TimePushSystem` (id `time_push`, sezione di salvataggio additiva `time_push`, schema v4): riserva di tempo (`reserve_s`, tetto `reserve_cap_s`) che un clic spende per far avanzare **solo l'azione in corso**. Tutto in `constants.time_push` (generato da `tools/gamedata/core.py::TIME_PUSH`), formule `Formulas.push_regen/push_spend`.
- **Avanzamento:** `Simulation.tick_subset(ids, dt)` (stesso ordine di `SystemRegistry`, `bank` prima; nessun tick agli altri sistemi; non cambia `stats.playtime_s`, calendario, buff, Orto, Tenuta, spedizioni, mercato). Mai `Clock.set_speed` né `FixedStepClock._acc`: un accumulo oltre 60 s scatterebbe `long_gap` (Bentornato per errore).
- **Coda:** `Game.request_push(n)` → `ClickLimiter.accept(now_usec)` (array circolare, `max_cps`/`window_ms`, solo CPU: il clic oltre il limite si ignora in silenzio, nessuna rilevazione di autoclicker) → `TimePushSystem.request` concede min(riserva libera, `click_s`) per clic in `pending_s` → `Game._process` esegue `drain(max_steps_per_frame, max_cpu_ms_per_frame)` a passi da 0,1 s. La riserva si scala SOLO a passo eseguito; se l'azione finisce la coda si svuota senza scalare. Comando di debug: `Game.debug_push(n)` (solo `OS.is_debug_build()`, senza limitatore).
- **Rigenerazione:** online `regen_online_pct` % del tempo di gioco con un'azione ammessa (non in pausa: il Clock non fa tick); offline `regen_offline_pct` % del Δt contato (R-OFF-1) con la riga «Sabbia ricaricata» del Bentornato (`UI_OFFL_PUSH_ROW`); regalo di sblocco `unlock_gift_s` una volta (`gift_given`).
- **Blocchi:** non sbloccata, Prova, modalità Estrema (`blocked_when`), nessuna azione, attività non ammessa (`allowed_activities`: solo `skill` nella v1; combattimento, dungeon, incursioni, Breccia, boss mondiali, coop no), pausa. Segnali `EventBus.push_changed(reserve_s, cap_s)` (max 10 Hz) e `push_blocked(reason_key)`.
- **Etica (docs/24):** nessun effetto su Casse, estrazioni (seme, id cassa, N), riempitivi, coop, Prove; nessun acquisto, ricarica, regalo ricorrente, serie o impresa «fai N clic»; nessuna telemetria sui clic.

## 14. Deposito: schede, selezione e ricerca (UI F17)

- **Modello** (`BankSystem`, regola 3): `tabs()`, `create_tab/rename_tab/set_tab_icon/set_tab_sort/move_tab/delete_tab`, `tab_key(def, uid)` («s:<def>» / «u:<uid>»), `can_assign`, `assign_to_tab(keys, tab)` (una voce = una scheda; "" = togli), `tab_counts()`, `sanitize_tab_name`, `unique_tab_name`; funzioni pure di ricerca `search_norm/parse_search/search_matches` (compilate con il sistema, non all'apertura della schermata). Limiti in `constants.bank.ui` (`max_tabs`, `tab_name_max`, `tab_of_cap`, `search_debounce_ms`, `sell_confirm_guard_ms`, `tabs_hint_used`), generati da `tools/gamedata/core.py::BANK_UI`.
- **Vendibilità** (un solo punto di verità): `SellRules.block_reason(bank, market, def, uid, market_open)`; `SellRules.collect_picks(...)` produce il piano di una selezione (stessa forma di `collect`, oro = `MarketSystem.quote_many`, quindi anteprima = esito).
- **Interfaccia**: `BankTabsBar` (barra: Risultati, Tutto, Armeria, schede, [+], «Schede ▾»; trascinamento con alternativa da menù e tasti), `BankTabDialog` (finestra nome/icona e, come funzioni statiche, le azioni rare: menù «Sposta in…», conferme, schede suggerite, tasti, vendita a selezione; si carica al primo uso per tenere la costruzione del Deposito nel budget), `SellDialog.setup_selection` (passaggio 2 con guardia), `BankScreen` (selezione unica `_selection`, stato solo UI mai salvato; modalità "select"/"sell" che si spegne in `close()`).
- **Tasti locali**: `ShortcutMap.BANK_TABLE` + `resolve_bank(event)` ([ ] / Ctrl+PgSu/PgGiù, S, V, Maiusc+L, Maiusc+M, O, Ctrl+A, F2, Alt+←/→, Esc a catena), attivi solo con il fuoco nel Deposito; nessun tasto vende o elimina. Gamepad: LB/RB schede, Y Ordina.
- **Coop**: il Deposito (e quindi le schede) non entra mai nel formato di rete (`CoopSheet.FORBIDDEN_KEYS`, `CoopLinkMessage.FORBIDDEN`).

