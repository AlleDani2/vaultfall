extends Node
## Cattura DAL VIVO degli effetti nelle schermate vere (Combattimento, Mansione, Rullo delle Casse, Missione completata,
## level up): bot fino a un punto avanzato, poi la schermata gira in tempo reale e si salvano i fotogrammi.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     res://scripts/capture_fx_live.tscn -- <cartella> [combat,skill,reel,progress] [full|reduced|off]

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://fxlive"
var _only: PackedStringArray = []
var _mode := "full"
var _fast := false                  # 5º argomento "fast": fotogrammi subito dopo l'evento (juice dei colpi)
var _main: Control
var _n := 0
var root: Window


func _ready() -> void:
	root = get_tree().root
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	if args.size() > 1 and args[1] != "all":
		_only = args[1].split(",")
	if args.size() > 2:
		_mode = args[2]
	_fast = args.size() > 3 and args[3] == "fast"
	SaveService.save_dir = "user://fxlive_saves"
	SaveService.autosave_enabled = false
	Settings.set_value("locale", "it")
	Settings.set_value("tutorials", false)
	Settings.set_value("reduce_motion", _mode == "off")
	Settings.set_value("fx_mode", "reduced" if _mode == "reduced" else "full")
	_run.call_deferred()


func _want(p: String) -> bool:
	return _only.is_empty() or _only.has(p)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(tag: String) -> void:
	await _frames(1)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, tag, _mode]
	img.save_png(path)
	_n += 1
	print("CATTURA ", path)


func _seq(tag: String, count: int, gap: float) -> void:
	for i in count:
		await get_tree().create_timer(gap).timeout
		await _snap("%s_%02d" % [tag, i])


func _press(name: String) -> void:
	var b: Node = _main.find_child(name, true, false)
	if b is BaseButton and b.is_visible_in_tree():
		(b as BaseButton).pressed.emit()


func _run() -> void:
	Game.new_game(1, "normal", 20261023)
	var bot = load("res://scripts/bot_player.gd").new(Game.sim, func(dt: float) -> void: Game._on_step(dt))
	bot.call("run_until_quest", "main_c1_q6", 3.0 * 3600.0)
	_cheat()
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(4)
	for k in 6:
		_press("WelcomeGo")
		_press("TutorialOk")
		await _frames(1)
	Settings.set_value("tutorials", false)
	_main.call("build_menu")
	await _frames(3)
	if _want("combat"):
		await _combat()
	if _want("skill"):
		await _skill()
	if _want("reel"):
		await _reel()
	if _want("progress"):
		await _progress()
	if _want("log"):
		await _log()
	print("FX_LIVE_OK ", _n)
	get_tree().quit(0)


func _cheat() -> void:
	var un: Object = Game.system("unlock")
	for t in ["combat", "crates", "market", "estate", "prestige", "skill_prestige", "bounties", "refinery", "tradeup"]:
		un.call("grant", "feature:" + t)
	var bank: Object = Game.system("bank")
	bank.call("add", "gold", 500000, "qa")
	for k in ["key_t1", "key_t2", "key_t3"]:
		bank.call("add", k, 40, "qa")
	for f in ["food_rabbit", "food_bleak"]:
		bank.call("add", f, 30, "qa")
	var cb: Object = Game.system("combat")
	cb.call("set_food", 0, "food_rabbit")
	var sk: Object = Game.system("skills")
	sk.call("add_xp", "woodcutting", 400000.0)
	sk.call("add_xp", "mining", 200000.0)
	sk.call("add_xp", "hero", 200000.0)
	for c in ["crate_millbrook", "crate_gatherer"]:
		bank.call("add", c, 12, "qa")


func _first_zone() -> String:
	var cb: Object = Game.system("combat")
	var best := ""
	for z in cb.call("zones"):
		if cb.call("zone_unlocked", z.id):
			best = z.id
	return best


