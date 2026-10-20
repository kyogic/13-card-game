extends RefCounted
## Tien Len (Southern Vietnamese "Thirteen") rules.
##
## A card is an int 0..51: value = rank * 4 + suit.
##   rank 0..12 -> 3 4 5 6 7 8 9 10 J Q K A 2   (2 is the highest rank)
##   suit 0..3  -> spades < clubs < diamonds < hearts
## Comparing card ints directly therefore gives the correct Tien Len order.

enum Type { INVALID, SINGLE, PAIR, TRIPLE, QUAD, STRAIGHT, DOUBLE_SEQ }

const RANK_NAMES := ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
const SUIT_NAMES := ["Spades", "Clubs", "Diamonds", "Hearts"]
const RANK_TWO := 12


static func rank(card: int) -> int:
	return card / 4


static func suit(card: int) -> int:
	return card % 4


static func card_name(card: int) -> String:
	return "%s of %s" % [RANK_NAMES[rank(card)], SUIT_NAMES[suit(card)]]


static func new_deck() -> Array:
	var deck := []
	for c in 52:
		deck.append(c)
	return deck


## Describes a set of cards. Returns {type, count, top, pairs} where `top` is the
## highest card (used for comparisons) and `pairs` is the pair count of a double sequence.
static func analyze(cards: Array) -> Dictionary:
	var result := {"type": Type.INVALID, "count": cards.size(), "top": -1, "pairs": 0}
	var n := cards.size()
	if n == 0:
		return result
	var sorted := cards.duplicate()
	sorted.sort()
	result.top = sorted[n - 1]

	var all_same_rank := true
	for c in sorted:
		if rank(c) != rank(sorted[0]):
			all_same_rank = false
			break

	if all_same_rank:
		match n:
			1: result.type = Type.SINGLE
			2: result.type = Type.PAIR
			3: result.type = Type.TRIPLE
			4: result.type = Type.QUAD
		return result

	# Straight: 3+ consecutive ranks, one card each, no 2s.
	if n >= 3 and _is_consecutive(sorted, 1):
		result.type = Type.STRAIGHT
		return result

	# Double sequence: 3+ consecutive pairs, no 2s.
	if n >= 6 and n % 2 == 0 and _is_consecutive(sorted, 2):
		result.type = Type.DOUBLE_SEQ
		result.pairs = n / 2
		return result

	return result


## True when sorted cards form consecutive ranks with `group` cards per rank and no 2s.
static func _is_consecutive(sorted: Array, group: int) -> bool:
	if rank(sorted[sorted.size() - 1]) == RANK_TWO:
		return false
	for i in sorted.size():
		var expected_rank: int = rank(sorted[0]) + i / group
		if rank(sorted[i]) != expected_rank:
			return false
	return true


static func is_valid(combo: Dictionary) -> bool:
	return combo.type != Type.INVALID


## Can `play` legally be put on top of `current`? An empty `current` means a fresh lead.
static func can_beat(play: Dictionary, current: Dictionary) -> bool:
	if not is_valid(play):
		return false
	if current.is_empty():
		return true

	# Normal beat: same type and size, higher top card.
	if play.type == current.type and play.count == current.count:
		return play.top > current.top

	# "Chop" (chặt) bombs that break the normal rules.
	var cur_is_single_two: bool = current.type == Type.SINGLE and rank(current.top) == RANK_TWO
	var cur_is_pair_two: bool = current.type == Type.PAIR and rank(current.top) == RANK_TWO
	if play.type == Type.QUAD:
		return cur_is_single_two or cur_is_pair_two \
			or (current.type == Type.DOUBLE_SEQ and current.pairs == 3)
	if play.type == Type.DOUBLE_SEQ:
		if cur_is_single_two:
			return true
		if play.pairs >= 4 and (cur_is_pair_two or current.type == Type.QUAD):
			return true
		if current.type == Type.DOUBLE_SEQ and play.pairs > current.pairs:
			return true
	return false


static func type_name(combo: Dictionary) -> String:
	match combo.type:
		Type.SINGLE: return "Single"
		Type.PAIR: return "Pair"
		Type.TRIPLE: return "Triple"
		Type.QUAD: return "Four of a Kind"
		Type.STRAIGHT: return "Straight of %d" % combo.count
		Type.DOUBLE_SEQ: return "%d Consecutive Pairs" % combo.pairs
	return "Invalid"


## Enumerates the playable combinations in a hand. To stay small it does not list every
## suit permutation; it keeps the variants that matter (every possible top card).
static func all_combos(hand: Array) -> Array:
	var combos := []
	var by_rank := {}
	for c in hand:
		var r := rank(c)
		if not by_rank.has(r):
			by_rank[r] = []
		by_rank[r].append(c)
	for r in by_rank:
		by_rank[r].sort()

	# Singles, pairs, triples, quads.
	for c in hand:
		combos.append([c])
	for r in by_rank:
		var cs: Array = by_rank[r]
		for i in cs.size():
			for j in range(i + 1, cs.size()):
				combos.append([cs[i], cs[j]])
		if cs.size() == 3:
			combos.append(cs.duplicate())
		elif cs.size() == 4:
			for skip in 4:
				var t := cs.duplicate()
				t.remove_at(skip)
				combos.append(t)
			combos.append(cs.duplicate())

	# Straights: lowest cards for the body, every suit for the top card.
	for start in range(0, RANK_TWO):
		var body := []
		var r := start
		while r < RANK_TWO and by_rank.has(r):
			if body.size() >= 2:
				for top in by_rank[r]:
					combos.append(body + [top])
			body.append(by_rank[r][0])
			r += 1

	# Double sequences: lowest pair for the body, every pair for the top rank.
	for start in range(0, RANK_TWO):
		var body := []
		var r := start
		while r < RANK_TWO and by_rank.has(r) and by_rank[r].size() >= 2:
			if body.size() >= 4:
				var cs: Array = by_rank[r]
				for i in cs.size():
					for j in range(i + 1, cs.size()):
						combos.append(body + [cs[i], cs[j]])
			body.append(by_rank[r][0])
			body.append(by_rank[r][1])
			r += 1

	return combos
