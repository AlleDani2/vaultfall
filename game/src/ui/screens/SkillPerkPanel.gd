class_name SkillPerkPanel
extends VBoxContainer
## Pannello «Talenti di mansione» (docs/04 §6): ogni 10 livelli si sceglie 1 talento su 3. Componente riusabile: lo usano
## SkillScreen (tutte le mansioni «normali»), FarmScreen (Coltivazione), HeroScreen (Eroe) e BountyScreen (Taglie), cioè
## OGNI schermata che il menù apre per una mansione con talenti nei dati. Il pallino del menù (SidebarBadges/MainScreen)
## conta le stesse scelte di `has_choice()`: pallino e pannello non possono più divergere (rapporto 116).
##
## Solo presentazione: la logica è in SkillSystem (perk_rows, pending_perk_tiers, choose_perk, respec_perk).
## Le righe si ricostruiscono solo quando cambia la firma (livello, scelte consentite, lettere scelte): `refresh()` si può
## chiamare a 10 Hz senza costo. Nessun numero di bilanciamento: tutto viene dal sistema e dai dati.

signal changed                                  # una scelta o un cambio di talento è stato fatto: il genitore può ridisegnarsi

var _skill_id: String = ""
var _sk: SkillSystem
var _perk_btn: Button
var _perk_box: VBoxContainer
var _perk_open: bool = false
var _perk_sig: String = ""                      # firma di livello/scelte: le righe si ricostruiscono solo quando cambia
var _compact: bool = false                      # F7: il pulsante sta nella testata della schermata («Talenti •»), qui restano le righe


## `compact` (F7: Mansioni e Coltivazione): il pulsante NON è figlio del pannello, lo prende il chiamante con perk_button() e lo
## mette nella testata; il pannello contiene solo le righe dei talenti, che compaiono sotto quando il pulsante è premuto.
## Senza `compact` tutto resta come prima (Eroe e Taglie).
func setup(skill_id: String, compact: bool = false) -> void:
	_compact = compact
	_skill_id = skill_id
	_sk = Game.system("skills") as SkillSystem
	name = "SkillPerkPanel"
	add_theme_constant_override("separation", 6)
	_perk_btn = Button.new()
	_perk_btn.name = "PerkToggle"
	_perk_btn.toggle_mode = true
	_perk_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_perk_btn.toggled.connect(func(on: bool) -> void:
		_perk_open = on
		_perk_box.visible = on
		_rebuild_perks())
	TutorialTargets.mark(_perk_btn, "perk_btn")
	if not _compact:
		add_child(_perk_btn)
	_perk_box = VBoxContainer.new()
	_perk_box.name = "PerkRows"
	_perk_box.visible = false
	_perk_box.add_theme_constant_override("separation", 6)
	add_child(_perk_box)
	refresh()


## Il pulsante «Talenti» (in modalità compatta lo mette il chiamante nella testata).
func perk_button() -> Button:
	return _perk_btn


## Testo del suggerimento del pulsante: «c'è una scelta» oppure «il prossimo talento arriva al livello N».
func status_text() -> String:
	if _sk == null:
		return ""
	if has_choice():
		return tr("UI_SKILLS_PERK_AVAILABLE")
	var nxt := next_tier_level()
	return Loc.tf("UI_SKILLS_PERKS_NEXT", {"n": nxt}) if nxt > 0 else tr("UI_SKILLS_PERKS")


func get_skill_id() -> String:
	return _skill_id


## La mansione ha righe di talenti nei dati (il pannello si mostra).
func has_rows() -> bool:
	return _sk != null and not _sk.perk_rows(_skill_id).is_empty()


## C'è almeno una scelta da fare adesso (è la stessa condizione del pallino nel menù).
func has_choice() -> bool:
	return _sk != null and not _sk.pending_perk_tiers(_skill_id).is_empty()


func is_open() -> bool:
	return _perk_open


func set_open(on: bool) -> void:
	_perk_btn.button_pressed = on


## Quante scelte attive (pulsanti abilitati e non ancora scelti) ci sono nelle righe aperte.
func choosable_buttons() -> int:
	var n := 0
	for h in _perk_box.get_children():
		if h.is_queued_for_deletion():
			continue
		for b in h.get_children():
			if b is Button and (b as Button).toggle_mode and not (b as Button).disabled and not (b as Button).button_pressed:
				n += 1
	return n


## Livello della prossima riga di talenti non ancora raggiunta (0 = tutte raggiunte).
func next_tier_level() -> int:
	var lvl := _sk.level(_skill_id)
	var best := 0
	for row in _sk.perk_rows(_skill_id):
		var lv := int(row.level)
		if lv > lvl and (best == 0 or lv < best):
			best = lv
	return best


