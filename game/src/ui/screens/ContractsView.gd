class_name ContractsView
extends WorkshopView
## Scheda Contratti (docs/09 §9): Contratto di Conversione (10 finiture della stessa rarità e variante → 1 della rarità
## successiva) e Contratto Aureo (5 Mitiche → 1 Reliquia ★). Si mostra OGNI esito possibile con la sua probabilità e il
## float previsto PRIMA di firmare. Nessuna posta, nessuna scelta di rischio: si consumano ingressi, si ottiene un
## oggetto con un esito dichiarato (docs/24 R-LEG-3). L'esito è estratto da CrateSystem.contract_sign() prima di
## qualunque testo di rivelazione; dopo la firma c'è solo un breve «forgiato» di scintille (Fx), mai un'attesa.

const MAX_LIST := 80
const NORMAL_RARITIES: Array = ["rare", "epic", "legendary"]

var golden: bool = false
var rarity: String = "rare"
var annal: bool = false
var selection: Array = []
var last_result: Dictionary = {}
var _actions: CrateActions
var _result_title: Label


func _apply_params(params: Dictionary) -> void:
	golden = bool(params.get("golden", golden))
	if params.has("add"):
		var inst := crates.instance(str(params.add))
		if not inst.is_empty() and str(inst.kind) == "skin":
			golden = str(inst.rarity) == "mythic"
			rarity = "mythic" if golden else str(inst.rarity)
			annal = bool(inst.get("annalist", false))
			selection = [str(params.add)]


func signature() -> String:
	return "%d|%s|%s|%s|%s|%s|%d" % [bank_revision(), golden, rarity, annal, ",".join(PackedStringArray(selection)),
		str(last_result.get("uid", "")), 1 if crates.contract_unlocked(golden) else 0]


func _prune() -> void:
	var keep: Array = []
	for u in selection:
		if crates.consume_block(u).is_empty():
			keep.append(u)
	selection = keep


func _empty_card_here() -> void:
	var gos: Array = []
	var hall := ScreenRegistry.get_entry("vault_hall")
	if not hall.is_empty() and ScreenRegistry.is_available(hall, GameState.data.get("unlocks", [])):
		gos.append({"text": tr("UI_MENU_VAULT_HALL"), "primary": true, "target": {"screen": "vault_hall", "params": {}, "hint": ""}})
	VaultKit.empty_card(self, IconLib.icon("crates", "capsule_emblems"), tr("UI_VUX_CT_EMPTY_TITLE"), tr("UI_VUX_CT_EMPTY_WHAT"),
		PackedStringArray([tr("UI_VUX_CT_STEP_1"), tr("UI_VUX_CT_STEP_2")]), gos)


func candidates() -> Array:
	var rar := "mythic" if golden else rarity
	var out: Array = []
	for inst in _instances_of(["skin"]):
		if str(inst.rarity) != rar:
			continue
		if not golden and bool(inst.get("annalist", false)) != annal:
			continue
		if crates.consume_block(str(inst.uid)).is_empty():
			out.append(inst)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa := float(a.get("float", 0.0))
		var fb := float(b.get("float", 0.0))
		return fa > fb if fa != fb else str(a.uid) < str(b.uid))
	return out


