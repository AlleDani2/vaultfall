extends GutTest
## COOP-2: «Controlla connessione» (CoopDiagnose, funzione pura) e testi di aiuto Hamachi/ZeroTier/LAN in italiano e inglese.

const DEF := 24680


func _inp(over: Dictionary = {}) -> Dictionary:
	var d := {"mode": "join", "local_ips": ["192.168.1.20", "127.0.0.1", "fe80::1"], "ip": "192.168.1.50", "port": DEF,
		"default_port": DEF, "status": "offline", "problem": "", "port_free": -1, "rtt_ms": 0}
	d.merge(over, true)
	return d


func _ids(res: Array) -> Array:
	var out: Array = []
	for r in res:
		out.append("%s:%s" % [r.id, r.level])
	return out


func test_rete_assente() -> void:
	var r := _ids(CoopDiagnose.analyze(_inp({"local_ips": ["127.0.0.1", "169.254.4.4", "::1"]})))
	assert_true(r.has("net_none:bad"))
	assert_true(r.has("verdict:bad"))


func test_amico_tutto_a_posto_in_casa() -> void:
	var res := CoopDiagnose.analyze(_inp())
	var r := _ids(res)
	assert_true(r.has("net_ok:ok") and r.has("ip_lan_same:ok") and r.has("port_ok:ok") and r.has("not_tried:ok"), str(r))
	assert_eq(res.back().id, "verdict")
	assert_eq(res.back().level, "ok", "il consiglio sul firewall non e' un problema")


func test_errori_comuni_di_indirizzo() -> void:
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": ""}))).has("ip_empty:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "25.12.34.56:24680"}))).has("ip_with_port:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "25.12.34"}))).has("ip_format:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "ciao"}))).has("ip_format:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "300.1.1.1"}))).has("ip_format:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "192.168.1.20"}))).has("ip_self:bad"), "il proprio indirizzo")
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "127.0.0.1"}))).has("ip_self:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "169.254.9.9"}))).has("ip_linklocal:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": " 192.168.1.50 "}))).has("ip_lan_same:ok"), "spazi attorno: tolti")


func test_hamachi_acceso_o_spento() -> void:
	var off := _ids(CoopDiagnose.analyze(_inp({"ip": "25.12.34.56"})))
	assert_true(off.has("ip_hamachi_off:bad"), "indirizzo 25.x ma Hamachi non e' su questo PC")
	var on := _ids(CoopDiagnose.analyze(_inp({"ip": "25.12.34.56", "local_ips": ["192.168.1.20", "25.1.2.3"]})))
	assert_true(on.has("ip_hamachi_on:ok"))


func test_rete_privata_diversa_e_indirizzo_pubblico() -> void:
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "10.9.8.7"}))).has("ip_lan_other:warn"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"ip": "8.8.4.4"}))).has("ip_public:warn"))
	var ts := _ids(CoopDiagnose.analyze(_inp({"ip": "100.100.1.1", "local_ips": ["100.64.0.9"]})))
	assert_true(ts.has("ip_lan_same:ok"), "Tailscale (100.64/10) e' una rete privata")


func test_porta() -> void:
	assert_true(_ids(CoopDiagnose.analyze(_inp({"port": 80}))).has("port_range:bad"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"port": 30000}))).has("port_other:warn"))


func test_problemi_in_parole_povere() -> void:
	for p in ["version", "password", "full", "kicked", "dup_uid", "bad_name", "host_lost", "connect"]:
		var r := _ids(CoopDiagnose.analyze(_inp({"problem": p})))
		assert_true(r.has("problem_%s:bad" % p), p)
	assert_true(_ids(CoopDiagnose.analyze(_inp({"status": "connecting"}))).has("link_waiting:warn"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"status": "connected", "rtt_ms": 40}))).has("link_ok:ok"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"status": "suspended"}))).has("link_lost:warn"))


