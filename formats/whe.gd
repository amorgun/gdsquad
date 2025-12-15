class_name Whe

enum ClauseType {
	FLOAT = 0,
	BOOLEAN = 1,
	STRING = 2,
}

enum ClauseComparisonType {
	EQUAL = 0,
	NOT_EQUAL = 1,
	LESS = 2,
	LESS_OR_EQUAL = 3,
	GREATER = 4,
	GREATER_OR_EQUAL = 5,
}

enum ModifierType {
	ABSOLUTE_TIME = 0,
	SPEED_SCALE = 1,
}

static var MotionEventTime: = {
	-1.: "START",
	PackedByteArray([0xff, 0xff, 0x7f, 0x7f]).decode_float(0): "END",
}

static var MotionEventTime2Name: = {
	"START": -1,
	"END": PackedByteArray([0xff, 0xff, 0x7f, 0x7f]).decode_float(0),
}

enum MotionType {
	NON_LOOPING = 0,
	LOOPING = 1,
	HOLD_END = 2,
}

enum ActionCompareType {
	IF = 0,
	ELSE_IF = 1,
	ELSE = 2,
	NONE = 3,
}

enum SelectedUiDisplayType {
	CIRCLE = 0,
	RECTANGLE = 1,
}

class Parser:
	func parse(data: PackedByteArray) -> Dictionary:
		var reader := ChunkReader.from_bytes(data)
		reader.skip_chunky()
		var result := {}
		var current_chunk := reader.read_header()
		if current_chunk.typeid == "DATAFBIF":
			var tool_name := reader.read_str()
			reader.read_32()  # 0
			result["burn_info"] = {
				"tool_name": tool_name,
				"username": reader.read_str(),
				"date": reader.read_str(),
			}
			current_chunk = reader.read_header("FOLDREBP")
		else:
			if not current_chunk.is_valid_typeid("FOLDREBP"): return {}
		current_chunk = reader.read_header()
		var xrefed_animations: Dictionary[String, Variant] = {}
		while current_chunk != null:
			match current_chunk.typeid:
				"FOLDEVCT": result["events"] = _parse_list(reader, current_chunk, _parse_event)
				"FOLDCLST": result["clauses"] = _parse_list(reader, current_chunk, _parse_clause)
				"FOLDCONL": result["conditions"] = _parse_list(reader, current_chunk, _parse_condition)
				"FOLDMODL": result["modifiers"] = _parse_list(reader, current_chunk, _parse_modifier)
				"FOLDMTRE": result["motions"] = _parse_list(reader, current_chunk, _parse_motion)
				"DATAACTS": result["actions"] = _parse_actions(reader)
				"DATASEUI": result["selected_ui"] = _parse_selected_ui(reader)
				"FOLDANIM": 
					var anim := _parse_xrefed_animation(reader)
					xrefed_animations[current_chunk.name] = anim
				_:
					reader.skip(current_chunk.size)
					GsqLogger.debug('Unexpected chunk typeid: "%s"' % current_chunk.typeid)
			current_chunk = reader.read_header()
		if len(xrefed_animations):
			result["xrefed_animations"] = xrefed_animations
		return result

	func parse_file(file: ModSet.FilePath, decode_hashes: bool = true) -> Dictionary:
		return parse(file.read_bytes())

	func _parse_list(reader: ChunkReader, header: ChunkReader.ChunkHeader, parse_fn: Callable) -> Dictionary[String, Dictionary]:
		var folder_reader := reader.read_folder(header)
		var result: Dictionary[String, Dictionary] = {}
		var current_chunk := folder_reader.read_header()
		while current_chunk != null:
			result[current_chunk.name] = parse_fn.call(folder_reader, current_chunk)
			current_chunk = folder_reader.read_header()
		return result

	func _parse_event(reader: ChunkReader, header: ChunkReader.ChunkHeader) -> Dictionary[String, Variant]:
		if not header.is_valid_typeid("DATAEVNT"): return {}
		var num_props := reader.read_u32()
		var properties: Array[Dictionary] = []
		for i in num_props:
			properties.append({
				"param": reader.read_str(),
				"value": reader.read_str(),
			})
		return {"properties": properties}

	func _parse_clause(reader: ChunkReader, header: ChunkReader.ChunkHeader) -> Dictionary[String, Variant]:
		if not header.is_valid_typeid("DATACLAS"): return {}
		var type := reader.read_u32()
		var variable := reader.read_str()
		var comparison := reader.read_u32()
		var value
		var default
		match type:
			ClauseType.FLOAT:
				value = reader.read_float() * 100
				default = reader.read_float() * 100
			ClauseType.BOOLEAN:
				value = bool(reader.read_u8())
				default = bool(reader.read_u8())
			ClauseType.STRING:
				value = reader.read_str()
				default = reader.read_str()
		return {
			"type": ClauseType.find_key(type),
			"variable": variable,
			"comparison": ClauseComparisonType.find_key(comparison),
			"value": value,
			"default": default,
		}

	func _parse_condition(reader: ChunkReader, header: ChunkReader.ChunkHeader) -> Dictionary[String, Variant]:
		if not header.is_valid_typeid("DATACOND"): return {}
		var num_clauses := reader.read_u32()
		var clauses: PackedStringArray = []
		for i in num_clauses:
			clauses.append(reader.read_str())
		return {"clauses": clauses}

	func _parse_modifier(reader: ChunkReader, header: ChunkReader.ChunkHeader) -> Dictionary[String, Variant]:
		if not header.is_valid_typeid("DATAMODF"): return {}
		return {
			"variable": reader.read_str(),
			"type": ModifierType.find_key(reader.read_u32()),
			"ref_value": reader.read_float() * 100,
			"default": reader.read_float() * 100,
		}

	func _parse_motion(reader: ChunkReader, header: ChunkReader.ChunkHeader) -> Dictionary[String, Variant]:
		if not header.is_valid_typeid("DATAMTON"): return {}
		var num_animations := reader.read_u32()
		var animations: PackedStringArray = []
		for i in num_animations:
			animations.append(reader.read_str())
		var num_random_motions := reader.read_u32()
		var random_motions: Array[Dictionary] = []
		for i in range(num_random_motions):
			random_motions.append({
				"name": reader.read_str(),
				"weight": reader.read_float(),
			})
		var randomize_each_loop := bool(reader.read_u8())
		var num_events := reader.read_u32()
		var events: Array[Dictionary] = []
		for i in num_events:
			var name := reader.read_str()
			var time := reader.read_float()
			events.append({
				"name": name,
				"time": Whe.MotionEventTime.get(time, time),
			})
		var type := MotionType.find_key(reader.read_u32())
		var start_delay: Dictionary[String, float] = {"min": reader.read_float(), "max": reader.read_float()}
		var loop_delay: Dictionary[String, float] = {"min": reader.read_float(), "max": reader.read_float()}
		var transition_out := reader.read_float()
		var inset: Dictionary[String, float] = {"min": reader.read_float(), "max": reader.read_float()}
		var exit_delay: Dictionary[String, float] = {"min": reader.read_float(), "max": reader.read_float()}
		var ignore_exit_delay := bool(reader.read_u8())
		var ignore_transitions := bool(reader.read_u8())
		var has_modifier := bool(reader.read_u8())
		var modifier := reader.read_str() if has_modifier else null
		return {
			"animations": animations,
			"random_motions": random_motions,
			"randomize_each_loop": randomize_each_loop,
			"events": events,
			"type": type,
			"start_delay": start_delay,
			"loop_delay": loop_delay,
			"exit_delay": exit_delay,
			"inset": inset,
			"transition_out": transition_out,
			"ignore_exit_delay": ignore_exit_delay,
			"ignore_transitions": ignore_transitions,
			"modifier": modifier,
		}

	func _parse_actions(reader: ChunkReader) -> Dictionary[String, Variant]:
		var result: Dictionary[String, Variant] = {}
		var num_actions := reader.read_u32()
		for i in num_actions:
			var action_name := reader.read_str()
			var num_motions := reader.read_u32()
			var motions: Array[Dictionary] = []
			for j in num_motions:
				var motion_name := reader.read_str()
				var compare_type := reader.read_u32()
				var condition_name := reader.read_str() if compare_type == ActionCompareType.IF or  compare_type == ActionCompareType.ELSE_IF else null
				motions.append({
					"motion": motion_name,
					"compare_type": ActionCompareType.find_key(compare_type),
					"condition": condition_name,
				})
			var num_subactions := reader.read_u32()
			var subactions: Array[Dictionary] = []
			for j in num_subactions:
				var subaction_name := reader.read_str()
				var compare_type := reader.read_u32()
				var condition_name := reader.read_str() if compare_type == ActionCompareType.IF or  compare_type == ActionCompareType.ELSE_IF else null
				subactions.append({
					"action": subaction_name,
					"compare_type": ActionCompareType.find_key(compare_type),
					"condition": condition_name,
				})
			result[action_name] = {
				"motions": motions,
				"subactions": subactions,
			}
		return result

	func _parse_selected_ui(reader: ChunkReader) -> Dictionary[String, Variant]:
		var result: Dictionary[String, Variant] = {
			"display_type": SelectedUiDisplayType.find_key(reader.read_u32()),
			"scale": {"x": reader.read_float(), "z": reader.read_float()},
			"offset": {"x": reader.read_float(), "z": reader.read_float()},
			"volume": {"x": reader.read_float(), "y": reader.read_float(), "z": reader.read_float()},
			"volume_scale": {"x": reader.read_float(), "y": reader.read_float(), "z": reader.read_float()},
			"matrix": [],
		}
		for i in 9:
			result["matrix"].append(reader.read_float())
		return result

	func _parse_xrefed_animation(reader: ChunkReader) -> Dictionary[String, Variant]:
		reader.read_header("DATAXREF")
		var src_path := reader.read_str()
		var src_name := reader.read_str()
		var dataanbv := reader.read_header('DATAANBV')
		reader.skip(dataanbv.size)
		return {
			"source_path": src_path,
			"source_name": src_name,
		}

