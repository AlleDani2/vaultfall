class_name SnapshotCache
extends RefCounted
## Snapshot dello stato per il salvataggio con costo ridotto (resoconto 47, E47-6; resoconto 50).
## `duplicate(true)` di 20.000 istanze costava ~80 ms sul thread principale a ogni autosalvataggio. Qui le liste GRANDI
## (>= MIN_BIG elementi, a profondità 2: `sezione.campo`, oggi `bank.instances`) si copiano a pezzi di CHUNK elementi:
## per ogni pezzo si calcola l'impronta (`Array.hash`, ~8 volte più economica della copia) e, se non è cambiata dall'ultimo
## snapshot, si riusa la copia già fatta. Il resto dello stato si copia in profondità come prima.
## Le copie riusate sono condivise tra snapshot successivi: vanno considerate SOLA LETTURA (il codec le legge soltanto).
## Garanzie: `full = true` (uscita, salvataggio sincrono, esportazione) rifà tutto da zero; gli snapshot incrementali sono
## comunque completi (nessuna sezione "sporca" da dimenticare) e ogni FULL_EVERY snapshot se ne fa uno completo, così un
## eventuale caso di impronta uguale con contenuto diverso (2^-32 per pezzo) non dura più di pochi autosalvataggi.

const CHUNK := 512
const MIN_BIG := 2048
const FULL_EVERY := 10

var _chunks: Dictionary = {}          # "sezione/campo" -> [{h, n, copy}]
var _count: int = 0
## Diagnostica (test): pezzi riusati e rifatti nell'ultimo snapshot.
var reused: int = 0
var rebuilt: int = 0


func reset() -> void:
	_chunks.clear()
	_count = 0


func snapshot(data: Dictionary, full: bool = false) -> Dictionary:
	_count += 1
	if _count % FULL_EVERY == 0:
		full = true
	reused = 0
	rebuilt = 0
	var out := {}
	for k in data:
		var sec: Variant = data[k]
		if sec is Dictionary:
			var cs := {}
			for f in sec:
				cs[f] = _copy_field(str(k) + "/" + str(f), sec[f], full)
			out[k] = cs
		elif sec is Array:
			out[k] = _copy_field(str(k), sec, full)
		else:
			out[k] = sec
	return out


func _copy_field(path: String, v: Variant, full: bool) -> Variant:
	if v is Array and (v as Array).size() >= MIN_BIG:
		return _copy_chunked(path, v, full)
	if v is Dictionary or v is Array:
		_chunks.erase(path)
		return v.duplicate(true)
	return v


func _copy_chunked(path: String, arr: Array, full: bool) -> Array:
	var old: Array = [] if full else _chunks.get(path, [])
	var fresh: Array = []
	var out: Array = []
	var n := arr.size()
	var i := 0
	var ci := 0
	while i < n:
		var part: Array = arr.slice(i, mini(i + CHUNK, n))       # copia superficiale: solo i riferimenti
		var h := part.hash()
		var copy: Array
		if ci < old.size() and int(old[ci].h) == h and int(old[ci].n) == part.size():
			copy = old[ci].copy
			reused += 1
		else:
			copy = part.duplicate(true)
			rebuilt += 1
		fresh.append({"h": h, "n": part.size(), "copy": copy})
		out.append_array(copy)
		i += CHUNK
		ci += 1
	_chunks[path] = fresh
	return out
