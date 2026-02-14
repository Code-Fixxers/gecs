@tool
class_name GECSQueryPlayground
extends Control

## Query Playground and "Why Not Matched" diagnostic tool for GECS.
##
## Provides an interactive editor panel where users can build ECS queries
## (with_all, with_any, with_none) against live runtime data and see which
## entities match. A second tab diagnoses why a specific entity does or does
## not match a given query by showing per-condition pass/fail results.
##
## Data is fed externally via [method set_editor_data].

# ---------------------------------------------------------------------------
# External data source
# ---------------------------------------------------------------------------

var _editor_data: GECSEditorData = null

## Extracted unique component type names mapped to their occurrence count.
## e.g. { "C_Health": 3, "C_Velocity": 2, ... }
var _available_components: Dictionary = {}

## Mapping of component instance id -> human-readable class name.
var _component_names: Dictionary = {}

## Mapping of entity id -> Array[String] of component class names attached
## to that entity.
var _entity_component_names: Dictionary = {}

## Mapping of entity id -> NodePath (display-friendly path string).
var _entity_paths: Dictionary = {}

# ---------------------------------------------------------------------------
# Color constants
# ---------------------------------------------------------------------------

const COLOR_PASS := Color(0.4, 0.9, 0.4)   # Green
const COLOR_FAIL := Color(0.95, 0.3, 0.3)   # Red
const COLOR_NEUTRAL := Color(0.7, 0.7, 0.7) # Gray
const COLOR_HEADER := Color(0.85, 0.85, 0.85)

# ---------------------------------------------------------------------------
# UI references  (built programmatically)
# ---------------------------------------------------------------------------

# Root layout
var _tab_container: TabContainer

# -- Query tab --
var _all_components_list: ItemList   # Multi-select for with_all
var _any_components_list: ItemList   # Multi-select for with_any
var _none_components_list: ItemList  # Multi-select for with_none
var _execute_button: Button
var _clear_button: Button
var _results_tree: Tree
var _match_count_label: Label

# -- Diagnose tab --
var _entity_selector: OptionButton
var _diagnose_button: Button
var _diagnostic_tree: Tree
var _diag_all_list: ItemList
var _diag_any_list: ItemList
var _diag_none_list: ItemList

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()


func set_editor_data(data: GECSEditorData) -> void:
	_editor_data = data
	if not _editor_data:
		return

	# Connect signals
	if not _editor_data.entity_added.is_connected(_on_entity_added):
		_editor_data.entity_added.connect(_on_entity_added)
	if not _editor_data.entity_removed.is_connected(_on_entity_removed):
		_editor_data.entity_removed.connect(_on_entity_removed)
	if not _editor_data.component_added.is_connected(_on_component_added):
		_editor_data.component_added.connect(_on_component_added)
	if not _editor_data.component_removed.is_connected(_on_component_removed):
		_editor_data.component_removed.connect(_on_component_removed)
	if not _editor_data.set_world.is_connected(_on_world_reset):
		_editor_data.set_world.connect(_on_world_reset)
	if not _editor_data.world_init.is_connected(_on_world_reset):
		_editor_data.world_init.connect(_on_world_reset)

	# Initial build
	_rebuild_component_index()
	_refresh_component_lists()
	_refresh_entity_selector()


# ---------------------------------------------------------------------------
# Signal Handlers
# ---------------------------------------------------------------------------

func _on_world_reset(_id, _path):
	_rebuild_component_index()
	_refresh_component_lists()
	_refresh_entity_selector()


func _on_entity_added(entity_id: int, path: NodePath):
	_entity_paths[entity_id] = path
	_refresh_entity_selector()


func _on_entity_removed(entity_id: int, _path: NodePath):
	_entity_paths.erase(entity_id)
	_entity_component_names.erase(entity_id)
	_refresh_entity_selector()


