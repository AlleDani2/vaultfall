extends GutTest
## FEEDBACK EQUIP-UI (giocatore reale): Deposito con marcatore «E», Eroe a slot disegnati (paper-doll) con elenco dei soli pezzi
## compatibili, un solo pezzo per slot (anche due copie identiche), blocco «Cibo» del Combattimento con scelta, soglia e scorta.
## Resoconto: docs/audit_2026-10-22/106_RESOCONTO_EQUIP_UI.md.

const HERO := "res://src/ui/screens/HeroScreen.tscn"
const BANK := "res://src/ui/screens/BankScreen.tscn"
const COMBAT := "res://src/ui/screens/CombatScreen.tscn"

var _old_dir: String
var combat: CombatSystem
var bank: BankSystem


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_equip_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 7))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 25, "record_level": 25, "stars": 0, "perks": {}, "unlocked": true}
	(GameState.data.unlocks as Array).append_array(["feature:combat", "feature:market", "zone:saltreach", "skill:hero", "skill:cooking"])
	combat = Game.system("combat") as CombatSystem
	bank = Game.system("bank") as BankSystem


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	return s


## Il Deposito di una nuova partita ha già un po' di cibo: lo si toglie per partire da zero.
func _clear_food() -> void:
	for it in DataRegistry.items_by_category("food"):
		var n := bank.count(str(it.id))
		if n > 0:
			bank.remove(str(it.id), n)
	for i in combat.food_slots().size():
		combat.set_food(i, "")


func _worn_count(uid: String) -> int:
	var n := 0
	for slot in CombatSystem.EQUIP_SLOTS:
		if slot != "ammo" and combat.equipped(slot) == uid:
			n += 1
	return n


# ------------------------------------------------------------------ un solo pezzo per slot (sistema)

func test_un_solo_pezzo_per_slot_il_nuovo_sostituisce_il_vecchio() -> void:
	var a := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	var b := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	assert_true(combat.equip(a))
	assert_true(combat.equip(b))
	assert_eq(combat.equipped("helm"), b, "lo slot ha un solo pezzo: l'ultimo")
	assert_false(combat.is_equipped(a), "il vecchio non è più indossato")
	assert_false(bank.get_instance(a).is_empty(), "…ma resta nel Deposito")
	assert_eq(_worn_count(a), 0)
	assert_eq(_worn_count(b), 1)
	assert_eq(combat.worn_slot(b), "helm")
	assert_eq(combat.worn_slot(a), "")


func test_due_copie_identiche_non_stanno_nello_stesso_slot_ne_in_due_slot() -> void:
	var a := bank.add_instance({"def": "plate_helm_copper"})
	assert_true(combat.equip(a))
	assert_true(combat.equip(a), "rimetterlo è innocuo")
	assert_eq(_worn_count(a), 1)
	assert_false(combat.equip_check(a, "ring")["ok"], "un elmo non va in uno slot anello")
	# anelli: due slot, due anelli; lo stesso anello non sta in entrambi
	var r1 := bank.add_instance({"def": "ring_might_t1"})
	var r2 := bank.add_instance({"def": "ring_might_t1"})
	var r3 := bank.add_instance({"def": "ring_might_t1"})
	assert_true(combat.equip(r1))
	assert_true(combat.equip(r2))
	assert_eq([combat.equipped("ring"), combat.equipped("ring2")], [r1, r2], "uno per slot")
	assert_false(combat.equip(r1, "ring2"), "lo stesso anello non va anche nell'altro slot")
	assert_eq(combat.equipped("ring2"), r2)
	assert_eq(str(combat.equip_check(r1, "ring2").why), "UI_EQ_WHY_WORN")
	assert_true(combat.equip(r3, "ring2"), "sostituisce lo slot scelto")
	assert_eq([combat.equipped("ring"), combat.equipped("ring2")], [r1, r3])
	assert_false(combat.is_equipped(r2))
	assert_false(bank.get_instance(r2).is_empty())


