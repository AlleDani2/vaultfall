class_name RefineryView
extends WorkshopView
## Scheda Affinatura (docs/09 §10): Lucidatura (float −10% verso il minimo), Incisione Annalista, Targhetta.
## Tutto deterministico e a posta zero: si spendono Schegge del Caveau (o oro) e l'oggetto resta sempre del giocatore.
## L'anteprima mostra già l'esito esatto (nuovo float, nuova condizione, costo).

const MAX_LIST := 60

var selected_uid: String = ""
var rarity_filter: String = ""
var tag_text: String = ""
var _msg: String = ""
var _bench_title: Label


func _apply_params(params: Dictionary) -> void:
	if params.has("add"):
		selected_uid = str(params.add)


func signature() -> String:
	return "%d|%s|%s|%d|%d|%d|%s" % [bank_revision(), selected_uid, rarity_filter, crates.shards(), gold(),
		1 if crates.refinery_unlocked() else 0, _msg]


func _items() -> Array:
	var out: Array = []
	for inst in _instances_of(["skin", "relic"]):
		if rarity_filter.is_empty() or str(inst.rarity) == rarity_filter:
			out.append(inst)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ua := 1 if crates.is_in_use(str(a.uid)) else 0
		var ub := 1 if crates.is_in_use(str(b.uid)) else 0
		if ua != ub:
			return ua > ub
		var ra := CrateSystem.RARITIES.find(str(a.rarity))
		var rb := CrateSystem.RARITIES.find(str(b.rarity))
		if ra != rb:
			return ra > rb
		return float(a.get("float", 1.0)) < float(b.get("float", 1.0)))
	return out


func build() -> void:
	if not crates.refinery_unlocked():
		_locked_note(CrateSystem.TOKEN_REFINERY, "UI_CRATES_TAB_REFINE", "UI_VUX_RF_EMPTY_WHAT")
		return
	var head := Label.new()
	head.text = Loc.tf("UI_CRATES2_RF_BALANCE", {"s": NumberFormat.fmt(crates.shards()), "g": NumberFormat.fmt(gold())})
	head.theme_type_variation = &"SectionLabel"
	add_child(head)
	if not _msg.is_empty():
		_label(_msg, false)

	var ob := _rarity_option(true, CrateSystem.RARITIES, rarity_filter)
	ob.item_selected.connect(func(i: int) -> void:
		rarity_filter = str(ob.get_item_metadata(i))
		rebuild(true))
	add_child(ob)

	var items := _items()
	if items.is_empty():
		if _instances_of(["skin", "relic"]).is_empty():
			var gos: Array = []
			var hall := ScreenRegistry.get_entry("vault_hall")
			if not hall.is_empty() and ScreenRegistry.is_available(hall, GameState.data.get("unlocks", [])):
				gos.append({"text": tr("UI_MENU_VAULT_HALL"), "primary": true, "target": {"screen": "vault_hall", "params": {}, "hint": ""}})
			VaultKit.empty_card(self, IconLib.icon("items", "bar_vaultsteel"), tr("UI_VUX_RF_EMPTY_TITLE"), tr("UI_VUX_RF_EMPTY_WHAT"),
				PackedStringArray([tr("UI_VUX_RF_STEP_1"), tr("UI_VUX_RF_STEP_2")]), gos)
		else:
			_label(tr("UI_CRATES2_RF_NO_ITEMS"))
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 170)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		for k in mini(items.size(), MAX_LIST):
			var inst: Dictionary = items[k]
			var uid := str(inst.uid)
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_pressed = uid == selected_uid
			b.clip_text = true
			b.icon = CrateUi.def_icon(str(inst.def_id))
			b.expand_icon = true
			b.text = CrateUi.inst_line(inst) + (" · " + tr("UI_CRATES2_RF_EQUIPPED") if crates.is_in_use(uid) else "")
			b.tooltip_text = CrateUi.instance_text(inst)
			b.add_theme_color_override("font_color", CrateUi.rarity_color(str(inst.rarity)))
			b.pressed.connect(_select.bind(uid))
			list.add_child(b)
		if items.size() > MAX_LIST:
			CrateUi.note(list, Loc.tf("UI_CRATES_MORE", {"n": items.size() - MAX_LIST}))

	var inst2 := crates.instance(selected_uid)
	if inst2.is_empty():
		_label(tr("UI_CRATES2_RF_PICK"))
		return
	_build_bench(inst2)


func _select(uid: String) -> void:
	selected_uid = uid
	tag_text = str(crates.instance(uid).get("tag", ""))
	_msg = ""
	rebuild(true)


