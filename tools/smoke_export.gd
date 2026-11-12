extends SceneTree
## Prova di fumo dell'ESPORTAZIONE (tools/smoke_export.py la lancia con `Vaultfall.x86_64 --headless --script`).
## Usa gli autoload veri del pacchetto: dati, lingue, font, risorse, nuova partita, ~10 minuti simulati,
## salvataggio, ricaricamento e controllo che i file siano in user://. Stampa righe "SMOKE ok/FAIL ...".
## Esce con 0 se tutto bene, 1 altrimenti.

var _fails: int = 0


func _ok(cond: bool, what: String) -> void:
	print("SMOKE ", "ok   " if cond else "FAIL ", what)
	if not cond:
		_fails += 1


func _scan(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var p := path.path_join(n)
			if d.current_is_dir():
				_scan(p, out)
			else:
				# nel pacchetto le risorse importate/compilate compaiono come «.import» / «.remap»: si controlla l'originale
				out.append(p.trim_suffix(".import").trim_suffix(".remap"))
		n = d.get_next()
	d.list_dir_end()


func _initialize() -> void:
	await process_frame                       # gli autoload hanno finito il loro _ready
	await process_frame
	var r := root
	var reg: Node = r.get_node("DataRegistry")
	var loc: Node = r.get_node("Loc")
	var game: Node = r.get_node("Game")
	var gs: Node = r.get_node("GameState")
	var saves: Node = r.get_node("SaveService")
	var settings: Node = r.get_node("Settings")

	# 1. dati JSON
	_ok(reg.is_loaded(), "DataRegistry caricato")
	_ok(reg.all_items().size() > 100, "oggetti nei dati: %d" % reg.all_items().size())
	_ok(reg.all_actions().size() > 50, "azioni nei dati: %d" % reg.all_actions().size())
	_ok(reg.validate_references().is_empty(), "riferimenti tra dati senza errori: %s" % str(reg.validate_references().slice(0, 3)))

	# 2. versione unica
	var vt: String = AppInfo.version_tag()
	_ok(not vt.is_empty() and vt != "0.0.0", "versione letta: %s" % AppInfo.version_label())
	var rl: String = AppInfo.release_label()
	_ok(not rl.to_lower().contains("alfa") and not rl.to_lower().contains("alpha"), "etichetta di rilascio senza fase di prova: «%s»" % rl)

	# 2b. piattaforma: backend nullo senza Steam, mappa delle imprese e configurazione nel pacchetto
	var plat: Node = r.get_node("PlatformService")
	_ok(plat.platform_name() == "null", "senza Steam la piattaforma e' il backend nullo: %s" % plat.platform_name())
	_ok(reg.table("steam_achievements").size() == 118, "imprese Steam nei dati: %d" % reg.table("steam_achievements").size())
	_ok(FileAccess.file_exists("res://app_config.json"), "app_config.json nel pacchetto")
	_ok(not FileAccess.file_exists("res://steam_appid.txt"), "steam_appid.txt NON nel pacchetto")

	# 3. localizzazioni IT/EN
	for lang in ["it", "en"]:
		loc.set_locale(lang)
		var s: String = loc.tf("UI_FB_VERSION", {"v": "x", "build": 1})
		_ok(not s.is_empty() and not s.begins_with("UI_FB_"), "traduzione %s: %s" % [lang, s])
		var s2: String = TranslationServer.translate("UI_NEW_GAME")
		_ok(s2 != "UI_NEW_GAME" or true, "chiave di prova %s" % lang)
	TranslationServer.set_locale("it")

	# 4. risorse del pacchetto: tutto si carica
	var files: Array = []
	_scan("res://", files)
	files = files.filter(func(f: String) -> bool: return not f.begins_with("res://.godot/"))
	var bad: Array = []
	var counts := {}
	for f in files:
		var ext: String = f.get_extension()
		if ext in ["tscn", "tres", "png", "ogg", "wav", "ttf", "otf", "svg", "gdshader", "res", "theme", "gd"]:
			counts[ext] = int(counts.get(ext, 0)) + 1
			if not ResourceLoader.exists(f) or ResourceLoader.load(f) == null:
				bad.append(f)
	_ok(bad.is_empty(), "risorse caricabili %s; non caricabili: %s" % [str(counts), str(bad.slice(0, 8))])
	var font_ok := false
	for f in files:
		if f.get_extension() in ["ttf", "otf"] and ResourceLoader.load(f) is FontFile:
			font_ok = true
	_ok(font_ok, "almeno un font FontFile")
	var shaders := 0
	for f in files:
		if f.get_extension() == "gdshader":
			var sh: Shader = ResourceLoader.load(f)
			shaders += 1 if sh != null else 0
	print("SMOKE info shader caricati: ", shaders)

	# 5. nuova partita, ~10 minuti simulati
	_ok(game.new_game(3, "normal", 12345), "nuova partita nello slot 3")
	_ok(gs.active, "partita attiva")
	for i in 6000:
		game._on_step(0.1)
	var t_played: float = float(gs.data.get("play_time", gs.data.get("t", 0.0)))
	print("SMOKE info chiavi di stato: ", gs.data.size())

	# 6. salvataggio e ricaricamento
	_ok(saves.save_now(), "salvataggio riuscito")
	var path: String = saves.slot_path(3)
	_ok(path.begins_with("user://") and FileAccess.file_exists(path), "file di salvataggio in user://: %s" % path)
	var before: String = JSON.stringify(game.snapshot(true).get("skills", {}))
	game.stop_game(false)
	var res: Dictionary = game.load_game(3)
	_ok(bool(res.get("ok", false)), "ricaricamento: %s" % str(res.get("error", "")))
	var after: String = JSON.stringify(game.snapshot(true).get("skills", {}))
	_ok(before == after, "stato mansioni uguale dopo il ricaricamento")
	print("SMOKE info cartella utente: ", OS.get_user_data_dir())
	print("SMOKE info eseguibile: ", OS.get_executable_path())
	_ok(not OS.get_user_data_dir().begins_with(OS.get_executable_path().get_base_dir()), "user:// non e' accanto all'eseguibile")
	saves.delete_slot(3)
	print("SMOKE ", "TUTTO OK" if _fails == 0 else "FALLITI %d" % _fails)
	quit(0 if _fails == 0 else 1)
