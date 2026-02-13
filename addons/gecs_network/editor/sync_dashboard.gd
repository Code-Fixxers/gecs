@tool
extends Control
## Sync Dashboard - Central dock panel for viewing and editing network sync configuration.
##
## Displays all SyncComponent subclasses with their property priorities,
## all Entity subclasses with their sync patterns, and global config settings.
## Designers can edit priorities inline and save as .sync.tres metadata files.

signal navigate_to_entity(entity_name: String)

const CodebaseScanner = preload("res://addons/gecs_network/editor/codebase_scanner.gd")
const CodeGenerator = preload("res://addons/gecs_network/editor/code_generator.gd")
const ReplicationOverlay = preload("res://addons/gecs_network/editor/replication_overlay.gd")

var _scanner: RefCounted  # CodebaseScanner instance
var _editor_interface: EditorInterface

# UI references
var _tab_container: TabContainer
var _scan_button: Button
var _summary_label: Label

# Components tab
var _component_search: LineEdit
var _component_filter: OptionButton
var _component_tree: Tree

# Entities tab
var _entity_search: LineEdit
var _entity_filter: OptionButton
var _entity_tree: Tree

# Config tab
var _scan_dirs_edit: TextEdit
var _skip_list_edit: TextEdit
var _model_ready_edit: LineEdit
var _transform_edit: LineEdit
var _reconciliation_check: CheckBox
var _reconciliation_interval_spin: SpinBox
var _export_button: Button

# Code preview popup
var _code_popup: AcceptDialog
var _code_text: TextEdit

# Export/Import profile
var _export_profile_button: Button
var _import_profile_button: Button
var _file_dialog: FileDialog

# Replication overlay tab
var _replication_overlay: Control  # GECSReplicationOverlay

# Priority option labels (used for inline dropdowns)
const PRIORITY_OPTIONS_STR := "REALTIME,HIGH,MEDIUM,LOW,LOCAL"
const PRIORITY_DROPDOWN_TO_VALUE := [0, 1, 2, 3, -1]
const PRIORITY_VALUE_TO_DROPDOWN := {0: 0, 1: 1, 2: 2, 3: 3, -1: 4}

# Colors for visual status
var _color_synced := Color(0.4, 0.9, 0.4)      # Green - actively synced
var _color_local := Color(0.6, 0.6, 0.6)        # Gray - local only
var _color_spawn_only := Color(0.5, 0.75, 1.0)  # Blue - spawn sync
var _color_continuous := Color(0.4, 0.9, 0.4)   # Green - continuous sync
var _color_none := Color(0.6, 0.6, 0.6)         # Gray - no sync
var _color_modified := Color(1.0, 0.85, 0.3)    # Yellow - unsaved changes

# Track unsaved changes per component/entity script_path
var _dirty_components: Dictionary = {}  # script_path -> true
var _dirty_entities: Dictionary = {}    # script_path -> true


func _ready() -> void:
	_scanner = CodebaseScanner.new()
	_build_ui()


func set_editor_interface(ei: EditorInterface) -> void:
	_editor_interface = ei


## Build the entire UI programmatically for reliable control references.
func _build_ui() -> void:
	# Main layout
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "GECS Network Sync"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)

	_scan_button = Button.new()
	_scan_button.text = "Scan"
	_scan_button.tooltip_text = "Scan project for components and entities"
	_scan_button.pressed.connect(_on_scan_pressed)
	header.add_child(_scan_button)

	# Summary label
	_summary_label = Label.new()
	_summary_label.text = "Press Scan to discover components and entities."
	_summary_label.add_theme_font_size_override("font_size", 11)
	_summary_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_summary_label)

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(_tab_container)

	_build_components_tab()
	_build_entities_tab()
	_build_config_tab()
	_build_replication_tab()

	# Code preview popup
	_code_popup = AcceptDialog.new()
	_code_popup.title = "Code Preview"
	_code_popup.min_size = Vector2i(500, 400)
	add_child(_code_popup)

	_code_text = TextEdit.new()
	_code_text.editable = false
	_code_text.custom_minimum_size = Vector2(480, 350)
	_code_popup.add_child(_code_text)