func test_host() -> void:
	var busy := _ids(CoopDiagnose.analyze(_inp({"mode": "host", "port_free": 0})))
	assert_true(busy.has("port_busy:bad") and busy.has("verdict:bad"))
	var ok := _ids(CoopDiagnose.analyze(_inp({"mode": "host", "port_free": 1, "local_ips": ["25.1.2.3"]})))
	assert_true(ok.has("port_free:ok") and ok.has("host_share_hamachi:ok") and ok.has("firewall_tip:info"), str(ok))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"mode": "host", "status": "hosting"}))).has("host_open:ok"))
	assert_true(_ids(CoopDiagnose.analyze(_inp({"mode": "host"}))).has("host_share_lan:ok"))


func _csv() -> Dictionary:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	var out: Dictionary = {}
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			out[row[0]] = row
	return out


func test_ogni_esito_ha_testo_in_italiano_e_inglese() -> void:
	var csv := _csv()
	for k in CoopDiagnose.all_keys():
		assert_true(csv.has(k), "chiave mancante " + k)
		if csv.has(k):
			assert_gt(csv[k][1].length(), 8, "EN " + k)
			assert_gt(csv[k][2].length(), 8, "IT " + k)
			assert_ne(csv[k][1], csv[k][2], "EN e IT diversi " + k)
	for k in ["BTN", "MARK_OK", "MARK_WARN", "MARK_BAD", "MARK_INFO"]:
		assert_true(csv.has("UI_COOPNET_DIAG_" + k), k)
	for k in ["HELP_START", "HELP_START_T"]:
		assert_true(csv.has("UI_COOPNET_" + k), k)


func test_tutti_gli_esiti_prodotti_hanno_una_chiave_dichiarata() -> void:
	var declared := CoopDiagnose.all_keys()
	var seen := 0
	var cases: Array = [_inp(), _inp({"ip": ""}), _inp({"ip": "25.1.1.1"}), _inp({"ip": "8.8.8.8", "status": "connecting"}),
		_inp({"mode": "host", "port_free": 0}), _inp({"mode": "host", "status": "hosting", "local_ips": []}),
		_inp({"problem": "password", "port": 1}), _inp({"ip": "1.2.3.4:5"}), _inp({"ip": "10.0.0.1", "status": "hosting"})]
	for c in cases:
		for r in CoopDiagnose.analyze(c):
			seen += 1
			assert_true(declared.has(CoopDiagnose.text_key(r)), "chiave non dichiarata: " + CoopDiagnose.text_key(r))
	assert_gt(seen, 20)


func test_testi_di_aiuto_spiegano_firewall_udp_e_cosa_fare() -> void:
	var csv := _csv()
	for lang in [1, 2]:
		var fw: String = csv["UI_COOPNET_HELP_FIREWALL"][lang]
		assert_true(fw.contains("UDP") and fw.contains("Firewall"), "firewall e UDP nominati")
		var tr_: String = csv["UI_COOPNET_HELP_TROUBLE"][lang]
		assert_true(tr_.contains("UDP") and tr_.contains("Hamachi") and tr_.contains("ZeroTier"))
		assert_true(csv["UI_COOPNET_HELP_HAMACHI"][lang].contains("25."))
		assert_true(csv["UI_COOPNET_HELP_ZEROTIER"][lang].contains("Auth"))


func test_la_lobby_mostra_il_controllo() -> void:
	var scr := load("res://src/ui/screens/CoopLobbyScreen.tscn") as PackedScene
	var s: Control = scr.instantiate()
	add_child_autofree(s)
	s.open({})
	await wait_process_frames(2)
	assert_not_null(s._diag_host)
	assert_not_null(s._diag_join)
	s._on_diag("join")
	s._on_diag("host")
	await wait_process_frames(1)
	assert_gt(s._diag_join.get_child_count(), 2, "righe di esito (la prima passata e' ancora in coda di rimozione)")
	assert_gt(s._diag_host.get_child_count(), 2)
