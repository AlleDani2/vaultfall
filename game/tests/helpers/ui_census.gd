class_name UiCensus
extends RefCounted
## Censimento della densità dell'interfaccia in un albero REALE di nodi (progetto di interfaccia, doc 06 D30, fase F0).
## Porta in GDScript il conteggio di docs/ui_redesign/strumenti/ux_density_dump.gd (cammino dell'albero) e di
## analizza_densita.py (definizioni delle metriche, doc 04 §1.2), senza catture: niente contrasto né occupazione, solo conteggi.
##
## Uso:  var r := UiCensus.measure(main_screen, get_viewport().get_visible_rect())
##   r = {"window": m, "top": m, "side": m, "right": m, "city": m, "content": m (le regioni assenti mancano),
##        "quota_cromo": float, "ripetizioni_extra": int}
## con m = {controlli_visibili, elementi_info, righe_testo, parole, parole_prosa, button_attivi, badge_pillole,
##          barre, testi_colorati, competitori_attenzione}.
##
## Definizioni (stesse del doc 04):
##   controllo visibile      Control visibile, con opacità >= 0,05 e rettangolo non vuoto dopo il ritaglio degli antenati
##   elemento informativo    foglia utile: Label/RichTextLabel con testo, Button, ProgressBar, TextureRect con icona, campo di input
##   riga di testo           righe visibili delle etichette + 1 per ogni pulsante con testo
##   pulsante attivo         Button non disabilitato
##   badge/pillola           riquadro (PanelContainer/Panel) piccolo (< 7000 px²) con un testo come figlio diretto
##   concorrente d'attenzione  pulsanti AccentButton attivi + badge/pillole + barre + testi molto colorati (s > 0,45 e v > 0,45)
##   cornice                 barra alta + menù + colonna destra + striscia Città; contenuto = riquadro «Content»
##   ripetizioni extra       testi uguali (normalizzati, >= 5 caratteri) che compaiono più volte fuori dal menù

const BUTTON_CLASSES: PackedStringArray = ["Button", "CheckBox", "CheckButton", "OptionButton", "MenuButton", "LinkButton",
	"ColorPickerButton"]
const TEXT_CLASSES: PackedStringArray = ["Label", "RichTextLabel"]
const INPUT_CLASSES: PackedStringArray = ["LineEdit", "TextEdit", "SpinBox", "HSlider", "VSlider", "ItemList", "Tree"]
const REGION_NODES := {"TopBar": "top", "Sidebar": "side", "Content": "content", "RightColumn": "right", "RightRail": "right", "GoalStrip": "goal", "CityStrip": "city",
	"Toasts": "toast"}
const PILL_MAX_AREA := 7000.0
const LONG_TEXT_CHARS := 70


## Misura tutto l'albero di `main`. `view` = rettangolo dell'area logica (di solito get_visible_rect()).
static func measure(main: Control, view: Rect2) -> Dictionary:
	var nodes: Array = []
	_walk(main, "main", view, -1, nodes)
	var out := {}
	out["window"] = metrics(nodes.filter(func(n): return n.reg != "toast"))
	for reg in ["top", "side", "content", "right", "goal", "city"]:
		var sub: Array = nodes.filter(func(n): return n.reg == reg)
		if not sub.is_empty():
			out[reg] = metrics(sub)
	var wi := maxi(1, int(out["window"].elementi_info))
	var cornice := 0
	for reg in ["top", "side", "right", "goal", "city"]:
		cornice += int(out.get(reg, {}).get("elementi_info", 0))
	out["cornice_elementi"] = cornice
	out["quota_cromo"] = snappedf(float(cornice) / float(wi), 0.001)
	out["ripetizioni_extra"] = repetitions(nodes)
	return out


## Metriche di un insieme di nodi (record di `_walk`), vedi l'intestazione.
static func metrics(nodes: Array) -> Dictionary:
	var on: Array = nodes.filter(func(n): return n.vw > 0.0 and n.vh > 0.0)
	var leaf: Array = on.filter(func(n): return _is_leaf_info(n))
	var m := {"controlli_visibili": on.size(), "elementi_info": leaf.size()}
	var lines := 0
	var words := 0
	var prose := 0
	var bars := 0
	var active_buttons := 0
	var accent := 0
	var colorful := 0
	for n in leaf:
		var k := _kind(n)
		if k == "text":
			lines += maxi(1, int(n.ln))
			words += str(n.t).split(" ", false).size()
			if str(n.t).length() >= LONG_TEXT_CHARS:
				prose += str(n.t).split(" ", false).size()
			var col := Color(str(n.fc))
			if col.s > 0.45 and col.v > 0.45:
				colorful += 1
		elif k == "button":
			if not n.dis:
				active_buttons += 1
				if str(n.get("var", "")).contains("Accent"):
					accent += 1
			if not str(n.t).strip_edges().is_empty():
				lines += 1
				words += str(n.t).split(" ", false).size()
		elif k == "bar":
			bars += 1
	var pills := 0
	for n in on:
		if n.box and n.w * n.h < PILL_MAX_AREA and n.w > 8.0:
			for kid in on:
				if kid.p == n.i and _kind(kid) == "text":
					pills += 1
					break
	m["righe_testo"] = lines
	m["parole"] = words
	m["parole_prosa"] = prose
	m["button_attivi"] = active_buttons
	m["barre"] = bars
	m["testi_colorati"] = colorful
	m["badge_pillole"] = pills
	m["competitori_attenzione"] = accent + pills + bars + colorful
	return m


