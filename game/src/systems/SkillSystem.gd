class_name SkillSystem
extends GameSystem
## Mansioni di raccolta e produzione (docs/04, docs/03 §2, docs/14). id "skills".
##
## Stato posseduto:
##   skills   (state_key): {skill_id: {"xp": float totale cumulato, "level": int, "record_level": int, "stars": int,
##                                     "perks": {"<livello_tier>": "a"|"ab"}}}
##   mastery  (ctx.state.mastery):  {action_id: {"xp": float totale cumulato, "level": int}}
##   activity (ctx.state.activity): {"type":"skill","action":id,"progress_s":float[,"stun_s":float,"dur_mult":float]}
##
## Una sola attività alla volta (R-AZ-1): start() sostituisce qualunque attività, anche di combattimento.
## Ordine di risoluzione di un'azione (R-AZ-3): ingredienti (con risparmio) → prodotti (con doppio) → secondari →
## cassa → famiglio → XP mansione → XP maestria → segnali → riavvio automatico.
##
## Bonus: tutto passa da ctx.modifiers (regola add/more, docs/14). I bonus di maestria sono per-azione e si sommano
## agli add della famiglia corrispondente nella funzione _mod(). Gli attrezzi equipaggiati
## (ctx.state.equipment.tools[skill] = uid istanza del bank) sono registrati come fonte "skilltool:<skill>";
## chi cambia attrezzo chiama refresh_tools(). Senza attrezzo equipaggiato l'attrezzo base (tier 1) vale +0%.
##
## Coda azioni (R-AZ-5): la possiede QueueSystem (stato "queue"); questo sistema lo avvisa a ogni ciclo riuscito
## (on_cycle) e, offline, gli chiede la condizione di fine dell'azione in testa (offline_cond/offline_commit).
## Automazione (R-AZ-4): con le Stelle richieste (constants.automation.stars) o con l'azione padroneggiata, a ingredienti
## finiti l'attività resta in attesa (activity.waiting) e riparte da sola quando tornano disponibili.
## Pozioni (PotionSystem) e Banchetti (BuffSystem) sono bonus normali in ctx.modifiers; la pozione perde una carica
## per azione riuscita del suo gruppo. Apprendisti: STUB (M6). La Coltivazione (kind "crop"/"tree") ha FarmingSystem.
## Il bank è raggiunto SOLO con ctx.get_system("bank") (docs/audit/17); se manca, le uscite non vanno da nessuna parte.

## Soglie TECNICHE (nessun numero di bilanciamento: Padronanza, Stelle, coda ecc. stanno in constants.json).
const LIMITS := {
	"max_cycles_per_tick": 1000,      # sicurezza contro durate quasi nulle
	"tick_epsilon": 1e-9,
}
const SOURCE_PERK := "perk:"
const SOURCE_TOOL := "skilltool:"
const NO_REASON := ""

var _skill_defs: Dictionary = {}      # skill_id -> definizione di skills.json
var _xp_cum: Array = []               # _xp_cum[L] = XP totali per essere al livello L (L>=1)
var _m_cum: Array = []                # idem per la maestria
var _cache: Dictionary = {}           # action_id -> profilo
var _mastery: Dictionary = {}
var _activity: Dictionary = {}
var _pet_by_skill: Dictionary = {}    # skill_id -> {"id": pet_id, "div": float}
var _last_success: bool = false       # esito dell'ultimo ciclo risolto (per la coda)


func _init() -> void:
	id = "skills"
	state_key = "skills"


# ------------------------------------------------------------------ ciclo di vita

func setup() -> void:
	_skill_defs.clear()
	for s in ctx.data.table("skills"):
		_skill_defs[s.id] = s
	var k := ctx.constants()
	_xp_cum = [0.0, 0.0]
	var cap := int(k.level_cap)
	for l in range(1, cap + 1):
		_xp_cum.append(float(_xp_cum[l]) + float(Formulas.xp_to_next(l)))     # indice l+1
	_m_cum = [0.0, 0.0]
	for m in range(1, int(k.mastery.cap) + 1):
		_m_cum.append(float(_m_cum[m]) + float(Formulas.mastery_to_next(m)))
	_pet_by_skill.clear()
	var rx := RegEx.new()
	rx.compile("/\\s*([0-9.]+)")
	for p in ctx.data.table("pets"):
		var src: Variant = p.get("source", {})
		if src is Dictionary and src.get("type", "") == "skill_action":
			var mt := rx.search(str(src.get("chance_formula", "")))
			if mt != null:
				_pet_by_skill[src.skill] = {"id": p.id, "div": float(mt.get_string(1))}
	if not ctx.modifiers.changed.is_connected(_invalidate):
		ctx.modifiers.changed.connect(_invalidate)


func default_state() -> Variant:
	var out := {}
	for sid in _skill_defs:
		out[sid] = _new_skill()
	return out


func from_state(section: Variant) -> void:
	state = section
	for sid in _skill_defs:
		if not state.has(sid) or not (state[sid] is Dictionary):
			state[sid] = _new_skill()
		var st: Dictionary = state[sid]
		for key in ["xp", "level", "record_level", "stars", "perks"]:
			if not st.has(key):
				st[key] = _new_skill()[key]
		var xp_v: Variant = st.xp
		st["xp"] = float(xp_v) if (xp_v is int or xp_v is float) and is_finite(float(xp_v)) and float(xp_v) >= 0.0 else 0.0
		var cap_l := level_cap(sid)
		st["level"] = clampi(int(st.level), 1, maxi(1, cap_l))        # F5: livelli negativi o oltre il tetto
		st["record_level"] = clampi(maxi(int(st.record_level), int(st.level)), 1, maxi(1, cap_l))
	if not (ctx.state.get("mastery") is Dictionary):
		ctx.state["mastery"] = {}
	_mastery = ctx.state["mastery"]
	if not (ctx.state.get("activity") is Dictionary):
		ctx.state["activity"] = {}
	_activity = ctx.state["activity"]
	if _activity.get("type", "") == "skill" and not ctx.data.has_action(str(_activity.get("action", ""))):
		_activity.clear()
	_cache.clear()
	_refresh_perks()
	refresh_tools()


func _new_skill() -> Dictionary:
	return {"xp": 0.0, "level": 1, "record_level": 1, "stars": 0, "perks": {}}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["*.level", "*.record_level", "*.stars"])


func _invalidate() -> void:
	_cache.clear()


# ------------------------------------------------------------------ letture

func level(skill_id: String) -> int:
	return int(state.get(skill_id, {}).get("level", 1))


func xp(skill_id: String) -> float:
	return float(state.get(skill_id, {}).get("xp", 0.0))


func record_level(skill_id: String) -> int:
	return int(state.get(skill_id, {}).get("record_level", 1))


func level_cap(skill_id: String) -> int:
	return int(_skill_defs.get(skill_id, {}).get("level_cap", ctx.constants().level_cap))


