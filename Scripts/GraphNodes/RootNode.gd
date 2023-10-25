@icon("res://Assets/Icons/NodesIcons/Root.svg")

class_name RootNode

extends GraphNode


var _node_dict: Dictionary

var id = UUID.v4()
var node_type = "NodeRoot"
var characters = []


func _ready():
	title = node_type


func _to_dict() -> Dictionary:
	var next_id_node = get_parent().get_all_connections_from_slot(name, 0)
	
	return {
		"$type": node_type,
		"ID": id,
		"NextID": next_id_node[0].id if next_id_node else -1,
		"EditorPosition": {
			"x": position_offset.x,
			"y": position_offset.y
		}
	}

func _from_dict(dict, _global_dict):
	_node_dict = dict
	
	id = dict.get("ID")
	
	var _pos = dict.get("EditorPosition")
	position_offset.x = _pos.get("x")
	position_offset.x = _pos.get("y")


func get_characters():
	var result = []
	for child in characters:
		if not child is PanelContainer:
			continue
		
		result.append(child._to_dict())
	
	return result
