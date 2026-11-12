extends Node
## Feedback (autoload) — strumenti per raccogliere segnalazioni e statistiche dai giocatori, tutto LOCALE (nessuna rete):
##  - registro degli errori ruotato in user://logs/ (ErrorLog);
##  - ultime righe del registro di gioco, per la segnalazione (record_game_line);
##  - statistiche di sessione, SOLO se l'utente le attiva nelle Impostazioni (SessionStats);
##  - Esc = menù di pausa con «Segnala un problema» (PauseMenu);
##  - F10 = strumenti da sviluppatore, SOLO build di sviluppo (editor / debug) (DevTools / DevMenu).
## Non contiene logica di gioco: osserva EventBus e il nodo della schermata corrente.

const FLUSH_S := 0.5
const STATS_TICK_S := 1.0
const STATS_SAVE_S := 120.0
const GAME_LINES_MAX := 120
## Caricamento PIGRO (resoconto 100): DevTools/DevMenu/PauseMenu/ReportBuilder non entrano nel codice compilato
## all'avvio (quasi 300 ms di CPU su un PC lento): si caricano con `load()` solo alla prima apertura.
const DEV_ENV_VAR := "VAULTFALL_DEBUG"            # stesso valore di ENV_VAR in DevTools (test_feedback lo verifica)
const _DEV_MENU := "res://src/feedback/DevMenu.gd"
const _PAUSE_MENU := "res://src/feedback/PauseMenu.gd"
const _REPORT_BUILDER := "res://src/feedback/ReportBuilder.gd"
const _BBCODE := "\\[/?(color|b|i|u|s|url|img|font_size|center|right|left|code|outline_size|outline_color|table|cell)[^\\]]*\\]"

var err_log := ErrorLog.new()
var stats := SessionStats.new()
## Solo test: finge una build di rilascio senza VAULTFALL_DEBUG.
var simulate_release: bool = false

var _sink: Logger
var _game_lines := PackedStringArray()
var _bb := RegEx.create_from_string(_BBCODE)
var _flush_acc: float = 0.0
var _stats_acc: float = 0.0
var _stats_save_acc: float = 0.0
var _exited: bool = false
var _pause_menu: Node
var _dev_menu: Node
var _clock_was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	err_log.start_session("VAULTFALL %s | %s %s | %s" % [AppInfo.version_tag(), OS.get_name(), OS.get_version(),
		Time.get_datetime_string_from_system(false, true)])
	_sink = err_log.make_sink()
	OS.add_logger(_sink)
	stats.load_file()
	stats.set_enabled(bool(Settings.get_value("stats_opt_in")))
	EventBus.settings_changed.connect(_on_setting)
	EventBus.game_started.connect(func(_s: int, _n: bool) -> void: _begin_stats_session())
	EventBus.game_stopped.connect(_end_stats_session)
	EventBus.level_up.connect(func(_s: String, _l: int) -> void: _reward("level_up"))
	EventBus.quest_completed.connect(func(_q: String) -> void: _reward("quest"))
	EventBus.crate_opened.connect(func(_r: Dictionary) -> void: _reward("crate"))
	EventBus.achievement_unlocked.connect(func(_a: String) -> void: _reward("achievement"))
	EventBus.pet_found.connect(func(_p: String) -> void: _reward("pet"))
	EventBus.star_gained.connect(func(_s: String) -> void: _reward("star"))
	EventBus.player_died.connect(func(_c: String) -> void: stats.on_death(chapter()))
	if GameState.active:
		_begin_stats_session()


func _exit_tree() -> void:
	_shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


## Chiusura: registra l'uscita (per capitolo), salva le statistiche, chiude il registro. Una volta sola.
func _shutdown() -> void:
	if _exited:
		return
	_exited = true
	if stats.enabled and GameState.active:
		stats.on_exit(chapter(), current_screen())
	if stats.enabled or stats.has_data():
		stats.save_file()
	if _sink != null:
		OS.remove_logger(_sink)
		_sink = null
	err_log.close()


func _process(delta: float) -> void:
	_flush_acc += delta
	if _flush_acc >= FLUSH_S:
		_flush_acc = 0.0
		err_log.flush()
	if not stats.enabled or not GameState.active or Clock.paused or not Clock.focused:
		return
	_stats_acc += delta
	if _stats_acc >= STATS_TICK_S:
		var dt := _stats_acc
		_stats_acc = 0.0
		stats.tick(dt, current_screen(), chapter())
		stats.note_chapter_reached(chapter(), float(GameState.data.get("stats", {}).get("playtime_s", 0.0)))
		_stats_save_acc += dt
		if _stats_save_acc >= STATS_SAVE_S:
			_stats_save_acc = 0.0
			stats.save_file()


# ------------------------------------------------------------------ contesto della partita

## Capitolo della missione principale in corso (-1 se nessuna partita o storia finita).
func chapter() -> int:
	if not GameState.active:
		return -1
	var q := Game.system("quests") as QuestSystem
	if q == null:
		return -1
	var id := q.current_main()
	return int(q.quest_def(id).get("chapter", 0)) if not id.is_empty() else 99


