class_name BotPlayer
extends RefCounted
## Giocatore automatico per i test di integrazione (test_playthrough.gd). Usa i sistemi VERI di una Simulation
## (quella dell'autoload Game in partita) e sceglie le azioni come farebbe una persona:
##   1. riscatta le missioni pronte, apre le Casse che può aprire, indossa l'equipaggiamento migliore;
##   2. segue la missione principale attiva: per ogni obiettivo non completato avvia la mansione, il
##      combattimento o l'azione di menù che serve (con la catena di ingredienti e l'allenamento necessari);
##   3. prima di combattere prepara cibo e armatura; se muore più volte si allena su mostri più facili.
## Il tempo è SOLO simulato: il bot chiama `step` (passo fisso di 0,1 s) e decide una volta al secondo.
## Non usa mai un sistema prima del suo sblocco (token in `unlocks`): se non trova nulla da fare è un BLOCCO
## (bug di integrazione o di dati), annotato in `blocks` con il motivo.
##
## Uso:
##   var bot := BotPlayer.new(Game.sim, func(dt: float) -> void: Game._on_step(dt))
##   var res := bot.run_until_quest("main_c1_q6", 3.0 * 3600.0)
##   res = {ok, t, quests: [{id, t}], blocks: [...], first_crate_t, unlock_t: {token: t}, deaths, max_tick_ms}

const STEP := 0.1
const DECIDE_EVERY := 10                # passi (1 s simulato)
const LONG_DECIDE_MULT := 5             # partita lunga: si guarda il gioco ogni 5 s (una persona non clicca ogni secondo)
const TRAIN_BATCH := 25                 # ingredienti raccolti in una volta per allenarsi
const FOOD_TARGET := 25                 # porzioni di cibo da avere prima di un combattimento impegnativo
const FOOD_MIN := 6
const IDLE_BLOCK_S := 300.0             # senza nulla da fare per 5 minuti simulati = blocco
const DEATHS_BEFORE_PREP := 2

var sim: Simulation
var step: Callable
var t: float = 0.0
var quests_log: Array = []              # [{id, t}]
var blocks: Array = []                  # [{t, quest, reason}]
var unlock_t: Dictionary = {}           # token -> t
var first_crate_t: float = -1.0
var max_tick_ms: float = 0.0
var clock: Callable = Callable()              # opzionale: orologio in µs per le misure (es. tempo di CPU, PerfGate.clock_usec)
var between_steps: Callable = Callable()      # opzionale: chiamata dopo ogni passo, FUORI dal tempo misurato
var violations: Array = []              # usi di un sistema prima del suo sblocco (non dovrebbero esserci)
var stubs: Array = []                   # obiettivi completati senza il sistema vero (oggi nessuno)
var log_lines: PackedStringArray = []
var verbose: bool = false
## Usa i Tomi dell'Esperienza sull'Eroe quando un mostro della storia è troppo forte (false = profilo "lento").
var use_tomes: bool = true

var _idle_s: float = 0.0
var _deaths_seen: int = 0
var _death_streak: int = 0
var _prep_until_t: float = -1.0
var _reason: String = ""
var _last_task: String = ""
var _spent: Dictionary = {}
var _hard_logged: String = ""
var _food_run: bool = false
var _prep_hard: bool = false
var _last_sig: String = ""
var _last_progress_t: float = 0.0
const STALL_BLOCK_S := 1200.0

# ---------------------------------------------------------------- partita lunga (integrazione finale, resoconto 47)
## Gioca oltre il Cap. I: Tenuta, Gilda, Fazioni, incursioni, Rito; come un giocatore idle che lascia il gioco
## acceso a lungo, durante i compiti lunghi "va via" (offline analitico vero, `step_long`) a blocchi.
var long_mode: bool = false
## Tetto di tempo REALE per la partita (ms, 0 = nessuno): un test non deve girare all'infinito.
var wall_limit_ms: int = 0                    # ms sull'orologio `clock` (CPU se impostato, altrimenti tempo reale)
## Callable(seconds: float) -> void: tempo in blocco (Game._on_long_gap). Necessario con long_mode.
var step_long: Callable
const AWAY_AFTER_S := 180.0             # stesso compito per 3 minuti attivi -> si va via (giocatore idle)
const AWAY_CHUNK_S := 1800.0            # blocco di assenza (offline vero)
const WAIT_CHUNK_S := 900.0             # attesa di un timer (spedizione, ricarica, coloni)
const SESSION_S := 300.0                # sessione attiva tipica: 5 minuti, poi mezz'ora via (si ricontrolla il gioco)
var played_s: float = 0.0               # tempo attivo (a passi da 0,1 s)
var away_s: float = 0.0                 # tempo in assenza (offline)
var rewards: Array = []                 # [{t, kind, id}] ricompense ricevute (missioni, livelli, casse...)
var chapter_t: Dictionary = {}          # capitolo -> t di fine (ultima missione riscattata)
var offline_max_ms: float = 0.0
var decide_ms: float = 0.0               # tempo reale speso a decidere (diagnosi della durata del test)
var step_ms: float = 0.0                 # tempo reale speso nei passi della simulazione
var _task_since_t: float = 0.0
var _wait_reason: String = ""
var _side_t: float = -1e9
var _cur_obj: String = ""
var _played_at_away: float = 0.0
var _tidy_t: float = -1e9


func _progress_signal() -> String:
	var xp := 0.0
	for s in sim.ctx.state.get("skills", {}).values():
		xp += float(s.get("xp", 0.0))
	var q := _quests()
	return "%s|%.3f|%d" % [q.current_main(), q.fraction(q.current_main()) if not q.current_main().is_empty() else 1.0, int(xp)]


func _init(p_sim: Simulation, p_step: Callable) -> void:
	sim = p_sim
	step = p_step
	var ev: Object = sim.ctx.events
	ev.unlocked.connect(_on_unlocked)
	ev.crate_opened.connect(_on_crate_opened)
	ev.level_up.connect(_on_level_up)


func _on_unlocked(token: String) -> void:
	if not unlock_t.has(token):
		unlock_t[token] = t
		rewards.append({"t": t, "kind": "unlock", "id": token})


func _on_crate_opened(_r: Dictionary) -> void:
	if first_crate_t < 0.0:
		first_crate_t = t
	rewards.append({"t": t, "kind": "crate", "id": ""})


func _on_level_up(skill: String, _lv: int) -> void:
	rewards.append({"t": t, "kind": "level", "id": skill})


# ====================================================================== sistemi

func _s(id: String) -> GameSystem:
	return sim.get_system(id)


func _bank() -> BankSystem:
	return _s("bank") as BankSystem


func _skills() -> SkillSystem:
	return _s("skills") as SkillSystem


func _combat() -> CombatSystem:
	return _s("combat") as CombatSystem


func _quests() -> QuestSystem:
	return _s("quests") as QuestSystem


func _has(token: String) -> bool:
	return (sim.ctx.state.get("unlocks", []) as Array).has(token)


func _data() -> Object:
	return sim.ctx.data


func _log(s: String) -> void:
	var line := "[%6.1f min] %s" % [t / 60.0, s]
	log_lines.append(line)
	if verbose:
		print(line)


# ====================================================================== ciclo

