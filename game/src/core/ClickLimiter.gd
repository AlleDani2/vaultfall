class_name ClickLimiter
extends RefCounted
## Limite duro di clic al secondo con finestra scorrevole (Sabbia del Custode, UI F13, docs/ui_redesign/03 §7.2).
## SERVE SOLO ALLA CPU E AGLI EFFETTI, NON ALL'EQUITA': l'equita' la dà la riserva di tempo (un autoclicker non conviene più di una
## mano). Quindi nessuna rilevazione di regolarità, nessuna segnalazione, nessuna telemetria: il clic oltre il limite si ignora
## in silenzio. Classe pura: l'istante entra come argomento (microsecondi), mai letto dal sistema.
##
## `accept(now_usec)`: array circolare degli ultimi `max_cps` clic accettati. Si accetta se ce ne sono meno di `max_cps` oppure se
## il più vecchio è uscito dalla finestra (>= window_ms). Un istante MINORE dell'ultimo visto (orologio che torna indietro, eventi
## fuori ordine) conta come l'ultimo: non regala mai clic in più.

var max_cps: int
var window_usec: int
var _stamps: PackedInt64Array = PackedInt64Array()
var _count: int = 0
var _head: int = 0                 # posizione del più vecchio quando l'array è pieno (= prossima da sovrascrivere)
var _newest: int = -9223372036854775807


func _init(p_max_cps: int = 1, p_window_ms: int = 1000) -> void:
	max_cps = maxi(1, p_max_cps)
	window_usec = maxi(1, p_window_ms) * 1000
	_stamps.resize(max_cps)


## Dai dati (constants.time_push): nessun numero nel codice.
static func from_constants(k: Dictionary) -> ClickLimiter:
	var tp: Dictionary = k.get("time_push", {})
	return ClickLimiter.new(int(tp.get("max_cps", 1)), int(tp.get("window_ms", 1000)))


## I tasti ripetuti dal sistema operativo (event.echo) non sono clic: la cadenza del «tieni premuto» è un timer interno.
static func is_echo(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).echo


func accept(now_usec: int) -> bool:
	var now := maxi(now_usec, _newest)
	if _count >= max_cps and now - _stamps[_head] < window_usec:
		_newest = now
		return false
	if _count < max_cps:
		_stamps[(_head + _count) % max_cps] = now
		_count += 1
	else:
		_stamps[_head] = now
		_head = (_head + 1) % max_cps
	_newest = now
	return true


func reset() -> void:
	_count = 0
	_head = 0
	_newest = -9223372036854775807
