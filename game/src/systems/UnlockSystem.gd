class_name UnlockSystem
extends GameSystem
## Sblocchi progressivi (docs/03 §3, docs/12 R-QU-9, docs/audit 17 "unlock"). Stato `unlocks`: Array di token
## ("skill:woodcutting", "feature:crates", "zone:millbrook", "chapter:1", ...). Chi legge senza dipendenza può
## usare `token in ctx.state.unlocks`. Gli sblocchi arrivano dalle missioni (QuestSystem chiama grant()).
##
## Qui vivono anche gli aiuti statici (puri, senza stato) per la UI e per QuestSystem:
##   hint_for(token, data)        "Si sblocca con: missione «X»" per le voci grigie (R-UNL-1)
##   tutorial_lines(token, data)  le 3 righe del tutorial al primo sblocco (R-UNL-2), già tradotte
##   required_tokens(obj, data)   token che servono per poter svolgere un obiettivo (vedi QuestSystem)

const TUTORIAL_PREFIXES: PackedStringArray = ["skill:", "feature:"]


func has_tick() -> bool:
	return false


func _init() -> void:
	id = "unlock"
	state_key = "unlocks"


func default_state() -> Variant:
	return []


func from_state(section: Variant) -> void:
	state = section if section is Array else []
	# salvataggi precedenti: la schermata Eroe si apriva più tardi del Combattimento; ora arrivano insieme
	var arr: Array = state
	if arr.has("feature:combat") and not arr.has("skill:hero"):
		arr.append("skill:hero")


func has(token: String) -> bool:
	return token.is_empty() or (state as Array).has(token)


## Aggiunge il token (idempotente) ed emette `unlocked` solo la prima volta. Ritorna true se era nuovo.
func grant(token: String) -> bool:
	if token.is_empty() or (state as Array).has(token):
		return false
	(state as Array).append(token)
	ctx.events.unlocked.emit(token)
	return true


func tokens() -> Array:
	return (state as Array).duplicate()


# ------------------------------------------------------------------ aiuti statici

static func has_tutorial(token: String) -> bool:
	for p in TUTORIAL_PREFIXES:
		if token.begins_with(p):
			return true
	return false


## Nome leggibile di un token (già tradotto): mansione dai dati, altrimenti chiave UI_QUESTS_TOKEN_<tipo>.
static func token_name(token: String, data: Object) -> String:
	var parts := token.split(":", true, 1)
	if parts.size() < 2:
		return token
	var kind := parts[0]
	var key := parts[1]
	match kind:
		"skill":
			var s: Dictionary = data.get_def("skills", key)
			return Loc.t(s.get("name", key)) if not s.is_empty() else key
		"zone":
			var z: Dictionary = data.get_def("zones", key)
			return Loc.t(z.get("name", key)) if not z.is_empty() else key
		"building":
			var b: Dictionary = data.get_def("estate_buildings", key)
			return Loc.t(b.get("name", key)) if not b.is_empty() else key
		"feature":
			var k := "UI_QUESTS_FEATURE_" + key.to_upper()
			return str(TranslationServer.translate(k)) if _has_key(k) else key
		"chapter":
			var c: Dictionary = data.get_def("chapters", key)
			return Loc.t(c.get("name", key)) if not c.is_empty() else key
		"dungeon", "raid", "class":
			var d: Dictionary = data.get_def({"dungeon": "dungeons", "raid": "raids", "class": "classes"}[kind], key)
			return Loc.t(d.get("name", key)) if not d.is_empty() else key
		"era":
			return Loc.tf("UI_QG_ERA", {"n": key})
	return key


static func _has_key(key: String) -> bool:
	return TranslationServer.translate(key) != key


## Prima missione dei dati che concede il token (id), "" se nessuna.
static func quest_for_token(token: String, data: Object) -> String:
	for q in data.table("quests"):
		if (q.get("unlocks", []) as Array).has(token):
			return str(q.id)
	return ""


