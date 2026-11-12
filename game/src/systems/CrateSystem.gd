class_name CrateSystem
extends GameSystem
## Casse, Finiture, Reliquie, Guardaroba e collezioni (docs/09, regola 5 di CLAUDE.md, docs/24).
##
## REGOLE ETICHE (non negoziabili): il risultato si estrae TUTTO dentro open(), prima di qualunque animazione;
## le probabilità mostrate (odds()) sono le stesse numeri usati per l'estrazione (rarity_weights());
## i riempitivi del rullo sono estratti con le probabilità reali; nessuna "quasi-vincita" costruita.
##
## Ordine dei numeri casuali (flusso "crates") per ogni apertura, fissato per il determinismo:
##   rarità → oggetto → condizione → float → Annalista → motivo → fase → punto d'arresto → 59 riempitivi.
##
## Stato (GameState.data.crates):
##   pity {famiglia: aperture senza ★} · opened · found {rarità: n}
##   collections {id_collezione: {def_id: {n, best, ann}}}   (Album: miglior float mai trovato per oggetto)
##   wardrobe {slot: uid} · reliquary [uid] · relic_slots · ann {uid: azioni/uccisioni contate}
##   stats {fused, sold, contracts, golden, polished, engraved, renamed, bought}   (contatori, solo per la UI)
##   challenge {week, score, max_tier, rivals {id: punti finali}, wins, best_place, pending {week, place, score},
##              last {week, place, score}}   (Sfida dei Collezionisti, creato alla prima sincronizzazione)
##
## Istanze (nel Deposito, via bank.add_instance): {def_id, kind: skin|relic|cosmetic, rarity, crate, condition,
## float, annalist, seed, phase, polish, locked}. I famigli ★ del pool non sono istanze: emettono pet_found.

const RARITIES: PackedStringArray = ["rare", "epic", "legendary", "mythic", "relic"]
const WARDROBE_PREFIX := "wardrobe:"
const RELIC_PREFIX := "relic:"
const COLLECTION_PREFIX := "collection:"
const GOLDEN_PREFIX := "collection_gold:"
const GROUP_ORDER: PackedStringArray = ["combat", "tool", "workshop", "merchant", "rogue", "bounty"]

var _contents_cache: Dictionary = {}
var _slots_cache: Array = []
var _ann_equipped: Array = []           # [[slot, uid, group]] delle finiture Annaliste equipaggiate


func has_tick() -> bool:
	return false


func _init() -> void:
	id = "crates"
	state_key = "crates"


func default_state() -> Variant:
	return _complete({})


func setup() -> void:
	if ctx.events != null:
		ctx.events.crate_found.connect(_on_crate_found)
		ctx.events.action_completed.connect(_on_action_completed)
		ctx.events.action_batch_completed.connect(_on_action_batch)
		ctx.events.monster_killed.connect(_on_monster_killed)
		ctx.events.monsters_killed_batch.connect(_on_monsters_killed_batch)
		ctx.events.important_event.connect(_on_important_event)


func from_state(section: Variant) -> void:
	state = _complete(section if section is Dictionary else {})
	_rebuild_all_modifiers()


func int_paths() -> PackedStringArray:
	return PackedStringArray(["pity.*", "opened", "found.*", "relic_slots", "ann.*",
		"collections.*.*.n", "collections.*.*.ann", "stats.*", "draw_n.*", "challenge.week", "challenge.score", "challenge.max_tier",
		"challenge.wins", "challenge.best_place", "challenge.rivals.*", "challenge.pending.*", "challenge.last.*"])


static func _complete(s: Dictionary) -> Dictionary:
	var base := {"pity": {}, "opened": 0, "found": {}, "collections": {}, "wardrobe": {},
		"reliquary": [], "relic_slots": 1, "ann": {}, "stats": {}, "challenge": {}, "retired": {},
		"draw_seed": "", "draw_n": {}}
	for k in base:
		if not s.has(k) or typeof(s[k]) != typeof(base[k]):
			s[k] = base[k]
	return s


# ------------------------------------------------------------------ dati

func rules() -> Dictionary:
	return ctx.data.rules("crate_rules")


func is_crate(crate_id: String) -> bool:
	return ctx.data.item(crate_id).has("crate")


func crate_def(crate_id: String) -> Dictionary:
	var c: Variant = ctx.data.item(crate_id).get("crate", {})
	return c if c is Dictionary else {}          # F8: le Finiture hanno `crate` = id della cassa (stringa)


## rarità -> [def_id] (finiture dalla rarità dell'oggetto; ★ = relic_pool, famigli compresi).
func contents(crate_id: String) -> Dictionary:
	if _contents_cache.has(crate_id):
		return _contents_cache[crate_id]
	var out := {}
	for r in RARITIES:
		out[r] = []
	var cr := crate_def(crate_id)
	for sid in cr.get("skins", []):
		var rar := str(ctx.data.item(sid).get("rarity", ""))
		if out.has(rar):
			out[rar].append(sid)
	out["relic"] = Array(cr.get("relic_pool", [])).duplicate()
	_contents_cache[crate_id] = out
	return out


func rarity_info(rarity: String) -> Dictionary:
	for r in rules().rarities:
		if r.id == rarity:
			return r
	return {}


func condition_info(cond_id: String) -> Dictionary:
	for c in rules().conditions:
		if c.id == cond_id:
			return c
	return {}


# ------------------------------------------------------------------ pity e probabilità

func _pity_cfg() -> Dictionary:
	return Formulas.k().crates.pity


## Aperture senza ★ dopo cui la pity morbida comincia (ridotta dal nodo "Destino Paziente").
func soft_start() -> int:
	var base := int(_pity_cfg().soft_start)
	return maxi(0, base - int(ctx.modifiers.total_add_capped("pity_soft_start_reduction")))


## Probabilità (0..1) che la prossima apertura sia ★ dopo `since` aperture senza ★ (stessa formula di
## Formulas.relic_pity_stats; alla `hard`-esima è garantita).
static func relic_chance(base: float, since: int, soft: int) -> float:
	var cfg: Dictionary = Formulas.k().crates.pity
	if since + 1 >= int(cfg.hard):
		return 1.0
	if since >= soft:
		return minf(1.0, base + float(cfg.soft_step) * float(since - soft + 1))
	return base


## [aperture medie tra due ★, probabilità effettiva della ★] con pity morbida che parte da `soft`.
static func pity_stats(base: float, soft: int) -> Array:
	var hard := int(Formulas.k().crates.pity.hard)
	var surv := 1.0
	var mean := 0.0
	for since in hard:
		mean += surv
		surv *= (1.0 - relic_chance(base, since, soft))
	return [mean, 1.0 / mean]


## Pesi di rarità NOMINALI normalizzati (rarità senza contenuto escluse): {rarità: 0..1}. Sono i numeri mostrati.
func nominal_fractions(crate_id: String) -> Dictionary:
	var odds_cfg: Dictionary = crate_def(crate_id).get("odds", {})
	var cont := contents(crate_id)
	var tot := 0.0
	for r in RARITIES:
		if not cont[r].is_empty():
			tot += float(odds_cfg.get(r, 0.0))
	var out := {}
	for r in RARITIES:
		out[r] = float(odds_cfg.get(r, 0.0)) / tot if (tot > 0.0 and not cont[r].is_empty()) else 0.0
	return out


## Pesi usati DAVVERO dalla prossima apertura (pity inclusa): {rarità: 0..1}. odds() mostra questi stessi numeri.
func rarity_weights(crate_id: String, since: int = -1) -> Dictionary:
	var nom := nominal_fractions(crate_id)
	var fam := pity_family(crate_id)
	if fam.is_empty() or nom.relic <= 0.0:
		return nom
	if since < 0:
		since = int(state.pity.get(fam, 0))
	var p_relic := relic_chance(nom.relic, since, soft_start())
	var scale: float = (1.0 - p_relic) / (1.0 - nom.relic) if nom.relic < 1.0 else 0.0
	var out := {}
	for r in RARITIES:
		out[r] = p_relic if r == "relic" else nom[r] * scale
	return out


func pity_family(crate_id: String) -> String:
	var f: Variant = crate_def(crate_id).get("pity_family")
	return "" if f == null else str(f)


