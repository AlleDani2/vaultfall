class_name MenuIcons
extends RefCounted
## Icone delle voci del menù laterale che non sono mansioni (rapporto 08 punto 4: righe uniformi, icona su tutte).
## Solo RIUSO di PNG già presenti in `assets/` a dimensione nativa (32x32): nessun file nuovo né modificato (D-6), nessun
## ridimensionamento. Se un'icona manca la voce resta con lo spazio vuoto (il testo resta allineato alle altre righe).

const SIZE := 32.0                       # lato nativo delle icone del menù (mansioni comprese)

const PATHS := {
	"summary": "res://assets/icons/items/map_fragment.png",
	"quests": "res://assets/ui/shop_action_queue_1.png",
	"combat": "res://assets/icons/items/greatsword_iron.png",
	"hero": "res://assets/icons/skills/hero.png",
	"talents": "res://assets/icons/items/essence_stone.png",
	"dungeon": "res://assets/icons/dungeons/cursed_granary.png",
	"bounty": "res://assets/icons/items/bounty_mark.png",
	"bank": "res://assets/ui/shop_bank_slot.png",
	"market": "res://assets/ui/shop_market_license_1.png",
	"shop": "res://assets/ui/shop_loadout_slot.png",
	"orders": "res://assets/icons/items/commission_token.png",
	"factions": "res://assets/icons/factions/merchant_league.png",
	"estate": "res://assets/icons/items/crop_wheat.png",
	"guild": "res://assets/icons/items/rally_horn.png",
	"secrets": "res://assets/icons/items/padlock_steel.png",
	"vault_hall": "res://assets/icons/crates/crate_millbrook.png",
	"album": "res://assets/icons/cosmetics/cosmetic_banner_01.png",
	"wardrobe": "res://assets/icons/cosmetics/cosmetic_emblem_01.png",
	"vault_workshop": "res://assets/icons/items/key_t1.png",
	"prestige": "res://assets/icons/items/gem_startear.png",
	"events": "res://assets/icons/items/event_petal.png",
	"compendium": "res://assets/icons/items/drowned_tome.png",
	"coop": "res://assets/icons/items/raid_seal.png",
	"coop_lobby": "res://assets/icons/items/raid_seal.png",
	"coop_guild": "res://assets/icons/items/raid_seal.png",
	"manual": "res://assets/icons/items/mm_wet_parchment.png",
	"guide": "res://assets/icons/relics/relic_archive_1.png",
	"news": "res://assets/icons/items/feather.png",
}


## Percorso dell'icona di una voce ("" se non ne ha una propria).
static func path_of(id: String) -> String:
	return str(PATHS.get(id, ""))


## Icona della voce: quella dichiarata dal registro (mansioni) oppure quella di questa tabella. null se manca il file.
static func texture(id: String, registry_icon: String = "") -> Texture2D:
	var p := registry_icon if not registry_icon.is_empty() else path_of(id)
	if p.is_empty() or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D


## Segnaposto trasparente della stessa misura per le voci senza icona: il testo resta allineato a quello delle altre righe.
static func blank() -> Texture2D:
	var t := PlaceholderTexture2D.new()
	t.size = Vector2(SIZE, SIZE)
	return t
