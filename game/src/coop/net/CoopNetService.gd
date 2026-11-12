class_name CoopNetService
extends Node
@warning_ignore_start("integer_division")
## Servizio di rete del coop tra amici (COOP-2, docs/audit_2026-10-22/70_RESOCONTO_COOP2.md).
##   Livello A «Presenza»: stanza ENet (host = uno degli amici), ogni 3 s un messaggio minuscolo per giocatore,
##   l'host rimanda a tutti il «roster» (nome, classe, livello, attività, latenza). Nessuno stato di gioco condiviso.
##   Livello B «Gilda di amici»: partita di gilda asincrona ospitata dall'host (CoopGuild, autorevole sull'host),
##   salvata a parte (CoopGuildStore). Comandi dai soci con numero di sequenza (applicati UNA volta), operazioni
##   rimandate a tutti, hash dello stato ogni 5 s per scoprire i desync (-> istantanea), riconnessione automatica.
##
## Il nodo è l'autoload `CoopNet` (project.godot); `CoopNetService.instance()` lo restituisce (nei test e negli
## strumenti senza autoload lo crea e lo aggiunge alla radice). La UI (FriendsPanel, CoopLobbyScreen, CoopGuildScreen)
## chiama solo i metodi pubblici qui sotto e ascolta i segnali. I bonus di gilda entrano nei modificatori con la fonte `guild:<progetto>` (regola 4) e restano
## attivi anche da soli/offline grazie alla copia in sola lettura nel salvataggio personale (sezione `coop_net`).
## Il fondo è A SOLO VERSAMENTO (regola 5): da qui non esiste alcun modo di riprendere o regalare qualcosa.

signal status_changed(status: String)
signal friends_changed()
signal guild_changed()
signal notice(key: String, params: Dictionary)

const ST_OFFLINE := "offline"
const ST_HOSTING := "hosting"
const ST_CONNECTING := "connecting"
const ST_CONNECTED := "connected"
const ST_SUSPENDED := "suspended"        # host perso: si riprova da soli, la gilda è in pausa
const SECTION := "coop_net"              # sezione del salvataggio personale (copia dei bonus, cassetta in uscita)
## Motivi di rifiuto che NON fanno riprovare la connessione.
const FATAL_REJECT: PackedStringArray = ["version", "password", "full", "kicked", "dup_uid", "bad_name"]

static var _instance: CoopNetService = null

var rules: Dictionary = {}
var net: Dictionary = {}
var transport: CoopEnetTransport = null
var limiter := CoopRateLimiter.new()
var store := CoopGuildStore.new()
var guild: CoopGuild = null
var status := ST_OFFLINE
var my_name := ""
var room_password := ""
var host_ip := ""
var host_port := 0
var ts_offset := 0                       # solo test: sposta l'orologio dell'host (giorni/settimane)
var sim_latency_ms := 0.0                # solo test: latenza/perdita simulate passate al trasporto
var sim_jitter_ms := 0.0
var sim_loss_pct := 0.0
var presence_provider: Callable          # -> Dictionary di presenza (predefinito: CoopPresence.local)
var hero_code_provider: Callable         # facoltativo (COOP-1): -> String codice-eroe
var current_screen := ""                 # aggiornato dalla UI (Tenuta/Mercato nella presenza)
var stats := {"desyncs": 0, "resyncs": 0, "rejected": 0, "kicked": 0, "ops": 0, "acks": 0, "refunds": 0}

# host
var _peer_uid: Dictionary = {}           # peer_id -> uid
var _peer_hello_t: Dictionary = {}       # peer_id -> istante di connessione (per il timeout del saluto)
var _presence: Dictionary = {}           # peer_id -> presenza (+ "_t", "uid")
var _codes: Dictionary = {}              # peer_id -> codice-eroe
var _dirty_save_at := -1.0
var _kicked: Dictionary = {}             # peer_id già espulsi (si conta una volta sola)
# client
var _roster: Array = []
var _roster_t := -1.0
var _welcomed := false
var _await_snap := false
var _snap_req_t := -100.0
var _hello_t := -100.0
var _last_host_msg := 0.0
var _ping_n := 0
var _ping_sent: Dictionary = {}
var rtt_ms := 0
var last_problem := ""                   # ultimo motivo per cui non si è collegati (per «Controlla connessione»)
var ever_connected := false              # in questa stanza l'host ha già risposto almeno una volta (altrimenti «nessuna risposta», non «host sparito»)
var _lost_notified := false              # l'avviso «host perso» esce una volta per episodio, non a ogni tentativo di riconnessione
var _reconnect_at := -1.0
var _reconnect_delay := 0.0
var _intentional_close := false
var _friend_codes: Dictionary = {}       # peer_id -> codice-eroe ricevuto
# comuni
var _t_presence := 0.0
var _t_ping := 0.0
var _t_hash := 0.0
var _t_roster := 0.0
var _crate_until := -1.0
var _fallback: Dictionary = {}           # sezione personale quando non c'è una partita (test, menù)


## Istanza unica, creata alla prima richiesta e aggiunta alla radice dell'albero.
static func instance() -> CoopNetService:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	var auto: Node = tree.root.get_node_or_null("/root/CoopNet") if tree != null else null
	if auto is CoopNetService:
		_instance = auto
		return _instance
	_instance = CoopNetService.new()
	_instance.name = "CoopNetService"
	if tree != null:
		tree.root.add_child.call_deferred(_instance)
	return _instance


static func has_instance() -> bool:
	return _instance != null and is_instance_valid(_instance)


