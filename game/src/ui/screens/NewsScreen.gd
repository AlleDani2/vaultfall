extends GameScreen
## Novità (menù Progressi): changelog bilingue di AppInfo, versione in alto. Solo presentazione.

@onready var _version: Label = %Version
@onready var _host: VBoxContainer = %Host


func open(_params: Dictionary) -> void:
	ScreenKit.title_style(get_node("Title") as Label)          # titolo di pagina unico (a larghezza del testo)
	_version.text = Loc.tf("UI_FB_VERSION", {"v": AppInfo.version_label(), "build": AppInfo.build()})
	for c in _host.get_children():
		c.free()
	_host.add_child(NewsView.new())
