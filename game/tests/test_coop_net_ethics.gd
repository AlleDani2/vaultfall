extends GutTest
## COOP-2: controllo etico statico di src/coop/net (CLAUDE.md regola 5, equivalente a quello di COOP-1).
## Il codice di rete PUÒ usare ENet (è il suo mestiere), ma:
##   - l'unica uscita dal Deposito personale è il versamento (`deposit()` -> bank.remove), l'unico ingresso il rimborso
##     dello stesso versamento rifiutato (`_refund()` -> bank.add); nessun'altra scrittura su Deposito/valute/istanze;
##   - nessun tipo di messaggio o comando per scambiare, regalare, prelevare, prestare o scommettere;
##   - il fondo cala solo per costruire progetti (bonus uguali per tutti), mai verso un giocatore;
##   - versabili solo oro e materie prime di base; niente denaro reale, niente Casse/chiavi/finiture/reliquie.

const DIR := "res://src/coop/net"
const FORBIDDEN_WORDS: PackedStringArray = ["gift", "trade", "withdraw", "lend", "loan", "steal", "bet", "wager",
	"gamble", "coinflip", "jackpot", "upgrader", "purchase", "microtransaction", "real_money"]


func _sources() -> Dictionary:
	var out := {}
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out[f] = _code_only(FileAccess.get_file_as_string(DIR.path_join(f)))
	return out


## Toglie commenti e stringhe di documentazione: si controlla solo il codice eseguibile.
func _code_only(text: String) -> String:
	var lines := PackedStringArray()
	for l in text.split("\n"):
		var s := l
		var i := s.find("#")
		if i >= 0:
			s = s.substr(0, i)
		lines.append(s)
	return "\n".join(lines)


func test_unica_uscita_e_unico_ingresso_del_deposito() -> void:
	var src := _sources()
	assert_false(src.is_empty())
	var removes := 0
	var adds := 0
	for f in src:
		var code: String = src[f]
		for bad in ["add_gold(", "spend_gold(", "add_currency(", "spend_currency(", "add_instance(", "remove_instance(",
				"discard(", "set_def_locked(", ".sell("]:
			assert_false(code.contains(bad), "%s: scrittura vietata sul Deposito/valute (%s)" % [f, bad])
		removes += code.count("bank.remove(")
		adds += code.count("bank.add(")
		if code.contains("bank.remove("):
			assert_eq(f, "CoopNetService.gd")
			var fn := code.substr(code.find("func deposit("), 1400)
			assert_true(fn.contains("bank.remove("), "bank.remove solo dentro deposit()")
		if code.contains("bank.add("):
			var fn2 := code.substr(code.find("func _refund("), 400)
			assert_true(fn2.contains("bank.add("), "bank.add solo dentro _refund() (restituzione del proprio versamento)")
	assert_eq(removes, 1, "una sola uscita dal Deposito: il versamento")
	assert_eq(adds, 1, "un solo ingresso: il rimborso del versamento rifiutato")


func test_nessun_messaggio_di_scambio_o_azzardo() -> void:
	for t in CoopProtocol.CLIENT_TYPES + CoopProtocol.HOST_TYPES + CoopProtocol.CMD_OPS:
		for w in FORBIDDEN_WORDS:
			assert_false(str(t).contains(w), "tipo/comando vietato: %s" % t)
	var src := _sources()
	for f in src:
		var code: String = (src[f] as String).to_lower()
		for w in FORBIDDEN_WORDS:
			assert_false(code.contains("\"%s\"" % w) or code.contains("func %s" % w) or code.contains("_op_%s" % w),
				"%s: parola vietata nel codice (%s)" % [f, w])


func test_il_fondo_scende_solo_per_i_progetti() -> void:
	var code: String = _sources()["CoopGuild.gd"]
	var decreases := RegEx.create_from_string("fund\\[\"points\"\\] = int\\(s\\.fund\\.points\\) - ").search_all(code).size()
	assert_eq(decreases, 1, "un solo punto in cui il fondo cala")
	var fn := code.substr(code.find("func _build("), 900)
	assert_true(fn.contains("int(s.fund.points) - cost"), "...ed è la costruzione di un progetto")


func test_versabili_solo_materie_prime_e_oro() -> void:
	var r := DataRegistry.rules("coop_net_rules")
	for id in r.deposit.items:
		var it: Dictionary = DataRegistry.item(str(id))
		assert_eq(str(it.get("category", "")), "material", "solo materiali: " + str(id))
		assert_false(str(id).begins_with("crate_") or str(id).begins_with("key_") or str(id).begins_with("relic_")
			or str(id).begins_with("skin_"), "niente Casse/chiavi/reliquie/finiture: " + str(id))
	var g := CoopGuild.make(r, CoopGuild.item_values_from(DataRegistry, r))
	for k in g.values:
		assert_true(k == "gold" or (r.deposit.items as Array).has(k))
	# le ricompense della gilda sono modificatori (bonus uguali), mai oggetti
	for p in r.projects:
		for m in p.mods:
			assert_true(str(m.key).split(":")[0] in ["skill_xp_pct", "skill_haste_pct", "estate_prod_pct"],
				"bonus su chiavi sicure (mai oro del Mercato, Casse, limite offline): " + str(m.key))