## Dati della pity per la schermata (nominale ed effettiva, contatore, soglie).
func pity_info(crate_id: String) -> Dictionary:
	var fam := pity_family(crate_id)
	var nom := nominal_fractions(crate_id)
	if fam.is_empty() or nom.relic <= 0.0:
		return {"family": "", "count": 0, "nominal_relic_pct": nom.relic * 100.0, "effective_relic_pct": nom.relic * 100.0,
			"mean_openings": 0.0, "soft_start": 0, "hard": 0, "next_relic_pct": nom.relic * 100.0}
	var soft := soft_start()
	var st := pity_stats(nom.relic, soft)
	var cnt := int(state.pity.get(fam, 0))
	return {"family": fam, "count": cnt, "nominal_relic_pct": nom.relic * 100.0,
		"effective_relic_pct": 100.0 * float(st[1]), "mean_openings": float(st[0]), "soft_start": soft,
		"hard": int(_pity_cfg().hard), "next_relic_pct": 100.0 * relic_chance(nom.relic, cnt, soft)}


## Probabilità da mostrare (contratto "crates"): una voce per rarità con contenuto, in ordine di rarità.
## {rarity, pct (nominale), current_pct (prossima apertura, pity inclusa), effective_pct (lungo periodo),
##  color, symbol, bonus_pct, count, items: [{def_id, pct (sulla cassa), pct_in_rarity, condition_odds,
##  float_min, float_max, annalist_pct}]}
func odds(crate_id: String) -> Array:
	var out: Array = []
	if not is_crate(crate_id):
		return out
	var nom := nominal_fractions(crate_id)
	var cur := rarity_weights(crate_id)
	var cont := contents(crate_id)
	var eff := _effective_fractions(crate_id, nom)
	var ann_pct := annalist_chance() * 100.0
	for r in RARITIES:
		if cont[r].is_empty():
			continue
		var ri := rarity_info(r)
		var items: Array = []
		var n: int = cont[r].size()
		for did in cont[r]:
			var d: Dictionary = ctx.data.item(did)
			var sk: Dictionary = d.get("skin", d.get("relic", {}))
			items.append({"def_id": did, "pct": nom[r] * 100.0 / n, "pct_in_rarity": 100.0 / n,
				"condition_odds": sk.get("condition_odds", {}), "float_min": float(sk.get("float_min", 0.0)),
				"float_max": float(sk.get("float_max", 1.0)),
				"annalist_pct": ann_pct if d.get("category", "") == "skin" else 0.0})
		out.append({"rarity": r, "pct": nom[r] * 100.0, "current_pct": cur[r] * 100.0, "effective_pct": eff[r] * 100.0,
			"color": str(ri.get("color", "#FFFFFF")), "symbol": str(ri.get("symbol", "")),
			"bonus_pct": float(ri.get("skin_bonus_pct", 0.0)), "count": n, "items": items})
	return out


func _effective_fractions(crate_id: String, nom: Dictionary) -> Dictionary:
	var fam := pity_family(crate_id)
	if fam.is_empty() or nom.relic <= 0.0:
		return nom
	var st := pity_stats(nom.relic, soft_start())
	var eff_relic: float = st[1]
	var k: float = (1.0 - eff_relic) / (1.0 - nom.relic)
	var out := {}
	for r in RARITIES:
		out[r] = eff_relic if r == "relic" else nom[r] * k
	return out


func annalist_chance() -> float:
	return float(rules().annalist.chance) + ctx.modifiers.total_add_capped("annalist_chance_abs_pct") / 100.0


# ------------------------------------------------------------------ casse in ingresso

func _bank() -> GameSystem:
	return ctx.get_system("bank")


## Aggiunge la cassa al Deposito (come oggetto impilabile).
func grant_crate(crate_id: String, qty: int = 1) -> void:
	if qty <= 0 or not is_crate(crate_id):
		return
	var b := _bank()
	if b != null:
		b.add(crate_id, qty, "crate")


func _on_crate_found(crate_id: String, _source: String) -> void:
	if enabled:           # a partita chiusa (Game.stop_game) i sistemi sono spenti e non ascoltano
		grant_crate(crate_id, 1)


## Quante casse di questo tipo si possono aprire ora (casse e chiave/costo disponibili).
func openable(crate_id: String) -> int:
	var b := _bank()
	if b == null or not is_crate(crate_id):
		return 0
	var n: int = b.count(crate_id)
	var cr := crate_def(crate_id)
	if cr.get("key") != null:
		n = mini(n, b.count(str(cr.key)))
	if cr.has("open_cost"):
		n = mini(n, int(floor(float(b.count(str(cr.open_cost.item))) / float(maxi(1, int(cr.open_cost.qty))))))
	return n


## Quante casse si possono aprire ORA. Dal resoconto 117 il Deposito pieno NON limita più l'apertura: la Finitura che non
## trova posto aspetta nel Carro di Ritiro (nessun premio perso, si scarica da sola). Resta per compatibilità con la UI.
func openable_now(crate_id: String) -> int:
	return openable(crate_id)


## Sempre false (il Deposito pieno non blocca più l'apertura); resta per compatibilità con la UI.
func blocked_by_space(_crate_id: String) -> bool:
	return false


# ------------------------------------------------------------------ estrazione indicizzata (Q82-1, anti save-scum)
# L'esito della N-esima apertura di una cassa e' una FUNZIONE PURA di (seme di estrazione del salvataggio, id cassa, N):
# non consuma il flusso `crates` condiviso, quindi nessuna azione a costo zero (aprire altre casse, rullo si/no, ricaricare,
# contratti) puo' cambiarlo. Il contatore N sta nello stato e viene fatto avanzare PRIMA dell'estrazione; il rullo ha un
# generatore a parte (riempitivi con le probabilita' reali, mai il risultato). Ricaricare un salvataggio precedente
# all'apertura riporta anche il contatore: stesso esito, nessun vantaggio. La pity dipende solo dal contatore di
# famiglia, che avanza soltanto aprendo (cioe' pagando chiavi). Specifica: docs/09 §6, docs/24.

const CONTRACT_DRAW_KEY := "@contract"


## Seme di estrazione del salvataggio (stringa uint64 nello stato). Se manca (partita nuova, o salvataggio ripristinato
## senza), si deriva UNA volta dal seme principale e si scrive nello stato: da li' in poi non cambia piu'.
func draw_seed() -> int:
	var cur := str(state.get("draw_seed", ""))
	if RngStreams.is_u64_string(cur) and cur != "0":
		return RngStreams.parse_u64(cur)
	var sd := RngStreams.derive_seed(ctx.rng.master_seed, "crate-draw-seed", 0)
	state["draw_seed"] = RngStreams.u64_to_string(sd)
	return sd


## Quante estrazioni sono gia' state fatte per questa chiave (cassa, o `@contract`).
func draw_count(key: String) -> int:
	return int((state.draw_n as Dictionary).get(key, 0))


## Generatore dell'estrazione successiva per `key`: avanza e PERSISTE il contatore, poi deriva dal vecchio valore.
func _draw_rng(key: String) -> RandomNumberGenerator:
	var n := draw_count(key)
	(state.draw_n as Dictionary)[key] = n + 1
	return RngStreams.derived_rng(draw_seed(), "draw:" + key, n)


## Generatore del rullo dell'ultima apertura di `crate_id` (flusso a parte: non puo' influire sull'esito).
func _reel_rng(crate_id: String) -> RandomNumberGenerator:
	return RngStreams.derived_rng(draw_seed(), "reel:" + crate_id, maxi(0, draw_count(crate_id) - 1))


# ------------------------------------------------------------------ apertura

## Apre `qty` casse. I risultati sono GIÀ estratti e applicati (Deposito, pity, album) quando la funzione
## ritorna: la UI li mostra soltanto. Si ferma se finiscono casse o chiavi. A Deposito pieno la Finitura estratta va nel
## Carro di Ritiro (risultato["carro"] = true), mai persa e mai un motivo per non aprire (resoconto 117). `with_reel` = false salta la
## costruzione del rullo (test di massa). Ogni risultato:
## {crate_id, def_id, kind, rarity, uid, instance, is_new, pity_before, relic_p, reel, reel_index, stop_frac}
func open(crate_id: String, qty: int = 1, with_reel: bool = true) -> Array:
	var out: Array = []
	for i in qty:
		var r := _open_one(crate_id, with_reel)
		if r.is_empty():
			break
		out.append(r)
	return out


