class_name AppConfig
extends RefCounted
## Configurazione del prodotto in UN solo file: res://app_config.json (nel pacchetto di gioco, accanto a version.json).
## Qui stanno i contatti di assistenza (pulsante «Segnala un problema»), i link pubblici e le impostazioni di Steam.
## Nessun numero di bilanciamento: solo indirizzi e interruttori di pubblicazione. Un campo vuoto = «non configurato»:
## il gioco funziona lo stesso e la funzione corrispondente si nasconde.

const PATH := "res://app_config.json"

static var _cfg: Dictionary = {}
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cfg = {}
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_cfg = parsed


## Solo test: sostituisce la configurazione (null = ricarica dal file).
static func override(cfg: Variant) -> void:
	if cfg is Dictionary:
		_cfg = cfg
		_loaded = true
	else:
		_loaded = false
		_load()


static func get_string(key: String) -> String:
	_load()
	return str(_cfg.get(key, "")).strip_edges()


static func support_url() -> String:
	return get_string("support_url")


static func support_email() -> String:
	return get_string("support_email")


static func privacy_url() -> String:
	return get_string("privacy_url")


static func wiki_url() -> String:
	return get_string("wiki_url")


static func store_url() -> String:
	return get_string("store_url")


static func steam_app_id() -> int:
	_load()
	return maxi(0, int(_cfg.get("steam_app_id", 0)))


## Fase delle imprese registrate su Steamworks (1 = le prime 100, 2 = tutte e 118).
static func steam_achievement_phase() -> int:
	_load()
	return clampi(int(_cfg.get("steam_achievement_phase", 1)), 1, 2)


static func steam_cloud() -> bool:
	_load()
	return bool(_cfg.get("steam_cloud", true))


## Indirizzo o pagina da mostrare a chi vuole contattare l'assistenza (vuoto se non configurato).
static func support_contact() -> String:
	var u := support_url()
	return u if not u.is_empty() else support_email()


static func has_support() -> bool:
	return not support_contact().is_empty()


## Solo http/https/mailto: niente schemi strani da un file di configurazione.
static func is_safe_url(u: String) -> bool:
	return u.begins_with("https://") or u.begins_with("http://") or u.begins_with("mailto:")


## Apre la pagina di assistenza (o il client di posta). Ritorna true se ha provato ad aprire qualcosa.
static func open_support() -> bool:
	var target := support_url()
	if target.is_empty() and not support_email().is_empty():
		target = "mailto:" + support_email()
	if target.is_empty() or not is_safe_url(target):
		return false
	OS.shell_open(target)
	return true