## [XP nel livello corrente, XP necessari per il successivo]; il secondo è 0 al livello massimo.
func xp_progress(skill_id: String) -> Array:
	var l := level(skill_id)
	if l >= level_cap(skill_id):
		return [0.0, 0.0]
	return [xp(skill_id) - float(_xp_cum[l]), float(_xp_cum[l + 1]) - float(_xp_cum[l])]


func mastery_level(action_id: String) -> int:
	return int(_mastery.get(action_id, {}).get("level", 1))


func mastery_xp(action_id: String) -> float:
	return float(_mastery.get(action_id, {}).get("xp", 0.0))


func mastery_cap() -> int:
	return int(ctx.constants().mastery.cap)


## [XP nel livello di maestria corrente, XP per il successivo]; 0 al massimo.
func mastery_progress(action_id: String) -> Array:
	var m := mastery_level(action_id)
	if m >= mastery_cap():
		return [0.0, 0.0]
	return [mastery_xp(action_id) - float(_m_cum[m]), float(_m_cum[m + 1]) - float(_m_cum[m])]


func current_action() -> String:
	_sync_activity()
	return str(_activity.get("action", "")) if _activity.get("type", "") == "skill" else ""


## L'attività è UNA sola (R-AZ-1): se un altro sistema ha sostituito il Dictionary in ctx.state.activity,
## si riaggancia quello vivo (altrimenti due attività girerebbero insieme).
func _sync_activity() -> void:
	var a: Variant = ctx.state.get("activity")
	if a is Dictionary and not is_same(a, _activity):
		_activity = a


func is_active() -> bool:
	return not current_action().is_empty()


func skill_of(action_id: String) -> String:
	return str(ctx.data.action(action_id).get("skill", ""))


## Frazione 0..1 del ciclo in corso (per la barra di avanzamento).
func cycle_fraction() -> float:
	var aid := current_action()
	if aid.is_empty():
		return 0.0
	return clampf(float(_activity.get("progress_s", 0.0)) / _cycle_duration(aid), 0.0, 1.0)


func stun_remaining() -> float:
	return float(_activity.get("stun_s", 0.0))


func is_unlocked(skill_id: String) -> bool:
	return ctx.state.get("unlocks", []).has("skill:" + skill_id)


# ------------------------------------------------------------------ avvio / arresto

## "" se l'azione si può avviare, altrimenti la chiave della ragione (UI_SKILLS_REASON_*).
func can_start(action_id: String) -> String:
	var a: Dictionary = ctx.data.action(action_id)
	if a.is_empty():
		return "UI_SKILLS_REASON_UNKNOWN"
	if str(a.get("kind", "")) in ["crop", "tree"]:
		return "UI_SKILLS_REASON_FARMING"
	if level(str(a.skill)) < int(a.get("level_req", 1)):
		return "UI_SKILLS_REASON_LEVEL"
	if not _has_inputs(a):
		return "UI_SKILLS_REASON_MATERIALS"
	return NO_REASON


## Imposta l'attività (sostituisce qualunque altra). Il progresso riparte da zero.
func start(action_id: String) -> bool:
	if can_start(action_id) != NO_REASON:
		return false
	_sync_activity()
	_activity.clear()
	_activity["type"] = "skill"
	_activity["action"] = action_id
	_activity["progress_s"] = 0.0
	_roll_duration_mult(action_id)
	refresh_tools()
	_cache.clear()
	return true


func stop() -> void:
	_sync_activity()
	if _activity.get("type", "") == "skill":
		_activity.clear()


## PRESTIGIO (chiamata SOLO da PrestigeSystem, docs/13 §2): conferisce una Stella e riporta la mansione a livello 1
## (XP 0, talenti azzerati; maestrie, oggetti e record_level restano: il record alimenta l'Eco). Se l'attività in corso
## è di questa mansione e a livello 1 non si può più svolgere, si ferma. Ritorna le Stelle dopo il reset (0 = rifiutato).
func reset_for_star(skill_id: String) -> int:
	if not state.has(skill_id):
		return 0
	var st: Dictionary = state[skill_id]
	st["stars"] = int(st.stars) + 1
	st["record_level"] = maxi(int(st.record_level), int(st.level))
	st["level"] = 1
	st["xp"] = 0.0
	st["perks"] = {}
	_cache.clear()
	_refresh_perks()
	refresh_tools()
	var aid := current_action()
	if not aid.is_empty() and skill_of(aid) == skill_id and can_start(aid) != NO_REASON:
		stop()
	return int(st.stars)


## Morte permanente (modalità Estrema, docs/05 §7): la mansione torna al livello 1 con 0 XP e senza talenti scelti.
## Stelle e livello record RESTANO (sono prestigio, non progresso del salvataggio corrente: l'Eco rende la risalita
## più breve). Ritorna il livello perso (0 se la mansione non esiste o era già al 1).
func reset_level(skill_id: String) -> int:
	if not state.has(skill_id):
		return 0
	var st: Dictionary = state[skill_id]
	var lost := int(st.level) - 1
	st["level"] = 1
	st["xp"] = 0.0
	st["perks"] = {}
	_cache.clear()
	_refresh_perks()
	refresh_tools()
	return maxi(0, lost)


# ------------------------------------------------------------------ XP e livelli

## XP grezzi alla mansione (il combattimento li usa per le mansioni di combattimento). Con apply_bonus si applicano
## skill_xp_pct e l'Eco; di base la quantità è già finale.
func add_xp(skill_id: String, amount: float, apply_bonus: bool = false) -> void:
	if not state.has(skill_id) or not is_finite(amount) or amount <= 0.0:
		return
	var a := amount
	if apply_bonus:
		a = _mod(a, "skill_xp_pct", _scopes(skill_id), 0.0) * Formulas.echo_multiplier(level(skill_id), record_level(skill_id))
	_grant_xp(skill_id, a)


## XP che darebbe un Tomo usato adesso sulla mansione (R-QU-4: mult × xph(tier del livello attuale) × frazione).
func tome_xp(item_id: String, skill_id: String) -> float:
	var tome: Dictionary = ctx.data.item(item_id).get("tome", {})
	if tome.is_empty() or not state.has(skill_id):
		return 0.0
	var base := float(tome.get("mult", 0.0)) * Formulas.xph(Formulas.tier_of_level(level(skill_id))) * float(tome.get("xph_frac", 0.0))
	var v := ctx.modifiers.apply(base, "xp_tome_pct", [])       # G13: Biblioteca (Costellazione del Custode)
	var cap_levels := int(tome.get("hero_max_levels", 0)) if skill_id == "hero" else 0     # QA1: 4 Tomi accumulati portavano l'Eroe da 26 a 47 in un istante
	if cap_levels > 0:
		v = minf(v, maxf(0.0, float(Formulas.xp_total_for_level(level(skill_id) + cap_levels)) - xp(skill_id)))
	return v