func _combat() -> void:
	var cb: Object = Game.system("combat")
	cb.call("start", _first_zone())
	_main.call("show_screen", "combat")
	_clear_banners()
	await _frames(6)
	# fotogramma poco dopo ogni evento interessante (uccisione, tecnica, critico, danno subito, colpo): max 3 per tipo
	var last: int = cb.call("log_last_id")
	var got := {}
	var t_end := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < t_end and _n < 16:
		if _fast:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.08).timeout
		var kinds := {}
		for e in cb.call("log_since", last):
			last = int(e.id)
			var k := str(e.k)
			if k == "hit" and bool(e.crit):
				k = "crit"
			kinds[k] = true
		for k in ["kill", "cast", "crit", "ahit", "mhit", "mech", "phase", "hit"]:
			if kinds.has(k) and int(got.get(k, 0)) < 3:
				got[k] = int(got.get(k, 0)) + 1
				if _fast:
					await _frames(2)
				else:
					await get_tree().create_timer(0.12).timeout
				await _snap("combat_%s_%d" % [k, got[k]])
				break


func _clear_banners() -> void:
	Fx._banner_queue.clear()
	if Fx._banner_cur != null and is_instance_valid(Fx._banner_cur):
		Fx._banner_cur.queue_free()
		Fx._banner_cur = null


func _skill() -> void:
	_main.call("show_screen", "skill:woodcutting")
	_clear_banners()
	await _frames(4)
	var sk: Object = Game.system("skills")
	sk.call("start", "wc_pine")
	await _frames(4)
	await _seq("skill_live", 12, 0.12 if _fast else 0.35)


func _reel() -> void:
	_main.call("show_screen", "vault_hall")
	_clear_banners()
	await _frames(6)
	var hall: Node = _main.call("current_screen")
	# apre la prima cassa disponibile con il pulsante del rullo (stessa via del giocatore)
	for b in hall.find_children("*", "Button", true, false):
		var tx := (b as Button).text
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled and tx.begins_with("Apri") and not tx.contains("×") and not tx.contains("rapida"):
			(b as Button).pressed.emit()
			break
	await get_tree().create_timer(2.0).timeout
	await _snap("reel_mid")
	await get_tree().create_timer(3.1).timeout
	await _seq("reel_live", 9, 0.14)


## Registro a sezioni colorate (rapporto 104): un messaggio per sezione, poi la schermata con filo di sezione.
func _log() -> void:
	_main.call("show_screen", "skill:woodcutting")
	await _frames(3)
	var n := EventBus.notice
	n.emit("success", "Missione completata: Percorso: Taglialegna I. Riscatta la ricompensa!", {"quest": "main_c1_q1"})
	n.emit("info", "Hai raggiunto il livello 12 di Taglialegna. Le asce ti riconoscono per strada.", {"section": "skills"})
	n.emit("info", "Colpito per 14 danni da un Granchio Corazzato; ti sei ripreso con uno Spiedino.", {"section": "combat"})
	n.emit("warning", "Deposito pieno: Tronco di Pino perso. Libera un po' di spazio o vendi qualcosa.", {"reason": "bank_full", "item": "Tronco di Pino"})
	n.emit("success", "Cassa aperta: ottieni Mantello di Brina (Rara).", {"crate": "crate_millbrook"})
	n.emit("success", "Impresa sbloccata: Accetta della Domenica.", {"digest": "ach", "ach": "x"})
	n.emit("info", "Il Mulino ha prodotto 40 Farina.", {"estate_event": "mill"})
	n.emit("success", "Venduti 12 Tronco di Pino per 340 monete.", {"category": "loot"})
	n.emit("success", "Rito completato: ottieni 3 Stelle.", {"era": 1})
	n.emit("info", "Evento stagionale iniziato: Festa del Raccolto.", {"digest": "event", "event": "harvest"})
	n.emit("info", "Marta si è unita alla tua Gilda di amici.", {"section": "coop"})
	n.emit("info", "Salvataggio completato. [slot 1]", {"section": "system"})
	await _frames(3)
	await get_tree().create_timer(0.4).timeout
	await _snap("log_skill")
	_main.call("show_screen", "market")
	await _frames(3)
	await _snap("log_market")


func _progress() -> void:
	Fx.banner("Missione completata", "Prova dal vivo", FxPalette.GOLD)
	await _seq("progress_live", 3, 0.5)
	EventBus.level_up.emit("woodcutting", 30)
	await _seq("levelup_live", 4, 0.15)
