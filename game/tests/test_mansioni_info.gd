extends GutTest
## Mansioni: la resa, le quantità richieste/possedute e le frasi di mancanza stanno IN VISTA (senza passare il mouse), in italiano e in
## inglese e anche a 1024×576 senza troncamenti (feedback giocatore: «non dice quanto dà, quanto ne ho, quanto ne serve»).
## Numeri dai dati e da SkillSystem.hourly (nessun numero di bilanciamento nel test); i testi si confrontano con ReqText/Loc.

const SCREEN := "res://src/ui/screens/SkillScreen.tscn"
const FARM := "res://src/ui/screens/FarmScreen.tscn"

var _old_dir: String
var _old_ts: String
var _old_settings_locale: Variant
var _old_size: Vector2i
var _old_fps: int


func before_all() -> void:
	_old_fps = Engine.max_fps
	Engine.max_fps = 0
	_old_size = get_tree().root.size


func after_all() -> void:
	Engine.max_fps = _old_fps


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_ts = TranslationServer.get_locale()
	_old_settings_locale = Settings.get_value("locale")
	SaveService.save_dir = "user://test_mansioni_info_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 6))
	Settings.set_value("seen_intro", [])
	_locale("it")


func after_each() -> void:
	_locale(_old_ts)
	Settings.set_value("locale", _old_settings_locale)
	Settings.set_value("seen_intro", [])
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _locale(l: String) -> void:
	TranslationServer.set_locale(l)
	Settings.set_value("locale", l)


func _open(skill: String, level: int = 0, w: float = 1100.0) -> Control:
	if level > 0:
		(Game.system("skills") as SkillSystem).state[skill]["level"] = level
	var s: Control = (load(SCREEN) as PackedScene).instantiate()
	var host := Control.new()
	add_child_autofree(host)
	host.size = Vector2(w, 700)
	host.add_child(s)
	s.open({"skill": skill})
	await wait_process_frames(3)
	return s


## Una ricetta di Forgiatura con almeno un ingrediente di quantità ≥ 2 (per avere «ne hai 1» contro «ne servono 2»).
func _recipe(skill: String, max_level: int, min_qty: int = 2) -> Dictionary:
	for a in DataRegistry.actions_for_skill(skill):
		if int(a.get("level_req", 1)) > max_level:
			continue
		for io in a.get("inputs", []):
			if int(io.qty) >= min_qty:
				return a
	return {}


func _give(item: String, n: int) -> void:
	(Game.system("bank") as BankSystem).add(item, n, "test")


func _plain(r: RichTextLabel) -> String:
	return r.get_parsed_text()


# ------------------------------------------------------------------ (1) resa sempre in vista

func test_resa_in_vista_senza_mouse() -> void:
	var sk := Game.system("skills") as SkillSystem
	var s := await _open("woodcutting", 5)
	var row: Dictionary = s._rows["wc_pine"]
	var give: Label = row.give
	assert_true(give.visible, "la riga «Dà» c'è sempre")
	assert_string_contains(give.text, ReqText.item_name("log_pine"), "dice COSA dà")
	assert_string_contains(give.text, "(ne hai 0)", "e quanto ne hai")
	var hr := sk.hourly("wc_pine")
	assert_string_contains(row.yield.text, NumberFormat.fmt(float(hr.xp)), "XP all'ora in vista")
	assert_string_contains(row.yield.text, NumberFormat.fmt(float(hr.items["log_pine"])), "pezzi all'ora in vista")
	var p := sk.profile_of("wc_pine")
	assert_string_contains(row.info.text, NumberFormat.fmt(float(p.xp)), "XP per azione in vista")
	assert_string_contains(row.info.text, NumberFormat.decimal(float(p.duration_s), 1, "it"), "tempo per azione in vista")
	assert_true((row.give as Control).is_visible_in_tree(), "senza hover")


func test_quantita_possedute_si_aggiornano() -> void:
	var s := await _open("woodcutting", 5)
	_give("log_pine", 53)
	for i in 6:
		s.refresh()
	assert_string_contains(s._rows["wc_pine"].give.text, "(ne hai 53)", "il prodotto posseduto compare sulla carta")


func test_intervallo_di_quantita_dai_dati() -> void:
	assert_eq(ReqText.qty_text(1), "1")
	assert_eq(ReqText.qty_text([1, 3]), "1–3")
	assert_eq(ReqText.qty_text([2, 2]), "2")
	var s := await _open("thievery", 1) if DataRegistry.get_def("skills", "thievery") != null else null
	if s != null:
		for aid in s._rows:
			assert_true(s._rows[aid].give.visible or not DataRegistry.action(str(aid)).has("gold"), "%s: l'oro per azione è in vista" % aid)


# ------------------------------------------------------------------ (2) ingredienti: servono N (hai M)

