class_name CombatUi
extends RefCounted
## Piccoli attrezzi condivisi dalle schermate di combattimento (Combattimento, Eroe, Talenti, Dungeon, Taglie):
## etichette, barre e animazioni a tween (scosse, scale, bagliori, numeri che salgono). Tutto rispetta l'impostazione
## "riduci animazioni" (Settings.reduce_motion): in quel caso i valori cambiano direttamente, senza movimento.
## Solo presentazione: nessuna logica di gioco.

const COL_HIT := Color("f2efe4")
const COL_CRIT := Color("ffd24a")
const COL_ABILITY := Color("7fc8ff")
const COL_DOT := Color("8fd47a")
const COL_HURT := Color("ff7b72")
const COL_HEAL := Color("7fcf8a")
const COL_WARN := Color("e0b640")
const COL_RES := {"fury": Color("d9544d"), "focus": Color("e0b640"), "mana": Color("5b8def")}
const COL_SAFE := {"green": Color("5fbf6a"), "yellow": Color("e0b640"), "red": Color("d9544d")}
const COL_LOCKED := Color(1, 1, 1, 0.38)
## Meccanica del boss -> frase del registro/striscione (chiavi del CSV).
const MECH_LOG := {"heavy_blow": "UI_C2_LOG_MECH_HEAVY", "poison_cloud": "UI_C2_LOG_MECH_POISON", "shield_phase": "UI_C2_LOG_MECH_SHIELD",
	"stun": "UI_C2_LOG_MECH_STUN", "summon_adds": "UI_C2_LOG_MECH_ADDS"}


## Avvisi di pericolo (COMBAT-3): finestra in cui si mostra «Colpo Devastante tra N s» e soglia dell'allarme rosso.
## Sono tempi di presentazione, non regole di gioco.
const THREAT_WARN_S := 6.0
const THREAT_NOW_S := 1.5


## Riga di riepilogo di uno scontro chiuso (CombatSystem.last_fight / campo `fight` dell'evento «kill» e «die»).
static func fight_text(f: Dictionary) -> String:
	if f.is_empty():
		return TranslationServer.translate("UI_C3_SUMMARY_NONE")
	var t := maxf(0.1, float(f.get("t", 0.0)))
	var mon := Loc.t(DataRegistry.get_def("monsters", str(f.get("monster", ""))).get("name", ""))
	var params := {"name": mon, "t": NumberFormat.fmt_time(float(f.get("t", 0.0))), "dealt": NumberFormat.fmt(floorf(float(f.get("dealt", 0.0)))),
		"dps": NumberFormat.fmt(floorf(float(f.get("dealt", 0.0)) / t)), "taken": NumberFormat.fmt(floorf(float(f.get("taken", 0.0)))),
		"casts": int(f.get("casts", 0)), "food": int(f.get("food", 0)), "crits": int(f.get("crits", 0)),
		"xp": NumberFormat.fmt(floorf(float(f.get("xp", 0.0)))), "gold": NumberFormat.fmt(int(f.get("gold", 0)))}
	return Loc.tf("UI_C3_FIGHT_LOST" if bool(f.get("died", false)) else "UI_C3_FIGHT_WON", params)


## Riga di riepilogo di una corsa (dungeon, incursione): CombatSystem.run_summary / campo `run` di «dungeon_done».
static func run_text(r: Dictionary, name: String) -> String:
	if r.is_empty():
		return ""
	return Loc.tf("UI_C3_RUN", {"name": name, "t": NumberFormat.fmt_time(float(r.get("wall", 0.0))), "kills": int(r.get("kills", 0)),
		"deaths": int(r.get("deaths", 0)), "dealt": NumberFormat.fmt(floorf(float(r.get("dealt", 0.0)))),
		"taken": NumberFormat.fmt(floorf(float(r.get("taken", 0.0)))), "food": int(r.get("food", 0)), "casts": int(r.get("casts", 0)),
		"xp": NumberFormat.fmt(floorf(float(r.get("xp", 0.0)))), "gold": NumberFormat.fmt(int(r.get("gold", 0)))})


## Striscia con il banner di una zona/dungeon/incursione (solo la parte utile del PNG, vedi `IconLib.banner`).
## Ritorna null se il PNG non c'è. Si riempie la larghezza senza deformare (ritaglio laterale).
## L'altezza segue la larghezza (BANNER_H_PER_W, tra `height` e BANNER_H_MAX): a 1920x1080 non si ritaglia il 75% dell'immagine.
const BANNER_H_PER_W := 0.2
const BANNER_H_MAX := 180.0


static func banner_rect(path: String, height: float = 64.0) -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = Vector2(0, height)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.resized.connect(func() -> void:
		var h := clampf(r.size.x * BANNER_H_PER_W, height, BANNER_H_MAX)
		if absf(r.custom_minimum_size.y - h) > 1.0:
			r.custom_minimum_size = Vector2(0, h))
	set_banner(r, path)
	return r


static func set_banner(r: TextureRect, path: String) -> void:
	var ok := path != "" and ResourceLoader.exists(path)
	r.visible = ok
	r.texture = IconLib.banner(path) if ok else null


static func reduce() -> bool:
	return bool(Settings.get_value("reduce_motion"))


