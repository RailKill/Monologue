extends Control


var dialog = {}
var dialog_for_localisation = []

const HISTORY_FILE_PATH: String = "user://history.save"
const MAX_FILENAME_LENGTH = 48

@onready var graph_edit_inst = preload("res://Objects/GraphEdit.tscn")
@onready var root_node = preload("res://Objects/GraphNodes/RootNode.tscn")
@onready var sentence_node = preload("res://Objects/GraphNodes/SentenceNode.tscn")
@onready var dice_roll_node = preload("res://Objects/GraphNodes/DiceRollNode.tscn")
@onready var choice_node = preload("res://Objects/GraphNodes/ChoiceNode.tscn")
@onready var end_node = preload("res://Objects/GraphNodes/EndPathNode.tscn")
@onready var bridge_in_node = preload("res://Objects/GraphNodes/BridgeInNode.tscn")
@onready var bridge_out_node = preload("res://Objects/GraphNodes/BridgeOutNode.tscn")
@onready var condition_node = preload("res://Objects/GraphNodes/ConditionNode.tscn")
@onready var action_node = preload("res://Objects/GraphNodes/ActionNode.tscn")
@onready var comment_node = preload("res://Objects/GraphNodes/CommentNode.tscn")
@onready var event_node = preload("res://Objects/GraphNodes/EventNode.tscn")
@onready var option_panel = preload("res://Objects/SubComponents/OptionNode.tscn")
@onready var recent_file_button = preload("res://Objects/SubComponents/RecentFileButton.tscn")

@onready var tab_bar: TabBar = $MarginContainer/MainContainer/GraphEditsArea/VBoxContainer/TabBar
@onready var graph_edits: Control = $MarginContainer/MainContainer/GraphEditsArea/VBoxContainer/GraphEdits
@onready var side_panel_node = $MarginContainer/MainContainer/GraphEditsArea/MarginContainer/SidePanelNodeDetails
@onready var saved_notification = $MarginContainer/MainContainer/Header/SavedNotification
@onready var graph_node_selecter = $GraphNodeSelecter
@onready var save_progress_bar: ProgressBar = $MarginContainer/MainContainer/Header/SaveProgressBarContainer/SaveProgressBar
@onready var save_button: Button = $MarginContainer/MainContainer/Header/Save
@onready var test_button: Button = $MarginContainer/MainContainer/Header/TestBtnContainer/Test
@onready var add_menu_bar: PopupMenu = $MarginContainer/MainContainer/Header/MenuBar/Add
@onready var recent_files_container = $WelcomeWindow/PanelContainer/CenterContainer/VBoxContainer2/RecentFilesContainer
@onready var recent_files_button_container = $WelcomeWindow/PanelContainer/CenterContainer/VBoxContainer2/RecentFilesContainer/ButtonContainer
@onready var file_dialog = $FileDialog

var live_dict: Dictionary

## Set to true if a file operation is triggered from Header instead of WelcomeWindow.
var is_header_file_operation: bool = false

var initial_pos = Vector2(40,40)
var option_index = 0
var node_index = 0
var all_nodes_index = 0

var root_node_ref
var root_dict

var picker_mode: bool = false
var picker_from_node
var picker_from_port
var picker_position


func _ready():
	var new_root_node = root_node.instantiate()
	get_current_graph_edit().add_child(new_root_node)
	connect_graph_edit_signal(get_current_graph_edit())
	
	saved_notification.hide()
	save_progress_bar.hide()
	
	# Load recent files
	if not FileAccess.file_exists(HISTORY_FILE_PATH):
		FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
		recent_files_container.hide()
	else:
		var file = FileAccess.open(HISTORY_FILE_PATH, FileAccess.READ)
		var raw_data = file.get_as_text()
		if raw_data:
			var data: Array = JSON.parse_string(raw_data)
			for path in data:
				if FileAccess.file_exists(path):
					continue
				data.erase(path)
			for path in data.slice(0, 3):
				var btn: Button = recent_file_button.instantiate()
				var btn_text = path.replace("\\", "/")
				btn_text = btn_text.replace("//", "/")
				btn_text = btn_text.split("/")
				if btn_text.size() >= 2:
					btn_text = btn_text.slice(-2, btn_text.size())
					btn_text = btn_text[0].path_join(btn_text[1])
				else:
					btn_text = btn_text.back()
				
				btn.text = truncate_filename(btn_text)
				btn.pressed.connect(file_selected.bind(path, 1))
				recent_files_button_container.add_child(btn)
			recent_files_container.show()
		else:
			recent_files_container.hide()
	
	$WelcomeWindow.show()
	$NoInteractions.show()
	
	GlobalSignal.add_listener("add_graph_node", add_node)
	GlobalSignal.add_listener("test_trigger", test_project)


