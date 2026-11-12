class_name ManualFacts
extends RefCounted
## Numeri del Manuale: ogni pagina ha 0..n righe «I numeri» (chiavi UI_MAN2_<PAGINA>_F_<n>) i cui segnaposto sono riempiti
## QUI dai dati (constants.json, tabelle, regole) e da Formulas: mai a mano, quindi mai fuori sincronia con il gioco.
## Funzioni pure. `params(page, data)` restituisce un Dictionary per riga, nell'ordine F_1, F_2, ...


static func _n(x: float, decimals: int = 1) -> String:
	return NumberFormat.decimal(x, decimals, Loc.locale())


static func _i(x: Variant) -> String:
	return str(int(x))


static func _pct(frac: float, decimals: int = 1) -> String:
	return _n(frac * 100.0, decimals)


## Elenco di numeri come «1, 5, 10» (interi se tali).
static func _list(values: Array, decimals: int = 0) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append(_n(float(v), decimals))
	return ", ".join(parts)


static func _sorted_int_keys(d: Dictionary) -> Array:
	var ks: Array = []
	for k in d.keys():
		ks.append(int(k))
	ks.sort()
	return ks


static func _rarity_name(id: String) -> String:
	return str(TranslationServer.translate("UI_RARITY_" + id.to_upper()))


static func _row(table: Array, id: String) -> Dictionary:
	for r in table:
		if r is Dictionary and str(r.get("id", "")) == id:
			return r
	return {}


