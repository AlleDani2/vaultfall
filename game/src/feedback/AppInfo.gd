class_name AppInfo
extends RefCounted
## Versione del gioco e registro delle novità (note di versione pubbliche).
## Fonti: res://version.json (numero, fase, build, data) e res://changelog.json (voci bilingui).
## `tools/make_release.py` tiene allineati version.json e project.godot (config/version) e copia il changelog nel LEGGIMI.
## Nessuna logica di gioco: solo etichette.

const VERSION_PATH := "res://version.json"
const CHANGELOG_PATH := "res://changelog.json"

static var _info: Dictionary = {}
static var _changelog: Array = []
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_info = {"version": "0.0.0", "stage": "", "build": 0, "date": ""}
	var v: Variant = _read_json(VERSION_PATH)
	if v is Dictionary:
		for k in v:
			_info[k] = v[k]
	else:
		var pv := str(ProjectSettings.get_setting("application/config/version", ""))
		if not pv.is_empty():
			_info["version"] = pv
	var c: Variant = _read_json(CHANGELOG_PATH)
	if c is Array:
		for e in c:
			if e is Dictionary and e.has("version"):
				_changelog.append(e)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Solo per i test: rilegge i file.
static func reload() -> void:
	_loaded = false
	_info = {}
	_changelog = []


static func version() -> String:
	_load()
	return str(_info.version)


static func stage() -> String:
	_load()
	return str(_info.get("stage", ""))


static func build() -> int:
	_load()
	return int(_info.get("build", 0))


static func release_date() -> String:
	_load()
	return str(_info.get("date", ""))


## «1.0.0» (numero + fase, solo se esiste una fase come «beta»).
static func version_tag() -> String:
	var s := stage()
	return version() + ("-" + s if not s.is_empty() else "")


## Nome del traguardo di rilascio («1.0»): campo "release" di version.json, solo per i metadati degli strumenti di rilascio.
static func release_label() -> String:
	_load()
	return str(_info.get("release", ""))


## Testo di versione da mostrare al giocatore: «1.0.0». UNICA fonte = game/version.json (la scrive tools/make_release.py).
static func version_label() -> String:
	return version_tag()


## Voci del changelog, dalla più recente: [{version, date, it: [..], en: [..]}].
static func changelog() -> Array:
	_load()
	return _changelog


## Voci di una lingua (ripiego sull'inglese).
static func entries_of(entry: Dictionary, lang: String) -> PackedStringArray:
	var src: Variant = entry.get(lang, entry.get("en", []))
	var out := PackedStringArray()
	if src is Array:
		for s in src:
			out.append(str(s))
	return out


## Changelog come testo semplice (LEGGIMI, riepiloghi, test).
static func changelog_text(lang: String) -> String:
	_load()
	var lines := PackedStringArray()
	for e in _changelog:
		lines.append("%s (%s)" % [e.version, e.get("date", "")])
		for s in entries_of(e, lang):
			lines.append("  - " + s)
		lines.append("")
	return "\n".join(lines).strip_edges()