## Gioca finché la missione indicata è completata (riscattata) o finisce il tempo. Ritorna il resoconto.
func run_until_quest(quest_id: String, max_s: float) -> Dictionary:
	var n := 0
	var wall0 := _now()
	var every := DECIDE_EVERY * (LONG_DECIDE_MULT if long_mode else 1)
	while t < max_s:
		if n % every == 0:
			if wall_limit_ms > 0 and float(_now() - wall0) / 1000.0 > float(wall_limit_ms):
				blocks.append({"t": t, "quest": _quests().current_main(), "reason": "tempo reale esaurito: " + _last_task})
				_log("BLOCCO: tempo reale esaurito con " + _last_task)
				break
			var td := Time.get_ticks_usec()
			_decide()
			decide_ms += float(Time.get_ticks_usec() - td) / 1000.0
			if (goal_skill.is_empty() and _quests().is_done(quest_id)) or (not goal_skill.is_empty() and _goal_reached()):
				break
			if _idle_s >= IDLE_BLOCK_S:
				blocks.append({"t": t, "quest": _quests().current_main(), "reason": _reason})
				_log("BLOCCO: " + _reason)
				break
			# segnale di progresso: missione, livelli, XP totale. Fermo per 20 minuti = blocco (es. Deposito pieno)
			var sig := _progress_signal()
			if sig != _last_sig:
				_last_sig = sig
				_last_progress_t = t
			elif t - _last_progress_t > STALL_BLOCK_S:
				blocks.append({"t": t, "quest": _quests().current_main(), "reason": "nessun progresso: %s (%s)" % [_last_task, _reason]})
				_log("BLOCCO: nessun progresso con %s (%s)" % [_last_task, _reason])
				break
			if long_mode and _maybe_go_away():
				n += 1
				continue
		_account(STEP)
		var t0 := _now()
		step.call(STEP)
		var ms := float(_now() - t0) / 1000.0
		step_ms += ms
		if ms > max_tick_ms:
			max_tick_ms = ms
		if between_steps.is_valid():          # fuori dalla misura del tick (es. calibrazione del carico, PerfGate)
			between_steps.call()
		t += STEP
		played_s += STEP
		n += 1
	return {"ok": _quests().is_done(quest_id), "t": t, "quests": quests_log, "blocks": blocks,
		"first_crate_t": first_crate_t, "unlock_t": unlock_t, "deaths": int(sim.ctx.state.hero.get("deaths", 0)),
		"max_tick_ms": max_tick_ms, "violations": violations, "stubs": stubs, "played_s": played_s, "away_s": away_s,
		"rewards": rewards, "chapter_t": chapter_t, "offline_max_ms": offline_max_ms}


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_usec()


## Assenza (solo long_mode): compito lungo da 10 minuti attivi o attesa di un timer -> offline vero a blocchi.
## Il segnale di progresso e il contatore di inattività ripartono (il tempo passato via non è un blocco).
func _maybe_go_away() -> bool:
	var chunk := 0.0
	if not _wait_reason.is_empty():
		chunk = WAIT_CHUNK_S
	elif _last_task.begins_with("combat:") or _last_task.begins_with("action:"):
		if t - _task_since_t >= AWAY_AFTER_S or played_s - _played_at_away >= SESSION_S:
			chunk = AWAY_CHUNK_S
	if chunk <= 0.0:
		return false
	var why := _wait_reason if not _wait_reason.is_empty() else _last_task
	if _last_task.begins_with("action:"):
		var outs: Array = _data().action(_last_task.trim_prefix("action:")).get("outputs", [])
		if not outs.is_empty():
			why += " [%s: %d, Deposito %d liberi]" % [str(outs[0].item), _bank().count(str(outs[0].item)), _bank().free_slots()]
	var t0 := _now()
	step_long.call(chunk)
	var ms := float(_now() - t0) / 1000.0
	offline_max_ms = maxf(offline_max_ms, ms)
	_spent["away"] = float(_spent.get("away", 0.0)) + chunk
	t += chunk
	away_s += chunk
	_played_at_away = played_s
	_task_since_t = t
	_idle_s = 0.0
	_last_progress_t = t
	_log("via per %d min (%s, offline %.0f ms)" % [int(chunk / 60.0), why, ms])
	_wait_reason = ""
	# il compito di prima potrebbe essersi fermato offline (cibo, Deposito): lo si riavvia alla prossima decisione
	_last_task = ""
	return true


var prof: Dictionary = {}                # parte della decisione -> ms reali (diagnosi)