class Writer:
	func write_file(data: Dictionary, path: String) -> Error:
		var writer := ChunkWriter.open(path)

		writer.write_chunky()
		
		writer.start_chunk("DATAFBIF", 1, "FileBurnInfo")
		writer.write_str('https://github.com/amorgun/dow_mod_editor')
		writer.write_u32(0)
		var burn_info = data.get("burn_info", {})
		writer.write_str(burn_info.get("username", "") if burn_info is Dictionary else "")
		var datetime := Time.get_datetime_dict_from_system(true)
		writer.write_str(_format_timestr(datetime))
		writer.end_chunk("DATAFBIF")

		writer.start_chunk("FOLDREBP", 4)
		var errors: PackedStringArray = []

		var xrefed_animations = data.get("xrefed_animations", {})
		for anim_name in xrefed_animations:
			var xref_data = xrefed_animations[anim_name]
			if xref_data is not Dictionary:
				continue
			var source_path := str(xref_data.get("source_path", ""))
			if source_path == "":
				errors.append('xrefed animation "%s" has emply source_path' % [anim_name])
				continue
			var source_name := str(xref_data.get("source_name", ""))
			if source_name == "":
				errors.append('xrefed animation "%s" has emply source_name' % [anim_name])
				continue
			writer.start_chunk("FOLDANIM", 3, anim_name)
			writer.start_chunk("DATAXREF", 1)
			writer.write_str(source_path)
			writer.write_str(source_name)
			writer.end_chunk("DATAXREF")
			writer.start_chunk("DATAANBV", 1, anim_name)
			writer.write_padding(24)
			writer.end_chunk("DATAANBV")
			writer.end_chunk("FOLDANIM")

		var get_array := func (data: Dictionary, key: String) -> Array:
			var res = data.get(key, [])
			if res is Dictionary:
				return res.values()
			return res

		writer.start_chunk("FOLDEVCT", 1)
		var events = data.get("events", {})
		var exported_events: Dictionary[String, bool] = {}
		if events is Dictionary:
			for event_name in events:
				var event = events[event_name]
				if event is not Dictionary:
					errors.append('Event "%s": not a table' % [event_name])
					continue
				var properties = get_array.call(event, "properties")
				if properties is not Array:
					errors.append('Event "%s": cannot parse properties' % [event_name])
					continue
				writer.start_chunk("DATAEVNT", 3, event_name)
				writer.write_u32(len(properties))
				for prop in properties:
					var param: String = str(prop.get("param", ""))
					if param.strip_edges() == "":
						errors.append('Event "%s": empty param name' % [event_name])
					writer.write_str(param)
					writer.write_str(str(prop.get("value", "")))
				writer.end_chunk("DATAEVNT")
				exported_events[event_name] = true
		writer.end_chunk("FOLDEVCT")

		writer.start_chunk("FOLDCLST", 1)
		var exported_clauses: Dictionary[String, bool] = {}
		var clauses = data.get("clauses", {})
		if clauses is Dictionary:
			for clause_name in clauses:
				var clause = clauses[clause_name]
				if clause is not Dictionary:
					errors.append('Clause "%s": not a table' % [clause_name])
					continue
				var clause_type_str := str(clause.get("type", ""))
				var clause_type = ClauseType.get(clause_type_str.to_upper(), -1)
				if clause_type == -1:
					errors.append('Clause "%s": unknown type %s' % [clause_name, clause_type_str])
					continue
				var clause_comparison_type_str := str(clause.get("comparison", ""))
				var clause_comparison_type = ClauseComparisonType.get(clause_comparison_type_str.to_upper(), -1)
				if clause_comparison_type == -1:
					errors.append('Clause "%s": unknown comparison type %s' % [clause_name, clause_comparison_type_str])
					continue
				writer.start_chunk("DATACLAS", 2, clause_name)
				writer.write_u32(clause_type)
				writer.write_str(str(clause.get("variable", "")))
				writer.write_u32(clause_comparison_type)
				match clause_type:
					ClauseType.FLOAT:
						writer.write_float(clause.get("value", 0) / 100.)
						writer.write_float(clause.get("default", 0) / 100.)
					ClauseType.BOOLEAN:
						writer.write_u8(bool(clause.get("value", 0)))
						writer.write_u8(bool(clause.get("default", 0)))
					ClauseType.STRING:
						writer.write_str(str(clause.get("value", "")))
						writer.write_str(str(clause.get("default", "")))
				writer.end_chunk("DATACLAS")
				exported_clauses[clause_name] = true
		writer.end_chunk("FOLDCLST")

		writer.start_chunk("FOLDCONL", 1)
		var exported_conditions: Dictionary[String, bool] = {}
		var conditions = data.get("conditions", {})
		if conditions is Dictionary:
			for condition_name in conditions:
				var condition = conditions[condition_name]
				if condition is not Dictionary:
					errors.append('Condition "%s": not a table' % [condition_name])
					continue
				var condition_clauses = get_array.call(condition, "clauses")
				if condition_clauses is not Array:
					errors.append('Condition "%s": cannot parse clauses' % [condition_name])
					continue
				writer.start_chunk("DATACOND", 1, condition_name)
				writer.write_u32(len(condition_clauses))
				for clause_name in condition_clauses:
					clause_name = str(clause_name)
					if clause_name not in exported_clauses:
						errors.append('Condition "%s": clause %s not found' % [condition_name, clause_name])
					writer.write_str(clause_name)
				writer.end_chunk("DATACOND")
				exported_conditions[condition_name] = true
		writer.end_chunk("FOLDCONL")

		writer.start_chunk("FOLDMODL", 1)
		var modifiers = data.get("modifiers", {})
		var exported_modifiers: Dictionary[String, bool] = {}
		if modifiers is Dictionary:
			for modifier_name in modifiers:
				var modifier = modifiers[modifier_name]
				if modifier is not Dictionary:
					errors.append('Modifier "%s": not a table' % [modifier_name])
					continue
				var modifier_type_str := str(modifier.get("type", "")	)
				var modifier_type = ModifierType.get(modifier_type_str.to_upper(), -1)
				if modifier_type == -1:
					errors.append('Modifier "%s": unknown type %s' % [modifier_name, modifier_type_str])
					continue
				writer.start_chunk("DATAMODF", 1, modifier_name)
				writer.write_str(str(modifier.get("variable", "")))
				writer.write_u32(modifier_type)
				writer.write_float(modifier.get("ref_value", 0) / 100.)
				writer.write_float(modifier.get("default", 0) / 100.)
				writer.end_chunk("DATAMODF")
				exported_modifiers[modifier_name] = true
		writer.end_chunk("FOLDMODL")

		writer.start_chunk("FOLDMTRE", 3)
		var motions = data.get("motions", {})
		var exported_motions: Dictionary[String, Dictionary] = {}
		if motions is Dictionary:
			var motion_graph: Dictionary[String, PackedStringArray] = {}
			for motion_name in motions:
				var motion = motions[motion_name]
				if motion is not Dictionary:
					errors.append('Motion "%s": not a table' % [motion_name])
					continue
				var motion_type_str := str(motion.get("type", ""))
				var motion_type = MotionType.get(motion_type_str.to_upper(), -1)
				if motion_type == -1:
					errors.append('Motion "%s": unknown type %s' % [motion_name, motion_type_str])
					continue
				var animations = get_array.call(motion, "animations")	
				if animations is not Array:
					errors.append('Motion "%s": cannot parse animations' % [motion_name])
					animations = []
				var random_motions_raw = get_array.call(motion, "random_motions")	
				if random_motions_raw is not Array:
					errors.append('Motion "%s": cannot parse random_motions' % [motion_name])
					random_motions_raw = []
				var random_motions: Array[Dictionary] = []
				for m in random_motions_raw:
					if m is not Dictionary:
						continue
					random_motions.append(m)
				if len(animations) > 0 and len(random_motions) > 0:
					errors.append('Motion "%s": cannot have both animations and random_motions' % [motion_name])
				var events_raw = get_array.call(motion, "events")
				if events_raw is not Array:
					errors.append('Motion "%s": cannot parse events' % [motion_name])
					events_raw = []
				var motion_events: Array[Dictionary] = []
				for e in events_raw:
					if e is not Dictionary:
						continue
					var time_str = e.get("time", -1)
					if time_str is String:
						if time_str not in Whe.MotionEventTime2Name:
							errors.append('Motion "%s": cannot parse time %s' % [motion_name, time_str])
							continue
						e = e.duplicate()
						e["time"] = Whe.MotionEventTime2Name[time_str]
					var event_name = e.get("name", "")
					if event_name == "" or event_name == null:
						errors.append('Motion "%s": event missing a name' % [motion_name])
						continue
					event_name = str(event_name)
					if event_name not in exported_events:
						errors.append('Motion "%s": unknown event %s' % [motion_name, event_name])
					motion_events.append(e)
				var child_motions := motion_graph.get_or_add(motion_name, PackedStringArray())
				for m in random_motions:
					child_motions.append(str(m.get("name", "")))
				exported_motions[motion_name] = {
					"animations": animations,
					"random_motions": random_motions,
					"events": motion_events,
					"type": motion_type,
					"motion": motion,
				}
			for motion_name in GsqGraphUtils.toporder(motion_graph):
				var motion_data = exported_motions[motion_name]
				writer.start_chunk("DATAMTON", 4, motion_name)
				var animations: Array = motion_data["animations"]
				writer.write_u32(len(animations))
				for animation in animations:
					writer.write_str(str(animation))
				var random_motions: Array = motion_data["random_motions"]
				writer.write_u32(len(random_motions))
				for rm in random_motions:
					writer.write_str(str(rm.get("name", "")))
					writer.write_float(rm.get("weight", 0))
				var motion: Dictionary = motion_data["motion"]
				writer.write_u8(bool(motion.get("randomize_each_loop", false)))
				var motion_events: Array = motion_data["events"]
				writer.write_u32(len(motion_events))
				for motion_event in motion_events:
					writer.write_str(str(motion_event.get("name", "")))
					writer.write_float(motion_event.get("time", 0))
				writer.write_u32(motion_data["type"])
				
				var write_min_max := func (key: String):
					var val = motion.get("key", {})
					if val is not Dictionary:
						errors.append('Motion "%s": %s is not a table' % [motion_name, key])
						writer.write_float(0)
						writer.write_float(0)
						return
					writer.write_float(val.get("min", 0))
					writer.write_float(val.get("max", 0))

				write_min_max.call("start_delay")
				write_min_max.call("loop_delay")
				writer.write_float(motion.get("transition_out", 0))
				write_min_max.call("inset")
				write_min_max.call("exit_delay")
				writer.write_u8(bool(motion.get("ignore_exit_delay", false)))
				writer.write_u8(bool(motion.get("ignore_transitions", false)))
				var modifier_val = motion.get("modifier", "")
				if modifier_val != "" and modifier_val != null:
					writer.write_u8(1)
					modifier_val = str(modifier_val)
					if modifier_val not in exported_modifiers:
						errors.append('Motion "%s": unknown modifier %s' % [motion_name, modifier_val])
					writer.write_str(modifier_val)
				else:
					writer.write_u8(0)
				writer.end_chunk("DATAMTON")
		writer.end_chunk("FOLDMTRE")
