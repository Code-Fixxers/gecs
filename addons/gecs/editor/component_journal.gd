@tool
## Component Change Journal / Timeline panel for the GECS editor debugger.
##
## Records and displays component lifecycle events (add, remove, property change)
## as a scrollable, filterable timeline. Intended to be embedded as a panel in the
## GECS debugger or used standalone.
class_name GECSComponentJournal
extends Control

## Journal entry types
enum EventType {
	COMPONENT_ADDED,
	COMPONENT_REMOVED,
	PROPERTY_CHANGED,
}

## Colors for event types
const EVENT_COLORS := {
	EventType.COMPONENT_ADDED: Color(0.4, 0.9, 0.4),     # Green
	EventType.COMPONENT_REMOVED: Color(1.0, 0.3, 0.3),    # Red
	EventType.PROPERTY_CHANGED: Color(1.0, 0.85, 0.3),    # Yellow
}

## Text icons for event types
const EVENT_ICONS := {
	EventType.COMPONENT_ADDED: "+",
	EventType.COMPONENT_REMOVED: "-",
	EventType.PROPERTY_CHANGED: "~",
}

## Maximum number of journal entries before oldest are evicted (FIFO).
const MAX_ENTRIES := 5000


## A single journal entry representing one component lifecycle event.
class JournalEntry:
	var timestamp: float  ## Time since session start in seconds
	var event_type: int   ## EventType enum value
	var entity_id: int
	var entity_name: String
	var component_name: String
	var property_name: String  ## Only for PROPERTY_CHANGED
	var old_value: String      ## Only for PROPERTY_CHANGED
	var new_value: String      ## Only for PROPERTY_CHANGED

	func format() -> String:
		var minutes := int(timestamp) / 60
		var seconds := fmod(timestamp, 60.0)
		var time_str := "[%02d:%06.3f]" % [minutes, seconds]
		match event_type:
			EventType.COMPONENT_ADDED:
				return "%s %s | %s | + ADDED" % [time_str, entity_name, component_name]
			EventType.COMPONENT_REMOVED:
				return "%s %s | %s | - REMOVED" % [time_str, entity_name, component_name]
			EventType.PROPERTY_CHANGED:
				return "%s %s | %s | %s: %s -> %s" % [time_str, entity_name, component_name, property_name, old_value, new_value]
		return ""


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _entries: Array = []  ## Array[JournalEntry]
var _session_start_time: float = 0.0
var _is_recording: bool = true
var _auto_scroll: bool = true
var _editor_data: GECSEditorData = null

## Entity / component name caches so that later events (e.g. property changes)
## can display human-readable names even if the caller only provides IDs.
var _entity_names: Dictionary = {}     ## entity_id -> entity_name
var _component_names: Dictionary = {}  ## component_id -> component_name

# ---------------------------------------------------------------------------
# UI references (built programmatically in _build_ui)
# ---------------------------------------------------------------------------

var _tree: Tree
var _stats_label: Label
var _search_edit: LineEdit
var _entity_filter: LineEdit
var _component_filter: LineEdit
var _event_type_filter: OptionButton
var _record_button: Button
var _clear_button: Button
var _copy_button: Button
var _auto_scroll_check: CheckBox


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_session_start_time = Time.get_ticks_msec() / 1000.0
	_build_ui()


func set_editor_data(data: GECSEditorData) -> void:
	_editor_data = data
	if not _editor_data:
		return

	# Connect signals
	if not _editor_data.entity_added.is_connected(_on_entity_added):
		_editor_data.entity_added.connect(_on_entity_added)
	if not _editor_data.component_added.is_connected(_on_component_added):
		_editor_data.component_added.connect(_on_component_added)
	if not _editor_data.component_removed.is_connected(_on_component_removed):
		_editor_data.component_removed.connect(_on_component_removed)
	if not _editor_data.component_property_changed.is_connected(_on_component_property_changed):
		_editor_data.component_property_changed.connect(_on_component_property_changed)


