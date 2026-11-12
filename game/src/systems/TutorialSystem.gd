class_name TutorialSystem
extends GameSystem
## Tutorial guidato (logica pura, nessun nodo). Sa QUALI passi del catalogo (TutorialCatalog) sono stati visti, quale è il
## prossimo da proporre in base agli sblocchi reali, e quando il tutorial si spegne da solo. La parte visiva
## (evidenziazione, scheda) sta in TutorialDirector.
##
## Stato `tutorial` (sezione additiva: i salvataggi vecchi non la hanno e ricevono il valore iniziale, nessuna migrazione):
##   {"v": 1, "started": bool, "off": bool, "seen": [id passo]}
##   started  = il tutorial ha già deciso come trattare questa partita (nuova: parte da zero; già avviata: vedi begin())
##   off      = disattivato dal giocatore («Salta il tutorial») o spento da solo a catalogo completo
##   seen     = passi già visti (non vengono riproposti; la checklist li mostra come scoperti)

const VERSION := 1


func _init() -> void:
	id = "tutorial"
	state_key = "tutorial"


func default_state() -> Variant:
	return _fresh()


static func _fresh() -> Dictionary:
	return {"v": VERSION, "started": false, "off": false, "seen": []}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["v"])


func has_tick() -> bool:
	return false


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	var clean: Array = []
	for s in state.seen:
		if s is String and not clean.has(s):
			clean.append(s)
	state.seen = clean


# ------------------------------------------------------------------ stato

func is_seen(step_id: String) -> bool:
	return (state.seen as Array).has(step_id)


func mark_seen(step_id: String) -> void:
	if not is_seen(step_id):
		(state.seen as Array).append(step_id)


func set_off(value: bool) -> void:
	state["off"] = value


## Riparte da capo: nessun passo visto, tutorial acceso.
func reset() -> void:
	state["seen"] = []
	state["off"] = false
	state["started"] = true


## Una volta per partita, all'apertura della schermata principale. Partita nuova: tutto da vedere. Partita già avviata
## prima dell'arrivo del tutorial guidato: i passi di base e quelli dei sistemi già sbloccati si danno per visti, così non
## si riparte da zero; resteranno da vedere solo i sistemi che si sbloccano da qui in avanti.
func begin() -> void:
	if bool(state.started):
		return
	state["started"] = true
	var q := ctx.get_system("quests") as QuestSystem
	if q == null or q.intro_pending():
		return
	for s in TutorialCatalog.STEPS:
		if str(s.cat) == "guide" or (token_ok(s) and conds_ok(s)):
			mark_seen(str(s.id))


func counts() -> Dictionary:
	var seen := 0
	for s in TutorialCatalog.STEPS:
		if is_seen(str(s.id)):
			seen += 1
	return {"seen": seen, "total": TutorialCatalog.STEPS.size()}


## Tutti i passi visti: il tutorial si spegne da solo (la checklist resta consultabile).
func finished() -> bool:
	var c := counts()
	return int(c.seen) >= int(c.total)


## Suggerimenti automatici attivi.
func active() -> bool:
	return not bool(state.off) and not finished()


# ------------------------------------------------------------------ quali passi si possono proporre

func unlocked(token: String) -> bool:
	return token.is_empty() or (ctx.state.get("unlocks", []) as Array).has(token)


func token_ok(step: Dictionary) -> bool:
	return unlocked(str(step.get("token", "")))


func conds_ok(step: Dictionary) -> bool:
	var c: Variant = step.get("cond", [])
	return (c as Array).is_empty() or cond_ok(c)


## Tipi di condizione: quest_reached / quest_done (id missione), queue_slots (almeno un posto in coda), building (id edificio
## costruito), item (id oggetto nel Deposito), bank_nearly_full (Deposito pieno o oltre la soglia constants.bank.warn_pct),
## bank_used_over (Spazio usato oltre la soglia constants.bank.ui.<argomento>, F17).
func cond_ok(c: Array) -> bool:
	if c.size() < 2:
		return true
	var arg := str(c[1])
	match str(c[0]):
		"quest_done":
			return (ctx.state.get("quests", {}).get("done", []) as Array).has(arg)
		"quest_reached":
			var qs: Dictionary = ctx.state.get("quests", {})
			return (qs.get("done", []) as Array).has(arg) or (qs.get("active", []) as Array).has(arg)
		"queue_slots":
			var qu := ctx.get_system("queue") as QueueSystem
			return qu != null and qu.slots() > 0
		"building":
			var es := ctx.get_system("estate") as EstateSystem
			return es != null and es.level_of(arg) > 0
		"item":
			var b := ctx.get_system("bank") as BankSystem
			return b != null and b.count(arg) > 0
		"bank_nearly_full":
			var bk := ctx.get_system("bank") as BankSystem
			return bk != null and (bk.nearly_full() or bk.is_full())
		"bank_used_over":                                   # F17: argomento = chiave di constants.bank.ui con la soglia
			var bu := ctx.get_system("bank") as BankSystem
			var lim: Variant = bu.ui_rules().get(arg) if bu != null else null
			return bu != null and (lim is int or lim is float) and bu.used_slots() > int(lim)
	return false


