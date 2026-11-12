class_name HeroKit
extends RefCounted
## Piccoli attrezzi condivisi dalle schermate della fase F10 (Eroe, Talenti, Prestigio): barra di schede a pulsanti
## (una pagina alla volta) e frase «a cosa serve» che compare alla prima visita e poi si richiude in un «?» (D17).
## Solo presentazione: nessuna regola di gioco qui dentro.

const SEEN_KEY := "seen_intro"


## Barra di schede: `tabs` = [[id, chiave_testo, chiave_tooltip], ...]. Ritorna {id: Button}. Un solo pulsante è premuto.
static func tab_bar(parent: Control, tabs: Array, accent_col: Color, on_select: Callable) -> Dictionary:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	parent.add_child(bar)
	var group := ButtonGroup.new()
	var out := {}
	for t in tabs:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(t[1])
		if t.size() > 2 and str(t[2]) != "":
			b.tooltip_text = str(t[2])
		var tid := str(t[0])
		b.pressed.connect(func() -> void: on_select.call(tid))
		ScreenKit.style_tab(b, accent_col)
		bar.add_child(b)
		out[tid] = b
	return out


## Il giocatore ha già visto la frase di questa schermata?
static func seen(screen_id: String) -> bool:
	var arr: Variant = Settings.get_value(SEEN_KEY)
	return arr is Array and (arr as Array).has(screen_id)


## Segna la frase come vista (una volta sola, salvata nelle impostazioni).
static func mark_seen(screen_id: String) -> void:
	var arr: Variant = Settings.get_value(SEEN_KEY)
	var cur: Array = (arr as Array).duplicate() if arr is Array else []
	if cur.has(screen_id):
		return
	cur.append(screen_id)
	Settings.set_value(SEEN_KEY, cur)


## Il «?» accanto al titolo: mostra o nasconde il testo `target`. Alla prima visita il testo è aperto (e si segna come visto),
## dalle visite successive parte chiuso. Ritorna il pulsante.
static func help_button(row: Control, target: Control, screen_id: String, tip: String) -> Button:
	var b := Button.new()
	b.text = "?"
	b.toggle_mode = true
	b.flat = false
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var first := not seen(screen_id)
	target.visible = first
	b.set_pressed_no_signal(first)
	b.toggled.connect(func(on: bool) -> void: target.visible = on)
	row.add_child(b)
	if first:
		mark_seen(screen_id)
	return b