func _ready() -> void:
	if _instance == null:
		_instance = self
	_load_rules()              # in _ready: da autoload, DataRegistry ha già letto i dati
	var tree := get_tree()
	var eb: Node = tree.root.get_node_or_null("/root/EventBus")
	if eb != null:
		eb.crate_opened.connect(_on_crate_opened)
		eb.game_stopped.connect(_on_game_stopped)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _load_rules() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var dr: Node = tree.root.get_node_or_null("/root/DataRegistry") if tree != null else null
	if dr != null and dr.has_method("rules"):
		rules = dr.rules("coop_net_rules")
	var missing := CoopGuild.missing_rule_keys(rules)
	if not missing.is_empty():
		# nessun numero di ripiego (regola 2): senza le regole dei dati il coop resta spento
		push_error("CoopNet: chiavi mancanti in coop_net_rules: %s" % ", ".join(missing))
		rules = {}
		return
	net = rules["net"]
	limiter.configure(net)


func default_port() -> int:
	return int(rules["default_port"])


# ================================================================== API per la UI

## Crea la stanza: questo PC fa da host. Riprende la gilda salvata (questa o `resume_id`) oppure ne fonda una nuova.
## Ritorna "" oppure un codice d'errore ("bad_name", "port", "no_rules").
func host_room(port: int, nick: String, guild_name: String = "", password: String = "", resume_id: String = "") -> String:
	if rules.is_empty():
		return "no_rules"
	var n := CoopProtocol.sanitize_name(nick, int(rules["name"]["max_len"]))
	if n.is_empty():
		return "bad_name"
	leave_room()
	last_problem = ""
	my_name = n
	_share_nick(n)
	room_password = password.left(32)
	var sec := _sec()
	sec["nick"] = n
	var gid := resume_id if not resume_id.is_empty() else str(sec.get("guild_id", ""))
	guild = null
	if CoopGuildStore.valid_id(gid):
		var res := store.load_guild(gid)
		if res.ok:
			guild = _new_guild()
			if not guild.from_dict(res.guild).is_empty():
				guild = null
	if guild == null:
		guild = _new_guild()
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var gname := CoopProtocol.sanitize_name(guild_name, 24)
		guild.create(CoopGuild.new_guild_id(rng), gname if not gname.is_empty() else n, my_uid(), n, _now_ts())
	elif not guild.is_member(my_uid()):
		var r := guild.apply({"k": "join", "uid": my_uid(), "name": n, "ts": _now_ts(), "seq0": int(sec.next_seq) - 1})
		if not r.ok:
			guild = null
			return "full" if r.err == "full" else "guild"
	transport = _make_transport()
	var err := transport.host(port, int(rules["max_members"]) - 1)
	if err != OK:
		transport = null
		_set_status(ST_OFFLINE)
		return "port"
	host_port = port
	# comandi di un'altra gilda: restituiti (con avviso); gli altri riallineati e applicati in ordine
	for c in (sec.outbox as Array).duplicate():
		if str(c.get("gid", "")) != guild.guild_id():
			_on_cmd_result(int(c.seq), false, "other_guild")
	_align_seq(int(guild.members()[my_uid()].seq))
	sec["guild_id"] = guild.guild_id()
	sec["guild_name"] = str(guild.state.name)
	_presence[CoopTransport.HOST_ID] = _local_presence()
	_set_status(ST_HOSTING)
	_after_guild_change()
	# comandi rimasti nella cassetta in uscita (fatti da client quando l'host era spento) per questa gilda
	for c in (sec.outbox as Array).duplicate():
		var r := _host_handle_cmd(my_uid(), int(c.seq), str(c.op), c.args)
		_on_cmd_result(int(c.seq), bool(r.ok) or r.err == "dup", str(r.err))
	_save_guild_now()
	return ""


## Entra nella stanza di un amico (IP:porta). Ritorna "" o un codice d'errore.
func join_room(ip: String, port: int, nick: String, password: String = "") -> String:
	if rules.is_empty():
		return "no_rules"
	var n := CoopProtocol.sanitize_name(nick, int(rules["name"]["max_len"]))
	if n.is_empty():
		return "bad_name"
	var clean_ip := ip.strip_edges()
	if clean_ip.is_empty() or clean_ip.length() > 64:
		return "bad_ip"
	leave_room()
	last_problem = ""
	ever_connected = false
	_lost_notified = false
	my_name = n
	_share_nick(n)
	room_password = password.left(32)
	host_ip = clean_ip
	host_port = port
	_sec()["nick"] = n
	# docs/24 §7.1 p.3: l'IP NON va nel salvataggio (finirebbe nello ZIP di «Segnala un problema»): solo nelle impostazioni locali.
	Settings.set_value("coop_last_host", {"ip": clean_ip, "port": port})
	# copia locale della gilda (se c'era): si gioca e si vede il fondo anche prima che l'host risponda
	_load_guild_copy()
	_reconnect_delay = float(net["reconnect_min_s"])
	return _connect_client()


## Esce dalla stanza (resta socio della gilda: i bonus restano con l'ultimo valore noto).
func leave_room() -> void:
	_intentional_close = true
	if transport != null:
		if transport.is_open():
			transport.send({"t": "bye"})
		transport.close()
	transport = null
	if is_host() and guild != null:
		_save_guild_now()
	elif guild != null:
		_save_guild_copy()
	_peer_uid.clear()
	_peer_hello_t.clear()
	_presence.clear()
	_codes.clear()
	_roster.clear()
	_friend_codes.clear()
	_welcomed = false
	_await_snap = false
	_reconnect_at = -1.0
	_intentional_close = false
	_set_status(ST_OFFLINE)
	friends_changed.emit()


