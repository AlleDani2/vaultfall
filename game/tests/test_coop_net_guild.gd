extends GutTest
## COOP-2: Gilda di amici (parti pure): fondo a solo versamento, tetti e cassetto di 7 giorni, voti e progetti,
## bonus uguali e con tetto, Boss della settimana a danno cumulativo, ruoli e anti-griefing, serializzazione,
## hash e determinismo (stesse operazioni = stesso stato), salvataggio atomico con backup.

const A := "aaaaaaaaaaaaaaaa"
const B := "bbbbbbbbbbbbbbbb"
const C := "cccccccccccccccc"
const T0 := 1_800_000_000          # un istante qualsiasi (secondi unix): lo decide sempre l'host
const DAY := 86400

var rules: Dictionary
var vals: Dictionary
var _seq := {}
var _dir := ""


func before_all() -> void:
	rules = DataRegistry.rules("coop_net_rules")
	vals = CoopGuild.item_values_from(DataRegistry, rules)


func before_each() -> void:
	_seq = {}
	_dir = "user://test_coop_net_%d" % Time.get_ticks_usec()


func after_each() -> void:
	var d := DirAccess.open(_dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(_dir)


func _g() -> CoopGuild:
	var g := CoopGuild.make(rules, vals)
	g.create("g_0123456789ab", "Amici", A, "Ale", T0)
	return g


func _op(g: CoopGuild, uid: String, k: String, extra: Dictionary = {}, ts: int = T0) -> Dictionary:
	# come il client: il numero di sequenza avanza solo quando l'host accetta il comando
	var seq := int(_seq.get(uid, 0)) + 1
	var op := {"k": k, "uid": uid, "seq": seq, "ts": ts}
	op.merge(extra, true)
	var r := g.apply(op)
	if r.ok:
		_seq[uid] = seq
	return r


func _join(g: CoopGuild, uid: String, nm: String, ts: int = T0) -> void:
	assert_true(g.apply({"k": "join", "uid": uid, "name": nm, "ts": ts}).ok)


func test_fondo_a_solo_versamento() -> void:
	var g := _g()
	assert_false(rules.deposit.items.is_empty())
	assert_true(_op(g, A, "deposit", {"item": "gold", "qty": 100}).ok)
	assert_eq(g.fund_points(), 100)
	assert_true(_op(g, A, "deposit", {"item": "log_pine", "qty": 10}).ok)
	assert_eq(g.fund_points(), 100 + 10 * int(vals.log_pine))
	# nessuna operazione per riprendere, regalare o scambiare
	for k in ["withdraw", "gift", "trade", "take", "transfer"]:
		assert_eq(_op(g, A, k, {"item": "gold", "qty": 1}).err, "bad_op", k)
	# Casse, chiavi, reliquie, gemme, equipaggiamento: non versabili
	for it in ["crate_millbrook", "key_t1", "relic_millbrook_1", "gem_quartz", "plate_helm_copper", "food_bleak"]:
		assert_eq(_op(g, A, "deposit", {"item": it, "qty": 1}).err, "not_depositable", it)
	assert_eq(_op(g, A, "deposit", {"item": "gold", "qty": 0}).err, "bad_qty")
	assert_eq(_op(g, A, "deposit", {"item": "gold", "qty": -5}).err, "bad_qty")
	for it in rules.deposit.items:
		var sub := str(DataRegistry.item(str(it)).get("subcategory", ""))
		assert_true(sub in ["log", "ore", "fish_raw", "fiber", "herb", "hide", "meat_raw", "crop"], "materia prima di base: " + str(it))


func test_tetto_giornaliero_e_cassetto_7_giorni() -> void:
	var g := _g()
	var daily := g.allowance(A, T0)
	assert_gt(daily, 0)
	assert_eq(_op(g, A, "deposit", {"item": "gold", "qty": daily + 1}).err, "cap", "oltre il tetto")
	assert_true(_op(g, A, "deposit", {"item": "gold", "qty": daily}).ok)
	assert_eq(g.allowance(A, T0), 0)
	assert_eq(_op(g, A, "deposit", {"item": "gold", "qty": 1}).err, "cap")
	# il cassetto si riempie un giorno alla volta fino a 7 giorni, non oltre
	assert_eq(g.allowance(A, T0 + DAY), daily)
	assert_eq(g.allowance(A, T0 + 3 * DAY), 3 * daily)
	assert_eq(g.allowance(A, T0 + 30 * DAY), 7 * daily)
	assert_true(_op(g, A, "deposit", {"item": "gold", "qty": 7 * daily}, T0 + 30 * DAY).ok, "chi gioca una volta a settimana versa quanto chi gioca ogni giorno")


func test_voto_progetto_e_bonus_uguali() -> void:
	var g := _g()
	_join(g, B, "Bea")
	_join(g, C, "Cico")
	assert_eq(g.n_active(), 3)
	assert_eq(_op(g, B, "propose", {"project": "banner_scholars"}).err, "not_leader", "propone solo il Capo")
	assert_true(_op(g, A, "propose", {"project": "banner_scholars"}).ok)
	assert_eq(str(g.state.target), "", "1 voto su 3: non basta")
	assert_true(_op(g, B, "vote", {"yes": true}).ok)
	assert_eq(str(g.state.target), "banner_scholars", "maggioranza: approvato")
	var cost := g.project_cost("banner_scholars", 1)
	assert_gt(cost, int(rules.projects[0].cost_by_level[1]), "costo scalato con n^0,75")
	# versano in tre fino al costo (ognuno nel suo tetto)
	var t := T0
	while g.project_level("banner_scholars") < 1:
		for u in [A, B, C]:
			var q := mini(g.allowance(u, t), cost)
			if q > 0:
				assert_true(_op(g, u, "deposit", {"item": "gold", "qty": q}, t).ok)
		t += DAY
	assert_eq(g.project_level("banner_scholars"), 1)
	assert_eq(int(g.state.fund.spent), cost)
	var mods := g.mods_by_source()
	assert_true(mods.has("guild:banner_scholars"))
	assert_eq(str(mods["guild:banner_scholars"][0].key), "skill_xp_pct:all")
	assert_eq(str(mods["guild:banner_scholars"][0].mode), "add")
	assert_almost_eq(float(mods["guild:banner_scholars"][0].value), float(rules.projects[0].value_by_level[1]), 0.0001)


func test_bonus_asintotici_con_tetto() -> void:
	var cap := float(rules.bonus_cap_pct)
	assert_lte(cap, 10.0)
	var levels := {}
	for p in rules.projects:
		levels[str(p.id)] = 999          # livelli fuori scala: il valore resta al massimo dei dati
		var v: Array = p.value_by_level
		for i in range(1, v.size()):
			assert_gt(float(v[i]), float(v[i - 1]), "cresce")
			if i >= 2:
				assert_lte(float(v[i]) - float(v[i - 1]), float(v[i - 1]) - float(v[i - 2]) + 0.0001, "asintotico")
		assert_lt(float(v[-1]), float(p.cap_pct))
	var per_key := {}
	for src in CoopGuild.mods_from_levels(levels, rules).values():
		for m in src:
			per_key[m.key] = float(per_key.get(m.key, 0.0)) + float(m.value)
	for k in per_key:
		assert_lte(float(per_key[k]), cap, "tetto per chiave " + k)
	# via Modifiers (unico sistema di bonus): la fonte guild:* si somma con la regola add
	var st := ModifierStack.new()
	st.set_catalog(DataRegistry.table("modifier_catalog"))
	for src in CoopGuild.mods_from_levels({"banner_scholars": 10}, rules):
		assert_true(st.set_source(src, CoopGuild.mods_from_levels({"banner_scholars": 10}, rules)[src]), "chiave nel catalogo")
	assert_almost_eq(st.apply(100.0, "skill_xp_pct", ["woodcutting", "gathering", "all"]),
		100.0 * (1.0 + float(rules.projects[0].value_by_level[10]) / 100.0), 0.001)


func test_boss_della_settimana_cumulativo_con_tetti() -> void:
	var g := _g()
	_join(g, B, "Bea")
	var b: Dictionary = g.state.boss
	assert_false(b.is_empty())
	assert_eq(int(b.week), g.week_of(T0))
	var hp := int(b.hp)
	var cap := int(b.cap)
	assert_eq(cap, int(rules.boss.member_week_cap_mult_milli) * hp / 1000 / 2, "tetto per socio = 1,5 x vita / n")
	assert_lt(cap, hp, "con 2 soci nessuno lo finisce da solo")
	assert_eq(_op(g, A, "boss_hit", {"week": int(b.week) - 1, "pts": 10}).err, "stale_week")
	assert_eq(_op(g, A, "boss_hit", {"week": int(b.week), "pts": 999999}).err, "bad_pts")
	var per := int(rules.boss.max_points_per_attempt)
	# A colpisce finché ha tentativi: il contributo si ferma al tetto
	var t := T0
	var guard := 0
	while int(g.state.boss.by_member.get(A, 0)) < cap and guard < 50:
		var r := _op(g, A, "boss_hit", {"week": int(b.week), "pts": per}, t)
		if r.err == "no_attempts":
			t += DAY
		guard += 1
	assert_eq(int(g.state.boss.by_member[A]), mini(cap, hp))
	var before := int(g.state.boss.dmg)
	_op(g, A, "boss_hit", {"week": int(b.week), "pts": per}, t + DAY)
	assert_eq(int(g.state.boss.dmg), before, "oltre il tetto non conta")
	var fund0 := g.fund_points()
	var trophies0 := int(g.state.trophies)
	while not bool(g.state.boss.done) and guard < 120:
		var r2 := _op(g, B, "boss_hit", {"week": int(b.week), "pts": per}, t)
		if r2.err == "no_attempts":
			t += DAY
		guard += 1
	assert_true(bool(g.state.boss.done), "sconfitto dalla somma dei contributi")
	assert_eq(int(g.state.boss.dmg), hp, "somma esatta, niente danno oltre la vita")
	assert_eq(int(g.state.trophies), trophies0 + 1, "trofeo (cosmetico) della gilda")
	assert_gt(g.fund_points(), fund0, "premio UGUALE per tutti: punti nel fondo comune, spendibili solo in progetti")
	assert_eq(_op(g, A, "boss_hit", {"week": int(b.week), "pts": 10}, t).err, "boss_done")
	# nuova settimana: nuovo boss, contributi azzerati
	var nw := t + int(rules.boss.week_s)
	assert_true(g.apply({"k": "time", "ts": nw}).ok)
	assert_eq(int(g.state.boss.week), g.week_of(nw))
	assert_eq(int(g.state.boss.dmg), 0)


func test_tentativi_si_accumulano_fino_a_7_giorni() -> void:
	var g := _g()
	var per_day := int(rules.boss.attempts_per_day)
	assert_eq(g.boss_attempts(A, T0), per_day)
	assert_eq(g.boss_attempts(A, T0 + 3 * DAY), 4 * per_day)
	assert_eq(g.boss_attempts(A, T0 + 40 * DAY), 7 * per_day, "cassetto pieno a 7 giorni, nessun orario fisso")


func test_ruoli_espulsione_e_contributi_conservati() -> void:
	var g := _g()
	_join(g, B, "Bea")
	assert_true(_op(g, B, "deposit", {"item": "gold", "qty": 50}).ok)
	var pts := g.fund_points()
	assert_eq(_op(g, B, "kick", {"target": A}).err, "not_leader")
	assert_eq(_op(g, A, "kick", {"target": A}).err, "bad_target")
	assert_true(_op(g, A, "kick", {"target": B}).ok)
	assert_false(g.is_member(B))
	assert_eq(g.fund_points(), pts, "l'espulsione non cancella i contributi")
	assert_eq(int(g.members()[B].dep_total), 50)
	assert_eq(_op(g, B, "deposit", {"item": "gold", "qty": 1}).err, "not_member")
	# rientro: i contributi di prima ci sono ancora
	_join(g, B, "Bea")
	assert_eq(int(g.members()[B].dep_total), 50)
	# il Capo esce: il ruolo passa al socio attivo più anziano
	assert_true(_op(g, A, "leave").ok)
	assert_eq(g.role_of(B), CoopGuild.ROLE_LEADER)
	assert_eq(g.fund_points(), pts, "uscire non toglie nulla al fondo")


func test_capo_decide_dopo_24_ore_senza_maggioranza_contraria() -> void:
	var g := _g()
	_join(g, B, "Bea")
	_join(g, C, "Cico")
	assert_true(_op(g, A, "propose", {"project": "guild_toolshed"}).ok)
	assert_eq(_op(g, A, "decide").err, "too_early")
	assert_true(_op(g, A, "decide", {}, T0 + int(rules.vote.proposal_timeout_s)).ok)
	assert_eq(str(g.state.target), "guild_toolshed")
	# maggioranza contraria: respinto
	var g2 := _g()
	_join(g2, B, "Bea")
	_join(g2, C, "Cico")
	_seq = {}
	assert_true(_op(g2, A, "propose", {"project": "guild_toolshed"}).ok)
	_op(g2, B, "vote", {"yes": false})
	_op(g2, C, "vote", {"yes": false})
	assert_true((g2.state.proposal as Dictionary).is_empty(), "respinto")
	assert_eq(str(g2.state.target), "")


func test_idempotenza_comandi() -> void:
	var g := _g()
	var op := {"k": "deposit", "uid": A, "seq": 1, "ts": T0, "item": "gold", "qty": 10}
	assert_true(g.apply(op).ok)
	assert_eq(g.apply(op).err, "dup", "stesso numero di sequenza: applicato una volta sola")
	var later := {"k": "deposit", "uid": A, "seq": 3, "ts": T0, "item": "gold", "qty": 5}
	assert_eq(g.apply(later).err, "gap", "il 3 non passa prima del 2 (comando perso in rete)")
	assert_true(g.apply({"k": "deposit", "uid": A, "seq": 2, "ts": T0, "item": "gold", "qty": 1}).ok)
	assert_true(g.apply(later).ok, "dopo il 2 il 3 entra")
	assert_eq(g.fund_points(), 16)
	# comando rifiutato (voto senza proposta): l'host lo «salta», il numero si consuma e il successivo entra
	assert_eq(g.apply({"k": "vote", "uid": A, "seq": 4, "ts": T0, "yes": true}).err, "no_proposal")
	assert_true(g.apply({"k": "skip", "uid": A, "seq": 4, "ts": T0}).ok)
	assert_true(g.apply({"k": "deposit", "uid": A, "seq": 5, "ts": T0, "item": "gold", "qty": 0 + 1}).ok)
	assert_eq(g.fund_points(), 17)
	assert_true(g.apply({"k": "join", "uid": B, "name": "Bea", "ts": T0, "seq0": 41}).ok)
	assert_eq(int(g.members()[B].seq), 41, "il nuovo socio parte dal numero dichiarato nel saluto")
	assert_true(g.apply({"k": "deposit", "uid": B, "seq": 42, "ts": T0, "item": "gold", "qty": 4}).ok)
	assert_eq(g.fund_points(), 21)
	var h := g.state_hash()
	assert_eq(g.apply({"k": "deposit", "uid": B, "seq": 43, "ts": T0, "item": "crate_millbrook", "qty": 1}).err, "not_depositable")
	assert_eq(g.state_hash(), h, "un'operazione rifiutata non cambia nulla")


func test_determinismo_e_serializzazione() -> void:
	var g := _g()
	var ops: Array = []
	ops.append({"k": "join", "uid": B, "name": "Bea", "ts": T0 + 5})
	ops.append({"k": "deposit", "uid": A, "seq": 1, "ts": T0 + 10, "item": "gold", "qty": 77})
	ops.append({"k": "deposit", "uid": B, "seq": 1, "ts": T0 + 20, "item": "log_pine", "qty": 3})
	ops.append({"k": "propose", "uid": A, "seq": 2, "ts": T0 + 30, "project": "guild_granary"})
	ops.append({"k": "vote", "uid": B, "seq": 2, "ts": T0 + 40, "yes": true})
	ops.append({"k": "boss_hit", "uid": B, "seq": 3, "ts": T0 + 50, "week": g.week_of(T0), "pts": 321})
	for o in ops:
		assert_true(g.apply(o).ok, str(o))
	# copia ricostruita dal JSON (come arriva da rete o da file: i numeri diventano float) = stesso hash
	var json := JSON.stringify(g.to_dict())
	var parsed: Dictionary = JSON.parse_string(json)
	var g2 := CoopGuild.make(rules, vals)
	assert_eq(g2.from_dict(parsed), "")
	assert_eq(g2.state_hash(), g.state_hash())
	# stesse operazioni, passate come JSON (float), su un'altra copia dalla fondazione: stesso stato
	var g3 := _g()
	for o in ops:
		assert_true(g3.apply(JSON.parse_string(JSON.stringify(o))).ok)
	assert_eq(g3.state_hash(), g.state_hash(), "determinismo: stesse operazioni = stesso hash")
	# contatori grandi come stringhe nella forma salvata (R-SAV-7), anche oltre 2^53
	g.state.fund.points = 9007199254740993
	var d := g.to_dict()
	assert_typeof(d.fund.points, TYPE_STRING)
	var g4 := CoopGuild.make(rules, vals)
	g4.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(g4.fund_points(), 9007199254740993, "nessuna perdita di cifre")
	# un desync (una cifra diversa) cambia l'hash
	g4.state.fund.points = 9007199254740992
	assert_ne(g4.state_hash(), g.state_hash())
	assert_false(JSON.stringify(g.to_dict()).contains("."), "nessun numero decimale nello stato di gilda")


func test_salvataggio_atomico_con_backup() -> void:
	var store := CoopGuildStore.new()
	store.dir = _dir
	var g := _g()
	assert_eq(store.save(g, "host"), OK)
	_op(g, A, "deposit", {"item": "gold", "qty": 5})
	assert_eq(store.save(g, "host"), OK)
	assert_true(FileAccess.file_exists(store.backup_path(g.guild_id(), 1)), "backup ruotato")
	var res := store.load_guild(g.guild_id())
	assert_true(res.ok)
	var g2 := CoopGuild.make(rules, vals)
	g2.from_dict(res.guild)
	assert_eq(g2.state_hash(), g.state_hash())
	# file principale rovinato: si riparte dal backup
	var f := FileAccess.open(store.path_for(g.guild_id()), FileAccess.WRITE)
	f.store_string("rovinato")
	f.close()
	res = store.load_guild(g.guild_id())
	assert_true(res.ok)
	assert_eq(res.source, "bak1")
	assert_eq(store.list_ids(), PackedStringArray([g.guild_id()]))
	assert_false(store.load_guild("g_../../evil").ok, "id non valido")
	store.delete(g.guild_id())
	assert_false(store.load_guild(g.guild_id()).ok)


func test_gilda_piena() -> void:
	var g := _g()
	for i in int(rules.max_members) - 1:
		_join(g, "%016x" % (i + 100), "Socio%d" % i)
	assert_eq(g.n_active(), int(rules.max_members))
	assert_eq(g.apply({"k": "join", "uid": "ffffffffffffffff", "name": "Ultimo", "ts": T0}).err, "full")


func test_tentativo_contro_il_boss_locale() -> void:
	var hero := {"hp": 400.0, "acc": 300.0, "eva": 200.0, "arm": 50.0, "min_hit": 20.0, "max_hit": 40.0,
		"interval": 2.4, "crit": 0.1, "critd": 1.5}
	var r1 := CoopBossSim.attempt(hero, 20, rules.boss, 1234)
	var r2 := CoopBossSim.attempt(hero, 20, rules.boss, 1234)
	assert_eq(r1.pts, r2.pts, "stesso seme = stesso esito")
	assert_between(int(r1.pts), 0, int(rules.boss.max_points_per_attempt))
	var strong := hero.duplicate()
	strong.max_hit = 400.0
	strong.min_hit = 200.0
	assert_gt(int(CoopBossSim.attempt(strong, 20, rules.boss, 1234).pts), int(r1.pts), "build migliore = più contributo")
	assert_ne(CoopBossSim.seed_for(1, A, 1), CoopBossSim.seed_for(1, A, 2))
