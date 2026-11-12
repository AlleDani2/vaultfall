class_name TimePushSystem
extends GameSystem
## Sabbia del Custode (UI F13, docs/ui_redesign/03 Design A, 06 D24-D26): riserva di tempo che un clic spende per far avanzare
## SOLO l'azione in corso (mansione + coda; sistemi `constants.time_push.systems_for`, `bank` prima), come la Clessidra.
## id "time_push", stato "time_push":
##   reserve_s       Sabbia disponibile (0..reserve_cap_s)
##   pending_s       tempo già concesso ai clic e non ancora eseguito (coda a passi da 0,1 s); la riserva si scala SOLO quando il
##                   passo è davvero eseguito, quindi un passo che non sta nel budget di un fotogramma non perde nulla
##   pushed_total_s  tempo regalato in tutta la partita (statistica locale, nessuna telemetria)
##   today_s         tempo regalato nel «giorno» corrente (giorno = 86400 s di tempo contato: offline compreso)
##   day_age_s       eta' del «giorno» corrente
##   gift_given      il regalo di sblocco (constants.time_push.unlock_gift_s) è stato dato (una volta sola)
##
## REGOLE (docs/ui_redesign/03 §5, §8; docs/24):
##   - la Sabbia NON è un modificatore e NON cambia la velocità del Clock: non tocca FixedStepClock né Clock.set_speed (un accumulo
##     oltre 60 s verrebbe scambiato per assenza). Avanza il tempo come la Clessidra: Simulation.tick_subset;
##   - nessun effetto su Casse, estrazioni (seme, id cassa, N), coop, Prove, dungeon, incursioni, Breccia, boss mondiali, Estremo;
##   - rigenerazione online solo con un'azione ammessa in corso (e, perché il Clock non fa tick in pausa, a gioco non in pausa);
##     offline: regen_offline_pct % dell'assenza contata (stesso Δt di R-OFF-1, già limitato);
##   - nessun numero di bilanciamento qui: tutto in constants.time_push (tools/gamedata/core.py::TIME_PUSH).

## Unità di misura del «giorno» (non è un numero di bilanciamento).
const DAY_S := 86400.0
const STEP := FixedStepClock.STEP
## Residuo numerico sotto il quale la Sabbia conta come finita (1e-9 s: sottrazioni ripetute di 0,1 lasciano polvere in virgola mobile).
const EPS := 1e-9

var _last_emit_msec: int = -1000000


func _init() -> void:
	id = "time_push"
	state_key = "time_push"


func default_state() -> Variant:
	return {"reserve_s": clampf(float(_k().get("start_reserve_s", 0.0)), 0.0, cap_s()), "pushed_total_s": 0.0, "pending_s": 0.0,
		"today_s": 0.0, "day_age_s": 0.0, "gift_given": false}


func from_state(section: Variant) -> void:
	if not (section is Dictionary):
		section = default_state()
		ctx.state[state_key] = section
	state = section
	var cap := cap_s()
	state["reserve_s"] = clampf(_num(state.get("reserve_s", 0.0)), 0.0, cap)
	state["pending_s"] = clampf(_num(state.get("pending_s", 0.0)), 0.0, state.reserve_s)
	state["pushed_total_s"] = maxf(0.0, _num(state.get("pushed_total_s", 0.0)))
	state["today_s"] = maxf(0.0, _num(state.get("today_s", 0.0)))
	state["day_age_s"] = clampf(_num(state.get("day_age_s", 0.0)), 0.0, DAY_S)
	state["gift_given"] = bool(state.get("gift_given", false))


## Numero finito (NaN/inf/tipi strani -> 0): un salvataggio danneggiato non rompe la riserva.
static func _num(v: Variant) -> float:
	if v is float or v is int:
		var f := float(v)
		return f if is_finite(f) else 0.0
	return 0.0


func _k() -> Dictionary:
	return ctx.constants().get("time_push", {})


# ------------------------------------------------------------------ letture

func cap_s() -> float:
	return maxf(0.0, float(_k().get("reserve_cap_s", 0.0)))


func click_s() -> float:
	return float(_k().get("click_s", 0.0))


func reserve_s() -> float:
	return float(state.reserve_s)


func pending_s() -> float:
	return float(state.pending_s)


func today_s() -> float:
	return float(state.today_s)


func pushed_total_s() -> float:
	return float(state.pushed_total_s)


## La Sabbia è sbloccata (token concesso da una missione del Capitolo 0).
func is_unlocked() -> bool:
	var u := ctx.get_system("unlock")
	return u != null and bool(u.call("has", str(_k().get("unlock_token", "feature:time_push"))))


## Secondi di gioco fino al prossimo clic possibile a riserva vuota (per la UI: «fra N s»). 0 se c'è già Sabbia per un clic.
func seconds_to_next_click() -> float:
	var need := click_s() - (reserve_s() - pending_s())
	var rate := float(_k().get("regen_online_pct", 0.0)) / 100.0
	if need <= 0.0:
		return 0.0
	return need / rate if rate > 0.0 else INF