## Vero se l'azione forgia una chiave (un prodotto di categoria "key"): lì vale key_craft_save_pct.
func _forges_key(a: Dictionary) -> bool:
	for o in a.get("outputs", []):
		if str(ctx.data.item(str(o.get("item", ""))).get("category", "")) == "key":
			return true
	return false


## Usa un Tomo dell'Esperienza (missioni, commesse) su una mansione sbloccata. false se non si può.
func use_tome(item_id: String, skill_id: String) -> bool:
	var b := _bank()
	var xp_amount := tome_xp(item_id, skill_id)
	if b == null or xp_amount <= 0.0 or not is_unlocked(skill_id) or not bool(b.remove(item_id, 1)):
		return false
	_grant_xp(skill_id, xp_amount)
	ctx.events.important_event.emit("tome")
	return true


func _grant_xp(skill_id: String, amount: float) -> void:
	var st: Dictionary = state[skill_id]
	st["xp"] = float(st.xp) + amount
	ctx.events.xp_gained.emit(skill_id, amount)
	var cap := level_cap(skill_id)
	var lv := int(st.level)
	var changed := false
	while lv < cap and float(st.xp) >= float(_xp_cum[lv + 1]) - 1e-9:
		lv += 1
		changed = true
		st["level"] = lv
		st["record_level"] = maxi(int(st.record_level), lv)
		ctx.events.level_up.emit(skill_id, lv)
	if changed:
		_cache.clear()
		refresh_tools()


func _grant_mastery(action_id: String, amount: float) -> void:
	var m: Dictionary = _mastery.get(action_id, {})
	if m.is_empty():
		m = {"xp": 0.0, "level": 1}
		_mastery[action_id] = m
	var cap := mastery_cap()
	if int(m.level) >= cap:
		return
	m["xp"] = float(m.xp) + amount
	var lv := int(m.level)
	while lv < cap and float(m.xp) >= float(_m_cum[lv + 1]) - 1e-9:
		lv += 1
	if lv != int(m.level):
		m["level"] = lv
		_cache.clear()


# ------------------------------------------------------------------ maestria: bonus per azione

## Traguardi raggiunti: somma per chiave (constants.mastery.milestones), es. {"action_haste_pct": 15.0}.
func mastery_milestone_totals(m_level: int) -> Dictionary:
	var out := {}
	var ms: Dictionary = ctx.constants().mastery.milestones
	for lv_str in ms:
		if m_level >= int(lv_str):
			var key: String = ms[lv_str].key
			out[key] = float(out.get(key, 0.0)) + float(ms[lv_str].value)
	return out


func mastery_double_pct(m_level: int) -> float:
	return float(ctx.constants().mastery.double_per_level_pct) * float(m_level)


# ------------------------------------------------------------------ profilo di un'azione

func _scopes(skill_id: String) -> Array:
	return [skill_id, str(_skill_defs.get(skill_id, {}).get("group", "")), "all", "current"]


## base × (1 + (Σadd + extra_add)/100) × Π more (regola unica di docs/14 §2).
func _mod(base: float, key: String, scopes: Array, extra_add: float) -> float:
	return base * (1.0 + (ctx.modifiers.total_add(key, scopes) + extra_add) / 100.0) * ctx.modifiers.total_more(key, scopes)


func _roll_duration_mult(action_id: String) -> void:
	var v := float(ctx.data.action(action_id).get("time_variance", 0.0))
	_activity["dur_mult"] = 1.0 + ctx.rng.randf_range("world", -v, v) if v > 0.0 else 1.0


func _cycle_duration(action_id: String) -> float:
	return maxf(0.05, float(_profile(action_id).duration_s) * float(_activity.get("dur_mult", 1.0)))


## Tutti i numeri derivati di un'azione con lo stato corrente (livello, maestria, modificatori). Messo in cache.
## La voce in cache ricorda livello e maestria con cui è stata calcolata: se lo stato cambia da fuori
## (salvataggio caricato, Prestigio, strumenti di debug) si ricalcola senza aspettare un segnale dei modificatori.
func _profile(action_id: String) -> Dictionary:
	var a: Dictionary = ctx.data.action(action_id)
	var hit: Variant = _cache.get(action_id)
	if hit != null and int(hit.get("_lv", -1)) == level(str(a.get("skill", ""))) \
			and int(hit.get("_ml", -1)) == mastery_level(action_id):
		return hit
	var sk: String = a.skill
	var sc := _scopes(sk)
	var lv := level(sk)
	var ml := mastery_level(action_id)
	var mm := mastery_milestone_totals(ml)
	var mastered := mm.has("action_mastered")
	var kc := ctx.constants()
	var p := {}
	var base_t := float(a.get("time_s", 0.0))
	var haste := _mod(1.0, "skill_haste_pct", sc, float(mm.get("action_haste_pct", 0.0)))
	p["duration_s"] = base_t / maxf(0.01, haste)
	var xp_mult := _mod(1.0, "skill_xp_pct", sc, 0.0) * (1.0 + float(mm.get("action_xp_pct", 0.0)) / 100.0) \
		* Formulas.echo_multiplier(lv, record_level(sk))
	p["xp"] = float(a.get("xp", 0.0)) * xp_mult
	p["mastery_xp"] = float(a.get("mastery_xp", 0.0)) * _mod(1.0, "mastery_xp_pct", [], 0.0)
	p["double_pct"] = maxf(0.0, ctx.modifiers.total_add("skill_double_pct", sc) + mastery_double_pct(ml))
	var save := ctx.modifiers.total_add("skill_save_pct", sc)
	if mastered and a.has("inputs"):
		save += float(kc.mastery.mastered_save_pct)
	if a.has("inputs") and _forges_key(a):        # G13: Forgia Fortunata, Stelle di Forgiachiavi, Lima, Portachiavi
		save += minf(ctx.modifiers.total_add("key_craft_save_pct"), ctx.modifiers.cap_of("key_craft_save_pct"))
	p["save_pct"] = minf(save, ctx.modifiers.cap_of("skill_save_pct"))
	p["secondary_mult"] = _mod(1.0, "skill_secondary_pct", sc, float(mm.get("action_secondary_pct", 0.0)))
	p["extra_yield"] = int(kc.mastery.mastered_extra_yield) if (mastered and not a.has("inputs") and a.has("outputs")) else 0
	p["success"] = 1.0
	p["stun_s"] = 0.0
	if a.has("success"):
		var s: Dictionary = a.success
		var d := float(maxi(0, lv - int(a.get("level_req", 1))))
		var sp := float(s.base) + float(s.per_level_above) * d + float(s.per_mastery) * float(ml) \
			+ ctx.modifiers.total_add("thievery_success_pct", []) / 100.0
		p["success"] = clampf(sp, 0.0, float(s.max))
		p["stun_s"] = float(a.get("stun_s", 0.0)) * maxf(0.0, 1.0 - ctx.modifiers.total_add_capped("thievery_stun_reduction_pct") / 100.0)
	p["burn"] = 0.0
	if a.has("burn"):
		var b: Dictionary = a.burn
		var d2 := float(maxi(0, lv - int(a.get("level_req", 1))))
		p["burn"] = clampf(float(b.base) - float(b.per_level) * d2 - float(b.per_mastery) * float(ml), float(b.get("min", 0.0)), 1.0)
	p["cycle_s"] = float(p.duration_s) + (1.0 - float(p.success)) * float(p.stun_s)
	# casse: la probabilità dei dati è riferita alla durata base; conta il TEMPO effettivo (docs/04 §9)
	var crate_p := 0.0
	var crate: Variant = a.get("crate")
	if crate is Dictionary and base_t > 0.0:
		var find := ctx.modifiers.total_add_capped("crate_find_pct", sc)
		crate_p = float(crate.chance) * (float(p.duration_s) / base_t) * (1.0 + find / 100.0) * ctx.modifiers.total_more("crate_find_pct", sc)
	p["crate_p"] = crate_p
	var pet_p := 0.0
	if _pet_by_skill.has(sk):
		pet_p = float(p.duration_s) / float(_pet_by_skill[sk].div) * (1.0 + float(lv) / 100.0)
		pet_p *= 1.0 + ctx.modifiers.total_add("pet_chance_pct", sc) / 100.0
	p["pet_p"] = pet_p
	p["quality"] = []
	if a.get("quality", false):
		var q: Array = Formulas.quality_chances(lv - int(a.get("level_req", 1)), ml)
		var boost := _mod(1.0, "craft_quality_pct", sc, 0.0)
		var fine := float(q[1]) * boost
		var exc := float(q[2]) * boost
		var mas := float(q[3]) * boost
		p["quality"] = [maxf(0.0, 1.0 - fine - exc - mas), fine, exc, mas]
	p["_lv"] = lv
	p["_ml"] = ml
	_cache[action_id] = p
	if kc.is_empty():
		push_warning("SkillSystem: costanti non configurate")
	return p