## Il passo è inutile (il giocatore ha già fatto ciò che insegna).
func should_skip(step: Dictionary) -> bool:
	for c in step.get("skip_if", []):
		if cond_ok(c):
			return true
	return false


## Il passo si può mostrare ora (sblocchi e condizioni), indipendentemente dall'ordine: serve a «Mostrami».
func available(step_id: String) -> bool:
	var s := TutorialCatalog.get_step(step_id)
	return not s.is_empty() and token_ok(s) and conds_ok(s)


## Prossimo passo da proporre da solo, o {}. `excluded` = passi rimandati o saltati in questa sessione.
func next_step(excluded: Dictionary = {}) -> Dictionary:
	var q := ctx.get_system("quests") as QuestSystem
	if q == null or q.intro_pending():
		return {}                        # prima il benvenuto
	for s in TutorialCatalog.STEPS:
		var sid := str(s.id)
		if is_seen(sid) or excluded.has(sid):
			continue
		var after := str(s.get("after", ""))
		if not after.is_empty() and not is_seen(after):
			continue
		if token_ok(s) and conds_ok(s):
			return s
	return {}


# ------------------------------------------------------------------ numeri nei testi (dai dati)

## Segnaposto del testo di un passo, ricavati dai dati e dal Manuale (nessun numero scritto nel codice).
static func text_params(step_id: String, data: Object) -> Dictionary:
	var p := {}
	var st := TutorialCatalog.get_step(step_id)
	p["menu"] = menu_name(str(st.get("screen", "")), data)
	match step_id:
		"b_level", "b_mastery", "b_compare":
			var sk: Array = ManualFacts.params("skills", data)
			p["cap"] = sk[0].cap
			p["mcap"] = sk[1].mcap
			p["levels"] = sk[1].levels
			p["save"] = sk[1].save
			var nxt := _next_action("woodcutting", "wc_pine", data)
			p["skill"] = Loc.t(data.get_def("skills", "woodcutting").get("name", {}))
			p["action"] = Loc.t(data.get_def("actions", "wc_pine").get("name", {})) if not data.get_def("actions", "wc_pine").is_empty() else "wc_pine"
			p["next_lvl"] = int(nxt.get("level_req", 0))
			p["next_name"] = Loc.t(nxt.get("name", {}))
		"f_queue":
			p.merge(ManualFacts.params("queue", data)[0])
		"f_potions", "f_feast":
			p.merge(ManualFacts.params("alchemy", data)[0])
		"f_run":
			var rr: Dictionary = data.rules("run_rules")
			p["kills"] = int(rr.get("kills_per_choice", 0))
			p["max"] = int(rr.get("max_choices", 0))
			p["offers"] = int(rr.get("offers", 0))
		"f_crates":
			var pity: Dictionary = data.rules("crate_rules").get("pity", {})
			p["soft"] = int(pity.get("soft_start", 0))
			p["hard"] = int(pity.get("hard", 0))
		"f_market":
			var tax := float(data.rules("market_rules").get("sell_tax", data.constants.market.sell_tax))
			p["tax"] = NumberFormat.decimal(tax * 100.0, 0, Loc.locale())
		"f_vault_tools":
			p["inputs"] = int(data.rules("crate_rules").get("tradeup", {}).get("inputs", 0))
		"f_offline":
			var o: Dictionary = data.constants.offline
			p["eff"] = int(o.efficiency_pct)
			p["base"] = int(o.cap_base_h)
			p["max"] = int(o.cap_max_h)
		"f_bank_expand":
			p["warn"] = int(data.constants.bank.warn_pct)
			p.merge(ManualFacts.params("bank", data)[2])
		"f_hourglass":
			p["hours"] = NumberFormat.decimal(float(data.item(Hourglass.ITEM).get("hourglass", {}).get("hours", 0)), 0, Loc.locale())
		"f_cozy":
			p["xp"] = NumberFormat.decimal(float(data.constants.get("cozy", {}).get("xp_pct", 0.0)), 0, Loc.locale())
	return p


static func menu_name(screen_id: String, data: Object) -> String:
	if screen_id.is_empty():
		return ""
	if screen_id.begins_with("skill:"):
		return Loc.t(data.get_def("skills", screen_id.substr(6)).get("name", {}))
	var e := ScreenRegistry.get_entry(screen_id, data)
	if e.is_empty():
		return screen_id
	return Loc.t(e.title_data) if e.has("title_data") else TranslationServer.translate(str(e.title))


## Prima azione della mansione con livello richiesto maggiore di quella data (l'esempio del livello che sblocca).
static func _next_action(skill_id: String, from_action: String, data: Object) -> Dictionary:
	var base_lvl := 1
	var best: Dictionary = {}
	for a in data.actions_for_skill(skill_id):
		if str(a.id) == from_action:
			base_lvl = int(a.get("level_req", 1))
	for a in data.actions_for_skill(skill_id):
		var l := int(a.get("level_req", 1))
		if l > base_lvl and (best.is_empty() or l < int(best.get("level_req", 0))):
			best = a
	return best
