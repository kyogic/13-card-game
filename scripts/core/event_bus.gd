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
signal new_story_requested(info: Dictionary)
signal continue_story_requested(info: Dictionary)  # load the saved story
signal date_requested(info: Dictionary)  # {character_id, location, opponent: {...}}
signal date_closed(info: Dictionary)     # {completed: bool}

# --- Dating layer -------------------------------------------------------------
signal talk_choice_made(info: Dictionary)   # {character_id, quality}
signal trivia_answered(info: Dictionary)    # {character_id, question, correct}
signal gift_given(info: Dictionary)         # {character_id, gift_id, category}
signal affection_changed(info: Dictionary)  # {character_id, delta, value, reason}
signal affection_stage_reached(info: Dictionary)  # {character_id, stage, unlocks}
signal time_advanced(info: Dictionary)      # {slot_index, time_left}
signal day_ended(info: Dictionary)          # {day, final}: final = the last day of the story
signal game_saved(info: Dictionary)         # {path}
signal game_loaded(info: Dictionary)        # {path}

## Card events the debug panel can fire by hand.
const CARD_EVENTS := ["match_started", "match_ended", "hand_won", "hand_lost", "bomb_played",
	"two_saved", "powerup_used"]


## Emits `event` by name. Used for generic dispatch (debug panel, tests).
func fire(event: String, info: Dictionary = {}) -> void:
	assert(has_signal(event), "Unknown event: %s" % event)
	emit_signal(event, info)
