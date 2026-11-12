extends GutTest
## COOP-1: etica (CLAUDE.md regola 5, docs/24): nessuno scambio, nessun regalo, nessuna ricompensa a chi ha creato il codice,
## nessuna Cassa, nessun denaro reale. Controlli sul codice sorgente, sull'interfaccia pubblica e sul comportamento.

const Env := preload("res://tests/helpers/coop_env.gd")
const RAID_ID := "collectors_den"
const NOW := 1760000000
const FORBIDDEN_CALLS: PackedStringArray = ["get_system(\"bank\")", ".add_gold(", ".add_instance(", ".spend_gold(", ".remove_instance(",
	"crate_found", "get_system(\"market\")", "get_system(\"crates\")", "OS.shell_open", "HTTPRequest", "ENetMultiplayerPeer",
	"PacketPeer", "StreamPeerTCP", "WebSocket", "Steam.", "SteamMultiplayerPeer", "OS.get_unique_id", "OS.get_environment"]
const FORBIDDEN_NAMES: PackedStringArray = ["trade", "gift", "send_item", "give", "transfer", "offer", "sell", "buy", "wager", "stake",
	"jackpot", "coinflip", "gamble", "auction", "lend", "loan"]


func _sources() -> Dictionary:
	var out := {}
	var stack: Array = ["res://src/coop"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out[d.path_join(f)] = FileAccess.get_file_as_string(d.path_join(f))
		for sub in DirAccess.get_directories_at(d):
			if sub == "net":                      # rete della fase 2 (COOP-2): ha le sue regole e i suoi test
				continue
			stack.append(d.path_join(sub))
	return out


func after_each() -> void:
	Env.free_all()


func test_il_modulo_coop_non_tocca_deposito_casse_mercato_ne_rete() -> void:
	var src := _sources()
	assert_gt(src.size(), 6, "sorgenti trovati")
	for path in src:
		for pattern in FORBIDDEN_CALLS:
			assert_false(str(src[path]).contains(pattern), "%s non deve contenere %s" % [path, pattern])


func test_nessun_metodo_pubblico_parla_di_scambi() -> void:
	for obj in [CoopSystem.new(), CoopLink.new(), LocalFileLink.new()]:
		for m in (obj as Object).get_method_list():
			var n := str(m.name).to_lower()
			if n.begins_with("_") or n == "advance_calendar":      # metodo ereditato da GameSystem: "calendar" contiene "lend" (falso positivo)
				continue
			for bad in FORBIDDEN_NAMES:
				assert_false(n.contains(bad), "%s ha un metodo sospetto: %s" % [(obj as Object).get_script().get_global_name(), n])
	for t in CoopLinkMessage.TYPES:
		for bad in FORBIDDEN_NAMES:
			assert_false(str(t).contains(bad), "tipo di messaggio sospetto: " + str(t))


func test_chi_crea_il_codice_non_riceve_niente() -> void:
	var owner_env: Object = Env.make(9, 55, "warrior", 6, 1700111111)
	var code: String = owner_env.coop.export_hero_code(NOW)
	var snap := JSON.stringify([owner_env.state, owner_env.bank.stacks, owner_env.bank.inst, owner_env.bank.gold_n], "", true, true)
	var me: Object = Env.make(5, 55, "warrior", 6, 1700000000)
	me.unlock_raid(RAID_ID)
	assert_true(me.coop.import_code(code, NOW).ok)
	var crates_seen: Array = [0]
	me.bus.crate_found.connect(func(_c: String, _s: String) -> void: crates_seen[0] += 1)
	me.combat.eg.start_raid(RAID_ID, me.party("epic", 40))
	var n := 0
	while me.combat.in_combat() and n < 30000:
		me.tick(1)
		n += 1
	assert_eq(int(me.combat.state.raid_clears.get(RAID_ID, 0)), 1)
	assert_eq(crates_seen[0], 2, "solo le 2 Casse normali dell'incursione, per me")
	assert_eq(JSON.stringify([owner_env.state, owner_env.bank.stacks, owner_env.bank.inst, owner_env.bank.gold_n], "", true, true), snap,
		"il proprietario del codice non riceve né perde nulla")


func test_la_prova_della_settimana_non_da_ricompense() -> void:
	var env: Object = Env.make(13, 60, "warrior", 6, 1700000044)
	env.state.unlocks.append("feature:rift")
	var before := JSON.stringify([env.bank.stacks, env.bank.inst, env.bank.gold_n, env.combat.state.rift], "", true, true)
	var crates_seen: Array = [0]
	env.bus.crate_found.connect(func(_c: String, _s: String) -> void: crates_seen[0] += 1)
	var r: Dictionary = env.coop.weekly_run(NOW)
	assert_false(r.is_empty())
	assert_eq(crates_seen[0], 0, "nessuna Cassa")
	assert_eq(JSON.stringify([env.bank.stacks, env.bank.inst, env.bank.gold_n, env.combat.state.rift], "", true, true), before,
		"né Frammenti né oro né oggetti né record della Breccia vera")


func test_la_scheda_e_gli_stati_non_contengono_valuta_reale_o_dati_personali() -> void:
	var env: Object = Env.make(13, 60, "warrior", 6, 1700000055)
	var sheet: Dictionary = env.coop.build_sheet(NOW)
	var text := JSON.stringify(sheet).to_lower()
	for bad in ["@", "http", "email", "steam", "password", "iban", "euro", "usd", "payment"]:
		assert_false(text.contains(bad), "nella scheda non deve comparire: " + bad)
	# l'identificativo deriva dalla partita, non dall'utente: due partite create allo stesso istante hanno lo stesso id
	# (nessun nome utente, nessun percorso, nessun indirizzo)
	assert_eq(str(sheet.uid).length(), 16)
	assert_true(str(sheet.uid).is_valid_hex_number())
	assert_false(DataRegistry.rules("coop_rules").is_empty())


func test_il_gioco_dichiara_la_regola_nei_documenti() -> void:
	var doc := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/audit_2026-10-22/69_PROTOCOLLO_COOP.md"))
	# il test etico della coop NON si salta: i test girano dal repository, dove il documento c'e' sempre
	assert_false(doc.is_empty(), "docs/audit_2026-10-22/69_PROTOCOLLO_COOP.md raggiungibile da res://")
	if doc.is_empty():
		return
	assert_true(doc.to_lower().contains("nessuno scambio"))
	assert_true(doc.contains("VFH1"))
