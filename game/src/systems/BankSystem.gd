class_name BankSystem
extends GameSystem
## Deposito (docs/07 §7, docs/17 §4) e valute. Unico sistema che conosce la forma di `bank` e `currencies`.
## Contratto con gli altri sistemi: docs/audit_2026-10-22/17_CONTRATTI_TRA_SISTEMI.md (firme invariabili).
##
## Stato `bank`:
##   stacks      {def_id: qty}          oggetti impilabili (1 spazio ciascuno, qualunque quantità)
##   instances   [{uid, def, quality, sockets, rank, locked}]   oggetti non impilabili (1 spazio ciascuno)
##   slots_bought  spazi comprati (Emporio, T-5.2)
##   next_uid    contatore degli uid ("i_000123"); le aggiunte alle pile ne consumano uno (vedi recent)
##   recent      {def_id: numero} «ultima aggiunta» di ogni pila, sulla stessa scala degli uid (ordinamento «recenti»)
##   locked_defs {def_id: true}         pile bloccate (non vendibili/fondibili)
##   gift_done   il regalo di nuova partita (dati) è già stato consegnato
##   overflow_stacks     {def_id: qty}   CARRO DI RITIRO (QA81 M3, esteso a tutte le fonti nel resoconto 117): ciò che non entra
##                       nel Deposito pieno (offline, Clessidra, aperture di Casse, acquisti, ricompense...) aspetta qui invece
##                       di perdersi; si scarica da solo appena c'è posto (tick). Le unità impilabili del Carro contano in count()
##                       e si possono consumare (chiavi, ingredienti): un posto mancante non ferma mai l'apertura o il mestiere.
##   overflow_instances  [{def, quality, sockets, rank, ...}]   idem per gli oggetti non impilabili (tetto: constants.offline.
##                       overflow_max_instances; oltre il tetto il pezzo si vende al prezzo del Mercato, e il Bentornato lo dice)
##   tabs        [{id, name, icon, sort: {id, desc}}]   SCHEDE del giocatore (F17, schema 5; ordine = posizione). Nome = dato
##               dell'utente (non si traduce; 1..constants.bank.ui.tab_name_max caratteri, ripulito); icona = def_id di un oggetto.
##   tab_of      {"s:<def_id>" | "u:<uid>": tab id}   assegnazione «appiccicosa» (una voce = una scheda; l'Armeria non si
##               assegna): le chiavi «s:» restano anche a pila esaurita, le «u:» spariscono con l'istanza.
##   next_tab    contatore degli id delle schede ("t_0001"), mai riusato
##   tabs_intro_done  il riquadro di benvenuto delle schede è già stato mostrato (una volta per partita)
## Stato `currencies` (sezione radice, scritta SOLO da qui): {"gold": int, "<id valuta>": int}. Le valute sono
## gli oggetti di categoria "currency" dei dati (+ l'oro): non occupano spazi.
##
## Numeri: capacità = shop.json «bank_slot».base_slots + slots_bought + Modifiers «bank_slots»; qualità
## predefinita = primo elemento di constants.quality; regalo iniziale = constants.new_game_gift (assente = nessuno).

const UID_FORMAT := "i_%06d"
const GOLD := "gold"
const CATEGORY_CURRENCY := "currency"
const SHOP_BANK_ENTRY := "bank_slot"
const SHOP_MOD_SOURCE := "shop:" + SHOP_BANK_ENTRY      # fonte Modifiers scritta da MarketSystem._apply_shop_mods
## Valore ritornato da add_instance() quando il pezzo è finito nel Carro di Ritiro (non è un uid reale).
const OVERFLOW_UID := "~carro"
const TAB_ID_FORMAT := "t_%04d"
## Criteri di ordinamento ammessi per una scheda (identificatori dell'interfaccia, non numeri di bilanciamento).
const TAB_SORTS: PackedStringArray = ["recent", "cat", "name", "value", "tier", "qty", "worn"]
const TAB_SORT_DEFAULT := {"id": "recent", "desc": true}

## Incrementato a ogni modifica (non salvato): la UI ricostruisce le liste solo quando cambia.
var revision: int = 0

var _by_uid: Dictionary = {}        # uid -> istanza (stesso Dictionary che sta in state.instances)
var _def_count: Dictionary = {}     # def_id -> numero di istanze
var _value_cache: float = -1.0
## Contatori del Carro dell'assenza in corso (non salvati): letti da OfflineOverflow.take_report() per il Bentornato.
var _ovf_report: Dictionary = {}
## Doppioni riciclati al caricamento ({pieces, gold}): il resoconto parte al primo tick (non salvato).
var _migr_report: Dictionary = {}
## Ultimo stato dell'avviso «Deposito quasi pieno» (non salvato): l'avviso parte solo quando si SUPERA la soglia.
var _warned: bool = false
## Secondi dall'ultimo riepilogo online del Carro nel Registro (non salvato).
var _notice_acc: float = 0.0
## Quante istanze del Deposito sono di classe «equipaggiamento» (Armeria, F15): non occupano Spazio. Tenuto da
## _insert_instance/_erase_instance/_reindex, l'unico punto che tocca state.instances (non salvato).
var _gear_n: int = 0
## def_id -> bool «è di una categoria libera» (cache; i dati non cambiano a partita in corso).
var _gear_defs: Dictionary = {}
## Ultimo stato dell'avviso «Armeria quasi piena» (non salvato).
var _gear_warned: bool = false
## Pezzi scaricati dal Carro verso l'Armeria al caricamento di un vecchio salvataggio (non salvato): una riga nel Registro.
var _gear_migr: int = 0
## Il caricamento ha ripulito schede o assegnazioni non valide (non salvato): una riga nel Registro al primo tick.
var _tabs_cleaned: bool = false


func _init() -> void:
	id = "bank"
	state_key = "bank"


func default_state() -> Variant:
	return {"stacks": {}, "instances": [], "slots_bought": 0, "next_uid": 1, "recent": {},
		"locked_defs": {}, "gift_done": false, "overflow_stacks": {}, "overflow_instances": [],
		"tabs": [], "tab_of": {}, "next_tab": 1, "tabs_intro_done": false}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["next_uid", "recent.*", "overflow_stacks.*", "overflow_instances[].rank", "next_tab"])


## Tetto delle quantita' (come il limite del codec dei salvataggi, 9e18): le somme non vanno mai in overflow int64.
const QTY_CAP := 9000000000000000000


## Somma `n` a `cur` saturando a QTY_CAP (nessun overflow).
static func sat_add(cur: int, n: int) -> int:
	if n >= QTY_CAP - cur:
		return QTY_CAP
	return cur + n


## Quantita' valida da un valore caricato: numero finito >= 0 (i float si troncano), altrimenti -1.
static func _clean_qty(v: Variant) -> int:
	if v is int:
		return clampi(v, -1, QTY_CAP) if v >= 0 else -1
	if v is float:
		var f: float = v
		if not is_finite(f) or f < 0.0:
			return -1
		return QTY_CAP if f >= float(QTY_CAP) else int(f)
	return -1


## I campi interi delle istanze (seed della forma, lucidatura) tornano `int` dopo il JSON (che li legge come float):
## una partita ricaricata resta identica a quella che continua (QA120). Solo valori interi e finiti; il resto non si tocca.
static func _int_fields_back_to_int(list: Array) -> void:
	for inst in list:
		if not (inst is Dictionary):
			continue
		for k in ["seed", "polish"]:
			var v: Variant = (inst as Dictionary).get(k)
			if v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
				inst[k] = int(v)


func from_state(section: Variant) -> void:
	state = section
	var d: Dictionary = default_state()
	for k in d:
		if state.has(k) and typeof(d[k]) == TYPE_INT and typeof(state[k]) == TYPE_FLOAT:
			state[k] = int(state[k])
		elif not state.has(k) or typeof(state[k]) != typeof(d[k]):
			state[k] = d[k]
	for k in state.stacks.keys():                    # F5: scorte negative o non finite non esistono
		var q := _clean_qty(state.stacks[k])
		if q <= 0:
			state.stacks.erase(k)
		else:
			state.stacks[k] = q
	for k in state.overflow_stacks.keys():           # Carro di Ritiro: stesse regole delle pile (e solo oggetti noti)
		var oq := _clean_qty(state.overflow_stacks[k])
		if oq <= 0 or not ctx.data.has_item(str(k)):
			state.overflow_stacks.erase(k)
		else:
			state.overflow_stacks[k] = oq
	_int_fields_back_to_int(state.instances)          # QA120: seed/polish tornano float dopo il JSON (round-trip non identico)
	var ovf_ok: Array = []
	for oi in state.overflow_instances:
		if oi is Dictionary and ctx.data.has_item(_inst_def(oi)):
			(oi as Dictionary)["def"] = _inst_def(oi)
			ovf_ok.append(oi)
	state["overflow_instances"] = ovf_ok
	_int_fields_back_to_int(ovf_ok)
	if not (ctx.state.get("currencies") is Dictionary):
		ctx.state["currencies"] = {}
	var cur: Dictionary = ctx.state.currencies
	if not cur.has(GOLD):
		cur[GOLD] = 0
	for k in cur.keys():
		cur[k] = maxi(0, _clean_qty(cur[k]))        # R-SAV-8: le valute diverse dall'oro non sono nei percorsi base
	_gear_defs.clear()
	_reindex()
	_recycle_loaded_duplicates()
	_unload_gear_cart_on_load()
	_clean_tabs_on_load()
	_apply_new_game_gift()


