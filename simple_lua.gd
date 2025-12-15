# Inspired by https://github.com/SirAnthony/slpp
class_name SimpleLua

static func stringify(data: Variant, indent: String = "", prefix: String = "", sort_keys: bool = true, as_script: bool = false) -> String:
	var parts: PackedStringArray = [prefix]
	assert(not (as_script and not data is Dictionary), "Data must be a Dictionaty, got %s" % type_string(typeof(data)))
	_encode(data, 0, true, indent, parts, sort_keys, as_script)
	return "".join(parts)

static func _encode(data: Variant, depth: int, leading_spaces: bool, indent: String, parts: PackedStringArray, sort_keys: bool, top_level: bool) -> void:
	match typeof(data):
		TYPE_STRING:
			if data.c_escape() != data:
				parts.append("[[")
				parts.append(data)
				parts.append("]]")
			else:
				parts.append('"')
				parts.append(data)
				parts.append('"')
		TYPE_PACKED_BYTE_ARRAY:
			parts.append('"')
			for p in data:
				parts.append("\\x%02x" % data)
			parts.append('"')
		TYPE_BOOL:
			parts.append(str(data).to_lower())
		TYPE_NIL:
			parts.append("nil")
		TYPE_FLOAT:
			parts.append(str(snapped(data, 0.0001)))
		TYPE_INT:
			parts.append(str(data))
		TYPE_DICTIONARY:
			var dp := ""
			if not top_level:
				if leading_spaces:
					parts.append(indent.repeat(depth))
				if len(data) == 0:
					parts.append("{}")
					return
				parts.append("{\n")
				dp = indent.repeat(depth + 1)
			var keys: Array = data.keys()
			if sort_keys:
				keys.sort()
			for k in keys:
				var key = ""
				if k is float or k is int:
					key = "[%s]" % k
				elif k is String:
					if k.is_valid_ascii_identifier():
						key = k
					else:
						key = '["%s"]' % k
				else:
					assert(false, "A table cannot have a key %" % k)
				parts.append(dp)
				parts.append(key)
				parts.append(" = ")
				_encode(data[k], depth + 1, false, indent, parts, sort_keys, false)
				if top_level:
					parts.append("\n")
				else:
					parts.append(",\n")
			parts.append(indent.repeat(depth))
			if not top_level:
				parts.append("}")
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			if leading_spaces:
				parts.append(indent.repeat(depth))
			if len(data) == 0:
				parts.append("{}")
				return
			var short_form := true
			for i in data:
				if not (
					i is int
					or i is float
					or (i is String and len(i) < 10)
				):
					short_form = false
					break
			var newline = "" if short_form else "\n"
			indent = "" if short_form else indent
			parts.append("{")
			parts.append(newline)
			var dp := indent.repeat(depth + 1)
			for idx in len(data):
				var i = data[idx]
				parts.append(dp)
				_encode(i, depth + 1, false, indent, parts, sort_keys, false)
				if not (short_form and idx + 1 == len(data)):
					parts.append(",")
				parts.append(newline)
			parts.append(indent.repeat(depth))
			parts.append("}")
