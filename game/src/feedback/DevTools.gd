class_name DevTools
extends RefCounted
## Strumenti da sviluppatore (menù F10) per riprodurre i problemi segnalati dagli amici.
## DISPONIBILI SOLO nelle build di sviluppo (editor o export di debug: `is_dev_build`). La variabile d'ambiente VAULTFALL_DEBUG=1
## serve solo ad accendere il menù in una build di sviluppo che lo tenesse spento: in un export di RILASCIO non fa NULLA
## (SHARK 1.0 #10: un giocatore non puo' attivare scorciatoie di sviluppo da un forum). Nemmeno il tasto F10 fa qualcosa.
## Qui solo azioni sui sistemi veri (nessuna formula nuova, nessun numero di bilanciamento): salto del tempo come offline,
## oro/oggetti/livelli, capitoli (riscattando le missioni vere), data degli eventi stagionali, salvataggio forzato,
## caricamento di un salvataggio ricevuto (file .sav o ZIP di segnalazione).

const ENV_VAR := "VAULTFALL_DEBUG"
const MAX_STEPS := 400


## True solo in una build di sviluppo: l'editor di Godot o un export di debug. MAI in un export di rilascio.
static func is_dev_build() -> bool:
	return OS.has_feature("editor") or OS.has_feature("debug")


## Menù F10 e strumenti: solo build di sviluppo; ignora VAULTFALL_DEBUG in rilascio. I parametri servono ai test (simulare un
## rilascio): `dev_build` = ci si trova in una build di sviluppo; `env_value` = valore di VAULTFALL_DEBUG ("" = leggi l'ambiente).
## In una build di sviluppo e' acceso (a meno che VAULTFALL_DEBUG valga esplicitamente "0").
static func is_enabled(dev_build: bool = is_dev_build(), env_value: String = "") -> bool:
	if not dev_build:
		return false
	var v := env_value if not env_value.is_empty() else OS.get_environment(ENV_VAR)
	return v.strip_edges() != "0"


func has_game() -> bool:
	return GameState.active


# ------------------------------------------------------------------ tempo, risorse, livelli

## Fa passare `seconds` di gioco come se il giocatore fosse stato via (stesso percorso dell'offline vero).
func skip_time(seconds: float) -> Dictionary:
	if not GameState.active or seconds <= 0.0:
		return {}
	var report := Game.sim.run_offline(seconds)
	EventBus.offline_progress.emit(seconds, report)
	return report


func give_gold(n: int) -> bool:
	var bank := Game.system("bank") as BankSystem
	if bank == null or not GameState.active or n <= 0:
		return false
	bank.add_gold(n)
	return true


## Dà un oggetto al Deposito. Ritorna la quantità davvero aggiunta (0 se l'id non esiste).
func give_item(item_id: String, qty: int) -> int:
	var bank := Game.system("bank") as BankSystem
	if bank == null or not GameState.active or qty <= 0 or not DataRegistry.has_item(item_id):
		return 0
	return bank.add(item_id, qty, "dev")


## Porta una mansione (sbloccata o no: la sblocca) al livello indicato, con XP veri. Ritorna il livello raggiunto.
func set_skill_level(skill_id: String, target: int) -> int:
	var sk := Game.system("skills") as SkillSystem
	if sk == null or not GameState.active or not GameState.data.skills.has(skill_id):
		return 0
	var steps := 0
	while sk.level(skill_id) < mini(target, sk.level_cap(skill_id)) and steps < MAX_STEPS:
		var p := sk.xp_progress(skill_id)
		sk.add_xp(skill_id, maxf(1.0, float(p[1]) - float(p[0])) + 0.01)
		steps += 1
	return sk.level(skill_id)


func all_skills_to(target: int) -> int:
	var n := 0
	for id in DataRegistry.skill_ids():
		if GameState.data.get("skills", {}).has(id) and set_skill_level(str(id), target) >= target:
			n += 1
	return n


# ------------------------------------------------------------------ capitoli

## Capitolo della missione principale in corso (-1 se la storia è finita o non c'è partita).
func current_chapter() -> int:
	var q := Game.system("quests") as QuestSystem
	if q == null or not GameState.active:
		return -1
	var id := q.current_main()
	return int(q.quest_def(id).get("chapter", 0)) if not id.is_empty() else -1


## Riscatta le missioni principali (ricompense e sblocchi veri) finché la missione in corso è nel capitolo `chapter`.
## Ritorna quante ne ha riscattate.
func unlock_chapter(chapter: int) -> int:
	var q := Game.system("quests") as QuestSystem
	if q == null or not GameState.active:
		return 0
	var n := 0
	while n < MAX_STEPS:
		var id := q.current_main()
		if id.is_empty() or int(q.quest_def(id).get("chapter", 0)) >= chapter:
			break
		var objs: Array = q.quest_def(id).get("objectives", [])
		var targets: Array = []
		for o in objs:
			targets.append(QuestSystem.target_of(o))
		q.state.progress[id] = targets
		if not q.claim(id):
			break
		n += 1
	return n


# ------------------------------------------------------------------ eventi stagionali, salvataggio

## Imposta la data (alle 12:00) che il calendario degli eventi vede. false se non c'è la partita.
func set_event_date(year: int, month: int, day: int) -> bool:
	var ev := Game.system("seasonal") as SeasonalEventSystem
	if ev == null or not GameState.active or month < 1 or month > 12 or day < 1 or day > 31 or year < 2000:
		return false
	ev.set_wall(SeasonalEventSystem.unix_of(year, month, day, 12), 0, true)
	return true


## Torna all'orologio vero.
func clear_event_date() -> void:
	var ev := Game.system("seasonal") as SeasonalEventSystem
	if ev != null:
		ev.wall_source = SeasonalEventSystem.system_wall


func force_save() -> bool:
	return SaveService.save_now()


# ------------------------------------------------------------------ salvataggio di un amico

## Estrae i byte di un salvataggio da un file .sav o da uno ZIP di segnalazione (salvataggio/slot_N.sav).
func read_save_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	if path.get_extension().to_lower() != "zip":
		return FileAccess.get_file_as_bytes(path)
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return PackedByteArray()
	var out := PackedByteArray()
	for f in zr.get_files():
		if f.begins_with("salvataggio/") and f.ends_with(".sav"):
			out = zr.read_file(f)
			break
	zr.close()
	return out


## Scrive il salvataggio dell'amico nello slot e lo carica. Con `keep_clock` (predefinito) l'orologio dell'ultimo salvataggio
## viene portato a «adesso»: nessun progresso offline inventato, si riparte esattamente da dov'era l'amico.
## Ritorna {ok, error}.
func load_friend_save(path: String, slot: int, keep_clock: bool = true) -> Dictionary:
	if not SaveService.is_valid_slot(slot):
		return {"ok": false, "error": "invalid_slot"}
	var bytes := read_save_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "error": "empty"}
	var res := SaveCodec.load_bytes(bytes, Game.sim.int_paths())
	if not res.ok:
		return {"ok": false, "error": str(res.error)}
	if keep_clock:
		res.data["saved_at_unix"] = Clock.now_unix()
	if SaveService.save_data(slot, res.data) != OK:
		return {"ok": false, "error": "write_failed"}
	var loaded := Game.load_game(slot)
	return {"ok": bool(loaded.ok), "error": str(loaded.get("error", ""))}