func test_controllo_equip_dice_il_perche() -> void:
	GameState.data.skills["hero"].level = 1
	var gear := bank.add_instance({"def": "plate_helm_copper"})
	assert_true(combat.equip_check(gear).ok)
	var tier2 := ""
	for it in DataRegistry.items_by_category("equipment"):
		if int(it.equipment.get("level_req", 1)) >= 30 and str(it.equipment.slot) == "helm":
			tier2 = str(it.id)
			break
	assert_ne(tier2, "")
	var hi := bank.add_instance({"def": tier2})
	var chk := combat.equip_check(hi)
	assert_false(chk.ok)
	assert_eq(str(chk.why), "UI_HERO_LEVEL_REQ")
	assert_gt(int(chk.args.n), 1)
	assert_false(combat.equip(hi), "equip() è d'accordo con equip_check()")
	# arma a due mani e mano secondaria
	var shield := bank.add_instance({"def": "shield_copper"})
	var two := bank.add_instance({"def": "greatsword_copper"})
	var one := bank.add_instance({"def": "sword_copper"})
	assert_true(combat.equip(one))
	assert_true(combat.equip(shield))
	assert_true(combat.equip(two))
	assert_eq(combat.equipped("offhand"), "", "a due mani: la mano secondaria si libera")
	assert_false(bank.get_instance(shield).is_empty(), "e lo scudo resta nel Deposito")
	assert_eq(str(combat.equip_check(shield).why), "UI_HERO_TWO_HANDED")
	assert_false(combat.equip(shield))


# ------------------------------------------------------------------ schermata Eroe a slot disegnati

func test_eroe_ha_uno_slot_disegnato_per_ogni_slot_dei_dati() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	for slot in CombatSystem.EQUIP_SLOTS:
		assert_true(doll.slot_buttons.has(slot), "slot " + slot)
		var b: EquipSlotButton = doll.slot_buttons[slot]
		assert_ne(b.get_theme_stylebox("normal"), null, "riquadro con bordo: " + slot)
		assert_true(b.custom_minimum_size.x >= 80.0)
	for slot in EquipDoll.SLOTS:
		assert_true(EquipDoll.GRID.has(slot), "posizione nella figura: " + slot)
		assert_false(EquipDoll.short_title(slot).begins_with("UI_EQ_SLOT_"), "nome tradotto: " + slot)


func test_slot_vuoto_si_vede_e_dice_quanti_pezzi_adatti_ci_sono() -> void:
	bank.add_instance({"def": "plate_gloves_copper"})
	bank.add_instance({"def": "plate_gloves_copper"})
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	var gl: EquipSlotButton = doll.slot_buttons["gloves"]
	assert_eq(gl.item_text(), Loc.tf("UI_EQ_AVAILABLE", {"n": 2}), "slot vuoto evidenziato con il numero di pezzi")
	var boots: EquipSlotButton = doll.slot_buttons["boots"]
	assert_eq(boots.item_text(), tr("UI_EQ_EMPTY"), "senza pezzi: «Vuoto»")


func test_elenco_dello_slot_ha_solo_pezzi_compatibili_con_motivi_e_codici() -> void:
	var g1 := bank.add_instance({"def": "plate_gloves_copper"})
	var g2 := bank.add_instance({"def": "plate_gloves_copper"})
	bank.add_instance({"def": "plate_helm_copper"})
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	doll._select_slot("gloves")
	assert_eq(doll._entries.size(), 2, "solo guanti")
	var tags: Array = []
	for e in doll._entries:
		assert_eq(str(DataRegistry.item(str(e.def)).equipment.slot), "gloves")
		tags.append(str(e.tag))
	assert_true(str(tags[0]).contains("#") and str(tags[1]).contains("#"), "due Manopole uguali: codice breve per distinguerle")
	assert_ne(tags[0], tags[1])
	# indosso la prima: nell'elenco resta solo l'altra e il pezzo indossato è nella scheda dello slot
	doll.picked_key = g1
	assert_true(doll._do_equip(g1))
	assert_eq(combat.equipped("gloves"), g1)
	assert_eq(doll._entries.size(), 1)
	assert_eq(str(doll._entries[0].key), g2)
	assert_true(doll._cur_name.text.contains("#"), "il pezzo indossato porta il suo codice")
	# sostituzione dall'elenco: l'altra copia prende il posto, la prima torna tra i disponibili
	assert_true(doll._do_equip(g2))
	assert_eq(combat.equipped("gloves"), g2)
	assert_eq(doll._entries.size(), 1)
	assert_eq(str(doll._entries[0].key), g1)
	# tasto destro sullo slot = togli (resta nel Deposito)
	doll._on_slot_right_click(Vector2.ZERO, "gloves")
	assert_eq(combat.equipped("gloves"), "")
	assert_false(bank.get_instance(g2).is_empty())
	assert_eq(doll._entries.size(), 2)


