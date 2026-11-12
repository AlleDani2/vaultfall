class_name CompendiumSystem
extends GameSystem
## Imprese, Titoli, Famigli e cosmetici del profilo (docs/15, GUILD-2). Offline, nessuna rete.
##
## Stato `compendium`: {"title": id selezionato, "frame": id, "companion": id famiglio visibile, "frames": [id cornici possedute],
##   "dupes": {pet_id: n}, "counters": {chiave: int} (contatori piatti: "act:<mansione>", "raid:<id>", "rarity:<r>"…),
##   "offline_h_max": float, "ach_total": int}.
## Gli elenchi `pets`, `achievements`, `titles` restano nelle sezioni radice dello stato (GameState.default_state): altri sistemi
## (SkillSystem, CombatSystem) vi leggono e scrivono già direttamente.
##
## Imprese: le condizioni di docs/15 §3 si leggono dallo stato degli altri sistemi (livelli, Stelle, Tenuta…) oppure da
## contatori alimentati dai segnali (EventBus.objective_event & co.). Si controllano ogni `social_rules.achievements.poll_s`
## secondi di gioco e a fine offline; sbloccare un'impresa paga la Polvere Stellare e, se c'è, il titolo (achievement_unlocked).
## Titoli e cornici arrivano anche da: missioni (QuestSystem.claim), Stelle (traguardi 25/…), collezioni auree, grado Esaltato.
## Famigli: pet_found registra il famiglio e applica il bonus passivo (fonte Modifiers "pet:<id>"); un doppione (★ delle Casse)
## si converte in Polvere Stellare.

const PET_SOURCE := "pet:"
const DUST := "stardust"

var _acc: float = 1e9
var _rr: int = -1                     # indice della prossima impresa da controllare (giro distribuito sui tick)
var _ach_by_cat: Dictionary = {}
var _chapter_quests: Dictionary = {}


func _init() -> void:
	id = "compendium"
	state_key = "compendium"


func default_state() -> Variant:
	return _fresh_state()


static func _fresh_state() -> Dictionary:
	return {"title": "", "frame": "", "companion": "", "frames": [], "dupes": {}, "counters": {}, "offline_h_max": 0.0}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["dupes.*", "counters.*"])


func setup() -> void:
	_ach_by_cat.clear()
	_chapter_quests.clear()
	for a in ctx.data.table("achievements"):
		var cat := str(a.get("category", ""))
		if not _ach_by_cat.has(cat):
			_ach_by_cat[cat] = []
		_ach_by_cat[cat].append(str(a.id))
	for q in ctx.data.table("quests"):
		if str(q.get("kind", "")) == "main":
			var ch := int(q.get("chapter", -1))
			if not _chapter_quests.has(ch):
				_chapter_quests[ch] = []
			_chapter_quests[ch].append(str(q.id))
	var ev: Object = ctx.events
	ev.pet_found.connect(_cb_pet_found)
	ev.objective_event.connect(_cb_objective)
	ev.crate_opened.connect(_cb_crate_opened)
	ev.action_completed.connect(_cb_action)
	ev.action_batch_completed.connect(_cb_action_batch)
	ev.offline_progress.connect(_cb_offline)
	ev.faction_rank_up.connect(_cb_rank_up)


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh_state()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	for k in ["pets", "achievements", "titles"]:
		if not (ctx.state.get(k) is Array):
			ctx.state[k] = []
	_acc = 1e9
	_rebuild_pet_mods()


func has_tick() -> bool:
	return true


## A gioco aperto il controllo è distribuito: ogni tick si guarda una fetta delle imprese (tutte in `poll_s` secondi)
## e le ricompense da riconciliare una volta per giro. Così nessun tick paga l'intero elenco (picco ≤ 15 ms, resoconto 47).
func tick(dt: float) -> void:
	if state == null:
		return
	var all: Array = ctx.data.table("achievements")
	if all.is_empty():
		return
	_acc += dt
	if _acc >= poll_s():
		_acc = 0.0
		_reconcile_rewards()
	var per_tick := maxi(1, ceili(float(all.size()) * dt / maxf(dt, poll_s())))
	for i in per_tick:
		_rr = (_rr + 1) % all.size()
		var a: Dictionary = all[_rr]
		if is_unlocked(str(a.id)):
			continue
		var p := ach_progress(a)
		if int(p.cur) >= int(p.target):
			_unlock(a)


func simulate_offline(_seconds: float) -> Dictionary:
	if state == null:
		return {}
	var n := evaluate()
	_acc = 0.0
	if n > 0:
		return {"rows": [{"key": "UI_GUILD2_WB_ACH", "params": {"n": n}}]}
	return {}


