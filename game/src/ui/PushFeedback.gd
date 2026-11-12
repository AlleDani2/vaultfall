class_name PushFeedback
extends Node
## Feedback della Sabbia del Custode (F14, docs/ui_redesign/06 §3.5, 03 §7.3, D26). Solo presentazione:
##   - «+N,N s» AGGREGATO ogni 200 ms accanto al pulsante (una sola etichetta; mai un numero per singolo clic, mai sopra il contenuto);
##   - scatto <= 120 ms della barra dell'attività (barra alta) e del segno nel menù, trovati per nome/classe senza toccare i loro file;
##   - UN solo tick sonoro: sempre lo stesso suono, sempre alla stessa altezza, al massimo 10 al secondo, bus «UI».
## Con «Riduci animazioni» o effetti ridotti: né scatto né «+N s» (restano il numero e l'anello del pulsante).
## ETICA: ricompensa uguale per tutti e deterministica; nessun suono di vittoria o «quasi»; nessuna statistica sui clic.

const TICK_PATH := "res://assets/audio/sfx/ui_click.ogg"
const TICK_PITCH := 1.0                    # sempre la stessa altezza (D26): nessuna variazione, nessuna salita
const TICK_GAP_MS := 100                   # al massimo 10 tick al secondo
const FLUSH_MS := 200                      # aggregazione del «+N s»
const SHOW_MS := 700                       # quanto resta visibile l'ultimo valore dopo l'ultimo clic
const FLASH_GAP_MS := 200                  # al massimo cinque scatti al secondo
const FLASH_S := 0.12                      # scatto <= 120 ms
const FLASH_TINT := Color(1.35, 1.25, 1.0)
const GAIN_H := 14.0                       # altezza fissa dell'etichetta: comparire non sposta nulla

var gain_label: Label
var tick_count: int = 0                    # tick decisi (anche se l'audio è spento): per i test
var flash_count: int = 0                   # scatti avviati: per i test
var last_stream: AudioStream = null
var last_pitch: float = 0.0
var label_updates: int = 0                 # quante volte l'etichetta è stata riscritta (una per finestra da 200 ms)

var _acc_s: float = 0.0
var _last_tick_msec: int = -1000000
var _last_flush_msec: int = 0
var _last_flash_msec: int = -1000000
var _show_until_msec: int = 0
var _player: AudioStreamPlayer
var _tween: Tween
var _targets: Array[CanvasItem] = []
var _bases: Dictionary = {}
var _targets_msec: int = -1000000
var _stream: AudioStream


func _init() -> void:
	name = "PushFeedback"
	gain_label = Label.new()
	gain_label.name = "PushGain"
	gain_label.theme_type_variation = &"MonoLabel"
	gain_label.custom_minimum_size = Vector2(0, GAIN_H)
	gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gain_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	gain_label.add_theme_font_size_override("font_size", 11)
	gain_label.add_theme_color_override("font_color", Color("#e0b95a"))
	gain_label.text = ""


func _ready() -> void:
	_last_flush_msec = Time.get_ticks_msec()


## Animazioni ammesse: né «Riduci animazioni» né effetti ridotti.
static func motion_ok() -> bool:
	return not bool(Settings.get_value("reduce_motion")) and str(Settings.get_value("fx_mode")) == "full"


## Un clic ha concesso `seconds` di tempo (aggregato: l'etichetta si aggiorna a finestre da FLUSH_MS).
func on_push(seconds: float) -> void:
	var now := Time.get_ticks_msec()
	if bool(Settings.get_value("push_sound")) and now - _last_tick_msec >= TICK_GAP_MS:
		_last_tick_msec = now
		_play_tick()
	if not motion_ok():
		return
	if bool(Settings.get_value("push_floaters")):
		_acc_s += maxf(0.0, seconds)
	if now - _last_flash_msec >= FLASH_GAP_MS:
		_last_flash_msec = now
		_flash()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_flush_msec >= FLUSH_MS:
		_last_flush_msec = now
		flush()
	if not gain_label.text.is_empty() and now >= _show_until_msec:
		gain_label.text = ""


## Scrive il totale accumulato nella finestra (una sola etichetta, un solo valore).
func flush() -> void:
	if _acc_s <= 0.0:
		return
	if not motion_ok() or not bool(Settings.get_value("push_floaters")):
		_acc_s = 0.0
		return
	gain_label.text = Loc.tf("UI_PUSH_GAIN", {"s": NumberFormat.decimal(_acc_s, 1, Loc.locale())})
	label_updates += 1
	_acc_s = 0.0
	_show_until_msec = Time.get_ticks_msec() + SHOW_MS


## Spegne tutto (pulsante nascosto o impostazioni cambiate).
func clear() -> void:
	_acc_s = 0.0
	gain_label.text = ""
	_stop_flash()


# ------------------------------------------------------------------ suono

func _play_tick() -> void:
	tick_count += 1
	if _stream == null:
		_stream = load(TICK_PATH) as AudioStream
	last_stream = _stream
	last_pitch = TICK_PITCH
	if _stream == null or not AudioManager.enabled or AudioManager.offline_silent() or not is_inside_tree():
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "PushTick"
		add_child(_player)
	_player.stream = _stream
	_player.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	_player.pitch_scale = TICK_PITCH
	_player.play()


# ------------------------------------------------------------------ scatto

func _flash() -> void:
	flash_count += 1
	if not is_inside_tree():
		return
	_stop_flash()
	var targets := _flash_targets()
	if targets.is_empty():
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	for t in targets:
		var base := t.modulate
		_bases[t] = base
		_tween.tween_property(t, "modulate", base * FLASH_TINT, FLASH_S * 0.4)
		_tween.tween_property(t, "modulate", base, FLASH_S * 0.6).set_delay(FLASH_S * 0.4)


func _stop_flash() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	for t in _bases:
		if is_instance_valid(t):
			(t as CanvasItem).modulate = _bases[t]      # ripristina il colore di prima dello scatto
	_bases.clear()


## Barra dell'attività (barra alta) e segni del menù, cercati al massimo una volta ogni 2 s.
func _flash_targets() -> Array[CanvasItem]:
	var now := Time.get_ticks_msec()
	if now - _targets_msec > 2000:
		_targets_msec = now
		_targets.clear()
		var root := get_tree().root
		var bar := root.find_child("ActivityBar", true, false) as CanvasItem
		if bar != null:
			_targets.append(bar)
		for m in root.find_children("*", "MenuMark", true, false):
			_targets.append(m as CanvasItem)
	var out: Array[CanvasItem] = []
	for t in _targets:
		if is_instance_valid(t) and t.is_visible_in_tree():
			out.append(t)
	return out