func test_elenco_mostra_le_restrizioni_di_livello() -> void:
	GameState.data.skills["hero"].level = 1
	var hi := ""
	for it in DataRegistry.items_by_category("equipment"):
		if int(it.equipment.get("level_req", 1)) >= 30 and str(it.equipment.slot) == "helm":
			hi = str(it.id)
			break
	var uid := bank.add_instance({"def": hi})
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	doll._select_slot("helm")
	var e := doll._entry_by_key(uid)
	assert_false(e.is_empty())
	assert_false(bool(e.chk.ok))
	assert_string_contains(str(e.info), str(int(DataRegistry.item(hi).equipment.level_req)), "la riga dice il livello che serve")
	doll.picked_key = uid
	doll._refresh_action()
	assert_true(doll._equip_btn.disabled, "non si può equipaggiare")
	assert_true(doll._why_lbl.visible)
	assert_false(doll._do_equip(uid))
	assert_eq(combat.equipped("helm"), "")


func test_trascinamento_su_slot_sbagliato_rifiutato_su_slot_giusto_equipaggia() -> void:
	var helm := bank.add_instance({"def": "plate_helm_copper"})
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	var body_slot: EquipSlotButton = doll.slot_buttons["body"]
	var helm_slot: EquipSlotButton = doll.slot_buttons["helm"]
	assert_false(body_slot._can_drop_data(Vector2.ZERO, {"equip_uid": helm}), "l'elmo non va sulla corazza")
	assert_true(helm_slot._can_drop_data(Vector2.ZERO, {"equip_uid": helm}))
	assert_false(helm_slot._can_drop_data(Vector2.ZERO, {"altro": 1}))
	helm_slot._drop_data(Vector2.ZERO, {"equip_uid": helm})
	assert_eq(combat.equipped("helm"), helm)


func test_munizioni_e_utensili_hanno_il_loro_slot() -> void:
	var axe := bank.add_instance({"def": "axe_copper"})
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	assert_true(doll.slot_buttons.has("tool:woodcutting"))
	doll._select_slot("tool:woodcutting")
	assert_eq(doll._entries.size(), 1)
	assert_true(doll._do_equip(axe))
	assert_eq(doll.worn_in("tool:woodcutting"), axe)
	assert_eq(combat.worn_slot(axe), "tool:woodcutting")
	doll._on_slot_right_click(Vector2.ZERO, "tool:woodcutting")
	assert_eq(doll.worn_in("tool:woodcutting"), "")


func test_nel_dungeon_non_si_cambia_e_la_schermata_lo_dice() -> void:
	var helm := bank.add_instance({"def": "plate_helm_copper"})
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll: EquipDoll = hs._doll
	assert_false(doll._dungeon_lbl.visible)
	assert_true(combat.equip_check(helm).ok)
	GameState.data.activity = {"type": "combat", "mode": "dungeon", "zone": "x", "monster": ""}
	doll.refresh(true)
	assert_true(combat.in_combat_blocking())
	assert_false(combat.equip_check(helm).ok)
	assert_eq(str(combat.equip_check(helm).why), "UI_UIA_ACT_WHY_DUNGEON")
	assert_true(doll._dungeon_lbl.visible, "la schermata dice perché non si cambia")
	assert_false(combat.equip(helm))
	GameState.data.activity = {}


