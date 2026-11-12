class_name FxUi
extends RefCounted
## «Juice» dell'interfaccia generale (transizioni, tooltip, pulsanti, riquadri, cassa che trema, cornice del risultato).
## Solo tween su proprietà VISIVE (modulate, scale, rotation): niente nodi nuovi per effetto, nessun toccare il layout.
## Tutto rispetta Fx.level(): 0 («Riduci animazioni») = nessun movimento (il nodo è subito nello stato finale);
## 1 («Effetti ridotti») = solo dissolvenze brevi; 2 = pieno. Durate brevi: transizioni <= 0,15 s.

const SCREEN_S := 0.12                 # transizione tra schermate (<= 0,15 s)
const TIP_S := 0.10
const PRESS_SCALE := 0.95
const PRESS_BACK_S := 0.12

const META_TW := "fxui_tw"


static func _kill(n: Node) -> void:
	if n.has_meta(META_TW):
		var old: Variant = n.get_meta(META_TW)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		n.remove_meta(META_TW)


# ------------------------------------------------------------------ transizioni

## Ingresso di una schermata appena aperta: dissolvenza + piccolo «assestamento» di scala (livello 2). Max 0,15 s.
static func screen_in(n: Control) -> void:
	var lv := Fx.level()
	if lv <= 0 or n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return
	_kill(n)
	n.modulate.a = 0.0
	var tw := n.create_tween()
	n.set_meta(META_TW, tw)
	tw.set_parallel(true)
	tw.tween_property(n, "modulate:a", 1.0, SCREEN_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if lv >= 2:
		n.pivot_offset = Vector2(n.size.x * 0.5, 0.0)
		n.scale = Vector2(0.992, 0.992)
		tw.tween_property(n, "scale", Vector2.ONE, SCREEN_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_screen_done.bind(n))


static func _screen_done(n: Control) -> void:
	if is_instance_valid(n):
		n.modulate.a = 1.0
		n.scale = Vector2.ONE
		n.remove_meta(META_TW)


## Tooltip personalizzato: compare con una dissolvenza breve (livello >= 1).
static func tooltip_in(c: Control) -> void:
	if c == null or Fx.level() <= 0:
		return
	c.modulate.a = 0.0
	c.tree_entered.connect(_tooltip_start.bind(c), CONNECT_ONE_SHOT)


static func _tooltip_start(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, TIP_S)


# ------------------------------------------------------------------ pulsanti e riquadri

## Pressione di un pulsante: si «schiaccia» (5%) e torna con un piccolo rimbalzo. Livello 2.
static func press(b: Control) -> void:
	if b == null or not is_instance_valid(b) or not b.is_inside_tree() or Fx.level() < 2:
		return
	_kill(b)
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	b.set_meta(META_TW, tw)
	tw.tween_property(b, "scale", Vector2(PRESS_SCALE, PRESS_SCALE), 0.05).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "scale", Vector2.ONE, PRESS_BACK_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_press_done.bind(b))


static func _press_done(b: Control) -> void:
	if is_instance_valid(b):
		b.scale = Vector2.ONE
		if b.has_meta(META_TW):
			b.remove_meta(META_TW)


## Riquadro (carta di un edificio, cella): il bordo si illumina leggermente al passaggio del mouse. Livello >= 1.
static func card_hover(panel: Control, amount: float = 0.14) -> void:
	if panel == null or panel.has_meta("fxui_hover"):
		return
	panel.set_meta("fxui_hover", true)
	panel.mouse_entered.connect(_hover.bind(panel, amount, true))
	panel.mouse_exited.connect(_hover.bind(panel, amount, false))


static func _hover(panel: Control, amount: float, on: bool) -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree():
		return
	var key := "fxui_hover_tw"
	if panel.has_meta(key):
		var old: Variant = panel.get_meta(key)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var target := Color(1.0 + amount, 1.0 + amount, 1.0 + amount * 0.6, 1.0) if on else Color.WHITE
	if Fx.level() <= 0:
		panel.self_modulate = Color.WHITE
		return
	var tw := panel.create_tween()
	panel.set_meta(key, tw)
	tw.tween_property(panel, "self_modulate", target, 0.1)


# ------------------------------------------------------------------ Sala delle Casse