func _open_one(crate_id: String, with_reel: bool) -> Dictionary:
	if openable(crate_id) < 1:
		return {}
	var b := _bank()
	# QA82 R1 -> resoconto 117: con il Deposito pieno la Finitura estratta non si perde e l'apertura non si rifiuta: la
	# Finitura entra nel Carro di Ritiro (bank.add_instance) e si scarica da sola quando si libera un posto.
	var cr := crate_def(crate_id)
	b.remove(crate_id, 1)
	if cr.get("key") != null:
		b.remove(str(cr.key), 1)
	if cr.has("open_cost"):
		b.remove(str(cr.open_cost.item), int(cr.open_cost.qty))

	var rng := _draw_rng(crate_id)          # Q82-1: generatore indicizzato (seme, cassa, N-esima apertura)
	var fam := pity_family(crate_id)
	var since := int(state.pity.get(fam, 0)) if not fam.is_empty() else 0
	var w := rarity_weights(crate_id, since)
	var wl: Array = []
	for r in RARITIES:
		wl.append(w[r])
	var rarity: String = RARITIES[maxi(0, RngStreams.weighted_pick(rng, wl))]
	if not fam.is_empty():
		state.pity[fam] = 0 if rarity == "relic" else since + 1
	var cont := contents(crate_id)
	var pool: Array = cont[rarity]
	var def_id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var d: Dictionary = ctx.data.item(def_id)
	var kind := "pet"
	if not d.is_empty():
		kind = str(d.category)            # skin | relic | cosmetic
	var inst: Dictionary = {"def_id": def_id, "kind": kind, "rarity": rarity, "crate": crate_id}
	if kind == "skin" or kind == "relic":
		var sk: Dictionary = d.get("skin", d.get("relic", {}))
		_roll_condition(inst, sk, rng)
		inst["annalist"] = kind == "skin" and rng.randf() < annalist_chance()
		inst["seed"] = rng.randi_range(0, int(sk.get("pattern_seeds", 1000)) - 1)
		inst["phase"] = _roll_phase(sk.get("phases", []), rng) if kind == "relic" else ""
		inst["polish"] = 0
		inst["locked"] = false
	elif kind == "cosmetic":
		inst["seed"] = 0
	var stop_frac := 0.05 + 0.9 * rng.randf()

	var uid := ""
	var in_carro := false
	if kind == "pet":
		ctx.events.pet_found.emit(def_id)
	elif b != null:
		uid = str(b.add_instance(inst))
		if uid == BankSystem.OVERFLOW_UID:            # Deposito pieno: il premio aspetta nel Carro (o è stato venduto oltre il tetto)
			uid = ""
			in_carro = true
		inst["uid"] = uid
	var is_new := _record_find(crate_id, def_id, inst)
	state.opened = int(state.opened) + 1
	state.found[rarity] = int(state.found.get(rarity, 0)) + 1
	var result := {"crate_id": crate_id, "def_id": def_id, "kind": kind, "rarity": rarity, "uid": uid, "carro": in_carro,
		"instance": inst, "is_new": is_new, "pity_before": since, "relic_p": float(w.relic),
		"reel": [], "reel_index": int(rules().reel.winner_index), "stop_frac": stop_frac}
	if with_reel:
		result["reel"] = build_reel(crate_id, def_id, rarity, _reel_rng(crate_id))
	_challenge_on_open(crate_id, rarity)
	ctx.events.crate_opened.emit(result)
	if rarity in ["legendary", "mythic", "relic"]:
		ctx.events.important_event.emit("crate")      # R-SAV-3: un'apertura che conta si salva subito
	return result


func _roll_condition(inst: Dictionary, sk: Dictionary, rng: RandomNumberGenerator) -> void:
	var co: Dictionary = sk.get("condition_odds", {})
	var ids: Array = []
	var ws: Array = []
	for c in rules().conditions:
		if co.has(c.id):
			ids.append(c.id)
			ws.append(float(co[c.id]))
	var cid: String = ids[maxi(0, RngStreams.weighted_pick(rng, ws))]
	var ci := condition_info(cid)
	var lo := maxf(float(ci.float_min), float(sk.get("float_min", 0.0)))
	var hi := minf(float(ci.float_max), float(sk.get("float_max", 1.0)))
	inst["condition"] = cid
	inst["float"] = rng.randf_range(lo, maxf(lo, hi))


func _roll_phase(allowed: Array, rng: RandomNumberGenerator) -> String:
	var ids: Array = []
	var ws: Array = []
	for p in rules().relic_phases:
		if allowed.is_empty() or allowed.has(p.id):
			ids.append(p.id)
			ws.append(float(p.weight))
	return str(ids[maxi(0, RngStreams.weighted_pick(rng, ws))])


## Rullo: 60 tessere, vincitore all'indice 52, le altre 59 estratte con le probabilità mostrate
## (nominali) della cassa. Nessuna quasi-vincita costruita. [{d: def_id, r: rarity}]
func build_reel(crate_id: String, winner_def: String, winner_rarity: String, reel_rng: RandomNumberGenerator = null) -> Array:
	if not is_crate(crate_id):
		return []                     # F8: cassa sconosciuta
	var rr: Dictionary = rules().reel
	var n := int(rr.length_items)
	var win := int(rr.winner_index)
	var nom := nominal_fractions(crate_id)
	# riempitivi con le probabilità EFFETTIVE (pity inclusa): docs/24 R-LEG-5 «reali» (QA3 §3: prima le nominali)
	if not pity_family(crate_id).is_empty() and float(nom.relic) > 0.0 and float(nom.relic) < 1.0:
		var eff := float(pity_stats(float(nom.relic), soft_start())[1])
		var k := (1.0 - eff) / (1.0 - float(nom.relic))
		for r in RARITIES:
			nom[r] = eff if r == "relic" else float(nom[r]) * k
	var wl: Array = []
	for r in RARITIES:
		wl.append(nom[r])
	var cont := contents(crate_id)
	var rr_rng := reel_rng if reel_rng != null else _draw_rng("@reel:" + crate_id)    # chiamata diretta (UI, test): un rullo nuovo a ogni chiamata
	var tiles: Array = []
	for i in n:
		if i == win:
			tiles.append({"d": winner_def, "r": winner_rarity})
			continue
		var rar: String = RARITIES[maxi(0, RngStreams.weighted_pick(rr_rng, wl))]
		var pool: Array = cont[rar]
		tiles.append({"d": pool[rr_rng.randi_range(0, pool.size() - 1)], "r": rar})
	return tiles


# ------------------------------------------------------------------ album e collezioni

func _record_find(crate_id: String, def_id: String, inst: Dictionary) -> bool:
	var cid := collection_of(crate_id)
	if cid.is_empty():
		return false
	var col: Dictionary = state.collections.get(cid, {})
	state.collections[cid] = col
	var is_new := not col.has(def_id)
	var e: Dictionary = col.get(def_id, {"n": 0, "best": 1.0, "ann": 0})
	e["n"] = int(e.n) + 1
	if inst.has("float"):
		e["best"] = minf(float(e.best), float(inst.float))
	if bool(inst.get("annalist", false)):
		e["ann"] = int(e.ann) + 1
	col[def_id] = e
	if is_new:
		_refresh_collection(cid)
	return is_new


## Collezione per id (collections.json) della cassa, "" se nessuna.
func collection_of(crate_id: String) -> String:
	var c: Variant = crate_def(crate_id).get("collection")
	return "" if c == null else str(c)


## {owned, total, relics_owned, relics_total, complete, golden, entries: {def_id: {n,best,ann}}}
func collection_progress(collection_id: String) -> Dictionary:
	var cdef: Dictionary = ctx.data.get_def("collections", collection_id)
	var cr := crate_def(str(cdef.get("crate", "")))
	var col: Dictionary = state.collections.get(collection_id, {})
	var owned := 0
	var total := Array(cr.get("skins", [])).size()
	for sid in cr.get("skins", []):
		if col.has(sid):
			owned += 1
	var ro := 0
	var rt := Array(cr.get("relic_pool", [])).size()
	for rid in cr.get("relic_pool", []):
		if col.has(rid):
			ro += 1
	var complete := total > 0 and owned == total
	return {"owned": owned, "total": total, "relics_owned": ro, "relics_total": rt, "complete": complete,
		"golden": complete and rt > 0 and ro == rt, "entries": col}