## "" se la Sabbia si può usare adesso, altrimenti la chiave UI del motivo (stessa idea di Hourglass.can_use).
func block_reason() -> String:
	if not is_unlocked():
		return "UI_PUSH_REASON_LOCKED"
	var blocked: Array = _k().get("blocked_when", [])
	if blocked.has("trial"):
		var pr := ctx.get_system("prestige")
		if pr != null and bool(pr.call("is_trial_active")):
			return "UI_PUSH_REASON_TRIAL"
	if blocked.has("extreme_risk") and ctx.mode_rules().has_permadeath():
		return "UI_PUSH_REASON_EXTREME"
	var kind := Hourglass.activity_kind(ctx)
	if kind.is_empty():
		return "UI_PUSH_REASON_NONE"
	if not (_k().get("allowed_activities", []) as Array).has(kind):
		return "UI_PUSH_REASON_ACT"
	return ""


# ------------------------------------------------------------------ clic

## Concede `n_clicks` clic: ognuno vale min(Sabbia libera, click_s). Il tempo concesso entra in coda (`pending_s`); la riserva si
## scala quando i passi vengono eseguiti (`drain`). Ritorna {ok, seconds, reason}; con `ok = false` nulla è stato concesso.
func request(n_clicks: int) -> Dictionary:
	var reason := block_reason()
	if not reason.is_empty():
		return {"ok": false, "seconds": 0.0, "reason": reason}
	var free := reserve_s() - pending_s()
	var granted := 0.0
	for i in maxi(0, n_clicks):
		var s := Formulas.push_spend(free, click_s())
		if s <= EPS:
			break
		free -= s
		granted += s
	if granted <= EPS:
		return {"ok": false, "seconds": 0.0, "reason": "UI_PUSH_EMPTY"}
	state["pending_s"] = pending_s() + granted
	return {"ok": true, "seconds": granted, "reason": ""}


## Esegue la coda: passi da 0,1 s (l'ultimo può essere più corto) sui soli sistemi dell'attività, al massimo `max_steps` passi e,
## se `cpu_budget_usec` > 0, fino a quel tempo CPU (il passo in corso finisce). Ritorna i passi eseguiti. Se l'attività non è più
## ammessa (azione finita, Prova...) la coda si svuota SENZA scalare la riserva: mai tempo perso.
func drain(max_steps: int, cpu_budget_usec: int = 0) -> int:
	var sim := ctx.simulation()
	if sim == null:
		return 0
	var steps := 0
	var start := Time.get_ticks_usec()
	while pending_s() > EPS and steps < max_steps:
		if not block_reason().is_empty():
			state["pending_s"] = 0.0
			break
		var dt := minf(pending_s(), STEP)
		var ids: Array = (_k().get("systems_for", {}) as Dictionary).get(Hourglass.activity_kind(ctx), [])
		sim.tick_subset(ids, dt)
		state["reserve_s"] = maxf(0.0, reserve_s() - dt)
		state["pending_s"] = maxf(0.0, pending_s() - dt)
		if reserve_s() < EPS:
			state["reserve_s"] = 0.0
		state["pushed_total_s"] = pushed_total_s() + dt
		state["today_s"] = today_s() + dt
		steps += 1
		if cpu_budget_usec > 0 and Time.get_ticks_usec() - start >= cpu_budget_usec:
			break
	if pending_s() <= EPS:
		state["pending_s"] = 0.0
	if steps > 0:
		_emit_changed(false)
	return steps


# ------------------------------------------------------------------ ciclo

func tick(dt: float) -> void:
	var unlocked := is_unlocked()
	if unlocked:
		_give_gift()
	_age_day(dt)
	if unlocked and block_reason().is_empty():
		var before := reserve_s()
		state["reserve_s"] = minf(cap_s(), before + Formulas.push_regen(dt, float(_k().get("regen_online_pct", 0.0))))
		if reserve_s() != before:
			_emit_changed(false)


## Offline (anche Bentornato): regen_offline_pct % del tempo contato, dal solito Δt già limitato da R-OFF-1. Nessuna condizione
## sull'attività (nell'assenza il giocatore non c'è). Riga «Sabbia ricaricata: +{time}» nel resoconto.
func simulate_offline(seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds <= 0.0 or not is_unlocked():
		return {}
	_give_gift()
	var before := reserve_s()
	state["reserve_s"] = minf(cap_s(), before + Formulas.push_regen(seconds, float(_k().get("regen_offline_pct", 0.0))))
	var gained := reserve_s() - before
	_age_day(seconds)
	_emit_changed(true)
	if gained < 1.0:
		return {}
	return {"rows": [{"key": "UI_OFFL_PUSH_ROW", "params": {"time": NumberFormat.fmt_time(gained)}}]}


## Assenza oltre il limite offline (R-OFF-6): passa solo il calendario, nessuna ricarica.
func advance_calendar(seconds: float) -> void:
	_age_day(seconds)


## Regalo di sblocco (una volta sola, mai oltre il tetto).
func _give_gift() -> void:
	if bool(state.gift_given):
		return
	state["gift_given"] = true
	state["reserve_s"] = minf(cap_s(), reserve_s() + float(_k().get("unlock_gift_s", 0.0)))
	_emit_changed(true)


func _age_day(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	var age := float(state.day_age_s) + seconds
	if age >= DAY_S:
		state["today_s"] = 0.0
		age = fmod(age, DAY_S)
	state["day_age_s"] = age


## Segnale per la UI, al massimo 10 Hz (tempo reale: serve solo a non inondare l'interfaccia, non entra nella simulazione).
func _emit_changed(force: bool) -> void:
	if ctx == null or ctx.events == null or not ctx.events.has_signal("push_changed"):
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_emit_msec < 100:
		return
	_last_emit_msec = now
	ctx.events.push_changed.emit(reserve_s(), cap_s())
