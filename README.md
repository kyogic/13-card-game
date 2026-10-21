# Tiến Lên (Thirteen): Godot prototype

A playable prototype of the Vietnamese card game **Tiến Lên** built with **Godot 4.3**. It uses no art assets: cards are drawn in code.

## Modes
- **4 Players:** you against 3 CPU opponents, full 52-card deck, 13 cards each.
- **2 Players:** you against 1 CPU, half the deck. 26 cards are dealt (13 each) and the rest stay out of play.

## 2-player matches, coins and the Wardrobe
- In 2-player mode you play against **Jessica**. The game sits in its own framed table on the right, and Jessica stands outside it on the left, full-length, so her whole outfit is visible. Her name is shown beneath her.
- 2-player games are a **best-of-3 match**. Whoever won the previous game leads the next one with any play.
- Winning a match earns **1 coin**.
- In **Jessica's Wardrobe** (main menu), Classic is free. Spend 1 coin to unlock each of her other outfits: Smile, Street, Pajamas, Maid and Lace. Unlocked outfits can be switched between for free.
- Coins, unlocked outfits and the selected outfit are saved in `user://save.cfg`.
- Saves from before she was named Jessica are migrated automatically.

### Character art layout
```
assets/characters/jessica/
  default.png smile.png street.png pajamas.png maid.png lace.png   <- game-ready (trimmed, 1000px tall)
  source/                                                          <- original uploads (ignored by Godot via .gdignore)
    jessica_default.png jessica_smile.png jessica_street.png ...
```
To add an outfit:
1. Put the original in `source/` as `jessica_<name>.png`.
2. Make a trimmed copy at `jessica/<name>.png`.
3. Add an entry to `OUTFITS` in `scripts/main.gd`.

## Power-ups
Each power-up can be switched on or off with a toggle on the main menu. In a game you can use each enabled power-up once, up to **2 power-ups in total**. They appear in the top-right panel. Power-ups are for you only; the CPUs don't use them.

| Power-up | Effect | When |
|---|---|---|
| **Suit Up** | Select one card to turn it into the ♥ of the same rank, the highest suit. This can give you a duplicate of a card an opponent holds. | Your turn |
| **Wild Card** | Select one card to make it wild; it is marked **WILD** in your hand. When you play it, it becomes whichever card makes your selection the strongest legal play. For example, 5♠ 6♠ + wild plays as a 5-6-7♥ straight, and J♠ + wild plays as a pair of Jacks. A wild card played alone becomes the strongest single that beats the table. The status line shows what the wild card will become before you press Play. | Your turn |
| **Lucky Draw** | Select one card to discard. You draw a random card from the dead pile (undealt cards, cleared tricks, and discards). | Your turn, once the dead pile isn't empty |
| **Lead Steal** | Arms the power-up. You lead the next new round, even if someone else won the round before it. | Any time |
| **Hand Lock** | The opponent you pick is locked out for the rest of the round. If they win that round, the lead passes to the next player instead of them. | Your turn |

Suit Up, Lucky Draw and Wild Card can't be used on the card you're required to open the game with, or on a card that is already wild.

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
- Play continues until only one player has cards left. Finishing order and total game length are shown at the end.
- A game clock in the top-right corner shows how long the current game has been running.
- Background music (`audio/cardgame_song.mp3`) loops the whole time. Turn it off with the **Background music** toggle on the main menu.

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
