extends GutTest
## Pannello «Bonus attivi» comprensibile (rapporto 112): ogni famiglia del catalogo ha nome e descrizione IT/EN, nessuna chiave
## tecnica né id grezzo di fonte nei testi mostrati, raggruppamento per categoria, tetto e moltiplicatori distinti.

const LANGS := ["it", "en"]
var _old_locale := ""


func before_each() -> void:
	_old_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_old_locale)


func _stack() -> ModifierStack:
	var st := ModifierStack.new()
	st.set_catalog(DataRegistry.table("modifier_catalog"))
	return st


## Un testo mostrato non deve contenere chiavi tecniche («skill_xp_pct», «crate_find_pct:all») né id con il trattino basso.
func _assert_clean(txt: String, what: String) -> void:
	var re := RegEx.new()
	re.compile("[a-z0-9]+_[a-z0-9_]+")
	var m := re.search(txt)
	assert_null(m, "%s: id grezzo o chiave tecnica a schermo -> %s" % [what, txt])
	assert_false(txt.contains("_pct"), what)
	assert_false(txt.contains("UI_"), "%s: chiave di traduzione non risolta -> %s" % [what, txt])


func test_ogni_famiglia_ha_nome_e_descrizione_bilingui() -> void:
	var cats: Array = Array(BonusSummary.CAT_ORDER)
	var seen := 0
	for f in DataRegistry.table("modifier_catalog"):
		seen += 1
		for lang in LANGS:
			assert_false(str(f.name.get(lang, "")).strip_edges().is_empty(), "%s: nome %s" % [f.family, lang])
			assert_false(str(f.blurb.get(lang, "")).strip_edges().is_empty(), "%s: descrizione %s" % [f.family, lang])
			if f.scopes != null:
				assert_false(str(f.scope_all.get(lang, "")).strip_edges().is_empty(), "%s: testo di «tutto» %s" % [f.family, lang])
		assert_true(cats.has(str(f.cat)), "%s: categoria valida" % f.family)
		# nome e descrizione non sono la chiave tecnica
		assert_ne(str(f.name.it).to_lower(), str(f.family))
		assert_false(str(f.blurb.it).contains("_pct"))
	assert_gt(seen, 60)


func test_categorie_e_ambiti_hanno_testo() -> void:
	for lang in LANGS:
		TranslationServer.set_locale(lang)
		for c in BonusSummary.CAT_ORDER:
			assert_ne(BonusSummary.category_label(c), "UI_BONUS_CAT_" + str(c).to_upper(), "categoria %s (%s)" % [c, lang])
			assert_false(LogCategory.tag(c).begins_with("UI_"))
		for f in DataRegistry.table("modifier_catalog"):
			if f.scopes == null:
				continue
			var scopes: Array = (f.scopes as Array).duplicate()
			if str(f.family).begins_with("dungeon_"):
				for d in DataRegistry.table("dungeons"):
					scopes.append(str(d.id))
			for sc in scopes:
				var lbl := BonusSummary.scope_label(f, str(sc))
				assert_false(lbl.is_empty(), "%s:%s senza nome (%s)" % [f.family, sc, lang])
				_assert_clean(lbl, "ambito %s:%s (%s)" % [f.family, sc, lang])
				_assert_clean(BonusSummary.title_of(f, str(sc)), "titolo %s:%s (%s)" % [f.family, sc, lang])


func test_nessuna_chiave_tecnica_nei_testi_renderizzati() -> void:
	for lang in LANGS:
		TranslationServer.set_locale(lang)
		var st := _stack()
		var n := 0
		for f in DataRegistry.table("modifier_catalog"):
			var scopes: Array = [""]
			if f.scopes != null:
				scopes = (f.scopes as Array).duplicate()
				scopes.append("")
				if str(f.family).begins_with("dungeon_"):
					scopes.append(str(DataRegistry.table("dungeons")[0].id))
			for sc in scopes:
				var key := str(f.family) + (":" + str(sc) if not str(sc).is_empty() else "")
				n += 1
				st.set_source("test:%d" % n, [{"key": key, "value": 7.0}, {"key": key, "value": 3.0, "mode": "more"}])
		var rows := BonusSummary.rows(st)
		assert_gt(rows.size(), 100, "molti bonus renderizzati")
		for r in rows:
			_assert_clean(BonusSummary.visible_text(r), "riga %s (%s)" % [r.key, lang])
			assert_false(str(r.blurb).is_empty(), "%s ha una descrizione" % r.key)


