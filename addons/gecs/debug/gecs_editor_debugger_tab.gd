@tool
class_name GECSEditorDebuggerTab
extends Control

@onready var query_builder_check_box: CheckBox = %QueryBuilderCheckBox
@onready var entities_filter_line_edit: LineEdit = %EntitiesQueryLineEdit
@onready var systems_filter_line_edit: LineEdit = %SystemsQueryLineEdit
@onready var collapse_all_btn: Button = %CollapseAllBtn
@onready var expand_all_btn: Button = %ExpandAllBtn
@onready var systems_collapse_all_btn: Button = %SystemsCollapseAllBtn
@onready var systems_expand_all_btn: Button = %SystemsExpandAllBtn
@onready var pop_out_btn: Button = %PopOutBtn

var editor_data: GECSEditorData = null

var timer = 5
var active := false
var _popup_window: Window = null
var _debugger_session: EditorDebuggerSession = null

@onready var system_tree: Tree = %SystemsTree
@onready var entities_tree: Tree = %EntitiesTree
@onready var entity_status_bar: TextEdit = %EntityStatusBar
@onready var systems_status_bar: TextEdit = %SystemsStatusBar
@onready var debug_mode_overlay: Panel = %DebugModeOverlay

# Sorting state
var _system_sort_column: int = -1 # -1 means no sorting
var _system_sort_ascending: bool = true
var _entity_sort_column: int = -1 # -1 means no sorting
var _entity_sort_ascending: bool = true

# Pinned items
var _pinned_entities: Dictionary = {} # entity_id -> bool
var _pinned_systems: Dictionary = {} # system_id -> bool

# Icon constants (using Unicode characters)
const ICON_ENTITY = "📦" # Entity icon
const ICON_COMPONENT = "🔧" # Component icon
const ICON_FLAG = "🚩" # Flag component (no properties)
const ICON_RELATIONSHIP = "🔗" # Relationship icon
const ICON_PIN = "📌" # Pinned item icon


func _ready() -> void:
	_update_debug_mode_overlay()
	_setup_ui()


func _process(delta: float) -> void:
	pass


func _setup_ui() -> void:
	if system_tree:
		# Five columns: name, group, execution time, status, and order
		system_tree.columns = 5
		system_tree.set_column_expand(0, true) # Name column expands
		system_tree.set_column_expand(1, false) # Group column resizable
		system_tree.set_column_expand(2, false) # Execution time column resizable
		system_tree.set_column_expand(3, false) # Status column resizable
		system_tree.set_column_expand(4, false) # Order column resizable

		# Set column widths
		system_tree.set_column_custom_minimum_width(1, 100) # Group: 100px min
		system_tree.set_column_custom_minimum_width(2, 100) # Execution time: 100px min
		system_tree.set_column_custom_minimum_width(3, 100) # Status: 100px min
		system_tree.set_column_custom_minimum_width(4, 60) # Order: 60px min

		# Enable column resizing (clip content allows manual resizing)
		system_tree.set_column_clip_content(0, true)
		system_tree.set_column_clip_content(1, true)
		system_tree.set_column_clip_content(2, true)
		system_tree.set_column_clip_content(3, true)
		system_tree.set_column_clip_content(4, true)

		# Set column titles (clickable for sorting)
		system_tree.set_column_title(0, "Name")
		system_tree.set_column_title(1, "Group")
		system_tree.set_column_title(2, "Time (ms)")
		system_tree.set_column_title(3, "Status")
		system_tree.set_column_title(4, "Order")
		system_tree.set_column_titles_visible(true)

		# Create root item
		if system_tree.get_root() == null:
			system_tree.create_item()
	if entities_tree:
		# Four columns: name, components count, relationships count, nodes count
		entities_tree.columns = 4
		entities_tree.set_column_expand(0, true) # Name column expands
		entities_tree.set_column_expand(1, false) # Components count resizable
		entities_tree.set_column_expand(2, false) # Relationships count resizable
		entities_tree.set_column_expand(3, false) # Nodes count resizable

		# Set column widths
		entities_tree.set_column_custom_minimum_width(1, 80) # Components: 80px min
		entities_tree.set_column_custom_minimum_width(2, 80) # Relationships: 80px min
		entities_tree.set_column_custom_minimum_width(3, 80) # Nodes: 80px min

		# Enable column resizing (clip content allows manual resizing)
		entities_tree.set_column_clip_content(0, true)
		entities_tree.set_column_clip_content(1, true)
		entities_tree.set_column_clip_content(2, true)
		entities_tree.set_column_clip_content(3, true)

		# Set column titles
		entities_tree.set_column_title(0, "Entity")
		entities_tree.set_column_title(1, "Comps")
		entities_tree.set_column_title(2, "Rels")
		entities_tree.set_column_title(3, "Nodes")
		entities_tree.set_column_titles_visible(true)

		# Create root item
		if entities_tree.get_root() == null:
			entities_tree.create_item()

	if entities_filter_line_edit and not entities_filter_line_edit.text_changed.is_connected(_on_entities_filter_changed):
		entities_filter_line_edit.text_changed.connect(_on_entities_filter_changed)
	if systems_filter_line_edit and not systems_filter_line_edit.text_changed.is_connected(_on_systems_filter_changed):
		systems_filter_line_edit.text_changed.connect(_on_systems_filter_changed)
	if collapse_all_btn and not collapse_all_btn.pressed.is_connected(_on_collapse_all_pressed):
		collapse_all_btn.pressed.connect(_on_collapse_all_pressed)
	if expand_all_btn and not expand_all_btn.pressed.is_connected(_on_expand_all_pressed):
		expand_all_btn.pressed.connect(_on_expand_all_pressed)
	if systems_collapse_all_btn and not systems_collapse_all_btn.pressed.is_connected(_on_systems_collapse_all_pressed):
		systems_collapse_all_btn.pressed.connect(_on_systems_collapse_all_pressed)
	if systems_expand_all_btn and not systems_expand_all_btn.pressed.is_connected(_on_systems_expand_all_pressed):
		systems_expand_all_btn.pressed.connect(_on_systems_expand_all_pressed)
	if pop_out_btn and not pop_out_btn.pressed.is_connected(_on_pop_out_pressed):
		pop_out_btn.pressed.connect(_on_pop_out_pressed)
	# Connect to system tree for clicking (single click to toggle)
	if system_tree and not system_tree.item_mouse_selected.is_connected(_on_system_tree_item_mouse_selected):
		system_tree.item_mouse_selected.connect(_on_system_tree_item_mouse_selected)
	# Connect to system tree for column clicking (for sorting)
	if system_tree and not system_tree.column_title_clicked.is_connected(_on_system_tree_column_clicked):
		system_tree.column_title_clicked.connect(_on_system_tree_column_clicked)
	# Connect to entities tree for column clicking (for sorting)
	if entities_tree and not entities_tree.column_title_clicked.is_connected(_on_entities_tree_column_clicked):
		entities_tree.column_title_clicked.connect(_on_entities_tree_column_clicked)
	# Connect to entities tree for right-click context menu
	if entities_tree and not entities_tree.item_mouse_selected.is_connected(_on_entities_tree_item_mouse_selected):
		entities_tree.item_mouse_selected.connect(_on_entities_tree_item_mouse_selected)
	# Connect to entities tree item_edited signal for live property editing
	if entities_tree and not entities_tree.item_edited.is_connected(_on_entity_property_edited):
		entities_tree.item_edited.connect(_on_entity_property_edited)
	# Connect to system tree for right-click context menu
	if system_tree and not system_tree.button_clicked.is_connected(_on_system_tree_button_clicked):
		system_tree.button_clicked.connect(_on_system_tree_button_clicked)


