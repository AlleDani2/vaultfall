class_name FxToolAnim
extends RefCounted
## Movimento dell'ATTREZZO (icona della mansione) e reazione del BERSAGLIO (icona della risorsa) durante un'azione.
## Solo tween su rotazione/scala dei nodi (nessuno sprite nuovo, nessuna geometria dei PNG toccata). SOBRIO E CONTENUTO
## (feedback del giocatore, rapporto 104): nessuno spostamento di posizione, rotazione al massimo MAX_ROT (±6°) e scala al
## massimo ±MAX_SCALE (6%), così l'icona resta nel proprio riquadro e non invade il testo vicino; i contenitori delle
## schermate hanno comunque `clip_contents`.
##   - start(): costruisce la linea del tempo di UN ciclo (durata = cycle_s dell'azione): l'attrezzo si porta appena
##     indietro nel finale (wind-up) e resta lì fino al colpo; niente colpetti intermedi;
##   - strike(): al completamento UN colpetto dell'attrezzo; la risorsa (bersaglio) si schiaccia e trema piano;
##   - stop(): rimette tutto a riposo.
## Livelli: 2 = pieno · 1 = ridotti (ampiezza dimezzata, niente scossa né lampo forte) · 0 = nessun movimento.

const META_TL := "fx_tool_tl"        # linea del tempo del ciclo (solo callback)
const META_POSE := "fx_tool_pose"    # tween breve della posa corrente
const META_REST := "fx_tool_rest"    # {pivot, rot, scale} originali
const WINDUP_MAX := 0.4
const MAX_ROT := 0.105               # rad (circa 6 gradi): tetto della rotazione di qualunque movimento
const MAX_SCALE := 0.06              # tetto della variazione di scala (±6%)
const TARGET_SQUASH := 0.06          # schiacciamento della risorsa al colpo
const TARGET_SHAKE_PX := 2.0         # tremolio della risorsa (solo livello 2)

## Parametri per movimento: pivot (frazione della dimensione), wind/hit (rotazione in rad), hit_s (durata del colpo).
const MOTIONS := {
	"chop": {"pivot": Vector2(0.5, 0.9), "wind": -0.08, "hit": 0.08, "hit_s": 0.08},
	"mine": {"pivot": Vector2(0.5, 0.9), "wind": -0.09, "hit": 0.09, "hit_s": 0.07},
	"rod": {"pivot": Vector2(0.5, 0.95), "wind": 0.07, "hit": -0.07, "hit_s": 0.1},
	"hammer": {"pivot": Vector2(0.5, 0.9), "wind": -0.07, "hit": 0.07, "hit_s": 0.06},
	"stir": {"pivot": Vector2(0.5, 0.5), "wobble": 0.07, "n": 4, "step": 0.09},
	"stitch": {"pivot": Vector2(0.5, 0.5), "wobble": 0.05, "n": 6, "step": 0.05},
	"sneak": {"pivot": Vector2(0.5, 0.9), "wobble": 0.06, "n": 3, "step": 0.08},
	"dip": {"pivot": Vector2(0.5, 1.0), "squash": Vector2(1.05, 0.94), "hit_s": 0.09},
	"gem": {"pivot": Vector2(0.5, 0.5), "squash": Vector2(1.06, 1.06), "hit_s": 0.07},
}


static func _rest(n: Control) -> Dictionary:
	if not n.has_meta(META_REST):
		n.set_meta(META_REST, {"pivot": n.pivot_offset, "rot": n.rotation, "scale": n.scale})
	return n.get_meta(META_REST)


static func _kill_meta(n: Control, key: String) -> void:
	if n.has_meta(key):
		var old: Variant = n.get_meta(key)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		n.remove_meta(key)


static func is_running(tool: Control) -> bool:
	if tool == null or not is_instance_valid(tool) or not tool.has_meta(META_TL):
		return false
	var t: Variant = tool.get_meta(META_TL)
	return t is Tween and (t as Tween).is_valid()


## Rimette a riposo attrezzo e bersaglio (cambio di azione, stordimento, uscita, «riduci animazioni»).
static func stop(tool: Control, target: Control = null) -> void:
	for n in [tool, target]:
		if n == null or not is_instance_valid(n):
			continue
		var c := n as Control
		_kill_meta(c, META_TL)
		_kill_meta(c, META_POSE)
		if c.has_meta(META_REST):
			var r: Dictionary = c.get_meta(META_REST)
			c.pivot_offset = r.pivot
			c.rotation = r.rot
			c.scale = r.scale
			c.remove_meta(META_REST)


