class_name PlatformBackend
extends RefCounted
## Interfaccia della piattaforma (Steam o altro) e BACKEND NULLO: tutti i metodi non fanno nulla e rispondono «non disponibile».
## È il backend predefinito: il gioco resta identico e 100% offline quando Steam non c'è. I backend veri (SteamBackend) ereditano
## da qui e sovrascrivono SOLO ciò che sanno fare. Nessuna logica di gioco qui dentro: sistemi e interfaccia non lo conoscono.


## Nome corto del backend per i log e i test: "null", "steam".
func backend_name() -> String:
	return "null"


## Prova ad avviare la piattaforma. Ritorna true solo se è davvero utilizzabile (client avviato, account valido...).
func init() -> bool:
	return false


func is_active() -> bool:
	return false


func shutdown() -> void:
	pass


## Da chiamare periodicamente (a bassa frequenza) per le risposte asincrone della piattaforma.
func run_callbacks() -> void:
	pass


# ---------------------------------------------------------------- imprese

## true se l'impresa è già sbloccata sulla piattaforma (nome API stabile, es. ACH_WOODCUTTING_50).
func has_achievement(_api_name: String) -> bool:
	return false


## Sblocca l'impresa sulla piattaforma. Ritorna true se la piattaforma l'ha accettata.
func unlock_achievement(_api_name: String) -> bool:
	return false


## Conferma le modifiche (su Steam: storeStats). Da chiamare dopo una o più unlock_achievement.
func store_stats() -> bool:
	return false


# ---------------------------------------------------------------- presenza

func set_presence(_text: String) -> bool:
	return false


func clear_presence() -> void:
	pass


# ---------------------------------------------------------------- cloud (copia dei file di salvataggio, formato invariato)

func cloud_enabled() -> bool:
	return false


func cloud_exists(_name: String) -> bool:
	return false


## Istante (secondi Unix) dell'ultima scrittura del file nel cloud; 0 se non esiste.
func cloud_timestamp(_name: String) -> int:
	return 0


## Contenuto del file nel cloud (vuoto se manca o è illeggibile).
func cloud_read(_name: String) -> PackedByteArray:
	return PackedByteArray()


func cloud_write(_name: String, _bytes: PackedByteArray) -> bool:
	return false