## Numero di copie dei prodotti con la regola del doppio (oltre il 100%: garantito + probabilità, docs/14 §3).
func _roll_copies(double_pct: float) -> int:
	var guaranteed := int(floor(double_pct / 100.0))
	var rest := double_pct / 100.0 - float(guaranteed)
	return 1 + guaranteed + (1 if ctx.rng.chance("loot", rest) else 0)


func _qty_roll(q: Variant) -> int:
	if q is Array:
		return ctx.rng.randi_range("loot", int(q[0]), int(q[1]))
	return int(q)


func _qty_mean(q: Variant) -> float:
	if q is Array:
		return (float(q[0]) + float(q[1])) / 2.0
	return float(q)


# ------------------------------------------------------------------ bank (solo firme del contratto)

func _bank() -> Object:
	return ctx.get_system("bank")


func _bank_count(item: String) -> int:
	var b := _bank()
	return int(b.count(item)) if b != null else 1000000000


func _has_inputs(a: Dictionary) -> bool:
	for io in a.get("inputs", []):
		if _bank_count(str(io.item)) < int(io.qty):
			return false
	return true


func _bank_add(item: String, qty: int, source: String) -> int:
	var b := _bank()
	if b == null or qty <= 0:
		return qty if b == null else 0
	var got := int(b.add(item, qty, source))
	_note_special(item, "normal", got)
	return got


## Aggiunge un oggetto in base alla sua natura: impilabile → add; istanza → add_instance (qualità data).
func _bank_give(item: String, qty: int, quality: String, source: String) -> int:
	var b := _bank()
	if b == null or qty <= 0:
		return qty if b == null else 0
	var def: Dictionary = ctx.data.item(item)
	if def.get("stackable", true):
		var got := int(b.add(item, qty, source))
		_note_special(item, "normal", got)
		return got
	var done := 0
	for i in qty:
		var uid: String = b.add_instance({"def": item, "quality": quality, "sockets": [], "rank": 0, "locked": false})
		if uid.is_empty():
			break
		done += 1
	_note_special(item, quality, done)
	return done        # item_gained lo emette il bank (proprietario degli oggetti)


## Eventi per imprese e missioni (Compendio): piatti bruciati (`burnt`) e pezzi di qualità (`craft_quality`,
## es. Capolavoro). Anche dall'offline analitico, una sola emissione per blocco.
func _note_special(item: String, quality: String, n: int) -> void:
	if n <= 0:
		return
	if item == "burnt_food":
		ctx.events.objective_event.emit("burnt", {"qty": n})
	if quality != "normal" and not quality.is_empty():
		ctx.events.objective_event.emit("craft_quality", {"quality": quality, "qty": n})


func _stop_with(reason_key: String) -> void:
	_activity.clear()
	if _queue_running():
		_queue().pause()
	ctx.events.notice.emit("warning", tr(reason_key), {"reason": reason_key, "section": "skills"})


## «Una costruzione per volta» (dati: `single_craft`): equipaggiamento e attrezzi non si ripetono da soli, nemmeno con
## la coda o l'Automazione. Dopo UNA costruzione l'attività si ferma e il Registro lo dice.
func is_single_craft(action_id: String) -> bool:
	return bool(ctx.data.action(action_id).get("single_craft", false))


## Ferma l'attività dopo una costruzione singola (nessuna pausa della coda: la coda passa da sé alla voce successiva).
func _stop_single(aid: String) -> void:
	_activity.clear()
	ctx.events.notice.emit("success", Loc.tf("UI_SKILLS_SINGLE_DONE", {"name": Loc.t(ctx.data.action(aid).get("name", aid))}),
		{"reason": "single_done", "action": aid, "section": "skills"})


## Ingredienti finiti: con l'automazione l'attività resta in attesa (nessuna uscita), altrimenti si ferma con avviso.
## Con una coda in esecuzione l'attesa non serve: la coda passa alla voce successiva.
func _stop_materials(aid: String) -> void:
	if can_automate(aid) and not _queue_running():
		_activity["waiting"] = "materials"
		_activity["progress_s"] = 0.0
		ctx.events.notice.emit("info", tr("UI_SKILLS_WAITING_MATERIALS"), {"reason": "waiting", "section": "skills"})
		return
	if _queue_running():
		_activity.clear()          # la coda segnala da sé il salto
		return
	_stop_with("UI_SKILLS_STOP_MATERIALS")


## Automazione (R-AZ-4): Stelle nella mansione oppure azione padroneggiata (Padronanza, maestria 50).
func can_automate(action_id: String) -> bool:
	var a: Dictionary = ctx.data.action(action_id)
	if a.is_empty():
		return false
	if int(state.get(str(a.skill), {}).get("stars", 0)) >= int(ctx.constants().automation.stars):
		return true
	return is_mastered(action_id)


## Padronanza: l'azione ha raggiunto il traguardo `action_mastered` della maestria.
func is_mastered(action_id: String) -> bool:
	return mastery_milestone_totals(mastery_level(action_id)).has("action_mastered")