## Lascia la gilda (i contributi restano alla gilda; il bonus personale si azzera). Se ci sono versamenti non ancora
## confermati dall'host serve `confirm_pending = true` (la UI lo chiede): partono PRIMA dell'uscita, nello stesso
## ordine, quindi vengono confermati (o restituiti se l'host li rifiuta). Nessuna perdita silenziosa.
func leave_guild(confirm_pending: bool = false) -> String:
	if guild == null or not guild.is_member(my_uid()):
		return "not_member"
	if pending_commands() > 0 and not confirm_pending:
		return "pending"
	var e := _command("leave", {})
	return e


func is_host() -> bool:
	return status == ST_HOSTING


## Chiave del testo di stato: «Host sparito» solo se l'host aveva già risposto, altrimenti «Nessuna risposta» (IP o porta sbagliati).
func status_key() -> String:
	if status == ST_SUSPENDED and not ever_connected:
		return "UI_COOPNET_ST_NOANSWER"
	return "UI_COOPNET_ST_" + status.to_upper()


func is_online() -> bool:
	return status == ST_HOSTING or status == ST_CONNECTED


func my_uid() -> String:
	var sec := _sec()
	var u := str(sec.get("uid", ""))
	if u.length() != 16:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		u = ""
		for i in 16:
			u += "0123456789abcdef"[rng.randi_range(0, 15)]
		sec["uid"] = u
	return u


func saved_nick() -> String:
	var n := str(_sec().get("nick", ""))
	return n if not n.is_empty() else _coop_name()


## Il nome dentro i codici-eroe (schermata Amici) e il soprannome della stanza sono la stessa persona: se ne hai scelto uno solo,
## l'altro lo riprende (playtest novizio 121: due campi nome diversi, i codici dicevano «Eroe» anche con soprannome «Alba»).
func _coop_name() -> String:
	var co := _coop()
	return str(co.state.get("name", "")) if co != null and co.state is Dictionary else ""


func _coop() -> Object:
	var game: Node = _node("Game")
	return game.system("coop") if game != null and _is_game_active() else null


func _share_nick(n: String) -> void:
	var co := _coop()
	if co != null and co.state is Dictionary and str(co.state.get("name", "")).is_empty() and co.has_method("set_my_name"):
		co.set_my_name(n)


## Ultimo host usato ({ip, port} o vuoto). Letto dalle impostazioni locali, mai dal salvataggio; valori ostili = vuoto.
func last_host() -> Dictionary:
	var v: Variant = Settings.get_value("coop_last_host")
	if v is Dictionary and v.get("ip") is String and not (v.get("ip") as String).is_empty() and (v.get("ip") as String).length() <= 64:
		var out := {"ip": v.ip}
		if v.get("port") is int or v.get("port") is float:
			out["port"] = int(v.port)
		return out
	return {}


## Amici visibili (escluso me): [{id, uid, name, cls, lvl, hl, act, sk, det, ping, age, state}] con
## state = "online" | "stale" | "offline".
func friends() -> Array:
	var out: Array = []
	var pr: Dictionary = rules["presence"]
	var stale := float(pr["stale_s"])
	var timeout := float(pr["timeout_s"])
	var list: Array = _host_roster_list() if is_host() else _roster
	var extra_age := 0.0 if is_host() else maxf(0.0, _now() - _roster_t)
	for e in list:
		if str(e.get("uid", "")) == my_uid():
			continue
		var f: Dictionary = e.duplicate()
		var age := float(e.get("age", 0)) + extra_age
		f["state"] = "online" if age < stale else ("stale" if age < timeout else "offline")
		if status == ST_SUSPENDED or status == ST_OFFLINE:
			f["state"] = "offline"
		f["code"] = str(_codes.get(int(e.id), "")) if is_host() else str(_friend_codes.get(int(e.id), ""))
		out.append(f)
	return out


func guild_state() -> Dictionary:
	return guild.state if guild != null else {}


## Versa oro ("gold") o una materia prima di base nel fondo comune. Gli oggetti escono SUBITO dal Deposito personale
## e partono verso l'host (o restano nella cassetta in uscita finché l'host non c'è). Se l'host rifiuta, si restituiscono.
func deposit(item: String, qty: int) -> String:
	if guild == null or not guild.is_member(my_uid()):
		return "not_member"
	if not guild.values.has(item):
		return "not_depositable"
	if qty < 1:
		return "bad_qty"
	var pts := qty * int(guild.values[item])
	if pts > guild.allowance(my_uid(), _now_ts()):
		return "cap"
	if (_sec().outbox as Array).size() >= int(net["max_outbox"]):
		return "outbox_full"
	var bank := _bank()
	if bank == null:
		return "no_game"
	if bank.has_method("is_def_locked") and bank.is_def_locked(item):
		return "locked"
	if not bank.remove(item, qty):
		return "not_enough"
	return _command("deposit", {"item": item, "qty": qty})


