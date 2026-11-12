class_name SteamBackend
extends PlatformBackend
## Backend Steam: usa l'estensione GodotSteam (GDExtension) SE c'è. L'estensione NON è nel repository (vedi
## docs/review_1_0/14_STEAMWORKS_INTEGRAZIONE.md, dove metterla): senza di lei `is_available()` è false e il gioco usa il backend nullo.
## Tutte le chiamate passano da `call()` sul singleton `Steam`, così questo file si carica anche quando l'estensione manca.
## Nomi delle funzioni di GodotSteam 4.x (da ricontrollare sulla versione scelta, docs/23 §6): steamInitEx, run_callbacks, getAchievement,
## setAchievement, storeStats, setRichPresence, clearRichPresence, fileExists, fileWrite, fileRead, getFileSize, getFileTimestamp.

const SINGLETON := "Steam"
const PRESENCE_MAX_BYTES := 250          # Steam accetta valori fino a 256 byte

var _steam: Object = null
var _active: bool = false
var last_error: String = ""


## true se l'estensione GodotSteam è caricata in questo processo (non vuol dire che Steam sia avviato).
static func is_available() -> bool:
	return Engine.has_singleton(SINGLETON)


func backend_name() -> String:
	return "steam"


func init() -> bool:
	_active = false
	last_error = ""
	if not is_available():
		last_error = "extension_missing"
		return false
	_steam = Engine.get_singleton(SINGLETON)
	if _steam == null:
		last_error = "extension_missing"
		return false
	var app_id := AppConfig.steam_app_id()
	if app_id > 0 and OS.get_environment("SteamAppId").is_empty():
		OS.set_environment("SteamAppId", str(app_id))     # in sviluppo; da Steam arriva già il valore giusto
		OS.set_environment("SteamGameId", str(app_id))
	var ok := false
	if _steam.has_method("steamInitEx"):
		var r: Variant = _steam.call("steamInitEx")
		ok = (r is Dictionary and int((r as Dictionary).get("status", -1)) == 0) or (r is bool and r)
		if not ok:
			last_error = str((r as Dictionary).get("verbal", "init_failed")) if r is Dictionary else "init_failed"
	elif _steam.has_method("steamInit"):
		var r2: Variant = _steam.call("steamInit")
		ok = (r2 is Dictionary and int((r2 as Dictionary).get("status", 0)) == 1) or (r2 is bool and r2)
		if not ok:
			last_error = "init_failed"
	else:
		last_error = "no_init_method"
	if ok and _steam.has_method("isSteamRunning") and not bool(_steam.call("isSteamRunning")):
		ok = false
		last_error = "steam_not_running"
	_active = ok
	return ok


func is_active() -> bool:
	return _active and _steam != null


func shutdown() -> void:
	if is_active() and _steam.has_method("steamShutdown"):
		_steam.call("steamShutdown")
	_active = false


func run_callbacks() -> void:
	if is_active() and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")


# ---------------------------------------------------------------- imprese

func has_achievement(api_name: String) -> bool:
	if not is_active() or not _steam.has_method("getAchievement"):
		return false
	var r: Variant = _steam.call("getAchievement", api_name)
	if r is Dictionary:
		return bool((r as Dictionary).get("achieved", false))
	return bool(r)


func unlock_achievement(api_name: String) -> bool:
	if not is_active() or api_name.is_empty() or not _steam.has_method("setAchievement"):
		return false
	return bool(_steam.call("setAchievement", api_name))


func store_stats() -> bool:
	if not is_active() or not _steam.has_method("storeStats"):
		return false
	return bool(_steam.call("storeStats"))


# ---------------------------------------------------------------- presenza

func set_presence(text: String) -> bool:
	if not is_active() or not _steam.has_method("setRichPresence"):
		return false
	var t := _clip(text)
	# «steam_display» punta al testo localizzato del file di Rich Presence (tools/steam/rich_presence.vdf); %status% è il testo già
	# tradotto dal gioco nella lingua del giocatore.
	_steam.call("setRichPresence", "steam_display", "#Status")
	return bool(_steam.call("setRichPresence", "status", t))


func clear_presence() -> void:
	if is_active() and _steam.has_method("clearRichPresence"):
		_steam.call("clearRichPresence")


## Taglia a PRESENCE_MAX_BYTES byte UTF-8 senza spezzare un carattere.
static func _clip(text: String) -> String:
	var t := text.strip_edges()
	while t.to_utf8_buffer().size() > PRESENCE_MAX_BYTES and t.length() > 1:
		t = t.substr(0, t.length() - 1)
	return t


# ---------------------------------------------------------------- cloud

func cloud_enabled() -> bool:
	if not is_active() or not AppConfig.steam_cloud():
		return false
	for m in ["isCloudEnabledForApp", "isCloudEnabledForAccount"]:
		if not _steam.has_method(m) or not bool(_steam.call(m)):
			return false
	return true


func cloud_exists(file_name: String) -> bool:
	return is_active() and _steam.has_method("fileExists") and bool(_steam.call("fileExists", file_name))


func cloud_timestamp(file_name: String) -> int:
	if not cloud_exists(file_name) or not _steam.has_method("getFileTimestamp"):
		return 0
	return int(_steam.call("getFileTimestamp", file_name))


func cloud_read(file_name: String) -> PackedByteArray:
	if not cloud_exists(file_name) or not _steam.has_method("fileRead") or not _steam.has_method("getFileSize"):
		return PackedByteArray()
	var size := int(_steam.call("getFileSize", file_name))
	if size <= 0:
		return PackedByteArray()
	var r: Variant = _steam.call("fileRead", file_name, size)
	if r is Dictionary and bool((r as Dictionary).get("ret", false)):
		var buf: Variant = (r as Dictionary).get("buf", PackedByteArray())
		return buf if buf is PackedByteArray else PackedByteArray()
	if r is PackedByteArray:
		return r
	return PackedByteArray()


func cloud_write(file_name: String, bytes: PackedByteArray) -> bool:
	if not is_active() or not _steam.has_method("fileWrite"):
		return false
	return bool(_steam.call("fileWrite", file_name, bytes))