func collection_ids() -> Array:
	var out: Array = []
	for c in ctx.data.table("collections"):
		out.append(str(c.id))
	return out


func _refresh_collection(cid: String) -> void:
	var cdef: Dictionary = ctx.data.get_def("collections", cid)
	if cdef.is_empty():
		return
	var p := collection_progress(cid)
	ctx.modifiers.set_source(COLLECTION_PREFIX + cid, cdef.complete_bonus.modifiers if p.complete else [])
	var g: Array = cdef.golden_bonus.modifiers if p.golden else []
	ctx.modifiers.set_source(GOLDEN_PREFIX + cid, g)


# ------------------------------------------------------------------ guardaroba

## Slot del Guardaroba in ordine di gruppo: [{slot, group}] (29, dai dati delle finiture).
func wardrobe_slots() -> Array:
	if not _slots_cache.is_empty():
		return _slots_cache
	var seen := {}
	for it in ctx.data.items_by_category("skin"):
		var sk: Dictionary = it.skin
		if not seen.has(sk.slot):
			seen[sk.slot] = {"slot": str(sk.slot), "group": str(sk.slot_group)}
	var list: Array = seen.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ga := GROUP_ORDER.find(a.group)
		var gb := GROUP_ORDER.find(b.group)
		return ga < gb if ga != gb else str(a.slot) < str(b.slot))
	_slots_cache = list
	return list


func equipped(slot: String) -> String:
	return str(state.wardrobe.get(slot, ""))


func equip(uid: String) -> bool:
	var inst := _instance(uid)
	if inst.is_empty() or inst.get("kind", "") != "skin":
		return false
	var slot := str(ctx.data.item(str(inst.def_id)).skin.slot)
	for s in state.wardrobe.keys():
		if state.wardrobe[s] == uid:
			unequip(s)
	state.wardrobe[slot] = uid
	_refresh_slot(slot)
	return true


func unequip(slot: String) -> void:
	state.wardrobe.erase(slot)
	_refresh_slot(slot)


## Bonus finale di una finitura = valore del dato × bonus della condizione + punti Annalista (docs/09 §5.5).
## Il valore nei dati include già bonus di rarità × moltiplicatore dello slot.
func skin_modifiers(inst: Dictionary) -> Array:
	var d: Dictionary = ctx.data.item(str(inst.get("def_id", "")))
	if d.is_empty() or not d.has("skin"):
		return []
	var m: Dictionary = d.skin.modifier
	var mult := float(condition_info(str(inst.get("condition", "marked"))).get("bonus_mult", 1.0))
	var v := float(m.value) * mult
	if bool(inst.get("annalist", false)):
		v += annalist_points(int(state.ann.get(str(inst.get("uid", "")), 0)))
	return [{"key": m.key, "value": v, "mode": m.get("mode", "add")}]


func relic_modifiers(inst: Dictionary) -> Array:
	var d: Dictionary = ctx.data.item(str(inst.get("def_id", "")))
	if d.is_empty() or not d.has("relic"):
		return []
	var mult := float(condition_info(str(inst.get("condition", "marked"))).get("bonus_mult", 1.0))
	var out: Array = []
	for m in d.relic.modifiers:
		out.append({"key": m.key, "value": float(m.value) * mult, "mode": m.get("mode", "add")})
	return out


## Punti Annalista maturati con `count` azioni/uccisioni (max +1,0).
func annalist_points(count: int) -> float:
	var a: Dictionary = rules().annalist
	var k := 0
	for ms in a.milestones:
		if count >= int(ms):
			k += 1
	return float(a.bonus_per_milestone_abs) * k


func _instance(uid: String) -> Dictionary:
	var b := _bank()
	return b.get_instance(uid) if (b != null and not uid.is_empty()) else {}


func _refresh_slot(slot: String) -> void:
	var uid := equipped(slot)
	var mods: Array = []
	if not uid.is_empty():
		var inst := _instance(uid)
		if inst.is_empty():
			state.wardrobe.erase(slot)          # la finitura non è più nel Deposito
		else:
			mods = skin_modifiers(inst)
	ctx.modifiers.set_source(WARDROBE_PREFIX + slot, mods)
	_rebuild_ann_list()


func _rebuild_ann_list() -> void:
	_ann_equipped.clear()
	for slot in state.wardrobe:
		var inst := _instance(str(state.wardrobe[slot]))
		if not inst.is_empty() and bool(inst.get("annalist", false)):
			var group := str(ctx.data.item(str(inst.def_id)).skin.slot_group)
			_ann_equipped.append([slot, str(state.wardrobe[slot]), group])


## Annalista: uccisioni per le finiture di combattimento, azioni per tutte le altre.
func _count_annalist(combat: bool) -> void:
	for e in _ann_equipped:
		if (e[2] == "combat") != combat:
			continue
		var uid: String = e[1]
		var old := int(state.ann.get(uid, 0))
		state.ann[uid] = old + 1
		if annalist_points(old + 1) != annalist_points(old):
			_refresh_slot(e[0])


func _on_action_completed(_action_id: String, _outputs: Array) -> void:
	if not _ann_equipped.is_empty():
		_count_annalist(false)


func _on_action_batch(_action_id: String, count: int, _outputs: Array) -> void:
	if not _ann_equipped.is_empty():
		for i in count:
			_count_annalist(false)


func _on_monsters_killed_batch(_monster_id: String, count: int, _drops: Array) -> void:
	if not _ann_equipped.is_empty():
		for i in count:
			_count_annalist(true)


func _on_monster_killed(_monster_id: String, _drops: Array) -> void:
	if not _ann_equipped.is_empty():
		_count_annalist(true)


# Reliquiari (slot: 1; altri dall'Emporio/Costellazioni via add_relic_slot)

func relic_slots() -> int:
	var extra := 0
	var mk := ctx.get_system("market")         # "Secondo Reliquiario" dell'Emporio (effetto relic_slots)
	if mk != null and mk.has_method("shop_effect_total"):
		extra = int(mk.call("shop_effect_total", "relic_slots"))
	return int(state.relic_slots) + extra


func add_relic_slot() -> void:
	state.relic_slots = int(state.relic_slots) + 1


func reliquary() -> Array:
	return state.reliquary


func equip_relic(uid: String) -> bool:
	var inst := _instance(uid)
	if inst.is_empty() or inst.get("kind", "") != "relic" or state.reliquary.has(uid):
		return false
	if state.reliquary.size() >= relic_slots():
		return false
	state.reliquary.append(uid)
	_rebuild_relics()
	return true


func unequip_relic(uid: String) -> void:
	state.reliquary.erase(uid)
	_rebuild_relics()


func _rebuild_relics() -> void:
	ctx.modifiers.clear_prefix(RELIC_PREFIX)
	for uid in state.reliquary.duplicate():
		var inst := _instance(str(uid))
		if inst.is_empty():
			state.reliquary.erase(uid)
			continue
		ctx.modifiers.set_source(RELIC_PREFIX + str(uid), relic_modifiers(inst))


func _rebuild_all_modifiers() -> void:
	for p in [WARDROBE_PREFIX, RELIC_PREFIX, COLLECTION_PREFIX, GOLDEN_PREFIX]:
		ctx.modifiers.clear_prefix(p)
	for slot in state.wardrobe.keys():
		_refresh_slot(slot)
	_rebuild_ann_list()
	_rebuild_relics()
	for cid in collection_ids():
		_refresh_collection(cid)


# ================================================================== CRATES-2: azioni sulle istanze
# Fondi, Vendi, Blocca, Contratti, Affinatura, Banco dei Caveau, Sfida dei Collezionisti (docs/09 §9-§12, docs/24).
# NESSUNA posta in gioco: ogni azione mostra PRIMA l'esito (o tutti gli esiti con la loro probabilità) e non
# esiste alcuna scelta di "rischio" o "moltiplicatore". Nessuno scambio tra giocatori, nessun denaro reale.