func _build_components_tab() -> void:
	var panel := VBoxContainer.new()
	panel.name = "Components"
	_tab_container.add_child(panel)

	# Search and filter row
	var filter_row := HBoxContainer.new()
	panel.add_child(filter_row)

	var search_label := Label.new()
	search_label.text = "Search:"
	filter_row.add_child(search_label)

	_component_search = LineEdit.new()
	_component_search.placeholder_text = "Filter by name..."
	_component_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_component_search.text_changed.connect(_on_component_search_changed)
	filter_row.add_child(_component_search)

	var filter_label := Label.new()
	filter_label.text = "Show:"
	filter_row.add_child(filter_label)

	_component_filter = OptionButton.new()
	_component_filter.add_item("All", 0)
	_component_filter.add_item("Synced", 1)
	_component_filter.add_item("Local", 2)
	_component_filter.item_selected.connect(_on_component_filter_changed)
	filter_row.add_child(_component_filter)

	# Bulk operations row
	var comp_bulk_row := HBoxContainer.new()
	panel.add_child(comp_bulk_row)

	var bulk_save_comps_btn := Button.new()
	bulk_save_comps_btn.text = "Save All Modified"
	bulk_save_comps_btn.tooltip_text = "Save .sync.tres for all components with unsaved changes"
	bulk_save_comps_btn.pressed.connect(_on_bulk_save_components)
	comp_bulk_row.add_child(bulk_save_comps_btn)

	# Tree
	_component_tree = Tree.new()
	_component_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_component_tree.columns = 4
	_component_tree.set_column_title(0, "Component")
	_component_tree.set_column_title(1, "Priority")
	_component_tree.set_column_title(2, "Sync")
	_component_tree.set_column_title(3, "Rate")
	_component_tree.column_titles_visible = true
	_component_tree.set_column_expand(0, true)
	_component_tree.set_column_expand(1, false)
	_component_tree.set_column_custom_minimum_width(1, 100)
	_component_tree.set_column_expand(2, false)
	_component_tree.set_column_custom_minimum_width(2, 50)
	_component_tree.set_column_expand(3, false)
	_component_tree.set_column_custom_minimum_width(3, 60)
	_component_tree.hide_root = true
	_component_tree.button_clicked.connect(_on_component_tree_button)
	_component_tree.item_edited.connect(_on_component_tree_item_edited)
	panel.add_child(_component_tree)


func _build_entities_tab() -> void:
	var panel := VBoxContainer.new()
	panel.name = "Entities"
	_tab_container.add_child(panel)

	# Search and filter row (matching component tab)
	var filter_row := HBoxContainer.new()
	panel.add_child(filter_row)

	var search_label := Label.new()
	search_label.text = "Search:"
	filter_row.add_child(search_label)

	_entity_search = LineEdit.new()
	_entity_search.placeholder_text = "Filter by name..."
	_entity_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_entity_search.text_changed.connect(_on_entity_search_changed)
	filter_row.add_child(_entity_search)

	var filter_label := Label.new()
	filter_label.text = "Show:"
	filter_row.add_child(filter_label)

	_entity_filter = OptionButton.new()
	_entity_filter.add_item("All", 0)
	_entity_filter.add_item("Networked", 1)
	_entity_filter.add_item("Local-only", 2)
	_entity_filter.item_selected.connect(_on_entity_filter_changed)
	filter_row.add_child(_entity_filter)

	# Bulk operations row
	var bulk_row := HBoxContainer.new()
	panel.add_child(bulk_row)

	var select_all_btn := Button.new()
	select_all_btn.text = "Select All"
	select_all_btn.pressed.connect(_on_select_all_entities)
	bulk_row.add_child(select_all_btn)

	var deselect_all_btn := Button.new()
	deselect_all_btn.text = "Deselect All"
	deselect_all_btn.pressed.connect(_on_deselect_all_entities)
	bulk_row.add_child(deselect_all_btn)

	var bulk_save_btn := Button.new()
	bulk_save_btn.text = "Save All Modified"
	bulk_save_btn.tooltip_text = "Save .sync.tres for all entities with unsaved changes"
	bulk_save_btn.pressed.connect(_on_bulk_save_entities)
	bulk_row.add_child(bulk_save_btn)

	_entity_tree = Tree.new()
	_entity_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_entity_tree.columns = 4
	_entity_tree.set_column_title(0, "Entity")
	_entity_tree.set_column_title(1, "Pattern")
	_entity_tree.set_column_title(2, "Owner")
	_entity_tree.set_column_title(3, "Sync Props")
	_entity_tree.column_titles_visible = true
	_entity_tree.set_column_expand(0, true)
	_entity_tree.set_column_expand(1, false)
	_entity_tree.set_column_custom_minimum_width(1, 90)
	_entity_tree.set_column_expand(2, false)
	_entity_tree.set_column_custom_minimum_width(2, 80)
	_entity_tree.set_column_expand(3, false)
	_entity_tree.set_column_custom_minimum_width(3, 100)
	_entity_tree.hide_root = true
	_entity_tree.button_clicked.connect(_on_entity_tree_button)
	panel.add_child(_entity_tree)


