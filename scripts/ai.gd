extends RefCounted
## Simple CPU opponent: plays the cheapest legal combination, saves 2s and bombs
## for when they matter, and dumps as many low cards as possible when leading.

const Rules := preload("res://scripts/rules.gd")


## Returns the cards to play, or an empty array to pass.
## `required_card` (>= 0) must be included (opening play of the game).
## `danger` is the fewest cards any opponent is holding.
static func choose_play(hand: Array, current: Dictionary, required_card: int, danger: int) -> Array:
	var candidates := []
	for cards in Rules.all_combos(hand):
		if required_card >= 0 and not cards.has(required_card):
			continue
		var combo := Rules.analyze(cards)
		if Rules.can_beat(combo, current):
			candidates.append({"cards": cards, "combo": combo})
	if candidates.is_empty():
		return []

	# Going out wins outright.
	for c in candidates:
		if c.cards.size() == hand.size():
			return c.cards

	if current.is_empty():
		return _choose_lead(hand, candidates)
	return _choose_follow(hand, current, candidates, danger)


static func _choose_lead(hand: Array, candidates: Array) -> Array:
	var lowest: int = hand.min()
	var best = null
	for c in candidates:
		if not c.cards.has(lowest) or _is_precious(c.combo):
			continue
		# Shed as many cards as possible, then keep the top card low.
		if best == null or c.cards.size() > best.cards.size() \
				or (c.cards.size() == best.cards.size() and c.combo.top < best.combo.top):
			best = c
	if best == null:
		best = _cheapest(candidates)
	return best.cards


static func _choose_follow(hand: Array, current: Dictionary, candidates: Array, danger: int) -> Array:
	var current_is_two: bool = Rules.rank(current.top) == Rules.RANK_TWO
	var urgent := danger <= 3 or hand.size() <= 5 or current_is_two
	var cheap := []
	for c in candidates:
		if urgent or not _is_precious(c.combo):
			cheap.append(c)
	if cheap.is_empty():
		return []
	# Occasionally pass with a weak hand to save cards, unless someone is close to winning.
	var best = _cheapest(cheap)
	if not urgent and Rules.rank(best.combo.top) >= 10 and randf() < 0.35:
		return []
	return best.cards


## 2s and bombs are worth holding on to.
static func _is_precious(combo: Dictionary) -> bool:
	return Rules.rank(combo.top) == Rules.RANK_TWO \
		or combo.type == Rules.Type.QUAD or combo.type == Rules.Type.DOUBLE_SEQ


static func _cheapest(candidates: Array):
	var best = candidates[0]
	for c in candidates:
		if c.combo.top < best.combo.top or (c.combo.top == best.combo.top and c.cards.size() < best.cards.size()):
			best = c
	return best
