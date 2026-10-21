extends Node
## Global event bus. The card game and the dating layer only talk through these
## signals. Every payload is a Dictionary; card events carry "opponent_id".

# --- Card game -> anyone ------------------------------------------------------
signal match_started(info: Dictionary)   # {opponent_id, date}
signal match_ended(info: Dictionary)     # {opponent_id, winner: "player"|"opponent", score: [you, them], date}
signal hand_won(info: Dictionary)        # player won a round (everyone else passed, or the final play)
signal hand_lost(info: Dictionary)       # opponent won a round
signal bomb_played(info: Dictionary)     # {by: "player"|"opponent"}
signal two_saved(info: Dictionary)       # player won a round still holding a dealt 2, late in the game
signal powerup_used(info: Dictionary)    # {by: "player"|"opponent", id, first: bool}

# --- Navigation between the layers --------------------------------------------
signal story_menu_requested(info: Dictionary)  # main menu "Story Mode": pick a save slot
signal new_story_requested(info: Dictionary)   # {slot}; no slot = the active one (or 1)
signal continue_story_requested(info: Dictionary)  # {slot}; no slot = the active one
signal wardrobe_requested(info: Dictionary)  # main menu: browse/wear owned outfits
signal date_requested(info: Dictionary)  # {character_id, location, opponent: {...}, background: path or ""}
signal date_closed(info: Dictionary)     # {completed: bool}

# --- Dating layer -------------------------------------------------------------
signal talk_choice_made(info: Dictionary)   # {character_id, quality}
signal trivia_answered(info: Dictionary)    # {character_id, question, correct}
signal compatibility_answered(info: Dictionary)  # {character_id, question, fit: "good"|"neutral"|"bad"}
signal gift_given(info: Dictionary)         # {character_id, gift_id, category}
signal conversation_opened(info: Dictionary)  # {character_id, location}
signal fact_learned(info: Dictionary)       # {character_id, facts: [trivia ids], source: "talk"|"quiz"}
signal affection_changed(info: Dictionary)  # {character_id, delta, value, reason}
signal affection_stage_reached(info: Dictionary)  # {character_id, stage, unlocks}
signal time_advanced(info: Dictionary)      # {slot_index, time_left}
signal day_ended(info: Dictionary)          # {day, final}: final = the last day of the story
signal game_saved(info: Dictionary)         # {path}
signal money_changed(info: Dictionary)      # {delta, value, reason}
signal item_bought(info: Dictionary)        # {item_id, price}
signal game_loaded(info: Dictionary)        # {path}

## Card events the debug panel can fire by hand.
const CARD_EVENTS := ["match_started", "match_ended", "hand_won", "hand_lost", "bomb_played",
	"two_saved", "powerup_used"]


## Emits `event` by name. Used for generic dispatch (debug panel, tests).
func fire(event: String, info: Dictionary = {}) -> void:
	assert(has_signal(event), "Unknown event: %s" % event)
	emit_signal(event, info)
