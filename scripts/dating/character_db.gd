extends Node
## Registry of every character: data/characters/<id>.json plus optional small talk in
## data/talk/<id>.json. Adding a character means adding files, not code.

const Character := preload("res://scripts/character.gd")
const CHAR_DIR := "res://data/characters/"
const TALK_DIR := "res://data/talk/"

var profiles := {}             # id -> Character
var talks := {}                # id -> Array of small-talk exchanges


func _init() -> void:
	for file in DirAccess.get_files_at(CHAR_DIR):
		if not file.ends_with(".json"):
			continue
		var profile = Character.load_profile(CHAR_DIR + file)
		if profile.id() == "":
			continue
		profiles[profile.id()] = profile
		var talk_path: String = TALK_DIR + profile.id() + ".json"
		if FileAccess.file_exists(talk_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(talk_path))
			if parsed is Dictionary:
				talks[profile.id()] = parsed.get("exchanges", [])


func ids() -> Array:
	return profiles.keys()


func profile(id: String):
	return profiles.get(id)


func talk(id: String) -> Array:
	return talks.get(id, [])