const SHARD := "vault_shard"
const TOKEN_TRADEUP := "feature:tradeup"
const TOKEN_GOLDEN := "feature:golden_contract"
const TOKEN_REFINERY := "feature:refinery"
const TOKEN_CHALLENGE := "feature:collectors_challenge"
const INST_KINDS: PackedStringArray = ["skin", "relic", "cosmetic"]


func _has_token(token: String) -> bool:
	return (ctx.state.get("unlocks", []) as Array).has(token)


func tradeup_unlocked() -> bool:
	return _has_token(TOKEN_TRADEUP)


func golden_unlocked() -> bool:
	return _has_token(TOKEN_GOLDEN)


func refinery_unlocked() -> bool:
	return _has_token(TOKEN_REFINERY)


func challenge_unlocked() -> bool:
	return _has_token(TOKEN_CHALLENGE)


func _stat_add(key: String, n: int = 1) -> void:
	state.stats[key] = int(state.stats.get(key, 0)) + n


func shards() -> int:
	var b := _bank()
	return int(b.currency(SHARD)) if b != null else 0


## L'istanza (skin / relic / cosmetic) del Deposito, {} se non esiste.
func instance(uid: String) -> Dictionary:
	var inst := _instance(uid)
	if inst.is_empty() or not INST_KINDS.has(str(inst.get("kind", ""))):
		return {}
	return inst


func is_in_use(uid: String) -> bool:
	if state.wardrobe.values().has(uid) or state.reliquary.has(uid):
		return true
	var b := _bank()
	return b != null and b.has_method("is_in_use") and bool(b.call("is_in_use", uid))


func is_locked(uid: String) -> bool:
	var b := _bank()
	return b != null and b.has_method("is_instance_locked") and bool(b.call("is_instance_locked", uid))


## Blocca/sblocca (un'istanza bloccata non si vende, non si fonde, non entra nei Contratti).
func set_locked(uid: String, locked: bool) -> bool:
	var b := _bank()
	if instance(uid).is_empty() or b == null or not b.has_method("set_instance_locked"):
		return false
	b.call("set_instance_locked", uid, locked)
	return true


## "" = si può consumare (fondere, vendere, mettere in un Contratto), altrimenti il motivo: missing | locked | in_use.
func consume_block(uid: String) -> String:
	if instance(uid).is_empty():
		return "missing"
	if is_locked(uid):
		return "locked"
	if is_in_use(uid):
		return "in_use"
	return ""


func _touch_bank(uid: String) -> void:
	# l'istanza è quella VIVA del Deposito: un blocco «uguale a prima» basta a farne aggiornare la UI (revision)
	var b := _bank()
	if b != null and b.has_method("set_instance_locked") and b.has_method("is_instance_locked"):
		b.call("set_instance_locked", uid, bool(b.call("is_instance_locked", uid)))


func _drop_instance(uid: String) -> bool:
	var b := _bank()
	state.ann.erase(uid)
	if b == null:
		return false
	return bool(b.remove_instance(uid))


func _refresh_equipped(uid: String) -> void:
	for slot in state.wardrobe.keys():
		if state.wardrobe[slot] == uid:
			_refresh_slot(slot)
	if state.reliquary.has(uid):
		_rebuild_relics()


# ------------------------------------------------------------------ Fondi

## Schegge che darebbe fondere questa istanza: dismantle_shards[rarità] × (1 + shards_pct/100), minimo 1.
func fuse_value(uid: String) -> int:
	var inst := instance(uid)
	if inst.is_empty():
		return 0
	var base := int(rules().dismantle_shards.get(str(inst.get("rarity", "rare")), 0))
	var mult := 1.0 + ctx.modifiers.total_add("shards_pct") / 100.0
	# Casse dell'Era: bonus del modello (×(1 + 0,25·(N−1))) sulle Schegge dei pezzi usciti da quella cassa
	mult *= float(crate_def(str(inst.get("crate", ""))).get("bonus_mult", 1.0))
	return maxi(1, roundi(float(base) * mult)) if base > 0 else 0


## Fonde un'istanza in Schegge del Caveau. Ritorna le Schegge ottenute, 0 se non si può (bloccata, in uso…).
func fuse(uid: String) -> int:
	if not consume_block(uid).is_empty():
		return 0
	var n := fuse_value(uid)
	if n <= 0 or not _drop_instance(uid):
		return 0
	_bank().add_currency(SHARD, n)
	_stat_add("fused")
	return n


## Fonde molte istanze (quelle non fondibili sono saltate). Ritorna {n, shards}.
func fuse_many(uids: Array) -> Dictionary:
	var count := 0
	var tot := 0
	for u in uids:
		var got := fuse(str(u))
		if got > 0:
			count += 1
			tot += got
	return {"n": count, "shards": tot}


# ------------------------------------------------------------------ Vendi

func _phase_value_mult(phase: String) -> float:
	for p in rules().relic_phases:
		if p.id == phase:
			return float(p.value_mult)
	return 1.0


func _pattern_value_mult(inst: Dictionary) -> float:
	var d: Dictionary = ctx.data.item(str(inst.get("def_id", "")))
	for sp in d.get("skin", {}).get("special_patterns", []):
		if Array(sp.seeds).has(int(inst.get("seed", -1))):
			return float(sp.value_mult)
	return 1.0


## Moltiplicatore di valore dell'istanza (condizione × Annalista × motivo × fase), docs/09 §13.
func value_mult(inst: Dictionary) -> float:
	var m := float(condition_info(str(inst.get("condition", "marked"))).get("value_mult", 1.0))
	if bool(inst.get("annalist", false)):
		m *= float(rules().annalist.value_mult)
	m *= _pattern_value_mult(inst)
	m *= _phase_value_mult(str(inst.get("phase", "")))
	m *= retired_mult(inst)
	return m


# ------------------------------------------------------------------ casse ritirate (G35, docs/09 §13)
# Quando una nuova Era porta una Cassa dell'Era più recente, le precedenti sono «ritirate»: le finiture uscite da loro
# valgono +retired_crate_drift_pct_per_week % a settimana di gioco dal ritiro (lineare, settimane intere; sapore
# "collezione", nessun valore reale, nessuna posta). `retired` = {id_cassa: tempo di gioco del ritiro}.

## Il ritiro si registra quando si sblocca un'Era (evento "era"), non al caricamento: un salvataggio resta identico a sé
## stesso quando si rilegge; quelli precedenti a G35 ritirano le casse vecchie al prossimo sblocco di Era.
func _on_important_event(reason: String) -> void:
	if reason == "era" and state is Dictionary:
		update_retired()


## Registra come ritirate le Casse dell'Era più vecchie di quella che il Custode consegna ora. Ritorna quante sono nuove.
func update_retired() -> int:
	var tpl: Dictionary = rules().get("era_crate_template", {})
	# dallo stato radice, non da PrestigeSystem: al caricamento questo sistema riceve lo stato prima del Prestigio
	var pst: Variant = ctx.state.get("prestige", {})
	if tpl.is_empty() or not (pst is Dictionary):
		return 0
	var newest := clampi(int((pst as Dictionary).get("era_max", 1)), int(tpl.get("min_era", 2)), int(tpl.get("max_era", 2)))
	var added := 0
	for n in range(int(tpl.get("min_era", 2)), newest):
		var cid := str(tpl.get("id_pattern", "")).replace("{n}", str(n))
		if not state.retired.has(cid) and is_crate(cid):
			state.retired[cid] = challenge_clock()
			added += 1
	return added


## Settimane di gioco intere dal ritiro della cassa da cui è uscita l'istanza (-1 se la cassa non è ritirata).
func retired_weeks(inst: Dictionary) -> int:
	var since: Variant = state.get("retired", {}).get(str(inst.get("crate", "")))
	if since == null:
		return -1
	var week := float(rules().get("market", {}).get("retired_week_days", 7)) * MarketSystem.DAY_S
	return int(floor(maxf(0.0, challenge_clock() - float(since)) / maxf(1.0, week)))


func retired_mult(inst: Dictionary) -> float:
	var w := retired_weeks(inst)
	if w <= 0:
		return 1.0
	return 1.0 + float(rules().get("market", {}).get("retired_crate_drift_pct_per_week", 0.0)) / 100.0 * w