## Il Deposito non ha nulla da fare col passare del tempo: niente tick a passi fissi offline.
func simulate_offline(_seconds: float) -> Dictionary:
	return {}


## Online: il Carro di Ritiro si scarica da solo appena nel Deposito c'è posto (controllo a costo zero se è vuoto).
func tick(_dt: float) -> void:
	if not state.overflow_stacks.is_empty() or not state.overflow_instances.is_empty():
		claim_overflow()
	_flush_online_report(_dt)
	if _gear_migr > 0:                              # vecchio Carro svuotato verso l'Armeria (F15): lo si dice una volta sola
		var moved := _gear_migr
		_gear_migr = 0
		ctx.events.notice.emit("info", Loc.tf("UI_BANKG_CARRO_TO_ARMORY", {"n": NumberFormat.fmt(float(moved))}),
			{"reason": "carro_to_armory", "section": "bank"})
	if not _migr_report.is_empty():                 # riciclo dei doppioni di una vecchia partita: lo si dice una volta sola
		var rep := _migr_report
		_migr_report = {}
		ctx.events.notice.emit("info", Loc.tf("UI_BANK_DUPES_MIGRATED", {"n": int(rep.pieces), "gold": NumberFormat.fmt(float(rep.gold))}),
			{"reason": "dupes_recycled", "section": "bank"})
	if _tabs_cleaned:                               # schede o assegnazioni non valide ripulite al caricamento: una riga sola
		_tabs_cleaned = false
		ctx.events.notice.emit("info", tr("UI_BANKG_TABS_CLEANED"), {"reason": "bank_tabs_cleaned", "section": "bank"})
	_check_warn()


# ------------------------------------------------------------------ Carro di Ritiro (QA81 M3)
## Durante l'offline il Deposito pieno NON deve far perdere il bottino né fermare la produzione: ciò che non entra va nel
## Carro (pile nuove e istanze; le pile già presenti non servono posto e entrano sempre). Nessuna perdita silenziosa, nessun
## azzardo: lo scarico è deterministico (ordine alfabetico, poi istanze nell'ordine di arrivo). Il tetto di istanze viene
## dai dati; oltre il tetto il pezzo è venduto al prezzo del Mercato (il Bentornato dice quanti pezzi e quanto oro).

func _offline_now() -> bool:
	var sim := ctx.simulation()
	return sim != null and sim.offline_running


func overflow_count() -> int:
	var n: int = (state.overflow_instances as Array).size()
	for k in state.overflow_stacks:
		n += int(state.overflow_stacks[k])
	return n


## Id di tutte le pile impilabili possedute, Carro di Ritiro compreso (prima il Deposito, poi il Carro). Per bot e strumenti.
func owned_stack_ids() -> Array:
	var out: Array = state.stacks.keys()
	for k in state.overflow_stacks:
		if not state.stacks.has(k):
			out.append(k)
	return out


func overflow_stacks_count() -> int:
	return state.overflow_stacks.size()


func overflow_instance_count() -> int:
	return state.overflow_instances.size()


func _rep_add(key: String, n: int) -> void:
	_ovf_report[key] = int(_ovf_report.get(key, 0)) + n


## Mette nel Carro `qty` unità impilabili di `def_id`.
func _stash_stack(def_id: String, qty: int) -> void:
	state.overflow_stacks[def_id] = sat_add(int(state.overflow_stacks.get(def_id, 0)), qty)
	_rep_add("stacked", qty)


## Questo pezzo può essere venduto automaticamente oltre il tetto? Mai Reliquie, pezzi unici, Annalisti, bloccati o non commerciabili.
func _auto_sellable(inst: Dictionary) -> bool:
	var def: Dictionary = ctx.data.item(_inst_def(inst))
	if def.is_empty() or bool(def.get("unique", false)) or bool(inst.get("locked", false)) or not bool(def.get("tradeable", true)):
		return false
	if bool(inst.get("annalist", false)):
		return false
	return str(def.get("category", "")) != "relic"


## Mette nel Carro un'istanza. Oltre il tetto la vende (se il Mercato la quota e non è una Reliquia/unico/bloccato);
## altrimenti la tiene comunque: mai persa.
func _stash_instance(inst: Dictionary) -> void:
	var def_id := _inst_def(inst)
	if state.overflow_instances.size() >= overflow_cap() and _auto_sellable(inst):
		var mk := ctx.get_system("market")
		var g := int(mk.call("quote_sell", def_id, 1)) if mk != null else 0
		if g > 0:
			add_gold(g)
			_rep_add("sold", 1)
			_rep_add("sold_gold", g)
			return
	var keep := inst.duplicate(true)
	keep["def"] = def_id
	keep.erase("uid")
	keep.erase("source")
	state.overflow_instances.append(keep)
	_rep_add("instances", 1)


## Elenco del Carro per la UI: [{id, qty, stack: bool}] (pile in ordine alfabetico, poi le istanze raggruppate per oggetto).
func overflow_entries() -> Array:
	var out: Array = []
	var ids: Array = state.overflow_stacks.keys()
	ids.sort()
	for k in ids:
		out.append({"id": str(k), "qty": int(state.overflow_stacks[k]), "stack": true})
	var per: Dictionary = {}
	for inst in state.overflow_instances:
		var d := _inst_def(inst)
		per[d] = int(per.get(d, 0)) + 1
	var dids: Array = per.keys()
	dids.sort()
	for d in dids:
		out.append({"id": str(d), "qty": int(per[d]), "stack": false})
	return out


## Tetto di istanze del Carro (dati: offline.overflow_max_instances).
func overflow_cap() -> int:
	return int((ctx.constants().get("offline", {}) as Dictionary).get("overflow_max_instances", 0))


## Le Finiture (istanze di categoria «skin») che aspettano nel Carro.
func overflow_skin_count() -> int:
	var n := 0
	for inst in state.overflow_instances:
		if str(ctx.data.item(_inst_def(inst)).get("category", "")) == "skin":
			n += 1
	return n


## Filtro «consigliato» per le Finiture in eccesso (dati: constants.bank.carro.sell_rule).
func recommended_sell_rule() -> Dictionary:
	var c: Variant = _bank_rules().get("carro", {})
	var r: Variant = (c as Dictionary).get("sell_rule", {}) if c is Dictionary else {}
	return (r as Dictionary).duplicate(true) if r is Dictionary else {}


## Scarica nel Deposito quanto entra. Ritorna {"moved": pezzi scaricati, "left": pezzi ancora nel Carro}.
func claim_overflow() -> Dictionary:
	var moved := 0
	var ids: Array = state.overflow_stacks.keys()
	ids.sort()
	for k in ids:
		var q := int(state.overflow_stacks[k])
		if state.stacks.has(k) or free_slots() > 0:
			state.stacks[k] = sat_add(int(state.stacks.get(k, 0)), q)
			_touch_recent(str(k))
			state.overflow_stacks.erase(k)
			moved += q
	if not state.overflow_instances.is_empty():      # per classe (R-SP-5): un pezzo di equipaggiamento aspetta solo se l'Armeria è piena
		var keep: Array = []
		var space_free := free_slots()
		var gear_room := gear_free()
		for inst in state.overflow_instances:
			if is_gear_def(_inst_def(inst)):
				if gear_room > 0:
					gear_room -= 1
					_insert_instance(inst)
					moved += 1
				else:
					keep.append(inst)
			elif space_free > 0:
				space_free -= 1
				_insert_instance(inst)
				moved += 1
			else:
				keep.append(inst)
		state.overflow_instances = keep
	if moved > 0:
		_changed()
		ctx.events.notice.emit("info", tr("UI_OFFL_OVERFLOW_CLAIMED").format({"n": moved}), {"reason": "overflow_claimed", "n": moved})
	return {"moved": moved, "left": overflow_count()}


