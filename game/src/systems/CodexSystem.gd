class_name CodexSystem
extends GameSystem
## Registro del Compendio (docs/15 §2, UI-A G16 e G32): oggetti mai ottenuti, drop già visti per ogni mostro, contatori
## a vita e cosmetici del profilo (Stendardo ed Emblema scelti). Offline, nessuna rete; non dà alcun bonus.
##
## Stato `codex`:
##   seen        {def_id: quanti ne sono arrivati in tutto}      (anche gli oggetti poi venduti o consumati)
##   mon_drops   {monster_id: {def_id: quanti}}                  (drop dai mostri, per le caselle della tabella)
##   offline_s   secondi di progresso offline accumulati a vita
##   banner / emblem   cosmetico del profilo scelto (id oggetto) o ""
## Un salvataggio vecchio parte con ciò che ha già nel Deposito (backfill) e dalle uccisioni registrate in `combat.kills`.

const NOT_COLLECTED: PackedStringArray = ["currency", "quest", "misc"]
const BANNER_SUBS: PackedStringArray = ["banner", "event"]
const EMBLEM_SUBS: PackedStringArray = ["emblem"]

var _ids_cache: Array = []


func _init() -> void:
	id = "codex"
	state_key = "codex"


func default_state() -> Variant:
	return _fresh()


static func _fresh() -> Dictionary:
	return {"seen": {}, "mon_drops": {}, "offline_s": 0.0, "banner": "", "emblem": ""}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["seen.*", "mon_drops.*.*"])


func setup() -> void:
	var ev: Object = ctx.events
	ev.item_gained.connect(_cb_item)
	ev.monster_killed.connect(_cb_kill)
	ev.monsters_killed_batch.connect(_cb_batch)
	ev.offline_progress.connect(_cb_offline)


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	_backfill()


func has_tick() -> bool:
	return false


func simulate_offline(_seconds: float) -> Dictionary:
	return {}


# ------------------------------------------------------------------ registrazione

func _backfill() -> void:
	var bank := ctx.get_system("bank")
	if bank == null or not (bank.state is Dictionary):
		return
	for def_id in bank.state.get("stacks", {}):
		if not state.seen.has(def_id):
			state.seen[def_id] = int(bank.state.stacks[def_id])
	for inst in bank.state.get("instances", []):
		var d := str(inst.get("def", ""))
		if not d.is_empty() and not state.seen.has(d):
			state.seen[d] = 1


func _cb_item(def_id: String, qty: int, _source: String) -> void:
	if state != null and qty > 0:
		state.seen[def_id] = int(state.seen.get(def_id, 0)) + qty


func _cb_kill(monster_id: String, drops: Array) -> void:
	_record_drops(monster_id, drops)


func _cb_batch(monster_id: String, _count: int, drops: Array) -> void:
	_record_drops(monster_id, drops)


func _record_drops(monster_id: String, drops: Array) -> void:
	if state == null or drops.is_empty():
		return
	if not state.mon_drops.has(monster_id):
		state.mon_drops[monster_id] = {}
	var md: Dictionary = state.mon_drops[monster_id]
	for d in drops:
		var i := str(d.get("id", ""))
		if not i.is_empty():
			md[i] = int(md.get(i, 0)) + maxi(1, int(d.get("qty", 1)))


func _cb_offline(seconds: float, _report: Dictionary) -> void:
	if state != null:
		state.offline_s = float(state.offline_s) + seconds


# ------------------------------------------------------------------ oggetti

## Id degli oggetti da collezionare (tutti tranne valute, oggetti-missione e vari), ordinati per categoria, tier e id.
func collectible_ids() -> Array:
	if _ids_cache.is_empty():
		var rows: Array = []
		for k in ctx.data.all_items():
			var d: Dictionary = ctx.data.item(str(k))
			if not NOT_COLLECTED.has(str(d.get("category", ""))):
				rows.append([str(d.get("category", "")), int(d.get("tier", 0)), str(k)])
		rows.sort()
		for r in rows:
			_ids_cache.append(r[2])
	return _ids_cache


func categories() -> Array:
	var out: Array = []
	for i in collectible_ids():
		var c := str(ctx.data.item(str(i)).get("category", ""))
		if not out.has(c):
			out.append(c)
	return out


func item_seen(def_id: String) -> bool:
	return int(state.seen.get(def_id, 0)) > 0


func item_count_seen(def_id: String) -> int:
	return int(state.seen.get(def_id, 0))


## {"have", "total"} sugli oggetti da collezionare, tutti o di una categoria.
func item_progress(category: String = "") -> Dictionary:
	var have := 0
	var total := 0
	for i in collectible_ids():
		if not category.is_empty() and str(ctx.data.item(str(i)).get("category", "")) != category:
			continue
		total += 1
		if item_seen(str(i)):
			have += 1
	return {"have": have, "total": total}


func unique_ids() -> Array:
	var out: Array = []
	for i in collectible_ids():
		if bool(ctx.data.item(str(i)).get("unique", false)):
			out.append(i)
	return out


func unique_progress() -> Dictionary:
	var have := 0
	var ids := unique_ids()
	for i in ids:
		if item_seen(str(i)):
			have += 1
	return {"have": have, "total": ids.size()}


# ------------------------------------------------------------------ mostri

func kills_of(monster_id: String) -> int:
	var cb := ctx.get_system("combat")
	if cb == null or not (cb.state is Dictionary):
		return 0
	return int((cb.state.get("kills", {}) as Dictionary).get(monster_id, 0))


## Mostri del gioco con almeno una casella di drop, in ordine di zona e livello.
func monster_ids() -> Array:
	var rows: Array = []
	for m in ctx.data.table("monsters"):
		rows.append([int(m.get("level", 0)), str(m.id)])
	rows.sort()
	var out: Array = []
	for r in rows:
		out.append(r[1])
	return out


