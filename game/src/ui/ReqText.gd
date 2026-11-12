class_name ReqText
extends RefCounted
## Testi dei requisiti con le QUANTITÀ: quanto serve, quanto hai, quanto manca (feedback giocatore: «Ti manca questo» senza dire
## quanto). Solo presentazione: legge Loc/NumberFormat e il Deposito, nessuna regola di gioco, nessun numero di bilanciamento.
## Tutti i testi sono chiavi UI_MSK_* del CSV (IT/EN). Gli ingredienti arrivano dai dati dell'azione ({item, qty}).

const WARN := "#e0c070"             ## colore di avvertimento (ambra, come «Mancano…» della Tenuta: il rosso è solo pericolo)


static func item_name(item_id: String) -> String:
	return Loc.t(DataRegistry.item(item_id).get("name", item_id))


static func owned(item_id: String) -> int:
	var bank: Object = Game.system("bank")
	return int(bank.count(item_id)) if bank != null else 0


## Quantità o intervallo dei dati («1» oppure «1–3»).
static func qty_text(q: Variant) -> String:
	if q is Array and (q as Array).size() >= 2 and int(q[0]) != int(q[1]):
		return "%s–%s" % [NumberFormat.fmt(float(q[0])), NumberFormat.fmt(float(q[1]))]
	if q is Array and not (q as Array).is_empty():
		return NumberFormat.fmt(float(q[0]))
	return NumberFormat.fmt(float(q))


## «2× Carbone (hai 14)» oppure, se non bastano, «60× Lino (hai 48, ne mancano 12)».
static func piece(item_id: String, need: int, have: int) -> String:
	if have >= need:
		return Loc.tf("UI_MSK_PIECE", {"need": NumberFormat.fmt(float(need)), "item": item_name(item_id), "have": NumberFormat.fmt(float(have))})
	return Loc.tf("UI_MSK_PIECE_SHORT", {"need": NumberFormat.fmt(float(need)), "item": item_name(item_id),
		"have": NumberFormat.fmt(float(have)), "miss": NumberFormat.fmt(float(need - have))})


## «Ti mancano 12 Lino: ne servono 60, ne hai 48» (singolare per 1).
static func missing_sentence(item_id: String, need: int, have: int) -> String:
	var miss := maxi(0, need - have)
	return Loc.tf("UI_MSK_MISSING_ONE" if miss == 1 else "UI_MSK_MISSING_MANY", {"n": NumberFormat.fmt(float(miss)),
		"item": item_name(item_id), "need": NumberFormat.fmt(float(need)), "have": NumberFormat.fmt(float(have))})


## Ingredienti [{item, qty}] che non bastano, nell'ordine dei dati: [{item, need, have}].
static func short_inputs(inputs: Array) -> Array:
	var out: Array = []
	for io in inputs:
		var need := int(io.qty)
		var have := owned(str(io.item))
		if have < need:
			out.append({"item": str(io.item), "need": need, "have": have})
	return out


## Tutte le frasi di mancanza degli ingredienti, una per riga (vuoto se non manca nulla).
static func missing_inputs_text(inputs: Array) -> String:
	var lines := PackedStringArray()
	for s in short_inputs(inputs):
		lines.append(missing_sentence(str(s.item), int(s.need), int(s.have)))
	return "\n".join(lines)


## «Servono: 2× Carbone (hai 14) · 60× Lino (hai 48, ne mancano 12)». Con `bbcode` i pezzi che non bastano sono ambra e (se
## `link` è true) cliccabili verso dove si ottengono; senza, testo semplice. Vuoto senza ingredienti.
static func inputs_text(inputs: Array, bbcode: bool = false, link: bool = true) -> String:
	if inputs.is_empty():
		return ""
	var parts := PackedStringArray()
	for io in inputs:
		var id := str(io.item)
		var need := int(io.qty)
		var have := owned(id)
		var p := piece(id, need, have)
		if bbcode:
			p = p.replace("[", "[lb]")             # i nomi non devono mai essere letti come BBCode
			if have < need:
				p = ReqLink.bbcode(p, ReqLink.target_for_item(id) if link else {}, WARN)
				if p.find("[url") < 0:
					p = "[color=%s]%s[/color]" % [WARN, p]
		parts.append(p)
	return Loc.tf("UI_SKILLS_INGREDIENTS", {"list": " · ".join(parts)})


## Livello richiesto e livello attuale: «Richiede livello 30 (il tuo: 25)».
static func level_text(req: int, cur: int) -> String:
	return Loc.tf("UI_MSK_LEVEL", {"req": req, "cur": cur})


## Come level_text, con il nome della mansione (avvisi): «Serve il livello 30 in Taglialegna: il tuo è 25».
static func level_sentence(skill_name: String, req: int, cur: int) -> String:
	return Loc.tf("UI_MSK_LEVEL_SENTENCE", {"skill": skill_name, "req": req, "cur": cur})


## Oro che manca: «Ti mancano 120 oro: ne servono 500, ne hai 380».
static func gold_sentence(need: int, have: int) -> String:
	return Loc.tf("UI_MSK_GOLD", {"n": NumberFormat.fmt(float(maxi(0, need - have))), "need": NumberFormat.fmt(float(need)),
		"have": NumberFormat.fmt(float(have))})
