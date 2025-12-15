class_name Lua

var state := GDLuaState.new()
var _error_msg: String

func dostring(code: String) -> Error:
	var err := state.dostring(code)
	if err != Error.OK:
		_error_msg = state.pop_value()
	return err

func get_error() -> String:
	return _error_msg

func get_value(name: String, default: Variant = null) -> Variant:
	var res = state.getglobal(name)
	return res if res != null else default
