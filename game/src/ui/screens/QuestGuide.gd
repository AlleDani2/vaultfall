class_name QuestGuide
extends RefCounted
## «Come si procede» per le missioni (feedback dei giocatori: «servono missioni più chiare su come procedere»).
## Dato un obiettivo ritorna un testo di istruzione esplicito («Apri Taglialegna, scegli «Pino» e premi Avvia»), il bersaglio del
## pulsante «Vai» ({screen, params, hint}: lo stesso formato di ReqLink) e, quando serve, DOVE si ottiene un oggetto (mansione,
## mostro/zona, Mercato) ricavato SEMPRE dai dati (azioni, tabelle di drop, mostri, zone), mai a mano.
## Solo presentazione: legge DataRegistry, i sistemi e ReqLink. Nessun numero di bilanciamento.
##
##   howto(obj)              -> {text, target, extra: [{text, target}]}
##   where_item(item_id)     -> {text, target}
##   why(quest_def)          -> «Sblocca: …» ("" se la missione non sblocca nulla)
##   lock_reason(def, qs)    -> {text, target} se la missione non è ancora disponibile (missione precedente da finire)
##   current_goal(qs)        -> l'«Obiettivo attuale» (missione principale o riscatto) con testo e «Vai»
##   discoveries(qs)         -> passi di scoperta (tabella `guides`) già sbloccati e non ancora visti
##   upcoming(qs, n)         -> le prossime n missioni principali non ancora iniziate

const MAX_EXTRA := 4
const SKIP_UNLOCK_KINDS: PackedStringArray = ["chapter"]

static var _drops: Dictionary = {}          # item -> {monster, zone}   (la fonte più probabile)
static var _acts: Dictionary = {}           # item -> Array[String] (id azioni che lo producono)
static var _finds: Dictionary = {}          # item -> Array[String] (id azioni che lo lasciano trovare: ritrovamenti rari `secondary`/`drops`)


static func reset_cache() -> void:
	_drops.clear()
	_acts.clear()
	_finds.clear()


# ------------------------------------------------------------------ nomi

static func _tr(key: String) -> String:
	return str(TranslationServer.translate(key))


static func item_name(item_id: String) -> String:
	return Loc.t(DataRegistry.item(item_id).get("name", item_id))


static func skill_name(skill_id: String) -> String:
	return Loc.t(DataRegistry.get_def("skills", skill_id).get("name", skill_id))


## Nome della schermata per il pulsante: «Taglialegna», «Combattimento»…
static func screen_name(screen_id: String) -> String:
	if screen_id.begins_with("skill:"):
		return skill_name(screen_id.substr(6))
	var e := ScreenRegistry.get_entry(screen_id)
	if e.is_empty():
		return screen_id
	if e.has("title_data"):
		return Loc.t(e.title_data)
	return str(TranslationServer.translate(str(e.title)))


static func go_label(target: Dictionary) -> String:
	if target.is_empty():
		return ""
	return Loc.tf("UI_QG_GO_TO", {"name": screen_name(str(target.screen))})


static func _t(screen: String, params: Dictionary = {}, hint: String = "UI_QG_HINT_GO") -> Dictionary:
	return {"screen": screen, "params": params, "hint": hint}


static func _screen_ok(screen: String) -> Dictionary:
	var e := ScreenRegistry.get_entry(screen)
	if e.is_empty() or not ScreenRegistry.is_available(e, GameState.data.get("unlocks", [])):
		return {}
	return _t(screen)


static func _skills() -> SkillSystem:
	return Game.system("skills") as SkillSystem


static func _skill_open(skill_id: String) -> bool:
	var sk := _skills()
	return sk != null and sk.is_unlocked(skill_id)


# ------------------------------------------------------------------ dove si ottiene un oggetto

static func _actions_producing(item_id: String) -> Array:
	if _acts.is_empty():
		var all: Dictionary = DataRegistry.all_actions()
		for aid in all:
			for o in all[aid].get("outputs", []):
				if o is Dictionary and not str(o.get("item", "")).is_empty():
					var k := str(o.item)
					if not _acts.has(k):
						_acts[k] = []
					(_acts[k] as Array).append(str(aid))
		if _acts.is_empty():
			_acts["_"] = []
	return _acts.get(item_id, [])