## Un tentativo contro il Boss della settimana: combattimento locale breve, poi il numero va all'host.
## Ritorna {"err": String, "pts": int, ...esito di CoopBossSim}.
func boss_attack() -> Dictionary:
	if guild == null or not guild.is_member(my_uid()):
		return {"err": "not_member"}
	var b: Dictionary = guild.state.get("boss", {})
	if b.is_empty() or bool(b.done):
		return {"err": "boss_done"}
	if guild.boss_attempts(my_uid(), _now_ts()) < 1:
		return {"err": "no_attempts"}
	var game: Node = _node("Game")
	var cb: Object = game.system("combat") if game != null and _is_game_active() else null
	if cb == null or str(_gs().data.get("hero", {}).get("class", "")).is_empty():
		return {"err": "no_hero"}
	var sec := _sec()
	var n := int(sec.get("boss_att_no", 0)) + 1
	sec["boss_att_no"] = n
	var res := CoopBossSim.attempt(cb.hero_stats(), int(cb.hero_level()), rules["boss"],
		CoopBossSim.seed_for(int(b.week), my_uid(), n))
	var e := _command("boss_hit", {"week": int(b.week), "pts": int(res.pts), "att": n})
	res["err"] = e
	return res


## Contributo «a numero» (usato dai test di rete e da COOP-1 per un fantasma già simulato).
func boss_contribute(pts: int) -> String:
	if guild == null or not guild.is_member(my_uid()):
		return "not_member"
	var b: Dictionary = guild.state.get("boss", {})
	if b.is_empty():
		return "no_boss"
	var n := int(_sec().get("boss_att_no", 0)) + 1
	_sec()["boss_att_no"] = n
	return _command("boss_hit", {"week": int(b.week), "pts": pts, "att": n})


func propose(project_id: String) -> String:
	return _command("propose", {"project": project_id})


func vote(yes: bool) -> String:
	return _command("vote", {"yes": yes})


func decide() -> String:
	return _command("decide", {})


func kick(uid: String) -> String:
	return _command("kick", {"uid": uid})


func pending_commands() -> int:
	return (_sec().get("outbox", []) as Array).size()


## Bonus di gilda attivi per questo giocatore (copia in sola lettura): fonte -> blocco.
func active_bonus() -> Dictionary:
	var sys := _bonus_sys()
	return sys.bonus_by_source() if sys != null else {}


# ================================================================== ciclo

func _process(_delta: float) -> void:
	var now := _now()
	if transport != null:
		var trp := transport          # riferimento locale: un gestore può chiudere il trasporto durante poll()
		trp.poll(now)
	if _dirty_save_at >= 0.0 and now >= _dirty_save_at:
		_save_guild_now()
	if transport == null:
		if status == ST_SUSPENDED and _reconnect_at >= 0.0 and now >= _reconnect_at:
			_reconnect_at = -1.0
			_connect_client()
		return
	var pr: Dictionary = rules["presence"]
	if is_host():
		_host_tick(now, pr)
	elif status == ST_CONNECTED or status == ST_CONNECTING:
		_client_tick(now, pr)


func _host_tick(now: float, pr: Dictionary) -> void:
	if now >= _t_presence:
		_t_presence = now + float(pr["interval_s"])
		var p := _local_presence()
		p["_t"] = now
		p["uid"] = my_uid()
		_presence[CoopTransport.HOST_ID] = p
	if now >= _t_roster:
		_t_roster = now + float(pr["interval_s"])
		_broadcast({"t": "roster", "list": _host_roster_list()})
		friends_changed.emit()
	if now >= _t_hash and guild != null:
		_t_hash = now + float(net["hash_interval_s"])
		_broadcast({"t": "hash", "gseq": guild.gseq(), "h": guild.state_hash()})
		# cambio di settimana: nuovo Boss anche se nessuno fa nulla
		if guild.week_of(_now_ts()) != int(guild.state.get("boss", {}).get("week", -1)):
			_host_apply_and_broadcast({"k": "time", "ts": _now_ts()})
	var hello_to := float(net["hello_timeout_s"])
	for pid in _peer_hello_t.keys():
		if not _peer_uid.has(pid) and now - float(_peer_hello_t[pid]) > hello_to:
			_peer_hello_t.erase(pid)
			transport.kick(pid)


func _client_tick(now: float, pr: Dictionary) -> void:
	if transport.status() != CoopTransport.ST_CONNECTED:
		return
	# l'host tace da troppo: lo si considera perso (cavo staccato, PC in sospensione)
	if now - _last_host_msg > float(pr["timeout_s"]):
		_on_host_lost()
		return
	var resend := float(net["resend_s"])
	if not _welcomed:
		if now - _hello_t > resend:
			_send_hello()             # il saluto (o la risposta) può essersi perso: si ripete
		return
	if now >= _t_presence:
		_t_presence = now + float(pr["interval_s"])
		var p := _local_presence()
		transport.send(p, false)
	if now >= _t_ping:
		_t_ping = now + float(net["ping_interval_s"])
		_ping_n += 1
		_ping_sent[_ping_n] = now
		if _ping_sent.size() > 16:
			_ping_sent.erase(_ping_sent.keys().min())
		transport.send({"t": "ping", "n": _ping_n})
	if _await_snap and now - _snap_req_t > resend:
		_request_snap()
	var ob: Array = _sec().outbox
	if not _await_snap and not ob.is_empty() and now - float(ob[0].get("_sent", -100.0)) > resend:
		# si rimandano TUTTI i comandi non confermati, in ordine: l'host li applica solo in sequenza
		for c in ob:
			c["_sent"] = now
			transport.send({"t": "cmd", "seq": int(c.seq), "op": str(c.op), "args": c.args})


# ================================================================== host: messaggi

func _on_received(peer_id: int, msg: Dictionary) -> void:
	if is_host():
		_host_on_msg(peer_id, msg)
	else:
		_client_on_msg(msg)