func _shortcut_input(event):
	if event.is_action_pressed("Save"):
		save(false)


func get_current_graph_edit() -> GraphEdit:
	return graph_edits.get_child(tab_bar.current_tab)


func _to_dict() -> Dictionary:
	var list_nodes = []
	
	save_progress_bar.max_value = get_current_graph_edit().get_children().size() + 1
	
	for node in get_current_graph_edit().get_children():
		if node.is_queued_for_deletion():
			continue
		list_nodes.append(node._to_dict())
		if node.node_type == "NodeChoice":
			for child in node.get_children():
				list_nodes.append(child._to_dict())
		
		save_progress_bar.value = list_nodes.size()
	
	root_dict = get_root_dict(list_nodes)
	root_node_ref = get_root_node_ref()
	
	var characters = get_current_graph_edit().speakers
	if get_current_graph_edit().speakers.size() <= 0:
		characters.append({
			"Reference": "_NARRATOR",
			"ID": 0
		})
	save_progress_bar.value += 1
	
	return {
		"EditorVersion": ProjectSettings.get_setting("application/config/version", "unknown"),
		"RootNodeID": root_dict.get("ID"),
		"ListNodes": list_nodes,
		"Characters": characters,
		"Variables": get_current_graph_edit().variables
	}


func file_selected(path, open_mode):
	if not FileAccess.open(path, FileAccess.READ):
		return
	
	for ge in graph_edits.get_children():
		if not ge is GraphEdit:
			continue
		
		if ge.file_path == path:
			return
	
	$NoInteractions.hide()
	
	tab_bar.add_tab(truncate_filename(path.get_file()))
	tab_bar.move_tab(tab_bar.tab_count - 2, tab_bar.tab_count - 1)
	tab_bar.current_tab = tab_bar.tab_count - 2
	
	var graph_edit = get_current_graph_edit()
	graph_edit.control_node = self
	graph_edit.file_path = path
	
	$WelcomeWindow.hide()
	if open_mode == 0: #NEW
		for node in graph_edit.get_children():
			node.queue_free()
		var new_root_node = root_node.instantiate()
		graph_edit.add_child(new_root_node)
		await save(true)

	if not FileAccess.file_exists(HISTORY_FILE_PATH):
		FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
	else:
		var file: FileAccess = FileAccess.open(HISTORY_FILE_PATH, FileAccess.READ_WRITE)
		var raw_data = file.get_as_text()
		var data: Array
		if raw_data:
			data = JSON.parse_string(raw_data)
			data.erase(path)
			data.insert(0, path)
		else:
			data = [path]
		for p in data:
			if FileAccess.file_exists(p):
				continue
			data.erase(p)
		file = FileAccess.open(HISTORY_FILE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(data.slice(0, 10)))
	
	load_project(path)


func get_root_dict(nodes):
	for node in nodes:
		if node.get("$type") == "NodeRoot":
			return node


func get_root_node_ref():
	for node in get_current_graph_edit().get_children():
		if !node.is_queued_for_deletion() and node.id == root_dict.get("ID"):
			return node


