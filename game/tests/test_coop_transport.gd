extends GutTest
## COOP-1: predisposizione per la fase successiva: formato dei messaggi (protocollo v1), CoopLink astratto e
## LocalFileLink (cartella condivisa). Nessuna rete.

var _dir: String


func before_each() -> void:
	_dir = "user://test_coop_transport_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_rm(_dir)


func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	DirAccess.remove_absolute(path)


func _pair() -> Array:
	var host := LocalFileLink.new(_dir)
	var client := LocalFileLink.new(_dir)
	assert_true(host.open(CoopLink.Role.HOST, "sessione1", "host"))
	assert_true(client.open(CoopLink.Role.CLIENT, "sessione1", "amico"))
	return [host, client]


func test_messaggio_andata_e_ritorno() -> void:
	var m := CoopLinkMessage.make("hello", "amico", "sessione1", 1, {"name": "Giulia", "proto": 1})
	assert_true(CoopLinkMessage.validate(m).ok)
	var text := CoopLinkMessage.encode(m)
	assert_true(text.begins_with("VFM1."))
	var back := CoopLinkMessage.decode(text)
	assert_true(back.ok, str(back))
	assert_eq(back.msg.t, "hello")
	assert_eq(back.msg.p.name, "Giulia")
	# manomesso: rifiutato
	var mid := text.length() >> 1
	var tampered := text.substr(0, mid) + ("B" if text[mid] != "B" else "C") + text.substr(mid + 1)
	assert_false(CoopLinkMessage.decode(tampered).ok)
	for e in get_errors():
		e.handled = true


func test_validazione_dei_messaggi() -> void:
	assert_false(CoopLinkMessage.validate({}).ok)
	assert_false(CoopLinkMessage.validate("ciao").ok)
	assert_eq(CoopLinkMessage.validate(CoopLinkMessage.make("teletrasporto", "a", "s", 1)).error, "type")
	var future := CoopLinkMessage.make("hello", "a", "s", 1)
	future["proto"] = 99
	assert_eq(CoopLinkMessage.validate(future).error, "version")
	assert_eq(CoopLinkMessage.validate(CoopLinkMessage.make("hello", "", "s", 1)).error, "ids")
	assert_eq(CoopLinkMessage.validate(CoopLinkMessage.make("hello", "a", "s", -1)).error, "seq")
	var big := CoopLinkMessage.make("state", "a", "s", 1, {"blob": "x".repeat(20000)})
	assert_eq(CoopLinkMessage.validate(big).error, "too_big")


func test_nessun_messaggio_trasporta_oggetti_o_valuta() -> void:
	for key in CoopLinkMessage.FORBIDDEN:
		var m := CoopLinkMessage.make("cmd", "a", "s", 1, {"azione": "versa", key: 1})
		assert_eq(CoopLinkMessage.validate(m).error, "forbidden", "campo vietato: " + key)
		var nested := CoopLinkMessage.make("cmd", "a", "s", 1, {"azione": {"dettagli": [{key: 5}]}})
		assert_eq(CoopLinkMessage.validate(nested).error, "forbidden", "anche annidato: " + key)
	var deep := {}
	var cur := deep
	for i in 12:
		cur["x"] = {}
		cur = cur["x"]
	assert_eq(CoopLinkMessage.validate(CoopLinkMessage.make("state", "a", "s", 1, deep)).error, "forbidden", "troppo profondo: respinto")


func test_trasporto_astratto_non_si_usa_da_solo() -> void:
	var t := CoopLink.new()
	assert_false(t.is_open())
	assert_eq(t.peers(), [])
	assert_eq(t.next_seq(), 1)
	assert_eq(t.next_seq(), 2)
	t.role = CoopLink.Role.HOST
	assert_true(t.is_host())
	var methods: Array = []
	for m in CoopLink.new().get_method_list():
		methods.append(str(m.name))
	for need in ["open", "close", "is_open", "send", "poll", "peers", "say"]:
		assert_true(methods.has(need), "interfaccia: " + need)
	for e in get_errors():
		e.handled = true


