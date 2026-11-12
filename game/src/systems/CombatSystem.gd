class_name CombatSystem
extends GameSystem
## Combattimento automatico a tick, eroe, equipaggiamento a slot, cibo, morte, drop, abilità, talenti, classi,
## dungeon (docs/05, 06, 07, 08, 14). Contratto con gli altri sistemi: docs/audit_2026-10-22/17_CONTRATTI_TRA_SISTEMI.md.
##
## Stato posseduto:
##   hero       (state_key)     classe, specializzazione, attributi, talenti, abilità, cibo, vita, risorse (rt), pozione
##   equipment  (ctx.state)     slot -> uid dell'istanza nel bank ("ammo" -> {"def","qty"})
##   activity   (ctx.state)     quando type == "combat": zona/dungeon, mostro scelto, nemico corrente, timer
## Tutto ciò che è bilanciamento viene da constants.json / dati / Formulas; nessun valore fisso qui.
##
## Il colpo, le abilità, le meccaniche dei boss e le stime offline passano tutte da CombatSim (un solo motore,
## in modalità vera col RNG e in modalità "valori attesi" per la stima): vedi CombatSim.gd.
## Aiutanti: HeroBuild (classi, specializzazioni, abilità equipaggiate, talenti).
## Bounty: se esiste il sistema "bounty" (BountySystem) viene interrogato per Ricercati e progressi.
## EndgameCombat (`eg`): Incursioni con la squadra di mercenari, Boss mondiali, La Breccia (modi di attività "raid", "wboss", "rift").

const ARMOR_SLOTS: PackedStringArray = ["helm", "body", "legs", "gloves", "boots"]
const EQUIP_SLOTS: PackedStringArray = ["weapon", "offhand", "ammo", "helm", "body", "legs", "gloves", "boots",
	"cape", "amulet", "ring", "ring2", "insignia"]
const RING_SLOTS: PackedStringArray = ["ring", "ring2"]
const MOD_PREFIX := "equip:"
const LOG_MAX := 200
const EPS := 1e-6
const IDLE_FOOD_RED_HOURS := 1.0       # «Sicuro in idle» diventa rosso se il cibo dura meno (soglia dell'indicatore, non di bilanciamento)
const AUTO_EAT_TOKEN_PREFIXES: PackedStringArray = ["shop:", "upgrade:"]
const ELEMENTS: PackedStringArray = ["fire", "frost", "lightning", "poison", "holy", "shadow"]
const STYLE_ATTR := {"melee": "str", "ranged": "dex", "arcane": "int"}
## Famiglie di modificatori di cui CombatSim ha bisogno per i rapporti dei buff delle abilità.
const SIM_TOTALS: PackedStringArray = ["combat_dmg_pct", "combat_haste_pct", "combat_defense_pct", "combat_eva_pct",
	"combat_dmg_taken_pct", "combat_dot_dmg_pct", "summon_dmg_pct"]
## Parametri di campionamento della stima (non sono regole di gioco): durata simulata e cicli minimi/massimi.
const EST_SECONDS := 120.0
## Misura Monte Carlo stratificata: secondi simulati di scontro+ricomparsa, cicli minimi/massimi, cicli di riscaldamento.
const EST_MC_SECONDS := 3000.0      # resoconto 47: 3600 costava ~0,9 s per mostro; COMBAT-3: passi fusi (2-3x meno costo), stesso tempo totale
const EST_MC_MIN := 48              # COMBAT-3: RNG stratificato per tipo + passi fusi: boss con sd ~0,35% allo stesso costo
const EST_MC_MAX := 400
const OFFLINE_CHAIN := 4              # FIX-COMBATTIMENTO: scontri per catena dopo una rinascita (rischio per posizione)
const OFFLINE_CHAIN_CYCLES := 64      # cicli della misura a catene (16 catene da 4)
const OFFLINE_RENEWAL_ATTEMPTS := 20000.0
const OFFLINE_MIN_EXPECTED_DEATHS := 0.25
const EST_MC_LONG_MIN := 16         # FIX-COMBATTIMENTO: minimo di cicli per gli scontri oltre ~60 s
const EST_MC_WARM := 2
## Voci massime della cache delle stime (chiave = mostro + impronta delle statistiche): oltre si svuota.
const EST_CACHE_MAX := 256
const EST_MIN_CYCLES := 6
const EST_MAX_CYCLES := 96
const EST_STEPS_CAP := 7000
## Quantili (i+0,5)/12 della normale, visitati con passo 5 (coprimo con 12): ordine "sparso" da un ciclo all'altro.
const EST_Z: Array = [-1.7317, -1.1503, -0.8122, -0.5485, -0.3186, -0.1043, 0.1043, 0.3186, 0.5485, 0.8122, 1.1503, 1.7317]
const EST_Z_STRIDE := 5
const TALENT_SOURCE := "talents"
## Fonte propria: "potion:" è il prefisso di PotionSystem (M5), che lo svuota al caricamento (OPEN_QUESTIONS C2-10).
const POTION_SOURCE := "combat:potion"
const DUNGEON_SOURCE := "dungeon:"

var build: HeroBuild
var eg: EndgameCombat
var _st_cache: Dictionary = {}           # stile/posizione -> statistiche
var _st_dirty: bool = true
var _st_level: int = -1
var _st_wounded: bool = false
var _gen: int = 0                        # cresce a ogni ricostruzione delle statistiche
var _abil_ver: int = 0
var _equip_dirty: bool = true
var _check_ticks: int = 0
var _amb_cd: float = 0.0                 # ricarica dell'Imboscata (secondi di gioco; non si salva: al massimo un'imboscata in più)
var ambush_count: int = 0               # imboscate comparse in questa sessione (diagnostica e test)
var _ms_cache: Dictionary = {}           # "ckey|era" -> statistiche del mostro scalate per Era
var _wave_cache: Dictionary = {}
var _unarmed_cache: Dictionary = {}
var _eq_pool_cache: Dictionary = {}      # tier -> [id equipaggiamento] (drop "pick_equipment_tier")
var _mech_cache: Dictionary = {}
var _est_cache: Dictionary = {}
var est_surv: bool = true                # pesi di sopravvivenza nella misura (false = esito binario, per i confronti)
var est_fast: bool = true                # passi fusi nella misura Monte Carlo (false = passo per passo, per i confronti)
var _log: Array = []
var _log_seq: int = 0
var _stance: String = ""
var _stance_live: String = ""            # postura corrente a metà scontro (classi ibride, fasi del boss): solo per la UI
var _fight: Dictionary = {}              # riepilogo dello scontro in corso (non salvato)
var _last_fight: Dictionary = {}
var _run: Dictionary = {}                # riepilogo della corsa (dungeon, incursione, Breccia) in corso
var _sim: CombatSim = CombatSim.new()
var _sim_key: String = ""
var _est_sim: CombatSim = CombatSim.new()


func _init() -> void:
	id = "combat"
	state_key = "hero"
	build = HeroBuild.new(self)
	eg = EndgameCombat.new(self)


func setup() -> void:
	if ctx.modifiers != null:
		ctx.modifiers.changed.connect(_on_modifiers_changed)
	_sim.sink = Callable(self, "_push")
	_sim.ammo_cb = Callable(self, "_consume_ammo")
	_sim.oil_cb = Callable(self, "_consume_oil")
	_sim.potion_cb = Callable(self, "_potion_charge")
	_sim.eat_cb = Callable(self, "_auto_eat")
	_sim.rng = ctx.rng


func _on_modifiers_changed() -> void:
	_st_dirty = true


# ====================================================================== stato

func default_state() -> Variant:
	return {"class": "warrior", "spec": "", "attrs": {}, "talents": {}, "abilities": [], "auto_abilities": true,
		"food": _empty_food(), "hp": 0.0, "hp_init": false, "kills": {}, "wounded_s": 0.0, "auto_alloc": true, "eat_pct": 0,
		"class_cd_s": 0.0, "class_prev": "", "class_prev_s": 0.0, "deaths": 0, "rt": CombatSim.new_rt(), "potion": {}, "dungeon_clears": {},
		"dungeon_repeat": true, "raid_cd": {}, "raid_clears": {}, "raid_best_s": {}, "wb": EndgameCombat.default_wb(),
		"rift": EndgameCombat.default_rift(),
		"return_to": {}, "fallback_action": "", "safe_fallback": bool(ctx.constants().get("offline", {}).get("safe_fallback_default", true))}


func from_state(section: Variant) -> void:
	state = section
	var d: Dictionary = default_state()
	for k in d:
		if not state.has(k) or typeof(state[k]) != typeof(d[k]):
			if k != "hp" and k != "wounded_s" and k != "class_cd_s" and k != "class_prev_s":
				state[k] = d[k]
			elif not state.has(k) or not (state[k] is float or state[k] is int):
				state[k] = d[k]
	for k in (d.rt as Dictionary):
		if not state.rt.has(k):
			state.rt[k] = d.rt[k]
	if str(state["class"]).is_empty() or ctx.data.get_def("classes", str(state["class"])).is_empty():
		state["class"] = "warrior"
	if not str(state.spec).is_empty() and ctx.data.get_def("classes", str(state.spec)).is_empty():
		state["spec"] = ""
	var slots_n := _food_slot_count()
	var food: Array = state["food"]
	while food.size() < slots_n:
		food.append("")
	if food.size() > slots_n:
		state["food"] = food.slice(0, slots_n)
	var seen_food := {}                       # un cibo per slot: i salvataggi con lo stesso cibo in più slot lo contavano più volte
	for fi in (state["food"] as Array).size():
		var fdef := str(state.food[fi])
		if fdef.is_empty():
			continue
		if seen_food.has(fdef):
			state.food[fi] = ""
		seen_food[fdef] = true
	if not ctx.state.has("equipment") or not (ctx.state["equipment"] is Dictionary):
		ctx.state["equipment"] = {}
	_equip_dirty = true
	_st_dirty = true
	_ms_cache.clear()
	_wave_cache.clear()
	_log.clear()
	_stance = ""
	_sim_key = ""
	_sim.invalidate()
	_est_cache.clear()
	eg.normalize()
	_apply_talents()
	_apply_potion()
	_apply_dungeon_milestones()
	# salvataggi precedenti a M7: il nemico in campo non ha i campi nuovi (max, effetti): si ricomincia dal prossimo
	var act: Variant = ctx.state.get("activity", {})
	if act is Dictionary and str(act.get("type", "")) == "combat":
		var en: Variant = act.get("enemy", {})
		if en is Dictionary and not (en as Dictionary).is_empty() and not (en as Dictionary).has("max"):
			act["enemy"] = {}
			act["respawn_s"] = 0.0
		if not act.has("mode"):
			act["mode"] = "zone"
		if en is Dictionary:
			# QA120: la fase del nemico e i turni degli effetti nel tempo tornano interi dopo il JSON (che li legge come float)
			var ph: Variant = (en as Dictionary).get("phase")
			if ph is float and is_finite(ph) and ph == floorf(ph):
				en["phase"] = int(ph)
			var dots: Variant = (en as Dictionary).get("dots")
			if dots is Dictionary:
				for dk in dots:
					var dd: Variant = dots[dk]
					if dd is Dictionary and (dd as Dictionary).get("n") is float and is_finite(dd.n) and dd.n == floorf(dd.n):
						dd["n"] = int(dd.n)


func int_paths() -> PackedStringArray:
	return PackedStringArray(["attrs.*", "kills.*", "deaths", "eat_pct", "talents.*", "dungeon_clears.*", "potion.charges", "raid_clears.*",
		"wb.done_slot", "wb.kills.*", "rift.best", "rift.guardian", "rift.runs", "rift.deaths", "rift.shards"])


# ====================================================================== accesso agli altri sistemi

func _bank() -> Variant:
	return ctx.get_system("bank")


func _skills() -> Variant:
	return ctx.get_system("skills")


func _bounty() -> Variant:
	return ctx.get_system("bounty")


func _equipment() -> Dictionary:
	return ctx.state["equipment"]


func _act() -> Dictionary:
	var a: Variant = ctx.state.get("activity", {})
	return a if a is Dictionary else {}


## Sostituisce l'attività MODIFICANDO il Dictionary esistente: SkillSystem ne tiene un riferimento, e un
## Dictionary nuovo lascerebbe girare due attività insieme (R-AZ-1).
func _set_activity(d: Dictionary) -> void:
	var a: Variant = ctx.state.get("activity")
	if not (a is Dictionary):
		ctx.state["activity"] = d.duplicate()
		return
	(a as Dictionary).clear()
	(a as Dictionary).merge(d)


func hero_level() -> int:
	var sk: Variant = _skills()
	if sk != null:
		return maxi(1, int(sk.level("hero")))
	var s: Variant = ctx.state.get("skills", {}).get("hero", {})
	return maxi(1, int(s.get("level", 1))) if s is Dictionary else 1


## Livello Eroe più alto mai raggiunto (record): una Stella dell'Eroe riporta il livello a 1 ma non richiude zone,
## dungeon e incursioni già aperti (FIX-MEDIO, QA2: la Stella dell'Eroe rendeva irraggiungibile la storia).
func hero_unlock_level() -> int:
	var sk: Variant = _skills()
	if sk != null and sk.has_method("record_level"):
		return maxi(hero_level(), int(sk.record_level("hero")))
	var s: Variant = ctx.state.get("skills", {}).get("hero", {})
	return maxi(hero_level(), int(s.get("record_level", 1))) if s is Dictionary else hero_level()


func _era() -> int:
	return maxi(1, int(ctx.state.get("prestige", {}).get("era_current", 1)))


func _rules() -> Dictionary:
	return Formulas.k().combat.rules


func _food_slot_count() -> int:
	return int(_rules().food_slots)


func _empty_food() -> Array:
	var out: Array = []
	for i in _food_slot_count():
		out.append("")
	return out


func _notice(kind: String, key: String, params: Dictionary = {}) -> void:
	ctx.events.notice.emit(kind, Loc.tf(key, params), {"section": "combat"})


## Dati delle meccaniche dei boss (data/boss_mechanics.json) indicizzati per id.
func mechanics() -> Dictionary:
	if _mech_cache.is_empty():
		for m in ctx.data.table("boss_mechanics"):
			_mech_cache[str(m.id)] = m
	return _mech_cache


## Chiamato da HeroBuild quando cambiano classe, specializzazione, abilità o talenti.
func on_build_changed() -> void:
	_apply_talents()
	_abil_ver += 1
	_st_dirty = true
	_est_cache.clear()
	_sim_key = ""


func _apply_talents() -> void:
	if ctx.modifiers == null:
		return
	var mods := build.talent_mods()
	if mods.is_empty():
		ctx.modifiers.clear_source(TALENT_SOURCE)
	else:
		ctx.modifiers.set_source(TALENT_SOURCE, mods)


# ====================================================================== registro (per la UI)

## Eventi recenti per registro e effetti visivi: {"id": progressivo, "k": tipo, ...}. Non è salvato.
func log_since(last_id: int) -> Array:
	var out: Array = []
	for e in _log:
		if int(e.id) > last_id:
			out.append(e)
	return out


func log_last_id() -> int:
	return _log_seq


func _push(entry: Dictionary) -> void:
	_track(entry)
	_audio_hint(entry)
	_log_seq += 1
	entry["id"] = _log_seq
	_log.append(entry)
	if _log.size() > LOG_MAX:
		_log.remove_at(0)


# ====================================================================== zone e mostri

func zone_def(zone_id: String) -> Dictionary:
	return ctx.data.get_def("zones", zone_id)


func zone_unlocked(zone_id: String) -> bool:
	var z := zone_def(zone_id)
	if z.is_empty():
		return false
	var req: Dictionary = z.get("unlock", {})
	if hero_unlock_level() < int(req.get("hero_level", 1)):
		return false
	if req.get("quest") == null:
		return true
	var unlocks: Array = ctx.state.get("unlocks", [])
	return unlocks.has("zone:" + zone_id)


