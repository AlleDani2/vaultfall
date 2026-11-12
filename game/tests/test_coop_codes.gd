extends GutTest
## COOP-1: codice-eroe («Scheda del Compagno»): andata e ritorno, rifiuto dei codici manomessi o enormi, limiti del gioco,
## nessun trasferimento di oggetti.

const Env := preload("res://tests/helpers/coop_env.gd")
const NOW := 1760000000


func _env(created: int = 1700000000, cls: String = "warrior", lvl: int = 55) -> Object:
	return Env.make(11, lvl, cls, 6, created)


func _code(env: Object) -> String:
	return env.coop.export_hero_code(NOW)


## Gli errori del motore (gzip rovinato) sono attesi: il gioco li gestisce, la prova li marca come gestiti.
func _handled() -> void:
	for e in get_errors():
		e.handled = true


func _fmt() -> Dictionary:
	return DataRegistry.rules("coop_rules").format


func after_each() -> void:
	Env.free_all()


func test_round_trip_della_scheda() -> void:
	var a: Object = _env(1700000000)
	var b: Object = _env(1700099999)
	var code := _code(a)
	assert_true(code.begins_with("VFH1."), "prefisso VF + tipo H + versione 1")
	assert_lt(code.length(), 6000, "il codice sta in una riga di chat")
	var r: Dictionary = b.coop.import_code(code, NOW)
	assert_true(r.ok, str(r))
	assert_eq(r.status, "added")
	var c: Dictionary = b.coop.companions()[0]
	var sh: Dictionary = c.sheet
	var hero: Dictionary = a.combat.hero_stats()
	assert_eq(sh["class"], "warrior")
	assert_eq(int(sh.level), a.combat.hero_level())
	assert_almost_eq(float(sh.st.hp), float(hero.hp), 1e-6)
	assert_almost_eq(float(sh.st.max_hit), float(hero.max_hit), 1e-6)
	assert_almost_eq(float(sh.st.interval), float(hero.interval), 1e-9)
	assert_eq(str(sh.uid), a.coop.my_uid())
	assert_eq(c.enabled, true)


func test_il_codice_e_deterministico_e_la_scheda_non_cambia_il_donatore() -> void:
	var a: Object = _env()
	var snap_bank := JSON.stringify([a.bank.stacks, a.bank.inst, a.bank.gold_n])
	var c1 = a.coop.export_hero_code(NOW)
	var rev1 := int(a.coop.state.rev)
	var c2 = a.coop.export_hero_code(NOW)
	assert_ne(c1, c2, "la revisione sale a ogni esportazione")
	assert_eq(int(a.coop.state.rev), rev1 + 1)
	assert_eq(JSON.stringify([a.bank.stacks, a.bank.inst, a.bank.gold_n]), snap_bank, "esportare non tocca il Deposito")


func test_codici_manomessi_o_rovinati_si_rifiutano_senza_crash() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var code := _code(a)
	var bad: Array = []
	bad.append("")
	bad.append("ciao")
	bad.append("VF")
	bad.append("VFH1.")
	bad.append("VFH1.AAAA")
	bad.append("VFX1." + code.substr(code.find(".") + 1))
	bad.append(code.substr(0, code.length() >> 1))
	bad.append(code + "A")
	bad.append(code.replace("VFH1.", "VFR1."))
	var mid := code.length() >> 1
	var ch := code.substr(mid, 1)
	var flip := "B" if ch != "B" else "C"
	bad.append(code.substr(0, mid) + flip + code.substr(mid + 1))
	bad.append(code.substr(0, mid) + "!" + code.substr(mid + 1))
	for t in bad:
		var r: Dictionary = b.coop.import_code(str(t), NOW)
		assert_false(r.ok, "deve essere rifiutato: " + str(t).left(24))
		assert_ne(str(r.error), "", "con un codice d'errore")
	assert_eq(b.coop.companions().size(), 0, "nessun compagno aggiunto")
	_handled()


