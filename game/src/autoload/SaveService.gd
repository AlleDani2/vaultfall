extends Node
## SaveService (autoload) — salvataggi sicuri (docs/17 §10, CLAUDE.md regola 7).
## - 3 slot: user://saves/slot_N.sav (JSON + gzip); Steam Cloud sincronizza solo slot_*.sav.
## - Scrittura atomica: slot_N.sav.tmp -> rilettura e decodifica di verifica -> rotazione backup
##   (.bak1..3, solo locali, al piu' una rotazione ogni BACKUP_INTERVAL_S) -> rinomina del .tmp. R-SAV-1.
## - Copie di sicurezza oltre ai .bak: `.pre_vN` (una per versione di schema, creata la prima volta che un salvataggio vN
##   viene migrato, MAI sovrascritta) e `.day_AAAA-MM-GG` (la partita com'era al primo salvataggio del giorno, ultime DAY_COPIES).
## - schema_version + migrazioni (SaveCodec); un salvataggio più nuovo del gioco NON si apre. R-SAV-2.
## - Salvataggio automatico ogni AUTOSAVE_S secondi reali, all'uscita e dopo EventBus.important_event. R-SAV-3.
## - Export/import Base64 (gzip+JSON). R-SAV-4.
## - Normalizzazione dei tipi dopo il load (R-SAV-8) con i percorsi di Simulation.int_paths().
## - Il salvataggio normale avviene su un THREAD: sul principale resta solo lo snapshot (spike S2).
##
## Esito: EventBus.save_completed(ok) / EventBus.save_failed(slot, errore).
## Fonti di load_slot (campo "source"): "main", "tmp" (scrittura completa ma non ancora rinominata: chiusura brusca proprio
## durante la rotazione), "bak1".."bak3". Codici d'errore di load_slot: "missing", "empty", "gzip", "json", "not_object", "no_version", "newer",
## "missing_migration", "migration_failed", "corrupt_types", "invalid_slot".

const SLOTS := 3
const BACKUPS := 3
const AUTOSAVE_S := 30.0
## Intervallo minimo tra due rotazioni dei backup .bak1..3 (secondi reali): con salvataggi ogni 30 s i tre backup
## coprirebbero solo ~90 s di gioco. Con 600 s coprono 20-30 minuti.
const BACKUP_INTERVAL_S := 600.0
const DAY_COPIES := 7
const _GameStateScript := preload("res://src/autoload/GameState.gd")

## Cartella dei salvataggi (i test la cambiano con una cartella temporanea).
var save_dir: String = "user://saves"
var autosave_enabled: bool = true
var last_error: String = ""
## Istante (secondi Unix) dell'ultimo salvataggio riuscito della partita in corso; 0 = nessuno ancora. Si aggiorna a ogni
## scrittura andata a buon fine (manuale, automatica, sincrona) e al caricamento prende l'istante scritto nel file.
var last_saved_unix: int = 0
## Intervallo di rotazione dei backup (i test lo azzerano o lo accorciano).
var backup_interval_s: float = BACKUP_INTERVAL_S
## Sorgente dell'ora (secondi Unix) per backup e copie giornaliere: i test la sostituiscono. Callable() = orologio di sistema.
var time_source: Callable = Callable()
## Esito dell'ultimo tentativo di scrittura (true = riuscito); false dopo un salvataggio fallito, finche' non ne riesce uno.
var last_save_ok: bool = true
## Percorsi interi saturati prima della scrittura (per non ripetere la stessa riga nel Registro a ogni autosalvataggio).
var _saturation_logged: Dictionary = {}
var _last_rotation: Dictionary = {}      # slot -> secondi Unix dell'ultima rotazione (solo in memoria)

