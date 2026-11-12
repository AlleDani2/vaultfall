class_name StratifiedRng
extends RefCounted
## Generatore di numeri casuali "stratificati" (Latin hypercube) per la stima offline del combattimento.
## Ha la stessa interfaccia di RngStreams usata dal motore (randf, chance) ma, su K cicli di scontro, ogni estrazione
## n-esima di uno scontro copre in modo uniforme i K strati: la media dei tempi di uccisione converge molto prima di
## un campionamento casuale puro (stessa precisione con ~3-5 volte meno cicli). Deterministico dal seme.
##
## COMBAT-3: le estrazioni hanno un TIPO (`kind`: colpo dell'eroe, danno, critico, colpo del mostro...). Ogni tipo ha il
## proprio contatore: la k-esima estrazione di danno è sempre «il danno del k-esimo colpo», anche se i colpi precedenti
## hanno mancato il bersaglio e non hanno estratto il danno (`skip` fa avanzare il contatore senza consumare numeri).
## Così la somma dei danni di uno scontro è stratificata davvero e il rumore residuo scende di circa 3 volte.
##
## Uso: `begin_cycle(c)` all'inizio di ogni scontro (c = 0..K-1). Oltre MAX_DRAWS estrazioni per tipo, o per cicli
## fuori intervallo (riscaldamento), si usano numeri casuali semplici.

const MAX_DRAWS := 640
const KINDS := 11

var strata: int
## Tipo dell'estrazione successiva per `randf` (0..KINDS-1); il motore usa `randk`, che lo passa direttamente.
var kind: int = 0
var _cycle: int = -1
var _draws: PackedInt32Array = PackedInt32Array()
var _perms: Array = []                   # (tipo × MAX_DRAWS + indice) -> PackedInt32Array, creata alla prima richiesta
var _plain := RandomNumberGenerator.new()
var _shuffler := RandomNumberGenerator.new()


func _init(p_strata: int, seed_value: int) -> void:
	strata = maxi(1, p_strata)
	_plain.seed = seed_value
	_shuffler.seed = seed_value ^ 0x5DEECE66D
	_draws.resize(KINDS)
	_perms.resize(KINDS * MAX_DRAWS)


## Inizia lo scontro del ciclo `c` (c fuori da 0..K-1 = numeri casuali semplici).
func begin_cycle(c: int) -> void:
	_cycle = c
	_draws.fill(0)


## Estrazione di tipo `k`: la d-esima di quel tipo nello scontro copre uniformemente i K strati.
func randk(k: int) -> float:
	var d := _draws[k]
	_draws[k] = d + 1
	if _cycle < 0 or _cycle >= strata or d >= MAX_DRAWS:
		return _plain.randf()
	var idx := k * MAX_DRAWS + d
	var perm: Variant = _perms[idx]
	if perm == null:
		perm = _make_perm()
		_perms[idx] = perm
	return (float((perm as PackedInt32Array)[_cycle]) + _plain.randf()) / float(strata)


func randf(_name: String = "") -> float:
	return randk(kind)


## Fa avanzare il contatore del tipo senza estrarre nulla (l'evento non è avvenuto in questo scontro).
func skip(k: int) -> void:
	_draws[k] = _draws[k] + 1


func chance(_name: String, p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return randf() < p


func _make_perm() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(strata)
	for i in strata:
		a[i] = i
	for i in range(strata - 1, 0, -1):
		var j := _shuffler.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t
	return a
