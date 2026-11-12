class_name CoopCombatAdapter
extends RefCounted
## UNICO punto in cui il modulo coop tocca membri privati (prefisso «_») di CombatSystem, EndgameCombat e CombatSim.
## Se un altro agente rinomina o cambia uno di questi membri, basta correggere questo file (e solo questo).
## Membri usati: CombatSystem._stats_for, _era, _sim_params, _est_regen, _scaled, _st_dirty, _gen, _abil_ver ·
## EndgameCombat._rift_floor_eval · CombatSim._phased, _check_phase.
## Se un giorno CombatSystem espone un'API pubblica equivalente, si cambia solo il corpo di queste funzioni.


static func stats_for(c: Object, stance: String) -> Dictionary:
	return c._stats_for(stance)


static func era(c: Object) -> int:
	return int(c._era())


static func sim_params(c: Object, st: Dictionary) -> Dictionary:
	return c._sim_params(st, {}, {}, true)


static func est_regen(c: Object, h: Dictionary, sim: CombatSim, st: Dictionary, dt: float) -> void:
	c._est_regen(h, sim, st, dt)


static func scaled(c: Object, mon: Dictionary) -> Dictionary:
	return c._scaled(mon, int(c._era()))


## Segna le statistiche da ricostruire (cambiano i compagni): svuota le stime in cache delle squadre.
static func mark_dirty(c: Object) -> void:
	c._st_dirty = true


## Impronta dell'assetto dell'Eroe (cambia quando cambiano statistiche, abilità o Era).
static func build_key(c: Object) -> String:
	c._stats_for("")                       # costruisce le statistiche se servono (aggiorna _gen)
	return "%d|%d|%d" % [c._gen, c._abil_ver, c._era()]


static func rift_floor_eval(eg: Object, fl: int, evals: Dictionary) -> Dictionary:
	return eg._rift_floor_eval(fl, evals)


static func sim_phased(sim: CombatSim) -> bool:
	return sim._phased


static func sim_check_phase(sim: CombatSim, e: Dictionary) -> void:
	sim._check_phase(e)