static func label(key: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = key
	if not variation.is_empty():
		l.theme_type_variation = StringName(variation)
	return l


## Etichetta con testo già tradotto (nessuna traduzione automatica del contenuto).
static func text_label(variation: String = "", wrap_text: bool = false) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if not variation.is_empty():
		l.theme_type_variation = StringName(variation)
	if wrap_text:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func bar(col: Color, height: float = 16.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.add_theme_stylebox_override("fill", UiKit.tinted_fill(col))
	FxBarGhost.attach(b)                    # scia di ciò che si è perso / lampo di ciò che si è guadagnato
	return b


static func set_bar(b: ProgressBar, v: float, secs: float = 0.1) -> void:
	v = clampf(v, 0.0, 1.0)
	if reduce() or not b.is_inside_tree() or absf(b.value - v) < 0.0005:
		b.value = v
		return
	var tw := b.create_tween()
	tw.tween_property(b, "value", v, secs)


static func set_bar_color(b: ProgressBar, col: Color) -> void:
	var fill := b.get_theme_stylebox("fill") as StyleBoxTexture
	if fill != null and fill.modulate_color != col:
		fill.modulate_color = col


## Rimbalzo di scala (ricompense, rango di un talento, abilità lanciata).
static func pop(n: Control, factor: float = 1.18, secs: float = 0.2) -> void:
	if reduce() or not n.is_inside_tree():
		return
	n.pivot_offset = n.size * 0.5
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(factor, factor), secs * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector2.ONE, secs * 0.6)


## Scossa orizzontale (colpi, fallimenti).
static func shake(n: Control, px: float = 6.0, secs: float = 0.14) -> void:
	if reduce() or not n.is_inside_tree():
		return
	# si trema attorno alla posizione di riposo (ritratto centrato con le ancore): la scossa precedente si ferma
	var old: Variant = n.get_meta("shake_tw") if n.has_meta("shake_tw") else null
	var running: bool = old is Tween and (old as Tween).is_valid()
	if running:
		(old as Tween).kill()
	var x0: float = float(n.get_meta("shake_x0")) if running and n.has_meta("shake_x0") else n.position.x
	n.set_meta("shake_x0", x0)
	n.position.x = x0
	var tw := n.create_tween()
	n.set_meta("shake_tw", tw)
	tw.tween_property(n, "position:x", x0 + px, secs * 0.25)
	tw.tween_property(n, "position:x", x0 - px, secs * 0.25)
	tw.tween_property(n, "position:x", x0, secs * 0.5)


## Lampo di colore sul modulate (danno subito, ricompensa).
static func flash(n: CanvasItem, col: Color, secs: float = 0.3) -> void:
	if reduce() or not n.is_inside_tree():
		return
	n.modulate = col
	var tw := n.create_tween()
	tw.tween_property(n, "modulate", Color.WHITE, secs)


## Respiro lento di opacità per ciò che è pronto (abilità, nodo acquistabile). Con riduci animazioni: nessun movimento.
static func glow(n: CanvasItem, on: bool) -> void:
	if n.has_meta("glow_tw"):
		var old: Tween = n.get_meta("glow_tw")
		if old != null and old.is_valid():
			old.kill()
		n.remove_meta("glow_tw")
	if not on or reduce() or not n.is_inside_tree():
		n.modulate = Color.WHITE
		return
	var tw := UiAnim.color_loop(n, &"modulate", Color.WHITE, Color(1.25, 1.25, 1.1), 0.7)      # a gradini: niente ridisegni a 60 Hz
	n.set_meta("glow_tw", tw)


## Testo fluttuante che sale e svanisce, sopra `layer` (un Control trasparente).
static func float_text(layer: Control, text: String, col: Color, pos: Vector2, rise: float = 48.0, secs: float = 0.9,
		outline: int = 4) -> void:
	if reduce() or not layer.is_inside_tree() or layer.get_child_count() > 14:
		return
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.position = pos
	layer.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - rise, secs)
	tw.tween_property(l, "modulate:a", 0.0, secs)
	tw.chain().tween_callback(l.queue_free)


## "1,2 s" per le ricariche (una cifra decimale sotto i 10 s).
static func secs_text(s: float) -> String:
	if s >= 10.0:
		return "%d" % int(ceil(s))
	return NumberFormat.decimal(s, 1, Loc.locale())


## Nome tradotto di un'abilità/mostro/oggetto dai dati ({"it","en"}).
static func name_of(def: Dictionary, fallback: String = "") -> String:
	return Loc.t(def.get("name", fallback))


static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## Righe che passano il filtro scelto: "all" tutte, "rare" solo drop rari, "boss" solo eventi del boss.
static func filter_lines(lines: PackedStringArray, cats: PackedStringArray, mode: String) -> PackedStringArray:
	if mode == "all":
		return lines
	var out := PackedStringArray()
	for i in lines.size():
		if i < cats.size() and cats[i] == mode:
			out.append(lines[i])
	return out


## Dimensione di una texture ingrandita a SCALA INTERA (×1…×kmax) in modo da stare in `avail` px di altezza (mai frazioni: D-6).
## Vector2.ZERO se la texture non c'è.
static func int_fit(tex: Texture2D, avail: float, kmax: int = 4) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var sz := tex.get_size()
	var k := clampi(int(floor(avail / maxf(1.0, sz.y))), 1, kmax)
	return sz * float(k)