func save(quick: bool = false):
	save_progress_bar.value = 0
	save_progress_bar.show()
	save_button.hide()
	test_button.hide()
	
	var data = JSON.stringify(_to_dict(), "\t", false, true)
	if not data: # Fail to load 
		save_progress_bar.hide()
		save_button.show()
		test_button.show()
	
	var file = FileAccess.open(get_current_graph_edit().file_path, FileAccess.WRITE)
	file.store_string(data)
	file.close()
	
	saved_notification.show()
	if !quick:
		await get_tree().create_timer(1.5).timeout
	saved_notification.hide()
	save_progress_bar.hide()
	save_button.show()
	test_button.show()

## Left-truncate a given string based on MAX_FILENAME_LENGTH.
func truncate_filename(filename: String):
	var truncated = filename
	if filename.length() > MAX_FILENAME_LENGTH:
		truncated = "..." + filename.right(MAX_FILENAME_LENGTH - 3)
	return truncated

func load_project(path):
	if not FileAccess.file_exists(path):
		return
		
	$NoInteractions.hide()
	var graph_edit = get_current_graph_edit()
	
	var file := FileAccess.get_file_as_string(path)
	graph_edit.name = path.get_file().trim_suffix(".json")
	
	var data := {}
	data = JSON.parse_string(file)

	if not data:
		data = _to_dict()
		save(true)
	
	live_dict = data
	
	graph_edit.speakers = data.get("Characters")
	graph_edit.variables = data.get("Variables")
	
	for node in graph_edit.get_children():
		node.queue_free()
	graph_edit.clear_connections()
	graph_edit.data = data
	
	var node_list = data.get("ListNodes")
	root_dict = get_root_dict(node_list)
	
	for node in node_list:
		var new_node
		match node.get("$type"):
			"NodeRoot":
				new_node = root_node.instantiate()
			"NodeSentence":
				new_node = sentence_node.instantiate()
			"NodeChoice":
				new_node = choice_node.instantiate()
			"NodeDiceRoll":
				new_node = dice_roll_node.instantiate()
			"NodeEndPath":
				new_node = end_node.instantiate()
			"NodeBridgeIn":
				new_node = bridge_in_node.instantiate()
			"NodeBridgeOut":
				new_node = bridge_out_node.instantiate()
			"NodeCondition":
				new_node = condition_node.instantiate()
			"NodeAction":
				new_node = action_node.instantiate()
			"NodeComment":
				new_node = comment_node.instantiate()
			"NodeEvent":
				new_node = event_node.instantiate()
		
		if not new_node:
			continue
		new_node.id = node.get("ID")
		
		graph_edit.add_child(new_node)
		new_node._from_dict(node)
	
	for node in node_list:
		if not node.has("ID"):
			continue
		
		var current_node = get_node_by_id(node.get("ID"))
		match node.get("$type"):
			"NodeRoot", "NodeSentence", "NodeBridgeOut", "NodeAction", "NodeEvent":
				if node.get("NextID") is String:
					var next_node = get_node_by_id(node.get("NextID"))
					graph_edit.connect_node(current_node.name, 0, next_node.name, 0)
			"NodeChoice":
				current_node._update()
			"NodeDiceRoll":
				if node.get("PassID") is String:
					var pass_node = get_node_by_id(node.get("PassID"))
					graph_edit.connect_node(current_node.name, 0, pass_node.name, 0)
				
				if node.get("FailID") is String:
					var fail_node = get_node_by_id(node.get("FailID"))
					graph_edit.connect_node(current_node.name, 1, fail_node.name, 0)
			"NodeCondition":
				if node.get("IfNextID") is String:
					var if_node = get_node_by_id(node.get("IfNextID"))
					graph_edit.connect_node(current_node.name, 0, if_node.name, 0)
				
				if node.get("ElseNextID") is String:
					var else_node = get_node_by_id(node.get("ElseNextID"))
					graph_edit.connect_node(current_node.name, 1, else_node.name, 0)
		
		if not current_node: # OptionNode
			continue
		
		if node.has("EditorPosition"):
			current_node.position_offset.x = node.EditorPosition.get("x")
			current_node.position_offset.y = node.EditorPosition.get("y")
			
	root_node_ref = get_root_node_ref()
	
	if not root_node_ref:
		var new_root_node = root_node.instantiate()
		get_current_graph_edit().add_child(new_root_node)
		
		save(true)
		root_node_ref = get_root_node_ref()
	
	