# ---------------------------------------------------------------------------
# Signal Handlers
# ---------------------------------------------------------------------------

func _on_entity_added(entity_id: int, path: NodePath) -> void:
	_entity_names[entity_id] = str(path).get_file()

func _on_component_added(entity_id: int, component_id: int, component_path: String, _data: Dictionary) -> void:
	var comp_name = component_path.get_file().get_basename()
	_component_names[component_id] = comp_name

	# Try to get entity name from cache or data
	var entity_name = _get_entity_name(entity_id)

	record_component_added(entity_id, entity_name, component_id, comp_name)

func _on_component_removed(entity_id: int, component_id: int) -> void:
	var entity_name = _get_entity_name(entity_id)
	var comp_name = _get_component_name(component_id)

	record_component_removed(entity_id, entity_name, component_id, comp_name)

func _on_component_property_changed(entity_id: int, component_id: int, property_name: String, old_value: Variant, new_value: Variant) -> void:
	record_property_changed(entity_id, component_id, property_name, old_value, new_value)


func _get_entity_name(entity_id: int) -> String:
	if _entity_names.has(entity_id):
		return _entity_names[entity_id]
	if _editor_data and _editor_data.ecs_data.has("entities") and _editor_data.ecs_data["entities"].has(entity_id):
		var path = _editor_data.ecs_data["entities"][entity_id].get("path", "")
		if str(path) != "":
			var name = str(path).get_file()
			_entity_names[entity_id] = name
			return name
	return "Entity_%d" % entity_id

func _get_component_name(component_id: int) -> String:
	if _component_names.has(component_id):
		return _component_names[component_id]
	return "Component_%d" % component_id


# ---------------------------------------------------------------------------
# Internal Recording
# ---------------------------------------------------------------------------

## Record a component being added to an entity.
func record_component_added(entity_id: int, entity_name: String, component_id: int, component_name: String) -> void:
	if not _is_recording:
		return
	var entry := JournalEntry.new()
	entry.timestamp = _get_elapsed_time()
	entry.event_type = EventType.COMPONENT_ADDED
	entry.entity_id = entity_id
	entry.entity_name = entity_name
	entry.component_name = component_name
	_add_entry(entry)


## Record a component being removed from an entity.
func record_component_removed(entity_id: int, entity_name: String, component_id: int, component_name: String) -> void:
	if not _is_recording:
		return
	var entry := JournalEntry.new()
	entry.timestamp = _get_elapsed_time()
	entry.event_type = EventType.COMPONENT_REMOVED
	entry.entity_id = entity_id
	entry.entity_name = entity_name
	entry.component_name = component_name
	_add_entry(entry)


## Record a component property change.
func record_property_changed(entity_id: int, component_id: int, property_name: String, old_value: Variant, new_value: Variant) -> void:
	if not _is_recording:
		return
	var entry := JournalEntry.new()
	entry.timestamp = _get_elapsed_time()
	entry.event_type = EventType.PROPERTY_CHANGED
	entry.entity_id = entity_id
	entry.entity_name = _get_entity_name(entity_id)
	entry.component_name = _get_component_name(component_id)
	entry.property_name = property_name
	entry.old_value = str(old_value)
	entry.new_value = str(new_value)
	_add_entry(entry)


## Reset the session (e.g. new game started). Clears all entries and caches.
func reset_session() -> void:
	_entries.clear()
	_entity_names.clear()
	_component_names.clear()
	_session_start_time = Time.get_ticks_msec() / 1000.0
	_refresh_tree()


# ---------------------------------------------------------------------------
# Internal -- entry management
# ---------------------------------------------------------------------------

func _add_entry(entry: JournalEntry) -> void:
	_entries.append(entry)
	# Cap entries (FIFO eviction)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	# Add to tree directly to avoid a full refresh for every event
	_add_entry_to_tree(entry)
	_update_stats()


