class_name ErrorLog
extends RefCounted
## Registro locale degli errori (errori di script e di motore, avvisi) in user://logs/.
## - Un file per avvio: vaultfall.log (avvio corrente), vaultfall.1.log (precedente)… fino a `keep` file in tutto.
## - Dimensione massima per file (`max_bytes`): oltre, si scrive un'ultima riga «troncato» e si smette.
## - Stesso errore ripetuto di fila: una riga + «ripetuto N volte»; stessa origine (file:riga) oltre PER_SOURCE_MAX volte: soppresso.
## - Non rallenta il gioco: `add()` mette solo una riga in memoria (thread-safe, il motore può chiamarlo da qualsiasi thread);
##   la scrittura avviene in `flush()`, chiamato dal nodo Feedback ogni mezzo secondo e solo se c'è qualcosa da scrivere.
## - Tutto LOCALE. Nessuna rete.

const DEFAULT_DIR := "user://logs"
const BASE_NAME := "vaultfall"
const MAX_BYTES := 262144
const KEEP := 5
const PER_SOURCE_MAX := 20
const BUFFER_MAX := 400

var dir: String = DEFAULT_DIR
var max_bytes: int = MAX_BYTES
var keep: int = KEEP

var _mutex := Mutex.new()
var _buffer := PackedStringArray()
var _bytes: int = 0
var _truncated: bool = false
var _last_key: String = ""
var _repeat: int = 0
var _per_source: Dictionary = {}
var _suppressed: int = 0
var _dropped: int = 0
var _started: bool = false
var _error_lines: int = 0


func current_path() -> String:
	return dir.path_join(BASE_NAME + ".log")


func old_path(n: int) -> String:
	return dir.path_join("%s.%d.log" % [BASE_NAME, n])


func is_started() -> bool:
	return _started


## Righe di errore/avviso scritte in questa sessione (per il riepilogo).
func error_count() -> int:
	return _error_lines