func _build_config_tab() -> void:
	var panel := VBoxContainer.new()
	panel.name = "Config"
	_tab_container.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(content)

	# Scan directories
	var scan_label := Label.new()
	scan_label.text = "Scan Directories (one per line):"
	content.add_child(scan_label)

	_scan_dirs_edit = TextEdit.new()
	_scan_dirs_edit.custom_minimum_size = Vector2(0, 50)
	_scan_dirs_edit.placeholder_text = "res://game/\nres://shared/"
	_scan_dirs_edit.text = "res://"
	_scan_dirs_edit.tooltip_text = "Directories to scan for components and entities. Addons and .godot are always excluded."
	content.add_child(_scan_dirs_edit)

	content.add_child(_make_separator())

	# Skip list
	var skip_label := Label.new()
	skip_label.text = "Skip List (Native Sync):"
	content.add_child(skip_label)

	_skip_list_edit = TextEdit.new()
	_skip_list_edit.custom_minimum_size = Vector2(0, 60)
	_skip_list_edit.placeholder_text = 'One component per line, e.g.:\nC_Transform'
	content.add_child(_skip_list_edit)

	# Model ready component
	content.add_child(_make_separator())

	var model_label := Label.new()
	model_label.text = "Model Ready Component:"
	content.add_child(model_label)

	_model_ready_edit = LineEdit.new()
	_model_ready_edit.placeholder_text = "C_Instantiated"
	content.add_child(_model_ready_edit)

	# Transform component
	var transform_label := Label.new()
	transform_label.text = "Transform Component:"
	content.add_child(transform_label)

	_transform_edit = LineEdit.new()
	_transform_edit.placeholder_text = "C_Transform"
	content.add_child(_transform_edit)

	# Reconciliation
	content.add_child(_make_separator())

	_reconciliation_check = CheckBox.new()
	_reconciliation_check.text = "Enable Reconciliation"
	_reconciliation_check.button_pressed = true
	content.add_child(_reconciliation_check)

	var interval_row := HBoxContainer.new()
	content.add_child(interval_row)

	var interval_label := Label.new()
	interval_label.text = "Interval (sec):"
	interval_row.add_child(interval_label)

	_reconciliation_interval_spin = SpinBox.new()
	_reconciliation_interval_spin.min_value = 1.0
	_reconciliation_interval_spin.max_value = 120.0
	_reconciliation_interval_spin.step = 1.0
	_reconciliation_interval_spin.value = 10.0
	interval_row.add_child(_reconciliation_interval_spin)

	# Export button
	content.add_child(_make_separator())

	_export_button = Button.new()
	_export_button.text = "Export to project_sync_config.gd"
	_export_button.tooltip_text = "Generate component_priorities code for copy-paste"
	_export_button.pressed.connect(_on_export_pressed)
	content.add_child(_export_button)

	# Import/Export sync profiles section
	content.add_child(_make_separator())

	var profile_label := Label.new()
	profile_label.text = "Sync Profiles:"
	content.add_child(profile_label)

	var profile_row := HBoxContainer.new()
	content.add_child(profile_row)

	_export_profile_button = Button.new()
	_export_profile_button.text = "Export Profile"
	_export_profile_button.tooltip_text = "Export current sync config as JSON file"
	_export_profile_button.pressed.connect(_on_export_profile)
	profile_row.add_child(_export_profile_button)

	_import_profile_button = Button.new()
	_import_profile_button.text = "Import Profile"
	_import_profile_button.tooltip_text = "Import sync config from JSON file"
	_import_profile_button.pressed.connect(_on_import_profile)
	profile_row.add_child(_import_profile_button)

	# Preset profiles
	var preset_row := HBoxContainer.new()
	content.add_child(preset_row)

	var preset_label := Label.new()
	preset_label.text = "Presets:"
	preset_row.add_child(preset_label)

	var lan_button := Button.new()
	lan_button.text = "LAN (High BW)"
	lan_button.tooltip_text = "Set all synced components to HIGH priority (LAN/local play)"
	lan_button.pressed.connect(_on_preset_lan)
	preset_row.add_child(lan_button)

	var wan_button := Button.new()
	wan_button.text = "WAN (Conservative)"
	wan_button.tooltip_text = "Set all synced components to MEDIUM/LOW priority (internet play)"
	wan_button.pressed.connect(_on_preset_wan)
	preset_row.add_child(wan_button)


