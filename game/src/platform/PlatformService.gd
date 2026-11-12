extends Node
## PlatformService (autoload) — unico punto di contatto tra il gioco e una piattaforma (Steam). Backend NULLO per default:
## senza Steam (o senza l'estensione GodotSteam) non si connette niente, non gira nessun _process e il gioco resta 100% offline.
## Il gioco non conosce Steam: sistemi e interfaccia ascoltano/chiamano solo EventBus; qui si traducono tre eventi in chiamate:
##   - EventBus.achievement_unlocked(id)  -> impresa Steam (tabella data/steam_achievements.json: ID stabili, fasi 1/2);
##   - cosa sta facendo l'Eroe            -> Rich Presence testuale (mai IP, mai nome del salvataggio);
##   - EventBus.save_completed / uscita   -> copia dei file slot_N.sav nel cloud (CloudSync).
## Mai il contrario: Steam non sblocca nulla nel gioco. Le imprese già sbloccate nel salvataggio e assenti su Steam si
## allineano a ogni caricamento. Documento: docs/review_1_0/14_STEAMWORKS_INTEGRAZIONE.md.

signal backend_changed(backend_name: String)

const PRESENCE_EVERY_S := 30.0
const CALLBACKS_EVERY_S := 0.25
const ENV_DISABLE := "VAULTFALL_NO_PLATFORM"

var backend: PlatformBackend = PlatformBackend.new()
var cloud: CloudSync
## Mappa id impresa del gioco -> {api, phase}; riempita da data/steam_achievements.json.
var _ach_map: Dictionary = {}
var _store_pending: bool = false
var _presence_acc: float = 0.0
var _callbacks_acc: float = 0.0
var _last_presence: String = ""
var _connected: bool = false
## Impostazioni di prova (i test le cambiano).
var cloud_enabled_override: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if OS.get_environment(ENV_DISABLE) == "1" or _is_test_run():
		return            # test e prove automatiche non parlano mai con un Steam vero (imprese, Cloud)
	if SteamBackend.is_available():
		var sb := SteamBackend.new()
		if sb.init():
			use_backend(sb)
		else:
			push_warning("PlatformService: Steam non disponibile (%s): si gioca offline." % sb.last_error)


## true se il processo e' una sessione GUT (riga di comando con -gtest / gut_cmdln).
static func _is_test_run() -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("-gtest") or a.contains("gut_cmdln"):
			return true
	return false


func platform_name() -> String:
	return backend.backend_name()


func is_active() -> bool:
	return backend != null and backend.is_active()


## Imposta il backend (all'avvio da _ready, nei test con un finto backend). null = backend nullo.
func use_backend(b: PlatformBackend) -> void:
	_disconnect_events()
	backend = b if b != null else PlatformBackend.new()
	_last_presence = ""
	_presence_acc = 0.0
	_store_pending = false
	_load_map()
	cloud = CloudSync.new(backend, SaveService.save_dir)
	set_process(is_active())
	if is_active():
		_connect_events()
		if _cloud_wanted():
			cloud.sync_all()
		sync_achievements()
		update_presence(true)
	backend_changed.emit(backend.backend_name())


func _cloud_wanted() -> bool:
	if cloud_enabled_override >= 0:
		return cloud_enabled_override == 1
	return AppConfig.steam_cloud()


func _load_map() -> void:
	_ach_map = {}
	for row in DataRegistry.table("steam_achievements"):
		_ach_map[str(row.get("id", ""))] = {"api": str(row.get("steam_api_name", "")), "phase": int(row.get("phase", 1))}


func _connect_events() -> void:
	if _connected:
		return
	_connected = true
	EventBus.achievement_unlocked.connect(_on_achievement)
	EventBus.state_loaded.connect(_on_state_loaded)
	EventBus.game_stopped.connect(_on_game_stopped)
	EventBus.save_completed.connect(_on_save_completed)


func _disconnect_events() -> void:
	if not _connected:
		return
	_connected = false
	EventBus.achievement_unlocked.disconnect(_on_achievement)
	EventBus.state_loaded.disconnect(_on_state_loaded)
	EventBus.game_stopped.disconnect(_on_game_stopped)
	EventBus.save_completed.disconnect(_on_save_completed)


func _process(delta: float) -> void:
	_callbacks_acc += delta
	if _callbacks_acc >= CALLBACKS_EVERY_S:
		_callbacks_acc = 0.0
		backend.run_callbacks()
	if _store_pending:
		_store_pending = false
		backend.store_stats()
	_presence_acc += delta
	if _presence_acc >= PRESENCE_EVERY_S:
		_presence_acc = 0.0
		update_presence()


func _exit_tree() -> void:
	if is_active():
		if cloud != null and _cloud_wanted():
			cloud.flush()
		backend.clear_presence()
		backend.shutdown()


# ---------------------------------------------------------------- imprese

func steam_id_of(achievement_id: String) -> String:
	return str(_ach_map.get(achievement_id, {}).get("api", ""))


## true se l'impresa va registrata ora su Steam (esiste nella tabella e la sua fase è già configurata su Steamworks).
func is_registered(achievement_id: String) -> bool:
	var m: Dictionary = _ach_map.get(achievement_id, {})
	return not m.is_empty() and int(m.phase) <= AppConfig.steam_achievement_phase()


## Sblocca su Steam l'impresa del gioco. Ritorna true se l'ha passata alla piattaforma.
func unlock(achievement_id: String) -> bool:
	if not is_active() or not is_registered(achievement_id):
		return false
	var api := steam_id_of(achievement_id)
	if backend.has_achievement(api):
		return false
	var ok := backend.unlock_achievement(api)
	if ok:
		_store_pending = true
	return ok


## Allinea Steam alle imprese già sbloccate nella partita in corso. Ritorna quante ne ha inviate.
func sync_achievements() -> int:
	if not is_active() or not GameState.active:
		return 0
	var n := 0
	for aid in GameState.data.get("achievements", []):
		if unlock(str(aid)):
			n += 1
	if n > 0:
		_store_pending = false
		backend.store_stats()
	return n


func _on_achievement(aid: String) -> void:
	unlock(aid)


func _on_state_loaded() -> void:
	sync_achievements()
	update_presence(true)


func _on_game_stopped() -> void:
	update_presence(true)


# ---------------------------------------------------------------- presenza

## Testo della Rich Presence: nel menù «Nel menù principale», in partita ciò che mostra la barra superiore.
func presence_text() -> String:
	if not GameState.active:
		return str(TranslationServer.translate("UI_PLAT_PRESENCE_MENU"))
	var t := ActivityText.text().strip_edges()
	return t if not t.is_empty() else str(TranslationServer.translate("UI_PLAT_PRESENCE_PLAYING"))


func update_presence(force: bool = false) -> void:
	if not is_active():
		return
	var t := presence_text()
	if t == _last_presence and not force:
		return
	_last_presence = t
	backend.set_presence(t)


# ---------------------------------------------------------------- cloud

func _on_save_completed(ok: bool) -> void:
	if ok and cloud != null and _cloud_wanted():
		cloud.save_dir = SaveService.save_dir
		cloud.upload_changed()