## Nuovo avvio: ruota i file (il più vecchio viene cancellato) e apre quello corrente con l'intestazione.
func start_session(header: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_mutex.lock()
	_buffer.clear()
	_bytes = 0
	_truncated = false
	_last_key = ""
	_repeat = 0
	_per_source.clear()
	_suppressed = 0
	_dropped = 0
	_error_lines = 0
	_mutex.unlock()
	rotate_files()
	var f := FileAccess.open(current_path(), FileAccess.WRITE)
	if f != null:
		var line := "=== %s ===\n" % header
		f.store_string(line)
		_bytes = line.length()
		f.close()
	_started = true


## vaultfall.(keep-1).log si cancella, ogni altro scala di uno, il corrente diventa .1.
func rotate_files() -> void:
	var oldest := old_path(keep - 1)
	if keep >= 2 and FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	if keep == 1 and FileAccess.file_exists(current_path()):
		DirAccess.remove_absolute(current_path())
		return
	for n in range(keep - 1, 1, -1):
		var src := old_path(n - 1)
		if FileAccess.file_exists(src):
			_replace(src, old_path(n))
	if FileAccess.file_exists(current_path()):
		_replace(current_path(), old_path(1))


static func _replace(src: String, dst: String) -> void:
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	DirAccess.rename_absolute(src, dst)


## Aggiunge una riga (thread-safe, a costo quasi nullo). level: ERROR | SCRIPT | WARNING | SHADER | INFO.
## `source` = «file:riga» (serve a limitare le ripetizioni).
func add(level: String, text: String, source: String = "") -> void:
	_mutex.lock()
	if _truncated:
		_mutex.unlock()
		return
	var key := level + "|" + source + "|" + text
	if key == _last_key:
		_repeat += 1
		_mutex.unlock()
		return
	if not source.is_empty():
		var n := int(_per_source.get(source, 0)) + 1
		_per_source[source] = n
		if n > PER_SOURCE_MAX:
			_suppressed += 1
			_mutex.unlock()
			return
	_close_repeat_locked()
	_last_key = key
	if _buffer.size() >= BUFFER_MAX:
		_dropped += 1
	else:
		var stamp := Time.get_time_string_from_system()
		var where := " (%s)" % source if not source.is_empty() else ""
		_buffer.append("[%s] %s: %s%s" % [stamp, level, text, where])
		if level != "INFO":
			_error_lines += 1
	_mutex.unlock()


func _close_repeat_locked() -> void:
	if _repeat > 0:
		_buffer.append("    ^ ripetuto %d volte" % _repeat)
		_repeat = 0


## Scrive su disco quel che è in coda. Da chiamare dal thread principale. Ritorna le righe scritte.
func flush(final: bool = false) -> int:
	_mutex.lock()
	if final:
		_close_repeat_locked()
		if _suppressed > 0:
			_buffer.append("    (%d righe soppresse: stessa origine troppe volte)" % _suppressed)
			_suppressed = 0
		if _dropped > 0:
			_buffer.append("    (%d righe perse: troppi errori insieme)" % _dropped)
			_dropped = 0
	var lines := _buffer.duplicate()
	_buffer.clear()
	_mutex.unlock()
	if lines.is_empty() or not _started:
		return 0
	var out := PackedStringArray()
	for l in lines:
		if _bytes + l.length() + 1 > max_bytes:
			if not _truncated:
				out.append("=== LOG TROPPO LUNGO (limite %d KB): il resto non viene scritto ===" % int(max_bytes / 1024.0))
				_mutex.lock()
				_truncated = true
				_mutex.unlock()
			break
		out.append(l)
		_bytes += l.length() + 1
	if out.is_empty():
		return 0
	var f := FileAccess.open(current_path(), FileAccess.READ_WRITE)
	if f == null:
		return 0
	f.seek_end()
	f.store_string("\n".join(out) + "\n")
	f.close()
	return out.size()


## Chiusura pulita (scrive code, ripetizioni e righe soppresse).
func close() -> void:
	flush(true)
	_started = false


## Elenco dei file di registro esistenti, dal più recente.
func files() -> PackedStringArray:
	var out := PackedStringArray()
	if FileAccess.file_exists(current_path()):
		out.append(current_path())
	for n in range(1, keep):
		if FileAccess.file_exists(old_path(n)):
			out.append(old_path(n))
	return out


## Coda del registro (avvio corrente, poi il precedente se c'è spazio), al massimo `limit` byte di testo.
func recent_text(limit: int = 65536) -> String:
	flush()
	var parts := PackedStringArray()
	var used := 0
	for p in files():
		var t := FileAccess.get_file_as_string(p)
		if used + t.length() > limit:
			t = t.substr(maxi(0, t.length() - (limit - used)))
		parts.append("##### %s #####\n%s" % [p.get_file(), t])
		used += t.length()
		if used >= limit:
			break
	return "\n".join(parts)


## Cancella tutti i file di registro.
func clear_files() -> void:
	for p in files():
		DirAccess.remove_absolute(p)


# ------------------------------------------------------------------ aggancio al motore

## Ascoltatore del motore (OS.add_logger). Il motore lo chiama da QUALSIASI thread: solo `ErrorLog.add`, niente push_error
## (si innescherebbe da solo).
class Sink extends Logger:
	var target: ErrorLog

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if target == null:
			return
		var level := "ERROR"
		match error_type:
			Logger.ERROR_TYPE_WARNING: level = "WARNING"
			Logger.ERROR_TYPE_SCRIPT: level = "SCRIPT"
			Logger.ERROR_TYPE_SHADER: level = "SHADER"
		var text := rationale if not rationale.is_empty() else code
		if not code.is_empty() and not rationale.is_empty() and code != rationale:
			text = "%s - %s" % [code, rationale]
		target.add(level, text, "%s:%d" % [file.get_file(), line] if not file.is_empty() else function)

	func _log_message(_message: String, _error: bool) -> void:
		pass          # il normale output (print) non ci interessa: solo errori e avvisi


func make_sink() -> Sink:
	var s := Sink.new()
	s.target = self
	return s