func test_host_e_client_si_parlano_su_cartella() -> void:
	var p := _pair()
	var host: LocalFileLink = p[0]
	var client: LocalFileLink = p[1]
	assert_true(host.is_host())
	assert_false(client.is_host())
	assert_true(client.say("hello", {"name": "Giulia"}))
	assert_true(host.say("hello_ack", {"ok": true}, "amico"))
	assert_true(client.say("snapshot_req", {}))
	var got_h := host.poll()
	assert_eq(got_h.size(), 2, "l'host vede i due messaggi del client")
	assert_eq(got_h[0].t, "hello")
	assert_eq(got_h[1].t, "snapshot_req")
	assert_lt(int(got_h[0].seq), int(got_h[1].seq), "in ordine di sequenza")
	var got_c := client.poll()
	assert_eq(got_c.size(), 1, "il client vede solo i messaggi degli altri")
	assert_eq(got_c[0].t, "hello_ack")
	assert_eq(host.poll().size(), 0, "ogni messaggio si legge una volta")
	assert_eq(host.peers(), ["amico"])
	assert_true(client.peers().has("host"))
	client.say("bye")
	host.poll()
	assert_eq(host.peers(), [])
	assert_eq(host.sent, 1)
	assert_eq(client.sent, 3)


func test_ordine_per_sequenza_e_destinatario() -> void:
	var p := _pair()
	var host: LocalFileLink = p[0]
	var client: LocalFileLink = p[1]
	var other := LocalFileLink.new(_dir)
	assert_true(other.open(CoopLink.Role.CLIENT, "sessione1", "terzo"))
	for i in 5:
		host.say("ping", {"n": i})
	host.say("state", {"solo_per": "terzo"}, "terzo")
	var a := client.poll()
	var c := other.poll()
	assert_eq(a.size(), 5, "il messaggio per «terzo» non arriva al client")
	assert_eq(c.size(), 6)
	for i in 5:
		assert_eq(int(a[i].p.n), i, "in ordine")


func test_file_corrotti_o_di_altre_sessioni_si_ignorano() -> void:
	var p := _pair()
	var host: LocalFileLink = p[0]
	var client: LocalFileLink = p[1]
	var dir := _dir.path_join("sessione1")
	var f := FileAccess.open(dir.path_join("000000007_x.msg"), FileAccess.WRITE)
	f.store_string("VFM1.QUJD")
	f.close()
	var g := FileAccess.open(dir.path_join("000000008_y.msg"), FileAccess.WRITE)
	g.store_string("spazzatura totale")
	g.close()
	# messaggio valido ma di un'altra sessione
	var foreign := CoopLinkMessage.make("hello", "intruso", "altra", 9)
	var h := FileAccess.open(dir.path_join("000000009_intruso.msg"), FileAccess.WRITE)
	h.store_string(CoopLinkMessage.encode(foreign))
	h.close()
	host.say("ping")
	var got := client.poll()
	assert_eq(got.size(), 1, "solo il messaggio valido della sessione")
	assert_eq(got[0].t, "ping")
	for e in get_errors():
		e.handled = true


func test_id_e_sessioni_pericolosi_si_rifiutano() -> void:
	var t := LocalFileLink.new(_dir)
	assert_false(t.open(CoopLink.Role.HOST, "../fuori", "host"))
	assert_false(t.open(CoopLink.Role.HOST, "s", "a/b"))
	assert_false(t.open(CoopLink.Role.HOST, "", "host"))
	assert_false(t.send(CoopLinkMessage.make("ping", "host", "s", 1)), "trasporto chiuso")
	assert_true(t.open(CoopLink.Role.HOST, "s", "host"))
	assert_false(t.send(CoopLinkMessage.make("ping", "impostore", "s", 1)), "il mittente deve essere chi ha aperto")
	assert_false(t.send(CoopLinkMessage.make("ping", "host", "altra", 1)), "la sessione deve essere la stessa")
	assert_false(t.send(CoopLinkMessage.make("cmd", "host", "s", 1, {"gold": 100})), "niente valuta")
