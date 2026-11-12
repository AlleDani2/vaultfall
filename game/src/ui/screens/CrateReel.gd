class_name CrateReel
extends Control
## Rullo delle Casse (docs/09 §6, docs/24 R-LEG-5). SOLO PRESENTAZIONE: riceve le 60 tessere già estratte da
## CrateSystem.open() (vincitore all'indice 52) e le fa scorrere. Non estrae nulla, non decide nulla.
## - striscia orizzontale, indicatore centrale, easing cubic_out, durata da crate_rules.reel (5,5 s; rapida 0,8 s);
## - punto d'arresto = result.stop_frac, già estratto, dentro la tessera vincente;
## - rivelazione: tween di scala e bagliore del colore della rarità (nessun effetto che spinga ad aprire ancora);
## - "riduci animazioni": nessuno scorrimento né tween, risultato subito;
## - suoni: solo segnali-gancio (nessun file audio): tick_sound a ogni tessera che passa, reveal_sound alla fine.

signal tick_sound(volume: float, pitch: float)
signal reveal_sound(rarity: String)
signal finished

const TILE_W := 124.0
const TILE_H := 150.0
const GAP := 8.0
const QUICK_S := 0.8
const NAME_LINES := 2                   # righe del nome alla grandezza normale
const NAME_LINES_MAX := 3               # al carattere minimo (i nomi più lunghi, «Amuleto della Precisione (Gemma del Caveau)»)
const NAME_W := TILE_W - 8.0
const NAME_MIN_FONT := 12               # carattere minimo del nome sulla tessera (sotto, il nome si accorcia con «…»)
const BG := Color("#14120f")
const TILE_BG := Color("#25211b")
const INDICATOR := Color("#f0e6c8")

var scroll: float = 0.0:
	set(v):
		scroll = v
		_check_tick()
		queue_redraw()

## Avanzamento 0..1 dello scorrimento (easing sul tween). Lo scroll si ricalcola DAL PUNTO D'ARRESTO con la
## larghezza attuale: così l'indicatore centrale cade sempre sulla tessera vincente anche se il pannello viene
## dimensionato dopo l'avvio (prima, con il pannello appena aperto, la larghezza era ancora quella minima e il
## vincitore finiva ~1 tessera a sinistra dell'indicatore).
var progress: float = 0.0:
	set(v):
		progress = v
		scroll = _stop_scroll() * v

var playing: bool = false
var _stop_x: float = 0.0              # punto della striscia che deve fermarsi sotto l'indicatore
var _tiles: Array = []
var _icons: Array = []
var _names: Array = []
var _winner: int = 52
var _fit: Dictionary = {}            # indice tessera -> {text, font_size}
var _tween: Tween
var _reveal: float = 0.0
var _pop: float = 0.0
var _last_idx: int = -1
var _pulse_t: float = 99.0           # secondi dalla rivelazione: la tessera vincente «respira» per ~2 s
var _tick_kick: float = 0.0          # 1 -> 0 dopo ogni tessera che passa sotto l'indicatore (scatto visivo del «tick»)


func _init() -> void:
	custom_minimum_size = Vector2(480, TILE_H + 40.0)
	clip_contents = true
	resized.connect(_on_resized)


func _stop_scroll() -> float:
	return _stop_x - size.x * 0.5


func _on_resized() -> void:
	if not _tiles.is_empty() and (not playing):
		scroll = _stop_scroll() * progress


func pitch() -> float:
	return TILE_W + GAP


