extends GutTest
## Regressioni del BOT CAOTICO (QA 83, docs/audit_2026-10-22/qa/83_BOT_CAOS.md). Un test per ogni bug corretto; il nome
## riporta l'identificativo del rapporto (C-nn).

const Env := preload("res://tests/helpers/coop_env.gd")

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_chaos_reg_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


# ---------------------------------------------------------------- C-01: reputazione in overflow e salvataggio inaffidabile

func test_c01_reputazione_non_va_in_overflow() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var mk := Game.system("market") as MarketSystem
	mk.add_reputation("order_of_wardens", 100)
	mk.add_reputation("order_of_wardens", 9223372036854775807)
	assert_gte(mk.reputation("order_of_wardens"), 100, "la reputazione non diventa negativa")
	assert_lte(mk.reputation("order_of_wardens"), MarketSystem.REP_CAP, "saturata al tetto tecnico")
	mk.add_reputation("order_of_wardens", 5)
	assert_lte(mk.reputation("order_of_wardens"), MarketSystem.REP_CAP)
	# e il salvataggio resta caricabile dal file principale
	assert_true(SaveService.save_now())
	var res := SaveService.load_slot(1)
	assert_true(res.ok, "load_slot: %s" % str(res.get("error", "")))
	assert_eq(res.source, "main")


func test_c01_un_intero_fuori_campo_si_satura_e_il_salvataggio_riesce() -> void:
	# SHARK 1.0 #3: prima la scrittura veniva rifiutata (e ogni salvataggio successivo falliva); ora il campo si satura ai limiti
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.currencies["gold"] = 777
	assert_true(SaveService.save_now(), "salvataggio buono")
	(GameState.data.factions as Dictionary)["order_of_wardens"] = -9223372036854775807 - 1
	GameState.data.currencies["gold"] = 888
	assert_true(SaveService.save_now(), "il salvataggio riesce, con il campo saturato")
	var res := SaveService.load_slot(1)
	assert_true(res.ok)
	assert_eq(res.source, "main")
	assert_eq(int(res.data.currencies.gold), 888, "il progresso successivo NON si perde")
	assert_eq(int(res.data.factions.order_of_wardens), -SaveCodec.SAFE_INT_MAX, "saturato al limite")
	assert_false(FileAccess.file_exists(SaveService.slot_path(1) + ".tmp"), "nessun file temporaneo lasciato")


# ---------------------------------------------------------------- C-02: la Cozy deve marcare le Schede e i risultati del coop

func test_c02_la_scheda_del_compagno_porta_la_marcatura_cozy() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var co := Game.system("coop") as CoopSystem
	var ms := Game.system("modes") as ModeSystem
	var f: Dictionary = co.rules().format
	var now := Clock.now_unix()
	ms.set_cozy(false)
	var plain := CoopCodec.unpack(co.export_hero_code(now), int(f.version), "", str(f.prefix), int(co.rules().code.max_chars), int(co.rules().code.max_json_bytes))
	assert_true(plain.ok)
	assert_false(bool(plain.payload.cozy), "partita senza Cozy: scheda non marcata")
	ms.set_cozy(true)
	var cozy := CoopCodec.unpack(co.export_hero_code(now), int(f.version), "", str(f.prefix), int(co.rules().code.max_chars), int(co.rules().code.max_json_bytes))
	assert_true(cozy.ok)
	assert_true(bool(cozy.payload.cozy), "partita in Cozy: la scheda porta la marcatura")
	ms.set_cozy(false)
	assert_true(co.is_cozy(), "la Cozy usata resta marcata per sempre (ModeSystem.cozy_used)")


# ---------------------------------------------------------------- C-03: gzip vuoto = ciclo infinito di decompress_dynamic

const EMPTY_GZIP := [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]


func test_c03_un_codice_coop_con_gzip_vuoto_viene_rifiutato_senza_bloccarsi() -> void:
	var code := "VFH1." + Marshalls.raw_to_base64(PackedByteArray(EMPTY_GZIP))
	var t0 := Time.get_ticks_msec()
	var r := CoopCodec.unpack(code, 1)
	assert_false(r.ok)
	assert_eq(r.error, "gzip")
	assert_lt(Time.get_ticks_msec() - t0, 2000, "risposta immediata")