## Id della schermata aperta in MainScreen ("" altrove).
func current_screen() -> String:
	var sc := get_tree().current_scene
	if sc != null and "current_id" in sc:
		return str(sc.current_id)
	return ""


# ------------------------------------------------------------------ registro di gioco

## Chiamata da MainScreen.add_log: tiene le ultime righe in testo semplice (senza colori).
func record_game_line(text: String) -> void:
	_game_lines.append(_bb.sub(text, "", true))
	if _game_lines.size() > GAME_LINES_MAX:
		_game_lines = _game_lines.slice(_game_lines.size() - GAME_LINES_MAX)


func game_lines() -> PackedStringArray:
	return _game_lines


## Un ReportBuilder già preparato con il registro e le righe di gioco correnti.
func new_report(note: String = "") -> RefCounted:
	var rb: RefCounted = (load(_REPORT_BUILDER) as GDScript).new()
	rb.note = note
	rb.error_log = err_log
	rb.game_lines = _game_lines
	return rb


# ------------------------------------------------------------------ statistiche

func _on_setting(key: String, value: Variant) -> void:
	if key != "stats_opt_in":
		return
	stats.set_enabled(bool(value))
	if bool(value) and GameState.active:
		_begin_stats_session()
	elif stats.has_data() or bool(value):
		stats.save_file()


func _begin_stats_session() -> void:
	if stats.enabled:
		stats.begin_session(AppInfo.version_tag(), chapter())


func _end_stats_session() -> void:
	if stats.enabled or stats.has_data():
		stats.save_file()


func _reward(kind: String) -> void:
	if stats.enabled and GameState.active and not Game.sim.offline_running:
		stats.on_reward(kind)


## «Esporta le mie statistiche»: scrive CSV e JSON nella cartella visibile. Ritorna {ok, csv, json, dir}.
func export_stats(dir: String = "") -> Dictionary:
	var rb_script := load(_REPORT_BUILDER) as GDScript
	var out_dir: String = dir if not dir.is_empty() else str(rb_script.call("default_output_dir"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var base := "VAULTFALL_statistiche_%s" % str(rb_script.call("stamp"))
	var res := {"ok": false, "csv": out_dir.path_join(base + ".csv"), "json": out_dir.path_join(base + ".json"), "dir": out_dir}
	var f1 := FileAccess.open(res.csv, FileAccess.WRITE)
	var f2 := FileAccess.open(res.json, FileAccess.WRITE)
	if f1 == null or f2 == null:
		return res
	f1.store_string(stats.export_csv())
	f2.store_string(stats.export_json())
	f1.close()
	f2.close()
	res["ok"] = true
	return res


# ------------------------------------------------------------------ menù (Esc, F10)

func dev_enabled() -> bool:
	# Solo build di sviluppo (editor / export di debug); VAULTFALL_DEBUG=1 non apre nulla in un export di rilascio.
	# (stessa logica di is_enabled nella classe degli strumenti: qui non la si nomina, per il caricamento pigro delle classi dei menu)
	if simulate_release or not (OS.has_feature("editor") or OS.has_feature("debug")):
		return false
	return OS.get_environment(DEV_ENV_VAR).strip_edges() != "0"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()


## Gestione dei tasti (separata dall'evento per poterla provare nei test). Ritorna true se il tasto è stato usato.
func handle_key(keycode: int) -> bool:
	if keycode == KEY_F10:
		return toggle_dev_menu()
	if keycode == KEY_ESCAPE:
		if _dev_menu != null and is_instance_valid(_dev_menu):
			toggle_dev_menu()
			return true
		return toggle_pause_menu()
	return false


## Apre/chiude il menù F10. In un export di rilascio non fa nulla e ritorna false.
func toggle_dev_menu() -> bool:
	if not dev_enabled():
		return false
	if _dev_menu != null and is_instance_valid(_dev_menu):
		_dev_menu.queue_free()
		_dev_menu = null
		return true
	_dev_menu = (load(_DEV_MENU) as GDScript).new()
	get_tree().root.add_child(_dev_menu)
	return true


func is_dev_menu_open() -> bool:
	return _dev_menu != null and is_instance_valid(_dev_menu)


## Menù di pausa (Esc), solo con una partita nella schermata principale.
## `force`: la chiama MainScreen stessa (anche quando non è la scena corrente, es. nei test).
func toggle_pause_menu(force: bool = false) -> bool:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		close_pause_menu()
		return true
	if not GameState.active or (current_screen().is_empty() and not force):
		return false
	_clock_was_paused = Clock.paused
	Clock.set_paused(true)
	_pause_menu = (load(_PAUSE_MENU) as GDScript).new()
	get_tree().root.add_child(_pause_menu)
	return true


func close_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null
	if not _clock_was_paused:
		Clock.set_paused(false)


func is_pause_menu_open() -> bool:
	return _pause_menu != null and is_instance_valid(_pause_menu)