var _thread: Thread
var _thread_slot: int = 0
var _pending: bool = false
var _autosave_acc: float = 0.0
var _last_usec: int = 0
var _mutex := Mutex.new()
var _save_soon: bool = false
var _quit_dialog: ConfirmationDialog
var _fail_dialog: ConfirmationDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)
	# Evento importante: il salvataggio parte al prossimo frame (fuori dal tick della simulazione) e più eventi nello
	# stesso frame ne fanno uno solo (resoconto 47: lo snapshot nel tick costava fino a 70 ms).
	EventBus.important_event.connect(func(_reason: String) -> void: _save_soon = true)
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real := (now - _last_usec) / 1_000_000.0
	_last_usec = now
	_poll_thread()
	if _save_soon:
		_save_soon = false
		request_save()
	if not GameState.active or not autosave_enabled:
		_autosave_acc = 0.0
		return
	_autosave_acc += real
	if _autosave_acc >= AUTOSAVE_S:
		_autosave_acc = 0.0
		request_save()


## Chiusura del motore (anche senza passare da quit_game): se un salvataggio su thread è in corso lo si aspetta,
## altrimenti il thread parte su un'istanza già liberata ("Could not call function '_thread_save' on previously freed instance").
func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


## Chiusura dalla X della finestra: con un combattimento attivo chiede conferma (CloseGuard, UI-A G20).
func request_quit() -> void:
	if is_instance_valid(_quit_dialog):
		return
	if CloseGuard.needs_confirmation():
		_quit_dialog = CloseGuard.build_dialog(CloseGuard.combat_status(), quit_game)
		_quit_dialog.canceled.connect(_quit_dialog.queue_free)
		get_tree().root.add_child(_quit_dialog)
		_quit_dialog.popup_centered()
		return
	quit_game()


## Salva (se c'è una partita) e chiude il gioco. Usata dalla X della finestra e dal pulsante Esci.
## Se il salvataggio finale NON riesce (disco pieno, cartella non scrivibile) il gioco non si chiude in silenzio: chiede
## «uscire comunque?». `force = true` chiude senza chiedere.
func quit_game(force: bool = false) -> void:
	if not final_save_ok() and not force:
		_ask_quit_anyway()
		return
	get_tree().quit()


## Salvataggio finale prima dell'uscita: true se non c'e' nulla da salvare o la scrittura e' riuscita.
func final_save_ok() -> bool:
	_finish_thread()
	if not GameState.active:
		return true
	return save_now()


func _ask_quit_anyway() -> void:
	if is_instance_valid(_fail_dialog):
		return
	var dlg := ConfirmationDialog.new()
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dlg.title = TranslationServer.translate("UI_SAVESAFE_QUIT_TITLE")
	dlg.dialog_text = Loc.tf("UI_SAVESAFE_QUIT_BODY", {"error": last_error})
	dlg.dialog_autowrap = true
	dlg.ok_button_text = TranslationServer.translate("UI_SAVESAFE_QUIT_OK")
	dlg.cancel_button_text = TranslationServer.translate("UI_SAVESAFE_QUIT_CANCEL")
	dlg.confirmed.connect(func() -> void: quit_game(true))
	dlg.canceled.connect(dlg.queue_free)
	_fail_dialog = dlg
	get_tree().root.add_child(dlg)
	dlg.popup_centered()


# ------------------------------------------------------------------ percorsi

func slot_path(slot: int) -> String:
	return "%s/slot_%d.sav" % [save_dir, slot]


func backup_path(slot: int, n: int) -> String:
	return "%s.bak%d" % [slot_path(slot), n]


func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOTS


## Lo slot esiste se c'e' il file principale o, QA120, se manca il principale ma resta un backup (chiusura brusca durante la
## rotazione: senza questo il menu mostrerebbe lo slot vuoto con i backup irraggiungibili). Un `.tmp` da solo, senza principale e
## senza backup, non e' un salvataggio (primo salvataggio mai completato: test_fuzz_save).
func slot_exists(slot: int) -> bool:
	if FileAccess.file_exists(slot_path(slot)):
		return true
	for n in range(1, BACKUPS + 1):
		if FileAccess.file_exists(backup_path(slot, n)):
			return true
	return false


