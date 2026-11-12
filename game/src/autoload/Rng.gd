extends Node
## Rng (autoload) — flussi RNG del giocatore (docs/17 §3). Delega a RngStreams (src/core/).
## Lo stato è salvato in GameState.data.rng con seed/state come stringhe (R-SAV-7):
## Game lo copia in GameState prima di ogni salvataggio (Rng.to_state) e lo ripristina dopo il load.
##   Rng.stream("loot").randf()      Rng.chance("crates", 0.003)      Rng.weighted_index("loot", [70, 25, 5])

var streams := RngStreams.new(0)


func seed_all(seed_value: int) -> void:
	streams.seed_all(seed_value)


func stream(stream_name: String) -> RandomNumberGenerator:
	return streams.stream(stream_name)


func randf(stream_name: String) -> float:
	return streams.randf(stream_name)


func randi_range(stream_name: String, from: int, to: int) -> int:
	return streams.randi_range(stream_name, from, to)


func chance(stream_name: String, p: float) -> bool:
	return streams.chance(stream_name, p)


func weighted_index(stream_name: String, weights: Array) -> int:
	return streams.weighted_index(stream_name, weights)


func to_state() -> Dictionary:
	return streams.to_state()


func from_state(d: Dictionary) -> bool:
	return streams.from_state(d)


static func parse_u64(s: String) -> int:
	return RngStreams.parse_u64(s)


static func u64_to_string(v: int) -> String:
	return RngStreams.u64_to_string(v)
