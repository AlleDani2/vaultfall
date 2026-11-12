class_name CoopTransport
extends RefCounted
## Interfaccia astratta del trasporto coop (contratto condiviso COOP-1 / COOP-2, docs/audit_2026-10-22/69 e 70).
## COOP-1 la implementa senza rete (`LocalFileTransport`), COOP-2 con ENet (`CoopEnetTransport`, src/coop/net/).
## Se all'unione esistono due copie di questo file, se ne tiene UNA: il contratto è identico.
##
## Contratto minimo:
##   send(msg)             client -> host; host -> tutti i client
##   send_to(peer_id, msg) solo l'host verso un client (o un client verso l'host, peer_id = HOST_ID)
##   received(peer_id, msg) messaggio arrivato (Dictionary già decodificato; la validazione la fa chi ascolta)
##   peers()               id dei pari collegati (sull'host: i client; sul client: [HOST_ID] se collegato)
##   role()                Role.NONE / HOST / CLIENT
##   protocol_version()    versione del formato dei messaggi
## Nessun metodo usa `await`; `poll(now_s)` va chiamato a ogni frame da chi possiede il trasporto.

signal received(peer_id: int, msg: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal status_changed(status: String)

enum Role { NONE, HOST, CLIENT }

const PROTOCOL_VERSION := 1
const HOST_ID := 1

## Stati leggibili: "closed", "listening" (host), "connecting", "connected", "failed".
const ST_CLOSED := "closed"
const ST_LISTENING := "listening"
const ST_CONNECTING := "connecting"
const ST_CONNECTED := "connected"
const ST_FAILED := "failed"


func send(_msg: Dictionary) -> void:
	push_error("CoopTransport.send non implementato")


func send_to(_peer_id: int, _msg: Dictionary) -> void:
	push_error("CoopTransport.send_to non implementato")


func peers() -> Array:
	return []


func role() -> int:
	return Role.NONE


func local_id() -> int:
	return 0


func protocol_version() -> int:
	return PROTOCOL_VERSION


func status() -> String:
	return ST_CLOSED


func is_open() -> bool:
	return status() == ST_LISTENING or status() == ST_CONNECTED


func poll(_now_s: float) -> void:
	pass


## Scollega un pari (solo host). Il pari riceve peer_left.
func kick(_peer_id: int) -> void:
	pass


func close() -> void:
	pass
