class_name LocalFileLink
extends CoopLink
## Trasporto su cartella (COOP-1): ogni messaggio è un file `<seq>_<mittente>.msg` nella cartella della sessione, scritto in modo
## atomico (file temporaneo + rinomina). Serve alle prove e a due istanze sullo stesso PC; NON è una rete.
## Il contenuto è la busta di CoopLinkMessage.encode (stesso testo che viaggerebbe in rete).

const EXT := ".msg"

var base_dir: String = ""
var _dir: String = ""
var _open: bool = false
var _seen: Dictionary = {}
var _peers: Dictionary = {}
var sent: int = 0


func _init(p_base_dir: String = "user://coop/local") -> void:
	base_dir = p_base_dir


func open(p_role: int, p_session: String, p_local: String) -> bool:
	if p_session.is_empty() or p_local.is_empty() or not _safe(p_session) or not _safe(p_local):
		return false
	role = p_role
	session_id = p_session
	local_id = p_local
	_dir = base_dir.path_join(p_session)
	if DirAccess.make_dir_recursive_absolute(_dir) != OK and not DirAccess.dir_exists_absolute(_dir):
		return false
	_open = true
	_seen.clear()
	_peers.clear()
	_seq = 0
	return true


func close() -> void:
	_open = false


func is_open() -> bool:
	return _open


func peers() -> Array:
	var out: Array = _peers.keys()
	out.sort()
	return out


func send(msg: Dictionary) -> bool:
	if not _open:
		return false
	if not bool(CoopLinkMessage.validate(msg).ok) or str(msg.from) != local_id or str(msg.s) != session_id:
		return false
	var text := CoopLinkMessage.encode(msg)
	if text.is_empty():
		return false
	var file_name := "%09d_%s%s" % [int(msg.seq), local_id, EXT]
	var final_path := _dir.path_join(file_name)
	var tmp := final_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, final_path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	sent += 1
	return true


func poll() -> Array:
	var out: Array = []
	if not _open:
		return out
	var names: PackedStringArray = DirAccess.get_files_at(_dir)
	var fresh: Array = []
	for n in names:
		if n.ends_with(EXT) and not _seen.has(n):
			fresh.append(n)
	fresh.sort()                                   # "<seq con zeri>_<mittente>": ordine per seq, poi per mittente
	for n in fresh:
		_seen[n] = true
		var f := FileAccess.open(_dir.path_join(n), FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var r := CoopLinkMessage.decode(text)
		if not bool(r.ok):
			continue                               # file corrotto o manomesso: ignorato, mai un crash
		var m: Dictionary = r.msg
		if str(m.s) != session_id or str(m.from) == local_id:
			continue
		if not str(m.get("to", "")).is_empty() and str(m.to) != local_id:
			continue
		match str(m.t):
			"hello", "hello_ack":
				_peers[str(m.from)] = true
			"bye":
				_peers.erase(str(m.from))
		out.append(m)
		message_received.emit(m)
	return out


## Cancella i file della sessione (pulizia nelle prove).
func wipe() -> void:
	if _dir.is_empty() or not DirAccess.dir_exists_absolute(_dir):
		return
	for n in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(n))


static func _safe(s: String) -> bool:
	if s.length() > 48:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 95):
			return false
	return true
