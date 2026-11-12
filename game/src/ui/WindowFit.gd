class_name WindowFit
extends RefCounted
## Finestra di gioco robusta (QA overflow, resoconto 107): dimensione minima e adattamento allo schermo.
## Il progetto parte a 1600x900 (project.godot): su un portatile 1366x768 o con scala di Windows al 150%/200% la finestra
## sarebbe più grande dello spazio utile e il bordo destro/basso resterebbe FUORI dallo schermo. All'avvio la finestra
## viene quindi ridotta (stessa proporzione, mai sotto il minimo) e centrata nell'area utile del monitor.
## Le funzioni di calcolo sono pure (testabili); `setup` è l'unica che tocca la finestra.

const MIN_SIZE := Vector2i(960, 540)         # con la scala automatica (UiScale) l'area logica non scende mai sotto 1024x576; senza, con 100% resta 1280x720
const SCREEN_MARGIN := 24                    # respiro tra la finestra e i bordi dello schermo (px)


## Dimensione (contenuto) che entra nell'area utile `usable` con le decorazioni `decor` (barra del titolo, bordi).
## Mantiene la proporzione di `want`; non scende sotto `min_size` a meno che lo schermo stesso sia più piccolo.
static func fit_size(want: Vector2i, usable: Vector2i, decor: Vector2i, min_size: Vector2i = MIN_SIZE) -> Vector2i:
	var room := Vector2i(maxi(320, usable.x - decor.x - SCREEN_MARGIN), maxi(240, usable.y - decor.y - SCREEN_MARGIN))
	if want.x <= room.x and want.y <= room.y:
		return want
	var f := minf(float(room.x) / float(want.x), float(room.y) / float(want.y))
	var out := Vector2i(int(floor(want.x * f)), int(floor(want.y * f)))
	out = Vector2i(maxi(out.x, mini(min_size.x, room.x)), maxi(out.y, mini(min_size.y, room.y)))
	return Vector2i(mini(out.x, room.x), mini(out.y, room.y))


## Minimo della finestra: MIN_SIZE, ma mai più grande dello spazio utile.
static func min_for(usable: Vector2i, decor: Vector2i) -> Vector2i:
	return Vector2i(mini(MIN_SIZE.x, maxi(320, usable.x - decor.x)), mini(MIN_SIZE.y, maxi(240, usable.y - decor.y)))


static func setup(win: Window) -> void:
	if win == null or DisplayServer.get_name() == "headless":
		return
	var screen := win.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var decor := win.get_size_with_decorations() - win.size
	win.min_size = min_for(usable.size, decor)
	if win.mode != Window.MODE_WINDOWED or win.borderless:
		return
	var want := win.size
	var fit := fit_size(want, usable.size, decor)
	if fit != want:
		win.size = fit
	# centrata (o riportata dentro) l'area utile
	var total := fit + decor
	var pos := win.position
	var x := clampi(pos.x, usable.position.x, maxi(usable.position.x, usable.position.x + usable.size.x - total.x))
	var y := clampi(pos.y, usable.position.y, maxi(usable.position.y, usable.position.y + usable.size.y - total.y))
	if fit != want:
		x = usable.position.x + int((usable.size.x - total.x) * 0.5)
		y = usable.position.y + int((usable.size.y - total.y) * 0.5)
	win.position = Vector2i(x, y)


## Dialoghi (AcceptDialog e derivati) che compaiono: se sono più grandi dell'area visibile si riducono e si riportano dentro
## (popup_centered con dimensioni fisse non lo fa). Collegato da Settings a SceneTree.node_added.
static func hook(n: Node) -> void:
	if n is AcceptDialog and not (n as Window).visibility_changed.is_connected(_on_dialog_visibility.bind(n)):
		(n as Window).visibility_changed.connect(_on_dialog_visibility.bind(n))


static func _on_dialog_visibility(d: Window) -> void:
	if d.visible and d.is_inside_tree():
		fit_dialog.call_deferred(d)


## Rettangolo [posizione, dimensione] di un dialogo dentro `view` (area visibile), con barra del titolo di `bar` px sopra.
static func dialog_rect(pos: Vector2i, size: Vector2i, view: Vector2i, bar: int, margin: int = 8) -> Rect2i:
	var s := Vector2i(mini(size.x, view.x - 2 * margin), mini(size.y, view.y - bar - 2 * margin))
	var p := Vector2i(clampi(pos.x, margin, maxi(margin, view.x - s.x - margin)), clampi(pos.y, bar + margin, maxi(bar + margin, view.y - s.y - margin)))
	return Rect2i(p, s)


## `d_ref` è Variant: il dialogo può essere già stato liberato quando parte la chiamata differita (un Window tipizzato farebbe
## fallire la chiamata con «Cannot convert argument 1 from Object to Object» prima ancora del controllo).
static func fit_dialog(d_ref: Variant) -> void:
	if d_ref == null or not is_instance_valid(d_ref):
		return
	var d := d_ref as Window
	if d == null or not d.visible or not d.is_inside_tree() or not d.is_embedded():
		return
	var win := d as Window
	var host: Node = win.get_parent()
	if host == null or host.get_viewport() == null:
		return
	var view := Vector2i(host.get_viewport().get_visible_rect().size)
	var bar: int = win.get_theme_constant("title_height") if win.has_theme_constant("title_height") else 30
	var r := dialog_rect(win.position, win.size, view, bar)
	if r.size != win.size:
		win.size = r.size
	if r.position != win.position:
		win.position = r.position
