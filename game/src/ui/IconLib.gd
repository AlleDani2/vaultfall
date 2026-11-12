class_name IconLib
extends RefCounted
## UNICO punto per ottenere le icone/ritratti (CLAUDE.md, docs/20). Se il PNG non esiste ancora restituisce un
## segnaposto colorato in modo stabile dall'id (mai un errore). Tipi = sottocartelle di assets/icons e portraits.
## Uso: IconLib.icon("items", "log_pine") · IconLib.icon("crates", "crate_millbrook") · IconLib.portrait("monsters", id)

static var _cache: Dictionary = {}


static func icon(kind: String, id: String) -> Texture2D:
	var path := "res://assets/icons/%s/%s.png" % [kind, id]
	if kind == "items" and not _cache.has(path) and not ResourceLoader.exists(path):
		var alt := _data_icon(id)      # QA119: oggetto che riusa l'icona di un altro (es. Sacchetto di Rune): niente quadrato colorato
		if alt != "" and ResourceLoader.exists(alt):
			path = alt
	return _load_cached(path, id)


## L'oggetto ha un'icona vera (per id oppure dal percorso dei dati), cioè non finirà sul segnaposto colorato.
static func item_has_art(item_id: String) -> bool:
	if ResourceLoader.exists("res://assets/icons/items/%s.png" % item_id):
		return true
	var alt := _data_icon(item_id)
	return alt != "" and ResourceLoader.exists(alt)


## Percorso `icon` dichiarato nei dati dell'oggetto ("" se assente o sconosciuto).
static func _data_icon(item_id: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var dr: Node = tree.root.get_node_or_null("DataRegistry") if tree != null else null
	if dr == null:
		return ""
	return str(dr.item(item_id).get("icon", ""))


static func portrait(kind: String, id: String) -> Texture2D:
	return _load_cached("res://assets/portraits/%s/%s.png" % [kind, id], id)


## Texture da un percorso qualsiasi (res://…), con la stessa cache: senza PNG o se il percorso è vuoto ritorna null.
## Serve alle schermate che hanno già il percorso nei dati (icone delle Imprese): `load()` diretto ricaricava ogni
## PNG a ogni apertura della schermata (la risorsa torna in cache solo finché qualcuno la tiene).
static func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex != null:
		_cache[path] = tex
	return tex


static func ui(id: String) -> Texture2D:
	return _load_cached("res://assets/ui/%s.png" % id, id)


## Banner di zone, dungeon e incursioni: i PNG hanno una fascia scura uniforme sopra e sotto. Non si tocca il file
## (CLAUDE.md, D-6): si mostra solo la parte utile con una `AtlasTexture` (region). Le fasce si riconoscono una volta
## dalle righe di un solo colore scuro e il risultato resta in cache. Senza PNG: segnaposto colorato.
const BANNER_BAR_MAX_LUM := 40.0
const BANNER_BAR_TOLERANCE := 6.0
static var _banner_cache: Dictionary = {}


static func banner(path: String) -> Texture2D:
	if _banner_cache.has(path):
		return _banner_cache[path]
	var tex: Texture2D = _load_cached(path, path.get_file().get_basename())
	var res: Texture2D = tex
	if ResourceLoader.exists(path) and tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var top := _bar_rows(img, true)
			var bottom := _bar_rows(img, false)
			var h := img.get_height() - top - bottom
			if (top > 0 or bottom > 0) and h > 8:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(0, top, img.get_width(), h)
				res = at
	_banner_cache[path] = res
	return res


## Righe consecutive (da sopra o da sotto) di un solo colore scuro.
static func _bar_rows(img: Image, from_top: bool) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	while n < h - 1:
		var y := n if from_top else h - 1 - n
		var first := img.get_pixel(0, y)
		if (first.r + first.g + first.b) / 3.0 * 255.0 > BANNER_BAR_MAX_LUM:
			break
		var uniform := true
		for x in range(1, w):
			var c := img.get_pixel(x, y)
			if maxf(absf(c.r - first.r), maxf(absf(c.g - first.g), absf(c.b - first.b))) * 255.0 > BANNER_BAR_TOLERANCE:
				uniform = false
				break
		if not uniform:
			break
		n += 1
	return n


static func has_art(path: String) -> bool:
	return ResourceLoader.exists(path)


static func _load_cached(path: String, id: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = _placeholder(id)
	_cache[path] = tex
	return tex


static func _placeholder(id: String) -> Texture2D:
	var h := id.hash()
	var col := Color.from_hsv(float(h % 360) / 360.0, 0.45, 0.65)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(3, 29):
		for x in range(3, 29):
			var edge := x == 3 or y == 3 or x == 28 or y == 28
			img.set_pixel(x, y, col.darkened(0.45) if edge else col)
	return ImageTexture.create_from_image(img)
