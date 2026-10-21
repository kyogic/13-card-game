# Tiến Lên (Thirteen): Godot prototype

A playable prototype of the Vietnamese card game **Tiến Lên** built with **Godot 4.3**. It uses no art assets: cards are drawn in code.

## Modes
- **4 Players:** you against 3 CPU opponents, full 52-card deck, 13 cards each.
- **2 Players:** you against 1 CPU, half the deck. 26 cards are dealt (13 each) and the rest stay out of play.

## Menus
- **Story Mode:** the dating sim. Choose **New Story** or **Continue Story**.
- **Quickplay:** straight into a card game, either 4 players against 3 CPUs, or 2 players against Jessica (best of 3, earns coins).
- **Wardrobe**, plus the power-up and music toggles, are on the main page. Power-ups apply in both modes.

## Story Mode (dating layer)
The story lasts **3 days**, each with Morning, Afternoon, Evening and Night.
- **Carried between days:** affection, unlocks and answered trivia.
- **Each new morning:** a few more gifts (`daily_gifts` in `data/story.json`).
- **After each day:** a summary of that day, with a **Start Day N** button.
- **After Day 3:** the summary also shows totals for the whole story.

There are two girls to pursue: **Jessica** and **Arisa**. In every part of the day they're in different places, so going to see one means missing the other:

| Slot | Jessica | Arisa |
|---|---|---|
| Morning | Phở Spot | Muay Thai Gym |
| Afternoon | Boba Shop (Jessica: Curious, 20) | Thai Tea Shop (Arisa: Friendly, 20) |
| Evening | Night Market (Jessica: Catching feelings, 70) | Breakfast Café (Arisa: Trusting, 70), her "breakfast" before a night shift |
| Night | Phở Spot (late-night run) | 7-Eleven (her 3am break; not a date spot) |

**Saving:**
- The day autosaves at the start of each new slot and when the day ends. The calendar also has a **Save game** button.
- **Continue Story** loads the save. If you saved at the end of a day, it opens that day's summary.
- The save is one slot in `user://dating_save.json`, holding the whole story. Coins and outfits are saved separately, in `user://save.cfg`.
- Coins were reset to 0 once with this update; unlocked outfits were kept.

You have one day with four parts: Morning, Afternoon, Evening and Night. In each part, pick where to go.
- **If Jessica is there,** you can:
  - **Talk:** small talk that hints at her trivia answers. Your reply is good, neutral or bad.
  - **Quiz me:** she asks one of her trivia questions.
  - **Give gift:** from your starting gifts.
  - **Ask on a date:** plays a best-of-3 Tiến Lên match against her. She reacts to card events in a speech bubble.
- **If she isn't there,** you lose a little time.

Some places stay locked until her affection reaches a stage. When the day ends, a summary shows:
- affection gained
- the stage reached
- unlocks earned
- your match record

