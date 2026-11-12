class_name DisplayOptions
extends RefCounted
## Schermo e finestra (1.0, docs/review_1_0/03 punto 1): modalità, risoluzione, monitor, VSync, limite di fotogrammi.
## Le scelte stanno in Settings («window_mode», «window_size», «monitor», «vsync», «fps_cap»). Qui:
##   - il calcolo puro di cosa fare (`plan`, `resolution_choices`) — testabile senza finestra;
##   - `apply` che lo esegue sulla finestra (non fa nulla in headless né quando le catture fissano la risoluzione con --resolution).

const MODES: PackedStringArray = ["windowed", "borderless", "fullscreen"]
const VSYNCS: PackedStringArray = ["off", "on", "adaptive"]
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]      # 0 = senza limite
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
const RISKY_KEYS: PackedStringArray = ["window_mode", "window_size", "monitor"]       # cambi dopo i quali si chiede «Mantieni?»
const KEEP_SECONDS := 10
const MIN_WINDOW := Vector2i(960, 540)
const MAX_WINDOW := Vector2i(7680, 4320)
const KEYS: PackedStringArray = ["window_mode", "window_size", "monitor", "vsync", "fps_cap"]


## Le impostazioni dello schermo adesso (per annullare un cambio).
static func snapshot() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = Settings.get_value(k)
	return d


static func restore(snap: Dictionary) -> void:
	for k in snap:
		Settings.set_value(k, snap[k])


## La finestra può essere gestita da noi? No in headless e quando la risoluzione è imposta dalla riga di comando (catture, prove).
static func managed() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.get_cmdline_args().has("--resolution")


## Risoluzioni offerte per un monitor di dimensione `screen`: quelle che entrano (con un po' di respiro per bordi e barra),
## più `current` se non è in elenco (finestra ridimensionata a mano). Ordinate.
static func resolution_choices(screen: Vector2i, current: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y - 48:
			out.append(r)
	if out.is_empty():
		out.append(MIN_WINDOW)
	if current.x >= MIN_WINDOW.x and current.y >= MIN_WINDOW.y and not out.has(current):
		out.append(current)
		out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


static func size_text(v: Vector2i) -> String:
	return "%d×%d" % [v.x, v.y]


## Cosa fare con la finestra: {"mode": Window.Mode, "borderless": bool, "size": Vector2i, "position": Vector2i} per il monitor
## `screen_rect` (posizione e dimensione intera) e `usable` (area libera da barre). In «finestra» la dimensione scelta viene
## ridotta se non entra e la finestra è centrata nell'area utile; «senza bordi» copre tutto il monitor; «schermo intero» usa il
## modo a schermo intero di Godot (posizione e dimensione le decide lui).
static func plan(mode: String, want: Vector2i, screen_rect: Rect2i, usable: Rect2i) -> Dictionary:
	match mode:
		"fullscreen":
			return {"mode": Window.MODE_FULLSCREEN, "borderless": false, "size": screen_rect.size, "position": screen_rect.position}
		"borderless":
			return {"mode": Window.MODE_WINDOWED, "borderless": true, "size": screen_rect.size, "position": screen_rect.position}
	var fit := WindowFit.fit_size(want, usable.size, Vector2i(0, 32))
	var pos := usable.position + Vector2i((usable.size.x - fit.x) / 2, maxi(0, (usable.size.y - fit.y - 32) / 2) + 32)
	return {"mode": Window.MODE_WINDOWED, "borderless": false, "size": fit, "position": pos}


## Porta la finestra sullo stato scelto. Ritorna false se non ha potuto (headless, risoluzione imposta, finestra assente).
static func apply_window(win: Window) -> bool:
	if win == null or not managed():
		return false
	var count := DisplayServer.get_screen_count()
	var screen := clampi(int(Settings.get_value("monitor")), 0, maxi(0, count - 1))
	var mode := str(Settings.get_value("window_mode"))
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED          # per spostarla e ridimensionarla bisogna uscire dallo schermo intero
	win.current_screen = screen
	var full := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	var p := plan(mode, Settings.get_value("window_size") as Vector2i, full, DisplayServer.screen_get_usable_rect(screen))
	win.borderless = bool(p.borderless)
	if mode == "fullscreen":
		win.mode = Window.MODE_FULLSCREEN
	else:
		win.size = p.size
		win.position = p.position
	return true


static func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match str(Settings.get_value("vsync")):
		"off":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"adaptive":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## Nome leggibile del monitor n: «1 – 1920×1080».
static func monitor_text(i: int) -> String:
	var sz := DisplayServer.screen_get_size(i)
	return "%d – %d×%d" % [i + 1, sz.x, sz.y]


## Modalità a cui passa F11 / Alt+Invio: dallo schermo intero torna alla modalità di prima (finestra se non c'è), altrimenti schermo intero.
static func toggled_mode(current: String, previous: String) -> String:
	if current == "fullscreen":
		return previous if previous == "windowed" or previous == "borderless" else "windowed"
	return "fullscreen"