func test_testo_con_spazi_e_a_capo_si_accetta() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var code := _code(a)
	var wrapped := ""
	for i in range(0, code.length(), 60):
		wrapped += code.substr(i, 60) + "\n"
	var r: Dictionary = b.coop.import_code("  " + wrapped + "  ", NOW)
	assert_true(r.ok, "le chat spezzano le righe")


func test_codice_troppo_lungo_e_bomba_gzip() -> void:
	var b: Object = _env()
	var r: Dictionary = b.coop.import_code("VFH1." + "A".repeat(7000), NOW)
	assert_false(r.ok)
	assert_eq(r.error, "too_long")
	var big := PackedByteArray()
	big.resize(400000)
	var b64 := Marshalls.raw_to_base64(big.compress(FileAccess.COMPRESSION_GZIP))
	assert_lt(b64.length(), 6000, "la bomba è piccola da incollare")
	var r2: Dictionary = b.coop.import_code("VFH1." + b64, NOW)
	assert_false(r2.ok, "non si decomprime oltre il tetto")
	assert_true(["too_big", "gzip"].has(r2.error), r2.error)


func test_versione_piu_nuova_si_rifiuta() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var sheet: Dictionary = a.coop.build_sheet(NOW)
	var code := CoopCodec.pack("H", 9, sheet)
	var r: Dictionary = b.coop.import_code(code, NOW)
	assert_false(r.ok)
	assert_eq(r.error, "version_newer")


func test_schema_di_salvataggio_invariato() -> void:
	assert_false(FileAccess.get_file_as_string("res://src/core/SaveCodec.gd").to_lower().contains("coop"), "il coop non compare nelle migrazioni: sezione additiva")
	assert_eq(int(_fmt().version), 1)


# ------------------------------------------------------------------ attaccante che ricalcola il checksum

func _attack(sheet: Dictionary, b: Object) -> Dictionary:
	return b.coop.import_code(CoopCodec.pack("H", 1, sheet), NOW)


func test_numeri_impossibili_vengono_riportati_ai_limiti_del_gioco() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var sh: Dictionary = a.coop.build_sheet(NOW)
	sh.level = 9999
	sh.st.hp = 1.0e18
	sh.st.max_hit = 1.0e18
	sh.st.acc = 1.0e15
	sh.st.arm = 1.0e15
	sh.st.crit = 5.0
	sh.st.critd = 1.0e9
	sh.st.lifesteal = 50.0
	sh.st.multihit = 9.0
	sh.st.dmg_taken_mult = 0.0
	sh.st.interval = 0.0001
	sh.tot.combat_dmg_pct = 1.0e12
	sh.elem_more.fire = 1.0e9
	var r := _attack(sh, b)
	assert_true(r.ok, str(r))
	assert_gt(int(r.clamped), 5, "molti campi riportati ai limiti")
	var s: Dictionary = b.coop.companions()[0].sheet
	var k: Dictionary = Formulas.k().combat
	var cap: int = int(DataRegistry.constants.level_cap)
	assert_eq(int(s.level), cap)
	var lim: Dictionary = CoopSheet.limits_for(DataRegistry, cap)
	assert_lte(float(s.st.hp), float(lim.hp))
	assert_lte(float(s.st.max_hit), float(lim.max_hit))
	assert_lte(float(s.st.crit), float(k.crit_cap))
	assert_lte(float(s.st.lifesteal), float(k.rules.lifesteal_cap_pct) / 100.0)
	assert_lte(float(s.st.multihit), float(k.rules.multihit_cap_pct) / 100.0)
	assert_gte(float(s.st.dmg_taken_mult), float(DataRegistry.rules("coop_rules").limits.dmg_taken_min))
	assert_gte(float(s.st.interval), float(lim.interval_min))
	assert_lte(float(s.tot.combat_dmg_pct), float(DataRegistry.rules("coop_rules").limits.tot_abs_max))
	assert_lte(float(s.elem_more.fire), float(DataRegistry.rules("coop_rules").limits.elem_more_max))


