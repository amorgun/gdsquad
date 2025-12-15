class_name GsqQueue

var in_st: Array
var out_st: Array

func _init(seq: Array = []):
	in_st.append_array(seq)

func size() -> int:
	return len(in_st) + len(out_st)

func append(val: Variant) -> void:
	in_st.append(val)

func popleft() -> Variant:
	if not out_st:
		in_st.reverse()
		out_st.append_array(in_st)
		in_st.clear()
	return out_st.pop_back()