func _on_component_added(entity_id: int, component_id: int, component_path: String, _data: Dictionary):
	var comp_name := _extract_class_name(component_path)
	_component_names[component_id] = comp_name

	if not _entity_component_names.has(entity_id):
		_entity_component_names[entity_id] = []

	if comp_name not in _entity_component_names[entity_id]:
		_entity_component_names[entity_id].append(comp_name)
		_available_components[comp_name] = _available_components.get(comp_name, 0) + 1
		_refresh_component_lists()


func _on_component_removed(entity_id: int, component_id: int):
	var comp_name: String = _component_names.get(component_id, "")
	if comp_name != "" and _entity_component_names.has(entity_id):
		if comp_name in _entity_component_names[entity_id]:
			_entity_component_names[entity_id].erase(comp_name)
			if _available_components.has(comp_name):
				_available_components[comp_name] -= 1
				if _available_components[comp_name] <= 0:
					_available_components.erase(comp_name)
			_refresh_component_lists()


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# -- Root VBox fills the entire Control --
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root_vbox)

	# Header
	var header_hbox := HBoxContainer.new()
	root_vbox.add_child(header_hbox)

	var title_label := Label.new()
	title_label.text = "Query Playground"
	title_label.add_theme_font_size_override("font_size", 16)
	header_hbox.add_child(title_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_match_count_label = Label.new()
	_match_count_label.text = "No query executed"
	_match_count_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	header_hbox.add_child(_match_count_label)

	# Separator
	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_tab_container)

	# Build tabs
	_build_query_tab()
	_build_diagnose_tab()