func test_fonti_con_nome_vero_mai_id_grezzo() -> void:
	var samples: Array = []
	for e in DataRegistry.table("events"):
		samples.append(["event:" + str(e.id), str(e.id)])
	for p in DataRegistry.table("pets"):
		samples.append(["pet:" + str(p.id), str(p.id)])
	for t in DataRegistry.table("trials"):
		samples.append(["trial:" + str(t.id), str(t.id)])
	for c in DataRegistry.table("collections"):
		samples.append(["collection:" + str(c.id), str(c.id)])
		samples.append(["collection_gold:" + str(c.id), str(c.id)])
	for f in DataRegistry.table("factions"):
		samples.append(["faction:" + str(f.id), str(f.id)])
	for d in DataRegistry.table("dungeons"):
		samples.append(["dungeon:" + str(d.id), str(d.id)])
	for s in DataRegistry.table("skills"):
		for h in ["star", "perk", "skilltool", "potion"]:
			samples.append(["%s:%s" % [h, s.id], str(s.id)])
	for e in DataRegistry.table("shop"):
		samples.append(["shop:" + str(e.id), str(e.id)])
	for p in DataRegistry.rules("coop_net_rules").get("projects", []):
		samples.append(["guild:" + str(p.id), str(p.id)])
	for slot in ["weapon", "head", "chest", "legs", "hands", "feet"]:
		samples.append(["equip:" + slot, slot])
		samples.append(["wardrobe:" + slot, slot])
	for fixed in ["talents", "constellation", "trial_active", "run:perks", "prestige:partners", "combat:potion", "mode:cozy",
			"buff:feast", "buff:xyz_unknown", "relic:abc123", "something_else:foo_bar"]:
		samples.append([fixed, "foo_bar"])
	assert_gt(samples.size(), 100)
	for lang in LANGS:
		TranslationServer.set_locale(lang)
		for sm in samples:
			var lbl := BonusSummary.source_label(str(sm[0]))
			assert_false(lbl.is_empty(), "fonte %s con nome (%s)" % [sm[0], lang])
			_assert_clean(lbl, "fonte %s (%s)" % [sm[0], lang])
			assert_false(lbl.ends_with(": "), str(sm[0]))
	TranslationServer.set_locale("it")
	assert_eq(BonusSummary.source_label("event:lantern_night"), "%s: %s" % [TranslationServer.translate("UI_UIA_SRC_EVENT"),
		Loc.t(DataRegistry.get_def("events", "lantern_night").name)], "evento col nome vero")
	assert_string_contains(BonusSummary.source_label("perk:cooking"), Loc.t(DataRegistry.get_def("skills", "cooking").name))


func test_esempi_del_giocatore_leggibili() -> void:
	TranslationServer.set_locale("it")
	var st := _stack()
	st.set_source("perk:cooking", [{"key": "craft_quality_pct:cooking", "value": 8.0}])
	st.set_source("event:lantern_night", [{"key": "crate_find_pct:all", "value": 10.0}])
	var rows := BonusSummary.rows(st)
	assert_eq(rows.size(), 2)
	var by: Dictionary = {}
	for r in rows:
		by[r.key] = r
	var q: Dictionary = by["craft_quality_pct:cooking"]
	assert_eq(q.title, "Qualità: Cucina")
	assert_eq(q.total, "+8%")
	assert_eq(q.cat, "skills")
	var c: Dictionary = by["crate_find_pct:all"]
	assert_eq(c.title, "Ritrovamento di Casse: tutte le Casse")
	assert_eq(c.cat, "loot")
	assert_string_contains(str(c.sources[0].label), "Evento")
	assert_eq(BonusSummary.count(st), 2)