func poll_s() -> float:
	return float(rules().get("achievements", {}).get("poll_s", 2.0))


func rules() -> Dictionary:
	return ctx.data.rules("social_rules")


# ================================================================== famigli

func pets_owned() -> Array:
	return ctx.state.pets


func has_pet(pet_id: String) -> bool:
	return (ctx.state.pets as Array).has(pet_id)


func pet_dupes(pet_id: String) -> int:
	return int(state.dupes.get(pet_id, 0))


func _cb_pet_found(pet_id: String) -> void:
	if state != null:
		found_pet(pet_id)


## Registra un famiglio trovato. Ritorna "new" | "dupe" | "unknown".
func found_pet(pet_id: String) -> String:
	var def: Dictionary = ctx.data.get_def("pets", pet_id)
	if def.is_empty():
		return "unknown"
	var nm := Loc.t(def.get("name", pet_id))
	if has_pet(pet_id):
		var src := str(def.get("source", {}).get("type", ""))
		var key := "crate_duplicate_stardust" if src == "crate_relic_pool" else "duplicate_stardust"
		if src == "event":            # G40: famiglio da evento, nessun potere -> nessuna Polvere (social_rules.pets)
			key = "event_duplicate_stardust"
		var dust := int(rules().get("pets", {}).get(key, 0))
		state.dupes[pet_id] = pet_dupes(pet_id) + 1
		_add_dust(dust)
		var text := Loc.tf("UI_GUILD2_PET_DUPE", {"name": nm, "dust": dust}) if dust > 0 \
			else Loc.tf("UI_GAPM_PET_DUPE_NODUST", {"name": nm})
		ctx.events.notice.emit("info", text, {"digest": "pet_dupe", "pet": pet_id, "dust": dust})
		return "dupe"
	(ctx.state.pets as Array).append(pet_id)
	if str(state.companion).is_empty():
		state.companion = pet_id
	_set_pet_mods(pet_id)
	ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_PET_NEW", {"name": nm}), {"digest": "pet", "pet": pet_id})
	ctx.events.important_event.emit("pet")
	return "new"


func set_companion(pet_id: String) -> bool:
	if not pet_id.is_empty() and not has_pet(pet_id):
		return false
	state.companion = pet_id
	return true


func companion() -> String:
	return str(state.companion)


func _rebuild_pet_mods() -> void:
	for pid in ctx.state.get("pets", []):
		_set_pet_mods(str(pid))


func _set_pet_mods(pet_id: String) -> void:
	var def: Dictionary = ctx.data.get_def("pets", pet_id)
	var mods: Array = []
	for m in def.get("modifiers", []):
		mods.append({"key": str(m.key), "value": float(m.value), "mode": str(m.get("mode", "add"))})
	ctx.modifiers.set_source(PET_SOURCE + pet_id, mods)


# ================================================================== titoli e cornici

func has_title(title_id: String) -> bool:
	return (ctx.state.titles as Array).has(title_id)


func owned_titles() -> Array:
	return ctx.state.titles


## Aggiunge un titolo (idempotente). Il primo titolo ottenuto si indossa da solo. Ritorna true se è nuovo.
func grant_title(title_id: String) -> bool:
	if title_id.is_empty() or ctx.data.get_def("titles", title_id).is_empty() or has_title(title_id):
		return false
	(ctx.state.titles as Array).append(title_id)
	if str(state.title).is_empty():
		state.title = title_id
	ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_TITLE_NEW", {"name": title_name(title_id)}), {"digest": "title", "title": title_id})
	return true


func set_title(title_id: String) -> bool:
	if not title_id.is_empty() and not has_title(title_id):
		return false
	state.title = title_id
	return true


func selected_title() -> String:
	return str(state.title)


func title_name(title_id: String) -> String:
	return Loc.t(ctx.data.get_def("titles", title_id).get("name", title_id))


## Cornice o cosmetico di profilo (tabella `frames`; in mancanza un oggetto cosmetico va nel Deposito).
func grant_cosmetic(cosmetic_id: String) -> bool:
	if cosmetic_id.is_empty():
		return false
	if not ctx.data.get_def("frames", cosmetic_id).is_empty():
		if (state.frames as Array).has(cosmetic_id):
			return false
		(state.frames as Array).append(cosmetic_id)
		if str(state.frame).is_empty():
			state.frame = cosmetic_id
		var nm := Loc.t(ctx.data.get_def("frames", cosmetic_id).get("name", cosmetic_id))
		ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_FRAME_NEW", {"name": nm}), {"digest": "frame", "frame": cosmetic_id})
		return true
	if ctx.data.has_item(cosmetic_id):
		var bank := ctx.get_system("bank")
		if bank != null:
			return int(bank.call("add_instance", {"def_id": cosmetic_id, "kind": "cosmetic", "source": "quest"})) != 0
	return false