func test_c03_un_salvataggio_o_una_stringa_con_gzip_vuoto_viene_rifiutato() -> void:
	var r := SaveCodec.decode(PackedByteArray(EMPTY_GZIP))
	assert_false(r.ok)
	assert_eq(r.error, "gzip")
	var b := SaveCodec.from_base64(Marshalls.raw_to_base64(PackedByteArray(EMPTY_GZIP)))
	assert_false(b.ok)
	assert_false(SaveService.import_string(Marshalls.raw_to_base64(PackedByteArray(EMPTY_GZIP))).ok)


# ---------------------------------------------------------------- C-04: acquisto all'Emporio con quantità enorme (ciclo di prezzi infinito)

func test_c04_acquisto_con_quantita_enorme_e_rifiutato_subito() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var mk := Game.system("market") as MarketSystem
	(Game.system("bank") as BankSystem).add_gold(1000)
	var gold0 := (Game.system("bank") as BankSystem).gold()
	var t0 := Time.get_ticks_msec()
	for q in [4611686018427387904, 9223372036854775807, MarketSystem.BULK_MAX + 1]:
		var st := mk.shop_status("buy_sickle_copper", q)
		assert_false(st.ok)
		assert_false(mk.buy("buy_sickle_copper", q))
	assert_lt(Time.get_ticks_msec() - t0, 2000, "nessun ciclo sulle quantità")
	assert_eq((Game.system("bank") as BankSystem).gold(), gold0, "nessun oro speso")
	assert_true(mk.shop_status("buy_sickle_copper", 1).ok or mk.shop_status("buy_sickle_copper", 1).reason != "unknown", "l'acquisto normale resta valutato")


# ---------------------------------------------------------------- C-06: la soglia di mangiare automatico si perdeva a ogni caricamento

func test_c06_la_soglia_di_mangiare_sopravvive_a_salvataggio_e_caricamento() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var cb := Game.system("combat") as CombatSystem
	cb.set_eat_pct(int(cb.auto_eat_max_pct()) - 4)          # sotto il massimo (il massimo stesso = predefinito, salvato come 0)
	assert_true(SaveService.save_now())
	assert_true(Game.load_game(1).ok)
	assert_eq(int((Game.system("combat") as CombatSystem).state.eat_pct), int(cb.auto_eat_max_pct()) - 4, "eat_pct invariata dopo il ricaricamento")
	assert_true((Game.system("combat") as CombatSystem).state.eat_pct is int, "e resta un intero")


# ---------------------------------------------------------------- C-07: impostazioni NaN/inf · C-08: valuta in overflow

func test_c07_le_impostazioni_numeriche_rifiutano_nan_e_infinito() -> void:
	var old: Variant = Settings.get_value("volume_master")
	for bad in [NAN, INF, -INF]:
		assert_false(Settings.set_value("volume_master", bad), "set_value(%s) rifiutata" % str(bad))
		assert_false(Settings.set_value("ui_scale", bad))
		assert_false(Settings.set_value("game_speed", bad))
	assert_eq(Settings.get_value("volume_master"), old, "il valore precedente resta")


func test_c08_la_valuta_non_va_in_overflow() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var bank := Game.system("bank") as BankSystem
	bank.add_gold(1000)
	bank.add_gold(9223372036854775807)
	assert_gt(bank.gold(), 0, "l'oro non diventa negativo")
	assert_lte(bank.gold(), BankSystem.QTY_CAP)
	bank.add_gold(5)
	assert_eq(bank.gold(), BankSystem.QTY_CAP, "saturato, non riavvolto")
	assert_true(bank.spend_gold(10), "si può ancora spendere")


# ---------------------------------------------------------------- C-09: lingua vuota · C-10: id d'azione sconosciuto nelle interrogazioni di SkillSystem

func test_c09_la_lingua_vuota_non_viene_applicata_al_motore() -> void:
	var before := TranslationServer.get_locale()
	assert_true(Settings.set_value("locale", ""))
	assert_eq(TranslationServer.get_locale(), before, "il motore mantiene la lingua precedente")
	Settings.set_value("locale", before.substr(0, 2) if before.substr(0, 2) in ["it", "en"] else "it")


