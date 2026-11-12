class_name ReportBuilder
extends RefCounted
## «Segnala un problema»: crea UNO ZIP in una cartella che l'utente vede (Desktop, altrimenti user://reports/).
## Dentro, solo cose del gioco: LEGGIMI, riepilogo, nota dell'utente, impostazioni, registro degli errori, ultime 50 righe
## del registro di gioco, copia dello slot di salvataggio. Tutto LOCALE: questo file non apre connessioni di rete
## (lo verifica un test) e l'invio lo fa la persona, a mano.
## Nessun dato personale: i percorsi nei testi sono ripuliti (`scrub`), niente nome utente né nome del PC.

const FALLBACK_DIR := "user://reports"
const GAME_LOG_LINES := 50
const NOTE_MAX := 4000
## Impostazioni che non vanno MAI nello ZIP (dato personale: l'IP dell'ultimo host coop, docs/24 §7.1 p.3).
const PRIVATE_SETTINGS: PackedStringArray = ["coop_last_host"]

## Cartella di destinazione ("" = Desktop, altrimenti user://reports).
var out_dir: String = ""
## Testo libero «cosa stavi facendo?» (facoltativo).
var note: String = ""
## Registro degli errori (se null, si usa quello del nodo Feedback).
var error_log: ErrorLog
## Ultime righe del registro di gioco (testo semplice).
var game_lines: PackedStringArray = PackedStringArray()
## Slot da copiare (0 = quello in corso, altrimenti l'ultimo usato).
var slot: int = 0
## Salva subito la partita in corso prima di copiare lo slot.
var save_first: bool = true
## Nome dello ZIP senza estensione (vuoto = automatico con data e ora).
var zip_name: String = ""


static func default_output_dir() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if not d.is_empty() and DirAccess.dir_exists_absolute(d):
		return d
	return FALLBACK_DIR


## Crea lo ZIP. Ritorna {ok, path, files: [nomi nello zip], error}.
func build() -> Dictionary:
	var entries: Array = []          # [nome nello zip, PackedByteArray]
	entries.append(["LEGGIMI.txt", _readme().to_utf8_buffer()])
	entries.append(["riepilogo.txt", summary_text().to_utf8_buffer()])
	entries.append(["nota_dell_utente.txt", _note_text().to_utf8_buffer()])
	entries.append(["impostazioni.cfg", settings_text().to_utf8_buffer()])
	var log_text := ""
	if error_log != null:
		log_text = error_log.recent_text()
	entries.append(["log/registro_errori.txt", scrub(log_text if not log_text.is_empty() else "(vuoto)").to_utf8_buffer()])
	var engine_log := _engine_log_tail()
	if not engine_log.is_empty():
		entries.append(["log/log_del_motore.txt", scrub(engine_log).to_utf8_buffer()])
	entries.append(["log/registro_di_gioco.txt", scrub("\n".join(_last_game_lines())).to_utf8_buffer()])
	var s := _slot_to_copy()
	if s > 0 and SaveService.slot_exists(s):
		if save_first and GameState.active and GameState.slot == s:
			SaveService.save_now()
		entries.append(["salvataggio/slot_%d.sav" % s, clean_save_bytes(FileAccess.get_file_as_bytes(SaveService.slot_path(s)))])
	var dir := out_dir if not out_dir.is_empty() else default_output_dir()
	var name := zip_name if not zip_name.is_empty() else "VAULTFALL_segnalazione_" + stamp()
	var res := _write_zip(dir, name + ".zip", entries)
	if not res.ok and dir != FALLBACK_DIR:
		res = _write_zip(FALLBACK_DIR, name + ".zip", entries)
	return res


static func stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


func _write_zip(dir: String, file_name: String, entries: Array) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var zip := ZIPPacker.new()
	var err := zip.open(path)
	if err != OK:
		return {"ok": false, "path": path, "files": [], "error": error_string(err)}
	var names: Array = []
	for e in entries:
		if zip.start_file(e[0]) != OK:
			continue
		zip.write_file(e[1])
		zip.close_file()
		names.append(e[0])
	zip.close()
	return {"ok": true, "path": path, "files": names, "error": ""}


