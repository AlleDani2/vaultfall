class_name HeroBuild
extends RefCounted
## Costruzione dell'Eroe (docs/06): classi base e ibride, specializzazioni, abilità equipaggiate (lista di priorità)
## e talenti (albero, punti, azzeramento). Aiutante di CombatSystem: legge/scrive la sua sezione `hero` e non ha
## numeri di bilanciamento propri (regole in constants.combat.rules, nodi in talents.json, abilità in abilities.json).
##
## Stato (sezione `hero` di CombatSystem):
##   class  classe corrente (base o ibrida) · spec  specializzazione scelta ("" = nessuna)
##   abilities  id equipaggiati in ordine di priorità · auto_abilities  true = scelta automatica
##   talents  {talent_id: rango}, SOLO dell'albero della classe corrente (al cambio classe si azzerano)

const TALENT_SOURCE := "talents"

var _ref: WeakRef
var sys: CombatSystem:
	get:
		return _ref.get_ref() as CombatSystem


func _init(p_sys: CombatSystem) -> void:
	_ref = weakref(p_sys)


func _rules() -> Dictionary:
	return Formulas.k().combat.rules


func _data() -> Object:
	return sys.ctx.data


# ====================================================================== classi e specializzazioni

func class_def(id: String) -> Dictionary:
	return _data().get_def("classes", id)


func _quest_done(quest_id: String) -> bool:
	var q: Variant = sys.ctx.get_system("quests")
	if q != null and q.has_method("is_done") and q.is_done(quest_id):
		return true
	return (sys.ctx.state.get("unlocks", []) as Array).has("class:" + quest_id.trim_prefix("class_"))


func hero_stars() -> int:
	var s: Variant = sys.ctx.state.get("skills", {}).get("hero", {})
	return int(s.get("stars", 0)) if s is Dictionary else 0


## Una classe base è sempre scelta liberamente; una ibrida richiede la Stella dell'Eroe e la missione di classe.
func class_available(class_id: String) -> bool:
	var cd := class_def(class_id)
	if cd.is_empty():
		return false
	if bool(cd.get("base", false)):
		return true
	if not bool(cd.get("hybrid", false)):
		return false
	var u: Dictionary = cd.get("unlock", {})
	return hero_stars() >= int(u.get("hero_stars", 1)) and _quest_done(str(u.get("quest", "")))


func selectable_classes() -> Array:
	var out: Array = []
	for c in _data().table("classes"):
		if bool(c.get("base", false)) or bool(c.get("hybrid", false)):
			out.append({"id": str(c.id), "def": c, "available": class_available(str(c.id))})
	return out


func specs_of(class_id: String) -> Array:
	return (class_def(class_id).get("specializations", []) as Array).duplicate()


## Specializzazione sbloccata: figlia della classe corrente, livello Eroe richiesto e missione di classe completata.
func spec_available(spec_id: String) -> bool:
	var sd := class_def(spec_id)
	if sd.is_empty() or str(sd.get("parent", "")) != str(sys.state.class):
		return false
	var u: Dictionary = sd.get("unlock", {})
	return sys.hero_level() >= int(u.get("hero_level", 1)) and _quest_done(str(u.get("quest", "")))


## Sceglie la specializzazione ("" = nessuna). Gratis, ma non durante il combattimento (R-CL-2).
func set_spec(spec_id: String) -> bool:
	if sys.in_combat():
		return false
	if not spec_id.is_empty() and not spec_available(spec_id):
		return false
	if spec_id == str(sys.state.spec):
		return true
	sys.state["spec"] = spec_id
	sys.on_build_changed()
	return true


# ====================================================================== abilità

## Le abilità di classe valgono solo se si impugna un'arma dello stile della classe (R-CL-4).
func class_abilities_enabled() -> bool:
	var cd := sys.class_def()
	var ws := sys.weapon_style()
	if ws.is_empty():
		return false
	if bool(cd.get("hybrid", false)):
		return (cd.get("styles", []) as Array).has(ws)
	return ws == str(cd.get("style", ""))


