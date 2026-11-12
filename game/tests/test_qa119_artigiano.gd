extends GutTest
## QA119 (playtest ARTIGIANO, docs/audit_2026-10-22/119_PLAYTEST_ARTIGIANO.md): regressioni dei difetti trovati giocando
## da mansioni/costruzione/Tenuta/Mercato. Ogni test porta il numero del difetto (Q119-n).


## Q119-1: ogni oggetto ha un'icona vera (per id o dal percorso dei dati): il Sacchetto di Rune finiva sul quadrato colorato.
func test_q119_1_ogni_oggetto_ha_icona() -> void:
	var senza: PackedStringArray = []
	var n := 0
	for t in DataRegistry.all_items().values():
		n += 1
		if not IconLib.item_has_art(str(t.id)):
			senza.append(str(t.id))
	assert_gt(n, 500, "gli oggetti ci sono")
	assert_eq(senza.size(), 0, "oggetti sul segnaposto colorato: " + ", ".join(senza))


## Q119-3: le Commesse giornaliere «Produci N» non scelgono azioni a costruzione singola (300 Spade da premere una a una).
func test_q119_commesse_produci_senza_pezzi_singoli() -> void:
	var c := ContractSystem.new()
	var ctx := SystemContext.make(DataRegistry, {"unlocks": [], "skills": {}}, ModifierStack.new(), RngStreams.new(5), EventBus)
	c.ctx = ctx
	for a in c._static_actions("craft"):
		assert_false(bool(a.get("single_craft", false)), "azione singola tra le candidate: " + str(a.id))
	assert_gt((c._static_actions("craft") as Array).size(), 0)


## Q119-4: «A cosa serve» dei materiali che non sono ingredienti ma servono altrove (Tenuta, Luoghi Segreti, Ere):
## prima dicevano «nessuna mansione lo usa direttamente, tienilo o vendilo» (Granito, Lucchetti, Essenza d'Era, Frammento di Mappa).
func test_q119_materiali_con_altri_usi() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	TranslationServer.set_locale("it")
	for id in ["granite", "padlock_bronze", "padlock_steel", "era_essence", "map_fragment"]:
		var p := ItemUse.purpose(id)
		assert_false(p.contains("nessuna mansione"), "testo sbagliato per " + id + ": " + p)
		assert_false(p.contains("UI_"), "chiave nuda per " + id + ": " + p)
	assert_true(ItemUse.purpose("granite").contains("Tenuta"))
	assert_true(ItemUse.purpose("era_essence").contains("Era"))
	assert_true(ItemUse.purpose("map_fragment").contains("Segreti"))
	TranslationServer.set_locale("en")
	assert_true(ItemUse.purpose("granite").contains("Estate"))
	TranslationServer.set_locale("it")


## Q119-5: nessuna chiave nuda nei testi «A cosa serve» di nessun oggetto (le pozioni di gruppo/mansione mostravano
## «(UI_USE_SCOPE_SKILL_GROUP:ARTISAN)») e le descrizioni dei bonus sono nomi brevi, senza formule.
func test_q119_purpose_senza_chiavi_nude_ne_formule() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for t in DataRegistry.all_items().values():
			var p := ItemUse.purpose(str(t.id))
			assert_false(p.contains("UI_"), "chiave nuda (%s) %s: %s" % [loc, t.id, p])
			assert_false(p.contains("valore/100") or p.contains("value/100"), "formula nel testo: %s: %s" % [t.id, p])
	TranslationServer.set_locale("it")