## Zone dei dati in ordine, ciascuna con "unlocked".
func zones() -> Array:
	var out: Array = []
	for z in ctx.data.table("zones"):
		out.append({"id": z.id, "def": z, "unlocked": zone_unlocked(str(z.id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.def.order) < int(b.def.order))
	return out


func monsters_of(zone_id: String) -> Array:
	var out: Array = []
	for mid in zone_def(zone_id).get("monsters", []):
		var m: Dictionary = ctx.data.get_def("monsters", str(mid))
		if not m.is_empty():
			out.append(m)
	return out


func kills_of(monster_id: String) -> int:
	return int(state.kills.get(monster_id, 0))


# ====================================================================== avvio / arresto

func in_combat() -> bool:
	return str(_act().get("type", "")) == "combat"


func in_dungeon() -> bool:
	return in_combat() and str(_act().get("mode", "")) == "dungeon"


## Modo di fine gioco in corso: "raid", "wboss", "rift" oppure "".
func endgame_mode() -> String:
	var m := str(_act().get("mode", ""))
	return m if in_combat() and eg.is_endgame_mode(m) else ""


## Avvia il combattimento (sostituisce qualunque attività). monster_id vuoto = a caso tra i mostri normali.
func start(zone_id: String, monster_id: String = "") -> bool:
	if not zone_unlocked(zone_id):
		return false
	var z := zone_def(zone_id)
	if not monster_id.is_empty() and not (z.monsters as Array).has(monster_id):
		return false
	return _begin({"zone": zone_id, "monster": monster_id, "mode": "zone"})


func _begin(extra: Dictionary) -> bool:
	_ensure()
	var st := _stats()
	if st.needs_ammo and not st.has_ammo:
		_notice("warning", "UI_COMBAT_NO_AMMO_ARCANE" if str(st.style) == "arcane" else ("UI_COMBAT_NO_AMMO_RANGED" if str(st.style) == "ranged" else "UI_COMBAT_NO_AMMO"))
		return false
	_remember_return_to(str(extra.get("mode", "")))
	var sk: Variant = _skills()
	if sk != null and sk.has_method("stop"):
		var prev := str(sk.current_action()) if sk.has_method("current_action") else ""
		if not prev.is_empty():
			state["fallback_action"] = prev          # mansione di riserva se il combattimento offline si ferma (QA81 M5)
		sk.stop()
	var a := {"type": "combat", "zone": "", "monster": "", "enemy": {},
		"respawn_s": 0.0, "hero_cd": 0.0, "mon_cd": 0.0, "revive_s": 0.0}
	a.merge(extra, true)
	_set_activity(a)      # stesso Dictionary di SkillSystem: una sola attività alla volta (R-AZ-1)
	_run = _new_tally()
	_fight = _new_tally()
	_st_dirty = true
	_sim_key = ""
	if float(state.hp) <= 0.0:
		state["hp"] = float(_stats().hp)
	return true


func stop() -> void:
	if in_combat():
		if not endgame_mode().is_empty():
			eg.on_stop(_act())
		state["return_to"] = {}          # ritirata voluta: l'Eroe non riprende da solo
		_set_activity({})
		_st_dirty = true


## Ripresa dopo incursioni, boss mondiali e Breccia (Q118-1, docs/05 §7b): prima di entrare in una di queste modalità si
## ricorda l'attività precedente (zona/mostro, dungeon o mansione); a fine incontro (vittoria, sconfitta, tempo scaduto,
## ritiro automatico) l'Eroe la riprende, come il dungeon con «Ripeti». Il ritiro voluto (stop) non riprende. Chiave
## additiva `return_to` (vuota di base): nessuna migrazione.
func _remember_return_to(new_mode: String) -> void:
	if not eg.is_endgame_mode(new_mode):
		state["return_to"] = {}
		return
	var a := _act()
	if eg.is_endgame_mode(str(a.get("mode", ""))) and in_combat():
		return                           # da un incontro all'altro: si conserva quello di partenza
	var rt := {}
	if in_combat():
		match str(a.get("mode", "")):
			"zone":
				rt = {"kind": "zone", "zone": str(a.get("zone", "")), "monster": str(a.get("monster", ""))}
			"dungeon":
				rt = {"kind": "dungeon", "dungeon": str(a.get("dungeon", ""))}
	else:
		var sk: Variant = _skills()
		var prev := str(sk.current_action()) if sk != null and sk.has_method("current_action") else ""
		if not prev.is_empty():
			rt = {"kind": "skill", "action": prev}
	state["return_to"] = rt


## Fine naturale di un incontro di fine gioco: svuota l'attività e riprende quella ricordata (se ancora possibile).
func _end_endgame() -> void:
	var rt: Variant = state.get("return_to", {})
	state["return_to"] = {}
	_set_activity({})
	_st_dirty = true
	if rt is Dictionary and not (rt as Dictionary).is_empty():
		_resume_return_to(rt)


func _resume_return_to(rt: Dictionary) -> bool:
	var ok := false
	match str(rt.get("kind", "")):
		"zone":
			ok = start(str(rt.zone), str(rt.get("monster", "")))
		"dungeon":
			ok = start_dungeon(str(rt.dungeon))
		"skill":
			var sk: Variant = _skills()
			ok = sk != null and sk.can_start(str(rt.action)) == "" and bool(sk.start(str(rt.action)))
	if ok:
		_push({"k": "resume"})
	return ok


# ====================================================================== statistiche dell'eroe

func _ensure() -> void:
	if _equip_dirty:
		_sync_equipment()


func class_def() -> Dictionary:
	return ctx.data.get_def("classes", str(state.class))


## Stile dell'arma impugnata ("" se senza arma).
func weapon_style() -> String:
	var w := _weapon_def()
	return str(w.get("style", ""))


## Attributi finali senza equipaggiamento: base + crescita per livello + punti liberi (auto o assegnati).
func base_attrs(level: int) -> Dictionary:
	var h: Dictionary = Formulas.k().combat.hero
	var cd := class_def()
	var growth: Dictionary = cd.get("growth_per_level", {})
	var out := {}
	for a in ["str", "dex", "int", "vit"]:
		out[a] = float(h.attr_base) + float(growth.get(a, 0.0)) * level
	if bool(state.auto_alloc):
		var auto: Dictionary = cd.get("auto_alloc", {})
		for a in auto:
			out[a] += float(auto[a]) * level
	else:
		for a in state.attrs:
			if out.has(a):
				out[a] += float(state.attrs[a])
	return out


func free_points() -> int:
	if bool(state.auto_alloc):
		return 0
	var total := int(Formulas.k().combat.hero.attr_points_per_level) * hero_level()
	var spent := 0
	for a in state.attrs:
		spent += int(state.attrs[a])
	return maxi(0, total - spent)


## Passa tra distribuzione automatica (preset della classe) e manuale (parte dal preset corrente).
func set_auto_alloc(on: bool) -> void:
	if on == bool(state.auto_alloc):
		return
	if not on:
		var lvl := hero_level()
		var auto: Dictionary = class_def().get("auto_alloc", {})
		state["attrs"] = {}
		for a in auto:
			state.attrs[a] = int(auto[a]) * lvl
	state["auto_alloc"] = on
	_st_dirty = true


## Aggiunge n punti liberi a un attributo (solo in modalità manuale e fuori dal combattimento).
func allocate(attr: String, n: int = 1) -> bool:
	if bool(state.auto_alloc) or in_combat() or not ["str", "dex", "int", "vit"].has(attr) or n <= 0:
		return false              # QA82 A2: n <= 0 portava un attributo sotto zero e regalava punti liberi
	if n > free_points():
		return false
	state.attrs[attr] = int(state.attrs.get(attr, 0)) + n
	_st_dirty = true
	return true


func reset_allocation() -> bool:
	if bool(state.auto_alloc) or in_combat():
		return false
	state["attrs"] = {}
	_st_dirty = true
	return true


func _class_change_rules() -> Dictionary:
	return _rules().class_change


func _dec_class_timers(seconds: float) -> void:
	state["class_cd_s"] = maxf(0.0, float(state.class_cd_s) - seconds)
	state["class_prev_s"] = maxf(0.0, float(state.class_prev_s) - seconds)


## Cambio classe (base o ibrida sbloccata): gratis fino al livello indicato nei dati, poi a pagamento con ricarica.
## Prova (BOT-05): dopo un cambio a pagamento, tornare alla classe lasciata entro `trial_return_s` di gioco e' gratis e senza ricarica.
## La specializzazione e i talenti della vecchia classe si azzerano (le abilità tornano automatiche).
func set_class(class_id: String) -> bool:
	var cd: Dictionary = ctx.data.get_def("classes", class_id)
	if cd.is_empty() or not build.class_available(class_id) or in_combat():
		return false
	if class_id == str(state.class):
		return true
	var cc := _class_change_rules()
	var old_class := str(state.class)
	var paid := false
	if class_change_cost(class_id) > 0:
		if float(state.class_cd_s) > 0.0:
			return false
		var bank: Variant = _bank()
		if bank == null or not bank.spend_gold(int(cc.gold_per_level) * hero_level()):
			return false
		state["class_cd_s"] = float(cc.cooldown_s)
		paid = true
	elif class_change_is_trial_return(class_id):
		state["class_cd_s"] = 0.0
	state["class_prev"] = old_class if paid else ""
	state["class_prev_s"] = float(cc.trial_return_s) if paid else 0.0
	state["class"] = class_id
	state["spec"] = ""
	state["attrs"] = {}
	state["talents"] = {}
	state["abilities"] = []
	state["auto_abilities"] = true
	_stance = ""
	state["rt"] = CombatSim.new_rt()
	_sim.invalidate()
	on_build_changed()
	return true


## true se `class_id` e' la classe lasciata con un cambio a pagamento e la finestra di prova non e' scaduta.
func class_change_is_trial_return(class_id: String) -> bool:
	return not class_id.is_empty() and class_id == str(state.get("class_prev", "")) and float(state.get("class_prev_s", 0.0)) > 0.0


## Costo del cambio verso `to_class` ("" = verso una classe nuova): 0 fino al livello libero e per il ritorno di prova.
func class_change_cost(to_class: String = "") -> int:
	var lvl := hero_level()
	var cc := _class_change_rules()
	if lvl <= int(cc.free_until_level) or class_change_is_trial_return(to_class):
		return 0
	return int(cc.gold_per_level) * lvl


## Statistiche finali (stesso formato di Formulas.hero_stats + campi aggiuntivi).
func hero_stats() -> Dictionary:
	return _stats().duplicate(true)


## Ingredienti del calcolo delle statistiche, per i tooltip di calcolo (UI-A G18, sola lettura): somma delle statistiche
## degli oggetti indossati (qualità e grado già applicati), blocco dell'arma e danno delle munizioni.
func stat_inputs() -> Dictionary:
	var gear := _gear_blocks()
	var weapon: Dictionary = {}
	var sums: Dictionary = {}
	for g in gear:
		if g.get("slot", "") == "weapon":
			weapon = g
		for key in g.get("stats", {}):
			sums[key] = float(sums.get(key, 0.0)) + float(g.stats[key])
	if weapon.is_empty():
		weapon = _unarmed()
	var ammo_dmg := 0.0
	if bool(_stats().get("has_ammo", false)):
		var ammo: Variant = _equipment().get("ammo")
		if ammo is Dictionary:
			ammo_dmg = float(ctx.data.item(str(ammo.def)).get("ammo", {}).get("damage", 0.0))
	return {"sums": sums, "weapon": weapon, "ammo_damage": ammo_dmg}


func max_hp() -> float:
	return float(_stats().hp)


func hp() -> float:
	return float(state.hp)


func _stats() -> Dictionary:
	return _stats_for(_stance_live if not _stance_live.is_empty() else _stance)


## Statistiche per una postura ("" = stile dell'arma/classe). Le ibride hanno una postura per stile.
func _stats_for(stance: String) -> Dictionary:
	_ensure()
	var lvl := hero_level()
	var wounded := float(state.wounded_s) > 0.0
	if _st_dirty or lvl != _st_level or wounded != _st_wounded:
		_st_cache.clear()
		# la cache delle stime NON si svuota qui: la chiave contiene l'impronta delle statistiche (estimate_mon), così
		# riavviare uno scontro (che segna le statistiche da ricostruire) non rifà stime identiche (resoconto 47)
		if _est_cache.size() > EST_CACHE_MAX:
			_est_cache.clear()
		_gen += 1
		_st_level = lvl
		_st_wounded = wounded
		_st_dirty = false
	var key := stance
	if not _st_cache.has(key):
		_st_cache[key] = _build_stats(lvl, wounded, stance)
	return _st_cache[key]


func _quality_mult(inst: Dictionary) -> float:
	var q: Variant = inst.get("quality", "normal")
	if q is float or q is int:
		return float(q)
	for e in ctx.data.constants.get("quality", []):
		if e.id == q:
			return float(e.mult)
	return 1.0


func _quality_sockets(inst: Dictionary) -> int:
	var q: Variant = inst.get("quality", "normal")
	for e in ctx.data.constants.get("quality", []):
		if e.id == q:
			return int(e.sockets)
	return 0


func _unarmed() -> Dictionary:
	# Pugni: danno, intervallo e rapporto minimo del tier-1 più debole tra le armi dei dati (nessun numero nel codice).
	if _unarmed_cache.is_empty():
		var best: Dictionary = {}
		for it in ctx.data.items_by_category("equipment"):
			var eq: Dictionary = it.get("equipment", {})
			if eq.get("slot", "") == "weapon" and int(it.get("tier", 0)) == 1 and eq.get("style", "") == "melee" \
					and not eq.get("two_handed", false) and not it.get("unique", false):
				if best.is_empty() or float(eq.damage) < float(best.damage):
					best = eq
		_unarmed_cache = {"slot": "weapon", "style": "melee", "damage": float(best.get("damage", 1.0)),
			"min_ratio": float(best.get("min_ratio", 0.5)), "attack_interval_s": float(best.get("attack_interval_s", 2.4)),
			"stats": {}}
	return _unarmed_cache


## Blocchi "equipment" dei pezzi indossati con qualità e rango già applicati, senza modificatori
## (quelli passano da ctx.modifiers: set_source("equip:<slot>")).
func _gear_blocks() -> Array:
	var out: Array = []
	var bank: Variant = _bank()
	var rank_info: Dictionary = ctx.data.rules("era_rules").get("item_rank", {})
	var rank_stats: Array = rank_info.get("applies_to_stats", [])
	var per_rank := float(rank_info.get("stat_mult_per_rank", 1.0))
	var eq_state := _equipment()
	for slot in EQUIP_SLOTS:
		if slot == "ammo" or not eq_state.has(slot) or bank == null:
			continue
		var inst: Dictionary = bank.get_instance(str(eq_state[slot]))
		if inst.is_empty():
			continue
		var def: Dictionary = ctx.data.item(str(inst.get("def", "")))
		if def.is_empty() or not def.has("equipment"):
			continue
		var eq: Dictionary = (def.equipment as Dictionary).duplicate(true)
		var qm := _quality_mult(inst) if bool(def.get("quality_applies", true)) else 1.0
		var rk := pow(per_rank, float(inst.get("rank", 0)))
		var stats: Dictionary = eq.get("stats", {})
		for key in stats:
			var v := float(stats[key])
			if key != "crit_chance":
				v *= qm
			if rank_stats.has(key):
				v *= rk
			stats[key] = v
		if eq.has("damage"):
			var dmg := float(eq.damage) * qm
			if rank_stats.has("damage"):
				dmg *= rk
			eq["damage"] = dmg
		eq.erase("modifiers")
		out.append(eq)
	return out


func _weapon_def() -> Dictionary:
	var bank: Variant = _bank()
	var uid := str(_equipment().get("weapon", ""))
	if bank == null or uid.is_empty():
		return {}
	var inst: Dictionary = bank.get_instance(uid)
	return ctx.data.item(str(inst.get("def", ""))).get("equipment", {}) if not inst.is_empty() else {}


## Postura che un'ibrida adotta contro un mostro (nella fase `phase` se il mostro ne ha): lo stile (tra i suoi due) in
## vantaggio di triangolo, altrimenti quello senza svantaggio, altrimenti il primo (docs/06 R-CL-3). Le classi non
## ibride: "". Negli scontri a fasi il motore la rivaluta a ogni cambio di fase (CombatSim.st_alt, COMBAT-3).
func stance_for(mon: Dictionary, phase: int = 0) -> String:
	var cd := class_def()
	if not bool(cd.get("hybrid", false)):
		return ""
	var mstyle := str(mon.get("style", ""))
	var ph: Variant = mon.get("phases")
	if ph is Array and (ph as Array).size() > 1:
		mstyle = str(((ph as Array)[clampi(phase, 0, (ph as Array).size() - 1)] as Dictionary).style)
	return CombatSim.pick_stance(cd.styles, mstyle)


## Statistiche di ogni postura di un'ibrida per gli scontri a fasi (stile -> statistiche), con gli effetti di squadra
## `fx` delle incursioni. Vuoto per le classi non ibride e per i mostri senza fasi.
func _stance_alts(mon: Dictionary, fx: Dictionary) -> Dictionary:
	var cd := class_def()
	var ph: Variant = mon.get("phases")
	if not bool(cd.get("hybrid", false)) or not (ph is Array) or (ph as Array).size() < 2:
		return {}
	var out := {}
	for sty in cd.styles:
		var sst := _stats_for(str(sty))
		out[str(sty)] = eg.apply_fx(sst, fx) if not fx.is_empty() else sst
	return out


func _dungeon_scope() -> String:
	var a := _act()
	return str(a.get("dungeon", "")) if str(a.get("mode", "")) == "dungeon" and in_combat() else ""


func _build_stats(lvl: int, wounded: bool, stance: String) -> Dictionary:
	var k: Dictionary = Formulas.k().combat
	var cd := class_def()
	var hybrid := bool(cd.get("hybrid", false))
	var gear := _gear_blocks()
	var has_weapon := false
	for g in gear:
		if g.get("slot", "") == "weapon":
			has_weapon = true
	if not has_weapon:
		gear.append(_unarmed())
	var weapon_eq: Dictionary = _weapon_def() if has_weapon else _unarmed()
	var wstyle := str(weapon_eq.get("style", ""))
	var style: String = str(cd.get("style", "melee"))
	var primary: String = str(cd.get("primary_attr", "str"))
	if hybrid:
		var styles: Array = cd.styles
		style = stance if not stance.is_empty() and styles.has(stance) else str(styles[0])
		primary = str(STYLE_ATTR[style])
	elif not wstyle.is_empty():
		style = wstyle
	var ammo_dmg := 0.0
	var needs_ammo := has_weapon and (wstyle == "ranged" or wstyle == "arcane")
	var has_ammo := false
	var ammo: Variant = _equipment().get("ammo")
	if ammo is Dictionary and int(ammo.get("qty", 0)) > 0:
		var ad: Dictionary = ctx.data.item(str(ammo.def))
		if str(ad.get("ammo", {}).get("style", "")) == wstyle:
			has_ammo = true
			ammo_dmg = float(ad.ammo.damage)
	var attrs := base_attrs(lvl)
	var s := Formulas.hero_stats(lvl, attrs, primary, style, gear, ammo_dmg, 1.0, 1.0, [])
	var m := ctx.modifiers
	var cap_crit := float(k.crit_cap)
	s["hp"] = float(s.hp) * m.multiplier("combat_hp_pct")
	s["acc"] = float(s.acc) * m.multiplier("combat_acc_pct")
	s["eva"] = float(s.eva) * m.multiplier("combat_eva_pct")
	var defm := m.multiplier("combat_defense_pct")
	s["arm"] = float(s.arm) * defm * m.multiplier("combat_arm_pct")
	s["ward"] = float(s.ward) * defm * m.multiplier("combat_ward_pct")
	s["max_hit"] = float(s.max_hit) * m.multiplier("combat_dmg_pct")
	s["crit"] = minf(cap_crit, float(s.crit) + m.total_add("combat_crit_chance_pct") / 100.0)
	s["critd"] = float(s.critd) + m.total_add("combat_crit_dmg_pct") / 100.0
	# tetto della velocità d'attacco (core.effective_haste_pct): sulla somma degli add, poi i «more»
	var haste_m := (1.0 + Formulas.effective_haste_pct(m.total_add("combat_haste_pct")) / 100.0) * m.total_more("combat_haste_pct")
	s["interval"] = float(s.interval) / maxf(0.01, haste_m)
	var dscope := _dungeon_scope()
	if not dscope.is_empty():
		s["interval"] = float(s.interval) / maxf(0.01, m.multiplier("dungeon_speed_pct", [dscope]))
	if hybrid:
		var pm := float(cd.get("passive", {}).get("stat_mult", 1.0))
		for key in ["hp", "acc", "eva", "arm", "ward", "max_hit"]:
			s[key] = float(s[key]) * pm
	if wounded:
		var wf := 1.0 + float(_rules().death_wounded_stat_pct) / 100.0
		for key in ["hp", "acc", "eva", "arm", "ward", "max_hit"]:
			s[key] = float(s[key]) * wf
	s["regen_pct"] = float(k.hero.regen_base_pct_per_s) + m.total_add("combat_regen_hps_pct")
	s["lifesteal"] = minf(m.total_add("combat_lifesteal_pct"), float(_rules().lifesteal_cap_pct)) / 100.0
	s["armor_pen"] = minf(m.total_add("combat_armor_pen_pct"), m.cap_of("combat_armor_pen_pct")) / 100.0
	s["dmg_taken_mult"] = m.multiplier("combat_dmg_taken_pct")
	s["dot_mult"] = m.multiplier("combat_dot_dmg_pct")
	s["summon_mult"] = m.multiplier("summon_dmg_pct")
	s["thorns"] = m.total_add("combat_thorns_pct") / 100.0
	s["multihit"] = minf(m.total_add("combat_multihit_pct"), float(_rules().multihit_cap_pct)) / 100.0
	s["status_resist"] = minf(m.total_add("combat_status_resist_pct"), m.cap_of("combat_status_resist_pct")) / 100.0
	s["heal_rx"] = m.total_add("combat_heal_received_pct") / 100.0
	s["vs_bounty"] = m.total_add("combat_dmg_vs_bounty_pct")
	s["revive_once"] = m.total_add("combat_revive_once") > 0.0
	s["res_mult"] = m.multiplier("combat_resource_regen_pct")
	s["element"] = str(weapon_eq.get("element", ""))
	s["needs_ammo"] = needs_ammo
	s["has_ammo"] = has_ammo
	s["armed"] = has_weapon
	s["wounded"] = wounded
	s["primary"] = primary
	s["attrs"] = attrs
	s["class"] = str(state.class)
	s["spec"] = str(state.spec)
	s["weapon_style"] = wstyle
	s["min_hit"] = float(s.max_hit) * float(s.min_ratio)
	if not bool(state.hp_init):
		state["hp"] = float(s.hp)          # prima volta: l'eroe parte a vita piena (non a zero che si rigenera piano)
		state["hp_init"] = true
	elif float(state.hp) > float(s.hp):
		state["hp"] = float(s.hp)
	return s


# ====================================================================== equipaggiamento

func is_equipped(uid: String) -> bool:
	if uid.is_empty():
		return false
	for slot in EQUIP_SLOTS:
		if slot != "ammo" and str(_equipment().get(slot, "")) == uid:
			return true
	var tools: Variant = _equipment().get("tools", {})
	return tools is Dictionary and (tools as Dictionary).values().has(uid)


## Insieme degli uid indossati (slot + attrezzi), per controlli in blocco: stessa regola di is_equipped() senza ripeterla per pezzo.
func equipped_uid_set() -> Dictionary:
	var out: Dictionary = {}
	var eqs := _equipment()
	for slot in EQUIP_SLOTS:
		if slot != "ammo":
			var u := str(eqs.get(slot, ""))
			if not u.is_empty():
				out[u] = true
	var tools: Variant = eqs.get("tools", {})
	if tools is Dictionary:
		for sk in (tools as Dictionary):
			var tu := str((tools as Dictionary)[sk])
			if not tu.is_empty():
				out[tu] = true
	return out


## Mappa uid → slot (stessa regola di worn_slot(), in una sola passata per elenchi lunghi).
func worn_slot_map() -> Dictionary:
	var out: Dictionary = {}
	var eqs := _equipment()
	for slot in EQUIP_SLOTS:
		if slot != "ammo":
			var u := str(eqs.get(slot, ""))
			if not u.is_empty() and not out.has(u):
				out[u] = slot
	var tools: Variant = eqs.get("tools", {})
	if tools is Dictionary:
		for sk in (tools as Dictionary):
			var tu := str((tools as Dictionary)[sk])
			if not tu.is_empty() and not out.has(tu):
				out[tu] = "tool:" + str(sk)
	return out


## Attrezzi di mansione (docs/04 §8): equipment.tools[skill] = uid. Il bonus lo applica SkillSystem.refresh_tools().
func equip_tool(uid: String) -> bool:
	var bank: Variant = _bank()
	if bank == null:
		return false
	var inst: Dictionary = bank.get_instance(uid)
	var t: Dictionary = ctx.data.item(str(inst.get("def", ""))).get("tool", {}) if not inst.is_empty() else {}
	if t.is_empty():
		return false
	var eqs := _equipment()
	if not (eqs.get("tools") is Dictionary):
		eqs["tools"] = {}
	eqs.tools[str(t.skill)] = uid
	_refresh_tools()
	return true


func unequip_tool(skill: String) -> void:
	var tools: Variant = _equipment().get("tools")
	if tools is Dictionary and (tools as Dictionary).erase(skill):
		_refresh_tools()


func _refresh_tools() -> void:
	var sk: Variant = _skills()
	if sk != null and sk.has_method("refresh_tools"):
		sk.refresh_tools()


## uid dell'istanza nello slot ("" se vuoto); per "ammo" l'id dell'oggetto.
func equipped(slot: String) -> String:
	var v: Variant = _equipment().get(slot, "")
	if v is Dictionary:
		return str(v.get("def", ""))
	return str(v)


func ammo_qty() -> int:
	var a: Variant = _equipment().get("ammo")
	return int(a.get("qty", 0)) if a is Dictionary else 0


## Slot in cui l'istanza è indossata ("" se non lo è). Gli attrezzi di mansione danno "tool:<mansione>".
func worn_slot(uid: String) -> String:
	if uid.is_empty():
		return ""
	var eqs := _equipment()
	for slot in EQUIP_SLOTS:
		if slot != "ammo" and str(eqs.get(slot, "")) == uid:
			return slot
	var tools: Variant = eqs.get("tools", {})
	if tools is Dictionary:
		for sk in (tools as Dictionary):
			if str(tools[sk]) == uid:
				return "tool:" + str(sk)
	return ""


## Lo slot in cui l'istanza finirebbe: quello del pezzo (gli anelli: `target_slot` se è un anello, altrimenti il primo libero).
## "" se l'istanza non è indossabile o `target_slot` non è compatibile.
func slot_for(uid: String, target_slot: String = "") -> String:
	var bank: Variant = _bank()
	var inst: Dictionary = bank.get_instance(uid) if bank != null else {}
	var eq: Dictionary = ctx.data.item(str(inst.get("def", ""))).get("equipment", {}) if not inst.is_empty() else {}
	if eq.is_empty():
		return ""
	var slot := str(eq.slot)
	var eqs := _equipment()
	if slot == "ring":
		if RING_SLOTS.has(target_slot):
			return target_slot
		if not target_slot.is_empty():
			return ""
		return RING_SLOTS[1] if (eqs.has("ring") and not eqs.has("ring2")) else RING_SLOTS[0]
	if not target_slot.is_empty() and target_slot != slot:
		return ""
	return slot


## Perché un pezzo si può o non si può indossare adesso (UI dell'Eroe): {"ok", "slot", "why": chiave UI, "args": {}}.
## Le stesse regole di equip(), senza effetti. `target_slot` serve per scegliere tra i due anelli.
func equip_check(uid: String, target_slot: String = "") -> Dictionary:
	var bank: Variant = _bank()
	var inst: Dictionary = bank.get_instance(uid) if bank != null else {}
	if inst.is_empty():
		return {"ok": false, "slot": "", "why": "UI_EQ_WHY_MISSING", "args": {}}
	var def: Dictionary = ctx.data.item(str(inst.get("def", "")))
	if in_combat_blocking():
		return {"ok": false, "slot": "", "why": "UI_UIA_ACT_WHY_DUNGEON", "args": {}}
	if def.has("tool"):
		return {"ok": true, "slot": "tool:" + str(def.tool.get("skill", "")), "why": "", "args": {}}
	var eq: Dictionary = def.get("equipment", {})
	if eq.is_empty():
		return {"ok": false, "slot": "", "why": "UI_EQ_WHY_NOT_GEAR", "args": {}}
	var slot := slot_for(uid, target_slot)
	if slot.is_empty():
		return {"ok": false, "slot": "", "why": "UI_EQ_WHY_WRONG_SLOT", "args": {}}
	if hero_level() < int(eq.get("level_req", 1)):
		return {"ok": false, "slot": slot, "why": "UI_HERO_LEVEL_REQ", "args": {"n": int(eq.level_req)}}
	var trial_why := _trial_equip_block(str(inst.get("def", "")))
	if not trial_why.is_empty():
		return {"ok": false, "slot": slot, "why": trial_why, "args": {"tier": int(trial_rules().get("max_gear_tier", 0))}}
	var worn := worn_slot(uid)
	if not worn.is_empty():
		return {"ok": false, "slot": slot, "why": "UI_EQ_WHY_WORN", "args": {"slot": worn}}
	if slot == "offhand" and _weapon_two_handed():
		return {"ok": false, "slot": slot, "why": "UI_HERO_TWO_HANDED", "args": {}}
	return {"ok": true, "slot": slot, "why": "", "args": {}}


## Indossa l'istanza (dal bank): UN SOLO pezzo per slot, quello nuovo sostituisce il vecchio, che resta (non indossato)
## nel Deposito. Ritorna false se non esiste, il livello non basta o lo slot è bloccato. Per gli anelli `target_slot`
## ("ring"/"ring2") sceglie quale sostituire; senza, il primo slot libero.
func equip(uid: String, target_slot: String = "") -> bool:
	var bank: Variant = _bank()
	if bank == null or in_combat_blocking():
		return false
	var inst: Dictionary = bank.get_instance(uid)
	if inst.is_empty():
		return false
	if ctx.data.item(str(inst.get("def", ""))).has("tool"):
		return equip_tool(uid)
	var eq: Dictionary = ctx.data.item(str(inst.get("def", ""))).get("equipment", {})
	if eq.is_empty():
		return false
	var chk := equip_check(uid, target_slot)
	if not bool(chk.ok):
		var why := str(chk.why)
		if why == "UI_EQ_WHY_WORN":
			return str(_equipment().get(str(chk.slot), "")) == uid      # già indossato proprio lì: nulla da fare, riuscito
		# come prima: l'avviso c'è per livello, Prova e due mani; "già indossato" e "slot sbagliato" tacciono
		if why == "UI_HERO_LEVEL_REQ" or why == "UI_HERO_TWO_HANDED" or (chk.args as Dictionary).has("tier"):
			_notice("warning", why, chk.args)
		return false
	var slot := str(chk.slot)
	var eqs := _equipment()
	if slot == "weapon" and bool(eq.get("two_handed", false)) and eqs.has("offhand"):
		eqs.erase("offhand")
		_notice("info", "UI_EQ_OFFHAND_REMOVED", {})
	eqs[slot] = uid
	_equip_dirty = true
	_sync_equipment()
	_abil_ver += 1
	return true


## Prova in corso: l'Eroe, con le regole della Prova, batterebbe `monster_id` dal vivo? Scontro atteso del motore dei boss
## (meccaniche comprese), senza estrazioni. Usata per non assegnare Prove "vinte" mentre si e' via (QA82 O1).
func trial_boss_safe(monster_id: String) -> bool:
	var mon: Dictionary = ctx.data.get_def("monsters", monster_id)
	if mon.is_empty():
		return true
	_ensure()
	var r := trial_rules()
	var opts := {"food": -1}
	if bool(r.get("no_food", false)):
		opts["food"] = 0
	elif r.has("max_food"):
		opts["food"] = int(r.max_food)
	var res: Dictionary = eg.boss_pass(mon, _scaled(mon, _era()), _stats_for(stance_for(mon)), opts)
	return bool(res.won) and not bool(res.died)


## Chiave UI del divieto se la Prova in corso non ammette questo pezzo ("" = si può indossare).
func _trial_equip_block(def_id: String) -> String:
	var pr: Variant = ctx.get_system("prestige")
	if pr == null or not pr.has_method("trial_equip_block"):
		return ""
	return str(pr.call("trial_equip_block", def_id))


## Morte permanente (modalità Estrema, docs/05 §7): distrugge l'equipaggiamento INDOSSATO (istanze del Deposito),
## salvo gli slot indicati (munizioni). Gli attrezzi di mansione non sono equipaggiamento dell'Eroe e restano.
## Ritorna quanti oggetti sono andati persi.
func lose_worn_gear(keep_slots: Array) -> int:
	var bank: Variant = _bank()
	var eqs := _equipment()
	var lost := 0
	for slot in EQUIP_SLOTS:
		if slot == "ammo" or keep_slots.has(slot):
			continue
		var uid := str(eqs.get(slot, ""))
		if uid.is_empty():
			continue
		eqs.erase(slot)
		if bank != null and bank.remove_instance(uid):
			lost += 1
	_equip_dirty = true
	_sync_equipment()
	_abil_ver += 1
	return lost


## Morte permanente: i punti di attributo e i talenti dipendono dal livello Eroe, quindi si azzerano con lui
## (classe e abilità scelte restano; la specializzazione si sceglie di nuovo).
func reset_hero_build() -> void:
	state["attrs"] = {}
	state["talents"] = {}
	state["spec"] = ""
	on_build_changed()


## Nei dungeon non si cambia equipaggiamento (docs/05 §8).
func in_combat_blocking() -> bool:
	return in_dungeon()


func _weapon_two_handed() -> bool:
	return bool(_weapon_def().get("two_handed", false))


func unequip(slot: String) -> void:
	if in_combat_blocking():
		return
	var eqs := _equipment()
	if slot == "ammo":
		var a: Variant = eqs.get("ammo")
		if a is Dictionary and int(a.get("qty", 0)) > 0:
			var bank: Variant = _bank()
			if bank != null:
				bank.add(str(a.def), int(a.qty), "unequip")
		eqs.erase("ammo")
	elif eqs.has(slot):
		eqs.erase(slot)
	_equip_dirty = true
	_sync_equipment()
	_abil_ver += 1


## Mette in uso le munizioni (tutta la scorta del bank): le sostituite tornano nel bank.
func equip_ammo(def_id: String) -> bool:
	var bank: Variant = _bank()
	var d: Dictionary = ctx.data.item(def_id)
	if bank == null or d.is_empty() or str(d.get("category", "")) != "ammo":
		return false
	var qty: int = int(bank.count(def_id))
	if qty <= 0:
		return false
	var cur: Variant = _equipment().get("ammo")
	if cur is Dictionary and str(cur.def) == def_id:
		qty = int(bank.count(def_id))
	elif cur is Dictionary:
		unequip("ammo")
	if not bank.remove(def_id, qty):
		return false
	var prev: Variant = _equipment().get("ammo")
	var base := int(prev.qty) if prev is Dictionary and str(prev.def) == def_id else 0
	_equipment()["ammo"] = {"def": def_id, "qty": base + qty}
	_st_dirty = true
	return true


## Riallinea slot, modificatori e cache al contenuto del bank (istanze vendute/sparite vengono tolte).
## I Glifi incastonati aggiungono i propri modificatori alla fonte "equip:<slot>".
func _sync_equipment() -> void:
	_equip_dirty = false
	var bank: Variant = _bank()
	var eqs := _equipment()
	var seen := {}
	for slot in EQUIP_SLOTS:
		if slot == "ammo":
			continue
		var src := MOD_PREFIX + slot
		var uid := str(eqs.get(slot, ""))
		var mods: Array = []
		if not uid.is_empty():
			var inst: Dictionary = bank.get_instance(uid) if bank != null else {}
			if inst.is_empty() or seen.has(uid):
				if bank != null:
					eqs.erase(slot)
			else:
				seen[uid] = true
				var eq: Dictionary = ctx.data.item(str(inst.get("def", ""))).get("equipment", {})
				mods = (eq.get("modifiers", []) as Array).duplicate(true)
				for gid in inst.get("sockets", []):
					var gd: Dictionary = ctx.data.item(str(gid)).get("glyph", {})
					mods.append_array((gd.get("modifiers", []) as Array).duplicate(true))
		if mods.is_empty():
			ctx.modifiers.clear_source(src)
		else:
			ctx.modifiers.set_source(src, mods)
	_st_dirty = true


# ---------------------------------------------------------------------- incastri e Glifi (docs/07 §5)

## {"max": incastri, "glyphs": [id, ...]} dell'istanza (uniche: nessun incastro).
func sockets_of(uid: String) -> Dictionary:
	var bank: Variant = _bank()
	var inst: Dictionary = bank.get_instance(uid) if bank != null else {}
	if inst.is_empty():
		return {"max": 0, "glyphs": []}
	var def: Dictionary = ctx.data.item(str(inst.get("def", "")))
	var n := _quality_sockets(inst) if bool(def.get("quality_applies", true)) else 0
	return {"max": n, "glyphs": (inst.get("sockets", []) as Array).duplicate()}


## Incastona un Glifo (consumato dal bank) in un incastro libero. Non nei dungeon.
func socket_glyph(uid: String, glyph_id: String) -> bool:
	var bank: Variant = _bank()
	if bank == null or in_combat_blocking() or not ctx.data.item(glyph_id).has("glyph"):
		return false
	var inst: Dictionary = bank.get_instance(uid)
	var info := sockets_of(uid)
	if inst.is_empty() or (info.glyphs as Array).size() >= int(info.max):
		return false
	if not bank.remove(glyph_id, 1):
		return false
	if not inst.has("sockets") or not (inst.sockets is Array):
		inst["sockets"] = []
	(inst.sockets as Array).append(glyph_id)
	_equip_dirty = true
	_est_cache.clear()
	ctx.events.objective_event.emit("socket_glyph", {"qty": 1})
	return true


## Rimuove il Glifo (distrutto, docs/07 §5).
func unsocket_glyph(uid: String, index: int) -> bool:
	var bank: Variant = _bank()
	var inst: Dictionary = bank.get_instance(uid) if bank != null else {}
	if inst.is_empty() or in_combat_blocking():
		return false
	var s: Variant = inst.get("sockets", [])
	if not (s is Array) or index < 0 or index >= (s as Array).size():
		return false
	(s as Array).remove_at(index)
	_equip_dirty = true
	_est_cache.clear()
	return true


# ====================================================================== pozioni di combattimento e oli

func active_potion() -> Dictionary:
	return (state.potion as Dictionary).duplicate()


## Beve una pozione di combattimento (cariche = attacchi). Ne è attiva una sola: la nuova sostituisce la vecchia.
func use_potion(def_id: String) -> bool:
	var bank: Variant = _bank()
	var d: Dictionary = ctx.data.item(def_id)
	var p: Dictionary = d.get("potion", {})
	if bank == null or p.is_empty() or str(p.get("scope", "")) != "combat" or not bank.has(def_id, 1):
		return false
	if not bank.remove(def_id, 1):
		return false
	# una sola pozione di combattimento attiva: quella bevuta dallo slot "combat" di PotionSystem si scarta
	var pots: Variant = ctx.get_system("potions")
	if pots != null and pots.has_method("discard") and pots.has_method("charges") and int(pots.charges("combat")) > 0:
		pots.discard("combat")
	var charges := int(round(float(p.charges) * (1.0 + ctx.modifiers.total_add("potion_charges_pct") / 100.0)))
	state["potion"] = {"def": def_id, "charges": maxi(1, charges)}
	_apply_potion()
	return true


func _apply_potion() -> void:
	if ctx.modifiers == null:
		return
	var p: Dictionary = state.potion
	if p.is_empty() or int(p.get("charges", 0)) <= 0:
		state["potion"] = {}
		ctx.modifiers.clear_source(POTION_SOURCE)
		return
	var d: Dictionary = ctx.data.item(str(p.def)).get("potion", {})
	ctx.modifiers.set_source(POTION_SOURCE, (d.get("modifiers", []) as Array).duplicate(true))


func _potion_charge() -> void:
	var p: Dictionary = state.potion
	if p.is_empty():
		return
	p["charges"] = int(p.charges) - 1
	if int(p.charges) <= 0:
		state["potion"] = {}
		ctx.modifiers.clear_source(POTION_SOURCE)


## Olio da lama: 1 per colpo andato a segno (docs/05 §6). Finito l'olio lo slot si svuota.
func _consume_oil() -> void:
	var am: Variant = _equipment().get("ammo")
	if not (am is Dictionary) or str(ctx.data.item(str(am.def)).get("subcategory", "")) != "oil":
		return
	am["qty"] = int(am.qty) - 1
	if int(am.qty) <= 0:
		_refill_ammo()
		_st_dirty = true


# ====================================================================== cibo

func food_slots() -> Array:
	return (state.food as Array).duplicate()


func set_food(index: int, def_id: String) -> bool:
	if index < 0 or index >= state.food.size():
		return false
	if not def_id.is_empty() and not ctx.data.item(def_id).has("food"):
		return false
	if not def_id.is_empty():                  # lo stesso cibo non sta in due slot: si sposta (la scorta è condivisa per tipo)
		for i in state.food.size():
			if i != index and str(state.food[i]) == def_id:
				state.food[i] = ""
	state.food[index] = def_id
	_est_cache.clear()
	return true


func _auto_eat_tier() -> int:
	var unl: Array = ctx.state.get("unlocks", [])
	var mk: Variant = ctx.get_system("market")      # cinture comprate all'Emporio (MarketSystem.owned)
	for n in [3, 2, 1]:
		if mk != null and mk.has_method("owned") and int(mk.owned("auto_eat_%d" % n)) > 0:
			return n
		for p in AUTO_EAT_TOKEN_PREFIXES:
			if unl.has("%sauto_eat_%d" % [p, n]):
				return n
	return 0


## {"tier","threshold_pct","target_pct","efficiency"}: cintura dell'Emporio (I-III) o regola di base (docs/05 §6).
func auto_eat_cfg() -> Dictionary:
	var r := _rules()
	var tier := _auto_eat_tier()
	var cfg: Dictionary
	if tier > 0:
		var eff: Dictionary = ctx.data.get_def("shop", "auto_eat_%d" % tier).get("effect", {}).get("auto_eat", {})
		cfg = {"tier": tier, "threshold_pct": float(eff.get("threshold_pct", r.emergency_eat_below_pct)),
			"target_pct": float(eff.get("target_pct", r.manual_eat_below_pct)),
			"efficiency": float(eff.get("efficiency_pct", 100)) / 100.0}
	else:
		cfg = {"tier": 0, "threshold_pct": float(r.emergency_eat_below_pct), "target_pct": float(r.manual_eat_below_pct),
			"efficiency": 1.0 - float(r.emergency_eat_waste_pct) / 100.0}
	var user := float(state.eat_pct)
	if user > 0.0 and user < cfg.threshold_pct:
		cfg["threshold_pct"] = user
	return cfg


## Soglia massima regolabile (% della vita): quella della cintura dell'Emporio (o la regola di base), senza la scelta del giocatore.
func auto_eat_max_pct() -> float:
	var tier := _auto_eat_tier()
	var r := _rules()
	if tier > 0:
		var eff: Dictionary = ctx.data.get_def("shop", "auto_eat_%d" % tier).get("effect", {}).get("auto_eat", {})
		return float(eff.get("threshold_pct", r.emergency_eat_below_pct))
	return float(r.emergency_eat_below_pct)


## Soglia scelta dal giocatore (1 .. massimo). Il massimo (o più) = soglia predefinita, salvata come 0.
func set_eat_pct(p: int) -> void:
	var mx := int(floor(auto_eat_max_pct()))
	state["eat_pct"] = 0 if p <= 0 or p >= mx else p
	_est_cache.clear()


## Quanto cura una porzione di questo cibo adesso (bonus inclusi, con l'efficienza del mangiare automatico): per la UI del Cibo.
func food_heal(def_id: String) -> float:
	return _food_heal_value(def_id, float(auto_eat_cfg().efficiency))


func _food_heal_value(def_id: String, efficiency: float) -> float:
	var f: Dictionary = ctx.data.item(def_id).get("food", {})
	return float(f.get("heal", 0)) * (1.0 + ctx.modifiers.total_add("food_heal_pct") / 100.0) * efficiency


func _first_food() -> String:
	var bank: Variant = _bank()
	if bank == null:
		return ""
	for fid in state.food:
		if not str(fid).is_empty() and int(bank.count(str(fid))) > 0:
			return str(fid)
	return ""


## Tipi di cibo assegnati, senza ripetizioni e in ordine di slot.
func food_distinct() -> Array:
	var out: Array = []
	for fid in state.food:
		if not str(fid).is_empty() and not out.has(str(fid)):
			out.append(str(fid))
	return out


## Porzioni totali dei cibi assegnati (ogni tipo conta una volta, anche se compare in più slot).
func food_available() -> int:
	var bank: Variant = _bank()
	var n := 0
	if bank != null:
		for fid in food_distinct():
			n += int(bank.count(str(fid)))
	return n


## Mangia una porzione del primo cibo disponibile. manual = pulsante (efficienza piena); altrimenti automatico.
func eat_food(manual: bool = true) -> bool:
	var fid := _first_food()
	if fid.is_empty():
		return false
	var mx := max_hp()
	if float(state.hp) >= mx - EPS and manual:
		return false
	var eff := 1.0 if manual else float(auto_eat_cfg().efficiency)
	var bank: Variant = _bank()
	if not bank.remove(fid, 1):
		return false
	var heal := _food_heal_value(fid, eff)
	state["hp"] = minf(mx, float(state.hp) + heal)
	_push({"k": "eat", "v": heal, "def": fid})
	return true


func _auto_eat() -> void:
	var cfg := auto_eat_cfg()
	var mx := max_hp()
	if float(state.hp) >= mx * float(cfg.threshold_pct) / 100.0:
		return
	if trial_food_blocked():              # Prova del Digiuno: l'automatico non ti fa fallire per sbaglio
		if not bool(_fight.get("fast_warned", false)):
			_fight["fast_warned"] = true
			_push({"k": "trial_nofood"})
		return
	var guard := 0
	while float(state.hp) < mx * float(cfg.target_pct) / 100.0 and guard < 64:
		guard += 1
		if not eat_food(false):
			break


# ====================================================================== tick

func tick(dt: float) -> void:
	_ensure()
	_check_ticks += 1
	eg.tick(dt)
	if _check_ticks >= 10:          # ogni secondo simulato: pezzi venduti o spariti dal bank
		_check_ticks = 0
		_equip_dirty = true
		_ensure()
		eg.housekeeping()
	if float(state.wounded_s) > 0.0:
		state["wounded_s"] = maxf(0.0, float(state.wounded_s) - dt)
	if float(state.class_cd_s) > 0.0 or float(state.class_prev_s) > 0.0:
		_dec_class_timers(dt)
	if _amb_cd > 0.0:
		_amb_cd -= dt
	var a := _act()
	var fighting := str(a.get("type", "")) == "combat"
	var enemy_alive := fighting and not (a.get("enemy", {}) as Dictionary).is_empty() and float(a.get("revive_s", 0.0)) <= 0.0
	if enemy_alive:
		var mon := _enemy_mon(a)
		_sync_sim(mon, _scaled(mon, _era()))
	else:
		_sync_sim({}, {})
	_sim.tick_timers(state, dt, enemy_alive)
	if fighting and not _run.is_empty():
		_run["wall"] = float(_run.wall) + dt
		if enemy_alive:
			_run["t"] = float(_run.t) + dt
			_fight["t"] = float(_fight.get("t", 0.0)) + dt
	if not fighting:
		_regen(dt)
		return
	_tick_combat(a, dt)


func _regen(dt: float) -> void:
	var st := _stats()
	var mx := float(st.hp)
	if float(state.hp) < mx:
		var rp := float(_sim.effective(state.rt).regen_pct) if _sim_ready() else float(st.regen_pct)
		state["hp"] = minf(mx, float(state.hp) + mx * rp / 100.0 * dt)


func _sim_ready() -> bool:
	return not _sim.st.is_empty()


func _scaled(mon: Dictionary, era: int) -> Dictionary:
	if mon.is_empty():
		return {}
	var key := "%s|%d" % [mon.get("ckey", mon.id), era]
	if _ms_cache.has(key):
		return _ms_cache[key]
	var em := Formulas.era_monster_mult(era)
	var s: Dictionary = (mon.stats as Dictionary).duplicate()
	for stat in ctx.data.rules("era_rules").get("monster_stats_scaled", []):
		if s.has(stat):
			s[stat] = float(s[stat]) * em
	_ms_cache[key] = s
	return s


func _pick_monster(a: Dictionary) -> String:
	var sel := str(a.get("monster", ""))
	if not sel.is_empty():
		return sel
	var normals: Array = []
	for m in monsters_of(str(a.get("zone", ""))):
		if str(m.type) == "normal":
			normals.append(str(m.id))
	if normals.is_empty():
		return ""
	return normals[ctx.rng.randi_range("combat", 0, normals.size() - 1)]


## Definizione del nemico in campo (nei dungeon è la versione "di ondata" con il bonus di livello).
func _enemy_mon(a: Dictionary) -> Dictionary:
	var e: Dictionary = a.get("enemy", {})
	if str(a.get("mode", "")) == "dungeon":
		return _wave_mon(dungeon_def(str(a.dungeon)), int(a.get("wave", 0)))
	if eg.is_endgame_mode(str(a.get("mode", ""))):
		return eg.mon_for(a)
	return ctx.data.get_def("monsters", str(e.get("id", "")))


func _tick_combat(a: Dictionary, dt: float) -> void:
	if float(a.get("revive_s", 0.0)) > 0.0:
		a["revive_s"] = float(a.revive_s) - dt
		if float(a.revive_s) <= EPS:
			_revive(a)
		return
	_regen(dt)
	if (a.enemy as Dictionary).is_empty():
		a["respawn_s"] = float(a.respawn_s) - dt
		if float(a.respawn_s) > EPS:
			return
		_spawn(a)
		return
	var mon := _enemy_mon(a)
	var amb := bool((a.enemy as Dictionary).get("ambush", false)) or bool((a.enemy as Dictionary).get("champion", false))
	if amb and food_available() <= 0 and float(state.hp) < max_hp() * _retreat_pct(a) / 100.0:
		_ambush_retreat(a, mon)
		return
	var r := _sim.step(state, a, dt) if not eg.is_endgame_mode(str(a.get("mode", ""))) else eg.step(a, dt)
	match r:
		CombatSim.R_KILL:
			_kill(a, mon)
		CombatSim.R_DIE:
			if amb:
				_ambush_retreat(a, mon)          # l'Imboscata non uccide
			else:
				_die(a, str(mon.id))
		CombatSim.R_STOP:
			stop()
			_notice("warning", "UI_COMBAT_AMMO_OUT")
		EndgameCombat.R_TIMEOUT:
			eg.on_timeout(a)


## Parametri del motore per uno scontro con `mon`/`ms` (modalità vera o attesa).
func _sim_params(st: Dictionary, mon: Dictionary, ms: Dictionary, expect: bool, fx: Dictionary = {}) -> Dictionary:
	var m := ctx.modifiers
	var tot := {}
	for key in SIM_TOTALS:
		tot[key] = m.total_add(key)
	var ea := {}
	var em := {}
	for el in ELEMENTS:
		ea[el] = m.total_add("element_dmg_pct:" + el, ["all"])
		em[el] = m.total_more("element_dmg_pct:" + el, ["all"])
	var rd := _resource_def()
	var k: Dictionary = Formulas.k().combat
	return {"expect": expect, "rng": null if expect else ctx.rng, "st": st, "tot": tot, "elem_add": ea, "elem_more": em,
		"mon": mon, "ms": ms, "rules": _rules(), "mech": mechanics(),
		"abilities": [] if bool(trial_rules().get("no_abilities", false)) else build.abilities_equipped(),
		"forced_dis": bool(trial_rules().get("forced_disadvantage", false)), "st_alt": _stance_alts(mon, fx),
		"res_def": rd, "res_max": _resource_max(rd, st), "res_mult": float(st.res_mult),
		"mon_avg_ratio": float(k.sim_assumptions.monster_avg_hit_ratio), "crit_cap": float(k.crit_cap)}


func _sync_sim(mon: Dictionary, ms: Dictionary) -> void:
	if not mon.is_empty():
		_stance = stance_for(mon)
	var st := eg.run_stats(_stats())
	var key := "%d|%d|%s|%d|%s|%s|%s" % [_gen, _abil_ver, str(mon.get("ckey", mon.get("id", ""))), _era(), _stance,
		str(_act().get("raid", "")) if in_combat() else "", str(trial_rules().hash())]
	if key == _sim_key:
		return
	_sim_key = key
	_stance_live = ""
	_sim.configure(_sim_params(st, mon, ms, false, eg.active_fx()))
	_sim.invalidate()


func _mon_min_ratio() -> float:
	return 2.0 * float(Formulas.k().combat.sim_assumptions.monster_avg_hit_ratio) - 1.0


func _resource_def() -> Dictionary:
	return ctx.data.get_def("resources", str(class_def().get("resource", "")))


func _resource_max(rd: Dictionary, st: Dictionary) -> float:
	if rd.is_empty():
		return 0.0
	if rd.has("max"):
		return float(rd.max)
	# "50 + 2*INT": formula di data/resources.json
	var re := RegEx.create_from_string("^\\s*([0-9.]+)\\s*\\+\\s*([0-9.]+)\\s*\\*\\s*INT\\s*$")
	var mt := re.search(str(rd.get("max_formula", "")))
	if mt == null:
		return 100.0
	return float(mt.get_string(1)) + float(mt.get_string(2)) * float((st.attrs as Dictionary).get("int", 0.0))


## Risorsa dell'eroe per la UI: {"id", "cur", "max"}.
func resource_info() -> Dictionary:
	var rd := _resource_def()
	return {"id": str(rd.get("id", "")), "cur": float(state.rt.res), "max": _resource_max(rd, _stats())}


## Ricariche, buff e evocazioni correnti per la UI.
func ability_status() -> Dictionary:
	return {"cd": (state.rt.cd as Dictionary).duplicate(), "buffs": (state.rt.buffs as Dictionary).duplicate(true),
		"summons": (state.rt.summons as Dictionary).duplicate(true), "shield": float(state.rt.shield)}


# ====================================================================== COMBAT-3: riepiloghi, avvisi, Prove, reliquie

## Contatori di uno scontro o di una corsa (non salvati): solo per la UI.
func _new_tally() -> Dictionary:
	return {"t": 0.0, "wall": 0.0, "dealt": 0.0, "taken": 0.0, "casts": 0, "food": 0, "healed": 0.0, "crits": 0, "hits": 0,
		"kills": 0, "deaths": 0, "xp": 0.0, "gold": 0}


func _bump(key: String, v: float) -> void:
	if _fight.has(key):
		_fight[key] = _fight[key] + v
	if _run.has(key):
		_run[key] = _run[key] + v


## Segnale di sola presentazione per l'audio: colpo, critico, colpo subito, schivata. Nessuna logica di gioco.
func _audio_hint(e: Dictionary) -> void:
	var kind := ""
	match str(e.get("k", "")):
		"hit", "ahit":
			kind = "crit" if bool(e.get("crit", false)) else "hit"
		"mhit":
			kind = "hurt"
		"mmiss":
			kind = "dodge"
	if not kind.is_empty() and ctx != null and ctx.events != null and ctx.events.has_signal("combat_hit"):
		ctx.events.combat_hit.emit(kind)


## Raccoglie dagli eventi del motore i numeri del riepilogo (danni, cibo, tecniche) e la postura a metà scontro.
func _track(e: Dictionary) -> void:
	match str(e.get("k", "")):
		"hit", "ahit":
			_bump("dealt", float(e.v))
			_bump("hits", 1.0)
			if bool(e.get("crit", false)):
				_bump("crits", 1.0)
		"dot":
			_bump("dealt", float(e.v))
		"mhit":
			_bump("taken", float(e.v))
		"cast":
			_bump("casts", 1.0)
		"eat":
			_bump("food", 1.0)
			_bump("healed", float(e.v))
		"stance":
			_stance_live = str(e.style)


func _close_fight(monster_id: String, xp: float, gold: int, died: bool) -> void:
	if _fight.is_empty():
		return
	_fight["monster"] = monster_id
	_fight["xp"] = xp
	_fight["gold"] = gold
	_fight["died"] = died
	_last_fight = _fight.duplicate(true)
	if not _run.is_empty():
		if died:
			_run["deaths"] = int(_run.deaths) + 1
		else:
			_run["kills"] = int(_run.kills) + 1
			_run["xp"] = float(_run.xp) + xp
			_run["gold"] = int(_run.gold) + gold


## Riepilogo dell'ultimo scontro chiuso: t, dealt, taken, casts, food, healed, crits, hits, xp, gold, monster, died.
func last_fight() -> Dictionary:
	return _last_fight.duplicate(true)


## Riepilogo della corsa in corso (dungeon, incursione, Breccia, o la sessione di caccia): t, wall, kills, deaths, dealt...
func run_summary() -> Dictionary:
	return _run.duplicate(true)


## Avvisi di pericolo per la UI: [{id, kind, in_s}]. `timer` = meccanica periodica del boss (secondi al prossimo colpo),
## `state` = condizione attiva (Furia) o in arrivo. Vuoto se non c'è un nemico in campo.
func threats() -> Array:
	var out: Array = []
	var a := _act()
	if not in_combat():
		return out
	var e: Dictionary = a.get("enemy", {})
	if e.is_empty():
		return out
	var mon := _enemy_mon(a)
	var mech := mechanics()
	for mid in mon.get("mechanics", []):
		var trig: Dictionary = (mech.get(str(mid), {}) as Dictionary).get("trigger", {})
		if trig.has("every_s"):
			var left := maxf(0.0, float(trig.every_s) - float((e.get("t", {}) as Dictionary).get(str(mid), 0.0)))
			out.append({"id": str(mid), "kind": "timer", "in_s": left})
		elif trig.has("hp_below_pct") and not bool(trig.get("once", false)):
			var active := float(e.hp) < float(e.max) * float(trig.hp_below_pct) / 100.0
			out.append({"id": str(mid), "kind": "state", "in_s": 0.0 if active else -1.0, "active": active})
	return out


## Stato dell'eroe per l'avviso di pericolo: "" (tutto bene), "low" (vita bassa) o "critical" (vita bassa e senza cibo).
func danger_level() -> String:
	var mx := maxf(1.0, max_hp())
	var frac := float(state.hp) / mx
	var cfg := auto_eat_cfg()
	# 0.15 = margine di PRESENTAZIONE dell'avviso (non bilanciamento: non cambia danni, cure ne' ricompense)
	if frac >= float(cfg.threshold_pct) / 100.0 + 0.15:
		return ""
	if food_available() <= 0 or trial_food_blocked():
		return "critical"
	return "low"


## Scorte per la UI: porzioni, quanto cura una porzione, soglia e obiettivo dell'auto-mangiare (% della vita).
func food_info() -> Dictionary:
	var cfg := auto_eat_cfg()
	var fid := _first_food()
	return {"count": food_available(), "def": fid, "heal": _food_heal_value(fid, float(cfg.efficiency)) if not fid.is_empty() else 0.0,
		"threshold_pct": float(cfg.threshold_pct), "target_pct": float(cfg.target_pct), "blocked": trial_food_blocked()}


## Prova «Digiuno»: niente cibo (o porzioni concesse finite). Il mangiare automatico resta fermo.
func trial_food_blocked() -> bool:
	var r := trial_rules()
	if bool(r.get("no_food", false)):
		return true
	if r.has("max_food"):
		var pr: Variant = ctx.get_system("prestige")
		if pr != null and pr.has_method("trial_active"):
			var ta: Variant = pr.trial_active()
			return ta is Dictionary and int((ta as Dictionary).get("food_eaten", 0)) >= int(r.max_food)
	return false


## Prova in corso per la UI: {} oppure {id, tier, rules: [righe], time_left_s (-1 se senza tempo)}.
func trial_status() -> Dictionary:
	var pr: Variant = ctx.get_system("prestige")
	if pr == null or not pr.has_method("is_trial_active") or not bool(pr.is_trial_active()):
		return {}
	var ta: Dictionary = pr.trial_active()
	var rules: Dictionary = pr.trial_rules_active()
	var left := -1.0
	if rules.has("time_limit_s") and pr.state is Dictionary:
		left = maxf(0.0, float(rules.time_limit_s) - (float(pr.state.clock_s) - float(ta.get("started_s", 0.0))))
	return {"id": str(ta.get("id", "")), "tier": int(ta.get("tier", 0)), "rules": pr.trial_rule_lines(rules), "time_left_s": left,
		"no_food": trial_food_blocked(), "no_abilities": bool(rules.get("no_abilities", false))}


## Famiglie di modificatori che toccano il combattimento (per mostrare cosa fa una reliquia equipaggiata).
const RELIC_COMBAT_PREFIXES: PackedStringArray = ["combat_", "element_dmg_pct", "monster_drop_pct", "ammo_save_pct",
	"potion_charges_pct", "bounty_", "rift_shard_pct", "dungeon_", "gold_gain_pct:combat"]


## Preparazione dei boss (resoconto 91, R2 §7): per ogni meccanica del mostro con una risposta nei dati, se l'Eroe ce l'ha
## adesso (abilità equipaggiate, statistiche). [{id, kind, ready, value, need}]. Solo descrizione: l'effetto è in CombatSim.
func boss_answers(mon: Dictionary) -> Array:
	var out: Array = []
	var st := _stats()
	var abil: Array = build.abilities_equipped()
	for mid in mon.get("mechanics", []):
		var an: Dictionary = mechanics().get(str(mid), {}).get("answer", {})
		if an.is_empty():
			continue
		var kind := str(an.get("kind", ""))
		var ready := false
		var value := 0.0
		var need := 0.0
		match kind:
			"guard":
				var keys: Array = an.get("buff_keys", [])
				for ab in abil:
					var fx: Dictionary = ab.effect
					if not CombatSim.is_boost(ab):
						continue
					if str(fx.type) == "shield":
						ready = true
					for m in fx.get("modifiers", []):
						var k := str(m.key)
						if keys.has(k) and ((k == "combat_dmg_taken_pct") == (float(m.value) < 0.0)):
							ready = true
			"pierce":
				value = float(st.armor_pen) * 100.0
				need = float(an.get("min_armor_pen_pct", 0.0))
				ready = value >= need - EPS
				if bool(an.get("or_dot", false)):
					for ab in abil:
						var fx2: Dictionary = ab.effect
						if str(fx2.type) == "dot" or fx2.has("dot_ticks"):
							ready = true
			"resist":
				value = float(st.status_resist) * 100.0
				need = float(an.get("ready_pct", 0.0))
				ready = value >= need - EPS
			"multi":
				for ab in abil:
					var fx3: Dictionary = ab.effect
					if int(fx3.get("hits", 1)) >= int(an.get("min_hits", 2)) or str(fx3.type) == "summon":
						ready = true
		out.append({"id": str(mid), "kind": kind, "ready": ready, "value": value, "need": need})
	return out


## Reliquie ★ nel Reliquiario con almeno un effetto sul combattimento: [{uid, def, name, mods}]. Il bonus è già
## applicato dai Modificatori (fonte «relic:<uid>» di CrateSystem): qui si descrive soltanto.
func relic_effects() -> Array:
	var out: Array = []
	var cr: Variant = ctx.get_system("crates")
	var bank: Variant = _bank()
	if cr == null or bank == null or not cr.has_method("reliquary") or not cr.has_method("relic_modifiers"):
		return out
	for uid in cr.reliquary():
		var inst: Dictionary = bank.get_instance(str(uid))
		if inst.is_empty():
			continue
		var mods: Array = []
		for m in cr.relic_modifiers(inst):
			for pre in RELIC_COMBAT_PREFIXES:
				if str(m.key).begins_with(pre):
					mods.append(m)
					break
		if mods.is_empty():
			continue
		var def_id := str(inst.get("def_id", inst.get("def", "")))
		out.append({"uid": str(uid), "def": def_id, "name": ctx.data.item(def_id).get("name", {}), "mods": mods})
	return out


## Regole della Prova in corso (PrestigeSystem.trial_rules_active): no_abilities, forced_disadvantage, monster_hp_mult…
## Senza PrestigeSystem (o senza il metodo) nessuna regola.
func trial_rules() -> Dictionary:
	var pr: Variant = ctx.get_system("prestige")
	if pr != null and pr.has_method("trial_rules_active"):
		var r: Variant = pr.trial_rules_active()
		if r is Dictionary:
			return r
	return {}


func _spawn(a: Dictionary) -> bool:
	var mon: Dictionary
	if str(a.get("mode", "")) == "dungeon":
		mon = _wave_mon(dungeon_def(str(a.dungeon)), int(a.get("wave", 0)))
	elif eg.is_endgame_mode(str(a.get("mode", ""))):
		mon = eg.mon_for(a)
	else:
		mon = ctx.data.get_def("monsters", _pick_monster(a))
	if mon.is_empty():
		_set_activity({})
		return false
	var ms := _scaled(mon, _era())
	_stance_live = ""
	_fight = _new_tally()
	_sync_sim(mon, ms)
	var hp_mult := float(trial_rules().get("monster_hp_mult", 1.0))
	var dmg_mult := 1.0
	var wanted := false
	var target := false
	var b: Variant = _bounty()
	if b != null:
		target = bool(b.is_target(str(mon.id)))
		if target and bool(b.roll_wanted(str(mon.id))):
			var w: Dictionary = b.wanted_mults()
			hp_mult *= float(w.hp)
			dmg_mult = float(w.dmg)
			wanted = true
	var amb := false
	var champ := false
	var rs: Variant = _run_sys()
	if not wanted and rs != null and str(mon.get("type", "")) == "normal" and str(a.get("mode", "")) in ["", "zone"] and rs.champion_due():
		hp_mult *= float(rs.rule("champion.hp_mult"))
		dmg_mult *= float(rs.rule("champion.dmg_mult"))
		champ = true
		rs.on_champion_spawn()
	elif not wanted and _ambush_ok(a, mon) and ctx.rng.randf("combat") * 100.0 < float(ambush_rules().chance_pct):
		var ar := ambush_rules()
		hp_mult *= float(ar.hp_mult)
		dmg_mult *= float(ar.dmg_mult)
		amb = true
		_amb_cd = float(ar.min_interval_s)
		ambush_count += 1
	_sim.spawn(state, a, hp_mult, dmg_mult, target)
	(a.enemy as Dictionary)["wanted"] = wanted
	(a.enemy as Dictionary)["ambush"] = amb
	if champ:
		(a.enemy as Dictionary)["champion"] = true
		_push({"k": "champion", "m": str(mon.id)})
	if amb:
		_push({"k": "ambush", "m": str(mon.id)})
	return true


func _run_sys() -> Variant:
	return ctx.get_system("run")


## Imboscata (FIX-COMBATTIMENTO, QA4 #5 / R2 pacchetto C): nelle zone, dopo il livello minimo, un mostro normale può
## comparire come élite (vita e danno maggiorati, premio d'XP e oro raddoppiato). Non può uccidere: quando sarebbe letale,
## o con poca vita e niente cibo, si ritira (si perde solo il premio, niente Ferito). Regole in combat.rules.ambush.
func ambush_rules() -> Dictionary:
	return _rules().get("ambush", {})


func _ambush_ok(a: Dictionary, mon: Dictionary) -> bool:
	var ar := ambush_rules()
	if ar.is_empty() or _amb_cd > 0.0 or not (str(a.get("mode", "")) in ["", "zone"]) or str(mon.get("type", "")) != "normal":
		return false
	return hero_level() >= int(ar.min_hero_level) and trial_rules().is_empty()


## Soglia di vita (senza cibo) sotto cui l'Imboscata o il Campione della Corsa si ritirano.
func _retreat_pct(a: Dictionary) -> float:
	if bool((a.get("enemy", {}) as Dictionary).get("champion", false)):
		var rs: Variant = _run_sys()
		return float(rs.rule("champion.retreat_hp_pct")) if rs != null else float(ambush_rules().retreat_hp_pct)
	return float(ambush_rules().retreat_hp_pct)


func _ambush_retreat(a: Dictionary, mon: Dictionary) -> void:
	if bool((a.get("enemy", {}) as Dictionary).get("champion", false)):
		var rs: Variant = _run_sys()
		if rs != null:
			rs.on_champion_result(false)
		_push({"k": "champion_fled", "m": str(mon.id)})
	state["hp"] = maxf(float(state.hp), 1.0)
	_close_fight(str(mon.id), 0.0, 0, false)
	_push({"k": "ambush_fled", "m": str(mon.id)})
	a["enemy"] = {}
	a["respawn_s"] = float(Formulas.k().combat.respawn_s)
	state["rt"] = CombatSim.new_rt()
	_sim.invalidate()


func _kill(a: Dictionary, mon: Dictionary) -> void:
	var era := _era()
	var is_dungeon := str(a.get("mode", "")) == "dungeon"
	var boss_wave := false
	var dd: Dictionary = {}
	if is_dungeon:
		dd = dungeon_def(str(a.dungeon))
		boss_wave = int(a.get("wave", 0)) >= (dd.waves as Array).size() - 1
	var egm := str(a.get("mode", ""))
	if egm == "raid":
		boss_wave = true            # come il boss di dungeon: solo drop rari, il premio vero è quello di fine incursione
	var res := loot_roll("" if egm == "wboss" else str(mon.get("drop_table", "")), boss_wave)
	var ess := era_essence_drop(mon, egm)
	if ess > 0:
		res.items.append({"id": "era_essence", "qty": ess})
	var gold := _roll_gold(mon, era)
	var xp := mon_xp(mon, era)
	var wanted := bool((a.enemy as Dictionary).get("wanted", false))
	if bool((a.enemy as Dictionary).get("ambush", false)):
		var rm := float(ambush_rules().reward_mult)
		xp *= rm
		gold = int(round(float(gold) * rm))
	var champ := bool((a.enemy as Dictionary).get("champion", false))
	var rsys: Variant = _run_sys()
	if champ and rsys != null:
		_champion_loot(res, mon, a)
		var crm := float(rsys.rule("champion.reward_mult"))
		xp *= crm
		gold = int(round(float(gold) * crm))
	_deliver(res, str(mon.id), gold)
	var sk: Variant = _skills()
	if sk != null:
		sk.add_xp("hero", xp)
	_count_kill(str(mon.id), gold)
	_close_fight(str(mon.id), xp, gold, false)
	_push({"k": "kill", "m": str(mon.id), "xp": xp, "gold": gold, "items": res.items, "crates": res.crates, "pets": res.pets,
		"gear": res.gear, "wanted": wanted, "fight": _last_fight})
	ctx.events.monster_killed.emit(str(mon.id), res.items)
	var b: Variant = _bounty()
	if b != null:
		b.on_kill(str(mon.id), wanted, xp)
	a["enemy"] = {}
	a["respawn_s"] = float(Formulas.k().combat.respawn_s)
	if rsys != null and egm in ["", "zone"]:
		if champ:
			_push({"k": "champion_won", "m": str(mon.id)})
			rsys.on_champion_result(true)
		else:
			rsys.on_kill()
	if is_dungeon:
		_dungeon_after_kill(a, dd)
	elif eg.is_endgame_mode(egm):
		eg.after_kill(a, mon)


## Premio del Campione della Corsa (run_rules.champion): tiri in più della tabella del mostro e Cassa della zona con probabilità.
func _champion_loot(res: Dictionary, mon: Dictionary, a: Dictionary) -> void:
	var rs: Variant = _run_sys()
	for i in int(rs.rule("champion.loot_rolls")):
		var extra := loot_roll(str(mon.get("drop_table", "")))
		for key in ["items", "crates", "pets", "gear"]:
			(res[key] as Array).append_array(extra.get(key, []))
	var crate := str(zone_def(str(a.get("zone", ""))).get("crate", ""))
	if not crate.is_empty() and ctx.rng.chance("loot", float(rs.rule("champion.crate_chance"))):
		(res.crates as Array).append(crate)


## Essenza d'Era di élite, boss di zona e boss di dungeon (era_rules.era_essence.drop, × Era), solo con le Ere
## sbloccate (`feature:eras`). Incursioni, boss mondiali e Breccia la danno a parte (EndgameCombat): qui 0, per non
## duplicarla (R44-1).
## XP di un'uccisione: XP del mostro x Era x riduzione per i mostri molto sotto il livello dell'Eroe (QA4 #5).
func mon_xp(mon: Dictionary, era: int) -> float:
	return float(mon.xp) * Formulas.era_reward_mult(era) * Formulas.overlevel_xp_mult(hero_level(), int(mon.get("level", 0)))


func era_essence_drop(mon: Dictionary, mode: String) -> int:
	if eg.is_endgame_mode(mode) or not (ctx.state.get("unlocks", []) as Array).has("feature:eras"):
		return 0
	var mtype := str(mon.get("type", ""))
	if not (mtype in ["elite", "boss", "dungeon_boss"]):
		return 0
	return eg._essence_qty(mtype)


func _count_kill(mid: String, gold: int) -> void:
	state.kills[mid] = int(state.kills.get(mid, 0)) + 1
	var stats: Variant = ctx.state.get("stats")
	if stats is Dictionary:
		stats["kills"] = int(stats.get("kills", 0)) + 1
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + gold


## Attesa prima di rialzarsi dopo una morte. Protezione del novizio (Q97): fino al livello `novice.until_level` dell'Eroe
## l'attesa e la durata di Ferito sono quelle ridotte di `combat.rules.novice` (nessun numero nel codice).
func death_delay_s() -> float:
	var r := _rules()
	if hero_level() <= int(r.novice.until_level):
		return float(r.novice.restart_delay_s)
	return float(r.death_restart_delay_s)


## Durata di Ferito dopo una morte (vedi death_delay_s).
func wounded_duration_s() -> float:
	var r := _rules()
	if hero_level() <= int(r.novice.until_level):
		return float(r.novice.wounded_duration_s)
	return float(r.death_wounded_duration_s)


func _die(a: Dictionary, cause: String) -> void:
	_close_fight(cause, 0.0, 0, true)
	state["hp"] = 0.0
	state["deaths"] = int(state.deaths) + 1
	a["enemy"] = {}
	a["revive_s"] = death_delay_s()
	state["rt"] = CombatSim.new_rt()
	_sim.invalidate()
	_push({"k": "die", "m": cause, "fight": _last_fight})
	ctx.events.player_died.emit(cause)


func _revive(a: Dictionary) -> void:
	state["wounded_s"] = wounded_duration_s()
	_st_dirty = true
	state["hp"] = float(_stats().hp)
	a["revive_s"] = 0.0
	a["respawn_s"] = 0.0
	_push({"k": "revive"})
	if str(a.get("mode", "")) == "dungeon":
		# la corsa fallisce: si perde l'avanzamento delle ondate, il bottino già ottenuto resta (docs/05 §7)
		_push({"k": "dungeon_failed", "d": str(a.dungeon)})
		_set_activity({})
		_st_dirty = true
	elif eg.is_endgame_mode(str(a.get("mode", ""))):
		eg.on_fail(a)
		_end_endgame()


# ====================================================================== drop

func _roll_gold(mon: Dictionary, era: int) -> int:
	var g: Array = mon.get("gold", [0, 0])
	var base := float(ctx.rng.randi_range("loot", int(g[0]), int(g[1])))
	base *= Formulas.era_reward_mult(era)
	return int(round(ctx.modifiers.apply(base, "gold_gain_pct", ["combat", "all"])))


func _qty(q: Variant) -> int:
	if q is Array:
		return ctx.rng.randi_range("loot", int(q[0]), int(q[1]))
	return int(q)


func _classify(res: Dictionary, item_id: String, qty: int) -> void:
	if qty <= 0:
		return
	if str(ctx.data.item(item_id).get("category", "")) == "crate":
		for i in qty:
			res.crates.append(item_id)
		return
	for it in res.items:
		if it.id == item_id:
			it["qty"] = int(it.qty) + qty
			return
	res.items.append({"id": item_id, "qty": qty})


## Tira una tabella di drop (data/drop_tables.json) con il flusso RNG "loot".
## Ritorna {"items": [{id, qty}], "crates": [crate_id], "pets": [pet_id]}; non consegna nulla (vedi _deliver).
## `rare_only` (boss di dungeon): niente drop garantiti né cassa, che arrivano dal premio di fine dungeon.
func loot_roll(table_id: String, rare_only: bool = false) -> Dictionary:
	var res := {"items": [], "crates": [], "pets": [], "gear": []}
	var t: Dictionary = ctx.data.get_def("drop_tables", table_id)
	if t.is_empty():
		return res
	var rng := ctx.rng
	var drop_mult := 1.0 + ctx.modifiers.total_add("monster_drop_pct") / 100.0      # reliquie, glifi, talenti, Costellazioni
	if not rare_only:
		for it in t.get("always", []):
			if it is Dictionary:
				_classify(res, str(it.item), _qty(it.get("qty", 1)))
			else:
				_classify(res, str(it), 1)
	for r in int(t.get("rolls", 1)):
		for e in t.get("entries", []):
			if not e.has("chance"):
				continue
			if rare_only and float(e.chance) >= 1.0:
				continue
			var ch := float(e.chance)
			if not bool(e.get("pet", false)):
				ch = minf(1.0, ch * drop_mult)         # niente famigli né casse (catalogo: «non casse, non famigli»)
			if not rng.chance("loot", ch):
				continue
			if e.has("pick_equipment_tier"):
				var gid := _pick_gear(int(e.pick_equipment_tier))
				if not gid.is_empty():
					res.gear.append(gid)
				continue
			if bool(e.get("pet", false)):
				res.pets.append(str(e.item))
			else:
				_classify(res, str(e.item), _qty(e.get("qty", 1)))
	var crate: Variant = t.get("crate")
	if crate is Dictionary and not rare_only:
		var find := 1.0 + ctx.modifiers.total_add_capped("crate_find_pct", ["combat", "all"]) / 100.0
		if rng.chance("loot", float(crate.chance) * find):
			res.crates.append(str(crate.id))
	if float(t.get("rare_table_chance", 0.0)) > 0.0 and rng.chance("loot", minf(1.0, float(t.rare_table_chance) * drop_mult)):
		var rt: Dictionary = ctx.data.get_def("drop_tables", "rare_table")
		var weights: Array = []
		for e in rt.get("entries", []):
			weights.append(float(e.get("weight", 0)))
		var idx := rng.weighted_index("loot", weights)
		if idx >= 0:
			var re: Dictionary = rt.entries[idx]
			_classify(res, str(re.item), _qty(re.get("qty", 1)))
	return res


## Equipaggiamento a caso del tier (non unico) per i drop "pick_equipment_tier" di élite e boss.
func _pick_gear(tier: int) -> String:
	var pool := _equipment_pool(tier)
	if pool.is_empty():
		return ""
	return str(pool[ctx.rng.randi_range("loot", 0, pool.size() - 1)])


## Equipaggiamento non unico e indossabile di un tier (id ordinati: estrazione deterministica), in cache.
func _equipment_pool(tier: int) -> Array:
	if not _eq_pool_cache.has(tier):
		var ids: Array = []
		for it in ctx.data.items_by_category("equipment"):
			if int(it.get("tier", 0)) == tier and not bool(it.get("unique", false)) and it.has("equipment"):
				ids.append(str(it.id))
		ids.sort()
		_eq_pool_cache[tier] = ids
	return _eq_pool_cache[tier]


func _deliver(res: Dictionary, mid: String, gold: int) -> void:
	var bank: Variant = _bank()
	if bank != null:
		if gold > 0:
			bank.add_gold(gold)
		for it in res.items:
			bank.add(str(it.id), int(it.qty), "combat")
		for gid in res.get("gear", []):
			bank.add_instance({"def": str(gid), "quality": "normal", "sockets": [], "rank": 0, "source": "combat"})
	for cid in res.crates:
		ctx.events.crate_found.emit(str(cid), "combat:" + mid)
	for pid in res.pets:
		ctx.events.pet_found.emit(str(pid))


# ====================================================================== munizioni

## Una munizione per attacco; frecce parzialmente recuperate; si ricarica dal bank con lo stesso tipo.
func _consume_ammo() -> bool:
	var eqs := _equipment()
	var am: Variant = eqs.get("ammo")
	if not (am is Dictionary) or int(am.get("qty", 0)) <= 0:
		if not _refill_ammo():
			return false
		am = eqs.get("ammo")
	if not ctx.rng.chance("combat", _ammo_recovery_pct(str(am.def))):
		am["qty"] = int(am.qty) - 1
		if int(am.qty) <= 0:
			_refill_ammo()
			_st_dirty = true
	return true


func _refill_ammo() -> bool:
	var eqs := _equipment()
	var am: Variant = eqs.get("ammo")
	var bank: Variant = _bank()
	if not (am is Dictionary) or bank == null:
		return false
	var n: int = int(bank.count(str(am.def)))
	if n <= 0:
		eqs.erase("ammo")
		_st_dirty = true
		return false
	bank.remove(str(am.def), n)
	am["qty"] = n
	return true


## Probabilità (0..1) di recuperare la munizione: base delle frecce + ammo_save_pct (col suo tetto di catalogo), poi
## tetto COMBINATO `ammo_recovery_max_pct` dai dati: restano sempre munizioni da consumare (QA82 Q82-2).
func _ammo_recovery_pct(ammo_def: String) -> float:
	var r := ctx.modifiers.total_add_capped("ammo_save_pct")
	if str(ctx.data.item(ammo_def).get("subcategory", "")) == "arrow":
		r += float(_rules().ammo_arrow_recovery_pct)
	return clampf(r, 0.0, float(_rules().ammo_recovery_max_pct)) / 100.0


func _ammo_recovery() -> float:
	var am: Variant = _equipment().get("ammo")
	return _ammo_recovery_pct(str(am.def)) if am is Dictionary else clampf(
		ctx.modifiers.total_add_capped("ammo_save_pct"), 0.0, float(_rules().ammo_recovery_max_pct)) / 100.0


func _bank_ammo_stock() -> int:
	var am: Variant = _equipment().get("ammo")
	var bank: Variant = _bank()
	if am is Dictionary and bank != null:
		return int(bank.count(str(am.def)))
	return 0


func _oil_in_use() -> bool:
	var am: Variant = _equipment().get("ammo")
	return am is Dictionary and str(ctx.data.item(str(am.def)).get("subcategory", "")) == "oil"


# ====================================================================== dungeon (docs/05 §8)

func dungeon_def(dungeon_id: String) -> Dictionary:
	return ctx.data.get_def("dungeons", dungeon_id)


func dungeon_unlocked(dungeon_id: String) -> bool:
	var d := dungeon_def(dungeon_id)
	if d.is_empty():
		return false
	var req: Dictionary = d.get("unlock", {})
	return hero_unlock_level() >= int(req.get("hero_level", 1)) and (ctx.state.get("unlocks", []) as Array).has("dungeon:" + dungeon_id)


## Dungeon dei dati in ordine, con "unlocked" e "clears".
func dungeons() -> Array:
	var out: Array = []
	for d in ctx.data.table("dungeons"):
		out.append({"id": d.id, "def": d, "unlocked": dungeon_unlocked(str(d.id)), "clears": dungeon_clears(str(d.id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.def.order) < int(b.def.order))
	return out


func dungeon_clears(dungeon_id: String) -> int:
	return int(state.dungeon_clears.get(dungeon_id, 0))


## Stato della corsa in corso: {"id","wave","total"} o {}.
func dungeon_progress() -> Dictionary:
	if not in_dungeon():
		return {}
	var a := _act()
	return {"id": str(a.dungeon), "wave": int(a.get("wave", 0)), "total": (dungeon_def(str(a.dungeon)).waves as Array).size()}


func set_dungeon_repeat(on: bool) -> void:
	state["dungeon_repeat"] = on


## Entra nel dungeon: sequenza di ondate con boss finale, senza cambio di equipaggiamento. false se bloccato.
func start_dungeon(dungeon_id: String) -> bool:
	if not dungeon_unlocked(dungeon_id):
		return false
	var d := dungeon_def(dungeon_id)
	return _begin({"zone": str(d.zone), "monster": "", "mode": "dungeon", "dungeon": dungeon_id, "wave": 0})


## Mostro di un'ondata: lo stesso mostro dei dati con il bonus di livello (statistiche ricalcolate dal livello).
func _wave_mon(dd: Dictionary, wave: int) -> Dictionary:
	var waves: Array = dd.waves
	var w: Dictionary = waves[clampi(wave, 0, waves.size() - 1)]
	var base: Dictionary = ctx.data.get_def("monsters", str(w.monster))
	var bonus := int(w.get("level_bonus", 0))
	if bonus == 0:
		return base
	var key := "%s+%d" % [base.id, bonus]
	if _wave_cache.has(key):
		return _wave_cache[key]
	var m: Dictionary = base.duplicate(true)
	var lv := int(base.level) + bonus
	var s := Formulas.monster_stats(lv, str(base.type))
	m["level"] = lv
	m["stats"] = {"hp": s.hp, "max_hit": s.max_hit, "accuracy": s.accuracy, "evasion": s.evasion, "armor": s.armor,
		"ward": s.ward, "attack_interval_s": s.attack_interval_s}
	m["xp"] = s.xp
	m["gold"] = [s.gold_min, s.gold_max]
	m["ckey"] = key
	_wave_cache[key] = m
	return m


## Rischio di una corsa (docs/05 §6 applicato alle ondate): {"level": "green"|"yellow"|"red", "worst_hit", "threshold_hp",
## "food_per_run", "food_have", "run_time"}. Rosso: un colpo (o il boss) può uccidere prima che l'auto-mangiare intervenga,
## o uno scontro è perso; giallo: il cibo non basta per una corsa.
func dungeon_risk(dungeon_id: String) -> Dictionary:
	var dd := dungeon_def(dungeon_id)
	if dd.is_empty():
		return {}
	var st := _stats()
	var cfg := auto_eat_cfg()
	var mx := float(st.hp)
	var worst := 0.0
	var loss_total := 0.0
	var time_total := 0.0
	var bad := false
	for w in (dd.waves as Array).size():
		var mon := _wave_mon(dd, w)
		var est := estimate_mon(mon, _scaled(mon, _era()), {})
		worst = maxf(worst, float(est.worst_hit))
		loss_total += maxf(0.0, float(est.loss_per_kill))
		time_total += float(est.cycle)
		bad = bad or bool(est.lethal) or bool(est.unwinnable)
	var thr_hp := mx * float(cfg.threshold_pct) / 100.0
	var heal := _food_heal_value(_first_food_or_slot(), float(cfg.efficiency)) if not _first_food_or_slot().is_empty() else 0.0
	var food_per_run := loss_total / heal if heal > 0.0 else (INF if loss_total > 0.0 else 0.0)
	var level := "green"
	if bad or worst >= (thr_hp if loss_total > 0.0 else mx) or (loss_total > 0.0 and heal <= 0.0):
		level = "red"
	elif food_per_run > float(food_available()):
		level = "yellow"
	return {"level": level, "worst_hit": worst, "threshold_hp": thr_hp, "food_per_run": food_per_run,
		"food_have": food_available(), "run_time": time_total}


func _dungeon_after_kill(a: Dictionary, dd: Dictionary) -> void:
	a["wave"] = int(a.get("wave", 0)) + 1
	if int(a.wave) < (dd.waves as Array).size():
		return
	_dungeon_complete(dd)
	if bool(state.dungeon_repeat):
		a["wave"] = 0
	else:
		_set_activity({})
		_st_dirty = true


## Premio di fine dungeon (oro, materiali con il bonus bottino, casse), traguardi di completamento e missioni.
func _dungeon_complete(dd: Dictionary) -> void:
	var did := str(dd.id)
	var reward: Dictionary = dd.completion_reward
	var bank: Variant = _bank()
	var scopes: Array = [did, "all"]
	var gold := int(round(ctx.modifiers.apply(float(reward.get("gold", 0)), "dungeon_loot_pct", scopes)))
	var items: Array = []
	if bank != null:
		if gold > 0:
			bank.add_gold(gold)
		for it in reward.get("items", []):
			var q := int(round(ctx.modifiers.apply(float(_qty(it.get("qty", 1))), "dungeon_loot_pct", scopes)))
			if q > 0:
				bank.add(str(it.item), q, "dungeon")
				items.append({"id": str(it.item), "qty": q})
	var crates: Array = []
	for c in reward.get("crates", []):
		for i in int(c.get("qty", 1)):
			crates.append(str(c.id))
			ctx.events.crate_found.emit(str(c.id), "dungeon:" + did)
	var stats: Variant = ctx.state.get("stats")
	if stats is Dictionary:
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + gold
	state.dungeon_clears[did] = dungeon_clears(did) + 1
	_push({"k": "dungeon_done", "d": did, "gold": gold, "items": items, "crates": crates, "run": run_summary()})
	_run = _new_tally()
	ctx.events.objective_event.emit("complete_dungeon", {"dungeon": did, "qty": 1})
	_apply_dungeon_milestones()
	for ms_def in dd.get("mastery_milestones", []):
		if int(ms_def.completions) == dungeon_clears(did) and ms_def.has("title"):
			var titles: Variant = ctx.state.get("titles")
			if titles is Array and not (titles as Array).has(str(ms_def.title)):
				(titles as Array).append(str(ms_def.title))
				_notice("info", "UI_C2_DUNGEON_TITLE")


## Traguardi (10/50/250 completamenti): bonus permanenti come fonte "dungeon:<id>".
func _apply_dungeon_milestones() -> void:
	if ctx.modifiers == null:
		return
	for d in ctx.data.table("dungeons"):
		var did := str(d.id)
		var n := dungeon_clears(did)
		var mods: Array = []
		for ms_def in d.get("mastery_milestones", []):
			if n >= int(ms_def.completions):
				mods.append_array((ms_def.get("modifiers", []) as Array).duplicate(true))
		if mods.is_empty():
			ctx.modifiers.clear_source(DUNGEON_SOURCE + did)
		else:
			ctx.modifiers.set_source(DUNGEON_SOURCE + did, mods)


## Incursioni dei dati (vedi EndgameCombat.raids): id, def, unlocked, cd_s, clears, best_s.
func raids() -> Array:
	return eg.raids()


# ====================================================================== stima analitica (motore in modalità attesa)

## Stima di uno scontro ripetuto col mostro dei dati (vedi estimate_mon). `precise` = misura completa (offline);
## senza, la stima rapida a valori attesi per l'interfaccia (indicatore "Sicuro in idle", tooltip).
func estimate(monster_id: String, precise: bool = false) -> Dictionary:
	var mon: Dictionary = ctx.data.get_def("monsters", monster_id)
	if mon.is_empty():
		return {}
	return estimate_mon(mon, _scaled(mon, _era()), {"precise": precise})


func _est_food_sig() -> String:
	return "%s|%d|%d" % [_first_food_or_slot(), _auto_eat_tier(), int(state.eat_pct)]


## Stima di uno scontro ripetuto: fa girare CombatSim in modalità "valori attesi" (stesso codice del tick vero) per
## cicli di scontro+ricomparsa. Con cibo: l'eroe mangia come nel gioco (cibo infinito, si contano le porzioni) e
## `loss_per_kill` è la vita netta persa per uccisione; senza cibo ogni scontro parte da vita piena.
## opts: hp_mult, dmg_mult (Ricercato), precise (misura Monte Carlo stratificata), target (bersaglio della taglia).
func estimate_mon(mon: Dictionary, ms: Dictionary, opts_in: Dictionary) -> Dictionary:
	var opts := opts_in
	var trial_hp := float(trial_rules().get("monster_hp_mult", 1.0))
	if trial_hp != 1.0:                         # Prova «Maratona»: stessa vita maggiorata del tick (spawn)
		opts = opts_in.duplicate()
		opts["hp_mult"] = float(opts_in.get("hp_mult", 1.0)) * trial_hp
	var st0 := _stats_for(stance_for(mon))      # ricostruisce le statistiche se serve
	var key := "%s|%d|%s|%s|%s|%d|%d" % [mon.get("ckey", mon.id), _era(), _est_food_sig(), JSON.stringify(opts), str(_abil_ver),
		st0.hash(), ms.hash()]
	if _est_cache.has(key):
		return _est_cache[key]
	var res := _estimate_run(mon, ms, st0, opts)
	_est_cache[key] = res
	return res


## Stima: prima un passaggio rapido in modalità "valori attesi" (durata dello scontro), poi la misura vera: il motore
## reale (CombatSim con RNG) su K scontri+ricomparse, con numeri casuali stratificati (StratifiedRng). Il motore è lo
## stesso del tick, quindi tecniche, risorse, meccaniche dei boss e discretizzazione sono identiche; la stratificazione
## porta lo scarto statistico sotto l'1% con poche centinaia di cicli (docs/05 §12: "simula 200 uccisioni...").
func _estimate_run(mon: Dictionary, ms: Dictionary, st: Dictionary, opts: Dictionary) -> Dictionary:
	var k: Dictionary = Formulas.k().combat
	var hp_mult := float(opts.get("hp_mult", 1.0))
	var sim := _est_sim
	sim.configure(_sim_params(st, mon, ms, true))
	var sigma := sim.hp_sigma(float(ms.hp) * hp_mult)
	var quick := _est_pass(mon, ms, st, opts, {"expect": true, "sigma": sigma})
	var res := quick
	var dt := FixedStepClock.STEP
	var respawn_ticks := int(ceil(float(k.respawn_s) / dt - 1e-6))
	# FIX-COMBATTIMENTO (QA4 #1): la misura vera gira anche sugli scontri letali: conta la frazione di scontri persi
	# (p_die) e la durata media di quelli persi, così l'offline modella le morti come il tick (rinascita compresa)
	if bool(opts.get("precise", false)) and not bool(quick.unwinnable):
		var mc_s := EST_MC_SECONDS / maxf(1.0, float(opts.get("mc_div", 1)))
		var cyc_s := float(quick.ttk) + respawn_ticks * dt
		# scontri lunghi (boss da minuti): ogni ciclo media già molti colpi, basta meno cicli (budget di tempo simulato)
		var c_min := clampi(int(EST_MC_SECONDS / maxf(cyc_s, 1e-6)), EST_MC_LONG_MIN, EST_MC_MIN)
		var cycles := clampi(int(mc_s / cyc_s), int(opts.get("mc_min", c_min)), EST_MC_MAX)
		res = _est_pass(mon, ms, st, opts, {"expect": false, "cycles": cycles})
		if float(res.p_die) > 0.01 and cycles < EST_MC_MIN and not opts.has("mc_min"):
			# scontro a rischio: il numero di morti offline dipende molto da p_die, si misura con tutti i cicli
			res = _est_pass(mon, ms, st, opts, {"expect": false, "cycles": EST_MC_MIN})
	res["cycle"] = float(res.ttk) + respawn_ticks * dt
	res["kills_per_h"] = 3600.0 / float(res.cycle)
	var ttk := maxf(float(res.ttk), 1e-9)
	res["m_dps"] = float(res.dmg_per_kill) / ttk
	res["p_dps"] = float(res.mhp) / ttk
	res["loss_per_kill"] = float(res.dmg_per_kill) - float(res.heal_per_kill) - float(res.regen_per_kill)
	return res


func _est_pass(mon: Dictionary, ms: Dictionary, st: Dictionary, opts: Dictionary, mode: Dictionary) -> Dictionary:
	var k: Dictionary = Formulas.k().combat
	var expect: bool = mode.expect
	var sim := _est_sim
	var params := _sim_params(st, mon, ms, expect)
	var strat: StratifiedRng = null
	var warm := 1 if expect else EST_MC_WARM
	var total_cycles := 0
	if not expect:
		total_cycles = warm + int(mode.cycles)
		strat = StratifiedRng.new(int(mode.cycles), int(str(mon.id).hash()) & 0x7fffffff)
		params["rng"] = strat
	sim.configure(params)
	sim.reset_acc()
	var mx := float(st.hp)
	var cfg := auto_eat_cfg()
	var heal_each := _food_heal_value(_first_food_or_slot(), float(cfg.efficiency)) if not _first_food_or_slot().is_empty() else 0.0
	var eat_mode := heal_each > 0.0
	var thr := mx * float(cfg.threshold_pct) / 100.0
	var target := mx * float(cfg.target_pct) / 100.0
	var hp_start := (thr + target) * 0.5 if eat_mode else mx
	var h := {"hp": hp_start, "rt": CombatSim.new_rt()}
	var a := {"enemy": {}, "hero_cd": 0.0, "mon_cd": 0.0}
	if eat_mode:
		sim.eat_cb = func() -> void:
			if float(h.hp) >= thr:
				return
			var guard := 0
			while float(h.hp) < target and guard < 64:
				guard += 1
				h["hp"] = minf(mx, float(h.hp) + heal_each)
				sim.acc["food"] = float(sim.acc.food) + 1.0
	else:
		sim.eat_cb = Callable()
	var dt := FixedStepClock.STEP
	var respawn_ticks := int(ceil(float(k.respawn_s) / dt - 1e-6))
	var hp_mult := float(opts.get("hp_mult", 1.0))
	var dmg_mult := float(opts.get("dmg_mult", 1.0))
	var sigma := float(mode.get("sigma", 0.0))
	var meas := {"kills": 0, "t": 0.0, "regen": 0.0, "lethal": 0, "deaths": 0.0, "t_die": 0.0, "cycles": 0}
	var chain_l := int(opts.get("chain", 0)) if not expect else 0
	var pos_d: Array = []
	var pos_n: Array = []
	var pos_td: Array = []
	for i in chain_l:
		pos_d.append(0.0)
		pos_n.append(0)
		pos_td.append(0.0)
	sim.surv_mode = est_surv and not expect
	var t_total := 0.0
	var cyc := 0
	var unwinnable := false
	while true:
		if expect:
			if cyc >= warm + EST_MIN_CYCLES and t_total >= EST_SECONDS:
				break
			if cyc >= EST_MAX_CYCLES:
				break
		elif cyc >= total_cycles:
			break
		var measuring := cyc >= warm
		if cyc == warm:
			sim.reset_acc()
		var pos := -1
		if chain_l > 0:
			pos = (cyc - warm) % chain_l if measuring else 0
			if pos == 0:
				# catena: si riparte a vita piena e senza risorse, come dopo una rinascita; la posizione dice quanti
				# scontri sono passati dalla rinascita (il rischio dipende molto dalla vita con cui si arriva)
				h["hp"] = mx
				h["rt"] = CombatSim.new_rt()
				sim.invalidate()
		if not eat_mode:
			h["hp"] = mx
		var reg_gain := 0.0
		for i in respawn_ticks:
			sim.tick_timers(h, dt, false)
			if float(h.hp) < mx:
				reg_gain += _est_regen(h, sim, st, dt)
		t_total += respawn_ticks * dt
		var shift := 0.0
		if expect:
			var zq: float = EST_Z[(cyc * EST_Z_STRIDE) % EST_Z.size()]
			shift = zq * sigma
		else:
			strat.begin_cycle(-1 if bool(mode.get("plain", false)) else cyc - warm)
		sim.spawn(h, a, hp_mult, dmg_mult, bool(opts.get("target", false)), shift)
		sim.surv = 1.0
		var tdie := 0.0                 # somma di (probabilità di morire in questo passo) x tempo
		var t := 0.0
		var steps := 0
		var r := CombatSim.R_NONE
		while steps < EST_STEPS_CAP:
			# misura Monte Carlo: i passi senza eventi si fondono (risultato identico, 5-10 volte meno passi)
			var m := 1 if (expect or not est_fast) else sim.ticks_until_event(h, a, dt)
			var sdt := dt * m
			sim.tick_timers(h, sdt, true)
			if float(h.hp) < mx:
				reg_gain += _est_regen(h, sim, st, sdt)
			var s0 := sim.surv
			r = sim.step(h, a, sdt)
			steps += m
			t += sdt
			tdie += (s0 - sim.surv) * t
			if r != CombatSim.R_NONE:
				break
		t_total += t
		cyc += 1
		if measuring and r != CombatSim.R_NONE and r != CombatSim.R_STOP:
			meas["cycles"] = int(meas.cycles) + 1
			if pos >= 0:
				var dpc := (1.0 - sim.surv) if r == CombatSim.R_KILL else 1.0
				pos_n[pos] = int(pos_n[pos]) + 1
				pos_d[pos] = float(pos_d[pos]) + dpc
				pos_td[pos] = float(pos_td[pos]) + tdie + (sim.surv * t if r == CombatSim.R_DIE else 0.0)
		if r == CombatSim.R_KILL:
			if measuring:
				meas["kills"] = int(meas.kills) + 1
				meas["t"] = float(meas.t) + t
				meas["regen"] = float(meas.regen) + reg_gain
				meas["deaths"] = float(meas.deaths) + (1.0 - sim.surv)
				meas["t_die"] = float(meas.t_die) + tdie
		elif r == CombatSim.R_DIE:
			meas["lethal"] = int(meas.lethal) + 1
			if measuring:
				meas["deaths"] = float(meas.deaths) + 1.0
				meas["t_die"] = float(meas.t_die) + tdie + sim.surv * t
			# come il tick: l'Eroe si rialza a vita piena (il Ferito è stimato a parte dall'offline)
			h["hp"] = hp_start if expect else mx
			h["rt"] = CombatSim.new_rt()
			sim.invalidate()
			if expect and cyc >= warm + 2:
				break
		else:
			unwinnable = true
			break
	sim.eat_cb = Callable()
	sim.rng = null
	sim.surv_mode = false
	var kills := maxi(1, int(meas.kills))
	var ttk := float(meas.t) / kills if int(meas.kills) > 0 else t_total
	var mhp := float(mon.stats.hp) * Formulas.era_monster_mult(_era()) * hp_mult
	var mi := float(ms.attack_interval_s)
	var worst := float(ms.max_hit)
	var def_v := float(st.arm) if str(mon.damage_type) == "physical" else float(st.ward)
	worst *= (1.0 - Formulas.damage_reduction(def_v, float(mon.level))) \
		* Formulas.triangle_mult(str(mon.style), str(st.style)) * float(st.dmg_taken_mult) * dmg_mult
	var mechs: Array = mon.get("mechanics", [])
	if mechs.has("heavy_blow"):
		worst *= float(mechanics().get("heavy_blow", {}).get("effect", {}).get("hit_mult", 1.0))
	var g: Array = mon.get("gold", [0, 0])
	var rew := Formulas.era_reward_mult(_era())
	var gold_avg := ctx.modifiers.apply((float(g[0]) + float(g[1])) * 0.5 * rew, "gold_gain_pct", ["combat", "all"])
	return {"monster": str(mon.id), "ttk": ttk,
		"swings": float(sim.acc.swings) / kills, "hits": float(sim.acc.hits) / kills, "casts": float(sim.acc.casts) / kills,
		"dmg_per_kill": float(sim.acc.dmg_in) / kills, "heal_per_kill": float(sim.acc.heal) / kills,
		"regen_per_kill": float(meas.regen) / kills, "food_per_kill": float(sim.acc.food) / kills,
		"regen_pps": mx * float(st.regen_pct) / 100.0, "worst_hit": worst, "mhp": mhp,
		"m_hit": Formulas.hit_chance(float(ms.accuracy), float(st.eva)),
		"xp": mon_xp(mon, _era()), "gold": gold_avg, "mon_interval": mi,
		"lethal": int(meas.lethal) > 0, "unwinnable": unwinnable, "level": int(mon.level), "type": str(mon.type),
		# frazione di scontri persi e loro durata media (solo misura vera; nel passaggio rapido 0)
		"p_die": float(meas.deaths) / float(meas.cycles) if float(meas.deaths) > 0.0 else 0.0,
		"t_die": float(meas.t_die) / float(meas.deaths) if float(meas.deaths) > 0.0 else 0.0,
		# porzioni per scontro: i percorsi pesati sopravvivono sempre, ma uno scontro perso dura t_die invece di ttk
		"food_per_att": float(sim.acc.food) / float(maxi(1, int(meas.cycles))) * _food_death_factor(meas, ttk),
		"mc": not expect and est_surv,
		"p_pos": _pos_ratio(pos_d, pos_n), "t_die_pos": _pos_ratio(pos_td, pos_d)}


func _pos_ratio(num: Array, den: Array) -> Array:
	var out: Array = []
	for i in num.size():
		out.append(float(num[i]) / float(den[i]) if float(den[i]) > 0.0 else 0.0)
	return out


func _food_death_factor(meas: Dictionary, ttk: float) -> float:
	var cyc := float(maxi(1, int(meas.cycles)))
	var pd := float(meas.deaths) / cyc
	if pd <= 0.0 or ttk <= 0.0:
		return 1.0
	var td := float(meas.t_die) / float(meas.deaths)
	return clampf((1.0 - pd) + pd * td / ttk, 0.0, 1.0)


func _est_regen(h: Dictionary, sim: CombatSim, st: Dictionary, dt: float) -> float:
	var mx := float(st.hp)
	if float(h.hp) >= mx:
		return 0.0
	var rp := float(sim.effective(h.rt).regen_pct)
	var g := minf(mx - float(h.hp), mx * rp / 100.0 * dt)
	h["hp"] = float(h.hp) + g
	return g


## Indicatore "Sicuro in idle" (docs/05 §6): {"level": "green"|"yellow"|"red", ...numeri per il tooltip}.
func idle_safety(monster_id: String) -> Dictionary:
	var est := estimate(monster_id)
	if est.is_empty():
		return {}
	var st := _stats()
	var cfg := auto_eat_cfg()
	var mx := float(st.hp)
	var thr_hp := mx * float(cfg.threshold_pct) / 100.0
	var losing := float(est.loss_per_kill) > 0.0
	var ref_hp := thr_hp if losing else mx
	var heal := _food_heal_value(_first_food_or_slot(), float(cfg.efficiency))
	var food_per_h := 0.0
	var food_hours := -1.0
	if losing and heal > 0.0:
		food_per_h = float(est.loss_per_kill) * float(est.kills_per_h) / heal
		var have := food_available()
		food_hours = float(have) / food_per_h if food_per_h > 0.0 else -1.0
	var level := "green"
	var reason := ""
	if float(est.worst_hit) >= ref_hp or (losing and heal <= 0.0) or bool(est.lethal) or bool(est.unwinnable):
		level = "red"
		reason = "hit"
	elif losing and food_hours >= 0.0 and food_hours < IDLE_FOOD_RED_HOURS:
		# QA1: con 0 cibo l'indicatore restava giallo e l'eroe moriva in pochi minuti d'assenza (8 casi su 9)
		level = "red"
		reason = "food"
	elif losing and food_hours >= 0.0 and food_hours < offline_cap_hours():
		level = "yellow"
		reason = "food"
	return {"level": level, "reason": reason, "worst_hit": est.worst_hit, "threshold_hp": thr_hp, "food_per_h": food_per_h,
		"food_hours": food_hours, "kills_per_h": est.kills_per_h, "losing": losing}


## Preparazione per combattere (Q97): cosa manca all'Eroe prima di uno scontro. {"weapon": bool, "armor_n": int, "food": bool,
## "missing": ["weapon"|"armor"|"food"], "unprepared": bool}. Solo informazione per l'avviso della scheda Combattimento:
## nessun blocco, nessun numero di bilanciamento. Armatura = almeno un pezzo tra elmo, corpo, gambe, guanti, stivali.
func readiness() -> Dictionary:
	var armor_n := 0
	for s in ARMOR_SLOTS:
		if not equipped(s).is_empty():
			armor_n += 1
	var has_weapon := not equipped("weapon").is_empty()
	var has_food := food_available() > 0
	var missing: Array = []
	if not has_weapon:
		missing.append("weapon")
	if armor_n == 0:
		missing.append("armor")
	if not has_food:
		missing.append("food")
	return {"weapon": has_weapon, "armor_n": armor_n, "food": has_food, "missing": missing, "unprepared": not missing.is_empty()}


func _first_food_or_slot() -> String:
	if trial_food_blocked():
		return ""
	var f := _first_food()
	if not f.is_empty():
		return f
	for fid in state.food:
		if not str(fid).is_empty():
			return str(fid)
	return ""


func offline_cap_hours() -> float:
	var off: Dictionary = ctx.data.constants.get("offline", {})
	return minf(float(off.get("cap_max_h", 0)), float(off.get("cap_base_h", 0)) + ctx.modifiers.total_add("offline_cap_hours"))


# ====================================================================== offline (analitico)

## Soglia TECNICA (non di bilanciamento): sotto un secondo avanzato non vale la pena di cambiare attività.
const OFFLINE_FALLBACK_MIN_S := 1.0

## Mansione di riserva (QA81 M5, docs/05 §12): se il combattimento offline si ferma prima del tempo (Eroe caduto, cibo o
## munizioni finiti, ritiro in Estrema), il tempo che avanza va all'ULTIMA mansione svolta prima del combattimento, con la
## stessa simulazione analitica (R-OFF-2/3), invece di andare perso. Interruttore: state.safe_fallback. Vale per zone e
## dungeon; non per incursioni, Breccia e boss mondiali (lì il tempo è parte della sfida). Il Bentornato lo dice.
func safe_fallback() -> bool:
	return bool(state.safe_fallback)


func set_safe_fallback(on: bool) -> void:
	state["safe_fallback"] = on


func fallback_action() -> String:
	var aid := str(state.get("fallback_action", ""))
	var sk: Variant = _skills()
	if aid.is_empty() or sk == null or not sk.has_method("can_start") or not ctx.data.has_action(aid) or str(sk.can_start(aid)) != "":
		return ""
	return aid


func simulate_offline(seconds: float) -> Dictionary:
	var mode := str(_act().get("mode", ""))
	var was_combat := str(_act().get("type", "")) == "combat"
	var report := _simulate_offline_core(seconds)
	if was_combat and eg.is_endgame_mode(mode):
		return _continue_after_endgame(report, seconds)
	if not was_combat or report.is_empty() or eg.is_endgame_mode(mode) or not safe_fallback():
		return report
	if not (str(report.get("stopped", "")) in ["death", "death_risk", "no_ammo", "no_food"]):
		return report
	var leftover := seconds - float(report.get("seconds", seconds))
	if leftover < OFFLINE_FALLBACK_MIN_S:
		return report
	var aid := fallback_action()
	if aid.is_empty():
		report["fallback"] = {"action": "", "seconds": leftover}      # nessuna mansione di riserva: il Bentornato lo spiega
		return report
	var st := _stats()
	state["hp"] = minf(float(st.hp), float(state.hp) + float(st.hp) * float(st.regen_pct) / 100.0 * leftover)
	state["wounded_s"] = maxf(0.0, float(state.wounded_s) - leftover)
	_dec_class_timers(leftover)
	var sk: Variant = _skills()
	if not bool(sk.start(aid)):
		return report
	var r: Dictionary = sk.simulate_offline(leftover)
	report["fallback"] = {"action": aid, "seconds": leftover, "skills": r}
	return report


## Dopo un incontro di fine gioco concluso offline (Q118-1): se l'Eroe ha ripreso l'attività di prima, il tempo che avanza
## è suo (zona/dungeon: stessa simulazione analitica, resoconti uniti; mansione: come il ripiego). Il Bentornato lo dice.
func _continue_after_endgame(report: Dictionary, seconds: float) -> Dictionary:
	if report.is_empty():
		return report
	var leftover := seconds - float(report.get("seconds", 0.0))
	if leftover < OFFLINE_FALLBACK_MIN_S:
		return report
	if in_combat():
		var r2 := _simulate_offline_core(leftover, false)
		if r2.is_empty():
			return report
		for k in ["kills", "gold", "crates", "food_used", "ambushes", "deaths"]:
			report[k] = int(report.get(k, 0)) + int(r2.get(k, 0))
		report["xp"] = float(report.get("xp", 0.0)) + float(r2.get("xp", 0.0))
		var itm: Dictionary = report.get("items", {})
		for iid in (r2.get("items", {}) as Dictionary):
			itm[iid] = int(itm.get(iid, 0)) + int(r2.items[iid])
		report["items"] = itm
		var rows: Array = report.get("rows", [])
		rows.append_array(r2.get("rows", []))
		report["rows"] = rows
		report["stopped"] = str(r2.get("stopped", ""))
		report["food_out"] = bool(r2.get("food_out", false))
		report["died"] = bool(report.get("died", false)) or bool(r2.get("died", false))
		report["monster"] = str(r2.get("monster", report.get("monster", "")))
		if r2.has("monster_name"):
			report["monster_name"] = r2.monster_name
		report["seconds"] = float(report.get("seconds", 0.0)) + float(r2.get("seconds", 0.0))
		rows.append({"key": "UI_OFFL_RESUMED_FIGHT", "params": {"time": NumberFormat.fmt_time(leftover)}})
		return report
	var sk: Variant = _skills()
	var aid := str(sk.current_action()) if sk != null and sk.has_method("current_action") else ""
	if aid.is_empty():
		return report
	var r: Dictionary = sk.simulate_offline(leftover)
	report["fallback"] = {"action": aid, "seconds": leftover, "skills": r, "resumed": true}
	return report


func _simulate_offline_core(seconds: float, advance_clocks: bool = true) -> Dictionary:
	var rs: Variant = _run_sys()
	if rs != null:
		rs.suspend()                 # la Corsa non agisce offline (91 §3.9): statistiche senza le sue voci
	_ensure()
	if advance_clocks:
		eg.advance_offline_clocks(seconds)
	var a := _act()
	if str(a.get("type", "")) != "combat":
		var st0 := _stats()
		state["hp"] = minf(float(st0.hp), float(state.hp) + float(st0.hp) * float(st0.regen_pct) / 100.0 * seconds)
		state["wounded_s"] = maxf(0.0, float(state.wounded_s) - seconds)
		_dec_class_timers(seconds)
		state["rt"] = CombatSim.new_rt()
		_sim.invalidate()
		return {}
	var left := seconds
	var wound0 := float(state.wounded_s)
	var report := {"kills": 0, "xp": 0.0, "gold": 0, "items": {}, "crates": 0, "food_used": 0, "stopped": "",
		"monster": "", "died": false}
	if float(a.get("revive_s", 0.0)) > 0.0:
		var rv := float(a.revive_s)
		if left < rv:
			a["revive_s"] = rv - left
			return {}
		left -= rv
		_revive(a)
		if not in_combat():
			return {}
	state["wounded_s"] = maxf(0.0, float(state.wounded_s) - left)
	_dec_class_timers(seconds)       # QA82 H4: la ricarica del cambio classe scorre anche con il combattimento in corso
	var en0: Dictionary = (a.get("enemy", {}) as Dictionary).duplicate(true)
	a["enemy"] = {}
	a["respawn_s"] = 0.0
	state["rt"] = CombatSim.new_rt()
	_sim.invalidate()
	_sim_key = ""
	if eg.is_endgame_mode(str(a.get("mode", ""))):
		return eg.offline(a, left, report, en0)
	if str(a.get("mode", "")) == "dungeon":
		return _offline_dungeon(a, left, report, wound0)
	var ids: Array = []
	var sel := str(a.get("monster", ""))
	if not sel.is_empty():
		ids.append(sel)
	else:
		for mn in monsters_of(str(a.zone)):
			if str(mn.type) == "normal":
				ids.append(str(mn.id))
	if ids.is_empty() or left <= 0.0:
		return {}
	var units: Array = []
	for mid in ids:
		units.append({"mon": ctx.data.get_def("monsters", str(mid)), "n": 1})
	return _offline_units(a, units, 1, left, report, wound0)


## Cuore dell'offline: `units` = scontri (mostro + numero di scontri per "giro"); un "giro" è una corsa del dungeon o
## una uccisione media nelle zone. Calcola quanti giri entrano nel tempo, i limiti (munizioni, cibo, morte attesa),
## poi estrae davvero i drop. Ritorna il resoconto.
func _offline_units(a: Dictionary, units: Array, per_lap: int, left: float, report: Dictionary, wound0: float,
		max_laps: int = -1) -> Dictionary:
	var st := _stats()
	var era := _era()
	var ests: Array = []
	var lap_time := 0.0
	var lap_loss := 0.0
	var lap_swings := 0.0
	var b: Variant = _bounty()
	var is_dungeon := per_lap > 1
	# misura Monte Carlo divisa tra i mostri del giro: la precisione del giro medio resta quella di un mostro solo,
	# il costo non cresce col numero di mostri della zona (offline 24 h ≤ 0,5 s, resoconto 47)
	var est_opts := {"precise": true} if units.size() <= 1 else {"precise": true, "mc_div": units.size()}
	for u in units:
		var mon: Dictionary = u.mon
		var est := estimate_mon(mon, _scaled(mon, era), est_opts)
		ests.append(est)
		lap_time += float(est.cycle)
		lap_loss += float(est.loss_per_kill)
		lap_swings += float(est.swings)
	if not is_dungeon:
		var n_u := float(units.size())
		lap_time /= n_u
		lap_loss /= n_u
		lap_swings /= n_u
	# Ricercati: scontri più lunghi sul bersaglio della taglia attiva
	if b != null and not is_dungeon:
		var extra := 0.0
		var cnt := 0.0
		for i in units.size():
			var mid := str((units[i].mon as Dictionary).id)
			if bool(b.is_target(mid)):
				extra += float(b.wanted_chance()) * (float(b.wanted_mults().hp) - 1.0) * float(ests[i].ttk)
				cnt += 1.0
		if cnt > 0.0:
			lap_time += extra / float(units.size())
	for e in ests:
		if bool(e.unwinnable):
			state["wounded_s"] = float(state.wounded_s)
	# Imboscate (valore atteso, come il tick: frazione delle uccisioni, scontri piu lunghi, premio maggiorato; non uccidono)
	var amb_f := 0.0 if is_dungeon else _ambush_fraction(a, units, ests, lap_time)
	if amb_f > 0.0:
		lap_time += amb_f * _ambush_extra_time(units, ests)
	var laps_total := int(floor(left / maxf(lap_time, 1e-6)))
	if max_laps >= 0:
		laps_total = mini(laps_total, max_laps)
	var stop_reason := ""
	var died := false
	var deaths_n := 0                 # morti con rinascita (zone): l'Eroe si rialza e continua, come nel tick
	var used := -1.0
	var att_n := float(laps_total)    # scontri a statistiche piene / da Ferito (per il cibo)
	var att_w := 0.0
	var f_n := _mean_of(ests, "food_per_att")
	if amb_f > 0.0:
		f_n *= 1.0 + amb_f * (float(ambush_rules().hp_mult) * float(ambush_rules().dmg_mult) - 1.0)
	var f_w := f_n
	var wounded_frac := 0.0
	var any_unwin := false
	for e in ests:
		if bool(e.unwinnable) or float(e.get("p_die", 0.0)) >= 0.999:
			any_unwin = true
	# rischio di morte per scontro (QA4 #1): il più alto tra la frazione di scontri persi nella misura vera e il
	# modello del colpo fortunato. Zone: processo di rinascita (morte, 10 s, Ferito per 5 min) come il tick;
	# dungeon: la prima corsa fallita ferma l'attività (come il tick).
	if not any_unwin and laps_total > 0:
		if is_dungeon:
			var surv := 1.0
			var all_mc := true
			for e in ests:
				surv *= 1.0 - float(e.get("p_die", 0.0))
				all_mc = all_mc and bool(e.get("mc", false))
			var p_run := 1.0 - surv if all_mc else maxf(_death_prob_per_kill(ests, st, true), 1.0 - surv)
			if p_run > 0.0:
				var k_exp := int(floor(1.0 / p_run))
				if k_exp < laps_total:
					laps_total = maxi(k_exp, 0)
					att_n = float(laps_total)
					stop_reason = "death"
					died = true
		else:
			var rn := _offline_renewal(units, ests, st, est_opts, left, lap_time)
			report["risk"] = rn            # diagnostica (resoconto offline): probabilità e durate usate
			if not rn.is_empty():
				var k_round := mini(laps_total, int(round(float(rn.kills))))
				var d_round := int(round(float(rn.deaths)))
				if d_round >= 1 and ctx.mode_rules().offline_stops_before_death():
					# Estrema: via dal gioco l'Eroe si ritira prima della prima morte attesa (OPEN_QUESTIONS M-2)
					laps_total = mini(laps_total, int(floor(float(rn.k0))))
					att_n = float(laps_total)
					stop_reason = "death_risk"
				else:
					laps_total = k_round
					deaths_n = d_round
					att_n = float(rn.att_n)
					att_w = float(rn.att_w)
					f_w = float(rn.f_w)
					wounded_frac = float(rn.wounded_frac)
					used = left
	# limite da munizioni
	if bool(st.needs_ammo):
		var per_lap_ammo := lap_swings * (1.0 - _ammo_recovery())
		var stock := ammo_qty() + _bank_ammo_stock()
		var max_k := int(floor(float(stock) / maxf(per_lap_ammo, 1e-9)))
		if max_k < laps_total:
			var fr := float(max_k) / maxf(1.0, float(laps_total))
			att_n *= fr
			att_w *= fr
			deaths_n = int(round(deaths_n * fr))
			laps_total = max_k
			stop_reason = "no_ammo"
			used = -1.0
	# limite da cibo (QA4 #1: porzioni misurate dallo stesso motore, non stimate dalla perdita media)
	var food_used := 0
	var food_out := false
	if any_unwin:
		laps_total = 0
		stop_reason = "death"
		died = true
	elif lap_loss > 0.0 and laps_total > 0:
		var cfg := auto_eat_cfg()
		var mx := float(st.hp)
		var thr_hp := mx * float(cfg.threshold_pct) / 100.0
		var tgt_hp := mx * float(cfg.target_pct) / 100.0
		var fid := _first_food_or_slot()
		var heal := _food_heal_value(fid, float(cfg.efficiency)) if not fid.is_empty() else 0.0
		var avail := food_available()
		var needed := 0
		if heal > 0.0:
			# la misura parte da metà tra soglia e obiettivo: la vita in più all'inizio fa risparmiare porzioni
			var spare := maxf(0.0, float(state.hp) - (thr_hp + tgt_hp) * 0.5) / heal
			needed = int(round(maxf(0.0, f_n * att_n + f_w * att_w - spare)))
		if heal <= 0.0 or needed > avail:
			var buffer := maxf(0.0, float(state.hp) - thr_hp)
			var capacity := buffer + (float(avail) * heal if heal > 0.0 else 0.0) + thr_hp
			var k_death := int(floor(capacity / lap_loss))
			if k_death < laps_total:
				laps_total = k_death
				stop_reason = "death"
				died = true
				deaths_n = 0
				used = -1.0
				food_out = true       # la causa è il cibo finito, non lo scontro: il Bentornato lo dice (docs/05 §6)
			food_used = avail if heal > 0.0 else 0
		else:
			food_used = needed
	if died and ctx.mode_rules().offline_stops_before_death():
		died = false                  # Estrema: via dal gioco l'Eroe si ritira al limite del rischio, non muore (OPEN_QUESTIONS M-2)
		stop_reason = "death_risk"
	_settle_offline(a, units, laps_total, per_lap, food_used, report, ests, false, int(round(amb_f * laps_total)))
	if used < 0.0:
		used = float(laps_total) * lap_time
	if died:
		_push({"k": "die", "m": str(report.monster)})
		state["deaths"] = int(state.deaths) + 1
		ctx.events.player_died.emit(str(report.monster))
		state["wounded_s"] = wounded_duration_s()
		_st_dirty = true
		state["hp"] = float(_stats().hp)
		_set_activity({})
	elif not stop_reason.is_empty():
		_set_activity({})
	else:
		_end_hp_after(lap_loss, laps_total, food_used)
	if deaths_n > 0:
		# cadute con rinascita: l'Eroe si è rialzato ogni volta e continua (riga nel Bentornato)
		_push({"k": "die", "m": str(report.monster), "n": deaths_n})
		state["deaths"] = int(state.deaths) + deaths_n
		ctx.events.player_died.emit(str(report.monster))
		state["wounded_s"] = wounded_duration_s() * wounded_frac
		_st_dirty = true
	report["stopped"] = stop_reason
	report["food_out"] = food_out
	report["died"] = died or deaths_n > 0
	report["deaths"] = deaths_n + (1 if died else 0)
	report["seconds"] = used
	report["wounded0"] = wound0
	_push({"k": "offline", "kills": report.kills, "stopped": stop_reason})
	return report


## Tempo in più di uno scontro d'Imboscata rispetto a uno normale: rapporto dei tempi nel passaggio rapido (valori attesi,
## stesso motore: la risorsa che cresce con i colpi subiti rende lo scontro lungo meno che proporzionale), sui mostri normali.
func _ambush_extra_time(units: Array, ests: Array) -> float:
	var ar := ambush_rules()
	var era := _era()
	var s := 0.0
	var n := 0.0
	for i in units.size():
		var mon: Dictionary = units[i].mon
		if str(mon.get("type", "")) != "normal":
			continue
		var ms := _scaled(mon, era)
		var q0 := estimate_mon(mon, ms, {})
		var q1 := estimate_mon(mon, ms, {"hp_mult": float(ar.hp_mult), "dmg_mult": float(ar.dmg_mult)})
		s += maxf(0.0, float(q1.ttk) / maxf(1e-6, float(q0.ttk)) - 1.0) * _mean_of(ests, "ttk")
		n += 1.0
		break                     # un mostro rappresentativo basta (costo: 2 passaggi rapidi)
	return s / maxf(1.0, n)


## Frazione attesa di uccisioni che sono Imboscate: probabilità per comparsa e ricarica minima tra due (rinnovo).
func _ambush_fraction(a: Dictionary, units: Array, _ests: Array, lap_time: float) -> float:
	var ar := ambush_rules()
	if ar.is_empty() or not (str(a.get("mode", "")) in ["", "zone"]) or hero_level() < int(ar.min_hero_level) or not trial_rules().is_empty():
		return 0.0
	var normals := 0.0
	for u in units:
		if str((u.mon as Dictionary).get("type", "")) == "normal":
			normals += 1.0
	if normals <= 0.0:
		return 0.0
	var c := float(ar.chance_pct) / 100.0
	if c <= 0.0:
		return 0.0
	var share := normals / float(units.size())
	var n_cd := float(ar.min_interval_s) / maxf(lap_time, 1e-6)
	return 1.0 / (n_cd + 1.0 / (c * share))


func _mean_of(ests: Array, key: String) -> float:
	if ests.is_empty():
		return 0.0
	var s := 0.0
	for e in ests:
		s += float(e.get(key, 0.0))
	return s / float(ests.size())


## Morti con rinascita nelle zone (QA4 #1), come nel tick: dopo una morte l'Eroe si rialza (10 s) a vita piena e resta
## Ferito (statistiche ridotte) per `death_wounded_duration_s`. Il rischio di uno scontro dipende molto dalla vita con
## cui ci si arriva, quindi si misura per POSIZIONE nella catena di scontri dopo una rinascita (catene di OFFLINE_CHAIN
## scontri che partono a vita piena; pesi di sopravvivenza), con statistiche piene e da Ferito. Poi un piccolo processo
## a eventi (solo aritmetica, RNG deterministico, molte ripetizioni) dà i valori attesi su `left` secondi.
## {} se il rischio è nullo. Ritorna kills, deaths, k0 (uccisioni attese prima della prima morte), att_n/att_w (scontri
## a statistiche piene / da Ferito), f_w (porzioni per scontro da Ferito), wounded_frac (quota del tempo da Ferito).
func _offline_renewal(units: Array, ests: Array, st: Dictionary, est_opts: Dictionary, left: float, lap_time: float) -> Dictionary:
	var rules := _rules()
	var revive := death_delay_s() + FixedStepClock.STEP
	var win := wounded_duration_s()
	var extra := lap_time - _mean_of(ests, "cycle")      # Ricercati: tempo in più per scontro
	var base := _att_stats(ests, st, revive, extra)
	# rischio trascurabile (meno di ~1/4 di morte attesa in tutto il periodo): niente misure in più, nessuna morte
	if float(base.p) * left / maxf(1.0, float(base.a)) < OFFLINE_MIN_EXPECTED_DEATHS:
		return {}
	var era := _era()
	var opts_c := est_opts.duplicate()
	opts_c["chain"] = OFFLINE_CHAIN
	opts_c["mc_min"] = OFFLINE_CHAIN_CYCLES
	opts_c["mc_div"] = float(est_opts.get("mc_div", 1)) * 4.0     # il minimo di cicli fa da tetto: costo fisso
	var ests_n: Array = []
	for u in units:
		ests_n.append(estimate_mon(u.mon, _scaled(u.mon, era), opts_c))
	var w0 := float(state.wounded_s)
	state["wounded_s"] = maxf(1.0, w0)                    # statistiche da Ferito (si ricostruiscono da sole)
	var ests_w: Array = []
	for u in units:
		ests_w.append(estimate_mon(u.mon, _scaled(u.mon, era), opts_c))
	state["wounded_s"] = w0
	_stats()
	var tab := [_chain_table(ests_n, extra), _chain_table(ests_w, extra)]   # 0 = pieno, 1 = Ferito
	# processo a eventi: valori attesi con molte ripetizioni di `left` secondi (circa 20.000 scontri in tutto)
	var a_mean := maxf(1.0, float(tab[0].t_kill))
	var reps := clampi(int(ceil(OFFLINE_RENEWAL_ATTEMPTS / maxf(1.0, left / a_mean))), 1, 400)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED + int(str((units[0].mon as Dictionary).id).hash() & 0xffff)
	var tot := {"kills": 0.0, "deaths": 0.0, "att_n": 0.0, "att_w": 0.0, "k0": 0.0, "t_w": 0.0}
	for r in reps:
		var t := 0.0
		var wound_end := -1.0
		var j := 0
		var first := -1
		var kills := 0
		var guard := 0
		while guard < 200000:
			guard += 1
			var w := 1 if t < wound_end else 0
			var tb: Dictionary = tab[w]
			var jj := mini(j, OFFLINE_CHAIN - 1)
			var dies := rng.randf() < float(tb.p[jj])
			var dur := float(tb.t_die[jj]) + revive if dies else float(tb.t_kill)
			if t + dur > left:
				break
			if w == 1:
				tot.att_w = float(tot.att_w) + 1.0
				tot.t_w = float(tot.t_w) + minf(dur, wound_end - t)
			else:
				tot.att_n = float(tot.att_n) + 1.0
			t += dur
			if dies:
				tot.deaths = float(tot.deaths) + 1.0
				if first < 0:
					first = kills
				wound_end = t + win
				j = 0
			else:
				kills += 1
				j += 1
		tot.kills = float(tot.kills) + kills
		tot.k0 = float(tot.k0) + float(first if first >= 0 else kills)
	var nr := float(reps)
	return {"kills": float(tot.kills) / nr, "deaths": float(tot.deaths) / nr, "att_n": float(tot.att_n) / nr,
		"att_w": float(tot.att_w) / nr, "k0": float(tot.k0) / nr, "f_w": _mean_of(ests_w, "food_per_att"),
		"wounded_frac": clampf(float(tot.t_w) / nr / maxf(left, 1e-6), 0.0, 1.0),
		"p_n": tab[0].p, "p_w": tab[1].p}


## Tabella del rischio per posizione nella catena (media sui mostri della zona): p[j], t_die[j] (durata di uno scontro
## perso) e t_kill (ciclo di uno scontro vinto).
func _chain_table(ests: Array, extra: float) -> Dictionary:
	var p: Array = []
	var td: Array = []
	var nn := maxf(1.0, float(ests.size()))
	for j in OFFLINE_CHAIN:
		var ps := 0.0
		var ts := 0.0
		for e in ests:
			var pp: Array = e.get("p_pos", [])
			var tt: Array = e.get("t_die_pos", [])
			var pj := float(pp[j]) if j < pp.size() else float(e.get("p_die", 0.0))
			var tj := float(tt[j]) if j < tt.size() and float(tt[j]) > 0.0 else float(e.ttk)
			ps += pj
			ts += tj
		p.append(ps / nn)
		td.append(ts / nn)
	return {"p": p, "t_die": td, "t_kill": _mean_of(ests, "cycle") + extra}


## Probabilità media di morte per scontro (p) e durata media di uno scontro (a: vinto = ciclo, perso = t_die + rinascita).
func _att_stats(ests: Array, st: Dictionary, revive: float, extra: float) -> Dictionary:
	var p := 0.0
	var a := 0.0
	for e in ests:
		# misura vera con pesi di sopravvivenza: contiene già i colpi fortunati (probabilità esatte a ogni colpo); il
		# modello analitico resta per le stime senza misura
		var pi := float(e.get("p_die", 0.0)) if bool(e.get("mc", false)) else maxf(float(e.get("p_die", 0.0)), _death_prob_per_kill([e], st, false))
		var td := float(e.get("t_die", 0.0))
		if td <= 0.0:
			td = float(e.ttk)
		p += pi
		a += (1.0 - pi) * (float(e.cycle) + extra) + pi * (td + revive)
	var nn := maxf(1.0, float(ests.size()))
	return {"p": p / nn, "a": a / nn}


## Probabilità (per uccisione, o per corsa con chain) di morire per un colpo che supera la vita rimasta: l'eroe mangia a
## ogni tick sotto soglia, quindi il rischio vero è un singolo colpo (o la combo del boss) più alto della vita che aveva
## prima del colpo (tra soglia e obiettivo dell'auto-mangiare; senza perdita netta, vita piena).
func _death_prob_per_kill(ests: Array, st: Dictionary, chain: bool = false) -> float:
	var cfg := auto_eat_cfg()
	var mx := float(st.hp)
	var worst := 0.0
	var survive := 1.0
	var rmin := _mon_min_ratio()
	for e in ests:
		var losing := float(e.loss_per_kill) > 0.0
		var lo := mx * float(cfg.threshold_pct) / 100.0 if losing else mx
		var hi := mx * float(cfg.target_pct) / 100.0 if losing else mx
		var swings := maxf(1.0, float(e.ttk) / float(e.mon_interval))
		var pd: float
		if e.has("hit_base"):
			# FIX-COMBATTIMENTO (QA4 #4): il Colpo Devastante arriva ogni `heavy_every` s (non a ogni colpo) e la Furia
			# solo nell'ultimo 30% della vita del boss: rischio per tipo di colpo invece del caso peggiore a ogni colpo
			var wb := float(e.hit_base)
			var hm := float(e.get("heavy_mult", 1.0))
			var em := float(e.get("enrage_mult", 1.0))
			var fe := 0.3 if em > 1.0 else 0.0
			var n_h := float(e.ttk) / maxf(1.0, float(e.get("heavy_every", 1e9))) if hm > 1.0 else 0.0
			var m_hit := float(e.m_hit)
			var ls := swings * (1.0 - fe) * _log_surv(wb, lo, hi, rmin, m_hit) + swings * fe * _log_surv(wb * em, lo, hi, rmin, m_hit) \
				+ n_h * (1.0 - fe) * _log_surv(wb * hm, lo, hi, rmin, m_hit) + n_h * fe * _log_surv(wb * hm * em, lo, hi, rmin, m_hit)
			pd = 1.0 - exp(ls)
		else:
			var p_swing := _p_swing(float(e.worst_hit), lo, hi, rmin) * float(e.m_hit)
			pd = 1.0 - pow(1.0 - p_swing, swings)
		worst = maxf(worst, pd)
		survive *= 1.0 - pd
	return 1.0 - survive if chain else worst


## Probabilità che un colpo di danno massimo `w` (danno uniforme tra rmin*w e w) superi la vita, con la vita prima del
## colpo uniforme tra lo e hi.
func _p_swing(w: float, lo: float, hi: float, rmin: float) -> float:
	var hp_exp := 0.0
	var n := 12
	for i in n:
		var hp0 := lerpf(lo, hi, (float(i) + 0.5) / n)
		hp_exp += clampf((w - hp0) / maxf(1e-9, w * (1.0 - rmin)), 0.0, 1.0)
	return hp_exp / n


func _log_surv(w: float, lo: float, hi: float, rmin: float, m_hit: float) -> float:
	var p := _p_swing(w, lo, hi, rmin) * m_hit
	return -INF if p >= 1.0 else log(1.0 - p)


## erf (Abramowitz-Stegun 7.1.26), sufficiente per stimare una probabilità.
func _erf(x: float) -> float:
	var sgn := 1.0 if x >= 0.0 else -1.0
	var ax := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * ax)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-ax * ax)
	return sgn * y


func _end_hp_after(mean_loss: float, kills: int, food_used: int) -> void:
	var st := _stats()
	var mx := float(st.hp)
	if mean_loss <= 0.0:
		state["hp"] = mx
		return
	var cfg := auto_eat_cfg()
	var target_hp := mx * float(cfg.target_pct) / 100.0
	state["hp"] = clampf(target_hp if food_used > 0 else float(state.hp) - mean_loss * kills, 1.0, mx)


## Estrae davvero i drop di ogni uccisione stimata (RNG "loot"), poi consegna tutto in blocco.
## Zone: i giri sono uccisioni (un mostro a turno); dungeon: ogni giro è una corsa intera (tutte le ondate + premio).
func _settle_offline(a: Dictionary, units: Array, laps: int, per_lap: int, food_used: int, report: Dictionary, ests: Array,
		rare_boss: bool = false, amb_n: int = 0) -> void:
	var amb_rm := float(ambush_rules().get("reward_mult", 1.0))
	var era := _era()
	var items: Dictionary = {}
	var crates: Array = []
	var pets: Array = []
	var gears: Array = []
	var gold_total := 0
	var xp_total := 0.0
	var kills_n := 0
	var kills_by: Dictionary = {}      # mostro -> uccisioni (un solo evento monsters_killed_batch per mostro, non uno per uccisione)
	var drops_by: Dictionary = {}      # mostro -> {oggetto: quantità}
	var b: Variant = _bounty()
	var dd: Dictionary = dungeon_def(str(a.get("dungeon", ""))) if per_lap > 1 else {}
	for i in laps:
		for j in per_lap:
			var u: Dictionary = units[(i * per_lap + j) % units.size()] if per_lap == 1 else units[j]
			var mon: Dictionary = u.mon
			var boss_wave := (per_lap > 1 and j == per_lap - 1) or rare_boss
			var res := loot_roll(str(mon.get("drop_table", "")), boss_wave)
			var ess := era_essence_drop(mon, str(a.get("mode", "")))
			if ess > 0:
				res.items.append({"id": "era_essence", "qty": ess})
			var g := _roll_gold(mon, era)
			var xp := mon_xp(mon, era)
			if i < amb_n and per_lap == 1:           # le prime amb_n uccisioni contano come Imboscate (premio maggiorato)
				g = int(round(float(g) * amb_rm))
				xp *= amb_rm
			gold_total += g
			xp_total += xp
			var mid := str(mon.id)
			kills_by[mid] = int(kills_by.get(mid, 0)) + 1
			if not (res.items as Array).is_empty():
				var md: Dictionary = drops_by.get_or_add(mid, {})
				for it in res.items:
					items[it.id] = int(items.get(it.id, 0)) + int(it.qty)
					md[it.id] = int(md.get(it.id, 0)) + int(it.qty)
			crates.append_array(res.crates)
			pets.append_array(res.pets)
			gears.append_array(res.gear)
			if b != null:
				b.on_kill_offline(mid, xp)
			report["monster"] = mid
			kills_n += 1
		if per_lap > 1:
			var r2 := _dungeon_reward_offline(dd)
			gold_total += int(r2.gold)
			for it2 in r2.items:
				items[it2.id] = int(items.get(it2.id, 0)) + int(it2.qty)
			crates.append_array(r2.crates)
	var stats: Variant = ctx.state.get("stats")
	if stats is Dictionary:
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + gold_total
		stats["kills"] = int(stats.get("kills", 0)) + kills_n
	for kid in kills_by:
		state.kills[kid] = int(state.kills.get(kid, 0)) + int(kills_by[kid])
		var dl: Array = []
		for did2 in drops_by.get(kid, {}):
			dl.append({"id": did2, "qty": int(drops_by[kid][did2])})
		ctx.events.monsters_killed_batch.emit(str(kid), int(kills_by[kid]), dl)
	var bank: Variant = _bank()
	if bank != null:
		if gold_total > 0:
			bank.add_gold(gold_total)
		for did in items:
			bank.add(str(did), int(items[did]), "combat")
		for gid in gears:
			bank.add_instance({"def": str(gid), "quality": "normal", "sockets": [], "rank": 0, "source": "combat"})
		_consume_food_units(food_used)
	var sk: Variant = _skills()
	if sk != null and xp_total > 0.0:
		sk.add_xp("hero", xp_total)
	var swings_total := 0.0
	var hits_total := 0.0
	for i in ests.size():
		swings_total += float(ests[i].swings)
		hits_total += float(ests[i].hits)
	var share := 1.0 if per_lap > 1 else 1.0 / maxf(1.0, float(ests.size()))
	var swings_all := swings_total * share * laps
	var hits_all := hits_total * share * laps
	if bool(_stats().needs_ammo):
		_consume_ammo_units(int(round(swings_all * (1.0 - _ammo_recovery()))))
	elif _oil_in_use():
		_consume_ammo_units(int(round(hits_all)))
	_consume_potion_charges(int(round(swings_all)))
	for cid in crates:
		ctx.events.crate_found.emit(str(cid), "combat:" + str(report.monster))
	for pid in pets:
		ctx.events.pet_found.emit(str(pid))
	report["kills"] = kills_n
	if amb_n > 0:
		report["ambushes"] = amb_n
	report["xp"] = xp_total
	report["gold"] = gold_total
	report["items"] = items
	report["crates"] = crates.size()
	report["gear"] = gears.size()
	report["food_used"] = food_used
	if per_lap > 1:
		report["runs"] = laps
	if report.monster == "" and not units.is_empty():
		report["monster"] = str((units[0].mon as Dictionary).id)


func _consume_potion_charges(n: int) -> void:
	var p: Dictionary = state.potion
	if p.is_empty() or n <= 0:
		return
	p["charges"] = int(p.charges) - n
	if int(p.charges) <= 0:
		state["potion"] = {}
		ctx.modifiers.clear_source(POTION_SOURCE)


## Premio di una corsa offline (stessa logica di _dungeon_complete, senza registro né eventi per corsa).
func _dungeon_reward_offline(dd: Dictionary) -> Dictionary:
	var did := str(dd.id)
	var reward: Dictionary = dd.completion_reward
	var scopes: Array = [did, "all"]
	var gold := int(round(ctx.modifiers.apply(float(reward.get("gold", 0)), "dungeon_loot_pct", scopes)))
	var items: Array = []
	for it in reward.get("items", []):
		var q := int(round(ctx.modifiers.apply(float(_qty(it.get("qty", 1))), "dungeon_loot_pct", scopes)))
		if q > 0:
			items.append({"id": str(it.item), "qty": q})
	var crates: Array = []
	for c in reward.get("crates", []):
		for i in int(c.get("qty", 1)):
			crates.append(str(c.id))
	state.dungeon_clears[did] = dungeon_clears(did) + 1
	ctx.events.objective_event.emit("complete_dungeon", {"dungeon": did, "qty": 1})
	_apply_dungeon_milestones()
	return {"gold": gold, "items": items, "crates": crates}


func _offline_dungeon(a: Dictionary, left: float, report: Dictionary, wound0: float) -> Dictionary:
	var dd := dungeon_def(str(a.dungeon))
	if dd.is_empty() or left <= 0.0:
		return {}
	var units: Array = []
	for w in (dd.waves as Array).size():
		units.append({"mon": _wave_mon(dd, w), "n": 1})
	a["wave"] = 0
	if not bool(state.dungeon_repeat):
		# una sola corsa: dopo la prima l'eroe si ferma
		var rep := _offline_units(a, units, units.size(), left, report, wound0, 1)
		_set_activity({})
		return rep
	return _offline_units(a, units, units.size(), left, report, wound0)


func _consume_ammo_units(n: int) -> void:
	var eqs := _equipment()
	var left := n
	var guard := 0
	while left > 0 and guard < 4:
		guard += 1
		var am: Variant = eqs.get("ammo")
		if not (am is Dictionary):
			break
		var take := mini(left, int(am.qty))
		am["qty"] = int(am.qty) - take
		left -= take
		if int(am.qty) <= 0 and not _refill_ammo():
			break
	_st_dirty = true


func _consume_food_units(n: int) -> void:
	var bank: Variant = _bank()
	var left := n
	for fid in state.food:
		if left <= 0:
			break
		if str(fid).is_empty():
			continue
		var have: int = int(bank.count(str(fid)))
		var take := mini(left, have)
		if take > 0 and bank.remove(str(fid), take):
			left -= take