func _host_on_msg(pid: int, m: Dictionary) -> void:
	var t := str(m.t)
	if t == "hello":
		_host_on_hello(pid, m)
		return
	if not _peer_uid.has(pid):
		_strike(pid, "no_hello")
		return
	var uid := str(_peer_uid[pid])
	match t:
		"presence":
			m["_t"] = _now()
			m["uid"] = uid
			if guild != null and guild.members().has(uid):
				m["name"] = str(guild.members()[uid].name)      # niente nomi falsi: vale quello del socio
			_presence[pid] = m
		"ping":
			transport.send_to(pid, {"t": "pong", "n": int(m.n)})
		"cmd":
			var r := _host_handle_cmd(uid, int(m.seq), str(m.op), m.args)
			var ok: bool = bool(r.ok) or str(r.err) == "dup"
			transport.send_to(pid, {"t": "ack", "seq": int(m.seq), "ok": ok, "err": "" if ok else str(r.err)})
		"snap_req":
			_send_snap(pid)
		"code":
			_codes[pid] = str(m.code)
			_broadcast({"t": "code", "id": pid, "code": str(m.code)})
		"bye":
			transport.kick(pid)


func _host_on_hello(pid: int, m: Dictionary) -> void:
	if int(m.v) != CoopProtocol.VERSION:
		_reject(pid, "version")
		return
	if not room_password.is_empty() and str(m.pw) != room_password:
		_reject(pid, "password")
		return
	var uid := str(m.uid)
	if uid == my_uid():
		_reject(pid, "dup_uid")
		return
	for other in _peer_uid:
		if other != pid and str(_peer_uid[other]) == uid:
			_reject(pid, "dup_uid")
			return
	if not guild.is_member(uid):
		var r := _host_apply_and_broadcast({"k": "join", "uid": uid, "name": str(m.name), "ts": _now_ts(), "seq0": int(m.seq)})
		if not r.ok:
			_reject(pid, "full" if r.err == "full" else "bad_name")
			return
	_peer_uid[pid] = uid
	_peer_hello_t.erase(pid)
	_presence[pid] = {"t": "presence", "name": str(m.name), "cls": "", "lvl": 0, "hl": 0, "act": "menu", "sk": "",
		"det": "", "ping": 0, "_t": _now(), "uid": uid}
	var member: Dictionary = guild.members()[uid]
	transport.send_to(pid, {"t": "welcome", "v": CoopProtocol.VERSION, "you": pid, "gseq": guild.gseq(),
		"guild": guild.guild_id(), "seq": int(member.seq)})
	_send_snap(pid)
	for other in _codes:
		transport.send_to(pid, {"t": "code", "id": int(other), "code": str(_codes[other])})
	var my_code := _my_code()
	if not my_code.is_empty():
		transport.send_to(pid, {"t": "code", "id": CoopTransport.HOST_ID, "code": my_code})
	notice.emit("UI_COOPNET_NOTE_JOINED", {"name": str(m.name)})
	_t_roster = 0.0


## Applica il comando di un socio (host). Ritorna {"ok", "err"}; "dup" = già applicato (idempotenza).
func _host_handle_cmd(uid: String, seq: int, opname: String, args: Dictionary) -> Dictionary:
	var op := {"k": opname, "uid": uid, "seq": seq, "ts": _now_ts()}
	match opname:
		"deposit":
			op["item"] = str(args.get("item", ""))
			op["qty"] = int(args.get("qty", 0))
		"boss_hit":
			op["week"] = int(args.get("week", -1))
			op["pts"] = int(args.get("pts", -1))
		"propose":
			op["project"] = str(args.get("project", ""))
		"vote":
			op["yes"] = args.get("yes", null)
		"kick":
			op["target"] = str(args.get("uid", ""))
		"leave", "decide":
			pass
		_:
			return {"ok": false, "err": "bad_op"}
	var r := _host_apply_and_broadcast(op)
	if not r.ok and r.err != "dup" and r.err != "gap":
		# rifiutato: il numero di sequenza si consuma comunque (operazione «skip» uguale per tutti), altrimenti
		# i comandi successivi resterebbero in attesa per sempre
		_host_apply_and_broadcast({"k": "skip", "uid": uid, "seq": seq, "ts": int(op.ts)})
	if r.ok and opname == "kick":
		for pid in _peer_uid.keys():
			if str(_peer_uid[pid]) == str(op.target):
				_reject(pid, "kicked", int(guild.members()[str(op.target)].seq))
				stats.kicked += 1
	return r


func _host_apply_and_broadcast(op: Dictionary) -> Dictionary:
	var r := guild.apply(op)
	if not r.ok:
		return r
	stats.ops += 1
	if transport != null:
		_broadcast({"t": "op", "gseq": guild.gseq(), "op": op})
	_after_guild_change()
	# salvataggio della gilda prima che l'operazione parta (il trasporto spedisce al prossimo poll): se l'host cade,
	# nessun socio ha in mano un'operazione che il file dell'host non contiene
	if float(net["save_debounce_s"]) <= 0.0:
		_save_guild_now()
	elif _dirty_save_at < 0.0:
		_dirty_save_at = _now() + float(net["save_debounce_s"])
	return r


## Host -> soli soci AUTENTICATI (saluto accettato): chi non ha la parola d'ordine o la versione giusta non vede
## né il roster né le operazioni della gilda.
func _broadcast(msg: Dictionary) -> void:
	for pid in _peer_uid:
		transport.send_to(int(pid), msg)


func _send_snap(pid: int) -> void:
	var bytes := SaveCodec.encode(guild.to_dict())
	transport.send_to(pid, {"t": "snap", "gseq": guild.gseq(), "data": Marshalls.raw_to_base64(bytes)})