func test_tetto_moltiplicatori_e_raggruppamento() -> void:
	TranslationServer.set_locale("it")
	var st := _stack()
	st.set_source("a:1", [{"key": "crate_find_pct", "value": 150.0}])
	st.set_source("a:2", [{"key": "crate_find_pct:all", "value": 100.0}])
	st.set_source("a:3", [{"key": "skill_xp_pct:mining", "value": 10.0}, {"key": "skill_xp_pct:mining", "value": 20.0, "mode": "more"}])
	st.set_source("a:4", [{"key": "combat_dmg_pct", "value": 5.0}, {"key": "bank_slots", "value": 4.0}])
	var rows := BonusSummary.rows(st)
	var by: Dictionary = {}
	for r in rows:
		by[r.key] = r
	assert_eq(rows.size(), 4, "«famiglia» e «famiglia:all» sono lo stesso bonus")
	var cr: Dictionary = by["crate_find_pct:all"]
	assert_true(bool(cr.capped))
	assert_eq((cr.sources as Array).size(), 2)
	assert_string_contains(str(cr.cap_note), "100%", "stai usando il 100%")
	assert_string_contains(str(cr.cap_note), "+250%", "quanto hai davvero")
	assert_almost_eq(float(cr.cap_ratio), 1.0, 0.001)
	var xp: Dictionary = by["skill_xp_pct:mining"]
	assert_true(bool(xp.has_more))
	assert_string_contains(str(xp.total), "×1,2")
	assert_true((xp.sources as Array).any(func(s: Dictionary) -> bool: return bool(s.more)), "la fonte moltiplicativa è distinta")
	assert_false(bool(xp.capped))
	assert_eq(str(xp.cap_note), "", "nessun tetto, nessuna frase sul tetto")
	var g := BonusSummary.groups(rows)
	var order: Array = g.map(func(x: Dictionary) -> String: return str(x.cat))
	assert_eq(order, ["skills", "combat", "loot", "system"], "categorie nell'ordine fisso")
	assert_eq(BonusSummary.rows(st, "casse").size(), 1, "ricerca per nome")
	assert_eq(BonusSummary.rows(st, "ordinamento-che-non-esiste").size(), 0)
	assert_eq(BonusSummary.rows(st, "combattimento").size(), 1, "ricerca per categoria")


func test_dialogo_raggruppato_senza_overflow() -> void:
	TranslationServer.set_locale("it")
	Modifiers.set_source("event:lantern_night", [{"key": "crate_find_pct:all", "value": 10.0}, {"key": "skill_xp_pct:all", "value": 5.0}])
	Modifiers.set_source("perk:cooking", [{"key": "craft_quality_pct:cooking", "value": 8.0}])
	var host := Control.new()
	add_child_autofree(host)
	var dlg := BonusDialog.open_on(host)
	await wait_process_frames(2)
	var txt := _texts(dlg)
	assert_string_contains(txt, "bonus attivi")
	assert_string_contains(txt, "Qualità: Cucina")
	_assert_clean(txt.replace("UI_BONUS_HELP", "").replace("UI_BONUS_LEGEND", "").replace("UI_UIA_BONUS_SEARCH", ""), "dialogo")
	assert_true(dlg.size.x <= 1280 and dlg.size.y <= 720, "il dialogo sta in 1280x720: %s" % dlg.size)
	dlg.queue_free()
	Modifiers.clear_source("event:lantern_night")
	Modifiers.clear_source("perk:cooking")


func test_pulsanti_facili_da_trovare_riepilogo_ed_eroe() -> void:
	TranslationServer.set_locale("it")
	assert_true(Game.new_game(1, "normal", 5))
	Modifiers.set_source("perk:cooking", [{"key": "craft_quality_pct:cooking", "value": 8.0}])
	var summary: Control = (load("res://src/ui/screens/SummaryScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(summary)
	await wait_process_frames(1)
	summary.open({})
	summary.refresh()
	var btn := summary._bonus_btn as Button
	assert_not_null(btn)
	assert_eq(btn.theme_type_variation, &"AccentButton", "pulsante evidente")
	assert_string_contains(btn.text, "Bonus attivi (%d)" % BonusSummary.count(Modifiers.stack), "col numero dei bonus")
	var hero: Control = (load("res://src/ui/screens/HeroScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(hero)
	await wait_process_frames(1)
	hero.open({})
	assert_not_null(hero.find_child("BonusBtn", true, false), "il pulsante c'è anche nell'Eroe")
	Modifiers.clear_source("perk:cooking")
	Game.stop_game(false)


func _texts(node: Node) -> String:
	var out := ""
	for c in node.get_children():
		if c is Label or c is Button:
			out += str(c.text) + "\n"
		out += _texts(c)
	return out
