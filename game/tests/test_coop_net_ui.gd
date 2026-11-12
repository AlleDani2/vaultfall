extends GutTest
## COOP-2: servizio vero (host su localhost), bonus di gilda nel salvataggio personale (anche senza rete), rimborsi
## espliciti, regole senza ripieghi, testi IT/EN, riquadro Amici, personaggini animati, schermate Lobby e Gilda.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const CSV_PATH := "res://localization/ui_strings.csv"

var _old_dir := ""
var _dir := ""
var _svc: CoopNetService
var _keys := {}


func before_all() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			_keys[row[0]] = true


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_dir = "user://test_coopnet_%d" % Time.get_ticks_usec()
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	_svc = CoopNetService.instance()
	_svc.store.dir = _dir + "/coop"


func after_each() -> void:
	_svc.leave_room()
	if GameState.active:
		Game.stop_game(false)
	for gid in _svc.store.list_ids():
		_svc.store.delete(gid)
	DirAccess.remove_absolute(_dir + "/coop")
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	_svc.store.dir = CoopGuildStore.DEFAULT_DIR


func _port() -> int:
	return 24900 + (Time.get_ticks_usec() % 50)


func test_regole_complete_senza_ripieghi() -> void:
	var r := DataRegistry.rules("coop_net_rules")
	assert_eq(CoopGuild.missing_rule_keys(r), PackedStringArray(), "tutte le chiavi lette dal codice sono nei dati")
	var broken: Dictionary = r.duplicate(true)
	broken.boss.erase("week_s")
	broken.net.erase("rate_per_s")
	var miss := CoopGuild.missing_rule_keys(broken)
	assert_true(miss.has("boss.week_s") and miss.has("net.rate_per_s"), "una chiave mancante si vede: nessun numero di ripiego")
	assert_false(_svc.rules.is_empty(), "il servizio (autoload CoopNet) ha le regole")
	assert_eq(get_tree().root.get_node_or_null("/root/CoopNet"), _svc, "servizio creato dal gioco, non dalla UI")


func test_testi_bilingui_presenti() -> void:
	var composed := []
	for s in ["OFFLINE", "HOSTING", "CONNECTING", "CONNECTED", "SUSPENDED"]:
		composed.append("UI_COOPNET_ST_" + s)
	for s in ["ONLINE", "STALE", "OFFLINE"]:
		composed.append("UI_COOPNET_ROW_CONN_" + s)
	for s in ["LEADER", "MEMBER"]:
		composed.append("UI_COOPNET_ROLE_" + s)
	for s in CoopNetService.FATAL_REJECT:
		composed.append("UI_COOPNET_REJECT_" + s.to_upper())
	for s in ["found", "join", "rejoin", "leave", "kick", "leader", "deposit", "propose", "vote", "approved", "rejected",
			"level", "boss_new", "boss_hit", "boss_down"]:
		composed.append("UI_COOPNET_LOG_" + s.to_upper())
	for s in ["bad_name", "port", "no_rules", "full", "guild", "bad_ip", "connect", "not_member", "not_depositable",
			"bad_qty", "cap", "outbox_full", "no_game", "locked", "not_enough", "no_guild", "pending", "boss_done",
			"no_boss", "no_attempts", "no_hero", "other_guild", "not_leader", "bad_target", "bad_project", "max_level",
			"busy", "no_proposal", "too_early", "rejected", "stale_week", "bad_pts", "dup", "gap", "bad_op", "already",
			"bad_member", "bad_vote", "bad_ts"]:
		composed.append("UI_COOPNET_ERR_" + s.to_upper())
	for k in ["HAMACHI", "ZEROTIER", "LAN", "FIREWALL", "TROUBLE"]:
		composed.append("UI_COOPNET_HELP_%s_T" % k)
	for k in composed:
		assert_true(_keys.has(k), "chiave nel CSV: " + k)


func test_host_versa_bonus_salvato_e_valido_da_solo() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var bank: Object = Game.system("bank")
	bank.add_gold(100000)
	var gold0: int = bank.gold()
	assert_eq(_svc.host_room(_port(), "Ale", "Amici", ""), "")
	assert_true(_svc.is_host())
	var g := _svc.guild
	assert_eq(_svc.deposit("gold", 10000), "")
	assert_eq(bank.gold(), gold0 - 10000, "l'oro esce dal Deposito personale")
	assert_eq(g.fund_points(), 10000)
	assert_eq(_svc.deposit("crate_millbrook", 1), "not_depositable")
	assert_eq(_svc.propose("banner_scholars"), "", "da solo: la maggioranza è il Capo")
	assert_eq(g.project_level("banner_scholars"), 1, "costruito subito (10.000 punti per 1 socio)")
	var expect := float(DataRegistry.rules("coop_net_rules").projects[0].value_by_level[1])
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["all"]), expect, 0.0001, "bonus via Modifiers, fonte guild:*")
	# chiudo la stanza, salvo, ricarico: il bonus resta (copia nel salvataggio personale, nessuna rete)
	_svc.leave_room()
	SaveService.save_now()
	Game.stop_game(false)
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["all"]), 0.0, 0.0001)
	var res := Game.load_game(1)
	assert_true(res.ok)
	assert_eq(_svc.status, CoopNetService.ST_OFFLINE)
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["all"]), expect, 0.0001, "bonus attivo anche offline/da solo")
	assert_true(Modifiers.stack.has_source("guild:banner_scholars"))


