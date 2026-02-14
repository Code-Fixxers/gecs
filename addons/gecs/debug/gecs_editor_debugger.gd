@tool
class_name GECSEditorDebugger
extends EditorDebuggerPlugin

## The Debugger session for the current game
var session: EditorDebuggerSession
## The tab that will be added to the debugger window
var debugger_tab: GECSEditorDebuggerTab = preload("res://addons/gecs/debug/gecs_editor_debugger_tab.tscn").instantiate()

## Query Playground panel (additional debugger tab)
var query_playground: GECSQueryPlayground
## Component Change Journal panel (additional debugger tab)
var component_journal: GECSComponentJournal

## The centralized data model for the editor
var editor_data: GECSEditorData = GECSEditorData.new()

## The debugger messages that will be sent to the editor debugger
var Msg := GECSEditorDebuggerMessages.Msg
## Reference to editor interface for selecting nodes
var editor_interface: EditorInterface = null


func _has_capture(capture):
	# Return true if you wish to handle messages with the prefix "gecs:".
	return capture == "gecs"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == Msg.WORLD_INIT:
		editor_data.on_world_init(data[0], data[1])
		return true
	elif message == Msg.SYSTEM_METRIC:
		editor_data.on_system_metric(data[0], data[1], data[2])
		return true
	elif message == Msg.SYSTEM_LAST_RUN_DATA:
		editor_data.on_system_last_run_data(data[0], data[1], data[2])
		return true
	elif message == Msg.SET_WORLD:
		if data.size() == 0:
			return true
		editor_data.on_set_world(data[0], data[1])
		return true
	elif message == Msg.PROCESS_WORLD:
		editor_data.on_process_world(data[0], data[1])
		return true
	elif message == Msg.EXIT_WORLD:
		editor_data.on_exit_world()
		return true
	elif message == Msg.ENTITY_ADDED:
		editor_data.on_entity_added(data[0], data[1])
		return true
	elif message == Msg.ENTITY_REMOVED:
		editor_data.on_entity_removed(data[0], data[1])
		return true
	elif message == Msg.ENTITY_DISABLED:
		editor_data.on_entity_disabled(data[0], data[1])
		return true
	elif message == Msg.ENTITY_ENABLED:
		editor_data.on_entity_enabled(data[0], data[1])
		return true
	elif message == Msg.SYSTEM_ADDED:
		editor_data.on_system_added(data[0], data[1], data[2], data[3], data[4], data[5])
		return true
	elif message == Msg.SYSTEM_REMOVED:
		editor_data.on_system_removed(data[0], data[1])
		return true
	elif message == Msg.ENTITY_COMPONENT_ADDED:
		editor_data.on_component_added(data[0], data[1], data[2], data[3])
		return true
	elif message == Msg.ENTITY_COMPONENT_REMOVED:
		editor_data.on_component_removed(data[0], data[1])
		return true
	elif message == Msg.ENTITY_RELATIONSHIP_ADDED:
		editor_data.on_relationship_added(data[0], data[1], data[2])
		return true
	elif message == Msg.ENTITY_RELATIONSHIP_REMOVED:
		editor_data.on_relationship_removed(data[0], data[1])
		return true
	elif message == Msg.COMPONENT_PROPERTY_CHANGED:
		editor_data.on_component_property_changed(data[0], data[1], data[2], data[3], data[4])
		return true
	return false


func _setup_session(session_id):
	# Add a new tab in the debugger session UI containing a label.
	debugger_tab.name = "GECS" # Will be used as the tab title.
	session = get_session(session_id)
	# Pass session reference to the tab for sending messages
	debugger_tab.set_debugger_session(session)
	# Pass editor interface to the tab for selecting nodes
	debugger_tab.set_editor_interface(editor_interface)
	# Pass editor data model
	if debugger_tab.has_method("set_editor_data"):
		debugger_tab.set_editor_data(editor_data)

	# Listens to the session started and stopped signals.
	if not session.started.is_connected(_on_session_started):
		session.started.connect(_on_session_started)
	if not session.stopped.is_connected(_on_session_stopped):
		session.stopped.connect(_on_session_stopped)
	session.add_session_tab(debugger_tab)

	# Create and add Query Playground tab
	query_playground = GECSQueryPlayground.new()
	query_playground.name = "Query Playground"
	if query_playground.has_method("set_editor_data"):
		query_playground.set_editor_data(editor_data)
	session.add_session_tab(query_playground)

	# Create and add Component Journal tab
	component_journal = GECSComponentJournal.new()
	component_journal.name = "Component Journal"
	if component_journal.has_method("set_editor_data"):
		component_journal.set_editor_data(editor_data)
	session.add_session_tab(component_journal)


func _on_session_started():
	print("GECS Debug Session started")
	editor_data.clear()
	# The tabs will clear themselves via signals or we can notify them if needed,
	# but clearing data should be enough if they react to it.
	# Actually, tabs might need to know session started to reset their UI state (like filters).
	# For now, let's rely on them clearing when data is cleared or explicitly calling clear if they have it.

	if debugger_tab.has_method("clear_all_data"):
		debugger_tab.clear_all_data()

	if component_journal.has_method("reset_session"):
		component_journal.reset_session()

	# debugger_tab.active = true # Managed internally or by data presence


func _on_session_stopped():
	print("GECS Debug Session stopped")
	# debugger_tab.active = false