## Inizia un ciclo da `elapsed` secondi su `dur`. Chiamare di nuovo a ogni completamento (o a ogni cambio di azione).
static func start(tool: Control, target: Control, skill_id: String, dur: float, elapsed: float = 0.0) -> void:
	if tool == null or not is_instance_valid(tool) or not tool.is_inside_tree():
		return
	if Fx.level() <= 0:
		stop(tool, target)
		return
	_kill_meta(tool, META_TL)
	_rest(tool)
	var motion := FxThemes.motion(skill_id)
	var wind := minf(WINDUP_MAX, dur * 0.35)
	var t_wind := maxf(0.32, dur - wind)
	var now := maxf(0.0, elapsed)
	var tl := tool.create_tween()
	tool.set_meta(META_TL, tl)
	if t_wind >= now:
		tl.tween_interval(t_wind - now)
		tl.tween_callback(_windup.bind(tool, motion, wind))
	else:                                           # già dentro la carica (ripartenza a metà ciclo): nessuna posa
		tl.tween_interval(0.0)


static func _pose_tween(tool: Control) -> Tween:
	_kill_meta(tool, META_POSE)
	var tw := tool.create_tween()
	tool.set_meta(META_POSE, tw)
	return tw


static func _set_pivot(tool: Control, m: Dictionary) -> void:
	var pv: Vector2 = m.get("pivot", Vector2(0.5, 0.5))
	tool.pivot_offset = tool.size * pv


## Carica: l'attrezzo si porta indietro e resta lì fino al colpo.
static func _windup(tool: Control, motion: String, secs: float) -> void:
	if not is_instance_valid(tool) or Fx.level() <= 0:
		return
	var m: Dictionary = MOTIONS.get(motion, MOTIONS.chop)
	_set_pivot(tool, m)
	var tw := _pose_tween(tool)
	var k := 1.0 if Fx.level() >= 2 else 0.5
	if m.has("wind"):
		tw.tween_property(tool, "rotation", float(m.wind) * k, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	elif m.has("squash"):
		var sq: Vector2 = m.squash
		tw.tween_property(tool, "scale", Vector2(2.0 - sq.x, 2.0 - sq.y).lerp(Vector2.ONE, 1.0 - k), secs)
	else:
		tw.tween_property(tool, "rotation", -float(m.get("wobble", 0.2)) * 0.5 * k, secs)


## Colpo di completamento.
static func strike(tool: Control, target: Control, skill_id: String) -> void:
	if Fx.level() <= 0:
		return
	if tool != null and is_instance_valid(tool) and tool.is_inside_tree():
		_rest(tool)
		_motion_hit(tool, FxThemes.motion(skill_id), 1.0 if Fx.level() >= 2 else 0.5, func() -> void:
			if target != null and is_instance_valid(target) and target.is_inside_tree():
				react(target, true))
	elif target != null:
		react(target, true)


## Un colpo dell'attrezzo a ampiezza `amp` (1 = pieno). `on_impact` parte al momento del contatto.
static func _motion_hit(tool: Control, motion: String, amp: float, on_impact: Callable) -> void:
	var m: Dictionary = MOTIONS.get(motion, MOTIONS.chop)
	_set_pivot(tool, m)
	var tw := _pose_tween(tool)
	var back := 0.22
	if m.has("hit"):
		tw.tween_property(tool, "rotation", float(m.hit) * amp, float(m.hit_s)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		tw.tween_callback(on_impact)
		tw.tween_interval(0.03)
		tw.tween_property(tool, "rotation", 0.0, back).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif m.has("wobble"):
		var a := float(m.wobble) * amp
		tw.tween_callback(on_impact)
		var steps := int(m.n)
		for i in steps:
			var f := 1.0 - float(i) / float(steps)
			tw.tween_property(tool, "rotation", a * f * (1.0 if i % 2 == 0 else -1.0), float(m.step)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tool, "rotation", 0.0, float(m.step))
	else:
		var sq: Vector2 = m.get("squash", Vector2(1.05, 0.95))
		tw.tween_property(tool, "scale", Vector2.ONE.lerp(sq, amp), float(m.get("hit_s", 0.08))).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		tw.tween_callback(on_impact)
		tw.tween_property(tool, "scale", Vector2.ONE, back).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Il bersaglio incassa: schiacciamento con rimbalzo (±6%), tremolio di 2 px (livello 2), lampo bianco se forte.
static func react(target: Control, strong: bool) -> void:
	var lv := Fx.level()
	if lv <= 0 or target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var r := _rest(target)
	_kill_meta(target, META_POSE)
	target.pivot_offset = target.size * 0.5
	var amt := TARGET_SQUASH * (1.0 if lv >= 2 else 0.5) * (1.0 if strong else 0.6)
	var tw := target.create_tween()
	target.set_meta(META_POSE, tw)
	tw.tween_property(target, "scale", Vector2(1.0 + amt, 1.0 - amt), 0.05)
	tw.tween_property(target, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(target):
			target.scale = r.scale
			target.pivot_offset = r.pivot)
	if lv >= 2:
		Fx.shake(target, TARGET_SHAKE_PX if strong else 1.0, 0.14 if strong else 0.1)
	if strong:
		FxJuice.hit_flash(target)
