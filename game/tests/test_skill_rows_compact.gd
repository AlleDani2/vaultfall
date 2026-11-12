extends GutTest
## F7 del progetto di interfaccia (docs/ui_redesign/06 §3.7): mansioni con testata unica, striscia «In corso» e righe compatte.
## Carte-azione (revisione grafica 1.0, problema 6: prima righe <= 56 px), ricette bloccate in un gruppo chiuso, requisiti solo se mancano, ordine «fattibili ora» e
## chiavi del tutorial presenti (Pino e Rame).

const SCREEN := "res://src/ui/screens/SkillScreen.tscn"
const FARM := "res://src/ui/screens/FarmScreen.tscn"
const MAX_CARD_H := 240.0
const MIN_CARD_H := 120.0

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_skill_rows_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 6))
	Settings.set_value("seen_intro", [])


func after_each() -> void:
	Settings.set_value("seen_intro", [])
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(skill: String, level: int = 0, params: Dictionary = {}) -> Control:
	if level > 0:
		(Game.system("skills") as SkillSystem).state[skill]["level"] = level
	var s: Control = (load(SCREEN) as PackedScene).instantiate()
	_mount(s)
	var p := {"skill": skill}
	p.merge(params)
	s.open(p)
	await wait_process_frames(3)
	return s


## La schermata riempie un riquadro di 1100x700 (area di contenuto tipica a 1280x720).
func _mount(s: Control) -> void:
	var host := Control.new()
	add_child_autofree(host)
	host.size = Vector2(1100, 700)
	host.add_child(s)


func _first_craft(skill: String, max_level: int) -> Dictionary:
	for a in DataRegistry.actions_for_skill(skill):
		if a.has("inputs") and not bool(a.get("single_craft", false)) and int(a.get("level_req", 1)) <= max_level:
			return a
	return {}


func _give_inputs(a: Dictionary, times: int = 1) -> void:
	var bank := Game.system("bank") as BankSystem
	for io in a.get("inputs", []):
		bank.add(str(io.item), int(io.qty) * times, "test")


func test_carte_azione_con_icona_e_pulsante_largo() -> void:
	for sk in ["woodcutting", "smithing"]:
		var s := await _open(sk, 30)
		s.refresh()
		await wait_process_frames(2)
		var checked := 0
		assert_gte(s._list.columns, 2, sk + ": a 1100 px di contenuto le carte stanno in almeno 2 colonne")
		for aid in s._rows:
			var panel: Control = s._rows[aid].panel
			if not panel.is_visible_in_tree():
				continue
			checked += 1
			assert_lte(panel.size.y, MAX_CARD_H, "%s: carta %s alta %s" % [sk, aid, str(panel.size.y)])
			assert_gte(panel.size.y, MIN_CARD_H, "%s: carta %s con icona da 64 px" % [sk, aid])
			var btn: Button = s._rows[aid].btn
			assert_gte(btn.size.y, 40.0, "%s: pulsante alto almeno 40 px" % sk)
			assert_gte(btn.size.x, panel.size.x * 0.8, "%s: pulsante a tutta larghezza della carta" % sk)
		assert_gt(checked, 3, sk + ": ci sono carte visibili da misurare")