## Q119-6: i testi dei bonus per il giocatore (Guardaroba, Album, Talenti, Prestigio) usano nomi brevi:
## nessuna formula «(durata = base / (1 + valore/100))» né tetti «(cap 50%)» dentro le frasi.
func test_q119_bonus_senza_formule_nei_testi() -> void:
	TranslationServer.set_locale("it")
	for k in ["skill_haste_pct:woodcutting", "skill_double_pct:fishing", "skill_save_pct:alchemy", "combat_haste_pct", "crate_find_pct:all",
			"combat_crit_chance_pct", "key_craft_save_pct"]:
		var txt := CrateUi.mod_text({"key": k, "value": 1.5})
		assert_false(txt.contains("(") or txt.contains("durata ="), "formula nel testo: " + txt)
		var t2 := BonusSummary.effect_text({"key": k, "value": 1.5})
		assert_false(t2.contains("(") or t2.contains("durata ="), "formula nel testo: " + t2)
		assert_true(t2.contains("1,5") or t2.contains("1.5"), "il valore c'e': " + t2)
	assert_true(CrateUi.mod_text({"key": "skill_haste_pct:woodcutting", "value": 0.68}).contains("Taglialegna"))
	assert_true(CrateUi.mod_text({"key": "skill_haste_pct:woodcutting", "value": 0.68}).ends_with("%"))


## Q119-7: testi italiani di genere neutro verso chi gioca: niente «sei stato», «non sei pronto», «Sicuro?», «Benvenuto» riferiti a te.
func test_q119_testi_italiani_genere_neutro() -> void:
	var rx := RegEx.new()
	rx.compile("(?i)(\\bsei (stato|stata|pronto|pronta|sicuro|sicura|arrivato|arrivata|tornato|tornata|rimasto|rimasta|bloccato|bloccata|stanco|stanca|morto|morta|diventato|diventata|riuscito|riuscita|entrato|entrata)\\b|\\bsicur[oa]\\?|\\b(bentornat[oa])\\b|\\bti sei (svegliato|svegliata|perso|persa|addormentato|addormentata)\\b)")
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	assert_not_null(f)
	var bad: PackedStringArray = []
	var n := 0
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3:
			continue
		n += 1
		var m := rx.search(row[2])
		if m != null:
			bad.append("%s: «%s»" % [row[0], m.get_string()])
	assert_gt(n, 3000, "il CSV e' stato letto")
	assert_eq(bad.size(), 0, "forme di genere nei testi italiani: " + "; ".join(bad.slice(0, 8)))


## Q119-8: i candidati della Taverna e i mercenari già assunti hanno nomi diversi tra loro (due «Vanda» si confondevano).
func test_q119_mercenari_nomi_distinti() -> void:
	assert_true(Game.new_game(1, "normal", 11))
	var mc := Game.system("mercenaries") as MercenarySystem
	assert_not_null(mc)
	for round_n in 60:
		mc._refill_board()
		var names: Array = []
		for c in mc.state.board.candidates:
			assert_false(names.has(str(c.name)), "nome doppio tra i candidati: " + str(c.name))
			names.append(str(c.name))
		for m in mc.state.roster:
			assert_false(names.has(str(m.name)), "candidato con il nome di un mercenario assunto: " + str(m.name))
		# assume il primo candidato direttamente nella squadra (senza oro) per riempirla
		if mc.state.roster.size() < 7:
			var c0: Dictionary = (mc.state.board.candidates as Array)[0]
			mc.state.roster.append(c0.duplicate(true))


## Q119-9: partire con una costruzione singola e restare via 8 h dava 1 pezzo e nessuna spiegazione: ora il «Rieccoti» dice
## perché si è fermata e come fare (Coda).
func test_q119_rieccoti_spiega_costruzione_singola() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	TranslationServer.set_locale("it")
	var report := {"skills": {"skill": "smithing", "action": "smith_sickle_copper", "completions": 1, "items": {"sickle_copper": 1},
		"xp": 8.0, "level_from": 3, "level_to": 3, "seconds": 28800.0, "stopped": "single", "crates": 0}}
	var wb := WelcomeBack.build(28800.0, report, DataRegistry, 12.0 * 3600.0)
	var found := false
	for sec in wb.sections:
		for line in sec.lines:
			if str(line).contains("Coda") and str(line).contains("per volta"):
				found = true
	assert_true(found, "il Rieccoti spiega la costruzione singola e la Coda: " + str(wb.sections))