func _build_replication_tab() -> void:
	_replication_overlay = ReplicationOverlay.new()
	_replication_overlay.name = "Replication"
	_tab_container.add_child(_replication_overlay)


## Returns the replication overlay instance for external data feeding.
func get_replication_overlay() -> Control:
	return _replication_overlay


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep


# ============================================================================
# SCAN
# ============================================================================

func _on_scan_pressed() -> void:
	_scan_button.disabled = true
	_scan_button.text = "Scanning..."
	_summary_label.text = "Scanning..."

	# Apply scan directory config from UI
	_apply_scan_dirs_config()

	# Allow UI to update before blocking scan
	await get_tree().process_frame

	_scanner.scan()

	_dirty_components.clear()
	_dirty_entities.clear()

	_populate_component_tree()
	_populate_entity_tree()
	_update_summary()

	_scan_button.disabled = false
	_scan_button.text = "Scan"


func _apply_scan_dirs_config() -> void:
	var text := _scan_dirs_edit.text.strip_edges()
	if text == "":
		return
	var dirs: Array[String] = []
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped != "":
			dirs.append(stripped)
	if not dirs.is_empty():
		_scanner.scan_directories = dirs


func _update_summary() -> void:
	var total_comps := _scanner.components.size()
	var synced_comps := 0
	for c in _scanner.components:
		if c.is_sync_component:
			synced_comps += 1

	var total_ents := _scanner.entities.size()
	var networked_ents := 0
	var continuous_ents := 0
	for e in _scanner.entities:
		if e.has_network_identity:
			networked_ents += 1
		if e.has_sync_entity:
			continuous_ents += 1

	_summary_label.text = "%d components (%d synced)  |  %d entities (%d networked, %d continuous)" % [
		total_comps, synced_comps, total_ents, networked_ents, continuous_ents
	]


# ============================================================================
# COMPONENTS TAB
# ============================================================================

func _populate_component_tree() -> void:
	_component_tree.clear()
	var root := _component_tree.create_item()

	var search_text := _component_search.text.to_lower() if _component_search else ""
	var filter_mode := _component_filter.selected if _component_filter else 0

	for comp in _scanner.components:
		# Search filter
		if search_text != "" and comp.class_name_str.to_lower().find(search_text) == -1:
			continue

		# Type filter
		if filter_mode == 1 and not comp.is_sync_component:
			continue
		if filter_mode == 2 and comp.is_sync_component:
			continue

		var item := _component_tree.create_item(root)
		var is_dirty := _dirty_components.has(comp.script_path)

		# Column 0: Name + type + dirty indicator
		var type_suffix := " (SyncComponent)" if comp.is_sync_component else " (Component)"
		var dirty_mark := " *" if is_dirty else ""
		item.set_text(0, comp.class_name_str + type_suffix + dirty_mark)
		item.set_tooltip_text(0, comp.script_path)

		if comp.is_sync_component:
			# Column 1: Default priority (highest priority found in properties)
			var highest_priority := _get_highest_priority(comp)
			item.set_text(1, CodebaseScanner.priority_to_string(highest_priority))

			# Column 2: Sync indicator
			item.set_text(2, "Sync")

			# Column 3: Rate
			item.set_text(3, CodebaseScanner.priority_to_rate(highest_priority))

			# Color coding
			var row_color := _color_modified if is_dirty else _color_synced
			item.set_custom_color(0, row_color)
			item.set_custom_color(2, _color_synced)

			# Add expandable child rows for each property (editable priority)
			for prop_name in comp.properties:
				var prop_data: Dictionary = comp.properties[prop_name]
				var child := _component_tree.create_item(item)
				child.set_text(0, "  %s (%s)" % [prop_name, prop_data.get("type", "?")])

				# Column 1: Editable priority dropdown
				child.set_cell_mode(1, TreeItem.CELL_MODE_RANGE)
				child.set_text(1, PRIORITY_OPTIONS_STR)
				child.set_range(1, PRIORITY_VALUE_TO_DROPDOWN.get(prop_data.priority, 1))
				child.set_editable(1, true)

				# Column 2: Sync status
				var is_synced := prop_data.priority != -1
				child.set_text(2, "Yes" if is_synced else "No")
				child.set_custom_color(2, _color_synced if is_synced else _color_local)

				# Column 3: Rate
				child.set_text(3, CodebaseScanner.priority_to_rate(prop_data.priority))

				# Store metadata: {comp: ComponentInfo, prop_name: String}
				child.set_metadata(0, {"comp": comp, "prop_name": prop_name})

			# Add action buttons
			_add_tree_button(item, 0, "Script", 0, "Open Script")
			_add_tree_button(item, 0, "Save", 1, "Save .sync.tres")
			item.set_metadata(0, comp)
		else:
			item.set_text(1, "--")
			item.set_text(2, "")
			item.set_text(3, "--")
			# Color coding: gray for non-synced
			item.set_custom_color(0, _color_local)
			_add_tree_button(item, 0, "Script", 0, "Open Script")
			item.set_metadata(0, comp)

		# Collapse by default
		item.collapsed = true