func _add_entry_to_tree(entry: JournalEntry) -> void:
	if _tree == null:
		return
	# Apply filters -- skip if entry doesn't match
	if not _matches_filters(entry):
		return
	var root := _tree.get_root()
	if root == null:
		root = _tree.create_item()
	var item := _tree.create_item(root)
	var color: Color = EVENT_COLORS.get(entry.event_type, Color.WHITE)
	var icon: String = EVENT_ICONS.get(entry.event_type, "?")

	# Column 0: Timestamp
	var minutes := int(entry.timestamp) / 60
	var seconds := fmod(entry.timestamp, 60.0)
	var time_str := "%02d:%06.3f" % [minutes, seconds]
	item.set_text(0, time_str)
	item.set_custom_color(0, Color(0.6, 0.6, 0.6))

	# Column 1: Event icon
	item.set_text(1, icon)
	item.set_custom_color(1, color)
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)

	# Column 2: Entity name
	item.set_text(2, entry.entity_name)

	# Column 3: Component name
	item.set_text(3, entry.component_name)
	item.set_custom_color(3, color)

	# Column 4: Details
	match entry.event_type:
		EventType.COMPONENT_ADDED:
			item.set_text(4, "ADDED")
			item.set_custom_color(4, color)
		EventType.COMPONENT_REMOVED:
			item.set_text(4, "REMOVED")
			item.set_custom_color(4, color)
		EventType.PROPERTY_CHANGED:
			item.set_text(4, "%s: %s -> %s" % [entry.property_name, entry.old_value, entry.new_value])
			item.set_custom_color(4, color)

	# Auto-scroll to the newly added item
	if _auto_scroll:
		_tree.scroll_to_item(item)


func _matches_filters(entry: JournalEntry) -> bool:
	# Full-text search filter
	if _search_edit:
		var search := _search_edit.text.strip_edges().to_lower()
		if search != "":
			var full_text := entry.format().to_lower()
			if full_text.find(search) == -1:
				return false

	# Entity name filter
	if _entity_filter:
		var entity_filter := _entity_filter.text.strip_edges().to_lower()
		if entity_filter != "" and entry.entity_name.to_lower().find(entity_filter) == -1:
			return false

	# Component name filter
	if _component_filter:
		var comp_filter := _component_filter.text.strip_edges().to_lower()
		if comp_filter != "" and entry.component_name.to_lower().find(comp_filter) == -1:
			return false

	# Event type filter (0 = All)
	if _event_type_filter:
		var type_filter := _event_type_filter.selected
		if type_filter > 0:
			if type_filter - 1 != entry.event_type:
				return false

	return true


func _refresh_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	_tree.create_item()  # invisible root
	for entry in _entries:
		_add_entry_to_tree(entry)
	_update_stats()


func _get_elapsed_time() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _session_start_time


func _update_stats() -> void:
	if _stats_label == null:
		return
	var added := 0
	var removed := 0
	var changed := 0
	for e in _entries:
		match e.event_type:
			EventType.COMPONENT_ADDED:
				added += 1
			EventType.COMPONENT_REMOVED:
				removed += 1
			EventType.PROPERTY_CHANGED:
				changed += 1
	_stats_label.text = "Total: %d | Added: %d | Removed: %d | Changed: %d" % [_entries.size(), added, removed, changed]


# ---------------------------------------------------------------------------
# Button / filter handlers
# ---------------------------------------------------------------------------

func _on_record_toggled() -> void:
	_is_recording = not _is_recording
	_record_button.text = "Pause" if _is_recording else "Record"


func _on_clear_pressed() -> void:
	_entries.clear()
	_refresh_tree()


func _on_copy_pressed() -> void:
	var text := ""
	for entry in _entries:
		text += entry.format() + "\n"
	DisplayServer.clipboard_set(text)


func _on_auto_scroll_toggled(toggled_on: bool) -> void:
	_auto_scroll = toggled_on


func _on_filter_changed(_new_text: String = "") -> void:
	_refresh_tree()


func _on_event_type_selected(_index: int) -> void:
	_refresh_tree()


