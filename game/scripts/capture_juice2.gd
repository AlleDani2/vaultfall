extends Node
## Catture del «juice 2» (Tenuta, Sala delle Casse, transizioni, barre, contatori) nelle schermate vere.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     res://scripts/capture_juice2.tscn -- <cartella> [estate,reel,trans,combat,counter] [full|reduced|off]
## Nessuna API nuova richiesta: gira anche sul codice «prima» per le catture di confronto.

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://juice2"
var _only: PackedStringArray = []
var _mode := "full"
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
	SaveService.save_dir = "user://juice2_saves"
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


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _snap(tag: String) -> void:
	await _frames(1)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, tag, _mode]
	img.save_png(path)
	_n += 1
	print("CATTURA ", path)


func _press(name: String) -> void:
	var b: Node = _main.find_child(name, true, false)
	if b is BaseButton and b.is_visible_in_tree():
		(b as BaseButton).pressed.emit()


func _clear_banners() -> void:
	Fx._banner_queue.clear()
	if Fx._banner_cur != null and is_instance_valid(Fx._banner_cur):
		Fx._banner_cur.queue_free()
		Fx._banner_cur = null


func _clear_toasts() -> void:
	var t: Node = _main.find_child("Toasts", true, false)
	if t != null:
		for c in t.get_children():
			c.free()


func _cheat() -> void:
	var un: Object = Game.system("unlock")
	for t in ["combat", "crates", "market", "estate", "prestige", "skill_prestige", "bounties", "refinery", "tradeup"]:
		un.call("grant", "feature:" + t)
	var est: Object = Game.system("estate")
	for bid in est.call("building_ids"):
		un.call("grant", "building:" + str(bid))
	var bank: Object = Game.system("bank")
	bank.call("add", "gold", 90000000, "qa")
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
	if _want("reel"):
		await _reel()                     # prima: la Tenuta riempie il Deposito e le Casse non si aprirebbero più
	if _want("estate"):
		await _estate()
	if _want("trans"):
		await _trans()
	if _want("combat"):
		await _combat()
	if _want("counter"):
		await _counter()
	print("JUICE2_OK ", _n)
	get_tree().quit(0)


func _estate() -> void:
	var est: Object = Game.system("estate")
	var bank: Object = Game.system("bank")
	for round in 8:
		for bid in est.call("building_ids"):
			for k in 12:
				var cost: Dictionary = est.call("cost_of", str(bid))
				for it in cost.items:
					bank.call("add", str(it), int(cost.items[it]), "qa")
				if not est.call("upgrade", str(bid)):
					break
		est.call("tick", 3.0 * 3600.0)
	est.call("tick", 4.0 * 3600.0)
	_main.call("show_screen", "estate")
	_clear_banners()
	await _frames(6)
	for sc in _main.call("current_screen").find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 520
	_clear_toasts()
	for i in 4:
		await _snap("estate_%d" % i)
		await _wait(0.23)
	# produzione: nuovo carico, si guarda il «pop»
	est.call("tick", 1800.0)
	await _wait(0.35)
	await _snap("estate_prod_a")
	await _wait(0.15)
	await _snap("estate_prod_b")
	# potenziamento
	var scr: Node = _main.call("current_screen")
	for b in scr.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled and (b as Button).text == "+1":
			(b as Button).pressed.emit()
			break
	await _wait(0.12)
	await _snap("estate_upgrade_a")
	await _wait(0.25)
	await _snap("estate_upgrade_b")


func _reel() -> void:
	_main.call("show_screen", "vault_hall")
	_clear_banners()
	await _frames(6)
	var hall: Node = _main.call("current_screen")
	for b in hall.find_children("*", "Button", true, false):
		var tx := (b as Button).text
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled and tx.begins_with("Apri") and not tx.contains("×") and not tx.contains("rapida"):
			(b as Button).pressed.emit()
			break
	for t in [0.12, 0.4, 0.8]:
		await _wait(t)
		await _snap("reel_start_%d" % int(t * 100))
	await _wait(1.5)
	await _snap("reel_mid")
	await _wait(2.2)
	await _snap("reel_slow")
	await _wait(1.9)
	for i in 6:
		await _snap("reel_result_%d" % i)
		await _wait(0.25)


func _trans() -> void:
	_main.call("show_screen", "summary")
	await _wait(0.4)
	_main.call("show_screen", "bank")
	await _frames(1)
	await _snap("trans_f1")
	await _wait(0.05)
	await _snap("trans_f2")
	await _wait(0.2)
	await _snap("trans_f3")


func _combat() -> void:
	var cb: Object = Game.system("combat")
	var best := ""
	for z in cb.call("zones"):
		if cb.call("zone_unlocked", z.id):
			best = z.id
	cb.call("start", best)
	_main.call("show_screen", "combat")
	_clear_banners()
	await _frames(6)
	for i in 8:
		await _wait(0.35)
		await _snap("combat_bars_%d" % i)


func _counter() -> void:
	_main.call("show_screen", "summary")
	await _wait(0.4)
	await _snap("counter_before")
	Game.system("bank").call("add", "gold", 12345678, "qa")
	for i in 5:
		await _wait(0.1)
		await _snap("counter_%d" % i)
	EventBus.level_up.emit("woodcutting", 31)
	await _wait(0.15)
	await _snap("levelup_a")
	await _wait(0.4)
	await _snap("levelup_b")
