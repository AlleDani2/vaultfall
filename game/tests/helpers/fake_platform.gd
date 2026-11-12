class_name TestFakePlatform
extends PlatformBackend
## Finto backend di piattaforma per i test: imprese e cloud in memoria. Nessuna rete, nessuna estensione.

var active: bool = true
var cloud_on: bool = true
var achievements: Dictionary = {}
var stored: int = 0
var presence: String = ""
var presence_sets: int = 0
var files: Dictionary = {}                  # nome -> PackedByteArray
var stamps: Dictionary = {}                 # nome -> istante Unix
var writes: int = 0
var clock: int = 1000
var refuse_write: bool = false


func backend_name() -> String:
	return "fake"


func init() -> bool:
	return active


func is_active() -> bool:
	return active


func has_achievement(api_name: String) -> bool:
	return achievements.has(api_name)


func unlock_achievement(api_name: String) -> bool:
	achievements[api_name] = true
	return true


func store_stats() -> bool:
	stored += 1
	return true


func set_presence(text: String) -> bool:
	presence = text
	presence_sets += 1
	return true


func clear_presence() -> void:
	presence = ""


func cloud_enabled() -> bool:
	return cloud_on


func cloud_exists(file_name: String) -> bool:
	return files.has(file_name)


func cloud_timestamp(file_name: String) -> int:
	return int(stamps.get(file_name, 0))


func cloud_read(file_name: String) -> PackedByteArray:
	return files.get(file_name, PackedByteArray())


func cloud_write(file_name: String, bytes: PackedByteArray) -> bool:
	if refuse_write:
		return false
	files[file_name] = bytes
	stamps[file_name] = clock
	writes += 1
	return true
