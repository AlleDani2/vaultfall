class_name UiType
extends RefCounted
## Gerarchia tipografica UNICA (revisione grafica 1.0, problema 2). Le dimensioni (px logici a scala 1,0) stanno qui e solo qui:
## `scripts/build_theme.gd` le legge per generare i temi e il codice che deve impostare un corpo a mano usa queste costanti.
## Sono pari: a 1,5× (1080p) restano px interi e il testo resta nitido. Nessuna sezione è più piccola del corpo.
##   PAGE     titolo di pagina (TitleLabel, Departure Mono: il pixel font va a multipli di 11 px)
##   SECTION  titolo di sezione (SectionLabel, Atkinson Bold, colore d'accento della sezione)
##   BODY     corpo del testo (tema: default_font_size)
##   NOTE     note, aiuti, etichette secondarie (MutedLabel, IntroHint): è anche il minimo leggibile su Steam Deck (1280×800)
## Pesi: PAGE = Departure Mono Regular · SECTION = Atkinson Bold · BODY/NOTE = Atkinson Regular · cifre = Atkinson Medium.

const PAGE := 22
const SECTION := 18
const BODY := 16
const NOTE := 14
const MIN := 14                      ## nessun testo visibile (fuori dal menù laterale/barra alta/binario) scende sotto questo corpo
const NUMBER_BIG := 22               ## cifre grandi dei riquadri di sintesi (stesso corpo del titolo di pagina)
const NUMBER_HERO := 44              ## il numero-evento di una schermata (Polvere Stellare del Prestigio, punti Talento): il doppio di NUMBER_BIG
