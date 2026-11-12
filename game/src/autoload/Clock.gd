extends Node
## Clock (autoload) — tempo di simulazione a passo fisso (docs/17 §5, §11). Delega a FixedStepClock.
## Il tempo è MISURATO (Time.get_ticks_usec), non contato in frame.
## Velocità: Settings.game_speed (×1 normale; ×10/×100 solo nelle build di debug, tasto F9).
## Segnali: EventBus.clock_speed_changed(speed), EventBus.clock_paused_changed(paused),
##          EventBus.app_focus_changed(focused). I passi arrivano a Game tramite core.stepped.

const DEBUG_SPEEDS: Array[float] = [1.0, 10.0, 100.0]
const FOCUS_FPS := 60
const BACKGROUND_FPS := 10

var core := FixedStepClock.new()
var focused := true
## Fotogrammi al secondo con la finestra in primo piano (Impostazioni «Fotogrammi al secondo»: 60 o 30 per PC lenti).
var focus_fps: int = FOCUS_FPS
var _last_usec: int = 0
var _last_wall: float = 0.0              # orologio di sistema (s, con decimali) al fotogramma precedente: rivela le sospensioni


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()
	_last_wall = Time.get_unix_time_from_system()
	Engine.max_fps = focus_fps


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real := (now - _last_usec) / 1_000_000.0
	_last_usec = now
	check_suspend(Time.get_unix_time_from_system(), real)
	core.advance(real)


## Il PC (o la Steam Deck) e' andato in sospensione con il gioco aperto: l'orologio di sistema e' avanzato piu' del tempo
## misurato dal motore. L'eccesso e' un'assenza vera (stesso limite, stesso Bentornato di una chiusura e riapertura). In pausa
## o senza partita non si fa nulla (la pausa e' una scelta del giocatore). Un orologio tornato indietro si ignora e si riallinea.
func check_suspend(wall_now: float, real: float) -> void:
	var wall := wall_now - _last_wall
	_last_wall = wall_now
	if core.paused or not GameState.active:
		return
	var off: Dictionary = DataRegistry.constants.get("offline", {})
	var gap := FixedStepClock.suspend_gap(wall, real, float(off.get("resume_min_gap_s", 120.0)))
	if gap > 0.0:
		core.long_gap.emit(gap)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			focused = false
			Engine.max_fps = BACKGROUND_FPS
			EventBus.app_focus_changed.emit(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			focused = true
			Engine.max_fps = focus_fps
			EventBus.app_focus_changed.emit(true)


func set_focus_fps(value: int) -> void:
	focus_fps = 0 if value <= 0 else clampi(value, 15, 144)      # 0 = senza limite (Impostazioni → Schermo)
	if focused:
		Engine.max_fps = focus_fps


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F9:
		cycle_debug_speed()
		get_viewport().set_input_as_handled()


var speed: float:
	get:
		return core.speed

var paused: bool:
	get:
		return core.paused


func set_speed(value: float) -> void:
	var v := value
	if not OS.is_debug_build():
		v = 1.0          # nelle build di rilascio la velocità resta ×1
	if is_equal_approx(v, core.speed):
		return
	core.speed = v
	EventBus.clock_speed_changed.emit(v)


func cycle_debug_speed() -> void:
	var i := DEBUG_SPEEDS.find(core.speed)
	set_speed(DEBUG_SPEEDS[(i + 1) % DEBUG_SPEEDS.size()])


func set_paused(value: bool) -> void:
	if value == core.paused:
		return
	core.paused = value
	_last_usec = Time.get_ticks_usec()
	_last_wall = Time.get_unix_time_from_system()
	EventBus.clock_paused_changed.emit(value)


func toggle_pause() -> void:
	set_paused(not core.paused)


## Ora reale (secondi Unix), per salvataggi, offline e timer reali.
func now_unix() -> int:
	return int(Time.get_unix_time_from_system())