## `seq` = ultimo comando applicato di quel socio (per l'espulsione: il client restituisce i versamenti successivi).
func _reject(pid: int, reason: String, seq: int = 0) -> void:
	transport.send_to(pid, {"t": "reject", "reason": reason, "seq": seq})
	transport.kick(pid)


func _strike(pid: int, reason: String) -> void:
	stats.rejected += 1
	limiter.strike(pid)
	if is_host() and limiter.should_kick(pid) and not _kicked.has(pid):
		_kicked[pid] = true
		stats.kicked += 1
		transport.kick(pid)
	if OS.is_debug_build():
		print_verbose("CoopNet: messaggio rifiutato da %d (%s)" % [pid, reason])


func _host_roster_list() -> Array:
	var out: Array = []
	var now := _now()
	for pid in _presence:
		var p: Dictionary = _presence[pid]
		if pid != CoopTransport.HOST_ID and not _peer_uid.has(pid):
			continue
		out.append({"id": int(pid), "uid": str(p.get("uid", my_uid())), "name": str(p.get("name", "")),
			"cls": str(p.get("cls", "")), "lvl": int(p.get("lvl", 0)), "hl": int(p.get("hl", 0)),
			"act": str(p.get("act", "menu")), "sk": str(p.get("sk", "")), "det": str(p.get("det", "")),
			"ping": int(p.get("ping", 0)), "age": clampi(int(now - float(p.get("_t", now))), 0, 86400)})
		if out.size() >= int(rules["max_members"]) + 1:
			break
	return out


func _on_peer_joined(pid: int) -> void:
	if is_host():
		_peer_hello_t[pid] = _now()


func _on_peer_left(pid: int) -> void:
	if is_host():
		var had := _peer_uid.has(pid)
		var nm := str(_presence.get(pid, {}).get("name", ""))
		_peer_uid.erase(pid)
		_peer_hello_t.erase(pid)
		_presence.erase(pid)
		_codes.erase(pid)
		_kicked.erase(pid)
		if had:
			notice.emit("UI_COOPNET_NOTE_LEFT", {"name": nm})
		friends_changed.emit()
	elif pid == CoopTransport.HOST_ID and not _intentional_close:
		_on_host_lost()


func _on_rejected(pid: int, reason: String) -> void:
	_strike(pid, reason)


# ================================================================== client: messaggi

func _client_on_msg(m: Dictionary) -> void:
	_last_host_msg = _now()
	match str(m.t):
		"welcome":
			_on_welcome(m)
		"reject":
			_on_reject(str(m.reason), int(m.seq))
		"roster":
			_roster = m.list
			_roster_t = _now()
			friends_changed.emit()
		"pong":
			var n := int(m.n)
			if _ping_sent.has(n):
				rtt_ms = clampi(int((_now() - float(_ping_sent[n])) * 1000.0), 0, 60000)
				_ping_sent.erase(n)
		"ping":
			transport.send({"t": "pong", "n": int(m.n)})
		"ack":
			stats.acks += 1
			_on_cmd_result(int(m.seq), bool(m.ok), str(m.err))
		"op":
			_on_op(int(m.gseq), m.op)
		"hash":
			_on_hash(int(m.gseq), str(m.h))
		"snap":
			_on_snap(int(m.gseq), str(m.data))
		"code":
			_friend_codes[int(m.id)] = str(m.code)
			friends_changed.emit()


func _on_welcome(m: Dictionary) -> void:
	_welcomed = true
	ever_connected = true
	_lost_notified = false
	last_problem = ""
	var sec := _sec()
	var gid := str(m.guild)
	if str(sec.get("guild_id", "")) != gid:
		# altra gilda: i comandi rimasti erano per la vecchia, si annullano (versamenti restituiti)
		guild = null
		sec["guild_id"] = gid
	for c in (sec.outbox as Array).duplicate():
		if str(c.get("gid", "")) != gid:
			_on_cmd_result(int(c.seq), false, "other_guild")
	if guild != null and guild.guild_id() != gid:
		guild = null
	_align_seq(int(m.seq))
	_reconnect_delay = float(net["reconnect_min_s"])
	_await_snap = true
	_snap_req_t = _now()
	var code := _my_code()
	if not code.is_empty():
		transport.send({"t": "code", "id": 0, "code": code})
	_set_status(ST_CONNECTED)


## Comandi già applicati dall'host (seq <= host_seq, conferma persa): tolti senza rimandarli. Gli altri non sono mai
## stati applicati: si rinumerano di seguito a host_seq (l'host li accetta solo in sequenza).
func _align_seq(host_seq: int) -> void:
	var sec := _sec()
	var keep: Array = []
	var next := host_seq + 1
	for c in sec.outbox:
		if int(c.seq) > host_seq:
			c["seq"] = next
			c["_sent"] = -100.0
			next += 1
			keep.append(c)
	sec["outbox"] = keep
	sec["next_seq"] = next


func _on_reject(reason: String, host_seq: int) -> void:
	last_problem = reason
	notice.emit("UI_COOPNET_REJECT_" + reason.to_upper(), {})
	if reason == "kicked":
		_drop_membership(host_seq)
	if FATAL_REJECT.has(reason):
		_intentional_close = true
		if transport != null:
			transport.close()
		transport = null
		_intentional_close = false
		_set_status(ST_OFFLINE)
	else:
		_on_host_lost()


func _on_op(gseq: int, op: Dictionary) -> void:
	if guild == null or _await_snap:
		return
	var mine := guild.gseq()
	if gseq <= mine:
		return
	if gseq != mine + 1:
		_request_snap()          # buco: un'operazione è andata persa
		return
	var r := guild.apply(op)
	if not r.ok or guild.gseq() != gseq:
		stats.desyncs += 1
		_request_snap()
		return
	stats.ops += 1
	_after_guild_change()