## Abilità che l'eroe può usare adesso (classe + specializzazione scelta), per livello crescente.
func abilities_available() -> Array:
	var out: Array = []
	var lvl := sys.hero_level()
	var owners: Array = [str(sys.state.class)]
	if not str(sys.state.spec).is_empty():
		owners.append(str(sys.state.spec))
	for ab in _data().table("abilities"):
		if owners.has(str(ab.class)) and int(ab.level_req) <= lvl:
			out.append(ab)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level_req) < int(b.level_req))
	return out


## Tutte le abilità della classe/spec (anche non ancora sbloccate) per la schermata.
func abilities_of_build() -> Array:
	var out: Array = []
	var owners: Array = [str(sys.state.class)]
	for sp in specs_of(str(sys.state.class)):
		owners.append(str(sp))
	for ab in _data().table("abilities"):
		if owners.has(str(ab.class)):
			out.append(ab)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level_req) < int(b.level_req))
	return out


func ability_slots() -> int:
	return int(_rules().ability_slots)


## Scelta automatica: una difesa d'emergenza (abilità con condizione), poi le tecniche offensive più avanzate
## (danno, danno nel tempo, evocazioni), poi i potenziamenti (buff/debuff/scudi: accompagnano l'attacco senza
## sostituirlo, QA4 #7) negli slot rimasti.
func abilities_auto() -> Array:
	var av := abilities_available()
	var trig: Array = []
	var rest: Array = []
	var boosts: Array = []
	for ab in av:
		var fx: Dictionary = ab.effect
		if fx.has("trigger"):
			trig.append(ab)
		elif ["damage", "dot", "summon"].has(str(fx.type)):
			rest.append(ab)
		elif CombatSim.is_boost(ab):
			boosts.append(ab)
	trig.reverse()
	rest.reverse()
	boosts.reverse()
	# Q97: le evocazioni combattono accanto all'Eroe senza prendere il posto dell'attacco: vanno prima delle altre tecniche
	# (il Domatore ne restava senza, 27% di uccisioni/h in meno contro il compagno scelto a mano). Ordine stabile.
	var summons: Array = []
	var others: Array = []
	for ab in rest:
		if str(ab.effect.type) == "summon":
			summons.append(ab)
		else:
			others.append(ab)
	rest = summons + others
	var out: Array = []
	for ab in trig:
		if out.size() < 1:
			out.append(ab)
	var n_off := 0
	for ab in rest:
		# al massimo 2 tecniche offensive se ci sono potenziamenti: il terzo slot rende di più a un potenziamento gratuito
		if out.size() < ability_slots() and (n_off < 2 or boosts.is_empty()):
			out.append(ab)
			n_off += 1
	for ab in boosts:
		if out.size() < ability_slots():
			out.append(ab)
	for ab in rest:
		if out.size() < ability_slots() and not out.has(ab):
			out.append(ab)
	return out


## Definizioni delle abilità equipaggiate, in ordine di priorità, già filtrate da livello e arma.
func abilities_equipped() -> Array:
	if not class_abilities_enabled():
		return []
	if bool(sys.state.auto_abilities):
		return abilities_auto()
	var out: Array = []
	var av := {}
	for ab in abilities_available():
		av[str(ab.id)] = ab
	for id in sys.state.abilities:
		if av.has(str(id)) and out.size() < ability_slots():
			out.append(av[str(id)])
	return out


func set_auto_abilities(on: bool) -> void:
	if on == bool(sys.state.auto_abilities):
		return
	if not on:
		sys.state["abilities"] = []
		for ab in abilities_auto():
			(sys.state.abilities as Array).append(str(ab.id))
	sys.state["auto_abilities"] = on
	sys.on_build_changed()