func test_ingredienti_servono_e_hai_it_en() -> void:
	var a := _recipe("smithing", 30)
	assert_false(a.is_empty())
	var aid := str(a.id)
	var io: Dictionary = {}
	for x in a.inputs:
		if int(x.qty) >= 2:
			io = x
			break
	for loc in ["it", "en"]:
		_locale(loc)
		var s := await _open("smithing", 30)
		var ingr: RichTextLabel = s._rows[aid].ingr
		var need := int(io.qty)
		_give(str(io.item), need - 1)
		s._dirty = true
		for i in 6:
			s.refresh()
		var txt := _plain(ingr)
		assert_true(ingr.visible, "gli ingredienti sono in vista (%s)" % loc)
		assert_string_contains(txt, ReqText.piece(str(io.item), need, need - 1), "servono N, ne hai M, ne mancano (%s)" % loc)
		assert_string_contains(txt, "ne hai" if loc == "it" else "you have")
		assert_string_contains(ingr.text, ReqText.WARN, "ambra se M < N (%s)" % loc)
		assert_string_contains(ingr.text, "[url", "il pezzo che manca porta a dove si ottiene (%s)" % loc)
		_give(str(io.item), 1)
		s._dirty = true
		for i in 6:
			s.refresh()
		assert_string_contains(_plain(ingr), ReqText.piece(str(io.item), need, need), "con la quantità giusta: servono N (hai N)")
		var ok_piece := ReqText.piece(str(io.item), need, need).replace("[", "[lb]")
		assert_true(ingr.text.contains(ok_piece), "e il pezzo è neutro, senza avvertimento")
		s.close()
		s.get_parent().queue_free()
		await wait_process_frames(1)
		(Game.system("bank") as BankSystem).remove(str(io.item), need)


func test_ambra_solo_se_manca_qualcosa() -> void:
	var a := _recipe("smithing", 30, 1)
	var s := await _open("smithing", 30)
	for io in a.inputs:
		_give(str(io.item), int(io.qty) * 2)
	s._dirty = true
	for i in 6:
		s.refresh()
	assert_false(s._rows[str(a.id)].ingr.text.contains(ReqText.WARN), "con tutto il necessario nessun colore di avvertimento")
	assert_eq(ReqText.short_inputs(a.inputs).size(), 0)


func test_frasi_di_mancanza_con_quantita_it_en() -> void:
	var nm := ReqText.item_name("log_pine")
	assert_eq(ReqText.missing_sentence("log_pine", 60, 48), "Ti mancano 12 %s: ne servono 60, ne hai 48" % nm)
	assert_eq(ReqText.missing_sentence("log_pine", 5, 4), "Ti manca 1 %s: ne servono 5, ne hai 4" % nm)
	assert_eq(ReqText.gold_sentence(500, 380), "Ti mancano 120 oro: ne servono 500, ne hai 380")
	_locale("en")
	nm = ReqText.item_name("log_pine")
	assert_eq(ReqText.missing_sentence("log_pine", 60, 48), "Missing 12 %s: you need 60, you have 48" % nm)
	assert_eq(ReqText.gold_sentence(500, 380), "You are 120 gold short: you need 500, you have 380")
	assert_eq(ReqText.level_text(30, 25), "Needs level 30 (yours: 25)")
	_locale("it")
	assert_eq(ReqText.level_text(30, 25), "Richiede livello 30 (il tuo: 25)")
	assert_string_contains(ReqText.level_sentence("Taglialegna", 30, 25), "30")
	assert_string_contains(ReqText.level_sentence("Taglialegna", 30, 25), "25")


func test_rifiuto_di_avvio_dice_quanto_manca() -> void:
	var a := _recipe("smithing", 30)
	var aid := str(a.id)
	var s := await _open("smithing", 30)
	watch_signals(EventBus)
	s._on_row_pressed(aid)
	assert_signal_emitted(EventBus, "notice")
	var params: Array = get_signal_parameters(EventBus, "notice")
	var msg := str(params[1])
	assert_string_contains(msg, "ne hai 0", "l'avviso dice quanto ne hai")
	assert_string_contains(msg, "ne servono", "e quanto ne serve")
	assert_false(msg == tr("UI_SKILLS_REASON_MATERIALS"), "non è più solo il messaggio generico")


func test_tooltip_resta_con_i_dettagli_extra() -> void:
	var a := _recipe("smithing", 30)
	var s := await _open("smithing", 30)
	var tip: String = (s._rows[str(a.id)].panel as Control).tooltip_text
	assert_string_contains(tip, "ne servono", "il suggerimento ha le frasi complete di mancanza")
	assert_string_contains(tip, ReqText.item_name(str(a.inputs[0].item)))


# ------------------------------------------------------------------ requisiti di livello

func test_livello_richiesto_e_attuale_it_en() -> void:
	for loc in ["it", "en"]:
		_locale(loc)
		var s := await _open("woodcutting")
		var locked := ""
		for aid in s._rows:
			if s._rows[aid].locked:
				locked = str(aid)
				break
		assert_ne(locked, "", "una azione bloccata")
		var box: VBoxContainer = s._rows[locked].req_box
		assert_eq(box.get_child_count(), 1)
		var req := int(s._rows[locked].a.level_req)
		assert_eq((box.get_child(0) as Button).text, ReqText.level_text(req, 1), "livello richiesto e livello attuale (%s)" % loc)
		assert_string_contains((box.get_child(0) as Button).text, str(req))
		s.close()
		s.get_parent().queue_free()
		await wait_process_frames(1)


