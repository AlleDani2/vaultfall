class_name GameScreen
extends Control
## Base delle schermate mostrate nell'area contenuto di MainScreen (una scena per schermata in src/ui/screens/).
## Regole (docs/17 §12, CLAUDE.md): nessuna logica di gioco qui, solo presentazione; i pulsanti chiamano i
## sistemi (Game.system("id").metodo(...)); testi solo con chiavi del CSV (tr / testo "UI_..." nei nodi).
##
## MainScreen chiama:
##   open(params)  una volta, subito dopo l'aggiunta all'albero (params da ScreenRegistry/EventBus.screen_requested)
##   refresh()     al massimo 10 volte al secondo (2 con la finestra in secondo piano): aggiornare qui i numeri
##   close()       prima della rimozione


## Costruzione «a fette» delle schermate con molte righe (resoconto 100): con true (solo nel gioco vero, la imposta MainScreen)
## le righe si creano a ROWS_PER_SLICE per fotogramma invece che tutte nell'apertura, così niente blocco di 0,2-0,4 s sui PC lenti.
## Nei test resta false: l'apertura è sincrona e completa.
static var sliced_builds: bool = false
const ROWS_PER_SLICE := 14


func open(_params: Dictionary) -> void:
	pass


func refresh() -> void:
	pass


func close() -> void:
	pass


## True se la schermata non ha uno scorrimento proprio e può essere più alta dell'area: MainScreen la mette in un ScrollContainer.
func wants_scroll() -> bool:
	return false