## Oro che si ricaverebbe vendendo ora (0 = non vendibile). Prezzo = valore × moltiplicatori × (tendenza, tassa).
## NIENTE `market_sell_pct`/`gold_gain_pct` sulle Finiture (QA3 E2): il ritorno atteso delle Casse resta 63-73% della chiave.
## Si vende al Mercato di gioco: nessun giocatore, nessun denaro reale.
func sell_price(uid: String) -> int:
	if not consume_block(uid).is_empty():
		return 0
	var inst := instance(uid)
	var def_id := str(inst.get("def_id", ""))
	var d: Dictionary = ctx.data.item(def_id)
	if d.is_empty() or not bool(d.get("tradeable", true)) or float(d.get("value", 0)) <= 0.0:
		return 0
	var mk := ctx.get_system("market")
	var unit: float
	if mk != null and mk.has_method("base_price"):
		unit = float(mk.call("base_price", def_id, false))
	else:
		unit = float(d.value) * (1.0 - float(ctx.data.constants.get("market", {}).get("skin_sell_tax", 0.10)))
	return maxi(1, roundi(unit * value_mult(inst)))


func sell(uid: String) -> int:
	var gold := sell_price(uid)
	if gold <= 0:
		return 0
	var def_id := str(instance(uid).get("def_id", ""))
	if not _drop_instance(uid):
		return 0
	_bank().add_gold(gold)
	_stat_add("sold")
	ctx.events.item_sold.emit(def_id, 1, gold)
	ctx.events.objective_event.emit("sell_market", {"gold": gold})
	return gold


# ------------------------------------------------------------------ condizione da float (Affinatura, Contratti)

## Condizione la cui fascia contiene `f` (le fasce sono contigue: l'ultima include l'estremo).
func condition_for_float(f: float) -> String:
	var last := ""
	for c in rules().conditions:
		last = str(c.id)
		if f < float(c.float_max):
			return last
	return last


func _float_range(def_id: String) -> Vector2:
	var d: Dictionary = ctx.data.item(def_id)
	var sk: Dictionary = d.get("skin", d.get("relic", {}))
	return Vector2(float(sk.get("float_min", 0.0)), float(sk.get("float_max", 1.0)))


func _next_rarity(rarity: String) -> String:
	var i := RARITIES.find(rarity)
	return RARITIES[i + 1] if (i >= 0 and i + 1 < RARITIES.size()) else ""


# ------------------------------------------------------------------ Contratti di Conversione e Contratto Aureo (docs/09 §9)

func contract_inputs(golden: bool = false) -> int:
	return int(rules().golden_contract.inputs) if golden else int(rules().tradeup.inputs)


func contract_unlocked(golden: bool = false) -> bool:
	return golden_unlocked() if golden else tradeup_unlocked()


## Convalida degli ingressi. `reason`: "" ok | locked_feature | count | missing | locked | in_use | kind | rarity |
## variant | dup | no_output. `need` = quanti ingressi servono.
func contract_check(uids: Array, golden: bool = false) -> Dictionary:
	var need := contract_inputs(golden)
	var res := {"ok": false, "reason": "", "need": need}
	if not contract_unlocked(golden):
		res.reason = "locked_feature"
		return res
	if uids.size() != need:
		res.reason = "count"
		return res
	var seen := {}
	var rarity := ""
	var annal := -1
	var allowed: Array = ["mythic"] if golden else Array(rules().tradeup.rarities_in)
	for u in uids:
		var uid := str(u)
		if seen.has(uid):
			res.reason = "dup"
			return res
		seen[uid] = true
		var blk := consume_block(uid)
		if not blk.is_empty():
			res.reason = blk
			return res
		var inst := instance(uid)
		if str(inst.kind) != "skin":
			res.reason = "kind"
			return res
		var r := str(inst.rarity)
		if rarity.is_empty():
			rarity = r
		if r != rarity or not allowed.has(r):
			res.reason = "rarity"
			return res
		var a := 1 if bool(inst.get("annalist", false)) else 0
		if not golden:
			if annal < 0:
				annal = a
			elif a != annal:
				res.reason = "variant"
				return res
		if _contract_pool(inst_crate(inst), rarity, golden).is_empty():
			res.reason = "no_output"
			return res
	res.ok = true
	return res


## Id della cassa di un'istanza: il campo `crate` (id della cassa aperta) o, se manca, quella dei dati dell'oggetto.
func inst_crate(inst: Dictionary) -> String:
	var c := str(inst.get("crate", ""))
	if is_crate(c):
		return c
	var dc := "crate_" + str(ctx.data.item(str(inst.get("def_id", ""))).get("crate", ""))
	return dc if is_crate(dc) else ""


func _contract_pool(crate_id: String, rarity_in: String, golden: bool) -> Array:
	if not is_crate(crate_id):
		return []
	var cont := contents(crate_id)
	return cont["relic"] if golden else cont[_next_rarity(rarity_in)]


## Anteprima PRIMA di firmare: ogni esito possibile con probabilità e float previsto.
## {ok, reason, need, rarity_in, rarity_out, annalist, avg_norm, outcomes: [{def_id, crate, collection, pct, kind,
##  float, condition}], phases: [{id, pct}]}   (phases solo per il Contratto Aureo: la fase colore della Reliquia)
func contract_preview(uids: Array, golden: bool = false) -> Dictionary:
	var out := contract_check(uids, golden)
	out["outcomes"] = []
	out["phases"] = []
	out["rarity_in"] = ""
	out["rarity_out"] = ""
	out["avg_norm"] = 0.0
	out["annalist"] = false
	if not bool(out.ok):
		return out
	var per_crate := {}
	var order: Array = []
	var norm_sum := 0.0
	var first := instance(str(uids[0]))
	var rarity_in := str(first.rarity)
	for u in uids:
		var inst := instance(str(u))
		var cid := inst_crate(inst)
		if not per_crate.has(cid):
			per_crate[cid] = 0
			order.append(cid)
		per_crate[cid] = int(per_crate[cid]) + 1
		var rg := _float_range(str(inst.def_id))
		norm_sum += clampf((float(inst.get("float", 0.0)) - rg.x) / maxf(1e-9, rg.y - rg.x), 0.0, 1.0)
	var avg := norm_sum / float(uids.size())
	out.avg_norm = avg
	out.rarity_in = rarity_in
	out.rarity_out = "relic" if golden else _next_rarity(rarity_in)
	out.annalist = (not golden) and bool(first.get("annalist", false))
	var outcomes: Array = []
	for cid in order:
		var pool := _contract_pool(cid, rarity_in, golden)
		var share := float(per_crate[cid]) / float(uids.size())
		for did in pool:
			var d: Dictionary = ctx.data.item(str(did))
			var o := {"def_id": did, "crate": cid, "collection": collection_of(cid), "pct": 100.0 * share / float(pool.size()),
				"kind": str(d.get("category", "pet")), "float": -1.0, "condition": ""}
			if o.kind == "skin" or o.kind == "relic":
				var rg2 := _float_range(str(did))
				o["float"] = rg2.x + (rg2.y - rg2.x) * avg
				o["condition"] = condition_for_float(float(o.float))
			outcomes.append(o)
	out.outcomes = outcomes
	if golden:
		var tot := 0.0
		for p in rules().relic_phases:
			tot += float(p.weight)
		for p in rules().relic_phases:
			out.phases.append({"id": str(p.id), "pct": 100.0 * float(p.weight) / tot})
	return out