func _update_debug_mode_overlay() -> void:
	if not debug_mode_overlay:
		return

	# Check if debug mode is enabled in project settings
	var debug_enabled = ProjectSettings.get_setting(GecsSettings.SETTINGS_DEBUG_MODE, false)

	# Show overlay if debug mode is disabled, hide if enabled
	debug_mode_overlay.visible = not debug_enabled


# --- External setters expected by debugger plugin ---
func set_debugger_session(_session):
	_debugger_session = _session


func set_editor_interface(_editor_interface):
	pass


func set_editor_data(data: GECSEditorData) -> void:
	editor_data = data
	if not editor_data:
		return

	# Connect signals
	if not editor_data.world_init.is_connected(_on_world_init):
		editor_data.world_init.connect(_on_world_init)
	if not editor_data.set_world.is_connected(_on_set_world):
		editor_data.set_world.connect(_on_set_world)
	if not editor_data.process_world.is_connected(_on_process_world):
		editor_data.process_world.connect(_on_process_world)
	if not editor_data.exit_world.is_connected(_on_exit_world):
		editor_data.exit_world.connect(_on_exit_world)

	if not editor_data.entity_added.is_connected(_on_entity_added):
		editor_data.entity_added.connect(_on_entity_added)
	if not editor_data.entity_removed.is_connected(_on_entity_removed):
		editor_data.entity_removed.connect(_on_entity_removed)
	if not editor_data.entity_disabled.is_connected(_on_entity_disabled):
		editor_data.entity_disabled.connect(_on_entity_disabled)
	if not editor_data.entity_enabled.is_connected(_on_entity_enabled):
		editor_data.entity_enabled.connect(_on_entity_enabled)

	if not editor_data.system_added.is_connected(_on_system_added):
		editor_data.system_added.connect(_on_system_added)
	if not editor_data.system_removed.is_connected(_on_system_removed):
		editor_data.system_removed.connect(_on_system_removed)
	if not editor_data.system_metric.is_connected(_on_system_metric):
		editor_data.system_metric.connect(_on_system_metric)
	if not editor_data.system_last_run_data.is_connected(_on_system_last_run_data):
		editor_data.system_last_run_data.connect(_on_system_last_run_data)

	if not editor_data.component_added.is_connected(_on_component_added):
		editor_data.component_added.connect(_on_component_added)
	if not editor_data.component_removed.is_connected(_on_component_removed):
		editor_data.component_removed.connect(_on_component_removed)
	if not editor_data.component_property_changed.is_connected(_on_component_property_changed):
		editor_data.component_property_changed.connect(_on_component_property_changed)

	if not editor_data.relationship_added.is_connected(_on_relationship_added):
		editor_data.relationship_added.connect(_on_relationship_added)
	if not editor_data.relationship_removed.is_connected(_on_relationship_removed):
		editor_data.relationship_removed.connect(_on_relationship_removed)


# Send a message from editor to the running game
func send_to_game(message: String, data: Array = []) -> bool:
	if _debugger_session == null:
		push_warning("GECS Debug: No active debugger session")
		return false
	_debugger_session.send_message(message, data)
	return true


func clear_all_data():
	# UI clear only. Data model is cleared by GECSEditorDebugger.
	# Clear system tree
	if system_tree:
		system_tree.clear()
		system_tree.create_item()

	# Clear entities tree
	if entities_tree:
		entities_tree.clear()
		entities_tree.create_item()

	# Reset status bars
	_update_entity_status_bar()
	_update_systems_status_bar()


# ---- Signal Handlers ----

func _on_world_init(world_id: int, world_path: NodePath):
	_update_debug_mode_overlay()


func _on_set_world(world_id: int, world_path: NodePath):
	pass


func _on_process_world(delta: float, group_name: String):
	pass


func _on_exit_world():
	pass


