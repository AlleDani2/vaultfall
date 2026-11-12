extends Node
## Settings (autoload) — impostazioni dell'utente in user://settings.cfg (docs/17 §3, docs/16 §7).
## Sono del PC, non della partita: non stanno nel salvataggio.
##   Settings.get_value("locale")          Settings.set_value("reduce_motion", true)
## Ogni modifica emette EventBus.settings_changed(key, value) e si applica subito (lingua, volumi, scala).

const SECTION := "settings"
const LOCALES: PackedStringArray = ["it", "en"]
const NUMBER_FORMATS: PackedStringArray = ["short", "full", "scientific"]
const FX_MODES: PackedStringArray = ["full", "reduced"]
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]      # 0 = senza limite (1.0: schermo)
const SETTINGS_REV := 2               # revisione dello schema del file: 1 = fino alla VAlfa, 2 = 1.0 (schermo, accessibilità, comandi)
const PAD_HINT_MODES: PackedStringArray = ["auto", "always", "never"]
## Bus audio previsti (docs/16 §7); quelli che non esistono ancora nel layout audio si ignorano.
const VOLUME_BUSES := {"volume_master": "Master", "volume_music": "Music", "volume_sfx": "SFX",
	"volume_ui": "UI", "volume_reel": "Reel"}

## Valori predefiniti (tipo compreso: set_value rifiuta valori di tipo diverso).
const DEFAULTS := {
	"locale": "",                 # "" = dalla lingua del sistema al primo avvio
	"volume_master": 0.8, "volume_music": 0.7, "volume_sfx": 0.8, "volume_ui": 0.8, "volume_reel": 0.8,
	"reduce_motion": false,
	"fx_mode": "full",             # effetti visivi: "full" (pieni) | "reduced" (meno particelle, niente scosse né lampi)
	"mute_in_background": true,   # silenzio con la finestra ridotta a icona (docs/21 §4)
	"game_speed": 1.0,            # velocità di simulazione (solo build di debug: Clock la forza a 1 in rilascio)
	"fps_cap": 60,                # fotogrammi al secondo in primo piano: 60 (fluido) | 30 (risparmio, PC lenti); resoconto 100
	"ui_scale": 1.0,              # dimensione RELATIVA all'automatica, 0,8–1,25 (F5, 06 §3.17); con la scala automatica spenta vale in assoluto
	"ui_scale_rev": 1,            # F5: 1 → 2 converte una volta i vecchi valori assoluti di ui_scale (0,75 → 0,8) e accende la scala automatica
	"number_format": "short",
	"last_slot": 0,
	"stats_opt_in": false,        # statistiche di gioco locali e anonime (Feedback/SessionStats): SPENTE di default
	"tutorials": true,            # schede tutorial di 3 righe al primo sblocco di ogni sistema (R-UNL-2)
	"right_col_visible": false,   # colonna destra FISSATA (solo in banda larga; di norma è un cassetto: tasto L). Predefinito false dalla F3
	"right_col_width": 250,       # larghezza in px della colonna destra, trascinabile (G24)
	# --- progetto di interfaccia (docs/ui_redesign/06 §3.3-3.4, §3.17), chiavi dell'ondata A: in F0 NESSUNA è ancora usata,
	# i valori non cambiano il comportamento finché la fase proprietaria non le legge (F3, F4, F5, F6 ecc.)
	"ui_layout_rev": 1,           # revisione del layout dell'interfaccia: le migrazioni una tantum (colonna → cassetto, scala) la portano a 2
	"drawer_section": "log",      # ultima sezione aperta nel cassetto destro: "log" | "friends" (F3)
	"sidebar_groups_closed": [],  # id dei gruppi del menù laterale richiusi dal giocatore (F4)
	"seen_intro": [],             # id delle schermate di cui il giocatore ha già visto la frase «a cosa serve» (F6-F11)
	"ui_scale_auto": true,        # scala automatica dell'area logica (F5, UiScale): porta l'area a 1536×864 sugli schermi grandi
	"cozy_mode": false,           # Modalità Cozy: +50% XP (Modifiers, sorgente «mode:cozy»); non conta per le classifiche (G53)
	# --- UI-A: notifiche per categoria (NoticeFilter), registro di combattimento, conferma alla chiusura
	"notify_loot": true, "notify_progress": true, "notify_achievements": true, "notify_levels": true,
	"notify_events": true, "notify_boss": true, "notify_info": true,
	"combat_log": true,           # registro di combattimento attivo (spegnerlo alleggerisce le schede lunghe)
	"combat_log_filter": "all",   # "all" | "rare" (solo drop rari) | "boss" (solo eventi del boss)
	"confirm_quit": true,         # chiede conferma se si chiude con un combattimento attivo
	# --- Sabbia del Custode (F14, docs/ui_redesign/06 §3.5, 03 §7.4)
	"push_enabled": true,         # mostra il pulsante della Sabbia (spento = nascosto, anche T e il controller)
	"push_assist": "off",         # Clic assistito: "off" | "hold" (tieni premuto) | "toggle" (interruttore) | "auto" (spende man mano che si ricarica)
	"push_assist_rate": 3,        # clic/s equivalenti del Clic assistito, 1-10 (il tetto vero è constants.time_push.max_cps)
	"push_floaters": true,        # «+N s» aggregato accanto al pulsante
	"push_sound": true,           # tick sonoro (uno solo, sempre alla stessa altezza)
	# --- Deposito (F16, docs/ui_redesign/02 §5.3): preferenze di vista, non fanno parte del salvataggio
	"bank_view": "grid",          # "grid" (griglia di icone, predefinita) | "list" (lista, per confrontare l'equipaggiamento)
	"bank_density": "auto",       # griglia: "auto" (comoda da 1100 px utili in su) | "comfortable" | "compact"
	# --- 1.0: schermo (DisplayOptions), accessibilità (Accessibility), comandi (InputBindings), controller (UiRuntime)
	"settings_rev": 2,            # revisione dello schema del file (migrazione una tantum da 1 a 2)
	"window_mode": "windowed",    # "windowed" | "borderless" (finestra senza bordi a tutto monitor) | "fullscreen"
	"window_size": Vector2i(1600, 900),   # dimensione della finestra in modalità «finestra» (segue anche il ridimensionamento a mano)
	"monitor": 0,                 # indice del monitor
	"vsync": "on",                # "off" | "on" | "adaptive"
	"text_scale": 1.0,            # testo grande: 1,0 | 1,25 | 1,5 (corpo dei caratteri, indipendente dalla scala dell'interfaccia)
	"colorblind": "off",          # "off" | "protanopia" | "deuteranopia" | "tritanopia" (filtro colore, mai i PNG: D-6)
	"high_contrast": false,       # alto contrasto (filtro colore)
	"keybinds": {},               # comandi cambiati dal giocatore: {azione: [evento salvato]} (InputBindings)
	"pad_glyphs": "auto",         # glifi dei pulsanti: "auto" (dal controller) | "xbox" | "playstation" | "deck"
	"pad_hints": "auto",          # barra dei suggerimenti dei pulsanti: "auto" (solo se si usa il controller) | "always" | "never"
	"display_revert": {},         # schermo di prima, finché un cambio aspetta «Mantieni?» (se il gioco si chiude, al riavvio si torna lì)
	"bar_percent": false,         # percentuale scritta sulle barre di avanzamento (non solo colore)
	"osk": true,                  # tastiera a schermo nei campi di testo quando si usa il controller
	"coop_last_host": {},         # docs/24 §7.1 p.3: ultimo host a cui ci si e' collegati {ip, port}; SOLO qui (computer locale), mai nel salvataggio ne' nello ZIP
	"coop_ip_ack": false,         # docs/24 §7.1: il giocatore ha confermato di aver capito che in coop l'IP dell'host è visibile (una tantum)
}
const BANK_VIEWS: PackedStringArray = ["grid", "list"]
const BANK_DENSITIES: PackedStringArray = ["auto", "comfortable", "compact"]
const PUSH_ASSIST_MODES: PackedStringArray = ["off", "hold", "toggle", "auto"]
const RANGES := {"volume_master": [0.0, 1.0], "volume_music": [0.0, 1.0], "volume_sfx": [0.0, 1.0],
	"volume_ui": [0.0, 1.0], "volume_reel": [0.0, 1.0], "ui_scale": [0.8, 1.25], "game_speed": [1.0, 100.0],
	"last_slot": [0, 3], "right_col_width": [180, 520], "fps_cap": [0, 144], "push_assist_rate": [1, 10],
	"monitor": [0, 15], "text_scale": [1.0, 1.5]}

