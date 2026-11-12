extends GutTest
## T-1.1: DataRegistry su TUTTI i file di res://data/.


func test_caricato_senza_errori() -> void:
	assert_true(DataRegistry.is_loaded(), "dati caricati (python tools/sync_data.py)")
	assert_eq(DataRegistry.errors, PackedStringArray(), "errori di lettura")
	PerfGate.assert_time(self, "caricamento dati (obiettivo 300 ms, docs/17 §11)", DataRegistry.load_ms, 1000.0, PerfGate.wall_factor())
	gut.p("Caricamento dati: %.1f ms" % DataRegistry.load_ms)


func test_tutti_i_file_del_manifest() -> void:
	var files: Array = DataRegistry.manifest.get("files", [])
	assert_gt(files.size(), 50)
	for f in files:
		var base: String = String(f).get_basename()
		if base.begins_with("items/"):
			continue
		if base.begins_with("actions/"):
			assert_gt(DataRegistry.actions_for_skill(base.get_file()).size(), 0, f)
		elif base == "constants":
			assert_false(DataRegistry.constants.is_empty(), f)
		elif base == "xp_table":
			assert_false(DataRegistry.xp_table.is_empty(), f)
		else:
			assert_true(DataRegistry.has_table(base), "tabella caricata: " + f)


func test_conteggi_come_manifest() -> void:
	var counts: Dictionary = DataRegistry.manifest.counts
	assert_eq(DataRegistry.all_items().size(), int(counts.items))
	assert_eq(DataRegistry.all_actions().size(), int(counts.actions))
	for cat in counts.items_by_category:
		assert_eq(DataRegistry.items_by_category(cat).size(), int(counts.items_by_category[cat]), cat)


func test_indici_per_id() -> void:
	for tname in DataRegistry.table_names():
		var key_field: String = DataRegistry.KEY_FIELD.get(tname, "id")
		for rec in DataRegistry.table(tname):
			if key_field == "id":
				assert_eq(DataRegistry.get_def(tname, str(rec.id)), rec, "%s/%s" % [tname, str(rec.id)])
	assert_eq(DataRegistry.item("log_pine").get("category"), "material")
	assert_eq(DataRegistry.action("mine_copper").skill, "mining")
	assert_eq(DataRegistry.get_def("monsters", "mud_slime").zone, "millbrook")
	assert_eq(DataRegistry.get_def("items", "key_t1").key_tier, 1.0)
	assert_true(DataRegistry.get_def("monsters", "inesistente").is_empty())
	assert_false(DataRegistry.modifier_family("skill_xp_pct").is_empty())
	assert_gt(DataRegistry.grouped("skill_perks", "mining").size(), 0)
	assert_eq(DataRegistry.rules("crate_rules").id, "crate_rules")
	assert_eq(DataRegistry.skill_ids().size(), DataRegistry.table("skills").size())
	assert_eq(DataRegistry.const_value("combat.hit_base"), 0.75)
	assert_eq(DataRegistry.const_value("non.esiste", 3), 3)


func test_riferimenti_incrociati() -> void:
	var errs := DataRegistry.validate_references()
	assert_eq(errs.size(), 0, "\n".join(errs.slice(0, 20)))


func test_formulas_configurate_dai_dati() -> void:
	assert_true(Formulas.is_configured())
	assert_eq(Formulas.key_econ_tier(2), int(DataRegistry.item("key_t2").tier), "KEY_TIER ricavato dalle chiavi")
	assert_eq(Formulas.xp_total_for_level(50), int(DataRegistry.xp_table.total_xp_for_level[50]), "xp_table.json")