func test_c10_le_interrogazioni_su_un_id_sconosciuto_non_vanno_in_errore() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var sk := Game.system("skills") as SkillSystem
	for bad in ["rime_citadel", "", "nope", "gold"]:
		assert_eq(sk.profile_of(bad), {})
		assert_eq(sk.hourly(bad), {})
		assert_eq(sk.expected_per_cycle(bad), {})
		assert_eq(sk.duration_of(bad), 0.0)
	var aid := str(DataRegistry.actions_for_skill("woodcutting")[0].id)
	assert_gt(sk.duration_of(aid), 0.0, "un'azione vera resta calcolata")
	assert_false(sk.hourly(aid).is_empty())


# ---------------------------------------------------------------- C-11: Prova della settimana con orologio impossibile

func test_c11_la_prova_con_un_orologio_impossibile_non_salva_un_risultato_che_sparirebbe() -> void:
	var env: Object = Env.make(13, 60, "warrior", 6, 1700000001)
	env.state.unlocks.append("feature:rift")
	assert_false(env.coop.weekly_run(1760000000).is_empty(), "con la data giusta la Prova funziona")
	var n_before: int = (env.coop.state.results as Dictionary).size()
	for bad_now in [0, 86400, -9223372036854775807 - 1, 9223372036854775807]:
		assert_true(env.coop.weekly_run(bad_now).is_empty(), "data %s: nessun risultato" % str(bad_now))
	assert_eq((env.coop.state.results as Dictionary).size(), n_before, "nessuna settimana fasulla in classifica")
	Env.free_all()


# ---------------------------------------------------------------- C-12: XP NaN (il salvataggio la scriveva come null e il caricamento andava in errore)

func test_c12_xp_nan_ignorata_e_xp_null_nel_salvataggio_diventa_zero() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var sk := Game.system("skills") as SkillSystem
	var before := float(GameState.data.skills.woodcutting.xp)
	sk.add_xp("woodcutting", NAN)
	sk.add_xp("woodcutting", INF)
	assert_eq(float(GameState.data.skills.woodcutting.xp), before, "NaN/inf ignorati")
	var snap: Dictionary = Game.snapshot(true)
	snap.skills.woodcutting["xp"] = null
	SaveService.write_atomic(1, SaveCodec.encode(snap))
	assert_true(Game.load_game(1).ok)
	assert_eq(float(GameState.data.skills.woodcutting.xp), 0.0, "xp null -> 0, senza errori")


# ---------------------------------------------------------------- C-05: sezioni/campi di tipo sbagliato in un salvataggio

func test_c05_un_campo_intero_con_testo_qualsiasi_e_corruzione() -> void:
	var d := {"currencies": {"gold": "x"}, "stats": {"kills": "12abc"}}
	var errs := SaveCodec.normalize(d, PackedStringArray(["currencies.gold", "stats.kills"]))
	assert_eq(errs.size(), 2, "testo non numerico in un campo intero")
	var ok := {"currencies": {"gold": "11351917047991728322"}, "stats": {"kills": "-5"}}
	assert_eq(SaveCodec.normalize(ok, PackedStringArray(["currencies.gold", "stats.kills"])).size(), 0, "interi enormi come stringa restano ammessi (R-SAV-7)")


func test_c05_sezioni_di_tipo_sbagliato_ripartono_dallo_stato_iniziale() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var snap: Dictionary = Game.snapshot(true)
	for key in ["bank", "assist", "contracts", "hero", "skills", "currencies", "stats", "equipment", "modes", "codex", "unlocks"]:
		var d := snap.duplicate(true)
		d[key] = 7 if not (d[key] is Array) else "x"
		SaveService.write_atomic(1, SaveCodec.encode(d))
		var r := Game.load_game(1)
		if not r.ok:       # FIX-F2: una sezione di tipo sbagliato è rifiutata (e ripiega sul backup, qui assente): mai uno stato a metà
			assert_eq(str(r.get("error", r.get("reason", ""))).contains("corrupt"), true, "rifiuto esplicito per %s di tipo sbagliato" % key)
			continue
		for i in 20:
			Game._on_step(0.1)
		Game._on_long_gap(300.0)
		assert_eq(typeof(GameState.data[key]), typeof(snap[key]), "%s riportata al tipo giusto" % key)
	var bad := snap.duplicate(true)
	bad.currencies["gold"] = "x"
	SaveService.write_atomic(1, SaveCodec.encode(bad))
	var lr := SaveService.load_slot(1)
	assert_ne(str(lr.get("source", "")), "main", "il file corrotto non è accettato come buono")
