class_name CoopRateLimiter
extends RefCounted
## Limite di frequenza per pari (secchio di gettoni) + conteggio delle violazioni (COOP-2).
## Puro e deterministico: il tempo lo passa il chiamante (`now_s`, secondi), così i test non dipendono dall'orologio.
## Ogni messaggio consuma un gettone; i gettoni si ricaricano a `rate_per_s` fino a `burst`. Messaggio senza gettone =
## scartato + 1 violazione. Anche i messaggi malformati contano come violazione (`strike`). Oltre `strikes_kick` il
## pari va scollegato (lo decide chi usa il limitatore).

var rate_per_s := 8.0
var burst := 24.0
var strikes_kick := 40
var _b: Dictionary = {}        # peer_id -> [gettoni, ultimo_t, violazioni]


func configure(net: Dictionary) -> void:
	rate_per_s = float(net["rate_per_s"])
	burst = float(net["rate_burst"])
	strikes_kick = int(net["strikes_kick"])


## True se il messaggio può passare (e consuma un gettone).
func allow(peer_id: int, now_s: float) -> bool:
	var b: Array = _b.get(peer_id, [burst, now_s, 0])
	var tokens := minf(burst, float(b[0]) + maxf(0.0, now_s - float(b[1])) * rate_per_s)
	b[1] = now_s
	if tokens < 1.0:
		b[0] = tokens
		b[2] = int(b[2]) + 1
		_b[peer_id] = b
		return false
	b[0] = tokens - 1.0
	_b[peer_id] = b
	return true


func strike(peer_id: int) -> void:
	var b: Array = _b.get(peer_id, [burst, 0.0, 0])
	b[2] = int(b[2]) + 1
	_b[peer_id] = b


func strikes(peer_id: int) -> int:
	return int(_b.get(peer_id, [0, 0, 0])[2])


func should_kick(peer_id: int) -> bool:
	return strikes(peer_id) >= strikes_kick


func forget(peer_id: int) -> void:
	_b.erase(peer_id)
