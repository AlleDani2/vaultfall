class_name CoopGuild
extends RefCounted
@warning_ignore_start("integer_division")    # divisioni intere VOLUTE: lo stato di gilda è solo interi
## Stato e regole della «Gilda di amici» (COOP-2, docs/audit_2026-10-22/70). Classe PURA e deterministica:
## nessun nodo, nessun `await`, nessun tempo reale (l'ora arriva dentro l'operazione, `op.ts`, decisa dall'host).
##
## Modello «comandi all'host, operazioni a tutti»: l'host (autorevole) riceve un comando, costruisce l'operazione
## (con ts e seq), la applica con `apply(op)` e la rimanda a tutti; i client applicano la STESSA operazione alla loro
## copia con lo stesso codice. Lo stato contiene solo interi e stringhe (niente float: nessuna differenza tra Windows e
## Linux); i contatori che possono crescere molto si serializzano come stringhe (R-SAV-7). `state_hash()` = MD5 del
## JSON ordinato: se l'hash dell'host e quello del client differiscono allo stesso gseq, il client chiede l'istantanea.
##
## Regole etiche (CLAUDE.md regola 5): il fondo è a SOLO VERSAMENTO. Non esiste alcuna operazione che tolga punti o
## oggetti dal fondo verso un giocatore; il fondo si spende SOLO nei progetti, i cui bonus sono UGUALI per tutti i soci.
## Uscire o essere espulsi NON cancella i contributi. Casse, chiavi, finiture, reliquie non sono versabili.

const SCHEMA := 1
const ROLE_LEADER := "leader"
const ROLE_MEMBER := "member"
const DAY_S := 86400

## Contatori serializzati come stringhe (possono superare 2^53 in partite lunghissime).
const BIG_FUND := ["points", "spent", "rewards"]
const BIG_MEMBER := ["dep_total", "allow"]
const BIG_BOSS := ["hp", "dmg", "cap"]

## Chiavi di data/coop_net_rules.json lette dal codice coop (lette SENZA numeri di ripiego, regola 2):
## se ne manca una il servizio non parte e il test tests/test_coop_net_protocol.gd fallisce.
const REQUIRED_RULES: PackedStringArray = ["protocol_version", "default_port", "max_members", "presence.interval_s",
	"presence.stale_s", "presence.timeout_s", "presence.crate_show_s", "presence.max_friends_shown",
	"net.max_packet_bytes", "net.max_snapshot_bytes", "net.rate_per_s", "net.rate_burst", "net.strikes_kick",
	"net.ping_interval_s", "net.hash_interval_s", "net.resend_s", "net.reconnect_min_s", "net.reconnect_max_s",
	"net.hello_timeout_s", "net.save_debounce_s", "net.copy_save_debounce_s", "net.max_outbox", "net.max_code_len",
	"name.max_len", "log_max", "deposit.items", "deposit.gold_points_per_coin", "deposit.daily_cap_mult_milli",
	"deposit.drawer_days", "deposit.max_qty_per_cmd", "member_scale_milli", "bonus_cap_pct", "projects",
	"vote.proposal_timeout_s", "boss.week_s", "boss.attempt_s", "boss.points_per_kill", "boss.hp_points_base",
	"boss.member_week_cap_mult_milli", "boss.attempts_per_day", "boss.drawer_days", "boss.monster_type",
	"boss.max_points_per_attempt", "boss.boss_min_hit_ratio", "boss.reward_fund_points_base", "boss.bosses"]

var rules: Dictionary = {}       # data/coop_net_rules.json (record unico)


