@tool
class_name GECSReplicationOverlay
extends Control
## Replication Overlay - Real-time network sync activity panel for debugging multiplayer GECS games.
##
## Displays a live table of all networked entities with their sync status,
## priority color coding, staleness detection, authority indicators, and
## aggregate statistics. Data is fed externally via update_entity_sync_data().
##
## Usage:
##   var overlay = GECSReplicationOverlay.new()
##   add_child(overlay)
##   overlay.update_entity_sync_data(entity_id, sync_info)

# ============================================================================
# CONSTANTS
# ============================================================================

## Color constants for priority levels
const PRIORITY_COLORS := {
	0: Color(1.0, 0.3, 0.3),    # REALTIME - Red
	1: Color(1.0, 0.6, 0.2),    # HIGH - Orange
	2: Color(1.0, 0.9, 0.3),    # MEDIUM - Yellow
	3: Color(0.4, 0.6, 1.0),    # LOW - Blue
	-1: Color(0.5, 0.5, 0.5),   # LOCAL - Gray
}

## Human-readable names for priority levels
const PRIORITY_NAMES := {
	0: "REALTIME",
	1: "HIGH",
	2: "MEDIUM",
	3: "LOW",
	-1: "LOCAL",
}

## Staleness thresholds in seconds
const STALE_WARNING := 1.0   # Yellow warning threshold
const STALE_CRITICAL := 5.0  # Red critical threshold

## Auto-refresh interval in seconds
const REFRESH_INTERVAL := 0.5

## Tree column indices
const COL_ENTITY := 0
const COL_COMPONENTS := 1
const COL_PRIORITY := 2
const COL_LAST_SYNC := 3
const COL_AUTHORITY := 4
const COL_STATUS := 5

## Column count
const COLUMN_COUNT := 6

# ============================================================================
# UI REFERENCES
# ============================================================================

var _tree: Tree
var _stats_label: Label
var _auto_refresh_check: CheckBox
var _refresh_button: Button
var _filter_search: LineEdit
var _filter_priority: OptionButton

# ============================================================================
# DATA
# ============================================================================

## Sync data keyed by entity_id. Each value is a Dictionary with entity sync info
## plus an internal "_last_update" timestamp.
var _sync_data: Dictionary = {}

## Accumulated time since last auto-refresh
var _refresh_timer: float = 0.0


# ============================================================================
# LIFECYCLE
# ============================================================================


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	if not _auto_refresh_check or not _auto_refresh_check.button_pressed:
		return
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_tree()


# ============================================================================
# PUBLIC API
# ============================================================================


## Update sync data for a single entity.
##
## sync_info structure:
## {
##   "entity_name": String,        # Display name
##   "entity_path": String,        # Full node path
##   "peer_id": int,               # Owner peer ID
##   "is_local": bool,             # Is locally owned
##   "is_server": bool,            # Is server-owned
##   "components": [               # Array of synced component info
##     {
##       "name": String,           # Component class name (e.g., "C_Transform")
##       "priority": int,          # Sync priority (0=REALTIME, 1=HIGH, etc.)
##       "last_sync_time": float,  # Time since last sync in seconds
##       "properties": [String],   # List of synced property names
##     }
##   ],
##   "authority": String,          # "local" | "remote" | "server"
##   "sync_active": bool,          # Is currently syncing
## }
func update_entity_sync_data(entity_id: int, sync_info: Dictionary) -> void:
	_sync_data[entity_id] = sync_info
	_sync_data[entity_id]["_last_update"] = Time.get_ticks_msec() / 1000.0


## Remove sync data for a single entity (e.g., when it despawns).
func remove_entity_sync_data(entity_id: int) -> void:
	_sync_data.erase(entity_id)


## Clear all sync data and refresh the display.
func clear_all_data() -> void:
	_sync_data.clear()
	_refresh_tree()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================