# ---------------------------------------------------------------------------
# UI construction (fully programmatic)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Root layout
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# ------- Header row -------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var title_label := Label.new()
	title_label.text = "Component Journal"
	title_label.add_theme_font_size_override("font_size", 14)
	header.add_child(title_label)

	# Spacer
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	_record_button = Button.new()
	_record_button.text = "Pause"
	_record_button.tooltip_text = "Pause / resume recording of events"
	_record_button.pressed.connect(_on_record_toggled)
	header.add_child(_record_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.tooltip_text = "Clear all journal entries"
	_clear_button.pressed.connect(_on_clear_pressed)
	header.add_child(_clear_button)

	_copy_button = Button.new()
	_copy_button.text = "Copy"
	_copy_button.tooltip_text = "Copy all entries to clipboard as text"
	_copy_button.pressed.connect(_on_copy_pressed)
	header.add_child(_copy_button)

	_auto_scroll_check = CheckBox.new()
	_auto_scroll_check.text = "Auto-scroll"
	_auto_scroll_check.button_pressed = _auto_scroll
	_auto_scroll_check.toggled.connect(_on_auto_scroll_toggled)
	header.add_child(_auto_scroll_check)

	# ------- Filter row -------
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	vbox.add_child(filter_row)

	var search_label := Label.new()
	search_label.text = "Search:"
	filter_row.add_child(search_label)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Full text..."
	_search_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_filter_changed)
	filter_row.add_child(_search_edit)

	var entity_label := Label.new()
	entity_label.text = "Entity:"
	filter_row.add_child(entity_label)

	_entity_filter = LineEdit.new()
	_entity_filter.placeholder_text = "Name..."
	_entity_filter.custom_minimum_size.x = 120
	_entity_filter.clear_button_enabled = true
	_entity_filter.text_changed.connect(_on_filter_changed)
	filter_row.add_child(_entity_filter)

	var comp_label := Label.new()
	comp_label.text = "Component:"
	filter_row.add_child(comp_label)

	_component_filter = LineEdit.new()
	_component_filter.placeholder_text = "Name..."
	_component_filter.custom_minimum_size.x = 120
	_component_filter.clear_button_enabled = true
	_component_filter.text_changed.connect(_on_filter_changed)
	filter_row.add_child(_component_filter)

	_event_type_filter = OptionButton.new()
	_event_type_filter.add_item("All", 0)
	_event_type_filter.add_item("Added", 1)
	_event_type_filter.add_item("Removed", 2)
	_event_type_filter.add_item("Changed", 3)
	_event_type_filter.item_selected.connect(_on_event_type_selected)
	filter_row.add_child(_event_type_filter)

	# ------- Stats label -------
	_stats_label = Label.new()
	_stats_label.text = "Total: 0 | Added: 0 | Removed: 0 | Changed: 0"
	_stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_stats_label)

	# ------- Tree (event log) -------
	_tree = Tree.new()
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.columns = 5
	_tree.hide_root = true
	_tree.set_column_titles_visible(true)
	_tree.allow_search = false

	# Column 0: Time
	_tree.set_column_title(0, "Time")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 80)
	_tree.set_column_clip_content(0, true)

	# Column 1: Type icon
	_tree.set_column_title(1, "")
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 30)
	_tree.set_column_clip_content(1, true)

	# Column 2: Entity
	_tree.set_column_title(2, "Entity")
	_tree.set_column_expand(2, true)
	_tree.set_column_clip_content(2, true)

	# Column 3: Component
	_tree.set_column_title(3, "Component")
	_tree.set_column_expand(3, false)
	_tree.set_column_custom_minimum_width(3, 150)
	_tree.set_column_clip_content(3, true)

	# Column 4: Details
	_tree.set_column_title(4, "Details")
	_tree.set_column_expand(4, true)
	_tree.set_column_clip_content(4, true)

	# Create invisible root
	_tree.create_item()

	vbox.add_child(_tree)

	# Initial stats
	_update_stats()