func _on_entity_added(ent: int, path: NodePath) -> void:
	if not entities_tree:
		return

	var root = entities_tree.get_root()
	if root == null:
		root = entities_tree.create_item()

	var item = entities_tree.create_item(root)
	# Column 0: Entity name with icon (and pin icon if pinned)
	var display_name = ICON_ENTITY + " " + str(path).get_file()
	if _pinned_entities.get(ent, false):
		display_name = ICON_PIN + " " + display_name
	item.set_text(0, display_name)
	item.set_tooltip_text(0, str(ent) + " : " + str(path))
	# Columns 1-3: Counts (will be updated)
	item.set_text(1, "0")
	item.set_text(2, "0")
	item.set_text(3, "0")
	item.set_meta("entity_id", ent)
	item.set_meta("path", path)
	item.collapsed = true # Start collapsed

	# Populate existing components and relationships from editor_data
	if editor_data:
		var entities = editor_data.ecs_data.get("entities", {})
		var entity_data = entities.get(ent, {})
		var components = entity_data.get("components", {})
		for comp_id in components:
			var comp_entry = components[comp_id]
			# Handle wrapped format
			if comp_entry.has("data") and comp_entry.has("path"):
				_attach_component_to_entity_item(item, ent, comp_id, comp_entry["path"], comp_entry["data"])
			else:
				# Fallback if legacy or raw data? Should not happen with new GECSEditorData
				_attach_component_to_entity_item(item, ent, comp_id, "Unknown", comp_entry)

		var relationships = entity_data.get("relationships", {})
		for rel_id in relationships:
			var rel_data = relationships[rel_id]
			_attach_relationship_to_entity_item(item, ent, rel_id, rel_data)

	_update_entity_counts(item, ent)

	# Re-sort if we have an active sort column
	if _entity_sort_column != -1:
		_sort_entity_tree()

	_update_entity_status_bar()


func _on_entity_removed(ent: int, path: NodePath) -> void:
	# Remove from tree
	if entities_tree and entities_tree.get_root():
		var root = entities_tree.get_root()
		var child = root.get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				root.remove_child(child)
				break
			child = child.get_next()

	_pinned_entities.erase(ent)
	_update_entity_status_bar()


func _on_entity_disabled(ent: int, path: NodePath) -> void:
	if entities_tree and entities_tree.get_root():
		var child = entities_tree.get_root().get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				child.set_text(0, child.get_text(0) + " (disabled)")
				break
			child = child.get_next()


func _on_entity_enabled(ent: int, path: NodePath) -> void:
	if entities_tree and entities_tree.get_root():
		var child = entities_tree.get_root().get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				# Remove any (disabled) suffix
				var txt = child.get_text(0)
				if txt.ends_with(" (disabled)"):
					child.set_text(0, txt.substr(0, txt.length() - 11))
				break
			child = child.get_next()


func _on_system_added(sys: int, group: String, process_empty: bool, active: bool, paused: bool, path: NodePath) -> void:
	_update_systems_status_bar()


func _on_system_removed(sys: int, path: NodePath) -> void:
	# Clean up pinned state
	_pinned_systems.erase(sys)
	# Remove from tree?
	# Wait, system_last_run_data updates the tree. If system is removed, we should probably remove it from tree.
	if system_tree and system_tree.get_root():
		var root = system_tree.get_root()
		var child = root.get_first_child()
		while child:
			if child.get_meta("system_id", null) == sys:
				root.remove_child(child)
				break
			child = child.get_next()

	_update_systems_status_bar()


func _on_system_metric(system: int, system_name: String, time: float):
	_update_systems_status_bar()


func _on_system_last_run_data(system_id: int, system_name: String, last_run_data: Dictionary):
	if not editor_data:
		return

	var systems_data = editor_data.ecs_data.get("systems", {})
	var sys_entry = systems_data.get(system_id, {})

	# Update or create tree item
	if system_tree:
		var root = system_tree.get_root()
		if root == null:
			root = system_tree.create_item()

		# Try to find existing item by metadata matching system_id
		var existing: TreeItem = null
		var child = root.get_first_child()
		while child != null:
			if child.get_meta("system_id", null) == system_id:
				existing = child
				break
			child = child.get_next()
		if existing == null:
			existing = system_tree.create_item(root)
			existing.set_meta("system_id", system_id)
			existing.collapsed = true # Start collapsed

		# Set main system name in column 0
		var display_name = system_name
		# Check if this system is pinned and update display
		if _pinned_systems.get(system_id, false):
			if not display_name.begins_with(ICON_PIN + " "):
				display_name = ICON_PIN + " " + display_name
		existing.set_text(0, display_name)

		# Set group in column 1
		var group = sys_entry.get("group", "")
		existing.set_text(1, group)

		# Set execution time in column 2
		var exec_ms = last_run_data.get("execution_time_ms", 0.0)
		existing.set_text(2, String.num(exec_ms, 3) + " ms")

		# Set active status in column 3
		var is_active = sys_entry.get("active", true)
		_update_system_active_display(existing, is_active)

		# Get execution order (index in systems array from last_run_data) - column 4
		var execution_order = last_run_data.get("execution_order", -1)
		if execution_order >= 0:
			existing.set_text(4, str(execution_order))
		else:
			existing.set_text(4, "-")

		# Clear previous children to avoid stale data
		var prev_child = existing.get_first_child()
		while prev_child:
			var next_child = prev_child.get_next()
			existing.remove_child(prev_child)
			prev_child = next_child

		# Create nested rows for key info
		var ent_count = last_run_data.get("entity_count", null)
		var arch_count = last_run_data.get("archetype_count", null)
		var parallel = last_run_data.get("parallel", false)
		var nested_data := {
			"execution_time_ms": String.num(exec_ms, 3),
			"entity_count": ent_count,
			"archetype_count": arch_count,
			"parallel": parallel,
		}
		for k in nested_data.keys():
			var v = nested_data[k]
			if v == null:
				continue
			var row = system_tree.create_item(existing)
			row.set_text(0, str(k) + ": " + str(v))
		# Subsystem details (numeric keys in last_run_data)
		for key in last_run_data.keys():
			if typeof(key) == TYPE_INT and last_run_data[key] is Dictionary:
				var sub = last_run_data[key]
				var sub_row = system_tree.create_item(existing)
				sub_row.set_text(0, "subsystem[" + str(key) + "] entity_count: " + str(sub.get("entity_count", 0)))
		# Optionally store raw json in metadata for tooltip or future expansion
		existing.set_meta("last_run_data", last_run_data.duplicate())

	# Re-sort if we have an active sort column
	if _system_sort_column != -1:
		_sort_system_tree()

	# Update status bar with latest system data
	_update_systems_status_bar()