## true se l'attività è in attesa di ingredienti (automazione).
func is_waiting() -> bool:
	return _activity.get("type", "") == "skill" and _activity.has("waiting")


func _queue() -> Object:
	return ctx.get_system("queue")


func _queue_running() -> bool:
	var q := _queue()
	return q != null and q.is_running()


## Dopo ogni ciclo: la coda conta i completamenti. true se ha cambiato/chiuso l'attività.
func _notify_queue(aid: String) -> bool:
	var q := _queue()
	if q == null or not q.is_running():
		return false
	return q.on_cycle(aid, _last_success)


func _potions() -> Object:
	return ctx.get_system("potions")


# ------------------------------------------------------------------ tick

func tick(dt: float) -> void:
	_sync_activity()
	if _activity.get("type", "") != "skill":
		return
	var aid := str(_activity.get("action", ""))
	if not ctx.data.has_action(aid):
		_activity.clear()
		return
	if _activity.has("waiting"):          # automazione: riparte da sola quando tornano gli ingredienti
		if not _has_inputs(ctx.data.action(aid)):
			return
		_activity.erase("waiting")
		_activity["progress_s"] = 0.0
	var t := dt
	var stun := float(_activity.get("stun_s", 0.0))
	if stun > 0.0:
		var used := minf(stun, t)
		stun -= used
		t -= used
		if stun <= LIMITS.tick_epsilon:
			_activity.erase("stun_s")
		else:
			_activity["stun_s"] = stun
	if t <= 0.0:
		return
	_activity["progress_s"] = float(_activity.get("progress_s", 0.0)) + t
	var guard := 0
	while guard < int(LIMITS.max_cycles_per_tick):
		guard += 1
		var dur := _cycle_duration(aid)
		var prog := float(_activity.get("progress_s", 0.0))
		if prog + LIMITS.tick_epsilon < dur:
			break
		_activity["progress_s"] = maxf(0.0, prog - dur)
		var ok := _complete(aid)
		if not ok or _activity.get("type", "") != "skill":
			break
		if _notify_queue(aid):               # la coda ha cambiato (o chiuso) l'attività in corso
			break
		if _last_success and is_single_craft(aid):       # «una costruzione per volta»: niente ripetizione automatica
			_stop_single(aid)
			break
		_roll_duration_mult(aid)
		var st := float(_activity.get("stun_s", 0.0))
		if st > 0.0:       # lo stordimento consuma subito l'eventuale avanzo di tempo
			var left := float(_activity.progress_s)
			var use := minf(st, left)
			_activity["progress_s"] = left - use
			st -= use
			if st <= LIMITS.tick_epsilon:
				_activity.erase("stun_s")
			else:
				_activity["stun_s"] = st
				break


## Risolve un ciclo completato. Ritorna false se l'attività si è fermata.
func _complete(aid: String) -> bool:
	var a: Dictionary = ctx.data.action(aid)
	var sk: String = a.skill
	var p := _profile(aid)
	var src := "skill:" + sk
	var inputs: Array = a.get("inputs", [])
	_last_success = false
	if not _has_inputs(a):
		_stop_materials(aid)
		return false
	var consume := not inputs.is_empty() and not ctx.rng.chance("loot", float(p.save_pct) / 100.0)
	var success := true
	if a.has("success"):
		success = ctx.rng.chance("loot", float(p.success))
		if not success:
			_activity["stun_s"] = float(p.stun_s)
	var outs: Array = []
	if success:
		var burned := float(p.burn) > 0.0 and ctx.rng.chance("loot", float(p.burn))
		var copies := _roll_copies(float(p.double_pct))
		var first := true
		for o in a.get("outputs", []):
			var base_q := _qty_roll(o.qty)
			var item: String = o.item
			var n := base_q * copies + int(p.extra_yield)
			if burned:
				item = "burnt_food"
				n = base_q
			var added := 0
			var qc: Array = p.quality
			if not qc.is_empty() and not burned:
				n = base_q * copies
				for i in n:
					added += _bank_give(item, 1, _roll_quality(qc), src)
			else:
				added = _bank_give(item, n, "normal", src)
			if first and added <= 0 and n > 0:
				_stop_with("UI_SKILLS_STOP_BANK_FULL")
				return false
			first = false
			outs.append({"item": item, "qty": added})
		for sec in a.get("secondary", []):
			_roll_secondary(sec, float(sec.chance) * float(p.secondary_mult), src, outs)
		for dr in a.get("drops", []):
			_roll_secondary(dr, float(dr.chance), src, outs)
		if a.has("gold"):
			var gold := ctx.rng.randi_range("loot", int(a.gold[0]), int(a.gold[1]))
			gold = int(round(_mod(float(gold), "gold_gain_pct", [sk, "all"], 0.0)))
			var b := _bank()
			if b != null and gold > 0:
				b.add_gold(gold)
			outs.append({"item": "gold", "qty": gold})
	if consume:
		var b2 := _bank()
		if b2 != null:
			for io in inputs:
				b2.remove(str(io.item), int(io.qty))
	if success:
		if ctx.rng.chance("loot", float(p.crate_p)):
			ctx.events.crate_found.emit(str(a.crate.id), src)
		if float(p.pet_p) > 0.0:
			_roll_pet(sk, float(p.pet_p))
		_grant_xp(sk, float(p.xp))
		_grant_mastery(aid, float(p.mastery_xp))
		ctx.events.action_completed.emit(aid, outs)
		_last_success = true
		var pot := _potions()
		if pot != null:
			pot.on_skill_action(sk)
	return true


func _roll_quality(weights: Array) -> String:
	var ids: Array = ctx.constants().quality
	var idx := ctx.rng.weighted_index("loot", weights)
	return str(ids[maxi(0, idx)].id)


func _roll_secondary(sec: Dictionary, chance: float, src: String, outs: Array) -> void:
	if not ctx.rng.chance("loot", minf(1.0, chance)):
		return
	var item: String = str(sec.get("item", ""))
	if sec.has("pick"):
		var ws: Array = []
		for pk in sec.pick:
			ws.append(pk.weight)
		var idx := ctx.rng.weighted_index("loot", ws)
		if idx < 0:
			return
		item = str(sec.pick[idx].item)
	var n := _qty_roll(sec.get("qty", 1))
	var added := _bank_give(item, n, "normal", src)
	if added > 0:
		outs.append({"item": item, "qty": added})


func _roll_pet(skill_id: String, prob: float) -> void:
	var pet: String = _pet_by_skill[skill_id].id
	if ctx.state.get("pets", []).has(pet):
		return
	if ctx.rng.chance("loot", prob):
		ctx.events.pet_found.emit(pet)


# ------------------------------------------------------------------ resa attesa (UI e offline)