# ------------------------------------------------------------------ Deposito

func test_deposito_marca_gli_equipaggiati_e_distingue_le_copie_uguali() -> void:
	var g1 := bank.add_instance({"def": "plate_gloves_copper"})
	var g2 := bank.add_instance({"def": "plate_gloves_copper"})
	var helm := bank.add_instance({"def": "plate_helm_copper"})
	combat.equip(g1)
	var bs := _open(BANK)
	bs._on_group("gear")                     # F15: l'equipaggiamento sta nell'Armeria
	await wait_process_frames(2)
	var e1: Dictionary = {}
	var e2: Dictionary = {}
	var eh: Dictionary = {}
	for e in bs._entries:
		if e.uid == g1:
			e1 = e
		elif e.uid == g2:
			e2 = e
		elif e.uid == helm:
			eh = e
	assert_eq(str(e1.worn), "gloves", "equipaggiato: slot Guanti")
	assert_eq(str(e1.worn_name), tr("UI_HERO_SLOT_GLOVES"))
	assert_eq(str(e2.worn), "", "la copia non indossata non è marcata")
	assert_eq(str(eh.worn), "")
	assert_ne(str(e1.code), "", "due Manopole uguali: codice breve")
	assert_ne(str(e1.code), str(e2.code))
	assert_eq(str(eh.code), "", "l'elmo è unico: niente codice")
	# indossare/togliere aggiorna le righe senza che cambi il Deposito
	combat.equip(helm)
	bs.refresh()
	for e in bs._entries:
		if e.uid == helm:
			assert_eq(str(e.worn), "helm")
	# filtro «solo equipaggiati» e ordinamento «equipaggiati prima»
	bs._on_only_worn(true)
	for e in bs._entries:
		assert_ne(str(e.worn), "", "con il filtro restano solo gli indossati")
	assert_eq(bs._entries.size(), 2)
	bs._on_only_worn(false)
	bs._on_sort(bs.SORTS.find(bs.SORTS.filter(func(s: Dictionary) -> bool: return s.id == "worn")[0]))
	assert_ne(str(bs._entries[0].worn), "", "gli indossati vengono prima")
	assert_ne(str(bs._entries[1].worn), "")
	assert_eq(str(bs._entries[2].worn), "")


func test_deposito_dettaglio_dice_equipaggiato_e_offre_equipaggia_o_togli() -> void:
	var g1 := bank.add_instance({"def": "plate_gloves_copper"})
	var g2 := bank.add_instance({"def": "plate_gloves_copper"})
	combat.equip(g1)
	var bs := _open(BANK)
	bs._on_group("gear")                     # F15: l'equipaggiamento sta nell'Armeria
	await wait_process_frames(2)
	bs._selected = g1
	bs._refresh_detail()
	var txt := _texts(bs._detail_box)
	assert_string_contains(txt, Loc.tf("UI_EQ_BANK_D_WORN", {"slot": tr("UI_HERO_SLOT_GLOVES")}))
	var btn := bs._detail_box.find_child("WornButton", true, false) as Button
	assert_not_null(btn)
	assert_eq(btn.text, "UI_EQ_BANK_UNEQUIP")
	btn.pressed.emit()
	assert_eq(combat.equipped("gloves"), "", "«Togli» dal Deposito")
	bs._selected = g2
	bs._refresh_detail()
	assert_string_contains(_texts(bs._detail_box), tr("UI_EQ_BANK_D_NOT_WORN"))
	btn = bs._detail_box.find_child("WornButton", true, false) as Button
	assert_eq(btn.text, "UI_EQ_BANK_EQUIP")
	btn.pressed.emit()
	assert_eq(combat.equipped("gloves"), g2, "«Equipaggia» dal Deposito")


