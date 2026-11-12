extends Node
## GameState (autoload) — UNICO stato mutabile del giocatore (docs/17 §3-4). Niente logica di gioco qui:
## solo la forma dello stato, la creazione di una nuova partita e letture di comodo.
## R-ARC-1: solo tipi JSON (Dictionary, Array, String, float/int, bool, null), MAI nodi o risorse.
## R-ARC-2: id stabili, mai indici di array dei dati.
## R-SAV-7: interi che possono superare 2^53 (seed RNG, contatori enormi) come STRINGHE.
##
## Ogni sistema (GameSystem) possiede UNA sezione (state_key) e la modifica attraverso il proprio riferimento:
## GameState.data["skills"] è lo stesso Dictionary che SkillSystem tiene in `state`.

const MODES: PackedStringArray = ["normal", "autarchic", "extreme"]
## Modalità selezionabili alla creazione della partita (R-SAV-5). Le regole sono in data/mode_rules.json (ModeRules);
## tutte disponibili dall'inizio: i docs non prevedono uno sblocco, la scelta è avvertita e confermata nel menù (OPEN_QUESTIONS M-1).
const ENABLED_MODES: PackedStringArray = ["normal", "autarchic", "extreme"]

## Campi interi delle sezioni non ancora possedute da un sistema (normalizzazione R-SAV-8 dopo il load).
## Sintassi: "a.b" percorso, "*" = ogni chiave di un dizionario, "[]" = ogni elemento di un array.
## Interi «morbidi» di sezioni senza un sistema proprio (vedi GameSystem.soft_int_paths): la sezione `activity` e' condivisa.
const BASE_SOFT_INT_PATHS: PackedStringArray = ["activity.floor", "activity.idx", "activity.start_floor", "activity.wave", "activity.slot"]
const BASE_INT_PATHS: PackedStringArray = [
	"schema_version", "saved_at_unix", "created_at_unix",
	"skills.*.level", "skills.*.record_level", "skills.*.stars", "mastery.*.level",
	"bank.stacks.*", "bank.instances[].rank", "bank.slots_bought", "equipment.ammo.qty",
	"hero.attrs.*", "hero.talents.*", "crates.pity.*", "crates.opened", "factions.*",
	"estate.buildings.*.level", "estate.buildings.*.settlers", "estate.settlers", "estate.partners",
	"quests.progress.*[]", "contracts.tokens", "prestige.stardust", "prestige.constellations.*",
	"prestige.era_max", "prestige.era_current", "currencies.gold", "stats.kills", "stats.gold_earned", "stats.actions.*",
]

## Sezioni di base che hanno già la loro forma definitiva (le altre sono segnaposto che il sistema proprietario rimpiazza in
## Simulation.bind_state, che ne controlla il tipo): un tipo sbagliato in un salvataggio danneggiato riparte dal valore iniziale.
const KIND_CHECKED: PackedStringArray = ["currencies", "stats", "equipment", "wardrobe", "unlocks", "pets", "achievements", "titles", "orders", "factions", "rng"]

var data: Dictionary = {}
var active: bool = false        # true quando una partita è in corso (nuova o caricata)
var slot: int = 0               # slot 1..3 della partita in corso (0 = nessuna)


## Forma iniziale dello stato (docs/17 §4). Le sezioni dei sistemi possono essere completate dai sistemi
## stessi (GameSystem.default_state) quando vengono agganciati.
static func default_state(p_mode: String = "normal") -> Dictionary:
	return {
		"schema_version": SaveCodec.SCHEMA_VERSION, "saved_at_unix": 0, "created_at_unix": 0, "mode": p_mode,
		"rng": {},
		"currencies": {"gold": 0},
		"skills": {}, "mastery": {},
		"bank": {"stacks": {}, "instances": [], "slots_bought": 0},
		"equipment": {}, "wardrobe": {},
		"hero": {"class": "", "spec": "", "attrs": {}, "talents": {}, "abilities": [], "food": [], "hp": 0.0},
		"activity": {}, "queue": [], "apprentices": [],
		"farming": {"garden": [], "orchard": []},
		"crates": {"pity": {}, "opened": 0, "collections": {}},
		"market": {"sold_recent": {}, "trend": {}, "history": {}, "gazette": {}},
		"orders": [], "factions": {},
		"estate": {"buildings": {}, "settlers": 0, "pantry": 0.0, "storage": {}, "prosperity": 0.0, "partners": 0},
		"mercenaries": [], "expeditions": [],
		"quests": {"active": [], "progress": {}, "done": []},
		"contracts": {"daily": [], "weekly": [], "tokens": 0},
		"prestige": {"stardust": 0, "constellations": {}, "era_max": 1, "era_current": 1, "trials": {}},
		"pets": [], "achievements": [], "titles": [],
		"stats": {"kills": 0, "actions": {}, "gold_earned": 0, "playtime_s": 0.0},
		"unlocks": [],
		"offline_carry_s": 0.0,       # assenze brevissime non ancora applicate (Game.apply_absence, QA81 M4); i vecchi salvataggi lo ricevono in replace()
	}


## Nuovo stato in memoria (non salva e non aggancia i sistemi: lo fa Game.new_game).
func reset_new(p_mode: String, now_unix: int) -> void:
	assert(MODES.has(p_mode), "modalità sconosciuta: " + p_mode)
	data = default_state(p_mode)
	data["created_at_unix"] = now_unix
	data["saved_at_unix"] = now_unix


## Sostituisce lo stato con uno caricato (già migrato e normalizzato da SaveService).
## Le sezioni mancanti (salvataggi vecchi) vengono aggiunte con i valori iniziali.
func replace(loaded: Dictionary) -> void:
	if not MODES.has(str(loaded.get("mode", "normal"))):
		loaded["mode"] = "normal"            # modalità sconosciuta (salvataggio manomesso o futuro): regole Normali
	var base := default_state(str(loaded.get("mode", "normal")))
	for k in base:
		if not loaded.has(k) or loaded[k] == null or (KIND_CHECKED.has(k) and not _same_kind(loaded[k], base[k])):
			loaded[k] = base[k]            # mancante, null o di tipo sbagliato (QA 83 C-05)
	data = loaded


static func _same_kind(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return true
	return typeof(a) == typeof(b)


func clear() -> void:
	data = {}
	active = false
	slot = 0


static func is_mode_enabled(p_mode: String) -> bool:
	return ENABLED_MODES.has(p_mode)


# ------------------------------------------------------------------ letture di comodo (nessuna logica)

func section(key: String) -> Variant:
	return data.get(key)


func has_unlock(token: String) -> bool:
	return data.get("unlocks", []).has(token)


func gold() -> int:
	return int(data.get("currencies", {}).get("gold", 0))


func mode() -> String:
	return str(data.get("mode", "normal"))


## Regole della modalità della partita in corso (per la UI; i sistemi usano ctx.mode_rules()).
func mode_rules() -> ModeRules:
	return ModeRules.make(DataRegistry, mode())


func total_level() -> int:
	return total_level_of(data)


static func total_level_of(d: Dictionary) -> int:
	var t := 0
	for s in d.get("skills", {}).values():
		if s is Dictionary:
			t += int(s.get("level", 0))
	return t