## "Si sblocca con: missione «Titolo»" ("" se il token non è concesso da nessuna missione).
static func hint_for(token: String, data: Object) -> String:
	var qid := quest_for_token(token, data)
	if qid.is_empty():
		return ""
	var q: Dictionary = data.get_def("quests", qid)
	return Loc.tf("UI_QUESTS_UNLOCK_HINT", {"quest": Loc.t(q.get("title", qid))})


## Le 3 righe del tutorial (già tradotte). Mansioni: descrizione dai dati + 2 righe per gruppo.
## Funzioni: 3 chiavi dedicate UI_QUESTS_TUT_<FEATURE>_1..3, oppure generiche.
static func tutorial_lines(token: String, data: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var parts := token.split(":", true, 1)
	if parts.size() < 2:
		return out
	if parts[0] == "skill":
		var s: Dictionary = data.get_def("skills", parts[1])
		var group := str(s.get("group", "gathering"))
		out.append(Loc.t(s.get("desc", "")))
		out.append(TranslationServer.translate("UI_QUESTS_TUT_SKILL_%s_2" % group.to_upper()))
		out.append(TranslationServer.translate("UI_QUESTS_TUT_SKILL_%s_3" % group.to_upper()))
	elif parts[0] == "feature":
		var base := "UI_QUESTS_TUT_%s_" % parts[1].to_upper()
		if _has_key(base + "1"):
			for i in range(1, 4):
				out.append(TranslationServer.translate(base + str(i)))
		else:
			for i in range(1, 4):
				out.append(TranslationServer.translate("UI_QUESTS_TUT_GENERIC_%d" % i))
	return out


## Token necessari per svolgere un obiettivo. ["*"] = tipo non classificato (QuestSystem concede tutto subito).
static func required_tokens(obj: Dictionary, data: Object) -> Array:
	var t := str(obj.get("type", ""))
	match t:
		"gather", "craft", "farm_harvest", "deliver":
			var sk := _skill_of_item(str(obj.get("item", obj.get("crop", ""))), data)
			return ["skill:" + sk] if not sk.is_empty() else []
		"skill_actions", "craft_any", "reach_level":
			var sk2 := str(obj.get("skill", ""))
			return ["skill:" + sk2] if not sk2.is_empty() and sk2 != "any" else []
		"craft_category", "craft_rank", "reach_total_level", "talk", "star":
			return []
		"kill":
			var m: Dictionary = data.get_def("monsters", str(obj.get("monster", "")))
			var out: Array = ["feature:combat"]
			if not m.is_empty():
				out.append("zone:" + str(m.get("zone", "")))
			return out
		"kill_zone":
			return ["feature:combat", "zone:" + str(obj.get("zone", ""))]
		"kill_any", "kill_any_as_class":
			return ["feature:combat"]
		"equip":
			return ["feature:combat", "skill:hero"]      # si indossa dalla scheda Eroe: si apre insieme al Combattimento
		"open_crates", "obtain_rarity":
			return ["feature:crates"]
		"build":
			# si costruisce dalla Tenuta: senza `feature:estate` la schermata resta chiusa e la missione che la sblocca
			# (main_c2_q2) non si potrebbe mai fare (playtest novizio 121)
			return ["feature:estate", "building:" + str(obj.get("building", ""))]
		"complete_dungeon":
			return ["dungeon:" + str(obj.get("dungeon", ""))] if str(obj.get("dungeon", "any")) != "any" else []
		"sell_market":
			return ["feature:market"]
	return ["*"]


static func _skill_of_item(item_id: String, data: Object) -> String:
	if item_id.is_empty():
		return ""
	var actions: Dictionary = data.all_actions()
	for aid in actions:
		var a: Dictionary = actions[aid]
		for o in a.get("outputs", []):
			if o is Dictionary and str(o.get("item", "")) == item_id:
				return str(a.get("skill", ""))
	return ""
