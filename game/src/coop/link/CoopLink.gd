class_name CoopLink
extends RefCounted
## Interfaccia ASTRATTA del trasporto coop (COOP-1, predisposizione per la fase 2 dello studio: Gilda di amici).
## Un trasporto sposta messaggi (CoopLinkMessage) tra un HOST e dei CLIENT; non sa nulla del gioco. Implementazioni:
##   LocalFileLink  cartella condivisa (prove, due istanze sullo stesso PC o cartella di rete): presente
##   (futuro) EnetTransport (LAN/VPN) e SteamTransport: NON in questa fase
## Regole: nessun `await` (si interroga con poll()), nessun tempo reale, solo messaggi già validi.

signal message_received(msg: Dictionary)

enum Role { HOST, CLIENT }

var role: int = Role.CLIENT
var session_id: String = ""
var local_id: String = ""
var _seq: int = 0


## Apre il trasporto. `p_session` = nome della sessione, `p_local` = id di questo giocatore. true se pronto.
func open(_p_role: int, _p_session: String, _p_local: String) -> bool:
	push_error("CoopLink.open: metodo astratto")
	return false


func close() -> void:
	push_error("CoopLink.close: metodo astratto")


func is_open() -> bool:
	return false


## Invia un messaggio già costruito con CoopLinkMessage.make (la validazione è qui, non nell'implementazione).
func send(_msg: Dictionary) -> bool:
	push_error("CoopLink.send: metodo astratto")
	return false


## Messaggi arrivati dall'ultima chiamata, in ordine (seq, mittente). Emette anche `message_received` per ognuno.
func poll() -> Array:
	push_error("CoopLink.poll: metodo astratto")
	return []


## Id degli altri partecipanti conosciuti (da hello/bye).
func peers() -> Array:
	return []


## Numero di sequenza del prossimo messaggio in uscita.
func next_seq() -> int:
	_seq += 1
	return _seq


## Comodo: costruisce e invia un messaggio di tipo `type`.
func say(type: String, payload: Dictionary = {}, to_id: String = "") -> bool:
	return send(CoopLinkMessage.make(type, local_id, session_id, next_seq(), payload, to_id))


func is_host() -> bool:
	return role == Role.HOST
