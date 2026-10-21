extends Node
## Story money ($): earned by talking, right quiz answers and dates (tuning.json -> economy),
## spent in the shop on gifts (data/shop.json). The shop restocks each morning.
## Separate from the Quickplay coins used in the Wardrobe.

const SHOP_PATH := "res://data/shop.json"

var shop: Dictionary = {}


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHOP_PATH))
	shop = parsed if parsed is Dictionary else {}


func _ready() -> void:
	EventBus.fact_learned.connect(func(i):
		if i.get("source") == "talk":
			earn(Config.int_value("economy.talk"), "talk"))
	EventBus.trivia_answered.connect(func(i):
		if i.correct:
			earn(Config.int_value("economy.trivia_correct"), "trivia"))
	EventBus.match_ended.connect(func(i):
		if GameState.in_date:
			var won: bool = i.get("winner") == "player"
			earn(Config.int_value("economy.date_won" if won else "economy.date_lost"), "date"))


func earn(amount: int, reason: String) -> void:
	if amount == 0:
		return
	GameState.money += amount
	EventBus.fire("money_changed", {"delta": amount, "value": GameState.money, "reason": reason})


func price(item_id: String) -> int:
	return int(shop.get("items", {}).get(item_id, 0))


## Picks today's stock at random from the catalog.
func restock() -> void:
	var catalog: Array = shop.get("items", {}).keys()
	catalog.shuffle()
	GameState.shop_stock = catalog.slice(0, int(shop.get("stock_per_day", 6)))


func can_buy(item_id: String) -> bool:
	return GameState.shop_stock.has(item_id) and GameState.money >= price(item_id)


func buy(item_id: String) -> bool:
	if not can_buy(item_id):
		return false
	var cost := price(item_id)
	GameState.money -= cost
	GameState.inventory[item_id] = GameState.inventory.get(item_id, 0) + 1
	GameState.log_event("purchase", "Bought %s for $%d." % [item_id, cost])
	EventBus.fire("money_changed", {"delta": -cost, "value": GameState.money, "reason": "shop"})
	EventBus.fire("item_bought", {"item_id": item_id, "price": cost})
	return true
