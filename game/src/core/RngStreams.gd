class_name RngStreams
extends RefCounted
## Flussi RNG separati e salvabili (docs/17 §3): loot, crates, combat, market, world.
## Classe pura: l'autoload Rng ne possiede una; i test e l'OfflineSimulator possono crearne altre.
## Seed e state (uint64) si salvano come STRINGHE decimali (R-SAV-7): vedi parse_u64 / u64_to_string.
## Determinismo: stesso seed principale -> stesse sequenze in ogni flusso, indipendenti tra loro
## (consumare numeri da "crates" non cambia "loot").

const STREAMS: PackedStringArray = ["loot", "crates", "combat", "market", "world"]
const U64_MAX_STR := "18446744073709551615"

# Costanti di splitmix64 scritte come int64 con segno (equivalgono a 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB)
const _SM_GAMMA := -7046029254386353131
const _SM_M1 := -4658895280553007687
const _SM_M2 := -7723592293110705685

var master_seed: int = 0
var _rngs: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	seed_all(seed_value)


## Inizializza tutti i flussi a partire da un seed principale (seed di flusso = splitmix64(master, indice)).
func seed_all(seed_value: int) -> void:
	master_seed = seed_value
	_rngs.clear()
	var x := seed_value
	for name in STREAMS:
		x = x + _SM_GAMMA
		var r := RandomNumberGenerator.new()
		r.seed = _mix(x)
		_rngs[name] = r


func stream(name: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = _rngs.get(name)
	assert(r != null, "flusso RNG sconosciuto: " + name)
	return r


func randf(name: String) -> float:
	return stream(name).randf()


func randi_range(name: String, from: int, to: int) -> int:
	return stream(name).randi_range(from, to)


func randf_range(name: String, from: float, to: float) -> float:
	return stream(name).randf_range(from, to)


## true con probabilità p (0..1).
func chance(name: String, p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return stream(name).randf() < p


## Indice estratto con pesi non negativi (Array di numeri). -1 se la somma è 0.
func weighted_index(name: String, weights: Array) -> int:
	return weighted_pick(stream(name), weights)


## Come weighted_index ma su un generatore dato (estrazioni indicizzate, QA82 Q82-1).
static func weighted_pick(r: RandomNumberGenerator, weights: Array) -> int:
	var tot := 0.0
	for w in weights:
		tot += maxf(0.0, float(w))
	if tot <= 0.0:
		return -1
	var x := r.randf() * tot
	for i in weights.size():
		x -= maxf(0.0, float(weights[i]))
		if x < 0.0:
			return i
	return weights.size() - 1


## Seed derivato in modo puro da (seme, etichetta, indice): FNV-1a a 64 bit sull'etichetta, poi splitmix64.
## Serve alle estrazioni INDICIZZATE (Casse): l'esito della N-esima apertura non dipende da nessun altro consumo di numeri casuali.
static func derive_seed(master: int, tag: String, index: int) -> int:
	var h := -3750763034362895579                       # 0xCBF29CE484222325 (offset FNV-1a) come int64 con segno
	for b in tag.to_utf8_buffer():
		h = (h ^ int(b)) * 1099511628211
	var x := _mix(master + _SM_GAMMA)
	x = _mix(x ^ h)
	x = _mix(x + _SM_GAMMA * (index + 1))
	return x


## Generatore pronto per (seme, etichetta, indice): stesso input, stessa sequenza, sempre.
static func derived_rng(master: int, tag: String, index: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = derive_seed(master, tag, index)
	return r


## {"loot": {"seed": "123", "state": "456"}, ...} con uint64 come stringhe (forma di docs/17 §4).
func to_state() -> Dictionary:
	var out := {}
	for name in STREAMS:
		var r: RandomNumberGenerator = _rngs[name]
		out[name] = {"seed": u64_to_string(r.seed), "state": u64_to_string(r.state)}
	out["master"] = u64_to_string(master_seed)
	return out


## Ripristina seed e state. Ritorna false (e lascia i flussi invariati) se i dati non sono validi.
func from_state(d: Dictionary) -> bool:
	for name in STREAMS:
		var s: Variant = d.get(name)
		if not (s is Dictionary) or not is_u64_string(str(s.get("seed", ""))) or not is_u64_string(str(s.get("state", ""))):
			return false
	for name in STREAMS:
		var r := RandomNumberGenerator.new()
		r.seed = parse_u64(d[name].seed)        # il seed reimposta lo state: va assegnato prima
		r.state = parse_u64(d[name].state)
		_rngs[name] = r
	if is_u64_string(str(d.get("master", ""))):
		master_seed = parse_u64(d.master)
	return true


# ------------------------------------------------------------------ uint64 <-> stringa (spike S2)

static func is_u64_string(s: String) -> bool:
	if s.is_empty() or s.length() > 20:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 48 or c > 57:
			return false
	if s.length() == 20 and s > U64_MAX_STR:
		return false
	return true


## Restituisce i 64 bit come int con segno (wraparound modulo 2^64). Stringa non valida -> 0.
static func parse_u64(s: String) -> int:
	if not is_u64_string(s):
		return 0
	var v := 0
	for i in s.length():
		v = v * 10 + (s.unicode_at(i) - 48)
	return v


static func u64_to_string(v: int) -> String:
	if v >= 0:
		return str(v)
	@warning_ignore("integer_division")
	var q := ((v >> 1) & 0x7FFFFFFFFFFFFFFF) / 5     # floor(v_senza_segno / 10)
	var r := v - q * 10
	return str(q) + str(r)


## Seed casuale per una nuova partita (non deterministico: ora + contatore del sistema).
static func fresh_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return (r.randi() << 32) ^ r.randi() ^ Time.get_ticks_usec()


static func _mix(x: int) -> int:
	var z := x
	z = (z ^ ((z >> 30) & 0x3FFFFFFFF)) * _SM_M1
	z = (z ^ ((z >> 27) & 0x1FFFFFFFFF)) * _SM_M2
	return z ^ ((z >> 31) & 0x1FFFFFFFF)