func _on_component_added(ent: int, comp: int, comp_path: String, data: Dictionary):
	if not entities_tree:
		return

	var root = entities_tree.get_root()
	if root != null:
		var entity_item: TreeItem = null
		var child = root.get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				entity_item = child
				break
			child = child.get_next()

		if entity_item:
			# Update or add
			var existing_comp_item: TreeItem = null
			var comp_child = entity_item.get_first_child()
			while comp_child:
				if comp_child.has_meta("component_id") and comp_child.get_meta("component_id") == comp:
					existing_comp_item = comp_child
					break
				comp_child = comp_child.get_next()

			if existing_comp_item:
				# Clear previous property rows
				var prev = existing_comp_item.get_first_child()
				while prev:
					var nxt = prev.get_next()
					existing_comp_item.remove_child(prev)
					prev = nxt
				# Update title/path
				var icon = ICON_FLAG if _is_flag_component(data) else ICON_COMPONENT
				existing_comp_item.set_text(0, icon + " " + comp_path.get_file().get_basename())
				existing_comp_item.set_tooltip_text(0, comp_path)
				existing_comp_item.set_meta("component_path", comp_path)
				_add_serialized_rows(existing_comp_item, data)
			else:
				_attach_component_to_entity_item(entity_item, ent, comp, comp_path, data)

			_update_entity_counts(entity_item, ent)

			if _entity_sort_column != -1:
				_sort_entity_tree()

	_update_entity_status_bar()


func _on_component_removed(ent: int, comp: int):
	if entities_tree and entities_tree.get_root():
		var entity_item: TreeItem = null
		var child = entities_tree.get_root().get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				entity_item = child
				break
			child = child.get_next()
		if entity_item:
			var comp_child = entity_item.get_first_child()
			while comp_child:
				if comp_child.has_meta("component_id") and comp_child.get_meta("component_id") == comp:
					entity_item.remove_child(comp_child)
					break
				comp_child = comp_child.get_next()
			_update_entity_counts(entity_item, ent)

	_update_entity_status_bar()


func _on_component_property_changed(ent: int, comp: int, property_name: String, old_value: Variant, new_value: Variant):
	if entities_tree and entities_tree.get_root():
		var entity_item: TreeItem = null
		var child = entities_tree.get_root().get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				entity_item = child
				break
			child = child.get_next()
		if entity_item:
			var comp_child = entity_item.get_first_child()
			while comp_child:
				if comp_child.has_meta("component_id") and comp_child.get_meta("component_id") == comp:
					var prop_row = comp_child.get_first_child()
					var updated := false
					while prop_row:
						if prop_row.has_meta("property_name") and prop_row.get_meta("property_name") == property_name:
							# Update value
							_update_editable_row_value(prop_row, property_name, new_value)
							updated = true
							break
						prop_row = prop_row.get_next()
					if not updated:
						# If not found, add it
						var new_row = entities_tree.create_item(comp_child)
						new_row.set_meta("property_name", property_name)
						_make_editable_row(new_row, property_name, new_value, comp_child)
					break
				comp_child = comp_child.get_next()


func _on_relationship_added(ent: int, rel: int, rel_data: Dictionary):
	if entities_tree:
		var root = entities_tree.get_root()
		if root != null:
			var entity_item: TreeItem = null
			var child = root.get_first_child()
			while child:
				if child.get_meta("entity_id", null) == ent:
					entity_item = child
					break
				child = child.get_next()

			if entity_item:
				# Find or create
				var existing_rel_item: TreeItem = null
				var rel_child = entity_item.get_first_child()
				while rel_child:
					if rel_child.has_meta("relationship_id") and rel_child.get_meta("relationship_id") == rel:
						existing_rel_item = rel_child
						break
					rel_child = rel_child.get_next()

				if existing_rel_item:
					# Clear and rebuild
					var prev = existing_rel_item.get_first_child()
					while prev:
						var nxt = prev.get_next()
						existing_rel_item.remove_child(prev)
						prev = nxt
					_update_relationship_item(existing_rel_item, rel_data)
				else:
					_attach_relationship_to_entity_item(entity_item, ent, rel, rel_data)

				_update_entity_counts(entity_item, ent)

	if _entity_sort_column != -1:
		_sort_entity_tree()

	_update_entity_status_bar()


func _on_relationship_removed(ent: int, rel: int):
	if entities_tree and entities_tree.get_root():
		var entity_item: TreeItem = null
		var child = entities_tree.get_root().get_first_child()
		while child:
			if child.get_meta("entity_id", null) == ent:
				entity_item = child
				break
			child = child.get_next()

		if entity_item:
			var rel_child = entity_item.get_first_child()
			while rel_child:
				if rel_child.has_meta("relationship_id") and rel_child.get_meta("relationship_id") == rel:
					entity_item.remove_child(rel_child)
					break
				rel_child = rel_child.get_next()
			_update_entity_counts(entity_item, ent)

	_update_entity_status_bar()


# ---- Helpers ----