# ------------------------------------------------------------------ salvataggio

## Salvataggio su thread della partita in corso (snapshot sul principale). Se un salvataggio è già in corso,
## ne accoda uno solo.
func request_save() -> void:
	if not GameState.active or not is_valid_slot(GameState.slot):
		return
	if _thread != null and _thread.is_alive():
		_pending = true
		return
	_finish_thread()
	var snapshot: Dictionary = Game.snapshot()
	var slot := GameState.slot
	var paths := Game.sim.int_paths()
	_thread_slot = slot
	_thread = Thread.new()
	_thread.start(_thread_save.bind(slot, snapshot, paths))


## Salvataggio sincrono della partita in corso (uscita, nuova partita, test).
func save_now(force_backup: bool = false) -> bool:
	if not GameState.active or not is_valid_slot(GameState.slot):
		return false
	_finish_thread()
	var ok := _save_owned(GameState.slot, Game.snapshot(true), force_backup) == OK
	_autosave_acc = 0.0
	return ok


## Scrive un dizionario di stato in uno slot (sincrono). Emette i segnali di esito. `data` non viene modificato.
## `force_backup`: il file attuale dello slot passa SEMPRE a .bak1 (import su uno slot occupato).
func save_data(slot: int, data: Dictionary, force_backup: bool = false) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	return _save_owned(slot, data.duplicate(true), force_backup)


## Come save_data, ma `data` e' una copia di proprieta' di chi chiama (snapshot): viene preparata in place.
func _save_owned(slot: int, data: Dictionary, force_backup: bool = false) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var paths := Game.sim.int_paths()
	_prepare_snapshot(slot, data, paths)
	var err := write_atomic(slot, SaveCodec.encode(data), paths, force_backup)
	_emit_result(slot, err)
	return err


## Stato non salvabile (intero oltre il limite, NaN...): SATURAZIONE ai limiti con una riga nel Registro, mai salvataggio perso.
## Le stringhe per gli interi oltre 2^53 (R-SAV-7) si applicano qui.
func _prepare_snapshot(slot: int, snapshot: Dictionary, int_paths: PackedStringArray) -> void:
	_log_saturation(slot, SaveCodec.prepare_for_write(snapshot, int_paths))


## Riga nel Registro per ogni campo corretto (una volta per percorso e per sessione). Va chiamata dal thread principale.
func _log_saturation(slot: int, fixed: PackedStringArray) -> void:
	for f in fixed:
		var key: String = f.get_slice(":", 0)
		if not _saturation_logged.has(key):
			if _saturation_logged.size() < 200:
				_saturation_logged[key] = true
			push_warning("SaveService: slot %d, campo fuori limite saturato per poter salvare: %s" % [slot, f])


## Secondi trascorsi dall'ultimo salvataggio (mai negativi anche se l'orologio di sistema torna indietro). -1.0 = nessun salvataggio noto.
func seconds_since_save(now_unix: int = -1) -> float:
	if last_saved_unix <= 0:
		return -1.0
	var now := now_unix if now_unix >= 0 else Clock.now_unix()
	return float(maxi(0, now - last_saved_unix))


## Registra l'istante dell'ultimo salvataggio (lo usa il caricamento di una partita: vale l'istante scritto nel file).
func mark_saved(unix: int) -> void:
	last_saved_unix = maxi(0, unix)


func is_saving() -> bool:
	return _thread != null and _thread.is_alive()


## Scrittura atomica con verifica e rotazione dei backup (R-SAV-1). Sicura da chiamare da un thread.
## `int_paths` (facoltativo, da Simulation.int_paths()): la verifica prova anche la normalizzazione dei campi interi che farà
## il caricamento (R-SAV-8). Un file che si decodifica ma che load_slot rifiuterebbe ("corrupt_types", es. un intero andato in
## overflow) NON sostituisce il salvataggio buono: la scrittura fallisce (save_failed) e backup e slot restano intatti.
func write_atomic(slot: int, bytes: PackedByteArray, int_paths: PackedStringArray = PackedStringArray(), force_backup: bool = false) -> Error:
	_mutex.lock()
	var err := _write_atomic_locked(slot, bytes, int_paths, force_backup)
	_mutex.unlock()
	return err


