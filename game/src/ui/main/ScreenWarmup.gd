class_name ScreenWarmup
extends Node
## Precaricamento delle schermate in background (resoconto docs/audit_2026-10-22/100_RESOCONTO_PRESTAZIONI.md).
## La PRIMA apertura di una schermata costa 100-300 ms di CPU su un PC lento perché compila gli script della scena
## (la seconda apertura costa 20-80 ms): un blocco visibile a ogni nuova schermata per tutta la prima ora di gioco.
## Qui una scena alla volta, ogni STEP_S secondi e solo con la finestra in primo piano, viene caricata da un thread
## (`ResourceLoader.load_threaded_*`); la PackedScene resta in mano a questo nodo, quindi script e risorse restano
## compilati e `show_screen` trova tutto pronto. Solo schermate già sbloccate (le altre si aggiungono allo sblocco).
## Non parte nei test (MainScreen lo aggiunge solo se è la scena principale) né su un PC con un solo processore.

const STEP_S := 0.4

var _queue: Array[String] = []
var _held: Dictionary = {}              # percorso -> PackedScene (tenuta: script e risorse restano in memoria)
var _cur: String = ""                   # scena in caricamento nel thread ("" = nessuna)
var _timer := Timer.new()


func _ready() -> void:
	name = "ScreenWarmup"
	if OS.get_processor_count() <= 1:
		return
	_timer.wait_time = STEP_S
	_timer.timeout.connect(_step)
	add_child(_timer)
	EventBus.unlocked.connect(func(_t: String) -> void: enqueue_available())
	enqueue_available()


## Mette in coda le scene delle schermate disponibili non ancora tenute (una volta ciascuna).
func enqueue_available() -> void:
	var unlocks: Array = GameState.data.get("unlocks", [])
	for e in ScreenRegistry.entries():
		var path := str(e.get("scene", ""))
		if path.is_empty() or _held.has(path) or _queue.has(path) or path == _cur:
			continue
		if ScreenRegistry.is_available(e, unlocks):
			_queue.append(path)
	if not _queue.is_empty() and _timer.is_inside_tree() and _timer.is_stopped():
		_timer.start()


func pending() -> int:
	return _queue.size() + (1 if not _cur.is_empty() else 0)


func held_count() -> int:
	return _held.size()


func _step() -> void:
	if not Clock.focused:
		return
	if not _cur.is_empty():
		var st := ResourceLoader.load_threaded_get_status(_cur)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_held[_cur] = ResourceLoader.load_threaded_get(_cur)
		_cur = ""
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		if _held.has(path):
			continue
		if ResourceLoader.has_cached(path):         # già caricata da show_screen: basta tenerla
			_held[path] = load(path)
			continue
		if ResourceLoader.load_threaded_request(path, "PackedScene", false) == OK:
			_cur = path
			return
	_timer.stop()


## Se si lascia la schermata principale (o si esce) con un caricamento in corso lo si aspetta: niente caricamenti
## interrotti a metà nel registro errori.
func _exit_tree() -> void:
	if not _cur.is_empty() and ResourceLoader.load_threaded_get_status(_cur) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		ResourceLoader.load_threaded_get(_cur)
		_cur = ""
