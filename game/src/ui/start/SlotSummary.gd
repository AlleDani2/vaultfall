class_name SlotSummary
extends RefCounted
## Riepilogo degli slot di salvataggio per il menù iniziale (eroe, classe, capitolo, tempo di gioco, ultimo salvataggio).
## Solo lettura e presentazione: legge SaveService (senza modificarlo) e tiene una CACHE per slot, valida finché i file
## (principale, .tmp e copie di sicurezza) non cambiano per data e dimensione. Così aprire il menù, tornare indietro o
## ridisegnare le carte non decodifica di nuovo i salvataggi: una sola lettura completa per slot e per modifica.
## Il ripristino da una copia di sicurezza non riscrive mai a caso: tiene da parte il file danneggiato (.danneggiato).

const CORRUPT_SUFFIX := ".danneggiato"
const _GameStateScript := preload("res://src/autoload/GameState.gd")

static var _cache: Dictionary = {}            # slot -> {"sig": String, "info": Dictionary}
static var _backup_cache: Dictionary = {}     # slot -> {"sig": String, "list": Array}
## Quante letture complete (decodifiche) sono state fatte: lo guardano i test per provare che la cache funziona.
static var decode_count: int = 0


## Impronta dei file dello slot: se non cambia, il riepilogo in cache è ancora vero.
static func signature(slot: int) -> String:
	var parts := PackedStringArray()
	var paths: Array[String] = [SaveService.slot_path(slot), SaveService.slot_path(slot) + ".tmp"]
	for n in range(1, SaveService.BACKUPS + 1):
		paths.append(SaveService.backup_path(slot, n))
	for p in paths:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			var size := f.get_length() if f != null else -1
			parts.append("%d:%d" % [FileAccess.get_modified_time(p), size])
		else:
			parts.append("-")
	return "%s|%d|%s" % [SaveService.save_dir, SaveService.last_saved_unix, "|".join(parts)]


static func invalidate(slot: int = 0) -> void:
	if slot <= 0:
		_cache.clear()
		_backup_cache.clear()
	else:
		_cache.erase(slot)
		_backup_cache.erase(slot)


## Riepilogo di uno slot (in cache se i file non sono cambiati). Campi: exists, ok, error, recovered (lo slot si legge solo da
## una copia di sicurezza), source, mode, saved_at_unix, playtime_s, total_level, hero_level, class_id, spec_id, chapter.
static func get_info(slot: int) -> Dictionary:
	if not SaveService.is_valid_slot(slot):
		return {"exists": false, "ok": false}
	var sig := signature(slot)
	var hit: Variant = _cache.get(slot)
	if hit is Dictionary and str(hit.sig) == sig:
		return hit.info
	var info := _read(slot)
	_cache[slot] = {"sig": sig, "info": info}
	return info


static func _read(slot: int) -> Dictionary:
	if not SaveService.slot_exists(slot):
		return {"exists": false, "ok": false}
	decode_count += 1
	var res := SaveService.load_slot(slot)
	if not res.ok:
		return {"exists": true, "ok": false, "error": str(res.error), "recovered": false}
	return _from_data(res.data, str(res.source))


static func _from_data(d: Dictionary, source: String) -> Dictionary:
	var hero: Dictionary = d.get("hero", {}) if d.get("hero", {}) is Dictionary else {}
	var skills: Dictionary = d.get("skills", {}) if d.get("skills", {}) is Dictionary else {}
	var stats: Dictionary = d.get("stats", {}) if d.get("stats", {}) is Dictionary else {}
	var hero_skill: Variant = skills.get("hero", {})
	return {"exists": true, "ok": true, "source": source, "recovered": source != "main" and source != "tmp",
		"mode": str(d.get("mode", "normal")),
		"saved_at_unix": int(d.get("saved_at_unix", 0)),
		"playtime_s": float(stats.get("playtime_s", 0.0)),
		"total_level": _GameStateScript.total_level_of(d),
		"hero_level": int(hero_skill.get("level", 0)) if hero_skill is Dictionary else 0,
		"class_id": str(hero.get("class", "")),
		"spec_id": str(hero.get("spec", "")),
		"chapter": chapter_of(d),
		"coop": ScreenRegistry.is_available(ScreenRegistry.get_entry("coop_lobby"), d.get("unlocks", []) if d.get("unlocks", []) is Array else [])}


## Capitolo della storia: quello della missione principale in corso o, a storia finita, l'ultimo completato. -1 = sconosciuto.
static func chapter_of(d: Dictionary) -> int:
	var q: Variant = d.get("quests", {})
	if not (q is Dictionary):
		return -1
	var best := -1
	for qid in q.get("active", []):
		var def := DataRegistry.get_def("quests", str(qid))
		if str(def.get("kind", "")) == "main":
			return int(def.get("chapter", -1))
	for qid in q.get("done", []):
		var def := DataRegistry.get_def("quests", str(qid))
		if str(def.get("kind", "")) == "main":
			best = maxi(best, int(def.get("chapter", -1)))
	return best


## Nome breve del capitolo («Capitolo II — La Costa del Sale»): senza la battuta tra parentesi.
static func chapter_label(chapter: int) -> String:
	if chapter < 0:
		return ""
	var full := QuestText.chapter_name(chapter, DataRegistry)
	var cut := full.find(" (")
	return full.substr(0, cut) if cut > 0 else full


## Nome della classe (con specializzazione), già tradotto; «» se l'eroe non ha ancora una classe.
static func class_label(info: Dictionary) -> String:
	var cid := str(info.get("class_id", ""))
	if cid.is_empty():
		return ""
	var t := Loc.t(DataRegistry.get_def("classes", cid).get("name", cid))
	var sid := str(info.get("spec_id", ""))
	if not sid.is_empty():
		t += " / " + Loc.t(DataRegistry.get_def("classes", sid).get("name", sid))
	return t


