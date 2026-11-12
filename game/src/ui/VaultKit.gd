class_name VaultKit
extends RefCounted
## Componenti comuni delle schermate del Caveau e del Mercato (Sala dei Caveau, Album, Guardaroba, Bottega, Mercato,
## Emporio, Commesse): intestazione con spiegazione richiudibile, riepilogo risorse, schede con icona e badge, carte con
## bordo personalizzato, stati vuoti utili («a cosa serve», «come si riempie», pulsanti Vai, anteprima).
## Solo presentazione: legge i sistemi, non decide nulla. Le icone sono PNG interi a scala 1x/2x/3x (mai ridimensionati
## a frazioni, CLAUDE.md regola 10); i colori vengono da FxPalette/CrateUi (nessun colore di altri giochi).

const GOLD_BORDER := FxPalette.GOLD
const CARD_BG := Color("1b2030")
const CARD_BG_SEL := Color("2a2a22")
const CARD_BG_GHOST := Color("151822")

## Icona di ogni scheda (PNG 32x32 esistenti): [cartella, id].
const TAB_ICON := {
	"hall": ["crates", "crate_millbrook"],
	"album": ["relics", "relic_millbrook_1"],
	"wardrobe": ["skins", "skin_millbrook_01"],
	"contracts": ["crates", "capsule_emblems"],
	"refine": ["items", "bar_vaultsteel"],
	"bank": ["items", "vault_shard"],
	"challenge": ["relics", "relic_archive_1"],
}

## Accento del bordo delle carte-cassa per genere di cassa (palette del progetto).
const KIND_COLOR := {
	"zone": FxPalette.GOLD_D, "era": FxPalette.TEAL, "event": FxPalette.VIOLET, "capsule": FxPalette.AMBER,
	"bounty": FxPalette.RED, "rift": FxPalette.BLUE_D,
}

static var _intro_open: Dictionary = {}       # id schermata -> aperta? (solo per la sessione, non è uno stato di gioco)


# ------------------------------------------------------------------ mattoni