func get_node_by_id(id):
	for node in get_current_graph_edit().get_children():
		if node.id == id:
			return node
	return null

## Check if an option ID exists in the entirety of the current GraphEdit.
func is_option_id_exists(id):
	for node in get_current_graph_edit().get_children():
		if node is ChoiceNode:
			return not node.find_option_dictionary(id).is_empty()
	
func get_options_nodes(node_list, options_id):
	var options = []
	
	for node in node_list:
		if node.get("ID") in options_id:
			options.append(node)
	return options


###############################
#  New node buttons callback  #
###############################

func center_node_in_graph_edit(node):
	var graph_edit = get_current_graph_edit()
	if picker_mode:
		graph_edit.disconnect_connection_from_node(picker_from_node, picker_from_port)
		node.position_offset = picker_position
		graph_edit.connect_node(picker_from_node, picker_from_port, node.name, 0)
		update_connection(graph_edit, picker_from_node, picker_from_port, node.name, 0)
		disable_picker_mode()
		return
	
	node.position_offset = ((graph_edit.size/2) + graph_edit.scroll_offset) / graph_edit.zoom

func _on_add_id_pressed(id):
	var node_type = add_menu_bar.get_item_text(id)
	GlobalSignal.emit("add_graph_node", [node_type])

func add_node(node_type):
	if node_type == "Bridge":
		var number = get_current_graph_edit().get_free_bridge_number()
	
		var in_node = bridge_in_node.instantiate()
		var out_node = bridge_out_node.instantiate()
		
		get_current_graph_edit().add_child(in_node)
		get_current_graph_edit().add_child(out_node)
		
		in_node.number_selector.value = number
		out_node.number_selector.value = number
		
		center_node_in_graph_edit(in_node)
		center_node_in_graph_edit(out_node)
		in_node.position_offset.x -= in_node.size.x/2+10
		out_node.position_offset.x += out_node.size.x/2+10
		
	var node
	match node_type:
		"Sentence":
			node = sentence_node
		"Choice":
			node = choice_node
		"DiceRoll":
			node = dice_roll_node
		"Condition":
			node = condition_node
		"Action":
			node = action_node
		"EndPath":
			node = end_node
		"Event":
			node = event_node
		"Comment":
			node = comment_node
	
	if not node:
		return
	
	node = node.instantiate()
	get_current_graph_edit().add_child(node)
	center_node_in_graph_edit(node)

func update_connection(graph_edit, from, from_slot, to, _to_slot, next = true):
	var graph_node = graph_edit.get_node(NodePath(from))
	if graph_node.has_method("update_next_id"):
		if next:
			graph_node.update_next_id(from_slot, graph_edit.get_node(NodePath(to)))
		else:
			graph_node.update_next_id(from_slot, null)
	
func _on_graph_edit_connection_request(from, from_slot, to, to_slot):
	var current_graph_edit = get_current_graph_edit()
	if current_graph_edit.get_all_connections_from_slot(from, from_slot).size() <= 0:
		current_graph_edit.connect_node(from, from_slot, to, to_slot)
	update_connection(current_graph_edit, from, from_slot, to, to_slot)

func _on_graph_edit_disconnection_request(from, from_slot, to, to_slot):
	var current_graph_edit = get_current_graph_edit()
	get_current_graph_edit().disconnect_node(from, from_slot, to, to_slot)
	update_connection(current_graph_edit, from, from_slot, to, to_slot, false)

func test_project(from_node: String = "-1"):
	await save(true)
	
	var global_vars = get_node("/root/GlobalVariables")
	global_vars.test_path = get_current_graph_edit().file_path
	
	var test_instance = preload("res://Test/Menu.tscn")
	var test_scene = test_instance.instantiate()
	
	if get_node_by_id(from_node) != null:
		test_scene._from_node_id = from_node
	
	get_tree().root.add_child(test_scene)

####################
#  File selection  #
####################

func new_file_select():
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Create New File"
	file_dialog.ok_button_text = "Create"
	file_dialog.popup_centered()

