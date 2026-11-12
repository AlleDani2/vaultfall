extends GutTest
## Regola 2 (CLAUDE.md): il codice recente legge i numeri di bilanciamento dai dati, SENZA valori di ripiego scritti nel codice.
## Qui: (1) le chiavi lette direttamente esistono nei dati; (2) nei file controllati non restano letture `.get("chiave", numero)`
## su regole/costanti (i ripieghi neutri 0/1 sugli stati di gioco non contano: si guardano solo i ricevitori di regole).

const READS := {
	"contract_rules": ["free_rerolls_daily", "rollover_days", "weekly_keep_days", "day_s", "week_days", "key_tier_div", "key_tier_max"],
	"event_rules.seasonal": ["min_valid_unix", "clock_tolerance_s", "drop_every_s", "echo_every_s", "max_drops_per_occurrence", "max_drops_echo", "crate_cost"],
	"mercenary_rules.raid_roles": ["power_base", "power_growth", "power_party_size", "ratio_cap"],
	"constants.prestige": ["rite_level", "respec_cost_stardust", "respec_free_interval_s"],
	"constants.prestige.advisor": ["refound_min_new_partners", "refound_min_ratio"],
	"constants.eras": ["rank_min_era"],
	"constants.market": ["skin_sell_tax"],
	"market_rules": ["sell_tax", "buy_markup", "buy_markup_equipment", "gazette_interval_h", "price_history_days", "demand", "trend", "npc_stock"],
	"market_rules.demand": ["half_life_h", "elasticity_hours_of_production", "min_volume", "drop_volume_per_tier"],
	"market_rules.trend": ["theta", "sigma", "min", "max", "mean"],
	"market_rules.npc_stock": ["refresh_min"],
	"orders_rules": ["board_slots", "refresh_h", "lifetime_days", "reject_cooldown_min", "crate_chance"],
}

const CHECKED_FILES := [
	"res://src/systems/ContractSystem.gd", "res://src/systems/SeasonalEventSystem.gd", "res://src/systems/Hourglass.gd",
	"res://src/systems/EndgameCombat.gd", "res://src/coop/CoopSystem.gd", "res://src/systems/RunSystem.gd",
	"res://src/ui/screens/RunPanel.gd", "res://src/systems/MarketSystem.gd", "res://src/ui/screens/EventsScreen.gd",
]


func _table(path: String) -> Variant:
	var parts := path.split(".")
	var cur: Variant
	if parts[0] == "constants":
		cur = DataRegistry.constants
	else:
		cur = DataRegistry.rules(parts[0])
	for i in range(1, parts.size()):
		if not (cur is Dictionary) or not (cur as Dictionary).has(parts[i]):
			return null
		cur = cur[parts[i]]
	return cur


func test_le_chiavi_lette_senza_ripiego_esistono_nei_dati() -> void:
	for path in READS:
		var d: Variant = _table(path)
		assert_true(d is Dictionary, "tabella " + path)
		if d is Dictionary:
			for k in READS[path]:
				assert_true((d as Dictionary).has(k), "%s.%s mancante nei dati" % [path, k])


func test_ogni_gabbia_di_ripiego_numerico_sulle_regole_e_sparita() -> void:
	var rx := RegEx.create_from_string("(?:_rules\\(\\)|\\brules\\(\\)|\\bcfg|_cfg\\(\\)|\\b_k\\(\\)|\\brr|\\bak|_market_rules\\(\\)|_orders_rules\\(\\)|\\bdem|\\btr_rules)\\.get\\(\"[a-z_0-9]+\", *-?[0-9][0-9.]*\\)")
	for f in CHECKED_FILES:
		var txt := FileAccess.get_file_as_string(f)
		var m := rx.search(txt)
		assert_null(m, "%s: ripiego numerico su una regola: %s" % [f, m.get_string() if m != null else ""])

