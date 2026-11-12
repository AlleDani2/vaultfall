extends GutTest
## T-0.4: layout principale, menù iniziale, registro delle schermate e regola "nessuna stringa visibile fissa".

const CSV_PATH := "res://localization/ui_strings.csv"
const MAIN := "res://src/ui/main/MainScreen.tscn"
const START := "res://src/ui/start/StartScreen.tscn"

var _keys: Dictionary = {}
var _old_dir: String


func before_all() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header := f.get_csv_line()
	assert_eq(Array(header), ["keys", "en", "it"])
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			_keys[row[0]] = [row[1], row[2]]


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ui_saves_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _files(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension() in exts:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(sub), exts))
	return out


func _without_comments(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			out.append(line)
	return "\n".join(out)


## Toglie specificatori di formato (%d, %s, %02d) e sequenze di escape prima di cercare lettere.
func _visible_letters(v: String, letters: RegEx) -> bool:
	var clean := RegEx.create_from_string("%[-0-9.]*[a-zA-Z]|\\\\.").sub(v, "", true)
	return letters.search(clean) != null


func test_csv_chiavi_complete() -> void:
	assert_gt(_keys.size(), 250)
	for k in _keys:
		assert_true(k.begins_with("UI_"), "chiave con prefisso UI_: " + k)
		assert_false(_keys[k][0].is_empty() or _keys[k][1].is_empty(), "EN e IT presenti: " + k)


func test_ogni_chiave_usata_esiste() -> void:
	var re := RegEx.create_from_string("\"(UI_[A-Z0-9_]+)\"")
	var missing := {}
	for p in _files("res://src", ["gd", "tscn"]):
		var text := _without_comments(FileAccess.get_file_as_string(p))
		for m in re.search_all(text):
			var k := m.get_string(1)
			if k.ends_with("_") :
				continue      # prefissi composti nel codice (es. "UI_MODE_" + modalità)
			if not _keys.has(k):
				missing[k] = p
	assert_eq(missing, {}, "chiavi usate nel codice ma assenti dal CSV")
	for m in GameState.MODES:
		assert_true(_keys.has("UI_MODE_" + m.to_upper()), "chiave composta per la modalità " + m)


func test_nessuna_stringa_visibile_fissa() -> void:
	# nelle scene: text/tooltip_text/placeholder_text devono essere chiavi UI_ o non contenere lettere
	var re_tscn := RegEx.create_from_string("(?m)^(text|tooltip_text|placeholder_text|dialog_text|title) = \"([^\"]*)\"")
	var re_gd := RegEx.create_from_string("\\.(text|tooltip_text|placeholder_text|dialog_text) = \"([^\"]*)\"")
	var letters := RegEx.create_from_string("[A-Za-zÀ-ÖØ-öø-ÿ]")
	var bad: Array = []
	for p in _files("res://src/ui", ["tscn"]):
		for m in re_tscn.search_all(FileAccess.get_file_as_string(p)):
			var v := m.get_string(2)
			if not v.begins_with("UI_") and _visible_letters(v, letters):
				bad.append("%s: %s" % [p, v])
	for p in _files("res://src/ui", ["gd"]):
		for m in re_gd.search_all(_without_comments(FileAccess.get_file_as_string(p))):
			var v := m.get_string(2)
			if not v.begins_with("UI_") and _visible_letters(v, letters):
				bad.append("%s: %s" % [p, v])
	assert_eq(bad, [], "stringhe visibili fisse (usare tr()/chiavi del CSV)")


func test_registro_schermate() -> void:
	var ids := {}
	var sections := {}
	for s in ScreenRegistry.SECTIONS:
		sections[s.id] = true
	var entries := ScreenRegistry.entries()
	for e in entries:
		assert_false(ids.has(e.id), "id unico: " + e.id)
		ids[e.id] = true
		assert_true(sections.has(e.section), "sezione valida per " + e.id)
		if not e.has("title_data"):
			assert_true(_keys.has(e.title), "titolo nel CSV: " + e.title)
		if not str(e.scene).is_empty():
			assert_true(ResourceLoader.exists(e.scene), "scena esistente: " + e.scene)
	var n_skills := 0
	for s in DataRegistry.table("skills"):
		if not ScreenRegistry.SKILL_GROUPS_HIDDEN.has(s.group):
			n_skills += 1
	assert_eq(entries.size(), ScreenRegistry.SCREENS.size() + n_skills, "una voce per mansione")
	assert_true(ScreenRegistry.is_available(ScreenRegistry.get_entry("summary"), []))
	assert_false(ScreenRegistry.is_available(ScreenRegistry.get_entry("vault_hall"), []), "bloccata")
	assert_true(ScreenRegistry.is_unlocked(ScreenRegistry.get_entry("vault_hall"), ["feature:crates"]))


func test_menu_iniziale() -> void:
	var start: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(start)
	await wait_process_frames(2)
	assert_true(start.get_node("%ContinueButton").disabled, "nessun salvataggio: Continua disattivato")
	start.show_slots()
	await wait_process_frames(1)
	assert_true(start.get_node("%Panel").visible)
	assert_eq(start.selected_mode(), "normal")
	assert_eq(start.describe_slot({"exists": false}), tr("UI_SLOT_EMPTY"))
	watch_signals(start)
	start.start_new(2)
	assert_signal_emitted_with_parameters(start, "navigate", [MAIN])
	assert_true(GameState.active)
	assert_eq(GameState.slot, 2)
	Game.stop_game(true)
	assert_eq(start.best_slot(), 2, "Continua sceglie lo slot salvato")
	start.show_settings()
	await wait_process_frames(1)
	assert_true(start.get_node("%Panel").visible)


func test_layout_principale() -> void:
	assert_true(Game.new_game(1, "normal", 99))
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_eq(main.current_id, "summary", "si apre sul Riepilogo")
	assert_true(main.current_screen() is GameScreen)
	assert_false(main.show_screen("prestige"), "voce bloccata")
	assert_false(main.show_screen("estate"), "voce non ancora realizzata")
	assert_true(main.show_screen("settings"))
	assert_eq(main.current_id, "settings")
	GameState.data.currencies.gold = 1250000
	main._on_ui_tick()
	assert_ne(main.get_node("%GoldValue").text, "0")
	EventBus.notice.emit("info", "test", {})
	assert_true(main.get_node("%Log").text.contains("test"))
	# ridimensionamento: il layout regge 1280x720 e 1920x1080
	for sz in [Vector2(1280, 720), Vector2(1920, 1080)]:
		main.size = sz
		await wait_process_frames(1)
		assert_true(main.get_node("Root/Body/Content").size.x > 300.0, "area contenuto visibile a %s" % str(sz))
	watch_signals(main)
	Game.stop_game(false)
	assert_signal_emitted_with_parameters(main, "navigate", ["res://src/ui/start/StartScreen.tscn"])