func _now_unix() -> int:
	if time_source.is_valid():
		return int(time_source.call())
	return int(Time.get_unix_time_from_system())


func _write_atomic_locked(slot: int, bytes: PackedByteArray, int_paths: PackedStringArray = PackedStringArray(), force_backup: bool = false) -> Error:
	var dir_err := DirAccess.make_dir_recursive_absolute(save_dir)
	if dir_err != OK and not DirAccess.dir_exists_absolute(save_dir):
		return dir_err
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	# verifica: i byte riletti coincidono e si decodificano
	var back := FileAccess.get_file_as_bytes(tmp)
	var dec := SaveCodec.decode(back) if back == bytes else {"ok": false}
	if not bool(dec.ok) or (not int_paths.is_empty() and not SaveCodec.normalize(dec.data, int_paths).is_empty()):
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	var now := _now_unix()
	if FileAccess.file_exists(path):
		_daily_copy(slot, path, now)
		# rotazione: bak2->bak3, bak1->bak2, sav->bak1 (rename su Windows fallisce se la destinazione esiste).
		# Al piu' una rotazione ogni backup_interval_s: i backup coprono 20-30 minuti, non 90 secondi.
		if force_backup or _rotation_due(slot, now):
			for n in range(BACKUPS, 1, -1):
				var src := backup_path(slot, n - 1)
				if FileAccess.file_exists(src):
					_replace(src, backup_path(slot, n))
			_replace(path, backup_path(slot, 1))
			_last_rotation[slot] = now
	return _replace(tmp, path)


## True se il file principale deve passare a .bak1: nessun .bak1 ancora, oppure e' passato l'intervallo dall'ultima rotazione
## (al primo salvataggio dopo l'avvio vale la data del .bak1 sul disco).
func _rotation_due(slot: int, now: int) -> bool:
	var b1 := backup_path(slot, 1)
	if not FileAccess.file_exists(b1):
		return true
	var last: int = int(_last_rotation.get(slot, FileAccess.get_modified_time(b1)))
	if last > now:
		return true                    # orologio tornato indietro: meglio una rotazione in piu' che nessuna
	return float(now - last) >= backup_interval_s


func _files() -> PackedStringArray:
	return DirAccess.get_files_at(save_dir) if DirAccess.dir_exists_absolute(save_dir) else PackedStringArray()


func day_copy_path(slot: int, date: String) -> String:
	return "%s.day_%s" % [slot_path(slot), date]


func pre_migration_path(slot: int, version: int) -> String:
	return "%s.pre_v%d" % [slot_path(slot), version]


## Copie giornaliere esistenti dello slot, dalla piu' recente (le date AAAA-MM-GG si ordinano come stringhe).
func day_copies(slot: int) -> PackedStringArray:
	var out: Array = []
	var prefix := "slot_%d.sav.day_" % slot
	for f in _files():
		if f.begins_with(prefix):
			out.append(f)
	out.sort()
	out.reverse()
	var res := PackedStringArray()
	for f in out:
		res.append("%s/%s" % [save_dir, f])
	return res


## Copie `.pre_vN` esistenti dello slot, dalla versione piu' alta.
func pre_migration_copies(slot: int) -> PackedStringArray:
	var found: Array = []
	var prefix := "slot_%d.sav.pre_v" % slot
	for f in _files():
		if f.begins_with(prefix) and f.substr(prefix.length()).is_valid_int():
			found.append(f.substr(prefix.length()).to_int())
	found.sort()
	found.reverse()
	var res := PackedStringArray()
	for v in found:
		res.append(pre_migration_path(slot, v))
	return res