## Chiavi richieste assenti dalle regole (vuoto = tutto a posto).
static func missing_rule_keys(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for path in REQUIRED_RULES:
		var cur: Variant = r
		for part in path.split("."):
			if cur is Dictionary and (cur as Dictionary).has(part):
				cur = cur[part]
			else:
				out.append(path)
				break
	for p in r.get("projects", []):
		for k in ["id", "cap_pct", "mods", "max_level", "cost_by_level", "value_by_level", "name"]:
			if not (p is Dictionary) or not p.has(k):
				out.append("projects[]." + k)
	return out
var values: Dictionary = {}      # oggetto versabile -> punti per unità ("gold" compreso)
var state: Dictionary = {}


## Gilda con le regole dei dati. `item_values`: id -> valore (dai dati); "gold" si aggiunge da solo.
static func make(p_rules: Dictionary, item_values: Dictionary) -> CoopGuild:
	var g := CoopGuild.new()
	g.rules = p_rules
	var dep: Dictionary = p_rules["deposit"]
	for id in dep.get("items", []):
		if item_values.has(id):
			g.values[str(id)] = maxi(1, int(item_values[id]))
	g.values["gold"] = maxi(1, int(dep["gold_points_per_coin"]))
	return g


## Valori dei versabili letti dal DataRegistry (oggetti di data/items).
static func item_values_from(data: Object, p_rules: Dictionary) -> Dictionary:
	var out := {}
	for id in p_rules["deposit"].get("items", []):
		var it: Dictionary = data.item(str(id))
		if not it.is_empty():
			out[str(id)] = int(it.get("value", 1))
	return out


static func new_guild_id(rng: RandomNumberGenerator) -> String:
	var s := "g_"
	for i in 12:
		s += "0123456789abcdef"[rng.randi_range(0, 15)]
	return s


func create(guild_id: String, guild_name: String, founder_uid: String, founder_name: String, ts: int) -> void:
	state = {"schema": SCHEMA, "id": guild_id, "name": guild_name, "gseq": 0, "created_ts": ts, "trophies": 0,
		"members": {}, "fund": {"points": 0, "spent": 0, "rewards": 0, "by_item": {}},
		"projects": {}, "proposal": {}, "target": "", "boss": {}, "log": []}
	for p in rules.get("projects", []):
		state.projects[str(p.id)] = 0
	_add_member(state, founder_uid, founder_name, ts, ROLE_LEADER)
	_advance(state, ts)
	_log(state, ts, "found", founder_uid, guild_name, "")


# ------------------------------------------------------------------ letture

func gseq() -> int:
	return int(state.get("gseq", 0))


func guild_id() -> String:
	return str(state["id"])


func members() -> Dictionary:
	return state.get("members", {})


func is_member(uid: String) -> bool:
	return members().has(uid) and bool(members()[uid].get("active", false))


func role_of(uid: String) -> String:
	return str(members().get(uid, {}).get("role", "")) if is_member(uid) else ""


func n_active() -> int:
	return _n_active(state)


func fund_points() -> int:
	return int(state.get("fund", {}).get("points", 0))


func project_level(pid: String) -> int:
	return int(state.get("projects", {}).get(pid, 0))


func project_def(pid: String) -> Dictionary:
	for p in rules.get("projects", []):
		if str(p.id) == pid:
			return p
	return {}


## Costo del livello `lvl` del progetto per la gilda di oggi (scalato con n^0,75 dai dati, solo interi).
func project_cost(pid: String, lvl: int) -> int:
	return _cost(state, pid, lvl)


## Punti che il socio può versare oggi (cassetto accumulato fino a drawer_days giorni).
func allowance(uid: String, ts: int) -> int:
	if not members().has(uid):
		return 0
	return _allow_now(state, members()[uid], int(ts / DAY_S))


func boss_attempts(uid: String, ts: int) -> int:
	if not members().has(uid):
		return 0
	return _att_now(members()[uid], int(ts / DAY_S))


func week_of(ts: int) -> int:
	return int(ts / maxi(1, int(rules["boss"]["week_s"])))


## Bonus UGUALI per tutti: fonte "guild:<progetto>" -> blocco di modificatori (regola add, docs/14).
func mods_by_source() -> Dictionary:
	return mods_from_levels(state.get("projects", {}), rules)


static func mods_from_levels(levels: Dictionary, p_rules: Dictionary) -> Dictionary:
	var out := {}
	var cap := float(p_rules["bonus_cap_pct"])
	for p in p_rules.get("projects", []):
		var lv := clampi(int(levels.get(str(p.id), 0)), 0, int(p.max_level))
		if lv <= 0:
			continue
		var v := minf(cap, float(p.value_by_level[lv]))
		var block: Array = []
		for m in p.mods:
			block.append({"key": str(m.key), "value": v, "mode": str(m.get("mode", "add"))})
		out["guild:" + str(p.id)] = block
	return out


# ------------------------------------------------------------------ operazioni

## Applica un'operazione (host e client, stesso codice). Lavora su una copia: se l'operazione non è valida lo stato
## resta identico. Ritorna {"ok": bool, "err": String}.
func apply(op: Dictionary) -> Dictionary:
	var work: Dictionary = state.duplicate(true)
	var err := _do(work, op)
	if not err.is_empty():
		return {"ok": false, "err": err}
	work["gseq"] = int(work.gseq) + 1
	state = work
	return {"ok": true, "err": ""}


## Solo controllo (nessuna modifica): "" se l'operazione sarebbe accettata.
func check(op: Dictionary) -> String:
	return _do(state.duplicate(true), op)


func _do(s: Dictionary, op: Dictionary) -> String:
	var k: Variant = op.get("k")
	var ts_v: Variant = op.get("ts")
	if not (k is String) or not (ts_v is int or ts_v is float):
		return "bad_op"
	var ts := int(ts_v)
	if ts < int(s.get("created_ts", 0)):
		return "bad_ts"
	var uid := str(op.get("uid", ""))
	var seq := int(op.get("seq", 0))
	_advance(s, ts)
	match str(k):
		"time":
			return ""
		"join":
			return _op_join(s, uid, str(op.get("name", "")), ts, maxi(0, int(op.get("seq0", 0))))
	# tutte le altre operazioni sono di un socio attivo, con numero di sequenza crescente (applicate una volta sola)
	if not s.members.has(uid) or not bool(s.members[uid].active):
		return "not_member"
	var m: Dictionary = s.members[uid]
	if seq <= int(m.seq):
		return "dup"
	if seq != int(m.seq) + 1:
		return "gap"             # manca un comando precedente: si applicano solo in sequenza
	var err := ""
	match str(k):
		"leave": err = _op_leave(s, uid, ts)
		"kick": err = _op_kick(s, uid, str(op.get("target", "")), ts)
		"deposit": err = _op_deposit(s, uid, str(op.get("item", "")), int(op.get("qty", 0)), ts)
		"propose": err = _op_propose(s, uid, str(op.get("project", "")), ts)
		"vote": err = _op_vote(s, uid, op.get("yes", null), ts)
		"decide": err = _op_decide(s, uid, ts)
		"boss_hit": err = _op_boss_hit(s, uid, int(op.get("week", -1)), int(op.get("pts", -1)), ts)
		"skip": err = ""          # comando rifiutato: consuma solo il numero di sequenza (nessun altro effetto)
		_: err = "bad_op"
	if err.is_empty():
		m["seq"] = seq
	return err


func _op_join(s: Dictionary, uid: String, member_name: String, ts: int, seq0: int) -> String:
	if uid.length() != 16 or member_name.is_empty():
		return "bad_member"
	if s.members.has(uid) and bool(s.members[uid].active):
		return "already"
	if _n_active(s) >= int(rules["max_members"]):
		return "full"
	if s.members.has(uid):           # rientro: i contributi di prima ci sono ancora
		var m: Dictionary = s.members[uid]
		m["active"] = true
		m["name"] = member_name
		m["role"] = ROLE_MEMBER
		_log(s, ts, "rejoin", uid, member_name, "")
	else:
		_add_member(s, uid, member_name, ts, ROLE_MEMBER)
		s.members[uid]["seq"] = seq0
		_log(s, ts, "join", uid, member_name, "")
	_rescale_boss(s)
	_resolve_votes(s, ts)
	return ""


func _op_leave(s: Dictionary, uid: String, ts: int) -> String:
	_deactivate(s, uid, ts)
	_log(s, ts, "leave", uid, "", "")
	return ""


func _op_kick(s: Dictionary, uid: String, target: String, ts: int) -> String:
	if str(s.members[uid].role) != ROLE_LEADER:
		return "not_leader"
	if target == uid or not s.members.has(target) or not bool(s.members[target].active):
		return "bad_target"
	_deactivate(s, target, ts)
	_log(s, ts, "kick", uid, target, "")
	return ""


func _op_deposit(s: Dictionary, uid: String, item: String, qty: int, ts: int) -> String:
	if not values.has(item):
		return "not_depositable"
	var max_q := int(rules["deposit"]["max_qty_per_cmd"])
	if qty < 1 or qty > max_q:
		return "bad_qty"
	var pts := qty * int(values[item])
	var m: Dictionary = s.members[uid]
	var day := int(ts / DAY_S)
	var allow := _allow_now(s, m, day)
	if pts > allow:
		return "cap"
	m["allow"] = allow - pts
	m["allow_day"] = day
	m["dep_total"] = int(m.dep_total) + pts
	var f: Dictionary = s.fund
	f["points"] = int(f.points) + pts
	f.by_item[item] = int(f.by_item.get(item, 0)) + qty
	_log(s, ts, "deposit", uid, item, str(qty))
	_build(s, ts)
	return ""


func _op_propose(s: Dictionary, uid: String, pid: String, ts: int) -> String:
	if str(s.members[uid].role) != ROLE_LEADER:
		return "not_leader"
	var p := project_def(pid)
	if p.is_empty():
		return "bad_project"
	if int(s.projects.get(pid, 0)) >= int(p.max_level):
		return "max_level"
	if not str(s.target).is_empty():
		return "busy"
	s["proposal"] = {"project": pid, "by": uid, "ts": ts, "votes": {uid: true}}
	_log(s, ts, "propose", uid, pid, "")
	_resolve_votes(s, ts)
	return ""


func _op_vote(s: Dictionary, uid: String, yes: Variant, ts: int) -> String:
	if not (yes is bool):
		return "bad_vote"
	if (s.proposal as Dictionary).is_empty():
		return "no_proposal"
	s.proposal.votes[uid] = yes
	_log(s, ts, "vote", uid, str(s.proposal.project), "1" if yes else "0")
	_resolve_votes(s, ts)
	return ""


## Il Capo decide da solo solo dopo `proposal_timeout_s` e se la maggioranza non ha votato contro.
func _op_decide(s: Dictionary, uid: String, ts: int) -> String:
	if str(s.members[uid].role) != ROLE_LEADER:
		return "not_leader"
	var pr: Dictionary = s.proposal
	if pr.is_empty():
		return "no_proposal"
	if ts - int(pr.ts) < int(rules["vote"]["proposal_timeout_s"]):
		return "too_early"
	var tally := _tally(s)
	if tally[1] >= _majority(s):
		return "rejected"
	_approve(s, ts)
	return ""


func _op_boss_hit(s: Dictionary, uid: String, week: int, pts: int, ts: int) -> String:
	var b: Dictionary = s.boss
	var br: Dictionary = rules["boss"]
	if week != int(b.week):
		return "stale_week"
	if bool(b.done):
		return "boss_done"
	if pts < 0 or pts > int(br["max_points_per_attempt"]):
		return "bad_pts"
	var m: Dictionary = s.members[uid]
	var day := int(ts / DAY_S)
	var att := _att_now(m, day)
	if att < 1:
		return "no_attempts"
	m["att"] = att - 1
	m["att_day"] = day
	var mine := int(b.by_member.get(uid, 0))
	var accepted := clampi(pts, 0, maxi(0, int(b.cap) - mine))
	accepted = mini(accepted, maxi(0, int(b.hp) - int(b.dmg)))
	b.by_member[uid] = mine + accepted
	b["dmg"] = int(b.dmg) + accepted
	_log(s, ts, "boss_hit", uid, str(accepted), str(pts))
	if int(b.dmg) >= int(b.hp):
		b["done"] = true
		s["trophies"] = int(s.trophies) + 1
		var reward := int(br["reward_fund_points_base"]) * _scale(s) / 1000
		s.fund["points"] = int(s.fund.points) + reward
		s.fund["rewards"] = int(s.fund.rewards) + reward
		_log(s, ts, "boss_down", uid, str(b.id), str(reward))
		_build(s, ts)
	return ""


# ------------------------------------------------------------------ meccanica interna

func _add_member(s: Dictionary, uid: String, member_name: String, ts: int, role: String) -> void:
	var day := int(ts / DAY_S)
	s.members[uid] = {"name": member_name, "role": role, "active": true, "joined_ts": ts, "seq": 0,
		"dep_total": 0, "allow": 0, "allow_day": day, "att": 0, "att_day": day}
	# il primo giorno: un cassetto pieno di un giorno (versamenti e tentativi)
	var m: Dictionary = s.members[uid]
	m["allow"] = _daily_cap(s)
	m["att"] = int(rules["boss"]["attempts_per_day"])


func _deactivate(s: Dictionary, uid: String, ts: int) -> void:
	var m: Dictionary = s.members[uid]
	m["active"] = false
	var was_leader := str(m.role) == ROLE_LEADER
	m["role"] = ROLE_MEMBER
	if (s.proposal as Dictionary).has("votes"):
		s.proposal.votes.erase(uid)
	if was_leader:
		# il ruolo di Capo passa al socio attivo più anziano (ordine deterministico: ingresso, poi uid)
		var best := ""
		for u in s.members:
			var o: Dictionary = s.members[u]
			if not bool(o.active):
				continue
			if best.is_empty() or int(o.joined_ts) < int(s.members[best].joined_ts) \
					or (int(o.joined_ts) == int(s.members[best].joined_ts) and str(u) < best):
				best = str(u)
		if not best.is_empty():
			s.members[best]["role"] = ROLE_LEADER
			_log(s, ts, "leader", best, "", "")
	_rescale_boss(s)
	_resolve_votes(s, ts)


func _n_active(s: Dictionary) -> int:
	var n := 0
	for u in s.get("members", {}):
		if bool(s.members[u].get("active", false)):
			n += 1
	return n


func _scale(s: Dictionary) -> int:
	var sc: Array = rules["member_scale_milli"]
	return int(sc[clampi(maxi(1, _n_active(s)), 1, sc.size() - 1)])


func _cost(s: Dictionary, pid: String, lvl: int) -> int:
	var p := project_def(pid)
	if p.is_empty() or lvl < 1 or lvl > int(p.max_level):
		return 0
	return maxi(1, int(p.cost_by_level[lvl]) * _scale(s) / 1000)


## Costo del prossimo traguardo: il progetto approvato, altrimenti il prossimo livello più economico.
func _next_cost(s: Dictionary) -> int:
	var t := str(s.get("target", ""))
	if not t.is_empty():
		return _cost(s, t, int(s.projects.get(t, 0)) + 1)
	var best := 0
	var last := 0
	for p in rules.get("projects", []):
		var lv := int(s.projects.get(str(p.id), 0))
		last = maxi(last, _cost(s, str(p.id), int(p.max_level)))
		if lv < int(p.max_level):
			var c := _cost(s, str(p.id), lv + 1)
			best = c if best == 0 else mini(best, c)
	return best if best > 0 else last


## Tetto giornaliero di versamento per socio = 2 x costo del prossimo traguardo / n (dati: daily_cap_mult_milli).
func _daily_cap(s: Dictionary) -> int:
	var dep: Dictionary = rules["deposit"]
	return maxi(1, int(dep["daily_cap_mult_milli"]) * _next_cost(s) / 1000 / maxi(1, _n_active(s)))


func _allow_now(s: Dictionary, m: Dictionary, day: int) -> int:
	var daily := _daily_cap(s)
	var days := maxi(0, day - int(m.allow_day))
	var full := daily * int(rules["deposit"]["drawer_days"])
	return mini(full, int(m.allow) + daily * days)


func _att_now(m: Dictionary, day: int) -> int:
	var br: Dictionary = rules["boss"]
	var per_day := int(br["attempts_per_day"])
	var days := maxi(0, day - int(m.att_day))
	return mini(per_day * int(br["drawer_days"]), int(m.att) + per_day * days)


## Nuova settimana -> nuovo Boss della settimana (rotazione dai dati, vita scalata per i soci di inizio settimana).
func _advance(s: Dictionary, ts: int) -> void:
	var br: Dictionary = rules["boss"]
	var w := int(ts / maxi(1, int(br["week_s"])))
	var b: Dictionary = s.get("boss", {})
	if not b.is_empty() and int(b.week) == w:
		return
	var bosses: Array = br.get("bosses", [])
	var bid := str(bosses[w % bosses.size()].id) if not bosses.is_empty() else ""
	var hp := maxi(1, int(br["hp_points_base"]) * _scale(s) / 1000)
	var cap := maxi(1, int(br["member_week_cap_mult_milli"]) * hp / 1000 / maxi(1, _n_active(s)))
	s["boss"] = {"week": w, "id": bid, "hp": hp, "dmg": 0, "cap": cap, "done": false, "by_member": {}}
	if not b.is_empty():
		_log(s, ts, "boss_new", "", bid, "")


## Soci cambiati durante la settimana: la vita del boss può solo CRESCERE (uscire o espellere non lo indebolisce:
## nessun «trucco» per finirlo prima), il tetto per socio si ricalcola sui soci attivi.
func _rescale_boss(s: Dictionary) -> void:
	var b: Dictionary = s.get("boss", {})
	if b.is_empty() or bool(b.done):
		return
	var br: Dictionary = rules["boss"]
	b["hp"] = maxi(int(b.hp), maxi(1, int(br["hp_points_base"]) * _scale(s) / 1000))
	b["cap"] = maxi(1, int(br["member_week_cap_mult_milli"]) * int(b.hp) / 1000 / maxi(1, _n_active(s)))


func _tally(s: Dictionary) -> Array:
	var yes := 0
	var no := 0
	var pr: Dictionary = s.proposal
	for u in pr.get("votes", {}):
		if not s.members.has(u) or not bool(s.members[u].active):
			continue
		if bool(pr.votes[u]):
			yes += 1
		else:
			no += 1
	return [yes, no]


func _majority(s: Dictionary) -> int:
	return int(_n_active(s) / 2) + 1


func _resolve_votes(s: Dictionary, ts: int) -> void:
	var pr: Dictionary = s.get("proposal", {})
	if pr.is_empty():
		return
	var t := _tally(s)
	if t[0] >= _majority(s):
		_approve(s, ts)
	elif t[1] >= _majority(s):
		_log(s, ts, "rejected", "", str(pr.project), "")
		s["proposal"] = {}


func _approve(s: Dictionary, ts: int) -> void:
	var pid := str(s.proposal.project)
	s["proposal"] = {}
	s["target"] = pid
	_log(s, ts, "approved", "", pid, "")
	_build(s, ts)


## Il progetto approvato sale di UN livello appena il fondo basta (i punti spesi non tornano a nessuno).
func _build(s: Dictionary, ts: int) -> void:
	var pid := str(s.get("target", ""))
	if pid.is_empty():
		return
	var lv := int(s.projects.get(pid, 0))
	var cost := _cost(s, pid, lv + 1)
	if cost <= 0:
		s["target"] = ""
		return
	if int(s.fund.points) < cost:
		return
	s.fund["points"] = int(s.fund.points) - cost
	s.fund["spent"] = int(s.fund.spent) + cost
	s.projects[pid] = lv + 1
	s["target"] = ""
	_log(s, ts, "level", "", pid, str(lv + 1))


func _log(s: Dictionary, ts: int, kind: String, uid: String, a: String, b: String) -> void:
	var lg: Array = s.log
	lg.append([int(s.get("gseq", 0)) + 1, ts, kind, uid, a, b])
	var mx := int(rules["log_max"])
	while lg.size() > mx:
		lg.pop_front()


# ------------------------------------------------------------------ serializzazione e hash

## Copia JSON-pronta: solo interi piccoli, stringhe, bool; i contatori grandi come stringhe (R-SAV-7).
func to_dict() -> Dictionary:
	var d: Dictionary = state.duplicate(true)
	if d.is_empty():
		return d
	for k in BIG_FUND:
		d.fund[k] = str(int(d.fund.get(k, 0)))
	for it in d.fund.by_item:
		d.fund.by_item[it] = str(int(d.fund.by_item[it]))
	for u in d.members:
		for k in BIG_MEMBER:
			d.members[u][k] = str(int(d.members[u].get(k, 0)))
	if not (d.boss as Dictionary).is_empty():
		for k in BIG_BOSS:
			d.boss[k] = str(int(d.boss.get(k, 0)))
		for u in d.boss.by_member:
			d.boss.by_member[u] = str(int(d.boss.by_member[u]))
	return d


## Ricostruisce lo stato da un dizionario JSON (anche letto da rete o da file). Ritorna "" o un errore.
func from_dict(d: Dictionary) -> String:
	if int(d.get("schema", -1)) != SCHEMA:
		return "schema"
	for k in ["id", "name", "gseq", "created_ts", "trophies", "members", "fund", "projects", "proposal", "target", "boss", "log"]:
		if not d.has(k):
			return "missing:" + k
	var s := {"schema": SCHEMA, "id": str(d.id), "name": str(d.name), "gseq": _i(d.gseq), "created_ts": _i(d.created_ts),
		"trophies": _i(d.trophies), "target": str(d.target), "members": {}, "projects": {}, "proposal": {}, "boss": {}, "log": []}
	var f: Dictionary = d.fund
	s["fund"] = {"points": _i(f.get("points")), "spent": _i(f.get("spent")), "rewards": _i(f.get("rewards")), "by_item": {}}
	for it in f.get("by_item", {}):
		s.fund.by_item[str(it)] = _i(f.by_item[it])
	for u in d.members:
		var m: Dictionary = d.members[u]
		s.members[str(u)] = {"name": str(m.get("name", "")), "role": str(m.get("role", ROLE_MEMBER)),
			"active": bool(m.get("active", false)), "joined_ts": _i(m.get("joined_ts")), "seq": _i(m.get("seq")),
			"dep_total": _i(m.get("dep_total")), "allow": _i(m.get("allow")), "allow_day": _i(m.get("allow_day")),
			"att": _i(m.get("att")), "att_day": _i(m.get("att_day"))}
	for p in d.projects:
		s.projects[str(p)] = _i(d.projects[p])
	var pr: Dictionary = d.proposal
	if not pr.is_empty():
		s["proposal"] = {"project": str(pr.get("project", "")), "by": str(pr.get("by", "")), "ts": _i(pr.get("ts")), "votes": {}}
		for u in pr.get("votes", {}):
			s.proposal.votes[str(u)] = bool(pr.votes[u])
	var b: Dictionary = d.boss
	if not b.is_empty():
		s["boss"] = {"week": _i(b.get("week")), "id": str(b["id"]), "hp": _i(b.get("hp")), "dmg": _i(b.get("dmg")),
			"cap": _i(b.get("cap")), "done": bool(b.get("done", false)), "by_member": {}}
		for u in b.get("by_member", {}):
			s.boss.by_member[str(u)] = _i(b.by_member[u])
	for e in d.log:
		if e is Array and e.size() == 6:
			s.log.append([_i(e[0]), _i(e[1]), str(e[2]), str(e[3]), str(e[4]), str(e[5])])
	state = s
	return ""


static func _i(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String:
		return (v as String).to_int()
	return 0


## Impronta dello stato (MD5 del JSON con chiavi ordinate della forma serializzata): uguale su ogni macchina.
func state_hash() -> String:
	return JSON.stringify(to_dict(), "", true).md5_text()