## Copie di sicurezza leggibili di uno slot, dalla più recente: [{n, saved_at_unix, total_level, hero_level, class_id, spec_id,
## chapter}]. Si decodificano solo quando servono (slot danneggiato o ripristinato) e restano in cache come il riepilogo.
static func backups(slot: int) -> Array:
	var sig := signature(slot)
	var hit: Variant = _backup_cache.get(slot)
	if hit is Dictionary and str(hit.sig) == sig:
		return hit.list
	var out: Array = []
	for n in range(1, SaveService.BACKUPS + 1):
		var p := SaveService.backup_path(slot, n)
		if not FileAccess.file_exists(p):
			continue
		decode_count += 1
		var res := SaveCodec.load_bytes(FileAccess.get_file_as_bytes(p), Game.sim.int_paths(), SaveCodec.SCHEMA_VERSION, {}, Game.sim.soft_int_paths())
		if bool(res.ok):
			var inf := _from_data(res.data, "bak%d" % n)
			inf["n"] = n
			out.append(inf)
	_backup_cache[slot] = {"sig": sig, "list": out}
	return out


## Ripristina uno slot dalla copia di sicurezza `n` (1…BACKUPS). Il file principale danneggiato non si butta: resta accanto,
## con suffisso .danneggiato, per l'assistenza. Ritorna true se lo slot ora si legge dal file principale.
static func restore_backup(slot: int, n: int) -> bool:
	if not SaveService.is_valid_slot(slot) or n < 1 or n > SaveService.BACKUPS:
		return false
	var src := SaveService.backup_path(slot, n)
	if not FileAccess.file_exists(src):
		return false
	var bytes := FileAccess.get_file_as_bytes(src)
	var main := SaveService.slot_path(slot)
	if FileAccess.file_exists(main):
		var keep := main + CORRUPT_SUFFIX
		if FileAccess.file_exists(keep):
			DirAccess.remove_absolute(keep)
		DirAccess.rename_absolute(main, keep)
	var f := FileAccess.open(main, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	invalidate(slot)
	var info := get_info(slot)
	return bool(info.get("ok", false)) and not bool(info.get("recovered", false))


## Copia il file principale (o, se manca, la prima copia) in una cartella a scelta: per spedirlo all'assistenza.
## Ritorna il percorso scritto, «» se non c'è nulla da copiare o la scrittura fallisce.
static func export_for_support(slot: int, dest_dir: String) -> String:
	var src := SaveService.slot_path(slot)
	if not FileAccess.file_exists(src):
		for n in range(1, SaveService.BACKUPS + 1):
			if FileAccess.file_exists(SaveService.backup_path(slot, n)):
				src = SaveService.backup_path(slot, n)
				break
	if not FileAccess.file_exists(src):
		return ""
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dst := "%s/vaultfall_slot_%d_assistenza.sav" % [dest_dir, slot]
	var data := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(data)
	f.close()
	return dst


# ------------------------------------------------------------------ testi

const _MONTH_KEY := "UI_M10_MONTHS"


## «28 ott 2026, 23:49» (o «Oct 28, 2026, 11:49 PM» in inglese): data nella lingua del gioco, ora locale.
static func format_date(unix: int) -> String:
	if unix <= 0:
		return "—"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	var months := str(TranslationServer.translate(_MONTH_KEY)).split(",")
	var mon := months[int(d.month) - 1] if months.size() == 12 else str(d.month)
	if Loc.locale() == "en":
		var h12 := int(d.hour) % 12
		if h12 == 0:
			h12 = 12
		return "%s %d, %d, %d:%02d %s" % [mon, d.day, d.year, h12, d.minute, "AM" if int(d.hour) < 12 else "PM"]
	return "%d %s %d, %02d:%02d" % [d.day, mon, d.year, d.hour, d.minute]


## «Guerriero · Capitolo II — La Costa del Sale · Eroe liv. 12»: la riga principale di una carta.
static func headline(info: Dictionary) -> String:
	var parts := PackedStringArray()
	var cls := class_label(info)
	parts.append(cls if not cls.is_empty() else str(TranslationServer.translate("UI_M10_NO_CLASS")))
	var ch := chapter_label(int(info.get("chapter", -1)))
	if not ch.is_empty():
		parts.append(ch)
	return " · ".join(parts)


## Tempo di gioco: «12 h 40 min»; sotto il minuto, «meno di 1 min» (non «0,0 s»).
static func play_time(seconds: float) -> String:
	if seconds < 60.0:
		return str(TranslationServer.translate("UI_M10_LESS_THAN_MIN"))
	return NumberFormat.fmt_time(seconds)


## «Livello totale 143 · Normale · 12 h 40 min · 28 ott 2026, 23:49»: la riga dei dettagli.
static func details(info: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(info.get("hero_level", 0)) > 0:
		parts.append(Loc.tf("UI_M10_HERO_LEVEL", {"n": NumberFormat.fmt(int(info.hero_level))}))
	parts.append("%s %s" % [TranslationServer.translate("UI_TOTAL_LEVEL"), TotalLevelText.text(int(info.get("total_level", 0)))])
	parts.append(str(TranslationServer.translate("UI_MODE_" + str(info.get("mode", "normal")).to_upper())))
	parts.append(play_time(float(info.get("playtime_s", 0.0))))
	parts.append(format_date(int(info.get("saved_at_unix", 0))))
	return " · ".join(parts)