## La partita com'era al primo salvataggio del giorno (il file principale PRIMA di essere sostituito). Ultime DAY_COPIES.
func _daily_copy(slot: int, main_path: String, now: int) -> void:
	var date := Time.get_date_string_from_unix_time(now)
	var dst := day_copy_path(slot, date)
	if FileAccess.file_exists(dst):
		return
	var bytes := FileAccess.get_file_as_bytes(main_path)
	if bytes.is_empty():
		return
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	var all := day_copies(slot)
	for i in range(DAY_COPIES, all.size()):
		DirAccess.remove_absolute(all[i])


## Copia del file cosi' com'era, UNA volta per versione di schema (mai sovrascritta): se la migrazione o una versione futura
## rovinasse la partita, il file originale resta recuperabile.
func _pre_migration_copy(slot: int, from_version: int, bytes: PackedByteArray) -> void:
	var dst := pre_migration_path(slot, from_version)
	if FileAccess.file_exists(dst) or bytes.is_empty():
		return
	_mutex.lock()
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	_mutex.unlock()


func _replace(src: String, dst: String) -> Error:
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	return DirAccess.rename_absolute(src, dst)


# ------------------------------------------------------------------ caricamento

## Legge uno slot: file principale, poi i backup in ordine. Ritorna
## {"ok", "data", "error", "source": "main"|"bak1"..} già migrato e normalizzato.
## Un salvataggio "newer" interrompe la ricerca (non si ripiega su backup vecchi in silenzio).
func load_slot(slot: int, int_paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not is_valid_slot(slot):
		return {"ok": false, "data": {}, "error": "invalid_slot", "source": ""}
	_finish_thread()
	var paths := int_paths if not int_paths.is_empty() else Game.sim.int_paths()
	# QA120: se il processo si ferma tra la rotazione (main -> bak1) e la rinomina del .tmp, il main manca ma il .tmp e' una scrittura
	# completa e piu' recente di bak1. Un .tmp parziale non si decodifica (CRC del gzip) e si passa al backup, come prima.
	# Solo se esiste almeno un backup: un .tmp orfano senza storia non e' un salvataggio (test_fuzz_save).
	var candidates := [[slot_path(slot), "main"]]
	var has_backup := false
	for n in range(1, BACKUPS + 1):
		has_backup = has_backup or FileAccess.file_exists(backup_path(slot, n))
	if has_backup:
		candidates.append([slot_path(slot) + ".tmp", "tmp"])      # un .tmp senza storia alle spalle non e' un salvataggio (fuzz)
	for n in range(1, BACKUPS + 1):
		candidates.append([backup_path(slot, n), "bak%d" % n])
	for dp in day_copies(slot):
		candidates.append([dp, "day"])
	for pp in pre_migration_copies(slot):
		candidates.append([pp, "pre_migration"])
	var first_error := ""
	for c in candidates:
		if not FileAccess.file_exists(c[0]):
			if first_error.is_empty():
				first_error = "missing"
			continue
		var raw := FileAccess.get_file_as_bytes(c[0])
		var res := SaveCodec.load_bytes(raw, paths, SaveCodec.SCHEMA_VERSION, {}, Game.sim.soft_int_paths())
		res["source"] = c[1]
		if res.ok:
			# F2 (QA 72): JSON valido ma con sezioni di tipo sbagliato = salvataggio corrotto -> si prova il candidato successivo
			var bad := SaveCodec.check_shape(res.data, _reference_shape())
			if not bad.is_empty():
				push_warning("SaveService: slot %d (%s) con sezioni di tipo sbagliato: %s" % [slot, c[1], ", ".join(bad)])
				res = {"ok": false, "data": {}, "error": "corrupt_types", "paths": bad, "source": c[1]}
		if res.ok:
			var fv := int(res.get("from_version", SaveCodec.SCHEMA_VERSION))
			if fv < SaveCodec.SCHEMA_VERSION and str(c[1]) in ["main", "tmp", "bak1", "bak2", "bak3"]:
				_pre_migration_copy(slot, fv, raw)
			if c[1] != "main":
				push_warning("SaveService: slot %d caricato dal backup %s" % [slot, c[1]])
			return res
		if res.error == "newer":
			last_error = "newer"
			return res
		if first_error.is_empty() or first_error == "missing":
			first_error = res.error
	last_error = first_error
	return {"ok": false, "data": {}, "error": first_error, "source": ""}


## Stato iniziale completo (GameState + sezioni dei sistemi): riferimento di forma per la validazione dei tipi.
func _reference_shape() -> Dictionary:
	var ref: Dictionary = _GameStateScript.default_state()
	for gs in Game.sim.systems:
		if gs.state_key.is_empty():
			continue
		var ds: Variant = gs.default_state()
		if not ref.has(gs.state_key) or typeof(ref[gs.state_key]) == typeof(ds):
			ref[gs.state_key] = ds
		else:
			ref[gs.state_key] = null      # forma storica diversa (es. lista vuota): il sistema la riconosce da solo
	return ref


## Informazioni per il menù (docs/17 §9: data, ore giocate, livello totale).
func slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {"exists": false, "ok": false}
	var res := load_slot(slot)
	if not res.ok:
		return {"exists": true, "ok": false, "error": res.error}
	var d: Dictionary = res.data
	return {"exists": true, "ok": true, "source": res.source, "mode": str(d.get("mode", "normal")),
		"saved_at_unix": int(d.get("saved_at_unix", 0)),
		"playtime_s": float(d.get("stats", {}).get("playtime_s", 0.0)),
		"total_level": _GameStateScript.total_level_of(d)}


func delete_slot(slot: int) -> void:
	if not is_valid_slot(slot):
		return
	_finish_thread()
	for p in [slot_path(slot), slot_path(slot) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for n in range(1, BACKUPS + 1):
		if FileAccess.file_exists(backup_path(slot, n)):
			DirAccess.remove_absolute(backup_path(slot, n))
	for p in day_copies(slot) + pre_migration_copies(slot):
		DirAccess.remove_absolute(p)
	_last_rotation.erase(slot)


# ------------------------------------------------------------------ export / import (R-SAV-4)

## Stringa Base64 della partita in corso ("" se nessuna partita).
func export_current() -> String:
	if not GameState.active:
		return ""
	return SaveCodec.to_base64(Game.snapshot(true))


## Decodifica e valida una stringa esportata; con slot valido la scrive nello slot.
## Validazione: gzip/JSON, versione di schema, tipi dei campi interi E forma delle sezioni (come load_slot): una stringa
## troncata o modificata a mano NON riesce, e lo slot di destinazione resta com'era. Uno slot gia' occupato si sovrascrive solo
## con `overwrite = true` (altrimenti errore "slot_occupied": chiedere conferma al giocatore); la partita che c'era passa a .bak1.
func import_string(text: String, slot: int = 0, overwrite: bool = false) -> Dictionary:
	var dec := SaveCodec.from_base64(text)
	if not dec.ok:
		return dec
	var res := SaveCodec.load_bytes(SaveCodec.encode(dec.data), Game.sim.int_paths(), SaveCodec.SCHEMA_VERSION, {}, Game.sim.soft_int_paths())
	if not res.ok:
		return res
	var bad := SaveCodec.check_shape(res.data, _reference_shape())
	if not bad.is_empty():
		push_warning("SaveService: stringa importata con sezioni di tipo sbagliato: %s" % ", ".join(bad))
		return {"ok": false, "data": {}, "error": "corrupt_types", "paths": bad}
	if slot != 0 and not is_valid_slot(slot):
		return {"ok": false, "data": {}, "error": "bad_slot"}       # 0 = solo controllo; uno slot inesistente non è un controllo
	if is_valid_slot(slot):
		if slot_exists(slot) and not overwrite:
			return {"ok": false, "data": {}, "error": "slot_occupied"}
		var err := save_data(slot, res.data, true)
		if err != OK:
			return {"ok": false, "data": {}, "error": "write_failed"}
	return res


## Testo (bilingue) per un codice d'errore di import_string.
func import_error_text(code: String) -> String:
	var key := "UI_SAVESAFE_IMPORT_ERR_" + code.to_upper()
	var t := TranslationServer.translate(key)
	if t == key:
		return TranslationServer.translate("UI_IMPORT_FAILED")
	return t


## Importazione guidata per la UI: se lo slot e' occupato chiede conferma (finestra), poi scrive; mostra l'esito con
## EventBus.notice (messaggio per codice d'errore). `on_done` (facoltativo) riceve il risultato di import_string
## (errore "cancelled" se il giocatore rinuncia).
func import_with_confirm(text: String, slot: int, on_done: Callable = Callable()) -> void:
	var res := import_string(text, slot, false)
	if not res.ok and res.error == "slot_occupied":
		var dlg := ConfirmationDialog.new()
		dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		dlg.title = TranslationServer.translate("UI_SAVESAFE_OVERWRITE_TITLE")
		dlg.dialog_text = Loc.tf("UI_SAVESAFE_OVERWRITE_BODY", {"n": slot})
		dlg.dialog_autowrap = true
		dlg.ok_button_text = TranslationServer.translate("UI_SAVESAFE_OVERWRITE_OK")
		dlg.cancel_button_text = TranslationServer.translate("UI_SAVESAFE_CANCEL")
		dlg.confirmed.connect(func() -> void:
			_finish_import(import_string(text, slot, true), on_done)
			dlg.queue_free())
		dlg.canceled.connect(func() -> void:
			if on_done.is_valid():
				on_done.call({"ok": false, "data": {}, "error": "cancelled"})
			dlg.queue_free())
		get_tree().root.add_child(dlg)
		dlg.popup_centered()
		return
	_finish_import(res, on_done)


func _finish_import(res: Dictionary, on_done: Callable) -> void:
	if res.ok:
		EventBus.notice.emit("success", TranslationServer.translate("UI_IMPORT_OK"), {})
	else:
		EventBus.notice.emit("error", import_error_text(str(res.error)), {})
	if on_done.is_valid():
		on_done.call(res)


# ------------------------------------------------------------------ thread

## Sul thread: preparazione dello snapshot (saturazione, interi grandi come stringa; e' una copia di proprieta' del thread,
## niente costo sul thread principale) e scrittura. Il Registro si aggiorna dal principale.
func _thread_save(slot: int, snapshot: Dictionary, int_paths: PackedStringArray) -> Error:
	var fixed := SaveCodec.prepare_for_write(snapshot, int_paths)
	if not fixed.is_empty():
		_log_saturation.call_deferred(slot, fixed)
	return write_atomic(slot, SaveCodec.encode(snapshot), int_paths)


func _poll_thread() -> void:
	if _thread == null or _thread.is_alive():
		return
	var err: Error = _thread.wait_to_finish()
	_thread = null
	_emit_result(_thread_slot, err)
	if _pending:
		_pending = false
		request_save()


func _finish_thread() -> void:
	if _thread != null:
		var err: Error = _thread.wait_to_finish()
		_thread = null
		_emit_result(_thread_slot, err)


func _emit_result(slot: int, err: Error) -> void:
	last_save_ok = err == OK
	if err == OK:
		last_saved_unix = Clock.now_unix()
		EventBus.save_completed.emit(true)
	else:
		last_error = error_string(err)
		push_warning("SaveService: salvataggio dello slot %d fallito (%s)" % [slot, last_error])
		EventBus.save_failed.emit(slot, last_error)
		EventBus.save_completed.emit(false)
