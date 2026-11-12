class_name CityStrip
extends PanelContainer
## Striscia della Città (G34, docs/08 §PNG, docs/10 §Gazzetta). Dalla fase F6 non sta più nella cornice: è UNA RIGA in fondo al
## Riepilogo (`make_row()`), una volta sola invece che in 12 schermate (D16). Contenuto:
## a sinistra la chiacchiera di un PNG (3-5 battute a rotazione, una ogni CHAT_SECONDS), a destra il ticker della
## Gazzetta del Mercato (una notizia alla volta, a scorrimento lento). Con «riduci animazioni» il ticker non scorre:
## le notizie si alternano ferme. Solo presentazione: legge npcs.json ("chat"), MarketSystem.active_gazette() e il suo diario.

const CHAT_SECONDS := 9.0
const NEWS_HOLD_SECONDS := 6.0       # con «riduci animazioni»: tempo di ogni notizia ferma
const SCROLL_PX_PER_S := 38.0        # scorrimento lento del ticker
const PORTRAIT_PX := 28
const HUMOR_COUNT := 50              # chiavi UI_HUMOR_TIP_01…50 (localization/parts/humor.csv): la battuta del Riepilogo passa qui (D17)
const ROW_HEIGHT := 36               # forma di riga (Riepilogo)
const ROW_PORTRAIT_PX := 24
const STEP_S := 0.05                 # il ticker avanza a 20 Hz (resoconto 100): ogni passo ridisegna tutto il canvas

var _portrait: TextureRect
var _chat: Label
var _news_clip: Control
var _news: Label
var _chat_t: float = 0.0
var _chat_i: int = 0
var _news_i: int = 0
var _news_hold: float = 0.0
var _news_text: String = ""
var _humor: String = ""              # forma di riga: una battuta a caso tra le notizie, scelta una volta per visita
var _acc: float = 0.0


func _init() -> void:
	name = "CityStrip"
	theme_type_variation = &"TopBarPanel"
	custom_minimum_size = Vector2(0, 48)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	add_child(h)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_portrait)
	_chat = Label.new()
	_chat.name = "Chat"
	_chat.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_chat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART        # la battuta può andare su due righe
	_chat.max_lines_visible = 2
	_chat.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chat.custom_minimum_size = Vector2(120, 0)
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chat.size_flags_stretch_ratio = 2.0
	h.add_child(_chat)
	var sep := VSeparator.new()
	h.add_child(sep)
	var tag := Label.new()
	tag.name = "NewsTag"
	tag.theme_type_variation = &"SectionLabel"
	tag.text = "UI_UIB_GAZETTE_TAG"
	h.add_child(tag)
	_news_clip = Control.new()
	_news_clip.name = "NewsClip"
	_news_clip.clip_contents = true
	_news_clip.custom_minimum_size = Vector2(120, 0)
	_news_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_news_clip.size_flags_vertical = Control.SIZE_FILL
	h.add_child(_news_clip)
	_news = Label.new()
	_news.name = "News"
	_news.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_news.theme_type_variation = &"MutedLabel"
	_news_clip.add_child(_news)
	mouse_filter = Control.MOUSE_FILTER_PASS


## La striscia in forma di riga per il Riepilogo: più bassa, senza il riquadro della barra, battuta su una sola riga.
static func make_row() -> CityStrip:
	var s := CityStrip.new()
	s.name = "CityRow"
	s.theme_type_variation = &""
	s.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	s._portrait.custom_minimum_size = Vector2(ROW_PORTRAIT_PX, ROW_PORTRAIT_PX)
	s._chat.max_lines_visible = 1
	# generatore locale, mai i flussi RNG di gioco (non devono muoversi)
	s._humor = TranslationServer.translate("UI_HUMOR_TIP_%02d" % (randi() % HUMOR_COUNT + 1))
	return s


func _ready() -> void:
	next_chat()
	next_news()