var path: String = "user://settings.cfg"
## Scritture ravvicinate (cursori che si trascinano) si fondono: la prima va subito, le successive al piu' una al secondo.
const SAVE_COALESCE_MS := 1000
var _values: Dictionary = {}
var _dirty: bool = false                 # modifiche non ancora scritte (scrittura ritardata)
var _dirty_path: String = ""
var _key_hits: Dictionary = {}           # chiave -> [cambi nella finestra, inizio finestra ms]
var _last_write_ms: int = -SAVE_COALESCE_MS
var last_save_error: int = OK            # esito dell'ultima scrittura (OK = riuscita)
var _last_csf := 0.0                     # ultimo fattore di scala impostato da Settings (0 = mai)
var _scale_notice_pending := false       # F5: avviso una tantum dopo la conversione di «Dimensione interfaccia»
var _bulk := false                       # apply_all in corso
var runtime: UiRuntime                   # 1.0: filtro colore, suggerimenti dei pulsanti, F11, aiuto al fuoco, tastiera a schermo


func _ready() -> void:
	load_settings()
	runtime = UiRuntime.new()
	add_child(runtime)
	InputBindings.install()
	apply_all()
	get_window().size_changed.connect(_on_window_resized)      # scala automatica: si ricalcola al cambio di dimensione della finestra
	EventBus.game_started.connect(_on_game_started_scale_notice)
	get_tree().node_added.connect(WindowFit.hook)            # dialoghi sempre dentro la finestra
	if not OS.get_cmdline_args().has("--resolution"):      # con --resolution (catture, prove) la dimensione è voluta
		WindowFit.setup.call_deferred(get_window())          # minimo + adattamento allo schermo (QA overflow 107)