#
		writer.start_chunk("DATAACTS", 1)
		var actions = data.get("actions", {})
		if actions is Dictionary:
			var action_graph: Dictionary[String, PackedStringArray] = {}
			var exported_actions: Dictionary[String, Dictionary] = {}
			for action_name in actions:
				var action = actions[action_name]
				if action is not Dictionary:
					errors.append('Action "%s": not a table' % [action_name])
					continue
				var item := {"name": action_name, "motions": [], "subactions": []}
				var action_motions = get_array.call(action, "motions")
				for motion in action_motions:
					if motion is not Dictionary:
						errors.append('Action "%s": motion is not a table' % [action_name])
						continue
					var motion_name = motion.get("motion", "")
					if motion_name == "" or motion_name == null:
						errors.append('Action "%s": motion missing a name' % [action_name])
						continue
					motion_name = str(motion_name)
					if motion_name not in exported_motions:
						errors.append('Action "%s": unknown motion %s' % [action_name, motion_name])
					var compare_type_str := str(motion.get("compare_type", ""))
					var compare_type = ActionCompareType.get(compare_type_str.to_upper(), -1)
					if compare_type == -1:
						errors.append('Action "%s": motion %s has unknown type %s' % [action_name, motion_name, compare_type_str])
						continue
					var motion_data := {"name": str(motion_name), "compare_type": compare_type}
					if compare_type == ActionCompareType.IF or compare_type == ActionCompareType.ELSE_IF:
						var condition_name = motion.get("condition", "")
						if condition_name == null or condition_name == "":
							errors.append('Action "%s": motion %s missing a condition name' % [action_name, motion_name])
							continue
						condition_name = str(condition_name)
						if condition_name not in exported_conditions:
							errors.append('Action "%s": unknown condition %s for motion %s' % [action_name, condition_name, motion_name])
						motion_data["condition_name"] = condition_name
					item["motions"].append(motion_data)
				var child_actions := action_graph.get_or_add(action_name, PackedStringArray())
				var subactions = get_array.call(action, "subactions")
				for subaction in subactions:
					if subaction is not Dictionary:
						errors.append('Action "%s": motion is not a table' % [action_name])
						continue
					var subaction_name = subaction.get("action", "")  # TODO validate
					if subaction_name == "" or subaction_name == null:
						errors.append('Action "%s": subaction missing a name' % [action_name])
						continue
					var compare_type_str := str(subaction.get("compare_type", ""))
					var compare_type = ActionCompareType.get(compare_type_str.to_upper(), -1)
					if compare_type == -1:
						errors.append('Action "%s": subaction %s has unknown type %s' % [action_name, subaction_name, compare_type_str])
						continue
					var subaction_data := {"name": str(subaction_name), "compare_type": compare_type}
					if compare_type == ActionCompareType.IF or compare_type == ActionCompareType.ELSE_IF:
						var condition_name = subaction.get("condition", "")
						if condition_name == null or condition_name == "":
							errors.append('Action "%s": subaction %s missing a condition name' % [action_name, subaction_name])
							continue
						condition_name = str(condition_name)
						if condition_name not in exported_conditions:
							errors.append('Action "%s": unknown condition %s for action %s' % [action_name, condition_name, subaction_name])
						subaction_data["condition_name"] = condition_name
					item["subactions"].append(subaction_data)
				exported_actions[action_name] = item
			writer.write_u32(len(exported_actions))
			for action_name in GsqGraphUtils.toporder(action_graph):
				var exported_action := exported_actions[action_name]
				writer.write_str(str(exported_action["name"]))
				writer.write_u32(len(exported_action["motions"]))
				for motion in exported_action["motions"]:
					writer.write_str(motion["name"])
					writer.write_u32(motion["compare_type"])
					if motion["compare_type"] == ActionCompareType.IF or motion["compare_type"] == ActionCompareType.ELSE_IF:
						writer.write_str(motion["condition_name"])
				writer.write_u32(len(exported_action["subactions"]))
				for subaction in exported_action["subactions"]:
					writer.write_str(subaction["name"])
					writer.write_u32(subaction["compare_type"])
					if subaction["compare_type"] == ActionCompareType.IF or subaction["compare_type"] == ActionCompareType.ELSE_IF:
						writer.write_str(subaction["condition_name"])
		writer.end_chunk("DATAACTS")