## Valori attesi PER CICLO COMPLETATO con lo stato corrente:
## {"items": {item: float}, "rare": {item: float}, "inst": {item: [pesi qualità]}, "consume": {item: float},
##  "gold": float, "crate": float, "pet": float, "xp": float, "mastery_xp": float, "cycle_s": float}
## "items" sono i prodotti principali (attesa esatta), "rare" secondari/drop (si estraggono a Poisson offline).
func expected_per_cycle(aid: String) -> Dictionary:
	if not ctx.data.has_action(aid):
		return {}
	var a: Dictionary = ctx.data.action(aid)
	var p := _profile(aid)
	var succ := float(p.success)
	var out := {"items": {}, "rare": {}, "inst": {}, "consume": {}, "gold": 0.0, "crate": 0.0, "pet": 0.0,
		"xp": 0.0, "mastery_xp": 0.0, "cycle_s": float(p.cycle_s), "crate_id": str(a.get("crate", {}).get("id", "")), "success": succ}
	var copies := 1.0 + float(p.double_pct) / 100.0
	var burn := float(p.burn)
	for o in a.get("outputs", []):
		var q := _qty_mean(o.qty)
		var good := succ * (1.0 - burn) * (q * copies + float(p.extra_yield))
		var def: Dictionary = ctx.data.item(str(o.item))
		var qc: Array = p.quality
		if not qc.is_empty() or not def.get("stackable", true):
			var w: Array = qc if not qc.is_empty() else [1.0, 0.0, 0.0, 0.0]
			out.inst[o.item] = {"n": succ * (1.0 - burn) * q * copies, "w": w}
		else:
			out.items[o.item] = float(out.items.get(o.item, 0.0)) + good
		if burn > 0.0:
			out.items["burnt_food"] = float(out.items.get("burnt_food", 0.0)) + succ * burn * q
	for sec in a.get("secondary", []) + a.get("drops", []):
		var c := minf(1.0, float(sec.chance) * (float(p.secondary_mult) if a.has("secondary") else 1.0))
		var q2 := _qty_mean(sec.get("qty", 1))
		if sec.has("pick"):
			var tw := 0.0
			for pk in sec.pick:
				tw += float(pk.weight)
			for pk in sec.pick:
				out.rare[pk.item] = float(out.rare.get(pk.item, 0.0)) + succ * c * q2 * float(pk.weight) / tw
		else:
			out.rare[sec.item] = float(out.rare.get(sec.item, 0.0)) + succ * c * q2
	for io in a.get("inputs", []):
		out.consume[io.item] = float(io.qty) * (1.0 - float(p.save_pct) / 100.0)
	if a.has("gold"):
		out.gold = succ * _mod(_qty_mean(a.gold), "gold_gain_pct", [a.skill, "all"], 0.0)
	out.crate = succ * float(p.crate_p)
	out.pet = succ * float(p.pet_p)
	out.xp = succ * float(p.xp)
	out.mastery_xp = succ * float(p.mastery_xp)
	return out


## Per l'interfaccia: valori attesi all'ora dell'azione (ignora la disponibilità degli ingredienti).
func hourly(aid: String) -> Dictionary:
	if not ctx.data.has_action(aid):
		return {}
	var e := expected_per_cycle(aid)
	if e.is_empty():
		return {}
	var per_h := 3600.0 / maxf(0.05, float(e.cycle_s))
	var items := {}
	for k in e["items"]:
		items[k] = float(e["items"][k]) * per_h
	for k in e["inst"]:
		items[k] = float(items.get(k, 0.0)) + float(e["inst"][k].n) * per_h
	return {"cycles": per_h, "xp": float(e.xp) * per_h, "items": items, "gold": float(e.gold) * per_h,
		"crates": float(e.crate) * per_h, "cycle_s": float(e.cycle_s)}


## Durata effettiva (dopo velocità e maestria) del ciclo, in secondi.
func duration_of(aid: String) -> float:
	if not ctx.data.has_action(aid):
		return 0.0                    # F8: azione sconosciuta -> valore neutro
	return float(_profile(aid).duration_s)


func profile_of(aid: String) -> Dictionary:
	if not ctx.data.has_action(aid):
		return {}
	return _profile(aid)


# ------------------------------------------------------------------ offline analitico (R-OFF-3, spike S4)

## Forma chiusa a segmenti: i parametri restano costanti fino al prossimo evento (livello mansione, livello di
## maestria, fine ingredienti, fine di una pozione o di un banchetto, fine della voce di coda); dentro ogni segmento
## i valori attesi sono n_cicli × atteso_per_ciclo.
## Prodotti principali = attesa (frazione arrotondata a caso); secondari/casse/famigli = estrazioni di Poisson
## con il flusso RNG "loot" (estrazioni vere, non valori attesi). Costo: O(livelli + livelli di maestria + voci di coda).
## Con una coda in esecuzione le voci si susseguono nello stesso tempo offline: il resoconto della prima è il
## risultato, le successive stanno in "chain". Il tempo dei banchetti scorre qui dentro (BuffSystem.advance_offline).
func simulate_offline(seconds: float) -> Dictionary:
	_sync_activity()
	if _activity.get("type", "") != "skill" or seconds <= 0.0:
		return {}
	if _activity.has("waiting"):
		var wa: Dictionary = ctx.data.action(str(_activity.get("action", "")))
		if wa.is_empty() or not _has_inputs(wa):
			return {}
		_activity.erase("waiting")
	var off: Dictionary = ctx.constants().get("offline", {})
	var cap_s := float(off.get("cap_max_h", 24)) * 3600.0
	var eff := maxf(0.0001, (float(off.get("efficiency_pct", 100)) + ctx.modifiers.total_add("offline_efficiency_pct", [])) / 100.0)
	var t_left := minf(seconds, cap_s) * eff
	var report_seconds := t_left
	var reports: Array = []
	var guard := 0
	while t_left > 1e-9 and _activity.get("type", "") == "skill" and guard < 64:
		guard += 1
		var aid := str(_activity.get("action", ""))
		if not ctx.data.has_action(aid):
			break
		var q := _queue()
		var in_queue: bool = q != null and q.is_running()
		var cond: Dictionary = q.offline_cond(aid) if in_queue else {}
		in_queue = in_queue and not cond.is_empty()
		var r := _offline_action(aid, t_left, eff, cond)
		reports.append(r.report)
		t_left -= float(r.used)
		var stopped := str(r.stopped)
		if in_queue:
			if stopped == "bank_full":
				q.pause()
				_stop_with("UI_SKILLS_STOP_BANK_FULL")
				break
			q.offline_commit(aid, float(r.cycles), float(r.used), bool(r.cond_met) or stopped == "no_materials" or stopped == "single")
			if not bool(r.cond_met) and stopped != "no_materials" and stopped != "single":
				break
			continue
		if stopped == "bank_full":
			_stop_with("UI_SKILLS_STOP_BANK_FULL")
		elif stopped == "no_materials":
			_stop_materials(aid)
		elif stopped == "single":
			_stop_single(aid)
		break
	if reports.is_empty():
		return {}
	var out: Dictionary = reports[0]
	if reports.size() == 1:
		out["seconds"] = report_seconds
	else:
		out["chain"] = reports.slice(1)
	return out


