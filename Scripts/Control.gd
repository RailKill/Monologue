extends Control

var dialog = {}
var dialog_for_localisation = []

@export var file_path: String

@onready var sentence_node = preload("res://Objects/GraphNodes/SentenceNode.tscn")
@onready var dice_roll_node = preload("res://Objects/GraphNodes/DiceRollNode.tscn")
@onready var choice_node = preload("res://Objects/GraphNodes/ChoiceNode.tscn")
@onready var end_node = preload("res://Objects/GraphNodes/EndPathNode.tscn")
@onready var root_node = preload("res://Objects/GraphNodes/RootNode.tscn")
@onready var option_panel = preload("res://Objects/SubComponents/OptionNode.tscn")

@onready var graph_edit: GraphEdit = $VBoxContainer/Control/GraphEdit

var live_dict: Dictionary

var initial_pos = Vector2(40,40)
var option_index = 0
var node_index = 0
var all_nodes_index = 0

var root_node_ref
var root_dict


func _ready():
	if not file_path.is_empty():
		$WelcomeWindow.show()
	
	var new_root_node = root_node.instantiate()
	graph_edit.add_child(new_root_node)


func _to_dict() -> Dictionary:
	var list_nodes = []
	
	for node in graph_edit.get_children():
		if node.is_queued_for_deletion():
			continue
		list_nodes.append(node._to_dict())
		if node.node_type == "NodeChoice":
			list_nodes.append_array(node.options)
	
	root_dict = get_root_dict(list_nodes)
	root_node_ref = get_root_node_ref()
	
	var characters = graph_edit.speakers
	if graph_edit.speakers.size() <= 0:
		characters.append({
			"ID": "_NARRATOR",
			"EditorIndex": 0
		})
	
	return {
		"RootNodeID": root_dict.get("ID"),
		"ListNodes": list_nodes,
		"Characters": characters,
		"Variables": root_node_ref.get_variables()
	}


func get_root_dict(nodes):
	for node in nodes:
		if node.get("$type") == "NodeRoot":
			return node


func get_root_node_ref():
	for node in graph_edit.get_children():
		if node.id == root_dict.get("ID"):
			return node


func _on_NewOption_pressed():
	var new_choice_node = choice_node.instantiate()
	graph_edit.add_child(new_choice_node)


func _on_GraphEdit_connection_request(from, from_slot, to, to_slot):
	if graph_edit.get_all_connections_from_slot(from, from_slot).size() <= 0:
		graph_edit.connect_node(from, from_slot, to, to_slot)


func _on_GraphEdit_disconnection_request(from, from_slot, to, to_slot):
	graph_edit.disconnect_node(from, from_slot, to, to_slot)


func _on_Clear_pressed():
	for node in get_tree().get_nodes_in_group("graph_nodes"):
		if node.node_type != "NodeRoot":
			node.queue_free()
	graph_edit.clear_connections()


func _on_NewRoll_pressed():
	var dice_roll = dice_roll_node.instantiate()
	graph_edit.add_child(dice_roll)


func save():
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	var data = JSON.stringify(_to_dict(), "\t", false, true)
	file.store_string(data)
	file.close()
	
	
func _on_file_selected(path):
	file_path = path
	$WelcomeWindow.hide()
	if $ProjectFinderDialog.open_mode == 0: #NEW
		save()
		
	load_project(path)
	
	
func load_project(path):
	assert(FileAccess.file_exists(path))
	
	var file = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(file)
	
	live_dict = data
	graph_edit.speakers = data.get("Characters")
	
	for node in graph_edit.get_children():
		node.queue_free()
	graph_edit.clear_connections()
	
	var node_list = data.get("ListNodes")
	root_dict = get_root_dict(node_list)
	
	for node in node_list:
		var new_node
		match node.get("$type"):
			"NodeRoot":
				new_node = root_node.instantiate()
				new_node._from_dict(node, node_list)
			"NodeSentence":
				new_node = sentence_node.instantiate()
				new_node._from_dict(node)
			"NodeChoice":
				new_node = choice_node.instantiate()
				new_node._from_dict(node, node_list)
			"NodeDiceRoll":
				new_node = dice_roll_node.instantiate()
				new_node._from_dict(node)
			"NodeEndPath":
				new_node = end_node.instantiate()
				new_node._from_dict(node)
		
		if not new_node:
			continue
		
		graph_edit.add_child(new_node)
	
	
	# Root Node Variables
	for variable in data.get("Variables"):
		root_node_ref.add_variable()
	
	for node in node_list:
		if not node.has("ID"):
			continue
		
		var current_node = get_node_by_id(node.get("ID"))
		match node.get("$type"):
			"NodeRoot":
				if node.get("NextID") is String:
					var next_node = get_node_by_id(node.get("NextID"))
					graph_edit.connect_node(current_node.name, 0, next_node.name, 0)
			"NodeSentence":
				if node.get("NextID") is String:
					var next_node = get_node_by_id(node.get("NextID"))
					graph_edit.connect_node(current_node.name, 0, next_node.name, 0)
			"NodeChoice":
				current_node.connect_all_options(node_list)
			"NodeDiceRoll":
				if node.get("PassID") is String:
					var pass_node = get_node_by_id(node.get("PassID"))
					graph_edit.connect_node(current_node.name, 0, pass_node.name, 0)
				
				if node.get("FailID") is String:
					var fail_node = get_node_by_id(node.get("FailID"))
					graph_edit.connect_node(current_node.name, 1, fail_node.name, 0)
		
		if not current_node: # OptionNode
			continue
		
		if node.has("EditorPosition"):
			current_node.position_offset.x = node.EditorPosition.get("x")
			current_node.position_offset.y = node.EditorPosition.get("y")
			
	root_node_ref = get_root_node_ref()
	
	
func get_node_by_id(id):
	for node in graph_edit.get_children():
		if node.id == id:
			return node
	
	
func get_options_nodes(node_list, options_id):
	var options = []
	
	for node in node_list:
		if node.get("ID") in options_id:
			options.append(node)
	return options


func _on_new_end_pressed():
	var node = end_node.instantiate()
	graph_edit.add_child(node)


func _on_new_sentence_pressed():
	var node = sentence_node.instantiate()
	graph_edit.add_child(node)
