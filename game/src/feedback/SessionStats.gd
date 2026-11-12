class_name SessionStats
extends RefCounted
## Statistiche di sessione LOCALI, a scelta del giocatore (spente di default: Settings "stats_opt_in").
## Servono a capire DOVE CI SI ANNOIA: tempo tra una ricompensa e l'altra, schermate più usate, tempo per capitolo,
## morti e uscite dal gioco per capitolo. Solo numeri aggregati: niente nomi, testo libero, percorsi, indirizzi.
## Il file sta in user://stats/ ed è esportabile (CSV/JSON) e cancellabile. Un ID casuale generato qui (non legato a Steam
## né al PC) lo distingue da altri file se più amici ne mandano uno. Nessuna rete.
## Pura: non conosce autoload né nodi; chi la usa (nodo Feedback) le passa schermata e capitolo.

const FORMAT := 1
const DEFAULT_PATH := "user://stats/session_stats.json"
const MAX_SESSIONS := 100
## Soglie in secondi di gioco attivo tra due ricompense.
const GAP_BUCKETS: PackedStringArray = ["lt_1m", "1_5m", "5_15m", "15_30m", "30_60m", "gt_60m"]
const GAP_LIMITS: Array[float] = [60.0, 300.0, 900.0, 1800.0, 3600.0]
## Eventi che contano come «ricompensa» per il tempo tra ricompense.
const REWARD_KINDS: PackedStringArray = ["level_up", "quest", "crate", "achievement", "pet", "star", "boss"]

var path: String = DEFAULT_PATH
var enabled: bool = false
var data: Dictionary = {}

var _since_reward: float = 0.0
var _session: Dictionary = {}
var _dirty: bool = false


static func fresh() -> Dictionary:
	var gaps := {}
	for b in GAP_BUCKETS:
		gaps[b] = 0
	return {
		"format": FORMAT, "install_id": "", "created_day": "", "game_version": "",
		"sessions": [], "screens": {}, "rewards": {}, "reward_gaps": gaps,
		"reward_gap_max_s": 0.0, "reward_gap_sum_s": 0.0, "reward_gap_count": 0,
		"chapters": {}, "totals": {"active_s": 0.0, "sessions": 0, "deaths": 0, "exits": 0},
	}


func _init() -> void:
	data = fresh()


## ID casuale locale di 16 caratteri esadecimali.
static func make_id() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()


func has_data() -> bool:
	return int(data.totals.sessions) > 0 or int(data.totals.active_s) > 0


func install_id() -> String:
	return str(data.install_id)


# ------------------------------------------------------------------ attivazione e file

## Attiva/disattiva la registrazione. Al primo attivarsi nasce l'ID casuale. Spegnere NON cancella il file.
func set_enabled(on: bool, today: String = "") -> void:
	enabled = on
	if on and str(data.install_id).is_empty():
		data["install_id"] = make_id()
		data["created_day"] = today if not today.is_empty() else Time.get_date_string_from_system()
		_dirty = true


func load_file() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary) or int(v.get("format", 0)) != FORMAT:
		return false
	var base := fresh()
	for k in base:
		if v.has(k) and _same_kind(v[k], base[k]):
			base[k] = v[k]
	data = base
	return true