**Debug panel:** press **F1** (or `` ` ``) to:
- set her affection
- jump to the next time slot
- fire card events by hand

**Architecture.** The card game and the dating layer never call each other. They only send and receive signals through the `EventBus` autoload:
- The card game emits:
  - `match_started` and `match_ended` (with the winner)
  - `hand_won` and `hand_lost`: a "hand" is a round
  - `bomb_played` (with who played it)
  - `two_saved`: once per game, when you win a round still holding a 2 you were dealt, with 3 or fewer cards left
  - `powerup_used` (with who used it and which one)
- The dating layer asks for a date with `date_requested`. It gets control back with `date_closed`.

| Piece | File |
|---|---|
| Event bus | `scripts/core/event_bus.gd` |
| Tuning numbers (affection, time costs, thresholds, UI timings, which card event triggers which line) | `data/config/tuning.json`, read by `scripts/core/config.gd` |
| Day state, in memory only, with `to_dict`/`from_dict` for a future save | `scripts/core/game_state.gd` |
| Character registry | `scripts/dating/character_db.gd`, which loads every `data/characters/*.json` and optional `data/talk/<id>.json` |
| Affection and stage unlocks | `scripts/dating/affection_system.gd` |
| Day, slots, schedule, time costs, locks | `scripts/dating/calendar.gd`, using `data/story.json` and `data/schedule.json` |
| Screens | `scripts/ui/`: calendar, conversation, dialogue box (typewriter + subtitles), reaction bubble, affection meter, summary, debug panel |
| Ties the screens together | `scripts/dating/dating_layer.gd` |
| Root scene (card game with the dating layer on top) | `scenes/app.tscn` |

**Adding a character:**
1. Add `data/characters/<id>.json` in the same shape as `jessica.json`.
2. Optionally add `data/talk/<id>.json` with small-talk exchanges.
3. Add a schedule entry in `data/schedule.json`.

No code changes are needed; the tests load an extra character from data to check this.

**Trivia and soft facts:**
- Trivia questions can have a `min_affection`. Quiz me only asks the questions she's ready for. For Jessica, 18 of 26 are available at the start.
- `soft_facts` are personal stories she shares once affection is high enough. When one is available, Talk plays it first.
- After the small-talk exchanges run out, Talk moves on to the one-line `facts` in `data/talk/<id>.json`.
- Every quiz answer is taught somewhere: in an exchange, a fact or a soft fact. A test checks this.

Dialogue lines can be a plain string or `{"text": ..., "translation": ...}`. The translation is shown as an English subtitle when the conversation screen's subtitles toggle is on.

### Arisa
Her profile is `data/characters/arisa.json`, and her small talk is in `data/talk/arisa.json`.
- **Who she is:** Arisa Wongsakul ("Ari"), a night-shift ER nurse.
- **Card AI:** defensive. She hoards 2s and bombs and passes a lot.
- **Signature power-up:** **Second Wind**, once per game. After she's passed and you think you've won the round, she jumps back in with a play that beats yours.
- **Nickname:** she calls you "phi" once that's unlocked at Trusting (70).
- **Subtitles:** her Thai phrases (mai pen rai, jing jing, chai yo, ...) have English subtitles.
- **Art:** `assets/characters/arisa/`. The outfits are Classic (free), Glam, Street, Muay Thai and School. Originals are in `source/`, named `arisa_<outfit>.png`.

### Jessica
Her profile is `data/characters/jessica.json`.
- **Card AI:** comes from `card_ai.tuning`: aggressive, spends her 2s early, loves straights.
- **Signature power-up:** Lead Steal, once per game, after losing a round she thought she'd win.
- **Schedule:** see the table above.
- **Wardrobe:** her outfits are Classic (free), Street, Pajamas, Maid and Lace.
  - Coins come from 2-player matches on the main menu and are saved in `user://save.cfg`.
  - **On a date** she shows up in a random outfit you've unlocked, kept for the whole match.
  - **Quick 2-player matches** from the menu use the outfit selected in the Wardrobe.
  - Smile was removed from the lineup. A save that had unlocked it gets its coin back.

### Wardrobe
- All outfits are listed in `data/outfits.json`, one list per girl. Each girl's first outfit is free; the rest cost 1 coin.
- The Wardrobe has a tab per girl, and each girl remembers her own selected outfit.
- On a date, each girl wears a random outfit from the ones you've unlocked for her.

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
3. Add an entry under her id in `data/outfits.json`.

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
| `scripts/main.gd` | Card game: menu, table UI, turn flow, matches, power-ups; emits card events |
| `scripts/character.gd` | Reads a character profile JSON (dialogue, stages, gifts, trivia, AI tuning) |
| `scripts/core/`, `scripts/dating/`, `scripts/ui/` | Dating layer (see Story Mode above) |
| `scripts/core/save_system.gd` | Save/load of the day (`SaveGame` autoload) |
| `tests/dating_test.gd` | Dating layer: affection, dialogue, calendar, summary, debug panel, a second character, and a real date |
| `tests/sim_test.gd` | Headless rule tests plus 300 CPU-only games |
| `tests/ui_test.gd` | Plays full games through the real scene, driving the human seat with Hint |

Run the tests with:
```
godot --headless --path . --script res://tests/sim_test.gd
godot --headless --path . --script res://tests/ui_test.gd
godot --headless --path . --script res://tests/dating_test.gd
```

## Not in the prototype yet
Instant wins (e.g. four 2s dealt), chopping out of turn after passing, multi-game scoring, the "winner of the last game leads" rule, sound, and animations.
