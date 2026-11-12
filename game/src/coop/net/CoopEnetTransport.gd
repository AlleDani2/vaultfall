class_name CoopEnetTransport
extends CoopTransport
## Trasporto coop su ENet (UDP affidabile e ordinato, `ENetMultiplayerPeer` di Godot): LAN, Hamachi, ZeroTier,
## Tailscale, Radmin VPN o IP diretto con porta aperta. L'host ascolta su tutte le interfacce.
## Due canali: 0 = affidabile e ordinato (comandi, operazioni, istantanee), 1 = inaffidabile (presenza).
## Ogni pacchetto in arrivo passa: limite di frequenza (solo sull'host) -> dimensione -> JSON -> schema
## (CoopProtocol.decode). Solo i messaggi validi escono da `received`; gli altri da `rejected(peer_id, motivo)`.
##
## Per i test (partite headless sulla stessa macchina) si possono simulare latenza, variazione e PERDITA dei pacchetti
## in uscita (`sim_latency_ms`, `sim_jitter_ms`, `sim_loss_pct`): la perdita colpisce anche i messaggi «affidabili»,
## così si provano i reinvii, le richieste di istantanea e l'idempotenza dei comandi.

signal rejected(peer_id: int, reason: String)

const CH_RELIABLE := 0
const CH_PRESENCE := 1

var net: Dictionary = {}
var limiter: CoopRateLimiter = null
var sim_latency_ms := 0.0
var sim_jitter_ms := 0.0
var sim_loss_pct := 0.0
var dropped := 0                  # pacchetti scartati dalla perdita simulata
var sent := 0

var _peer: ENetMultiplayerPeer = null
var _role := Role.NONE
var _status := ST_CLOSED
var _out: Array = []              # [consegna_s, destinatario, canale, byte]
var _last_reliable_at := 0.0
var _rng := RandomNumberGenerator.new()
var _now := 0.0
var _peers: Dictionary = {}
var _events: Array = []           # [tipo, id]: i segnali di ENet arrivano DENTRO poll(); si rimandano a dopo


func _init(p_net: Dictionary = {}) -> void:
	net = p_net
	_rng.seed = Time.get_ticks_usec()


func host(port: int, max_clients: int, bind_ip: String = "*") -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_ip)
	var err := _peer.create_server(port, maxi(1, max_clients), 2)
	if err != OK:
		_peer = null
		_set_status(ST_FAILED)
		return err
	_role = Role.HOST
	_connect_signals()
	_set_status(ST_LISTENING)
	return OK


func join(ip: String, port: int) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port, 2)
	if err != OK:
		_peer = null
		_set_status(ST_FAILED)
		return err
	_role = Role.CLIENT
	_connect_signals()
	_set_status(ST_CONNECTING)
	return OK


func _connect_signals() -> void:
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)


func role() -> int:
	return _role


func status() -> String:
	return _status


func local_id() -> int:
	return _peer.get_unique_id() if _peer != null else 0


func peers() -> Array:
	return _peers.keys()


## Client -> host, oppure host -> tutti. `reliable = false` usa il canale inaffidabile (presenza).
func send(msg: Dictionary, reliable: bool = true) -> void:
	_queue(0 if _role == Role.HOST else HOST_ID, CoopProtocol.encode(msg), reliable)


func send_to(peer_id: int, msg: Dictionary, reliable: bool = true) -> void:
	_queue(peer_id, CoopProtocol.encode(msg), reliable)


## Solo per i test di robustezza: manda byte grezzi (malformati, enormi...) senza passare dal protocollo.
func send_raw(bytes: PackedByteArray, peer_id: int = -1) -> void:
	_queue(peer_id if peer_id >= 0 else (0 if _role == Role.HOST else HOST_ID), bytes, true)


func kick(peer_id: int) -> void:
	if _peer != null and _role == Role.HOST and _peers.has(peer_id):
		_flush(true)
		# «più tardi»: ENet consegna prima i pacchetti in coda (es. il messaggio di rifiuto), poi scollega
		var pp := _peer.get_peer(peer_id)
		if pp != null:
			pp.peer_disconnect_later()
		else:
			_peer.disconnect_peer(peer_id)