## Firma il contratto. L'esito è estratto QUI, per intero (ordine RNG "crates": esito → motivo → fase), e applicato
## prima che la UI mostri qualcosa. Ritorna {} se non valido, altrimenti
## {def_id, kind, rarity, uid, instance, is_new, pct, golden}. Gli ingressi sono consumati.
func contract_sign(uids: Array, golden: bool = false) -> Dictionary:
	var pv := contract_preview(uids, golden)
	if not bool(pv.ok):
		return {}
	var ws: Array = []
	for o in pv.outcomes:
		ws.append(float(o.pct))
	var crng := _draw_rng(CONTRACT_DRAW_KEY)            # Q82-1: anche il contratto e' indicizzato (nessuna ri-estrazione ricaricando)
	var pick: Dictionary = pv.outcomes[maxi(0, RngStreams.weighted_pick(crng, ws))]
	var inst: Dictionary = {}
	var def_id := str(pick.def_id)
	var kind := str(pick.kind)
	var rarity := str(pv.rarity_out)
	if kind == "skin" or kind == "relic":
		var d: Dictionary = ctx.data.item(def_id)
		var sk: Dictionary = d.get("skin", d.get("relic", {}))
		inst = {"def_id": def_id, "kind": kind, "rarity": rarity, "crate": str(pick.crate), "condition": str(pick.condition),
			"float": float(pick.float), "annalist": bool(pv.annalist),
			"seed": crng.randi_range(0, int(sk.get("pattern_seeds", 1000)) - 1),
			"phase": "", "polish": 0, "locked": false}
		if kind == "relic":
			inst["phase"] = _roll_phase(sk.get("phases", []), crng)
	var b := _bank()
	for u in uids:
		_drop_instance(str(u))
	var uid := ""
	var is_new := false
	if kind == "pet":
		ctx.events.pet_found.emit(def_id)
	else:
		uid = str(b.add_instance(inst))
		if uid == BankSystem.OVERFLOW_UID:
			uid = ""
		inst["uid"] = uid
		is_new = _record_find(str(pick.crate), def_id, inst)
	_stat_add("golden" if golden else "contracts")
	ctx.events.objective_event.emit("tradeup", {"qty": 1})
	ctx.events.important_event.emit("crate")
	return {"def_id": def_id, "kind": kind, "rarity": rarity, "uid": uid, "instance": inst, "is_new": is_new,
		"pct": float(pick.pct), "golden": golden}


## Elenca gli `n` ingressi «peggiori» (float più alto = condizione peggiore) tra le istanze consumabili della
## rarità `rarity` e della variante `annalist`. Aiuto per la UI: non decide nulla, propone soltanto.
func auto_pick(rarity: String, annalist: bool, golden: bool = false) -> Array:
	var cands: Array = []
	for inst in _all_instances():
		if str(inst.get("kind", "")) != "skin" or str(inst.get("rarity", "")) != rarity:
			continue
		if not golden and bool(inst.get("annalist", false)) != annalist:
			continue
		if consume_block(str(inst.uid)).is_empty():
			cands.append(inst)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa := float(a.get("float", 0.0))
		var fb := float(b.get("float", 0.0))
		return fa > fb if fa != fb else str(a.uid) < str(b.uid))
	var out: Array = []
	for c in cands:
		if out.size() >= contract_inputs(golden):
			break
		out.append(str(c.uid))
	return out


func _all_instances() -> Array:
	var b := _bank()
	return b.list_instances() if (b != null and b.has_method("list_instances")) else []


# ------------------------------------------------------------------ Affinatura (docs/09 §10)

func _refinery_cfg() -> Dictionary:
	return rules().refinery


func polish_max() -> int:
	return int(_refinery_cfg().polish.max_per_item)


## Costo in Schegge della prossima Lucidatura: ceil(schegge_fusione × cost_mult × (1 + lucidature_fatte)).
func polish_cost(inst: Dictionary) -> int:
	var base := float(rules().dismantle_shards.get(str(inst.get("rarity", "rare")), 0))
	return _refine_discount(int(ceil(base * float(_refinery_cfg().polish.cost_mult) * float(1 + int(inst.get("polish", 0))))))


## Sconto dell'Affinatura (modificatore `refine_cost_reduction_pct`: fazione Mano Grigia + reliquia Lente del Lucidatore, tetto
## nel catalogo). Il costo non scende sotto 1 Scheggia. Vale per Lucidatura e Incisione Annalista.
func _refine_discount(cost: int) -> int:
	if cost <= 0 or ctx.modifiers == null:
		return cost
	var pct := ctx.modifiers.total_add_capped("refine_cost_reduction_pct")
	return maxi(1, int(ceil(float(cost) * (1.0 - pct / 100.0))))


## {ok, reason (locked_feature|missing|kind|max|at_min|shards), cost, done, max, float, condition, new_float,
##  new_condition, shards}. Deterministica: l'anteprima è già l'esito.
func polish_info(uid: String) -> Dictionary:
	var inst := instance(uid)
	var info := {"ok": false, "reason": "", "cost": 0, "done": 0, "max": polish_max(), "float": 0.0, "condition": "",
		"new_float": 0.0, "new_condition": "", "shards": shards()}
	if not refinery_unlocked():
		info.reason = "locked_feature"
		return info
	if inst.is_empty():
		info.reason = "missing"
		return info
	if not inst.has("float"):
		info.reason = "kind"
		return info
	var f := float(inst.float)
	var rg := _float_range(str(inst.def_id))
	info.done = int(inst.get("polish", 0))
	info.float = f
	info.condition = str(inst.get("condition", ""))
	info.cost = polish_cost(inst)
	info.new_float = f - float(_refinery_cfg().polish.float_step) * (f - rg.x)
	info.new_condition = condition_for_float(float(info.new_float))
	if int(info.done) >= int(info.max):
		info.reason = "max"
	elif f - rg.x <= 1e-9:
		info.reason = "at_min"
	elif shards() < int(info.cost):
		info.reason = "shards"
	else:
		info.ok = true
	return info


func polish(uid: String) -> bool:
	var info := polish_info(uid)
	if not bool(info.ok):
		return false
	var b := _bank()
	if not b.spend_currency(SHARD, int(info.cost)):
		return false
	var inst := instance(uid)
	inst["float"] = float(info.new_float)
	inst["condition"] = str(info.new_condition)
	inst["polish"] = int(info.done) + 1
	var col: Dictionary = state.collections.get(collection_of(inst_crate(inst)), {})
	if col.has(str(inst.def_id)):
		col[str(inst.def_id)]["best"] = minf(float(col[str(inst.def_id)].best), float(inst.float))
	_refresh_equipped(uid)
	_touch_bank(uid)
	_stat_add("polished")
	ctx.events.objective_event.emit("refine_polish", {"qty": 1})
	return true


## Incisione Annalista: {ok, reason (locked_feature|missing|kind|already|shards), cost}.
func engrave_info(uid: String) -> Dictionary:
	var inst := instance(uid)
	var cost := _refine_discount(int(rules().dismantle_shards.get(str(inst.get("rarity", "rare")), 0)) * int(_refinery_cfg().engrave_annalist.cost_mult))
	var info := {"ok": false, "reason": "", "cost": cost, "shards": shards()}
	if not refinery_unlocked():
		info.reason = "locked_feature"
	elif inst.is_empty():
		info.reason = "missing"
	elif str(inst.kind) != "skin":
		info.reason = "kind"
	elif bool(inst.get("annalist", false)):
		info.reason = "already"
	elif shards() < cost:
		info.reason = "shards"
	else:
		info.ok = true
	return info


func engrave(uid: String) -> bool:
	var info := engrave_info(uid)
	if not bool(info.ok) or not _bank().spend_currency(SHARD, int(info.cost)):
		return false
	instance(uid)["annalist"] = true
	_refresh_equipped(uid)
	_rebuild_ann_list()
	_touch_bank(uid)
	_stat_add("engraved")
	return true


## Testo ripulito per la Targhetta: senza caratteri di controllo, spazi ai bordi tolti, al massimo `max_len` caratteri.
func clean_tag(text: String) -> String:
	var t := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			t += ch
	return t.strip_edges().substr(0, int(_refinery_cfg().rename.max_len))


func rename_cost() -> int:
	return int(_refinery_cfg().rename.cost_gold)


## Targhetta: {ok, reason (locked_feature|missing|gold), cost}. Testo vuoto = toglie la targhetta (gratis).
func rename_info(uid: String, text: String) -> Dictionary:
	var inst := instance(uid)
	var removing := clean_tag(text).is_empty()
	var cost := 0 if removing else rename_cost()
	var info := {"ok": false, "reason": "", "cost": cost}
	var b := _bank()
	if not refinery_unlocked():
		info.reason = "locked_feature"
	elif inst.is_empty():
		info.reason = "missing"
	elif b != null and b.gold() < cost:
		info.reason = "gold"
	else:
		info.ok = true
	return info


func rename(uid: String, text: String) -> bool:
	var info := rename_info(uid, text)
	if not bool(info.ok):
		return false
	if int(info.cost) > 0 and not _bank().spend_gold(int(info.cost)):
		return false
	var inst := instance(uid)
	var t := clean_tag(text)
	if t.is_empty():
		inst.erase("tag")
	else:
		inst["tag"] = t
	_touch_bank(uid)
	_stat_add("renamed")
	return true