## Online: il Registro riassume ogni `constants.bank.carro.notice_s` secondi cosa è entrato nel Carro (una riga, non una per pezzo).
## Offline il resoconto lo dà il Bentornato (finish_offline), quindi qui non si tocca.
func _flush_online_report(dt: float) -> void:
	if _ovf_report.is_empty() or _offline_now():
		_notice_acc = 0.0
		return
	_notice_acc += dt
	var every := float((_bank_rules().get("carro", {}) as Dictionary).get("notice_s", 0))
	if _notice_acc < every:
		return
	_notice_acc = 0.0
	var r := take_overflow_report()
	var n := int(r.get("stacked", 0)) + int(r.get("instances", 0))
	if n > 0:
		ctx.events.notice.emit("warning", Loc.tf("UI_CARRO_STASHED", {"n": NumberFormat.fmt(float(n)), "waiting": NumberFormat.fmt(float(r.waiting))}),
			{"reason": "carro_stash", "section": "bank"})
	if int(r.get("sold", 0)) > 0:
		ctx.events.notice.emit("info", Loc.tf("UI_OFFL_OVERFLOW_SOLD", {"n": NumberFormat.fmt(float(r.sold)), "gold": NumberFormat.fmt(float(r.sold_gold))}),
			{"reason": "carro_sold", "section": "bank"})


## Righe del Bentornato sul Carro (R-OFF-4: «banca piena» non è più un motivo di perdita, ma un'attesa spiegata).
func finish_offline() -> Dictionary:
	var r := take_overflow_report()
	var rows: Array = []
	if int(r.get("waiting", 0)) > 0:
		rows.append({"key": "UI_OFFL_OVERFLOW_WAITING", "params": {"n": NumberFormat.fmt(float(r.waiting))}})
	if int(r.get("sold", 0)) > 0:
		rows.append({"key": "UI_OFFL_OVERFLOW_SOLD", "params": {"n": NumberFormat.fmt(float(r.sold)), "gold": NumberFormat.fmt(float(r.sold_gold))}})
	return {"rows": rows} if not rows.is_empty() else {}


## Resoconto del Carro dell'assenza appena finita, per il Bentornato (e lo azzera). Chiavi: stacked (unità), instances
## (pezzi), sold (pezzi venduti oltre il tetto), sold_gold; "waiting" = quanto aspetta ADESSO nel Carro.
func take_overflow_report() -> Dictionary:
	var r := _ovf_report.duplicate()
	_ovf_report = {}
	r["waiting"] = overflow_count()
	return r


# ------------------------------------------------------------------ capacità

## Spazi totali: base dai dati + comprati + bonus (Costellazioni, reliquie…).
func capacity() -> int:
	var shop: Dictionary = ctx.data.get_def("shop", SHOP_BANK_ENTRY)
	var base := int(shop.get("base_slots", 0))
	return maxi(0, base + int(state.slots_bought) + int(ctx.modifiers.total_add("bank_slots")))


## Da dove vengono gli spazi (riepilogo del Deposito, resoconto 114): {base, bought, quests, constellations, relics, other, total}.
## `bought` = cassetti comprati (Emporio o «Espandi Deposito»), `relics` = solo le reliquie nel Reliquiario. La somma è `total`.
func capacity_breakdown() -> Dictionary:
	var shop: Dictionary = ctx.data.get_def("shop", SHOP_BANK_ENTRY)
	var out := {"base": int(shop.get("base_slots", 0)), "bought": int(state.slots_bought), "quests": 0, "constellations": 0, "relics": 0, "other": 0}
	for c in ctx.modifiers.contributions("bank_slots"):
		var src := str(c.source)
		var v := int(float(c.value))
		if src == SHOP_MOD_SOURCE:
			out.bought += v
		elif src == QuestSystem.BANK_SLOTS_SOURCE:
			out.quests += v
		elif src == PrestigeSystem.SRC_CONSTELLATION:
			out.constellations += v
		elif src.begins_with(CrateSystem.RELIC_PREFIX):
			out.relics += v
		else:
			out.other += v
	out["total"] = capacity()
	return out


## Le fonti permanenti di spazi che NON si comprano, lette dai dati (nessun nome o numero scritto nel codice):
## {quest_earned, quest_total, quest_left (missioni ancora da riscattare), quest_next_chapter (-1 se finite),
##  node: {id, name, per, max, level} | {}, relic: {name, slots, def_id} | {}}. Serve al riepilogo di «Espandi Deposito».
func permanent_sources() -> Dictionary:
	var out := {"quest_earned": 0, "quest_total": 0, "quest_left": 0, "quest_next_chapter": -1, "node": {}, "relic": {}}
	var qs := ctx.get_system("quests") as QuestSystem
	if qs != null:
		for r in qs.bank_slot_rewards():
			out.quest_total += int(r.slots)
			if bool(r.done):
				out.quest_earned += int(r.slots)
			else:
				out.quest_left += 1
				if int(out.quest_next_chapter) < 0:
					out.quest_next_chapter = int(r.chapter)
	var pr := ctx.get_system("prestige") as PrestigeSystem
	for n in ctx.data.table("constellations"):
		var mp: Dictionary = n.get("modifier_per_level", {})
		if str(mp.get("key", "")) == "bank_slots":
			out.node = {"id": str(n.id), "name": n.get("name", {}), "per": float(mp.get("value", 0)), "max": int(n.get("max_level", 0)),
				"level": pr.node_level(str(n.id)) if pr != null else 0}
			break
	for it in ctx.data.items_by_category("relic"):
		for m in (it.get("relic", {}) as Dictionary).get("modifiers", []):
			if str(m.get("key", "")) == "bank_slots":
				out.relic = {"def_id": str(it.id), "name": it.get("name", {}), "slots": int(float(m.get("value", 0)))}
				break
		if not (out.relic as Dictionary).is_empty():
			break
	return out


## Spazio usato (R-SP-1): una casella per pila e per istanza che NON è di una categoria libera (equipaggiamento e attrezzi
## vanno nell'Armeria). Collezionabili (Finiture, Reliquie, cosmetici) contano.
func used_slots() -> int:
	return state.stacks.size() + state.instances.size() - _gear_n


func free_slots() -> int:
	return maxi(0, capacity() - used_slots())


func is_full() -> bool:
	return free_slots() <= 0


# ------------------------------------------------------------------ Armeria (F15, docs/ui_redesign/02 §4.1)

func _space_rules() -> Dictionary:
	var r: Variant = _bank_rules().get("space", {})
	return r if r is Dictionary else {}


## Questa definizione è di classe «equipaggiamento» (categoria in constants.bank.space.free_categories)?
func is_gear_def(def_id: String) -> bool:
	if _gear_defs.has(def_id):
		return bool(_gear_defs[def_id])
	var free: Array = _space_rules().get("free_categories", [])
	var res := free.has(str(ctx.data.item(def_id).get("category", "")))
	_gear_defs[def_id] = res
	return res


## Pezzi nell'Armeria (istanze di categoria libera, indossate comprese: R-SP-4).
func gear_used() -> int:
	return _gear_n


## Tetto tecnico dell'Armeria (dati: constants.bank.space.gear_cap; non si compra).
func gear_cap() -> int:
	return int(_space_rules().get("gear_cap", 0))


## Posti ancora liberi nell'Armeria (mai negativo: un vecchio salvataggio può averne più del tetto, e nessuno si toglie).
func gear_free() -> int:
	return maxi(0, gear_cap() - _gear_n)


func gear_is_full() -> bool:
	return gear_free() <= 0


## Posti liberi per la classe di questa definizione (le pile hanno la loro regola in add()).
func free_for(def_id: String) -> int:
	return gear_free() if is_gear_def(def_id) else free_slots()


func gear_nearly_full() -> bool:
	var cap := gear_cap()
	return cap > 0 and not gear_is_full() and float(_gear_n) * 100.0 >= float(cap) * float(_space_rules().get("gear_warn_pct", 100))


## Pezzi di equipaggiamento / altri pezzi che aspettano nel Carro (per il pannello, che ragiona per classe).
func overflow_gear_count() -> int:
	var n := 0
	for inst in state.overflow_instances:
		if is_gear_def(_inst_def(inst)):
			n += 1
	return n


func overflow_space_count() -> int:
	return overflow_count() - overflow_gear_count()