## Prepara e avvia. `tiles` = [{d: def_id, r: rarity}] (60), `winner` = indice del vincitore,
## `stop_frac` = punto d'arresto dentro la tessera (0..1).
func play(tiles: Array, winner: int, stop_frac: float, quick: bool = false) -> void:
	stop()
	_tiles = tiles
	_winner = winner
	_icons.clear()
	_names.clear()
	_fit.clear()
	for t in tiles:
		_icons.append(CrateUi.def_icon(str(t.d)))
		_names.append(CrateUi.def_name(str(t.d)))
	_reveal = 0.0
	_pop = 0.0
	_last_idx = -1
	_stop_x = float(winner) * pitch() + clampf(stop_frac, 0.02, 0.98) * TILE_W
	progress = 0.0
	scroll = 0.0
	playing = true
	if CrateUi.reduce_motion() or _tiles.is_empty():
		progress = 1.0
		_finish(false)
		return
	var dur := QUICK_S if quick else float(CrateUi.rules().get("reel", {}).get("duration_s", 5.5))
	_tween = create_tween()
	_tween.tween_property(self, "progress", 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_scroll_done)


## Salta: va subito al risultato (che era già stato estratto).
func skip() -> void:
	if not playing:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	progress = 1.0
	_finish(not CrateUi.reduce_motion())


func stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	playing = false


func _on_scroll_done() -> void:
	_finish(true)


func _finish(animate: bool) -> void:
	playing = false
	reveal_sound.emit(str(_tiles[_winner].r) if _winner < _tiles.size() else "")
	_fx_reveal.call_deferred()
	if animate:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "_reveal", 1.0, 0.45)
		var pop := create_tween()
		pop.tween_property(self, "_pop", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(self, "_pop", 0.0, 0.25)
		tw.finished.connect(func() -> void: finished.emit())
	else:
		_reveal = 1.0
		queue_redraw()
		finished.emit()


func _check_tick() -> void:
	if _tiles.is_empty():
		return
	var idx := int(floor((scroll + size.x * 0.5) / pitch()))
	if idx != _last_idx:
		_last_idx = idx
		if playing and _stop_x > 0.0:
			var prog := clampf(progress, 0.0, 1.0)
			if Fx.level() >= 1:
				_tick_kick = 1.0 if Fx.level() >= 2 else 0.5
				set_process(true)
			tick_sound.emit(lerpf(1.0, 0.25, prog), lerpf(1.25, 0.8, prog))


func _process(dt: float) -> void:
	if _pulse_t < 2.2:
		_pulse_t += dt
	if _tick_kick > 0.0:
		_tick_kick = maxf(0.0, _tick_kick - dt * 9.0)
	if _reveal > 0.0 or _pop > 0.0 or _pulse_t < 2.2 or _tick_kick > 0.0:
		queue_redraw()


## Effetti della rivelazione (SOLO dopo la fermata: l'esito era già estratto; niente anticipazioni durante la corsa).
## Particelle, bagliore e flash dei bordi crescono con la rarità, con i colori originali dei dati.
func _fx_reveal() -> void:
	if _winner >= _tiles.size() or not is_inside_tree():
		return
	var top := (size.y - TILE_H) * 0.5
	var x := float(_winner) * pitch() - scroll
	var rect := Rect2(get_global_rect().position + Vector2(x, top), Vector2(TILE_W, TILE_H))
	var rid := str(_tiles[_winner].r)
	Fx.reveal(rect, rid)
	if Fx.level() >= 1 and FxPalette.rarity_t(rid) >= 0.25:
		Fx.frame_flash(get_global_rect(), FxPalette.rarity(rid), 8.0 + 10.0 * FxPalette.rarity_t(rid), 0.6, 0.6)
	_pulse_t = 0.0 if Fx.level() >= 1 else 99.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font := ThemeDB.fallback_font
	var top := (size.y - TILE_H) * 0.5
	var first := maxi(0, int(floor(scroll / pitch())))
	var last := mini(_tiles.size() - 1, int(ceil((scroll + size.x) / pitch())))
	for i in range(first, last + 1):
		var x := float(i) * pitch() - scroll
		var rect := Rect2(x, top, TILE_W, TILE_H)
		var col := CrateUi.rarity_color(str(_tiles[i].r))
		var is_win := i == _winner and not playing
		if is_win:
			var grow := 10.0 * _pop
			if _pulse_t < 2.2:
				grow += 3.0 * sin(_pulse_t * TAU * 1.3) * maxf(0.0, 1.0 - _pulse_t / 2.2)
			rect = rect.grow(grow)
			draw_rect(rect.grow(6.0 + 10.0 * _reveal), Color(col, 0.35 * _reveal))
		var under := playing and i == _last_idx and _tick_kick > 0.0
		draw_rect(rect, TILE_BG.lerp(Color(col, 1.0), 0.22 * _tick_kick) if under else TILE_BG)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 6.0)), col)
		draw_rect(rect, col, false, 2.0)
		var icon: Texture2D = _icons[i]
		var isz := minf(rect.size.x - 40.0, 64.0)
		draw_texture_rect(icon, Rect2(rect.position + Vector2((rect.size.x - isz) * 0.5, 12.0), Vector2(isz, isz)), false)
		draw_string(font, rect.position + Vector2(0, 12.0 + isz + 17.0), CrateUi.rarity_symbol(str(_tiles[i].r)),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, UiType.SECTION, col)
		_draw_name(font, rect, 12.0 + isz + 33.0, i)
	var cx := size.x * 0.5
	var kick := _tick_kick if playing else 0.0
	var ind := INDICATOR.lerp(Color.WHITE, kick)
	var bump := roundf(4.0 * kick)                    # le punte «scattano» verso l'interno a ogni tessera
	# la linea dell'indicatore passa solo sopra e sotto le tessere (e, durante la corsa, in trasparenza sopra di esse): da ferma
	# non taglia mai il nome della tessera vincente (cattura 31/7: «Rete da Pesca» attraversata dalla linea)
	var lw := 3.0 + roundf(2.0 * kick)
	draw_line(Vector2(cx, 0), Vector2(cx, top), ind, lw)
	draw_line(Vector2(cx, top + TILE_H), Vector2(cx, size.y), ind, lw)
	if playing:
		draw_line(Vector2(cx, top), Vector2(cx, top + TILE_H), Color(ind, 0.3), lw)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 9, 0), Vector2(cx + 9, 0), Vector2(cx, 12 + bump)]), ind)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 9, size.y), Vector2(cx + 9, size.y), Vector2(cx, size.y - 12 - bump)]), ind)


