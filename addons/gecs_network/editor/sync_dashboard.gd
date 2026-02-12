@tool
extends Control
## Sync Dashboard - Central dock panel for viewing and editing network sync configuration.
##
## Displays all SyncComponent subclasses with their property priorities,
## all Entity subclasses with their sync patterns, and global config settings.
## Designers can edit settings and save as .sync.tres metadata files.

const CodebaseScanner = preload("res://addons/gecs_network/editor/codebase_scanner.gd")
const CodeGenerator = preload("res://addons/gecs_network/editor/code_generator.gd")

var _scanner: RefCounted  # CodebaseScanner instance
var _editor_interface: EditorInterface

# UI references (set in _ready from scene tree, or built programmatically)
var _tab_container: TabContainer
var _scan_button: Button

# Components tab
var _component_search: LineEdit
var _component_filter: OptionButton
var _component_tree: Tree

# Entities tab
var _entity_tree: Tree

# Config tab
var _skip_list_edit: TextEdit
var _model_ready_edit: LineEdit
var _transform_edit: LineEdit
var _reconciliation_check: CheckBox
var _reconciliation_interval_spin: SpinBox
var _export_button: Button

# Code preview popup
var _code_popup: AcceptDialog
var _code_text: TextEdit

# Priority option labels
const PRIORITY_OPTIONS := ["REALTIME", "HIGH", "MEDIUM", "LOW", "LOCAL"]
const PRIORITY_VALUES := [0, 1, 2, 3, -1]


func _ready() -> void:
	_scanner = CodebaseScanner.new()
	_build_ui()


func set_editor_interface(ei: EditorInterface) -> void:
	_editor_interface = ei


## Build the entire UI programmatically for reliable control references.
func _build_ui() -> void:
	# Main layout — use size flags for dock panel (anchors don't apply in docks)
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

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(_tab_container)

	_build_components_tab()
	_build_entities_tab()
	_build_config_tab()

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
	_component_tree.set_column_custom_minimum_width(1, 90)
	_component_tree.set_column_expand(2, false)
	_component_tree.set_column_custom_minimum_width(2, 50)
	_component_tree.set_column_expand(3, false)
	_component_tree.set_column_custom_minimum_width(3, 60)
	_component_tree.hide_root = true
	_component_tree.button_clicked.connect(_on_component_tree_button)
	panel.add_child(_component_tree)


func _build_entities_tab() -> void:
	var panel := VBoxContainer.new()
	panel.name = "Entities"
	_tab_container.add_child(panel)

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

	# Allow UI to update before blocking scan
	await get_tree().process_frame

	_scanner.scan()
	_populate_component_tree()
	_populate_entity_tree()

	_scan_button.disabled = false
	_scan_button.text = "Scan"


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

		# Column 0: Name + type
		var type_suffix := " (SyncComponent)" if comp.is_sync_component else " (Component)"
		item.set_text(0, comp.class_name_str + type_suffix)
		item.set_tooltip_text(0, comp.script_path)

		if comp.is_sync_component:
			# Column 1: Default priority (highest priority found in properties)
			var highest_priority := _get_highest_priority(comp)
			item.set_text(1, CodebaseScanner.priority_to_string(highest_priority))

			# Column 2: Sync indicator
			item.set_text(2, "Sync" if comp.is_sync_component else "")

			# Column 3: Rate
			item.set_text(3, CodebaseScanner.priority_to_rate(highest_priority))

			# Add expandable child rows for each property
			for prop_name in comp.properties:
				var prop_data: Dictionary = comp.properties[prop_name]
				var child := _component_tree.create_item(item)
				child.set_text(0, "  %s (%s)" % [prop_name, prop_data.get("type", "?")])
				child.set_text(1, CodebaseScanner.priority_to_string(prop_data.priority))
				child.set_text(2, "No" if prop_data.priority == -1 else "Yes")
				child.set_text(3, CodebaseScanner.priority_to_rate(prop_data.priority))

			# Add action buttons
			_add_tree_button(item, 0, "Script", 0, "Open Script")
			_add_tree_button(item, 0, "Save", 1, "Save .sync.tres")
			item.set_metadata(0, comp)
		else:
			item.set_text(1, "--")
			item.set_text(2, "")
			item.set_text(3, "--")
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


func _on_component_tree_button(item: TreeItem, _column: int, id: int, _mouse_button: int) -> void:
	var comp = item.get_metadata(0)
	if comp == null:
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
		print("[SyncDashboard] Saved: %s" % tres_path)
	else:
		push_error("[SyncDashboard] Failed to save: %s (error %d)" % [tres_path, err])


# ============================================================================
# ENTITIES TAB
# ============================================================================

func _populate_entity_tree() -> void:
	_entity_tree.clear()
	var root := _entity_tree.create_item()

	for ent in _scanner.entities:
		var item := _entity_tree.create_item(root)

		# Column 0: Name
		item.set_text(0, ent.class_name_str)
		item.set_tooltip_text(0, ent.script_path)

		# Column 1: Sync pattern
		if ent.has_sync_entity:
			item.set_text(1, "Continuous")
		elif ent.has_network_identity:
			item.set_text(1, "Spawn-only")
		else:
			item.set_text(1, "None")

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

		# Add expandable children: component list
		if ent.component_names.size() > 0:
			for comp_name in ent.component_names:
				var child := _entity_tree.create_item(item)
				child.set_text(0, "  %s" % comp_name)

				# Check if this component is synced
				var is_synced := _is_component_synced(comp_name)
				child.set_text(2, "Sync" if is_synced else "")

		# Action buttons
		_add_tree_button(item, 0, "Script", 0, "Open Script")
		_add_tree_button(item, 0, "CodeEdit", 1, "Preview Code")
		_add_tree_button(item, 0, "Save", 2, "Save .sync.tres")
		item.set_metadata(0, ent)
		item.collapsed = true


func _is_component_synced(comp_name: String) -> bool:
	for comp in _scanner.components:
		if comp.class_name_str == comp_name:
			return comp.is_sync_component
	return false


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
