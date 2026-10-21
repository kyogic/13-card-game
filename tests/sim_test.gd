extends SceneTree
## Headless sanity checks: rule unit tests plus many CPU-only games.
## Run: godot --headless --path . --script res://tests/sim_test.gd

const Rules := preload("res://scripts/rules.gd")
const AI := preload("res://scripts/ai.gd")

var failures := 0


func _init() -> void:
	_rule_tests()
	var jessica := {"aggression": 0.8, "two_hold_tendency": 0.2, "bluff_rate": 0.4, "prefers_straights": true}
	for i in 300:
		_simulate(4 if i % 2 == 0 else 2, jessica if i % 3 == 0 else {})
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func c(rank_name: String, suit: int) -> int:
	return Rules.RANK_NAMES.find(rank_name) * 4 + suit


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _rule_tests() -> void:
	var T := Rules.Type
	check(Rules.analyze([c("3", 0)]).type == T.SINGLE, "single")
	check(Rules.analyze([c("7", 0), c("7", 3)]).type == T.PAIR, "pair")
	check(Rules.analyze([c("7", 0), c("8", 3)]).type == T.INVALID, "bad pair")
	check(Rules.analyze([c("9", 0), c("10", 1), c("J", 2)]).type == T.STRAIGHT, "straight")
	check(Rules.analyze([c("K", 0), c("A", 1), c("2", 2)]).type == T.INVALID, "no 2 in straight")
	var ds := [c("4", 0), c("4", 1), c("5", 0), c("5", 2), c("6", 1), c("6", 3)]
	check(Rules.analyze(ds).type == T.DOUBLE_SEQ, "double seq")
	var quad := [c("8", 0), c("8", 1), c("8", 2), c("8", 3)]
	check(Rules.analyze(quad).type == T.QUAD, "quad")
	var two := Rules.analyze([c("2", 0)])
	check(Rules.can_beat(Rules.analyze(quad), two), "quad chops 2")
	check(Rules.can_beat(Rules.analyze(ds), two), "3 pairs chop 2")
	check(not Rules.can_beat(Rules.analyze([c("A", 3)]), two), "A < 2")
	check(Rules.can_beat(Rules.analyze([c("5", 3)]), Rules.analyze([c("5", 2)])), "suit order")
	check(not Rules.can_beat(Rules.analyze([c("5", 0), c("5", 1)]), Rules.analyze([c("9", 0)])), "type mismatch")
	var s4 := Rules.analyze([c("3", 0), c("4", 0), c("5", 0), c("6", 0)])
	check(not Rules.can_beat(Rules.analyze([c("9", 0), c("10", 1), c("J", 2)]), s4), "straight length must match")


func _simulate(n: int, tuning: Dictionary) -> void:
	var deck := Rules.new_deck()
	deck.shuffle()
	var hands := []
	for p in n:
		var h := deck.slice(p * 13, p * 13 + 13)
		h.sort()
		hands.append(h)
	var required := 52
	var current := 0
	for p in n:
		if hands[p][0] < required:
			required = hands[p][0]
			current = p
	var last := {}
	var last_player := -1
	var passed := []
	passed.resize(n)
	passed.fill(false)
	var finished := 0
	for _turn in 2000:
		var danger := 99
		for q in n:
			if q != current and hands[q].size() > 0:
				danger = mini(danger, hands[q].size())
		var cards := AI.choose_play(hands[current], last, required, danger, tuning if current == 1 else {})
		if cards.is_empty():
			check(not last.is_empty(), "AI passed while leading")
			passed[current] = true
		else:
			var combo := Rules.analyze(cards)
			check(Rules.can_beat(combo, last), "AI made illegal play %s" % [cards])
			check(required < 0 or cards.has(required), "AI skipped required card")
			for card in cards:
				check(hands[current].has(card), "AI played card it doesn't hold")
				hands[current].erase(card)
			last = combo
			last_player = current
			required = -1
			if hands[current].is_empty():
				finished += 1
				if finished >= n - 1:
					return
		# Advance (mirrors main.gd).
		var i := current
		var moved := false
		for _s in n:
			i = (i + 1) % n
			if i == last_player:
				passed.fill(false)
				last = {}
				last_player = -1
				while hands[i].is_empty():
					i = (i + 1) % n
				current = i
				moved = true
				break
			if hands[i].size() > 0 and not passed[i]:
				current = i
				moved = true
				break
		check(moved, "turn did not advance")
	check(false, "game did not finish")
