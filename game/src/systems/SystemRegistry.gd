class_name SystemRegistry
extends RefCounted
## UNICO punto in cui si agganciano i sistemi di gioco al ciclo di tick (docs/17 §5).
## Per aggiungere un sistema: creare src/systems/MioSystem.gd (extends GameSystem) e aggiungere UNA riga
## nella posizione giusta di SYSTEMS. L'ordine è l'ordine di esecuzione a ogni tick:
##   Activity (skill|combat) → Apprentices → Farming → Estate → Expeditions → Buffs/Timers →
##   Quests/Achievements (eventi accodati) → Unlocks
## Una riga per sistema, sempre con la virgola finale: due agenti che aggiungono sistemi diversi toccano
## righe diverse e il merge resta banale.

const SYSTEMS: PackedStringArray = [
	# --- Bank (Deposito e valute: prima di tutto, le attività vi depositano)
	"res://src/systems/BankSystem.gd",
	# --- Activity (skill | combat)
	"res://src/systems/SkillSystem.gd",
	"res://src/systems/CombatSystem.gd",
	"res://src/systems/BountySystem.gd",      # COMBAT-2 (M7): Caccia alle Taglie
	"res://src/systems/RunSystem.gd",         # CORSA (resoconto 91): Corsa a scelte del combattimento in zona
	"res://src/systems/CrateSystem.gd",       # CRATES (M4): in coda alla sezione Activity
	"res://src/systems/QueueSystem.gd",       # SKILLS-2 (M5): coda azioni, dopo le attività che avanza
	"res://src/systems/LoadoutSystem.gd",     # GAP-MECCANICHE (G15): set di equipaggiamento (solo azioni, nessun tick)
	# --- Apprentices
	"res://src/systems/ApprenticeSystem.gd",  # ESTATE (M6): apprendisti dell'Accademia
	# --- Farming
	"res://src/systems/FarmingSystem.gd",     # SKILLS-2 (M5): Orto e Frutteto a timer
	# --- Estate
	"res://src/systems/EstateSystem.gd",      # ESTATE (M6): Tenuta
	"res://src/systems/MarketSystem.gd",
	# --- Expeditions
	"res://src/systems/MercenarySystem.gd",   # ESTATE (M6): mercenari (prima delle spedizioni)
	"res://src/systems/ExpeditionSystem.gd",  # ESTATE (M6): spedizioni
	"res://src/systems/SecretSystem.gd",      # GUILD-2: Luoghi Segreti (esplorazioni a tempo)
	# --- Buffs / Timers
	"res://src/systems/BuffSystem.gd",
	"res://src/systems/PotionSystem.gd",      # SKILLS-2 (M5): pozioni a cariche e banchetti (usa BuffSystem)
	"res://src/coop/net/CoopBonusSystem.gd",  # COOP-2: copia dei bonus di gilda (guild:*) e cassetta in uscita
	# --- Prestige (PRESTIGE): dopo le attività e la Tenuta, prima delle missioni
	"res://src/systems/PrestigeSystem.gd",
	# --- Quests / Achievements
	"res://src/systems/QuestSystem.gd",
	"res://src/systems/ContractSystem.gd",    # PROGRESSIONE: Commesse giornaliere/settimanali (dopo QuestSystem: ne riceve gli eventi)
	"res://src/systems/CompendiumSystem.gd",  # GUILD-2: Imprese, Titoli, Famigli, cornici
	"res://src/systems/CodexSystem.gd",       # UI-A: registro del Compendio (oggetti visti, drop dei mostri, Stendardi/Emblemi)
	"res://src/systems/ModeSystem.gd",        # MODALITA': morte permanente (Estrema), titolo e cornice delle modalità
	"res://src/systems/SeasonalEventSystem.gd",  # EVENTI (T-11.3): eventi stagionali, valuta, missioni, Eco
	"res://src/coop/CoopSystem.gd",           # COOP-1: modalità Amici senza rete (compagni d'armi, Prova della settimana)
	"res://src/systems/AssistSystem.gd",      # UI-A: vendita automatica del Deposito e avviso del boss mondiale
	"res://src/systems/TutorialSystem.gd",    # TUTORIAL: passi del tutorial guidato già visti (sezione additiva `tutorial`)
	"res://src/systems/TimePushSystem.gd",    # UI F13: Sabbia del Custode (riserva di tempo spendibile a clic sull'azione in corso)
	# --- Unlocks
	"res://src/systems/UnlockSystem.gd",
]


static func create_all() -> Array[GameSystem]:
	var out: Array[GameSystem] = []
	for path in SYSTEMS:
		var script: GDScript = load(path)
		assert(script != null, "sistema non trovato: " + path)
		var inst: Object = script.new()
		assert(inst is GameSystem, "%s non estende GameSystem" % path)
		out.append(inst)
	return out