# ------------------------------------------------------------------ contenuti

func _readme() -> String:
	return "%s\n\n%s" % [_tr_in("UI_FB_ZIP_README", "it"), _tr_in("UI_FB_ZIP_README", "en")]


## Coda del log che il motore scrive da solo (user://logs/godot.log): schianti e messaggi di sistema.
func _engine_log_tail(limit: int = 65536) -> String:
	var path := "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return ""
	var t := FileAccess.get_file_as_string(path)
	return t.substr(maxi(0, t.length() - limit))


func _note_text() -> String:
	var t := note.strip_edges()
	if t.length() > NOTE_MAX:
		t = t.substr(0, NOTE_MAX)
	return scrub(t if not t.is_empty() else "(nessuna nota)") + "\n"


func _last_game_lines() -> PackedStringArray:
	var n := game_lines.size()
	return game_lines.slice(maxi(0, n - GAME_LOG_LINES))


func _slot_to_copy() -> int:
	if slot > 0:
		return slot
	if GameState.active and GameState.slot > 0:
		return GameState.slot
	var last := int(Settings.get_value("last_slot"))
	if SaveService.is_valid_slot(last) and SaveService.slot_exists(last):
		return last
	for s in range(1, SaveService.SLOTS + 1):
		if SaveService.slot_exists(s):
			return s
	return 0


## Traduzione di una chiave in una lingua precisa (il LEGGIMI è bilingue).
static func _tr_in(key: String, lang: String) -> String:
	var tr_obj := TranslationServer.get_translation_object(lang)
	if tr_obj != null:
		var m := str(tr_obj.get_message(key))
		if not m.is_empty():
			return m
	return key


## Riepilogo leggibile (per lo sviluppatore): versione, sistema, schermo, stato della partita.
func summary_text() -> String:
	var L := PackedStringArray()
	L.append("VAULTFALL - riepilogo della segnalazione")
	L.append("Creato il: %s (ora locale)" % Time.get_datetime_string_from_system(false, true))
	L.append("")
	L.append("== Gioco ==")
	L.append("Versione: %s (build %d, %s)" % [AppInfo.version_label(), AppInfo.build(), AppInfo.release_date()])
	L.append("Motore: Godot %s | build di debug: %s" % [Engine.get_version_info().get("string", "?"), str(OS.is_debug_build())])
	L.append("Lingua: %s | formato numeri: %s | effetti: %s" % [Settings.get_value("locale"), Settings.get_value("number_format"), Settings.get_value("fx_mode")])
	L.append("")
	L.append("== Computer ==")
	L.append("Sistema: %s %s" % [OS.get_name(), OS.get_version()])
	L.append("Processore: %d core | scheda video: %s" % [OS.get_processor_count(), RenderingServer.get_video_adapter_name()])
	var win := DisplayServer.window_get_size()
	L.append("Finestra: %dx%d | schermo: %dx%d | scala interfaccia: %s" % [win.x, win.y,
		DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y, str(Settings.get_value("ui_scale"))])
	L.append("")
	L.append("== Partita ==")
	if GameState.active:
		var d: Dictionary = GameState.data
		L.append("Slot: %d | modalità: %s" % [GameState.slot, GameState.mode()])
		L.append("Livello totale: %d" % GameState.total_level())
		var playtime := float(d.get("stats", {}).get("playtime_s", 0.0))
		L.append("Ore giocate: %.2f (%s)" % [playtime / 3600.0, NumberFormat.fmt_time(playtime)])
		L.append("Capitolo: %s" % _chapter_text())
		L.append("Oro: %s | uccisioni: %s" % [NumberFormat.fmt(GameState.gold()), NumberFormat.fmt(int(d.get("stats", {}).get("kills", 0)))])
		L.append("Missioni completate: %d" % (d.get("quests", {}).get("done", []) as Array).size())
		L.append("Sistemi sbloccati: %s" % ", ".join(_unlocked_features()))
		L.append("Orologio: velocità x%d, in pausa: %s" % [int(Clock.speed), str(Clock.paused)])
	else:
		L.append("Nessuna partita in corso (la segnalazione è stata fatta dal menù iniziale).")
	L.append("")
	L.append("== Registro ==")
	L.append("Righe di errore/avviso in questo avvio: %d" % (error_log.error_count() if error_log != null else 0))
	return scrub("\n".join(L)) + "\n"