func _get_highest_priority(comp) -> int:
	var highest := 3  # LOW
	for prop_name in comp.properties:
		var p: int = comp.properties[prop_name].priority
		if p == -1:
			continue  # Skip LOCAL
		if p < highest:
			highest = p
	return highest


func _on_component_search_changed(_text: String) -> void:
	_populate_component_tree()


func _on_component_filter_changed(_index: int) -> void:
	_populate_component_tree()


## Handle inline priority editing on component property rows.
func _on_component_tree_item_edited() -> void:
	var item := _component_tree.get_edited()
	if item == null:
		return

	var meta = item.get_metadata(0)
	if meta == null or not meta is Dictionary:
		return  # Not a property row

	var comp = meta.get("comp")
	var prop_name: String = meta.get("prop_name", "")
	if comp == null or prop_name == "":
		return

	# Read new dropdown index and map to priority value
	var dropdown_index := int(item.get_range(1))
	if dropdown_index < 0 or dropdown_index >= PRIORITY_DROPDOWN_TO_VALUE.size():
		return
	var new_priority: int = PRIORITY_DROPDOWN_TO_VALUE[dropdown_index]

	# Update the in-memory ComponentInfo
	if comp.properties.has(prop_name):
		comp.properties[prop_name].priority = new_priority

	# Mark as dirty
	_dirty_components[comp.script_path] = true

	# Update the child row's sync and rate columns
	var is_synced := new_priority != -1
	item.set_text(2, "Yes" if is_synced else "No")
	item.set_custom_color(2, _color_synced if is_synced else _color_local)
	item.set_text(3, CodebaseScanner.priority_to_rate(new_priority))

	# Update parent row aggregate
	var parent := item.get_parent()
	if parent:
		var highest := _get_highest_priority(comp)
		parent.set_text(1, CodebaseScanner.priority_to_string(highest))
		parent.set_text(3, CodebaseScanner.priority_to_rate(highest))
		parent.set_custom_color(0, _color_modified)
		# Update name to show dirty indicator
		var type_suffix := " (SyncComponent)" if comp.is_sync_component else " (Component)"
		parent.set_text(0, comp.class_name_str + type_suffix + " *")


func _on_component_tree_button(item: TreeItem, _column: int, id: int, _mouse_button: int) -> void:
	var comp = item.get_metadata(0)
	if comp == null:
		return
	# Skip if this is a property child row (metadata is a Dictionary)
	if comp is Dictionary:
		return

	if id == 0:
		# Open Script
		_open_script(comp.script_path)
	elif id == 1:
		# Save .sync.tres
		_save_component_metadata(comp)