## Azioni che lasciano TROVARE l'oggetto come ritrovamento raro mentre si lavora (campi `secondary` e `drops`, anche con `pick`).
## Contano per gli obiettivi «raccogli» (l'evento dell'azione include i ritrovamenti), non per i prodotti veri e propri.
static func _actions_finding(item_id: String) -> Array:
	if _finds.is_empty():
		var all: Dictionary = DataRegistry.all_actions()
		for aid in all:
			var a: Dictionary = all[aid]
			for key in ["secondary", "drops"]:
				for sec in a.get(key, []):
					if not (sec is Dictionary):
						continue
					var rows: Array = sec.get("pick", [])
					if rows.is_empty():
						rows = [sec]
					for p in rows:
						if p is Dictionary and not str(p.get("item", "")).is_empty():
							var k := str(p.item)
							if not _finds.has(k):
								_finds[k] = []
							if not (_finds[k] as Array).has(str(aid)):
								(_finds[k] as Array).append(str(aid))
		if _finds.is_empty():
			_finds["_"] = []
	return _finds.get(item_id, [])


## L'azione `a` dà l'oggetto (come prodotto o come ritrovamento raro): lo usa anche il filtro «produce» della schermata mansione.
static func action_yields(a: Dictionary, item_id: String) -> bool:
	for o in a.get("outputs", []):
		if o is Dictionary and str(o.get("item", "")) == item_id:
			return true
	return _actions_finding(item_id).has(str(a.get("id", "")))


