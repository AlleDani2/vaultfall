extends GutTest
## Rapporto 36 N2 (docs/24 §7.1 punto 3): l'IP dell'ultimo host coop NON deve stare nel salvataggio né nello ZIP di
## «Segnala un problema». Vive solo nelle impostazioni locali (che lo ZIP non copia). I salvataggi vecchi che lo contengono
## vengono ripuliti e il loro contenuto passa alle impostazioni; la copia dello slot nello ZIP ne è comunque priva.

const HOST_IP := "203.0.113.77"

var _old_dir := ""
var _tmp := ""
var _old_host: Variant


func before_each() -> void:
	_tmp = "user://test_ippriv_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_tmp)
	_old_dir = SaveService.save_dir
	SaveService.save_dir = _tmp + "/saves"
	SaveService.autosave_enabled = false
	_old_host = Settings.get_value("coop_last_host")
	Settings.set_value("coop_last_host", {})


func after_each() -> void:
	CoopNetService.instance().leave_room()
	if GameState.active:
		Game.stop_game(false)
	Settings.set_value("coop_last_host", _old_host)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	_rm_rf(_tmp)


func _rm_rf(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm_rf(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _zip(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	assert_eq(zr.open(path), OK)
	var out := {}
	for f in zr.get_files():
		if not f.ends_with("/"):
			out[f] = zr.read_file(f)
	zr.close()
	return out


## Tutto il contenuto dello ZIP come testo (i .sav vengono decompressi: sono gzip).
func _zip_as_text(z: Dictionary) -> String:
	var all := ""
	for k in z:
		var b: PackedByteArray = z[k]
		if str(k).ends_with(".sav"):
			var dec := SaveCodec.decode(b)
			assert_true(dec.ok, "salvataggio nello ZIP decodificabile")
			all += JSON.stringify(dec.data)
		else:
			all += b.get_string_from_utf8()
	return all


func test_join_room_salva_l_ip_solo_nelle_impostazioni() -> void:
	var svc := CoopNetService.instance()
	Game.new_game(1, "normal", 5)
	assert_eq(svc.join_room(HOST_IP, 24991, "Bruno"), "")
	assert_eq(svc.last_host().get("ip"), HOST_IP, "il campo della Lobby si riempie ancora")
	assert_eq(int(svc.last_host().get("port")), 24991)
	var sec: Dictionary = (Game.system("coop_net") as CoopBonusSystem).state
	assert_false(sec.has("last_host"), "nella sezione del salvataggio non c'e' l'host")
	assert_false(JSON.stringify(GameState.data).contains(HOST_IP), "nessun HOST_IP nei dati di gioco")
	svc.leave_room()


func test_zip_reale_dopo_un_collegamento_non_contiene_alcun_ip() -> void:
	var svc := CoopNetService.instance()
	Game.new_game(1, "normal", 5)
	assert_eq(svc.join_room(HOST_IP, 24991, "Bruno"), "")
	svc.leave_room()
	assert_true(SaveService.save_now(true))
	var rb: Variant = Feedback.new_report("provo a entrare in coop su " + HOST_IP + " e anche 10.0.0.5")
	rb.out_dir = _tmp + "/out"
	var res: Variant = rb.build()
	assert_true(res.ok, str(res))
	var z := _zip(res.path)
	assert_true(z.has("salvataggio/slot_1.sav"))
	assert_true(z.has("impostazioni.cfg"))
	var txt := _zip_as_text(z)
	assert_false(txt.contains(HOST_IP), "l'HOST_IP e' nello ZIP")
	assert_false(txt.contains("10.0.0.5"), "gli HOST_IP scritti nella nota vanno ripuliti")
	assert_false(txt.contains("last_host") or txt.contains("coop_last_host"), "nessuna traccia della chiave")
	var re := RegEx.new()
	re.compile("(?<![0-9.])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9])")
	assert_null(re.search(txt), "nello ZIP non ci sono indirizzi IPv4")


func test_salvataggio_vecchio_con_ip_non_finisce_nello_zip_e_si_ripulisce() -> void:
	Game.new_game(1, "normal", 5)
	# simula un salvataggio di una versione precedente: l'HOST_IP sta in coop_net.last_host
	GameState.data["coop_net"]["last_host"] = {"ip": HOST_IP, "port": 24920}
	assert_true(SaveService.save_now(true))
	var raw := FileAccess.get_file_as_bytes(SaveService.slot_path(1))
	assert_true(JSON.stringify(SaveCodec.decode(raw).data).contains(HOST_IP), "premessa: il file vecchio contiene l'HOST_IP")
	var rb: Variant = Feedback.new_report("")
	rb.out_dir = _tmp + "/out"
	rb.save_first = false
	var res: Variant = rb.build()
	assert_true(res.ok)
	assert_false(_zip_as_text(_zip(res.path)).contains(HOST_IP), "la copia nello ZIP ha l'HOST_IP del file vecchio")
	# caricamento: la sezione si ripulisce e l'host passa alle impostazioni locali
	Game.stop_game(false)
	var sys := CoopBonusSystem.new()
	var old := SaveCodec.decode(raw).data["coop_net"] as Dictionary
	sys.from_state(old)
	assert_false(sys.state.has("last_host"), "from_state toglie l'HOST_IP dal salvataggio")
	assert_eq(str(Settings.get_value("coop_last_host").get("ip")), HOST_IP, "l'host ricordato passa alle impostazioni")


func test_impostazioni_dello_zip_senza_l_host() -> void:
	Settings.set_value("coop_last_host", {"ip": HOST_IP, "port": 24920})
	var rb: Variant = Feedback.new_report("")
	assert_false(rb.settings_text().contains(HOST_IP))
	assert_false(rb.settings_text().contains("coop_last_host"))


func test_scrub_ips() -> void:
	assert_eq(ReportBuilder.scrub_ips("host 192.168.1.20:24920 ok"), "host <ip>:24920 ok")
	assert_eq(ReportBuilder.scrub_ips("Godot 4.7.2 e v1.0.0"), "Godot 4.7.2 e v1.0.0", "le versioni non sono HOST_IP")
	assert_false(ReportBuilder.scrub_ips("fe80:0:0:0:1:2:3:4 chiuso").contains("fe80"))


func test_valori_ostili_in_impostazioni_danno_host_vuoto() -> void:
	var svc := CoopNetService.instance()
	Settings.set_value("coop_last_host", {"ip": 5, "port": "x"})
	assert_true(svc.last_host().is_empty())
	Settings.set_value("coop_last_host", {"ip": "a".repeat(100)})
	assert_true(svc.last_host().is_empty())