func has_frame(frame_id: String) -> bool:
	return (state.frames as Array).has(frame_id)


func set_frame(frame_id: String) -> bool:
	if not frame_id.is_empty() and not has_frame(frame_id):
		return false
	state.frame = frame_id
	return true


func selected_frame() -> String:
	return str(state.frame)


## Nome dell'Eroe con il titolo scelto: «Titolo» (testo locale, anche per la UI).
func title_line() -> String:
	var t := selected_title()
	return "" if t.is_empty() else title_name(t)


# ================================================================== imprese

func is_unlocked(ach_id: String) -> bool:
	return (ctx.state.achievements as Array).has(ach_id)


func unlocked_count() -> int:
	return (ctx.state.achievements as Array).size()


func total_count() -> int:
	return ctx.data.table("achievements").size()


func categories() -> Array:
	return _ach_by_cat.keys()


func ids_in_category(cat: String) -> Array:
	return _ach_by_cat.get(cat, [])


## Controlla tutte le imprese ancora chiuse e riconcilia titoli/cornici di altri sistemi. Ritorna quante imprese ha sbloccato.
func evaluate() -> int:
	if state == null:
		return 0
	_reconcile_rewards()
	var n := 0
	for a in ctx.data.table("achievements"):
		var aid := str(a.id)
		if is_unlocked(aid):
			continue
		var p := ach_progress(a)
		if int(p.cur) >= int(p.target):
			_unlock(a)
			n += 1
	return n


func _unlock(a: Dictionary) -> void:
	var aid := str(a.id)
	(ctx.state.achievements as Array).append(aid)
	var r: Dictionary = a.get("reward", {})
	if int(r.get("stardust", 0)) > 0:
		_add_dust(int(r.stardust))
	if str(r.get("title", "")) != "":
		grant_title(str(r.title))
	ctx.events.achievement_unlocked.emit(aid)
	ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_ACH_NEW", {"name": Loc.t(a.get("name", aid))}), {"digest": "ach", "ach": aid})
	ctx.events.important_event.emit("achievement")


## {"cur": int, "target": int} per la condizione di un'impresa (def o id). Valori già limitati al bersaglio.
func ach_progress(ach: Variant) -> Dictionary:
	var a: Dictionary = ach if ach is Dictionary else ctx.data.get_def("achievements", str(ach))
	if a.is_empty():
		return {"cur": 0, "target": 1}
	var c: Dictionary = a.get("condition", {})
	var target := _target_of(c)
	return {"cur": mini(_current_of(c), target), "target": target}


func _target_of(c: Dictionary) -> int:
	match str(c.get("type", "")):
		"skill_level", "total_level":
			return int(c.get("level", 1))
		"gold_earned", "kills_total", "crates_opened", "pets", "items_sold", "orders_complete", "soci_total", "building_level":
			return int(c.get("qty", 1))
		"rift_floor":
			return int(c.get("floor", 1))
		"era":
			return int(c.get("era", 1))
		"chapter_complete":
			return 1
	return maxi(1, int(c.get("qty", 1)))


