class_name GsqGraphUtils

static func toporder(graph: Dictionary[String, PackedStringArray], sort: bool = true) -> PackedStringArray:
		var ans: PackedStringArray = []
		var visited: Dictionary[String, bool] = {}
		
		var walk := func (node: String, walk: Callable) -> void:
			if node in visited:
				return
			visited[node] = true
			var children: PackedStringArray = graph.get(node, [])
			if sort:
				children.sort()
			for child in children:
				walk.call(child, walk)
			ans.append(node)
		
		var keys := graph.keys()
		if sort:
			keys.sort()
		for v in keys:
			walk.call(v, walk)
		return ans