func test_il_tetto_dipende_dal_livello_e_la_scheda_vera_ci_sta_sotto() -> void:
	var lo: Dictionary = CoopSheet.limits_for(DataRegistry, 5)
	var hi: Dictionary = CoopSheet.limits_for(DataRegistry, 100)
	assert_lt(float(lo.hp), float(hi.hp))
	assert_lt(float(lo.max_hit), float(hi.max_hit))
	var a: Object = _env(1700000000, "warrior", 55)
	var sh: Dictionary = a.coop.build_sheet(NOW)
	var lim: Dictionary = CoopSheet.limits_for(DataRegistry, 55)
	for k in ["hp", "acc", "eva", "arm", "ward", "max_hit"]:
		assert_lte(float(sh.st[k]), float(lim[k]), "l'Eroe vero sta sotto il tetto: " + k)
	var v := CoopSheet.sanitize(sh, DataRegistry, NOW)
	assert_true(v.ok)
	assert_eq(int(v.clamped), 0, "una scheda vera non viene toccata")
	assert_eq(int(v.dropped), 0)


func test_ogni_classe_esporta_una_scheda_valida() -> void:
	for cls in ["warrior", "ranger", "arcanist"]:
		var a: Object = _env(1700000000, cls, 60)
		var sh: Dictionary = a.coop.build_sheet(NOW)
		var v := CoopSheet.sanitize(sh, DataRegistry, NOW)
		assert_true(v.ok, cls)
		assert_eq(int(v.clamped), 0, cls)


func test_id_sconosciuti_e_abilita_non_ammesse_si_scartano() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var sh: Dictionary = a.coop.build_sheet(NOW)
	sh["class"] = "warrior"
	sh.spec = "pyromancer"
	sh.abilities = ["cleave", "fireball_inesistente", "cleave", "ability_che_non_esiste", "x", "y", "z"]
	sh.title = "titolo_inventato"
	var r := _attack(sh, b)
	assert_true(r.ok, str(r))
	var s: Dictionary = b.coop.companions()[0].sheet
	assert_eq(s.spec, "", "la spec non figlia della classe cade")
	assert_eq(s.title, "")
	for aid in s.abilities:
		var ad: Dictionary = DataRegistry.get_def("abilities", aid)
		assert_false(ad.is_empty())
		assert_eq(ad["class"], "warrior")
	assert_lte(s.abilities.size(), 4, "al massimo gli slot del gioco")
	var bad = a.coop.build_sheet(NOW)
	bad["class"] = "dio_dei_dadi"
	assert_false(_attack(bad, b).ok, "classe sconosciuta")
	var bad2 = a.coop.build_sheet(NOW)
	bad2.erase("st")
	assert_false(_attack(bad2, b).ok, "mancano le statistiche")
	var bad3 = a.coop.build_sheet(NOW)
	bad3.st.hp = "tantissimi"
	var r3 := _attack(bad3, b)
	assert_true(r3.ok or str(r3.error) != "", "tipo sbagliato: o riparato o rifiutato, mai crash")
	var bad4 = a.coop.build_sheet(NOW)
	bad4.issued = NOW + 99999999
	assert_eq(_attack(bad4, b).error, "future", "date dal futuro oltre la tolleranza")


func test_nessun_oggetto_viaggia_nel_codice() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var sh: Dictionary = a.coop.build_sheet(NOW)
	var text := JSON.stringify(sh)
	for bad in ["item", "inventory", "bank", "instances", "gold", "currencies"]:
		assert_false(sh.has(bad), "chiave vietata assente: " + bad)
	# nessun id di oggetto dei dati compare nel testo della scheda
	var hits: Array = []
	for iid in DataRegistry.all_items():
		if str(iid).length() >= 8 and text.contains("\"" + str(iid) + "\""):
			hits.append(iid)
	assert_eq(hits, [], "nessun id di oggetto nella scheda")
	assert_false(text.contains("sword_") or text.contains("helm_") or text.contains("plate_"), "nemmeno per sbaglio")
	# un attaccante che ci infila oggetti: rifiutato
	for key in ["items", "bank", "gold", "inventory", "instances", "equipment"]:
		var evil = a.coop.build_sheet(NOW)
		if key == "gold":
			evil[key] = 1000000
		else:
			evil[key] = {"sword_copper": 1}
		var r := _attack(evil, b)
		assert_false(r.ok, "chiave vietata: " + key)
		assert_eq(r.error, "forbidden")
	# importare non muove nulla nel Deposito di chi importa né oro
	var bank_before := JSON.stringify([b.bank.stacks, b.bank.inst, b.bank.gold_n])
	var ok = b.coop.import_code(a.coop.export_hero_code(NOW), NOW)
	assert_true(ok.ok)
	assert_eq(JSON.stringify([b.bank.stacks, b.bank.inst, b.bank.gold_n]), bank_before, "né oggetti né oro dal codice")