## Build the entire UI programmatically for reliable control references.
func _build_ui() -> void:
	# Root VBoxContainer fills entire panel
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# -- Header row --
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Network Replication"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.tooltip_text = "Manually refresh the entity sync table"
	_refresh_button.pressed.connect(_on_refresh_pressed)
	header.add_child(_refresh_button)

	_auto_refresh_check = CheckBox.new()
	_auto_refresh_check.text = "Auto"
	_auto_refresh_check.tooltip_text = "Auto-refresh every %.1fs" % REFRESH_INTERVAL
	_auto_refresh_check.button_pressed = true
	header.add_child(_auto_refresh_check)

	# -- Filter row --
	var filter_row := HBoxContainer.new()
	vbox.add_child(filter_row)

	var search_label := Label.new()
	search_label.text = "Search:"
	filter_row.add_child(search_label)

	_filter_search = LineEdit.new()
	_filter_search.placeholder_text = "Filter by entity name..."
	_filter_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_filter_search.text_changed.connect(_on_search_changed)
	filter_row.add_child(_filter_search)

	var priority_label := Label.new()
	priority_label.text = "Priority:"
	filter_row.add_child(priority_label)

	_filter_priority = OptionButton.new()
	_filter_priority.add_item("All", 0)
	_filter_priority.add_item("REALTIME", 1)
	_filter_priority.add_item("HIGH", 2)
	_filter_priority.add_item("MEDIUM", 3)
	_filter_priority.add_item("LOW", 4)
	_filter_priority.add_item("LOCAL", 5)
	_filter_priority.tooltip_text = "Filter entities by their highest sync priority"
	_filter_priority.item_selected.connect(_on_priority_filter_changed)
	filter_row.add_child(_filter_priority)

	# -- Stats summary label --
	_stats_label = Label.new()
	_stats_label.text = "Entities: 0 | Active: 0 | Stale: 0"
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_stats_label)

	# -- Main entity tree --
	_tree = Tree.new()
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.columns = COLUMN_COUNT
	_tree.column_titles_visible = true
	_tree.hide_root = true

	# Column 0: Entity
	_tree.set_column_title(COL_ENTITY, "Entity")
	_tree.set_column_expand(COL_ENTITY, true)
	_tree.set_column_custom_minimum_width(COL_ENTITY, 120)

	# Column 1: Components
	_tree.set_column_title(COL_COMPONENTS, "Components")
	_tree.set_column_expand(COL_COMPONENTS, true)
	_tree.set_column_custom_minimum_width(COL_COMPONENTS, 150)

	# Column 2: Priority
	_tree.set_column_title(COL_PRIORITY, "Priority")
	_tree.set_column_expand(COL_PRIORITY, false)
	_tree.set_column_custom_minimum_width(COL_PRIORITY, 80)

	# Column 3: Last Sync
	_tree.set_column_title(COL_LAST_SYNC, "Last Sync")
	_tree.set_column_expand(COL_LAST_SYNC, false)
	_tree.set_column_custom_minimum_width(COL_LAST_SYNC, 70)

	# Column 4: Authority
	_tree.set_column_title(COL_AUTHORITY, "Authority")
	_tree.set_column_expand(COL_AUTHORITY, false)
	_tree.set_column_custom_minimum_width(COL_AUTHORITY, 70)

	# Column 5: Status
	_tree.set_column_title(COL_STATUS, "Status")
	_tree.set_column_expand(COL_STATUS, false)
	_tree.set_column_custom_minimum_width(COL_STATUS, 60)

	vbox.add_child(_tree)


# ============================================================================
# TREE POPULATION
# ============================================================================