# ------------------------------------------------------------------ 1024×576: nessun troncamento

func _truncated(root: Node) -> PackedStringArray:
	var bad := PackedStringArray()
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var text := ""
		var clip := false
		if c is Label:
			text = (c as Label).text
			clip = (c as Label).clip_text or (c as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
		elif c is Button:
			text = (c as Button).text
			clip = (c as Button).clip_text
		if not clip or text.is_empty() or c.size.x <= 0.0:
			continue
		var font := c.get_theme_font("font")
		var fs := c.get_theme_font_size("font_size")
		if font != null and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > c.size.x + 1.0:
			bad.append("%s: «%s»" % [c.name, text])
	return bad


func test_nessun_troncamento_a_1024x576() -> void:
	DisplayServer.window_set_size(Vector2i(1024, 576))
	get_tree().root.size = Vector2i(1024, 576)
	for loc in ["it", "en"]:
		_locale(loc)
		for sk in ["woodcutting", "smithing", "alchemy", "cooking"]:
			var s := await _open(sk, 12, 1024.0 - 200.0)
			var any := _recipe(sk, 12)
			if not any.is_empty():
				_give(str(any.inputs[0].item), 1)
			s._dirty = true
			for i in 6:
				s.refresh()
			await wait_process_frames(3)
			var bad := _truncated(s._list)
			assert_eq(bad.size(), 0, "%s/%s: testi troncati: %s" % [sk, loc, ", ".join(bad)])
			for aid in s._rows:
				var r: Dictionary = s._rows[aid]
				if (r.panel as Control).visible and (r.panel as Control).get_parent() == s._list:
					assert_lte((r.ingr as Control).size.x, (r.panel as Control).size.x, "%s: gli ingredienti stanno nella carta" % aid)
			s.close()
			s.get_parent().queue_free()
			await wait_process_frames(1)


# ------------------------------------------------------------------ Coltivazione, Tenuta, Commesse, Emporio

func test_coltivazione_resa_e_semi_in_vista() -> void:
	(Game.system("skills") as SkillSystem).state["farming"]["level"] = 5
	var s: Control = (load(FARM) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	await wait_process_frames(3)
	var sec: Dictionary = s._sections["garden"] if s._sections.has("garden") else s._sections[s._sections.keys()[0]]
	var info: Label = sec.info
	var seeds: RichTextLabel = sec.seeds
	assert_true(info.visible, "la resa del seme scelto è in vista")
	assert_string_contains(info.text, "(ne hai", "e quanto ne hai")
	assert_string_contains(info.text, "XP", "e gli XP")
	assert_true(seeds.visible)
	assert_string_contains(seeds.get_parsed_text(), "ne hai", "servono N (hai M)")
	var aid: String = s._selected_action(str(s._sections.find_key(sec)))
	var a: Dictionary = DataRegistry.action(aid)
	_give(str(a.seed), 3)
	s._dirty = true
	s.refresh()
	assert_false(seeds.text.contains(ReqText.WARN), "con i semi nessun avviso")
	assert_string_contains(s._why_text(aid, "UI_FARM_REASON_SEEDS"), "ne servono")


func test_tenuta_materiali_e_oro_con_le_quantita() -> void:
	var s: GameScreen = (load("res://src/ui/screens/EstateScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	await wait_process_frames(2)
	var bank := Game.system("bank") as BankSystem
	var gold := int(bank.gold())
	var gs: String = s._why_text("UI_ESTATE_REASON_GOLD", {"gold": gold + 120, "items": {}})
	assert_eq(gs, ReqText.gold_sentence(gold + 120, gold))
	assert_string_contains(gs, str(gold + 120))
	var ms: String = s._why_text("UI_ESTATE_REASON_MATERIALS", {"gold": 0, "items": {"log_pine": 10}})
	assert_string_contains(ms, "10", "quanti ne servono")
	assert_string_contains(ms, "ne hai 0", "e quanti ne hai")
	assert_string_contains(s._cost_tip({"gold": 0, "items": {"log_pine": 10}}), ReqText.piece("log_pine", 10, 0))


func test_commesse_dicono_quanto_manca() -> void:
	var mk := Game.system("market") as MarketSystem
	var orders: Array = mk.orders()
	var s: GameScreen = (load("res://src/ui/screens/OrdersScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	await wait_process_frames(3)
	s.refresh()
	if orders.is_empty():
		pass_test("nessuna commessa in bacheca in questa partita: la frase è coperta da test_frasi_di_mancanza")
		return
	var o: Dictionary = orders[0]
	var c: Dictionary = s._cards[str(o.id)]
	assert_string_contains((c.have as Label).text, "ne mancano", "senza oggetti: quanto ne hai e quanto ne manca")
	assert_string_contains((c.deliver as Button).tooltip_text, "ne servono")
