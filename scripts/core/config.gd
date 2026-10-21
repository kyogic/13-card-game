extends Node
## Every tuning number (affection gains, time costs, thresholds, UI timings) lives in
## data/config/tuning.json. Read values with Config.value("affection.match_won").

const PATH := "res://data/config/tuning.json"

var data: Dictionary = {}


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("Could not read %s" % PATH)


## Dotted lookup, e.g. value("time.talk", 1). Numbers come back as JSON floats;
## use int_value() for whole numbers.
func value(path: String, default = null):
	var node = data
	for key in path.split("."):
		if not (node is Dictionary and node.has(key)):
			return default
		node = node[key]
	return node


func int_value(path: String, default := 0) -> int:
	return int(value(path, default))