## Un'azione per un tempo `t_avail` (già scalato dall'efficienza). `cond` (dalla coda): max_n (cicli), until_level,
## max_s (secondi). Ritorna {"report", "used" (s), "cycles", "stopped", "cond_met"}.
func _offline_action(aid: String, t_avail: float, eff: float, cond: Dictionary) -> Dictionary:
	var a: Dictionary = ctx.data.action(aid)
	var sk: String = a.skill
	var t_left := t_avail
	var time_capped := false
	if cond.has("max_s") and float(cond.max_s) < t_left:
		t_left = maxf(0.0, float(cond.max_s))
		time_capped = true
	var t_start := t_left
	var carry := float(_activity.get("progress_s", 0.0))
	_activity.erase("stun_s")
	var lv_from := level(sk)
	var tot_n := 0.0
	var tot_xp := 0.0
	var items: Dictionary = {}       # main
	var rare: Dictionary = {}        # lambda
	var inst: Dictionary = {}        # item -> [n per qualità]
	var consume: Dictionary = {}
	var gold := 0.0
	var crates := 0.0
	var crate_id := ""
	var pet_l := 0.0
	var stopped := ""
	var single_done := false
	var segments := 0
	var last_frac := 0.0
	var pot := _potions()
	var pot_slot: String = str(pot.slot_for_skill(sk)) if pot != null else ""
	var bf := ctx.get_system("buffs")
	while t_left > 1e-9 and segments < 100000:
		segments += 1
		var e := expected_per_cycle(aid)
		var cyc := maxf(0.05, float(e.cycle_s))
		var n_avail := (t_left + carry) / cyc
		var n := n_avail
		var limit := "time"
		# livello mansione
		if float(e.xp) > 0.0 and level(sk) < level_cap(sk):
			var need := (float(_xp_cum[level(sk) + 1]) - xp(sk)) / float(e.xp) + 1e-7
			if need < n:
				n = need
				limit = "level"
		# livello di maestria
		if float(e.mastery_xp) > 0.0 and mastery_level(aid) < mastery_cap():
			var mneed := (float(_m_cum[mastery_level(aid) + 1]) - mastery_xp(aid)) / float(e.mastery_xp) + 1e-7
			if mneed < n:
				n = mneed
				limit = "mastery"
		# ingredienti
		for k in e.consume:
			var per := float(e.consume[k])
			if per > 0.0:
				var have := float(_bank_count(k)) - float(consume.get(k, 0.0))
				var mn := maxf(0.0, have) / per
				if mn < n:
					n = mn
					limit = "materials"
		# coda: cicli o livello da raggiungere
		if cond.has("max_n"):
			var rem := float(cond.max_n) - tot_n
			if rem < n:
				n = maxf(0.0, rem)
				limit = "queue"
		if cond.has("until_level") and float(e.xp) > 0.0 and level(sk) < int(cond.until_level):
			var lneed := (float(_xp_cum[int(cond.until_level)]) - xp(sk)) / float(e.xp) + 1e-7
			if lneed < n:
				n = lneed
				limit = "queue"
		# pozione: le cariche finiscono a metà (poi i parametri cambiano)
		if not pot_slot.is_empty():
			var ch := int(pot.charges(pot_slot))
			if ch > 0 and float(ch) < n:
				n = float(ch)
				limit = "potion"
		# banchetti e altri effetti a tempo: scadono a metà
		if bf != null:
			var soon := float(bf.soonest_remaining())
			if soon > 0.0 and soon * eff < n * cyc - carry:
				n = (soon * eff + carry) / cyc
				limit = "buff"
		if is_single_craft(aid) and n > 1.0:       # una sola costruzione per azione, anche offline
			n = 1.0
			limit = "single"
		n = maxf(0.0, n)
		tot_n += n
		for k in e["items"]:
			items[k] = float(items.get(k, 0.0)) + n * float(e["items"][k])
		for k in e["rare"]:
			rare[k] = float(rare.get(k, 0.0)) + n * float(e["rare"][k])
		for k in e["inst"]:
			var cur: Array = inst.get(k, [0.0, 0.0, 0.0, 0.0])
			for qi in 4:
				cur[qi] = float(cur[qi]) + n * float(e["inst"][k].n) * float(e["inst"][k].w[qi])
			inst[k] = cur
		for k in e.consume:
			consume[k] = float(consume.get(k, 0.0)) + n * float(e.consume[k])
		gold += n * float(e.gold)
		crates += n * float(e.crate)
		crate_id = str(e.crate_id)
		pet_l += n * float(e.pet)
		tot_xp += n * float(e.xp)
		var seg_s := maxf(0.0, n * cyc - carry)
		t_left -= seg_s
		carry = 0.0
		last_frac = n - floorf(n) if limit == "time" else 0.0
		if float(e.xp) > 0.0:
			_grant_xp(sk, n * float(e.xp))
		if float(e.mastery_xp) > 0.0:
			_grant_mastery(aid, n * float(e.mastery_xp))
		if not pot_slot.is_empty() and int(pot.charges(pot_slot)) > 0:
			pot.consume(pot_slot, int(floor(n + 1e-6)))
		if bf != null:
			bf.advance_offline(seg_s / eff)
		if limit == "materials":
			stopped = "no_materials"
			break
		if limit == "single":
			single_done = true
			last_frac = 0.0
			break
		if limit == "time" or limit == "queue":
			break
	# consegna al bank: prima si consumano gli ingredienti (libera posti), poi si aggiungono le uscite
	var b := _bank()
	var src := "skill:" + sk
	if b != null:
		for k in consume:
			b.remove(k, mini(int(round(float(consume[k]))), int(b.count(k))))
	var given := {}
	for k in items:
		var q := _random_round(float(items[k]))
		var got := _bank_add(k, q, src)
		if got < q and stopped.is_empty():
			stopped = "bank_full"
		if got > 0:
			given[k] = int(given.get(k, 0)) + got
	for k in inst:
		var w: Array = inst[k]
		var ids: Array = ctx.constants().quality
		for qi in 4:
			var q2 := _random_round(float(w[qi]))
			var got2 := _bank_give(k, q2, str(ids[qi].id), src)
			if got2 < q2 and stopped.is_empty():
				stopped = "bank_full"
			if got2 > 0:
				given[k] = int(given.get(k, 0)) + got2
	for k in rare:
		var q3 := _poisson(float(rare[k]))
		if q3 > 0:
			var got3 := _bank_give(k, q3, "normal", src)
			if got3 > 0:
				given[k] = int(given.get(k, 0)) + got3
				# 1.0 (docs/review_1_0/02 punto 6): i ritrovamenti secondari (gemme, ecc.) contano per gli obiettivi «raccogli»
				# anche offline, come online (action_completed con le uscite estratte): prima restavano nel Deposito ma non nella missione.
				ctx.events.objective_event.emit("gather", {"item": k, "qty": got3, "skill": sk})
	if b != null and gold > 0.0:
		var g := _random_round(gold)
		if g > 0:
			b.add_gold(g)
	if single_done and stopped.is_empty():
		stopped = "single"
	var crate_n := _poisson(crates)
	for i in crate_n:
		ctx.events.crate_found.emit(crate_id, src)
	if pet_l > 0.0 and _pet_by_skill.has(sk) and not ctx.state.get("pets", []).has(_pet_by_skill[sk].id):
		if _poisson(pet_l) > 0:
			ctx.events.pet_found.emit(_pet_by_skill[sk].id)
	var done := int(floor(tot_n + 1e-6))
	var avg_out: Array = []
	for o in a.get("outputs", []):
		avg_out.append({"item": str(o.item), "qty": int(_qty_mean(o.qty))})
	if done > 0:
		ctx.events.action_batch_completed.emit(aid, done, avg_out)
	var cond_met := false
	if cond.has("max_n") and tot_n >= float(cond.max_n) - 1e-6:
		cond_met = true
	if cond.has("until_level") and level(sk) >= int(cond.until_level):
		cond_met = true
	if time_capped and t_left <= 1e-6:
		cond_met = true
	_activity["progress_s"] = last_frac * maxf(0.05, float(_profile(aid).cycle_s)) if (stopped.is_empty() and not cond_met) else 0.0
	_roll_duration_mult(aid)
	var report := {"skill": sk, "action": aid, "seconds": t_start - t_left, "completions": done, "xp": tot_xp,
		"level_from": lv_from, "level_to": level(sk), "items": given, "crates": crate_n, "stopped": stopped}
	return {"report": report, "used": t_start - t_left, "cycles": tot_n, "stopped": stopped, "cond_met": cond_met}