func open_file_select():
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Open File"
	file_dialog.ok_button_text = "Open"
	file_dialog.popup_centered()

func _on_file_dialog_selected(path: String):
	if is_header_file_operation:
		$WelcomeWindow.hide()
		file_dialog.hide()
		new_graph_edit()
	
	match file_dialog.file_mode:
		FileDialog.FILE_MODE_SAVE_FILE:
			FileAccess.open(path, FileAccess.WRITE)
			file_selected(path, 0)
		FileDialog.FILE_MODE_OPEN_FILE:
			file_selected(path, 1)

func _on_graph_edit_connection_to_empty(from_node, from_port, _release_position):
	graph_node_selecter.position = get_viewport().get_mouse_position()
	graph_node_selecter.show()
	
	picker_from_node = from_node
	picker_from_port = from_port
	picker_position = (get_local_mouse_position() + get_current_graph_edit().scroll_offset) / get_current_graph_edit().zoom
	
	picker_mode = true
	$NoInteractions.show()


func disable_picker_mode():
	graph_node_selecter.hide()
	picker_mode = false
	$NoInteractions.hide()


func _on_graph_node_selecter_focus_exited():
	disable_picker_mode()


func _on_graph_node_selecter_close_requested():
	disable_picker_mode()


func tab_changed(_idx):
	if tab_bar.get_tab_title(tab_bar.current_tab) != "+":
		for ge in graph_edits.get_children():
			if graph_edits.get_child(tab_bar.current_tab) == ge:
				ge.visible = true
				if ge.graphnode_selected:
					side_panel_node.on_graph_node_selected(ge.active_graphnode, true)
					side_panel_node.show()
				else:
					side_panel_node.hide()
			else:
				ge.visible = false
		return
	
	new_graph_edit()
	var welcome_close_button = $WelcomeWindow/PanelContainer/CloseButton
	if tab_bar.tab_count > 1:
		welcome_close_button.show()
	else:
		welcome_close_button.hide()
	$WelcomeWindow.show()
	$NoInteractions.show()
	side_panel_node.hide()


func connect_graph_edit_signal(graph_edit: GraphEdit) -> void:
	graph_edit.connect("connection_to_empty", _on_graph_edit_connection_to_empty)
	graph_edit.connect("connection_request", _on_graph_edit_connection_request)
	graph_edit.connect("disconnection_request", _on_graph_edit_disconnection_request)
	graph_edit.connect("node_selected", side_panel_node.on_graph_node_selected)
	graph_edit.connect("node_deselected", side_panel_node.on_graph_node_deselected)

func close_welcome_tab():
	# check number of tabs as safety measure and for future hotkey command
	if tab_bar.tab_count > 1:
		tab_bar.select_previous_available()
		$WelcomeWindow.hide()
		$NoInteractions.hide()

func tab_close_pressed(tab):
	var ge = graph_edits.get_child(tab)
	graph_edits.get_child(tab).queue_free()
	await ge.tree_exited  # buggy if we switch tabs without waiting
	tab_bar.remove_tab(tab)

func _on_file_id_pressed(id):
	match id:
		0: # Open file
			is_header_file_operation = true
			open_file_select()

		1: # New file
			is_header_file_operation = true
			new_file_select()

		3: # Config
			side_panel_node.show_config()

		4: # Test
			GlobalSignal.emit("test_trigger")

func new_graph_edit():
	var graph_edit: GraphEdit = graph_edit_inst.instantiate()
	var new_root_node = root_node.instantiate()
	
	graph_edit.name = "new"
	connect_graph_edit_signal(graph_edit)
	
	graph_edits.add_child(graph_edit)
	graph_edit.add_child(new_root_node)
	
	for ge in graph_edits.get_children():
		ge.visible = ge == graph_edit


func _on_new_file_btn_pressed():
	is_header_file_operation = false
	new_file_select()


func _on_open_file_btn_pressed():
	is_header_file_operation = false
	open_file_select()


func _on_help_id_pressed(id):
	match id:
		0:
			OS.shell_open("https://github.com/atomic-junky/Monologue/wiki")