func _build_bench(inst: Dictionary) -> void:
	var title := Label.new()
	title.text = CrateUi.tagged_name(inst)
	ScreenKit.title_style(title)
	title.add_theme_color_override("font_color", CrateUi.rarity_color(str(inst.rarity)))
	add_child(title)
	_bench_title = title
	_label(CrateUi.instance_text(inst).split("\n", false, 1)[1] if CrateUi.instance_text(inst).contains("\n") else "")

	# --- Lucidatura
	_section(tr("UI_CRATES2_RF_POLISH"))
	var pi := crates.polish_info(selected_uid)
	if str(pi.reason) == "kind":
		_label(CrateUi.why("kind"))
	else:
		_label(Loc.tf("UI_CRATES2_RF_POLISH_PREVIEW", {
			"a": NumberFormat.decimal(float(pi.float), 4, _lang()), "ca": CrateUi.condition_name(str(pi.condition)),
			"b": NumberFormat.decimal(float(pi.new_float), 4, _lang()), "cb": CrateUi.condition_name(str(pi.new_condition)),
			"cost": NumberFormat.fmt(int(pi.cost)), "n": int(pi.done), "max": int(pi.max)}), false)
		var pb := Button.new()
		pb.text = Loc.tf("UI_CRATES2_RF_POLISH_BTN", {"cost": NumberFormat.fmt(int(pi.cost))})
		pb.disabled = not bool(pi.ok)
		if pb.disabled:
			pb.tooltip_text = CrateUi.why(str(pi.reason))
		pb.pressed.connect(do_polish)
		add_child(pb)
		if pb.disabled:
			_label(CrateUi.why(str(pi.reason)))

	# --- Incisione Annalista
	if str(inst.kind) == "skin":
		_section(tr("UI_CRATES2_RF_ENGRAVE"))
		var ei := crates.engrave_info(selected_uid)
		_label(Loc.tf("UI_CRATES2_RF_ENGRAVE_INFO", {"cost": NumberFormat.fmt(int(ei.cost))}), false)
		var eb := Button.new()
		eb.text = Loc.tf("UI_CRATES2_RF_ENGRAVE_BTN", {"cost": NumberFormat.fmt(int(ei.cost))})
		eb.disabled = not bool(ei.ok)
		if eb.disabled:
			eb.tooltip_text = CrateUi.why(str(ei.reason))
		eb.pressed.connect(do_engrave)
		add_child(eb)
		if eb.disabled:
			_label(CrateUi.why(str(ei.reason)))

	# --- Targhetta
	_section(tr("UI_CRATES2_RF_TAG"))
	_label(Loc.tf("UI_CRATES2_RF_TAG_INFO", {"g": NumberFormat.fmt(crates.rename_cost())}))
	var row := HBoxContainer.new()
	add_child(row)
	var tb := Button.new()
	var le := LineEdit.new()
	le.text = tag_text
	le.max_length = int(CrateUi.rules().refinery.rename.max_len)
	le.placeholder_text = tr("UI_CRATES2_RF_TAG_PLACEHOLDER")
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t: String) -> void:
		tag_text = t
		_refresh_tag_btn(tb))
	row.add_child(le)
	tb.pressed.connect(do_rename)
	row.add_child(tb)
	_refresh_tag_btn(tb)


func _refresh_tag_btn(tb: Button) -> void:
	var ri := crates.rename_info(selected_uid, tag_text)
	tb.text = Loc.tf("UI_CRATES2_RF_TAG_BTN", {"g": NumberFormat.fmt(int(ri.cost))}) if int(ri.cost) > 0 else tr("UI_CRATES2_RF_TAG_REMOVE")
	tb.disabled = not bool(ri.ok)
	tb.tooltip_text = CrateUi.why(str(ri.reason)) if tb.disabled else ""


func _lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


func do_polish() -> void:
	var before := crates.polish_info(selected_uid)
	if crates.polish(selected_uid):
		_msg = Loc.tf("UI_CRATES2_RF_POLISHED", {"f": NumberFormat.decimal(float(before.new_float), 4, _lang()), "c": CrateUi.condition_name(str(before.new_condition))})
		rebuild(true)
		_fx_refined.call_deferred("forge")
		return
	rebuild(true)


func do_engrave() -> void:
	if crates.engrave(selected_uid):
		_msg = tr("UI_CRATES2_RF_ENGRAVED")
		rebuild(true)
		_fx_refined.call_deferred("glint")
		return
	rebuild(true)


## «Affinato!»: scintille di forgia (lucidatura) o luccichii (incisione) sul titolo dell'oggetto, nel colore della sua rarità.
func _fx_refined(preset: String) -> void:
	if _bench_title == null or not is_instance_valid(_bench_title) or not _bench_title.is_inside_tree():
		return
	var r := _bench_title.get_global_rect()
	var col := _bench_title.get_theme_color("font_color") if _bench_title.has_theme_color_override("font_color") else FxPalette.GOLD
	Fx.burst(preset, r.get_center(), [col, FxPalette.WHITE, FxPalette.lighten(col, 0.5)], 1.1, 1.4, Vector2(maxf(40.0, r.size.x * 0.3), 6.0), 1)
	Fx.frame_flash(r.grow(6.0), col, 14.0, 0.5, 0.8)
	Fx.number(r.get_center() + Vector2(0, -24), tr("UI_FX_REFINED"), col, Fx.NUM_M, 34.0, 0.9)


func do_rename() -> void:
	if crates.rename(selected_uid, tag_text):
		_msg = tr("UI_CRATES2_RF_TAGGED") if not crates.clean_tag(tag_text).is_empty() else tr("UI_CRATES2_RF_TAG_REMOVED")
	rebuild(true)