## Oggetti che la tabella di drop di un mostro può dare (sempre + voci con probabilità, famigli esclusi), senza doppioni.
func drop_slots(monster_id: String) -> Array:
	var m: Dictionary = ctx.data.get_def("monsters", monster_id)
	var t: Dictionary = ctx.data.get_def("drop_tables", str(m.get("drop_table", "")))
	var out: Array = []
	for it in t.get("always", []):
		var i := str(it.item) if it is Dictionary else str(it)
		if ctx.data.has_item(i) and not out.has(i):
			out.append(i)
	for e in t.get("entries", []):
		if bool(e.get("pet", false)) or not e.has("item"):
			continue
		var i2 := str(e.item)
		if ctx.data.has_item(i2) and not out.has(i2):
			out.append(i2)
	for u in m.get("unique_drops", []):
		if ctx.data.has_item(str(u)) and not out.has(str(u)):
			out.append(str(u))
	return out


func drop_got(monster_id: String, def_id: String) -> int:
	return int((state.mon_drops.get(monster_id, {}) as Dictionary).get(def_id, 0))


## {"have", "total"} caselle dei drop di un mostro.
func monster_drop_progress(monster_id: String) -> Dictionary:
	var slots := drop_slots(monster_id)
	var have := 0
	for i in slots:
		if drop_got(monster_id, str(i)) > 0:
			have += 1
	return {"have": have, "total": slots.size()}


## Mostri incontrati (almeno un'uccisione) su tutti.
func monster_progress() -> Dictionary:
	var have := 0
	var ids := monster_ids()
	for m in ids:
		if kills_of(str(m)) > 0:
			have += 1
	return {"have": have, "total": ids.size()}


# ------------------------------------------------------------------ percentuali e contatori

## Percentuale di completamento di una voce (0-100, intera sotto il 100: 99,9% non arrotonda a 100).
static func pct(have: int, total: int) -> int:
	if total <= 0:
		return 0
	return mini(100 if have >= total else 99, int(floor(100.0 * float(have) / float(total))))


## Percentuale in testo come nel resto del gioco (1 decimale sotto il 10%, docs/16 §5); non arriva mai a «100%» finché manca qualcosa.
static func pct_text(have: int, total: int) -> String:
	if total <= 0:
		return NumberFormat.fmt_pct(0.0)
	var p := 100.0 * float(have) / float(total)
	if have < total:
		p = minf(p, 99.9)
	return NumberFormat.fmt_pct(p)


## Completamento per sezione e totale: {"items": {have,total}, "monsters": {...}, "uniques": {...}, "pets": {...},
## "total": pct medio pesato per numero di voci}.
func completion() -> Dictionary:
	var items := item_progress()
	var mons := monster_progress()
	var uniq := unique_progress()
	var pets := {"have": (ctx.state.get("pets", []) as Array).size(), "total": ctx.data.table("pets").size()}
	var have := int(items.have) + int(mons.have) + int(pets.have)
	var total := int(items.total) + int(mons.total) + int(pets.total)
	return {"items": items, "monsters": mons, "uniques": uniq, "pets": pets, "have": have, "total": total, "pct": pct(have, total),
		"pct_text": pct_text(have, total)}


## Contatori a vita (docs/15 §2).
func lifetime() -> Dictionary:
	var st: Dictionary = ctx.state.get("stats", {})
	var comp := ctx.get_system("compendium") as CompendiumSystem
	var acts := 0
	if comp != null:
		for k in comp.state.counters:
			if str(k).begins_with("act:"):
				acts += int(comp.state.counters[k])
	var acts2 := 0
	for v in (st.get("actions", {}) as Dictionary).values():
		acts2 += int(v)
	return {
		"kills": int(st.get("kills", 0)),
		"actions": maxi(acts, acts2),
		"crates": int(ctx.state.get("crates", {}).get("opened", 0)),
		"stars": (comp.counter("rarity:relic") + (ctx.state.get("pets", []) as Array).size()) if comp != null else 0,
		"gold": int(st.get("gold_earned", 0)),
		"playtime_s": float(st.get("playtime_s", 0.0)),
		"offline_s": float(state.offline_s),
	}


# ------------------------------------------------------------------ Stendardi ed Emblemi (G32)

## Cosmetici di profilo ottenuti di un tipo ("banner" o "emblem"): id oggetto, nell'ordine dei dati.
func owned_cosmetics(kind: String) -> Array:
	var subs: PackedStringArray = BANNER_SUBS if kind == "banner" else EMBLEM_SUBS
	var out: Array = []
	for i in ctx.data.items_by_category("cosmetic"):
		if subs.has(str(i.get("subcategory", ""))) and item_seen(str(i.id)):
			out.append(str(i.id))
	return out


func all_cosmetics(kind: String) -> Array:
	var subs: PackedStringArray = BANNER_SUBS if kind == "banner" else EMBLEM_SUBS
	var out: Array = []
	for i in ctx.data.items_by_category("cosmetic"):
		if subs.has(str(i.get("subcategory", ""))):
			out.append(str(i.id))
	return out


func selected(kind: String) -> String:
	return str(state.banner if kind == "banner" else state.emblem)


## Sceglie lo Stendardo o l'Emblema ("" = nessuno). false se non è stato ottenuto o non è del tipo giusto.
func select(kind: String, def_id: String) -> bool:
	if kind != "banner" and kind != "emblem":
		return false
	if not def_id.is_empty() and not owned_cosmetics(kind).has(def_id):
		return false
	state[kind] = def_id
	return true
