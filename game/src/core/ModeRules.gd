class_name ModeRules
extends RefCounted
## Regole della modalità di gioco (docs/05 §7, docs/17 §4). UNICO punto da interrogare: nessun sistema confronta
## mai `mode == "extreme"`; chiede al ModeRules ("si può comprare questo?", "esiste la morte permanente?").
## Le regole sono DATI (data/mode_rules.json, generato da tools/gamedata/meta.py): qui nessun numero e nessun elenco.
##
## Uso nei sistemi:  ctx.mode_rules().market_buy_allowed("vial")  ·  ctx.mode_rules().orders_enabled()
## Uso nella UI:     ModeRules.make(DataRegistry, GameState.mode())  ·  ModeRules.all_ids(DataRegistry)

const NORMAL := "normal"

var mode_id: String = NORMAL
var _rec: Dictionary = {}


## Crea le regole per `p_mode` leggendo `mode_rules` da `data` (DataRegistry o finto dei test).
## Modalità o dati sconosciuti = Normale (nessuna restrizione): un salvataggio non si blocca mai per colpa dei dati.
static func make(data: Object, p_mode: String) -> ModeRules:
	var m := ModeRules.new()
	var rules: Dictionary = data.rules("mode_rules") if data != null and data.has_method("rules") else {}
	var modes: Variant = rules.get("modes", {})
	if modes is Dictionary and (modes as Dictionary).has(p_mode):
		m.mode_id = p_mode
		m._rec = modes[p_mode]
	return m


## Id delle modalità nell'ordine del menù (Normale per prima).
static func all_ids(data: Object) -> PackedStringArray:
	var out := PackedStringArray([NORMAL])
	var rules: Dictionary = data.rules("mode_rules") if data != null and data.has_method("rules") else {}
	var modes: Variant = rules.get("modes", {})
	if modes is Dictionary:
		for k in modes:
			if not out.has(str(k)):
				out.append(str(k))
	return out


static func label_key(p_mode: String) -> String:
	return "UI_MODE_" + p_mode.to_upper()


func is_normal() -> bool:
	return mode_id == NORMAL


# ------------------------------------------------------------------ Autarchica

## true se in questa modalità gli acquisti da Mercato/Emporio sono limitati a un elenco.
func market_buy_restricted() -> bool:
	return _rec.has("market_buy")


## Oggetti acquistabili da PNG (Emporio «merci», scorte del Mercato). Senza restrizioni: tutti.
func market_buy_allowed(item_id: String) -> bool:
	if not market_buy_restricted():
		return true
	return (_rec.market_buy.get("allow_items", []) as Array).has(item_id)


func market_buy_allow_list() -> Array:
	return (_rec.market_buy.get("allow_items", []) as Array) if market_buy_restricted() else []


## Commesse (bacheca dei PNG) attive?
func orders_enabled() -> bool:
	return bool(_rec.get("orders", true))


# ------------------------------------------------------------------ Estrema

## Regole della morte permanente ({} = la morte è quella normale, docs/05 §7).
func permadeath() -> Dictionary:
	var pd: Variant = _rec.get("permadeath", {})
	return pd if pd is Dictionary else {}


func has_permadeath() -> bool:
	return not permadeath().is_empty()


## Offline l'Eroe si ferma PRIMA del rischio di morte invece di morire ad assenza lunga (scelta conservativa, OPEN_QUESTIONS M-2).
func offline_stops_before_death() -> bool:
	return bool(permadeath().get("offline_stops_before_death", false))


# ------------------------------------------------------------------ cosmetici dedicati

func title_id() -> String:
	return str(_rec.get("title", "") if _rec.get("title") != null else "")


## Secondo titolo, alla prima Stella nella modalità.
func star_title_id() -> String:
	return str(_rec.get("star_title", "") if _rec.get("star_title") != null else "")


func frame_id() -> String:
	return str(_rec.get("frame", "") if _rec.get("frame") != null else "")