## Nome della tessera, centrato e sempre intero: se non sta in due righe si rimpicciola il carattere, poi si accorcia con «…».
## Il calcolo si fa una volta per tessera (cache), non a ogni fotogramma.
func _draw_name(font: Font, rect: Rect2, dy: float, i: int) -> void:
	var f := name_fit(i)
	var x := rect.position.x + (rect.size.x - NAME_W) * 0.5   # larghezza fissa: la tessera vincente ingrandita non sposta il testo
	draw_multiline_string(font, Vector2(x, rect.position.y + dy), str(f.text), HORIZONTAL_ALIGNMENT_CENTER, NAME_W, int(f.font_size),
		int(f.lines), Color("#e6dfcf"))


func _line_count(font: Font, text: String, fs: int) -> int:
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, NAME_W, fs).y
	return int(round(h / maxf(1.0, font.get_height(fs))))


## Testo, corpo del carattere e righe con cui il nome della tessera `i` sta intero: prima si rimpicciolisce (fino a
## NAME_MIN_FONT) per stare in NAME_LINES righe, poi si usano NAME_LINES_MAX righe, e solo in ultimo si accorcia con «…».
func name_fit(i: int) -> Dictionary:
	if not _fit.has(i):
		var font := ThemeDB.fallback_font
		var text := str(_names[i])
		var fs := UiType.NOTE
		var lines := NAME_LINES
		while fs > NAME_MIN_FONT and _line_count(font, text, fs) > lines:
			fs -= 1
		if _line_count(font, text, fs) > lines:
			lines = NAME_LINES_MAX
		while _line_count(font, text, fs) > lines and text.length() > 4:
			text = text.substr(0, text.length() - 2).strip_edges() + "…"
		_fit[i] = {"text": text, "font_size": fs, "lines": lines}
	return _fit[i]