func _on_hash(gseq: int, h: String) -> void:
	if guild == null or _await_snap:
		return
	if gseq == guild.gseq():
		if guild.state_hash() != h:
			stats.desyncs += 1
			notice.emit("UI_COOPNET_NOTE_DESYNC", {})
			_request_snap()
	elif gseq > guild.gseq():
		_request_snap()


func _on_snap(gseq: int, data: String) -> void:
	var dec := SaveCodec.decode(Marshalls.base64_to_raw(data))
	if not dec.ok:
		_request_snap()
		return
	var g := _new_guild()
	if not g.from_dict(dec.data).is_empty() or g.gseq() != gseq:
		_request_snap()
		return
	guild = g
	stats.resyncs += 1
	_await_snap = false
	for c in _sec().outbox:
		c["_sent"] = -100.0
	if not guild.is_member(my_uid()):
		var m: Dictionary = guild.members().get(my_uid(), {})
		_drop_membership(int(m.seq) if m.has("seq") else -1)
	_after_guild_change()
	_save_guild_copy()


func _request_snap() -> void:
	_await_snap = true
	_snap_req_t = _now()
	if transport != null and transport.is_open():
		transport.send({"t": "snap_req"})


## Esito di un comando (ack dell'host, o applicazione locale sull'host).
func _on_cmd_result(seq: int, ok: bool, err: String) -> void:
	var sec := _sec()
	if not ok and err == "gap":
		# l'host aspetta un comando precedente (perso in rete): nessun rimborso; il prossimo reinvio periodico
		# rimanda TUTTI i comandi in ordine (rimandarli subito a ogni «gap» moltiplicherebbe i pacchetti)
		return
	var keep: Array = []
	var leave_seq := -1
	for c in sec.outbox:
		if int(c.seq) != seq:
			keep.append(c)
			continue
		if not ok:
			_refund(c, err)
		elif str(c.op) == "leave":
			leave_seq = seq
	sec["outbox"] = keep
	if leave_seq >= 0:
		_drop_membership(leave_seq)
	guild_changed.emit()


func _refund(c: Dictionary, err: String) -> void:
	if str(c.op) == "deposit":
		var bank := _bank()
		if bank != null:
			bank.add(str(c.args.item), int(c.args.qty), "coop_refund")
			stats.refunds += 1
	notice.emit("UI_COOPNET_ERR_" + err.to_upper(), {})


func _on_host_lost() -> void:
	if status == ST_OFFLINE or is_host() or (status == ST_SUSPENDED and transport == null):
		return
	if OS.is_debug_build() or OS.has_feature("headless"):
		print_verbose("CoopNet: host perso (ultimo messaggio %.1f s fa)" % (_now() - _last_host_msg))
	if last_problem.is_empty():
		last_problem = "host_lost"
	_intentional_close = true
	if transport != null:
		transport.close()
	transport = null
	_intentional_close = false
	_welcomed = false
	_await_snap = false
	if guild != null:
		_save_guild_copy()
	_set_status(ST_SUSPENDED)
	if not _lost_notified:       # playtest novizio 121: prima l'avviso rientrava a ogni tentativo e diceva «host sparito» anche se non aveva mai risposto
		_lost_notified = true
		notice.emit("UI_COOPNET_NOTE_HOST_LOST" if ever_connected else "UI_COOPNET_NOTE_NO_ANSWER", {})
	friends_changed.emit()
	var mx := float(net["reconnect_max_s"])
	_reconnect_delay = clampf(_reconnect_delay * 2.0 if _reconnect_delay > 0.0 else float(net["reconnect_min_s"]),
		float(net["reconnect_min_s"]), mx)
	_reconnect_at = _now() + _reconnect_delay


# ================================================================== comandi (comuni)

func _command(op: String, args: Dictionary) -> String:
	if guild == null:
		return "no_guild"
	var sec := _sec()
	var seq := int(sec.get("next_seq", 1))
	sec["next_seq"] = seq + 1
	if is_host():
		var r := _host_handle_cmd(my_uid(), seq, op, args)
		var ok: bool = bool(r.ok) or str(r.err) == "dup"
		sec.outbox.append({"seq": seq, "op": op, "args": args, "gid": guild.guild_id()})
		_on_cmd_result(seq, ok, str(r.err))
		return "" if ok else str(r.err)
	sec.outbox.append({"seq": seq, "op": op, "args": args, "gid": guild.guild_id(), "_sent": -100.0})
	if status == ST_CONNECTED and _welcomed and not _await_snap:
		sec.outbox[-1]["_sent"] = _now()
		transport.send({"t": "cmd", "seq": seq, "op": op, "args": args})
	guild_changed.emit()
	return ""


# ================================================================== gilda, bonus, salvataggi

func _after_guild_change() -> void:
	if guild == null:
		return
	if guild.is_member(my_uid()):
		var sys := _bonus_sys()
		if sys != null:
			sys.set_membership(guild.guild_id(), str(guild.state.name), guild.state.projects)
		else:
			var sec := _sec()
			sec["guild_id"] = guild.guild_id()
			sec["guild_name"] = str(guild.state.name)
			sec["levels"] = (guild.state.projects as Dictionary).duplicate()
	if not is_host():
		_dirty_save_at = _now() + float(net["copy_save_debounce_s"])
	guild_changed.emit()