func test_tooltip_dell_oggetto_dice_dove_e_indossato() -> void:
	var g1 := bank.add_instance({"def": "plate_gloves_copper"})
	var g2 := bank.add_instance({"def": "plate_gloves_copper"})
	combat.equip(g1)
	var worn := ItemTooltip.build("plate_gloves_copper", bank.get_instance(g1))
	var other := ItemTooltip.build("plate_gloves_copper", bank.get_instance(g2))
	var wt := ItemTooltip.to_bbcode(worn)
	assert_string_contains(wt, Loc.tf("UI_EQ_BANK_BADGE_TIP", {"slot": tr("UI_HERO_SLOT_GLOVES")}))
	assert_false(ItemTooltip.to_bbcode(other).contains(Loc.tf("UI_EQ_BANK_BADGE_TIP", {"slot": tr("UI_HERO_SLOT_GLOVES")})))


func _texts(node: Node) -> String:
	var out := ""
	for c in node.get_children():
		if c is Label or c is Button or c is RichTextLabel:
			out += str(c.text) + "\n"
		out += _texts(c)
	return out


# ------------------------------------------------------------------ Cibo

func test_blocco_cibo_ha_gli_slot_dell_eroe_e_assegna_dal_deposito() -> void:
	_clear_food()
	bank.add("food_bleak", 12, "test")
	bank.add("food_carp", 5, "test")
	var cs := _open(COMBAT)
	await wait_process_frames(2)
	var fp: FoodPanel = cs._food_panel
	assert_eq(fp._slot_btns.size(), combat.food_slots().size(), "uno slot per slot del cibo dei dati")
	assert_string_contains(fp._intro.text, tr("UI_EQ_FOOD_INTRO").substr(0, 20), "istruzione esplicita")
	fp._open_picker(0)
	assert_eq(fp._pick_defs.size(), 2, "il menù elenca i cibi del Deposito")
	fp._on_food_picked(fp._pick_defs.find("food_carp"))
	assert_eq(combat.food_slots()[0], "food_carp")
	# lo stesso cibo in un altro slot lo sposta: mai due slot con lo stesso cibo
	fp._open_picker(1)
	fp._on_food_picked(fp._pick_defs.find("food_carp"))
	assert_eq(combat.food_slots()[1], "food_carp")
	assert_eq(combat.food_slots()[0], "")
	# svuota con il tasto destro
	fp._clear_slot(1)
	assert_eq(combat.food_slots()[1], "")


func test_blocco_cibo_soglia_e_scorta() -> void:
	_clear_food()
	bank.add("food_bleak", 12, "test")
	combat.set_food(0, "food_bleak")
	var cs := _open(COMBAT)
	await wait_process_frames(2)
	var fp: FoodPanel = cs._food_panel
	fp.refresh(true)
	assert_string_contains(fp._stock.text, NumberFormat.fmt(12), "scorta: porzioni nel Deposito")
	assert_true(fp._eat_slider.max_value >= 2.0)
	fp._eat_slider.value = 5.0
	assert_eq(int(combat.state.eat_pct), 5, "lo slider regola la soglia")
	assert_string_contains(fp._eat_label.text, "5")
	# durata contro un mostro che toglie vita
	var zone := str(DataRegistry.table("zones")[0].id)
	var worst := ""
	for m in combat.monsters_of(zone):
		var s := combat.idle_safety(str(m.id))
		if not s.is_empty() and bool(s.get("losing", false)) and float(s.food_hours) > 0.0:
			worst = str(m.id)
	# precondizione dei dati (SHARK 1.0 #11: prima il test si saltava in silenzio con pending()): un mostro della prima zona consuma cibo
	assert_false(worst.is_empty(), "almeno un mostro della prima zona consuma cibo con questo equipaggiamento")
	if worst.is_empty():
		return
	fp.target_monster = worst
	fp.refresh(true)
	assert_string_contains(fp._stock.text, tr("UI_EQ_FOOD_LASTS").split("{t}")[0].strip_edges(), "«dura circa…»")


