extends Control
## Character profile page: who she is, affection progress and unlocks, and gifts.
## Reads and changes progress through the main scene (`game`).

const Character := preload("res://scripts/character.gd")

## Unlock keys from the profile that the prototype already implements.
const UNLOCK_TEXT := {
	"casual_outfit_2": "Street outfit (free in the Wardrobe)",
	"nickname_anh": "She calls you “anh”",
	"bracelet_story": "The story behind her bracelet",
}

var game                       # main.gd
var portrait: TextureRect
var title_label: Label
var info_label: Label
var summary_label: Label
var affection_bar: ProgressBar
var affection_text: Label
var unlocks_label: Label
var story_label: Label
var coins_label: Label
var gift_buttons := {}         # gift id -> Button
var reaction_label: Label


func setup(main) -> void:
	game = main
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var c = game.character

	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	game._set_offsets(portrait, 10, 400, 10, -10)
	add_child(portrait)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	game._set_offsets(col, 420, -30, 24, -16)
	add_child(col)

	title_label = _left(game._make_label("%s  “%s”" % [c.full_name(), c.data.get("nickname", "")], 36,
		Color(1, 0.85, 0.4)))
	col.add_child(title_label)
	info_label = _left(game._make_label("%s  ·  %s  ·  %s" % [c.data.get("age", ""),
		c.data.get("occupation", ""), c.data.get("heritage", "")], 16, game.IDLE_COLOR))
	col.add_child(info_label)
	summary_label = _left(game._make_label(c.data.get("personality", {}).get("summary", ""), 16,
		Color(0.85, 0.92, 0.85)))
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(summary_label)

	affection_bar = ProgressBar.new()
	affection_bar.max_value = c.affection_max()
	affection_bar.show_percentage = false
	affection_bar.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.45, 0.65)
	fill.set_corner_radius_all(6)
	affection_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(affection_bar)
	affection_text = _left(game._make_label("", 17, Color(1, 0.75, 0.85)))
	col.add_child(affection_text)
	unlocks_label = _left(game._make_label("", 15, Color(0.85, 0.92, 0.85)))
	col.add_child(unlocks_label)
	story_label = _left(game._make_label("", 15, Color(1, 0.9, 0.7)))
	story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(story_label)

	coins_label = _left(game._make_label("", 18, Color(1, 0.85, 0.2)))
	col.add_child(coins_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for g in c.gifts():
		var b: Button = game._make_button(Character.pretty(g.id), 16)
		b.custom_minimum_size = Vector2(230, 32)
		b.pressed.connect(_on_gift.bind(g.id))
		grid.add_child(b)
		gift_buttons[g.id] = b
	col.add_child(grid)
	reaction_label = _left(game._make_label("", 16, Color(1, 0.9, 0.6)))
	reaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(reaction_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var wardrobe: Button = game._make_button("Wardrobe", 20)
	wardrobe.pressed.connect(game._show_wardrobe)
	row.add_child(wardrobe)
	var back: Button = game._make_button("Back", 20)
	back.pressed.connect(game._show_menu)
	row.add_child(back)
	col.add_child(row)


func _left(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


func refresh() -> void:
	var c = game.character
	var aff: int = game.affection
	portrait.texture = load(game._outfit(game.selected_outfit).path)
	affection_bar.value = aff
	var next: Dictionary = c.next_stage(aff)
	affection_text.text = "Affection %d/%d  ·  %s%s" % [aff, c.affection_max(), c.stage(aff).get("label", ""),
		"   (next: %s at %d)" % [next.label, next.min] if not next.is_empty() else ""]

	var lines := []
	for s in c.stages():
		var texts := []
		for key in s.get("unlocks", []):
			texts.append(UNLOCK_TEXT.get(key, Character.pretty(key) + " (soon)"))
		lines.append("%s  %s (%d):  %s" % ["[x]" if aff >= s.min else "[  ]", s.label, s.min, ", ".join(texts)])
	unlocks_label.text = "\n".join(lines)
	story_label.text = ""
	if c.is_unlocked("bracelet_story", aff):
		story_label.text = "“%s”" % c.data.get("personality", {}).get("hidden_side", "")

	coins_label.text = "Give a gift  (%d coin each)   ·   Coins: %d" % [game.GIFT_COST, game.coins]
	for id in gift_buttons:
		gift_buttons[id].disabled = game.coins < game.GIFT_COST


func _on_gift(id: String) -> void:
	var reaction: String = game.give_gift(id)
	if reaction != "":
		reaction_label.text = "%s:  %s" % [Character.pretty(id), reaction]
	refresh()