# ------------------------------------------------------------------ dati (puri, testabili)

## Tutte le battute: [{npc, name, line}] nell'ordine dei dati (solo PNG con campo "chat").
static func chat_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in DataRegistry.table("npcs"):
		for l in n.get("chat", []):
			out.append({"npc": str(n.id), "name": Loc.t(n.get("name", {})), "line": Loc.t(l)})
	return out


## Battuta numero `i` a rotazione: PNG diversi a turno (i % n_png), battuta diversa a ogni giro (i / n_png).
static func chat_at(i: int) -> Dictionary:
	var by_npc: Array = []
	for n in DataRegistry.table("npcs"):
		if not (n.get("chat", []) as Array).is_empty():
			by_npc.append(n)
	if by_npc.is_empty():
		return {}
	var n: Dictionary = by_npc[i % by_npc.size()]
	var lines: Array = n.chat
	var l: Variant = lines[floori(float(i) / float(by_npc.size())) % lines.size()]
	return {"npc": str(n.id), "name": Loc.t(n.get("name", {})), "line": Loc.t(l)}


## Notizie della Gazzetta da mostrare (testi già nella lingua attiva): quelle in corso; se non ce ne sono, le ultime
## del diario; se è tutto calmo, la frase «giornata tranquilla».
static func news_items() -> PackedStringArray:
	var out := PackedStringArray()
	var mk := Game.system("market") as MarketSystem
	if mk != null:
		for e in mk.active_gazette():
			out.append(Loc.t(e.text))
		if out.is_empty():
			var gz_log: Array = mk.state.gazette.get("log", [])
			for k in range(gz_log.size() - 1, maxi(-1, gz_log.size() - 4), -1):
				var d: Dictionary = DataRegistry.get_def("gazette_events", str(gz_log[k].id))
				if not d.is_empty():
					out.append(Loc.t(d.text))
	if out.is_empty():
		out.append(TranslationServer.translate("UI_MARKET_GAZETTE_QUIET"))
	return out


# ------------------------------------------------------------------ aggiornamento

func next_chat() -> void:
	var c := chat_at(_chat_i)
	_chat_i += 1
	if c.is_empty():
		_chat.text = ""
		_portrait.texture = null
		return
	_chat.text = "%s: %s" % [c.name, c.line]
	_chat.tooltip_text = _chat.text
	_portrait.texture = IconLib.portrait("npcs", str(c.npc))
	if Fx.enabled():
		_chat.modulate.a = 0.0
		create_tween().tween_property(_chat, "modulate:a", 1.0, 0.4)
	else:
		_chat.modulate.a = 1.0


func next_news() -> void:
	var items := news_items()
	if not _humor.is_empty():
		items.append(_humor)
	_news_text = items[_news_i % items.size()]
	_news_i += 1
	_news.text = _news_text
	_news.reset_size()                 # la larghezza segue il testo (serve a sapere quando è uscito dal bordo)
	_news.tooltip_text = _news_text
	_news_hold = 0.0
	_news.position = Vector2(_news_clip.size.x if Fx.enabled() else 0.0, 0.0)
	_news.position.y = maxf(0.0, (_news_clip.size.y - _news.size.y) * 0.5)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not Clock.focused:       # in secondo piano il ticker sta fermo (niente ridisegni inutili)
		return
	_acc += delta
	if _acc < STEP_S:
		return
	var dt := _acc
	_acc = 0.0
	_chat_t += dt
	if _chat_t >= CHAT_SECONDS:
		_chat_t = 0.0
		next_chat()
	_news.position.y = maxf(0.0, (_news_clip.size.y - _news.size.y) * 0.5)
	if Fx.enabled():
		_news.position.x -= SCROLL_PX_PER_S * dt
		if _news.position.x + _news.get_minimum_size().x < 0.0:
			next_news()
	else:
		_news_hold += dt
		if _news_hold >= NEWS_HOLD_SECONDS:
			next_news()