func refresh() -> void:
	if _sk == null or _perk_btn == null:
		return
	var rows := _sk.perk_rows(_skill_id)
	visible = not rows.is_empty()
	_perk_btn.visible = not rows.is_empty()
	if rows.is_empty():
		return
	var pending := has_choice()
	var nxt := next_tier_level()
	if _compact:                 # «Talenti •»: il puntino sostituisce il banner; la frase lunga sta nel suggerimento
		_perk_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_perk_btn.text = tr("UI_SKILLS_PERKS") + (" •" if pending else "")
		_perk_btn.tooltip_text = status_text()
		_perk_btn.theme_type_variation = &"AccentButton" if pending else &""
		if _perk_open and _perk_signature() != _perk_sig:
			_rebuild_perks()
		return
	if pending:
		Disclosure.apply(_perk_btn, "UI_SKILLS_PERK_AVAILABLE", _perk_open)
	elif nxt > 0:
		_perk_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_perk_btn.text = (Disclosure.OPEN if _perk_open else Disclosure.CLOSED) + Loc.tf("UI_SKILLS_PERKS_NEXT", {"n": nxt})
	else:
		Disclosure.apply(_perk_btn, "UI_SKILLS_PERKS", _perk_open)
	_perk_btn.theme_type_variation = &"AccentButton" if pending else &""
	if _perk_open and _perk_signature() != _perk_sig:       # al level-up le scelte si sbloccano da sole, senza riaprire la scheda
		_rebuild_perks()


func _perk_signature() -> String:
	var parts: PackedStringArray = [str(_sk.level(_skill_id)), str(_sk.perks_allowed_per_tier(_skill_id))]
	for row in _sk.perk_rows(_skill_id):
		parts.append(str(row.level) + ":" + str(_sk.chosen_letters(_skill_id, int(row.level))))
	return "|".join(parts)


func _rebuild_perks() -> void:
	if _perk_box == null:
		return
	_perk_sig = _perk_signature()
	for c in _perk_box.get_children():
		c.queue_free()
	if not _perk_open:
		return
	for row in _sk.perk_rows(_skill_id):
		var lv := int(row.level)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		_perk_box.add_child(h)
		var tl := Label.new()
		tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tl.theme_type_variation = &"MutedLabel"
		tl.text = Loc.tf("UI_SKILLS_PERK_TIER", {"n": lv})
		tl.custom_minimum_size = Vector2(90, 0)
		h.add_child(tl)
		var reached := _sk.level(_skill_id) >= lv
		var chosen := _sk.chosen_letters(_skill_id, lv)
		for opt in row.options:
			var letter := str(opt.id).substr(str(opt.id).length() - 1)
			var b := Button.new()
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = _mods_text(opt.modifiers)
			b.toggle_mode = true
			b.button_pressed = chosen.contains(letter)
			b.disabled = not reached or (not b.button_pressed and chosen.length() >= _sk.perks_allowed_per_tier(_skill_id))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(on_perk_pressed.bind(lv, letter))
			h.add_child(b)
		if not chosen.is_empty():
			var cost := _sk.respec_cost(_skill_id, lv)
			var rb := Button.new()
			rb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			rb.text = Loc.tf("UI_SKILLS_PERK_CHANGE", {"gold": NumberFormat.fmt(cost)})
			rb.pressed.connect(func() -> void:
				_sk.respec_perk(_skill_id, lv)
				_rebuild_perks()
				refresh()
				changed.emit())
			h.add_child(rb)


func on_perk_pressed(tier_level: int, letter: String) -> void:
	if not _sk.chosen_letters(_skill_id, tier_level).contains(letter):       # per cambiare si usa «Cambia» (costa oro)
		_sk.choose_perk(_skill_id, tier_level, letter)
		var fp := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		var at := Fx.center_of(fp) if fp != null else get_global_mouse_position()
		Fx.burst("star", at, [FxPalette.GOLD, FxPalette.WHITE, FxPalette.TEAL], 0.7, 0.8, Vector2.ZERO, 1)
		Fx.ring(at, FxPalette.TEAL, 50.0, 0.45)
	_rebuild_perks()
	refresh()
	changed.emit()


func _mods_text(mods: Array) -> String:
	var parts: PackedStringArray = []
	for m in mods:
		var fam := str(m.key).split(":")[0]
		var key := "UI_SKILLS_MOD_" + fam.to_upper()
		var t := tr(key)
		if t == key:
			t = Loc.t(DataRegistry.modifier_family(fam).get("desc", fam))
		parts.append(t.format({"v": NumberFormat.decimal(float(m.value), 1, Loc.locale())}))
	return ", ".join(parts)
