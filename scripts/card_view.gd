extends Control
## Draws a single playing card (no image assets needed). Emits `clicked` when pressed.

signal clicked(card_view)

const Rules := preload("res://scripts/rules.gd")
const CARD_SIZE := Vector2(72, 104)
const RED := Color(0.82, 0.1, 0.12)
const BLACK := Color(0.08, 0.08, 0.1)

var card: int = -1
var face_up := true
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var interactive := false


func setup(p_card: int, p_face_up := true, p_interactive := false, scale_factor := 1.0) -> void:
	card = p_card
	face_up = p_face_up
	interactive = p_interactive
	custom_minimum_size = CARD_SIZE * scale_factor
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if interactive:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(6 * size.x / CARD_SIZE.x))
	box.set_border_width_all(2)
	if not face_up:
		box.bg_color = Color(0.15, 0.25, 0.6)
		box.border_color = Color(0.95, 0.95, 0.95)
		draw_style_box(box, rect)
		var inner := rect.grow(-size.x * 0.12)
		draw_rect(inner, Color(0.25, 0.4, 0.8), false, 2.0)
		return

	box.bg_color = Color(1, 1, 0.97)
	box.border_color = Color(1.0, 0.8, 0.1) if selected else Color(0.3, 0.3, 0.3)
	if selected:
		box.set_border_width_all(4)
	draw_style_box(box, rect)

	var s := Rules.suit(card)
	var color := RED if s >= 2 else BLACK
	var font := ThemeDB.fallback_font
	var k := size.x / CARD_SIZE.x
	var font_size := int(20 * k)
	var label: String = Rules.RANK_NAMES[Rules.rank(card)]
	draw_string(font, Vector2(6 * k, 22 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	_draw_suit(s, Vector2(14 * k, 36 * k), 7 * k, color)
	_draw_suit(s, size * 0.5 + Vector2(4 * k, 10 * k), 18 * k, color)


## Suit pips built from primitives so no special font glyphs are required.
func _draw_suit(s: int, c: Vector2, r: float, color: Color) -> void:
	match s:
		0: # Spades
			draw_circle(c + Vector2(-r * 0.48, r * 0.15), r * 0.52, color)
			draw_circle(c + Vector2(r * 0.48, r * 0.15), r * 0.52, color)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r, r * 0.05), c + Vector2(0, -r), c + Vector2(r, r * 0.05)]), color)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, r * 0.2), c + Vector2(-r * 0.4, r), c + Vector2(r * 0.4, r)]), color)
		1: # Clubs
			draw_circle(c + Vector2(0, -r * 0.45), r * 0.45, color)
			draw_circle(c + Vector2(-r * 0.5, r * 0.15), r * 0.45, color)
			draw_circle(c + Vector2(r * 0.5, r * 0.15), r * 0.45, color)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, 0), c + Vector2(-r * 0.4, r), c + Vector2(r * 0.4, r)]), color)
		2: # Diamonds
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)]), color)
		3: # Hearts
			draw_circle(c + Vector2(-r * 0.48, -r * 0.3), r * 0.52, color)
			draw_circle(c + Vector2(r * 0.48, -r * 0.3), r * 0.52, color)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.98, -r * 0.15), c + Vector2(r * 0.98, -r * 0.15), c + Vector2(0, r)]), color)