func _attach_component_to_entity_item(entity_item: TreeItem, ent: int, comp: int, comp_path: String, final_data: Dictionary) -> void:
	var comp_item = entities_tree.create_item(entity_item)
	var icon = ICON_FLAG if _is_flag_component(final_data) else ICON_COMPONENT
	comp_item.set_text(0, icon + " " + comp_path.get_file().get_basename())
	comp_item.set_tooltip_text(0, comp_path)
	comp_item.set_meta("component_id", comp)
	comp_item.set_meta("component_path", comp_path)
	comp_item.collapsed = true
	_add_serialized_rows(comp_item, final_data)


func _attach_relationship_to_entity_item(entity_item: TreeItem, ent: int, rel: int, rel_data: Dictionary) -> void:
	var rel_item = entities_tree.create_item(entity_item)
	rel_item.set_meta("relationship_id", rel)
	rel_item.collapsed = true
	_update_relationship_item(rel_item, rel_data)


func _update_relationship_item(rel_item: TreeItem, rel_data: Dictionary):
	var relation_type = rel_data.get("relation_type", "Unknown")
	var target_type = rel_data.get("target_type", "Unknown")

	var title = ICON_RELATIONSHIP + " " + relation_type + " -> "
	if target_type == "Entity":
		var target_data = rel_data.get("target_data", {})
		title += "Entity " + str(target_data.get("path", "Unknown"))
	elif target_type == "Component":
		var target_data = rel_data.get("target_data", {})
		title += target_data.get("type", "Unknown")
	elif target_type == "Archetype":
		var target_data = rel_data.get("target_data", {})
		var script_path = target_data.get("script_path", "")
		title += "Archetype " + script_path.get_file().get_basename()
	elif target_type == "null":
		title += "Wildcard"
	else:
		title += target_type

	rel_item.set_text(0, title)

	var relation_data = rel_data.get("relation_data", {})
	if not relation_data.is_empty():
		var rel_data_item = entities_tree.create_item(rel_item)
		rel_data_item.set_text(0, "Relation Properties:")
		_add_serialized_rows(rel_data_item, relation_data)

	if target_type == "Component":
		var target_data = rel_data.get("target_data", {})
		var target_comp_data = target_data.get("data", {})
		if not target_comp_data.is_empty():
			var target_data_item = entities_tree.create_item(rel_item)
			target_data_item.set_text(0, "Target Properties:")
			_add_serialized_rows(target_data_item, target_comp_data)


func _is_flag_component(component_data: Dictionary) -> bool:
	if component_data.is_empty():
		return true
	if component_data.size() == 1 and component_data.has("<no_serialized_properties>"):
		return true
	return false


func _update_entity_counts(entity_item: TreeItem, ent_id: int):
	# Update the count columns for an entity based on CHILDREN in the tree
	# This matches visual state rather than data state (which might be async)
	if not entity_item:
		return

	# Count child items
	var comp_count = 0
	var rel_count = 0

	var child = entity_item.get_first_child()
	while child:
		if child.has_meta("component_id"):
			comp_count += 1
		elif child.has_meta("relationship_id"):
			rel_count += 1
		child = child.get_next()

	entity_item.set_text(1, str(comp_count))
	entity_item.set_text(2, str(rel_count))
	# Nodes count is always 0 as GECS doesn't track nodes in this view currently
	entity_item.set_text(3, str(comp_count + rel_count))


func _update_entity_status_bar():
	if not entity_status_bar or not editor_data:
		return

	var entities = editor_data.ecs_data.get("entities", {})
	var entity_count = entities.size()

	var total_components = 0
	for entity_data in entities.values():
		var components = entity_data.get("components", {})
		total_components += components.size()

	var total_relationships = 0
	for entity_data in entities.values():
		var relationships = entity_data.get("relationships", {})
		total_relationships += relationships.size()

	entity_status_bar.text = "Entities: %d | Components: %d | Relationships: %d" % [
		entity_count,
		total_components,
		total_relationships
	]


func _update_systems_status_bar():
	if not systems_status_bar or not editor_data:
		return

	var systems_data = editor_data.ecs_data.get("systems", {})
	var system_count = systems_data.size()

	var total_time_ms = 0.0
	var most_expensive_name = ""
	var most_expensive_time = 0.0

	for system_id in systems_data.keys():
		var system_data = systems_data[system_id]
		var last_run_data = system_data.get("last_run_data", {})
		var exec_time_ms = last_run_data.get("execution_time_ms", 0.0)

		total_time_ms += exec_time_ms

		if exec_time_ms > most_expensive_time:
			most_expensive_time = exec_time_ms
			var system_name = last_run_data.get("system_name", "")
			if not system_name:
				var path = system_data.get("path", "")
				if path:
					system_name = str(path).get_file().get_basename()
				else:
					system_name = "System_%d" % system_id
			most_expensive_name = system_name

	if most_expensive_name:
		systems_status_bar.text = "Systems: %d | Total ms: %.1fms | Most Expensive: %s (%.1fms)" % [
			system_count,
			total_time_ms,
			most_expensive_name,
			most_expensive_time
		]
	else:
		systems_status_bar.text = "Systems: %d | Total ms: %.1fms" % [
			system_count,
			total_time_ms
		]


# ---- UI Logic (Filters, Sorting, Pinning, Toggling) ----
# Copied from original but cleaned up

func _on_entities_filter_changed(new_text: String):
	_refresh_entity_tree_filter()


func _on_systems_filter_changed(new_text: String):
	_refresh_system_tree_filter()


func _on_collapse_all_pressed():
	if not entities_tree: return
	var item = entities_tree.get_root().get_first_child()
	while item:
		_collapse_item_recursive(item)
		item = item.get_next()


func _on_expand_all_pressed():
	if not entities_tree: return
	var item = entities_tree.get_root().get_first_child()
	while item:
		_expand_item_recursive(item)
		item = item.get_next()


func _on_systems_collapse_all_pressed():
	if not system_tree: return
	var item = system_tree.get_root().get_first_child()
	while item:
		_collapse_item_recursive(item)
		item = item.get_next()