func close() -> void:
	if _peer != null:
		_flush(true)
		_peer.close()
	_peer = null
	_out.clear()
	_events.clear()
	_peers.clear()
	_role = Role.NONE
	if _status != ST_CLOSED:
		_set_status(ST_CLOSED)


func poll(now_s: float) -> void:
	_now = now_s
	if _peer == null:
		return
	_peer.poll()
	# connessioni/disconnessioni avvenute durante poll(): ora che ENet ha finito si possono avvisare gli ascoltatori
	# (che potrebbero anche chiudere il trasporto: farlo dentro poll() fa cadere il motore)
	var evs := _events
	_events = []
	for e in evs:
		if _peer == null:
			return
		_dispatch_event(str(e[0]), int(e[1]))
	if _peer == null:
		return
	_flush(false)
	while _peer != null and _peer.get_available_packet_count() > 0:
		var pid := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		_on_packet(pid, bytes)
	if _peer != null and _role == Role.CLIENT:
		var cs := _peer.get_connection_status()
		if cs == MultiplayerPeer.CONNECTION_DISCONNECTED and (_status == ST_CONNECTING or _status == ST_CONNECTED):
			var was := _status
			_peers.clear()
			_peer.close()                 # niente più poll() su un collegamento morto (riempirebbe il registro)
			_peer = null
			_role = Role.NONE
			_set_status(ST_FAILED if was == ST_CONNECTING else ST_CLOSED)
			if was == ST_CONNECTED:
				peer_left.emit(HOST_ID)


# ------------------------------------------------------------------ interno

func _queue(target: int, bytes: PackedByteArray, reliable: bool) -> void:
	if _peer == null:
		return
	if sim_loss_pct > 0.0 and _rng.randf() * 100.0 < sim_loss_pct:
		dropped += 1
		return
	var at := _now
	if sim_latency_ms > 0.0 or sim_jitter_ms > 0.0:
		at += maxf(0.0, sim_latency_ms + _rng.randf_range(-sim_jitter_ms, sim_jitter_ms)) / 1000.0
	if reliable:
		at = maxf(at, _last_reliable_at)      # il canale affidabile resta ordinato anche con la variazione simulata
		_last_reliable_at = at
	_out.append([at, target, CH_RELIABLE if reliable else CH_PRESENCE, bytes])


func _flush(all: bool) -> void:
	if _peer == null or _out.is_empty():
		return
	var cs := _peer.get_connection_status()
	if cs != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var keep: Array = []
	for item in _out:
		if not all and float(item[0]) > _now:
			keep.append(item)
			continue
		var target := int(item[1])
		if target > 1 and not _peers.has(target):
			continue
		_peer.set_target_peer(target)
		_peer.transfer_channel = int(item[2])
		_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if int(item[2]) == CH_RELIABLE \
			else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		_peer.put_packet(item[3])
		sent += 1
	_out = keep


func _on_packet(pid: int, bytes: PackedByteArray) -> void:
	if _role == Role.HOST and limiter != null and not limiter.allow(pid, _now):
		rejected.emit(pid, "rate")
		return
	var dec := CoopProtocol.decode(bytes, net, _role == Role.CLIENT)
	if not dec.ok:
		rejected.emit(pid, str(dec.err))
		return
	received.emit(pid, dec.msg)


func _on_peer_connected(id: int) -> void:
	_events.append(["in", id])


func _on_peer_disconnected(id: int) -> void:
	_events.append(["out", id])


func _dispatch_event(kind: String, id: int) -> void:
	if kind == "in":
		_peer_in(id)
	else:
		_peer_out(id)


func _peer_in(id: int) -> void:
	_peers[id] = true
	if _role == Role.CLIENT and id == HOST_ID:
		_set_status(ST_CONNECTED)
	peer_joined.emit(id)


func _peer_out(id: int) -> void:
	_peers.erase(id)
	if limiter != null:
		limiter.forget(id)
	if _role == Role.CLIENT and id == HOST_ID:
		# l'host ci ha scollegati: il collegamento è finito, niente più poll() su di lui
		if _peer != null:
			_peer.close()
		_peer = null
		_role = Role.NONE
		_set_status(ST_CLOSED)
	peer_left.emit(id)


func _set_status(s: String) -> void:
	if s == _status:
		return
	_status = s
	status_changed.emit(s)