## Vecchi salvataggi (F15): il Carro che conteneva equipaggiamento in attesa lo scarica nell'Armeria, una sola volta
## (idempotente: dopo il primo caricamento nel Carro non c'è più equipaggiamento che potrebbe entrare).
func _unload_gear_cart_on_load() -> void:
	if state.overflow_instances.is_empty():
		return
	var keep: Array = []
	var moved := 0
	var room := gear_free()
	for inst in state.overflow_instances:
		if room > 0 and is_gear_def(_inst_def(inst)):
			room -= 1
			_insert_instance(inst)
			moved += 1
		else:
			keep.append(inst)
	if moved > 0:
		state.overflow_instances = keep
		_gear_migr += moved
		_changed()


# ------------------------------------------------------------------ oggetti

## Aggiunge `qty` unità. Impilabili: sommate alla pila (serve 1 spazio solo per una pila nuova).
## Non impilabili: una istanza ciascuna con valori predefiniti. Valute: vanno in `currencies`, senza spazi.
## Ritorna la quantità aggiunta: a Deposito pieno il resto va nel Carro di Ritiro (conta come aggiunto, sempre `qty`).
func add(def_id: String, qty: int, source: String = "") -> int:
	if qty <= 0:
		return 0
	if is_currency(def_id):
		add_currency(def_id, qty)
		ctx.events.item_gained.emit(def_id, qty, source)
		return qty
	var def: Dictionary = ctx.data.item(def_id)
	if def.is_empty():
		push_warning("BankSystem.add: oggetto sconosciuto " + def_id)
		return 0
	var added := 0
	if bool(def.get("stackable", false)):
		if state.stacks.has(def_id) or free_slots() > 0:
			state.stacks[def_id] = sat_add(int(state.stacks.get(def_id, 0)), qty)
			_touch_recent(def_id)
			added = qty
	else:
		added = mini(qty, free_for(def_id))
		for i in added:
			_insert_instance({"def": def_id})
	if added < qty:
		# Carro di Ritiro (resoconto 117): il resto aspetta, non si perde e non blocca nulla, né offline né online
		if bool(def.get("stackable", false)):
			_stash_stack(def_id, qty - added)
		else:
			for i in qty - added:
				_stash_instance({"def": def_id})
		added = qty
	if added > 0:
		_changed()
		ctx.events.item_gained.emit(def_id, added, source)
	return added


## Toglie `qty` unità (tutte o niente). Ignora il blocco: il blocco protegge da vendita/fusione, non dal consumo.
## Per i non impilabili toglie prima le istanze non bloccate, dalle più recenti.
func remove(def_id: String, qty: int) -> bool:
	if qty <= 0:
		return qty == 0
	if is_currency(def_id):
		if not spend_currency(def_id, qty):
			return false
		ctx.events.item_removed.emit(def_id, qty)
		return true
	var def: Dictionary = ctx.data.item(def_id)
	if def.is_empty() or count(def_id) < qty:
		return false
	if bool(def.get("stackable", false)):
		var in_stack := int(state.stacks.get(def_id, 0))
		var left := in_stack - qty
		if left > 0:
			state.stacks[def_id] = left
		else:
			if state.stacks.has(def_id):
				state.stacks.erase(def_id)
				state.recent.erase(def_id)
			if left < 0:                              # il resto si toglie dal Carro di Ritiro
				var rest := int(state.overflow_stacks.get(def_id, 0)) + left
				if rest > 0:
					state.overflow_stacks[def_id] = rest
				else:
					state.overflow_stacks.erase(def_id)
	else:
		# ordine: liberi, poi bloccati, per ultimi quelli in uso (equipaggiati / Guardaroba / Reliquiario)
		var victims: Array = []
		for pass_n in 3:
			var i: int = state.instances.size() - 1
			while i >= 0 and victims.size() < qty:
				var inst: Dictionary = state.instances[i]
				if inst.def == def_id and not victims.has(inst.uid):
					var used := is_in_use(str(inst.uid))
					var cls := 2 if used else (1 if bool(inst.locked) else 0)
					if cls == pass_n:
						victims.append(inst.uid)
				i -= 1
		for u in victims:
			_erase_instance(u)
	_changed()
	ctx.events.item_removed.emit(def_id, qty)
	return true


func count(def_id: String) -> int:
	if is_currency(def_id):
		return currency(def_id)
	if state.stacks.has(def_id) or state.overflow_stacks.has(def_id):
		# le unità nel Carro di Ritiro si possono usare (chiavi, ingredienti): un posto mancante non le rende inservibili
		return sat_add(int(state.stacks.get(def_id, 0)), int(state.overflow_stacks.get(def_id, 0)))
	return int(_def_count.get(def_id, 0))


func has(def_id: String, qty: int = 1) -> bool:
	return count(def_id) >= qty


## Quanti pezzi si possono vendere/fondere (0 se bloccati; esclusi i pezzi in uso).
func sellable_count(def_id: String) -> int:
	if is_currency(def_id):
		return 0
	if state.stacks.has(def_id):
		return 0 if is_def_locked(def_id) else int(state.stacks[def_id])
	var n := 0
	for inst in state.instances:
		if inst.def == def_id and not bool(inst.locked) and not is_in_use(str(inst.uid)):
			n += 1
	return n


## Quanti pezzi si possono SCARTARE: come i vendibili (niente bloccati, niente pezzi in uso) ma anche gli oggetti che il
## Mercato non compra. Valute e oggetti-missione non si scartano mai (GUILD-2, Deposito pieno).
func discardable_count(def_id: String) -> int:
	if is_currency(def_id) or str(ctx.data.item(def_id).get("category", "")) == "quest":
		return 0
	return sellable_count(def_id)


## Distrugge fino a `qty` pezzi (senza oro in cambio) rispettando blocchi e pezzi in uso. Ritorna quanti ne ha scartati.
## Dei non impilabili toglie le istanze più recenti. Emette `item_removed` (e libera spazio nel Deposito).
func discard(def_id: String, qty: int) -> int:
	var n := mini(qty, discardable_count(def_id))
	if n <= 0:
		return 0
	if state.stacks.has(def_id):
		var left := int(state.stacks[def_id]) - n
		if left > 0:
			state.stacks[def_id] = left
		else:
			state.stacks.erase(def_id)
			state.recent.erase(def_id)
	else:
		var victims: Array = []
		var i: int = state.instances.size() - 1
		while i >= 0 and victims.size() < n:
			var inst: Dictionary = state.instances[i]
			if inst.def == def_id and not bool(inst.locked) and not is_in_use(str(inst.uid)):
				victims.append(str(inst.uid))
			i -= 1
		for u in victims:
			_erase_instance(u)
		n = victims.size()
	_changed()
	ctx.events.item_removed.emit(def_id, n)
	return n


## Oggetti «apribili» (Nido d'Uccello, Tesoro Sommerso: campo `open_table` -> data/loot_tables.json). Apre UNA unità:
## `rolls` estrazioni pesate dalla tabella (+ oro nell'intervallo `gold` se presente). Probabilità e quantità sono nei dati;
## il flusso RNG è `loot`. Ritorna {"gold": int, "items": [{"item","qty"}]} oppure {} se non si può aprire (assente o
## Deposito pieno non è un motivo: le estrazioni che non entrano vanno nel Carro di Ritiro).
func open_item(def_id: String) -> Dictionary:
	var table_id := str(ctx.data.item(def_id).get("open_table", ""))
	var table: Dictionary = ctx.data.get_def("loot_tables", table_id)
	if table.is_empty() or count(def_id) <= 0:
		return {}
	var rolls := int(table.get("rolls", 1))
	if not remove(def_id, 1):
		return {}
	var entries: Array = table.get("entries", [])
	var weights: Array = []
	for e in entries:
		weights.append(float(e.get("weight", 0)))
	var out := {"gold": 0, "items": []}
	var g: Variant = table.get("gold")
	if g is Array and g.size() == 2:
		out.gold = ctx.rng.randi_range("loot", int(g[0]), int(g[1]))
		add_gold(int(out.gold))
	for _r in rolls:
		var idx := ctx.rng.weighted_index("loot", weights)
		if idx < 0:
			continue
		var e: Dictionary = entries[idx]
		var q: Variant = e.get("qty", 1)
		var n := int(q) if not (q is Array) else ctx.rng.randi_range("loot", int(q[0]), int(q[1]))
		var item := str(e.item)
		if str(ctx.data.item(item).get("category", "")) == "crate":
			var crates := ctx.get_system("crates")
			if crates != null:
				crates.call("grant_crate", item, n)
		else:
			add(item, n, "open")
		out.items.append({"item": item, "qty": n})
	ctx.events.notice.emit("success", Loc.tf("UI_BANK_OPEN_DONE", {"name": Loc.t(ctx.data.item(def_id).get("name", def_id))}), {"item": def_id})
	return out


