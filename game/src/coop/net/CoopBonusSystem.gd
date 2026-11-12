class_name CoopBonusSystem
extends GameSystem
## Sezione `coop_net` del salvataggio PERSONALE (COOP-2): proprietario unico (docs/audit_2026-10-22/17_CONTRATTI).
## Contiene la copia in SOLA LETTURA dei livelli dei progetti di gilda, la cassetta in uscita dei comandi non ancora
## confermati dall'host, l'identificativo del giocatore e l'ultimo host. Applica i bonus di gilda ai modificatori
## (fonte `guild:<progetto>`, regola add, docs/14) in `from_state`, cioè PRIMA dell'offline del caricamento: i bonus
## valgono anche da soli, senza rete e senza il servizio CoopNetService. Nessun tick (puramente a eventi).
## I numeri (valori dei bonus per livello, tetto) arrivano da data/coop_net_rules.json.

const SOURCE_PREFIX := "guild:"


func _init() -> void:
	id = "coop_net"
	state_key = "coop_net"


## La voce «Amici» del menù (token `feature:coop`) la sblocca COOP-1 (CoopSystem, coop_rules.unlock): qui nessuno sblocco.


func default_state() -> Variant:
	return {"uid": "", "nick": "", "guild_id": "", "guild_name": "", "levels": {}, "outbox": [], "next_seq": 1,
		"boss_att_no": 0}


func from_state(section: Variant) -> void:
	state = section
	# Pulizia (privacy, docs/24 §7.1 p.3): prima l'IP dell'ultimo host stava qui. Si sposta nelle impostazioni locali
	# (se non ce n'e' gia' uno) e si toglie dal salvataggio, cosi' non finisce piu' in uno ZIP di segnalazione.
	if state is Dictionary and state.has("last_host"):
		var old: Variant = state["last_host"]
		state.erase("last_host")
		if old is Dictionary and old.get("ip") is String and not (old.get("ip") as String).is_empty() \
				and (Settings.get_value("coop_last_host") as Dictionary).is_empty():
			Settings.set_value("coop_last_host", {"ip": old.ip, "port": int(old.get("port", 0))})
	var d: Dictionary = default_state()
	for k in d:
		if not state.has(k) or typeof(state[k]) != typeof(d[k]):
			state[k] = d[k]
	apply_bonus()


func has_tick() -> bool:
	return false


func int_paths() -> PackedStringArray:
	return PackedStringArray(["next_seq", "boss_att_no", "levels.*"])


func _rules() -> Dictionary:
	return ctx.data.rules("coop_net_rules")


## Bonus di gilda attivi (copia locale): fonte -> blocco di modificatori.
func bonus_by_source() -> Dictionary:
	if state == null or str(state.guild_id).is_empty():
		return {}
	return CoopGuild.mods_from_levels(state.levels, _rules())


## Riallinea i modificatori `guild:*` alla copia salvata.
func apply_bonus() -> void:
	if ctx == null or ctx.modifiers == null:
		return
	ctx.modifiers.clear_prefix(SOURCE_PREFIX)
	var by_src := bonus_by_source()
	for src in by_src:
		ctx.modifiers.set_source(src, by_src[src])


## Aggiornamento dall'host (o dalla copia della gilda): nuovi livelli dei progetti, uguali per tutti i soci.
func set_membership(guild_id: String, guild_name: String, levels: Dictionary) -> void:
	state["guild_id"] = guild_id
	state["guild_name"] = guild_name
	var clean := {}
	for p in levels:
		clean[str(p)] = int(levels[p])
	state["levels"] = clean
	apply_bonus()


## Fuori dalla gilda (uscita confermata o espulsione): niente più bonus di gilda.
func clear_membership() -> void:
	state["guild_id"] = ""
	state["guild_name"] = ""
	state["levels"] = {}
	apply_bonus()