## Cassa che TREMA e poi «si apre» (prima del rullo). `secs` = durata della scossa; `done` viene chiamata UNA volta
## alla fine (o subito se non c'è animazione). Con livello 0: nessuna animazione, `done` subito. Livello 1: solo un
## breve «pop» (0,15 s). L'esito è già stato estratto: questa è solo scena.
## Ritorna il Tween (null se non animata) per poterlo fermare con `finish_chest`.
static func chest_open(icon: Control, secs: float, done: Callable) -> Tween:
	var lv := Fx.level()
	if lv <= 0 or icon == null or not is_instance_valid(icon) or not icon.is_inside_tree():
		if done.is_valid():
			done.call()
		return null
	_kill(icon)
	icon.visible = true
	icon.modulate = Color.WHITE
	icon.self_modulate = Color.WHITE
	icon.pivot_offset = (icon.size if icon.size.x > 1.0 else icon.custom_minimum_size) * 0.5     # appena mostrato: il layout può non esserci ancora
	var tw := icon.create_tween()
	icon.set_meta(META_TW, tw)
	if lv >= 2:
		var n := maxi(3, int(secs / 0.06))
		for i in n:
			var k := float(i + 1) / float(n)               # l'ampiezza cresce
			var ang := (1 if i % 2 == 0 else -1) * deg_to_rad(2.0 + 7.0 * k)
			tw.tween_property(icon, "rotation", ang, secs / float(n)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(icon, "rotation", 0.0, 0.04)
		tw.tween_callback(_chest_burst.bind(icon))
		tw.tween_property(icon, "scale", Vector2(1.35, 1.35), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(icon, "self_modulate", Color(2.0, 1.9, 1.6, 1.0), 0.08)
		tw.tween_property(icon, "modulate:a", 0.0, 0.12)
	else:
		tw.tween_property(icon, "scale", Vector2(1.12, 1.12), 0.06)
		tw.tween_property(icon, "modulate:a", 0.0, 0.09)
	tw.tween_callback(_chest_done.bind(icon, done))
	return tw


static func _chest_burst(icon: Control) -> void:
	if is_instance_valid(icon):
		Fx.burst("glint", Fx.center_of(icon), [FxPalette.GOLD, FxPalette.WHITE], 1.0, 1.0, icon.size * 0.35, 1)
		Fx.ring(Fx.center_of(icon), FxPalette.AMBER, 60.0, 0.35, FxPalette.WHITE, 1)


static func _chest_done(icon: Control, done: Callable) -> void:
	if is_instance_valid(icon):
		icon.visible = false
		icon.rotation = 0.0
		icon.scale = Vector2.ONE
		icon.modulate = Color.WHITE
		icon.self_modulate = Color.WHITE
		if icon.has_meta(META_TW):
			icon.remove_meta(META_TW)
	if done.is_valid():
		done.call()


## Salta la scena della cassa: ferma il tween e chiama subito `done`. Ritorna true se c'era una scena in corso.
static func finish_chest(icon: Control, done: Callable) -> bool:
	if icon == null or not is_instance_valid(icon) or not icon.has_meta(META_TW):
		return false
	_kill(icon)
	_chest_done(icon, done)
	return true


## Cornice del risultato che PULSA nel colore della rarità (non spinge ad aprire ancora: dura ~2 s e si spegne).
## Livello 0: un solo tono fisso breve (FxGlowPulse lo gestisce); livello 1/2: respiri di colore.
static func result_frame(panel: Control, rarity_id: String) -> void:
	if panel == null or not is_instance_valid(panel) or not panel.is_inside_tree():
		return
	var t := FxPalette.rarity_t(rarity_id)
	var col := FxPalette.rarity(rarity_id)
	FxGlowPulse.pulse(panel, col, 2 + int(round(2.0 * t)), 1.6 + 0.8 * t, 0.55 + 0.35 * t)
	if Fx.level() >= 1:
		Fx.glow(panel.get_global_rect(), col, 1.6 + 1.2 * t, 0.5 + 0.5 * t, 4.0, 0)


# ------------------------------------------------------------------ notifiche

## Uscita di una notifica: si rimpicciolisce un poco mentre svanisce (0,25 s). Livello 0: sparisce subito.
static func toast_out(p: Control) -> void:
	if p == null or not is_instance_valid(p):
		return
	if Fx.level() <= 0 or not p.is_inside_tree():
		p.queue_free()
		return
	p.pivot_offset = p.size * 0.5
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	if Fx.level() >= 2:
		tw.tween_property(p, "scale", Vector2(0.94, 0.94), 0.25)
	tw.chain().tween_callback(p.queue_free)