#
		writer.start_chunk("DATASEUI", 3)
		var selected_ui = data.get("selected_ui", {})
		if selected_ui is not Dictionary:
			selected_ui = {}
		var display_type_str = selected_ui.get("display_type", "")
		writer.write_u32(SelectedUiDisplayType.get(display_type_str.to_upper(), SelectedUiDisplayType.CIRCLE))
		
		var write_vetor = func (key: String, items: PackedStringArray, default: float):
			var key_data = selected_ui.get(key, {})
			if key_data is not Dictionary:
				errors.append("Selected Ui: %s is not a table" % [key])
				key_data = {}
			for i in items:
				writer.write_float(key_data.get(i, default))
		
		write_vetor.call("scale", ["x", "z"], 1)
		write_vetor.call("offset", ["x", "z"], 0)
		write_vetor.call("volume", ["x", "y", "z"], 0)
		write_vetor.call("volume_scale", ["x", "y", "z"], 1)
		var matrix = selected_ui.get("matrix", [])
		if matrix is not Array or len(matrix) < 9:
			matrix = [1, 0, 0, 0, 1, 0, 0, 0, 1]
		for i in matrix:
			writer.write_float(i)
		writer.end_chunk("DATASEUI")

		writer.end_chunk("FOLDREBP")

		if len(errors):
			GsqLogger.warning("\n".join(errors))
		return Error.OK

	const _MONTH_NAMES := {
		1: "January", 2: "February", 3: "March", 4: "April", 5: "May", 6: "June",
		7: "July", 8: "August", 9: "September", 10: "October", 11: "November", 12: "December",
	}

	static func _format_timestr(datetime: Dictionary) -> String:
		var period := "AM"
		var hour: int = datetime["hour"]
		if hour == 0:
			hour = 12
			period = "PM"
		elif hour > 12:
			hour -= 12
			period = "PM"
		return "%s %02d, %04d, %d:%d:%d %s" % [
			_MONTH_NAMES[datetime["month"]], datetime["day"], datetime["year"],
			hour, datetime["minute"], datetime["second"], period,
		]