static func params(page: String, data: Object) -> Array[Dictionary]:
	var k: Dictionary = data.constants
	var out: Array[Dictionary] = []
	match page:
		"start", "settings":
			var o: Dictionary = k.offline
			out.append({"base": _i(o.cap_base_h), "max": _i(o.cap_max_h), "eff": _i(o.efficiency_pct)})
			if page == "settings":      # revisione finale B: le scale di testo, di interfaccia e i limiti di fotogrammi vengono dal codice delle Impostazioni
				var scales: Array = []
				for t in Accessibility.TEXT_SCALES:
					scales.append(float(t) * 100.0)
				var caps: PackedStringArray = PackedStringArray()
				for c in Settings.FPS_CAPS:
					caps.append(str(c) if c > 0 else str(TranslationServer.translate("UI_I10_SCR_FPS_UNLIMITED")))
				var ui_range: Array = Settings.RANGES["ui_scale"]
				out.append({"scales": _list(scales), "umin": _pct(float(ui_range[0]), 0), "umax": _pct(float(ui_range[1]), 0), "caps": ", ".join(caps)})
		"quests":
			var cr: Dictionary = data.rules("contract_rules")
			var rw: Dictionary = cr.get("rewards", {})
			out.append({"daily": _i(cr.get("daily_slots", 0)), "weekly": _i(cr.get("weekly_slots", 0)),
				"rerolls": _i(cr.get("free_rerolls_daily", 0)), "days": _i(cr.get("rollover_days", 0))})
			out.append({"tokd": _i(rw.get("daily", {}).get("commission_token", 0)), "keyp": _pct(float(rw.get("daily", {}).get("key_chance", 0.0)), 0),
				"tokw": _i(rw.get("weekly", {}).get("commission_token", 0))})
			out.append({"chapters": _i(data.table("chapters").size())})
		"skills":
			out.append({"cap": _i(k.level_cap), "base": _n(float(k.xp.base), 0), "growth": _n(float(k.xp.growth), 2),
				"xp50": NumberFormat.fmt(Formulas.xp_to_next(50))})
			out.append({"mcap": _i(k.mastery.cap), "levels": _list(_sorted_int_keys(k.mastery.milestones)), "save": _n(float(k.mastery.mastered_save_pct), 0)})
			out.append({"xpcap": _n(float(k.stars.xp_cap_pct), 0), "hcap": _n(float(k.stars.haste_cap_pct), 0),
				"xp5": _n(Formulas.star_xp_pct(5), 1), "h5": _n(Formulas.star_haste_pct(5), 1)})
		"queue":
			out.append({"max": _i(k.queue.max_slots), "base": _i(k.queue.base_slots)})
			out.append({"n": _i((k.queue.modes as Array).size())})
		"push":
			var tp: Dictionary = k.get("time_push", {})
			var on_pct := float(tp.get("regen_online_pct", 0.0))
			var off_pct := float(tp.get("regen_offline_pct", 0.0))
			var day_s := Formulas.push_regen(4.0 * 3600.0, on_pct) + Formulas.push_regen(12.0 * 3600.0, off_pct)
			out.append({"click": _n(float(tp.get("click_s", 0.0)), 1), "cap": _n(float(tp.get("reserve_cap_s", 0.0)) / 60.0, 0),
				"on": _n(on_pct, 0), "off": _n(off_pct, 1)})
			out.append({"min": _n(day_s / 60.0, 0), "gift": _i(tp.get("unlock_gift_s", 0))})
			out.append({"cps": _i(tp.get("max_cps", 0))})
		"farm":
			var plots: Array = data.table("farming_plots")
			var g := _row(plots, "garden")
			var orc := _row(plots, "orchard")
			out.append({"gb": _i(g.get("base_plots", 0)), "gm": _i(g.get("max_plots", 0)),
				"ob": _i(orc.get("base_plots", 0)), "om": _i(orc.get("max_plots", 0))})
			out.append({"pet": _i(k.farming.pet_one_in), "stars": _i(k.farming.auto_stars)})
		"alchemy":
			out.append({"n": _i((k.consumables.potion_slots as Array).size()), "feast": _i(k.consumables.feast_slots)})
		"apprentices":
			var acad: Dictionary = _row(data.table("estate_buildings"), "academy")
			var sbl: Dictionary = acad.get("effect", {}).get("slots_by_level", {})
			var lv := _sorted_int_keys(sbl)
			var slot_vals: Array = []
			for l in lv:
				slot_vals.append(int(sbl[str(l)]))
			var pd: Dictionary = k.get("apprentice_tuning", {})
			out.append({"slots": _list(slot_vals), "lv": _list(lv), "max": _i(pd.max_slots)})
			out.append({"eb": _pct(float(pd.eff_base), 0), "el": _pct(float(pd.eff_per_level), 0), "ec": _pct(float(pd.eff_cap), 0)})
		"combat":
			var c: Dictionary = k.combat
			out.append({"crit": _pct(float(c.crit_base), 0), "critd": _pct(float(c.crit_dmg_base), 0), "ccap": _pct(float(c.crit_cap), 0),
				"resp": _n(float(c.respawn_s), 1)})
			out.append({"adv": _n(float(c.triangle.advantage), 2), "dis": _n(float(c.triangle.disadvantage), 2),
				"ab": _i(c.hero.attr_base), "ap": _i(c.hero.attr_points_per_level)})
		"classes":
			out.append({"classes": _i(data.table("classes").size()), "abilities": _i(data.table("abilities").size()),
				"talents": _i(data.table("talents").size())})
		"bounty":
			var b: Dictionary = data.rules("bounty_board")
			var wv: Dictionary = b.get("wanted_variant", {})
			var cb: Dictionary = b.get("completion_bonus", {})
			out.append({"offers": _i(b.get("offers", 0)), "free": _i(b.get("free_rerolls_per_day", 0)), "cost": _i(b.get("reroll_cost_gold_per_tier", 0))})
			out.append({"wc": _pct(float(wv.get("chance_per_kill", 0.0)), 0), "whp": _n(float(wv.get("hp_mult", 1.0)), 1),
				"wd": _n(float(wv.get("dmg_mult", 1.0)), 1), "cc": _pct(float(cb.get("crate_bounty_chance", 0.0)), 0)})
		"raids":
			var raids: Array = data.table("raids")
			var r0: Dictionary = raids[0] if raids.size() > 0 else {}
			out.append({"n": _i(raids.size()), "size": _i(r0.get("party", {}).get("size", 0)), "cd": _i(r0.get("cooldown_h", 0))})
		"worldboss":
			var wbs: Array = data.table("world_bosses")
			var w0: Dictionary = wbs[0] if wbs.size() > 0 else {}
			var tiers: Array = []
			for t in w0.get("contribution_tiers", []):
				tiers.append(float(t.damage_pct))
			out.append({"every": _i(w0.get("spawn_every_h", 0)), "win": _i(w0.get("window_min", 0)), "n": _i(tiers.size()), "tiers": _list(tiers)})
		"rift":
			var rf: Dictionary = data.rules("rift")
			var cc: Dictionary = rf.get("crate_chance", {})
			var sh: Dictionary = rf.get("shards", {})
			out.append({"mult": _n(float(rf.get("stat_mult_per_floor", 1.0)), 2), "mpf": _i(rf.get("monsters_per_floor", 0)), "g": _i(rf.get("guardian_every", 0))})
			out.append({"base": _i(sh.get("base", 0)), "per": _i(sh.get("per_floors", 0)), "cb": _pct(float(cc.get("base", 0.0)), 0),
				"cp": _pct(float(cc.get("per_floor", 0.0)), 1), "cm": _pct(float(cc.get("max", 0.0)), 0)})
		"crates":
			var cru: Dictionary = data.rules("crate_rules")
			out.append({"dur": _n(float(cru.reel.duration_s), 1), "multi": _list(cru.reel.multi_open), "ann": _pct(float(cru.annalist.chance), 0)})
		"bank":
			out.append({"gold": NumberFormat.fmt(float(k.new_game_gift.gold))})
			out.append({"tax": _pct(float(k.market.sell_tax), 0), "skintax": _pct(float(data.rules("crate_rules").get("market", {}).get("sell_tax", 0.0)), 0)})
			var shop: Dictionary = data.get_def("shop", "bank_slot")        # resoconto 114: capacità e fonti di spazi, tutto dai dati
			var qslots := 0
			for qd in data.table("quests"):
				qslots += int(qd.get("rewards", {}).get("bank_slots", 0))
			var vault := 0.0
			var vname := ""
			for nd in data.table("constellations"):
				if str(nd.get("modifier_per_level", {}).get("key", "")) == "bank_slots":
					vault += float(nd.modifier_per_level.value) * float(nd.get("max_level", 0))
					vname = Loc.t(nd.get("name", {}))
			var rname := ""
			for rd in data.items_by_category("relic"):
				for rm in (rd.get("relic", {}) as Dictionary).get("modifiers", []):
					if str(rm.get("key", "")) == "bank_slots":
						rname = Loc.t(rd.get("name", {}))
			out.append({"base": _i(shop.get("base_slots", 0)), "max": _i(shop.get("max_purchases", 0)), "quests": _i(qslots),
				"vault": _n(vault, 0), "vname": vname, "rname": rname})
			var sp: Dictionary = k.bank.get("space", {})                    # F15: l'Armeria (equipaggiamento e attrezzi fuori dallo Spazio)
			out.append({"gearcap": _i(sp.get("gear_cap", 0)), "gearwarn": _i(sp.get("gear_warn_pct", 0))})
		"vault_tools":
			var cv: Dictionary = data.rules("crate_rules")
			var tu: Dictionary = cv.get("tradeup", {})
			var rin: PackedStringArray = []
			for rid in tu.get("rarities_in", []):
				rin.append(_rarity_name(str(rid)))
			out.append({"gi": _i(cv.get("golden_contract", {}).get("inputs", 0)), "tu": _i(tu.get("inputs", 0)), "rin": ", ".join(rin)})
			var pol: Dictionary = cv.get("refinery", {}).get("polish", {})
			out.append({"step": _pct(float(pol.get("float_step", 0.0)), 0), "cm": _n(float(pol.get("cost_mult", 0.0)), 1)})
			var sv: Array = []
			for v in cv.get("dismantle_shards", {}).values():
				sv.append(float(v))
			var pv: Array = []
			for v2 in cv.get("collectors_challenge", {}).get("points", {}).values():
				pv.append(float(v2))
			out.append({"shards": " / ".join(_list(sv).split(", ")), "pts": " / ".join(_list(pv).split(", "))})
		"album":
			out.append({"coll": _i(data.table("collections").size()), "pets": _i(data.table("pets").size())})
		"market":
			var mr: Dictionary = data.rules("market_rules")
			out.append({"tax": _pct(float(mr.get("sell_tax", 0.0)), 0), "buy": _n(float(mr.get("buy_markup", 0.0)), 1),
				"equip": _n(float(mr.get("buy_markup_equipment", 0.0)), 1)})
			out.append({"half": _i(mr.get("demand", {}).get("half_life_h", 0)), "days": _i(mr.get("price_history_days", 0))})
		"orders":
			var orr: Dictionary = data.rules("orders_rules")
			var qr: Array = orr.get("qty_range", [0, 0])
			var rr: Array = orr.get("reward_mult_range", [0, 0])
			out.append({"slots": _i(orr.get("board_slots", 0)), "refresh": _i(orr.get("refresh_h", 0)), "deadline": _i(orr.get("deadline_h", 0)),
				"q1": _pct(float(qr[0]), 0), "q2": _pct(float(qr[1]), 0), "r1": _n(float(rr[0]), 1), "r2": _n(float(rr[1]), 1),
				"crate": _pct(float(orr.get("crate_chance", 0.0)), 0)})
		"factions":
			var fs: Array = data.table("factions")
			var ranks: Array = fs[0].get("ranks", []) if fs.size() > 0 else []
			var thr: Array = []
			for rk in ranks:
				thr.append(float(rk.rep))
			out.append({"n": _i(fs.size()), "ranks": _i(ranks.size()), "thr": ", ".join(PackedStringArray(_list(thr).split(", ")))})
		"estate":
			var er: Dictionary = data.rules("estate_rules")
			out.append({"base": _n(float(k.estate.cost_base), 0), "growth": _n(float(k.estate.cost_growth), 2),
				"c10": NumberFormat.fmt(Formulas.estate_cost_gold(10, 1))})
			out.append({"upl": _n(float(k.estate.units_per_level), 0), "ms": _list(er.get("milestones", [])),
				"mm": _n(float(er.get("milestone_mult", 1)), 0), "ex10": NumberFormat.fmt(Formulas.estate_units_per_hour(10))})
		"guild":
			out.append({"ach": _i(data.table("achievements").size()), "titles": _i(data.table("titles").size()), "pets": _i(data.table("pets").size())})
		"mercenaries":
			var mc: Dictionary = data.rules("mercenary_rules")
			var maxl: Array = []
			for rr2 in mc.get("rarities", []):
				maxl.append(int(rr2.max_level))
			out.append({"cand": _i(mc.get("recruit_board", {}).get("candidates", 0)), "refresh": _i(mc.get("recruit_board", {}).get("refresh_h", 0)),
				"reroll": NumberFormat.fmt(float(mc.get("recruit_board", {}).get("reroll_cost_gold", 0)))})
			out.append({"maxl": _list(maxl), "inj": _pct(float(mc.get("injury", {}).get("chance_on_fail", 0.0)), 0), "dur": _i(mc.get("injury", {}).get("duration_h", 0))})
		"expeditions":
			var ex: Dictionary = data.rules("expedition_rules")
			var pd2: Dictionary = k.get("expedition_tuning", {})
			out.append({"durs": _list(ex.get("durations_h", []), 1), "mults": _list(ex.get("duration_reward_mult", []), 2)})
			out.append({"k": _n(float(pd2.success_gain), 1), "off": _n(float(pd2.success_bias), 2), "lo": _pct(float(pd2.success_min), 0),
				"hi": _pct(float(pd2.success_max), 0), "fail": _i(ex.get("fail_reward_pct", 0))})
		"secrets":
			var sr: Dictionary = data.rules("social_rules").get("secrets", {})
			var spots: Array = data.table("secret_spots")
			var fr: Array = []
			for s in spots:
				fr.append(int(s.get("map_fragments_required", 0)))
			fr.sort()
			out.append({"min": _i(sr.get("explore_minutes", 0)), "runs": _i(sr.get("runs_per_reveal", 0)), "xp": _n(float(sr.get("xp_mult", 1.0)), 1),
				"bonus": _pct(float(sr.get("bonus_chance", 0.0)), 0), "spots": _i(spots.size()),
				"fmin": _i(fr[0] if fr.size() > 0 else 0), "fmax": _i(fr[fr.size() - 1] if fr.size() > 0 else 0)})
		"compendium":
			var pr: Dictionary = data.rules("social_rules").get("pets", {})
			out.append({"d1": _i(pr.get("duplicate_stardust", 0)), "d2": _i(pr.get("crate_duplicate_stardust", 0)), "pets": _i(data.table("pets").size())})
		"prestige":
			out.append({"rite": _i(k.prestige.rite_level), "cap": _i(k.level_cap)})
			out.append({"xpcap": _n(float(k.stars.xp_cap_pct), 0), "xpdecay": _n(float(k.stars.xp_decay), 2),
				"x1": _n(Formulas.star_xp_pct(1), 1), "x5": _n(Formulas.star_xp_pct(5), 1), "x10": _n(Formulas.star_xp_pct(10), 1),
				"h1": _n(Formulas.star_haste_pct(1), 1), "h5": _n(Formulas.star_haste_pct(5), 1), "h10": _n(Formulas.star_haste_pct(10), 1)})
			out.append({"d1": _i(Formulas.stardust_for_star(1)), "d10": _i(Formulas.stardust_for_star(10)),
				"e1": _n(Formulas.echo_multiplier(10, 100), 1), "e2": _n(Formulas.echo_multiplier(70, 100), 1), "e3": _n(Formulas.echo_multiplier(95, 100), 1)})
		"constellations":
			var names := {}
			for cn in data.table("constellations"):
				names[str(cn.get("constellation", ""))] = true
			out.append({"c": _i(names.size()), "n": _i(data.table("constellations").size())})
			out.append({"days": _n(float(k.prestige.respec_free_interval_s) / 86400.0, 0), "cost": _i(k.prestige.respec_cost_stardust)})
		"refound":
			var estk: Dictionary = k.estate
			var adv: Dictionary = k.prestige.advisor
			var mu := float(estk.prestige_min_units)
			out.append({"minu": NumberFormat.fmt(mu), "coef": _n(float(estk.soci_coeff), 0), "div": NumberFormat.fmt(float(estk.soci_divisor)),
				"p1": _i(Formulas.soci_total(mu)), "p2": _i(Formulas.soci_total(200000.0))})
			out.append({"bonus": _n(float(estk.socio_bonus_pct), 0), "mn": _i(adv.refound_min_new_partners)})
		"eras":
			var ek: Dictionary = k.eras
			var trials: Array = data.table("trials")
			var t0: Dictionary = trials[0] if trials.size() > 0 else {}
			out.append({"mm": _n(float(ek.monster_mult), 2), "ra": _pct(float(ek.reward_add), 0),
				"m5": _n(Formulas.era_monster_mult(5), 2), "r5": _n(Formulas.era_reward_mult(5), 1)})
			out.append({"rm": _n((float(ek.rank_stat_mult) - 1.0) * 100.0, 0), "rc": _i(ek.rank_cap_per_era)})
			out.append({"t": _i(trials.size()), "tiers": _i((t0.get("tiers", []) as Array).size())})
		"events":
			var evr: Dictionary = data.rules("event_rules").get("seasonal", {})
			var prices: Array = []
			for pv2 in evr.get("shop_prices", {}).values():
				prices.append(float(pv2))
			out.append({"n": _i(data.table("events").size()), "drop": _i(evr.get("drop_every_s", 0)), "echo": _i(evr.get("echo_every_s", 0))})
			out.append({"cost": _i(evr.get("crate_cost", 0)), "prices": _list(prices), "cap": _i(evr.get("max_drops_per_occurrence", 0))})
		"modes":
			var mrl: Dictionary = data.rules("mode_rules")
			var md: Dictionary = mrl.get("modes", {})
			out.append({"n": _i(md.size()), "allow": _i(md.get("autarchic", {}).get("market_buy", {}).get("allow_items", []).size()),
				"skills": _i(md.get("extreme", {}).get("permadeath", {}).get("reset_skills", []).size())})
		"coop":
			var cnr: Dictionary = data.rules("coop_net_rules")       # esiste solo quando c'è il coop in rete
			out.append({"port": _i(cnr.default_port) if cnr.has("default_port") else str(TranslationServer.translate("UI_MAN2_COOP_PORT_TBD"))})
	return out