## Scarta una singola istanza (se non bloccata e non in uso).
func discard_instance(uid: String) -> bool:
	var inst: Dictionary = _by_uid.get(uid, {})
	if inst.is_empty() or bool(inst.get("locked", false)) or is_in_use(uid):
		return false
	if str(ctx.data.item(str(inst.def)).get("category", "")) == "quest":
		return false
	return remove_instance(uid)


## L'istanza è in uso: equipaggiata (eroe o attrezzo, sistema combat) o nel Guardaroba/Reliquiario (crates).
## Le istanze in uso non si vendono e si consumano per ultime.
func is_in_use(uid: String) -> bool:
	var cb := ctx.get_system("combat")
	if cb != null and cb.has_method("is_equipped") and bool(cb.call("is_equipped", uid)):
		return true
	var cr := ctx.get_system("crates")
	if cr != null and cr.state is Dictionary:
		var st: Dictionary = cr.state
		if (st.get("wardrobe", {}) as Dictionary).values().has(uid) or (st.get("reliquary", []) as Array).has(uid):
			return true
	return false


## Pila «in uso»: il cibo assegnato agli slot dell'eroe (la regola di vendita automatica «Cibo» non deve lasciarlo senza
## scorte, QA82 B10). Come is_in_use() per le istanze, ma per definizione.
func is_def_in_use(def_id: String) -> bool:
	var cb := ctx.get_system("combat")
	if cb != null and cb.has_method("food_slots"):
		return (cb.call("food_slots") as Array).has(def_id)
	return false


# ------------------------------------------------------------------ istanze

## Aggiunge un'istanza (oggetto non impilabile con qualità, incastri, grado). Assegna e ritorna l'uid;
## OVERFLOW_UID se il Deposito è pieno e il pezzo è finito nel Carro (o venduto oltre il tetto), "" se la definizione è
## sconosciuta. I campi mancanti hanno valori predefiniti.
func add_instance(inst: Dictionary) -> String:
	var def_id := _inst_def(inst)
	if not ctx.data.has_item(def_id):
		push_warning("BankSystem.add_instance: oggetto sconosciuto " + def_id)
		return ""
	if free_for(def_id) <= 0:              # Carro di Ritiro (per classe, F15): nessun premio si perde, nessuna apertura si ferma (resoconto 117)
		_stash_instance(inst)
		_changed()
		ctx.events.item_gained.emit(def_id, 1, str(inst.get("source", "")))
		return OVERFLOW_UID
	var uid := _insert_instance(inst)
	_changed()
	ctx.events.item_gained.emit(def_id, 1, str(inst.get("source", "")))
	return uid


## L'istanza VIVA (modificarla solo con i metodi di questo sistema) o {} se non esiste.
func get_instance(uid: String) -> Dictionary:
	return _by_uid.get(uid, {})


func remove_instance(uid: String) -> bool:
	if not _by_uid.has(uid):
		return false
	var def_id: String = _by_uid[uid].def
	_erase_instance(uid)
	_changed()
	ctx.events.item_removed.emit(def_id, 1)
	return true


## Copia superficiale dell'elenco (le istanze sono quelle vive).
func list_instances() -> Array:
	return state.instances.duplicate()


func instance_count() -> int:
	return state.instances.size()


# ------------------------------------------------------------------ blocco

func is_def_locked(def_id: String) -> bool:
	return bool(state.locked_defs.get(def_id, false))


## Blocca/sblocca una pila (oggetto impilabile) per id di definizione.
func set_def_locked(def_id: String, locked: bool) -> void:
	if locked:
		if not state.stacks.has(def_id):
			return
		state.locked_defs[def_id] = true
	else:
		state.locked_defs.erase(def_id)
	_changed()


func is_instance_locked(uid: String) -> bool:
	return bool(_by_uid.get(uid, {}).get("locked", false))


func set_instance_locked(uid: String, locked: bool) -> void:
	if _by_uid.has(uid):
		_by_uid[uid]["locked"] = locked
		_changed()


## Rango dell'istanza (G03): lo decide PrestigeSystem.do_rank_up (costi e tetto), qui solo la scrittura.
func set_instance_rank(uid: String, rank: int) -> void:
	if _by_uid.has(uid):
		_by_uid[uid]["rank"] = maxi(0, rank)
		_changed()


# ------------------------------------------------------------------ valute

func is_currency(currency_id: String) -> bool:
	return currency_id == GOLD or str(ctx.data.item(currency_id).get("category", "")) == CATEGORY_CURRENCY


func gold() -> int:
	return currency(GOLD)


func add_gold(n: int) -> void:
	add_currency(GOLD, n)


func spend_gold(n: int) -> bool:
	return spend_currency(GOLD, n)


func currency(currency_id: String) -> int:
	return int(ctx.state.currencies.get(currency_id, 0))


func add_currency(currency_id: String, n: int) -> void:
	if n <= 0 or not is_currency(currency_id):
		return
	var total := sat_add(currency(currency_id), n)
	ctx.state.currencies[currency_id] = total
	_changed()
	ctx.events.currency_changed.emit(currency_id, total)


func spend_currency(currency_id: String, n: int) -> bool:
	if n < 0 or currency(currency_id) < n:
		return false
	if n == 0:
		return true
	var total := currency(currency_id) - n
	ctx.state.currencies[currency_id] = total
	_changed()
	ctx.events.currency_changed.emit(currency_id, total)
	return true


## Valute con saldo > 0 (oro sempre incluso, per primo), ordinate per tier e id.
func currency_ids() -> PackedStringArray:
	var out: Array = []
	for k in ctx.state.currencies:
		if k != GOLD and int(ctx.state.currencies[k]) > 0:
			out.append(k)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ta := int(ctx.data.item(a).get("tier", 0))
		var tb := int(ctx.data.item(b).get("tier", 0))
		return ta < tb if ta != tb else a < b)
	return PackedStringArray([GOLD] + out)


# ------------------------------------------------------------------ valore e ordinamento

## Valore base totale del Deposito (somma di value × quantità; docs/07 §7). In cache fino alla prossima modifica.
func total_value() -> float:
	if _value_cache >= 0.0:
		return _value_cache
	var v := 0.0
	for def_id in state.stacks:
		v += float(ctx.data.item(def_id).get("value", 0)) * float(state.stacks[def_id])
	for def_id in _def_count:
		v += float(ctx.data.item(def_id).get("value", 0)) * float(_def_count[def_id])
	_value_cache = v
	return v


## Ordine di inserimento di una pila (per «recenti»): più alto = più recente. 0 se assente.
func recency_of_stack(def_id: String) -> int:
	return int(state.recent.get(def_id, 0))


# ------------------------------------------------------------------ interni

## Id della definizione di un'istanza: "def" (forma del Deposito) o "def_id" (forma delle Casse, CrateSystem).
static func _inst_def(inst: Dictionary) -> String:
	return str(inst.get("def", inst.get("def_id", "")))