func test_carta_in_esecuzione_ha_barra_e_bordo() -> void:
	var s := await _open("woodcutting", 30)
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start("wc_pine"))
	s.refresh()
	await wait_process_frames(2)
	var row: Dictionary = s._rows["wc_pine"]
	assert_true(row.prog.visible, "barra di avanzamento sulla carta in esecuzione")
	var st := (row.panel as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(st.border_color, FxPalette.GREEN, "bordo verde: in esecuzione")
	assert_false(s._rows["wc_birch"].prog.visible, "le altre no")


func test_bloccate_in_un_gruppo_chiuso() -> void:
	var s := await _open("woodcutting", 1)
	assert_true(s._locked_btn.visible, "ci sono ricette bloccate: il gruppo compare")
	assert_false(s._locked_box.visible, "il gruppo è chiuso")
	var locked := 0
	for aid in s._rows:
		var r: Dictionary = s._rows[aid]
		if r.locked:
			locked += 1
			assert_eq(r.panel.get_parent(), s._locked_box, "%s: la riga bloccata sta nel gruppo" % aid)
			assert_false(r.panel.is_visible_in_tree(), "%s: bloccata e non visibile finché il gruppo è chiuso" % aid)
		else:
			assert_eq(r.panel.get_parent(), s._list, "%s: la riga sbloccata sta nell'elenco" % aid)
	assert_gt(locked, 0)
	assert_string_contains(s._locked_btn.text, "(%d)" % locked, "il numero di bloccate")
	var first := ""
	var best := 9999
	for aid in s._rows:
		var lv := int(s._rows[aid].a.get("level_req", 1))
		if s._rows[aid].locked and lv < best:
			best = lv
			first = str(aid)
	assert_string_contains(s._locked_btn.text, Loc.t(DataRegistry.action(first).name), "dice quale sarà la prossima")
	assert_string_contains(s._locked_btn.text, str(best), "e a quale livello")
	s._locked_btn.button_pressed = true
	await wait_process_frames(2)
	assert_true(s._locked_box.visible, "si apre")
	# salendo di livello la riga passa nell'elenco
	(Game.system("skills") as SkillSystem).state["woodcutting"]["level"] = 100
	s._dirty = true
	s.refresh()
	assert_false(s._locked_btn.visible, "nessuna bloccata: niente gruppo")
	for aid in s._rows:
		assert_eq(s._rows[aid].panel.get_parent(), s._list)


func test_requisiti_visibili_solo_se_mancano() -> void:
	var a := _first_craft("smithing", 30)
	assert_false(a.is_empty(), "esiste una ricetta di Forgiatura con ingredienti")
	var aid := str(a.id)
	var s := await _open("smithing", 30)
	var ingr: RichTextLabel = s._rows[aid].ingr
	assert_true(ingr.visible, "gli ingredienti sono sempre in vista con le quantità")
	assert_string_contains(ingr.text, "[url", "senza ingredienti il pezzo mancante è cliccabile (porta a dove si ottiene)")
	assert_string_contains(ingr.text, ReqText.WARN, "e in colore di avvertimento")
	assert_eq(s._rows[aid].req_box.get_child_count(), 0, "livello sufficiente: nessun requisito di livello")
	_give_inputs(a, 3)
	s._dirty = true
	s.refresh()
	assert_false(ingr.text.contains(ReqText.WARN), "con gli ingredienti nessun avvertimento")
	assert_eq(s._rows[aid].req_box.custom_minimum_size.x, 0.0, "e il requisito di livello non occupa spazio")
	assert_string_contains(s._rows[aid].panel.tooltip_text, Loc.t(DataRegistry.item(str(a.inputs[0].item)).name), "gli ingredienti stanno anche nel suggerimento")
	s.close()


func test_ordine_fattibili_prima_poi_livello() -> void:
	var sk := Game.system("skills") as SkillSystem
	var crafts: Array = []
	for a in DataRegistry.actions_for_skill("smithing"):
		if a.has("inputs") and int(a.get("level_req", 1)) <= 30:
			crafts.append(a)
	assert_gt(crafts.size(), 3)
	var target: Dictionary = crafts[crafts.size() - 1]            # l'ultima per livello: senza il nuovo ordine starebbe in fondo
	_give_inputs(target)
	var s := await _open("smithing", 30)
	assert_eq(sk.can_start(str(target.id)), "", "con gli ingredienti la ricetta è fattibile")
	var feasible: Array = []
	var others: Array = []
	for a in DataRegistry.actions_for_skill("smithing"):
		if int(a.get("level_req", 1)) > 30:
			continue
		(feasible if sk.can_start(str(a.id)) == "" else others).append(a)
	var by_level := func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("level_req", 1)) < int(y.get("level_req", 1))
	feasible.sort_custom(by_level)
	others.sort_custom(by_level)
	var want := PackedStringArray()
	for a in feasible + others:
		want.append(str(a.id))
	var got := PackedStringArray()
	for k in s._list.get_children():
		for aid in s._rows:
			if s._rows[aid].panel == k:
				got.append(str(aid))
	assert_eq(got[0], str(feasible[0].id), "in cima la prima fattibile ora")
	assert_true(got.slice(0, feasible.size()).has(str(target.id)), "la ricetta fattibile sta tra le prime")
	assert_eq(",".join(got), ",".join(want), "prima le fattibili (per livello), poi le altre (per livello)")