func build() -> void:
	_prune()
	if not crates.tradeup_unlocked():
		_locked_note(CrateSystem.TOKEN_TRADEUP, "UI_CRATES_TAB_TRADE", "UI_VUX_CT_EMPTY_WHAT")
		return
	if _instances_of(["skin"]).is_empty():
		_empty_card_here()

	# --- tipo di contratto
	var modes := HFlowContainer.new()
	add_child(modes)
	var b1 := Button.new()
	b1.text = tr("UI_CRATES2_CT_MODE_TRADE")
	b1.toggle_mode = true
	b1.button_pressed = not golden
	b1.pressed.connect(_set_golden.bind(false))
	modes.add_child(b1)
	var b2 := Button.new()
	b2.text = tr("UI_CRATES2_CT_MODE_GOLDEN")
	b2.toggle_mode = true
	b2.button_pressed = golden
	b2.disabled = not crates.golden_unlocked()
	if b2.disabled:
		var hint2 := UnlockSystem.hint_for(CrateSystem.TOKEN_GOLDEN, DataRegistry)
		b2.tooltip_text = hint2 if not hint2.is_empty() else CrateUi.why("locked_feature")
	b2.pressed.connect(_set_golden.bind(true))
	modes.add_child(b2)
	_label(tr("UI_CRATES2_CT_GOLDEN_RULE" if golden else "UI_CRATES2_CT_TRADE_RULE"))

	# --- filtri
	var need := crates.contract_inputs(golden)
	if not golden:
		var f := HFlowContainer.new()
		add_child(f)
		var ob := _rarity_option(false, NORMAL_RARITIES, rarity)
		ob.item_selected.connect(func(i: int) -> void:
			rarity = str(ob.get_item_metadata(i))
			selection = []
			last_result = {}
			rebuild(true))
		f.add_child(ob)
		var vn := Button.new()
		vn.text = tr("UI_CRATES2_CT_VARIANT_NORMAL")
		vn.toggle_mode = true
		vn.button_pressed = not annal
		vn.pressed.connect(_set_annal.bind(false))
		f.add_child(vn)
		var va := Button.new()
		va.text = tr("UI_CRATES2_CT_VARIANT_ANNALIST")
		va.toggle_mode = true
		va.button_pressed = annal
		va.pressed.connect(_set_annal.bind(true))
		f.add_child(va)

	# --- scelta degli ingressi
	var row := HFlowContainer.new()
	add_child(row)
	var auto := Button.new()
	auto.text = Loc.tf("UI_CRATES2_CT_AUTO", {"n": need})
	auto.tooltip_text = tr("UI_CRATES2_CT_AUTO_TIP")
	auto.pressed.connect(auto_pick)
	row.add_child(auto)
	var clear := Button.new()
	clear.text = tr("UI_CRATES2_CT_CLEAR")
	clear.disabled = selection.is_empty()
	clear.pressed.connect(func() -> void:
		selection = []
		rebuild(true))
	row.add_child(clear)
	var cnt := Label.new()
	cnt.text = Loc.tf("UI_CRATES2_CT_SELECTED", {"n": selection.size(), "need": need})
	cnt.theme_type_variation = &"SectionLabel"
	add_child(cnt)

	var cands := candidates()
	if cands.is_empty():
		_label(tr("UI_CRATES2_CT_NO_CANDIDATES"), false)
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 180)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		for k in mini(cands.size(), MAX_LIST):
			var inst: Dictionary = cands[k]
			var uid := str(inst.uid)
			var cb := CheckBox.new()
			cb.text = CrateUi.inst_line(inst)
			cb.clip_text = true
			cb.tooltip_text = CrateUi.instance_text(inst)
			cb.button_pressed = selection.has(uid)
			cb.add_theme_color_override("font_color", CrateUi.rarity_color(str(inst.rarity)))
			cb.toggled.connect(_on_toggle.bind(uid))
			list.add_child(cb)
		if cands.size() > MAX_LIST:
			CrateUi.note(list, Loc.tf("UI_CRATES_MORE", {"n": cands.size() - MAX_LIST}))

	# --- anteprima di tutti gli esiti
	var pv := crates.contract_preview(selection, golden)
	if not bool(pv.ok):
		if selection.size() > 0 or not cands.is_empty():
			_label(Loc.tf("UI_CRATES2_CT_NEED", {"n": need}) if str(pv.reason) == "count" else CrateUi.why(str(pv.reason)))
	else:
		_build_preview(pv)
	_build_result()


func _build_preview(pv: Dictionary) -> void:
	_section(tr("UI_CRATES2_CT_OUTCOMES"))
	var rout := str(pv.rarity_out)
	_label(Loc.tf("UI_CRATES2_CT_OUT_RARITY", {"r": CrateUi.rarity_label(rout), "v": tr("UI_CRATES2_CT_VARIANT_ANNALIST") if bool(pv.annalist) else tr("UI_CRATES2_CT_VARIANT_NORMAL")}), false)
	_label(Loc.tf("UI_CRATES2_CT_FLOAT_RULE", {"m": CrateUi.num(float(pv.avg_norm), 3)}))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 140)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var total := 0.0
	for o in pv.outcomes:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var txt := "%s  %s" % [CrateUi.def_name(str(o.def_id)), CrateUi.pct(float(o.pct))]
		if float(o.float) >= 0.0:
			txt += "  ·  " + Loc.tf("UI_CRATES2_CT_PREDICTED", {"f": NumberFormat.decimal(float(o.float), 4, TranslationServer.get_locale().substr(0, 2)),
				"c": CrateUi.condition_name(str(o.condition))})
		l.text = txt
		l.add_theme_color_override("font_color", CrateUi.rarity_color(rout))
		list.add_child(l)
		total += float(o.pct)
	_label(Loc.tf("UI_CRATES2_CT_TOTAL", {"p": CrateUi.pct(total)}))
	if not pv.phases.is_empty():
		var parts := PackedStringArray()
		for p in pv.phases:
			parts.append("%s %s" % [_phase_name(str(p.id)), CrateUi.pct(float(p.pct))])
		_label(Loc.tf("UI_CRATES2_CT_PHASES", {"list": " · ".join(parts)}))
	var sign_btn := Button.new()
	sign_btn.text = Loc.tf("UI_CRATES2_CT_SIGN", {"n": selection.size()})
	sign_btn.theme_type_variation = &"AccentButton"
	sign_btn.pressed.connect(_on_sign_pressed)
	add_child(sign_btn)


