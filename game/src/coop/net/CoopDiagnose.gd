class_name CoopDiagnose
extends RefCounted
## «Controlla connessione» della Lobby (COOP-2): funzione PURA che legge ciò che il PC sa (indirizzi locali, IP e porta
## scritti, stato della stanza, ultimo problema) e produce una lista di esiti in parole povere. Nessun numero di
## bilanciamento: solo controlli di rete di buon senso. I testi sono chiavi UI_COOPNET_DIAG_<ID>_<LIVELLO> (bilingui).
##
## Ingressi (`inp`): mode ("host"|"join"), local_ips (Array di stringhe), ip, port, default_port, status (stato del servizio),
##   problem (ultimo problema: "version","password","full","kicked","dup_uid","bad_name","host_lost","connect","" ),
##   port_free (-1 non so, 0 occupata, 1 libera; solo host), rtt_ms.
## Uscita: Array di {"id": String, "level": "ok"|"warn"|"bad", "params": Dictionary}; l'ultimo è sempre il verdetto («verdict»).

const OK := "ok"
const WARN := "warn"
const BAD := "bad"
const INFO := "info"          # consiglio: non conta come problema
const PORT_MIN := 1024        # limiti dei campi «Porta» della Lobby (porte non riservate); non sono bilanciamento
const PORT_MAX := 65535


