extends SceneTree
## Giro fotografico UI-A: Deposito (menù contestuale, vendita multipla, regole automatiche), Compendio (nuove schede),
## Riepilogo (profilo, Bonus attivi), Eroe (tooltip di calcolo, finitura, trascinamento), Combattimento (filtri del registro),
## Impostazioni (notifiche), conferma di chiusura.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_ui_a.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_ui_a"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_ui_a_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	root.get_node("Settings").call("set_value", "tutorials", false)
	_tour.call_deferred()


func _noop() -> void:
	pass


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var code := OS.execute("import", ["-window", "root", abs_path])
	if code != 0:
		root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name, " codice ", code)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var state: Node = root.get_node("GameState")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 11)
	var d: Dictionary = state.get("data")
	for t in ["feature:combat", "feature:crates", "feature:market", "feature:factions", "skill:woodcutting", "skill:mining",
			"feature:world_bosses"]:
		(d.unlocks as Array).append(t)
	for sk in ["woodcutting", "mining"]:
		(d.skills as Dictionary)[sk] = {"xp": 0.0, "level": 40}
	var bank: Object = game.call("system", "bank")
	var combat: Object = game.call("system", "combat")
	var codex: Object = game.call("system", "codex")
	for it in ["plate_helm_copper", "plate_helm_copper", "plate_helm_copper"]:
		bank.call("add_instance", {"def": it})
	var fine: String = bank.call("add_instance", {"def": "plate_helm_copper", "quality": "fine"})
	bank.call("add_instance", {"def": "plate_body_copper", "quality": "excellent"})
	bank.call("add", "log_pine", 60, "prova")
	bank.call("add", "ore_copper", 45, "prova")
	bank.call("add", "mm_rough_fang", 12, "prova")
	bank.call("add_gold", 5000)
	var worn: String = bank.call("add_instance", {"def": "plate_helm_copper", "quality": "normal"})
	combat.call("equip", worn)
	bank.call("add_instance", {"def_id": "cosmetic_banner_01", "kind": "cosmetic", "source": "prova"})
	bank.call("add_instance", {"def_id": "cosmetic_banner_02", "kind": "cosmetic", "source": "prova"})
	var emblems: Array = codex.call("all_cosmetics", "emblem")
	bank.call("add_instance", {"def_id": str(emblems[0]), "kind": "cosmetic", "source": "prova"})
	codex.call("select", "banner", "cosmetic_banner_01")
	codex.call("select", "emblem", str(emblems[0]))
	root.get_node("EventBus").emit_signal("monster_killed", "mud_slime", [{"id": "mm_rough_fang", "qty": 2}])
	(d.stats as Dictionary)["kills"] = 3120
	(d.stats as Dictionary)["gold_earned"] = 184500
	root.get_node("Modifiers").call("set_source", "constellation", [{"key": "auto_sell_unlock", "value": 1}])
	var assist: Object = game.call("system", "assist")
	assist.call("add_rule", {"cat": "material", "max_tier": 1})
	assist.call("add_rule", {"cat": "equipment", "max_tier": 2, "max_quality": "normal"})
	game.get("sim").call("tick", 0.1)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	var wb := main.find_child("WelcomeGo", true, false) as Button
	if wb != null:
		wb.pressed.emit()
		await _frames(2)
	var tut := main.find_child("TutorialOk", true, false) as Button
	if tut != null:
		tut.pressed.emit()
		await _frames(2)
	await create_timer(6.0).timeout          # lascia sparire i banner di «Impresa sbloccata» e gli avvisi
	# Riepilogo con profilo e Bonus attivi
	main.call("show_screen", "summary")
	await _shot("riepilogo_profilo")
	var sm: Control = main.call("current_screen")
	sm.call("open_bonus_panel")
	await _shot("bonus_attivi")
	var dlgs := sm.find_children("*", "BonusDialog", false, false)
	for dl in dlgs:
		dl.queue_free()
	await _frames(3)
	# Deposito
	main.call("show_screen", "bank")
	var b: Control = main.call("current_screen")
	await _frames(3)
	b.set("_selected", fine)
	b.call("_mark_dirty")
	await _shot("deposito_confronto")
	# tooltip dell'oggetto con confronto (i tooltip veri compaiono solo al passaggio del mouse: qui lo si mostra a mano)
	var tp := PanelContainer.new()
	tp.theme_type_variation = &"RaisedPanel"
	tp.position = Vector2(330, 250)
	var tip: Control = (load("res://src/ui/ItemTooltip.gd") as GDScript).call("make_control", "plate_helm_copper", bank.call("get_instance", fine))
	tp.add_child(tip)
	root.add_child(tp)
	await _shot("tooltip_oggetto")
	tp.queue_free()
	b.call("open_multi_sell")
	await _frames(3)
	await _shot("deposito_vendita_multipla")
	for dl in b.find_children("*", "SellDialog", false, false):
		dl.queue_free()
	await _frames(3)
	b.call("open_auto_sell")
	await _shot("deposito_regole_automatiche")
	for dl in b.find_children("*", "AutoSellDialog", false, false):
		dl.queue_free()
	await _frames(3)
	# Compendio
	main.call("show_screen", "compendium")
	var cs: Control = main.call("current_screen")
	for tab in [1, 4, 5, 6, 7]:
		cs.get("_tabs").set("current_tab", tab)
		cs.call("refresh")
		if tab == 5:
			var mv: Control = cs.get("_views")[5]
			mv.set("_selected", "mud_slime")
			mv.call("_rebuild")
		await _shot("compendio_%d" % tab)
	# Eroe
	main.call("show_screen", "hero")
	await _shot("eroe")
	var bd := PanelContainer.new()
	bd.theme_type_variation = &"RaisedPanel"
	bd.position = Vector2(60, 300)
	var bl := Label.new()
	bl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size.x = 420
	var sb := load("res://src/ui/StatBreakdown.gd") as GDScript
	var lines := ""
	for sname in ["acc", "hp", "max_hit", "interval"]:
		lines += str((sb.call("explain", combat, sname) as Dictionary).get("formula", "")) + "\n"
	bl.text = lines
	bd.add_child(bl)
	root.add_child(bd)
	await _shot("eroe_tooltip_calcolo")
	bd.queue_free()
	# Combattimento (con registro)
	main.call("show_screen", "combat")
	var zone := str((root.get_node("DataRegistry").call("table", "zones") as Array)[0].id)
	combat.call("start", zone)
	game.get("sim").call("tick", 0.1)
	await _frames(4)
	var cb: Control = main.call("current_screen")
	cb.call("_add_line", "[color=#e0b640]Drop raro: Cassa della Valle[/color]", "rare")
	cb.call("_add_line", "[color=#e0b640]Colpo Devastante![/color]", "boss")
	cb.call("_add_line", "Colpo: 12")
	cb.call("refresh")
	await _shot("combattimento_registro")
	root.get_node("Settings").call("set_value", "combat_log_filter", "rare")
	cb.call("refresh")
	await _shot("combattimento_registro_raro")
	root.get_node("Settings").call("set_value", "combat_log_filter", "all")
	# Impostazioni
	main.call("show_screen", "settings")
	await _shot("impostazioni_notifiche")
	var st: Control = main.call("current_screen")
	st.get_v_scroll_bar().value = 600
	await _shot("impostazioni_notifiche_2")
	# Conferma di chiusura
	var closer: GDScript = load("res://src/ui/CloseGuard.gd")
	var dlg: ConfirmationDialog = closer.call("build_dialog", closer.call("combat_status"), Callable(self, "_noop"))
	root.add_child(dlg)
	dlg.popup_centered()
	await _shot("conferma_chiusura")
	quit(0)