func _random_round(x: float) -> int:
	var f := floorf(x)
	return int(f) + (1 if ctx.rng.chance("loot", x - f) else 0)


## Estrazione di Poisson con il flusso "loot": inversione per λ piccolo, normale approssimata per λ grande.
func _poisson(lambda: float) -> int:
	if lambda <= 0.0:
		return 0
	var r: RandomNumberGenerator = ctx.rng.stream("loot")
	if lambda > 30.0:
		return maxi(0, int(round(lambda + sqrt(lambda) * r.randfn())))
	var l := exp(-lambda)
	var k := 0
	var pr := r.randf()
	var cum := l
	var term := l
	while pr > cum and k < 1000:
		k += 1
		term *= lambda / float(k)
		cum += term
	return k


# ------------------------------------------------------------------ talenti di mansione (docs/04 §7)

func perk_rows(skill_id: String) -> Array:
	return ctx.data.grouped("skill_perks", skill_id)


func perks_allowed_per_tier(skill_id: String) -> int:
	return 2 if int(state.get(skill_id, {}).get("stars", 0)) >= int(ctx.constants().automation.perk_double_pick_stars) else 1


func chosen_letters(skill_id: String, tier_level: int) -> String:
	return str(state.get(skill_id, {}).get("perks", {}).get(str(tier_level), ""))


## Livelli dei tier raggiunti con ancora scelte da fare.
func pending_perk_tiers(skill_id: String) -> Array:
	var out: Array = []
	for row in perk_rows(skill_id):
		var lv := int(row.level)
		if level(skill_id) >= lv and chosen_letters(skill_id, lv).length() < perks_allowed_per_tier(skill_id):
			out.append(lv)
	return out


## letter = "a"|"b"|"c". Ritorna false se il tier non è raggiunto, la scelta è già fatta o piena.
func choose_perk(skill_id: String, tier_level: int, letter: String) -> bool:
	var row := _perk_row(skill_id, tier_level)
	if row.is_empty() or level(skill_id) < tier_level or letter.length() != 1:
		return false
	var found := false
	for opt in row.options:
		if str(opt.id).ends_with("_" + letter):
			found = true
	var cur := chosen_letters(skill_id, tier_level)
	if not found or cur.contains(letter) or cur.length() >= perks_allowed_per_tier(skill_id):
		return false
	state[skill_id].perks[str(tier_level)] = cur + letter
	_refresh_perks()
	return true


## Costo del respec: formula "N * livello_mansione" dei dati (oro).
func respec_cost(skill_id: String, tier_level: int) -> int:
	var row := _perk_row(skill_id, tier_level)
	var f := str(row.get("respec_cost_gold_formula", ""))
	var rx := RegEx.new()
	rx.compile("^\\s*([0-9.]+)\\s*\\*\\s*livello_mansione\\s*$")
	var mt := rx.search(f)
	return int(float(mt.get_string(1)) * float(level(skill_id))) if mt != null else 0


func respec_perk(skill_id: String, tier_level: int) -> bool:
	if chosen_letters(skill_id, tier_level).is_empty():
		return false
	var b := _bank()
	var cost := respec_cost(skill_id, tier_level)
	if b != null and cost > 0 and not b.spend_gold(cost):
		return false
	state[skill_id].perks.erase(str(tier_level))
	_refresh_perks()
	return true


func _perk_row(skill_id: String, tier_level: int) -> Dictionary:
	for row in perk_rows(skill_id):
		if int(row.level) == tier_level:
			return row
	return {}


func _refresh_perks() -> void:
	for sid in _skill_defs:
		var mods: Array = []
		var perks: Dictionary = state[sid].perks
		for tier_str in perks:
			var row := _perk_row(sid, int(tier_str))
			for letter in str(perks[tier_str]):
				for opt in row.get("options", []):
					if str(opt.id).ends_with("_" + letter):
						mods.append_array(opt.modifiers)
		ctx.modifiers.set_source(SOURCE_PERK + sid, mods)


# ------------------------------------------------------------------ attrezzi

## Ricalcola i bonus degli attrezzi equipaggiati (ctx.state.equipment.tools[skill] = uid). Chiamarla dopo ogni cambio.
func refresh_tools() -> void:
	var tools: Dictionary = ctx.state.get("equipment", {}).get("tools", {})
	var b := _bank()
	for sid in _skill_defs:
		var mods: Array = []
		var uid: String = str(tools.get(sid, ""))
		if not uid.is_empty() and b != null:
			var inst: Dictionary = b.get_instance(uid)
			var def: Dictionary = ctx.data.item(str(inst.get("def", "")))
			var t: Dictionary = def.get("tool", {})
			if not t.is_empty() and str(t.skill) == sid and level(sid) >= int(t.get("level_req", 1)):
				if float(t.get("haste_pct", 0)) != 0.0:
					mods.append({"key": "skill_haste_pct:" + sid, "value": float(t.haste_pct), "mode": "add"})
				if float(t.get("double_pct", 0)) != 0.0:
					mods.append({"key": "skill_double_pct:" + sid, "value": float(t.double_pct), "mode": "add"})
		if mods.is_empty() and not ctx.modifiers.has_source(SOURCE_TOOL + sid):
			continue
		ctx.modifiers.set_source(SOURCE_TOOL + sid, mods)
