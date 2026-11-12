class_name GameSystem
extends RefCounted
## Classe base di ogni sistema di gioco (docs/17 §2-5, CLAUDE.md regola 3). Leggere game/README_SISTEMI.md.
##
## Un sistema è una classe PURA (niente nodi, niente await, niente tempo reale): riceve dt dal ciclo a passo
## fisso, legge i dati da ctx.data, modifica SOLO la propria sezione di stato (`state`), usa ctx.modifiers e
## ctx.rng, ed emette segnali su ctx.events. Così è deterministico e testabile in GUT senza scena.
##
## Ciclo di vita (lo guida Simulation):
##   _init()              -> imposta id / state_key
##   setup()              -> una volta, dopo che ctx è assegnato (indici privati, connessioni ai segnali)
##   default_state()      -> sezione iniziale per una nuova partita (o per salvataggi che non la hanno)
##   from_state(section)  -> dopo nuova partita/caricamento: riceve il Dictionary VIVO di GameState.data[state_key]
##   tick(dt)             -> ogni passo fisso (0,1 s simulati), nell'ordine di SystemRegistry
##   simulate_offline(s)  -> tempo in blocco (offline, lag lungo); di base esegue tick a passi fissi
##   to_state()           -> prima di ogni salvataggio: ritorna la sezione da scrivere in GameState.data[state_key]
##   int_paths()          -> campi interi della sezione da normalizzare dopo il load (R-SAV-8)

## Identificatore unico del sistema (snake_case, es. "skills", "combat", "buffs").
var id: String = ""
## Sezione di GameState.data posseduta dal sistema ("" = nessuno stato salvato).
var state_key: String = ""
var enabled: bool = true
var ctx: SystemContext
## Riferimento alla sezione di stato (stesso oggetto di GameState.data[state_key]).
var state: Variant = null


func setup() -> void:
	pass


func default_state() -> Variant:
	return {}


func from_state(section: Variant) -> void:
	state = section


func to_state() -> Variant:
	return state


func tick(_dt: float) -> void:
	pass


## Tempo in blocco. L'implementazione di base è esatta ma lenta (tick a passi fissi): i sistemi con molte
## azioni la sostituiscono con una versione analitica (docs/17 §5, OfflineSimulator in M2).
## Ritorna un resoconto per la finestra "Bentornato" (chiavi libere, solo tipi JSON).
func simulate_offline(seconds: float) -> Dictionary:
	if not has_tick():
		return {}                  # tick() di base è vuoto: 864 000 chiamate a vuoto per 24 h non cambiano nulla
	var step := FixedStepClock.STEP
	var n := int(floor(seconds / step))
	for i in n:
		tick(step)
	return {}


## Dopo che TUTTI i sistemi hanno consumato il tempo offline (Simulation.run_offline, Hourglass): chi ha raccolto qualcosa
## da dire al Bentornato a fine giro (es. il Carro di Ritiro del Deposito) lo ritorna qui, nello stesso formato di
## simulate_offline. Di base niente.
func finish_offline() -> Dictionary:
	return {}


## R-OFF-6 (audit 84): assenza OLTRE il limite offline. Avanzano solo gli orologi di calendario (Commesse giornaliere e
## settimanali, limiti giornalieri dell'Emporio, rinnovi della bacheca): nessuna produzione, nessun guadagno. Di base non
## fa nulla; Game la chiama PRIMA di simulate_offline, così l'offline vero cade negli ultimi giorni dell'assenza.
func advance_calendar(_seconds: float) -> void:
	pass


## false nei sistemi che NON ridefiniscono tick() (puramente a eventi): l'offline di base li salta, invece di
## fare 864 000 chiamate a vuoto per 24 h.
func has_tick() -> bool:
	return true


## Percorsi interi RELATIVI alla sezione (stessa sintassi di SaveCodec.normalize: "a.b", "*", "[]").
func int_paths() -> PackedStringArray:
	return PackedStringArray()


## Come int_paths, ma «morbidi» (QA120): al caricamento i float interi tornano int, un valore non intero resta com'e' e NON rende il
## salvataggio corrotto. Per i campi che il codice produce sempre interi (indici, contatori) e che non devono cambiare tipo dopo
## salva e ricarica, senza rischiare di rifiutare un vecchio salvataggio.
func soft_int_paths() -> PackedStringArray:
	return PackedStringArray()