func _process(_delta: float) -> void:
	if _dirty and Time.get_ticks_msec() - _last_write_ms >= SAVE_COALESCE_MS:
		flush()


func _exit_tree() -> void:
	flush()                                # chiusura del gioco: l'ultima modifica ritardata non si perde


func load_settings() -> void:
	_dirty = false                         # rileggere dal disco scarta le modifiche non ancora scritte (accade solo all'avvio)
	_values = DEFAULTS.duplicate(true)
	_scale_notice_pending = false
	var cfg := ConfigFile.new()
	var existing := cfg.load(path) == OK
	if not existing and FileAccess.file_exists(path + ".tmp"):
		existing = cfg.load(path + ".tmp") == OK      # chiusura brusca tra la scrittura del .tmp e la rinomina: il .tmp e' completo
	var file_rev := SETTINGS_REV
	var repaired := false
	if existing:
		file_rev = 1       # i file della VAlfa non hanno «settings_rev»
		for key in DEFAULTS:
			if cfg.has_section_key(SECTION, key):
				var v: Variant = cfg.get_value(SECTION, key)
				if key == "keybinds":
					if v is Dictionary:
						var clean := InputBindings.sanitize(v)
						repaired = repaired or clean != v      # comandi illeggibili scartati: il file si riscrive pulito
						_values[key] = clean
					else:
						repaired = true
				elif _valid(key, v):
					_values[key] = _clamp(key, v)
		if cfg.has_section_key(SECTION, "settings_rev") and cfg.get_value(SECTION, "settings_rev") is int:
			file_rev = int(cfg.get_value(SECTION, "settings_rev"))
	_restore_pending_display()
	if str(_values.locale).is_empty():
		_values["locale"] = "it" if OS.get_locale_language() == "it" else "en"
	_migrate_ui_scale(existing and cfg.has_section_key(SECTION, "ui_scale"))
	_migrate_rev(file_rev)
	if repaired:
		save_settings()


## F5, una tantum (ui_scale_rev 1 → 2): i vecchi valori assoluti di «Dimensione interfaccia» (0,75 / 1,0 / 1,25) diventano
## relativi all'automatica (0,8 / 1,0 / 1,25) e la scala automatica si accende. Chi ha già un file di impostazioni vede un avviso.
func _migrate_ui_scale(had_old_value: bool) -> void:
	if int(_values.get("ui_scale_rev", 1)) >= 2:
		return
	_values["ui_scale"] = _clamp("ui_scale", UiScale.migrate_old_scale(float(_values.get("ui_scale", 1.0))))
	_values["ui_scale_auto"] = true
	_values["ui_scale_rev"] = 2
	_scale_notice_pending = had_old_value
	save_settings()


