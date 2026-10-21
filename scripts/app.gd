extends Control
## Root of the game: the Tiến Lên card game with the dating layer on top.
## The two never call each other; they communicate through the EventBus autoload.

const DatingLayer := preload("res://scripts/dating/dating_layer.gd")

var card_game: Control
var dating: Control


func _ready() -> void:
	card_game = load("res://scenes/main.tscn").instantiate()
	add_child(card_game)
	dating = DatingLayer.new()
	add_child(dating)
