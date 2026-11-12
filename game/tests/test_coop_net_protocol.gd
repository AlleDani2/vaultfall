extends GutTest
## COOP-2: protocollo di rete (validazione, dimensioni, versione, nomi) e limite di frequenza. Parti pure.

var net: Dictionary


func before_all() -> void:
	net = DataRegistry.rules("coop_net_rules").get("net", {})


func _dec(msg: Variant, from_host: bool = false) -> Dictionary:
	return CoopProtocol.decode(JSON.stringify(msg).to_utf8_buffer(), net, from_host)


func _presence() -> Dictionary:
	return {"t": "presence", "name": "Ale", "cls": "warrior", "lvl": 120, "hl": 30, "act": "skill",
		"sk": "woodcutting", "det": "wc_pine", "ping": 40}


func test_regole_nei_dati() -> void:
	var r := DataRegistry.rules("coop_net_rules")
	assert_false(r.is_empty(), "data/coop_net_rules.json generato")
	assert_eq(int(r.protocol_version), CoopProtocol.VERSION, "versione di protocollo uguale tra dati e codice")
	assert_lte(float(r.bonus_cap_pct), 10.0, "tetto dei bonus di gilda <= +10%")


func test_presenza_valida() -> void:
	var d := _dec(_presence())
	assert_true(d.ok, str(d.err))
	assert_typeof(d.msg.lvl, TYPE_INT, "interi JSON riportati a int")


func test_campi_extra_mancanti_e_tipi() -> void:
	var p := _presence()
	p["evil"] = 1
	assert_eq(_dec(p).err, "extra_field:evil")
	p = _presence()
	p.erase("lvl")
	assert_eq(_dec(p).err, "missing:lvl")
	p = _presence()
	p["lvl"] = 1.5
	assert_eq(_dec(p).err, "not_int:lvl")
	p = _presence()
	p["lvl"] = 999999999
	assert_eq(_dec(p).err, "range:lvl")
	p = _presence()
	p["act"] = "dance"
	assert_eq(_dec(p).err, "act:act")
	p = _presence()
	p["sk"] = "../../etc"
	assert_eq(_dec(p).err, "id:sk")


func test_tipi_vietati_nessuno_scambio() -> void:
	for t in ["gift", "trade", "withdraw", "give_item", "send_item"]:
		assert_eq(_dec({"t": t, "item": "crate_millbrook", "qty": 1}).err, "bad_type", "tipo inesistente: " + t)
	# il client non può fingersi host
	assert_eq(_dec({"t": "op", "gseq": 1, "op": {"k": "deposit"}}).err, "bad_type")
	assert_eq(_dec({"t": "cmd", "seq": 1, "op": "withdraw", "args": {}}).err, "op:op")
	assert_eq(_dec({"t": "cmd", "seq": 1, "op": "deposit", "args": {"item": "log_pine", "qty": 0}}).err, "args_range:qty")
	assert_true(_dec({"t": "cmd", "seq": 1, "op": "deposit", "args": {"item": "log_pine", "qty": 5}}).ok)


func test_pacchetti_malformati_e_troppo_grandi() -> void:
	assert_eq(CoopProtocol.decode(PackedByteArray(), net, false).err, "empty")
	assert_eq(CoopProtocol.decode("{non json".to_utf8_buffer(), net, false).err, "json")
	assert_eq(CoopProtocol.decode("[1,2,3]".to_utf8_buffer(), net, false).err, "not_object")
	var big := _presence()
	big["name"] = "x".repeat(5000)
	assert_eq(CoopProtocol.decode(JSON.stringify(big).to_utf8_buffer(), net, false).err, "oversize",
		"dimensione controllata prima del JSON")
	var junk := PackedByteArray()
	junk.resize(300)
	junk.fill(0xff)
	assert_false(CoopProtocol.decode(junk, net, false).ok, "byte casuali")
	assert_eq(_dec({"x": 1}).err, "no_type")


func test_nomi_filtrati() -> void:
	assert_eq(CoopProtocol.sanitize_name("  Ale   Silio  "), "Ale Silio")
	assert_eq(CoopProtocol.sanitize_name("Ségolène_1"), "Ségolène_1")
	assert_eq(CoopProtocol.sanitize_name("<script>"), "")
	assert_eq(CoopProtocol.sanitize_name("a" + String.chr(0x202e) + "b"), "", "caratteri di controllo/bidi")
	assert_eq(CoopProtocol.sanitize_name("x".repeat(40)).length(), 16)
	var p := _presence()
	p["name"] = "Bad<Name>"
	assert_eq(_dec(p).err, "name:name")