## Fuori dalla gilda. `host_seq` = ultimo comando di questo socio applicato dall'host (-1 = sconosciuto):
## i comandi successivi non arriveranno mai, quindi i versamenti si RESTITUISCONO (con avviso, mai in silenzio).
func _drop_membership(host_seq: int = -1) -> void:
	var sec := _sec()
	if host_seq >= 0:
		for c in (sec.outbox as Array).duplicate():
			if int(c.seq) > host_seq:
				_on_cmd_result(int(c.seq), false, "not_member")
			else:
				_on_cmd_result(int(c.seq), true, "")
	var sys := _bonus_sys()
	if sys != null:
		sys.clear_membership()
	else:
		sec["levels"] = {}
		sec["guild_id"] = ""
		sec["guild_name"] = ""
	guild_changed.emit()


func _bonus_sys() -> CoopBonusSystem:
	var game: Node = _node("Game")
	if game == null or not _is_game_active():
		return null
	return game.system("coop_net") as CoopBonusSystem


func _save_guild_now() -> void:
	_dirty_save_at = -1.0
	if guild != null:
		store.save(guild, "host" if is_host() else "copy")


func _save_guild_copy() -> void:
	if guild != null:
		store.save(guild, "copy")


func _load_guild_copy() -> void:
	var gid := str(_sec().get("guild_id", ""))
	guild = null
	if not CoopGuildStore.valid_id(gid):
		return
	var res := store.load_guild(gid)
	if res.ok:
		var g := _new_guild()
		if g.from_dict(res.guild).is_empty():
			guild = g
			guild_changed.emit()


func _new_guild() -> CoopGuild:
	var dr: Node = _node("DataRegistry")
	return CoopGuild.make(rules, CoopGuild.item_values_from(dr, rules) if dr != null else {})


# ================================================================== aiuti

func _connect_client() -> String:
	transport = _make_transport()
	var err := transport.join(host_ip, host_port)
	if err != OK:
		transport = null
		last_problem = "connect"
		_set_status(ST_SUSPENDED)
		_reconnect_at = _now() + maxf(1.0, _reconnect_delay)
		return "connect"
	_welcomed = false
	_last_host_msg = _now()
	_set_status(ST_CONNECTING)
	return ""


func _send_hello() -> void:
	_hello_t = _now()
	_last_host_msg = maxf(_last_host_msg, _now() - 1.0)
	transport.send({"t": "hello", "v": CoopProtocol.VERSION, "name": my_name, "uid": my_uid(),
		"guild": str(_sec().get("guild_id", "")), "pw": room_password, "seq": maxi(0, int(_sec().get("next_seq", 1)) - 1)})


func _make_transport() -> CoopEnetTransport:
	var t := CoopEnetTransport.new(net)
	t.limiter = limiter
	t.sim_latency_ms = sim_latency_ms
	t.sim_jitter_ms = sim_jitter_ms
	t.sim_loss_pct = sim_loss_pct
	t.received.connect(_on_received)
	t.rejected.connect(_on_rejected)
	t.peer_joined.connect(_on_peer_joined)
	t.peer_left.connect(_on_peer_left)
	t.status_changed.connect(_on_transport_status)
	return t


func _on_transport_status(s: String) -> void:
	if is_host():
		return
	if s == CoopTransport.ST_CONNECTED and status == ST_CONNECTING:
		_last_host_msg = _now()
		_send_hello()
	elif (s == CoopTransport.ST_FAILED or s == CoopTransport.ST_CLOSED) and not _intentional_close:
		_on_host_lost()


func _local_presence() -> Dictionary:
	var crate := _now() < _crate_until
	if presence_provider.is_valid():
		var p: Dictionary = presence_provider.call()
		p["t"] = "presence"
		p["name"] = my_name
		p["ping"] = rtt_ms
		return p
	return CoopPresence.local(my_name, current_screen, crate, rtt_ms)


func _my_code() -> String:
	if hero_code_provider.is_valid():
		var c := str(hero_code_provider.call())
		if c.length() <= int(net["max_code_len"]):
			return c
	return ""


func _set_status(s: String) -> void:
	if s == status:
		return
	status = s
	status_changed.emit(s)


func _on_game_stopped() -> void:
	# la partita personale si chiude: la stanza resta solo se si è host senza partita (non succede dalla UI)
	if not is_host():
		leave_room()


func _on_crate_opened(_result: Dictionary) -> void:
	_crate_until = _now() + float(rules["presence"]["crate_show_s"])


## Sezione personale nel salvataggio (GameState.data.coop_net) o, senza partita, una copia in memoria.
func _sec() -> Dictionary:
	var target: Dictionary = _fallback
	var sys := _bonus_sys()
	if sys != null and sys.state is Dictionary:
		target = sys.state
	for k in ["uid", "nick", "guild_id", "guild_name"]:
		if not target.has(k):
			target[k] = ""
	if not (target.get("levels") is Dictionary):
		target["levels"] = {}
	if not (target.get("outbox") is Array):
		target["outbox"] = []
	if not target.has("next_seq"):
		target["next_seq"] = 1
	target.erase("last_host")      # docs/24 §7.1 p.3: salvataggi vecchi che contenevano l'IP dell'ultimo host
	return target


func _gs() -> Node:
	return _node("GameState")


func _bank() -> Object:
	var game: Node = _node("Game")
	return game.system("bank") if game != null and _is_game_active() else null


func _is_game_active() -> bool:
	var gs := _gs()
	return gs != null and bool(gs.active)


func _node(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("/root/" + n) if tree != null else null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _now_ts() -> int:
	return int(Time.get_unix_time_from_system()) + ts_offset