func _pt(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = float(prof.get(key, 0.0)) + float(now - t0) / 1000.0
	return now


func _decide() -> void:
	var p0 := Time.get_ticks_usec()
	_claim_ready()
	p0 = _pt("claim", p0)
	_open_crates()
	p0 = _pt("crates", p0)
	_equip_best()
	p0 = _pt("equip", p0)
	_tidy_bank()
	p0 = _pt("tidy", p0)
	_track_deaths()
	_eat_if_needed()
	_harvest_ready()
	p0 = _pt("misc", p0)
	if long_mode:
		_side_activities()
	p0 = _pt("side", p0)
	var task := _choose_task()
	p0 = _pt("choose", p0)
	if task.is_empty():
		_idle_s += float(DECIDE_EVERY * (LONG_DECIDE_MULT if long_mode else 1)) * STEP
		return
	_idle_s = 0.0
	_apply(task)


# ====================================================================== azioni "di menù"

func _claim_ready() -> void:
	var q := _quests()
	for e in q.active_quests():
		if bool(e.ready) and q.claim(str(e.id)):
			if str(e.kind) == "main":
				quests_log.append({"id": str(e.id), "t": t, "hero": _skills().level("hero"), "spent": _spent,
					"played": played_s, "away": away_s})
				_spent = {}
				var d := q.quest_def(str(e.id))
				if str(e.id).ends_with("_q6"):
					chapter_t[int(d.get("chapter", 0))] = t
			rewards.append({"t": t, "kind": "quest", "id": str(e.id)})
			_log("missione riscattata: %s" % e.id)


## Tempo speso per attività (per missione): "skill:<mansione>" | "combat:<mostro>" | "idle".
func _account(dt: float) -> void:
	var a: Dictionary = sim.ctx.state.get("activity", {})
	var key := "idle"
	match str(a.get("type", "")):
		"skill":
			key = "skill:" + str(_data().action(str(a.get("action", ""))).get("skill", ""))
		"combat":
			key = "combat:" + str(a.get("monster", ""))
	_spent[key] = float(_spent.get(key, 0.0)) + dt


func _open_crates() -> void:
	if not _has("feature:crates"):
		return
	var cr := _s("crates") as CrateSystem
	var bank := _bank()
	for sid in bank.owned_stack_ids():       # Carro di Ritiro compreso: le Casse e le chiavi nel Carro si aprono lo stesso
		if cr.is_crate(str(sid)) and cr.openable(str(sid)) > 0:
			var res := cr.open(str(sid), cr.openable(str(sid)), false)
			for r in res:
				_log("cassa aperta: %s -> %s (%s)" % [sid, r.def_id, r.rarity])
				_wear_skin(r)


## Indossa nel Guardaroba la finitura trovata se lo slot è vuoto (bonus gratuito: lo farebbe chiunque).
func _wear_skin(r: Dictionary) -> void:
	if not _has("feature:wardrobe") or str(r.get("kind", "")) != "skin" or str(r.get("uid", "")).is_empty():
		return
	var cr := _s("crates") as CrateSystem
	var slot := str(_data().item(str(r.def_id)).get("skin", {}).get("slot", ""))
	if not slot.is_empty() and cr.equipped(slot).is_empty():
		cr.equip(str(r.uid))


func _class_style() -> String:
	return str(_combat().class_def().get("style", "melee"))


## Punteggio grezzo di un pezzo: tier e somma delle statistiche (il bot non è un ottimizzatore).
func _gear_score(def: Dictionary) -> float:
	var eq: Dictionary = def.get("equipment", {})
	var s := float(def.get("tier", 0)) * 100.0 + float(eq.get("damage", 0.0)) * 3.0
	for k in eq.get("stats", {}):
		s += float(eq.stats[k])
	return s


func _equip_best() -> void:
	if not _has("feature:combat"):
		return
	var cb := _combat()
	var bank := _bank()
	var lvl := cb.hero_level()
	var best := {}          # slot -> [score, uid]
	for inst in bank.state.instances:
		var def: Dictionary = _data().item(str(inst.def))
		var eq: Dictionary = def.get("equipment", {})
		if eq.is_empty() or lvl < int(eq.get("level_req", 1)):
			if def.has("tool"):
				_consider_tool(inst, def)
			continue
		var slot := str(eq.slot)
		if slot == "weapon" and (str(eq.get("style", "")) != _class_style() or bool(eq.get("two_handed", false))):
			continue
		if slot == "ammo" or slot == "ring":
			continue
		var sc := _gear_score(def) + _quality_bonus(inst)
		if not best.has(slot) or sc > float(best[slot][0]):
			best[slot] = [sc, str(inst.uid)]
	for slot in best:
		var cur := cb.equipped(slot)
		var uid: String = best[slot][1]
		if cur == uid:
			continue
		var cur_sc := -1.0
		if not cur.is_empty():
			var ci := bank.get_instance(cur)
			cur_sc = _gear_score(_data().item(str(ci.get("def", "")))) + _quality_bonus(ci)
		if float(best[slot][0]) > cur_sc and cb.equip(uid):
			_log("indossato: %s (%s)" % [bank.get_instance(uid).def, slot])


## Deposito quasi pieno: vende l'equipaggiamento non in uso (Mercato) come farebbe una persona.
func _tidy_bank() -> void:
	var bank := _bank()
	if long_mode and bank.free_slots() < 10 and t - _tidy_t >= 60.0:
		_tidy_t = t
		_tidy_bank_long()
	if bank.free_slots() >= 8 or not _has("feature:market"):
		return
	var mk: Variant = _s("market")
	var sold := 0
	for inst in bank.state.instances.duplicate():
		var def: Dictionary = _data().item(str(inst.def))
		if (def.has("equipment") or def.has("tool")) and not bank.is_in_use(str(inst.uid)) and not bool(inst.locked):
			sold += int(mk.sell(str(inst.def), 1))
	if sold > 0:
		_log("Deposito pieno: venduto equipaggiamento in più per %d oro" % sold)


## Partita lunga, Deposito quasi pieno: come una persona compra cassetti all'Emporio (se l'oro avanza), scarta il cibo
## bruciato e vende le pile che non servono a nessuna ricetta sbloccata né alla missione in corso.
func _tidy_bank_long() -> void:
	var bank := _bank()
	var mk: Variant = _s("market")
	if bank.count("burnt_food") > 0:
		bank.discard("burnt_food", bank.count("burnt_food"))
	if mk != null and _has("feature:market"):
		for i in 5:
			var st: Dictionary = mk.shop_status("bank_slot", 1)
			if not bool(st.get("ok", false)) or bank.gold() < int(st.cost) * 3:
				break
			if mk.buy("bank_slot", 1):
				_log("comprato un cassetto del Deposito (%d oro)" % int(st.cost))
	if bank.free_slots() >= 10 or mk == null or not _has("feature:market"):
		return
	var used := {}
	for aid in _data().all_actions():
		var a: Dictionary = _data().action(aid)
		var sk := str(a.get("skill", ""))
		if _has("skill:" + sk):
			for io in a.get("inputs", []):
				used[str(io.item)] = true
	var qid := _quests().current_main()
	for o in _quests().quest_def(qid).get("objectives", []) if not qid.is_empty() else []:
		used[str(o.get("item", ""))] = true
	for sid in bank.state.stacks.keys():
		if bank.free_slots() >= 10:
			break
		var d: Dictionary = _data().item(str(sid))
		var cat := str(d.get("category", ""))
		if used.has(str(sid)) or cat in ["key", "crate", "food", "currency", "seed", "potion", "quest", "consumable", "ammo"] \
				or bank.is_def_locked(str(sid)):
			continue
		var n := bank.count(str(sid))
		if mk.is_tradeable(str(sid)):
			if int(mk.sell(str(sid), n)) > 0:
				_log("Deposito pieno: venduta la pila di %s" % sid)
		elif bank.discard(str(sid), n) > 0:
			_log("Deposito pieno: scartato %s" % sid)


func _quality_bonus(inst: Dictionary) -> float:
	return ["normal", "fine", "excellent", "masterwork"].find(str(inst.get("quality", "normal"))) * 0.5


func _consider_tool(inst: Dictionary, def: Dictionary) -> void:
	var cb := _combat()
	if not cb.has_method("equip_tool"):
		return
	var skill := str(def.tool.skill)
	var cur: String = str(sim.ctx.state.get("equipment", {}).get("tools", {}).get(skill, ""))
	if cur == str(inst.uid):
		return
	if not cur.is_empty():
		var ci := _bank().get_instance(cur)
		if int(_data().item(str(ci.get("def", ""))).get("tier", 0)) >= int(def.get("tier", 0)):
			return
	if cb.call("equip_tool", str(inst.uid)):
		_log("attrezzo: %s" % def.id)


## Nella prima ora si gioca attivi: sotto metà vita si preme "Mangia ora" (efficienza piena, docs/05 §6).
func _eat_if_needed() -> void:
	var cb := _combat()
	if cb.in_combat() and cb.hp() > 0.0 and cb.hp() < cb.max_hp() * 0.45:
		cb.eat_food(true)


func _track_deaths() -> void:
	var d := int(sim.ctx.state.hero.get("deaths", 0))
	if d > _deaths_seen:
		_death_streak += d - _deaths_seen
		_deaths_seen = d
		_log("morte n. %d" % d)


# ====================================================================== scelta del compito

## Compito = {"kind": "action", "action": id} | {"kind": "combat", "zone": z, "monster": m} | {"kind": "none"}
## (azione già svolta in giornata: niente da avviare, si aspetta). {} = non so cosa fare (blocco).
## Obiettivo libero dopo la storia (partita lunga): allenare `goal_skill` fino al livello del Rito e farlo.
var goal_skill: String = ""
var goal_done_t: float = -1.0


func _goal_reached() -> bool:
	var ps := _s("prestige") as PrestigeSystem
	if ps != null and ps.rite_done(goal_skill):
		if goal_done_t < 0.0:
			goal_done_t = t
		return true
	return false


## Gioca fino al Rito della mansione indicata (allenandola con le assenze del long_mode). Stesso resoconto di run_until_quest.
func run_until_rite(skill: String, max_s: float) -> Dictionary:
	goal_skill = skill
	var res := run_until_quest("", max_s)
	res["ok"] = _goal_reached()
	goal_skill = ""
	return res


func _choose_task() -> Dictionary:
	if not goal_skill.is_empty():
		var ps := _s("prestige") as PrestigeSystem
		_cur_obj = "Rito di " + goal_skill
		var tk := _plan_train(goal_skill, ps.rite_level(), 0)
		return tk if not tk.is_empty() else {"kind": "none"}
	var q := _quests()
	var qid := q.current_main()
	if qid.is_empty():
		_reason = "nessuna missione principale attiva"
		return {}
	var d := q.quest_def(qid)
	var objs: Array = d.get("objectives", [])
	var pr := q.progress_of(qid)
	for i in objs.size():
		var obj: Dictionary = objs[i]
		var target := QuestSystem.target_of(obj)
		var cur := int(pr[i]) if i < pr.size() else 0
		if cur >= target:
			continue
		var tp := Time.get_ticks_usec()
		var task := _task_for(qid, i, obj, target - cur)
		_pt("obj:" + str(obj.get("type", "")), tp)
		if not task.is_empty():
			_cur_obj = "%s#%d %s" % [qid, i, str(obj.get("type", ""))]
			return task
	# tutti gli obiettivi in attesa di aggiornamento (eventi accodati): si continua com'è
	if q.is_ready(qid):
		return {"kind": "none"}
	return {}


func _task_for(qid: String, idx: int, obj: Dictionary, left: int) -> Dictionary:
	var type := str(obj.get("type", ""))
	match type:
		"gather":
			return _plan_produce(str(obj.item), left, 0)
		"craft":
			return _plan_produce(str(obj.item), left, 0)
		"equip":
			return _plan_equip(str(obj.item))
		"kill":
			var m: Dictionary = _data().get_def("monsters", str(obj.monster))
			return _plan_kill(str(m.get("zone", "")), str(obj.monster))
		"kill_zone":
			return _plan_kill(str(obj.zone), "")
		"kill_any":
			return _plan_kill("", "")
		"open_crates":
			return _plan_open_crate()
		"sell_market":
			return _plan_sell(left)
		"deliver":
			var have := _bank().count(str(obj.item))
			if have > 0 and _quests().deliver(qid, idx):
				return {"kind": "none"}
			if _action_for(str(obj.item)).is_empty():
				return _plan_drop(str(obj.item))
			return _plan_produce(str(obj.item), left, 0)
		"talk":
			# come il giocatore che preme «Parla» nella scheda della missione
			_quests().talk(str(obj.get("npc", "")))
			return {"kind": "none"}
		"build":
			return _plan_build(str(obj.building), int(obj.get("level", 1)))
		"steal":
			return _plan_steal(str(obj.target))
		"recruit":
			return _plan_recruit()
		"expedition":
			return _plan_expedition()
		"bounty_complete":
			return _plan_bounty()
		"tradeup":
			return _plan_tradeup()
		"complete_raid":
			return _plan_raid(str(obj.get("raid", "")))
		"reach_level":
			return _plan_train(str(obj.skill), int(obj.level), 0)
		"farm_harvest":
			return _plan_farm(qid, obj, left)
		"skill_actions":
			return _plan_train(str(obj.skill), _skills().level(str(obj.skill)) + 1, 0)
	_reason = "%s: tipo di obiettivo non gestito dal bot (%s)" % [qid, type]
	return {}


# ---------------------------------------------------------------- produzione

## Azione che produce l'oggetto (la più bassa di livello tra quelle sbloccate).
var _action_for_cache: Dictionary = {}


func _action_for(item: String) -> Dictionary:
	if _action_for_cache.has(item):
		return _action_for_cache[item]
	var res := _action_for_scan(item)
	_action_for_cache[item] = res
	return res


func _action_for_scan(item: String) -> Dictionary:
	var best := {}
	var acts: Dictionary = _data().all_actions()
	for aid in acts:
		var a: Dictionary = acts[aid]
		if str(a.get("kind", "")) == "crop":
			continue
		for o in a.get("outputs", []):
			if o is Dictionary and str(o.get("item", "")) == item:
				if best.is_empty() or int(a.get("level_req", 1)) < int(best.get("level_req", 1)):
					best = a
	return best


func _out_qty(a: Dictionary, item: String) -> float:
	for o in a.get("outputs", []):
		if str(o.item) == item:
			var q: Variant = o.qty
			return (float(q[0]) + float(q[1])) / 2.0 if q is Array else float(q)
	return 1.0


func _producing(item: String) -> bool:
	var aid := _skills().current_action()
	if aid.is_empty():
		return false
	for o in _data().action(aid).get("outputs", []):
		if str(o.item) == item:
			return true
	return false


## Procura `need_min` pezzi in Deposito (se ne sta già producendo, continua fino a `need_full`). {} = già a posto.
func _plan_obtain(item: String, need_min: int, need_full: int, depth: int) -> Dictionary:
	var have := _bank().count(item)
	if have >= need_full or (have >= need_min and not _producing(item)):
		return {}
	return _plan_produce(item, need_full - have, depth)


## Produce `qty` pezzi nuovi (contano per gli obiettivi gather/craft): prima gli ingredienti, poi l'azione.
func _plan_produce(item: String, qty: int, depth: int) -> Dictionary:
	if depth > 8:
		_reason = "catena di produzione troppo profonda per " + item
		return {}
	var a := _action_for(item)
	if a.is_empty():
		if long_mode:
			return _plan_external(item, qty)
		_reason = "nessuna azione produce " + item
		return {}
	var sk := str(a.skill)
	if not _has("skill:" + sk):
		_reason = "%s richiede la mansione %s, non ancora sbloccata" % [item, sk]
		return {}
	if _skills().level(sk) < int(a.get("level_req", 1)):
		return _plan_train(sk, int(a.level_req), depth + 1)
	var crafts := int(ceil(float(qty) / maxf(1.0, _out_qty(a, item))))
	var running := _skills().current_action() == str(a.id)
	for io in a.get("inputs", []):
		var need := int(io.qty) * crafts
		if _action_for(str(io.item)).is_empty():
			# ingrediente che non si fabbrica (Emporio o bottino dei mostri)
			if _bank().count(str(io.item)) < (int(io.qty) if running else need):
				var ext := _plan_external(str(io.item), need - _bank().count(str(io.item)))
				if not ext.is_empty():
					return ext
				return {}
			continue
		# già in produzione: si continua finché basta per un ciclo (niente avanti e indietro per un pezzo bruciato)
		var sub := _plan_obtain(str(io.item), int(io.qty) if running else need, need, depth + 1)
		if not sub.is_empty():
			return sub
	return {"kind": "action", "action": str(a.id)}


## Ingrediente che non si fabbrica: si compra all'Emporio se c'è, altrimenti dal mostro che lo lascia cadere.
var _ext_depth: int = 0


func _plan_external(item: String, qty: int) -> Dictionary:
	if _ext_depth > 3:
		_reason = "catena di acquisti/bottino troppo profonda per " + item
		return {}
	_ext_depth += 1
	var r := _plan_external_impl(item, qty)
	_ext_depth -= 1
	return r


func _plan_external_impl(item: String, qty: int) -> Dictionary:
	var mk: Variant = _s("market")
	if mk != null and _has("feature:market"):
		for e in _data().table("shop"):
			if str(e.get("item", "")) == item and str(e.get("section", "")) == "goods":
				var st: Dictionary = mk.shop_status(str(e.id), qty)
				if bool(st.get("ok", false)) and mk.buy(str(e.id), qty):
					_log("comprato all'Emporio: %d x %s" % [qty, item])
					return {"kind": "none"}
				if _bank().gold() < int(e.get("price", 0)) * qty:
					return _plan_gold(int(e.get("price", 0)) * qty)
	if not long_mode:
		_reason = "nessuna azione produce " + item
		return {}
	if item == "vault_shard":
		return _plan_shards(qty)
	var sec := _plan_secondary(item)
	if not sec.is_empty():
		return sec
	return _plan_drop(item)


## Schegge del Caveau: si fondono le finiture in più (prima le rare; mai quelle indossate o bloccate), altrimenti si
## aprono casse per averne.
func _plan_shards(qty: int) -> Dictionary:
	var cr := _s("crates") as CrateSystem
	var got := 0
	var keep := 10            # dieci finiture della stessa rarità servono ai Contratti di Scambio
	for r in ["rare", "epic"]:
		var free_uids: Array = []
		for inst in _bank().state.instances:
			if str(inst.get("kind", "")) == "skin" and str(inst.get("rarity", "")) == r and cr.consume_block(str(inst.uid)).is_empty():
				free_uids.append(str(inst.uid))
		for i in maxi(0, free_uids.size() - keep):
			if got >= qty:
				break
			got += cr.fuse(str(free_uids[i]))
	if got > 0:
		_log("fuse finiture: +%d Schegge" % got)
		return {"kind": "none"}
	return _plan_kill("", "")          # le casse (e quindi le finiture) cadono combattendo e lavorando


## Oggetto che esce come secondario o bottino di un'azione (gemme dalla Miniera, semi dalle raccolte...): l'azione
## sbloccata senza ingredienti che lo dà con più probabilità al secondo. {} se nessuna.
func _plan_secondary(item: String) -> Dictionary:
	var best := {}
	var best_rate := 0.0
	var acts: Dictionary = _data().all_actions()
	for aid in acts:
		var x: Dictionary = acts[aid]
		var sk := str(x.get("skill", ""))
		if not _has("skill:" + sk) or _skills().level(sk) < int(x.get("level_req", 1)) \
				or not (x.get("inputs", []) as Array).is_empty() or str(x.get("kind", "")) in ["crop", "tree"]:
			continue
		for sec in x.get("secondary", []) + x.get("drops", []):
			if not (sec is Dictionary):
				continue
			var share := 0.0
			if str(sec.get("item", "")) == item:
				share = 1.0
			elif sec.has("pick"):
				var tw := 0.0
				var mine := 0.0
				for pk in sec.pick:
					tw += float(pk.weight)
					if str(pk.item) == item:
						mine += float(pk.weight)
				share = mine / maxf(1e-9, tw)
			var rate := float(sec.get("chance", 0.0)) * share / maxf(0.1, float(x.get("time_s", 3.0)))
			if rate > best_rate:
				best_rate = rate
				best = x
	if best.is_empty():
		return {}
	return {"kind": "action", "action": str(best.id)}


## Allena una mansione fino al livello: l'azione sbloccata con più XP all'ora i cui ingredienti si procurano.
func _plan_train(skill: String, level: int, depth: int) -> Dictionary:
	var sk := _skills()
	if sk.level(skill) >= level:
		return {}
	if skill == "hero":
		return _plan_kill("", "")
	if not _has("skill:" + skill):
		_reason = "allenare %s: mansione non sbloccata" % skill
		return {}
	if long_mode and level - sk.level(skill) >= 3:
		# una persona usa il Tomo ricevuto dalla storia proprio sulla mansione che la ferma
		for tome in ["tome_xp_large", "tome_xp_medium", "tome_xp_small"]:
			while sk.level(skill) < level and _bank().count(tome) > 0 and sk.use_tome(tome, skill):
				_log("Tomo usato su %s: %s -> livello %d" % [skill, tome, sk.level(skill)])
		if sk.level(skill) >= level:
			return {"kind": "none"}
	var best := {}
	var best_rate := -1.0
	for a in _data().actions_for_skill(skill):
		if str(a.get("kind", "")) == "crop" or sk.level(skill) < int(a.get("level_req", 1)):
			continue
		if not _inputs_reachable(a, depth):
			continue
		# pezzi non impilabili riempiono il Deposito: per allenarsi solo se c'è molto spazio
		var out_def: Dictionary = _data().item(str((a.get("outputs", [{}]) as Array)[0].get("item", "")))
		if not bool(out_def.get("stackable", true)) and _bank().free_slots() < 20:
			continue
		var rate := float(a.get("xp", 0.0)) / maxf(0.1, float(a.get("time_s", 3.0)))
		if long_mode:
			# il tempo vero comprende quello per procurarsi gli ingredienti (50 lingotti per una chiave non conviene)
			rate = float(a.get("xp", 0.0)) / maxf(0.1, float(a.get("time_s", 3.0)) + _inputs_cost_s(a, 0))
		else:
			# gli ingredienti costano tempo: penalità grezza per ogni ingrediente da produrre
			rate /= 1.0 + float((a.get("inputs", []) as Array).size())
		if rate > best_rate:
			best_rate = rate
			best = a
	if best.is_empty():
		_reason = "allenare %s: nessuna azione possibile" % skill
		return {}
	for io in best.get("inputs", []):
		var sub := _plan_obtain(str(io.item), int(io.qty), int(io.qty) * TRAIN_BATCH, depth + 1)
		if not sub.is_empty():
			return sub
	return {"kind": "action", "action": str(best.id)}


## Secondi stimati per procurarsi gli ingredienti di un ciclo (catena di produzione, a passi base). Il Deposito
## non conta: allenarsi consuma le scorte.
func _inputs_cost_s(a: Dictionary, depth: int) -> float:
	var c := 0.0
	for io in a.get("inputs", []):
		var src := _action_for(str(io.item))
		if src.is_empty() or depth > 4:
			c += 30.0 * float(io.qty)          # da comprare o da far cadere: caro
			continue
		var per := (float(src.get("time_s", 3.0)) + _inputs_cost_s(src, depth + 1)) / maxf(1.0, _out_qty(src, str(io.item)))
		c += per * float(io.qty)
	return c


func _inputs_reachable(a: Dictionary, depth: int) -> bool:
	if depth > 6:
		return false
	for io in a.get("inputs", []):
		if _bank().count(str(io.item)) >= int(io.qty):
			continue
		var src := _action_for(str(io.item))
		if src.is_empty() or not _has("skill:" + str(src.skill)) \
				or _skills().level(str(src.skill)) < int(src.get("level_req", 1)) or not _inputs_reachable(src, depth + 1):
			return false
	return true


# ---------------------------------------------------------------- equipaggiamento, casse, mercato

func _plan_equip(item: String) -> Dictionary:
	if not _has("feature:combat"):
		_reason = "equipaggiare %s: combattimento non sbloccato" % item
		return {}
	var bank := _bank()
	for inst in bank.state.instances:
		if str(inst.def) == item:
			if _combat().is_equipped(str(inst.uid)) or _combat().equip(str(inst.uid)):
				return {"kind": "none"}
			_reason = "equipaggiare %s: equip() rifiutato" % item
			return {}
	return _plan_produce(item, 1, 0)


var _farm_until: float = -1.0       # PT118: dopo una chiave rifiutata per materiali (oro finito) si combatte per un po' invece di riprovare


func _plan_open_crate() -> Dictionary:
	if t < _farm_until:
		return _plan_kill("", "")
	if not _has("feature:crates"):
		_reason = "aprire casse: funzione non sbloccata"
		return {}
	var cr := _s("crates") as CrateSystem
	var bank := _bank()
	for sid in bank.owned_stack_ids():
		if cr.is_crate(str(sid)):
			var key: Variant = cr.crate_def(str(sid)).get("key")
			if key != null and bank.count(str(key)) <= 0:
				return _plan_produce(str(key), 1, 0)
	# nessuna cassa: si gioca normalmente (le casse cadono da mansioni e mostri)
	return _plan_kill("", "")


func _plan_sell(gold_left: int) -> Dictionary:
	if not _has("feature:market"):
		_reason = "vendere: Mercato non sbloccato"
		return {}
	var mk: Variant = _s("market")
	var bank := _bank()
	var sold := 0
	for sid in bank.state.stacks.keys():
		if sold >= gold_left:
			break
		var d: Dictionary = _data().item(str(sid))
		var cat := str(d.get("category", ""))
		if cat in ["key", "crate", "food", "currency"] or bank.is_def_locked(str(sid)) or not mk.is_tradeable(str(sid)):
			continue
		var n := bank.count(str(sid))
		if n > 0:
			sold += int(mk.sell(str(sid), n))
	if sold > 0:
		_log("venduto per %d oro" % sold)
		return {"kind": "none"}
	# niente da vendere: raccogli qualcosa che si vende (tronchi)
	return _plan_produce("log_pine", 50, 0)


# ---------------------------------------------------------------- combattimento

func _monster_ok(mid: String) -> bool:
	var tp := Time.get_ticks_usec()
	var est := _combat().estimate(mid)
	_pt("estimate", tp)
	if est.is_empty():
		return false
	var hp := _combat().max_hp()
	var heal_pool := float(_bank().count(_food_id())) * _food_heal()
	# come una persona: ci prova se non muore al primo colpo e se il cibo in borsa copre la perdita di vita stimata
	return float(est.worst_hit) < hp * 0.95 and float(est.loss_per_kill) < (hp * 0.8 + heal_pool * 0.8)


func _food_id() -> String:
	var best := ""
	var best_heal := 0.0
	for sid in _bank().owned_stack_ids():
		var f: Dictionary = _data().item(str(sid)).get("food", {})
		if not f.is_empty() and float(f.get("heal", 0)) > best_heal:
			best_heal = float(f.heal)
			best = str(sid)
	return best


func _food_heal() -> float:
	var f := _food_id()
	return float(_data().item(f).get("food", {}).get("heal", 0.0)) if not f.is_empty() else 0.0


func _plan_kill(zone: String, monster: String) -> Dictionary:
	if not _has("feature:combat"):
		_reason = "combattere: combattimento non sbloccato"
		return {}
	var cb := _combat()
	var z := zone
	if z.is_empty():
		for e in cb.zones():
			if bool(e.unlocked):
				z = str(e.id)
	if z.is_empty() or not cb.zone_unlocked(z):
		_reason = "zona %s non sbloccata (eroe %d)" % [zone, cb.hero_level()]
		return {}
	# cibo negli slot
	var fid := _food_id()
	if not fid.is_empty() and not cb.food_slots().has(fid):
		cb.set_food(0, fid)
	# preparazione: dopo morti ripetute, armatura e cibo (come farebbe una persona)
	if _death_streak >= DEATHS_BEFORE_PREP and _prep_until_t < 0.0:
		_prep_until_t = t + 600.0
		_death_streak = 0
		_log("troppe morti: preparazione (armatura, cibo, allenamento)")
	var target := monster
	var hard := not monster.is_empty() and not _monster_ok(monster)
	if hard and use_tomes:
		# "ah, il Tomo della missione!": una persona lo usa quando un mostro la ferma
		for tome in ["tome_xp_large", "tome_xp_medium", "tome_xp_small"]:
			while _bank().count(tome) > 0 and _skills().use_tome(tome, "hero"):
				_log("Tomo usato sull'Eroe: %s -> livello %d" % [tome, _skills().level("hero")])
		hard = not _monster_ok(monster)
	if hard and _hard_logged != monster:
		_hard_logged = monster
		var est := cb.estimate(monster)
		_log("%s troppo forte per ora (eroe %d, vita %.0f, colpo peggiore %.0f, perdita/uccisione %.0f, cibo %d)" % [monster,
			cb.hero_level(), cb.max_hp(), float(est.worst_hit), float(est.loss_per_kill), _bank().count(_food_id())])
	if hard or _prep_until_t > t or _food_run:
		_prep_hard = hard
		var prep := _plan_prep()
		_prep_hard = false
		if not prep.is_empty():
			return prep
		# allenamento sul mostro più forte che si batte in sicurezza nella zona
		var easy := ""
		for m in cb.monsters_of(z):
			if str(m.get("type", "")) == "normal" and _monster_ok(str(m.id)):
				easy = str(m.id)
		if not easy.is_empty() and easy != monster:
			target = easy
	if _prep_until_t >= 0.0 and _prep_until_t <= t:
		_prep_until_t = -1.0
	if target.is_empty():
		for m in cb.monsters_of(z):
			if str(m.get("type", "")) == "normal" and (target.is_empty() or _monster_ok(str(m.id))):
				target = str(m.id)
	return {"kind": "combat", "zone": z, "monster": target}


## Armatura mancante (fucinabile) e scorta di cibo. {} = già pronti.
func _plan_prep() -> Dictionary:
	var tp := Time.get_ticks_usec()
	var r := _plan_prep_impl()
	_pt("prep", tp)
	return r


func _plan_prep_impl() -> Dictionary:
	# cibo: scorta minima subito; rifornimento completo prima di un mostro impegnativo (dopo l'armatura)
	var a0 := _best_cook() if _has("skill:cooking") else {}
	var food_item := str(a0.outputs[0].item) if not a0.is_empty() else _food_id()
	var food0 := _bank().count(food_item) if not food_item.is_empty() else 0
	if food0 >= FOOD_TARGET:
		_food_run = false
	elif food0 < FOOD_MIN:
		_food_run = true
	if _food_run and not a0.is_empty():
		var ft := _plan_produce(food_item, FOOD_TARGET - food0, 0)
		if not ft.is_empty():
			return ft
	var gear := _plan_gear()
	if not gear.is_empty():
		return gear
	if _prep_hard and food0 < FOOD_TARGET and not a0.is_empty():
		_food_run = true
		return _plan_produce(food_item, FOOD_TARGET - food0, 0)
	return {}


## Armatura migliore che si sa fabbricare (allenandosi al più GEAR_TRAIN_LEVELS livelli). {} = già a posto.
func _plan_gear() -> Dictionary:
	var cb := _combat()
	var slots: Array = ["body", "legs", "offhand", "helm", "gloves", "boots", "cape"]
	if long_mode:
		slots.push_front("weapon")          # nella partita lunga si forgia anche l'arma (danno del tier)
	for slot in slots:
		var item := _craftable_gear(slot)
		if item.is_empty() or _bank().count(item) > 0:
			continue
		var cur := cb.equipped(slot)
		if not cur.is_empty():
			var ci := _bank().get_instance(cur)
			if _gear_score(_data().item(str(ci.get("def", "")))) >= _gear_score(_data().item(item)):
				continue
		var task := _plan_produce(item, 1, 0)
		if not task.is_empty():
			return task
	return {}


func _producing_food() -> bool:
	var aid := _skills().current_action()
	return not aid.is_empty() and str(_data().action(aid).get("skill", "")) in ["cooking", "fishing"]


func _best_cook() -> Dictionary:
	var best := {}
	for a in _data().actions_for_skill("cooking"):
		if _skills().level("cooking") >= int(a.get("level_req", 1)) and _inputs_reachable(a, 0):
			if best.is_empty() or int(a.get("level_req", 1)) > int(best.get("level_req", 1)):
				best = a
	return best


## Pezzo del tier più alto che si sa fabbricare per lo slot (stile della classe), allenandosi al più
## GEAR_TRAIN_LEVELS livelli nella mansione. Una persona fa così: forgia l'armatura, cuce il mantello.
const GEAR_TRAIN_LEVELS := 3

var _gear_cache: Dictionary = {}         # slot -> [t, risultato] (la ricerca scorre centinaia di ricette)


func _craftable_gear(slot: String) -> String:
	if long_mode:
		var c: Variant = _gear_cache.get(slot)
		if c is Array and t - float(c[0]) < 120.0:
			return str(c[1])
		var r := _craftable_gear_scan(slot)
		_gear_cache[slot] = [t, r]
		return r
	return _craftable_gear_scan(slot)


func _craftable_gear_scan(slot: String) -> String:
	var best := ""
	var best_sc := -1.0
	for skill in ["smithing", "tailoring", "woodworking", "jewelcrafting"]:
		if not _has("skill:" + skill):
			continue
		for a in _data().actions_for_skill(skill):
			if _skills().level(skill) + GEAR_TRAIN_LEVELS < int(a.get("level_req", 1)):
				continue
			var out := str(a.outputs[0].item)
			var def: Dictionary = _data().item(out)
			var eq: Dictionary = def.get("equipment", {})
			if eq.is_empty() or str(eq.slot) != slot or _combat().hero_level() < int(eq.get("level_req", 1)):
				continue
			if slot == "offhand" and str(eq.get("style", "")) not in ["", _class_style()]:
				continue
			if slot == "weapon" and (str(eq.get("style", "")) != _class_style() or bool(eq.get("two_handed", false))):
				continue
			if eq.has("armor_type") and str(eq.armor_type) != "plate" and _class_style() == "melee":
				continue
			if not _inputs_reachable_any_level(a, 0):
				continue
			var sc := _gear_score(def)
			if sc > best_sc:
				best_sc = sc
				best = out
	return best


## Come _inputs_reachable ma accetta di allenare le mansioni degli ingredienti (sbloccate).
func _inputs_reachable_any_level(a: Dictionary, depth: int) -> bool:
	if depth > 6:
		return false
	for io in a.get("inputs", []):
		if _bank().count(str(io.item)) >= int(io.qty):
			continue
		var src := _action_for(str(io.item))
		if src.is_empty() or not _has("skill:" + str(src.skill)) \
				or _skills().level(str(src.skill)) + GEAR_TRAIN_LEVELS < int(src.get("level_req", 1)) \
				or not _inputs_reachable_any_level(src, depth + 1):
			return false
	return true


# ---------------------------------------------------------------- coltivazione (FarmingSystem vero)

func _farming() -> FarmingSystem:
	return _s("farming") as FarmingSystem


## Raccoglie ciò che è pronto nell'Orto/Frutteto (come una persona che passa dal Giardino): XP e ortaggi gratis.
func _harvest_ready() -> void:
	var fs := _farming()
	if fs == null or not _has("skill:farming") or fs.ready_count() == 0:
		return
	var n := fs.harvest_all()
	if n > 0:
		_log("raccolti %d appezzamenti" % n)


## Obiettivo farm_harvest con la Coltivazione vera: semina il seme giusto negli appezzamenti liberi, aspetta la
## crescita facendo altro di utile (cibo, armatura, combattimento) e raccoglie. Senza semi li cerca dove cadono
## (oggetto secondario di una mansione sbloccata, es. il lino dell'Erboristeria).
func _plan_farm(_qid: String, obj: Dictionary, _left: int) -> Dictionary:
	if not _has("skill:farming"):
		_reason = "coltivare: mansione non sbloccata"
		return {}
	var fs := _farming()
	if fs == null:
		_reason = "coltivare: sistema farming assente"
		return {}
	var a := {}
	var kind := ""
	for k in fs.kinds():
		for x in fs.actions_for(str(k)):
			if str((x.get("outputs", [{}]) as Array)[0].get("item", "")) == str(obj.crop):
				a = x
				kind = str(k)
	if a.is_empty():
		_reason = "coltivare: nessuna coltura produce " + str(obj.crop)
		return {}
	if fs.level() < int(a.get("level_req", 1)):
		_reason = "coltivare %s: livello di Coltivazione insufficiente" % obj.crop
		return {}
	_harvest_ready()
	var growing := false
	var free := false
	for i in fs.plot_count(kind):
		var pl := fs.plot(kind, i)
		if str(pl.crop) == str(a.id) and fs.is_growing(kind, i):
			growing = true
		elif str(pl.crop) == "":
			free = true
	if free and _bank().count(str(a.seed)) >= int(a.get("seeds_per_plant", 1)):
		var n := fs.plant_all(kind, str(a.id))
		if n > 0:
			_log("seminati %d x %s" % [n, a.id])
			growing = true
	if growing:
		# nel frattempo si fa altro di utile: cibo e allenamento in combattimento
		var prep := _plan_prep()
		return prep if not prep.is_empty() else _plan_kill("", "")
	return _plan_seed(str(a.seed))


## Procura un seme: la mansione sbloccata (senza ingredienti) che lo dà come secondario con più probabilità al secondo.
func _plan_seed(seed_id: String) -> Dictionary:
	var best := {}
	var best_rate := -1.0
	var acts: Dictionary = _data().all_actions()
	for aid in acts:
		var x: Dictionary = acts[aid]
		var sk := str(x.get("skill", ""))
		if not _has("skill:" + sk) or _skills().level(sk) < int(x.get("level_req", 1)) \
				or not (x.get("inputs", []) as Array).is_empty():
			continue
		for sec in x.get("secondary", []):
			if sec is Dictionary and str(sec.get("item", "")) == seed_id:
				var rate := float(sec.get("chance", 0.0)) / maxf(0.1, float(x.get("time_s", 3.0)))
				if rate > best_rate:
					best_rate = rate
					best = x
	if best.is_empty():
		_reason = "coltivare: nessuna fonte sbloccata per " + seed_id
		return {}
	return {"kind": "action", "action": str(best.id)}


# ====================================================================== esecuzione

func _apply(task: Dictionary) -> void:
	var kind := str(task.get("kind", ""))
	var key := ""
	match kind:
		"action":
			var aid := str(task.action)
			key = "action:" + aid
			var sk := str(_data().action(aid).get("skill", ""))
			if not _has("skill:" + sk):
				violations.append({"t": t, "use": "skill:" + sk})
			if _skills().current_action() != aid:
				if not _skills().start(aid):
					_reason = "start(%s) rifiutato: %s" % [aid, _skills().can_start(aid)]
					if str(_skills().can_start(aid)).ends_with("MATERIALS") and str(_data().action(aid).get("category", "")) == "keys":
						_farm_until = t + 1800.0
					_idle_s += float(DECIDE_EVERY * (LONG_DECIDE_MULT if long_mode else 1)) * STEP
					return
		"combat":
			key = "combat:%s:%s" % [task.zone, task.monster]
			if not _has("feature:combat"):
				violations.append({"t": t, "use": "feature:combat"})
			var a: Dictionary = sim.ctx.state.get("activity", {})
			if str(a.get("type", "")) != "combat" or str(a.get("zone", "")) != str(task.zone) \
					or str(a.get("monster", "")) != str(task.monster):
				if not _combat().start(str(task.zone), str(task.monster)):
					_reason = "combat.start(%s, %s) rifiutato" % [task.zone, task.monster]
					_idle_s += float(DECIDE_EVERY * (LONG_DECIDE_MULT if long_mode else 1)) * STEP
					return
		"none":
			key = "none"
		"wait":
			key = "wait:" + str(task.get("why", ""))
			_wait_reason = str(task.get("why", "attesa"))
	if key != _last_task:
		_last_task = key
		_task_since_t = t
		_log("-> %s  [%s]" % [key, _cur_obj])


# ====================================================================== partita lunga (long_mode, resoconto 47)

func _estate() -> EstateSystem:
	return _s("estate") as EstateSystem


func _mercs() -> MercenarySystem:
	return _s("mercenaries") as MercenarySystem


## Attività di contorno di una persona che passa dai menù ogni tanto (una volta al minuto simulato):
## raccoglie la Tenuta, riempie la Dispensa, accetta gli incarichi di fazione, fa il Rito quando può.
func _side_activities() -> void:
	if t - _side_t < 60.0:
		return
	_side_t = t
	var es := _estate()
	if es != null and _has("feature:estate"):
		es.collect_all()
		if es.settlers() > 0 and es.pantry_hours() < 4.0:
			var fid := _food_id()
			var spare := _bank().count(fid) - FOOD_TARGET if not fid.is_empty() else 0
			if spare > 0:
				es.stock_pantry(fid, spare)
	if _has("feature:factions"):
		var q := _quests()
		for f in _data().table("factions"):
			for qid in q.faction_quests(str(f.id)):
				if q.faction_quest_status(qid) == "available" and q.accept_faction_quest(qid):
					_log("incarico di fazione accettato: " + qid)
	if _has("feature:market") and t - _gear_buy_t >= 600.0:
		_gear_buy_t = t
		_buy_gear()
	var ps := _s("prestige") as PrestigeSystem
	if ps != null:
		for row in _data().table("skill_prestige"):
			var sk := str(row.skill)
			if ps.can_rite(sk).is_empty():
				var p := ps.do_star(sk, true)
				if not p.is_empty():
					rewards.append({"t": t, "kind": "rite", "id": sk})
					_log("Rito fatto: %s (+%d Polvere)" % [sk, int(p.get("dust_gain", 0))])
			elif ps.can_star(sk).is_empty():
				if not ps.do_star(sk, false).is_empty():
					rewards.append({"t": t, "kind": "star", "id": sk})
					_log("Stella: " + sk)


## Equipaggiamento dal Mercato (scorte dei mercanti, prezzo ×1,8 del valore): come una persona che resta indietro
## con la forgia, compra per ogni slot il pezzo migliore che può indossare se costa meno di un terzo del suo oro.
var _gear_buy_t: float = -1e9
var _gear_by_slot: Dictionary = {}       # slot -> [def, ...] (dati, calcolato una volta)


func _buy_gear() -> void:
	var mk: Variant = _s("market")
	var cb := _combat()
	if mk == null:
		return
	if _gear_by_slot.is_empty():
		for it in _data().items_by_category("equipment"):
			var eq: Dictionary = it.get("equipment", {})
			if not eq.is_empty():
				(_gear_by_slot.get_or_add(str(eq.slot), []) as Array).append(it)
	var lvl := cb.hero_level()
	for slot in ["weapon", "body", "legs", "helm", "gloves", "boots", "offhand", "cape"]:
		var cur := cb.equipped(slot)
		var cur_sc := -1.0
		if not cur.is_empty():
			cur_sc = _gear_score(_data().item(str(_bank().get_instance(cur).get("def", ""))))
		var best := {}
		var best_sc := cur_sc
		for d in _gear_by_slot.get(slot, []):
			var eq: Dictionary = d.equipment
			if lvl < int(eq.get("level_req", 1)) or bool(d.get("unique", false)):
				continue
			if slot == "weapon" and (str(eq.get("style", "")) != _class_style() or bool(eq.get("two_handed", false))):
				continue
			if slot == "offhand" and str(eq.get("style", "")) not in ["", _class_style()]:
				continue
			if eq.has("armor_type") and str(eq.armor_type) != "plate" and _class_style() == "melee":
				continue
			var sc := _gear_score(d)
			var price := int(mk.buy_price_npc(str(d.id)))
			if sc > best_sc and price > 0 and price * 3 <= _bank().gold() and int(mk.npc_stock(str(d.id))) > 0:
				best_sc = sc
				best = d
		if not best.is_empty() and mk.buy_npc(str(best.id), 1):
			_log("comprato al Mercato: %s (%s)" % [best.id, slot])


## In attesa di un timer (spedizione, ricarica): si combatte nella zona più alta, come farebbe una persona.
func _while_waiting(why: String) -> Dictionary:
	var k := _plan_kill("", "")
	return k if not k.is_empty() else {"kind": "wait", "why": why}


## Oggetto che non si fabbrica: lo si procura dal mostro che lo lascia cadere (tabella dei drop).
func _plan_drop(item: String) -> Dictionary:
	var cb := _combat()
	var best := {}
	for m in _data().table("monsters"):
		var tbl: Dictionary = _data().get_def("drop_tables", str(m.get("drop_table", "")))
		for e in tbl.get("entries", []) + tbl.get("always", []):
			if e is Dictionary and str(e.get("item", "")) == item and cb.zone_unlocked(str(m.get("zone", ""))):
				if best.is_empty() or int(m.level) < int(best.level):
					best = m
	if best.is_empty():
		_reason = "nessun mostro raggiungibile lascia " + item
		return {}
	return _plan_kill(str(best.zone), str(best.id))


## Oro per un acquisto: si vende il superfluo, poi si fa ciò che rende oro (Borseggio se c'è, altrimenti combattimento).
func _plan_gold(need: int) -> Dictionary:
	if _has("feature:market") and _sell_surplus() > 0 and _bank().gold() >= need:
		return {"kind": "none"}
	if _has("skill:thievery"):
		var best := {}
		for a in _data().actions_for_skill("thievery"):
			if _skills().level("thievery") >= int(a.get("level_req", 1)):
				best = a
		if not best.is_empty():
			return {"kind": "action", "action": str(best.id)}
	return _plan_kill("", "")


## Vende al Mercato ciò che avanza: raccolti e prodotti oltre una scorta, equipaggiamento non in uso.
const SURPLUS_KEEP := 150

func _sell_surplus() -> int:
	var mk: Variant = _s("market")
	var bank := _bank()
	var sold := 0
	for sid in bank.state.stacks.keys():
		var d: Dictionary = _data().item(str(sid))
		var cat := str(d.get("category", ""))
		if cat in ["key", "crate", "food", "currency", "seed", "potion", "quest", "consumable", "ammo"] or bank.is_def_locked(str(sid)) \
				or not mk.is_tradeable(str(sid)):
			continue
		var n := bank.count(str(sid)) - SURPLUS_KEEP
		if n > 0:
			sold += int(mk.sell(str(sid), n))
	for inst in bank.state.instances.duplicate():
		var def: Dictionary = _data().item(str(inst.def))
		if (def.has("equipment") or def.has("tool")) and not bank.is_in_use(str(inst.uid)) and not bool(inst.get("locked", false)):
			sold += int(mk.sell(str(inst.def), 1))
	if sold > 0:
		_log("venduto il superfluo per %d oro" % sold)
	return sold


func _plan_build(bid: String, level: int) -> Dictionary:
	var es := _estate()
	if es == null:
		_reason = "costruire: sistema Tenuta assente"
		return {}
	if es.level_of(bid) >= level:
		return {"kind": "none"}
	var why := es.can_upgrade(bid)
	if why.is_empty():
		if es.upgrade(bid):
			_log("costruito: %s livello %d" % [bid, es.level_of(bid)])
			rewards.append({"t": t, "kind": "build", "id": bid})
			return {"kind": "none"}
	var c := es.cost_of(bid)
	match why:
		"UI_ESTATE_REASON_GOLD":
			return _plan_gold(int(c.gold))
		"UI_ESTATE_REASON_MATERIALS":
			for it in c.items:
				var need := int(c.items[it])
				if _bank().count(str(it)) < need:
					if _action_for(str(it)).is_empty():
						return _plan_drop(str(it))
					return _plan_obtain(str(it), need, need, 0)
		"UI_ESTATE_REASON_SETTLERS":
			# i coloni arrivano col tempo (Casolare): se si può si alza il Casolare, altrimenti si aspetta
			if es.settlers() >= es.settler_cap() and es.can_upgrade("cottage").is_empty() and es.upgrade("cottage"):
				_log("Casolare livello %d (più coloni)" % es.level_of("cottage"))
				return {"kind": "none"}
			return {"kind": "wait", "why": "coloni per " + bid}
	_reason = "costruire %s: %s" % [bid, why]
	return {}


func _plan_steal(target: String) -> Dictionary:
	var a: Dictionary = _data().action(target)
	if a.is_empty():
		_reason = "borseggio: bersaglio sconosciuto " + target
		return {}
	if not _has("skill:thievery"):
		_reason = "borseggio: mansione non sbloccata"
		return {}
	if _skills().level("thievery") < int(a.get("level_req", 1)):
		return _plan_train("thievery", int(a.level_req), 0)
	return {"kind": "action", "action": target}


func _plan_recruit() -> Dictionary:
	var ms := _mercs()
	if ms == null or ms.tavern_level() <= 0:
		_reason = "reclutare: Taverna non costruita"
		return {}
	var best := ""
	var best_cost := 1 << 60
	for c in ms.candidates():
		var cost := ms.hire_cost(str(c.rarity))
		if cost < best_cost:
			best_cost = cost
			best = str(c.uid)
	if best.is_empty():
		return {"kind": "wait", "why": "nuovi candidati in Taverna"}
	var why := ms.can_hire(best)
	if why.is_empty() and ms.hire(best):
		_log("reclutato: %s (%d oro)" % [best, best_cost])
		return {"kind": "none"}
	if why == "UI_GUILD_REASON_GOLD":
		return _plan_gold(best_cost)
	_reason = "reclutare: " + why
	return {}


func _plan_expedition() -> Dictionary:
	var ex := _s("expeditions") as ExpeditionSystem
	var ms := _mercs()
	if ex == null or ms == null:
		_reason = "spedizioni: sistemi assenti"
		return {}
	if not ex.active().is_empty():
		return _while_waiting("spedizione in corso")
	var team: Array = []
	for m in ms.roster():
		if ms.is_available(str(m.uid)) and team.size() < 4:
			team.append(str(m.uid))
	if team.is_empty():
		var any_injured := false
		for m in ms.roster():
			any_injured = any_injured or ms.is_injured(str(m.uid))
		return {"kind": "wait", "why": "mercenari feriti"} if any_injured else _plan_recruit()
	var best := ""
	var best_p := -1e9
	for o in ex.board():
		var pv := ex.preview(o, team)
		# la prima spedizione della storia: la più breve tra quelle con buone probabilità (una persona non aspetta 8 ore)
		var score := (1.0 if float(pv.p_success) >= 0.6 else 0.0) + float(pv.p_success) * 0.1 - float(pv.duration_s) / 36000.0
		if score > best_p:
			best_p = score
			best = str(o.id)
	if best.is_empty():
		return {"kind": "wait", "why": "bacheca delle spedizioni vuota"}
	if ex.start(best, team):
		_log("spedizione partita (%d mercenari, %.1f h)" % [team.size(), float(ex.preview(ex.get_active(str(ex.active().back().id)), team).duration_s) / 3600.0 if not ex.active().is_empty() else 0.0])
		return {"kind": "none"}
	_reason = "spedizione rifiutata: " + ex.can_start(best, team)
	return {}


func _plan_bounty() -> Dictionary:
	var bs := _s("bounty") as BountySystem
	if bs == null:
		_reason = "taglie: sistema assente"
		return {}
	if not bs.has_active():
		var offers := bs.offers()
		if offers.is_empty():
			_reason = "taglie: bacheca vuota"
			return {}
		var pick := 0
		for i in offers.size():          # il bersaglio più facile
			if _monster_ok(str(offers[i].monster)):
				pick = i
				break
		bs.accept(pick)
		_log("taglia accettata: " + str(bs.active().offer.monster))
	var mid := str(bs.active().offer.monster)
	var m: Dictionary = _data().get_def("monsters", mid)
	if str(m.get("type", "")) == "dungeon_boss":
		bs.abandon()
		return {"kind": "none"}
	return _plan_kill(str(m.get("zone", "")), mid)


func _plan_tradeup() -> Dictionary:
	var cr := _s("crates") as CrateSystem
	if not cr.tradeup_unlocked():
		_reason = "contratto: funzione non sbloccata"
		return {}
	for r in ["rare", "epic", "legendary", "mythic"]:
		var pick := cr.auto_pick(r, false)
		if not pick.is_empty() and cr.contract_check(pick).get("ok", false):
			var res := cr.contract_sign(pick)
			if not res.is_empty():
				_log("Contratto di Scambio firmato (%s)" % r)
				return {"kind": "none"}
	# una persona toglie dal Guardaroba le finiture da poco per firmare il Contratto
	for r in ["rare", "epic"]:
		var have := cr.auto_pick(r, false).size()
		var worn: Array = []
		for slot in (cr.state.wardrobe as Dictionary).keys():
			var uid := cr.equipped(str(slot))
			if not uid.is_empty() and str(cr.instance(uid).get("rarity", "")) == r:
				worn.append(str(slot))
		if have + worn.size() >= int(cr.contract_inputs(false)) and have > 0:
			for sl in worn:
				cr.unequip(str(sl))
			_log("tolte dal Guardaroba %d finiture %s per il Contratto" % [worn.size(), r])
			return {"kind": "none"}
	# servono finiture: si aprono casse (chiavi comprese)
	return _plan_open_crate()


func _plan_raid(rid: String) -> Dictionary:
	var cb := _combat()
	var eg := cb.eg
	var a: Dictionary = sim.ctx.state.get("activity", {})
	if str(a.get("mode", "")) == "raid":
		return {"kind": "none"}
	if not eg.raid_unlocked(rid):
		var lv := int(eg.raid_def(rid).get("unlock", {}).get("hero_level", 1))
		if _skills().level("hero") < lv:
			return _plan_train("hero", lv, 0)
		_reason = "incursione %s non sbloccata" % rid
		return {}
	if eg.raid_cd(rid) > 0.0:
		return _while_waiting("ricarica dell'incursione")
	var rd := eg.raid_def(rid)
	var party := eg.suggest_party(rid)
	if party.size() < int(rd.party.size):
		var ms := _mercs()
		if ms != null and ms.roster().size() < ms.roster_cap():
			return _plan_recruit()
	var food := _food_id()
	if not food.is_empty() and not cb.food_slots().has(food):
		cb.set_food(0, food)
	var pv := eg.raid_preview(rid, party)
	if float(pv.get("p_win", 0.0)) < 0.6 or str(pv.get("level", "red")) == "red":
		if _hard_logged != rid:
			_hard_logged = rid
			_log("incursione %s ancora rischiosa (vittoria %.0f%%, eroe %d): ci si allena" % [rid, float(pv.get("p_win", 0.0)) * 100.0, cb.hero_level()])
		_prep_hard = true
		var prep := _plan_prep()
		_prep_hard = false
		if not prep.is_empty():
			return prep
		return _plan_kill("", "")
	if eg.start_raid(rid, party):
		_log("incursione %s iniziata (vittoria stimata %.0f%%)" % [rid, float(pv.p_win) * 100.0])
		return {"kind": "none"}
	_reason = "incursione %s rifiutata" % rid
	return {}