func _current_of(c: Dictionary) -> int:
	var t := str(c.get("type", ""))
	match t:
		"skill_level":
			return int(ctx.state.get("skills", {}).get(str(c.get("skill", "")), {}).get("level", 0))
		"total_level":
			var tot := 0
			for s in ctx.state.get("skills", {}).values():
				if s is Dictionary:
					tot += int(s.get("level", 0))
			return tot
		"chapter_complete":
			var ids: Array = _chapter_quests.get(int(c.get("chapter", -1)), [])
			if ids.is_empty():
				return 0
			var qs := ctx.get_system("quests")
			for q in ids:
				if qs == null or not bool(qs.call("is_done", q)):
					return 0
			return 1
		"kill":
			var cb := ctx.get_system("combat")
			if cb != null and cb.state is Dictionary:
				return int((cb.state.get("kills", {}) as Dictionary).get(str(c.get("monster", "")), 0))
			return 0
		"kills_total":
			return int(ctx.state.get("stats", {}).get("kills", 0))
		"gold_earned":
			return int(ctx.state.get("stats", {}).get("gold_earned", 0))
		"crates_opened":
			return int(ctx.state.get("crates", {}).get("opened", 0))
		"obtain_rarity":
			return counter("rarity:" + str(c.get("rarity", "")))
		"obtain_skin":
			return counter(("skin_ann:" if bool(c.get("annalist", false)) else "skin:") + str(c.get("rarity", "")))
		"stars_total":
			var pr := ctx.get_system("prestige")
			return int(pr.call("stars_total")) if pr != null else 0
		"stars_every_skill":
			return _stars_every(int(c.get("qty", 1)))
		"era":
			var pr2 := ctx.get_system("prestige")
			return int(pr2.call("era_max")) if pr2 != null else 1
		"complete_raid":
			var r := str(c.get("raid", "any"))
			if r == "any":
				var n := 0
				for k in state.counters:
					if str(k).begins_with("raid:"):
						n += int(state.counters[k])
				return n
			return counter("raid:" + r)
		"collections_complete", "golden_collection":
			return _collections(t == "golden_collection")
		"pets":
			return (ctx.state.pets as Array).size()
		"dungeons_all":
			return _all_dungeons_done()
		"orders_complete":
			return int(ctx.state.get("market", {}).get("orders_done", 0))
		"items_sold":
			return int(ctx.state.get("market", {}).get("sold_total", 0))
		"soci_total":
			return int(ctx.state.get("estate", {}).get("partners", 0))
		"building_level":
			var best := 0
			for b in ctx.state.get("estate", {}).get("buildings", {}).values():
				if b is Dictionary:
					best = maxi(best, int(b.get("level", 0)))
			return best
		"recruit":
			var rar := str(c.get("rarity", "any"))
			return counter("recruit") if rar == "any" else counter("recruit:" + rar)
		"skill_actions":
			return counter("act:" + str(c.get("skill", "")))
		"offline_hours":
			return int(floor(float(state.offline_h_max)))
		"mastery":
			var lv := int(c.get("level", 1))
			var m := 0
			for v in ctx.state.get("mastery", {}).values():
				if v is Dictionary and int(v.get("level", 0)) >= lv:
					m += 1
			return m
		"rift_floor":
			return counter("rift_floor")
		"collectors_challenge_wins":
			# dallo stato della Sfida (vale anche per i salvataggi precedenti all'evento)
			var cw := int(ctx.state.get("crates", {}).get("challenge", {}).get("wins", 0))
			return maxi(cw, counter(t))
		"tradeup", "refine_polish", "expeditions", "estate_prestige", "challenge", "burnt", "craft_quality":
			return counter(_counter_key(t, c))
		"classes_unlocked":
			return _classes_unlocked()
		"challenge_all_max":
			return maxi(counter(t), _trials_all_max())
	return 0


func _counter_key(t: String, c: Dictionary) -> String:
	if t == "expeditions":
		return "expedition"
	if t == "craft_quality":
		return "quality:" + str(c.get("quality", ""))
	return t


## Classi sbloccate oltre alle tre di base: specializzazioni e ibride con la missione di classe completata.
func _classes_unlocked() -> int:
	var qs := ctx.get_system("quests")
	var n := 0
	for cd in ctx.data.table("classes"):
		var u: Variant = cd.get("unlock")
		if not (u is Dictionary) or str(u.get("quest", "")).is_empty():
			continue
		var qid := str(u.quest)
		if (qs != null and bool(qs.call("is_done", qid))) or (ctx.state.get("unlocks", []) as Array).has("class:" + qid.trim_prefix("class_")):
			n += 1
	return n


## 1 se tutte le Prove del Custode sono al grado massimo.
func _trials_all_max() -> int:
	var pr := ctx.get_system("prestige")
	if pr == null or not pr.has_method("trial_ids"):
		return 0
	var ids: PackedStringArray = pr.call("trial_ids")
	if ids.is_empty():
		return 0
	for tid in ids:
		if int(pr.call("trial_tiers_done", tid)) < int(pr.call("trial_tier_count", tid)):
			return 0
	return 1


func _stars_every(per_skill: int) -> int:
	var pr := ctx.get_system("prestige")
	if pr == null:
		return 0
	for row in ctx.data.table("skill_prestige"):
		if int(pr.call("stars", str(row.skill))) < per_skill:
			return 0
	return per_skill


func _collections(golden: bool) -> int:
	var cr := ctx.get_system("crates")
	if cr == null:
		return 0
	var n := 0
	for cid in cr.call("collection_ids"):
		var p: Dictionary = cr.call("collection_progress", cid)
		if bool(p.golden) if golden else bool(p.complete):
			n += 1
	return n