## Mette l'abilità nello slot `slot` (0..3); `ability_id` vuoto svuota lo slot. Passa alla scelta manuale.
func set_slot(slot: int, ability_id: String) -> bool:
	if slot < 0 or slot >= ability_slots():
		return false
	if bool(sys.state.auto_abilities):
		set_auto_abilities(false)
	var list: Array = sys.state.abilities
	while list.size() < ability_slots():
		list.append("")
	if ability_id.is_empty():
		list[slot] = ""
	else:
		var ok := false
		for ab in abilities_available():
			if str(ab.id) == ability_id:
				ok = true
		if not ok:
			return false
		var old := list.find(ability_id)
		if old >= 0:
			list[old] = str(list[slot])
		list[slot] = ability_id
	# compatta: niente buchi
	var packed: Array = []
	for id in list:
		if not str(id).is_empty():
			packed.append(str(id))
	sys.state["abilities"] = packed
	sys.on_build_changed()
	return true


# ====================================================================== talenti

func talent_nodes(class_id: String = "") -> Array:
	var cid := class_id if not class_id.is_empty() else str(sys.state.class)
	var out: Array = []
	for t in _data().table("talents"):
		if str(t.class) == cid:
			out.append(t)
	return out


func talent_def(id: String) -> Dictionary:
	return _data().get_def("talents", id)


func rank(id: String) -> int:
	return int(sys.state.talents.get(id, 0))


func points_total() -> int:
	var r: Dictionary = _rules().talents
	var by_level := mini(int(r.max_level_points), int(floor(float(sys.hero_level()) / float(r.hero_levels_per_point))))
	return by_level + mini(int(r.max_star_points), hero_stars())


func points_spent(branch: String = "") -> int:
	var n := 0
	for id in sys.state.talents:
		if branch.is_empty() or str(talent_def(str(id)).get("branch", "")) == branch:
			n += int(sys.state.talents[id])
	return n


func points_free() -> int:
	return maxi(0, points_total() - points_spent())


## "" se si può aggiungere un rango, altrimenti il motivo (chiave breve usata dalla UI).
func why_not(id: String) -> String:
	var t := talent_def(id)
	if t.is_empty() or str(t.class) != str(sys.state.class):
		return "class"
	if rank(id) >= int(t.max_rank):
		return "max"
	if points_free() <= 0:
		return "points"
	var branch := str(t.branch)
	if branch != "general" and branch != "hybrid" and not spec_available(branch):
		return "spec"
	if not branch_active(branch):
		return "inactive"
	if points_spent(branch) < int(t.requires_points_in_branch):
		return "branch"
	return ""


func rank_up(id: String) -> bool:
	if not why_not(id).is_empty():
		return false
	sys.state.talents[id] = rank(id) + 1
	sys.on_build_changed()
	return true


func respec_cost() -> int:
	var r: Dictionary = _rules().talents
	var lvl := sys.hero_level()
	return 0 if lvl <= int(r.respec_free_until_level) else int(r.respec_gold_per_level) * lvl


## Azzera tutti i talenti (gratis fino al livello indicato nei dati, poi a pagamento). Non in combattimento.
func respec() -> bool:
	if sys.in_combat() or sys.state.talents.is_empty():
		return false
	var cost := respec_cost()
	if cost > 0:
		var bank: Variant = sys.ctx.get_system("bank")
		if bank == null or not bank.spend_gold(cost):
			return false
	sys.state["talents"] = {}
	sys.on_build_changed()
	return true


## Ramo che conta adesso: Generale/Ibrido sempre, un ramo di specializzazione solo se è quella attiva (QA4 #9, resoconto 91).
## I punti nel ramo inattivo restano salvati e tornano a valere cambiando specializzazione.
func branch_active(branch: String) -> bool:
	return branch == "general" or branch == "hybrid" or branch == str(sys.state.spec)


## Modificatori dei talenti della classe corrente (rango × valore per rango), solo dei rami attivi.
func talent_mods() -> Array:
	var out: Array = []
	for id in sys.state.talents:
		var t := talent_def(str(id))
		if t.is_empty() or str(t.class) != str(sys.state.class) or not branch_active(str(t.branch)):
			continue
		var r := int(sys.state.talents[id])
		for m in t.modifiers_per_rank:
			var mm: Dictionary = (m as Dictionary).duplicate()
			mm["value"] = float(m.value) * r
			out.append(mm)
	return out