## Azione consigliata per ottenere l'oggetto come RITROVAMENTO (mansione già sbloccata e livello più basso).
static func best_find(item_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_key := 1e18
	for aid in _actions_finding(item_id):
		var a: Dictionary = DataRegistry.action(str(aid))
		var key := float(a.get("level_req", 1)) + (0.0 if _skill_open(str(a.get("skill", ""))) else 100000.0)
		if key < best_key:
			best_key = key
			best = a
	return best


## Azione consigliata per ottenere l'oggetto: la prima con mansione già sbloccata (a parità, il livello richiesto più basso).
static func best_action(item_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_key := 1e18
	for aid in _actions_producing(item_id):
		var a: Dictionary = DataRegistry.action(str(aid))
		var key := float(a.get("level_req", 1)) + (0.0 if _skill_open(str(a.get("skill", ""))) else 100000.0)
		if key < best_key:
			best_key = key
			best = a
	return best


static func _drop_source(item_id: String) -> Dictionary:
	if _drops.is_empty():
		var tables := {}
		for t in DataRegistry.table("drop_tables"):
			tables[str(t.id)] = t
		for m in DataRegistry.table("monsters"):
			var t: Dictionary = tables.get(str(m.get("drop_table", "")), {})
			var rows: Array = []
			rows.append_array(t.get("always", []))
			rows.append_array(t.get("entries", []))
			for r in rows:
				if not (r is Dictionary) or str(r.get("item", "")).is_empty():
					continue
				var k := str(r.item)
				var ch := float(r.get("chance", 1.0))
				if not _drops.has(k) or ch > float(_drops[k].chance):
					_drops[k] = {"monster": str(m.id), "zone": str(m.get("zone", "")), "chance": ch}
		if _drops.is_empty():
			_drops["_"] = {"monster": "", "zone": "", "chance": 0.0}
	return _drops.get(item_id, {})


## Voce dell'Emporio (data/shop.json) che vende l'oggetto a prezzo fisso, {} se nessuna. Resoconto 117: la guida di main_c5_q1
## mandava a cercare la Fiala Vuota al Mercato, ma si compra all'Emporio.
static func _shop_source(item_id: String) -> Dictionary:
	for e in DataRegistry.table("shop"):
		if e is Dictionary and str(e.get("item", "")) == item_id and str(e.get("section", "")) == "goods":
			return e
	return {}


## Missione che dà l'oggetto come ricompensa (la prima nell'ordine dei dati), {} se nessuna.
static func _reward_quest(item_id: String) -> Dictionary:
	for q in DataRegistry.table("quests"):
		for r in q.get("rewards", {}).get("items", []):
			if r is Dictionary and str(r.get("item", "")) == item_id:
				return q
	return {}


## Dove si ottiene l'oggetto: {text, target}. Prima una mansione che lo produce, poi il mostro che lo lascia cadere (con la
## zona), poi il Mercato. Mai testo inventato: se i dati non indicano una fonte, lo dice onestamente.
static func where_item(item_id: String) -> Dictionary:
	var a := best_action(item_id)
	if not a.is_empty():
		var sk := str(a.skill)
		if _skill_open(sk):
			return {"text": Loc.tf("UI_QG_WHERE_ACTION", {"skill": skill_name(sk), "action": Loc.t(a.name)}),
				"target": _t("skill:" + sk, {"skill": sk, "produces": item_id}, "UI_UIB_REQ_HINT_PRODUCE")}
		var hint := UnlockSystem.hint_for("skill:" + sk, DataRegistry)
		return {"text": Loc.tf("UI_QG_WHERE_LOCKED", {"skill": skill_name(sk), "hint": hint if not hint.is_empty() else _tr("UI_INTEG_LOCKED_LATER")}),
			"target": ReqLink.target_for_token("skill:" + sk)}
	var fa := best_find(item_id)
	if not fa.is_empty():
		var fsk := str(fa.skill)
		if _skill_open(fsk):
			return {"text": Loc.tf("UI_QG_WHERE_FIND", {"skill": skill_name(fsk), "action": Loc.t(fa.name)}),
				"target": _t("skill:" + fsk, {"skill": fsk, "produces": item_id}, "UI_UIB_REQ_HINT_PRODUCE")}
	var d := _drop_source(item_id)
	if not d.is_empty() and not str(d.monster).is_empty():
		var m := DataRegistry.get_def("monsters", str(d.monster))
		var z := DataRegistry.get_def("zones", str(d.zone))
		var tgt := _screen_ok("combat")
		if not tgt.is_empty():
			tgt = _t("combat", {"zone": str(d.zone), "monster": str(d.monster)})
		return {"text": Loc.tf("UI_QG_WHERE_DROP", {"monster": Loc.t(m.get("name", d.monster)), "zone": Loc.t(z.get("name", d.zone))}), "target": tgt}
	var rq := _reward_quest(item_id)
	if not rq.is_empty():
		return {"text": Loc.tf("UI_QG_WHERE_QUEST", {"quest": QuestText.title(rq)}), "target": ReqLink.target_for_quest(str(rq.id))}
	var shop_row := _shop_source(item_id)            # Emporio (tabella shop dei dati): Fiala Vuota, chiavi...
	if not shop_row.is_empty():
		var sh := _screen_ok("shop")
		if not sh.is_empty():
			return {"text": Loc.tf("UI_QG_WHERE_SHOP", {"price": NumberFormat.fmt(int(shop_row.get("price", 0)))}),
				"target": _t("shop", {}, "UI_UIB_REQ_HINT_SHOP")}
	if bool(DataRegistry.item(item_id).get("tradeable", false)):
		var mk := _screen_ok("market")
		if not mk.is_empty():
			return {"text": _tr("UI_QG_WHERE_MARKET"), "target": _t("market", {"item": item_id}, "UI_UIB_REQ_HINT_BUY")}
	return {"text": _tr("UI_QG_WHERE_OTHER"), "target": {}}


# ------------------------------------------------------------------ istruzioni per obiettivo

static func _extra(text: String, target: Dictionary) -> Dictionary:
	return {"text": text, "target": target}


static func _level_gap(a: Dictionary) -> Array:
	var sk := _skills()
	var out: Array = []
	var skill := str(a.get("skill", ""))
	if sk != null and sk.is_unlocked(skill) and sk.level(skill) < int(a.get("level_req", 1)):
		out.append(_extra(Loc.tf("UI_QG_NEED_LEVEL", {"n": int(a.level_req), "skill": skill_name(skill)}), ReqLink.target_for_level(skill)))
	return out


## Produzione di un oggetto con una mansione (raccolta o creazione): «Apri X, scegli «Y» e premi Avvia» + ingredienti con la loro fonte.
static func _produce(item_id: String) -> Dictionary:
	var a := best_action(item_id)
	if a.is_empty():
		var fa := best_find(item_id)
		if not fa.is_empty() and _skill_open(str(fa.skill)):
			# ritrovamento raro (es. il Quarzo Grezzo mentre si estrae): si dice COSA fare, non di comprarlo al Mercato
			var fsk := str(fa.skill)
			return {"text": Loc.tf("UI_QG_HOW_FIND", {"skill": skill_name(fsk), "action": Loc.t(fa.name), "item": item_name(item_id)}),
				"target": _t("skill:" + fsk, {"skill": fsk, "produces": item_id}, "UI_UIB_REQ_HINT_PRODUCE"), "extra": _level_gap(fa)}
		var w := where_item(item_id)
		return {"text": Loc.tf("UI_QG_HOW_NOACTION", {"item": item_name(item_id), "where": w.text}), "target": w.target, "extra": []}
	var sk := str(a.skill)
	var extra: Array = []
	if not _skill_open(sk):
		var w2 := where_item(item_id)
		return {"text": Loc.tf("UI_QG_HOW_LOCKED", {"skill": skill_name(sk), "item": item_name(item_id), "hint": w2.text}), "target": w2.target, "extra": []}
	extra.append_array(_level_gap(a))
	var inputs: Array = a.get("inputs", [])
	for inp in inputs:
		if extra.size() >= MAX_EXTRA:
			break
		var iid := str(inp.get("item", ""))
		var w3 := where_item(iid)
		extra.append(_extra(Loc.tf("UI_QG_INPUT", {"n": NumberFormat.fmt(int(inp.get("qty", 1))), "item": item_name(iid), "where": w3.text}), w3.target))
	return {"text": Loc.tf("UI_QG_HOW_ACTION", {"skill": skill_name(sk), "action": Loc.t(a.name)}),
		"target": _t("skill:" + sk, {"skill": sk, "produces": item_id}, "UI_UIB_REQ_HINT_PRODUCE"), "extra": extra}


static func _first_open_skill() -> String:
	var sk := _skills()
	if sk == null:
		return ""
	for d in DataRegistry.table("skills"):
		if sk.is_unlocked(str(d.id)) and not ScreenRegistry.SKILL_GROUPS_HIDDEN.has(str(d.get("group", ""))):
			return str(d.id)
	return ""


static func _skill_target(skill_id: String) -> Dictionary:
	if skill_id == "hero":
		return _screen_ok("combat")
	var t := ReqLink.target_for_level(skill_id)
	return t


static func _quests_target() -> Dictionary:
	return _t("quests")


static func _simple(key: String, params: Dictionary, target: Dictionary, extra: Array = []) -> Dictionary:
	return {"text": Loc.tf(key, params), "target": target, "extra": extra}


## Istruzione per un obiettivo: {text, target, extra}. `text` non è mai vuoto (ripiego generico), `target` è {} solo se la
## schermata giusta non è ancora sbloccata (allora `extra` e il motivo dicono cosa fare prima).
static func howto(obj: Dictionary) -> Dictionary:
	var t := str(obj.get("type", ""))
	var n := NumberFormat.fmt(QuestSystem.target_of(obj))
	match t:
		"gather", "craft":
			return _produce(str(obj.get("item", "")))
		"farm_harvest":
			var crop := str(obj.get("crop", ""))
			return _simple("UI_QG_HOW_FARM", {"crop": item_name(crop), "skill": skill_name("farming")}, _skill_target("farming"))
		"kill":
			var mid := str(obj.get("monster", ""))
			var m := DataRegistry.get_def("monsters", mid)
			var zid := str(m.get("zone", ""))
			var z := DataRegistry.get_def("zones", zid)
			var extra: Array = []
			var combat := Game.system("combat") as CombatSystem
			if combat != null and not combat.zone_unlocked(zid):
				var zt := ReqLink.target_for_token("zone:" + zid)
				extra.append(_extra(Loc.tf("UI_QG_ZONE_LOCKED", {"zone": Loc.t(z.get("name", zid))}), zt))
			# MURI (BOT-06): un boss che richiede molto cibo lo dice (quante porzioni, quante ne hai, e che il Deposito pieno blocca la cucina).
			if combat != null and combat.zone_unlocked(zid) and ["boss", "dungeon_boss", "raid_boss"].has(str(m.get("type", ""))):
				var need := int(ceil(float(combat.estimate(mid).get("food_per_kill", 0.0))))
				var have := combat.food_available()
				if need > have:
					extra.append(_extra(Loc.tf("UI_QG_BOSS_FOOD", {"need": need, "have": have}), _screen_ok("skill:cooking")))
					# Resoconto 117 (P4 del 111): il Collezionista chiede 113 porzioni di food_lynx ma ~10 di food_vaultkoi, che la
					# missione precedente regala. Se in borsa c'è un cibo migliore di quello negli slot, la guida lo dice.
					var bf := _best_food_for(combat, need)
					if not bf.is_empty():
						extra.append(_extra(Loc.tf("UI_QG_BOSS_FOOD_BEST", {"food": item_name(str(bf.id)), "have": NumberFormat.fmt(int(bf.have)),
							"need": int(bf.need)}), _screen_ok("hero")))
					var bank := Game.system("bank") as BankSystem
					if bank != null and bank.free_slots() <= 2:
						extra.append(_extra(Loc.tf("UI_QG_BANK_FULL", {}), _screen_ok("bank")))
			var tgt := _screen_ok("combat")
			if not tgt.is_empty():
				tgt = _t("combat", {"zone": zid, "monster": mid, "focus": "start"})
			return _simple("UI_QG_HOW_KILL", {"zone": Loc.t(z.get("name", zid)), "monster": Loc.t(m.get("name", mid))}, tgt, extra)
		"kill_any":
			return _simple("UI_QG_HOW_KILL_ANY", {}, _screen_ok("combat"))
		"kill_any_as_class":
			return _simple("UI_QG_HOW_KILL_CLASS", {"class": QuestText._name_for(obj, DataRegistry)}, _screen_ok("hero"))
		"complete_dungeon":
			return _simple("UI_QG_HOW_DUNGEON", {}, _dungeon_target("dungeon", {"dungeon": str(obj.get("dungeon", ""))}))
		"complete_raid":
			return _simple("UI_QG_HOW_RAID", {}, _dungeon_target("raids"))
		"world_boss":
			return _simple("UI_QG_HOW_WBOSS", {}, _dungeon_target("worldboss"))
		"rift_floor":
			return _simple("UI_QG_HOW_RIFT", {}, _dungeon_target("rift"))
		"reach_level", "skill_actions":
			var sid := str(obj.get("skill", ""))
			if sid == "hero":
				return _simple("UI_QG_HOW_LEVEL_HERO", {}, _skill_target("hero"))
			if not _skill_open(sid):
				var hint := UnlockSystem.hint_for("skill:" + sid, DataRegistry)
				return _simple("UI_QG_HOW_SKILL_LOCKED", {"skill": skill_name(sid), "hint": hint if not hint.is_empty() else _tr("UI_INTEG_LOCKED_LATER")},
					ReqLink.target_for_token("skill:" + sid))
			return _simple("UI_QG_HOW_LEVEL_SKILL", {"skill": skill_name(sid)}, _skill_target(sid))
		"reach_total_level":
			var fs := _first_open_skill()
			return _simple("UI_QG_HOW_TOTAL", {}, _skill_target(fs) if not fs.is_empty() else {})
		"equip":
			return _simple("UI_QG_HOW_EQUIP", {"item": item_name(str(obj.get("item", "")))}, _screen_ok("hero"))
		"build":
			var bid := str(obj.get("building", ""))
			var bname := Loc.t(DataRegistry.get_def("estate_buildings", bid).get("name", bid))
			return _simple("UI_QG_HOW_BUILD", {"building": bname, "level": int(obj.get("level", 1))}, ReqLink.target_for_building(bid))
		"estate_total_levels", "estate_prestige":
			return _simple("UI_QG_HOW_ESTATE", {}, _screen_ok("estate"))
		"sell_market":
			return _simple("UI_QG_HOW_SELL", {"gold": NumberFormat.fmt(int(obj.get("gold", 0)))}, _screen_ok("market"))
		"orders_complete":
			return _simple("UI_QG_HOW_ORDERS", {}, _screen_ok("orders"))
		"steal":
			return _simple("UI_QG_HOW_STEAL", {"skill": skill_name("thievery")}, ReqLink.target_for_level("thievery"))
		"deliver":
			var iid := str(obj.get("item", ""))
			var w := where_item(iid)
			return {"text": Loc.tf("UI_QG_HOW_DELIVER", {"item": item_name(iid), "where": w.text}), "target": w.target, "extra": []}
		"talk":
			var npc := Loc.t(DataRegistry.get_def("npcs", str(obj.get("npc", ""))).get("name", obj.get("npc", "")))
			return _simple("UI_QG_HOW_TALK", {"name": npc}, _quests_target())
		"open_crates", "obtain_rarity":
			return _simple("UI_QG_HOW_CRATES", {}, _screen_ok("vault_hall"))
		"tradeup":
			return _simple("UI_QG_HOW_TRADEUP", {}, _t("vault_workshop", {"tab": "contracts"}) if not _screen_ok("vault_workshop").is_empty() else {})
		"refine_polish", "socket_glyph":
			return _simple("UI_QG_HOW_WORKSHOP", {}, _t("vault_workshop", {"tab": "refine"}) if not _screen_ok("vault_workshop").is_empty() else {})
		"recruit":
			return _simple("UI_QG_HOW_RECRUIT", {}, _screen_ok("guild"))
		"expedition":
			return _simple("UI_QG_HOW_EXPEDITION", {}, _screen_ok("guild"))
		"bounty_complete":
			return _simple("UI_QG_HOW_BOUNTY", {}, _screen_ok("bounty"))
		"star":
			return _simple("UI_QG_HOW_STAR", {}, _screen_ok("prestige") if not _screen_ok("prestige").is_empty() else ReqLink.target_for_token("feature:prestige"))
		"secret_spot", "secret_spot_all":
			return _simple("UI_QG_HOW_SECRET", {}, _screen_ok("secrets"))
		"craft_any", "craft_category", "craft_rank":
			var cs := str(obj.get("skill", ""))
			if cs.is_empty() or not _skill_open(cs):
				return _simple("UI_QG_HOW_GENERIC", {"goal": QuestText.objective(obj, DataRegistry)}, _quests_target())
			return _simple("UI_QG_HOW_LEVEL_SKILL", {"skill": skill_name(cs)}, _skill_target(cs))
	return _simple("UI_QG_HOW_GENERIC", {"goal": QuestText.objective(obj, DataRegistry), "n": n}, _quests_target())


## Il cibo con la cura più alta che il giocatore ha in borsa (Carro compreso), se batte quello degli slot: {id, have, need}
## con `need` = porzioni stimate di QUEL cibo (proporzionale alla cura), {} se non c'è niente di meglio.
static func _best_food_for(combat: CombatSystem, need: int) -> Dictionary:
	var bank := Game.system("bank") as BankSystem
	if combat == null or bank == null:
		return {}
	var cur_heal := 0.0
	for fid in combat.food_slots():
		if not str(fid).is_empty():
			cur_heal = float((DataRegistry.item(str(fid)).get("food", {}) as Dictionary).get("heal", 0))
			break
	if cur_heal <= 0.0:
		return {}
	var best_id := ""
	var best_heal := cur_heal
	for it in DataRegistry.items_by_category("food"):
		var h := float((it.get("food", {}) as Dictionary).get("heal", 0))
		if h > best_heal and bank.count(str(it.id)) > 0:
			best_heal = h
			best_id = str(it.id)
	if best_id.is_empty():
		return {}
	return {"id": best_id, "have": bank.count(best_id), "need": int(ceil(float(need) * cur_heal / best_heal))}


static func _dungeon_target(tab: String, extra_params: Dictionary = {}) -> Dictionary:
	if _screen_ok("dungeon").is_empty():
		return {}
	var p := {"tab": tab}
	for k in extra_params:
		if not str(extra_params[k]).is_empty():
			p[k] = extra_params[k]
	return _t("dungeon", p)


# ------------------------------------------------------------------ motivo, requisiti

## «Sblocca: Fabbro, Zona X» dai token `unlocks` della missione (i capitoli non si elencano). "" se non sblocca nulla.
static func why(quest_def: Dictionary) -> String:
	var names := PackedStringArray()
	for tok in quest_def.get("unlocks", []):
		var kind := str(tok).get_slice(":", 0)
		if SKIP_UNLOCK_KINDS.has(kind):
			continue
		names.append(UnlockSystem.token_name(str(tok), DataRegistry))
	if names.is_empty():
		return ""
	return Loc.tf("UI_QG_WHY", {"list": ", ".join(names)})


## Missione non ancora disponibile perché ne manca una precedente: {text, target} (vuoto se è disponibile).
static func lock_reason(quest_def: Dictionary, quests: QuestSystem) -> Dictionary:
	for r in quest_def.get("requires", []):
		if not quests.is_done(str(r)):
			var rd := quests.quest_def(str(r))
			return {"text": Loc.tf("UI_QG_REQUIRES", {"quest": QuestText.title(rd)}), "target": ReqLink.target_for_quest(str(r))}
	return {}


## Prossime n missioni principali non ancora iniziate, nell'ordine dei dati.
static func upcoming(quests: QuestSystem, n: int) -> Array:
	var out: Array = []
	for q in DataRegistry.table("quests"):
		if str(q.get("kind", "")) != "main":
			continue
		var qid := str(q.id)
		if quests.is_done(qid) or quests.is_active(qid):
			continue
		out.append(q)
		if out.size() >= n:
			break
	return out


# ------------------------------------------------------------------ scoperta

## Passi di scoperta da proporre: requisiti soddisfatti e schermata mai aperta. [{id, title, text, why, target, screen}]
static func discoveries(quests: QuestSystem) -> Array:
	var out: Array = []
	var unlocks: Array = GameState.data.get("unlocks", [])
	for g in DataRegistry.table("guides"):
		var ok := true
		for tok in g.get("requires", []):
			if not unlocks.has(tok):
				ok = false
				break
		if not ok or quests.has_seen_screen(str(g.screen)):
			continue
		var goto: Dictionary = g.get("goto", {})
		var tgt := _screen_ok(str(goto.get("screen", g.screen)))
		if not tgt.is_empty():
			tgt = _t(str(goto.screen), goto.get("params", {}))
		out.append({"id": str(g.id), "title": Loc.t(g.title), "text": Loc.t(g.text), "why": Loc.t(g.why), "target": tgt, "screen": str(g.screen)})
	return out


## Obiettivo attuale: {kind: claim|quest|end|none, qid, title, ready, obj_text, cur, tg, how, target, extra, why, discover}.
## `discover` = primo passo di scoperta (o {}): la UI lo mostra accanto alla missione, mai al suo posto.
static func current_goal(quests: QuestSystem) -> Dictionary:
	var g := {"kind": "none", "qid": "", "title": "", "ready": false, "obj_text": "", "cur": 0, "tg": 0, "how": "", "target": {}, "extra": [],
		"why": "", "discover": {}}
	var ds := discoveries(quests)
	if not ds.is_empty():
		g.discover = ds[0]
	var qid := ""
	for a in quests.active_quests():
		if a.ready and (qid.is_empty() or a.kind == "main"):
			qid = str(a.id)
	var ready := not qid.is_empty()
	if not ready:
		qid = quests.current_main()
	if qid.is_empty():
		g.kind = "end" if not (quests.state.done as Array).is_empty() else "none"
		return g
	var d := quests.quest_def(qid)
	g.qid = qid
	g.title = QuestText.title(d)
	g.ready = ready
	g.why = why(d)
	if ready:
		g.kind = "claim"
		g.how = _tr("UI_QG_HOW_CLAIM")
		g.target = _quests_target()
		return g
	g.kind = "quest"
	var objs: Array = d.get("objectives", [])
	var pr := quests.progress_of(qid)
	for i in objs.size():
		var tgv := QuestSystem.target_of(objs[i])
		var cur := int(pr[i]) if i < pr.size() else 0
		if cur < tgv:
			var h := howto(objs[i])
			g.obj_text = QuestText.objective(objs[i], DataRegistry)
			g.cur = cur
			g.tg = tgv
			g.how = h.text
			g.target = h.target
			g.extra = h.extra
			break
	return g
