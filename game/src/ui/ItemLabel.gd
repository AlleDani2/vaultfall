class_name ItemLabel
extends RefCounted
## Nomi leggibili delle ISTANZE di equipaggiamento per Deposito ed Eroe (feedback del giocatore: due «Manopole di Rame»
## identiche in elenco non si distinguevano). Il nome porta qualità e rango; se due istanze hanno lo stesso nome compare
## anche un codice breve «#14» (il numero dell'istanza), così si sa quale è quale e quale è indossata. Solo presentazione.

const QUALITY_KEYS := {"normal": "UI_BANK_Q_NORMAL", "fine": "UI_BANK_Q_FINE", "excellent": "UI_BANK_Q_EXCELLENT",
	"masterwork": "UI_BANK_Q_MASTERWORK"}


## «Manopole di Rame · Fine +2» (nome, qualità se non Normale, rango se > 0).
static func label(inst: Dictionary) -> String:
	var def := DataRegistry.item(str(inst.get("def", "")))
	return label_from(Loc.t(def.get("name", {})), inst)


## Come label() con il nome base già pronto (elenchi lunghi: il nome sta in una cache della schermata).
static func label_from(base_name: String, inst: Dictionary) -> String:
	var nm := base_name
	var q := str(inst.get("quality", ""))
	if not q.is_empty() and q != "normal" and QUALITY_KEYS.has(q):
		nm += " · " + TranslationServer.translate(QUALITY_KEYS[q])
	if int(inst.get("rank", 0)) > 0:
		nm += " +%d" % int(inst.rank)
	return nm


## Codice breve dell'istanza: «#14» (da «i_14»). Per le pile ("") nulla.
static func short_id(uid: String) -> String:
	if uid.is_empty():
		return ""
	return "#" + str(uid.trim_prefix("i_").to_int())


## Slot (testo tradotto) dove un'istanza è indossata, «» se non lo è. Gli attrezzi: «Utensile: Ascia…» → solo la mansione.
static func worn_slot_name(uid: String) -> String:
	if not GameState.active or uid.is_empty():
		return ""
	var cb := Game.system("combat") as CombatSystem
	if cb == null:
		return ""
	return slot_name(cb.worn_slot(uid))


static func slot_name(slot: String) -> String:
	if slot.is_empty():
		return ""
	if slot.begins_with("tool:"):
		var sk := DataRegistry.get_def("skills", slot.substr(5))
		return Loc.tf("UI_EQ_TOOL_OF", {"skill": Loc.t(sk.get("name", slot.substr(5)))})
	return TranslationServer.translate("UI_HERO_SLOT_" + slot.to_upper())


## Nome della finitura del Guardaroba su un pezzo indossato nello slot («» se nessuna): «◆ Spiga Dorata».
static func finish_text(slot: String) -> String:
	var crates := Game.system("crates") as CrateSystem if GameState.active else null
	if crates == null:
		return ""
	var inst: Dictionary = crates.instance(crates.equipped(slot)) if not crates.equipped(slot).is_empty() else {}
	if inst.is_empty():
		return ""
	return "%s %s" % [CrateUi.rarity_symbol(str(inst.get("rarity", "rare"))), CrateUi.def_name(str(inst.get("def_id", "")))]