func test_espulsione_restituisce_i_versamenti_non_confermati() -> void:
	assert_true(Game.new_game(1, "normal", 8))
	var bank: Object = Game.system("bank")
	bank.add_gold(5000)
	var gold0: int = bank.gold()
	var sys := Game.system("coop_net") as CoopBonusSystem
	sys.set_membership("g_0123456789ab", "Amici", {"banner_scholars": 2})
	assert_gt(Modifiers.total_add("skill_xp_pct", ["all"]), 0.0)
	# due versamenti in cassetta: il 5 l'host lo aveva applicato, il 6 no
	bank.remove("gold", 300)
	sys.state.outbox = [{"seq": 5, "op": "deposit", "args": {"item": "gold", "qty": 100}, "gid": "g_0123456789ab"},
		{"seq": 6, "op": "deposit", "args": {"item": "gold", "qty": 200}, "gid": "g_0123456789ab"}]
	watch_signals(_svc)
	_svc._on_reject("kicked", 5)
	assert_eq(bank.gold(), gold0 - 100, "il versamento non applicato (200) torna nel Deposito, quello applicato no")
	assert_eq((sys.state.outbox as Array).size(), 0, "cassetta svuotata")
	assert_signal_emitted(_svc, "notice", "rimborso con avviso, mai in silenzio")
	assert_eq(str(sys.state.guild_id), "")
	assert_almost_eq(Modifiers.total_add("skill_xp_pct", ["all"]), 0.0, 0.0001, "fuori dalla gilda: niente bonus")


func test_uscita_con_versamenti_in_attesa_chiede_conferma() -> void:
	assert_true(Game.new_game(1, "normal", 9))
	Game.system("bank").add_gold(50000)
	assert_eq(_svc.host_room(_port(), "Ale", "", ""), "")
	var g := _svc.guild
	# simulo un comando non ancora confermato
	(Game.system("coop_net") as CoopBonusSystem).state.outbox.append({"seq": 999, "op": "deposit",
		"args": {"item": "gold", "qty": 1}, "gid": g.guild_id()})
	assert_eq(_svc.leave_guild(), "pending", "prima la conferma esplicita")
	(Game.system("coop_net") as CoopBonusSystem).state.outbox.clear()
	assert_eq(_svc.leave_guild(), "")
	assert_false(g.is_member(_svc.my_uid()) and _svc.guild.n_active() > 1)


func test_personaggini_e_riquadro_amici() -> void:
	for a in ["strike", "chop", "pick", "hammer", "saw", "fish", "cook", "brew", "gather", "sneak", "walk", "crate", "sleep"]:
		var s := FriendSprite.new()
		s.setup("warrior", a, true)
		add_child_autofree(s)
		s._t = 0.4
		s.queue_redraw()
	await wait_process_frames(2)
	assert_ne(FriendSprite.color_for_class("warrior"), FriendSprite.color_for_class("arcanist"), "colore per classe")
	assert_eq(FriendSprite.color_for_class("paladin"), FriendSprite.color_for_class("warrior"), "le figlie ereditano")
	var f := {"act": "skill", "sk": "woodcutting", "det": "wc_pine"}
	assert_true(FriendsPanel.activity_text(f).length() > 3)
	assert_ne(FriendsPanel.activity_text({"act": "crate"}), FriendsPanel.activity_text({"act": "rest"}))


func test_ogni_attivita_ha_testo_e_animazione_distinti() -> void:
	var acts := {"skill": "chop", "combat": "strike", "dungeon": "strike", "raid": "strike", "wboss": "strike", "rift": "strike",
		"crate": "crate", "estate": "hammer", "market": "walk", "rest": "sleep", "menu": "sleep", "idle": "sleep"}
	var texts: Dictionary = {}
	for a in acts:
		var f := {"act": a, "sk": "woodcutting", "det": "wc_pine"}
		assert_eq(CoopPresence.anim_of(f), acts[a], "animazione di %s" % a)
		var t := FriendsPanel.activity_text(f)
		assert_gt(t.length(), 3, "testo di %s" % a)
		assert_false(t.begins_with("UI_"), "%s: chiave non tradotta" % a)
		texts[t] = true
	assert_gte(texts.size(), 9, "testi diversi per le attivita' diverse")


func test_schermate_lobby_e_gilda() -> void:
	assert_true(Game.new_game(1, "normal", 10))
	Game.system("unlock").grant("feature:coop")      # lo concede COOP-1 al primo raid
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var col: Node = main.get_node("Root/Body/RightColumn/RightScroll/VBox/AmiciSlot")
	assert_true(col.get_child(0) is FriendsPanel, "riquadro Amici nello slot del cassetto destro (F3)")
	assert_true(main.show_screen("coop_lobby"), "Lobby nel menù Progressi")
	await wait_process_frames(1)
	assert_true(main.show_screen("coop_guild"))
	await wait_process_frames(1)
	assert_eq(_svc.host_room(_port(), "Ale", "Amici", ""), "")
	await wait_process_frames(1)
	main.current_screen().refresh()
	await wait_process_frames(1)
	assert_true(main.show_screen("coop_lobby"))
	main.current_screen().refresh()
	await wait_process_frames(1)
	Game.stop_game(false)