## Icona a scala intera: `scale` volte la dimensione del PNG (1 = nativa), filtro nearest, mai deformata.
static func pix(tex: Texture2D, scale: int = 1, dim: bool = false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sz := Vector2(32, 32)
	if tex != null:
		sz = tex.get_size()
	r.custom_minimum_size = sz * float(maxi(1, scale))
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if dim:
		r.modulate = Color(0.0, 0.0, 0.0, 0.8)      # sagoma
	return r


static func style(bg: Color, border: Color, width: int = 2, pad: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(pad)
	return sb


## Etichetta di testo (autowrap) con colore e dimensione facoltativi.
static func label(parent: Node, text: String, muted: bool = false, size: int = 0, color: Variant = null) -> Label:
	var l := Label.new()
	l.text = text
	if muted:
		l.theme_type_variation = &"MutedLabel"
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color is Color:
		l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


## Colore smorzato per i numeri a zero, altrimenti nessun override (null).
static func _dim_if(cond: bool) -> Variant:
	if cond:
		return FxPalette.SMOKE
	return null


## Piccolo riquadro «icona + testo» (riepilogo risorse). `tip` è il tooltip.
static func chip(tex: Texture2D, text: String, tip: String = "", color: Variant = null, scale: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"InsetPanel"
	p.tooltip_text = tip
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(h)
	if tex != null:
		h.add_child(pix(tex, scale))
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"NumberLabel"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if color is Color:
		l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return p


# ------------------------------------------------------------------ intestazione

## Titolo + spiegazione breve richiudibile («▾ A cosa serve»). Aperta di default solo con lo schermo alto; la scelta
## del giocatore vale per tutta la sessione.
static func header(parent: Control, id: String, title_key: String, intro_key: String) -> void:
	var title := Label.new()
	title.text = TranslationServer.translate(title_key)
	ScreenKit.title_style(title)
	parent.add_child(title)
	if intro_key.is_empty():
		return
	var open: bool = bool(_intro_open.get(id, _default_open(parent)))
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_ALL
	btn.name = "IntroToggle"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Disclosure.apply(btn, "UI_VUX_WHAT_FOR", open)
	parent.add_child(btn)
	var intro := Label.new()
	intro.text = TranslationServer.translate(intro_key)
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.visible = open
	intro.name = "IntroText"
	parent.add_child(intro)
	btn.pressed.connect(func() -> void:
		var now := not intro.visible
		intro.visible = now
		_intro_open[id] = now
		Disclosure.apply(btn, "UI_VUX_WHAT_FOR", now))


static func _default_open(parent: Control) -> bool:
	var vp := parent.get_viewport()
	return vp != null and vp.get_visible_rect().size.y >= 860.0


# ------------------------------------------------------------------ riepilogo risorse

## Casse possedute, chiavi (una per tipo posseduto) e Schegge del Caveau: le tre cose con cui si apre e si compra.
static func resource_bar(parent: Control) -> HFlowContainer:
	var bar := HFlowContainer.new()
	bar.name = "ResourceBar"
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	parent.add_child(bar)
	var bank := CrateUi.bank()
	if bank == null:
		return bar
	var n_crates := 0
	for it in DataRegistry.items_by_category("crate"):
		n_crates += int(bank.count(it.id))
	bar.add_child(chip(IconLib.icon("crates", "crate_millbrook"), NumberFormat.fmt(n_crates),
		TranslationServer.translate("UI_VUX_RES_CRATES"), _dim_if(n_crates <= 0)))
	var any_key := false
	for it in DataRegistry.items_by_category("key"):
		var n: int = bank.count(it.id)
		if n > 0:
			any_key = true
			bar.add_child(chip(IconLib.icon("items", str(it.id)), "×" + NumberFormat.fmt(n), CrateUi.def_name(str(it.id))))
	if not any_key:
		bar.add_child(chip(IconLib.icon("items", "key_t1"), "0", TranslationServer.translate("UI_VUX_RES_NO_KEYS"), FxPalette.SMOKE))
	var crates := CrateUi.crates()
	var sh: int = crates.shards() if crates != null else 0
	bar.add_child(chip(IconLib.icon("items", "vault_shard"), NumberFormat.fmt(sh),
		TranslationServer.translate("UI_VUX_RES_SHARDS"), _dim_if(sh <= 0)))
	return bar


## Contenitore del riepilogo risorse che si aggiorna da solo: si ricostruisce solo se i numeri cambiano.
static func resource_host(parent: Control) -> VBoxContainer:
	var host := VBoxContainer.new()
	host.name = "ResourceHost"
	parent.add_child(host)
	update_resources(host)
	return host


static func update_resources(host: Control) -> void:
	var bank := CrateUi.bank()
	var crates := CrateUi.crates()
	var parts := PackedStringArray([str(crates.shards()) if crates != null else "-"])
	if bank != null:
		for cat in ["crate", "key"]:
			for it in DataRegistry.items_by_category(cat):
				parts.append(str(bank.count(it.id)))
	var sig := ",".join(parts)
	if str(host.get_meta("sig", "")) == sig:
		return
	host.set_meta("sig", sig)
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	resource_bar(host)


## Chip dell'oro (Mercato, Emporio, Commesse).
static func gold_chip(parent: Control) -> PanelContainer:
	var c := chip(IconLib.ui("ui_currency_gold"), NumberFormat.fmt(GameState.gold()), TranslationServer.translate("UI_VUX_RES_GOLD"), null, 2)
	c.name = "GoldChip"
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(c)
	return c


# ------------------------------------------------------------------ schede

## Dati delle schede del Caveau: {id, key, screen, tab, token}. Vive in CrateUi.TAB_DEFS.
## Badge: numero (casse da aprire, pezzi dell'Album), «!» (premio da ritirare), vuoto.
static func tab_badge(tab_id: String) -> String:
	var crates := CrateUi.crates()
	var bank := CrateUi.bank()
	if crates == null or bank == null:
		return ""
	match tab_id:
		"hall":
			var n := 0
			for it in DataRegistry.items_by_category("crate"):
				if crates.openable(str(it.id)) > 0:
					n += 1
			return str(n) if n > 0 else ""
		"challenge":
			return "!" if crates.challenge_unlocked() and not crates.challenge_pending().is_empty() else ""
	return ""


## Riga di schede con icona e badge; la scheda attiva è l'unica «AccentButton» e ha una barra d'oro sotto.
## Una scheda chiusa NON è un vicolo cieco: resta spenta con il lucchetto e la riga sotto dice come si apre.
static func tabs(parent: Control, current: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 10)
	parent.add_child(row)
	var locked: Array = []
	for t in CrateUi.TAB_DEFS:
		var b := Button.new()
		b.name = "Tab_" + str(t.id)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = TranslationServer.translate(str(t.key))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 32)
		b.add_theme_font_size_override("font_size", 14)
		_slim(b, t.id == current)
		var ic: Array = TAB_ICON.get(str(t.id), ["items", "vault_shard"])
		if t.id == current:
			b.theme_type_variation = &"AccentButton"
			b.focus_mode = Control.FOCUS_NONE
			b.icon = IconLib.icon(str(ic[0]), str(ic[1]))
		elif not CrateUi.unlocked(str(t.token)):
			b.disabled = true
			b.icon = IconLib.ui("ui_lock")
			locked.append(t)
			var hint := UnlockSystem.hint_for(str(t.token), DataRegistry)
			b.tooltip_text = hint if not hint.is_empty() else str(TranslationServer.translate("UI_CRATES2_TAB_LOCKED"))
		else:
			b.icon = IconLib.icon(str(ic[0]), str(ic[1]))
			var scr: String = t.screen
			var params := {} if str(t.tab).is_empty() else {"tab": str(t.tab)}
			b.pressed.connect(func() -> void: EventBus.screen_requested.emit(scr, params))
		var badge := tab_badge(str(t.id))
		if not badge.is_empty() and not b.disabled:
			_add_badge(b, badge)
		row.add_child(b)
	locked_strip(parent, locked)
	return row


## Margini laterali dei pulsanti-scheda più stretti (7 schede in una riga a 1280 px); stesso tema, stessi telai.
static func _slim(b: Button, accent: bool) -> void:
	var th := ThemeDB.get_project_theme()
	if th == null:
		return
	var type := "AccentButton" if accent else "Button"
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := th.get_stylebox(st, type)
		if sb == null:
			continue
		var d := sb.duplicate() as StyleBox
		d.content_margin_left = maxf(4.0, sb.get_margin(SIDE_LEFT) - 4.0)
		d.content_margin_right = maxf(4.0, sb.get_margin(SIDE_RIGHT) - 4.0)
		b.add_theme_stylebox_override(st, d)


static func _add_badge(b: Button, text: String) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", style(FxPalette.RED, FxPalette.darken(FxPalette.RED, 0.4), 1, 2))
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -16.0
	p.offset_right = 6.0
	p.offset_top = -9.0
	p.offset_bottom = 9.0
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", UiType.NOTE)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	b.add_child(p)


## «Ancora chiuse: Rimpasti, Affinatura, Sfida. Si aprono con le missioni.» + Vai alla prima missione che serve.
static func locked_strip(parent: Control, locked: Array) -> void:
	if locked.is_empty():
		return
	var h := HFlowContainer.new()
	h.name = "LockedStrip"
	h.add_theme_constant_override("h_separation", 6)
	parent.add_child(h)
	h.add_child(pix(IconLib.ui("ui_lock")))
	var names := PackedStringArray()
	for t in locked:
		names.append(TranslationServer.translate(str(t.key)))
	var l := Label.new()
	l.text = Loc.tf("UI_VUX_LOCKED_TABS", {"list": ", ".join(names)})
	l.theme_type_variation = &"MutedLabel"
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var target := ReqLink.target_for_token(str(locked[0].token))
	if not target.is_empty():
		var go := Button.new()
		go.text = Loc.tf("UI_VUX_GO", {"to": TranslationServer.translate("UI_MENU_QUESTS")})
		go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		go.pressed.connect(ReqLink.go.bind(target))
		h.add_child(go)


# ------------------------------------------------------------------ carte

## Pannello a bordo personalizzato (cassa, slot, collezione). `accent` = colore del bordo; `selected` = oro e sfondo caldo.
static func card(accent: Color, selected: bool = false, ghost: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := CARD_BG_SEL if selected else (CARD_BG_GHOST if ghost else CARD_BG)
	var col := GOLD_BORDER if selected else (FxPalette.darken(accent, 0.55) if ghost else FxPalette.darken(accent, 0.3))
	p.add_theme_stylebox_override("panel", style(bg, col, 3 if selected else 2, 6))
	return p


## Rende cliccabile una carta: un pulsante piatto a tutta carta (tastiera e fuoco compresi) con effetto al passaggio.
static func make_clickable(p: Control, on_press: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(on_press)
	b.mouse_entered.connect(func() -> void: p.modulate = Color(1.18, 1.14, 1.05))
	b.mouse_exited.connect(func() -> void: p.modulate = Color.WHITE)
	p.add_child(b)
	return b


## Colore del bordo di una cassa dal suo genere (zona, Era, evento…).
static func crate_accent(crate_id: String) -> Color:
	var kind := str(DataRegistry.item(crate_id).get("crate", {}).get("kind", "zone"))
	return KIND_COLOR.get(kind, FxPalette.GOLD_D)


## Barra impilata delle probabilità di una cassa: un segmento per rarità, largo quanto la probabilità (minimo 3 px).
static func odds_bar(rows: Array) -> Control:
	var bar := HBoxContainer.new()
	bar.name = "OddsBar"
	bar.add_theme_constant_override("separation", 1)
	bar.custom_minimum_size = Vector2(0, 14)
	for r in rows:
		var seg := ColorRect.new()
		seg.color = CrateUi.rarity_color(str(r.rarity))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(float(r.pct), 1.5)           # le rarità rare restano visibili
		seg.custom_minimum_size = Vector2(3, 14)
		seg.tooltip_text = "%s %s" % [CrateUi.rarity_label(str(r.rarity)), CrateUi.pct(float(r.pct))]
		bar.add_child(seg)
	return bar


## Barra di avanzamento sottile x/N (collezioni, slot).
static func progress(value: float, max_value: float, color: Color = FxPalette.GOLD_D) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = maxf(1.0, max_value)
	pb.value = value
	pb.custom_minimum_size = Vector2(0, 10)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.add_theme_stylebox_override("fill", style(color, color, 0, 0))
	pb.add_theme_stylebox_override("background", style(Color("0d1018"), FxPalette.darken(color, 0.6), 1, 0))
	return pb


## Dissolvenza breve (≤ 0,15 s) quando cambia il contenuto di un pannello: nessun effetto con «Riduci animazioni».
static func fade_in(n: CanvasItem, seconds: float = 0.14) -> void:
	if n == null or not n.is_inside_tree() or CrateUi.reduce_motion():
		return
	n.modulate.a = 0.0
	n.create_tween().tween_property(n, "modulate:a", 1.0, seconds)


# ------------------------------------------------------------------ stato vuoto utile

## Stato vuoto che spiega: a cosa serve, come si riempie (passi + pulsanti Vai) e, facoltativo, un'anteprima.
## `gos`: [{text (già tradotto), target (ReqLink), primary}]. Mai una schermata muta o un vicolo cieco.
static func empty_card(parent: Control, tex: Texture2D, title: String, what: String, steps: PackedStringArray, gos: Array, preview: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "EmptyCard"
	p.theme_type_variation = &"CardPanel"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	if tex != null:
		var pic := pix(tex, 2)
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(pic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	top.add_child(col)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"SectionLabel"
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(t)
	label(col, what, false)
	if not steps.is_empty():
		var hs := Label.new()
		hs.text = TranslationServer.translate("UI_VUX_HOW_TO_FILL")
		hs.theme_type_variation = &"SectionLabel"
		col.add_child(hs)
		for s in steps:
			label(col, "•  " + s, true)
	if not gos.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		col.add_child(row)
		for g in gos:
			var b := Button.new()
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = Loc.tf("UI_VUX_GO", {"to": str(g.text)})
			if bool(g.get("primary", false)):
				b.theme_type_variation = &"AccentButton"
			var tg: Dictionary = g.target
			b.pressed.connect(ReqLink.go.bind(tg))
			row.add_child(b)
	if preview != null:
		var hp := Label.new()
		hp.text = TranslationServer.translate("UI_VUX_PREVIEW")
		hp.theme_type_variation = &"SectionLabel"
		v.add_child(hp)
		v.add_child(preview)
	return p


## Obiettivi «Vai» per ottenere casse e chiavi (solo schermate raggiungibili adesso).
static func crate_sources() -> Array:
	var out: Array = []
	var entries := [["quests", "UI_MENU_QUESTS", {}], ["combat", "UI_MENU_COMBAT", {}], ["bounty", "UI_MENU_BOUNTY", {}], ["shop", "UI_MENU_SHOP", {}]]
	for e in entries:
		var entry := ScreenRegistry.get_entry(str(e[0]))
		if entry.is_empty() or not ScreenRegistry.is_available(entry, GameState.data.get("unlocks", [])):
			continue
		out.append({"text": TranslationServer.translate(str(e[1])), "target": {"screen": e[0], "params": e[2], "hint": ""},
			"primary": out.is_empty()})
	return out