func _insert_instance(src: Dictionary) -> String:
	var uid := UID_FORMAT % int(state.next_uid)
	state.next_uid = int(state.next_uid) + 1
	var q: Array = ctx.constants().get("quality", [])
	var inst := {}
	# i campi degli altri sistemi restano nell'istanza (Casse: def_id, rarity, condition, float, seed, phase…)
	for k in src:
		if k != "uid" and k != "source":
			var v: Variant = src[k]
			inst[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	inst.merge({
		"uid": uid,
		"def": _inst_def(src),
		"quality": str(src.get("quality", q[0].id if not q.is_empty() else "")),
		"sockets": Array(src.get("sockets", [])).duplicate(),
		"rank": int(src.get("rank", 0)),
		"locked": bool(src.get("locked", false)),
	}, true)
	state.instances.append(inst)
	if is_gear_def(str(inst.def)):
		_gear_n += 1
	_by_uid[uid] = inst
	_def_count[inst.def] = int(_def_count.get(inst.def, 0)) + 1
	return uid


func _erase_instance(uid: String) -> void:
	var inst: Dictionary = _by_uid[uid]
	_by_uid.erase(uid)
	var n := int(_def_count.get(inst.def, 0)) - 1
	if n > 0:
		_def_count[inst.def] = n
	else:
		_def_count.erase(inst.def)
	var idx: int = state.instances.rfind(inst)
	if idx >= 0:
		state.instances.remove_at(idx)
		if is_gear_def(str(inst.def)):
			_gear_n = maxi(0, _gear_n - 1)
	if state.has("tab_of"):
		(state.tab_of as Dictionary).erase("u:" + uid)       # F17: l'istanza sparita non resta assegnata (le pile sì: appiccicose)


func _touch_recent(def_id: String) -> void:
	state.recent[def_id] = int(state.next_uid)      # stesso contatore degli uid: ordinabile insieme alle istanze
	state.next_uid = int(state.next_uid) + 1


func _changed() -> void:
	revision += 1
	_value_cache = -1.0


func _reindex() -> void:
	_by_uid.clear()
	_def_count.clear()
	_gear_n = 0
	var max_uid := 0
	for inst in state.instances:
		if not inst.has("def"):
			inst["def"] = _inst_def(inst)
		if is_gear_def(str(inst.def)):
			_gear_n += 1
		_by_uid[inst.uid] = inst
		_def_count[inst.def] = int(_def_count.get(inst.def, 0)) + 1
		max_uid = maxi(max_uid, str(inst.uid).trim_prefix("i_").to_int())
	state.next_uid = maxi(int(state.next_uid), max_uid + 1)     # sicurezza: mai riusare un uid esistente
	_changed()


func _notice_full(def_id: String) -> void:
	var names: Dictionary = ctx.data.item(def_id).get("name", {})
	var lang := TranslationServer.get_locale().substr(0, 2)
	var name_text := str(names.get(lang, names.get("en", def_id)))
	ctx.events.notice.emit("warning", tr("UI_BANK_FULL_NOTICE").format({"item": name_text}), {"def_id": def_id, "reason": "bank_full", "item": name_text})


## Regalo di nuova partita: SOLO dai dati (constants.new_game_gift = {"gold": n, "items": [{"item", "qty"}]}).
## Assente nei dati attuali (docs/03 e docs/12 non prevedono oggetti o oro di partenza: l'oro arriva dalla
## prima missione del Prologo). Consegnato una volta sola, e solo a una partita ancora a tempo di gioco zero.
func _apply_new_game_gift() -> void:
	if bool(state.gift_done):
		return
	state.gift_done = true
	if float(ctx.state.get("stats", {}).get("playtime_s", 0.0)) > 0.0:
		return
	var gift: Variant = ctx.data.constants.get("new_game_gift", {})
	if not (gift is Dictionary):
		return
	if int(gift.get("gold", 0)) > 0:
		add_gold(int(gift.gold))
	for e in gift.get("items", []):
		add(str(e.item), int(e.qty), "gift")


# ------------------------------------------------------------------ doppioni, riciclo, avviso (feedback giocatore 23/10/2026)
## Attrezzi e pezzi uguali non occupano il Deposito in eterno: «Vendi i doppioni» e il riciclo dei doppioni di una vecchia
## partita. Numeri (soglia di avviso, % di riciclo, categorie riciclabili) da constants.bank (tools/gamedata/core.py::BANK_RULES).

func _bank_rules() -> Dictionary:
	var r: Variant = ctx.data.constants.get("bank", {})
	return r if r is Dictionary else {}


## Questa definizione si ricicla in oro (senza Mercato) quando è un doppione? Oggi: gli attrezzi di mansione.
func is_recyclable(def_id: String) -> bool:
	var cats: Array = _bank_rules().get("recycle_dupe_categories", [])
	return cats.has(str(ctx.data.item(def_id).get("category", "")))


## Oro del riciclo di un pezzo: valore × constants.bank.recycle_pct.
func recycle_value(def_id: String) -> int:
	return roundi(float(ctx.data.item(def_id).get("value", 0)) * float(_bank_rules().get("recycle_pct", 0)) / 100.0)


## Il pezzo può essere considerato doppione? Mai bloccato, unico, con grado o con incastri.
func _dupe_candidate(inst: Dictionary, def: Dictionary) -> bool:
	if bool(inst.get("locked", false)) or bool(def.get("unique", false)):
		return false
	if int(inst.get("rank", 0)) > 0:
		return false
	for sk in inst.get("sockets", []):
		if sk != null and str(sk) != "":
			return false
	return true


## Uid dei doppioni: per ogni definizione con 2+ istanze se ne tiene UNA (prima quella bloccata o in uso, poi quella di
## qualità più alta, poi la più vecchia) e le altre sono doppioni se candidabili. Solo equipaggiamento e attrezzi.
## `worn`: uid da considerare in uso (la migrazione al caricamento non può ancora chiedere al combattimento); se vuoto,
## «in uso» lo decide is_in_use().
func duplicate_uids(worn: Dictionary = {}) -> Array:
	var in_use_all := worn if not worn.is_empty() else in_use_set()      # una passata, non is_in_use() per ogni pezzo
	var by_def: Dictionary = {}
	for inst in state.instances:
		var cat := str(ctx.data.item(str(inst.def)).get("category", ""))
		if cat == "equipment" or cat == "tool":
			if not by_def.has(inst.def):
				by_def[inst.def] = []
			by_def[inst.def].append(inst)
	var q_ids: Array = []
	for qd in ctx.constants().get("quality", []):
		q_ids.append(str(qd.id))
	var out: Array = []
	for d in by_def:
		var list: Array = by_def[d]
		if list.size() < 2:
			continue
		var def: Dictionary = ctx.data.item(str(d))
		var keep: Dictionary = {}
		for inst in list:                              # chi è già al sicuro resta (e basta a sé stesso)
			if bool(inst.get("locked", false)) or in_use_all.has(str(inst.uid)):
				keep = inst
				break
		if keep.is_empty():
			var best := -1
			for inst in list:
				var qi := q_ids.find(str(inst.get("quality", "")))
				if qi > best:
					best = qi
					keep = inst
		for inst in list:
			if inst == keep or not _dupe_candidate(inst, def) or in_use_all.has(str(inst.uid)):
				continue
			out.append(str(inst.uid))
	return out


## Come is_in_use() per tutti gli uid insieme (una sola passata invece di una per pezzo). {} se nulla è in uso.
func in_use_set() -> Dictionary:
	var out: Dictionary = {}
	var cb := ctx.get_system("combat")
	if cb != null and cb.has_method("equipped_uid_set"):
		out = cb.call("equipped_uid_set")
	elif cb != null and cb.has_method("is_equipped"):
		for inst in state.instances:                         # ripiego per sistemi di prova senza l'insieme
			if bool(cb.call("is_equipped", str(inst.uid))):
				out[str(inst.uid)] = true
	var cr := ctx.get_system("crates")
	if cr != null and cr.state is Dictionary:
		for u in ((cr.state as Dictionary).get("wardrobe", {}) as Dictionary).values():
			out[str(u)] = true
		for u in (cr.state as Dictionary).get("reliquary", []) as Array:
			out[str(u)] = true
	return out


## Ricicla istanze in oro (`recycle_value`), senza passare dal Mercato. Salta bloccate e in uso. Ritorna l'oro dato.
func recycle_instances(uids: Array) -> int:
	var paid := 0
	for u in uids:
		var inst: Dictionary = _by_uid.get(str(u), {})
		if inst.is_empty() or bool(inst.get("locked", false)) or is_in_use(str(u)):
			continue
		var g := recycle_value(str(inst.def))
		if remove_instance(str(u)):
			paid += g
	if paid > 0:
		add_gold(paid)
	return paid


## Migrazione al caricamento: gli attrezzi doppioni di un vecchio salvataggio (Forgiatura ripetuta) si riciclano in oro pari
## al loro valore; resta l'attrezzo in uso (o bloccato, o il migliore). Nessuna perdita: pezzi uguali, senza stato proprio.
func _recycle_loaded_duplicates() -> void:
	var worn: Dictionary = {}
	var eqs: Variant = ctx.state.get("equipment", {})
	if eqs is Dictionary:
		for slot in eqs:
			var v: Variant = eqs[slot]
			if v is String and str(v) != "":
				worn[str(v)] = true
			elif v is Dictionary:
				for k in v:
					if v[k] is String and str(v[k]) != "":
						worn[str(v[k])] = true
	if worn.is_empty():
		worn["~"] = true                               # mappa non vuota: «nessuno in uso noto», non «chiedi al combattimento»
	var victims: Array = []
	for u in duplicate_uids(worn):
		if is_recyclable(str(_by_uid[u].def)):
			victims.append(u)
	if victims.is_empty():
		return
	var paid := 0
	for u in victims:
		paid += recycle_value(str(_by_uid[u].def))
		_erase_instance(str(u))
	add_gold(paid)
	_changed()
	_migr_report = {"pieces": victims.size(), "gold": paid}


## Avviso «Deposito quasi pieno»: una volta sola quando i posti usati raggiungono constants.bank.warn_pct, di nuovo solo dopo
## essere scesi sotto. Mai una perdita: dice cosa fare (Vendi i doppioni, Vendita automatica, Scarta).
func nearly_full() -> bool:
	var cap := capacity()
	return cap > 0 and not is_full() and float(used_slots()) * 100.0 >= float(cap) * float(_bank_rules().get("warn_pct", 100))


func _check_warn() -> void:
	var now := nearly_full()
	if now and not _warned:
		ctx.events.notice.emit("warning", Loc.tf("UI_BANK_NEARLY_FULL", {"used": used_slots(), "cap": capacity()}),
			{"reason": "bank_nearly_full", "section": "bank"})
	_warned = now or is_full()
	var gnow := gear_nearly_full()                  # Armeria: un avviso proprio, una volta sola a gear_warn_pct (R-SP-6)
	if gnow and not _gear_warned:
		ctx.events.notice.emit("warning", Loc.tf("UI_BANKG_ARMORY_NEARLY", {"used": gear_used(), "cap": gear_cap()}),
			{"reason": "armory_nearly_full", "section": "bank"})
	_gear_warned = gnow or gear_is_full()


# ------------------------------------------------------------------ schede del giocatore (F17, docs/ui_redesign/02 §4.3, §5.1)
## Le schede organizzano soltanto: non danno capacità, non costano nulla, non spostano quantità. «Tutto» e «Armeria» sono viste
## fisse dell'interfaccia (non stanno qui). Limiti e tetti dai dati (constants.bank.ui), mai nel codice.

func ui_rules() -> Dictionary:
	var r: Variant = _bank_rules().get("ui", {})
	return r if r is Dictionary else {}


func max_tabs() -> int:
	return int(ui_rules().get("max_tabs", 0))


func tab_name_max() -> int:
	return maxi(1, int(ui_rules().get("tab_name_max", 1)))


func tab_of_cap() -> int:
	return int(ui_rules().get("tab_of_cap", 0))


## Schede nell'ordine della barra (gli Dictionary sono quelli vivi: modificarli solo con i metodi qui sotto).
func tabs() -> Array:
	return state.tabs


func tab_count() -> int:
	return (state.tabs as Array).size()


func can_add_tab() -> bool:
	return tab_count() < max_tabs()


func get_tab(tab_id: String) -> Dictionary:
	for t in state.tabs:
		if str(t.id) == tab_id:
			return t
	return {}


func tab_index(tab_id: String) -> int:
	for i in (state.tabs as Array).size():
		if str(state.tabs[i].id) == tab_id:
			return i
	return -1


## Chiave di assegnazione di una voce del Deposito: «u:<uid>» per un'istanza, «s:<def_id>» per una pila.
static func tab_key(def_id: String, uid: String) -> String:
	return "u:" + uid if uid != "" else "s:" + def_id


## Nome ripulito (R10 del doc 02): niente caratteri di controllo né parentesi o segni di markup, spazi compattati, al più
## `max_len` caratteri. Ritorna "" se non resta nulla (nome non valido). Il nome si mostra solo in Label, mai in RichTextLabel.
static func sanitize_tab_name(text: String, max_len: int) -> String:
	var out := ""
	var space := false
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 32 or (c >= 127 and c < 160) or c == 0x2028 or c == 0x2029 or c == 0xFEFF or (c >= 0x200B and c <= 0x200F):
			c = 32                                     # controllo, a capo, larghezza zero: diventano uno spazio
		if c == 91 or c == 93 or c == 123 or c == 125 or c == 60 or c == 62:      # [ ] { } < >: nessun markup né segnaposto
			continue
		if c == 32:
			space = true
			continue
		if space and not out.is_empty():
			out += " "
		space = false
		out += String.chr(c)
	return out.substr(0, maxi(1, max_len)).strip_edges()


## Nome unico senza distinzione di maiuscole (suffisso « 2», « 3»…, accorciando la base se serve). `except_id` = la scheda che
## si sta rinominando (può tenere il suo stesso nome).
func unique_tab_name(name_text: String, except_id: String = "", among: Variant = null) -> String:
	var lim := tab_name_max()
	var taken: Dictionary = {}
	for t in (among as Array if among is Array else state.tabs as Array):
		if str(t.id) != except_id:
			taken[str(t.name).to_lower()] = true
	if not taken.has(name_text.to_lower()):
		return name_text
	var n := 2
	while n < 1000:
		var suffix := " %d" % n
		var cand := name_text.substr(0, maxi(1, lim - suffix.length())).strip_edges() + suffix
		if not taken.has(cand.to_lower()):
			return cand
		n += 1
	return name_text


func _valid_icon(def_id: String) -> String:
	return def_id if def_id != "" and ctx.data.has_item(def_id) else ""


## Crea una scheda in fondo alla barra. Ritorna il suo id, oppure "" se il limite è raggiunto o il nome non è valido.
func create_tab(name_text: String, icon_def: String = "") -> String:
	if not can_add_tab():
		return ""
	var nm := sanitize_tab_name(name_text, tab_name_max())
	if nm.is_empty():
		return ""
	var tid := TAB_ID_FORMAT % int(state.next_tab)
	state.next_tab = int(state.next_tab) + 1
	state.tabs.append({"id": tid, "name": unique_tab_name(nm), "icon": _valid_icon(icon_def), "sort": TAB_SORT_DEFAULT.duplicate()})
	_changed()
	return tid


func rename_tab(tab_id: String, name_text: String) -> bool:
	var t := get_tab(tab_id)
	var nm := sanitize_tab_name(name_text, tab_name_max())
	if t.is_empty() or nm.is_empty():
		return false
	t["name"] = unique_tab_name(nm, tab_id)
	_changed()
	return true


func set_tab_icon(tab_id: String, icon_def: String) -> bool:
	var t := get_tab(tab_id)
	if t.is_empty() or (icon_def != "" and _valid_icon(icon_def).is_empty()):
		return false
	t["icon"] = icon_def
	_changed()
	return true


func set_tab_sort(tab_id: String, sort_id: String, desc: bool) -> bool:
	var t := get_tab(tab_id)
	if t.is_empty() or not TAB_SORTS.has(sort_id):
		return false
	t["sort"] = {"id": sort_id, "desc": desc}
	_changed()
	return true


## Sposta la scheda di `delta` posizioni (-1 = a sinistra). Ritorna true se si è mossa.
func move_tab(tab_id: String, delta: int) -> bool:
	var i := tab_index(tab_id)
	var j := i + delta
	if i < 0 or j < 0 or j >= tab_count() or delta == 0:
		return false
	var t: Dictionary = state.tabs[i]
	state.tabs.remove_at(i)
	state.tabs.insert(j, t)
	_changed()
	return true


## Elimina la scheda: cancella SOLO le assegnazioni (le voci tornano in «Tutto»; nessun oggetto si perde). Ritorna quante
## assegnazioni ha tolto.
func delete_tab(tab_id: String) -> int:
	var i := tab_index(tab_id)
	if i < 0:
		return 0
	state.tabs.remove_at(i)
	var n := 0
	for k in (state.tab_of as Dictionary).keys():
		if str(state.tab_of[k]) == tab_id:
			state.tab_of.erase(k)
			n += 1
	_changed()
	return n


## Scheda della voce ("" = nessuna).
func tab_of(key: String) -> String:
	return str((state.tab_of as Dictionary).get(key, ""))


## La voce si può mettere in una scheda? Pile (oggetti noti, impilabili, non valute) e istanze presenti che NON sono
## dell'Armeria (il gear si organizza con i filtri dell'Armeria, doc 02 §4.3).
func can_assign(key: String) -> bool:
	if key.begins_with("u:"):
		var inst: Dictionary = _by_uid.get(key.substr(2), {})
		return not inst.is_empty() and not is_gear_def(str(inst.def))
	if key.begins_with("s:"):
		return _stack_def_assignable(key.substr(2))
	return false


func _stack_def_assignable(def_id: String) -> bool:
	var def: Dictionary = ctx.data.item(def_id)
	return not def.is_empty() and bool(def.get("stackable", false)) and not is_currency(def_id) and not is_gear_def(def_id)


## Mette le voci `keys` nella scheda `tab_id` ("" = toglie dalla scheda: tornano solo in «Tutto»). Una voce sta in una sola
## scheda: l'assegnazione nuova sostituisce la vecchia. Non muta quantità. Ritorna quante voci sono state assegnate/tolte.
func assign_to_tab(keys: Array, tab_id: String) -> int:
	if tab_id != "" and tab_index(tab_id) < 0:
		return 0
	var n := 0
	for k in keys:
		var key := str(k)
		if not can_assign(key):
			continue
		if tab_id == "":
			if (state.tab_of as Dictionary).has(key):
				state.tab_of.erase(key)
				n += 1
			continue
		if not (state.tab_of as Dictionary).has(key) and not _tab_of_room():
			break
		state.tab_of[key] = tab_id
		n += 1
	if n > 0:
		_changed()
	return n


## C'è posto per un'assegnazione nuova? Al tetto si scartano prima le pile esaurite (ordine alfabetico: deterministico).
func _tab_of_room() -> bool:
	var cap := tab_of_cap()
	var tof: Dictionary = state.tab_of
	if cap <= 0 or tof.size() < cap:
		return true
	var gone: Array = []
	for k in tof:
		var d := str(k).substr(2)
		if str(k).begins_with("s:") and not state.stacks.has(d) and not state.overflow_stacks.has(d):
			gone.append(str(k))
	gone.sort()
	var i := 0
	while tof.size() >= cap and i < gone.size():
		tof.erase(gone[i])
		i += 1
	return tof.size() < cap


## Voci PRESENTI per scheda ({tab id: caselle}), in una passata: il numero della barra conta le caselle, non le quantità.
func tab_counts() -> Dictionary:
	var out: Dictionary = {}
	for t in state.tabs:
		out[str(t.id)] = 0
	for k in state.tab_of:
		var key := str(k)
		var tid := str(state.tab_of[k])
		var present: bool = state.stacks.has(key.substr(2)) if key.begins_with("s:") else _by_uid.has(key.substr(2))
		if present and out.has(tid):
			out[tid] = int(out[tid]) + 1
	return out


func tabs_intro_done() -> bool:
	return bool(state.get("tabs_intro_done", false))


func mark_tabs_intro_done() -> void:
	state["tabs_intro_done"] = true


## Caricamento tollerante (regola 7): schede oltre il limite, id doppi, nomi non validi, icone sconosciute, ordinamenti
## sbagliati, assegnazioni orfane o verso l'Armeria: tutto si ripulisce senza toccare un solo oggetto. Una riga nel Registro.
func _clean_tabs_on_load() -> void:
	var dirty := false
	var seen: Dictionary = {}
	var kept: Array = []
	var max_id := 0
	for t in state.tabs:
		if not (t is Dictionary) or not ((t as Dictionary).get("id") is String) or str(t.id).is_empty() or seen.has(str(t.id)):
			dirty = true
			continue
		if kept.size() >= max_tabs():
			dirty = true
			continue
		var td: Dictionary = t
		var tid := str(td.id)
		var raw_name: Variant = td.get("name", "")
		var nm := sanitize_tab_name(str(raw_name) if raw_name is String else "", tab_name_max())
		if nm.is_empty():
			nm = Loc.tf("UI_BANKG_TAB_DEFAULT_N", {"n": kept.size() + 1})
		var raw_icon: Variant = td.get("icon", "")
		var icon := _valid_icon(str(raw_icon)) if raw_icon is String else ""
		var so: Variant = td.get("sort", {})
		var sort: Dictionary = TAB_SORT_DEFAULT.duplicate()
		if so is Dictionary and TAB_SORTS.has(str((so as Dictionary).get("id", ""))) and (so as Dictionary).get("desc") is bool:
			sort = {"id": str(so.id), "desc": bool(so.desc)}
		var un := unique_tab_name(nm, "", kept)
		var clean := {"id": tid, "name": un, "icon": icon, "sort": sort}
		if JSON.stringify(clean, "", true) != JSON.stringify(td, "", true):
			dirty = true
		kept.append(clean)
		seen[tid] = true
		if tid.begins_with("t_") and tid.substr(2).is_valid_int():
			max_id = maxi(max_id, tid.substr(2).to_int())
	state.tabs = kept
	state.next_tab = maxi(int(state.next_tab), max_id + 1)
	var tof: Dictionary = state.tab_of
	for k in tof.keys():
		var ok: bool = (k is String) and (tof[k] is String) and seen.has(str(tof[k]))
		var key := str(k)
		if ok and key.begins_with("u:"):
			ok = can_assign(key)                        # istanza presente e non dell'Armeria
		elif ok and key.begins_with("s:"):
			ok = _stack_def_assignable(key.substr(2))   # appiccicosa: la pila può essere esaurita, ma l'oggetto deve esistere
		else:
			ok = false
		if not ok:
			tof.erase(k)
			dirty = true
	var cap := tab_of_cap()
	if cap > 0 and tof.size() > cap:
		_tab_of_room()
		var ks: Array = tof.keys()
		ks.sort()
		while tof.size() > cap and not ks.is_empty():   # ancora oltre: si tolgono le ultime in ordine alfabetico
			tof.erase(ks.pop_back())
		dirty = true
	if dirty:
		_tabs_cleaned = true


# ------------------------------------------------------------------ ricerca nel Deposito (F17, docs/ui_redesign/02 §5.7)
## Funzioni pure e statiche (scheda «Risultati» di BankScreen, finestra delle icone): minuscolo e senza accenti, parole in
## AND, operatori facoltativi cat: t: lock: q: rar:. Qui e non nella UI: si compilano con il sistema, non all'apertura.

const _SEARCH_ACCENTS := {"à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ù": "u", "ú": "u", "û": "u",
	"ü": "u", "ñ": "n", "ç": "c", "ß": "ss", "’": "'"}
const SEARCH_OPS: PackedStringArray = ["cat", "t", "lock", "q", "rar"]


## Testo normalizzato per la ricerca: minuscolo, senza accenti, spazi compattati.
static func search_norm(text: String) -> String:
	var low := text.to_lower()
	var out := ""
	for i in low.length():
		var ch := low[i]
		out += str(_SEARCH_ACCENTS.get(ch, ch))
	return " ".join(out.split(" ", false))


static func _search_stem(v: String) -> String:
	var s := v
	while s.length() > 3 and "aeiou".contains(s[s.length() - 1]):
		s = s.substr(0, s.length() - 1)
	return s


## `value` (scritto dal giocatore) corrisponde a `label`? Prefisso, tollerante a singolare/plurale («materiale» ~ «materiali»).
static func search_soft_match(value: String, label: String) -> bool:
	if value.is_empty() or label.is_empty():
		return false
	var st := _search_stem(value)
	for w in ([label] + Array(label.split(" ", false))):
		var ws := str(w)
		if ws.begins_with(st) or value.begins_with(ws) or ws.begins_with(value):
			return true
	return false


## Interpreta la ricerca. `names` = {"cat": {id: [etichette]}, "q": {id: [etichette]}, "rar": {id: [etichette]}} già
## normalizzate (più "<op>_group", nomi di ripiego usati solo se i primi non trovano nulla). Ritorna {words: [], ops: {op: insieme di id | valore}}; un operatore che non corrisponde a nulla ha
## l'insieme vuoto (e quindi nessun risultato, come ci si aspetta).
static func parse_search(text: String, names: Dictionary) -> Dictionary:
	var out := {"words": [], "ops": {}}
	for tok in search_norm(text).split(" ", false):
		var t := str(tok)
		var c := t.find(":")
		var op := t.substr(0, c) if c > 0 else ""
		if not SEARCH_OPS.has(op):
			(out.words as Array).append(t)
			continue
		var v := t.substr(c + 1)
		match op:
			"t":
				out.ops["t"] = v.to_int() if v.is_valid_int() else -1
			"lock":
				out.ops["lock"] = not (v == "no" or v == "0" or v == "off")
			_:
				var ids := _search_ids(v, names.get(op, {}))
				if ids.is_empty():                          # ripiego: i nomi dei gruppi (es. «Materiali» = materiali e semi)
					ids = _search_ids(v, names.get(op + "_group", {}))
				out.ops[op] = ids
	return out


static func _search_ids(v: String, table: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	for id in table:
		if v.is_empty() or search_soft_match(v, str(id)):
			ids[id] = true
			continue
		for lab in table[id]:
			if search_soft_match(v, str(lab)):
				ids[id] = true
				break
	return ids


## La voce passa la ricerca? `e` = {name (normalizzato), cat, tier, locked, q (qualità), rar (rarità)}.
static func search_matches(pq: Dictionary, e: Dictionary) -> bool:
	for w in pq.words:
		if not str(e.get("name", "")).contains(str(w)):
			return false
	var ops: Dictionary = pq.ops
	if ops.has("cat") and not (ops.cat as Dictionary).has(str(e.get("cat", ""))):
		return false
	if ops.has("t") and int(e.get("tier", 0)) != int(ops.t):
		return false
	if ops.has("lock") and bool(e.get("locked", false)) != bool(ops.lock):
		return false
	if ops.has("q") and not (ops.q as Dictionary).has(str(e.get("q", ""))):
		return false
	if ops.has("rar") and not (ops.rar as Dictionary).has(str(e.get("rar", ""))):
		return false
	return true