func _phase_name(phase_id: String) -> String:
	for p in CrateUi.rules().get("relic_phases", []):
		if p.id == phase_id:
			return Loc.t(p.name)
	return phase_id


func _build_result() -> void:
	if last_result.is_empty():
		return
	_section(tr("UI_CRATES2_CT_RESULT"))
	var r := last_result
	var l := Label.new()
	l.text = Loc.tf("UI_CRATES_FOUND_PLAIN", {"name": CrateUi.def_name(str(r.def_id))})
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_color_override("font_color", CrateUi.rarity_color(str(r.rarity)))
	add_child(l)
	_result_title = l
	var extra := CrateUi.rarity_label(str(r.rarity))
	if str(r.kind) == "pet":
		extra += "\n" + tr("UI_CRATES_PET_FOUND")
	else:
		extra += "\n" + CrateUi.instance_text(r.instance).split("\n", false, 1)[1]
	if bool(r.is_new):
		extra += "\n" + tr("UI_CRATES_NEW")
	_label(extra)
	if not str(r.uid).is_empty():
		_actions = CrateActions.new()
		add_child(_actions)
		_actions.setup(crates, str(r.uid))


# ------------------------------------------------------------------ azioni

func _set_golden(on: bool) -> void:
	if golden == on:
		rebuild(true)
		return
	golden = on
	selection = []
	last_result = {}
	rebuild(true)


func _set_annal(on: bool) -> void:
	annal = on
	selection = []
	last_result = {}
	rebuild(true)


func _on_toggle(on: bool, uid: String) -> void:
	var need := crates.contract_inputs(golden)
	if on and not selection.has(uid) and selection.size() < need:
		selection.append(uid)
	elif not on:
		selection.erase(uid)
	last_result = {}
	rebuild(true)


func auto_pick() -> void:
	selection = []
	for u in crates.auto_pick("mythic" if golden else rarity, annal, golden):
		selection.append(str(u))
	last_result = {}
	rebuild(true)


func _on_sign_pressed() -> void:
	CrateUi.confirm(self, Loc.tf("UI_CRATES2_CT_CONFIRM", {"n": selection.size()}), sign_now)


## Firma il contratto (dopo la conferma). L'esito è già deciso dentro CrateSystem.contract_sign().
func sign_now() -> void:
	var res := crates.contract_sign(selection, golden)
	if res.is_empty():
		return
	last_result = res
	selection = []
	rebuild(true)
	_fx_forged.call_deferred(str(res.get("rarity", "")))


## «Forgiato!»: scintille e bagliore nel colore della rarità ottenuta (DOPO l'esito, già estratto da CrateSystem).
func _fx_forged(rarity_id: String) -> void:
	if _result_title == null or not is_instance_valid(_result_title) or not _result_title.is_inside_tree():
		return
	var r := _result_title.get_global_rect()
	Fx.reveal(Rect2(r.position - Vector2(10, 6), Vector2(maxf(r.size.x, 160.0), r.size.y + 12.0)), rarity_id)
	Fx.number(r.get_center() + Vector2(0, -26), tr("UI_FX_FORGED"), FxPalette.rarity(rarity_id), Fx.NUM_L, 40.0, 1.0, 1)
	Fx.burst("forge", r.get_center(), [], 1.0, 1.0, Vector2(r.size.x * 0.3, 6.0), 1)