func _on_systems_expand_all_pressed():
	if not system_tree: return
	var item = system_tree.get_root().get_first_child()
	while item:
		_expand_item_recursive(item)
		item = item.get_next()


func _collapse_item_recursive(item: TreeItem):
	if item == null: return
	item.collapsed = true
	var child = item.get_first_child()
	while child:
		_collapse_item_recursive(child)
		child = child.get_next()


func _expand_item_recursive(item: TreeItem):
	if item == null: return
	item.collapsed = false
	var child = item.get_first_child()
	while child:
		_expand_item_recursive(child)
		child = child.get_next()


func _refresh_system_tree_filter():
	if not system_tree: return
	var root = system_tree.get_root()
	if root == null: return
	var filter = systems_filter_line_edit.text.to_lower() if systems_filter_line_edit else ""
	var item = root.get_first_child()
	while item:
		var name = item.get_text(0).to_lower()
		item.visible = filter == "" or name.find(filter) != -1
		item = item.get_next()


func _refresh_entity_tree_filter():
	if not entities_tree: return
	var root = entities_tree.get_root()
	if root == null: return
	var filter = entities_filter_line_edit.text.to_lower() if entities_filter_line_edit else ""
	var item = root.get_first_child()
	while item:
		var label = item.get_text(0).to_lower()
		var matches = filter == "" or label.find(filter) != -1
		if not matches:
			var comp_child = item.get_first_child()
			while comp_child and not matches:
				if comp_child.get_text(0).to_lower().find(filter) != -1:
					matches = true
					break
				var prop_row = comp_child.get_first_child()
				while prop_row and not matches:
					if prop_row.get_text(0).to_lower().find(filter) != -1:
						matches = true
						break
					prop_row = prop_row.get_next()
				comp_child = comp_child.get_next()
		item.visible = matches
		item = item.get_next()


func _on_pop_out_pressed():
	if _popup_window != null:
		_on_popup_window_closed()
		return
	_popup_window = Window.new()
	_popup_window.title = "GECS Debug Viewer"
	_popup_window.size = Vector2i(1200, 800)
	_popup_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	var hsplit = get_node("HSplit")
	remove_child(hsplit)
	_popup_window.add_child(hsplit)
	add_child(_popup_window)
	_popup_window.close_requested.connect(_on_popup_window_closed)
	_popup_window.show()
	pop_out_btn.text = "Pop In"


func _on_popup_window_closed():
	if _popup_window != null:
		var hsplit = _popup_window.get_node("HSplit")
		_popup_window.remove_child(hsplit)
		add_child(hsplit)
		move_child(hsplit, 0)
		_popup_window.queue_free()
		_popup_window = null
		pop_out_btn.text = "Pop Out"


func _on_system_tree_item_mouse_selected(position: Vector2, mouse_button_index: int):
	var selected = system_tree.get_selected()
	if not selected: return
	var system_id = selected.get_meta("system_id", null)
	if system_id == null: return
	if selected.get_parent() == system_tree.get_root():
		if mouse_button_index == MOUSE_BUTTON_LEFT:
			var column = system_tree.get_column_at_position(position)
			if column == 3: # Status column
				_toggle_system_active()
		elif mouse_button_index == MOUSE_BUTTON_RIGHT:
			_show_system_context_menu(selected, position)


func _on_system_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int):
	pass


