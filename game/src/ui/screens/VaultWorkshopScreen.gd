extends GameScreen
## Bottega dei Caveau: le schede Contratti, Affinatura, Banco e Sfida (docs/09 §9-§12). Ogni scheda è una vista
## (ContractsView, RefineryView, VaultBankView, ChallengeView) che mostra i numeri di CrateSystem; qui c'è solo la
## cornice: titolo, schede, avviso legale (docs/24). Parametri: {"tab": contracts|refine|bank|challenge, "add": uid}.

const TABS := ["contracts", "refine", "bank", "challenge"]

var _crates: CrateSystem
var _tab: String = "contracts"
var _view: WorkshopView
var _host: VBoxContainer
var _res: Control


func open(params: Dictionary) -> void:
	_crates = CrateUi.crates()
	_tab = str(params.get("tab", _tab))
	if not TABS.has(_tab):
		_tab = "bank"
	_build(params)


func refresh() -> void:
	if _res != null and is_instance_valid(_res):
		VaultKit.update_resources(_res)
	if _view != null:
		_view.refresh()


func current_view() -> WorkshopView:
	return _view


func current_tab() -> String:
	return _tab


func _build(params: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var intro := {"contracts": "UI_CRATES2_CT_INTRO", "refine": "UI_CRATES2_RF_INTRO", "challenge": "UI_CRATES2_CH_INTRO"}
	VaultKit.header(self, "workshop_" + _tab, "UI_MENU_VAULT_WORKSHOP", str(intro.get(_tab, "UI_CRATES2_VB_INTRO")))
	_res = VaultKit.resource_host(self)
	CrateUi.build_tabs(self, _tab)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_host = VBoxContainer.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_host)
	match _tab:
		"contracts":
			_view = ContractsView.new()
		"refine":
			_view = RefineryView.new()
		"challenge":
			_view = ChallengeView.new()
		_:
			_view = VaultBankView.new()
	_host.add_child(_view)
	if _crates != null:
		_view.setup(_crates, params)
	var legal := Label.new()
	legal.text = tr("UI_CRATES_LEGAL")
	legal.theme_type_variation = &"MutedLabel"
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(legal)
