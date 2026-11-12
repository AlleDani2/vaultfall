class_name CloudSync
extends RefCounted
## Cloud dei salvataggi come COPIA DEI FILE `slot_N.sav`: il formato non cambia (si copiano i byte così come sono, nessuna
## decodifica) e SaveService/SaveCodec non vengono toccati. Funziona solo con un backend che offre il cloud (Steam Remote
## Storage); con il backend nullo non fa nulla. Regole prudenti (R-SAV-1/2 restano di SaveService):
##   - non cancella mai niente, né in locale né nel cloud;
##   - se il cloud ha una copia più recente e diversa, prima di sostituire il file locale ne tiene una copia
##     `slot_N.sav.pre_cloud_<istante>` (le ultime KEEP_PRE_CLOUD);
##   - se il file locale è più recente (o il cloud non ha nulla) lo carica nel cloud;
##   - il file scaricato si scrive in modo atomico (.tmp + rinomina); un salvataggio di schema più nuovo lo gestisce poi
##     SaveService con il suo messaggio («versione più recente»);
##   - attenzione (docs/review_1_0/14): il tempo di assenza dipende dall'orologio del PC; con orologi molto diversi tra due PC il
##     bonus di assenza può risultare nullo o maggiore del dovuto (vedi anche il tetto di 12/24 h).
## `.tmp`, `.bak*`, `.day_*`, `.pre_v*`, impostazioni e registri NON vanno nel cloud (restano su ogni PC).

const SLOTS := 3
const KEEP_PRE_CLOUD := 3
const MIN_UPLOAD_GAP_S := 120.0

var backend: PlatformBackend
var save_dir: String = "user://saves"
## Esiti dell'ultimo giro: file -> "uploaded" | "downloaded" | "same" | "skipped" | "failed".
var last_result: Dictionary = {}
## Firma (SHA-256 del contenuto) dell'ultimo file locale caricato o riconosciuto uguale, per non ricaricare lo stesso file.
var _synced_sig: Dictionary = {}
var _last_upload_unix: Dictionary = {}


func _init(p_backend: PlatformBackend = null, p_dir: String = "user://saves") -> void:
	backend = p_backend if p_backend != null else PlatformBackend.new()
	save_dir = p_dir


static func cloud_name(slot: int) -> String:
	return "saves/slot_%d.sav" % slot


func local_path(slot: int) -> String:
	return save_dir.path_join("slot_%d.sav" % slot)


func is_enabled() -> bool:
	return backend != null and backend.is_active() and backend.cloud_enabled()


## Giro completo (all'avvio, prima che si scelga lo slot): confronta ogni slot con il cloud.
func sync_all(now_unix: int = -1) -> Dictionary:
	last_result = {}
	if not is_enabled():
		return last_result
	for s in range(1, SLOTS + 1):
		last_result[cloud_name(s)] = sync_slot(s, now_unix)
	return last_result


func sync_slot(slot: int, now_unix: int = -1) -> String:
	var cname := cloud_name(slot)
	var lpath := local_path(slot)
	var has_local := FileAccess.file_exists(lpath)
	var has_cloud := backend.cloud_exists(cname)
	if not has_local and not has_cloud:
		return "skipped"
	if has_local and not has_cloud:
		return "uploaded" if upload_slot(slot, now_unix, true) else "failed"
	if has_cloud and not has_local:
		return "downloaded" if _download(slot, now_unix) else "failed"
	var local_bytes := FileAccess.get_file_as_bytes(lpath)
	var cloud_bytes := backend.cloud_read(cname)
	if cloud_bytes.is_empty():
		return "failed"                       # cloud illeggibile: non si tocca nulla
	if _digest(local_bytes) == _digest(cloud_bytes):
		_synced_sig[slot] = _signature(lpath)
		return "same"
	if backend.cloud_timestamp(cname) > FileAccess.get_modified_time(lpath) + 1:
		_keep_local_copy(slot, now_unix)
		return "downloaded" if _write_local(slot, cloud_bytes) else "failed"
	return "uploaded" if upload_slot(slot, now_unix, true) else "failed"


## Carica nel cloud il file locale dello slot. `force` salta il limite di frequenza e il controllo «già caricato».
func upload_slot(slot: int, now_unix: int = -1, force: bool = false) -> bool:
	if not is_enabled():
		return false
	var lpath := local_path(slot)
	if not FileAccess.file_exists(lpath):
		return false
	if not force:
		var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
		if float(now - int(_last_upload_unix.get(slot, -1000000))) < MIN_UPLOAD_GAP_S:
			return false
	var sig := _signature(lpath)
	if not force and _synced_sig.get(slot, "") == sig:
		return false
	var bytes := FileAccess.get_file_as_bytes(lpath)
	if bytes.is_empty():
		return false
	if not backend.cloud_write(cloud_name(slot), bytes):
		return false
	_synced_sig[slot] = sig
	_last_upload_unix[slot] = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	return true


## Dopo un salvataggio riuscito (EventBus.save_completed): carica gli slot cambiati, al massimo uno ogni MIN_UPLOAD_GAP_S.
func upload_changed(now_unix: int = -1) -> int:
	var n := 0
	for s in range(1, SLOTS + 1):
		if upload_slot(s, now_unix, false):
			n += 1
	return n


## All'uscita: carica subito ciò che è cambiato, senza limite di frequenza.
func flush(now_unix: int = -1) -> int:
	var n := 0
	for s in range(1, SLOTS + 1):
		if FileAccess.file_exists(local_path(s)) and _synced_sig.get(s, "") != _signature(local_path(s)):
			if upload_slot(s, now_unix, true):
				n += 1
	return n


func _download(slot: int, now_unix: int) -> bool:
	var bytes := backend.cloud_read(cloud_name(slot))
	if bytes.is_empty():
		return false
	return _write_local(slot, bytes)


## Scrittura atomica del file locale (.tmp + rinomina) e rilettura di controllo.
func _write_local(slot: int, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	var lpath := local_path(slot)
	var tmp := lpath + ".cloud_tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	if FileAccess.get_file_as_bytes(tmp).size() != bytes.size():
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, lpath) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	_synced_sig[slot] = _signature(lpath)
	return true


## Copia di sicurezza del file locale prima di sostituirlo con quello del cloud.
func _keep_local_copy(slot: int, now_unix: int) -> void:
	var lpath := local_path(slot)
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var dst := "%s.pre_cloud_%d" % [lpath, now]
	var bytes := FileAccess.get_file_as_bytes(lpath)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	_prune_pre_cloud(slot)


func _prune_pre_cloud(slot: int) -> void:
	var prefix := "slot_%d.sav.pre_cloud_" % slot
	var found: Array = []
	var d := DirAccess.open(save_dir)
	if d == null:
		return
	for name in d.get_files():
		if name.begins_with(prefix):
			found.append(name)
	found.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix(prefix)) > int(b.trim_prefix(prefix)))
	for i in range(KEEP_PRE_CLOUD, found.size()):
		DirAccess.remove_absolute(save_dir.path_join(found[i]))


func _signature(path: String) -> String:
	return FileAccess.get_sha256(path)       # contenuto, non data: due salvataggi nello stesso secondo restano distinti


static func _digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
