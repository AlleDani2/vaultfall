extends GutTest
## Rapporto 116: ogni mansione con talenti nei dati mostra il pannello «Talenti di mansione» nella schermata che il menù
## apre per lei, e il pallino del menù compare SOLO se in quella schermata c'è davvero una scelta (Coltivazione aveva il
## pallino ma non il pannello).

const MAIN := "res://src/ui/main/MainScreen.tscn"


func before_each() -> void:
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 7))


func after_each() -> void:
	Game.stop_game(false)
	SaveService.autosave_enabled = true


func _main() -> Control:
	Settings.set_value("tutorials", false)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func _skills_with_perks() -> Array:
	var sk := Game.system("skills") as SkillSystem
	var out: Array = []
	for s in DataRegistry.table("skills"):
		if not sk.perk_rows(str(s.id)).is_empty():
			out.append(str(s.id))
	return out


func _unlock(skill_id: String) -> Dictionary:
	var entry := ScreenRegistry.get_entry(ScreenRegistry.menu_id_for_skill(skill_id))
	var unlocks: Array = GameState.data.unlocks
	for tok in [str(entry.get("unlock", "")), "skill:" + skill_id]:
		if not tok.is_empty() and not unlocks.has(tok):
			unlocks.append(tok)
	return entry


func _panel(main: Control) -> SkillPerkPanel:
	if main._current.has_method("_set_tab") and main._current.has_method("current_tab"):
		main._current._set_tab("abilities")      # Eroe a schede: i talenti stanno in «Abilità»
	return main._current.find_child("SkillPerkPanel", true, false) as SkillPerkPanel


func test_ci_sono_mansioni_con_talenti() -> void:
	var ids := _skills_with_perks()
	assert_gt(ids.size(), 10)
	for must in ["woodcutting", "farming", "trapping", "thievery", "keysmithing", "alchemy", "runecarving", "jewelcrafting", "hero"]:
		assert_true(ids.has(must), must)


func test_ogni_mansione_con_talenti_mostra_il_pannello_e_il_pallino_e_coerente() -> void:
	var main := await _main()
	var sk := Game.system("skills") as SkillSystem
	for sid in _skills_with_perks():
		var entry := _unlock(sid)
		var menu_id := str(entry.id)
		assert_false(entry.is_empty(), "%s: la mansione ha una voce di menù" % sid)
		# livello 1: nessuna scelta, quindi nessun pallino di talenti; il pannello c'è comunque e dice quando arriva il primo
		sk.state[sid]["level"] = 1
		assert_true(main.show_screen(menu_id, entry.get("params", {})), "%s: la schermata si apre" % sid)
		await wait_process_frames(2)
		var p := _panel(main)
		assert_not_null(p, "%s (%s): la schermata ha il pannello dei talenti" % [sid, menu_id])
		if p == null:
			continue
		assert_true(p.is_visible_in_tree(), "%s: pannello visibile" % sid)
		assert_false(p.has_choice(), "%s: a livello 1 nessuna scelta" % sid)
		assert_eq(int(SidebarBadges.perk_counts().get(menu_id, 0)), 0, "%s: a livello 1 nessun pallino" % sid)
		assert_string_contains(p.status_text(), Loc.tf("UI_SKILLS_PERKS_NEXT", {"n": p.next_tier_level()}), "%s: dice quando arriva il prossimo" % sid)
		# livello del primo talento: scelta disponibile, pallino acceso, pulsanti attivi
		var first := int(sk.perk_rows(sid)[0].level)
		sk.state[sid]["level"] = first
		main._update_slow()
		main._current.refresh()
		await wait_process_frames(1)
		assert_true(p.has_choice(), "%s: a livello %d c'è una scelta" % [sid, first])
		assert_eq(p.status_text(), tr("UI_SKILLS_PERK_AVAILABLE"), "%s: messaggio «un nuovo talento ti aspetta»" % sid)
		assert_gt(int(SidebarBadges.perk_counts().get(menu_id, 0)), 0, "%s: pallino acceso" % sid)
		assert_true((main._badges[menu_id] as Control).visible, "%s: pallino disegnato sulla voce %s" % [sid, menu_id])
		p.set_open(true)
		await wait_process_frames(2)
		assert_gt(p.choosable_buttons(), 0, "%s: almeno un pulsante di scelta attivo" % sid)
		# scelta fatta: pallino e pannello si spengono insieme
		var letter := str(sk.perk_rows(sid)[0].options[0].id)
		p.on_perk_pressed(first, letter.substr(letter.length() - 1))
		main._update_slow()
		assert_false(p.has_choice(), "%s: dopo la scelta niente più «da scegliere»" % sid)
		assert_eq(int(SidebarBadges.perk_counts().get(menu_id, 0)), 0, "%s: pallino spento dopo la scelta" % sid)


func test_nessun_pallino_senza_pannello() -> void:
	# ogni id di voce che compare in perk_counts() ha una schermata con il pannello
	var main := await _main()
	var sk := Game.system("skills") as SkillSystem
	for sid in _skills_with_perks():
		_unlock(sid)
		sk.state[sid]["level"] = 100
	var counts := SidebarBadges.perk_counts()
	assert_gt(counts.size(), 10)
	for id in counts:
		var entry := ScreenRegistry.get_entry(str(id))
		assert_true(main.show_screen(str(id), entry.get("params", {})), str(id))
		await wait_process_frames(2)
		var p := _panel(main)
		assert_not_null(p, "pallino su %s ma nessun pannello nella schermata" % id)
		if p != null:
			assert_true(p.has_choice(), "%s: pallino e pannello d'accordo" % id)


func test_mansione_bloccata_non_ha_pallino() -> void:
	var sk := Game.system("skills") as SkillSystem
	GameState.data.unlocks.erase("skill:trapping")
	sk.state["trapping"]["level"] = 30
	assert_false(SidebarBadges.perk_counts().has("skill:trapping"))