func test_versione_e_saluto() -> void:
	var h := {"t": "hello", "v": CoopProtocol.VERSION, "name": "Ale", "uid": "0123456789abcdef", "guild": "",
		"pw": "", "seq": 0}
	assert_true(_dec(h).ok)
	h["uid"] = "XYZ"
	assert_eq(_dec(h).err, "hex:uid")
	h["uid"] = "0123456789abcdef"
	h["guild"] = "g_zz"
	assert_eq(_dec(h).err, "gid:guild")


func test_roster_dall_host() -> void:
	var e := {"id": 1, "uid": "0123456789abcdef", "name": "Host", "cls": "", "lvl": 3, "hl": 1, "act": "rest",
		"sk": "", "det": "", "ping": 0, "age": 2}
	assert_true(_dec({"t": "roster", "list": [e]}, true).ok)
	var bad := e.duplicate()
	bad["name"] = 7
	assert_false(_dec({"t": "roster", "list": [bad]}, true).ok)
	var many: Array = []
	for i in 20:
		many.append(e)
	assert_false(_dec({"t": "roster", "list": many}, true).ok, "al massimo 9 voci")


func test_limite_di_frequenza() -> void:
	var rl := CoopRateLimiter.new()
	rl.configure({"rate_per_s": 2.0, "rate_burst": 4, "strikes_kick": 3})
	var passed := 0
	for i in 10:
		if rl.allow(5, 0.0):
			passed += 1
	assert_eq(passed, 4, "raffica massima")
	assert_true(rl.should_kick(5), "troppe violazioni")
	assert_true(rl.allow(6, 0.0), "pari separati")
	rl.forget(5)
	assert_true(rl.allow(5, 1.0))
	assert_false(rl.should_kick(5))


func test_presenza_costruita_dalle_attivita() -> void:
	var base := {"name": "Ale", "active": true, "cls": "ranger", "lvl": 50, "hl": 10}
	var p := CoopPresence.build(base.merged({"action": "wc_pine", "skill": "woodcutting"}))
	assert_eq([p.act, p.sk, p.det], ["skill", "woodcutting", "wc_pine"])
	assert_eq(CoopPresence.anim_of(p), "chop")
	p = CoopPresence.build(base.merged({"activity": {"type": "combat", "zone": "millbrook", "monster": "mud_slime"}}))
	assert_eq([p.act, p.det], ["combat", "millbrook"])
	assert_eq(CoopPresence.anim_of(p), "strike")
	p = CoopPresence.build(base.merged({"activity": {"type": "combat"}, "endgame": "raid"}))
	assert_eq(p.act, "raid")
	assert_eq(CoopPresence.build(base.merged({"crate_recent": true})).act, "crate")
	assert_eq(CoopPresence.anim_of(CoopPresence.build(base.merged({"crate_recent": true}))), "crate")
	assert_eq(CoopPresence.build(base.merged({"screen": "estate"})).act, "estate")
	assert_eq(CoopPresence.anim_of(CoopPresence.build(base)), "sleep", "riposo = dorme")
	# la schermata guardata vince sulla mansione/combattimento che gira da sola
	var busy := base.merged({"action": "wc_pine", "skill": "woodcutting", "screen": "estate"})
	assert_eq(CoopPresence.build(busy).act, "estate", "Tenuta aperta + mansione in corso = Tenuta")
	assert_eq(CoopPresence.anim_of(CoopPresence.build(busy)), "hammer")
	assert_eq(CoopPresence.build(busy.merged({"screen": "market"}, true)).act, "market")
	assert_eq(CoopPresence.build(busy.merged({"screen": "skills"}, true)).act, "skill", "altra schermata: resta la mansione")
	assert_eq(CoopPresence.build(base.merged({"activity": {"type": "combat", "zone": "z"}, "screen": "estate"})).act, "estate")
	assert_eq(CoopPresence.build({"name": "Ale"}).act, "menu")
	assert_true(_dec(CoopPresence.build(base.merged({"action": "wc_pine", "skill": "woodcutting"}))).ok,
		"la presenza costruita passa la validazione")
	var cook := CoopPresence.build(base.merged({"action": "cook_x", "skill": "cooking"}))
	assert_eq(CoopPresence.anim_of(cook), "cook")
	assert_eq(CoopPresence.anim_of({"act": "skill", "sk": "fishing"}), "fish")
	assert_eq(CoopPresence.anim_of({"act": "skill", "sk": "smithing"}), "hammer")