## Il gioco è stato chiuso mentre aspettava «Mantieni queste impostazioni?» (schermo nero, finestra fuori dal monitor):
## al riavvio tornano le impostazioni dello schermo di prima.
func _restore_pending_display() -> void:
	var rv: Variant = _values.get("display_revert", {})
	if not (rv is Dictionary) or (rv as Dictionary).is_empty():
		return
	for k in rv:
		if DisplayOptions.KEYS.has(str(k)) and _valid(str(k), rv[k]):
			_values[str(k)] = _clamp(str(k), rv[k])
	_values["display_revert"] = {}
	save_settings()


## 1.0, una tantum (settings_rev 1 → 2): il file della VAlfa non ha le chiavi di schermo, accessibilità e comandi. Restano tutti i
## valori che c'erano; le chiavi nuove hanno i predefiniti (finestra 1600×900, VSync acceso, nessun filtro, comandi di serie).
## Il limite di fotogrammi 30/60 resta com'era. Una revisione più nuova di questa (file di una versione futura) non si tocca.
func _migrate_rev(file_rev: int) -> void:
	if file_rev >= SETTINGS_REV:
		_values["settings_rev"] = maxi(file_rev, SETTINGS_REV)
		return
	_values["settings_rev"] = SETTINGS_REV
	save_settings()


## Ricalcola il fattore di scala della finestra radice (UiScale) dalla dimensione attuale e dalle preferenze.
func _apply_ui_scale() -> void:
	if not is_inside_tree():
		return
	var win := get_window()
	if win == null:
		return
	_last_csf = UiScale.content_scale_factor(win.size, float(_values.get("ui_scale", 1.0)), bool(_values.get("ui_scale_auto", true)))
	win.content_scale_factor = _last_csf


## Cambio di dimensione della finestra: ricalcola la scala. Se qualcun altro ha fissato a mano il fattore (prove, catture)
## non lo si sovrascrive finché cambia solo la finestra.
func _on_window_resized() -> void:
	var win := get_window()
	if win != null and _last_csf > 0.0 and not is_equal_approx(win.content_scale_factor, _last_csf):
		return
	_apply_ui_scale()


func _on_game_started_scale_notice(_slot: int, _is_new: bool) -> void:
	if not _scale_notice_pending:
		return
	_scale_notice_pending = false
	await get_tree().create_timer(1.5).timeout      # la cornice deve aver collegato EventBus.notice
	EventBus.notice.emit("info", tr("UI_SCALE_MIGRATED"), {})


## Scrive subito, in modo ATOMICO: prima su `<file>.tmp`, poi rinomina (un arresto a meta' non lascia un file troncato).
func save_settings() -> Error:
	return _write(path)


func _write(target: String) -> Error:
	_dirty = false
	_last_write_ms = Time.get_ticks_msec()
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, key, _values[key])
	var tmp := target + ".tmp"
	var err := cfg.save(tmp)
	if err == OK:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)             # su Windows la rinomina non sovrascrive
		err = DirAccess.rename_absolute(tmp, target)
	if err != OK:
		push_warning("Settings: scrittura di %s non riuscita (%s)" % [target, error_string(err)])
		DirAccess.remove_absolute(tmp)
	last_save_error = err
	return err


## Scrive subito se c'e' una scrittura ritardata in attesa.
func flush() -> void:
	if _dirty:
		_write(_dirty_path if not _dirty_path.is_empty() else path)


## Un cambio isolato si scrive subito. Un cursore trascinato cambia lo STESSO valore decine di volte al secondo: dal terzo cambio
## della stessa chiave dentro la finestra di COALESCE si scrive al massimo una volta al secondo (e all'uscita, `flush`).
func _queue_save(key: String) -> void:
	var now := Time.get_ticks_msec()
	var hit: Array = _key_hits.get(key, [0, -SAVE_COALESCE_MS * 2])
	if now - int(hit[1]) > SAVE_COALESCE_MS:
		hit = [1, now]
	else:
		hit[0] = int(hit[0]) + 1
	_key_hits[key] = hit
	if int(hit[0]) <= 2 or now - _last_write_ms >= SAVE_COALESCE_MS:
		save_settings()
	else:
		_dirty = true
		_dirty_path = path


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Imposta, applica, salva ed emette il segnale. Ritorna false se chiave o tipo non sono validi.
func set_value(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key) or not _valid(key, value):
		return false
	var v: Variant = _clamp(key, value)
	if _values.get(key) == v:
		return true
	_values[key] = v
	_apply(key)
	_queue_save(key)
	EventBus.settings_changed.emit(key, v)
	return true