func test_aggiornamento_e_scheda_piu_vecchia() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var old_code = a.coop.export_hero_code(NOW)
	var new_code = a.coop.export_hero_code(NOW + 100)
	assert_eq(b.coop.import_code(old_code, NOW + 100).status, "added")
	assert_eq(b.coop.import_code(new_code, NOW + 100).status, "updated", "la scheda più recente aggiorna")
	assert_eq(b.coop.companions().size(), 1)
	assert_eq(b.coop.import_code(old_code, NOW + 100).status, "older", "quella vecchia viene ignorata")
	assert_eq(b.coop.import_code(new_code, NOW + 100).status, "same")
	assert_eq(b.coop.companions().size(), 1)


func test_il_proprio_codice_si_rifiuta() -> void:
	var a: Object = _env()
	var r: Dictionary = a.coop.import_code(a.coop.export_hero_code(NOW), NOW)
	assert_false(r.ok)
	assert_eq(r.error, "self")


func test_scheda_scaduta_si_segnala_e_non_partecipa() -> void:
	var a: Object = _env()
	var b: Object = _env(1700099999)
	var code = a.coop.export_hero_code(NOW)
	var later := NOW + 31 * 86400
	var r: Dictionary = b.coop.import_code(code, later)
	assert_true(r.ok)
	var c: Dictionary = b.coop.companions()[0]
	assert_true(c.expired, "scaduta dopo i giorni dei dati")
	assert_eq(b.coop.companion_status(c), "expired")
	assert_eq(b.coop.active_companions().size(), 0)
	# aggiornabile: un codice nuovo la rinfresca
	var fresh = a.coop.export_hero_code(later)
	assert_eq(b.coop.import_code(fresh, later).status, "updated")
	assert_false(b.coop.companions()[0].expired)
	assert_eq(b.coop.active_companions().size(), 1)
	# l'interfaccia può rinfrescare i segnalini con un orologio nuovo
	b.coop.refresh(later + 40 * 86400)
	assert_true(b.coop.companions()[0].expired)


func test_massimo_tre_compagni() -> void:
	var b: Object = _env(1700099999)
	for i in 3:
		var a: Object = _env(1700000000 + i * 1000)
		assert_true(a.share_to(b).ok)
	var extra: Object = _env(1700777777)
	var r: Dictionary = extra.share_to(b)
	assert_false(r.ok)
	assert_eq(r.error, "full")
	assert_eq(b.coop.companions().size(), 3)
	assert_true(b.coop.remove_companion(b.coop.companions()[0].id))
	assert_true(extra.share_to(b).ok)


func test_nome_ripulito() -> void:
	var a: Object = _env()
	assert_eq(a.coop.set_my_name("  Mario   Rossi<script>  "), "Mario Rossiscript")
	assert_eq(a.coop.set_my_name("x".repeat(80)).length(), 24)
	assert_eq(a.coop.set_my_name("@@@@"), Loc.t(DataRegistry.rules("coop_rules").code.default_name), "tutto vietato: nome di riserva")
	var sh: Dictionary = a.coop.build_sheet(NOW)
	assert_eq(sh.name, Loc.t(DataRegistry.rules("coop_rules").code.default_name))
