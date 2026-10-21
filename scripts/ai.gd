extends RefCounted
## Simple CPU opponent: plays the cheapest legal combination, saves 2s and bombs
## for when they matter, and dumps as many low cards as possible when leading.
##
## Optional `tuning` (from a character profile's card_ai.tuning) changes its style:
##   aggression         0..1  less likely to pass on purpose
##   two_hold_tendency  0..1  how often 2s/bombs are held back (1 = always, the default)
##   bluff_rate         0..1  chance to lead a straight that skips her lowest card
##   prefers_straights  bool  leads with straights when she can

const Rules := preload("res://scripts/rules.gd")


## Returns the cards to play, or an empty array to pass.
## `required_card` (>= 0) must be included (opening play of the game).
## `danger` is the fewest cards any opponent is holding.
static func choose_play(hand: Array, current: Dictionary, required_card: int, danger: int,
		tuning: Dictionary = {}) -> Array:
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
		return _choose_lead(hand, candidates, tuning)
	return _choose_follow(hand, current, candidates, danger, tuning)


static func _choose_lead(hand: Array, candidates: Array, tuning: Dictionary) -> Array:
	var lowest: int = hand.min()
	if tuning.get("prefers_straights", false):
		var with_lowest = _longest_straight(candidates, lowest)
		if with_lowest != null:
			return with_lowest.cards
		if randf() < tuning.get("bluff_rate", 0.0):
			var any = _longest_straight(candidates, -1)
			if any != null:
				return any.cards
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


static func _choose_follow(hand: Array, current: Dictionary, candidates: Array, danger: int,
		tuning: Dictionary) -> Array:
	var current_is_two: bool = Rules.rank(current.top) == Rules.RANK_TWO
	var urgent := danger <= 3 or hand.size() <= 5 or current_is_two
	var spend_precious: bool = urgent or randf() >= tuning.get("two_hold_tendency", 1.0)
	var cheap := []
	for c in candidates:
		if spend_precious or not _is_precious(c.combo):
			cheap.append(c)
	if cheap.is_empty():
		return []
	# Occasionally pass with a weak hand to save cards, unless someone is close to winning.
	var best = _cheapest(cheap)
	var pass_chance: float = 0.35 * (1.0 - tuning.get("aggression", 0.0))
	if not urgent and Rules.rank(best.combo.top) >= 10 and randf() < pass_chance:
		return []
	return best.cards


## Longest non-precious straight (lowest top on ties), optionally one containing `must_have`.
static func _longest_straight(candidates: Array, must_have: int):
	var best = null
	for c in candidates:
		if c.combo.type != Rules.Type.STRAIGHT or (must_have >= 0 and not c.cards.has(must_have)):
			continue
		if best == null or c.cards.size() > best.cards.size() \
				or (c.cards.size() == best.cards.size() and c.combo.top < best.combo.top):
			best = c
	return best


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
