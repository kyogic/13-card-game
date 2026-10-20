# Tiến Lên (Thirteen): Godot prototype

A playable prototype of the Vietnamese card game **Tiến Lên** built with **Godot 4.3**. It uses no art assets: cards are drawn in code.

## Modes
- **4 Players:** you against 3 CPU opponents, full 52-card deck, 13 cards each.
- **2 Players:** you against 1 CPU, half the deck. 26 cards are dealt (13 each) and the rest stay out of play.

## Running
1. Install Godot 4.3 or later (standard build, not .NET).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (Run Project).

## How to play
- Click cards to select them, then press **Play**. Press **Pass** to sit out the round. **Hint** selects a suggested play.
- Rank order runs 3 (low) … 10 J Q K A 2 (high). Suit order runs ♠ < ♣ < ♦ < ♥.
- Combinations: single, pair, triple, four of a kind, straight (3+ consecutive ranks, no 2s), and double sequence (3+ consecutive pairs, no 2s).
- To beat the table you must play the same kind and size with a higher top card.
- Once you pass, you are out until the round resets. When everyone else has passed, the last player to play leads a new round with anything.
- The lowest card dealt (3♠ in the 4-player game) starts the game, and the opening play must include it.
- Bombs ("chặt"):
  - 3 consecutive pairs or four of a kind beat a single 2.
  - Four of a kind beats a pair of 2s and 3 consecutive pairs.
  - 4+ consecutive pairs beat a pair of 2s, four of a kind, and shorter double sequences.
- Play continues until only one player has cards left. Finishing order is shown at the end.

## Code layout
| File | Purpose |
|---|---|
| `scripts/rules.gd` | Card encoding, combination detection, beat rules, and combo enumeration |
| `scripts/ai.gd` | CPU strategy: cheapest legal play; saves 2s and bombs unless an opponent is close to going out |
| `scripts/card_view.gd` | Card drawn in code; clickable |
| `scripts/main.gd` | Menu, table UI, and turn flow |
| `tests/sim_test.gd` | Headless rule tests plus 300 CPU-only games |
| `tests/ui_test.gd` | Plays full games through the real scene, driving the human seat with Hint |

Run the tests with:
```
godot --headless --path . --script res://tests/sim_test.gd
godot --headless --path . --script res://tests/ui_test.gd
```

## Not in the prototype yet
Instant wins (e.g. four 2s dealt), chopping out of turn after passing, multi-game scoring, the "winner of the last game leads" rule, sound, and animations.
