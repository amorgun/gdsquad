# Based on https://github.com/pygments/pygments/blob/0328cfaf1d953b3a0c7eb0ec0efd363deb2f9d51/pygments/lexers/scripting.py#L28
class_name LuaSyntaxHighlighter extends SyntaxHighlighter

var line_start_state: Dictionary[int, Array] = {}

enum HighlightColor {
	DEFAULT,
	HIGHLIGHT,
	TEXT,
	COMMENT,
	STRING,
	KEYWORD,
	CONTROL_FLOW_KEYWORD,
	NUMBER,
	FUNCTION_NAME,
	FUNCTION_CALL,
	CLASS_NAME,
}

class Token:
	var color: HighlightColor
	var size: int

func _re(s: String) -> RegEx:
	return RegEx.create_from_string(s)

const _name = r"(?:[^\W\d]\w*)"
var STATES := {
	"base": [
		[_re(r"\s+"), HighlightColor.TEXT, null],
		[_re(r"--\[(=*)\["), HighlightColor.COMMENT, start_multiline_comment],
		[_re(r"--.*"), HighlightColor.COMMENT, null],

		[_re(r"(?i)0x[\da-f]*(\.[\da-f]*)?(p[+-]?\d+)?"), HighlightColor.NUMBER, null],
		[_re(r"(?i)(\d*\.\d+|\d+\.\d*)(e[+-]?\d+)"), HighlightColor.NUMBER, null],
		[_re(r"(?i)\d+e[+-]?\d+"), HighlightColor.NUMBER, null],
		[_re(r"\d+"),HighlightColor.NUMBER, null],
		
		[_re(r"\[(=*)\["),HighlightColor.STRING, start_multiline_string],
		
		[_re(r"::"), HighlightColor.HIGHLIGHT, "label"],
		[_re(r"\.{3}"), HighlightColor.HIGHLIGHT, null],
		[_re(r"[=<>|~&+\-*/%#^]+|\.\."), HighlightColor.HIGHLIGHT, null],
		[_re(r"[\[\]{}().,:;]"), HighlightColor.HIGHLIGHT, null],
		[_re(r"(and|or|not)\b"), HighlightColor.KEYWORD, null],

		[
			_re(r"(break|do|else|elseif|end|for|if|in|repeat|return|then|until|while)\b"),
			HighlightColor.CONTROL_FLOW_KEYWORD, null,
		],
		[_re(r"goto\b"), HighlightColor.CONTROL_FLOW_KEYWORD, "goto"],
		[_re(r"(local)\b"), HighlightColor.KEYWORD, null],
		[_re(r"(true|false|nil)\b"), HighlightColor.KEYWORD, null],

		[_re(r"function\b"), HighlightColor.FUNCTION_NAME, "funcname"],

		#(words(all_lua_builtins(), suffix=r"\b"), Name.Builtin),
		[_re(r"[A-Za-z_]\w*(?=\s*[.:])"), HighlightColor.TEXT, "varname"],
		[_re(r"[A-Za-z_]\w*(?=\s*\()"), HighlightColor.FUNCTION_CALL, null],
		[_re(r"[A-Za-z_]\w*"), HighlightColor.TEXT, null],
#
		[_re(r"'"), HighlightColor.STRING, "sqs"],
		[_re(r'"'), HighlightColor.STRING, "dqs"],
	],
	"varname": [
		[_re(r"\s+"), HighlightColor.TEXT, null],
		[_re(r"--\[(=*)\["), HighlightColor.COMMENT, start_multiline_comment],
		[_re(r"--.*"), HighlightColor.COMMENT, null],

		[_re(r"\.\."), HighlightColor.HIGHLIGHT, "#pop"],
		[_re(r"[.:]"), HighlightColor.HIGHLIGHT, null],
		[_re(r"{0}(?=\s*[.:])".format([_name])), HighlightColor.TEXT, null],
		[_re(r"{0}(?=\s*\()".format([_name])), HighlightColor.FUNCTION_CALL, "#pop"],
		[_re(_name), HighlightColor.TEXT, "#pop"],
	],
	"funcname": [
		[_re(r"\s+"), HighlightColor.TEXT, null],
		[_re(r"--\[(=*)\["), HighlightColor.COMMENT, start_multiline_comment],
		[_re(r"--.*"), HighlightColor.COMMENT, null],

		[_re(r"[.:]"), HighlightColor.HIGHLIGHT, null],
		[_re(r"{0}(?=\s*[.:])".format([_name])), HighlightColor.CLASS_NAME, null],
		[_re(_name), HighlightColor.FUNCTION_NAME, "#pop"],
		# inline function
		[_re(r"\("), HighlightColor.HIGHLIGHT, "#pop"],
	],
	"goto": [
		[_re(r"\s+"), HighlightColor.TEXT, null],
		[_re(r"--\[(=*)\["), HighlightColor.COMMENT, start_multiline_comment],
		[_re(r"--.*"), HighlightColor.COMMENT, null],

		[_re(_name), HighlightColor.TEXT, "#pop"],
	],
	"label": [
		[_re(r"\s+"), HighlightColor.TEXT, null],
		[_re(r"--\[(=*)\["), HighlightColor.COMMENT, start_multiline_comment],
		[_re(r"--.*"), HighlightColor.COMMENT, null],
		
		[_re(r"::"), HighlightColor.TEXT, "#pop"],
		[_re(_name), HighlightColor.HIGHLIGHT, null],
	],
	"sqs": [
		[_re(r'\\([abfnrtv\\"\']|[\r\n]{1,2}|z\s*|x[0-9a-fA-F]{2}|\d{1,3}|u\{[0-9a-fA-F]+\})'), HighlightColor.STRING, null],
		[_re(r"'|$"), HighlightColor.STRING, "#pop"],
		[_re(r"[^\\']+"), HighlightColor.STRING, null],
	],
	"dqs": [
		[_re(r'\\([abfnrtv\\"\']|[\r\n]{1,2}|z\s*|x[0-9a-fA-F]{2}|\d{1,3}|u\{[0-9a-fA-F]+\})'), HighlightColor.STRING, null],
		[_re(r'"|$'), HighlightColor.STRING, '#pop'],
		[_re(r'[^\\"]+'), HighlightColor.STRING, null],
	]
};