func _on_entities_tree_item_mouse_selected(position: Vector2, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_RIGHT: return
	var selected = entities_tree.get_selected()
	if not selected: return
	var entity_id = selected.get_meta("entity_id", null)
	if entity_id == null: return
	if selected.get_parent() == entities_tree.get_root():
		_show_entity_context_menu(selected, position)


func _show_entity_context_menu(item: TreeItem, position: Vector2):
	var entity_id = item.get_meta("entity_id", null)
	if entity_id == null: return
	var popup = PopupMenu.new()
	add_child(popup)
	var is_pinned = _pinned_entities.get(entity_id, false)
	popup.add_item("Unpin Entity" if is_pinned else "Pin Entity", 0)
	var screen_pos = entities_tree.get_screen_position() + position
	popup.position = screen_pos
	popup.popup()
	popup.id_pressed.connect(func(id):
		if id == 0: _toggle_entity_pin(entity_id, item)
		popup.queue_free()
	)
	popup.popup_hide.connect(func(): if is_instance_valid(popup): popup.queue_free())


func _show_system_context_menu(item: TreeItem, position: Vector2):
	var system_id = item.get_meta("system_id", null)
	if system_id == null: return
	var popup = PopupMenu.new()
	add_child(popup)
	var is_pinned = _pinned_systems.get(system_id, false)
	popup.add_item("Unpin System" if is_pinned else "Pin System", 0)
	var screen_pos = system_tree.get_screen_position() + position
	popup.position = screen_pos
	popup.popup()
	popup.id_pressed.connect(func(id):
		if id == 0: _toggle_system_pin(system_id, item)
		popup.queue_free()
	)
	popup.popup_hide.connect(func(): if is_instance_valid(popup): popup.queue_free())


func _toggle_entity_pin(entity_id: int, item: TreeItem):
	var is_pinned = _pinned_entities.get(entity_id, false)
	_pinned_entities[entity_id] = not is_pinned
	_update_entity_pin_display(item, not is_pinned)
	if _entity_sort_column != -1 or not is_pinned:
		_sort_entity_tree()


func _toggle_system_pin(system_id: int, item: TreeItem):
	var is_pinned = _pinned_systems.get(system_id, false)
	_pinned_systems[system_id] = not is_pinned
	_update_system_pin_display(item, not is_pinned)
	if _system_sort_column != -1 or not is_pinned:
		_sort_system_tree()


func _update_entity_pin_display(item: TreeItem, is_pinned: bool):
	var current_text = item.get_text(0)
	if current_text.begins_with(ICON_PIN + " "):
		current_text = current_text.substr(2)
	if is_pinned:
		item.set_text(0, ICON_PIN + " " + current_text)
	else:
		item.set_text(0, current_text)


func _update_system_pin_display(item: TreeItem, is_pinned: bool):
	var current_text = item.get_text(0)
	if current_text.begins_with(ICON_PIN + " "):
		current_text = current_text.substr(2)
	if is_pinned:
		item.set_text(0, ICON_PIN + " " + current_text)
	else:
		item.set_text(0, current_text)


func _toggle_system_active():
	var selected = system_tree.get_selected()
	if not selected: return
	var system_id = selected.get_meta("system_id", null)
	if system_id == null: return
	if not editor_data: return

	var systems_data = editor_data.ecs_data.get("systems", {})
	var system_data = systems_data.get(system_id, {})
	var current_active = system_data.get("active", true)
	var new_active = not current_active

	send_to_game("gecs:set_system_active", [system_id, new_active])

	# Optimistically update
	system_data["active"] = new_active
	_update_system_active_display(selected, new_active)


func _update_system_active_display(system_item: TreeItem, is_active: bool):
	if is_active:
		system_item.set_text(3, "ACTIVE")
		system_item.set_custom_color(3, Color(0.5, 1.0, 0.5))
	else:
		system_item.set_text(3, "INACTIVE")
		system_item.set_custom_color(3, Color(1.0, 0.3, 0.3))
	system_item.set_cell_mode(3, TreeItem.CELL_MODE_STRING)
	system_item.set_selectable(3, true)
	system_item.set_editable(3, false)


func _on_system_tree_column_clicked(column: int, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT: return
	if _system_sort_column == column:
		if _system_sort_ascending: _system_sort_ascending = false
		else:
			_system_sort_column = -1
			_system_sort_ascending = true
	else:
		_system_sort_column = column
		_system_sort_ascending = true
	_update_system_column_indicators()
	_sort_system_tree()


func _update_system_column_indicators():
	for i in range(5):
		var title = ""
		match i:
			0: title = "Name"
			1: title = "Group"
			2: title = "Time (ms)"
			3: title = "Status"
			4: title = "Order"
		if i == _system_sort_column:
			title += " ▲" if _system_sort_ascending else " ▼"
		system_tree.set_column_title(i, title)


func _sort_system_tree():
	if not system_tree: return
	var root = system_tree.get_root()
	if not root: return
	var systems: Array = []
	var pinned_systems: Array = []
	var child = root.get_first_child()
	while child:
		var system_id = child.get_meta("system_id", null)
		var system_data = {
			"item": child,
			"name": child.get_text(0),
			"group": child.get_text(1),
			"time": 0.0,
			"status": child.get_text(3),
			"order": int(child.get_text(4)) if child.get_text(4).is_valid_int() else 0,
			"system_id": system_id,
			"is_pinned": _pinned_systems.get(system_id, false)
		}
		var time_text = child.get_text(2)
		if time_text: system_data["time"] = float(time_text.replace(" ms", ""))
		if system_data["is_pinned"]: pinned_systems.append(system_data)
		else: systems.append(system_data)
		child = child.get_next()

	if _system_sort_column != -1:
		var sort_func = func(a, b): return 0
		match _system_sort_column:
			0: sort_func = func(a, b): return a["name"].nocasecmp_to(b["name"])
			1: sort_func = func(a, b): return a["group"].nocasecmp_to(b["group"])
			2: sort_func = func(a, b): return 1 if a["time"] > b["time"] else -1 if a["time"] < b["time"] else 0
			3: sort_func = func(a, b): return a["status"].casecmp_to(b["status"])
			4: sort_func = func(a, b): return 1 if a["order"] > b["order"] else -1 if a["order"] < b["order"] else 0

		if _system_sort_ascending:
			systems.sort_custom(func(a,b): return sort_func.call(a,b) < 0)
		else:
			systems.sort_custom(func(a,b): return sort_func.call(a,b) > 0)

	for system_data in pinned_systems:
		var item = system_data["item"]
		root.remove_child(item)
		root.add_child(item)
	for system_data in systems:
		var item = system_data["item"]
		root.remove_child(item)
		root.add_child(item)


func _on_entities_tree_column_clicked(column: int, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT: return
	if _entity_sort_column == column:
		if _entity_sort_ascending: _entity_sort_ascending = false
		else:
			_entity_sort_column = -1
			_entity_sort_ascending = true
	else:
		_entity_sort_column = column
		_entity_sort_ascending = true
	_update_entity_column_indicators()
	_sort_entity_tree()


func _update_entity_column_indicators():
	for i in range(4):
		var title = ""
		match i:
			0: title = "Entity"
			1: title = "Comps"
			2: title = "Rels"
			3: title = "Nodes"
		if i == _entity_sort_column:
			title += " ▲" if _entity_sort_ascending else " ▼"
		entities_tree.set_column_title(i, title)


func _sort_entity_tree():
	if not entities_tree: return
	var root = entities_tree.get_root()
	if not root: return
	var entities: Array = []
	var pinned_entities: Array = []
	var child = root.get_first_child()
	while child:
		var entity_id = child.get_meta("entity_id", null)
		var entity_data = {
			"item": child,
			"name": child.get_text(0),
			"comps": int(child.get_text(1)),
			"rels": int(child.get_text(2)),
			"nodes": int(child.get_text(3)),
			"entity_id": entity_id,
			"is_pinned": _pinned_entities.get(entity_id, false)
		}
		if entity_data["is_pinned"]: pinned_entities.append(entity_data)
		else: entities.append(entity_data)
		child = child.get_next()

	if _entity_sort_column != -1:
		var sort_func = func(a, b): return 0
		match _entity_sort_column:
			0: sort_func = func(a, b): return a["name"].nocasecmp_to(b["name"])
			1: sort_func = func(a, b): return 1 if a["comps"] > b["comps"] else -1 if a["comps"] < b["comps"] else 0
			2: sort_func = func(a, b): return 1 if a["rels"] > b["rels"] else -1 if a["rels"] < b["rels"] else 0
			3: sort_func = func(a, b): return 1 if a["nodes"] > b["nodes"] else -1 if a["nodes"] < b["nodes"] else 0

		if _entity_sort_ascending:
			entities.sort_custom(func(a,b): return sort_func.call(a,b) < 0)
		else:
			entities.sort_custom(func(a,b): return sort_func.call(a,b) > 0)

	for entity_data in pinned_entities:
		var item = entity_data["item"]
		root.remove_child(item)
		root.add_child(item)
	for entity_data in entities:
		var item = entity_data["item"]
		root.remove_child(item)
		root.add_child(item)


# ---- Recursive Serialization Rendering ----
func _add_serialized_rows(parent_item: TreeItem, data: Dictionary):
	for key in data.keys():
		var value = data[key]
		var row = entities_tree.create_item(parent_item)
		row.set_meta("property_name", key)

		# Make leaf values editable based on type; complex types remain read-only
		if value is Dictionary:
			row.set_text(0, str(key) + ": " + _value_to_string(value))
			_add_serialized_rows(row, value)
		elif value is Array:
			row.set_text(0, str(key) + ": " + _value_to_string(value))
			_add_array_rows(row, value)
		else:
			_make_editable_row(row, key, value, parent_item)


func _add_array_rows(parent_item: TreeItem, arr: Array):
	for i in range(arr.size()):
		var value = arr[i]
		var row = entities_tree.create_item(parent_item)
		row.set_text(0, "[" + str(i) + "] " + _value_to_string(value))
		row.set_meta("property_name", str(i))
		if value is Dictionary:
			_add_serialized_rows(row, value)
		elif value is Array:
			_add_array_rows(row, value)


func _value_to_string(v):
	match typeof(v):
		TYPE_DICTIONARY:
			return "{...}" # expanded in children
		TYPE_ARRAY:
			return "[..." + str(v.size()) + "]"
		TYPE_STRING:
			return '"' + v + '"'
		TYPE_OBJECT:
			if v is Resource:
				return "Resource(" + v.resource_path.get_file() + ")"
			return str(v)
		_:
			return str(v)


func _make_editable_row(row: TreeItem, key: String, value: Variant, parent_item: TreeItem) -> void:
	match typeof(value):
		TYPE_BOOL:
			row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			row.set_text(0, str(key))
			row.set_checked(0, value)
			row.set_editable(0, true)
		TYPE_INT:
			row.set_cell_mode(0, TreeItem.CELL_MODE_RANGE)
			row.set_text(0, str(key))
			row.set_range_config(0, -999999, 999999, 1)
			row.set_range(0, value)
			row.set_editable(0, true)
			row.set_meta("value_type", TYPE_INT)
		TYPE_FLOAT:
			row.set_cell_mode(0, TreeItem.CELL_MODE_RANGE)
			row.set_text(0, str(key))
			row.set_range_config(0, -999999, 999999, 0.01)
			row.set_range(0, value)
			row.set_editable(0, true)
			row.set_meta("value_type", TYPE_FLOAT)
		TYPE_STRING:
			row.set_text(0, str(key) + ": " + str(value))
			row.set_editable(0, true)
			row.set_meta("editable_string", true)
		_:
			row.set_text(0, str(key) + ": " + _value_to_string(value))

	var entity_item = _find_entity_parent(parent_item)
	if entity_item:
		row.set_meta("entity_id", entity_item.get_meta("entity_id", -1))
	var comp_item = _find_component_parent(parent_item)
	if comp_item:
		row.set_meta("component_id", comp_item.get_meta("component_id", -1))


func _update_editable_row_value(row: TreeItem, key: String, value: Variant) -> void:
	var cell_mode = row.get_cell_mode(0)
	match cell_mode:
		TreeItem.CELL_MODE_CHECK:
			row.set_checked(0, bool(value))
		TreeItem.CELL_MODE_RANGE:
			row.set_range(0, float(value))
		_:
			if row.has_meta("editable_string"):
				row.set_text(0, str(key) + ": " + str(value))
			else:
				row.set_text(0, str(key) + ": " + _value_to_string(value))


func _find_entity_parent(item: TreeItem) -> TreeItem:
	var current = item
	while current:
		if current.has_meta("entity_id"):
			return current
		current = current.get_parent()
	return null


func _find_component_parent(item: TreeItem) -> TreeItem:
	var current = item
	while current:
		if current.has_meta("component_id"):
			return current
		current = current.get_parent()
	return null


func _on_entity_property_edited() -> void:
	var item = entities_tree.get_edited()
	if item == null: return

	var entity_id = item.get_meta("entity_id", -1)
	var component_id = item.get_meta("component_id", -1)
	var property_name = item.get_meta("property_name", "")

	if entity_id == -1 or component_id == -1 or property_name == "":
		return

	var new_value
	var cell_mode = item.get_cell_mode(0)
	match cell_mode:
		TreeItem.CELL_MODE_CHECK:
			new_value = item.is_checked(0)
		TreeItem.CELL_MODE_RANGE:
			new_value = item.get_range(0)
			if item.has_meta("value_type") and item.get_meta("value_type") == TYPE_INT:
				new_value = int(new_value)
		TreeItem.CELL_MODE_STRING:
			var text = item.get_text(0)
			if item.has_meta("editable_string"):
				var colon_pos = text.find(": ")
				if colon_pos >= 0:
					new_value = text.substr(colon_pos + 2)
				else:
					new_value = text
			else:
				new_value = text
		_:
			return

	send_to_game(GECSEditorDebuggerMessages.Msg.EDIT_COMPONENT_PROPERTY, [entity_id, component_id, property_name, new_value])