static func _octets(ip: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var parts := ip.split(".")
	if parts.size() != 4:
		return out
	for p in parts:
		if p.is_empty() or not p.is_valid_int() or p.length() > 3:
			return PackedInt32Array()
		var n := int(p)
		if n < 0 or n > 255:
			return PackedInt32Array()
		out.append(n)
	return out


static func is_valid_ipv4(ip: String) -> bool:
	return _octets(ip).size() == 4


static func is_private(o: PackedInt32Array) -> bool:
	if o.size() != 4:
		return false
	return o[0] == 10 or (o[0] == 172 and o[1] >= 16 and o[1] <= 31) or (o[0] == 192 and o[1] == 168) or is_cgnat(o)


## 100.64.0.0/10: gli indirizzi che danno Tailscale e simili.
static func is_cgnat(o: PackedInt32Array) -> bool:
	return o.size() == 4 and o[0] == 100 and o[1] >= 64 and o[1] <= 127


static func _same_net(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if is_cgnat(a):
		return is_cgnat(b)
	return a[0] == b[0] and a[1] == b[1]


## Indirizzi usabili da questo PC (IPv4, senza loopback né auto-assegnati 169.254).
static func usable_local(ips: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for a in ips:
		var s := str(a)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254.") or not is_valid_ipv4(s):
			continue
		out.append(s)
	return out


static func _f(id: String, level: String, params: Dictionary = {}) -> Dictionary:
	return {"id": id, "level": level, "params": params}


static func analyze(inp: Dictionary) -> Array:
	var out: Array = []
	var local := usable_local(inp.get("local_ips", []))
	var has_hamachi := false
	for a in local:
		if a.begins_with("25."):
			has_hamachi = true
	var port := int(inp.get("port", 0))
	var def_port := int(inp.get("default_port", 0))
	var mode := str(inp.get("mode", "join"))
	var status := str(inp.get("status", "offline"))
	var problem := str(inp.get("problem", ""))
	# 1) questo PC è in rete?
	if local.is_empty():
		out.append(_f("net_none", BAD))
	else:
		out.append(_f("net_ok", OK, {"list": ", ".join(local)}))
	# 2) porta
	if port < PORT_MIN or port > PORT_MAX:
		out.append(_f("port_range", BAD, {"min": PORT_MIN, "max": PORT_MAX}))
	elif port != def_port:
		out.append(_f("port_other", WARN, {"port": port, "def": def_port}))
	else:
		out.append(_f("port_ok", OK, {"port": port}))
	if mode == "host":
		_host_checks(out, inp, local, has_hamachi, status)
	else:
		_join_checks(out, inp, local, has_hamachi, status, problem)
	# 3) verdetto
	var bad := 0
	var warn := 0
	for r in out:
		if r.level == BAD:
			bad += 1
		elif r.level == WARN:
			warn += 1
	if bad > 0:
		out.append(_f("verdict", BAD, {"n": bad}))
	elif warn > 0:
		out.append(_f("verdict", WARN, {"n": warn}))
	else:
		out.append(_f("verdict", OK))
	return out


static func _host_checks(out: Array, inp: Dictionary, local: PackedStringArray, has_hamachi: bool, status: String) -> void:
	if status == "hosting":
		out.append(_f("host_open", OK))
	else:
		var pf := int(inp.get("port_free", -1))
		if pf == 0:
			out.append(_f("port_busy", BAD, {"port": int(inp.get("port", 0))}))
		elif pf == 1:
			out.append(_f("port_free", OK))
	if not local.is_empty():
		out.append(_f("host_share_hamachi" if has_hamachi else "host_share_lan", OK, {"list": ", ".join(local)}))
	out.append(_f("firewall_tip", INFO))


static func _join_checks(out: Array, inp: Dictionary, local: PackedStringArray, has_hamachi: bool, status: String,
		problem: String) -> void:
	var ip := str(inp.get("ip", "")).strip_edges()
	if ip.is_empty():
		out.append(_f("ip_empty", BAD))
	elif ip.contains(":") and is_valid_ipv4(ip.get_slice(":", 0)):
		out.append(_f("ip_with_port", BAD, {"ip": ip.get_slice(":", 0), "port": ip.get_slice(":", 1)}))
	elif not is_valid_ipv4(ip):
		out.append(_f("ip_format", BAD, {"ip": ip}))
	else:
		var o := _octets(ip)
		if ip.begins_with("127.") or local.has(ip):
			out.append(_f("ip_self", BAD, {"ip": ip}))
		elif ip.begins_with("169.254."):
			out.append(_f("ip_linklocal", BAD))
		elif o[0] == 25:
			out.append(_f("ip_hamachi_on" if has_hamachi else "ip_hamachi_off", OK if has_hamachi else BAD))
		elif is_private(o):
			var same := false
			for a in local:
				if _same_net(o, _octets(a)):
					same = true
			out.append(_f("ip_lan_same" if same else "ip_lan_other", OK if same else WARN, {"ip": ip}))
		else:
			out.append(_f("ip_public", WARN, {"ip": ip}))
	# stato della connessione e ultimo problema, in parole povere
	if problem != "":
		out.append(_f("problem_" + problem, BAD))
	match status:
		"connected":
			out.append(_f("link_ok", OK, {"ms": int(inp.get("rtt_ms", 0))}))
		"connecting":
			out.append(_f("link_waiting", WARN))
		"suspended":
			out.append(_f("link_lost", WARN))
		"hosting":
			out.append(_f("link_hosting", WARN))
	if problem == "" and status == "offline" and not ip.is_empty():
		out.append(_f("not_tried", OK))
	out.append(_f("firewall_tip", INFO))


## Chiave di testo di un esito.
static func text_key(r: Dictionary) -> String:
	return "UI_COOPNET_DIAG_%s_%s" % [str(r.id).to_upper(), str(r.level).to_upper()]


## Tutte le chiavi che analyze() può produrre (per il test di completezza delle traduzioni).
static func all_keys() -> PackedStringArray:
	var ids: Array = [["net_none", BAD], ["net_ok", OK], ["port_range", BAD], ["port_other", WARN], ["port_ok", OK],
		["host_open", OK], ["port_busy", BAD], ["port_free", OK], ["host_share_hamachi", OK], ["host_share_lan", OK],
		["firewall_tip", INFO], ["ip_empty", BAD], ["ip_with_port", BAD], ["ip_format", BAD], ["ip_self", BAD],
		["ip_linklocal", BAD], ["ip_hamachi_on", OK], ["ip_hamachi_off", BAD], ["ip_lan_same", OK], ["ip_lan_other", WARN],
		["ip_public", WARN], ["problem_version", BAD], ["problem_password", BAD], ["problem_full", BAD],
		["problem_kicked", BAD], ["problem_dup_uid", BAD], ["problem_bad_name", BAD], ["problem_host_lost", BAD],
		["problem_connect", BAD], ["link_ok", OK], ["link_waiting", WARN], ["link_lost", WARN], ["link_hosting", WARN],
		["not_tried", OK], ["verdict", OK], ["verdict", WARN], ["verdict", BAD]]
	var out := PackedStringArray()
	for p in ids:
		out.append(text_key(_f(p[0], p[1])))
	return out