## Q119-10: «Come si usa» non contraddice la riga sul Mercato: le Casse si vendono (valgono poco, docs/10 R-EC-6), le chiavi no.
func test_q119_come_si_usa_coerente_con_vendibilita() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for t in DataRegistry.all_items().values():
			var how := ItemUse.howto(str(t.id)).to_lower()
			var sellable := bool(t.get("tradeable", true)) and float(t.get("value", 0)) > 0.0
			if sellable and str(t.category) in ["crate", "key"]:
				assert_false(how.contains("non si vend") or how.contains("never sold") or how.contains("cannot be sold"),
					"«Come si usa» dice che non si vende ma il Mercato lo compra: %s (%s): %s" % [t.id, loc, how])
	TranslationServer.set_locale("it")


## Q119-11: le finestre di conferma hanno titolo e pulsanti tradotti e il testo va a capo (la conferma della Rifondazione era
## «Please Confirm...» / «Cancel» in inglese con la frase tagliata a destra).
func test_q119_finestre_di_conferma_tradotte_e_a_capo() -> void:
	var d := ConfirmationDialog.new()
	DialogKit.style_confirm(d)
	assert_true(d.dialog_autowrap)
	assert_gte(d.min_size.x, 400)
	TranslationServer.set_locale("it")
	assert_eq(TranslationServer.translate(d.title), "Conferma")
	assert_eq(TranslationServer.translate(d.cancel_button_text), "Annulla")
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate(d.title), "Please confirm")
	TranslationServer.set_locale("it")
	d.free()
	# ogni file che crea una ConfirmationDialog o usa DialogKit o ne imposta il titolo
	var bad: PackedStringArray = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var txt := FileAccess.get_file_as_string(dir + "/" + f)
			if txt.contains("ConfirmationDialog.new()") and not (txt.contains("DialogKit.style_confirm") or txt.contains(".title =")):
				bad.append(dir + "/" + f)
	assert_eq(bad.size(), 0, "ConfirmationDialog senza titolo tradotto: " + ", ".join(bad))


## Q119-12: «Attrezzo: di base» ha un suggerimento che dice dove si costruisce un attrezzo migliore (dai dati).
func test_q119_attrezzo_di_base_dice_dove_si_costruisce() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	TranslationServer.set_locale("it")
	var scr: Node = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"skill": "woodcutting"})
	await get_tree().process_frame
	scr.refresh()
	var tip := str(scr.get("_tool_l").tooltip_text)
	assert_true(tip.contains("Forgiatura"), "il suggerimento dice dove si forgia l'ascia: " + tip)
	assert_false(tip.contains("{") or tip.contains("UI_"), tip)


## Q119-13: un Apprendista non può essere assegnato a una costruzione singola: prima ne faceva ~320 l'ora (Spade di Rame),
## scavalcando «una costruzione per volta» (Deposito pieno di pezzi e profitto automatico). Slot già assegnati nei vecchi
## salvataggi tornano liberi al caricamento.
func test_q119_apprendisti_non_costruiscono_pezzi_singoli() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var ap := Game.system("apprentices") as ApprenticeSystem
	assert_not_null(ap)
	var singles := 0
	for aid in DataRegistry.all_actions():
		if bool(DataRegistry.action(str(aid)).get("single_craft", false)):
			singles += 1
			assert_eq(ap.can_assign(str(aid)), "UI_APPRENTICES_REASON_SINGLE", "assegnabile ma e' un pezzo singolo: " + str(aid))
	assert_gt(singles, 100, "ci sono molte azioni a costruzione singola")
	# vecchio salvataggio: lo slot con una spada torna libero, quello con i lingotti resta
	var st: Dictionary = {"slots": [{"action": "smith_sword_copper", "progress_s": 1.0, "carry": {}}, {"action": "smelt_copper", "progress_s": 0.0, "carry": {}}]}
	ap.from_state(st)
	assert_eq(str(ap.state.slots[0].action), "")
	assert_eq(str(ap.state.slots[1].action), "smelt_copper")
