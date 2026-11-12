class_name ModeSystem
extends GameSystem
## Conseguenze delle modalità di gioco che toccano più sistemi (docs/05 §7). Le regole in sé sono in ModeRules
## (dati: mode_rules.json); qui solo ciò che "accade":
##   - Estrema: alla morte (qualunque causa, segnale player_died) il livello Eroe e l'equipaggiamento indossato vanno persi.
##     Mansioni, Stelle, Polvere, Costellazioni, Ere e tutto il resto restano (regole di conservazione del prestigio invariate).
##   - Titolo e cornice dedicati alla creazione della partita; secondo titolo alla prima Stella.
## Il resto (acquisti, Commesse, ritiro offline) lo applicano i sistemi interessati interrogando ctx.mode_rules().
##
## Stato (GameState.data.modes): {"deaths_lost": n morti permanenti, "levels_lost": n, "items_lost": n,
##   "last": {"cause", "level", "items"} ultima morte, "badge": bool titolo+cornice dati, "star_badge": bool secondo titolo}
##   "cozy": bool Modalità Cozy attiva in questa partita (+% XP, sorgente Modifiers «mode:cozy», valore da constants.cozy.xp_pct),
##   "cozy_used": bool la partita è stata giocata in Cozy almeno una volta (vale per sempre: i codici-risultato del co-op e le
##   classifiche la marcano con run_tags() = ["cozy"]; non si cancella spegnendo la Cozy).
## La Cozy è della PARTITA (salvata qui), non della UI: si applica a new_game/load_game (da from_state, prima dell'offline),
## e al cambio dell'impostazione «cozy_mode» di Settings (segnale settings_changed) mentre la partita è accesa.
## Sezione nuova: i salvataggi precedenti la ricevono da default_state (nessun cambio di forma, SCHEMA_VERSION invariato).


func _init() -> void:
	id = "modes"
	state_key = "modes"


func default_state() -> Variant:
	return {"deaths_lost": 0, "levels_lost": 0, "items_lost": 0, "last": {}, "badge": false, "star_badge": false,
		"cozy": false, "cozy_used": false}


func from_state(section: Variant) -> void:
	state = section
	var base: Dictionary = default_state()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	apply_cozy()


func int_paths() -> PackedStringArray:
	return PackedStringArray(["deaths_lost", "levels_lost", "items_lost", "last.level", "last.items"])


const COZY_SOURCE := "mode:cozy"


## Cozy attiva in questa partita?
func is_cozy() -> bool:
	return state != null and bool(state.get("cozy", false))


## Partita giocata in Cozy (anche solo per un periodo): per i codici-risultato e le classifiche.
func is_cozy_run() -> bool:
	return state != null and bool(state.get("cozy_used", false))


## Etichette da aggiungere a ogni codice-risultato condivisibile (co-op, sfida settimanale): [] o ["cozy"].
func run_tags() -> Array:
	return ["cozy"] if is_cozy_run() else []


func set_cozy(on: bool) -> void:
	if state == null:
		return
	state["cozy"] = on
	if on:
		state["cozy_used"] = true
	apply_cozy()


## Allinea la sorgente di modificatori allo stato salvato (richiamata da from_state: dopo ogni caricamento, prima dell'offline).
func apply_cozy() -> void:
	if ctx == null or ctx.modifiers == null:
		return
	var pct := float(ctx.constants().get("cozy", {}).get("xp_pct", 0.0))
	if is_cozy() and pct > 0.0:
		ctx.modifiers.set_source(COZY_SOURCE, [{"key": "skill_xp_pct:all", "value": pct}])
	else:
		ctx.modifiers.clear_source(COZY_SOURCE)


func _cb_setting(key: String, value: Variant) -> void:
	if enabled and key == "cozy_mode":
		set_cozy(bool(value))


func setup() -> void:
	var ev: Object = ctx.events
	if ev.has_signal("settings_changed") and not ev.settings_changed.is_connected(_cb_setting):
		ev.settings_changed.connect(_cb_setting)
	# callback come metodi (non lambda): un sistema distrutto si scollega da solo (schema di PrestigeSystem)
	if not ev.player_died.is_connected(_cb_player_died):
		ev.player_died.connect(_cb_player_died)
		ev.star_gained.connect(_cb_star_gained)


func rules() -> ModeRules:
	return ctx.mode_rules()


## Titolo e cornice alla creazione: appena il Compendio c'è (un tick basta). Per la Normale non c'è nulla da dare.
func tick(_dt: float) -> void:
	if bool(state.badge):
		return
	var r := rules()
	if r.is_normal():
		state["badge"] = true
		return
	var comp := ctx.get_system("compendium")
	if comp == null:
		return
	state["badge"] = true
	comp.call("grant_title", r.title_id())
	comp.call("grant_cosmetic", r.frame_id())


## Il tick di questa sezione assegna soltanto i titoli (idempotente): per il tempo in blocco ne basta uno solo.
func simulate_offline(_seconds: float) -> Dictionary:
	if has_tick():
		tick(FixedStepClock.STEP)
	return {}


func has_tick() -> bool:
	return state == null or not bool(state.get("badge", true))


func _cb_star_gained(_skill: String) -> void:
	if state == null or bool(state.star_badge) or rules().is_normal():
		return
	var comp := ctx.get_system("compendium")
	if comp == null:
		return
	state["star_badge"] = true
	comp.call("grant_title", rules().star_title_id())


## Morte: se la modalità prevede la morte permanente, applica le perdite e avvisa (testo chiaro, nessun silenzio).
func _cb_player_died(cause: String) -> void:
	if state == null:
		return
	var pd := rules().permadeath()
	if pd.is_empty():
		return
	var lvl := 0
	var sk := ctx.get_system("skills")
	if sk != null:
		for sid in pd.get("reset_skills", []):
			lvl += int(sk.call("reset_level", str(sid)))
	var items := 0
	var combat := ctx.get_system("combat")
	if combat != null:
		if bool(pd.get("lose_equipment", false)):
			items = int(combat.call("lose_worn_gear", pd.get("keep_equipment_slots", [])))
		if bool(pd.get("reset_build", false)):
			combat.call("reset_hero_build")
	state["deaths_lost"] = int(state.deaths_lost) + 1
	state["levels_lost"] = int(state.levels_lost) + lvl
	state["items_lost"] = int(state.items_lost) + items
	state["last"] = {"cause": cause, "level": lvl, "items": items}
	ctx.events.notice.emit("warning", Loc.tf("UI_MODES_DEATH_NOTICE", {"lv": lvl, "n": items}), {"section": "combat"})
	ctx.events.important_event.emit("permadeath")           # salvataggio subito (R-SAV-3)
