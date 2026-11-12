class_name CoopPresence
extends RefCounted
## Messaggio di PRESENZA (COOP-2, livello A): chi sei e cosa stai facendo, in poche decine di byte.
## Nessuno stato di gioco viene sincronizzato: solo nome scelto, classe, livello totale, livello dell'Eroe e un codice
## di attività (mansione/azione, combattimento/zona, Tenuta, riposo, Cassa...). Il testo lo compone chi RICEVE, con i
## propri dati e la propria lingua (mai testo libero dall'altro giocatore oltre al soprannome filtrato).

## Animazione del personaggino per attività e mansione (chiavi lette da FriendSprite).
const SKILL_ANIM := {"woodcutting": "chop", "mining": "pick", "fishing": "fish", "foraging": "gather",
	"trapping": "gather", "farming": "gather", "thievery": "sneak", "smithing": "hammer", "keysmithing": "hammer",
	"jewelcrafting": "hammer", "runecarving": "hammer", "woodworking": "saw", "tailoring": "saw",
	"cooking": "cook", "alchemy": "brew"}


## Presenza costruita dagli stati passati (funzione pura, testabile). `info`:
##   name, cls, lvl, hl, action (id azione o ""), skill (id mansione), activity (GameState.data.activity),
##   endgame ("raid"|"wboss"|"rift"|""), dungeon (bool), crate_recent (bool), screen (id schermata), active (partita).
static func build(info: Dictionary) -> Dictionary:
	var p := {"t": "presence", "name": str(info.get("name", "")), "cls": _id(info.get("cls", "")),
		"lvl": clampi(int(info.get("lvl", 0)), 0, 100000), "hl": clampi(int(info.get("hl", 0)), 0, 100000),
		"act": "menu", "sk": "", "det": "", "ping": clampi(int(info.get("ping", 0)), 0, 60000)}
	if not bool(info.get("active", false)):
		return p
	if bool(info.get("crate_recent", false)):
		p.act = "crate"
		return p
	# Chi sta guardando la Tenuta o il Mercato li sta usando davvero (la mansione intanto gira da sola): vince la schermata,
	# altrimenti chi gioca tycoon con una mansione sempre accesa non comparirebbe mai nella Tenuta.
	var scr := str(info.get("screen", ""))
	if scr == "estate" or scr in ["market", "shop", "orders"]:
		p.act = "estate" if scr == "estate" else "market"
		return p
	var action := _id(info.get("action", ""))
	if not action.is_empty():
		p.act = "skill"
		p.sk = _id(info.get("skill", ""))
		p.det = action
		return p
	var act: Dictionary = info.get("activity", {})
	if str(act.get("type", "")) == "combat":
		var eg := str(info.get("endgame", ""))
		p.act = eg if eg in ["raid", "wboss", "rift"] else ("dungeon" if bool(info.get("dungeon", false)) else "combat")
		p.det = _id(act.get("zone", act.get("dungeon", act.get("raid", ""))))
		p.sk = _id(act.get("monster", ""))
		return p
	match str(info.get("screen", "")):
		"estate": p.act = "estate"
		"market", "shop", "orders": p.act = "market"
		_: p.act = "rest"
	return p


## Presenza del giocatore locale letta dalla partita in corso (solo letture pubbliche dei sistemi).
static func local(player_name: String, screen_id: String, crate_recent: bool, ping_ms: int) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("/root/GameState") if tree != null else null
	var game: Node = tree.root.get_node_or_null("/root/Game") if tree != null else null
	var info := {"name": player_name, "ping": ping_ms, "screen": screen_id, "crate_recent": crate_recent,
		"active": gs != null and bool(gs.active)}
	if bool(info.active):
		var data: Dictionary = gs.data
		info["cls"] = str(data.get("hero", {}).get("class", ""))
		info["lvl"] = gs.total_level()
		info["activity"] = data.get("activity", {})
		var sk: Object = game.system("skills")
		if sk != null and sk.has_method("current_action"):
			var aid: String = sk.current_action()
			info["action"] = aid
			if not aid.is_empty():
				info["skill"] = sk.skill_of(aid)
		var cb: Object = game.system("combat")
		if cb != null:
			info["hl"] = cb.hero_level() if cb.has_method("hero_level") else 0
			info["endgame"] = cb.endgame_mode() if cb.has_method("endgame_mode") else ""
			info["dungeon"] = cb.in_dungeon() if cb.has_method("in_dungeon") else false
	return build(info)


## Chiave dell'animazione per una presenza (anche ricevuta da un amico).
static func anim_of(p: Dictionary) -> String:
	match str(p.get("act", "")):
		"skill": return str(SKILL_ANIM.get(str(p.get("sk", "")), "gather"))
		"combat", "dungeon", "raid", "wboss", "rift": return "strike"
		"crate": return "crate"
		"estate": return "hammer"
		"market": return "walk"
		"rest", "menu", "idle": return "sleep"
	return "sleep"


static func _id(v: Variant) -> String:
	var s := str(v).to_lower()
	return s if s.length() <= 48 and RegEx.create_from_string("^[a-z0-9_:]*$").search(s) != null else ""
