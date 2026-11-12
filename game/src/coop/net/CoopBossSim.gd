class_name CoopBossSim
extends RefCounted
## Tentativo contro il «Boss della settimana» (COOP-2): un combattimento LOCALE, breve e deterministico, dell'Eroe del
## giocatore contro un boss del SUO livello (Formulas.monster_stats(livello, "boss"), le stesse curve dei mostri).
## Il risultato è un numero intero di punti = points_per_kill x (danno inflitto / vita del boss), con un tetto per
## tentativo: così il contributo dipende dalla build e dall'equipaggiamento, non dal livello assoluto, e due amici a
## livelli diversi contribuiscono in modo paragonabile. L'host somma solo i numeri (con i tetti per socio).
## Puro: niente nodi, niente tempo reale; caso da un RandomNumberGenerator con seme (settimana, giocatore, tentativo).
## Il combattimento personale NON viene toccato: si leggono solo le statistiche già calcolate dell'Eroe.


## hero: Dictionary di CombatSystem.hero_stats() (hp, acc, eva, arm, min_hit, max_hit, interval, crit, critd).
## Ritorna {"pts": int, "dmg": float, "boss_hp": float, "secs": float, "survived": bool, "hits": int}.
static func attempt(hero: Dictionary, hero_level: int, boss_rules: Dictionary, seed_value: int) -> Dictionary:
	var lvl := maxi(1, hero_level)
	var mon := Formulas.monster_stats(lvl, str(boss_rules["monster_type"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dur := float(boss_rules["attempt_s"])
	var boss_hp := maxf(1.0, float(mon.hp))
	var h_hp := maxf(1.0, float(hero["hp"]))
	var interval := maxf(0.2, float(hero["interval"]))
	var max_hit := maxf(0.0, float(hero["max_hit"]))
	var min_hit := clampf(float(hero["min_hit"]), 0.0, max_hit)
	var crit := clampf(float(hero["crit"]), 0.0, 1.0)
	var critd := maxf(1.0, float(hero["critd"]))
	var hit_h := Formulas.hit_chance(float(hero["acc"]), float(mon.evasion))
	var dr_b := Formulas.damage_reduction(float(mon.armor), float(lvl))
	var hit_b := Formulas.hit_chance(float(mon.accuracy), float(hero["eva"]))
	var dr_h := Formulas.damage_reduction(float(hero["arm"]), float(lvl))
	var b_int := maxf(0.5, float(mon.attack_interval_s))
	var dmg := 0.0
	var t_h := interval
	var t_b := b_int
	var t := 0.0
	var hits := 0
	var alive := true
	# eventi in ordine di tempo (al massimo qualche centinaio): niente passi fissi, niente float accumulati a lungo
	while alive:
		var nt := minf(t_h, t_b)
		if nt > dur:
			break
		t = nt
		if t_h <= t_b:
			if rng.randf() < hit_h:
				var d := rng.randf_range(min_hit, max_hit)
				if rng.randf() < crit:
					d *= critd
				dmg += d * (1.0 - dr_b)
				hits += 1
			t_h += interval
		else:
			if rng.randf() < hit_b:
				h_hp -= rng.randf_range(float(mon.max_hit) * float(boss_rules["boss_min_hit_ratio"]), float(mon.max_hit)) * (1.0 - dr_h)
				if h_hp <= 0.0:
					alive = false
			t_b += b_int
	var per_kill := int(boss_rules["points_per_kill"])
	var pts := clampi(int(floor(float(per_kill) * minf(dmg, boss_hp * 100.0) / boss_hp)), 0,
		int(boss_rules["max_points_per_attempt"]))
	return {"pts": pts, "dmg": dmg, "boss_hp": boss_hp, "secs": t if not alive else dur, "survived": alive, "hits": hits}


## Seme riproducibile del tentativo: stessa settimana + stesso giocatore + stesso numero di tentativo = stesso esito
## (ripetere non «ritira i dadi»: ogni tentativo consuma un posto del cassetto).
static func seed_for(week: int, uid: String, attempt_no: int) -> int:
	return hash("%d|%s|%d" % [week, uid, attempt_no]) & 0x7fffffff