func _save_component_metadata(comp) -> void:
	var metadata := ComponentSyncMetadata.new()
	metadata.component_script_path = comp.script_path
	metadata.sync_enabled = comp.is_sync_component

	# Determine default priority from properties
	metadata.default_priority = _get_highest_priority(comp)

	# Save per-property settings
	for prop_name in comp.properties:
		var prop_data: Dictionary = comp.properties[prop_name]
		var settings := PropertySyncSettings.new()
		settings.priority = prop_data.priority
		settings.sync_enabled = prop_data.priority != -1
		metadata.properties[prop_name] = settings

	var tres_path := comp.script_path.replace(".gd", ".sync.tres")
	var err := ResourceSaver.save(metadata, tres_path)
	if err == OK:
		SyncMetadataRegistry.invalidate_component(comp.script_path)
		_dirty_components.erase(comp.script_path)
		# Refresh tree to clear dirty indicators
		_populate_component_tree()
		print("[SyncDashboard] Saved: %s" % tres_path)
	else:
		push_error("[SyncDashboard] Failed to save: %s (error %d)" % [tres_path, err])


# ============================================================================
# ENTITIES TAB
# ============================================================================

func _populate_entity_tree() -> void:
	_entity_tree.clear()
	var root := _entity_tree.create_item()

	var search_text := _entity_search.text.to_lower() if _entity_search else ""
	var filter_mode := _entity_filter.selected if _entity_filter else 0

	for ent in _scanner.entities:
		# Search filter
		if search_text != "" and ent.class_name_str.to_lower().find(search_text) == -1:
			continue

		# Type filter
		var is_networked := ent.has_network_identity or ent.has_sync_entity
		if filter_mode == 1 and not is_networked:
			continue
		if filter_mode == 2 and is_networked:
			continue

		var item := _entity_tree.create_item(root)

		# Column 0: Name (checkable for bulk operations)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, false)
		item.set_text(0, ent.class_name_str)
		item.set_tooltip_text(0, ent.script_path)

		# Column 1: Sync pattern + color
		if ent.has_sync_entity:
			item.set_text(1, "Continuous")
			item.set_custom_color(0, _color_continuous)
			item.set_custom_color(1, _color_continuous)
		elif ent.has_network_identity:
			item.set_text(1, "Spawn-only")
			item.set_custom_color(0, _color_spawn_only)
			item.set_custom_color(1, _color_spawn_only)
		else:
			item.set_text(1, "None")
			item.set_custom_color(0, _color_none)
			item.set_custom_color(1, _color_none)

		# Column 2: Ownership
		if ent.peer_id_value == 0:
			item.set_text(2, "Server")
		elif ent.peer_id_value > 0:
			item.set_text(2, "Player")
		elif ent.has_network_identity:
			item.set_text(2, "Dynamic")
		else:
			item.set_text(2, "--")

		# Column 3: Sync properties summary
		var sync_parts: PackedStringArray = []
		if ent.sync_position:
			sync_parts.append("pos")
		if ent.sync_rotation:
			sync_parts.append("rot")
		if ent.sync_velocity:
			sync_parts.append("vel")
		for cp in ent.custom_properties:
			sync_parts.append(cp)
		item.set_text(3, "+".join(sync_parts) if sync_parts.size() > 0 else "--")

		# Add expandable children: component list with sync status
		if ent.component_names.size() > 0:
			for comp_name in ent.component_names:
				var child := _entity_tree.create_item(item)
				child.set_text(0, "  %s" % comp_name)

				# Check if this component is synced and color accordingly
				var is_synced := _is_component_synced(comp_name)
				child.set_text(2, "Sync" if is_synced else "")
				if is_synced:
					child.set_custom_color(0, _color_synced)
					child.set_custom_color(2, _color_synced)
				else:
					child.set_custom_color(0, _color_local)

		# Action buttons
		_add_tree_button(item, 0, "Script", 0, "Open Script")
		_add_tree_button(item, 0, "CodeEdit", 1, "Preview Code")
		_add_tree_button(item, 0, "Save", 2, "Save .sync.tres")
		_add_tree_button(item, 0, "Search", 3, "Find in Debugger")
		item.set_metadata(0, ent)
		item.collapsed = true


func _is_component_synced(comp_name: String) -> bool:
	for comp in _scanner.components:
		if comp.class_name_str == comp_name:
			return comp.is_sync_component
	return false


func _on_entity_search_changed(_text: String) -> void:
	_populate_entity_tree()


func _on_entity_filter_changed(_index: int) -> void:
	_populate_entity_tree()


func _on_entity_tree_button(item: TreeItem, _column: int, id: int, _mouse_button: int) -> void:
	var ent = item.get_metadata(0)
	if ent == null:
		return

	if id == 0:
		_open_script(ent.script_path)
	elif id == 1:
		_show_code_preview(ent)
	elif id == 2:
		_save_entity_metadata(ent)
	elif id == 3:
		# Navigate to debugger - emit signal with entity class name
		navigate_to_entity.emit(ent.class_name_str)