func test_solo_cio_che_posso_fare_dalla_seconda_visita() -> void:
	var s1 := await _open("smithing", 30)
	assert_false(s1._only.button_pressed, "prima visita: il filtro è spento")
	s1.close()
	s1.queue_free()
	await wait_process_frames(1)
	var s2 := await _open("smithing", 30)
	assert_true(s2._only.button_pressed, "seconda visita: il filtro è acceso")
	var a := _first_craft("smithing", 30)
	for aid in s2._rows:
		var r: Dictionary = s2._rows[aid]
		if not r.locked:
			assert_eq(r.panel.visible, (Game.system("skills") as SkillSystem).can_start(str(aid)) == "", "%s: visibile solo se fattibile" % aid)
	assert_true(s2._empty_l.visible, "senza ingredienti il filtro nasconde tutto e lo dice")
	_give_inputs(a, 2)
	s2._dirty = true
	s2.refresh()
	assert_true(s2._rows[str(a.id)].panel.visible, "con gli ingredienti la ricetta compare")
	assert_false(s2._empty_l.visible)


func test_testata_e_striscia() -> void:
	var s := await _open("woodcutting", 5)
	var hdr: SkillHeader = s._hdr
	assert_not_null(hdr)
	assert_not_null(TutorialTargets.find(get_tree(), "skill_header"), "chiave skill_header sulla testata")
	assert_eq(s._perks.perk_button().get_parent(), hdr.buttons, "«Talenti» nella testata")
	assert_eq(s._extras.toggle_button().get_parent(), hdr.buttons, "«Coda ▾» nella testata")
	assert_eq(hdr.help_btn.get_parent(), hdr.buttons, "«?» nella testata")
	assert_lte(hdr.head_panel.size.y, 80.0, "testata di una riga (%s px)" % str(hdr.head_panel.size.y))
	assert_lte(hdr.strip.size.y, 48.0, "striscia di una riga")
	assert_false(hdr.strip_btn.visible, "a riposo: nessun «Ferma»")
	assert_string_contains(hdr.strip_name.text, "—", "a riposo: «scegli un'azione qui sotto»")
	(Game.system("skills") as SkillSystem).start("wc_pine")
	s.refresh()
	assert_true(hdr.strip_btn.visible)
	assert_string_contains(hdr.strip_name.text, Loc.t(DataRegistry.action("wc_pine").name))
	# niente banner dei talenti né descrizione fissa nel corpo della schermata
	for l in s.find_children("*", "Label", true, false):
		var t := (l as Label).text
		assert_false(t.contains(tr("UI_SKILLS_PERK_AVAILABLE")), "il banner «Un nuovo talento ti aspetta» non c'è più")
		assert_false(t.contains(Loc.t(DataRegistry.get_def("skills", "woodcutting").desc)), "la descrizione comica sta nel «?»")
	assert_string_contains(hdr.help_btn.tooltip_text, Loc.t(DataRegistry.get_def("skills", "woodcutting").desc))


func test_chiavi_del_tutorial_presenti_per_pino_e_rame() -> void:
	var s := await _open("woodcutting")
	for key in ["skill_header", "perk_btn", "row:wc_pine", "action:wc_pine", "mastery:wc_pine", "extras_toggle"]:
		assert_not_null(TutorialTargets.find(get_tree(), key), "woodcutting: " + key)
	s.tut_prepare("extras")
	await wait_process_frames(2)
	for key in ["extras_queue", "extras_potion"]:
		assert_true(get_tree().get_nodes_in_group("tut:" + key).size() > 0, "woodcutting: " + key + " esiste")
	s.close()
	s.queue_free()
	await wait_process_frames(1)
	var m := await _open("mining")
	for key in ["skill_header", "row:mine_copper", "action:mine_copper", "mastery:mine_copper"]:
		assert_not_null(TutorialTargets.find(get_tree(), key), "mining: " + key)
	m.close()


func test_coltivazione_ha_la_stessa_testata() -> void:
	var f: Control = (load(FARM) as PackedScene).instantiate()
	_mount(f)
	f.open({})
	await wait_process_frames(3)
	f.refresh()
	var hdr: SkillHeader = f._hdr
	assert_not_null(hdr, "Coltivazione usa la testata unica")
	assert_eq(f._perks.perk_button().get_parent(), hdr.buttons)
	assert_not_null(TutorialTargets.find(get_tree(), "skill_header"))
	assert_true(f._harvest_all.get_parent().get_parent() == hdr.strip, "«Raccogli tutto» nella striscia")
	assert_lte(hdr.head_panel.size.y, 80.0, "testata di una riga")
	assert_gt(f._sections.size(), 0, "le parcelle restano")
	f.close()