func reset_to_defaults() -> void:
	for key in DEFAULTS:
		if key != "locale":
			set_value(key, DEFAULTS[key])


func apply_all() -> void:
	_bulk = true
	for key in _values:
		_apply(key)
	_bulk = false
	if runtime != null:
		DisplayOptions.apply_window(get_window())      # una sola volta: modalità, dimensione e monitor insieme


func _apply(key: String) -> void:
	var v: Variant = _values[key]
	match key:
		"locale":
			if not str(v).is_empty():          # "" = «dalla lingua del sistema»: non è un codice da applicare (QA 83 C-09)
				TranslationServer.set_locale(v)
				EventBus.locale_changed.emit(v)
		"game_speed":
			Clock.set_speed(float(v))
		"fps_cap":
			Clock.set_focus_fps(int(v))
		"window_mode", "window_size", "monitor":
			if runtime != null and not _bulk:
				DisplayOptions.apply_window(get_window())
		"vsync":
			DisplayOptions.apply_vsync()
		"text_scale":
			Accessibility.apply_text_scale(Accessibility.project_theme(), float(v))
		"bar_percent":
			if runtime != null:
				runtime.apply_bar_percent()
		"colorblind", "high_contrast":
			if runtime != null:
				runtime.apply_vision()
		"keybinds":
			InputBindings.apply_saved(v)
		"ui_scale", "ui_scale_auto":
			_apply_ui_scale()
		_:
			if VOLUME_BUSES.has(key):
				var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
				if bus >= 0:
					AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, float(v))))


func _valid(key: String, v: Variant) -> bool:
	var d: Variant = DEFAULTS[key]
	if key == "locale":
		return v is String and (LOCALES.has(v) or str(v).is_empty())
	if key == "number_format":
		return v is String and NUMBER_FORMATS.has(v)
	if key == "combat_log_filter":
		return v is String and ["all", "rare", "boss"].has(v)
	if key == "push_assist":
		return v is String and PUSH_ASSIST_MODES.has(v)
	if key == "bank_view":
		return v is String and BANK_VIEWS.has(v)
	if key == "bank_density":
		return v is String and BANK_DENSITIES.has(v)
	if key == "fx_mode":
		return v is String and FX_MODES.has(v)
	if key == "fps_cap":
		return v is int and FPS_CAPS.has(v)
	if key == "window_mode":
		return v is String and DisplayOptions.MODES.has(v)
	if key == "vsync":
		return v is String and DisplayOptions.VSYNCS.has(v)
	if key == "colorblind":
		return v is String and Accessibility.COLORBLIND_MODES.has(v)
	if key == "pad_glyphs":
		return v is String and (v == "auto" or GamepadGlyphs.STYLES.has(v))
	if key == "pad_hints":
		return v is String and PAD_HINT_MODES.has(v)
	if key == "text_scale":
		return (v is float or v is int) and Accessibility.TEXT_SCALES.any(func(t: float) -> bool: return is_equal_approx(t, float(v)))
	if key == "window_size":
		return v is Vector2i and v.x >= DisplayOptions.MIN_WINDOW.x and v.y >= DisplayOptions.MIN_WINDOW.y \
			and v.x <= DisplayOptions.MAX_WINDOW.x and v.y <= DisplayOptions.MAX_WINDOW.y
	if key == "keybinds":
		return v is Dictionary and v.keys().all(func(k: Variant) -> bool: return k is String and v[k] is Array)
	if key == "display_revert":
		return v is Dictionary
	if key == "settings_rev":
		return v is int and v >= 1
	if d is float:
		return (v is float or v is int) and is_finite(float(v))      # NaN/inf non sono mai valori validi (QA 83 C-07)
	return typeof(v) == typeof(d)


func _clamp(key: String, v: Variant) -> Variant:
	var d: Variant = DEFAULTS[key]
	if d is float:
		var f := float(v)
		if RANGES.has(key):
			f = clampf(f, RANGES[key][0], RANGES[key][1])
		return f
	if d is int and RANGES.has(key):
		return clampi(int(v), RANGES[key][0], RANGES[key][1])
	return v