func _chapter_text() -> String:
	var q := Game.system("quests") as QuestSystem
	if q == null:
		return "?"
	var id := q.current_main()
	if id.is_empty():
		return "storia conclusa"
	var ch := int(q.quest_def(id).get("chapter", 0))
	var name := Loc.t(DataRegistry.get_def("chapters", str(ch)).get("name", ""))
	return "%d (%s) - missione %s" % [ch, name, id]


func _unlocked_features() -> PackedStringArray:
	var out := PackedStringArray()
	for t in GameState.data.get("unlocks", []):
		var s := str(t)
		if s.begins_with("feature:") or s.begins_with("skill:"):
			out.append(s)
	return out


## Impostazioni dell'utente come testo (solo preferenze di gioco).
func settings_text() -> String:
	var cfg := ConfigFile.new()
	for k in Settings.DEFAULTS:
		if PRIVATE_SETTINGS.has(k):
			continue
		cfg.set_value("settings", k, Settings.get_value(k))
	return cfg.encode_to_text()


# ------------------------------------------------------------------ privacy

## Copia dello slot per lo ZIP: i salvataggi di versioni precedenti tenevano l'IP dell'ultimo host in `coop_net.last_host`;
## se c'e', la copia ne e' priva (il file originale resta com'e': si ripulisce da solo al prossimo caricamento).
## Senza IP la copia e' identica byte per byte al file.
static func clean_save_bytes(raw: PackedByteArray) -> PackedByteArray:
	var dec := SaveCodec.decode(raw)
	if not dec.ok:
		return raw
	var data: Dictionary = dec.data
	var net: Variant = data.get("coop_net")
	if net is Dictionary and net.has("last_host"):
		net.erase("last_host")
		return SaveCodec.encode(data)
	return raw


## Indirizzi IP (IPv4 e IPv6 lunghi) nei testi: mai nello ZIP.
static func scrub_ips(text: String) -> String:
	var t := text
	var v4 := RegEx.new()
	v4.compile("(?<![0-9.])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9])")
	t = v4.sub(t, "<ip>", true)
	var v6 := RegEx.new()
	v6.compile("(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{1,4}:){5,7}[0-9A-Fa-f]{1,4}(?![0-9A-Fa-f:])")
	t = v6.sub(t, "<ip>", true)
	return t


## Toglie dai testi i percorsi del computer (cartella utente, nome utente, profilo) e li sostituisce con segnaposto.
static func scrub(text: String) -> String:
	var t := scrub_ips(text)
	var pairs: Array = []
	var user_dir := OS.get_user_data_dir()
	if not user_dir.is_empty():
		pairs.append([user_dir, "<dati-di-gioco>"])
		pairs.append([user_dir.replace("/", "\\"), "<dati-di-gioco>"])
	for env in ["USERPROFILE", "HOME", "APPDATA", "LOCALAPPDATA"]:
		var v := OS.get_environment(env)
		if v.length() >= 4 and v != "/":
			pairs.append([v, "<profilo>"])
			pairs.append([v.replace("/", "\\"), "<profilo>"])
			pairs.append([v.replace("\\", "/"), "<profilo>"])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0].length() > b[0].length())
	for p in pairs:
		t = t.replace(p[0], p[1])
	for env in ["USERNAME", "USER", "LOGNAME", "COMPUTERNAME", "HOSTNAME"]:
		var v := OS.get_environment(env)
		if v.length() >= 4:
			t = t.replace("/" + v + "/", "/<utente>/").replace("\\" + v + "\\", "\\<utente>\\")
			if env == "COMPUTERNAME" or env == "HOSTNAME":
				t = t.replace(v, "<pc>")
	return t