## JSON restituisce solo float: interi e decimali sono lo stesso «tipo» numero.
static func _same_kind(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return true
	return typeof(a) == typeof(b)


func save_file() -> bool:
	if not enabled and not has_data():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var ok := DirAccess.rename_absolute(tmp, path) == OK
	_dirty = not ok
	return ok


func is_dirty() -> bool:
	return _dirty


## «Cancella tutto»: dati in memoria, file, ID. Dopo, se si riattiva, nasce un ID nuovo.
func clear_all() -> void:
	data = fresh()
	_since_reward = 0.0
	_session = {}
	_dirty = false
	for p in [path, path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if enabled:
		set_enabled(true)          # la registrazione prosegue, con un ID nuovo


# ------------------------------------------------------------------ registrazione (no-op se spenta)

func begin_session(version: String, chapter: int, today: String = "") -> void:
	if not enabled:
		return
	data["game_version"] = version
	_since_reward = 0.0
	_session = {"n": int(data.totals.sessions) + 1, "day": today if not today.is_empty() else Time.get_date_string_from_system(),
		"version": version, "active_s": 0.0, "start_chapter": chapter, "end_chapter": chapter, "exit_screen": ""}
	data.totals["sessions"] = int(data.totals.sessions) + 1
	var arr: Array = data.sessions
	arr.append(_session)
	while arr.size() > MAX_SESSIONS:
		arr.pop_front()
	_dirty = true


## Passa il tempo di gioco ATTIVO (finestra in primo piano, partita in corso, non in pausa).
func tick(dt: float, screen: String, chapter: int) -> void:
	if not enabled or dt <= 0.0:
		return
	_since_reward += dt
	data.totals["active_s"] = float(data.totals.active_s) + dt
	if not screen.is_empty():
		_add(data.screens, screen, dt)
	var ch := _chapter(chapter)
	ch["active_s"] = float(ch.get("active_s", 0.0)) + dt
	if not _session.is_empty():
		_session["active_s"] = float(_session.active_s) + dt
		_session["end_chapter"] = chapter
	_dirty = true


## Un capitolo visto per la prima volta: memorizza a che punto del tempo di gioco totale (secondi di partita).
func note_chapter_reached(chapter: int, playtime_s: float) -> void:
	if not enabled:
		return
	var ch := _chapter(chapter)
	if not ch.has("first_playtime_s"):
		ch["first_playtime_s"] = playtime_s
		_dirty = true


func on_reward(kind: String) -> void:
	if not enabled:
		return
	_add(data.rewards, kind, 1.0)
	var gap := _since_reward
	_since_reward = 0.0
	var b := GAP_BUCKETS.size() - 1
	for i in GAP_LIMITS.size():
		if gap < GAP_LIMITS[i]:
			b = i
			break
	data.reward_gaps[GAP_BUCKETS[b]] = int(data.reward_gaps[GAP_BUCKETS[b]]) + 1
	data["reward_gap_count"] = int(data.reward_gap_count) + 1
	data["reward_gap_sum_s"] = float(data.reward_gap_sum_s) + gap
	data["reward_gap_max_s"] = maxf(float(data.reward_gap_max_s), gap)
	_dirty = true


func on_death(chapter: int) -> void:
	if not enabled:
		return
	var ch := _chapter(chapter)
	ch["deaths"] = int(ch.get("deaths", 0)) + 1
	data.totals["deaths"] = int(data.totals.deaths) + 1
	_dirty = true


## L'utente chiude il gioco con una partita in corso.
func on_exit(chapter: int, screen: String) -> void:
	if not enabled:
		return
	var ch := _chapter(chapter)
	ch["exits"] = int(ch.get("exits", 0)) + 1
	data.totals["exits"] = int(data.totals.exits) + 1
	if not _session.is_empty():
		_session["exit_screen"] = screen
		_session["end_chapter"] = chapter
	_dirty = true


func _chapter(chapter: int) -> Dictionary:
	var k := str(chapter)
	if not data.chapters.has(k):
		data.chapters[k] = {"active_s": 0.0, "deaths": 0, "exits": 0}
	return data.chapters[k]


static func _add(d: Dictionary, key: String, amount: float) -> void:
	d[key] = float(d.get(key, 0.0)) + amount


# ------------------------------------------------------------------ esportazione

func export_json() -> String:
	return JSON.stringify(data, "  ")


## CSV «lungo»: section,key,field,value (si apre in Excel/LibreOffice e si filtra facilmente).
func export_csv() -> String:
	var rows: Array = [["section", "key", "field", "value"]]
	rows.append(["info", "install_id", "", data.install_id])
	rows.append(["info", "game_version", "", data.game_version])
	rows.append(["info", "created_day", "", data.created_day])
	rows.append(["info", "format", "", data.format])
	for k in data.totals:
		rows.append(["totals", k, "", _num(data.totals[k])])
	for k in data.screens:
		rows.append(["screens_seconds", k, "", _num(data.screens[k])])
	for k in data.rewards:
		rows.append(["rewards", k, "count", _num(data.rewards[k])])
	for k in GAP_BUCKETS:
		rows.append(["reward_gaps", k, "count", _num(data.reward_gaps.get(k, 0))])
	rows.append(["reward_gaps", "max", "seconds", _num(data.reward_gap_max_s)])
	rows.append(["reward_gaps", "sum", "seconds", _num(data.reward_gap_sum_s)])
	rows.append(["reward_gaps", "events", "count", _num(data.reward_gap_count)])
	var keys: Array = data.chapters.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for k in keys:
		var ch: Dictionary = data.chapters[k]
		for f in ch:
			rows.append(["chapters", k, f, _num(ch[f])])
	for s in data.sessions:
		var n := str(int(s.get("n", 0)))
		for f in ["day", "version", "active_s", "start_chapter", "end_chapter", "exit_screen"]:
			rows.append(["sessions", n, f, _num(s.get(f, ""))])
	var lines := PackedStringArray()
	for r in rows:
		var cells := PackedStringArray()
		for c in r:
			cells.append(_csv(str(c)))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func _num(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.01)
	return v


static func _csv(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


## Riga di riepilogo per la schermata: sessioni e tempo registrato.
func summary() -> Dictionary:
	return {"sessions": int(data.totals.sessions), "active_s": float(data.totals.active_s),
		"deaths": int(data.totals.deaths), "exits": int(data.totals.exits)}