func test_blocco_cibo_senza_scorte_rimanda_a_cucina_e_mercato() -> void:
	_clear_food()
	var cs := _open(COMBAT)
	await wait_process_frames(2)
	var fp: FoodPanel = cs._food_panel
	fp.refresh(true)
	assert_true(fp._empty_box.visible)
	assert_string_contains(fp._empty_lbl.text, tr("UI_EQ_FOOD_NONE_GO"))
	var labels: Array = []
	for b in fp._go_row.get_children():
		labels.append((b as Button).text)
	assert_has(labels, tr("UI_EQ_GO_MARKET"), "pulsante Vai al Mercato (sbloccato)")
	var asked: Array = []
	EventBus.screen_requested.connect(func(id: String, _p: Dictionary) -> void: asked.append(id))
	for b in fp._go_row.get_children():
		if (b as Button).text == tr("UI_EQ_GO_MARKET"):
			(b as Button).pressed.emit()
	assert_eq(asked, ["market"])
	# con cibo nel Deposito ma slot vuoti: invito ad assegnarlo
	bank.add("food_bleak", 3, "test")
	fp.refresh(true)
	assert_string_contains(fp._empty_lbl.text, tr("UI_EQ_FOOD_ASSIGN_HINT"))
	# con cibo assegnato il messaggio sparisce
	combat.set_food(0, "food_bleak")
	fp.refresh(true)
	assert_false(fp._empty_box.visible)


func test_blocco_cibo_munizioni_e_pozione_solo_nella_scheda_combattimento() -> void:
	var cs := _open(COMBAT)
	var hs := _open(HERO)
	await wait_process_frames(2)
	assert_true((cs._food_panel as FoodPanel).show_supplies)
	assert_false((hs._food_panel as FoodPanel).show_supplies, "nell'Eroe munizioni e pozione hanno già il loro slot")
	assert_not_null((cs._food_panel as FoodPanel)._supplies)


# ------------------------------------------------------------------ testi

func test_tutti_i_testi_nuovi_hanno_italiano_e_inglese() -> void:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	assert_not_null(f)
	var seen := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and str(row[0]).begins_with("UI_EQ_"):
			seen += 1
			assert_ne(str(row[1]).strip_edges(), "", str(row[0]) + " EN")
			assert_ne(str(row[2]).strip_edges(), "", str(row[0]) + " IT")
	assert_gt(seen, 60)


# ------------------------------------------------------------------ regressione: il dettaglio non distrugge un menù aperto

func test_dettaglio_del_deposito_non_chiude_il_menu_del_tomo_a_ogni_aggiornamento() -> void:
	var tome := ""
	for k in DataRegistry.all_items():
		if DataRegistry.item(str(k)).has("tome"):
			tome = str(k)
			break
	assert_ne(tome, "")
	bank.add(tome, 2, "test")
	(GameState.data.skills as Dictionary)["woodcutting"] = {"xp": 0.0, "level": 5, "record_level": 5, "stars": 0, "perks": {}, "unlocked": true}
	var bs := _open(BANK)
	await wait_process_frames(2)
	bs._selected = tome
	bs._refresh_detail()
	var opts: Array = bs._detail_box.find_children("*", "OptionButton", true, false)
	assert_gt(opts.size(), 0, "il menù «scegli la mansione» c'è")
	var opt: OptionButton = opts[0]
	if opt.item_count > 1:
		opt.select(1)
	var chosen := opt.selected
	opt.get_popup().popup()
	await wait_process_frames(1)
	assert_true(opt.get_popup().visible)
	# un'azione completata cambia oro e valore totale: il dettaglio NON si ricostruisce
	bank.add_gold(500)
	bs.refresh()
	await wait_process_frames(1)
	assert_true(is_instance_valid(opt) and opt.is_inside_tree(), "lo stesso menù è ancora lì")
	assert_true(opt.get_popup().visible, "…e aperto")
	assert_eq(opt.selected, chosen, "con la selezione intatta")
	# se cambia qualcosa di rilevante (quantità) mentre è aperto: si aspetta la chiusura, poi si aggiorna
	bank.add(tome, 1, "test")
	bs.refresh()
	assert_true(opt.is_inside_tree(), "aperto: niente ricostruzione")
	opt.get_popup().hide()
	bs.refresh()
	assert_true(_texts(bs._detail_box).contains("3"), "chiuso: il dettaglio si aggiorna (3 pezzi)")