func _all_dungeons_done() -> int:
	var cb := ctx.get_system("combat")
	var ds: Array = ctx.data.table("dungeons")
	if cb == null or ds.is_empty():
		return 0
	for d in ds:
		if int(cb.call("dungeon_clears", str(d.id))) < 1:
			return 0
	return 1


func counter(key: String) -> int:
	return int(state.counters.get(key, 0))


func _bump(key: String, n: int = 1) -> void:
	state.counters[key] = counter(key) + n


# ------------------------------------------------------------------ contatori dai segnali

func _cb_objective(kind: String, params: Dictionary) -> void:
	if state == null:
		return
	var q := int(params.get("qty", 1))
	match kind:
		"tradeup", "refine_polish", "expedition", "estate_prestige", "challenge", "collectors_challenge_wins", "burnt", "challenge_all_max":
			_bump(kind, q)
		"craft_quality":
			_bump("quality:" + str(params.get("quality", "")), q)
		"recruit":
			_bump("recruit", q)
			if params.has("rarity"):
				_bump("recruit:" + str(params.rarity), q)
		"complete_raid":
			_bump("raid:" + str(params.get("raid", "")), q)
		"rift_floor":
			state.counters["rift_floor"] = maxi(counter("rift_floor"), int(params.get("floor", 0)))


func _cb_crate_opened(result: Dictionary) -> void:
	if state == null:
		return
	var rar := str(result.get("rarity", ""))
	if rar.is_empty():
		return
	var n := int(result.get("count", 1))
	_bump("rarity:" + rar, n)
	if str(result.get("kind", "")) == "skin":
		_bump("skin:" + rar, n)
		if bool((result.get("instance", {}) as Dictionary).get("annalist", false)):
			_bump("skin_ann:" + rar, n)


func _cb_action(action_id: String, _outputs: Array) -> void:
	_count_action(action_id, 1)


func _cb_action_batch(action_id: String, count: int, _outputs: Array) -> void:
	_count_action(action_id, count)


func _count_action(action_id: String, n: int) -> void:
	if state == null:
		return
	var skill := str(ctx.data.action(action_id).get("skill", ""))
	if not skill.is_empty():
		_bump("act:" + skill, n)


## Salita di grado in una fazione: avviso (il bonus del grado è già nei Modificatori) e titolo «Esaltato» subito.
func _cb_rank_up(faction_id: String, rank_id: String) -> void:
	if state == null:
		return
	var f: Dictionary = ctx.data.get_def("factions", faction_id)
	var rank_name := rank_id
	for r in f.get("ranks", []):
		if str(r.id) == rank_id:
			rank_name = Loc.t(r.name)
	ctx.events.notice.emit("success", Loc.tf("UI_GUILD2_FAC_RANKUP", {"faction": Loc.t(f.get("name", faction_id)), "rank": rank_name}),
		{"digest": "rank"})
	_reconcile_rewards()


func _cb_offline(seconds: float, _report: Dictionary) -> void:
	if state != null and is_finite(seconds):
		state.offline_h_max = maxf(float(state.offline_h_max), seconds / 3600.0)


# ------------------------------------------------------------------ titoli e cornici di altri sistemi

func _reconcile_rewards() -> void:
	var pr := ctx.get_system("prestige")
	if pr != null:
		for row in ctx.data.table("skill_prestige"):
			var stars := int(pr.call("stars", str(row.skill)))
			for m in row.get("milestones", []):
				if stars >= int(m.stars):
					if str(m.get("cosmetic", "")) != "":
						grant_cosmetic(str(m.cosmetic))
					if str(m.get("title", "")) != "":
						grant_title(str(m.title))
	var cr := ctx.get_system("crates")
	if cr != null:
		for cdef in ctx.data.table("collections"):
			var t := str(cdef.get("golden_bonus", {}).get("title", ""))
			if not t.is_empty() and not has_title(t) and bool((cr.call("collection_progress", str(cdef.id)) as Dictionary).golden):
				grant_title(t)
	var mk := ctx.get_system("market")
	if mk != null:
		for f in ctx.data.table("factions"):
			var ranks: Array = f.get("ranks", [])
			var cur := int(mk.call("rank_index", str(f.id)))
			for rw in f.get("rank_rewards", []):
				if rw.get("title") == null or str(rw.title) == "":
					continue
				for i in ranks.size():
					if str(ranks[i].id) == str(rw.rank) and cur >= i:
						grant_title(str(rw.title))


func _add_dust(n: int) -> void:
	var bank := ctx.get_system("bank")
	if bank != null and n > 0:
		bank.call("add_currency", DUST, n)
