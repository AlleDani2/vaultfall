class_name Hourglass
extends RefCounted
## Clessidra del Custode (docs/03 R-OFF-5, audit 71 G05): consuma `hourglass_1h` e applica SUBITO `hourglass.hours`
## ore di progresso offline all'AZIONE ATTIVA, con la stessa simulazione dell'offline vero (R-OFF-2/3: efficienza 100%).
## Logica pura (nessun nodo, nessun tempo reale); `Game.use_hourglass()` la chiama e mostra il Bentornato.
##
## LIMITI (chiari e mostrati dalla UI con il motivo):
##   - serve un'attività in corso tra quelle dei dati (`hourglass.activities`: "skill" = mansione, "zone" = combattimento
##     in una zona). Niente dungeon, incursioni, Breccia, boss mondiali: lì il tempo è parte della sfida;
##   - mai durante una Prova del Custode (si gioca contro le regole, non contro l'orologio);
##   - una Clessidra alla volta (1 h per uso); i sistemi che non riguardano l'attività (Tenuta, Orto, spedizioni,
##     timer dei buff, giorno del mercato...) NON avanzano: la Clessidra regala tempo all'azione, non al mondo.

const ITEM := "hourglass_1h"
## Sistemi che consumano il tempo per ciascun tipo di attività, nell'ordine di SystemRegistry.
const SYSTEMS_FOR := {"skill": ["skills", "queue"], "zone": ["combat"]}


static func _def(ctx: SystemContext) -> Dictionary:
	return ctx.data.item(ITEM).get("hourglass", {})


static func hours(ctx: SystemContext) -> float:
	return float(_def(ctx)["hours"])


static func owned(ctx: SystemContext) -> int:
	var b := ctx.get_system("bank")
	return int(b.call("count", ITEM)) if b != null else 0


## Tipo dell'attività in corso secondo la Clessidra: "skill", "zone", "other" (combattimenti speciali) o "" (nessuna).
static func activity_kind(ctx: SystemContext) -> String:
	var a: Variant = ctx.state.get("activity", {})
	if not (a is Dictionary) or (a as Dictionary).is_empty():
		return ""
	match str(a.get("type", "")):
		"skill":
			return "skill"
		"combat":
			var mode := str(a.get("mode", "zone"))
			return "zone" if mode == "zone" or mode.is_empty() else "other"
	return ""


## "" se la Clessidra si può usare adesso, altrimenti la chiave UI del motivo.
static func can_use(ctx: SystemContext) -> String:
	if owned(ctx) <= 0:
		return "UI_GAPM_HG_REASON_NONE"
	var pr := ctx.get_system("prestige")
	if pr != null and bool(pr.call("is_trial_active")):
		return "UI_GAPM_HG_REASON_TRIAL"
	var kind := activity_kind(ctx)
	if kind.is_empty():
		return "UI_GAPM_HG_REASON_IDLE"
	if not (_def(ctx).get("activities", []) as Array).has(kind):
		return "UI_GAPM_HG_REASON_ACTIVITY"
	return ""


## Anteprima per la UI: cosa farebbe la Clessidra ora.
static func preview(ctx: SystemContext) -> Dictionary:
	var reason := can_use(ctx)
	return {"kind": "hourglass", "ok": reason.is_empty(), "reason": reason, "owned": owned(ctx),
		"seconds": hours(ctx) * 3600.0, "activity": activity_kind(ctx)}


## Consuma una Clessidra e fa scorrere il tempo dei soli sistemi dell'attività. Ritorna
## {"ok": true, "seconds", "report"} (report nel formato di Simulation.run_offline + la riga "hourglass")
## oppure {"ok": false, "reason"}.
static func use(ctx: SystemContext) -> Dictionary:
	var reason := can_use(ctx)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var kind := activity_kind(ctx)
	var b := ctx.get_system("bank")
	if b == null or not bool(b.call("remove", ITEM, 1)):
		return {"ok": false, "reason": "UI_GAPM_HG_REASON_NONE"}
	var seconds := hours(ctx) * 3600.0
	var report := {}
	var sim := ctx.simulation()
	if sim != null:
		sim.offline_running = true          # audio in silenzio come nell'offline vero (docs/21 §4)
	for sid in SYSTEMS_FOR.get(kind, []):
		var gs := ctx.get_system(str(sid))
		if gs != null and gs.enabled:
			var r: Dictionary = gs.simulate_offline(seconds)
			if not r.is_empty():
				report[str(sid)] = r
	if sim != null:
		sim.offline_running = false
	if b != null:
		var fin: Dictionary = b.call("finish_offline")      # Carro di Ritiro: stesso resoconto dell'offline vero
		if not fin.is_empty():
			report["bank"] = fin
	report["hourglass"] = {"rows": [{"key": "UI_GAPM_HG_WB_ROW", "params": {"time": NumberFormat.fmt_time(seconds)}}]}
	ctx.events.important_event.emit("hourglass")
	return {"ok": true, "seconds": seconds, "report": report}