# ------------------------------------------------------------------ Banco dei Caveau (docs/09 §11)

## [{item, shards, owned}] dai dati (vault_bank).
func vault_stock() -> Array:
	var out: Array = []
	var b := _bank()
	for e in rules().vault_bank:
		out.append({"item": str(e.item), "shards": int(e.shards), "owned": int(b.count(str(e.item))) if b != null else 0})
	return out


func _vault_price(item_id: String) -> int:
	for e in rules().vault_bank:
		if e.item == item_id:
			return int(e.shards)
	return 0


## "" = si può comprare, altrimenti: unknown | shards | space.
func vault_buy_check(item_id: String, qty: int = 1) -> String:
	var price := _vault_price(item_id)
	var b := _bank()
	if price <= 0 or qty < 1 or b == null:
		return "unknown"
	if shards() < price * qty:
		return "shards"
	return ""            # il Deposito pieno non blocca l'acquisto: il pezzo va nel Carro di Ritiro (resoconto 117)


func vault_buy(item_id: String, qty: int = 1) -> bool:
	if not vault_buy_check(item_id, qty).is_empty():
		return false
	var b := _bank()
	if not b.spend_currency(SHARD, _vault_price(item_id) * qty):
		return false
	if b.add(item_id, qty, "vault_bank") < qty:
		return false
	_stat_add("bought", qty)
	return true


# ------------------------------------------------------------------ Sfida dei Collezionisti (docs/09 §12)
# Classifica settimanale contro 3 rivali PNG. Punteggio = punti-rarità degli oggetti TROVATI aprendo casse nella
# settimana. Nessuna scommessa, nessun oggetto in palio, nessuna penalità se non si partecipa (R-LEG-6).
# Il tempo è il tempo di gioco (stats.playtime_s); la settimana dura `week_days` giorni di gioco.

func _challenge_cfg() -> Dictionary:
	return rules().collectors_challenge


func challenge_clock() -> float:
	return float(ctx.state.get("stats", {}).get("playtime_s", 0.0))


func _week_seconds() -> float:
	return float(_challenge_cfg().week_days) * MarketSystem.DAY_S


func challenge_points(rarity: String) -> int:
	return int(_challenge_cfg().points.get(rarity, 0))


func _challenge_state() -> Dictionary:
	var c: Dictionary = state.challenge
	for k in ["week", "score", "max_tier", "wins", "best_place"]:
		if not c.has(k):
			c[k] = -1 if k == "week" else (1 if k == "max_tier" else 0)
	for k in ["rivals", "pending", "last"]:
		if typeof(c.get(k)) != TYPE_DICTIONARY:
			c[k] = {}
	return c


func _week_index() -> int:
	return int(floor(challenge_clock() / _week_seconds()))


## Allinea la sfida alla settimana corrente: alla prima volta si iscrive, a settimana finita assegna il piazzamento
## (premio in attesa di ritiro) e ne apre una nuova. Idempotente.
func challenge_sync() -> void:
	var c := _challenge_state()
	if not challenge_unlocked():
		return
	var w := _week_index()
	if int(c.week) < 0:
		_challenge_start(c, w)
	elif w > int(c.week):
		var place := _place_of(int(c.score), c.rivals)
		c.last = {"week": int(c.week), "place": place, "score": int(c.score)}
		c.pending = {"week": int(c.week), "place": place, "score": int(c.score)}
		if place == 1:
			c.wins = int(c.wins) + 1
		c.best_place = place if (int(c.best_place) == 0 or place < int(c.best_place)) else int(c.best_place)
		_challenge_start(c, w)


func _challenge_start(c: Dictionary, week: int) -> void:
	c.week = week
	c.score = 0
	c.rivals = {}
	var tier := maxi(1, int(c.max_tier))
	for r in _challenge_cfg().rivals:
		var mean := float(r.mean_per_tier) * float(tier)
		var dev := mean * float(r.dev_pct) / 100.0
		c.rivals[str(r.id)] = maxi(0, roundi(ctx.rng.stream("world").randfn(mean, dev)))


## Piazzamento 1..4: 1 + rivali con più punti (a parità vince chi gioca).
func _place_of(score: int, rivals: Dictionary) -> int:
	var p := 1
	for rid in rivals:
		if int(rivals[rid]) > score:
			p += 1
	return p


func _challenge_on_open(crate_id: String, rarity: String) -> void:
	var c := _challenge_state()
	var tier := maxi(1, roundi(float(ctx.data.item(crate_id).get("tier", 2)) / 2.0))
	if tier > int(c.max_tier):
		c.max_tier = tier
	if not challenge_unlocked():
		return
	challenge_sync()
	c.score = int(c.score) + challenge_points(rarity)


## Quanta parte della settimana è trascorsa (0..1).
func challenge_progress() -> float:
	var c := _challenge_state()
	if int(c.week) < 0:
		return 0.0
	return clampf((challenge_clock() - float(c.week) * _week_seconds()) / _week_seconds(), 0.0, 1.0)


## Secondi di gioco alla fine della settimana.
func challenge_time_left() -> float:
	return (1.0 - challenge_progress()) * _week_seconds()


## Classifica attuale: [{id, name (testo bilingue), score, player}] in ordine di punti. I rivali mostrano i punti
## maturati finora (finale × avanzamento della settimana).
func challenge_board() -> Array:
	challenge_sync()
	var c := _challenge_state()
	var out: Array = [{"id": "player", "name": {}, "score": int(c.score), "player": true}]
	var prog := challenge_progress()
	for r in _challenge_cfg().rivals:
		out.append({"id": str(r.id), "name": r.name, "score": roundi(float(c.rivals.get(str(r.id), 0)) * prog), "player": false})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.score) != int(b.score):
			return int(a.score) > int(b.score)
		return bool(a.player) and not bool(b.player))
	return out


## Premio in attesa: {} oppure {week, place, score, rewards: [{item, qty}]}.
func challenge_pending() -> Dictionary:
	challenge_sync()
	var c := _challenge_state()
	if c.pending.is_empty():
		return {}
	var rw: Array = _challenge_cfg().rewards_by_place.get(str(int(c.pending.place)), [])
	return {"week": int(c.pending.week), "place": int(c.pending.place), "score": int(c.pending.score), "rewards": rw}


## "" = ritirabile, altrimenti: none | space.
func challenge_claim_check() -> String:
	var p := challenge_pending()
	if p.is_empty():
		return "none"
	return ""            # il Deposito pieno non blocca il ritiro: i premi che non entrano vanno nel Carro di Ritiro (resoconto 117)


func challenge_claim() -> bool:
	if not challenge_claim_check().is_empty():
		return false
	var p := challenge_pending()
	var b := _bank()
	for e in p.rewards:
		b.add(str(e.item), int(e.qty), "challenge")
	_challenge_state().pending = {}
	return true


func challenge_info() -> Dictionary:
	challenge_sync()
	var c := _challenge_state()
	return {"week": int(c.week), "score": int(c.score), "wins": int(c.wins), "best_place": int(c.best_place),
		"tier": maxi(1, int(c.max_tier)), "last": c.last.duplicate(), "progress": challenge_progress(),
		"time_left_s": challenge_time_left()}


# ------------------------------------------------------------------ apertura multipla: la migliore

## Indice della «migliore» di una serie di risultati di open(): rarità più alta, poi più valore (Annalista, motivo,
## fase, float basso), poi l'ordine di apertura. Presentazione soltanto: non cambia nulla del risultato.
static func best_result_index(results: Array) -> int:
	var best := -1
	var best_key := -1.0
	for i in results.size():
		if not (results[i] is Dictionary):
			continue
		var r: Dictionary = results[i]
		var inst: Dictionary = r.get("instance", {})
		var key := float(RARITIES.find(str(r.get("rarity", "rare")))) * 100.0
		if bool(inst.get("annalist", false)):
			key += 10.0
		if str(inst.get("phase", "")) in ["gem_ruby", "gem_sapphire"]:
			key += 20.0
		key += 5.0 * (1.0 - clampf(float(inst.get("float", 1.0)), 0.0, 1.0))
		if key > best_key + 1e-9:
			best_key = key
			best = i
	return best
