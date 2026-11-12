extends Node
@warning_ignore_start("unused_signal")
## EventBus (autoload) — segnali globali (docs/17 §6). Nessuna logica qui.
## I sistemi EMETTONO (ctx.events.<segnale>.emit(...)), la UI e i sistemi "osservatori" (missioni, imprese)
## ASCOLTANO. Missioni e imprese ascoltano questi segnali, mai il contrario.
## Per aggiungere un segnale: dichiararlo qui con tipi e una riga di commento, nella sezione giusta.
## NB: il segnale "notification" di docs/17 §6 qui si chiama `notice` (Node ha già un metodo notification()).
## NB: GDScript non verifica i tipi degli argomenti dei segnali a runtime: rispettare le firme.

# ---- gioco (docs/17 §6)
signal action_completed(action_id: String, outputs: Array)
## Versione aggregata per l'offline (N completamenti in un solo segnale: evita decine di migliaia di emissioni).
signal action_batch_completed(action_id: String, count: int, outputs: Array)
signal xp_gained(skill: String, amount: float)
signal level_up(skill: String, level: int)
signal item_gained(def_id: String, qty: int, source: String)
signal item_removed(def_id: String, qty: int)
signal crate_found(crate_id: String, source: String)
signal crate_opened(result: Dictionary)
signal monster_killed(monster_id: String, drops: Array)
## Offline: N uccisioni dello stesso mostro in blocco (drops aggregati [{id, qty}]); stessa semantica di N monster_killed, ma silenzioso (niente suoni).
signal monsters_killed_batch(monster_id: String, count: int, drops: Array)
signal player_died(cause: String)
## Colpo di combattimento, SOLO per audio/effetti (nessuna logica): kind = "hit" | "crit" | "hurt" (subito dall'eroe) | "dodge" (schivata dell'eroe).
signal combat_hit(kind: String)
## Evento generico per gli obiettivi delle missioni (docs/12 §3): kind = tipo di obiettivo ("build", "sell_market", "dungeon"...),
## params = campi da confrontare con l'obiettivo (+ "qty"/"gold"/"floor" per la quantità). Lo ascolta QuestSystem.
signal objective_event(kind: String, params: Dictionary)
signal quest_progress(quest_id: String, objective_index: int, value: int)
signal quest_completed(quest_id: String)
signal unlocked(token: String)
signal pet_found(pet_id: String)
signal achievement_unlocked(id: String)
signal star_gained(skill: String)
signal estate_changed()
signal expedition_finished(id: String, result: Dictionary)
signal market_event(event_id: String)
## kind: "info" | "success" | "warning" | "error" | "level" | "loot" ... ; text: GIÀ tradotto (tr/Loc.t)
signal notice(kind: String, text: String, data: Dictionary)
signal save_completed(ok: bool)
## Evento importante che merita un salvataggio subito (R-SAV-3): apertura ★, Stella, Rifondazione, missione.
signal important_event(reason: String)
signal currency_changed(currency_id: String, amount: int)

# ---- ciclo di vita della partita (Game / SaveService)
signal game_started(slot: int, is_new: bool)
signal game_stopped()
signal state_loaded()
signal save_failed(slot: int, error: String)

# ---- tempo (Clock)
signal clock_speed_changed(speed: float)
signal clock_paused_changed(paused: bool)
signal app_focus_changed(focused: bool)
## Tempo simulato in blocco (lag lungo o rientro dall'offline), già applicato ai sistemi.
signal offline_progress(seconds: float, report: Dictionary)

# ---- Sabbia del Custode (TimePushSystem, UI F13): riserva cambiata (al massimo 10 Hz) e motivo per cui un clic non e' stato accettato
signal push_changed(reserve_s: float, cap_s: float)
signal push_blocked(reason_key: String)

# ---- modificatori / impostazioni / interfaccia
signal modifiers_changed()
signal settings_changed(key: String, value: Variant)
signal locale_changed(locale: String)
## Ultimo dispositivo di input usato: "keyboard" (tastiera e mouse) o "gamepad". Cambia i glifi e la barra dei suggerimenti.
signal input_device_changed(device: String)
## Richiesta di navigazione (la gestisce MainScreen): id di ScreenRegistry + parametri facoltativi.
signal screen_requested(screen_id: String, params: Dictionary)

# ---- mercato (MarketSystem)
signal item_sold(def_id: String, qty: int, gold: int)
## Acquisto dal Mercato/Emporio (solo per il suono): def_id comprato e quantità.
signal item_bought(def_id: String, qty: int)
signal order_completed(order_id: String)
signal faction_rank_up(faction_id: String, rank_id: String)