func _build_query_tab() -> void:
	var query_vbox := VBoxContainer.new()
	query_vbox.name = "Query"
	query_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(query_vbox)

	# --- Component selection area ---
	var lists_hbox := HBoxContainer.new()
	lists_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists_hbox.custom_minimum_size.y = 160
	query_vbox.add_child(lists_hbox)

	# with_all
	_all_components_list = _create_component_list_column(lists_hbox, "with_all", "Entities MUST have ALL of these components")

	# with_any
	_any_components_list = _create_component_list_column(lists_hbox, "with_any", "Entities MUST have AT LEAST ONE of these components")

	# with_none
	_none_components_list = _create_component_list_column(lists_hbox, "with_none", "Entities MUST NOT have any of these components")

	# --- Buttons ---
	var button_hbox := HBoxContainer.new()
	query_vbox.add_child(button_hbox)

	_execute_button = Button.new()
	_execute_button.text = "Execute Query"
	_execute_button.pressed.connect(_on_execute_pressed)
	_execute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_hbox.add_child(_execute_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.pressed.connect(_on_clear_pressed)
	button_hbox.add_child(_clear_button)

	# --- Results tree ---
	var results_label := Label.new()
	results_label.text = "Results"
	query_vbox.add_child(results_label)

	_results_tree = Tree.new()
	_results_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_tree.columns = 2
	_results_tree.set_column_title(0, "Entity")
	_results_tree.set_column_title(1, "Components")
	_results_tree.set_column_titles_visible(true)
	_results_tree.set_column_expand(0, true)
	_results_tree.set_column_expand(1, true)
	_results_tree.set_column_clip_content(0, true)
	_results_tree.set_column_clip_content(1, true)
	_results_tree.create_item() # root
	query_vbox.add_child(_results_tree)


func _build_diagnose_tab() -> void:
	var diag_vbox := VBoxContainer.new()
	diag_vbox.name = "Diagnose"
	diag_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(diag_vbox)

	# --- Entity selector ---
	var selector_hbox := HBoxContainer.new()
	diag_vbox.add_child(selector_hbox)

	var ent_label := Label.new()
	ent_label.text = "Entity: "
	selector_hbox.add_child(ent_label)

	_entity_selector = OptionButton.new()
	_entity_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_selector.tooltip_text = "Select an entity to diagnose"
	selector_hbox.add_child(_entity_selector)

	# --- Query definition for diagnosis ---
	var diag_query_label := Label.new()
	diag_query_label.text = "Query to diagnose against:"
	diag_vbox.add_child(diag_query_label)

	var diag_lists_hbox := HBoxContainer.new()
	diag_lists_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diag_lists_hbox.custom_minimum_size.y = 140
	diag_vbox.add_child(diag_lists_hbox)

	_diag_all_list = _create_component_list_column(diag_lists_hbox, "with_all", "Required components")
	_diag_any_list = _create_component_list_column(diag_lists_hbox, "with_any", "Any-of components")
	_diag_none_list = _create_component_list_column(diag_lists_hbox, "with_none", "Excluded components")

	# --- Diagnose button ---
	_diagnose_button = Button.new()
	_diagnose_button.text = "Diagnose: Why Not Matched?"
	_diagnose_button.pressed.connect(_on_diagnose_pressed)
	_diagnose_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diag_vbox.add_child(_diagnose_button)

	# --- Diagnostic results tree ---
	var diag_results_label := Label.new()
	diag_results_label.text = "Diagnostic Results"
	diag_vbox.add_child(diag_results_label)

	_diagnostic_tree = Tree.new()
	_diagnostic_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diagnostic_tree.columns = 2
	_diagnostic_tree.set_column_title(0, "Condition")
	_diagnostic_tree.set_column_title(1, "Result")
	_diagnostic_tree.set_column_titles_visible(true)
	_diagnostic_tree.set_column_expand(0, true)
	_diagnostic_tree.set_column_expand(1, false)
	_diagnostic_tree.set_column_custom_minimum_width(1, 60)
	_diagnostic_tree.set_column_clip_content(0, true)
	_diagnostic_tree.set_column_clip_content(1, true)
	_diagnostic_tree.create_item() # root
	diag_vbox.add_child(_diagnostic_tree)


## Helper: creates a labelled column containing a multi-select ItemList.
func _create_component_list_column(parent: HBoxContainer, title: String, tooltip: String) -> ItemList:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(vbox)

	var label := Label.new()
	label.text = title
	label.tooltip_text = tooltip
	vbox.add_child(label)

	var item_list := ItemList.new()
	item_list.select_mode = ItemList.SELECT_MULTI
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.tooltip_text = tooltip
	item_list.allow_reselect = true
	vbox.add_child(item_list)

	return item_list

# ---------------------------------------------------------------------------
# Data Indexing
# ---------------------------------------------------------------------------

## Scans editor_data.ecs_data to rebuild the component index and entity-component map.
func _rebuild_component_index() -> void:
	_available_components.clear()
	_entity_component_names.clear()
	_entity_paths.clear()
	_component_names.clear()

	if not _editor_data:
		return

	var entities: Dictionary = _editor_data.ecs_data.get("entities", {})
	for ent_id in entities:
		var ent_data: Dictionary = entities[ent_id]
		var ent_path = ent_data.get("path", "")
		_entity_paths[ent_id] = ent_path

		var comp_names_for_entity: Array = []
		var components: Dictionary = ent_data.get("components", {})

		for comp_id in components:
			var comp_entry = components[comp_id]
			# Handle both new structure (dict with path) and potential legacy (raw dict, though we aim for new)
			var comp_path = ""
			if comp_entry.has("path"):
				comp_path = comp_entry["path"]
			else:
				# Should not happen with new GECSEditorData, but defensive coding
				comp_path = "UnknownComponent"

			var comp_name: String = _extract_class_name(comp_path)
			_component_names[comp_id] = comp_name

			if comp_name not in comp_names_for_entity:
				comp_names_for_entity.append(comp_name)
			_available_components[comp_name] = _available_components.get(comp_name, 0) + 1

		_entity_component_names[ent_id] = comp_names_for_entity


## Repopulates every ItemList with the current set of known component names.
func _refresh_component_lists() -> void:
	var sorted_names: Array = _available_components.keys()
	sorted_names.sort()

	for item_list: ItemList in [_all_components_list, _any_components_list, _none_components_list,
								_diag_all_list, _diag_any_list, _diag_none_list]:
		if item_list == null:
			continue
		# Remember currently selected items so we can restore them.
		var previously_selected: Array = _get_selected_items(item_list)

		item_list.clear()
		for comp_name in sorted_names:
			var count: int = _available_components[comp_name]
			item_list.add_item("%s  (%d)" % [comp_name, count])
			item_list.set_item_metadata(item_list.item_count - 1, comp_name)

		# Restore previous selection where possible.
		for idx in range(item_list.item_count):
			var meta = item_list.get_item_metadata(idx)
			if meta in previously_selected:
				item_list.select(idx, false) # false = don't deselect others


## Repopulates the entity selector dropdown on the Diagnose tab.
func _refresh_entity_selector() -> void:
	if _entity_selector == null:
		return

	# Remember current selection.
	var prev_id: int = -1
	if _entity_selector.selected >= 0 and _entity_selector.selected < _entity_selector.item_count:
		prev_id = _entity_selector.get_item_metadata(_entity_selector.selected)

	_entity_selector.clear()

	if not _editor_data:
		return

	var entities: Dictionary = _editor_data.ecs_data.get("entities", {})
	var sorted_ids: Array = entities.keys()
	sorted_ids.sort()

	for ent_id in sorted_ids:
		var ent_data: Dictionary = entities[ent_id]
		var path = ent_data.get("path", "")
		var display_name: String = str(path).get_file() if str(path) != "" else "Entity_%s" % str(ent_id)
		_entity_selector.add_item(display_name)
		_entity_selector.set_item_metadata(_entity_selector.item_count - 1, ent_id)

	# Restore previous selection if still present.
	for idx in range(_entity_selector.item_count):
		if _entity_selector.get_item_metadata(idx) == prev_id:
			_entity_selector.select(idx)
			break

# ---------------------------------------------------------------------------
# Query Execution
# ---------------------------------------------------------------------------

func _on_execute_pressed() -> void:
	_execute_query()


func _on_clear_pressed() -> void:
	# Deselect everything in all lists.
	for item_list: ItemList in [_all_components_list, _any_components_list, _none_components_list]:
		if item_list:
			item_list.deselect_all()
	# Clear results.
	if _results_tree:
		_results_tree.clear()
		_results_tree.create_item()
	if _match_count_label:
		_match_count_label.text = "No query executed"
		_match_count_label.add_theme_color_override("font_color", COLOR_NEUTRAL)


func _execute_query() -> void:
	var all_selected: Array = _get_selected_components(_all_components_list)
	var any_selected: Array = _get_selected_components(_any_components_list)
	var none_selected: Array = _get_selected_components(_none_components_list)

	# Early out: if nothing is selected, show a hint.
	if all_selected.is_empty() and any_selected.is_empty() and none_selected.is_empty():
		_match_count_label.text = "Select at least one component to query"
		_match_count_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
		return

	var matching_entities: Array = []
	if not _editor_data:
		return
	var entities: Dictionary = _editor_data.ecs_data.get("entities", {})

	for ent_id in entities:
		var ent_comp_names: Array = _get_entity_component_names(ent_id)

		var matches := true

		# Check with_all: entity must have every listed component.
		for comp_name in all_selected:
			if comp_name not in ent_comp_names:
				matches = false
				break

		# Check with_any: entity must have at least one (when list is non-empty).
		if matches and not any_selected.is_empty():
			var has_any := false
			for comp_name in any_selected:
				if comp_name in ent_comp_names:
					has_any = true
					break
			if not has_any:
				matches = false

		# Check with_none: entity must not have any excluded component.
		if matches:
			for comp_name in none_selected:
				if comp_name in ent_comp_names:
					matches = false
					break

		if matches:
			matching_entities.append(ent_id)

	_display_query_results(matching_entities)


## Populate the results tree with matching entities.
func _display_query_results(matching_ids: Array) -> void:
	_results_tree.clear()
	var root := _results_tree.create_item()

	if not _editor_data:
		return

	for ent_id in matching_ids:
		var ent_data: Dictionary = _editor_data.ecs_data.get("entities", {}).get(ent_id, {})
		var path = ent_data.get("path", "")
		var display_name: String = str(path).get_file() if str(path) != "" else "Entity_%s" % str(ent_id)

		var item := _results_tree.create_item(root)
		item.set_text(0, display_name)
		item.set_tooltip_text(0, str(ent_id) + " : " + str(path))
		item.set_meta("entity_id", ent_id)

		# Column 1: comma-separated component list.
		var comp_names: Array = _get_entity_component_names(ent_id)
		item.set_text(1, ", ".join(comp_names))

		# Also add components as children for expandability.
		for comp_name in comp_names:
			var child := _results_tree.create_item(item)
			child.set_text(0, comp_name)
		item.collapsed = true

	# Update match count label.
	var total_entities: int = _editor_data.ecs_data.get("entities", {}).size()
	_match_count_label.text = "%d / %d entities matched" % [matching_ids.size(), total_entities]
	if matching_ids.size() > 0:
		_match_count_label.add_theme_color_override("font_color", COLOR_PASS)
	else:
		_match_count_label.add_theme_color_override("font_color", COLOR_FAIL)

# ---------------------------------------------------------------------------
# Diagnosis
# ---------------------------------------------------------------------------

func _on_diagnose_pressed() -> void:
	_run_diagnosis()


func _run_diagnosis() -> void:
	_diagnostic_tree.clear()
	var root := _diagnostic_tree.create_item()

	# Get the selected entity.
	if _entity_selector.selected < 0 or _entity_selector.selected >= _entity_selector.item_count:
		var err_item := _diagnostic_tree.create_item(root)
		err_item.set_text(0, "No entity selected")
		err_item.set_custom_color(0, COLOR_NEUTRAL)
		return

	var ent_id: int = _entity_selector.get_item_metadata(_entity_selector.selected)
	var ent_comp_names: Array = _get_entity_component_names(ent_id)

	var all_selected: Array = _get_selected_components(_diag_all_list)
	var any_selected: Array = _get_selected_components(_diag_any_list)
	var none_selected: Array = _get_selected_components(_diag_none_list)

	if all_selected.is_empty() and any_selected.is_empty() and none_selected.is_empty():
		var hint_item := _diagnostic_tree.create_item(root)
		hint_item.set_text(0, "Select at least one component in the query lists above")
		hint_item.set_custom_color(0, COLOR_NEUTRAL)
		return

	# Display entity info header.
	var header := _diagnostic_tree.create_item(root)
	var ent_path = _entity_paths.get(ent_id, "")
	var display_name: String = str(ent_path).get_file() if str(ent_path) != "" else "Entity_%s" % str(ent_id)
	header.set_text(0, "Entity: %s" % display_name)
	header.set_text(1, "")
	header.set_custom_color(0, COLOR_HEADER)

	# Show which components the entity has.
	var comps_item := _diagnostic_tree.create_item(root)
	comps_item.set_text(0, "Components: %s" % ", ".join(ent_comp_names) if not ent_comp_names.is_empty() else "Components: (none)")
	comps_item.set_custom_color(0, COLOR_NEUTRAL)

	var overall_pass := true

	# --- with_all section ---
	if not all_selected.is_empty():
		var section := _diagnostic_tree.create_item(root)
		section.set_text(0, "with_all")
		section.set_custom_color(0, COLOR_HEADER)

		for comp_name in all_selected:
			var row := _diagnostic_tree.create_item(section)
			if comp_name in ent_comp_names:
				row.set_text(0, "%s: PASS (entity has this component)" % comp_name)
				row.set_text(1, "PASS")
				row.set_custom_color(0, COLOR_PASS)
				row.set_custom_color(1, COLOR_PASS)
			else:
				row.set_text(0, "%s: FAIL (entity does NOT have this component)" % comp_name)
				row.set_text(1, "FAIL")
				row.set_custom_color(0, COLOR_FAIL)
				row.set_custom_color(1, COLOR_FAIL)
				overall_pass = false

	# --- with_any section ---
	if not any_selected.is_empty():
		var section := _diagnostic_tree.create_item(root)
		section.set_text(0, "with_any")
		section.set_custom_color(0, COLOR_HEADER)

		var any_pass := false
		for comp_name in any_selected:
			var row := _diagnostic_tree.create_item(section)
			if comp_name in ent_comp_names:
				row.set_text(0, "%s: PRESENT (entity has this component)" % comp_name)
				row.set_text(1, "PASS")
				row.set_custom_color(0, COLOR_PASS)
				row.set_custom_color(1, COLOR_PASS)
				any_pass = true
			else:
				row.set_text(0, "%s: ABSENT (entity does NOT have this component)" % comp_name)
				row.set_text(1, "-")
				row.set_custom_color(0, COLOR_NEUTRAL)
				row.set_custom_color(1, COLOR_NEUTRAL)

		# Summary row for with_any.
		var summary := _diagnostic_tree.create_item(section)
		if any_pass:
			summary.set_text(0, "with_any result: PASS (at least one component present)")
			summary.set_text(1, "PASS")
			summary.set_custom_color(0, COLOR_PASS)
			summary.set_custom_color(1, COLOR_PASS)
		else:
			summary.set_text(0, "with_any result: FAIL (none of the listed components present)")
			summary.set_text(1, "FAIL")
			summary.set_custom_color(0, COLOR_FAIL)
			summary.set_custom_color(1, COLOR_FAIL)
			overall_pass = false

	# --- with_none section ---
	if not none_selected.is_empty():
		var section := _diagnostic_tree.create_item(root)
		section.set_text(0, "with_none")
		section.set_custom_color(0, COLOR_HEADER)

		for comp_name in none_selected:
			var row := _diagnostic_tree.create_item(section)
			if comp_name in ent_comp_names:
				row.set_text(0, "%s: FAIL (entity HAS this excluded component)" % comp_name)
				row.set_text(1, "FAIL")
				row.set_custom_color(0, COLOR_FAIL)
				row.set_custom_color(1, COLOR_FAIL)
				overall_pass = false
			else:
				row.set_text(0, "%s: PASS (entity does not have excluded component)" % comp_name)
				row.set_text(1, "PASS")
				row.set_custom_color(0, COLOR_PASS)
				row.set_custom_color(1, COLOR_PASS)

	# --- Overall verdict ---
	var verdict := _diagnostic_tree.create_item(root)
	if overall_pass:
		verdict.set_text(0, "Overall: MATCH - entity satisfies all query conditions")
		verdict.set_text(1, "MATCH")
		verdict.set_custom_color(0, COLOR_PASS)
		verdict.set_custom_color(1, COLOR_PASS)
	else:
		verdict.set_text(0, "Overall: NO MATCH - entity fails one or more conditions")
		verdict.set_text(1, "FAIL")
		verdict.set_custom_color(0, COLOR_FAIL)
		verdict.set_custom_color(1, COLOR_FAIL)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns the selected component names from an ItemList using stored metadata.
func _get_selected_components(item_list: ItemList) -> Array:
	var result: Array = []
	if item_list == null:
		return result
	var selected_indices: PackedInt32Array = item_list.get_selected_items()
	for idx in selected_indices:
		var meta = item_list.get_item_metadata(idx)
		if meta != null and meta is String:
			result.append(meta)
	return result


## Returns the previously selected item metadata strings from an ItemList.
func _get_selected_items(item_list: ItemList) -> Array:
	var result: Array = []
	if item_list == null:
		return result
	var selected_indices: PackedInt32Array = item_list.get_selected_items()
	for idx in selected_indices:
		var meta = item_list.get_item_metadata(idx)
		if meta != null:
			result.append(meta)
	return result


## Returns the list of component class names for a given entity id.
func _get_entity_component_names(ent_id: int) -> Array:
	if _entity_component_names.has(ent_id):
		return _entity_component_names[ent_id]
	return []


## Extracts a human-readable class name from a component path string.
## Handles both class names like "C_Health" and resource paths like
## "res://components/C_Health.gd".
func _extract_class_name(comp_path: String) -> String:
	if comp_path.is_empty():
		return ""
	# If it looks like a resource path, extract filename without extension.
	if "/" in comp_path or comp_path.ends_with(".gd"):
		return comp_path.get_file().get_basename()
	# Already a plain class name.
	return comp_path