func _show_code_preview(ent) -> void:
	var code := CodeGenerator.generate_entity_network_preview(ent)
	_code_text.text = code
	_code_popup.popup_centered()


func _save_entity_metadata(ent) -> void:
	var metadata := EntitySyncMetadata.new()
	metadata.entity_script_path = ent.script_path

	# Determine sync pattern
	if ent.has_sync_entity:
		metadata.sync_pattern = EntitySyncMetadata.SyncPattern.CONTINUOUS
	elif ent.has_network_identity:
		metadata.sync_pattern = EntitySyncMetadata.SyncPattern.SPAWN_ONLY
	else:
		metadata.sync_pattern = EntitySyncMetadata.SyncPattern.NONE

	# Determine ownership
	if ent.peer_id_value == 0:
		metadata.ownership = EntitySyncMetadata.Ownership.SERVER
	else:
		metadata.ownership = EntitySyncMetadata.Ownership.PLAYER

	metadata.sync_position = ent.sync_position
	metadata.sync_rotation = ent.sync_rotation
	metadata.sync_velocity = ent.sync_velocity
	metadata.custom_properties = ent.custom_properties.duplicate()

	var tres_path := ent.script_path.replace(".gd", ".sync.tres")
	var err := ResourceSaver.save(metadata, tres_path)
	if err == OK:
		SyncMetadataRegistry.invalidate_entity(ent.script_path)
		_dirty_entities.erase(ent.script_path)
		print("[SyncDashboard] Saved: %s" % tres_path)
	else:
		push_error("[SyncDashboard] Failed to save: %s (error %d)" % [tres_path, err])


# ============================================================================
# CONFIG TAB
# ============================================================================

func _on_export_pressed() -> void:
	# Build config priorities from scanned components
	var config_priorities := {}
	for comp in _scanner.components:
		if not comp.is_sync_component:
			continue
		var highest := _get_highest_priority(comp)
		if highest >= 0:
			config_priorities[comp.class_name_str] = highest

	var code := CodeGenerator.generate_component_priorities(_scanner.components, config_priorities)

	# Add skip list
	var skip_text := _skip_list_edit.text.strip_edges()
	var skip_types: Array[String] = []
	if skip_text != "":
		for line in skip_text.split("\n"):
			var stripped := line.strip_edges()
			if stripped != "":
				skip_types.append(stripped)
	code += "\n\n" + CodeGenerator.generate_skip_list(skip_types)

	_code_text.text = code
	_code_popup.popup_centered()


# ============================================================================
# BULK OPERATIONS
# ============================================================================

func _on_select_all_entities() -> void:
	if not _entity_tree:
		return
	var root = _entity_tree.get_root()
	if root == null:
		return
	var child = root.get_first_child()
	while child:
		child.set_checked(0, true)
		child = child.get_next()


func _on_deselect_all_entities() -> void:
	if not _entity_tree:
		return
	var root = _entity_tree.get_root()
	if root == null:
		return
	var child = root.get_first_child()
	while child:
		child.set_checked(0, false)
		child = child.get_next()


func _on_bulk_save_entities() -> void:
	var saved_count := 0
	for script_path in _dirty_entities.keys():
		for ent in _scanner.entities:
			if ent.script_path == script_path:
				_save_entity_metadata(ent)
				saved_count += 1
				break
	if saved_count > 0:
		_populate_entity_tree()
		_summary_label.text = "Saved %d entity metadata files." % saved_count


func _on_bulk_save_components() -> void:
	var saved_count := 0
	for script_path in _dirty_components.keys():
		for comp in _scanner.components:
			if comp.script_path == script_path:
				_save_component_metadata(comp)
				saved_count += 1
				break
	if saved_count > 0:
		_populate_component_tree()
		_summary_label.text = "Saved %d component metadata files." % saved_count


# ============================================================================
# EXPORT/IMPORT PROFILES
# ============================================================================

func _on_export_profile() -> void:
	_show_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _on_export_profile_path_selected, "*.json")
	_file_dialog.current_file = "sync_profile.json"