## Rebuild the tree contents from current sync data, applying active filters.
func _refresh_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()

	var search_text := _filter_search.text.to_lower() if _filter_search else ""
	var priority_filter := _get_selected_priority_filter()

	var total_entities := 0
	var active_syncing := 0
	var stale_count := 0
	var current_time := Time.get_ticks_msec() / 1000.0

	for entity_id in _sync_data:
		var info: Dictionary = _sync_data[entity_id]
		var entity_name: String = info.get("entity_name", "Entity_%d" % entity_id)

		# Apply search filter
		if search_text != "" and entity_name.to_lower().find(search_text) == -1:
			continue

		# Determine the highest (most urgent) priority across all components.
		# Lower numeric value = higher priority. Default to LOW (3).
		var highest_priority := 3
		var components: Array = info.get("components", [])
		for comp in components:
			var p: int = comp.get("priority", 3)
			if p >= 0 and p < highest_priority:
				highest_priority = p

		# Apply priority filter (-2 means "All")
		if priority_filter >= -1 and highest_priority != priority_filter:
			continue

		total_entities += 1

		var item := _tree.create_item(root)

		# Column 0: Entity name (tooltip shows full node path)
		item.set_text(COL_ENTITY, entity_name)
		item.set_tooltip_text(COL_ENTITY, info.get("entity_path", ""))

		# Column 1: Comma-separated component names
		var comp_names: PackedStringArray = []
		for comp in components:
			comp_names.append(comp.get("name", "?"))
		item.set_text(COL_COMPONENTS, ", ".join(comp_names))

		# Column 2: Priority (colored by level)
		item.set_text(COL_PRIORITY, PRIORITY_NAMES.get(highest_priority, "?"))
		item.set_custom_color(COL_PRIORITY, PRIORITY_COLORS.get(highest_priority, Color.WHITE))

		# Column 3: Time since last sync update (with staleness coloring)
		var last_update: float = info.get("_last_update", 0.0)
		var time_since := current_time - last_update
		item.set_text(COL_LAST_SYNC, "%.1fs" % time_since)

		if time_since > STALE_CRITICAL:
			item.set_custom_color(COL_LAST_SYNC, Color(1.0, 0.3, 0.3))   # Red
			stale_count += 1
		elif time_since > STALE_WARNING:
			item.set_custom_color(COL_LAST_SYNC, Color(1.0, 0.85, 0.3))  # Yellow
		else:
			item.set_custom_color(COL_LAST_SYNC, Color(0.4, 0.9, 0.4))   # Green
			active_syncing += 1

		# Column 4: Authority (colored by ownership)
		var authority: String = info.get("authority", "?")
		item.set_text(COL_AUTHORITY, authority)
		match authority:
			"local":
				item.set_custom_color(COL_AUTHORITY, Color(0.4, 0.9, 0.4))   # Green
			"remote":
				item.set_custom_color(COL_AUTHORITY, Color(0.5, 0.75, 1.0))  # Blue
			"server":
				item.set_custom_color(COL_AUTHORITY, Color(1.0, 0.85, 0.3))  # Yellow

		# Column 5: Status indicator
		var sync_active: bool = info.get("sync_active", false)
		if not sync_active:
			item.set_text(COL_STATUS, "Idle")
			item.set_custom_color(COL_STATUS, Color(0.5, 0.5, 0.5))
		elif time_since > STALE_CRITICAL:
			item.set_text(COL_STATUS, "STALE")
			item.set_custom_color(COL_STATUS, Color(1.0, 0.3, 0.3))
		else:
			item.set_text(COL_STATUS, "Active")
			item.set_custom_color(COL_STATUS, Color(0.4, 0.9, 0.4))

		# Store entity_id on the item for external reference
		item.set_meta("entity_id", entity_id)

		# Add expandable child rows for each component's details
		for comp in components:
			var comp_item := _tree.create_item(item)
			comp_item.set_text(COL_ENTITY, "  " + comp.get("name", "?"))

			# Show synced property names in the Components column
			var props: Array = comp.get("properties", [])
			comp_item.set_text(COL_COMPONENTS, ", ".join(props))

			# Show per-component priority with color
			var comp_priority: int = comp.get("priority", -1)
			comp_item.set_text(COL_PRIORITY, PRIORITY_NAMES.get(comp_priority, "?"))
			comp_item.set_custom_color(COL_PRIORITY, PRIORITY_COLORS.get(comp_priority, Color.WHITE))

		# Collapse component children by default
		item.collapsed = true

	# Update the stats summary bar
	_update_stats(total_entities, active_syncing, stale_count)


## Map the priority OptionButton selection to a filter value.
## Returns -2 for "All" (no filter), or the priority int (0-3, -1) for specific filters.
func _get_selected_priority_filter() -> int:
	if _filter_priority == null:
		return -2  # All
	var selected := _filter_priority.selected
	# Index 0 = All, 1 = REALTIME(0), 2 = HIGH(1), 3 = MEDIUM(2), 4 = LOW(3), 5 = LOCAL(-1)
	match selected:
		0:
			return -2  # All
		1:
			return 0   # REALTIME
		2:
			return 1   # HIGH
		3:
			return 2   # MEDIUM
		4:
			return 3   # LOW
		5:
			return -1  # LOCAL
		_:
			return -2  # All (fallback)


# ============================================================================
# STATS
# ============================================================================


## Update the stats summary label with current counts.
func _update_stats(total: int, active: int, stale: int) -> void:
	if _stats_label:
		_stats_label.text = "Entities: %d | Active: %d | Stale: %d" % [total, active, stale]


# ============================================================================
# SIGNAL CALLBACKS
# ============================================================================


func _on_refresh_pressed() -> void:
	_refresh_tree()


func _on_search_changed(_text: String) -> void:
	_refresh_tree()


func _on_priority_filter_changed(_index: int) -> void:
	_refresh_tree()