## Testi uguali (normalizzati) che compaiono più volte fuori dal menù: somma di (occorrenze - 1).
static func repetitions(nodes: Array) -> int:
	var counts := {}
	var re_digits := RegEx.new()
	re_digits.compile("\\d[\\d\\.,]*")
	var re_junk := RegEx.new()
	re_junk.compile("^[#\\s/%:\\-\\.,]*$")
	for n in nodes:
		if n.reg == "toast" or n.reg == "side" or n.vw <= 0.0 or n.vh <= 0.0:
			continue
		var k := _kind(n)
		if (k != "text" and k != "button") or str(n.get("t", "")).strip_edges().is_empty():
			continue
		var nt := re_digits.sub(str(n.t).strip_edges().to_lower(), "#", true)
		nt = " ".join(nt.split(" ", false))
		if nt.length() < 5 or re_junk.search(nt) != null:
			continue
		counts[nt] = int(counts.get(nt, 0)) + 1
	var extra := 0
	for k2 in counts:
		if int(counts[k2]) >= 2:
			extra += int(counts[k2]) - 1
	return extra


static func _kind(n: Dictionary) -> String:
	var c := str(n.cls)
	if TEXT_CLASSES.has(c):
		return "text" if not str(n.get("t", "")).strip_edges().is_empty() else ""
	if BUTTON_CLASSES.has(c):
		return "button"
	if c == "ProgressBar":
		return "bar"
	if c == "TextureRect" and n.get("ic", false):
		return "icon"
	if INPUT_CLASSES.has(c):
		return "input"
	return ""


static func _is_leaf_info(n: Dictionary) -> bool:
	return _kind(n) != ""


static func _walk(n: Node, reg: String, clip: Rect2, parent_idx: int, nodes: Array) -> void:
	var c := n as Control
	var reg2: String = REGION_NODES.get(str(n.name), reg)
	var my_idx := parent_idx
	var clip2 := clip
	if c != null:
		if not c.visible or c.modulate.a < 0.05:
			return
		var r := c.get_global_rect()
		var vis := r.intersection(clip)
		var rec := {"i": nodes.size(), "p": parent_idx, "cls": c.get_class(), "reg": reg2, "w": r.size.x, "h": r.size.y,
			"vw": maxf(vis.size.x, 0.0), "vh": maxf(vis.size.y, 0.0), "box": c is PanelContainer or c is Panel,
			"t": "", "ln": 0, "fc": "#ffffff", "dis": false, "ic": false}
		var tv := str(c.theme_type_variation)
		if tv != "":
			rec["var"] = tv
		if c is Label:
			var l := c as Label
			var t: String = TranslationServer.translate(l.text) if l.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else l.text
			rec["t"] = t.left(160)
			rec["fc"] = l.get_theme_color("font_color").to_html(false)
			rec["ln"] = maxi(1, l.get_visible_line_count()) if t != "" else 0
		elif c is RichTextLabel:
			var rt := c as RichTextLabel
			var t2 := rt.get_parsed_text()
			rec["t"] = t2.left(160)
			rec["fc"] = rt.get_theme_color("default_color").to_html(false)
			var fs := rt.get_theme_font_size("normal_font_size")
			var lh := maxf(1.0, rt.get_theme_font("normal_font").get_height(fs))
			rec["ln"] = maxi(1, int(round(rt.get_content_height() / lh))) if t2 != "" else 0
		elif c is BaseButton:
			var b := c as BaseButton
			rec["dis"] = b.disabled
			if b is Button:
				var bt := b as Button
				var t3: String = TranslationServer.translate(bt.text) if bt.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else bt.text
				rec["t"] = t3.left(160)
				rec["ic"] = bt.icon != null
		elif c is TextureRect:
			rec["ic"] = (c as TextureRect).texture != null
		nodes.append(rec)
		my_idx = int(rec["i"])
		if c is ScrollContainer or c.clip_contents:
			clip2 = clip.intersection(r)
	for ch in n.get_children():
		if ch is Window:
			continue
		_walk(ch, reg2, clip2, my_idx, nodes)