static var colors: Dictionary[HighlightColor, Color] = {}
var RE_MULTILINE_END :=  RegEx.create_from_string(r"\](=*)\]")

func transition_dict(line: String, pos: int, stack: Array, key: String) -> Token:
	var result := Token.new()
	var rules: Array = STATES.get(key, [])
	for rule in rules:
		var regex: RegEx = rule[0]
		var re_match := regex.search(line, pos)
		if re_match != null and re_match.get_start() == pos:
			result.size = re_match.get_end() - re_match.get_start()
			result.color = rule[1]
			var new_state = rule[2]
			if new_state != null:
				if new_state is String:
					if new_state != "#pop":
						stack.append(new_state)
					else:
						stack.pop_back()
				if new_state is Callable:
					new_state.call(re_match, stack)
			return result
	stack.pop_back()
	return result

func start_multiline_comment(re_match: RegExMatch, stack: Array) -> void:
	stack.append(state_multiline.bind(HighlightColor.COMMENT, re_match.get_end(1) - re_match.get_start(1)))

func start_multiline_string(re_match: RegExMatch, stack: Array) -> void:
	stack.append(state_multiline.bind(HighlightColor.STRING, re_match.get_end(1) - re_match.get_start(1)))

func state_multiline(line: String, pos: int, stack: Array, color: HighlightColor, level: int) -> Token:
	var result := Token.new()
	result.color = color
	var idx := line.find("]%s]" % "=".repeat(level), pos)
	if idx == -1:
		result.size = len(line) - pos
		return result
	result.size = idx - pos + 2 + level
	stack.pop_back()
	return result

func _get_line_syntax_highlighting(line_idx: int) -> Dictionary:
	var line_text := get_text_edit().get_line(line_idx)
	if line_idx == 0 and line_text.begins_with("!#"):
		return {0: {"color": colors[HighlightColor.COMMENT]}}
	var stack: Array = line_start_state.get(line_idx, ["base"]).duplicate()
	var pos := 0
	var result: Dictionary[int, Dictionary] = {}
	while pos < len(line_text):
		if len(stack) == 0:
			result[pos] = {"color": colors[HighlightColor.DEFAULT]}
			break
		var stack_top = stack[len(stack) - 1]
		var state_fn: Callable = stack_top if stack_top is Callable else transition_dict.bind(stack_top)
		var token := state_fn.call(line_text, pos, stack)
		if token == null:
			continue
		if token.color != null:
			result[pos] = {"color": colors[token.color]}
		pos += token.size
	if len(stack) > 1:
		line_start_state[line_idx + 1] = stack.duplicate()
	else:
		line_start_state.erase(line_idx + 1)
	return result

func _clear_highlighting_cache() -> void:
	line_start_state = {}
	return