func _on_export_profile_path_selected(path: String) -> void:
	var profile := _build_export_profile()
	var json_str := JSON.stringify(profile, "  ")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		_summary_label.text = "Profile exported to: %s" % path.get_file()
	else:
		push_error("[SyncDashboard] Failed to export profile to: %s" % path)


func _build_export_profile() -> Dictionary:
	var profile := {}
	profile["version"] = 1
	profile["exported_at"] = Time.get_datetime_string_from_system()
	profile["components"] = {}
	profile["entities"] = {}

	for comp in _scanner.components:
		if not comp.is_sync_component:
			continue
		var comp_data := {}
		for prop_name in comp.properties:
			comp_data[prop_name] = comp.properties[prop_name].priority
		profile["components"][comp.class_name_str] = comp_data

	for ent in _scanner.entities:
		if not ent.has_network_identity and not ent.has_sync_entity:
			continue
		profile["entities"][ent.class_name_str] = {
			"sync_position": ent.sync_position,
			"sync_rotation": ent.sync_rotation,
			"sync_velocity": ent.sync_velocity,
			"custom_properties": ent.custom_properties,
		}

	return profile


func _on_import_profile() -> void:
	_show_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, _on_import_profile_path_selected, "*.json")


func _on_import_profile_path_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[SyncDashboard] Failed to open profile: %s" % path)
		return
	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_error("[SyncDashboard] Invalid JSON in profile: %s" % path)
		return

	var profile: Dictionary = json.data
	if not profile.has("version") or not profile.has("components"):
		push_error("[SyncDashboard] Invalid profile format")
		return

	# Apply component priorities
	var applied := 0
	var comp_profiles: Dictionary = profile.get("components", {})
	for comp in _scanner.components:
		if not comp.is_sync_component:
			continue
		if comp_profiles.has(comp.class_name_str):
			var comp_data: Dictionary = comp_profiles[comp.class_name_str]
			for prop_name in comp_data:
				if comp.properties.has(prop_name):
					comp.properties[prop_name].priority = int(comp_data[prop_name])
					_dirty_components[comp.script_path] = true
					applied += 1

	_populate_component_tree()
	_populate_entity_tree()
	_summary_label.text = "Imported profile: %d priorities applied from %s" % [applied, path.get_file()]


func _on_preset_lan() -> void:
	for comp in _scanner.components:
		if not comp.is_sync_component:
			continue
		for prop_name in comp.properties:
			if comp.properties[prop_name].priority != -1:  # Don't change LOCAL
				comp.properties[prop_name].priority = 1  # HIGH
				_dirty_components[comp.script_path] = true
	_populate_component_tree()
	_summary_label.text = "LAN preset applied: all synced properties set to HIGH priority"


func _on_preset_wan() -> void:
	for comp in _scanner.components:
		if not comp.is_sync_component:
			continue
		for prop_name in comp.properties:
			var current = comp.properties[prop_name].priority
			if current == -1:
				continue  # Don't change LOCAL
			if current <= 1:  # REALTIME or HIGH -> MEDIUM
				comp.properties[prop_name].priority = 2
			else:
				comp.properties[prop_name].priority = 3  # LOW
			_dirty_components[comp.script_path] = true
	_populate_component_tree()
	_summary_label.text = "WAN preset applied: priorities reduced for conservative bandwidth"


func _show_file_dialog(mode: FileDialog.FileMode, callback: Callable, filter: String) -> void:
	if _file_dialog:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = mode
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter(filter)
	_file_dialog.file_selected.connect(callback)
	add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(600, 400))


# ============================================================================
# HELPERS
# ============================================================================

func _open_script(path: String) -> void:
	if _editor_interface:
		var script := load(path)
		if script:
			_editor_interface.edit_script(script)
	else:
		print("[SyncDashboard] Cannot open script (no EditorInterface): %s" % path)


func _get_theme_icon(icon_name: String) -> Texture2D:
	if _editor_interface:
		var theme := _editor_interface.get_editor_theme()
		if theme and theme.has_icon(icon_name, "EditorIcons"):
			return theme.get_icon(icon_name, "EditorIcons")
	return null


## Safely add a button to a TreeItem, skipping if the icon cannot be loaded.
## TreeItem.add_button() requires a non-null Texture2D.
func _add_tree_button(item: TreeItem, column: int, icon_name: String, id: int, tooltip: String) -> void:
	var icon := _get_theme_icon(icon_name)
	if icon:
		item.add_button(column, icon, id, false, tooltip)
